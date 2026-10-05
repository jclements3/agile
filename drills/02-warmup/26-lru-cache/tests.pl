+{
    class => 'LRU',
    cases => [
        [ 'sample', [ [ 'new', 2 ], [ 'put', 'a', 1 ], [ 'put', 'b', 2 ], [ 'get', 'a' ], [ 'put', 'c', 3 ], [ 'get', 'b' ], [ 'get', 'c' ], [ 'get', 'a' ] ],
          [ undef, undef, undef, 1, undef, undef, 3, 1 ] ],
        [ 'update moves to front', [ [ 'new', 2 ], [ 'put', 'a', 1 ], [ 'put', 'b', 2 ], [ 'put', 'a', 99 ], [ 'put', 'c', 3 ], [ 'get', 'a' ], [ 'get', 'b' ] ],
          [ undef, undef, undef, undef, undef, 99, undef ] ],
        [ 'capacity one', [ [ 'new', 1 ], [ 'put', 'x', 1 ], [ 'put', 'y', 2 ], [ 'get', 'x' ], [ 'get', 'y' ] ],
          [ undef, undef, undef, undef, 2 ] ],
        [ 'miss is not a use', [ [ 'new', 2 ], [ 'get', 'z' ], [ 'put', 'a', 1 ], [ 'get', 'a' ] ],
          [ undef, undef, undef, 1 ] ],
    ],
}
