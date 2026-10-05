+{
    fn    => 'reverse_list',
    call  => sub { my ($f, $list) = @_; Drills::list_to($f->(Drills::list_from($list))) },
    cases => [
        [ 'sample',       [ [ 7, 8, 9 ] ],       [ 9, 8, 7 ] ],
        [ 'one node',     [ [4] ],               [4] ],
        [ 'empty',        [ [] ],                [] ],
        [ 'two nodes',    [ [ 1, 2 ] ],          [ 2, 1 ] ],
        [ 'duplicates',   [ [ 5, 5, 6, 5 ] ],    [ 5, 6, 5, 5 ] ],
    ],
}
