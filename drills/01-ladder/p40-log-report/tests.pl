+{
    stdio => 1,
    cases => [
        [ "sample", "2026-09-03T10:00:01 ERROR api: upstream timeout\n2026-09-03T10:00:02 INFO web: ok\ngarbage line\n2026-09-03T10:00:03 ERROR api: db down\n2026-09-03T10:00:04 ERROR web: 500\n2026-09-03T10:00:05 WARN api: slow\n2026-09-03T10:00:06 DEBUG api: nope\n2026-09-03T10:00:07 ERROR db missing colon\n", "api 2\nweb 1\nmalformed 3\n" ],
        [ "nothing but malformed", "t1 INFO web: fine\nhalf a line but still garbage?\n", "malformed 1\n" ],
        [ "ties and an empty message", "t1 ERROR b: x\nt2 ERROR a: y\nt3 ERROR svc:\n", "a 1\nb 1\nsvc 1\nmalformed 0\n" ],
    ],
}
