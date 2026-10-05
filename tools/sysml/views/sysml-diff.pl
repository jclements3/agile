#!/usr/bin/perl
# sysml-diff.pl : review a change to a SysML v2 model as two pictures and a change list.
# Core Perl 5 and git. Runs sysml-tree-svg.pl and sysml-trace-svg.pl with --compare.
#
#   perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... OLD_DIR NEW_DIR
#   perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... --git OLD[..NEW] [PATH...]
#
#   --git OLD..NEW  compare two revisions (anything git accepts: a tag, a branch, HEAD~3,
#                   origin/main...). --git OLD alone compares OLD with the working tree.
#                   PATHs limit the comparison (default: the current directory).
#   --changed       draw only what changed (unchanged parts and requirements are counted)
#   --root NAME     tree view roots (passed to sysml-tree-svg.pl)
#   --today DATE    date for risk-acceptance expiry (passed to sysml-threats.pl)
#
# Writes PREFIX-tree.svg, PREFIX-trace.svg (both colored by change), PREFIX-packages.svg and
# PREFIX-ibd.svg (the new version, findings in red) and PREFIX-changes.txt (default PREFIX:
# model-diff). The security checks (markings, zones, threats) run on both versions and their
# findings are compared by message: a finding only in the new version is reported as
# "new finding", one only in the old version as "resolved".
# The change list is GNU format (file:line: note|warning: ...), sorted by file: paste it into a
# merge request, or load it into Vim's quickfix list. Warnings are new requirement gaps.
# Exit status: 0 no new gaps and no new error findings, 1 otherwise, 2 usage or git error.
use strict; use warnings;
use Getopt::Long; use File::Temp qw(tempdir); use File::Spec; use File::Path qw(make_path); use File::Basename qw(dirname);
binmode STDOUT, ':encoding(UTF-8)';

my %O = (o => 'model-diff', root => []);
GetOptions(\%O, 'o=s', 'changed', 'root=s@', 'git=s', 'today=s')
    or usage();
sub usage { print STDERR "usage: perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... OLD_DIR NEW_DIR\n"
                       . "       perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... --git OLD[..NEW] [PATH...]\n"; exit 2 }
my $here = dirname($0);
my ($olddir, @new, %label);

if (defined $O{git}) {
    my ($a, $b) = $O{git} =~ /^(.+?)\.\.(.+)$/ ? ($1, $2) : ($O{git}, undef);
    my @paths = @ARGV ? @ARGV : ('.');
    $olddir = extract($a, @paths); $label{$olddir} = $a;
    @new = defined $b ? (extract($b, @paths)) : @paths;
    $label{$new[0]} = $b if defined $b;
} else {
    usage() unless @ARGV == 2;
    ($olddir, @new) = @ARGV;
}

sub git_lines {
    my @cmd = @_;
    open my $h, '-|', 'git', @cmd or die "git: $!";
    binmode $h; local $/ = "\0"; my @l = <$h>; chomp @l;
    close $h or do { print STDERR "sysml-diff: 'git @cmd' failed\n"; exit 2 };
    return @l;
}
sub extract {
    my ($rev, @paths) = @_;
    my $dir = tempdir('sysml-diff-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my @files = grep { /\.sysml$/ } git_lines('ls-tree', '-r', '-z', '--name-only', $rev, '--', @paths);
    print STDERR "sysml-diff: $rev: no .sysml files under @paths\n" unless @files;
    for my $f (@files) {
        (my $rel = $f) =~ s{^(\.\./)+}{up/}g;
        my $out = "$dir/$rel";
        make_path(dirname($out));
        open my $g, '-|', 'git', 'show', "$rev:./$f" or die "git: $!";
        binmode $g; local $/; my $data = <$g>;
        close $g or do { print STDERR "sysml-diff: 'git show $rev:./$f' failed\n"; exit 2 };
        open my $w, '>:raw', $out or die "$out: $!"; print $w $data; close $w;
    }
    return $dir;
}

my @changes; my $gaps = 0;
for my $view (['tree', 'sysml-tree-svg.pl', map { ('--root', $_) } @{$O{root}}], ['trace', 'sysml-trace-svg.pl']) {
    my ($name, $script, @extra) = @$view;
    my @cmd = ($^X, "$here/$script", '-o', "$O{o}-$name.svg", ($O{changed} ? '--changed' : ()), @extra,
               (map { ('--label', "$_=$label{$_}:") } sort keys %label),
               '--compare', $olddir, @new);
    open my $h, '-|', @cmd or die "$script: $!";
    binmode $h, ':encoding(UTF-8)';
    while (my $l = <$h>) {
        chomp $l;
        if ($l =~ /^(?:tree|trace)-svg: /) { print "$l\n"; next }
        $gaps++ if $l =~ /: warning: /;
        push @changes, $l;
    }
    close $h or do { print STDERR "sysml-diff: $script failed\n"; exit 2 };
}
# security findings: run each check on both versions, compare messages (multisets)
my $newerr = 0;
sub relabel { my $l = shift; for my $d (keys %label) { $l =~ s/^\Q$d\E\//$label{$d}:/ } $l }
sub findings {
    my ($script, @args) = @_;
    open my $h, '-|', $^X, "$here/$script", @args or die "$script: $!";
    binmode $h, ':encoding(UTF-8)';
    my (@f, $sum);
    while (my $l = <$h>) {
        chomp $l;
        if ($l =~ /^(.*?:\d+): (error|warning): (.*)$/) { push @f, [relabel($1), $2, $3] }
        elsif ($l =~ /\d+ file\(s\): /) { $sum = $l }
    }
    close $h;
    if (($? >> 8) == 2) { print STDERR "sysml-diff: $script failed\n"; exit 2 }
    return (\@f, $sum);
}
for my $chk (['markings', 'sysml-pkg-svg.pl', 'packages'], ['zones', 'sysml-ibd-svg.pl', 'ibd'], ['threats', 'sysml-threats.pl', undef]) {
    my ($name, $script, $svg) = @$chk;
    my @t = $name eq 'threats' && $O{today} ? ('--today', $O{today}) : ();
    my ($old) = findings($script, @t, ($svg ? ('-o', File::Spec->devnull) : ()), $olddir);
    my ($cur, $sum) = findings($script, @t, ($svg ? ('-o', "$O{o}-$svg.svg") : ()), @new);
    my %was; $was{"$_->[1]: $_->[2]"}++ for @$old;
    my %now; $now{"$_->[1]: $_->[2]"}++ for @$cur;
    my ($nnew, $nres) = (0, 0);
    for my $f (@$cur) { my $k = "$f->[1]: $f->[2]"; if (($was{$k} // 0) > 0) { $was{$k}--; next } push @changes, "$f->[0]: $f->[1]: new finding ($name): $f->[2]"; $nnew++; $newerr++ if $f->[1] eq 'error' }
    for my $f (@$old) { my $k = "$f->[1]: $f->[2]"; if (($now{$k} // 0) > 0) { $now{$k}--; next } push @changes, "$f->[0]: note: resolved ($name): $f->[2]"; $nres++ }
    $sum //= ''; $sum =~ s/ -> \S+$//;
    print "$name: $nnew new finding(s), $nres resolved; now $sum\n";
}

my %seen;
@changes = grep { !$seen{$_}++ } sort { my @a = $a =~ /^(.*?):(\d+):/; my @b = $b =~ /^(.*?):(\d+):/;
                                         ($a[0] // '') cmp ($b[0] // '') || ($a[1] // 0) <=> ($b[1] // 0) || $a cmp $b } @changes;
open my $c, '>:encoding(UTF-8)', "$O{o}-changes.txt" or die "$O{o}-changes.txt: $!";
print $c "$_\n" for @changes;
close $c;
printf "sysml-diff: %d change line(s), %d new gap(s), %d new error finding(s) -> %s-{tree,trace,packages,ibd}.svg %s-changes.txt\n",
    scalar @changes, $gaps, $newerr, $O{o}, $O{o};
exit($gaps || $newerr ? 1 : 0);
