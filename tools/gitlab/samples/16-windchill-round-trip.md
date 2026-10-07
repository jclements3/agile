# Windchill requests, round trip

Users ask for DevSecOps work in Windchill. The team plans and does it in GitLab. On a managed network there is no API
between the two, so the bridge is one file in and one file out, run at backlog refinement.

## In: a Windchill export becomes issues

1. In Windchill, run the saved report (or search) of open requests and export it as CSV. The sample is
   `windchill-export.csv` here: Number, Name, Type, State, Created By, Priority, Need Date, Created On, Description.
2. Check that `[windchill]` in `.gitlab/project.conf` names those columns (the defaults match the sample).
3. Look first, then create:

```sh
perl $KIT/bin/gitlab.pl --dry-run windchill intake windchill-export.csv     # the issues it would create
perl $KIT/bin/gitlab.pl windchill intake windchill-export.csv
```

```text
created #41 WC-000123: Nightly model check report for the station leads
created #42 WC-000124: Add the buoy station variant to the part tree
created #43 WC-000125: Export the requirements trace as CSV, for the CCB
skipped WC-000126: state 'Canceled' is not accepted (accept = approved, open, under review)
created #44 WC-000127: Read access to the model for the data center contractor
windchill: 5 rows, 4 created, 1 skipped, 0 drift
```

Each issue is titled `WC-000123: ...`, labelled ~"source::windchill" ~"type::story" and the priority label, due on the
need date, and its description is the request with a link back to Windchill. Refine it like any story: split it,
estimate it, put it in a sprint. Retitle it if you like; keep the number at the front.

Run the same export again next week: known numbers are skipped. When Windchill changed a request since (its state,
priority or title), intake prints it as drift; `--note` records the change on the issue for the team to act on:

```text
drift   #42 WC-000124: state 'Under Review' -> 'Approved'; priority 'Medium' -> 'High'
```

## Out: progress for Windchill

```sh
perl $KIT/bin/gitlab.pl windchill status                          # a table, to read at the review
perl $KIT/bin/gitlab.pl windchill status --csv windchill-status.csv   # the sheet to import or paste into Windchill
```

```text
windchill  issue  state   workflow     milestone  closed      merge_requests  release
WC-000123  #41    closed  done         Sprint 3   2026-11-13  !52 merged      baseline-1
WC-000124  #42    open    in-progress  Sprint 4   -           !57 opened      -
WC-000125  #43    open    ready        -          -           -               -
WC-000127  #44    closed  done         Sprint 3   2026-10-23  -               -
```

A merge request counts for a request when it says `Closes #41` (or Fixes, Resolves, Implements, Related to) or its
branch is `feature/41-...`. The release is the first release whose tag holds the merge. The person who owns the
request in Windchill updates its state from this sheet; the team does not edit Windchill from GitLab.
