+{
    stdio => 1,
    cases => [
        [ "sample", "1 2 5\n11\n", "3\n" ],
        [ "impossible", "2\n3\n", "-1\n" ],
        [ "amount 0", "7\n0\n", "0\n" ],
        [ "greedy fails", "1 3 4\n6\n", "2\n" ],
    ],
}
