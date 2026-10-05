# parse-config: Parse key=value lines
#
# Pattern:  split on the first separator only
# Why:      a limit of 2 on split keeps any later '=' inside the value
# Time:     O(n)   Space: O(n)
# Edge:     blank and whitespace-only lines; an empty text
# Perl:     split /=/, $line, 2; next unless /\S/
use strict;
use warnings;

sub parse_config {
    my ($text) = @_;
    my %c;
    for my $line (split /\n/, $text) {
        next unless $line =~ /\S/;
        my ($k, $v) = split /=/, $line, 2;
        $c{$k} = 0 + $v;
    }
    return \%c;
}

1;
