+{
    stdio => 1,
    cases => [
        [ "sample", "2 2\n..\n..\n", "2\n" ],
        [ "walled off", "2 2\n.#\n#.\n", "-1\n" ],
        [ "1x1", "1 1\n.\n", "0\n" ],
        [ "winding path", "3 3\n..#\n#.#\n#..\n", "4\n" ],
    ],
}
