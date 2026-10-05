# The phased drill, scenario "sensors": the data for each phase and the checker.
# `do` returns { check => sub ($solve, $phase, $say) -> 1 when the phase passes }.
# The random parts come from a small LCG seeded by $ENV{DRILL_SEED} (default 49): DRILL_SEED=99 gives fresh data.
package Drills::Phased::Sensors;
use strict;
use warnings;
use Scalar::Util qw(refaddr);

my $state;
sub _seed { $state = (shift) % 2147483648 }
sub _rand { $state = ($state * 1103515245 + 12345) % 2147483648; $state / 2147483648 }
sub _uniform { my ($lo, $hi) = @_; $lo + ($hi - $lo) * _rand() }
sub _shuffle { my @a = @_; for (my $i = $#a; $i > 0; $i--) { my $j = int(_rand() * ($i + 1)); @a[ $i, $j ] = @a[ $j, $i ] } @a }
sub _det { my ($id, $t, $b) = @_; +{ id => $id, t => $t, bearing => $b } }

sub _data {
    my ($phase) = @_;
    _seed(($ENV{DRILL_SEED} // 49) + $phase);
    my @truth = map { [ 10.0 + 3.0 * $_, _uniform(5, 355) ] } 0 .. 7;
    my (@a, @b);
    if ($phase == 1) {
        @a = map { _det("A$_", @{ $truth[$_] }) } 0 .. 7;
        @b = map { _det("B$_", @{ $truth[$_] }) } 0 .. 7;
    }
    elsif ($phase == 2) {
        @a = map { _det("A$_", @{ $truth[$_] }) } 0 .. 7;
        for my $i (0 .. 7) {
            my ($t, $br) = @{ $truth[$i] };
            push @b, _det("B$i", $t + _uniform(-0.4, 0.4), $br + _uniform(-1.5, 1.5));
            push @b, _det("B${i}x", $t + 1.5 + _uniform(-0.3, 0.3), $br + _uniform(-1.5, 1.5));
        }
        @b = _shuffle(@b);
    }
    elsif ($phase == 3) {
        for my $i (0 .. 7) {
            my ($t, $br) = @{ $truth[$i] };
            push @a, _det("A$i", $t, $br);
            push @b, _det("B$i", $t + _uniform(-0.4, 0.4), $br + _uniform(-1.5, 1.5)) if $i % 4 != 3;   # two A's have no partner
        }
        push @b, _det("Bclutter$_", _uniform(0, 60), _uniform(0, 360)) for 0 .. 2;                   # clutter matches nothing
        @a = _shuffle(@a);
        @b = _shuffle(@b);
    }
    else {                                                       # bearings that wrap
        @a = (_det('A0', 10.0, 359.2), _det('A1', 13.0, 0.5), _det('A2', 16.0, 180.0));
        @b = (_det('B0', 10.2, 0.9), _det('B1', 13.1, 359.8), _det('B2', 16.1, 181.0));
    }
    (\@a, \@b);
}
sub _unsolvable { ([ _det('A0', 0.0, 10.0), _det('A1', 1.0, 20.0) ], [ _det('B0', 900.0, 200.0), _det('B1', 950.0, 300.0) ]) }

sub _same_object {                                               # the ground truth: the numeric parts of the ids match
    my ($x, $y) = @_;
    (my $p = $x->{id} // '') =~ tr/0-9//cd;
    (my $q = $y->{id} // '') =~ tr/0-9//cd;
    $p eq $q && $p ne '' && ($x->{id} . $y->{id}) !~ /clutter/;
}

+{
    check => sub {
        my ($solve, $phase, $say) = @_;
        my ($a, $b) = _data($phase);
        my $r = eval { $solve->($a, $b) };
        if (!defined $r && $@) { my $e = $@; $e =~ s/\s+$//; $say->("solve died: $e"); return 0 }
        if (ref $r ne 'HASH' || ref $r->{pairs} ne 'ARRAY') { $say->('solve should return a hash ref { pairs => [...], unpaired_a => [...], unpaired_b => [...], ok => 1|0, reason => "..." }'); return 0 }
        my @pairs = grep { ref $_ eq 'ARRAY' && ref $_->[0] eq 'HASH' && ref $_->[1] eq 'HASH' } @{ $r->{pairs} };
        if (@pairs != @{ $r->{pairs} }) { $say->('every pair should be [ $detection_a, $detection_b ] (the hash refs you were given)'); return 0 }
        my $good = grep { _same_object(@$_) } @pairs;
        my $bad = @pairs - $good;
        $say->("correct pairs: $good   wrong pairs: $bad");
        if ($phase >= 3) {
            my ($ua, $ub) = (scalar @{ $r->{unpaired_a} // [] }, scalar @{ $r->{unpaired_b} // [] });
            $say->("unpaired A: $ua   unpaired B: $ub");
            my %ua = map { refaddr($_->[0]) => 1 } @pairs;
            my %ub = map { refaddr($_->[1]) => 1 } @pairs;
            if (keys %ua != @pairs || keys %ub != @pairs) { $say->('FAIL: a detection was used in more than one pair'); return 0 }
            if ($ua + @pairs != @$a || $ub + @pairs != @$b) { $say->('FAIL: pairs plus unpaired do not account for every detection'); return 0 }
        }
        if ($phase >= 4) {
            my ($ua, $ub) = _unsolvable();
            my $ru = eval { $solve->($ua, $ub) };
            if (!defined $ru && $@) { my $e = $@; $e =~ s/\s+$//; $say->("the unsolvable case died: $e  (fine, if that is your stated contract)") }
            elsif (ref $ru eq 'HASH' && $ru->{ok} && @{ $ru->{pairs} // [] }) { $say->('FAIL: reported pairs for an input that has no valid pairing'); return 0 }
            elsif (ref $ru eq 'HASH' && $ru->{ok}) { $say->('FAIL: the unsolvable case came back ok => 1 with no pairs: say it failed (ok => 0, a reason)'); return 0 }
            else { $say->('unsolvable case handled' . (ref $ru eq 'HASH' && $ru->{reason} ? ": $ru->{reason}" : '')) }
        }
        $bad == 0 && $good > 0 ? 1 : 0;
    },
};
