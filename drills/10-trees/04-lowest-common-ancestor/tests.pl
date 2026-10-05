+{
    fn    => 'lowest_common_ancestor',
    call  => sub { my ($f, $t, $p, $q) = @_; my $r = Drills::tree_from($t); my $n = $f->($r, Drills::tree_find($r, $p), Drills::tree_find($r, $q)); $n ? $n->{val} : undef },
    cases => [
        [ 'sample',            [ [ 6, 2, 8, 0, 4, 7, 9 ], 2, 8 ], 6 ],
        [ 'ancestor of itself',[ [ 6, 2, 8, 0, 4, 7, 9 ], 2, 4 ], 2 ],
        [ 'both on the right', [ [ 6, 2, 8, 0, 4, 7, 9 ], 7, 9 ], 8 ],
        [ 'deep split',        [ [ 6, 2, 8, 0, 4, 7, 9, undef, undef, 3, 5 ], 3, 5 ], 4 ],
        [ 'two nodes',         [ [ 2, 1 ], 2, 1 ], 2 ],
    ],
}
