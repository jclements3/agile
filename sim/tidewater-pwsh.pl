#!/usr/bin/env perl
# sim/tidewater-pwsh.pl -- an EMULATION of Windows PowerShell 5.1 running a GitLab job script, for the Tidewater
# simulation (the team's Windows shell runner speaks PowerShell; the simulation's runner is this script).
#
#   tidewater-pwsh.pl -e SCRIPTFILE        (called by lib/GitLabCI.pm in place of `sh -e`)
#
# It does not implement PowerShell. It reproduces the three ways sh-style script lines fail there -- a `NAME=$(...)`
# assignment is read as a command name, `&&` and `||` are not statement separators in Windows PowerShell 5.1, and
# `$KIT` is a PowerShell variable (empty), not the environment variable ($env:KIT) -- with PowerShell's messages, and
# runs every other line as a plain command with PowerShell's quoting, stopping at the first failure as the runner does.
# A line like `perl ci/job.pl lint` runs unchanged, which is why the pipeline's script lines are written that way.
use strict;
use warnings;

my ($flag, $file) = @ARGV;
open my $fh, '<:raw', $file or do { print "Cannot find path '$file' because it does not exist.\n"; exit 1 };
my @lines = <$fh>;
close $fh;
my $n = 0;
for my $l (@lines) {
    chomp $l;
    next unless $l =~ /\S/;
    if ($l =~ /^printf "%s\\n" '(.*)'$/) { (my $e = $1) =~ s/'\\''/'/g; print "$e\n"; next }   # the runner's echo of the command
    $n++;
    my $col = 1;
    if ($l =~ /^\s*(\w+)=\$\(/) {
        my ($word) = $l =~ /^\s*(\S+)/;
        print "$word : The term '$word' is not recognized as the name of a cmdlet, function, script file, or operable program. Check the\n"
            . "spelling of the name, or if a path was included, verify that the path is correct and try again.\nAt line:$n char:1\n"
            . "+ $l\n+ ~~~~~~\n    + CategoryInfo          : ObjectNotFound: ($word:String) [], CommandNotFoundException\n"
            . "    + FullyQualifiedErrorId : CommandNotFoundException\n";
        exit 1;
    }
    if ($l =~ /(\|\||&&)/) {
        my $tok = $1; my $at = index($l, $tok) + 1;
        print "At line:$n char:$at\n+ $l\n+ " . (' ' x ($at - 1)) . "~~\nThe token '$tok' is not a valid statement separator in this version.\n"
            . "    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordException\n    + FullyQualifiedErrorId : InvalidEndOfLine\n";
        exit 1;
    }
    my @w;                                         # PowerShell quoting: "..." expands $var (a PowerShell variable: empty), '...' does not
    while ($l =~ /\G\s*(?:"((?:[^"`]|`.)*)"|'([^']*)'|(\S+))/g) {
        my $v = defined $1 ? $1 : defined $2 ? $2 : $3;
        if (!defined $2) { $v =~ s/\$env:(\w+)/$ENV{$1} \/\/ ''/ge; $v =~ s/\$\{?\w+\}?//g }
        push @w, $v;
    }
    next unless @w;
    my $rc = system(@w);
    if ($rc == -1) {
        print "$w[0] : The term '$w[0]' is not recognized as the name of a cmdlet, function, script file, or operable program.\n";
        exit 1;
    }
    exit($rc >> 8 || 1) if $rc;
}
exit 0;
