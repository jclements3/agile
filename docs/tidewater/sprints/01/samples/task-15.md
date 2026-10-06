# Prove a direct push to develop is refused

Part of #3

## Do

- [ ] Prove a direct push to develop is refused
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@tom** (2026-10-09T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@tom** (2026-10-09T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@tom** (2026-10-13T15:00:00Z) [system]:
added 1d of time spent

**@tom** (2026-10-13T15:00:00Z) [system]:
removed ~"workflow::in-progress" label

**@tom** (2026-10-13T15:00:00Z) [system]:
added ~"workflow::done" label

**@tom** (2026-10-13T15:00:00Z) [system]:
closed

**@tom** (2026-10-13T15:00:00Z):
A direct push to develop is refused by the server:

```text
remote: GitLab: You are not allowed to push code to protected branches on this project.        
To data/tidewater/gitlab/repos/tidewater/model.git
 ! [remote rejected] HEAD -> develop (pre-receive hook declined)
error: failed to push some refs to 'data/tidewater/gitlab/repos/tidewater/model.git'
```
