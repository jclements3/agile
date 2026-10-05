+{
    stdio => 1,
    cases => [
        [ "sample", "abcabcbb\n", "3\n" ],
        [ "one letter", "bbbbb\n", "1\n" ],
        [ "empty line", "\n", "0\n" ],
        [ "abba trap", "abba\n", "2\n" ],
    ],
}
