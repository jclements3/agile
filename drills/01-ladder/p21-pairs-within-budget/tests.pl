+{
    stdio => 1,
    cases => [
        [ "sample", "5\n3 1 4 2\n", "4\n" ],
        [ "negatives", "-1\n-2 -3 5\n", "1\n" ],
        [ "every pair", "100\n1 2 3\n", "3\n" ],
        [ "no pair", "0\n1 2\n", "0\n" ],
    ],
}
