# lru-cache: LRU cache (LeetCode 146)
#
# Pattern:  hash plus a recency order
# Why:      the hash gives the value; a counter stamped on every use tells which
#           key was used longest ago, so eviction picks the smallest stamp
# Time:     get O(1), put O(1) until an eviction, which is O(capacity) here
#           (a doubly linked list makes it O(1): say so)
# Space:    O(capacity)
# Edge:     put on an existing key is an update and a use; capacity 1
# Perl:     a blessed hash; exists before reading; sort keys by stamp to evict
use strict;
use warnings;

package LRU;

sub new {
    my ($class, $cap) = @_;
    return bless { cap => $cap, val => {}, used => {}, clock => 0 }, $class;
}

sub get {
    my ($self, $k) = @_;
    return unless exists $self->{val}{$k};
    $self->{used}{$k} = ++$self->{clock};
    return $self->{val}{$k};
}

sub put {
    my ($self, $k, $v) = @_;
    if (!exists $self->{val}{$k} && keys %{ $self->{val} } >= $self->{cap}) {
        my ($old) = sort { $self->{used}{$a} <=> $self->{used}{$b} } keys %{ $self->{used} };
        delete $self->{val}{$old};
        delete $self->{used}{$old};
    }
    $self->{val}{$k} = $v;
    $self->{used}{$k} = ++$self->{clock};
    return;
}

1;
