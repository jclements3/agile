# Definition of Ready

The entry criteria for a sprint: the checklist a story must meet before the team commits to it, so nobody starts
work that is not understood. (Like the entry criteria of a review: if they are not met, the item waits.)

A story can be pulled into a sprint (moved to %"Sprint N" and ~"workflow::ready") when:

- [ ] It fits in one sprint, and every task under it is at most 5 points (one point = one ideal person-day).
- [ ] It carries exactly one ~"type::story", one ~"tome::..." and one ~"epic::..." label.
- [ ] The acceptance criteria are written as a checklist someone else can verify.
- [ ] The v1 elements (xmi:id) and DOORS ids it touches are named.
- [ ] Dependencies are linked: on the prime (a DR or a drop), or on another story (`/relate #N`, *blocked by*).
- [ ] Jim has ordered it on the backlog board.

A **task** is ready when it names its story ("Part of #N"), has an estimate (`/estimate`) and an assignee.

> [!tip]
> If a story does not fit in a sprint, split it by package, by requirement module, or by "convert / close TODOs /
> review". Never carry a story on purpose.
