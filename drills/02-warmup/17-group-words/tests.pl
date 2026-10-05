+{
    fn    => 'group_words',
    cases => [
        [ 'sample',  [ [qw(ant bee ape)] ], { a => [qw(ant ape)], b => ['bee'] } ],
        [ 'one',     [ ['cat'] ],           { c => ['cat'] } ],
        [ 'empty',   [ [] ],                {} ],
        [ 'order kept', [ [qw(zoo yak zip zap)] ], { z => [qw(zoo zip zap)], y => ['yak'] } ],
    ],
}
