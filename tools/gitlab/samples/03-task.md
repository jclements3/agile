Part of #18

## Do

- [x] Read the v1 diagram *stm BuoyModes* in Cameo (drop v1.0): 4 states, 7 transitions, 6 triggers
- [x] Replace the line `// TODO uml:StateMachine 'BuoyModes' (xmi:id _22_1_7f3a0c1_…)` with a `state def`
- [x] Keep the `xmi:id` in a comment above it, so the next drop's delta can find it
- [ ] Run `gitlab.pl ci` locally before pushing

```sysml
// v1: uml:StateMachine 'BuoyModes' (xmi:id _22_1_7f3a0c1_…), drop v1.0
state def BuoyModes {
    entry; then Observing;
    state Observing; state Degraded; state Maintenance; state Recovered;
    transition first Observing accept lowBattery then Degraded;
    transition first Degraded accept charged then Observing;
    transition first Observing accept crewOnSite then Maintenance;
    transition first Degraded accept crewOnSite then Maintenance;
    transition first Maintenance accept crewDeparts then Observing;
    transition first Maintenance accept liftedAboard then Recovered;
}
```

## Done when

`grep -c TODO model/stations/Stations.sysml` drops by one, and the grammar job passes.

/spend 1d
