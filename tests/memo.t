#!/usr/bin/perl
# perl tests/memo.t -- tools/memo/md2memo.pl renders the sample memo exactly as shipped
use strict;
use warnings;
use FindBin;
use Digest::SHA qw(sha256_hex);

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }

my $root = "$FindBin::Bin/..";
my $tool = "$root/tools/memo/md2memo.pl";
my $md   = "$root/tools/memo/examples/status-report.md";
sub render { my @opt = @_;
    open my $fh, '-|', $^X, $tool, @opt, $md or die "cannot run md2memo: $!\n";
    binmode $fh; local $/; my $out = <$fh>; close $fh; return ($out, $? >> 8) }

# sums of the PDF and text that came with the tool (DOD-Writing-Guide.zip, 2026-10-05)
my %want = (
    pdf   => '5f9795d954661b72520248e8321003de21b0248575edcf66bd4bceac09cfc702',
    text  => '38438d18b6e6816df056d6d201b366c6d171b91e91175695a69c415efb2c533e',
    plain => 'e6367ccd36002a9a7e124322e16e94be9c891769efd60b279a65f30f2562938d',
);
for my $form (qw(pdf text plain)) {
    my ($out, $rc) = render($form eq 'pdf' ? () : ("--$form"));
    check("$form exits 0", $rc, 0);
    check("$form output unchanged", sha256_hex($out), $want{$form});
}

my ($plain) = render('--plain');
my ($banner) = $plain =~ /^\s*(\S+)/;
check('CUI tags roll up to a CUI banner', $banner, 'CUI');
check('untagged portion marked (U)', ($plain =~ /^\(U\)\s+MONTHLY PROGRAM STATUS REPORT/m ? 1 : 0), 1);
check('tagged portion marked (CUI)', ($plain =~ /^\(CUI\) 1\.  This memorandum/m ? 1 : 0), 1);
check('tags are stripped from the text', ($plain =~ /\{CUI\}|\{\/\}/ ? 1 : 0), 0);

print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
