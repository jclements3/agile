# Ten SysML v2 artifacts as IDEF0 plates

One racing drone ("QuadX"), described ten ways. Each model letter is
one SysML v2 artifact kind rendered as an IDEF0 plate; the `##` doc
on each model states the mapping rule. Two cross-model links (R↔V)
show requirement-to-verification traceability in the interface table.

## K — Package / Namespace View

Package = decomposition scope; node ids are qualified names; the p.1
NODE INDEX of any drawing set *is* the rendered package view.

```idef0
tK Package View
## SysML v2 **package/namespace view**. The model-letter partition
## and node-id prefixes (`K`, `K1`, `K12`) are the qualified-name
## tree; this plate shows namespace governance as work.
  a1 Define Structure Package
    i1 Modeling Conventions
    o1 Structure Namespace
    m1 Model Librarian
  a2 Define Behavior Package
    i1 Modeling Conventions
    o1 Behavior Namespace
    m1 Model Librarian
  a3 Integrate Model Set
    i1 Structure Namespace
    i2 Behavior Namespace
    c1 Naming Policy
    o1 Published Model Set
    m1 Model Librarian
```

## D — Part Definition View (v1 BDD)

Composition tree = plate decomposition; a box is a part rendered as
the function it contributes; drill into D2 for the propulsion parts.

```idef0
tD Definition View
## SysML v2 **part definition** (v1 BDD). Composition = the activity
## tree: the subtree under a box is its parts list; attributes and
## multiplicities live in doc comments like this one.
  a1 Constitute Airframe
    i1 Structural Loads
    o1 Rigid Support
    m1 Carbon Frame
  a2 Constitute Propulsion
  ## Decomposes -- plate `D2` is the composition tree: ESC board,
  ## motors *x4*, propellers *x4*.
    i1 Electrical Power
    o1 Thrust
    m1 Propulsion Set
    a1 Constitute Speed Control
      i1 Electrical Power
      o1 Drive Current
      m1 ESC Board
    a2 Constitute Motors
      i1 Drive Current
      o1 Shaft Torque
      m1 Brushless Motors
    a3 Constitute Propellers
      i1 Shaft Torque
      o1 Thrust
      m1 Propeller Set
  a3 Constitute Avionics
    i1 Electrical Power
    o1 Control Authority
    m1 FC Stack
```

## I — Interconnection View (v1 IBD)

IDEF0's home turf: every connector is a named, directional, typed
flow; interface blocks are simply flow names.

```idef0
tI Interconnection View
## SysML v2 **interconnection view** (v1 IBD): parts wired by typed
## interfaces. Connections here are first-class: named, directed,
## and lintable.
  a1 Supply Pack Power
    i1 Charged Battery Pack
    o1 Pack Voltage
    m1 XT60 Connector
  a2 Regulate Bus Power
    i1 Pack Voltage
    o1 Bus Power
    m1 Power Distribution Board
  a3 Command Motors
    i1 Bus Power
    i2 Pilot Stick Inputs
    o1 Motor Drive Signals
    m1 Flight Controller
  a4 Drive Propulsion
    i1 Motor Drive Signals
    i2 Pack Voltage
    o1 Thrust
    m1 ESC & Motors
  a5 Stream Video
    i1 Bus Power
    o1 Video Downlink
    m1 VTX & Camera
```

## F — Action Flow View (v1 activity diagram)

IDEF0 is an action-flow notation natively: object flow = `i`/`o`,
control flow = `c`, fork = one output consumed twice.

```idef0
tF Action Flow View
## SysML v2 **action flow view**. The `Race Start Protocol` control
## fanning to two actions is the control-flow fork; `Live Telemetry`
## is object flow.
  a1 Arm & Preflight
    i1 Ready Drone
    c1 Race Start Protocol
    o1 Armed Drone
    m1 Pilot
  a2 Fly Heat
    i1 Armed Drone
    c1 Race Start Protocol
    o1 Flown Heat
    o2 Live Telemetry
    m1 Pilot
  a3 Record Telemetry
    i1 Live Telemetry
    o1 Heat Log
    m1 Timing System
  a4 Land & Disarm
    i1 Flown Heat
    o1 Safed Drone
    m1 Pilot
```

## S — State Transition View

A state is a *sustained activity*; a transition is the event flow
that ends one and starts the next; a guard is a control. Return
transitions are the feedback flows routing back against the
staircase.

```idef0
tS State Transition View
## SysML v2 **state transition view**. Standby -> Armed -> Flight,
## with `Landed Event` and `Recovery Event` as feedback transitions
## and `Arming Interlocks` as the guard on the Armed state.
  a1 Maintain Standby
    i1 Power On Event
    i2 Landed Event
    i3 Recovery Event
    o1 Arm Event
    m1 Flight Controller
  a2 Maintain Armed
    i1 Arm Event
    c1 Arming Interlocks
    o1 Launch Event
    m1 Flight Controller
  a3 Maintain Flight
    i1 Launch Event
    o1 Landed Event
    o2 Link Loss Event
    m1 Flight Controller
  a4 Maintain Failsafe
    i1 Link Loss Event
    o1 Recovery Event
    m1 Flight Controller
```

## Q — Sequence View

Lifelines become participants-as-functions; messages become flows;
time order is the flow chain read along the staircase. The FPV feed
back to the pilot is a return message.

```idef0
tQ Sequence View
## SysML v2 **sequence view**. Message order = the dependency chain:
## Start Command -> Stick Commands -> Lap Crossings -> Lap Times,
## with `FPV Feed` as the return message closing the pilot loop.
  a1 Direct Race Heat
    i1 Heat Schedule
    o1 Start Command
    m1 Race Director
  a2 Pilot Drone
    i1 Start Command
    i2 FPV Feed
    o1 Stick Commands
    m1 Pilot
  a3 Fly & Report
    i1 Stick Commands
    o1 Lap Crossings
    o2 FPV Feed
    m1 Drone
  a4 Score Laps
    i1 Lap Crossings
    o1 Lap Times
    m1 Timing System
```

## U — Use Case View

Actors are mechanisms plus the flows they exchange; «include» is a
shared control; the value delivered is the output. (See also the
standalone ATM example for the full treatment.)

```idef0
tU Use Case View
## SysML v2 **use case**. `Race Credentials` steering both sessions
## is the included use case made visible and checkable.
  a1 Check In Pilot
    i1 Pilot Registration
    o1 Race Credentials
    m1 Race Director
  a2 Run Practice Session
    i1 Practice Request
    c1 Race Credentials
    o1 Practice Results
    m1 Pilot
  a3 Run Race Heat
    i1 Heat Entry
    c1 Race Credentials
    o1 Heat Results
    m1 Pilot
```

## R — Requirement View

The requirement is an artifact that FLOWS: `derive` is a
transformation, `satisfy` is the requirement acting as a control on
design work, `verify` consumes requirement and evidence together.

```idef0
tR Requirement View
## SysML v2 **requirement view**. Requirement Spec forks three ways:
## off-model to the verification case, into derivation, and into the
## verify step as its pass/fail control -- derive/satisfy/verify as
## visible arrows.
  a1 Author Requirement
    i1 Stakeholder Need
    o1 Requirement Spec > V|Execute Verification Case|Requirement Spec
    m1 Systems Engineer
  a2 Derive Subsystem Reqs
    i1 Requirement Spec
    o1 Derived Requirements
    m1 Systems Engineer
  a3 Satisfy By Design
    i1 Design Candidates
    c1 Derived Requirements
    o1 Compliant Design
    m1 Design Team
  a4 Verify Satisfaction
    i1 Compliant Design
    i2 Verification Verdict < V|Execute Verification Case|Verification Verdict
    c1 Requirement Spec
    o1 Verified Baseline
    m1 Systems Engineer
```

## A — Analysis / Calculation Case (v1 parametric diagram)

Constraint blocks become controls (the governing equations); value
bindings are the flows between calculations.

```idef0
tA Analysis Case View
## SysML v2 **analysis case**. The `Rotor Momentum Model` and
## `Battery Discharge Model` controls are the constraint blocks;
## the flows are the value bindings.
  a1 Gather Vehicle Parameters
    i1 Component Datasheets
    o1 Mass & Power Figures
    m1 Analyst
  a2 Compute Hover Power
    i1 Mass & Power Figures
    c1 Rotor Momentum Model
    o1 Power Draw Estimate
    m1 Analysis Notebook
  a3 Compute Endurance
    i1 Power Draw Estimate
    c1 Battery Discharge Model
    o1 Endurance Estimate
    m1 Analysis Notebook
```

## V — Verification Case View

The third v2 case kind: consumes the requirement as its control (the
pass/fail criterion) and returns the verdict — both cross-model
links, visible in this file's interface table.

```idef0
tV Verification Case View
## SysML v2 **verification case**, paired with model R by two
## cross-model links: requirement in as control, verdict back out.
  a1 Plan Verification
    i1 Test Resources
    c1 Verification Policy
    o1 Verification Plan
    m1 Test Engineer
  a2 Execute Verification Case
    i1 Verification Plan
    i2 Test Article
    c1 Requirement Spec < R|Author Requirement|Requirement Spec
    o1 Verification Verdict > R|Verify Satisfaction|Verification Verdict
    m1 Test Range
```
