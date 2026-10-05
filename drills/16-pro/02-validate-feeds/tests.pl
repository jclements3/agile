+{
    fn    => 'validate_feeds',
    cases => [
        [ 'sample',       [ [], [1] ],   'empty feed' ],
        [ 'both full',    [ [1], [2] ],  undef ],
        [ 'second empty', [ [1], [] ],   'empty feed' ],
        [ 'both empty',   [ [], [] ],    'empty feed' ],
    ],
}
