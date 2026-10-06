# Administration

What Tom (configuration management) and Jim (the project owner) keep running, and how often. None of this is
new in kind: it is the upkeep a CM office always did (access lists, backups, audits), with GitLab doing the recording.

| What | How often | Who | How |
|---|---|---|---|
| Project settings match `project.conf` | each change; monthly check | Tom | `gitlab.pl setup project.conf` (idempotent) |
| Sprint milestones exist two sprints ahead | each planning | Jim | `gitlab.pl sprints 2026-10-05 39` |
| Runner healthy, kit current on it | weekly | Tom | Admin > Runners; `git -C $KIT pull` on the runner |
| Pipeline schedule (weekly status) | weekly | Tom | Build > Pipeline schedules |
| Access tokens rotated | before expiry (90 days) | token owner | Settings > Access tokens; update the CI/CD variable |
| Members reviewed | quarterly; on every departure | Jim | Manage > Members: remove leavers the same day |
| Audit events reviewed | monthly | Jim | Secure > Audit events (Premium) |
| Backups | daily (server); per baseline (export) | instance admin; Tom | `gitlab-backup create`; project export per baseline |
| GitLab upgrades | per the instance policy | instance admin | read the release notes for CI and API changes |

## Runner

A Windows shell runner uses the same Git for Windows Perl as the team's laptops. GitLab Runner's Windows shell executor
runs PowerShell (`pwsh`); every job is a single `perl ci/job.pl NAME` line, so the same pipeline works in PowerShell,
Git Bash and Docker alike:

```toml
[[runners]]
  name = "mbse-win-01"
  executor = "shell"
  shell = "pwsh"            # the Windows default; job lines are plain `perl ci/job.pl NAME`, so no sh syntax is needed
  environment = ["KIT=C:/agile"]   # where the kit is checked out on this machine
```

## When someone leaves

- [ ] Remove them from the project and group the same day
- [ ] Revoke their tokens; rotate any shared CI/CD variable they could read
- [ ] Reassign their open issues and MRs
- [ ] Update `CODEOWNERS` if they were an owner
