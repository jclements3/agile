# p55-gate-summary: Gate summary from diagnostics
#
# Pattern:  one anchored regex per line, counts in hashes, an exit status
# Why:      the regex picks only diagnostic lines; the files hash counts each
#           file once however many lines it has
# Time:     O(n)   Space: O(files)
# Edge:     non-diagnostic lines ignored; a colon inside the message; drive
#           letters: the lazy (.+?) stops at the first ":digits:", so C:\x:3:
#           works too
# Perl:     exit($n{error} ? 1 : 0) after printing; // 0 for absent counts
use strict;
use warnings;

my (%files, %n);
while (my $line = <STDIN>) {
    next unless $line =~ /^(.+?):(\d+):\s*(error|warning):/;
    $files{$1} = 1;
    $n{$3}++;
}
printf "%d file(s): %d error(s), %d warning(s)\n", scalar(keys %files), $n{error} // 0, $n{warning} // 0;
exit($n{error} ? 1 : 0);
