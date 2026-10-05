#!/bin/sh
# parity.sh -- run python reference and perl port on identical inputs;
# compare stdout, stderr and exit status byte-for-byte. Run from tools/idef0; needs python3.
# Known divergences (the Perl port is ahead of the reference, by design; see README.md):
#   html        -- logo, fit/1:1 zoom and table captions
#   fmt --auto  -- keeps the model letter on t lines
# Those cases are counted as "diverge" and do not fail the run.
PY="python3 ./reference/idef0"; PL="perl ./idef0.pl"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0; div=0
run() {
  $PY "$@" >$T/py.out 2>$T/py.err; pe=$?
  $PL "$@" >$T/pl.out 2>$T/pl.err; le=$?
  if cmp -s $T/py.out $T/pl.out && cmp -s $T/py.err $T/pl.err && [ $pe = $le ]; then
    pass=$((pass+1))
  elif [ $pe = $le ] && cmp -s $T/py.err $T/pl.err && { [ "$1" = html ] || [ "$1 $2" = "fmt --auto" ]; }; then
    div=$((div+1))
  else
    fail=$((fail+1)); echo "FAIL: $* (exit py=$pe pl=$le)"
    diff $T/py.out $T/pl.out | head -8; diff $T/py.err $T/pl.err | head -8
  fi
}
for set in "examples/halberd/halberd.md" "examples/dronecorp/dronecorp.md" "examples/quadfactory/assembly.txt examples/quadfactory/design.txt examples/quadfactory/fabrication.txt examples/quadfactory/shipping.txt examples/quadfactory/test.txt" \
           "tests/broken.md" "tests/plain.txt" "tests/unclosed.md" "tests/clean.md" \
           "tests/clean.md tests/plain.txt" "examples/quadfactory/design.txt" "tests/missing.txt"; do
  for c in lint dump links text html fmt "fmt --number" "fmt --auto"; do run $c $set; done
done
for n in E0 E2 E22 E2222 E22222 P0 P32121 T2222 Q32222 H22212 R222 F0 L32222 S22222 C2222 NOPE; do
  run svg $n examples/dronecorp/dronecorp.md
done
for n in K0 K2 Q0; do run svg $n tests/clean.md; done
for n in A0 T0 S0; do run svg $n examples/quadfactory/*.txt; done
run; run bogus; run svg
echo "parity: $pass passed, $div known divergences, $fail failed"
[ $fail = 0 ]
