+{
    fn    => 'find_peak',
    check => sub {
        my ($got, $want, $nums) = @_;
        return 0 unless defined $got && $got =~ /^\d+$/ && $got <= $#$nums;
        my $v = $nums->[$got];
        return 0 if $got > 0 && $nums->[ $got - 1 ] >= $v;
        return 0 if $got < $#$nums && $nums->[ $got + 1 ] >= $v;
        return 1;
    },
    cases => [
        [ 'sample',       [ [ 1, 3, 2 ] ],              1 ],
        [ 'two peaks',    [ [ 1, 2, 1, 3, 1 ] ],        3 ],
        [ 'one element',  [ [5] ],                      0 ],
        [ 'rising',       [ [ 1, 2, 3, 4 ] ],           3 ],
        [ 'falling',      [ [ 9, 4, 1 ] ],              0 ],
    ],
}
