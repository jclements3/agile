# LRU cache
# Call: LRU->new($capacity); $c->put($key, $value); $c->get($key) -> value | undef
# Write your solution below. Run: perl drills/drill.pl test lru-cache
use strict;
use warnings;

package LRU;

sub new {
    my ($class, $cap) = @_;
    my $self = bless {}, $class;
    # your code here
    return $self;
}

sub get {
    my ($self, $k) = @_;
    # your code here
    return;
}

sub put {
    my ($self, $k, $v) = @_;
    # your code here
    return;
}

1;
