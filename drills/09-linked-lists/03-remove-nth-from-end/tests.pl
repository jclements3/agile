+{
    fn    => 'remove_nth_from_end',
    call  => sub { my ($f, $list, $n) = @_; Drills::list_to($f->(Drills::list_from($list), $n)) },
    cases => [
        [ 'sample',          [ [ 1, 2, 3, 4 ], 2 ],  [ 1, 2, 4 ] ],
        [ 'only node',       [ [9], 1 ],             [] ],
        [ 'remove the head', [ [ 5, 6 ], 2 ],        [6] ],
        [ 'remove the tail', [ [ 5, 6, 7 ], 1 ],     [ 5, 6 ] ],
    ],
}
