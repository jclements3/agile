The MBSE DevSecOps Primer -- source files and markup
====================================================

This directory is the source of the primer. `perl sim/primer.pl` renders it to
docs/mbse-devsecops-primer.html and docs/mbse-devsecops-primer.tex; `--pdf` also
builds docs/mbse-devsecops-primer.pdf (XeLaTeX + latexmk); `--check` validates the
source without writing anything. This README is not part of the book.

FILES
-----
One file per chapter, named NN-slug.txt (NN two digits, an optional letter: 08a,
08b ...). Files are rendered in file-name order ('08-x' comes before '08a-x').
A file named NN-part-*.txt starts a part: its first line is '= Part title'.
Chapters that come before the first part are front matter (unnumbered).
A part whose title starts with "Appendi" (= Appendices) letters its chapters
A, B, C ... instead of numbering them.

Lines starting with @key: value set book data (00-front.txt holds them):
    @title:      the book title
    @subtitle:   the subtitle
    @coverline:  the small-caps line on the cover band (default "A Case Study")
    @author:     the author line on the title page
    @edition:    edition and date (title page; also the PDF's date)
    @copyright:  one paragraph of the copyright/notice page; repeat the key for more paragraphs
    @dedication: one line of the dedication; repeat the key for more lines

HEADINGS
--------
    = Part I: Where they start            a part (first line of a NN-part-*.txt file only)
    == Thirty years of documents {#documents}
                                          a chapter; {#slug} is its anchor (default: ch-<title>)
    === The SEMP {#semp}                  a section (numbered 2.1); {#slug} optional
    ==== Who signed it                    a subsection (numbered 2.1.1)
    == Bottom line up front {#bluf} @before-contents
                                          a front-matter chapter (before the first part) that
                                          must be read first: printed right after the title
                                          pages, before the contents, unnumbered, on a
                                          right-hand page (HTML: after the cover, before the
                                          contents)

PARAGRAPHS AND INLINE MARKUP
----------------------------
Paragraphs are separated by blank lines; the lines of one paragraph are joined.
    *italic*        **bold**        `code` (verbatim, no markup inside)
    [[slug]]        a cross-reference: "Chapter 3, The directive (p. 41)" in the PDF,
                    a link in the HTML; the slug of a chapter, section or exercise
    [[slug|text]]   the same with your own text
    ^[a footnote]   a footnote; markup allowed inside, brackets must balance
    {{value: docs/tidewater/sprints/06/scorecard.json todo.after}}
                    one value from a JSON file (dotted keys; array indexes as numbers)
    {{count: docs/tidewater/sprints/06/todo.txt ^model/}}
                    how many lines of a file match a Perl regular expression
    {{n: 13}}       a number that is a definition, not evidence (13 sprints in a semester)
These three work anywhere inline: in paragraphs, list items, table cells, box
titles, and alone on a line (as a paragraph).

NUMBERS FROM EVIDENCE
In Part III and Part IV (the twelve weeks and the case) every number about the
work should come from the evidence, so it cannot drift from what the simulation
produced. --check warns about a bare number next to a counted thing (TODO lines,
requirements, points, sprints, merge requests, pipelines, issues, tasks, stories,
defects, DRs, elements, diagrams, commits, conflicts, findings, errors, warnings,
hours, minutes, percent):
    docs/src/primer/15-sprint-2.txt:40: "52 TODO lines" is a bare number: cite it with
    {{value: FILE KEY}} or {{count: FILE REGEX}}, or mark a definition with {{n: 52}}
Names such as "Sprint 3" are not counts and are not flagged.
An asterisk inside a word or followed by a space is literal (2*3, a * b); put
file globs and other symbols in `code`.

LISTS
-----
    - a bullet
    - another, with a continuation line
      indented under it
      - a nested bullet (two more spaces)
    1. a numbered item
    2. the next one
A list ends at a blank line.

QUOTED SPEECH
-------------
    > Why can't we just send the Word document like we always have?
    > -- Bob, sprint 1 planning
The last line, if it starts with "-- ", is the attribution. A line with only ">"
separates paragraphs inside one quote.

CODE
----
    ```sh
    git switch -c feature/12-close-stations-todos
    ```
Languages: sysml sh yaml md text perl csv diff json html tex vim (or none).
Tabs are expanded to 8 columns. Nothing inside a code block is interpreted.

RUNNABLE CODE BLOCKS (the primer is tested before anyone is told to follow it)
    ```sh run sandbox=scratch expect="^\[develop [0-9a-f]+\]" exit=0 timeout=120
    git commit -m "Add the stations package"
    ```
    ```vim run sandbox=tidewater
    edit model/stations/Stations.sysml
    //TODO
    ```
A transcript can be tested as shown: ```text run marks a block whose lines starting with
"$ " are the commands (a command ending in a backslash continues on the next line,
which may start with "> "); they run as one sh block and every other line is the
output the reader sees, which is shown, not compared: say what must be true of the
real output with expect=.
    ```text run sandbox=scratch expect="tidewater\.xmi"
    $ ls drop1
    MANIFEST.txt
    tidewater.xmi
    ```
Only sh, vim and text blocks can carry "run". Options (all optional; quote a value with
spaces, \" for a quote inside):
    sandbox=   where the block runs; a block without one uses the previous block's
               sandbox in the same chapter (the chapter's first defaults to scratch):
                 scratch      an empty directory
                 kit          the kit itself, read-only (the test fails if git status changes)
                 practice-N   the sandbox of perl agile.pl practice N
                 tidewater    the simulation's state after 6 sprints (tidewater-N: after N),
                              from perl sim/tidewater-sim.pl --sprints N, cached between runs
               Sandboxes are fresh for each chapter and shared by its blocks, in order, so a
               chapter reads (and is tested) as one session.
    cwd=       the folder in the sandbox the block runs in (default: the sandbox itself); ~/x
               is under the private home, a relative path is under the sandbox; sticky:
               later blocks in the same sandbox use it until another cwd= or sandbox=
               (a cd inside a block does not carry over to the next block)
    expect=    a Perl regular expression the block's output (stdout + stderr) must match
    exit=      the exit status wanted (default 0; sh blocks run with sh -e, so the first
               failing command ends the block with its status)
    timeout=   seconds (default 60, or PRIMER_RUNS_TIMEOUT)
A vim block is Ex commands, run headless: vim -Es -N -u NONE with the kit's vim/
on the runtimepath and filetype plugins on; "qa!" is appended. Every block runs
with KIT set to the kit, HOME set to a private home with a git identity, and the
sandbox as the current directory.
In the book a runnable block looks like any other code block.

QUOTED VALUES keep their backslashes as written: expect="foo\(bar\)" matches the text
"foo(bar)". Only \" is an escape (a quote inside the value).

READER SAFETY: the reader types these blocks into their own shell. Never write a
line that is just `exit` or `exit N` in a runnable block -- a reader typing it
closes their terminal. To show a command failing, keep the shell alive and show
the status:
    ```sh run expect="exit status 1"
    git push origin develop || echo "exit status $?"
    ```
(`sh -c 'exit 3'` is fine: it exits a child shell.) --check flags a bare exit line
in a runnable block.

A HALF-WRITTEN CHAPTER does not stop the others from being tested: primer-runs.t
reports its source errors as one failure for that file and runs every chapter
that parses; --extract-runs prints the errors, extracts the other chapters and
exits 1.

Run them:
    perl tests/primer-runs.t                          every chapter, in order
    PRIMER_RUNS=git perl tests/primer-runs.t          one chapter (its slug; a comma list for several)
    PRIMER_RUNS=self-test perl tests/primer-runs.t    only the runner's own self-test
    PRIMER_RUNS_VERBOSE=1 ...                         print each block's output
    perl sim/primer.pl --extract-runs DIR             DIR/manifest.tsv (chapter, file, line, block, lang,
                                                      sandbox, exit, timeout, expect, script),
                                                      DIR/<chapter>/NN.sh|NN.vim and DIR/<chapter>.sh
A failure is reported as FILE:LINE with the reason and the last lines of output.
A sandbox whose prerequisite is missing (sh, vim, sim/tidewater-sim.pl) is skipped
with the reason.

TABLES
------
    || Measure | Document era | Week 12 ||
    | Requirement change through the CCB | 23 days | 2.1 days |
    | Unverified requirements found | 2 days | 40 s |
    Table: The scorecard, before and after
The header row is fenced with ||, rows with |. Every row has as many cells as
the header (write \| for a literal bar inside a cell). The optional "Table:"
line right after the last row is the caption; captioned tables are numbered
(Table 3.2) and listed in the PDF's list of tables.

BOXES
-----
    ::: KIND Optional title
    ... paragraphs, lists, code, tables (no headings, no nested boxes) ...
    :::
KIND is one of:
    note        a plain note                     tip         a tip
    warning     a heavy-ruled warning            sidebar     a case-study box (grey rule on the left)
    objection   an old-way objection; a paragraph starting "Answer:" starts the answer
    exercise    numbered per chapter (Exercise 3.2); give it an anchor to point at it from the answers:
                ::: exercise {#ex-first-branch} Make your first branch
    answer      an answer (title it "Exercise 3.2" or similar)
    checklist   lines "[ ] item" (or "[x] item" for a ticked box)
    scorecard   the measures box
    definition  lines "term: text" (indented lines continue the text)
    survival    the chapter-opening box; "What you have:" and "What you need:" lines start its two halves
Inside any box, a paragraph that starts with "Answer:", "What you have:", "What you
need:", "Hint:" or "Solution:" gets that word as a small heading.

DIRECTIVES (each on a line of its own)
--------------------------------------
    {{include: examples/tidewater-v1/README.md}}               a file, verbatim, as a code block
    {{include: tools/gitlab/templates/gitlab-ci.yml | lines 10-40}}   a line range
    {{include-md: tools/gitlab/samples/story-issue.md}}         a GitLab Markdown sample, captioned with its path
    {{csv: docs/tidewater/sprints/01/plan.csv | Sprint 1 plan}} a CSV file as a table (first row = header)
    {{figure: docs/img/halberd-tree.svg | The part tree}}      an SVG figure (inlined in HTML; greyed and
                                                                converted with rsvg-convert for the PDF)
    {{pagebreak}}                                               a page break in the PDF (and in print)
Paths are relative to the kit's root and may not contain '..'.

ERRORS
------
Unknown markup, a box never closed, a missing include path, a [[slug]] that
names nothing, a table row with the wrong number of cells: every problem is
listed as FILE:LINE: message and nothing is written. Run --check while writing.
