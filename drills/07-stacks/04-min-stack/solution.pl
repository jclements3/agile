# min-stack: Min stack (LeetCode 155)
#
# Pattern:  keep a parallel stack whose top is the minimum so far
# Why:      every push records min(x, previous min); a pop removes both tops,
#           so the minimum of what is left is exposed again
# Time:     O(1) every operation   Space: O(n)
# Edge:     equal minimums: each push stores its own copy
# Perl:     a blessed hash holding two array refs; $a->[-1] is the top;
#           methods named push/pop are fine inside a package (called as methods)
use strict;
use warnings;

package MinStack;

sub new {
    my ($class) = @_;
    return bless { items => [], mins => [] }, $class;
}

sub push {
    my ($self, $x) = @_;
    my $m = $self->{mins};
    CORE::push @{ $self->{items} }, $x;
    CORE::push @$m, (@$m && $m->[-1] < $x ? $m->[-1] : $x);
    return;
}

sub pop {
    my ($self) = @_;
    CORE::pop @{ $self->{mins} };
    return CORE::pop @{ $self->{items} };
}

sub top {
    my ($self) = @_;
    return $self->{items}[-1];
}

sub get_min {
    my ($self) = @_;
    return $self->{mins}[-1];
}

1;
