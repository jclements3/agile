+{
    stdio => 1,
    cases => [
        [ "sample", "5 1 3\n2 4 0\n", "YES\n1 3 5\n0 2 4\n" ],
        [ "equal heights fail", "1 2 3\n1 2 3\n", "NO\n" ],
        [ "already sorted", "10 9\n1 2\n", "YES\n9 10\n1 2\n" ],
        [ "one each, too short", "2\n3\n", "NO\n" ],
    ],
}
