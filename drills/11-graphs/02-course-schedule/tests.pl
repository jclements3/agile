+{
    fn    => 'can_finish',
    cmp   => 'bool',
    cases => [
        [ 'sample',          [ 2, [ [ 1, 0 ] ] ],                         1 ],
        [ 'two-cycle',       [ 2, [ [ 1, 0 ], [ 0, 1 ] ] ],               0 ],
        [ 'no prerequisites',[ 3, [] ],                                   1 ],
        [ 'diamond',         [ 4, [ [ 1, 0 ], [ 2, 0 ], [ 3, 1 ], [ 3, 2 ] ] ], 1 ],
        [ 'longer cycle',    [ 4, [ [ 1, 0 ], [ 2, 1 ], [ 3, 2 ], [ 1, 3 ] ] ], 0 ],
        [ 'self loop',       [ 1, [ [ 0, 0 ] ] ],                         0 ],
    ],
}
