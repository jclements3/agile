+{
    stdio => 1,
    cases => [
        [ "sample", "4\n1 3\n2 6\n8 10\n15 18\n", "1 6\n8 10\n15 18\n" ],
        [ "touching", "2\n1 2\n2 3\n", "1 3\n" ],
        [ "unsorted", "3\n5 7\n1 2\n3 6\n", "1 2\n3 7\n" ],
        [ "single point", "1\n4 4\n", "4 4\n" ],
    ],
}
