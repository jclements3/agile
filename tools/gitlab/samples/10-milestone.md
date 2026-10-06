<!-- The description of milestone "Sprint 4" (Plan > Milestones). Written at planning, updated at the review. -->

**Sprint 4** · Mon 2026-11-16 to Fri 2026-11-27 · Capacity 24 points (Jim 6, Bob 9, Tom 9)

## Sprint goal

Stations and DataCenter packages have no stereotype TODOs left, and the pipeline runs on the team's Windows runner.

## Committed stories

| Story | Epic | Points | Owner |
|---|---|---|---|
| #18 Close the Stations TODO lines | ~"epic::structure" | 8 | @bob |
| #21 Close the DataCenter and Operations TODO lines | ~"epic::structure" | 5 | @bob |
| #25 Move CI to the Windows shell runner | ~"epic::pipeline" | 6 | @tom |
| #26 Onboarding page and laptop checklist | ~"epic::onboarding" | 3 | @jim |

## Review (Fri 2026-11-27)

- Done: #18, #25, #26 (17 points). Carried: #21 (5 points: the DataCenter ports need a decision on proxy vs full
  ports, spike #32 next sprint).
- Structure TODO lines: 43 → 19.
- Pipelines on `develop`: 14 of 14 green.

> [!tip]
> The burn-down chart on this page counts issues and weight (Premium). On Free, use the issue list filtered by this
> milestone and ~"type::story".
