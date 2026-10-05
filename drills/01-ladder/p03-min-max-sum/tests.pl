+{
    stdio => 1,
    cases => [
        [ "sample", "5\n7 3 9 1 5\n", "1 9 25\n" ],
        [ "one value", "1\n42\n", "42 42 42\n" ],
        [ "all negative", "3\n-5 -1 -9\n", "-9 -1 -15\n" ],
    ],
}
