+{
    stdio => 1,
    cases => [
        [ 'sample', "models/a.sysml:41: error: x\nmodels/b.sysml:12: error: y\nmodels/a.sysml:88: warning: z\nchecked 3 files\n",
          "2 file(s): 2 error(s), 1 warning(s)\n", { exit => 1 } ],
        [ 'nothing to report', "nothing to report\n", "0 file(s): 0 error(s), 0 warning(s)\n", { exit => 0 } ],
        [ 'warnings only exit 0', "x.pl:3: warning: unused\nx.pl:9: warning: shadow\n", "1 file(s): 0 error(s), 2 warning(s)\n", { exit => 0 } ],
        [ 'a colon inside the message', "m.txt:2: error: expected a: b\n", "1 file(s): 1 error(s), 0 warning(s)\n", { exit => 1 } ],
    ],
}
