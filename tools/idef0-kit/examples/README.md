# examples/ — notation mapping demonstrations

- `usecase-atm.md` — one plate carrying the semantics of the classic
  ATM use case diagram; the «include» relationship rendered as a
  shared control flow.
- `sysml-views.md` — ten models, one per SysML v2 artifact kind
  (package, part definition, interconnection, action flow, state
  transition, sequence, use case, requirement, analysis case,
  verification case), all describing one racing drone; R and V are
  paired by cross-model links.

- `fp-variants.md` — railway-oriented error pipeline using variant
  groups (`o/`): each stage's exclusive output bundle is a visible,
  lintable sum type.

Build:  idef0lint examples/*.md
        idef2html examples/sysml-views.md > sysml-views.html
