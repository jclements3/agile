# clone-graph: Clone a graph (LeetCode 133)
#
# Pattern:  breadth-first search with a map from each original node to its copy
# Why:      a node is copied the first time it is seen, so cycles stop there;
#           each original's neighbour list is then rebuilt from the copies
# Time:     O(V + E)   Space: O(V)
# Edge:     undef in, undef out; one node with no neighbours; cycles
# Perl:     a reference stringifies to a unique address: "$node" is a hash key
use strict;
use warnings;

sub clone_graph {
    my ($node) = @_;
    return undef unless $node;
    my %copy = ("$node" => { val => $node->{val}, neighbors => [] });
    my @queue = ($node);
    while (my $cur = shift @queue) {
        for my $nbr (@{ $cur->{neighbors} }) {
            if (!$copy{"$nbr"}) {
                $copy{"$nbr"} = { val => $nbr->{val}, neighbors => [] };
                push @queue, $nbr;
            }
            push @{ $copy{"$cur"}{neighbors} }, $copy{"$nbr"};
        }
    }
    return $copy{"$node"};
}

1;
