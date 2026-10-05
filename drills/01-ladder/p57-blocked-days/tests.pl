+{
    stdio => 1,
    cases => [
        [ 'sample', "2026-10-05 A-1 block\n2026-10-07 A-1 unblock\n2026-10-06 B-2 block\ntoday 2026-10-14\n", "A-1 2\nB-2 8 !\n" ],
        [ 'same-day unblock', "2026-10-05 C-3 block\n2026-10-05 C-3 unblock\ntoday 2026-10-09\n", "C-3 0\n" ],
        [ 'two stretches sum, flag per stretch', "2026-10-01 D-4 block\n2026-10-04 D-4 unblock\n2026-10-05 D-4 block\n2026-10-09 D-4 unblock\ntoday 2026-10-20\n", "D-4 7\n" ],
        [ 'nothing blocked', "today 2026-10-20\n", "" ],
    ],
}
