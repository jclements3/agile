# Monthly Program Status Report

## Memorandum for Program Manager, Integrated Air Defense Simulation Office

## From: Lead Systems Engineer, M&S Integration Team

## Subject: Program Status for September 2026

This memorandum summarizes technical progress, schedule, cost, and risk for the simulation modernization effort during September 2026. Overall status is **yellow**: technical work is on track, but the {CUI}radar model validation data delivery from the government test range slipped three weeks{/}, which pushes the integrated verification event into November.

Accomplishments this period:

- Completed the SysML v2 transition for the sensor and fire control subsystems. All 412 legacy requirements were migrated from DOORS and traced to v2 requirement definitions with no orphans.
  - The interceptor flyout model now consumes requirements directly from the textual model, removing the manual spreadsheet step.
  - Automated lint checks run on every merge and block any requirement without a verification method.
- Delivered build 4.2 of the engagement simulation to the integration lab. Regression suite passed 1,184 of 1,190 cases; the six failures are all traced to a single timing defect in the track correlation module.
- Stood up the digital twin data pipeline for the launcher subsystem, ingesting telemetry at 50 Hz from the hardware-in-the-loop bench.

Schedule status is shown in the table below. Dates are planned versus forecast completion.

| Milestone | Planned | Forecast | Status | Notes |
|:----------|:-------:|:--------:|:------:|:------|
| SysML v2 requirements baseline | 15 Aug | 12 Aug | Complete | Baselined and placed under configuration control. |
| Build 4.2 delivery | 30 Sep | 29 Sep | Complete | Six known defects carried forward to build 4.3. |
| Radar model validation | 15 Oct | 5 Nov | Late | Awaiting range data delivery; see risk R-07. |
| Integrated verification event | 1 Nov | 22 Nov | At risk | Depends on radar model validation; lab time is reserved for both windows. |
| Digital twin initial capability | 15 Dec | 15 Dec | On track | Launcher subsystem complete; interceptor subsystem in work. |
| Final report | 31 Jan | 31 Jan | On track | Outline approved by the program office. |

The current simulation architecture is shown below. The track correlation defect sits between the sensor model and the fire control model.

```
┌──────────────────┐        ┌──────────────────┐        ┌──────────────────┐
│   Sensor Model   │───────▶│ Track Correlation│───────▶│   Fire Control   │
│  (radar, EO/IR)  │        │   ░░ DEFECT ░░   │        │      Model       │
└────────┬─────────┘        └──────────────────┘        └────────┬─────────┘
         │                                                       │
         ▼                                                       ▼
╔══════════════════╗                                    ┏━━━━━━━━━━━━━━━━━━┓
║   Digital Twin   ║◀───────────────────────────────────┃Interceptor Flyout┃
║  Data Pipeline   ║          telemetry (50 Hz)         ┃      Model       ┃
╚══════════════════╝                                    ┗━━━━━━━━━━━━━━━━━━┛
```

Cost performance through September is summarized here. Figures are cumulative and in thousands of dollars.

| Element | Budget (BCWS) | Earned (BCWP) | Actual (ACWP) | CPI | SPI |
|:--------|------------:|-------------:|-------------:|----:|----:|
| Systems engineering | 1,240 | 1,215 | 1,190 | 1.02 | 0.98 |
| Simulation development | 2,860 | 2,790 | 2,905 | 0.96 | 0.98 |
| Digital twin | 980 | 1,010 | 965 | 1.05 | 1.03 |
| Verification and validation | 640 | 470 | 455 | 1.03 | 0.73 |
| **Total** | **5,720** | **5,485** | **5,515** | **0.99** | **0.96** |

Top risks and mitigations:

- R-07, radar validation data late. Likelihood 4, consequence 3. {CUI}The range has not released the July flight test radar returns pending a data review{/}. Mitigation:
  - Validate against the June data set now, and treat the July data as a confirmation run when it arrives.
  - Request that the program office escalate the data release through the test range liaison.
- R-11, track correlation timing defect. Likelihood 3, consequence 3. Root cause is a race between the sensor update and the correlation window. A fix is in code review and is planned for build 4.3.
- R-14, lab availability in November. Likelihood 2, consequence 4. Both the original and slipped verification windows are reserved; the earlier window will be released if not needed by 20 October.
  - Fallback is a reduced-scope verification event using the software-only configuration.

Staffing remains at 14 full-time equivalents. One simulation developer departs on 17 October; a replacement has accepted an offer and starts 3 November, so a two-week gap is expected on the flyout model work.

Decisions requested from the program manager:

- Approve validation of the radar model against the June data set so that the November verification event can hold.
- Approve release of the early November lab window on 20 October if radar validation is not complete.
- Concur with carrying the six build 4.2 defects into build 4.3 rather than issuing a patch release.

Planned activities for October:

- Complete radar model validation against June data and prepare the validation report.
- Deliver build 4.3 with the track correlation fix and close the six open defects.
- Begin the interceptor subsystem of the digital twin, starting with the flyout model telemetry interface:

```
 flyout model ──▶ telemetry encoder ──▶ pipeline ingest ──▶ twin state store
        ▲                                                         │
        └────────────────── state replay (test only) ◀────────────┘
```

- Conduct the quarterly model review with the program office on 23 October.

The point of contact for this report is the lead systems engineer, M&S Integration Team.
