#!/usr/bin/env bash
# handup.sh -- rebuild ./handup: a flat, text-only copy of the kit (code, docs, tests, and the notional project data
# under data/demo and data/lab) for upload to a web project's files folder: no subdirectories, no SVG or binary,
# everything UTF-8. Nested names are flattened with "__" for "/" (data__demo__standups__2026-09-01.txt); kit files
# keep their basename unless it would collide. MANIFEST.txt lists "origin -> flatname" for every file; unhandup.sh
# (included) rebuilds the original tree from the manifest; HANDOFF.md carries the state of the work.
#   bash bin/handup.sh            (from anywhere)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT=handup
rm -rf "$OUT" && mkdir "$OUT"
warn() { echo "handup: WARNING: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
WARNINGS=0

# ---- what goes in: kit files by glob (a missing name warns), then every tracked, text file of the notional projects
KIT=(CLAUDE.md agile.pl claude.bat .gitignore .gitattributes
     lib/*.pm bin/*.pl bin/*.tcl bin/*.sh sim/*.pl tests/*.t tests/fake-ps.pl
     docs/*.html docs/*.txt vim/scrum.vim vim/syntax/*.vim vim/ftdetect/scrum.vim .github/workflows/*.yml
     tools/idef0/idef0.pl tools/idef0/README.md tools/idef0/idef0fmt tools/idef0/idef0lint tools/idef0/idef2html tools/idef0/idef2svg tools/idef0/idef2text
     tools/idef0/examples/dronecorp/dronecorp.md tools/idef0/examples/quadfactory/*.txt
     examples/*.txt examples/*.json examples/*.html examples/*.csv)
DATA_PROJECTS=(data/demo data/lab)             # notional data only: nothing real, nothing sensitive
SKIP_DATA_OVER_KB=1024                         # data/history and any other project: reported, not included, unless small

flatname() {                                   # origin path -> upload name
  local f=$1 b; b=$(basename "$f")
  case "$f" in
    data/*)                                    echo "${f//\//__}";;
    vim/ftdetect/scrum.vim)                    echo "ftdetect-scrum.vim";;
    tools/idef0/README.md)                     echo "idef0-README.md";;
    tools/idef0/examples/dronecorp/dronecorp.md) echo "idef0-dronecorp.md";;
    tools/idef0/examples/quadfactory/*)        echo "idef0-quadfactory-${b}";;
    tools/idef0/idef0fmt|tools/idef0/idef0lint|tools/idef0/idef2html|tools/idef0/idef2svg|tools/idef0/idef2text) echo "idef0-${b}.sh";;
    docs/*.txt)                                echo "$b";;
    examples/*)                                echo "example-${b}";;
    .gitignore)                                echo "gitignore.txt";;
    .gitattributes)                            echo "gitattributes.txt";;
    .github/workflows/*)                       echo "workflow-${b}";;
    *)                                         echo "$b";;
  esac
}
is_text() {                                    # text we can carry (after conversion); binaries and SVG are refused
  case "$1" in *.svg|*.png|*.jpg|*.jpeg|*.gif|*.zip|*.pdf|*.exe|*.dll) return 1;; esac
  local t; t=$(file -b "$1")
  case "$t" in *text*|*JSON*|*HTML*|*script*|*empty*|*CSV*) return 0;; *) return 1;; esac
}
copy_utf8() {                                  # copy, converting UTF-16 (BOM) or other single-byte encodings to UTF-8; strip a UTF-8 BOM
  local src=$1 dst=$2 t; t=$(file -b "$src")
  case "$t" in
    *UTF-16*BE*) iconv -f UTF-16BE -t UTF-8 "$src" | sed '1s/^\xEF\xBB\xBF//' > "$dst";;
    *UTF-16*)    iconv -f UTF-16   -t UTF-8 "$src" | sed '1s/^\xEF\xBB\xBF//' > "$dst";;
    *ISO-8859*|*Non-ISO*) iconv -f WINDOWS-1252 -t UTF-8 "$src" > "$dst" || cp "$src" "$dst";;
    *)           sed '1s/^\xEF\xBB\xBF//' "$src" > "$dst";;
  esac
  [ "$t" != "${t/UTF-16/}" ] && echo "handup: converted $src from UTF-16 to UTF-8" >&2
  return 0
}

declare -A SEEN
add() {                                        # add ORIGIN
  local f=$1 n
  [ -f "$f" ] || { warn "missing: $f"; return; }
  is_text "$f" || { warn "skipped (not text): $f ($(file -b "$f" | cut -c1-40))"; return; }
  n=$(flatname "$f")
  if [ -n "${SEEN[$n]:-}" ]; then warn "name collision: $f and ${SEEN[$n]} both map to $n; using path form"; n="${f//\//__}"; fi
  SEEN[$n]=$f
  copy_utf8 "$f" "$OUT/$n"
  printf '%s -> %s\n' "$f" "$n" >> "$OUT/MANIFEST.txt"
}

{ echo "# handup: flat, text-only, UTF-8 copy of the agile kit + notional project data (no subdirectories, no SVG/binary)."
  echo "# generated $(date +%F) from $(git rev-parse --short HEAD 2>/dev/null || echo untracked) on branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ?)"
  echo "# origin path -> upload name.  Rebuild the tree with:  bash unhandup.sh [SRC=/mnt/project] [DEST]"; } > "$OUT/MANIFEST.txt"

shopt -s nullglob
for pat in "${KIT[@]}"; do
  matched=0
  for f in $pat; do matched=1; add "$f"; done
  [ $matched = 1 ] || warn "no file matches: $pat"
done
shopt -u nullglob
for p in "${DATA_PROJECTS[@]}"; do
  if [ ! -d "$p/.git" ]; then warn "$p is not a git repo (data projects are each their own repo); skipped"; continue; fi
  n=$(git -C "$p" ls-files | wc -l); kb=$(( $(git -C "$p" ls-files -z | xargs -0 -I{} stat -c %s "$p/{}" | awk '{s+=$1} END{print s+0}') / 1024 ))
  if [ "$kb" -gt "$SKIP_DATA_OVER_KB" ]; then warn "$p: $n tracked files, ${kb} KB > ${SKIP_DATA_OVER_KB} KB; skipped"; continue; fi
  while IFS= read -r f; do add "$p/$f"; done < <(git -C "$p" ls-files)
  echo "handup: $p: $n tracked files, ${kb} KB" >&2
done
for p in data/*/; do                           # report what was not included
  p=${p%/}; case " ${DATA_PROJECTS[*]} " in *" $p "*) continue;; esac
  echo "handup: not included: $p ($(du -sh "$p" | cut -f1), $(git -C "$p" ls-files 2>/dev/null | wc -l) tracked files)" >&2
done

# ---- unhandup.sh and HANDOFF.md travel with the files
cp bin/unhandup.sh "$OUT/unhandup.sh" && printf '%s -> %s\n' bin/unhandup.sh unhandup.sh >> "$OUT/MANIFEST.txt"
bash bin/handoff.sh > "$OUT/HANDOFF.md" && printf '%s -> %s\n' "(generated by bin/handoff.sh)" HANDOFF.md >> "$OUT/MANIFEST.txt"

n=$(ls "$OUT" | wc -l); sz=$(du -sh "$OUT" | cut -f1)
echo "handup: $n files, $sz, $WARNINGS warning(s)"
echo "largest:"; ls -S -l "$OUT" | awk 'NR>1 && NR<=6 {printf "  %7d  %s\n", $5, $9}'
exit 0
