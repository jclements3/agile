+{
    stdio => 1,
    cases => [
        [ 'sample', "ID\telement\tdomain\tscore\tkind\tref\nSE-1\tBuild\tCI\tin place\t2\tgit-log\nSE-2\tScan\tSec\tin place\t6\tnotes\nSE-3\tDeploy\tCD\tdone\t1\tx\n",
          "SE-2: in place needs kind 1-4\nSE-3: bad score\n2 problem(s)\n" ],
        [ 'one valid partial row', "ID\telement\tdomain\tscore\tkind\tref\nSE-1\tBuild\tCI\tpartial\t\t\n", "OK\n" ],
        [ 'two rules on one row', "ID\telement\tdomain\tscore\tkind\tref\nSE-9\tx\ty\tin place\t5\t\n",
          "SE-9: in place needs kind 1-4\nSE-9: in place needs a ref\n2 problem(s)\n" ],
        [ 'empty kind is not 1-4', "ID\telement\tdomain\tscore\tkind\tref\nSE-4\tx\ty\tin place\t\tdoc\n", "SE-4: in place needs kind 1-4\n1 problem(s)\n" ],
        [ 'header only', "ID\telement\tdomain\tscore\tkind\tref\n", "OK\n" ],
    ],
}
