<!-- An MR discussion as it reads on !19, top to bottom. Each block is one comment; "resolvable" threads must be
     resolved before the MR can merge (project setting). -->

**@jim** commented on `model/stations/Stations.sysml` line 47 (resolvable):

`ShoreStation` is tagged `@L3Station`, but in v1 it is a specialization of `ObservingStation`, which is also L3.
That is fine. Please also keep the v1 `xmi:id` next to the tag, as #20 does for BuoyModes, so the delta can
point at it.

```suggestion:-0+1
    part def ShoreStation :> ObservingStation {
        @L3Station;   // v1 stereotype L3Station (xmi:id _22_1_7f3a0c1_…)
```

**@bob** replied:

Applied the suggestion (commit `3c9e1a2`). I did the same for the other 24 tags in a second commit so the file is
consistent.

**@jim** resolved the thread.

---

**@tom** commented (resolvable):

The `trace` job is yellow because of TW-SYS-012 and TW-SYS-016. Those are DR-1 (#8) and DR-4 (#11), both with the
prime, so not this MR's problem. Linking them so the reviewer sees why.

/relate #8 #11

**@tom** resolved the thread.

---

**@jim** commented:

Lint 0/0, outline passes, docs current. Approving.

/approve
/label ~"workflow::done"

**@bob** commented:

Thanks. Merging when the pipeline on the merged result finishes.

/merge
