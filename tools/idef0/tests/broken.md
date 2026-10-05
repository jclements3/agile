# Broken-input regression file

Prose with a ```ledger fence that must stay raw:

```ledger
2026-01 P3212  1000
```

## doc before any element
```idef0
## dangling doc comment
tQ Quadco
  a1 Build Frame
    i1 Carbon Sheet < Z|Nowhere|Carbon Sheet
    i2 Frame Kitt
    o1 Frame Kit
    o2 Frame Kit
    o3 Bare Frames
    c1 Spec < QQ|Build Frame|Spec
    m1 Jig
  a1 Duplicate Pin
    o1 Widget < Build Frame|Frame Kit
  a0 Zero Pin
  aB Bad Suffix
  a7. Wrong Assert
     a# Odd Indent
	a# Tab Indent
  a# Needs | Pipe
  a#
  i1 Port > Build Frame|i1
    a# Under Port
  a# Link Via Ambig
    i# Something < Build Frame|Frame Kit
  a# Numbered Target
    i1 Bare Frame
    i2 Via Number < Q1|o3
    c1 Via Role < Build Frame|c1
    c9 Pin Nine
    c22 Bad Pin
    o1. Bad Assert
tQ Quadco Again
  a# Only
    o1 Missing Pair > Quadco|Build Frame|i2
    o2 Empty Seg > Quadco||Spec
    o3 Deep > Quadco|Build Frmae|Carbon Sheet
tr lower
  a# Many
    a#  A1
    a#  A2
    a#  A3
    a#  A4
    a#  A5
    a#  A6
    a#  A7
    a#  A8
    a#  A9
    a#  A10
this line cannot parse
t9 Bad Model Suffix
  a# Stub  ## trailing doc **bold**
    i# Input  # trailing comment
      a# Nested Under Port
```

```idef0
t# Élan Ünïcode — model
  a# Draw “quotes” & <angles>
    ## doc with `code` and [link](http://x.y) and *em* \n second para
    o# Résumé ✓
  a# Consume
    i# Resume ✓
