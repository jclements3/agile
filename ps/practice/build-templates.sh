#!/usr/bin/env bash
# build-templates.sh -- make ps/practice/templates/ from the Perl kit (run on a machine with Perl and git; the gov PC
# only copies the result). practice.ps1 builds each lesson's sandbox from these at set-up, the way lib/Practice.pm builds
# it from the kit's generators, so the templates hold the generators' raw output, not a finished sandbox:
#
#   halberd/    sim/halberd-gen.pl output (it takes no date): scrum.conf, roster.txt and every stand-up and answers file,
#               with their own dates. practice.ps1 shifts them by whole weeks and compiles, as _setup_halberd does.
#   dronecorp/  sim/idef0-backlog.pl's plan (its only date is the first line, written DATE here), the roster, and one
#               sim/rehearsal.pl chat with its answer key (no dates inside). Perl's rehearsal differs run to run (hash
#               order), so any one run is as faithful as another.
#   idef0/      tools/idef0/examples/quadfactory/*.txt plus Practice.pm's seeded design.txt.
#   sysml/      tests/fixtures/xmi2sysml/courier.xmi as legacy.xmi, and Practice.pm's sysml.conf.
#   tw-model/   lesson 10: the model repository's history as c1/ (the first commit's tree), c2/ ... (what each later
#               commit added or changed; cK.deleted lists what it removed) and commits.txt (author|email|subject).
#
#   ps/practice/build-templates.sh [PERL-SANDBOX-DIR]      default ps/work/p/tpl-src (made with perl agile.pl practice N)
set -euo pipefail
PS="$(cd "$(dirname "$0")/.." && pwd)"; KIT="$(dirname "$PS")"; T="$PS/practice/templates"
SRC="${1:-$PS/work/p/tpl-src}"
ANCHOR=2026-10-14                                  # the set-up date of the Perl sandboxes in $SRC
rm -rf "$T"; mkdir -p "$T"/{halberd/standups,dronecorp,idef0/model,sysml,tw-model}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# halberd: the generator's raw output
mkdir -p "$tmp/data"; perl "$KIT/sim/halberd-gen.pl" --dir "$tmp/data/halberd" --no-html >/dev/null
cp "$tmp/data/halberd/scrum.conf" "$tmp/data/halberd/roster.txt" "$T/halberd/"
for f in "$tmp/data/halberd/standups/"*; do b=$(basename "$f"); [[ $b =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(\.txt|-[A-Za-z0-9_]+-answers\.txt)$ ]] && cp "$f" "$T/halberd/standups/"; done

# dronecorp: the plan (date-free but its first line), roster and conf from the Perl sandbox, the chat and its key
M="$KIT/tools/idef0/examples/dronecorp/dronecorp.md"
perl "$KIT/sim/idef0-backlog.pl" "$M" --cap 30 --commit --people 2 --date 2000-01-03 2>/dev/null | sed '1s/^2000-01-03$/DATE/' | grep -v '^Wide character' > "$T/dronecorp/plan.txt"
cp "$SRC/lesson4/roster.txt" "$SRC/lesson4/scrum.conf" "$T/dronecorp/"
cp "$SRC/lesson4/standups/$ANCHOR-chat.txt" "$T/dronecorp/chat.txt"
cp "$SRC/lesson4/.answer-key.txt" "$T/dronecorp/answer-key.txt"

# idef0 and sysml: static
cp "$SRC/lesson6/model/"*.txt "$T/idef0/model/"
cp "$SRC/lesson8/legacy.xmi" "$SRC/lesson8/sysml.conf" "$SRC/lesson8/.gitignore" "$T/sysml/"

# tw-model: lesson 10's history, one folder per commit (c1 = the whole first tree, cK = what commit K added or changed,
# cK.deleted = what it removed), and commits.txt (author|email|subject per commit, oldest first). The Perl set-up's own
# last commit ("practice lesson 10: set-up") is left out: practice.ps1 makes it.
L10="$SRC/lesson10"
git -C "$L10" log --reverse --format='%H|%an|%ae|%s' | grep -v '|practice lesson 10: set-up$' > "$tmp/commits"
k=0; prev=""
while IFS='|' read -r h an ae subj; do
  k=$((k+1)); d="$T/tw-model/c$k"; mkdir -p "$d"
  if [ -z "$prev" ]; then git -C "$L10" archive "$h" | tar -x -C "$d"
  else
    git -C "$L10" diff --name-only --no-renames --diff-filter=AM "$prev" "$h" | while read -r p; do mkdir -p "$d/$(dirname "$p")"; git -C "$L10" show "$h:$p" > "$d/$p"; done
    git -C "$L10" diff --name-only --no-renames --diff-filter=D "$prev" "$h" > "$T/tw-model/c$k.deleted"
    [ -s "$T/tw-model/c$k.deleted" ] || rm -f "$T/tw-model/c$k.deleted"
  fi
  case "$ae" in *@example.invalid) ;; *) an=Tom; ae=tom@example.invalid ;; esac   # never ship a builder's own git identity
  printf '%s|%s|%s\n' "$an" "$ae" "$subj" >> "$T/tw-model/commits.txt"
  prev="$h"
done < "$tmp/commits"
echo "templates in $T: $(find "$T" -type f | wc -l) files, $(du -sh "$T" | cut -f1)"
