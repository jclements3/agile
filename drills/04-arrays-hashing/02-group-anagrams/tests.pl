+{
    fn    => 'group_anagrams',
    cmp   => 'nested',
    cases => [
        [ 'sample',        [ [qw(ten net cat act dog)] ],               [ [qw(ten net)], [qw(cat act)], ['dog'] ] ],
        [ 'empty string',  [ [''] ],                                    [ [''] ] ],
        [ 'no words',      [ [] ],                                      [] ],
        [ 'one group',     [ [qw(abc bca cab)] ],                       [ [qw(abc bca cab)] ] ],
        [ 'lesson set',    [ [qw(eat tea tan ate nat bat)] ],           [ [qw(ate eat tea)], ['bat'], [qw(nat tan)] ] ],
        [ 'letter counts', [ [qw(aab abb ab)] ],                        [ ['aab'], ['abb'], ['ab'] ] ],
    ],
}
