# Min stack
# Call: MinStack->new; $s->push($x); $s->pop; $s->top; $s->get_min
# Write your solution below. Run: perl drills/drill.pl test min-stack
use strict;
use warnings;

package MinStack;

sub new {
    my ($class) = @_;
    my $self = bless {}, $class;
    # your code here
    return $self;
}

sub push {
    my ($self, $x) = @_;
    # your code here
    return;
}

sub pop {
    my ($self) = @_;
    # your code here
    return;
}

sub top {
    my ($self) = @_;
    # your code here
    return;
}

sub get_min {
    my ($self) = @_;
    # your code here
    return;
}

1;
