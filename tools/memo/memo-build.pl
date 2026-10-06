#!/usr/bin/perl
# memo-build.pl -- render a memo written from tools/gitlab/templates/memos/ with md2memo.pl.
#
#   perl tools/memo/memo-build.pl [--check] [--out DIR] [--pdf-only|--text-only] FILE.md... [-- md2memo options]
#
# For each FILE.md it:
#   1. removes the template's guidance, every <!-- ... --> comment (md2memo itself would print them);
#   2. checks the memorandum has its header lines (## Memorandum for ..., ## From: ..., ## Subject: ...) and warns
#      about anything still to fill in: <<placeholders>> and TODO-SIM markers;
#   3. writes FILE.pdf (md2memo.pl, Times 12) and FILE.txt (md2memo.pl --plain) beside it, or under --out DIR.
# Options after `--` go to md2memo.pl unchanged (for example `-- --mark` or `-- --default CUI`).
# --check renders nothing and exits 1 when a header line is missing or a placeholder is left.
# Exit status: 0 done, 1 a problem was found (missing header, placeholder left with --check, md2memo failed), 2 usage.
use strict;
use warnings;
use FindBin;
use File::Basename qw(fileparse);
use File::Temp qw(tempfile);

my $MD2MEMO = "$FindBin::Bin/md2memo.pl";
my (%o, @files, @pass);
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--')          { @pass = @ARGV; last }
    elsif ($a eq '--check')     { $o{check} = 1 }
    elsif ($a eq '--pdf-only')  { $o{pdf_only} = 1 }
    elsif ($a eq '--text-only') { $o{text_only} = 1 }
    elsif ($a eq '--out')       { $o{out} = shift @ARGV // usage() }
    elsif ($a =~ /^-(h|-help)$/) { usage(0) }
    elsif ($a =~ /^-/)          { print STDERR "memo-build: unknown option $a\n"; usage() }
    else                        { push @files, $a }
}
usage() unless @files;
sub usage { my $rc = shift // 2; print STDERR "usage: memo-build.pl [--check] [--out DIR] [--pdf-only|--text-only] FILE.md... [-- md2memo options]\n"; exit $rc }

sub strip {                                     # the memo text without the template's guidance
    my $t = shift;
    $t =~ s/\r\n?/\n/g;
    $t =~ s/<!--.*?-->//gs;
    $t =~ s/[ \t]+$//mg;
    $t =~ s/\n{3,}/\n\n/g;
    $t =~ s/^\n+//;
    $t;
}

sub problems {                                  # (stripped text) -> (errors, warnings)
    my $t = shift;
    my (@err, @warn);
    push @err, 'no "## Memorandum for ..." line' unless $t =~ /^##\s*Memorandum\s+for\b/mi;
    push @err, 'no "## From: ..." line'          unless $t =~ /^##\s*From:\s*\S/mi;
    push @err, 'no "## Subject: ..." line'       unless $t =~ /^##\s*Subject:\s*\S/mi;
    my %seen;
    my @ph = grep { !$seen{$_}++ } $t =~ /(<<[^<>\n]+>>)/g;
    push @warn, scalar(@ph) . ' placeholder(s) to fill in: ' . join(', ', @ph[0 .. ($#ph < 4 ? $#ph : 4)]) . (@ph > 5 ? ', ...' : '') if @ph;
    my $sim = () = $t =~ /TODO-SIM/g;
    push @warn, "$sim TODO-SIM marker(s): numbers still to come from the simulation's evidence" if $sim;
    return (\@err, \@warn);
}

my $bad = 0;
for my $f (@files) {
    next if $f =~ m{(?:^|[/\\])README\.md$}i;     # a folder's README is not a memo (so `memo-build.pl DIR/*.md` works)
    open my $in, '<:raw', $f or do { print STDERR "memo-build: cannot read $f: $!\n"; $bad = 1; next };
    my $text = strip(do { local $/; <$in> });
    close $in;
    my ($err, $warn) = problems($text);
    print STDERR "memo-build: $f: $_\n" for @$err;
    print STDERR "memo-build: $f: warning: $_\n" for @$warn;
    if (@$err || ($o{check} && @$warn)) { $bad = 1; next if $o{check} || @$err }
    next if $o{check};
    my ($name, $dir) = fileparse($f, qr/\.[^.]*/);
    $dir = $o{out} if defined $o{out};
    $dir =~ s{[/\\]?$}{/};
    my ($tfh, $tmp) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $tfh; print $tfh $text; close $tfh;
    for my $form ($o{text_only} ? () : (['pdf', []]), $o{pdf_only} ? () : (['txt', ['--plain']])) {
        my ($ext, $opt) = @$form;
        my $target = "$dir$name.$ext";
        open my $out, '>:raw', $target or do { print STDERR "memo-build: cannot write $target: $!\n"; $bad = 1; next };
        open my $run, '-|', $^X, $MD2MEMO, @$opt, @pass, $tmp or do { print STDERR "memo-build: cannot run md2memo.pl: $!\n"; $bad = 1; next };
        binmode $run;
        my $body = do { local $/; <$run> };
        close $run;
        if ($? >> 8 || !defined $body || !length $body) { print STDERR "memo-build: md2memo.pl failed on $f ($ext)\n"; $bad = 1; close $out; unlink $target; next }
        print $out $body;
        close $out;
        print "wrote $target\n";
    }
}
exit $bad;
