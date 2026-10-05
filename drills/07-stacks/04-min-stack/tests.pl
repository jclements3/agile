+{
    class => 'MinStack',
    cases => [
        [ 'sample',         [ ['new'], [ 'push', 3 ], [ 'push', 1 ], ['get_min'], ['pop'], ['get_min'], ['top'] ], [ undef, undef, undef, 1, 1, 3, 3 ] ],
        [ 'equal minimums', [ ['new'], [ 'push', 2 ], [ 'push', 2 ], ['pop'], ['get_min'] ],                    [ undef, undef, undef, 2, 2 ] ],
        [ 'negatives',      [ ['new'], [ 'push', -2 ], [ 'push', 0 ], [ 'push', -3 ], ['get_min'], ['pop'], ['top'], ['get_min'] ], [ undef, undef, undef, undef, -3, -3, 0, -2 ] ],
        [ 'rising',         [ ['new'], [ 'push', 1 ], [ 'push', 5 ], ['get_min'], ['top'] ],                    [ undef, undef, undef, 1, 5 ] ],
    ],
}
