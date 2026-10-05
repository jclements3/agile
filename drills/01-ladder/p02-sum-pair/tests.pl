+{
    stdio => 1,
    cases => [
        [ "sample", "3 4\n", "7\n" ],
        [ "negatives", "-2 -8\n", "-10\n" ],
        [ "beyond 32 bits", "1000000000 1000000000\n", "2000000000\n" ],
    ],
}
