#!/usr/bin/perl
# sim/msp.pl -- build docs/ModernSoftwarePractices.pdf from docs/src/msp/ModernSoftwarePractices.tex
#   (Modern Software Practices: A Condensed Guide -- an unofficial condensation of the DoW CIO library's software
#   modernization, DevSecOps, open source and cATO documents; the source documents are not in the repository)
#
#   perl sim/msp.pl [--keep]      XeLaTeX via latexmk in a temporary directory; copies the PDF to docs/;
#                                 fails on an overfull box wider than 5pt or an undefined reference
# Needs XeLaTeX + latexmk (not on the target laptop, so the PDF is committed), the TeX Gyre and DejaVu fonts, and
# docs/img/cover-art-color.jpg (the cover art).
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(abs_path);

my $keep = grep { $_ eq '--keep' } @ARGV;
my $ROOT = abs_path(dirname(abs_path($0)) . '/..');
my $SRC  = "$ROOT/docs/src/msp/ModernSoftwarePractices.tex";
my $OUT  = "$ROOT/docs/ModernSoftwarePractices.pdf";
-f $SRC or die "msp: no source at $SRC\n";
for my $tool (qw(xelatex latexmk)) {
    system("$tool -v >/dev/null 2>&1") == 0 or die "msp: $tool not found (install TeX Live with XeLaTeX and latexmk)\n";
}
my $dir = tempdir('msp-XXXXXX', TMPDIR => 1, CLEANUP => !$keep);
copy($SRC, "$dir/ModernSoftwarePractices.tex") or die "msp: copy: $!\n";
copy("$ROOT/docs/img/cover-art-color.jpg", "$dir/cover-art-color.jpg") or die "msp: no docs/img/cover-art-color.jpg: $!\n";
chdir $dir or die "msp: $dir: $!\n";
my $rc = system('latexmk -xelatex -interaction=nonstopmode -halt-on-error ModernSoftwarePractices.tex >latexmk.out 2>&1');
open my $lf, '<', 'ModernSoftwarePractices.log' or die "msp: no log (latexmk failed early; see $dir/latexmk.out)\n";
my $log = do { local $/; <$lf> };
die "msp: latexmk failed; see $dir/ModernSoftwarePractices.log\n" if $rc;
my @over = grep { $_ > 5 } $log =~ /Overfull \\hbox \(([\d.]+)pt too wide\)/g;
my @undef = $log =~ /(Reference `[^']+' on page \d+ undefined)/g;
die "msp: " . scalar(@over) . " overfull box(es) wider than 5pt (widest " . (sort { $b <=> $a } @over)[0] . "pt); see $dir\n" if @over;
die "msp: undefined references: @undef\n" if @undef;
copy('ModernSoftwarePractices.pdf', $OUT) or die "msp: copy PDF: $!\n";
my ($pages) = `pdfinfo '$OUT' 2>/dev/null` =~ /^Pages:\s+(\d+)/m;
print "wrote $OUT" . ($pages ? " ($pages pages)" : '') . "\n";
print "kept $dir\n" if $keep;
