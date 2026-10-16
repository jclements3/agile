status-metrics (PowerShell): the 26 A-Z status metrics on a PC with only PowerShell, Excel, Edge and Teams
==========================================================================================================

Files (in the ps folder of the kit)
  status-metrics.ps1, status-metrics.cmd   init / collect / report; a port of bin/status-metrics.pl
  ziplib.ps1                               needed beside it (inflate: git objects are zlib streams)
  status-metrics\lint.ps1                  the sample model lint (sim/status-metrics/lint.pl, same output)
  status-metrics\gen_docs.ps1              the sample document generator (sim/status-metrics/gen_docs.pl, same bytes)
  status-metrics\metrics.example.json      a starting config for a Halberd team

Daily use
  status-metrics init    --config metrics.json --xmi legacy.xmi --reqif export.reqif        (once: freezes totals)
  status-metrics collect --config metrics.json --history history.jsonl                      (end of every working day)
  status-metrics report  --config metrics.json --history history.jsonl --out report -Workbook -Html

  report writes status-weekly.md, status-daily.csv and dashboard.json (byte for byte what the Perl and Python kits
  write), and with -Workbook report\status-dashboard.xml (double-click: Excel opens it; sheets Dashboard, A-Z by
  week, Daily; status colours from docs/STATUS-DASHBOARD.html) and with -Html report\status-dashboard.html (open in
  Edge; Ctrl+A, Ctrl+C, paste into a Teams post or an Outlook mail). dashboard.json still loads into
  docs/STATUS-DASHBOARD.html (paste it into the page's JSON box).

No git needed
  collect reads the model repository's .git folder directly: refs, packed-refs, tags, commits, trees, blobs. It
  reads LOOSE objects only. A repository that git has packed (after a clone, or "git gc") must be unpacked once
  where git exists:  mkdir ..\packs; move .git\objects\pack\* ..\packs;  for each .pack:  git unpack-objects < it
  (pgit, the kit's PowerShell git, writes loose objects, so repositories it makes need nothing).

lint_cmd and gen_cmd
  Run in the repository folder. Each is a list: a program or a .ps1 script, then its arguments. {src} and {out}
  in gen_cmd are replaced as in the Perl kit. A .ps1 runs inside PowerShell, so it works under Constrained
  Language Mode. lint_cmd must print "errors=N warnings=M" (both sample lint.ps1 and sysml\model.ps1 lint do).
  gen_cmd must write {out}\docs\* from the model at {src}; S (reproducible baselines) compares their sha256 with
  the "sha256=..." message of each baseline-N tag. Give absolute paths to scripts outside the repository.

Differences from Perl
  -h also lists -Workbook and -Html. Stderr lines are written to the console (Write-Host), not to a separate
  stream. A collect takes about 1.5 minutes on the 12-week Halberd simulation (pure PowerShell inflate and
  sha256); the Perl one takes 3 seconds. Nothing else differs: see the comparison counts in the notes.
