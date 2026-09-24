#!/usr/bin/env bash
# handup-publish.sh -- regenerate ./handup and publish it as the orphan branch "handup" of this repo: the flat
# files (MANIFEST.txt, unhandup.sh, HANDOFF.md and everything they list) at the branch root, nothing else, no
# history worth keeping (the branch is force-replaced each time). One command, idempotent:
#   bash bin/handup-publish.sh
# The notional demo/lab data lives only on that branch; master never gets data/. Phone-side changes come back
# as patch files or replaced files: apply them on master (git apply / review), run the tests, then run this again.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BRANCH=handup
REMOTE=${REMOTE:-origin}
[ -d .git ] || { echo "handup-publish: not a git repository" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then echo "handup-publish: WARNING: working tree not clean; HANDOFF.md will say so" >&2; fi

bash bin/handup.sh 2> >(grep -v '^handup: converted\|^handup: data/' >&2)
src_head=$(git rev-parse --short HEAD)

WT=$(mktemp -d "${TMPDIR:-/tmp}/handup-wt.XXXXXX")
git worktree prune
git worktree add --detach "$WT" HEAD > /dev/null 2>&1
(
  cd "$WT"
  git checkout -q --orphan "$BRANCH"
  git rm -rfq . > /dev/null 2>&1 || true
  cp "$ROOT"/handup/* .
  printf '# handup branch\n\nFlat, text-only copy of the agile kit at %s for upload to a web project (no subdirectories, no SVG/binary).\n\nRebuild the tree: `bash unhandup.sh SRC DEST`. State of the work: `HANDOFF.md`. File map: `MANIFEST.txt`.\n\nThis branch is force-replaced by `bin/handup-publish.sh`; do not commit to it by hand.\n' "$src_head" > README.md
  git add -A
  git -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo handup@local)}" -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo handup)}" \
      commit -q -m "handup of $src_head ($(date +%F))" --allow-empty
  git push -q --force "$REMOTE" "$BRANCH:$BRANCH"
)
git worktree remove --force "$WT"
git branch -D "$BRANCH" > /dev/null 2>&1 || true            # the local ref is not needed; the remote branch is the artefact
url=$(git remote get-url "$REMOTE" | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')
echo "handup-publish: pushed $BRANCH (from $src_head): $url/tree/$BRANCH"
