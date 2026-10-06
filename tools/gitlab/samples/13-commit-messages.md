<!-- Commit messages from Sprints 1 to 6, as `git log` shows them. Subject in the imperative, under 72 characters; a
     blank line; the why; trailers last. GitLab links "#19" and "!19"; the CHANGELOG is built from "Changelog:". -->

```text
Replace the Stations level-tag TODOs with @L tags

The converter reports v1 profile stereotypes as TODO lines. Each one
becomes the metadata tag defined in model/gov/Conventions.sysml, in
place, so the next drop's three-way merge keeps it.

Changelog: changed
Issue: #19
```

```text
Write state def BuoyModes from the v1 state machine

The converter does not carry state machines. Written from drop v1.0
(xmi:id kept in a comment) after the prime's modeler confirmed the XMI,
not the diagram, is current.

Changelog: added
Issue: #20
Reviewed-by: Jim <jim@example.invalid>
```

```text
Import prime drop v1.0 (MANIFEST sha256 4f1c…9a7e)

CDRL A003, delivered 2026-10-02. Converted with xmi2sysml.pl and
reqif2sysml.pl; raw files under imports/v1.0/. No hand edits on this
branch.

Issue: #5
```

```text
Merge branch 'feature/19-stations-level-tags' into 'develop'

Replace the Stations level-tag TODOs with @L tags

Closes #19

See merge request tidewater/model!19
```

```text
Fix the missing @L6Component tag on Cell

!31 resolved a merge conflict by taking the prime's text and did not
re-apply the government edit.

Changelog: fixed
Fixes: #34
```
