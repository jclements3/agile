## Goal

Every top-level package of the prime's v1 model (drop v1.0) exists in the government's SysML v2 model on `develop`,
with every converter TODO line closed or turned into a task, passing lint 0/0 and the outline check.

## Scope

| In | Out |
|---|---|
| The 12 converted packages under `model/` | Requirements and trace (~"epic::requirements") |
| Level tags `@L1Network` … `@L6Component` | Behavior TODOs: state machine, sequence, fork (~"epic::behavior") |
| Units, value types, the parametric binding | Any change to the prime's v1 model (raise a DR instead) |

## Stories

- [x] #7 Import drop v1.0 onto `vendor/prime` and merge it into `develop`
- [x] #12 Define the level tags in `model/gov/Conventions.sysml`
- [x] #15 Close the Network and Interfaces TODO lines
- [ ] #18 Close the Stations TODO lines
- [ ] #21 Close the DataCenter and Operations TODO lines
- [ ] #24 Replace the unit TODOs with ISQ quantities
- [ ] #27 Review the structure with the prime's modeler

## Measures

| Measure | Target | Now (Sprint 4) |
|---|---|---|
| Structure TODO lines left (stereotypes, units, profile) | 0 | 24 of 43 |
| Packages accepted by @jim | 9 | 3 |
| Lint | 0 errors / 0 warnings | 0 / 0 |

## Timeline

| Start | Target | Semester |
|---|---|---|
| %"Sprint 2" | %"Sprint 9" | 1 (Oct 2026 – Mar 2027) |

Tome: ~"tome::port" · Owner: @jim · Engineers: @bob, @tom
