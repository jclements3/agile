+{
    fn    => 'reorder_list',
    call  => sub { my ($f, $list) = @_; Drills::list_to($f->(Drills::list_from($list))) },
    cases => [
        [ 'sample, even', [ [ 1, 2, 3, 4 ] ],          [ 1, 4, 2, 3 ] ],
        [ 'odd length',   [ [ 1, 2, 3, 4, 5 ] ],       [ 1, 5, 2, 4, 3 ] ],
        [ 'one node',     [ [7] ],                     [7] ],
        [ 'two nodes',    [ [ 7, 8 ] ],                [ 7, 8 ] ],
        [ 'empty',        [ [] ],                      [] ],
        [ 'six',          [ [ 1, 2, 3, 4, 5, 6 ] ],    [ 1, 6, 2, 5, 3, 4 ] ],
    ],
}
