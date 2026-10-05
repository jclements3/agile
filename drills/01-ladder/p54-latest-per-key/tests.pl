+{
    stdio => 1,
    cases => [
        [ 'sample', "2026-10-07 SE-1 partial\n2026-10-05 SE-1 unknown\n2026-10-06 SE-2 missing\n", "2026-10-07 SE-1 partial\n2026-10-06 SE-2 missing\n" ],
        [ 'equal dates: later line wins', "2026-10-05 X a\n2026-10-05 X b\n", "2026-10-05 X b\n" ],
        [ 'sorted by id', "2026-01-01 B x\n2026-01-01 A y\n", "2026-01-01 A y\n2026-01-01 B x\n" ],
        [ 'older line later in the input', "2026-05-05 K new\n2026-04-04 K old\n", "2026-05-05 K new\n" ],
    ],
}
