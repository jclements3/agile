+{
    stdio => 1,
    cases => [
        [ "sample", "2\nthe cat the dog the cat bird\n", "the 3\ncat 2\n" ],
        [ "all tie", "3\nb a a b c c\n", "a 2\nb 2\nc 2\n" ],
        [ "words over several lines", "2\nthe cat the\ndog the cat\nbird\n", "the 3\ncat 2\n" ],
    ],
}
