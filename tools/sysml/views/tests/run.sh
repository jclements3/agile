#!/bin/bash
# tests/run.sh : run the views tools, v1v2.pl and doors2v2.pl (in tools/sysml/) on the fixtures and compare with the golden transcript.
#   bash tests/run.sh          compare (exit 1 on any difference)
#   bash tests/run.sh --bless  rewrite the golden transcript after a reviewed change
cd "$(dirname "$0")/.." || exit 2
T=$(mktemp -d)
TOOLS=$PWD
F=tests/fixtures
norm() { sed -e "s#$T#OUT#g" -e "s#$TOOLS#TOOLS#g"; }
run() { echo "\$ $*" | norm; "$@" 2>&1 | norm; echo "[exit ${PIPESTATUS[0]}]"; }
dump() { for f in $(cd "$1" && find . -type f | LC_ALL=C sort); do echo "--- $f"; show "$1/$f"; done; }
show() { norm < "$1"; }
{
run perl ../v1v2.pl inventory $F/halberd.xmi
run perl ../v1v2.pl inventory $F/halberd.xmi --tsv
run perl ../v1v2.pl check $F/halberd.xmi
run perl ../v1v2.pl check $F/halberd.xmi --typemap $F/types.tsv
run perl ../v1v2.pl convert $F/halberd.xmi -o $T/full --prefix Halberd --marking U
dump $T/full
run perl ../v1v2.pl convert $F/halberd.xmi -o $T/slice --package 'Interceptor Structure' --prefix Halberd --no-provenance --typemap $F/types.tsv
dump $T/slice
run perl ../v1v2.pl convert $F/halberd.xmi -o $T/keep --keep-names --no-provenance
dump $T/keep
run perl ../v1v2.pl convert $F/halberd.xmi -o $T/bad --package 'No Such Package'
run perl ../v1v2.pl reqs $F/reqs.csv -o $T/reqs-csv.sysml --package HalberdSystemRequirements --marking U
show $T/reqs-csv.sysml
run perl ../v1v2.pl reqs $F/reqs.reqif -o $T/reqs-reqif.sysml --package HalberdFireControlRequirements
show $T/reqs-reqif.sysml
run perl sysml-trace-svg.pl -o $T/trace.svg --title 'Halberd interceptor trace' $F/trace
show $T/trace.svg
run perl sysml-trace-svg.pl -o $T/gaps.svg --gaps $F/trace $T/full/model
show $T/gaps.svg
run perl sysml-trace-svg.pl -o $T/match.svg --match 'HAL-INT-00[12]' $F/trace
show $T/match.svg
run perl sysml-trace-svg.pl -o $T/none.svg no/such/dir
run perl sysml-tree-svg.pl -o $T/tree.svg --title 'Halberd structure' $F/tree
show $T/tree.svg
run perl sysml-tree-svg.pl -o $T/tree-f.svg --root HalberdSystemDef --features --outline $F/tree
show $T/tree-f.svg
run perl sysml-tree-svg.pl -o $T/tree-c.svg --all --depth 2 $T/full/model
show $T/tree-c.svg
run perl sysml-tree-svg.pl -o $T/tree-x.svg --root NoSuchDef $F/tree
run perl sysml-trace-svg.pl -o $T/trace-d.svg --compare $F/trace $F/trace-v2
show $T/trace-d.svg
run perl sysml-trace-svg.pl -o $T/trace-dc.svg --changed --compare $F/trace $F/trace-v2
show $T/trace-dc.svg
run perl sysml-trace-svg.pl -o $T/trace-bad.svg --changed $F/trace
run perl sysml-tree-svg.pl -o $T/tree-d.svg --root HalberdSystemDef --compare $F/tree $F/tree-v2
show $T/tree-d.svg
run perl sysml-tree-svg.pl -o $T/tree-dc.svg --changed --compare $F/tree $F/tree-v2
show $T/tree-dc.svg
run perl sysml-diff.pl --today 2026-10-03 -o $T/dirs --changed --root HalberdSystemDef $F/tree $F/tree-v2
show $T/dirs-changes.txt
run perl sysml-pkg-svg.pl -o $T/pkg.svg --title 'Halberd packages' $F/pkg
show $T/pkg.svg
run perl sysml-pkg-svg.pl -o $T/pkg-n.svg --nested --hide SecMeta $F/pkg
show $T/pkg-n.svg
run perl sysml-pkg-svg.pl -o $T/pkg-clean.svg $F/pkg/SecMeta.sysml $F/pkg/HalberdInterfaces.sysml $F/pkg/HalberdSeekerPerformance.sysml
run perl sysml-pkg-svg.pl -o $T/pkg-lv.svg --levels U,CUI $F/pkg
run perl sysml-ibd-svg.pl -o $T/ibd.svg --title 'Halberd interconnection' $F/ibd
show $T/ibd.svg
run perl sysml-ibd-svg.pl -o $T/ibd-r.svg --root FlightTestConfiguration $F/ibd
run perl sysml-ibd-svg.pl -o $T/ibd-none.svg $F/tree
run perl sysml-ibd-svg.pl -o $T/ibd-x.svg --root NoSuchDef $F/ibd
run perl sysml-threats.pl --today 2026-10-03 $F/threats
run perl sysml-threats.pl --today 2027-06-01 $F/threats
run perl sysml-threats.pl --today 2026-10-03 $F/ibd
run perl sysml-threats.pl --today tomorrow $F/threats
run perl sysml-check.pl --tools binder --today 2026-10-03 $F/clean
run perl sysml-check.pl --tools binder --today 2026-10-03 --strict $F/clean
run perl sysml-check.pl --tools binder --today 2026-10-03 $F/threats
run perl sysml-check.pl --tools no/such/dir --only text,markings $F/clean
run perl sysml-check.pl --only bogus $F/clean
run perl sysml-diff.pl --today 2026-10-03 -o $T/sec $F/clean $F/threats
show $T/sec-changes.txt
run perl sysml-diff.pl --today 2026-10-03 -o $T/sec2 $F/threats $F/clean
show $T/sec2-changes.txt
run perl sysml-plates.pl -o $T/plates --source test --date 2026-10-03 --rev B --owner 'Halberd Program' $F/plates
for f in $T/plates/*.svg; do echo "--- $(basename $f)"; show $f; done
run perl sysml-plates.pl -o $T/plates-auto --source test --date 2026-10-03 --size A3 --color $F/tree
run perl sysml-plates.pl -o $T/plates-x --size B5 $F/plates
run perl ../doors2v2.pl -o $T/doors --prefix Halberd --tests STP --keep Priority --marking U $F/doors/SRS.csv $F/doors/STP.csv $F/doors/SYS.txt $F/doors/dng.reqif
dump $T/doors
run perl ../doors2v2.pl -o $T/doors2 --prefix Halberd --tests STP --design SDD --no-provenance $F/doors/SRS.csv $F/doors/STP.csv $F/doors/SDD.csv
dump $T/doors2
run perl ../doors2v2.pl -o $T/doors3 --map text=Bar $F/doors/SDD.csv
run perl ../doors2v2.pl -o $T/doors4 $F/doors/missing.csv
# git mode: a throwaway repository with two commits and a working-tree edit
R=$T/repo; mkdir -p $R/model
cp $F/trace/*.sysml $F/tree/*.sysml $R/model/
( cd $R && git init -q && git config core.autocrlf false && git -c user.email=t@t -c user.name=t add . && git -c user.email=t@t -c user.name=t commit -qm v1 && git tag baseline-1 )
cp $F/trace-v2/*.sysml $F/tree-v2/*.sysml $R/model/
( cd $R && git -c user.email=t@t -c user.name=t commit -qam v2 )
sed -i 's/part def DivertSystem;/part def DivertSystem { part thruster : Thruster[4]; } part def Thruster;/' $R/model/HalberdSystem.sysml
cd $R
run perl $TOOLS/sysml-diff.pl --today 2026-10-03 -o $T/g1 --changed --root HalberdSystemDef --git baseline-1..HEAD model
show $T/g1-changes.txt
run perl $TOOLS/sysml-diff.pl --today 2026-10-03 -o $T/g2 --changed --git HEAD model
show $T/g2-changes.txt
run perl $TOOLS/sysml-diff.pl -o $T/g3 --git no-such-rev model
cd $TOOLS
} > $T/transcript.txt
if [ "$1" = --bless ]; then cp $T/transcript.txt tests/golden.txt; echo "blessed: tests/golden.txt"; rm -rf "$T"; exit 0; fi
diff -u tests/golden.txt $T/transcript.txt
rc=$?
rm -rf "$T"
if [ $rc -eq 0 ]; then echo "tests: golden transcript matches"; else echo "tests: DIFFERENCES (see above)"; fi
exit $rc
