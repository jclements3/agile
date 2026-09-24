# agile

A plain-text scrum kit for a solutions architect running several teams' daily townhall in one
Microsoft Teams chat. Everything (backlog, sprints, stand-up notes, estimates, attendance) lives
in a ledger-style text journal edited in Vim; every report, mail and the cockpit dashboard is
derived from it.

**Requirements:** Git for Windows (its Perl, Vim and Bash are all that is needed; nothing to
install, no CPAN, no network). Provisions for Teams (chat paste parsing, 1:1 read-backs) and
classic Outlook (calendar via COM) are optional.

**Start here:** the documentation is HTML, written for a Windows / Office desktop.

- `docs/README.html` — commands and the daily workflow
- `docs/WORKFLOW.html` — the operating model: hierarchy of work, the two-week cadence, metrics
- `docs/TUTORIAL.html` and `docs/TRAINING.html` — hands-on Vim tutorial and a recorded one-sprint replay
- `docs/PILOT.html` — how to roll it out, from a lab project to ten teams
- `docs/SECURITY.html` — what the kit protects and where the gates are

```
perl agile.pl                         # build ./dashboard.html for the demo project (data/demo)
perl sim/training.pl --fast           # rebuild the demo from the DroneCorp IDEF0 model
for t in tests/*.t; do perl $t | tail -1; done
```

Project data lives in `data/<project>/`, each its own git repo, and is never committed here.

MIT licence.
