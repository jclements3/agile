#!/usr/bin/perl
# Tally votes/estimates from a pasted Teams chat file (or stdin).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptionsFromArray);
use Chat;

my %o;
GetOptionsFromArray(\@ARGV, 'est=s' => \$o{est}, 'vote=s' => \$o{vote}, 'since=s' => \$o{since}, 'options=s' => \$o{options}, 'lines' => \$o{lines}, 'messages' => \$o{messages}) or exit 2;
my $file = shift @ARGV // '-';
open my $fh, '<', $file or die "cannot open $file: $!\n";
my $text = do { local $/; <$fh> };
close $fh;
if ($o{messages}) { printf "%s %-20s %s\n", $_->{time} // '--:--', $_->{who}, (split /\n/, $_->{text})[0] // '' for parse_chat($text); exit 0 }
if (defined $o{est} || defined $o{vote}) {
    my @m = parse_chat($text);
    my $t = defined $o{est} ? quick_est(\@m, $o{since}, $o{est}) : quick_vote(\@m, $o{since}, [ map { lc } split /[\/,\s]+/, ($o{options} // 'y/n') ], $o{vote});
    print $o{lines} ? standup_lines($t) : tally_text($t);
    exit 0;
}
my ($report, $lines, $n) = report($text);
print $o{lines} ? $lines : ($n ? $report : "no #est / #vote markers found (use --est ID or --vote Q for markerless tallies)\n");
