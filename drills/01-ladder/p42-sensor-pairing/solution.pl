# p42-sensor-pairing: Sensor feed pairing
#
# Pattern:  build every compatible candidate, sort by (cost, A id, B id),
#           take greedily while both ends are unused
# Why:      the sort encodes the tie-breaks; walking it once gives the
#           defined greedy order; wrap_diff and compatible keep each rule in
#           one place
# Time:     O(nA*nB log(nA*nB))   Space: O(nA*nB). At 10^5 per feed: sort by
#           time and sweep a window of width t_tol, or bucket by time
# Edge:     wrap at 0/360; one detection compatible with several; nothing
#           pairs (exact text); uneven feeds
# Perl:     % is integer modulo in Perl: POSIX::fmod for the wrap
use strict;
use warnings;
use POSIX qw(fmod);

my @tok = split ' ', do { local $/; <STDIN> // '' };
my ($t_tol, $b_tol) = splice @tok, 0, 2;
my @A = read_feed();
my @B = read_feed();

my @cands;
for my $i (0 .. $#A) {
    for my $j (0 .. $#B) {
        next unless compatible($A[$i], $B[$j]);
        my $cost = abs($A[$i]{t} - $B[$j]{t}) + wrap_diff($A[$i]{b}, $B[$j]{b});
        push @cands, [ $cost, $i, $j ];
    }
}
my (%used_a, %used_b, @pairs);
for my $c (sort { $a->[0] <=> $b->[0] or $A[ $a->[1] ]{id} cmp $A[ $b->[1] ]{id} or $B[ $a->[2] ]{id} cmp $B[ $b->[2] ]{id} } @cands) {
    my (undef, $i, $j) = @$c;
    next if $used_a{$i} || $used_b{$j};
    $used_a{$i} = $used_b{$j} = 1;
    push @pairs, [ $A[$i]{id}, $B[$j]{id} ];
}
if (!@pairs) { print "NO PAIRING\n"; exit 0 }
print "$_->[0] $_->[1]\n" for sort { $a->[0] cmp $b->[0] } @pairs;
print 'unpaired A: ', unpaired(\@A, \%used_a), "\n";
print 'unpaired B: ', unpaired(\@B, \%used_b), "\n";

sub read_feed {
    my $n = shift @tok;
    return map { my ($id, $t, $b) = splice @tok, 0, 3; { id => $id, t => $t, b => $b } } 1 .. $n;
}

sub wrap_diff {
    my ($x, $y) = @_;
    my $d = fmod(abs($x - $y), 360);
    return $d < 360 - $d ? $d : 360 - $d;
}

sub compatible {
    my ($p, $q) = @_;
    return abs($p->{t} - $q->{t}) <= $t_tol && wrap_diff($p->{b}, $q->{b}) <= $b_tol;
}

sub unpaired {
    my ($feed, $used) = @_;
    my @ids = sort map { $feed->[$_]{id} } grep { !$used->{$_} } 0 .. $#$feed;
    return @ids ? "@ids" : '-';
}
