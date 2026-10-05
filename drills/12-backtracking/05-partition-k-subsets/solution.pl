# partition-k-subsets: Split into k equal sums (LeetCode 698)
#
# Pattern:  backtracking: place each value (largest first) into a bucket that
#           still has room; prune hard
# Why:      large values first fail fast; if a value does not fit into an
#           empty bucket it fits into none, so stop trying further buckets
# Time:     O(k^n) worst case, far less with pruning   Space: O(n)
# Edge:     total not divisible by k; a value larger than the target
# Perl:     List::Util sum; sort { $b <=> $a } for descending; a recursive
#           closure over @bucket
use strict;
use warnings;
use List::Util qw(sum);

sub can_partition_k {
    my ($nums, $k) = @_;
    my $total = sum(0, @$nums);
    return 0 if $total % $k;
    my $target = $total / $k;
    my @v = sort { $b <=> $a } @$nums;
    return 0 if @v && $v[0] > $target;
    my @bucket = (0) x $k;
    my $go;
    $go = sub {
        my ($i) = @_;
        return 1 if $i == @v;
        for my $b (0 .. $k - 1) {
            if ($bucket[$b] + $v[$i] <= $target) {
                $bucket[$b] += $v[$i];
                return 1 if $go->($i + 1);
                $bucket[$b] -= $v[$i];
            }
            last if $bucket[$b] == 0;
        }
        return 0;
    };
    my $ok = $go->(0);
    undef $go;
    return $ok;
}

1;
