# caesar: Caesar cipher
#
# Pattern:  modular arithmetic on character codes
# Why:      offset from 'a' (or 'A'), add k, take mod 26, add the base back
# Time:     O(n)   Space: O(n)
# Edge:     wrap past z; k = 0 or 26; non-letters untouched
# Perl:     s///ge runs code per match; ord/chr convert; ($_ % 26) is non-negative for k >= 0
use strict;
use warnings;

sub caesar {
    my ($s, $k) = @_;
    $s =~ s{([A-Za-z])}{
        my $base = ord($1 ge 'a' ? 'a' : 'A');
        chr($base + (ord($1) - $base + $k) % 26);
    }ge;
    return $s;
}

1;
