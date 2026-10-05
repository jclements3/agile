# top-k-frequent: Top k frequent values (LeetCode 347)
#
# Pattern:  count in a hash, then bucket sort by count
# Why:      a count is at most n, so bucket[c] lists the values seen c times;
#           walking the buckets from n down collects the most frequent first
# Time:     O(n)   Space: O(n)
# Edge:     k equal to the number of distinct values; negative values
# Perl:     $count{$_}++ for @$nums ; push @{ $bucket[$c] }, $x
use strict;
use warnings;

sub top_k_frequent {
    my ($nums, $k) = @_;
    my %count;
    $count{$_}++ for @$nums;
    my @bucket;
    push @{ $bucket[ $count{$_} ] }, $_ for keys %count;
    my @out;
    for (my $c = $#bucket; $c > 0 && @out < $k; $c--) {
        for my $x (@{ $bucket[$c] || [] }) {
            push @out, $x;
            last if @out == $k;
        }
    }
    return \@out;
}

1;
