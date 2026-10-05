# phased-sensors: the reference for all four phases (read it only after a timed attempt)
#
# Decomposition, chosen in phase 1 so that later phases cost one function each:
#   close_enough($x, $y, %o)  phase 2 put the tolerances here; phase 4 put the bearing wrap here (wrap_diff)
#   validate($a, $b, %o)      phase 4: inputs that cannot pair at all are refused here, before any pairing
#   pair($a, $b, %o)          phase 3: each detection used at most once, leftovers returned
#   solve($a, $b, %o)         the contract: { pairs, unpaired_a, unpaired_b, ok, reason }
#
# Say out loud:
#   Time: O(n*m) to build the candidates, O(nm log nm) to sort them; fine for a few thousand per feed.
#     At 10^5 per feed: sort both feeds by t and sweep with a window of width t_tol (or bucket by time),
#     so only near-in-time pairs are ever built: about O((n + m) log(n + m)).
#   Greedy by lowest cost is not globally optimal. The optimal assignment is the Hungarian algorithm,
#     O(n^3). Naming the better algorithm and choosing the simpler one on purpose is the senior move.
#   The wrap fix is min(d, 360 - d) with d = |x - y| mod 360, and it lives in ONE function.
#   Contract for "no answer": ok => 0 with a reason, never a partial list that looks right.
use strict;
use warnings;

sub solve {
    my ($feed_a, $feed_b, %o) = @_;
    my %tol = (t_tol => $o{t_tol} // 0.75, b_tol => $o{b_tol} // 2.5);
    if (my $why = validate($feed_a, $feed_b, %tol)) {
        return { pairs => [], unpaired_a => [@$feed_a], unpaired_b => [@$feed_b], ok => 0, reason => $why };
    }
    my ($pairs, $ua, $ub) = pair($feed_a, $feed_b, %tol);
    return { pairs => [], unpaired_a => $ua, unpaired_b => $ub, ok => 0, reason => 'no pairing satisfies the tolerances' } unless @$pairs;
    return { pairs => $pairs, unpaired_a => $ua, unpaired_b => $ub, ok => 1, reason => '' };
}

sub wrap_diff {                                                  # degrees apart on a circle
    my ($x, $y) = @_;
    my $d = abs($x - $y);
    $d -= 360 * int($d / 360);
    return $d < 360 - $d ? $d : 360 - $d;
}

sub close_enough {
    my ($x, $y, %o) = @_;
    return abs($x->{t} - $y->{t}) <= $o{t_tol} && wrap_diff($x->{bearing}, $y->{bearing}) <= $o{b_tol};
}

sub validate {
    my ($feed_a, $feed_b, %o) = @_;
    return 'a feed is empty' unless @$feed_a && @$feed_b;
    my ($a_lo, $a_hi) = _span($feed_a);
    my ($b_lo, $b_hi) = _span($feed_b);
    return 'the feeds do not overlap in time' if $b_lo - $a_hi > $o{t_tol} || $a_lo - $b_hi > $o{t_tol};
    return;
}

sub pair {                                                       # greedy, best cost first; ties by A id then B id
    my ($feed_a, $feed_b, %o) = @_;
    my @cand;
    for my $i (0 .. $#$feed_a) {
        for my $j (0 .. $#$feed_b) {
            my ($x, $y) = ($feed_a->[$i], $feed_b->[$j]);
            next unless close_enough($x, $y, %o);
            push @cand, [ abs($x->{t} - $y->{t}) + wrap_diff($x->{bearing}, $y->{bearing}), $i, $j ];
        }
    }
    my (%used_a, %used_b, @pairs);
    for my $c (sort { $a->[0] <=> $b->[0] || $feed_a->[ $a->[1] ]{id} cmp $feed_a->[ $b->[1] ]{id}
                      || $feed_b->[ $a->[2] ]{id} cmp $feed_b->[ $b->[2] ]{id} } @cand) {
        my (undef, $i, $j) = @$c;
        next if $used_a{$i} || $used_b{$j};
        $used_a{$i} = $used_b{$j} = 1;
        push @pairs, [ $feed_a->[$i], $feed_b->[$j] ];
    }
    return (\@pairs, [ map { $feed_a->[$_] } grep { !$used_a{$_} } 0 .. $#$feed_a ],
                     [ map { $feed_b->[$_] } grep { !$used_b{$_} } 0 .. $#$feed_b ]);
}

sub _span { my $f = shift; my ($lo, $hi) = ($f->[0]{t}) x 2; for (@$f) { $lo = $_->{t} if $_->{t} < $lo; $hi = $_->{t} if $_->{t} > $hi } ($lo, $hi) }

1;
