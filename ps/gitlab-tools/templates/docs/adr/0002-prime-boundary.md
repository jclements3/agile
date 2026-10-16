# 2. The prime's model enters only through the vendor branch

Date: (the day you merge this)

## Status

Accepted

## Context

The prime keeps the authoritative SysML v1 model and the DOORS requirements, and delivers them as drops. The
government ports each drop to SysML v2 text and then edits it: it closes the converter's TODO lines, adds its own
conventions and untangles clutter. The next drop must not overwrite that work, and the government must not quietly
change what the prime delivered.

## Decision

- Each drop is converted by the kit's converters and committed, untouched, on the branch `vendor/prime`
  (`gitlab.pl flow vendor DROPDIR VERSION`). Nobody edits that branch by hand. Only the configuration manager can
  push to it.
- `vendor/prime` is merged into a feature branch, and from there into `develop`, through a merge request a person
  reviews. Git's three-way merge keeps the government's edits and takes the prime's changes. Conflicts show exactly
  where both sides changed the same lines.
- The raw drop is kept as delivered in `imports/<version>/` and in the package registry.
- Problems in the prime's content go back as discrepancy reports. The government does not fix them in the prime's
  lines, except to close a converter TODO line.

## Consequences

- Every change in the government model can be traced to either a drop or a government merge request.
- Merges stay clean only while the prime's ids and package names are stable, so the exchange agreement asks for that.
- The converter's output layout is fixed: the same v1 package always lands at the same path. Changing the layout
  later means re-importing every drop on the vendor branch.
