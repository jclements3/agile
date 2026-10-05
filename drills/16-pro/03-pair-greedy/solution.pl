# pair-greedy: Pair values within a tolerance
#
# Pattern:  every compatible (difference, i, j) candidate, sorted, then taken
#           greedily when both ends are still free
# Why:      sorting by difference then index makes the choice deterministic;
#           the used sets enforce "at most once"
# Time:     O(n*m log(n*m))   Space: O(n*m)
# Edge:     no compatible pair -> []; one value close to several
# Perl:     named arguments as a hash after the positional ones (my %opt);
#           a three-key sort with ||
use strict;
use warnings;

sub pair_greedy {
    my ($x, $y, %opt) = @_;
    my $tol = $opt{tol} // 0;
    my @cand;
    for my $i (0 .. $#$x) {
        for my $j (0 .. $#$y) {
            my $d = abs($x->[$i] - $y->[$j]);
            push @cand, [ $d, $i, $j ] if $d <= $tol;
        }
    }
    my (%used_a, %used_b, @pairs);
    for my $c (sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @cand) {
        my (undef, $i, $j) = @$c;
        next if $used_a{$i} || $used_b{$j};
        $used_a{$i} = $used_b{$j} = 1;
        push @pairs, [ $x->[$i], $y->[$j] ];
    }
    return [ sort { $a->[0] <=> $b->[0] } @pairs ];
}

1;
