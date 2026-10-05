+{
    stdio => 1,
    cases => [
        [ "sample", "0.5 2.0\n2\nA0 10.0 90.0\nA1 20.0 180.0\n2\nB0 10.2 91.0\nB1 20.1 179.5\n", "A0 B0\nA1 B1\nunpaired A: -\nunpaired B: -\n" ],
        [ "bearing wraps", "0.5 2.0\n1\nA0 10.0 359.5\n1\nB0 10.1 0.3\n", "A0 B0\nunpaired A: -\nunpaired B: -\n" ],
        [ "no pairing", "0.5 2.0\n2\nA0 0.0 10.0\nA1 1.0 20.0\n2\nB0 900.0 200.0\nB1 950.0 300.0\n", "NO PAIRING\n" ],
        [ "uneven feeds", "1.0 2.0\n2\nA0 10.0 45.0\nA1 30.0 90.0\n3\nB0 10.5 44.5\nB1 10.6 46.0\nB2 50.0 200.0\n", "A0 B0\nunpaired A: A1\nunpaired B: B1 B2\n" ],
    ],
}
