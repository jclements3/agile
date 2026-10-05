# phased-payments: the reference for all four phases (read it only after a timed attempt)
#
#   close_enough($o, $p, %o)  phase 2 cost one pair of constants: the two tolerances, as options
#   pair($orders, $pays, %o)  phase 3 cost a filter: used-once sets and the leftover lists
#                             phase 4 cost nothing new: the sort by combined difference already existed
#   solve(...)                the contract: { pairs, unpaired_a, unpaired_b, ok, reason }; no match at all is ok => 0
#
# Say out loud:
#   Time: O(n*m) candidates plus an O(nm log nm) sort; fine here. At scale, sort by time and only build
#     candidates inside a time_tol window (or bucket by time).
#   Greedy best-first is not globally optimal; the Hungarian algorithm is, at O(n^3). Choosing the simpler one
#     deliberately, and saying so, is the senior move.
#   Ties in the combined difference break by order id, then payment id, so the answer is deterministic.
use strict;
use warnings;

sub solve {
    my ($orders, $pays, %o) = @_;
    my %tol = (amount_tol => $o{amount_tol} // 0.05, time_tol => $o{time_tol} // 5.0);
    my ($pairs, $uo, $up) = pair($orders, $pays, %tol);
    return { pairs => [], unpaired_a => $uo, unpaired_b => $up, ok => 0, reason => 'nothing matches under the tolerances' } unless @$pairs;
    return { pairs => $pairs, unpaired_a => $uo, unpaired_b => $up, ok => 1, reason => '' };
}

sub close_enough {
    my ($ord, $pay, %o) = @_;
    return abs($ord->{amount} - $pay->{amount}) <= $o{amount_tol} + 1e-9 && abs($ord->{time} - $pay->{time}) <= $o{time_tol};
}

sub pair {
    my ($orders, $pays, %o) = @_;
    my @cand;
    for my $i (0 .. $#$orders) {
        for my $j (0 .. $#$pays) {
            my ($x, $y) = ($orders->[$i], $pays->[$j]);
            push @cand, [ abs($x->{amount} - $y->{amount}) + abs($x->{time} - $y->{time}), $i, $j ] if close_enough($x, $y, %o);
        }
    }
    my (%used_o, %used_p, @pairs);
    for my $c (sort { $a->[0] <=> $b->[0] || $orders->[ $a->[1] ]{id} cmp $orders->[ $b->[1] ]{id}
                      || $pays->[ $a->[2] ]{id} cmp $pays->[ $b->[2] ]{id} } @cand) {
        my (undef, $i, $j) = @$c;
        next if $used_o{$i} || $used_p{$j};
        $used_o{$i} = $used_p{$j} = 1;
        push @pairs, [ $orders->[$i], $pays->[$j] ];
    }
    return (\@pairs, [ map { $orders->[$_] } grep { !$used_o{$_} } 0 .. $#$orders ],
                     [ map { $pays->[$_] } grep { !$used_p{$_} } 0 .. $#$pays ]);
}

1;
