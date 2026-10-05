+{
    stdio => 1,
    cases => [
        [ 'sample', "SE-1\nSE-2\nSEC-1\n---\nSE-2\n", "SE-1\nSEC-1\n" ],
        [ 'none left', "A\n---\nA\n", "-\n" ],
        [ 'duplicates print once', "B\nA\nB\n---\nC\n", "B\nA\n" ],
        [ 'empty second list', "A\n\nB\n---\n", "A\nB\n" ],
    ],
}
