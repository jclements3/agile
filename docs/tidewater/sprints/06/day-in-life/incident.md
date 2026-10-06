# #132 Nightly full check failed: no space left on the runner

The nightly full check (pipeline #83, scheduled 02:00) failed in every job before running any check:

```text
fatal: could not create work tree dir 'builds/tidewater/model': No space left on device
```

Job: https://gitlab.gov.example.invalid/tidewater/model/-/pipelines/83/../jobs/543

Not a model problem: develop's last MR pipeline was green. Picked up at the stand-up.
---- comments

**@tom** (2026-12-17T15:30:00Z) [system]:
added 1h of time spent

**@tom** (2026-12-17T15:30:00Z) [system]:
removed ~"workflow::in-progress" label

**@tom** (2026-12-17T15:30:00Z) [system]:
added ~"workflow::done" label

**@tom** (2026-12-17T15:30:00Z) [system]:
closed

**@tom** (2026-12-17T15:30:00Z):
Cleared the runner's old build directories (14 GB) and set the runner to clean up after each job. Re-ran the full check: pipeline #84 success.
