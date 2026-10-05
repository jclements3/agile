<!-- Notional demo model set for idef0-kit training.
     Build:  idef0lint halberd.md
             idef2html halberd.md > out/plates.html
             idef0.pl links halberd.md > out/INTERFACES              -->

# Halberd Interceptor Program — IDEF0 model set (notional)

A **fictional** ballistic-missile-interceptor acquisition program,
modeled at the program-management / work-breakdown level: organizations,
activities, and the artifacts that flow between them. It contains no
performance parameters, design data, or real program information; the
structure follows the public shape of a MIL-STD-881 missile WBS and a
DoD 5000-style acquisition lifecycle.

Seven models, one per organization. Cross-model interfaces are paired
explicitly (`<` on the consumer, `>` on the producer). `Authorized
Funding` is a hub-and-spoke fan-out from the program office to every
performing organization, like DroneCorp's `Approved Budgets`. One flow
is renamed at a boundary: `Delivered Interceptors` (M) arrives at
Logistics as `Interceptor Deliveries` (L).

## Model G — Government Program Office

The program office owns requirements, money, and milestone decisions.
SPINE: G3 Oversee Program Execution -> G33 Conduct Milestone Reviews ->
G331-3. Status reports and test reports come in; milestone decisions
(including the production decision) go out.

```idef0
tG Government Program Office
## **Government Program Office** -- the acquisition authority. Owns
## requirements, funding, and milestone decisions; every other model
## is a performing organization under its oversight.\n *Notional
## model for training only.*
  a1 Define Capability Requirements
    i1 Threat Assessments
    i2 Warfighter Needs
    c1 Defense Acquisition Policy
    o1 Capability Requirements > E|Engineer the System|Capability Requirements
    m1 Requirements Office
    a1 Analyze Threat Environment
      i1 Threat Assessments
      o1 Threat Baseline
      m1 Intelligence Analysts
    a2 Derive Capability Gaps
      i1 Threat Baseline
      i2 Warfighter Needs
      o1 Capability Gaps
      m1 Requirements Office
    a3 Validate Requirements Document
      i1 Capability Gaps
      c1 Defense Acquisition Policy
      o1 Capability Requirements
      m1 Requirements Oversight Council
  a2 Manage Program Funding
    i1 Congressional Appropriations
    i2 Budget Estimates
    c1 Defense Acquisition Policy
    o1 Authorized Funding > E|Engineer the System|Authorized Funding
      ## The **funding hub**: one representative `>` link, and every
      ## performing organization (E V B T M L) declares a `<` control
      ## back to this port.
    m1 Financial Management Office
    a1 Build Budget Submission
      i1 Budget Estimates
      c1 Defense Acquisition Policy
      o1 Budget Submission
      m1 Financial Management Office
    a2 Execute Appropriations
      i1 Congressional Appropriations
      i2 Budget Submission
      o1 Funding Allotments
      m1 Financial Management Office
    a3 Obligate Contract Funds
      i1 Funding Allotments
      o1 Authorized Funding
      m1 Contracting Officer
  a3 Oversee Program Execution
    i1 Program Status Reports < E|Manage Technical Program|Program Status Reports
    i2 Test Reports < T|Evaluate Performance|Test Reports
    c1 Capability Requirements
    c2 Defense Acquisition Policy
    o1 Budget Estimates
    o2 Milestone Decisions > M|Plan Production|Milestone Decisions
    m1 Program Manager
    a1 Track Earned Value
      i1 Program Status Reports
      o1 Earned Value Assessments
      m1 Cost Analysts
    a2 Assess Program Risk
      i1 Test Reports
      i2 Earned Value Assessments
      c1 Capability Requirements
      o1 Risk Assessments
      o2 Budget Estimates
      m1 Program Manager
    a3 Conduct Milestone Reviews
      i1 Risk Assessments
      c1 Defense Acquisition Policy
      o1 Milestone Decisions
      m1 Milestone Decision Authority
      a1 Verify Entrance Criteria
        i1 Risk Assessments
        c1 Defense Acquisition Policy
        o1 Review Package
        m1 Program Manager
      a2 Convene Review Board
        i1 Review Package
        o1 Board Recommendations
        m1 Milestone Decision Authority
      a3 Issue Decision Memorandum
        i1 Board Recommendations
        o1 Milestone Decisions
        m1 Milestone Decision Authority
        ## The Acquisition Decision Memorandum. At the production
        ## milestone this authorizes **Manufacturing** to start lots.
```

## Model E — Systems Engineering & Integration

The prime contractor's SE&I team turns capability requirements into
segment specifications, integrates segment deliveries, and reports
status. SPINE: E1 Engineer the System -> E12 Architect the System ->
E122 Define Functional Architecture -> E1222 Allocate Functions to
Segments -> E12221-3.

```idef0
tE Systems Engineering & Integration
## Prime-contractor **SE&I**: requirements, architecture, interfaces,
## integration, and technical program management.
  a1 Engineer the System
    i1 Capability Requirements < G|Define Capability Requirements|Capability Requirements
    i2 Test Reports < T|Evaluate Performance|Test Reports
    i3 Field Reliability Data < L|Sustain Fielded Inventory|Field Reliability Data
    c1 Authorized Funding < G|Manage Program Funding|Authorized Funding
    c2 Systems Engineering Plan
    o1 Interceptor Specification > V|Design Interceptor|Interceptor Specification
    o2 Fire Control Specification > B|Develop Fire Control|Fire Control Specification
    o3 Verification Requirements > T|Plan Test Program|Verification Requirements
    m1 Systems Engineers
    a1 Analyze Requirements
      i1 Capability Requirements
      i2 Test Reports
      i3 Field Reliability Data
      c1 Systems Engineering Plan
      o1 System Requirements
      m1 Systems Engineers
    a2 Architect the System
      i1 System Requirements
      c1 Systems Engineering Plan
      o1 Segment Allocations
      o2 Interface Control Documents
      m1 Chief Engineer
      a1 Define Operational Concept
        i1 System Requirements
        o1 Operational Concept
        m1 Systems Engineers
      a2 Define Functional Architecture
        i1 Operational Concept
        i2 System Requirements
        c1 Systems Engineering Plan
        o1 Segment Allocations
        m1 Chief Engineer
        a1 Decompose System Functions
          i1 Operational Concept
          o1 Function Hierarchy
          m1 MBSE Tools
        a2 Allocate Functions to Segments
          i1 Function Hierarchy
          i2 System Requirements
          c1 Systems Engineering Plan
          o1 Segment Allocations
          m1 Chief Engineer
          ## Where the **Solutions Architect** role lives: cross-segment
          ## allocation decisions no single segment team can make alone.
          a1 Allocate Interceptor Functions
            i1 Function Hierarchy
            o1 Interceptor Allocations
            m1 Interceptor Segment Lead
          a2 Allocate Fire Control Functions
            i1 Function Hierarchy
            o1 Fire Control Allocations
            m1 Fire Control Segment Lead
          a3 Reconcile Segment Budgets
            i1 Interceptor Allocations
            i2 Fire Control Allocations
            c1 Systems Engineering Plan
            o1 Segment Allocations
            m1 Chief Engineer
      a3 Define Interface Control Documents
        i1 Segment Allocations
        o1 Interface Control Documents
        m1 Interface Engineers
    a3 Write Segment Specifications
      i1 Segment Allocations
      i2 Interface Control Documents
      o1 Interceptor Specification
      o2 Fire Control Specification
      o3 Verification Requirements
      m1 Specification Writers
  a2 Integrate & Verify System
    i1 Interceptor Design Baseline < V|Design Interceptor|Interceptor Design Baseline
    i2 Fire Control Software Build < B|Develop Fire Control|Fire Control Software Build
    c1 Interface Control Documents
    c2 Verification Requirements
    o1 Integrated System Baseline > M|Plan Production|Integrated System Baseline
    o2 Integration Issues
    m1 Integration Engineers
    a1 Run Hardware-in-the-Loop Integration
      i1 Interceptor Design Baseline
      i2 Fire Control Software Build
      c1 Interface Control Documents
      o1 Integrated Configurations
      m1 HWIL Facility
    a2 Verify Interfaces
      i1 Integrated Configurations
      c1 Interface Control Documents
      o1 Interface Verification Results
      o2 Integration Issues
      m1 Integration Engineers
    a3 Baseline System Configuration
      i1 Interface Verification Results
      c1 Verification Requirements
      o1 Integrated System Baseline
      m1 Configuration Management Board
  a3 Manage Technical Program
    i1 Integration Issues
    i2 Cost & Schedule Actuals
    c1 Authorized Funding
    o1 Program Status Reports > G|Oversee Program Execution|Program Status Reports
    o2 Systems Engineering Plan
    m1 Contractor Program Manager
    a1 Maintain Systems Engineering Plan
      c1 Authorized Funding
      o1 Systems Engineering Plan
      m1 Chief Engineer
    a2 Track Cost & Schedule
      i1 Cost & Schedule Actuals
      o1 Earned Value Data
      m1 Program Control Analysts
    a3 Report Program Status
      i1 Earned Value Data
      i2 Integration Issues
      o1 Program Status Reports
      m1 Contractor Program Manager
```

## Model V — Interceptor Development

The interceptor segment designs the vehicle, builds development units
for flight test, and releases the technical data package to
manufacturing. SPINE: V1 Design Interceptor -> V12 Design Kill Vehicle
-> V122 Develop Seeker Assembly -> V1222 Develop Seeker Processing ->
V12221-3.

```idef0
tV Interceptor Development
## **Interceptor segment**: design, development units, and the
## technical data package. Structure only -- no design content.
  a1 Design Interceptor
    i1 Interceptor Specification < E|Engineer the System|Interceptor Specification
    i2 Supplier Component Data
    c1 Authorized Funding < G|Manage Program Funding|Authorized Funding
    o1 Interceptor Design Baseline > E|Integrate & Verify System|Interceptor Design Baseline
    o2 Interceptor Design Data
    m1 Vehicle Design Team
    a1 Define Interceptor Architecture
      i1 Interceptor Specification
      o1 Interceptor Architecture
      m1 Vehicle Design Team
    a2 Design Kill Vehicle
      i1 Interceptor Architecture
      i2 Supplier Component Data
      o1 Kill Vehicle Design
      m1 Kill Vehicle Engineers
      a1 Design Kill Vehicle Structure
        i1 Interceptor Architecture
        o1 Structure Design
        m1 Structural Engineers
      a2 Develop Seeker Assembly
        i1 Interceptor Architecture
        i2 Supplier Component Data
        o1 Seeker Design
        m1 Seeker Engineers
        a1 Allocate Seeker Requirements
          i1 Interceptor Architecture
          o1 Seeker Requirements
          m1 Seeker Engineers
        a2 Develop Seeker Processing
          i1 Seeker Requirements
          o1 Seeker Processing Design
          m1 Seeker Engineers
          a1 Build Seeker Simulation Models
            i1 Seeker Requirements
            o1 Seeker Models
            m1 Digital Simulation Lab
          a2 Implement Processing Software
            i1 Seeker Models
            o1 Processing Software Build
            m1 Seeker Software Engineers
          a3 Validate Processing in Simulation
            i1 Processing Software Build
            i2 Seeker Models
            o1 Seeker Processing Design
            m1 Digital Simulation Lab
            ## Digital simulation gates the software before any
            ## hardware-in-the-loop time is spent.
        a3 Integrate & Characterize Seeker
          i1 Seeker Processing Design
          i2 Supplier Component Data
          o1 Seeker Design
          m1 Seeker Test Chamber
      a3 Integrate Kill Vehicle Design
        i1 Structure Design
        i2 Seeker Design
        o1 Kill Vehicle Design
        m1 Kill Vehicle Engineers
    a3 Integrate Booster & Avionics Design
      i1 Kill Vehicle Design
      i2 Supplier Component Data
      o1 Interceptor Design Data
      m1 Vehicle Design Team
    a4 Conduct Design Reviews
      i1 Interceptor Design Data
      c1 Interceptor Specification
      o1 Interceptor Design Baseline
      m1 Design Review Board
  a2 Build Development Units
    i1 Interceptor Design Data
    c1 Authorized Funding
    o1 Test Interceptors > T|Conduct Flight Tests|Test Interceptors
    m1 Development Shop
    a1 Fabricate Development Hardware
      i1 Interceptor Design Data
      o1 Development Hardware
      m1 Development Shop
    a2 Assemble Test Articles
      i1 Development Hardware
      o1 Assembled Test Articles
      m1 Integration & Test Crew
    a3 Instrument Test Articles
      i1 Assembled Test Articles
      o1 Test Interceptors
      m1 Telemetry Technicians
  a3 Release Technical Data Package
    i1 Interceptor Design Baseline
    i2 Qualification Results < T|Evaluate Performance|Qualification Results
    c1 Configuration Management Plan
    o1 Technical Data Package > M|Plan Production|Technical Data Package
    m1 Configuration Managers
    a1 Compile Drawings & Specifications
      i1 Interceptor Design Baseline
      o1 Draft Data Package
      m1 Configuration Managers
    a2 Incorporate Qualification Results
      i1 Draft Data Package
      i2 Qualification Results
      o1 Qualified Data Package
      m1 Design Engineers
    a3 Release Controlled Data
      i1 Qualified Data Package
      c1 Configuration Management Plan
      o1 Technical Data Package
      m1 Configuration Managers
```

## Model B — Battle Management & Fire Control

The fire-control segment develops software in agile increments and
sustains fielded builds. SPINE: B1 Develop Fire Control -> B12 Develop
Software Increments -> B122 Implement Mission Functions -> B1221-3.

```idef0
tB Battle Management & Fire Control
## **Fire-control software segment**, run as an agile team-of-teams:
## backlog, increments, continuous integration.
  a1 Develop Fire Control
    i1 Fire Control Specification < E|Engineer the System|Fire Control Specification
    i2 Sensor Interface Data
    c1 Authorized Funding < G|Manage Program Funding|Authorized Funding
    o1 Fire Control Software Build > E|Integrate & Verify System|Fire Control Software Build
    m1 Fire Control Software Team
    a1 Define Software Requirements
      i1 Fire Control Specification
      o1 Software Requirements
      m1 Software Systems Engineers
    a2 Develop Software Increments
      i1 Software Requirements
      i2 Sensor Interface Data
      c1 Software Development Plan
      o1 Software Increments
      m1 Fire Control Software Team
      a1 Plan Increment Backlog
        i1 Software Requirements
        o1 Increment Backlog
        m1 Product Owner
      a2 Implement Mission Functions
        i1 Increment Backlog
        i2 Sensor Interface Data
        o1 Implemented Functions
        m1 Development Teams
        a1 Implement Track Management
          i1 Increment Backlog
          i2 Sensor Interface Data
          o1 Track Services
          m1 Development Teams
        a2 Implement Engagement Planning
          i1 Track Services
          o1 Engagement Planning Services
          m1 Development Teams
        a3 Implement Operator Displays
          i1 Engagement Planning Services
          o1 Implemented Functions
          m1 User Interface Team
      a3 Integrate Increment
        i1 Implemented Functions
        c1 Software Development Plan
        o1 Software Increments
        m1 Continuous Integration Pipeline
    a3 Qualify Software Build
      i1 Software Increments
      o1 Fire Control Software Build
      m1 Software Test Team
  a2 Sustain Fire Control Software
    i1 Software Problem Reports < L|Sustain Fielded Inventory|Software Problem Reports
    i2 Fire Control Software Build
    o1 Software Maintenance Releases > L|Sustain Fielded Inventory|Software Maintenance Releases
    m1 Software Sustainment Team
    a1 Triage Problem Reports
      i1 Software Problem Reports
      o1 Prioritized Defects
      m1 Software Sustainment Team
    a2 Develop Corrections
      i1 Prioritized Defects
      i2 Fire Control Software Build
      o1 Corrected Builds
      m1 Software Sustainment Team
    a3 Release Maintenance Builds
      i1 Corrected Builds
      o1 Software Maintenance Releases
      m1 Software Configuration Managers
```

## Model T — Test & Evaluation

Test plans events, flies them on a test range, and evaluates results
against pre-flight predictions. SPINE: T2 Conduct Flight Tests -> T22
Execute Flight Test Mission -> T223 Fly Mission & Collect Data ->
T2231-3.

```idef0
tT Test & Evaluation
## **Test & Evaluation**: plan, predict, fly, evaluate. Modeling and
## simulation predictions are made *before* every flight and compared
## after it.
  a1 Plan Test Program
    i1 Verification Requirements < E|Engineer the System|Verification Requirements
    c1 Authorized Funding < G|Manage Program Funding|Authorized Funding
    c2 Range Safety Requirements
    o1 Test Plans
    m1 Test Planning Cell
    a1 Develop Test Strategy
      i1 Verification Requirements
      o1 Test Strategy
      m1 Test Planning Cell
    a2 Design Test Events
      i1 Test Strategy
      c1 Range Safety Requirements
      o1 Test Event Designs
      m1 Test Planning Cell
    a3 Coordinate Range Resources
      i1 Test Event Designs
      o1 Test Plans
      m1 Range Coordinators
  a2 Conduct Flight Tests
    i1 Test Interceptors < V|Build Development Units|Test Interceptors
    i2 Fire Control Software Build < B|Develop Fire Control|Fire Control Software Build
    i3 Production Lot Samples < M|Produce Interceptors|Production Lot Samples
    c1 Test Plans
    c2 Range Safety Requirements
    o1 Flight Test Data
    o2 Quick-Look Reports
    m1 Test Range
    a1 Predict Test Outcomes
      i1 Fire Control Software Build
      c1 Test Plans
      o1 Pre-Flight Predictions
      m1 Digital Simulation Lab
    a2 Execute Flight Test Mission
      i1 Test Interceptors
      i2 Production Lot Samples
      i3 Pre-Flight Predictions
      c1 Test Plans
      c2 Range Safety Requirements
      o1 Flight Test Data
      m1 Test Range
      a1 Prepare Test Article & Range
        i1 Test Interceptors
        i2 Production Lot Samples
        c1 Range Safety Requirements
        o1 Ready Test Configuration
        m1 Range Crew
      a2 Conduct Mission Countdown
        i1 Ready Test Configuration
        c1 Test Plans
        o1 Mission Go Decision
        m1 Test Director
      a3 Fly Mission & Collect Data
        i1 Mission Go Decision
        i2 Pre-Flight Predictions
        c1 Range Safety Requirements
        o1 Flight Test Data
        m1 Range Instrumentation
        a1 Launch Target Vehicle
          i1 Mission Go Decision
          o1 Target in Flight
          m1 Target Vehicle Provider
        a2 Launch Interceptor
          i1 Target in Flight
          o1 Engagement Telemetry
          m1 Launch Crew
        a3 Record Range Data
          i1 Engagement Telemetry
          i2 Pre-Flight Predictions
          o1 Flight Test Data
          m1 Range Instrumentation
    a3 Produce Quick-Look Assessment
      i1 Flight Test Data
      o1 Quick-Look Reports
      m1 Test Director
  a3 Evaluate Performance
    i1 Flight Test Data
    i2 Quick-Look Reports
    c1 Verification Requirements
    o1 Test Reports > G|Oversee Program Execution|Test Reports
      ## Fan-out: the program office and SE&I both consume test
      ## reports; one `>` here, a `<` on each consumer.
    o2 Qualification Results > V|Release Technical Data Package|Qualification Results
    m1 Test Evaluators
    a1 Reduce Flight Test Data
      i1 Flight Test Data
      o1 Reduced Data Products
      m1 Data Reduction Analysts
    a2 Compare Against Predictions
      i1 Reduced Data Products
      i2 Quick-Look Reports
      o1 Performance Assessments
      m1 Test Evaluators
    a3 Report Verification Status
      i1 Performance Assessments
      c1 Verification Requirements
      o1 Test Reports
      o2 Qualification Results
      m1 Test Evaluators
```

## Model M — Manufacturing & Production

Manufacturing plans from the released TDP and the production milestone
decision, builds rounds, runs lot acceptance, and delivers. SPINE: M2
Produce Interceptors -> M22 Assemble Interceptor Rounds -> M221 Build
Kill Vehicle Assemblies -> M2211-3.

```idef0
tM Manufacturing & Production
## **Manufacturing**: gated by the production milestone decision from
## the program office; samples every lot back to Test.
  a1 Plan Production
    i1 Technical Data Package < V|Release Technical Data Package|Technical Data Package
    i2 Integrated System Baseline < E|Integrate & Verify System|Integrated System Baseline
    c1 Milestone Decisions < G|Oversee Program Execution|Milestone Decisions
    c2 Authorized Funding < G|Manage Program Funding|Authorized Funding
    o1 Production Plan
    o2 Supplier Orders
    m1 Production Control
    a1 Plan Manufacturing Processes
      i1 Technical Data Package
      o1 Process Plans
      m1 Manufacturing Engineers
    a2 Qualify Supply Chain
      i1 Technical Data Package
      o1 Qualified Suppliers
      m1 Supplier Quality Engineers
    a3 Schedule Production Lots
      i1 Process Plans
      i2 Qualified Suppliers
      i3 Integrated System Baseline
      c1 Milestone Decisions
      o1 Production Plan
      o2 Supplier Orders
      m1 Production Control
  a2 Produce Interceptors
    i1 Supplier Deliveries
    i2 Production Plan
    c1 Process Plans
    o1 Accepted Interceptors
    o2 Production Lot Samples > T|Conduct Flight Tests|Production Lot Samples
    m1 Production Workforce
    a1 Receive & Inspect Components
      i1 Supplier Deliveries
      o1 Accepted Components
      m1 Receiving Inspection
    a2 Assemble Interceptor Rounds
      i1 Accepted Components
      i2 Production Plan
      c1 Process Plans
      o1 Assembled Rounds
      m1 Production Workforce
      a1 Build Kill Vehicle Assemblies
        i1 Accepted Components
        c1 Process Plans
        o1 Kill Vehicle Assemblies
        m1 Clean Room Assembly Line
        a1 Assemble Seeker Modules
          i1 Accepted Components
          o1 Seeker Modules
          m1 Clean Room Assembly Line
        a2 Integrate Avionics Stack
          i1 Seeker Modules
          i2 Accepted Components
          o1 Avionics Stacks
          m1 Electronics Technicians
        a3 Close Out Kill Vehicle
          i1 Avionics Stacks
          c1 Process Plans
          o1 Kill Vehicle Assemblies
          m1 Clean Room Assembly Line
      a2 Integrate Booster Stack
        i1 Kill Vehicle Assemblies
        i2 Accepted Components
        o1 Integrated Rounds
        m1 Final Assembly Cell
      a3 Load Software & Checkout Round
        i1 Integrated Rounds
        o1 Assembled Rounds
        m1 Automated Test Equipment
    a3 Perform Lot Acceptance
      i1 Assembled Rounds
      o1 Accepted Interceptors
      o2 Production Lot Samples
      m1 Quality Assurance Inspectors
  a3 Deliver Interceptors
    i1 Accepted Interceptors
    o1 Delivered Interceptors > L|Field & Deploy Interceptors|Interceptor Deliveries
      ## Renamed at the boundary: Logistics receives this flow as
      ## `Interceptor Deliveries` -- two rows in the interface table.
    m1 Delivery Team
    a1 Containerize Rounds
      i1 Accepted Interceptors
      o1 Canistered Rounds
      m1 Delivery Team
    a2 Complete Government Acceptance
      i1 Canistered Rounds
      o1 Government-Accepted Rounds
      m1 Government Quality Representative
    a3 Ship to Deployment Site
      i1 Government-Accepted Rounds
      o1 Delivered Interceptors
      m1 Secure Transport
```

## Model L — Logistics & Sustainment

Logistics fields delivered rounds, monitors and maintains them, and
closes two feedback loops: reliability data to SE&I and software
problem reports to Fire Control. SPINE: L2 Sustain Fielded Inventory ->
L22 Maintain Rounds -> L222 Perform Corrective Maintenance -> L2221-3.

```idef0
tL Logistics & Sustainment
## **Logistics & sustainment**: fielding, health monitoring,
## maintenance, and the feedback loops that close the lifecycle.
  a1 Field & Deploy Interceptors
    i1 Interceptor Deliveries < M|Deliver Interceptors|Delivered Interceptors
    c1 Authorized Funding < G|Manage Program Funding|Authorized Funding
    o1 Deployed Inventory
    m1 Fielding Team
    a1 Receive at Deployment Site
      i1 Interceptor Deliveries
      o1 Received Rounds
      m1 Site Logistics Crew
    a2 Emplace Rounds
      i1 Received Rounds
      o1 Emplaced Rounds
      m1 Emplacement Crew
    a3 Certify Operational Readiness
      i1 Emplaced Rounds
      o1 Deployed Inventory
      m1 Site Commander
  a2 Sustain Fielded Inventory
    i1 Deployed Inventory
    i2 Software Maintenance Releases < B|Sustain Fire Control Software|Software Maintenance Releases
    o1 Field Reliability Data > E|Engineer the System|Field Reliability Data
    o2 Software Problem Reports > B|Sustain Fire Control Software|Software Problem Reports
    m1 Sustainment Team
    a1 Monitor Round Health
      i1 Deployed Inventory
      o1 Health Status Data
      o2 Software Problem Reports
      m1 Health Monitoring System
    a2 Maintain Rounds
      i1 Health Status Data
      i2 Software Maintenance Releases
      o1 Maintained Rounds
      m1 Maintenance Technicians
      a1 Diagnose Faults
        i1 Health Status Data
        o1 Fault Diagnoses
        m1 Maintenance Technicians
      a2 Perform Corrective Maintenance
        i1 Fault Diagnoses
        o1 Repaired Rounds
        m1 Maintenance Technicians
        a1 Remove & Replace Modules
          i1 Fault Diagnoses
          o1 Module Replacements
          m1 Maintenance Technicians
        a2 Apply Software Updates
          i1 Module Replacements
          i2 Software Maintenance Releases
          o1 Updated Rounds
          m1 Software Load Equipment
        a3 Retest Repaired Rounds
          i1 Updated Rounds
          o1 Repaired Rounds
          m1 Automated Test Equipment
      a3 Return Rounds to Service
        i1 Repaired Rounds
        o1 Maintained Rounds
        m1 Site Logistics Crew
    a3 Analyze Field Reliability
      i1 Health Status Data
      i2 Maintained Rounds
      o1 Field Reliability Data
      m1 Reliability Engineers
```
