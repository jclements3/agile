#!/usr/bin/perl
# perl tests/memo-templates.t -- the memo templates (tools/gitlab/templates/memos/) and Tidewater's memos
# (docs/tidewater/memos/) render with tools/memo/memo-build.pl: PDF and text, header lines present, guidance comments
# stripped, placeholders reported, and the committed renderings are what memo-build.pl writes today
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return ''; local $/; my $t = <$fh>; close $fh; $t }
sub run { my $err = "$_[0]/stderr"; my ($dir, @cmd) = @_;
    my $q = join ' ', map { my $a = $_; $a =~ s/'/'\\''/g; "'$a'" } @cmd;
    my $out = qx($q 2>"$err"); return ($? >> 8, $out, slurp($err)) }

my $root  = "$FindBin::Bin/..";
my $build = "$root/tools/memo/memo-build.pl";
my $tdir  = "$root/tools/gitlab/templates/memos";
my $mdir  = "$root/docs/tidewater/memos";
my $tmp   = tempdir(CLEANUP => 1);

opendir my $dh, $tdir or die "$tdir: $!\n";
my @templates = sort grep { /^[a-z-]+\.md$/ && $_ ne 'README.md' } readdir $dh;
closedir $dh;
check('five memo templates', scalar(@templates), 5);
for my $t (@templates) {
    (my $base = $t) =~ s/\.md$//;
    my ($rc, $out, $err) = run($tmp, $^X, $build, '--out', $tmp, "$tdir/$t");
    check("$t: renders", $rc, 0);
    check("$t: a PDF", substr(slurp("$tmp/$base.pdf"), 0, 5), '%PDF-');
    my $txt = slurp("$tmp/$base.txt");
    check("$t: header lines", join('', map { $txt =~ $_ ? 1 : 0 } qr/^(?:\(\S+\)\s+)?MEMORANDUM FOR/m, qr/^(?:\(\S+\)\s+)?FROM: /m, qr/^(?:\(\S+\)\s+)?SUBJECT: /m), '111');
    check("$t: guidance comments stripped", ($txt =~ /<!--|-->/ ? 1 : 0), 0);
    check("$t: placeholders reported", ($err =~ /placeholder\(s\) to fill in/ ? 1 : 0), 1);
    ($rc) = run($tmp, $^X, $build, '--check', "$tdir/$t");
    check("$t: --check fails while placeholders are left", $rc, 1);
}
my $dr = slurp("$tmp/discrepancy-report-transmittal.txt");
check('the {CUI} example marks its portion and the banner', join('', ($dr =~ /^\s+CUI\s*$/m ? 1 : 0), ($dr =~ /^\(CUI\) 2\./m ? 1 : 0)), '11');

opendir $dh, $mdir or die "$mdir: $!\n";
my @memos = sort grep { /^\d{4}-\d\d-\d\d-.*\.md$/ } readdir $dh;
closedir $dh;
check('five Tidewater memos', scalar(@memos), 5);
check('no TODO-SIM marker left in the Tidewater memos', scalar(grep { slurp("$mdir/$_") =~ /TODO-SIM/ } @memos), 0);
mkdir "$tmp/tw";
for my $m (@memos) {
    (my $base = $m) =~ s/\.md$//;
    my ($rc) = run($tmp, $^X, $build, '--out', "$tmp/tw", "$mdir/$m");
    check("$m: renders", $rc, 0);
    for my $ext (qw(pdf txt)) {
        check("$m: committed .$ext is current (perl tools/memo/memo-build.pl docs/tidewater/memos/*.md)",
              (slurp("$tmp/tw/$base.$ext") eq slurp("$mdir/$base.$ext") ? 1 : 0), 1);
    }
    ($rc) = run($tmp, $^X, $build, '--check', "$mdir/$m");
    check("$m: complete (--check)", $rc, 0);
}

# problems are reported, not rendered
open my $fh, '>', "$tmp/bad.md" or die; print $fh "## Memorandum for Record\n\n## From: X\n\nNo subject line.\n"; close $fh;
my ($rc, undef, $err) = run($tmp, $^X, $build, '--out', $tmp, "$tmp/bad.md");
check('a memo without a subject line is refused', join('|', $rc, ($err =~ /no "## Subject: \.\.\." line/ ? 1 : 0), (-e "$tmp/bad.pdf" ? 1 : 0)), '1|1|0');
($rc) = run($tmp, $^X, $build);
check('no file: usage, exit 2', $rc, 2);
open $fh, '>', "$tmp/mark.md" or die; print $fh "## Memorandum for Record\n\n## From: X\n\n## Subject: Y\n\nText.\n"; close $fh;
($rc) = run($tmp, $^X, $build, '--text-only', '--out', $tmp, "$tmp/mark.md", '--', '--mark');
check('options after -- reach md2memo (--mark adds portion marks)', (slurp("$tmp/mark.txt") =~ /^\(U\)/m ? 1 : 0), 1);

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
