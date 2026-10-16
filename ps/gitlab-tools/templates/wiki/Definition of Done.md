# Definition of Done

"Done" means the same thing for everyone, and someone other than the author can check it. Think of it as the closure
criteria of an action item, written once for every item of that kind.

## A task is done when

- [ ] **Its merge request is merged into `develop`**, the master copy. (The MR description says `Closes #task`, so the
      task closes by itself.)
- [ ] **The pipeline passed.** These are the automated audit checks, each in plain words:

  | Check | What it means |
  |---|---|
  | `grammar` | every model file is valid SysML v2 text |
  | `lint` **0/0** | every name points at something that exists; zero errors, zero warnings |
  | `outline` | every level of the part tree has 2 to 9 children, and each part carries its level tag |
  | `secrets` | no password, token or key was committed |
  | `docs` | the generated documents match the model |

- [ ] **It adds no new `// TODO` line**, unless a task exists for it. (A TODO line is something the converter could not
      translate; a person must close it.)
- [ ] **The owner approved it.** For a requirement change that is Jim; for structure, Bob or Jim; for the pipeline, Tom.

## A story is done when

- [ ] Every task under it is closed.
- [ ] Its acceptance criteria are checked, by someone other than the author.
- [ ] The **trace** check shows no *new* gap: no new requirement without something that satisfies it (an *orphan*), no
      new requirement without a verification (*unverified*), and no new difference between DOORS and the model
      (*drift*). A gap that is the prime's to fix has a discrepancy report.
- [ ] It was shown at the sprint review, in the model or on the model's web site.

## A drop intake is done when

- [ ] The drop is on the vendor branch `vendor/prime`, filed in the package registry, and merged into `develop`.
- [ ] Every merge conflict and every *manual* line of the delta report is resolved, with a task for each.
- [ ] Discrepancy reports this drop fixes are closed; new ones are open and sent to the prime.

## Writing the change's reason (the commit message)

A commit message is the "reason for change" block. Write a short subject saying what the change does, a blank line,
why, and then trailers that GitLab and the changelog read:

```text
Close the BuoyModes TODO with a state definition

The converter does not translate state machines. Written from the v1
diagram "stm BuoyModes" (drop v1.0, xmi:id _22_1_7f3a0c1_9c2e...).

Changelog: added
Issue: #23
Reviewed-by: Jim <jim@example.invalid>
```

> [!tip]
> If you cannot meet one of these, say so in the MR and ask. A known, written exception is fine; a silent one is not.
