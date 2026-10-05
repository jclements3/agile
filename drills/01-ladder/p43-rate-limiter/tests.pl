+{
    stdio => 1,
    cases => [
        [ "sample", "10 2\n1 alice\n2 alice\n3 alice\n5 bob\n12 alice\n13 alice\n", "3 alice\n" ],
        [ "within the limit", "5 3\n1 a\n2 a\n3 a\n", "ok\n" ],
        [ "half-open window", "5 1\n1 a\n2 b\n3 a\n7 a\n8 b\n", "3 a\n" ],
    ],
}
