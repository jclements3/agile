# idef0-perl — Perl 5 port of idef0-kit

`idef0.pl` is a drop-in Perl 5 replacement for the Python `idef0` tool.
Core modules only (Encode, List::Util, Scalar::Util). Output is
byte-identical to the Python reference: diagnostics, lint summary,
links table, dump, text/SVG/HTML plates, and fmt.

## Layout

    idef0.pl        core tool: lint | dump | links | text | html | svg | fmt
    idef0lint idef2text idef2html idef2svg idef0fmt
                    sh wrappers -> perl idef0.pl <cmd>
    idef0-mode.el   Emacs mode; set idef0-program to .../idef0.pl
    examples/dronecorp/    10-model literate source (dronecorp.md)
      out/                 plates.html, plates.txt, INTERFACES, plate-P32121.svg
    examples/quadfactory/  5-model plain-text sample (*.txt)
      out/                 plates.html, plates.txt, INTERFACES, plate-A0.svg
      out/                 plates.html, plates.txt, INTERFACES, plate-T223.svg
    tests/          parity.sh, fuzz.py, broken.md (regression), clean.md,
                    plain.txt, unclosed.md
    reference/idef0 Python original, used only by the parity tests

## Use

    ./idef0lint examples/dronecorp/dronecorp.md
    # 1 file(s): 0 error(s), 0 warning(s), 10 model(s), 264 activities, 52 link(s)
    ./idef2html examples/dronecorp/dronecorp.md > plates.html
    ./idef2svg  E22 examples/dronecorp/dronecorp.md > plate-E22.svg
    ./idef0fmt --number --write model.md

Keep rendered output out of source directories: `*.txt` globs will
pick up a `plates.txt` and lint it as model source.

## Tests (need python3 for the reference)

    tests/parity.sh        # 105 cases: every command x every input, stdout+stderr+exit
    python3 tests/fuzz.py 250   # random mutants of dronecorp.md vs reference

## Known inherited bug

`fmt --auto` writes `t#` on model lines, dropping the model letter;
letters then re-derive from names (Contracting and Customer Support
both become C) and dronecorp.md no longer lints. Both implementations
do this; the README of idef0-kit says `t` should keep its letter.
