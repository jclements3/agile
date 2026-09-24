#!/usr/bin/perl
# docs2txt.pl -- read Office/PDF documents from the shell, using the converters Git for Windows already ships.
#
#   perl bin/docs2txt.pl FILE...                    text of each file to stdout (a "==> FILE <==" header when more than one)
#   perl bin/docs2txt.pl -o DIR FILE...             write DIR/<name>.txt per file instead (grep/diff/vim them later)
#   perl bin/docs2txt.pl grep [-i] PATTERN FILE...  grep the text of each file: "FILE:LINE: text" -- greps a PDF like a .txt
#   perl bin/docs2txt.pl tools                      which converters were found
#
# Formats: .pdf (pdftotext), .docx (docx2txt), .doc (antiword), .odt (odt2txt), .html/.htm (tags stripped here),
# .txt/.md/.csv (as is). Core Perl only; the converters are looked up on PATH and in the usual Git for Windows
# directories. A file whose converter is missing is reported, not silently skipped.
use strict;
use warnings;
use File::Basename qw(basename);

my @GIT = grep { -d } ('/mingw64/bin', '/usr/bin', 'C:/Program Files/Git/mingw64/bin', 'C:/Program Files/Git/usr/bin',
                       '/mnt/c/Program Files/Git/mingw64/bin', '/mnt/c/Program Files/Git/usr/bin');
sub which_ { my $n = shift; for my $d (split(/[:;]/, $ENV{PATH} // ''), @GIT) { for my $x ('', '.exe') { my $p = "$d/$n$x"; return $p if -f $p && -x $p } } undef }
my %TOOL = (pdf => 'pdftotext', docx => 'docx2txt', doc => 'antiword', odt => 'odt2txt');
my %BIN  = map { $_ => which_($TOOL{$_}) } keys %TOOL;

sub text_of {                                  # -> (text, error)
    my $f = shift;
    return (undef, "no such file") unless -f $f;
    my ($ext) = lc($f) =~ /\.(\w+)$/;
    $ext //= 'txt';
    if ($ext =~ /^(txt|md|csv|text|log)$/) { local $/; open my $fh, '<', $f or return (undef, $!); my $t = <$fh>; close $fh; return ($t, undef) }
    if ($ext =~ /^html?$/) { local $/; open my $fh, '<', $f or return (undef, $!); my $t = <$fh>; close $fh;
        $t =~ s/<(script|style)\b.*?<\/\1>//gis; $t =~ s/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/\n/gi; $t =~ s/<[^>]+>//g;
        $t =~ s/&nbsp;/ /g; $t =~ s/&amp;/&/g; $t =~ s/&lt;/</g; $t =~ s/&gt;/>/g; $t =~ s/&#(\d+);/chr $1/ge; $t =~ s/\n{3,}/\n\n/g; return ($t, undef) }
    my $tool = $TOOL{$ext} or return (undef, "no converter for .$ext");
    my $bin  = $BIN{$ext}  or return (undef, "$tool not found (Git for Windows ships it in mingw64/bin or usr/bin)");
    my @cmd = $ext eq 'pdf'  ? ($bin, '-layout', '-enc', 'UTF-8', $f, '-')
            : $ext eq 'docx' ? ($bin, $f, '-')
            : $ext eq 'doc'  ? ($bin, '-t', $f)
            :                  ($bin, $f);
    my $out = do { open my $ph, '-|', @cmd or return (undef, "cannot run $tool: $!"); local $/; my $t = <$ph>; close $ph; $t };
    return (undef, "$tool failed on $f") if !defined $out || ($? >> 8 && !length $out);
    ($out, undef);
}

my @a = @ARGV;
if (!@a || $a[0] =~ /^(-h|--help)$/) { open my $s, '<', $0 or die; my @src = <$s>; close $s; print map { s/^#\s?//r } @src[1..11]; exit 0 }
if ($a[0] eq 'tools') { printf "%-5s %-9s %s\n", ".$_", $TOOL{$_}, $BIN{$_} // 'NOT FOUND' for sort keys %TOOL; exit 0 }

my $rc = 0;
if ($a[0] eq 'grep') {
    shift @a;
    my $ci = @a && $a[0] eq '-i' ? shift @a : 0;
    my $pat = shift @a // die "usage: docs2txt.pl grep [-i] PATTERN FILE...\n";
    my $re = $ci ? qr/$pat/i : qr/$pat/;
    for my $f (@a) {
        my ($t, $err) = text_of($f);
        if ($err) { print STDERR "$f: $err\n"; $rc = 2; next }
        my $n = 0;
        for my $l (split /\n/, $t) { $n++; next unless $l =~ $re; (my $s = $l) =~ s/^\s+//; print "$f:$n: $s\n" }
    }
    exit $rc;
}

my $dir;
if ($a[0] eq '-o') { shift @a; $dir = shift @a // die "-o needs a directory\n"; mkdir $dir unless -d $dir }
for my $f (@a) {
    my ($t, $err) = text_of($f);
    if ($err) { print STDERR "$f: $err\n"; $rc = 2; next }
    if ($dir) { (my $o = basename($f)) =~ s/\.\w+$//; open my $fh, '>', "$dir/$o.txt" or die "cannot write $dir/$o.txt: $!\n"; print $fh $t; close $fh; print "wrote $dir/$o.txt\n" }
    else { print "==> $f <==\n" if @a > 1; print $t; print "\n" unless $t =~ /\n\z/ }
}
exit $rc;
