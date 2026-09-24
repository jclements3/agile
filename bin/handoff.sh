#!/usr/bin/env bash
# handoff.sh -- print HANDOFF.md: the state of the work for another Claude (or person) picking the kit up from a
# flat handup. Git facts are computed here; the narrative sections are maintained in this file -- update them when
# the work moves on. Used by handup.sh; run alone to read it: bash bin/handoff.sh
cd "$(dirname "$0")/.."
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'); head=$(git rev-parse --short HEAD 2>/dev/null || echo '?')
headmsg=$(git log -1 --format=%s 2>/dev/null); when=$(git log -1 --format=%cd --date=short 2>/dev/null)
dirty=$(git status --porcelain 2>/dev/null)
tests=$(ls tests/*.t 2>/dev/null | wc -l)
cat <<EOF
# HANDOFF -- the agile kit, $(date +%F)

## Where the repo is
- Branch \`$branch\`, HEAD \`$head\` ($when): $headmsg
- Remote: the GitHub remote (origin). Tags: $(git tag 2>/dev/null | tr '\n' ' ')
- Uncommitted changes at hand-up: $(if [ -z "$dirty" ]; then echo "none (clean tree)"; else echo; echo '```'; git status --short; echo '```'; echo "  Summary of the diff:"; git diff --stat | tail -1; fi)

## What this is
A plain-text scrum kit for a solutions architect running ~10 teams' daily townhall in one Teams chat. Everything is a
ledger-cli-style journal (\`scrum.txt\`); stand-up verb files compile into it; every report, the cockpit and the mails
are derived from it. Core Perl 5 only (Git for Windows' Perl 5.42 is the target), Vim as the editor, Tcl/Tk console
optional. Read \`CLAUDE.md\` first, then \`docs/README.html\`, \`docs/WORKFLOW.html\`, \`docs/TUTORIAL.html\`.
\`lib/Prelude.pm\` is the FP toolkit every module is built from -- read its header before writing code.

## Working on now / next
- Pilot preparation (docs/PILOT.html): Phase 1 needs a real project directory with real names in roster.txt and the
  marking_* fields in scrum.conf (optional); nothing in the kit blocks it.
- The one untested layer is Outlook COM (lib/Calendar.pm): docs/TEST-PLAN.html is the manual session; \`daily.pl invite --dry\`
  works, the real create is one command at the keyboard.
- A real Teams chat paste has never been observed: the parsers' model of "Edited", quoted replies and @mentions is a guess
  (sim/fuzz-chat.pl). One real sample would settle it; the parser lives in lib/Chat.pm (parse_chat) and lib/Answers.pm (_fields).
- Open decisions for the owner (see docs/PILOT.html): same-plan thresholds, readback_clean_days, the training replay's RED sprint.

## Known bugs / open issues
- The owner's ~/.vimrc line 1 (\`Plug ...\` without plug#begin) errors on every Vim start; launch demos with \`vim -N -u NONE -c "source vim/scrum.vim"\`.
- perlcritic is not available on the target; static analysis is perl -c + strict/warnings + the suites (the one DevSecOps gap).
- Teams' Ctrl-A copy of a very long meeting chat may be truncated by list virtualisation: untested; the mitigation (paste in
  chunks into the same -chat.txt) already works.

## How to run the tests
    cd agile && for t in tests/*.t; do perl \$t | tail -1; done
Expected: $tests suites, each ending "# all N passed" (1,054 tests at hand-up). One suite verbose: \`perl tests/answers.t\`.
On Windows with Git for Windows, also: \`GP="/c/Program Files/Git/usr/bin/perl.exe"; for t in tests/*.t; do "\$GP" \$t | tail -1; done\`.
The gates in one go: \`perl bin/devsecops.pl --quick\` (writes devsecops.html).

## Runtime dependencies
- Perl 5.10+ core only: no CPAN, no XS. Modules used are all core (JSON::PP, File::Temp, IPC::Open3, Digest::SHA, Getopt::Long, POSIX, ...).
  Developed on Perl 5.34 (Linux) and 5.42 (Git for Windows, cygwin build) -- both must stay green.
- git (any recent), for daily.pl commit/init and release.pl.
- Optional: Tcl/Tk 8.6 (\`wish\`, shipped with Git for Windows) for bin/townhall.tcl; Vim 8+ with +clipboard for vim/scrum.vim;
  PowerShell + classic Outlook for lib/Calendar.pm (the mock backend needs neither); curl for the optional AI endpoint;
  pdftotext/docx2txt/antiword/odt2txt (Git for Windows) for bin/docs2txt.pl.
- Nothing needs network access at build, test or run time.

## Do not
- Do not run \`sim/training.pl\`: it wipes and rebuilds \`data/demo\` (guarded to that directory name, but still).
- Do not commit anything under \`data/\` into the kit repo: it is git-ignored on purpose (project data may be confidential). Each
  project directory is its own git repo. The handup carries only the notional demo and lab data.
- Do not \`--send\` mail or create real calendar items unless the owner asked; \`--dry\` first.   recipients outside mail_domains; do not bypass it with \`--force\`.
- Do not rewrite journal history: corrections are new postings (\`est\`, \`carry\`, \`commit\`), never edits of old lines.
- Do not put non-ASCII characters in Perl heredocs that generate HTML/JS (they get double-encoded); use entities or \\u escapes.
  Keep .tcl sources ASCII (wish reads them in the system code page).

## Layout after unhandup
bin/ lib/ tests/ docs/ sim/ vim/ tools/idef0/ examples/ .github/workflows/ data/demo data/lab (+ agile.pl, CLAUDE.md).
Not included: assets/logo.svg (SVG; Scrum::logo_svg() degrades to no logo), release/, data/history (2.4 MB, untracked).
EOF
