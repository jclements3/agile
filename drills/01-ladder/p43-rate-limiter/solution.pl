# p43-rate-limiter: Sliding-window rate limiter
#
# Pattern:  a queue of allowed timestamps per client, a state machine over
#           the stream
# Why:      drop timestamps that left the window (<= ts - W) from the front;
#           what remains is exactly the allowed requests in (ts - W, ts]
# Time:     O(1) amortised per request (each timestamp enters and leaves
#           once)   Space: O(clients * L)
# Edge:     the half-open boundary (exactly W later is outside); denials do not
#           use budget; many clients
# Perl:     a hash of array refs; shift @{ $q{$c} } drops the front
use strict;
use warnings;

my ($W, $L) = split ' ', <STDIN> // '';
my (%q, @denied);
while (my $line = <STDIN>) {
    my ($ts, $client) = split ' ', $line;
    next unless defined $client;
    my $win = $q{$client} ||= [];
    shift @$win while @$win && $win->[0] <= $ts - $W;
    if (@$win >= $L) { push @denied, "$ts $client" }
    else { push @$win, $ts }
}
print @denied ? map { "$_\n" } @denied : "ok\n";
