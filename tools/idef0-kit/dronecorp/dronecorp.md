<!-- Generated & maintained as the canonical DroneCorp model source.
     Build:  idef0 lint dronecorp.md
             idef2html dronecorp.md > plates.html
             idef0 links dronecorp.md > INTERFACES              -->

# DroneCorp — IDEF0 model set

A ten-model IDEF0 decomposition of a racing-drone company, written as a
single literate document: the prose is the narrative, and the
```` ```idef0 ```` fences are the model source. All fences concatenate
into one project — the toolchain (`idef0 lint/fmt/links`, `idef2html`,
`idef2text`, `idef2svg`) reads this file directly and reports
diagnostics against its line numbers.

Every model runs a six-level spine, carries `##` doc comments that
surface as hover tooltips in `plates.html`, and pairs its cross-model
interfaces explicitly. The interface table (52 links) includes five
flows renamed across boundaries, shown as paired rows.

## Model E — Executive & Strategy (racing drone company)

SPINE (primary value path): E2 Plan & Allocate -> E22 Build Annual
Operating Plan -> E222 Build Financial Plan -> E2222 Build Expense &
Capex Budgets -> E22222 Consolidate Department Budgets -> E222221-3.
The spine carries the capital-allocation flow: market intelligence and
finance reporting in; Strategic Plan and Approved Budgets out as
controls consumed by every other model. Off-spine: E1 direction-setting
and E3 performance governance decompose one level; E4 risk/compliance
is atomic.

Interfaces (paired as partner models land): budgets > R P T Q C L S F H;
Strategic Plan > R C; Portfolio Mandate > R; Trade-Compliance Policy >
C L; Financial Statements & KPIs < F; Demand Forecast < C; Department
Budget Requests < F (consolidated submission).

```idef0
tE Executive & Strategy
## **Executive & Strategy** sets direction and allocates resources for
## the whole enterprise. Strategy and budgets flow *out*; statements,
## forecasts, and KPIs flow *back in*.
  a1 Set Direction
    i1 Market & Race-Scene Intelligence
    i2 Board Guidance
    c1 Corporate Charter
    o1 Strategic Plan > R|Define Product Requirements|Strategic Plan
    o2 Portfolio Mandate > R|Define Product Requirements|Portfolio Mandate
    m1 Executive Team
    a1 Scan Market & Race Scene
      i1 Market & Race-Scene Intelligence
      c1 Corporate Charter
      o1 Market Assessment
      m1 Strategy Staff
    a2 Set Product & Race Strategy
      i1 Market Assessment
      i2 Board Guidance
      c1 Corporate Charter
      o1 Strategic Plan
      m1 Executive Team
    a3 Approve Portfolio Mandate
      i1 Strategic Plan
      o1 Portfolio Mandate
      m1 Executive Team
  a2 Plan & Allocate
    i1 Financial Statements & KPIs < F|Close Books & Report|Financial Statements & KPIs
    i2 Department Budget Requests < F|Plan & Steward Budgets|Department Budget Requests
    i3 Demand Forecast < C|Manage Contract Fulfillment|Demand Forecast
    c1 Strategic Plan
    c2 Portfolio Mandate
    c3 Planning Calendar < F|Plan & Steward Budgets|Planning Calendar
    c4 Budget Policy < F|Plan & Steward Budgets|Budget Policy
    o1 Approved Budgets
      ## The **budget hub**: nine `<` consumers across R P T Q C L S F
      ## H all draw from this one port -- the fan-out is hub-and-spoke,
      ## one representative `>` link plus consumer-side `<` paths.
    o2 Performance Targets
    m1 FP&A Team
    a1 Consolidate Demand & Capacity Outlook
      i1 Demand Forecast
      i2 Financial Statements & KPIs
      c1 Planning Calendar
      o1 Demand & Capacity Outlook
      m1 FP&A Team
    a2 Build Annual Operating Plan
      i1 Demand & Capacity Outlook
      i2 Department Budget Requests
      c1 Strategic Plan
      c2 Portfolio Mandate
      c3 Budget Policy
      o1 Annual Operating Plan
      m1 FP&A Team
      a1 Draft Product-Line Plans
        i1 Demand & Capacity Outlook
        c1 Portfolio Mandate
        o1 Product-Line Plans
        m1 Strategy Staff
      a2 Build Financial Plan
        i1 Product-Line Plans
        i2 Department Budget Requests
        c1 Budget Policy
        o1 Financial Plan
        m1 FP&A Team
        a1 Project Revenue & Bookings
          i1 Product-Line Plans
          o1 Revenue Projection
          m1 FP&A Team
        a2 Build Expense & Capex Budgets
          i1 Department Budget Requests
          i2 Revenue Projection
          c1 Budget Policy
          o1 Budget Baseline
          m1 FP&A Team
          a1 Collect Budget Submissions
            i1 Department Budget Requests
            c1 Budget Policy
            o1 Normalized Submissions
            m1 FP&A Team
          a2 Consolidate Department Budgets
            i1 Normalized Submissions
            i2 Revenue Projection
            c1 Budget Policy
            o1 Consolidated Budget
            m1 FP&A Team
            a1 Check Submissions Against Targets
              i1 Normalized Submissions
              c1 Budget Policy
              o1 Flagged Variances
              m1 FP&A Team
            a2 Resolve Variances With Departments
              i1 Flagged Variances
              i2 Revenue Projection
              o1 Settled Budget Lines
              m1 FP&A Team
            a3 Lock Consolidated Budget
              i1 Settled Budget Lines
              o1 Consolidated Budget
              m1 FP&A Team
          a3 Prioritize Capex
            i1 Consolidated Budget
            o1 Budget Baseline
            m1 Executive Team
        a3 Assemble Financial Plan
          i1 Budget Baseline
          i2 Revenue Projection
          o1 Financial Plan
          m1 FP&A Team
      a3 Reconcile & Approve Plan
        i1 Financial Plan
        c1 Strategic Plan
        o1 Annual Operating Plan
        m1 Executive Team
    a3 Issue Budgets & Targets
      i1 Annual Operating Plan
      c1 Board Guidance
      c2 Budget Policy
      o1 Approved Budgets > R|Develop Product Design|Approved Budgets
      o2 Performance Targets > F|Close Books & Report|Performance Targets
      m1 Executive Team
  a3 Govern Performance
    i1 Financial Statements & KPIs
    c1 Performance Targets
    o1 Corrective Directives
    o2 Board Report
    m1 Executive Team
    a1 Compile Performance Review
      i1 Financial Statements & KPIs
      c1 Performance Targets
      o1 Performance Review Pack
      m1 FP&A Team
    a2 Hold Business Reviews
      i1 Performance Review Pack
      o1 Review Findings
      m1 Executive Team
    a3 Direct Corrective Action
      i1 Review Findings
      o1 Corrective Directives
      o2 Board Report
      m1 Executive Team
  a4 Manage Risk & Compliance
    i1 Regulatory & Trade Watch
    c1 Corporate Charter
    o1 Compliance Policy
    o2 Trade-Compliance Policy > C|Win Contracts|Develop Proposals|Price & Clear the Deal|Clear Export & Trade Compliance|Trade-Compliance Policy
    m1 General Counsel
```

## Model R — Research & Development (racing drone company)

SPINE (primary value path): R2 Develop Product Design -> R22 Develop
Electronics -> R222 Develop Flight Controller Board -> R2222 Lay Out
FC PCB -> R22222 Route Board -> R222221-3. The spine carries the
design-realization flow: requirements and component technology in;
Design Data Package out through verification to the Engineering
Baseline release. Off-spine: airframe (R21) and firmware (R23) branch
one level below their plates; requirements (R1), verification (R3)
and release (R4) decompose one level.

Interfaces: Strategic Plan / Portfolio Mandate / Approved Budgets < E
(paired now). Pending partners: Engineering Baseline and Firmware
Release > P T Q as controls; Customer Feedback < S into R11;
Manufacturability Feedback < P into R2222 area.

```idef0
tR Research & Development
  a1 Define Product Requirements
    i1 Market & Pilot Inputs
    i2 Customer Feedback
    c1 Strategic Plan < E|Set Direction|Strategic Plan
    c2 Portfolio Mandate < E|Set Direction|Portfolio Mandate
    o1 Product Requirements
    m1 Product Managers
    a1 Gather Race-Team & Market Inputs
      i1 Market & Pilot Inputs
      i2 Customer Feedback < S|Synthesize Feedback & Insights|Customer Feedback
      o1 Requirement Candidates
      m1 Product Managers
    a2 Write Product Requirements
      i1 Requirement Candidates
      c1 Portfolio Mandate
      o1 Draft Requirements
      m1 Product Managers
    a3 Baseline Requirements
      i1 Draft Requirements
      c1 Strategic Plan
      o1 Product Requirements
      m1 Product Managers
  a2 Develop Product Design
    i1 Candidate Components & Technologies
    i2 Design Issues
    i3 Manufacturability Feedback < P|Support Manufacturing Engineering|Manufacturability Feedback
    c1 Product Requirements
    c2 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Design Data Package
    m1 Design Engineers
    m2 CAD & EDA Tools
    a1 Design Airframe
      i1 Candidate Components & Technologies
      i2 Design Issues
      c1 Product Requirements
      o1 Airframe Design
      m1 Design Engineers
      a1 Model Frame Geometry
        i1 Candidate Components & Technologies
        c1 Product Requirements
        o1 Frame CAD Model
        m1 CAD & EDA Tools
      a2 Analyze Structure & Aero
        i1 Frame CAD Model
        o1 Frame Analysis Results
        m1 Simulation Cluster
      a3 Prototype & Iterate Frame
        i1 Frame Analysis Results
        i2 Design Issues
        o1 Airframe Design
        m1 Prototype Shop
    a2 Develop Electronics
      i1 Candidate Components & Technologies
      i2 Design Issues
      c1 Product Requirements
      o1 Electronics Design
      m1 Design Engineers
      a1 Architect Electronics Suite
        i1 Candidate Components & Technologies
        c1 Product Requirements
        o1 Electronics Architecture
        m1 Design Engineers
      a2 Develop Flight Controller Board
        i1 Electronics Architecture
        i2 Design Issues
        o1 FC Design Files
        m1 Design Engineers
        a1 Capture FC Schematic
          i1 Electronics Architecture
          o1 FC Schematic
          m1 CAD & EDA Tools
        a2 Lay Out FC PCB
          i1 FC Schematic
          c1 Fab Design Rules
          o1 FC Layout
          m1 CAD & EDA Tools
          a1 Place Components & Plan Stackup
            i1 FC Schematic
            c1 Fab Design Rules
            o1 Placed Board
            m1 CAD & EDA Tools
          a2 Route Board
            i1 Placed Board
            c1 Fab Design Rules
            o1 Routed Board
            m1 CAD & EDA Tools
            a1 Route Power Stages
              i1 Placed Board
              o1 Power Routing
              m1 CAD & EDA Tools
            a2 Route High-Speed & RF Nets
              i1 Power Routing
              c1 Fab Design Rules
              o1 Signal Routing
              m1 CAD & EDA Tools
            a3 Tune & Clean Up Routing
              i1 Signal Routing
              o1 Routed Board
              m1 CAD & EDA Tools
          a3 Run DRC & Prepare Fab Package
            i1 Routed Board
            c1 Fab Design Rules
            o1 FC Layout
            m1 CAD & EDA Tools
        a3 Bring Up FC Prototype
          i1 FC Layout
          i2 Design Issues
          o1 FC Design Files
          m1 Lab Bench
      a3 Develop ESC & VTX Boards
        i1 Electronics Architecture
        o1 ESC & VTX Designs
        m1 Design Engineers
      a4 Integrate Electronics Package
        i1 FC Design Files
        i2 ESC & VTX Designs
        o1 Electronics Design
        m1 Design Engineers
    a3 Develop Firmware
      i1 Electronics Design
      c1 Product Requirements
      o1 Firmware Build
      m1 Firmware Engineers
      a1 Define Firmware Architecture
        i1 Electronics Design
        c1 Product Requirements
        o1 Firmware Architecture
        m1 Firmware Engineers
      a2 Implement Flight & Config Code
        i1 Firmware Architecture
        o1 Firmware Candidate
        m1 Firmware Engineers
      a3 Bench-Validate Firmware
        i1 Firmware Candidate
        o1 Firmware Build
        m1 HIL Bench
    a4 Integrate Design Data
      i1 Airframe Design
      i2 Electronics Design
      i3 Firmware Build
      o1 Design Data Package
      m1 Configuration Manager
  a3 Verify Design
    i1 Design Data Package
    c1 Product Requirements
    o1 Verification Report
    o2 Design Issues
    m1 Test Engineers
    a1 Build Verification Units
      i1 Design Data Package
      o1 Verification Units
      m1 Prototype Shop
    a2 Run Design Verification Tests
      i1 Verification Units
      c1 Product Requirements
      o1 Test Results
      m1 Flight Test Pilots
    a3 Disposition Findings
      i1 Test Results
      o1 Verification Report
      o2 Design Issues
      m1 Test Engineers
  a4 Release Engineering Baseline
    i1 Design Data Package
    i2 Verification Report
    c1 Release Procedure
    o1 Engineering Baseline > P|Build Products|Engineering Baseline
    o2 Firmware Release > P|Build Products|Flash & Configure Firmware|Firmware Release
    m1 Configuration Manager
    a1 Compile Release Package
      i1 Design Data Package
      i2 Verification Report
      c1 Release Procedure
      o1 Release Candidate Package
      m1 Configuration Manager
    a2 Review & Approve Release
      i1 Release Candidate Package
      c1 Release Procedure
      o1 Approved Release
      m1 Engineering Review Board
    a3 Publish Baseline
      i1 Approved Release
      o1 Engineering Baseline
      o2 Firmware Release
      m1 Configuration Manager
```

## Model P — Production (racing drone company)

SPINE: P3 Build Products -> P32 Build Electronics Assemblies -> P321
Run SMT Line -> P3212 Process Panels -> P32121 Print Solder Paste ->
P321211-3. The spine carries the physical product-realization flow:
kitted materials in; configured, firmware-flashed drones out to Testing.
Off-spine: planning (P1), procurement & kitting (P2), frame fabrication
(P31), final assembly (P33) decompose one level; manufacturing
engineering (P4) is atomic and closes the DFM loop back to R.

Interfaces: Approved Budgets < E; Engineering Baseline + Firmware
Release < R; Manufacturability Feedback > R (paired now). Pending:
Spot Orders + Continuous Supply Schedule < C; Rework Units < T
(renamed from Test Rejects); Configured Drones > T; CAPA Directives +
Approved Supplier List < Q; Line Nonconformance Reports > Q; Inbound
Component Deliveries < L; Production Crew < H.

```idef0
tP Production
## **Production** converts kitted materials into configured,
## firmware-flashed racing drones.\n The six-level spine follows the
## SMT line down to paste printing: `P3 > P32 > P321 > P3212 > P32121`.
  a1 Plan Production
    i1 Spot Orders < C|Manage Contract Fulfillment|Spot Orders
    i2 Continuous Supply Schedule < C|Manage Contract Fulfillment|Continuous Supply Schedule
    c1 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    c2 Engineering Baseline
    o1 Master Production Schedule
    o2 Work Orders
    o3 Material Requirements
    m1 Production Planners
    a1 Build Master Schedule
      i1 Spot Orders
      i2 Continuous Supply Schedule
      c1 Approved Budgets
      o1 Master Production Schedule
      m1 Production Planners
    a2 Plan Materials
      i1 Master Production Schedule
      c1 Engineering Baseline
      o1 Material Requirements
      m1 ERP MRP Module
    a3 Release Work Orders
      i1 Master Production Schedule
      o1 Work Orders
      m1 Production Planners
  a2 Procure & Kit Materials
    i1 Material Requirements
    i2 Inbound Component Deliveries < L|Receive Inbound Freight|Inbound Component Deliveries
    i3 Work Orders
    o1 Line Kits
    o2 Purchase Orders
    m1 Supply Chain Team
    a1 Order Components
      i1 Material Requirements
      c1 Approved Supplier List < Q|Maintain Quality System|Approved Supplier List
      o1 Purchase Orders
      m1 Buyers
    a2 Receive & Stage Materials
      i1 Inbound Component Deliveries
      o1 Staged Materials
      m1 Stockroom Crew
    a3 Kit Jobs to Line
      i1 Staged Materials
      i2 Work Orders
      o1 Line Kits
      m1 Stockroom Crew
  a3 Build Products
    i1 Line Kits
    i2 Rework Units < T|Disposition & Report|Test Rejects
      ## Units failing acceptance test. Testing calls this flow `Test
      ## Rejects`; the rename marks the boundary where a *failed*
      ## product becomes *work in process* again.\n Routed to board
      ## test & rework (P323) inside Build Electronics Assemblies.
    c1 Engineering Baseline < R|Release Engineering Baseline|Engineering Baseline
    c2 Process Specifications
    c3 Work Orders
    o1 Configured Drones
    o2 Line Nonconformance Reports > Q|Manage Nonconformance & CAPA|Line Nonconformances
    m1 Production Crew < H|Staff & Develop Workforce|Staffed Production Workforce
      ## Certified operators supplied by HR as `Staffed Production
      ## Workforce` (renamed at this boundary). IPC-certified for
      ## solder work -- see plate *H2221*.
    a1 Fabricate Frames
      i1 Line Kits
      c1 Process Specifications
      o1 Frame Sets
      m1 CNC Router
      a1 CNC-Cut Carbon Plates
        i1 Line Kits
        c1 Process Specifications
        o1 Cut Plates
        m1 CNC Router
      a2 Finish & Deburr Plates
        i1 Cut Plates
        o1 Finished Plates
        m1 Finishing Bench
      a3 Fit-Check & Bag Frame Sets
        i1 Finished Plates
        o1 Frame Sets
        m1 Assembly Jigs
    a2 Build Electronics Assemblies
      i1 Line Kits
      i2 Rework Units
      c1 Process Specifications
      o1 Tested Boards
      m1 SMT Line
      a1 Run SMT Line
        i1 Line Kits
        c1 Process Specifications
        o1 Inspected Panels
        m1 SMT Line
        a1 Prepare Line & Programs
          i1 Line Kits
          c1 Process Specifications
          o1 Loaded Line
          m1 SMT Line
        a2 Process Panels
          i1 Loaded Line
          c1 Process Specifications
          o1 Reflowed Panels
          m1 SMT Line
          a1 Print Solder Paste
          ## First and most defect-prone SMT step: squeegee paste
          ## through the stencil onto bare panels. Roughly **60% of
          ## SMT defects** trace back to paste printing, which is why
          ## it decomposes to its own plate.
            i1 Loaded Line
            c1 Process Specifications
            o1 Pasted Panels
            m1 Stencil Printer
            a1 Align Stencil & Load Paste
              i1 Loaded Line
              o1 Ready Printer
              m1 Stencil Printer
            a2 Print Panel
              i1 Ready Printer
              o1 Printed Panels
              m1 Stencil Printer
            a3 Verify Paste Deposition
            ## *Solder Paste Inspection* (SPI) measures deposit height,
            ## area, and volume on every panel.\n Catching a bad print
            ## here costs seconds; catching it after reflow costs a
            ## board.
              i1 Printed Panels
              c1 Process Specifications
              o1 Pasted Panels
              m1 SPI Station
          a2 Place Components
            i1 Pasted Panels
            o1 Populated Panels
            m1 Pick-and-Place Machines
          a3 Reflow Solder
            i1 Populated Panels
            c1 Process Specifications
            o1 Reflowed Panels
            m1 Reflow Oven
        a3 Inspect Panels
          i1 Reflowed Panels
          o1 Inspected Panels
          m1 AOI Station
      a2 Assemble Through-Hole & Connectors
        i1 Inspected Panels
        o1 Assembled Boards
        m1 Solder Stations
      a3 Test & Rework Boards
        i1 Assembled Boards
        i2 Rework Units
        o1 Tested Boards
        m1 ICT Fixtures
    a3 Final-Assemble Drones
      i1 Frame Sets
      i2 Tested Boards
      c1 Process Specifications
      o1 Assembled Drones
      m1 Assembly Cells
      a1 Assemble Airframe
        i1 Frame Sets
        o1 Built Frames
        m1 Assembly Cells
      a2 Install Electronics Stack
        i1 Built Frames
        i2 Tested Boards
        o1 Stacked Drones
        m1 Assembly Cells
      a3 Close Out & Serialize
        i1 Stacked Drones
        c1 Process Specifications
        o1 Assembled Drones
        m1 Assembly Cells
    a4 Flash & Configure Firmware
      i1 Assembled Drones
      i2 Firmware Release < R|Release Engineering Baseline|Firmware Release
      ## Signed firmware image plus default tune from R's baseline
      ## release. Every unit flashes the **exact release build** -- no
      ## dev builds reach the line.
      o1 Configured Drones > T|Execute Acceptance Tests|Configured Drones
      m1 Flashing Stations
  a4 Support Manufacturing Engineering
    i1 CAPA Directives < Q|Manage Nonconformance & CAPA|CAPA Directives
    c1 Engineering Baseline
    o1 Process Specifications
    o2 Manufacturability Feedback > R|Develop Product Design|Manufacturability Feedback
    m1 Manufacturing Engineers
```

## Model T — Testing (racing drone company)

SPINE: T2 Execute Acceptance Tests -> T22 Flight-Test Units -> T222
Fly Acceptance Profile -> T2222 Run Performance Circuits -> T22223
Evaluate Circuit Data -> T222231-3. The spine carries the acceptance
flow: configured drones from Production in; dispositioned accepts,
rejects (renamed Rework Units at the P boundary), and test records
out. Off-spine: test-program preparation (T1) and disposition (T3)
decompose one level.

Interfaces: Configured Drones < P; Test Rejects > P (renamed);
Engineering Baseline < R; Approved Budgets < E (paired now).
Pending: Accepted Drones + Test Records > Q; Acceptance Test
Procedure < Q; Test Pilots < H.

```idef0
tT Testing
  a1 Prepare Test Program
    i1 Test Demand Forecast
    c1 Engineering Baseline < R|Release Engineering Baseline|Engineering Baseline
    c2 Acceptance Test Procedure < Q|Maintain Quality System|Acceptance Test Procedure
    c3 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Test Procedures
    o2 Test Schedule
    m1 Test Engineers
    a1 Author Test Procedures
      c1 Engineering Baseline
      c2 Acceptance Test Procedure
      o1 Test Procedures
      m1 Test Engineers
    a2 Plan Test Capacity & Schedule
      i1 Test Demand Forecast
      o1 Test Schedule
      m1 Test Engineers
    a3 Maintain & Calibrate Rigs
      c1 Test Procedures
      o1 Rig Calibration Records
      m1 Lab Techs
  a2 Execute Acceptance Tests
    i1 Configured Drones < P|Build Products|Flash & Configure Firmware|Configured Drones
    c1 Test Procedures
    c2 Test Schedule
    o1 Test Data
    o2 Returned Units
    m1 Test Pilots < H|Staff & Develop Workforce|Certified Test Pilots
    a1 Bench-Test Units
      i1 Configured Drones
      c1 Test Procedures
      o1 Bench Results
      o2 Bench-Passed Units
      m1 Bench Rigs
    a2 Flight-Test Units
      i1 Bench-Passed Units
      c1 Test Procedures
      c2 Test Schedule
      o1 Flight Results
      o2 Returned Units
      m1 Test Pilots
      a1 Stage & Preflight Units
        i1 Bench-Passed Units
        c1 Test Procedures
        o1 Preflighted Units
        m1 Ground Crew
      a2 Fly Acceptance Profile
        i1 Preflighted Units
        c1 Test Procedures
        o1 Flight Results
        o2 Flown Units
        m1 Test Pilots
        a1 Hover & Failsafe Checks
          i1 Preflighted Units
          c1 Test Procedures
          o1 Hover-Checked Units
          m1 Test Pilots
        a2 Run Performance Circuits
          i1 Hover-Checked Units
          c1 Test Procedures
          o1 Circuit Results
          o2 Flown Units
          m1 Test Pilots
          a1 Fly Speed Runs
            i1 Hover-Checked Units
            o1 Speed-Run Telemetry
            o2 Speed-Tested Units
            m1 Test Pilots
          a2 Fly Agility Circuits
            i1 Speed-Tested Units
            o1 Agility Telemetry
            o2 Flown Units
            m1 Test Pilots
          a3 Evaluate Circuit Data
            i1 Speed-Run Telemetry
            i2 Agility Telemetry
            c1 Test Procedures
            o1 Circuit Results
            m1 Telemetry Workstation
            a1 Extract Telemetry Metrics
              i1 Speed-Run Telemetry
              i2 Agility Telemetry
              o1 Telemetry Metrics
              m1 Telemetry Workstation
            a2 Compare Against Acceptance Gates
              i1 Telemetry Metrics
              c1 Test Procedures
              o1 Gate Comparisons
              m1 Telemetry Workstation
            a3 Tag Pass-Fail & Archive Runs
              i1 Gate Comparisons
              o1 Circuit Results
              m1 Test Data Server
        a3 Consolidate Flight Results
          i1 Circuit Results
          o1 Flight Results
          m1 Telemetry Workstation
      a3 Post-Flight Inspect & Return Units
        i1 Flown Units
        o1 Returned Units
        m1 Ground Crew
    a3 Consolidate Test Data
      i1 Bench Results
      i2 Flight Results
      o1 Test Data
      m1 Test Data Server
  a3 Disposition & Report
    i1 Test Data
    i2 Returned Units
    c1 Test Procedures
    o1 Accepted Drones > Q|Inspect & Release Product|Accepted Drones
    o2 Test Rejects > P|Build Products|Rework Units
      ## Dispositioned failures returned to Production, where this
      ## flow is renamed `Rework Units`. Both names appear in the
      ## interface table -- **one flow, two vocabularies**.
    o3 Test Records > Q|Inspect & Release Product|Test Records
    m1 Test Engineers
    a1 Review Results & Disposition Units
      i1 Test Data
      c1 Test Procedures
      o1 Disposition Decisions
      m1 Test Engineers
    a2 Segregate Accepts & Rejects
      i1 Disposition Decisions
      i2 Returned Units
      o1 Accepted Drones
      o2 Test Rejects
      m1 Ground Crew
    a3 Compile Test Records
      i1 Disposition Decisions
      o1 Test Records
      m1 Test Data Server
```

## Model Q — Quality Assurance (racing drone company)

SPINE: Q3 Manage Nonconformance & CAPA -> Q32 Run CAPA Cases -> Q322
Investigate Root Cause -> Q3222 Analyze Failed Units -> Q32222 Run
Electrical Fault Isolation -> Q322221-3. The spine carries the quality
feedback flow: NCRs, test records, and field complaints in; verified
root causes and CAPA directives out to Production. Off-spine: the
quality system (Q1) and product release (Q2) decompose one level.

Interfaces: Engineering Baseline < R; Approved Budgets < E; Accepted
Drones + Test Records < T; Acceptance Test Procedure > T; Approved
Supplier List > P; Line Nonconformances < P (renamed); CAPA
Directives > P (paired now). Pending: Released Products > L; Field
Complaints < S.

```idef0
tQ Quality Assurance
  a1 Maintain Quality System
    i1 Regulatory & Standards Updates
    i2 Supplier Performance Data
    c1 Engineering Baseline < R|Release Engineering Baseline|Engineering Baseline
    c2 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Quality Procedures
    o2 Inspection Criteria
    o3 Acceptance Test Procedure > T|Prepare Test Program|Acceptance Test Procedure
    o4 Approved Supplier List > P|Procure & Kit Materials|Order Components|Approved Supplier List
    m1 Quality Manager
    a1 Maintain Procedures & Standards
      i1 Regulatory & Standards Updates
      c1 Engineering Baseline
      o1 Quality Procedures
      m1 Quality Engineers
    a2 Author Acceptance & Inspection Criteria
      c1 Engineering Baseline
      c2 Quality Procedures
      o1 Acceptance Test Procedure
      o2 Inspection Criteria
      m1 Quality Engineers
    a3 Qualify & Audit Suppliers
      i1 Supplier Performance Data
      c1 Quality Procedures
      o1 Approved Supplier List
      m1 Supplier Quality Engineers
  a2 Inspect & Release Product
    i1 Accepted Drones < T|Disposition & Report|Accepted Drones
    i2 Test Records < T|Disposition & Report|Test Records
    c1 Quality Procedures
    c2 Inspection Criteria
    o1 Released Products > L|Warehouse Finished Goods|Released Products
    o2 Inspection NCRs
    m1 Quality Inspectors
    a1 Inspect Units & Records
      i1 Accepted Drones
      i2 Test Records
      c1 Inspection Criteria
      o1 Inspection Results
      o2 Inspection NCRs
      m1 Quality Inspectors
    a2 Disposition Release Decisions
      i1 Inspection Results
      c1 Quality Procedures
      o1 Release Decisions
      m1 Quality Manager
    a3 Certify & Release Products
      i1 Release Decisions
      i2 Accepted Drones
      o1 Released Products
      m1 Quality Inspectors
  a3 Manage Nonconformance & CAPA
    i1 Inspection NCRs
    i2 Field Complaints < S|Synthesize Feedback & Insights|Field Complaint Reports
    i3 Line Nonconformances < P|Build Products|Line Nonconformance Reports
    c1 Quality Procedures
    o1 CAPA Directives > P|Support Manufacturing Engineering|CAPA Directives
    o2 Closed CAPA Records
    m1 Quality Engineers
    a1 Log & Screen Quality Events
      i1 Inspection NCRs
      i2 Field Complaints
      i3 Line Nonconformances
      o1 Screened Quality Events
      m1 Quality Engineers
    a2 Run CAPA Cases
      i1 Screened Quality Events
      c1 Quality Procedures
      o1 Corrective Action Plans
      m1 Quality Engineers
      a1 Contain & Segregate
        i1 Screened Quality Events
        o1 Containment Actions
        m1 Quality Engineers
      a2 Investigate Root Cause
        i1 Containment Actions
        o1 Root Cause Reports
        m1 FA Lab
        a1 Reproduce Failure
          i1 Containment Actions
          o1 Reproduced Failures
          m1 FA Lab
        a2 Analyze Failed Units
          i1 Reproduced Failures
          o1 Failure Analyses
          m1 FA Lab
          a1 Perform Visual & X-Ray Inspection
            i1 Reproduced Failures
            o1 Localized Defects
            m1 X-Ray Station
          a2 Run Electrical Fault Isolation
            ## Bench FA on failed boards: flying-probe net mapping,
            ## component-level isolation, failure-mode
            ## characterization.\n Feeds verified root causes to the
            ## CAPA loop that closes back into Production.
            i1 Localized Defects
            o1 Isolated Faults
            m1 FA Lab
            a1 Map Failing Nets
              i1 Localized Defects
              o1 Failing-Net Maps
              m1 Flying-Probe Tester
            a2 Isolate Faulty Components
              i1 Failing-Net Maps
              o1 Component-Level Faults
              m1 FA Lab
            a3 Characterize Failure Mode
              i1 Component-Level Faults
              o1 Isolated Faults
              m1 FA Lab
          a3 Cross-Section & Materials Analysis
            i1 Isolated Faults
            o1 Failure Analyses
            m1 Metallurgy Lab
        a3 Confirm Root Cause
          i1 Failure Analyses
          o1 Root Cause Reports
          m1 Quality Engineers
      a3 Define Corrective Actions
        i1 Root Cause Reports
        c1 Quality Procedures
        o1 Corrective Action Plans
        m1 Quality Engineers
    a3 Track Effectiveness & Close
      i1 Corrective Action Plans
      o1 CAPA Directives
      o2 Closed CAPA Records
      m1 Quality Engineers
```

## Model C — Contracting & Sales (international; one-time contracts and

continuous supply arrangements)

SPINE: C2 Win Contracts -> C22 Develop Proposals -> C222 Price & Clear
the Deal -> C2222 Clear Export & Trade Compliance -> C22222 Screen
Parties & End Use -> C222221-3. The spine carries the deal flow:
qualified opportunities in; closed international contracts out. FPV
racing drones are export-sensitive goods, so party/end-use screening
sits on the critical path of every deal. Off-spine: market development
(C1) and contract fulfillment (C3) decompose one level.

Interfaces: Strategic Plan + Approved Budgets + Trade-Compliance
Policy < E; Spot Orders + Continuous Supply Schedule > P; Demand
Forecast > E (paired now). Pending: Delivery Orders > L; Shipment
Confirmations < L; Billing Milestones > F; Renewal & Upsell
Signals < S.

```idef0
tC Contracting & Sales
  a1 Develop Markets & Pipeline
    i1 Market Signals
    i2 Renewal & Upsell Signals < S|Synthesize Feedback & Insights|Renewal & Upsell Signals
    c1 Strategic Plan < E|Set Direction|Strategic Plan
    c2 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Qualified Opportunities
    m1 Sales Team
    a1 Build Market Presence
      i1 Market Signals
      c1 Strategic Plan
      o1 Race-Scene Presence
      m1 Sales Team
    a2 Develop Channel & Team Relationships
      i1 Market Signals
      o1 Channel Relationships
      m1 Sales Team
    a3 Maintain Opportunity Pipeline
      i1 Channel Relationships
      i2 Renewal & Upsell Signals
      o1 Qualified Opportunities
      m1 Sales Ops
  a2 Win Contracts
    i1 Qualified Opportunities
    c1 Trade-Compliance Policy
    c2 Pricing Policy
    o1 Closed Contracts
    m1 Sales Team
    a1 Scope Opportunity & Bid Decision
      i1 Qualified Opportunities
      o1 Bid Decisions
      m1 Sales Team
    a2 Develop Proposals
      i1 Bid Decisions
      c1 Trade-Compliance Policy
      c2 Pricing Policy
      o1 Submitted Proposals
      m1 Proposal Team
      a1 Define Solution & Supply Terms
        i1 Bid Decisions
        o1 Solution Definitions
        m1 Proposal Team
      a2 Price & Clear the Deal
        i1 Solution Definitions
        c1 Trade-Compliance Policy
        c2 Pricing Policy
        o1 Cleared Priced Offers
        m1 Proposal Team
        a1 Estimate Costs & Margins
          i1 Solution Definitions
          c1 Pricing Policy
          o1 Cost Estimates
          m1 Finance Partners
        a2 Clear Export & Trade Compliance
          i1 Solution Definitions
          c1 Trade-Compliance Policy < E|Manage Risk & Compliance|Trade-Compliance Policy
          o1 Export Clearances
          m1 Trade Compliance Officers
          a1 Classify Products & Destinations
            i1 Solution Definitions
            c1 Trade-Compliance Policy
            o1 Export Classifications
            m1 Trade Compliance Officers
          a2 Screen Parties & End Use
            i1 Export Classifications
            o1 Screening Results
            m1 Trade Compliance Officers
            a1 Run Denied-Party Screening
              i1 Export Classifications
              o1 Party Screening Hits
              m1 Screening Database
            a2 Verify End-Use & End-User Statements
              i1 Party Screening Hits
              o1 End-Use Verifications
              m1 Trade Compliance Officers
            a3 Assess Diversion Risk
              i1 End-Use Verifications
              o1 Screening Results
              m1 Trade Compliance Officers
          a3 Determine License Needs & File
            i1 Screening Results
            c1 Trade-Compliance Policy
            o1 Export Clearances
            m1 Trade Compliance Officers
        a3 Approve Pricing
          i1 Cost Estimates
          i2 Export Clearances
          c1 Pricing Policy
          o1 Cleared Priced Offers
          m1 Sales Leadership
      a3 Assemble & Submit Proposal
        i1 Cleared Priced Offers
        o1 Submitted Proposals
        m1 Proposal Team
    a3 Negotiate & Close
      i1 Submitted Proposals
      o1 Closed Contracts
      m1 Sales Leadership
  a3 Manage Contract Fulfillment
    i1 Closed Contracts
    i2 Shipment Confirmations < L|Ship Customer Orders|Shipment Confirmations
    o1 Spot Orders > P|Plan Production|Spot Orders
    o2 Continuous Supply Schedule > P|Plan Production|Continuous Supply Schedule
    o3 Delivery Orders > L|Ship Customer Orders|Delivery Orders
    o4 Demand Forecast > E|Plan & Allocate|Demand Forecast
    o5 Billing Milestones > F|Run Financial Operations|Billing Milestones
    m1 Sales Ops
    a1 Book Orders & Supply Schedules
      i1 Closed Contracts
      o1 Spot Orders
      o2 Continuous Supply Schedule
      o3 Booked Order Base
      m1 Sales Ops
    a2 Coordinate Deliveries & Billing
      i1 Booked Order Base
      i2 Shipment Confirmations
      o1 Delivery Orders
      o2 Billing Milestones
      m1 Sales Ops
    a3 Forecast Demand & Renewals
      i1 Booked Order Base
      o1 Demand Forecast
      m1 Sales Ops
```

## Model L — Logistics & Shipping (racing drone company)

SPINE: L3 Ship Customer Orders -> L32 Process Export Shipments -> L322
Prepare Export Documentation -> L3222 File Export Declarations ->
L32222 Submit Customs Filings -> L322221-3. The spine carries the
outbound flow: released products and delivery orders in; shipped,
customs-cleared international orders out. Lithium-battery dangerous-
goods documentation and export filings dominate the paperwork path
for an international drone shipper. Off-spine: inbound freight (L1)
and finished-goods warehousing (L2) decompose one level.

Interfaces: Trade-Compliance Policy + Approved Budgets < E; Inbound
Component Deliveries > P; Released Products < Q; Delivery Orders < C;
Shipment Confirmations > C (paired now). Pending: Shipping & Freight
Documents > F.

```idef0
tL Logistics & Shipping
  a1 Receive Inbound Freight
    i1 Supplier Shipments
    o1 Inbound Component Deliveries > P|Procure & Kit Materials|Inbound Component Deliveries
    m1 Receiving Dock
    a1 Unload & Check Freight
      i1 Supplier Shipments
      o1 Checked Freight
      m1 Receiving Dock
    a2 Clear Import Customs
      i1 Checked Freight
      o1 Cleared Goods
      m1 Customs Broker
    a3 Deliver to Production Stores
      i1 Cleared Goods
      o1 Inbound Component Deliveries
      m1 Forklift Crew
  a2 Warehouse Finished Goods
    i1 Released Products < Q|Inspect & Release Product|Released Products
    o1 Staged Finished Goods
    m1 Warehouse Crew
    a1 Put Away Released Stock
      i1 Released Products
      o1 Stored Stock
      m1 Warehouse Crew
    a2 Count & Reconcile Inventory
      i1 Stored Stock
      o1 Inventory Records
      m1 WMS Terminals
    a3 Stage Orders for Shipment
      i1 Stored Stock
      o1 Staged Finished Goods
      m1 Warehouse Crew
  a3 Ship Customer Orders
    i1 Staged Finished Goods
    i2 Delivery Orders < C|Manage Contract Fulfillment|Delivery Orders
    c1 Trade-Compliance Policy < E|Manage Risk & Compliance|Trade-Compliance Policy
    c2 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Shipped Orders
    o2 Shipment Confirmations > C|Manage Contract Fulfillment|Shipment Confirmations
    o3 Shipping & Freight Documents > F|Run Financial Operations|Shipping & Freight Documents
    m1 Shipping Crew
    a1 Plan Shipments & Book Carriers
      i1 Delivery Orders
      o1 Shipment Plans
      m1 Freight Forwarders
    a2 Process Export Shipments
      i1 Shipment Plans
      i2 Staged Finished Goods
      c1 Trade-Compliance Policy
      o1 Tendered Shipments
      o2 Shipping & Freight Documents
      m1 Shipping Crew
      a1 Pick & Pack Orders
        i1 Shipment Plans
        i2 Staged Finished Goods
        o1 Packed Shipments
        m1 Packing Stations
      a2 Prepare Export Documentation
        i1 Packed Shipments
        c1 Trade-Compliance Policy
        o1 Documented Shipments
        o2 Shipping & Freight Documents
        m1 Export Documentation Team
        a1 Prepare Commercial Invoice & Packing List
          i1 Packed Shipments
          o1 Commercial Documents
          m1 Export Documentation Team
        a2 File Export Declarations
          i1 Commercial Documents
          c1 Trade-Compliance Policy
          o1 Filed Declarations
          m1 Export Documentation Team
          a1 Validate License & Screening Data
            i1 Commercial Documents
            c1 Trade-Compliance Policy
            o1 Validated Filing Inputs
            m1 Export Documentation Team
          a2 Submit Customs Filings
            i1 Validated Filing Inputs
            o1 Filing Acknowledgments
            m1 Customs Filing System
            a1 Assemble Filing Data Set
              i1 Validated Filing Inputs
              o1 Filing Data Sets
              m1 Customs Filing System
            a2 Transmit Export & Destination Filings
              i1 Filing Data Sets
              o1 Transmitted Filings
              m1 Customs Filing System
            a3 Archive Filing Acknowledgments
              i1 Transmitted Filings
              o1 Filing Acknowledgments
              m1 Document Archive
          a3 Resolve Filing Exceptions
            i1 Filing Acknowledgments
            o1 Filed Declarations
            m1 Export Documentation Team
        a3 Compile Battery & Dangerous-Goods Docs
          i1 Filed Declarations
          o1 Documented Shipments
          o2 Shipping & Freight Documents
          m1 DG-Certified Packers
      a3 Tender to Carrier
        i1 Documented Shipments
        o1 Tendered Shipments
        m1 Freight Carriers
    a3 Track & Confirm Delivery
      i1 Tendered Shipments
      o1 Shipped Orders
      o2 Shipment Confirmations
      m1 Tracking Systems
```

## Model S — Customer Support & Feedback (racing drone company)

SPINE: S2 Resolve Customer Cases -> S22 Execute Repairs & RMAs -> S222
Process Returned Units -> S2222 Repair Units -> S22222 Execute Repairs
-> S222221-3. The spine carries the case-resolution flow: support
cases and returned crash-damaged units in; resolved cases and repaired
or replacement units out. Racing drones crash, so the repair bench is
the heart of support. Off-spine: channel operations (S1) and feedback
synthesis (S3) decompose one level.

Interfaces: Approved Budgets < E; Customer Feedback > R; Field
Complaint Reports > Q (renamed Field Complaints at the Q boundary);
Renewal & Upsell Signals > C (all paired now).

```idef0
tS Customer Support & Feedback
  a1 Operate Support Channels
    i1 Customer Contacts
    c1 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Support Cases
    m1 Support Agents
    a1 Run Help Desk & Community Channels
      i1 Customer Contacts
      o1 Logged Contacts
      m1 Support Agents
    a2 Publish Guides & Firmware Notes
      o1 Knowledge Base Articles
      m1 Technical Writers
    a3 Open Support Cases
      i1 Logged Contacts
      o1 Support Cases
      m1 Support Agents
  a2 Resolve Customer Cases
    i1 Support Cases
    i2 Returned Units
    c1 Warranty Policy
    o1 Resolved Cases
    o2 Outbound Replacements
    m1 Support Technicians
    a1 Triage & Diagnose Cases
      i1 Support Cases
      c1 Warranty Policy
      o1 Triaged Cases
      m1 Support Agents
    a2 Execute Repairs & RMAs
      i1 Triaged Cases
      i2 Returned Units
      c1 Warranty Policy
      o1 Completed RMAs
      o2 Outbound Replacements
      m1 Support Technicians
      a1 Authorize Returns
        i1 Triaged Cases
        c1 Warranty Policy
        o1 Return Authorizations
        m1 Support Agents
      a2 Process Returned Units
        i1 Return Authorizations
        i2 Returned Units
        o1 Serviced Units
        m1 Support Technicians
        a1 Receive & Log Returns
          i1 Return Authorizations
          i2 Returned Units
          o1 Logged Returns
          m1 Support Technicians
        a2 Repair Units
          i1 Logged Returns
          o1 Repaired Units
          m1 Repair Bench
          a1 Diagnose Faults
            i1 Logged Returns
            o1 Fault Diagnoses
            m1 Repair Bench
          a2 Execute Repairs
            i1 Fault Diagnoses
            o1 Completed Repairs
            m1 Repair Bench
            a1 Replace Damaged Modules
              i1 Fault Diagnoses
              o1 Module Replacements
              m1 Repair Bench
            a2 Rework Solder & Connectors
              i1 Module Replacements
              o1 Reworked Units
              m1 Solder Stations
            a3 Rebind & Configure Electronics
              i1 Reworked Units
              o1 Completed Repairs
              m1 Repair Bench
          a3 Verify & Reflash Units
            i1 Completed Repairs
            o1 Repaired Units
            m1 Repair Bench
        a3 QC & Restock or Scrap
          i1 Repaired Units
          o1 Serviced Units
          m1 Support Technicians
      a3 Close RMAs & Ship Replacements
        i1 Serviced Units
        o1 Completed RMAs
        o2 Outbound Replacements
        m1 Support Technicians
    a3 Close Cases & Follow Up
      i1 Completed RMAs
      o1 Resolved Cases
      m1 Support Agents
  a3 Synthesize Feedback & Insights
    i1 Resolved Cases
    o1 Customer Feedback > R|Define Product Requirements|Gather Race-Team & Market Inputs|Customer Feedback
    o2 Field Complaint Reports > Q|Manage Nonconformance & CAPA|Field Complaints
    o3 Renewal & Upsell Signals > C|Develop Markets & Pipeline|Renewal & Upsell Signals
    m1 Support Analysts
    a1 Mine Case & Telemetry Data
      i1 Resolved Cases
      o1 Case Analytics
      m1 Support Analysts
    a2 Identify Product Issues & Trends
      i1 Case Analytics
      o1 Issue Trend Reports
      o2 Field Complaint Reports
      m1 Support Analysts
    a3 Publish Feedback & Signals
      i1 Issue Trend Reports
      o1 Customer Feedback
      o2 Renewal & Upsell Signals
      m1 Support Analysts
```

## Model F — Finance (racing drone company)

SPINE: F2 Run Financial Operations -> F22 Process Order-to-Cash ->
F222 Collect Receivables -> F2222 Run Collection Actions -> F22222
Negotiate Payment Arrangements -> F222221-3. The spine carries the
cash flow: billing milestones and shipping documents in; collected,
reconciled cash out. International B2B sales to race teams and
distributors on credit terms make collections a real discipline.
Off-spine: budget stewardship (F1) and close-and-report (F3)
decompose one level.

Interfaces: Approved Budgets + Performance Targets < E; Budget Policy
+ Planning Calendar + Department Budget Requests + Financial
Statements & KPIs > E; Billing Milestones < C; Shipping & Freight
Documents < L (paired now). Pending: Payroll Inputs < H.

```idef0
tF Finance
  a1 Plan & Steward Budgets
    i1 Department Budget Submissions
    c1 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Budget Policy > E|Plan & Allocate|Budget Policy
    o2 Planning Calendar > E|Plan & Allocate|Planning Calendar
    o3 Department Budget Requests > E|Plan & Allocate|Department Budget Requests
    m1 FP&A Partners
    a1 Issue Budget Policy & Calendar
      c1 Approved Budgets
      o1 Budget Policy
      o2 Planning Calendar
      m1 FP&A Partners
    a2 Consolidate Budget Requests
      i1 Department Budget Submissions
      c1 Budget Policy
      o1 Department Budget Requests
      m1 FP&A Partners
    a3 Monitor Budget Execution
      i1 Financial Statements & KPIs
      c1 Approved Budgets
      o1 Budget Variance Alerts
      m1 FP&A Partners
  a2 Run Financial Operations
    i1 Billing Milestones < C|Manage Contract Fulfillment|Billing Milestones
    i2 Shipping & Freight Documents < L|Ship Customer Orders|Shipping & Freight Documents
    i3 Supplier Invoices
    i4 Payroll Inputs
    c1 Financial Controls Policy
    o1 Posted Transactions
    m1 Accounting Team
    a1 Process Procure-to-Pay
      i1 Supplier Invoices
      c1 Financial Controls Policy
      o1 Supplier Payments
      o2 Posted Transactions
      m1 Accounts Payable Clerks
    a2 Process Order-to-Cash
      i1 Billing Milestones
      i2 Shipping & Freight Documents
      c1 Financial Controls Policy
      o1 Collected Cash
      o2 Posted Transactions
      m1 Accounts Receivable Clerks
      a1 Invoice Customers
        i1 Billing Milestones
        i2 Shipping & Freight Documents
        o1 Issued Invoices
        m1 Billing System
      a2 Collect Receivables
        i1 Issued Invoices
        c1 Financial Controls Policy
        o1 Collected Cash
        m1 Accounts Receivable Clerks
        a1 Monitor Aging & Prioritize
          i1 Issued Invoices
          o1 Prioritized Collections
          m1 AR Aging Reports
        a2 Run Collection Actions
          i1 Prioritized Collections
          o1 Secured Payments
          m1 Accounts Receivable Clerks
          a1 Send Dunning Notices
            i1 Prioritized Collections
            o1 Dunning Responses
            m1 Billing System
          a2 Negotiate Payment Arrangements
            i1 Dunning Responses
            o1 Payment Arrangements
            m1 Credit Analysts
            a1 Assess Customer Credit Position
              i1 Dunning Responses
              o1 Credit Assessments
              m1 Credit Analysts
            a2 Structure Payment Plans
              i1 Credit Assessments
              o1 Structured Plans
              m1 Credit Analysts
            a3 Document & Monitor Arrangements
              i1 Structured Plans
              o1 Payment Arrangements
              m1 Credit Analysts
          a3 Coordinate Credit Holds
            i1 Payment Arrangements
            o1 Secured Payments
            m1 Credit Analysts
        a3 Resolve Disputes & Write-Offs
          i1 Secured Payments
          o1 Collected Cash
          m1 Accounts Receivable Clerks
      a3 Apply & Reconcile Cash
        i1 Collected Cash
        o1 Posted Transactions
        m1 Accounting Team
    a3 Run Payroll
      i1 Payroll Inputs < H|Administer HR Operations|Payroll Inputs
      c1 Financial Controls Policy
      o1 Payroll Payments
      o2 Posted Transactions
      m1 Payroll System
  a3 Close Books & Report
    i1 Posted Transactions
    c1 Performance Targets < E|Plan & Allocate|Issue Budgets & Targets|Performance Targets
    o1 Financial Statements & KPIs > E|Plan & Allocate|Financial Statements & KPIs
    m1 Controllers
    a1 Close Ledgers
      i1 Posted Transactions
      o1 Closed Ledgers
      m1 Controllers
    a2 Consolidate & Analyze Results
      i1 Closed Ledgers
      c1 Performance Targets
      o1 Analyzed Results
      m1 Controllers
    a3 Publish Statements & KPIs
      i1 Analyzed Results
      o1 Financial Statements & KPIs
      m1 Controllers
```

## Model H — Human Resources (racing drone company)

SPINE: H2 Staff & Develop Workforce -> H22 Train & Certify Workforce
-> H222 Run Certification Programs -> H2221 Certify Assembly & Solder
Operators -> H22212 Administer Practical Assessments -> H222121-3.
The spine carries the workforce flow: candidates and hires in;
certified, deployed staff out to Production and Testing. IPC-style
solder certification with practical workmanship assessment is a real
gate for electronics manufacturing staff. Off-spine: workforce
planning (H1) and HR operations (H3) decompose one level.

Interfaces: Approved Budgets < E; Staffed Production Workforce > P
(renamed Production Crew at the P boundary); Certified Test Pilots >
T (renamed Test Pilots at the T boundary); Payroll Inputs > F (all
paired now -- this completes the ten-model set).

```idef0
tH Human Resources
  a1 Plan Workforce & Organization
    i1 Headcount Demand Signals
    c1 Approved Budgets < E|Plan & Allocate|Issue Budgets & Targets|Approved Budgets
    o1 Workforce Plan
    m1 HR Business Partners
    a1 Plan Headcount & Skills
      i1 Headcount Demand Signals
      c1 Approved Budgets
      o1 Headcount Plan
      m1 HR Business Partners
    a2 Design Organization & Roles
      i1 Headcount Plan
      o1 Role Definitions
      m1 HR Business Partners
    a3 Set Compensation Structures
      i1 Role Definitions
      o1 Workforce Plan
      m1 Compensation Analysts
  a2 Staff & Develop Workforce
    i1 Workforce Plan
    i2 Candidate Pool
    c1 Certification Standards
    o1 Staffed Production Workforce > P|Build Products|Production Crew
    o2 Certified Test Pilots > T|Execute Acceptance Tests|Test Pilots
    o3 Staffed Teams
    m1 HR Team
    a1 Recruit & Hire
      i1 Workforce Plan
      i2 Candidate Pool
      o1 New Hires
      m1 Recruiters
      a1 Source Candidates
        i1 Candidate Pool
        c1 Workforce Plan
        o1 Candidate Slates
        m1 Recruiters
      a2 Interview & Select
        i1 Candidate Slates
        o1 Selected Candidates
        m1 Hiring Panels
      a3 Onboard New Hires
        i1 Selected Candidates
        o1 New Hires
        m1 HR Team
    a2 Train & Certify Workforce
      i1 New Hires
      c1 Certification Standards
      o1 Staffed Production Workforce
      o2 Certified Test Pilots
      o3 Staffed Teams
      m1 Training Staff
      a1 Maintain Training Curricula
        i1 Qualification Records
        c1 Certification Standards
        o1 Training Curricula
        m1 Training Staff
      a2 Run Certification Programs
        i1 New Hires
        c1 Training Curricula
        o1 Certified Personnel
        m1 Training Staff
        a1 Certify Assembly & Solder Operators
          i1 New Hires
          c1 Training Curricula
          o1 Certified Personnel
          m1 IPC Trainers
          a1 Deliver Skills Training
            i1 New Hires
            c1 Training Curricula
            o1 Trained Candidates
            m1 IPC Trainers
          a2 Administer Practical Assessments
            i1 Trained Candidates
            o1 Assessment Results
            m1 Assessment Stations
            a1 Stage Assessment Stations
              i1 Trained Candidates
              o1 Staged Assessments
              m1 Assessment Stations
            a2 Score Workmanship Samples
              i1 Staged Assessments
              o1 Scored Samples
              m1 IPC Trainers
            a3 Adjudicate & Record Results
              i1 Scored Samples
              o1 Assessment Results
              m1 Certification Registrar
          a3 Issue & Record Certifications
            i1 Assessment Results
            o1 Certified Personnel
            m1 Certification Registrar
        a2 Certify Test Pilots
          i1 New Hires
          c1 Training Curricula
          o1 Certified Personnel
          m1 Chief Test Pilot
        a3 Certify Compliance & Export Handlers
          i1 New Hires
          c1 Training Curricula
          o1 Certified Personnel
          m1 Trade Compliance Officers
      a3 Track Qualifications & Deploy Staff
        i1 Certified Personnel
        o1 Qualification Records
        o2 Staffed Production Workforce
        o3 Certified Test Pilots
        o4 Staffed Teams
        m1 Training Staff
    a3 Manage Performance & Retention
      i1 Qualification Records
      o1 Performance & Retention Actions
      m1 HR Business Partners
  a3 Administer HR Operations
    i1 Time & Attendance Records
    i2 Employee Records
    o1 Payroll Inputs > F|Run Financial Operations|Run Payroll|Payroll Inputs
    m1 HR Operations Team
    a1 Compile Payroll Inputs
      i1 Time & Attendance Records
      o1 Payroll Inputs
      m1 HR Operations Team
    a2 Administer Benefits & Records
      i1 Employee Records
      o1 Benefits Enrollments
      m1 HR Operations Team
    a3 Ensure Labor & Safety Compliance
      i1 Employee Records
      c1 Labor & Safety Regulations
      o1 Compliance Filings
      m1 HR Operations Team
```
