# Baseline Procedure

A baseline is the model as released for analyses and reviews, exactly as you have always meant it: a merge to `main`, an annotated tag `baseline-N`, and a
GitLab release with notes. It must rebuild: the tag pipeline regenerates `docs/` and checks its hash against the one
recorded in the tag message. That is the physical configuration audit, done by machine in a minute; the functional
audit is the trace report (every requirement satisfied and verified, or an accepted gap).

## Steps

1. Jim decides the content: which drops and stories are in. Move what is not ready to the next milestone.
2. Cut the release branch and fill the *Release* MR template:
   ```sh
   perl $KIT/bin/gitlab.pl flow start release baseline-1
   # move CHANGELOG [Unreleased] under "## [baseline-1] -- date", regenerate docs, commit
   perl $KIT/bin/gitlab.pl flow finish --template .gitlab/merge_request_templates/Release.md
   ```
3. The deputy PM records the CCB's concurrence as a comment on the release MR; a code owner approves; the MR merges
   into `main`. Then, with the MR's number:
   ```sh
   perl $KIT/bin/gitlab.pl flow released 42
   ```
   `flow released` tags `baseline-1` on the merge commit (message `sha256=<docs hash>`, the hash of
   `git ls-tree -r <commit> -- docs`) and opens the back-merge MR `main → develop`. The tag pipeline audits the
   baseline, writes its toolchain and VCRM, then its `publish-release` job creates the GitLab release with the
   CHANGELOG section, the verification summary and the toolchain as notes.
4. Check the tag pipeline: the `baseline` job prints `baseline-1 rebuilds identically`.
5. Close the milestones the baseline covers.

| Baseline | When | Contents |
|---|---|---|
| baseline-1 | end of the port | drop v1.0 ported, TODOs closed, trace complete but for accepted gaps |
| baseline-N | after each drop merged in maintenance | the drop, its rework, closed DRs |
