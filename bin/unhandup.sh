#!/usr/bin/env bash
# unhandup.sh -- rebuild the kit's tree from a flat handup (MANIFEST.txt: "origin -> flatname", one per line).
#   bash unhandup.sh [SRC] [DEST]        SRC defaults to /mnt/project (a claude.ai project's files), DEST to ./agile
# Bash + coreutils only. Makes bin/ and sim/ scripts executable. Data projects (data/demo, data/lab) come back as
# plain directories; run "git init" in them if you want their history to restart. The web project may have renamed
# "/" in upload names to "_": names are looked up as given, then with "/"->"_", then case-insensitively.
set -uo pipefail
SRC=${1:-/mnt/project}
DEST=${2:-./agile}
MAN="$SRC/MANIFEST.txt"
[ -f "$MAN" ] || MAN=$(ls "$SRC"/*MANIFEST* 2>/dev/null | head -1)
[ -f "${MAN:-}" ] || { echo "unhandup: no MANIFEST.txt in $SRC" >&2; exit 1; }
mkdir -p "$DEST"
n=0; missing=0
find_src() {                                   # the uploaded file for a flat name, tolerating the host's renames
  local name=$1 alt
  [ -f "$SRC/$name" ] && { echo "$SRC/$name"; return; }
  alt=${name//\//_}; [ -f "$SRC/$alt" ] && { echo "$SRC/$alt"; return; }
  alt=$(ls "$SRC" | grep -i -x -F "$name" | head -1); [ -n "$alt" ] && { echo "$SRC/$alt"; return; }
  return 1
}
while IFS= read -r line; do
  case "$line" in '#'*|'') continue;; esac
  origin=${line%% -> *}; flat=${line##* -> }
  case "$origin" in '('*) continue;; esac       # generated files (HANDOFF.md) stay at the top level of the handup only
  src=$(find_src "$flat") || { echo "unhandup: missing in $SRC: $flat (for $origin)" >&2; missing=$((missing + 1)); continue; }
  mkdir -p "$DEST/$(dirname "$origin")"
  cp "$src" "$DEST/$origin"
  n=$((n + 1))
done < "$MAN"
chmod +x "$DEST"/bin/*.pl "$DEST"/bin/*.sh "$DEST"/sim/*.pl "$DEST"/agile.pl "$DEST"/tools/idef0/idef0.pl 2>/dev/null
[ -f "$SRC/HANDOFF.md" ] && cp "$SRC/HANDOFF.md" "$DEST/HANDOFF.md"
echo "unhandup: $n files restored into $DEST, $missing missing"
echo "next:  cd $DEST && for t in tests/*.t; do perl \$t | tail -1; done"
[ "$missing" = 0 ]
