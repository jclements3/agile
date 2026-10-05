# combination-sum: Combinations that hit a target (LeetCode 39)
#
# Pattern:  backtracking; the start index forbids going back to earlier
#           candidates, so [2, 3] and [3, 2] are not both produced
# Why:      recursing with the same index allows reuse; skipping candidates
#           larger than what remains prunes dead branches
# Time:     exponential in target / min(candidate)   Space: O(target / min)
# Edge:     no combination -> []; a target smaller than every candidate
# Perl:     a recursive closure (undef it afterwards to free the cycle)
use strict;
use warnings;

sub combination_sum {
    my ($cands, $target) = @_;
    my (@out, @cur);
    my $go;
    $go = sub {
        my ($start, $left) = @_;
        if ($left == 0) { push @out, [@cur]; return }
        for my $i ($start .. $#$cands) {
            next if $cands->[$i] > $left;
            push @cur, $cands->[$i];
            $go->($i, $left - $cands->[$i]);
            pop @cur;
        }
    };
    $go->(0, $target);
    undef $go;
    return \@out;
}

1;
