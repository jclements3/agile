+{
    fn    => 'dijkstra',
    cases => [
        [ 'sample', [ { a => [ [ 'b', 4 ], [ 'c', 1 ] ], c => [ [ 'b', 2 ] ], b => [] }, 'a' ], { a => 0, b => 3, c => 1 } ],
        [ 'unreachable left out', [ { a => [ [ 'b', 1 ] ], b => [], z => [ [ 'a', 1 ] ] }, 'a' ], { a => 0, b => 1 } ],
        [ 'lone source', [ {}, 's' ], { s => 0 } ],
        [ 'longer path is shorter', [ { 1 => [ [ 2, 10 ], [ 3, 1 ] ], 3 => [ [ 4, 1 ] ], 4 => [ [ 2, 1 ] ] }, 1 ], { 1 => 0, 2 => 3, 3 => 1, 4 => 2 } ],
        [ 'zero weights and a cycle', [ { a => [ [ 'b', 0 ] ], b => [ [ 'a', 0 ], [ 'c', 5 ] ] }, 'a' ], { a => 0, b => 0, c => 5 } ],
    ],
}
