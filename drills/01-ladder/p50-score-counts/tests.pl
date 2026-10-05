+{
    stdio => 1,
    cases => [
        [ 'sample', "ID\telement\tdomain\tscore\nSE-1\tBuild\tCI\tpartial\nSE-2\tScan\tSec\tunknown\nSE-3\tDeploy\tCD\tpartial\n",
          "in place: 0\npartial: 2\nmissing: 0\nunknown: 1\ntotal: 3\n" ],
        [ 'header only', "ID\telement\tdomain\tscore\n", "in place: 0\npartial: 0\nmissing: 0\nunknown: 0\ntotal: 0\n" ],
        [ 'a space inside the score', "ID\telement\tdomain\tscore\nSE-1\tA\tB\tin place\nSE-2\tC\tD\tin place\nSE-3\tE\tF\tmissing\n",
          "in place: 2\npartial: 0\nmissing: 1\nunknown: 0\ntotal: 3\n" ],
        [ 'Windows line ends', "ID\telement\tdomain\tscore\r\nSE-1\tA\tB\tmissing\r\n", "in place: 0\npartial: 0\nmissing: 1\nunknown: 0\ntotal: 1\n" ],
    ],
}
