<!-- Comments on story #18 over Sprint 4, newest last. Quick actions on their own line run when the comment is saved
     and disappear from the text; GitLab shows a system note instead (e.g. "Bob added ~workflow::blocked"). -->

**@bob** · Mon 2026-11-16

Started. Doing #19 first, then #20.

/label ~"workflow::in-progress"
/spend 4h

---

**@bob** · Wed 2026-11-18

Blocked on #20: the v1 diagram *stm BuoyModes* shows a trigger `liftedAboard` that is not on any transition in the
XMI. Asked the prime's modeler which one is right.

/label ~"workflow::blocked"
/relate #20

---

**@jim** · Wed 2026-11-18

The prime's modeler confirms the XMI is right: the diagram is stale. Not a DR (diagrams are not delivered content),
but noted for the next model review. Unblocking.

/unlabel ~"workflow::blocked"
/label ~"workflow::in-progress"

---

**@bob** · Fri 2026-11-20

#19 merged (!19), #20 in review (!20). #22 is @tom's. On track for the sprint.

/spend 1d 2h

---

**@jim** · Fri 2026-11-27

All four tasks closed; acceptance criteria checked. Demoed at the review.

/label ~"workflow::done"
/close
