#!/bin/bash
# Golden parity gate: the Rust port must be byte-identical to the Python
# tool on stdout, stderr, and exit code for every command and fixture.
# Run from the idef0-kit root:  tests/golden.sh
set -u
cd "$(dirname "$0")/.."
rustc -O idef0.rs -o idef0-rs || { echo "GOLDEN ABORT: rust build failed"; exit 2; }
PY="python3 ./idef0"
RS="./idef0-rs"
fail=0
check() {
    desc="$1"; shift
    $PY "$@" > /tmp/py.out 2> /tmp/py.err; pyc=$?
    $RS "$@" > /tmp/rs.out 2> /tmp/rs.err; rsc=$?
    ok=1
    diff -q /tmp/py.out /tmp/rs.out > /dev/null || { echo "STDOUT DIFF: $desc"; diff /tmp/py.out /tmp/rs.out | head -6; ok=0; }
    diff -q /tmp/py.err /tmp/rs.err > /dev/null || { echo "STDERR DIFF: $desc"; diff /tmp/py.err /tmp/rs.err | head -6; ok=0; }
    [ "$pyc" = "$rsc" ] || { echo "EXIT DIFF: $desc py=$pyc rs=$rsc"; ok=0; }
    [ $ok = 1 ] && echo "OK  $desc" || fail=1
}
QF="quadfactory/design.txt quadfactory/fabrication.txt quadfactory/assembly.txt quadfactory/test.txt quadfactory/shipping.txt"
for cmd in lint dump links text html; do
    check "$cmd dronecorp.md" $cmd dronecorp/dronecorp.md
    check "$cmd quadfactory" $cmd $QF
done
for f in tests/fixtures/*; do
    check "lint $(basename $f)" lint "$f"
done
check "svg E0" svg E0 dronecorp/dronecorp.md
check "svg P32121" svg P32121 dronecorp/dronecorp.md
check "svg missing" svg ZZZ dronecorp/dronecorp.md
check "fmt normalize md" fmt dronecorp/dronecorp.md
check "fmt --auto md" fmt --auto dronecorp/dronecorp.md
check "fmt --number md" fmt --number dronecorp/dronecorp.md
check "fmt multi quadfactory" fmt --number quadfactory/design.txt quadfactory/fabrication.txt
check "fmt hashtest" fmt tests/fixtures/hashtest.idef0
check "fmt variants (refusal)" fmt tests/fixtures/variants.idef0
check "no args"
check "unknown cmd" bogus
exit $fail
