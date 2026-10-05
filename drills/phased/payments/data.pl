# The phased drill, scenario "payments": the data for each phase and the checker.
# `do` returns { check => sub ($solve, $phase, $say) -> 1 when the phase passes }. The data is fixed.
package Drills::Phased::Payments;
use strict;
use warnings;
use Scalar::Util qw(refaddr);

sub _r { my ($id, $time, $amount) = @_; +{ id => $id, time => $time, amount => $amount } }
sub _data {
    my ($phase) = @_;
    my @o = (_r('O1', 10.0, 25.00), _r('O2', 20.0, 40.00), _r('O3', 30.0, 60.00));
    my @p;
    if    ($phase == 1) { @p = (_r('P1', 10.0, 25.00), _r('P2', 20.0, 40.00), _r('P3', 30.0, 60.00)) }
    elsif ($phase == 2) { @p = (_r('P3', 28.0, 60.01), _r('P1', 11.5, 25.03), _r('P2', 22.0, 39.98)) }
    elsif ($phase == 3) { push @o, _r('O4', 40.0, 15.00); @p = (_r('P1', 11.5, 25.03), _r('P9', 90.0, 999.00), _r('P3', 28.0, 60.01)) }
    else                { @o = (_r('O1', 10.0, 25.00), _r('O2', 12.0, 25.00)); @p = (_r('P1', 10.5, 25.02), _r('P2', 12.5, 25.01)) }
    (\@o, \@p);
}
sub _unsolvable { ([ _r('O1', 0.0, 10.00) ], [ _r('P1', 500.0, 99.00) ]) }
sub _same { my ($o, $p) = @_; substr($o->{id} // '', 1) eq substr($p->{id} // '', 1) }

+{
    check => sub {
        my ($solve, $phase, $say) = @_;
        my ($o, $p) = _data($phase);
        my $r = eval { $solve->($o, $p) };
        if (!defined $r && $@) { my $e = $@; $e =~ s/\s+$//; $say->("solve died: $e"); return 0 }
        if (ref $r ne 'HASH' || ref $r->{pairs} ne 'ARRAY') { $say->('solve should return a hash ref { pairs => [...], unpaired_a => [...], unpaired_b => [...], ok => 1|0, reason => "..." }'); return 0 }
        my @pairs = grep { ref $_ eq 'ARRAY' && ref $_->[0] eq 'HASH' && ref $_->[1] eq 'HASH' } @{ $r->{pairs} };
        if (@pairs != @{ $r->{pairs} }) { $say->('every match should be [ $order, $payment ] (the hash refs you were given)'); return 0 }
        my $good = grep { _same(@$_) } @pairs;
        my $bad = @pairs - $good;
        $say->("correct matches: $good   wrong: $bad");
        if ($phase >= 3) {
            my ($uo, $up) = (scalar @{ $r->{unpaired_a} // [] }, scalar @{ $r->{unpaired_b} // [] });
            $say->("unmatched orders: $uo   unmatched payments: $up");
            my %a = map { refaddr($_->[0]) => 1 } @pairs;
            my %b = map { refaddr($_->[1]) => 1 } @pairs;
            if (keys %a != @pairs || keys %b != @pairs) { $say->('FAIL: a record was used in more than one match'); return 0 }
            if ($uo + @pairs != @$o || $up + @pairs != @$p) { $say->('FAIL: matches plus leftovers do not account for every record'); return 0 }
        }
        if ($phase >= 4) {
            my ($uo, $up) = _unsolvable();
            my $ru = eval { $solve->($uo, $up) };
            if (!defined $ru && $@) { my $e = $@; $e =~ s/\s+$//; $say->("the unsolvable case died: $e  (fine, if that is your stated contract)") }
            elsif (ref $ru eq 'HASH' && $ru->{ok} && @{ $ru->{pairs} // [] }) { $say->('FAIL: matched an input that has no valid matching'); return 0 }
            elsif (ref $ru eq 'HASH' && $ru->{ok}) { $say->('FAIL: the unsolvable case came back ok => 1 with no matches: say it failed (ok => 0, a reason)'); return 0 }
            else { $say->('unsolvable case handled' . (ref $ru eq 'HASH' && $ru->{reason} ? ": $ru->{reason}" : '')) }
        }
        $bad == 0 && $good > 0 ? 1 : 0;
    },
};
