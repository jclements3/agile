+{
    fn    => 'merge_two_lists',
    call  => sub { my ($f, $x, $y) = @_; Drills::list_to($f->(Drills::list_from($x), Drills::list_from($y))) },
    cases => [
        [ 'sample',        [ [ 1, 4, 6 ], [ 2, 3 ] ],    [ 1, 2, 3, 4, 6 ] ],
        [ 'first empty',   [ [], [5] ],                  [5] ],
        [ 'both empty',    [ [], [] ],                   [] ],
        [ 'equal values',  [ [ 1, 2, 2 ], [ 2, 3 ] ],    [ 1, 2, 2, 2, 3 ] ],
        [ 'one runs out',  [ [ 10, 20, 30 ], [ 1 ] ],    [ 1, 10, 20, 30 ] ],
    ],
}
