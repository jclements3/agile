# Draft .gitlab-ci.yml: grammar, lint, outline

Part of #4

## Do

- [ ] Draft .gitlab-ci.yml: grammar, lint, outline
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@tom** (2026-10-14T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@tom** (2026-10-14T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@tom** (2026-10-15T15:00:00Z) [system]:
added 0.5d of time spent

**@tom** (2026-10-15T15:00:00Z) [system]:
removed ~"workflow::in-progress" label

**@tom** (2026-10-15T15:00:00Z) [system]:
added ~"workflow::done" label

**@tom** (2026-10-15T15:00:00Z) [system]:
closed

**@tom** (2026-10-15T15:00:00Z):
The draft pipeline (sh syntax, as the tutorials write it):

```yaml
# .gitlab-ci.yml -- first draft (sprint 1): the three checks, written the way the tutorials write them (sh syntax)
stages:
  - check

variables:
  GIT_DEPTH: "0"

grammar:
  stage: check
  script:
    - FILES=$(find model -name '*.sysml' | sort)
    - perl "$KIT/tools/sysml/sysml.pl" check $FILES

lint:
  stage: check
  script:
    - perl "$KIT/tools/sysml/model.pl" lint > lint.txt || true
    - tail -1 lint.txt | grep -q ' errors=0 warnings=0$'

outline:
  stage: check
  script:
    - perl "$KIT/tools/sysml/model.pl" check
```
