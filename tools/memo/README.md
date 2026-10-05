# md2memo — Markdown to a military-style memo

`md2memo.pl` turns Markdown into a DoD-style memorandum on US Letter with
1" margins: numbered paragraphs (1. a. (1) (a) ...), uppercase headings,
ruled tables, verbatim code with box drawing, and portion and banner
marking from inline classification tags. Core Perl only (Getopt::Long,
charnames); the PDF writer is pure Perl, no TeX or Office.

    perl tools/memo/md2memo.pl examples/status-report.md > memo.pdf          # PDF, Times 12
    perl tools/memo/md2memo.pl --font courier examples/status-report.md > memo.pdf
    perl tools/memo/md2memo.pl --text  examples/status-report.md > memo.txt  # overstrike underline
    perl tools/memo/md2memo.pl --plain examples/status-report.md > memo.txt  # ASCII only
    perl tools/memo/md2memo.pl --ps    examples/status-report.md > memo.ps

Marking: tag a phrase `{CUI}...{/}`, `{S//NF}...{/}` etc. Each portion is
marked in the left margin with the rollup of its tags, and each page gets
top and bottom banners (`--banner page|doc`, `--default S//NF`, `--mark`).
The full syntax is in the header comment of `md2memo.pl`.

`examples/status-report.md` is a notional monthly status memo (the
program, figures and the CUI-tagged phrases are made up) that exercises
every feature. `tests/memo.t` renders it in all three forms and checks
them against fixed SHA-256 sums, so any change to the output shows up.
Rendered output is not committed: rebuild it from the `.md`.
