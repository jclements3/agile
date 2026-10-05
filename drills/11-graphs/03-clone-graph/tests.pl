# call builds the graph from adjacency lists (node i+1 = row i), clones node 1, then walks the copy:
# the result is its adjacency lists by value, plus 'shared' if any copied node is an original node.
+{
    fn    => 'clone_graph',
    call  => sub {
        my ($f, $adj) = @_;
        my @n = map { { val => $_ + 1, neighbors => [] } } 0 .. $#$adj;
        for my $i (0 .. $#$adj) { $n[$i]{neighbors} = [ map { $n[ $_ - 1 ] } @{ $adj->[$i] } ] }
        my %orig = map { ("$_" => 1) } @n;
        my $c = $f->(@n ? $n[0] : undef);
        return 'undef' unless $c;
        my (%seen, @q, %lists, $shared);
        @q = ($c); $seen{"$c"} = 1;
        while (my $x = shift @q) {
            $shared = 1 if $orig{"$x"};
            $lists{ $x->{val} } = [ map { $_->{val} } @{ $x->{neighbors} } ];
            for (@{ $x->{neighbors} }) { push @q, $_ unless $seen{"$_"}++ }
        }
        return [ (map { $lists{$_} } sort { $a <=> $b } keys %lists), $shared ? 'shared' : 'fresh' ];
    },
    cases => [
        [ 'sample, a square', [ [ [ 2, 4 ], [ 1, 3 ], [ 2, 4 ], [ 1, 3 ] ] ], [ [ 2, 4 ], [ 1, 3 ], [ 2, 4 ], [ 1, 3 ], 'fresh' ] ],
        [ 'one node',         [ [ [] ] ],                                    [ [], 'fresh' ] ],
        [ 'empty graph',      [ [] ],                                        'undef' ],
        [ 'two nodes',        [ [ [2], [1] ] ],                              [ [2], [1], 'fresh' ] ],
        [ 'triangle',         [ [ [ 2, 3 ], [ 1, 3 ], [ 1, 2 ] ] ],          [ [ 2, 3 ], [ 1, 3 ], [ 1, 2 ], 'fresh' ] ],
    ],
}
