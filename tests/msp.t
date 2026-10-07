#!/usr/bin/perl
# perl tests/msp.t -- docs/ModernSoftwarePractices.pdf, the condensed guide to the DoW CIO library's modern software
# practices documents (source docs/src/msp/ModernSoftwarePractices.tex, built by sim/msp.pl): the source cites only
# the short names it defines, lists all nineteen sources with a SHA-256 each, flags the drafts and the unofficial
# status; the committed PDF exists and has 30-50 pages; and, when the source documents are present in refs/ (they are
# git-ignored), every checksum in the sources appendix matches a file there
use strict;
use warnings;
use FindBin;
use Digest::SHA;

my $ROOT = "$FindBin::Bin/..";
my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if (defined $got && $got eq $want) { print "ok $n - $name\n"; return 1 }
    $bad++; print "not ok $n - $name\n#   got:  " . ($got // 'undef') . "\n#   want: $want\n"; return 0 }
sub list { my ($name, @bad) = @_; check_($name, scalar(@bad), 0) or print map { "#   | $_\n" } @bad[0 .. ($#bad < 9 ? $#bad : 9)] }
sub slurp { my $p = shift; open my $fh, '<:raw', $p or return undef; local $/; my $t = <$fh>; close $fh; $t }

my $tex = slurp("$ROOT/docs/src/msp/ModernSoftwarePractices.tex");
check_('the source exists', defined $tex ? 1 : 0, 1);
$tex //= '';

# the short names defined in the status table (column 2 of tab:status)
my ($status) = $tex =~ /\\label\{tab:status\}(.*?)\\end\{longtable\}/s;
my %short;
for my $row (split /\\\\\s*\n/, $status // '') {
    my @c = split /(?<!\\)&/, $row;
    next unless @c == 4;
    (my $s = $c[1]) =~ s/^\s+|\s+$//g;
    $short{$s} = 1 if $s && $s !~ /Short name/;
}
check_('the status table defines a short name for each of the 19 documents', scalar(keys %short), 19);
my %used; $used{$1}++ while $tex =~ /\\pg\{([^}]+)\}\{/g;
list('every citation uses a short name the status table defines', grep { !$short{$_} } sort keys %used);
list('every document is cited at least once (the workbook through the guidebook)', grep { !$used{$_} && $_ ne 'Workbook' } sort keys %short);

# sources appendix: 19 rows, each with a URL and a SHA-256
my ($src) = $tex =~ /\\label\{app:sources\}(.*?)\\end\{longtable\}/s;
my @rows = grep { /^\d+ & / } map { (my $r = $_) =~ s/^.*\n(?=\d+ & )//s; $r } split /\\\\\s*\n/, $src // '';
check_('the sources appendix lists 19 documents', scalar(@rows), 19);
list('each source has an address and a SHA-256', grep { !(/\\url\{https:\/\/[^}]+\}/ && /\b[0-9a-f]{64}\b/) } @rows);
check_('the drafts are flagged as drafts', ($tex =~ /RD-AWS.*\\st\{DRAFT\}/ && $tex =~ /RD-Azure.*\\st\{DRAFT\}/) ? 1 : 0, 1);
check_('the guide says it is unofficial and the originals govern', ($tex =~ /unofficial condensation\. The originals govern/) ? 1 : 0, 1);
check_('the Distribution C marking of the cATO guide is called out', ($tex =~ /Distribution Statement~C/) ? 1 : 0, 1);

# the committed PDF
my $pdf = "$ROOT/docs/ModernSoftwarePractices.pdf";
check_('docs/ModernSoftwarePractices.pdf is committed', -s $pdf ? 1 : 0, 1);
my ($pages) = (qx(pdfinfo "$pdf" 2>/dev/null) // '') =~ /^Pages:\s+(\d+)/m;
if (defined $pages) { check_("the PDF has 30-50 pages ($pages)", ($pages >= 30 && $pages <= 50) ? 1 : 0, 1) }
else { print "ok " . ++$n . " # skip pdfinfo not available\n" }

# checksums against refs/ when the source documents are present
my $refs = "$ROOT/refs";
if (-d $refs) {
    my %have;
    opendir my $dh, $refs or die "$refs: $!";
    for my $f (grep { -f "$refs/$_" } readdir $dh) { $have{ Digest::SHA->new(256)->addfile("$refs/$f", 'b')->hexdigest } = $f }
    my @sha = map { /\b([0-9a-f]{64})\b/ ? $1 : () } @rows;
    list('every SHA-256 in the sources appendix matches a document in refs/', grep { !$have{$_} } @sha);
} else { print "ok " . ++$n . " # skip refs/ not present (the source documents are not in the repository)\n" }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
