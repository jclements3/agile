# subsets: All subsets (LeetCode 78)
#
# Pattern:  backtracking: for each element, recurse without it, then with it
# Why:      two choices per element give every combination exactly once
# Time:     O(n * 2^n)   Space: O(n) recursion besides the output
# Edge:     empty input -> one empty subset
# Perl:     [@cur] copies the current choice before it changes again;
#           push / pop make and undo a choice
use strict;
use warnings;

sub subsets {
    my ($nums) = @_;
    my (@out, @cur);
    my $go;
    $go = sub {
        my ($i) = @_;
        if ($i == @$nums) { push @out, [@cur]; return }
        $go->($i + 1);
        push @cur, $nums->[$i];
        $go->($i + 1);
        pop @cur;
    };
    $go->(0);
    undef $go;
    return \@out;
}

1;
