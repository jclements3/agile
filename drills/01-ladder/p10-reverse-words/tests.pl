+{
    stdio => 1,
    cases => [
        [ "sample", "the quick brown fox\n", "fox brown quick the\n" ],
        [ "leading and trailing blanks", "  hello   world  \n", "world hello\n" ],
        [ "one word", "solo\n", "solo\n" ],
    ],
}
