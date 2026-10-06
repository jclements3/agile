# Tidewater -- a notional SysML v1 project for testing the v1 -> v2 port

**Tidewater is fictional.** It is a coastal weather-observation network: moored buoys and shore
stations observe, a data center ingests, checks, archives and publishes a marine bulletin, and a
field crew services the stations. Structure only; every value is notional.

The files here are prime drop 1, written by `perl sim/tidewater-v1.pl` (rerun it after changing the script):

| file | shape |
|---|---|
| `tidewater.xmi` | a Cameo Systems Modeler 2022x XMI export |
| `tidewater.reqif` | a DOORS 9.7 ReqIF 1.2 export, three formal modules |
| `tidewater.csv` | the same modules as a DOORS CSV export |
| `MANIFEST.txt` | the delivery record: version, date, CDRL, change requests, sha256 of each file |
| `CHANGES.csv` | the prime's change requests in this drop, with the xmi:ids each one touches |
| `layout.map` | the government's repository layers (hand-written, not generated) |

What the XMI holds: blocks on six levels with a project profile of level stereotypes, a generalization,
proxy, full and flow ports, interface blocks with flow properties, IBD connectors, a constraint block
bound in a parametric, activities with call actions, a fork, a pin and an object flow, a state machine,
a sequence interaction, actors and use cases with an include, 30 requirements of six Cameo kinds,
satisfy, verify, deriveReqt, refine, trace and allocate, six test cases, value types with units, and
diagrams in `xmi:Extension`.

## The spider web

The government team was made to point-and-click its documents into Cameo a few years ago, and the prime has
maintained the result since. It shows. Each run of the generator measures it:

    spider web: 560 elements, 47 diagrams, 99 relationships over 40 blocks (max 14 on ObservingStation, mean 1.2)
      package dependency cycles: 2  [DataCenter <-> Stations]  [Network <-> Operations]
      unused: 4 (Battery_old, Copy of SensorSuite, TBD Component, Requirement from slide 14)
      duplicates: 2  [Battery = Battery_old]  [Copy of SensorSuite = SensorSuite]

- **47 diagrams**, stale ones included: "bdd Stations OLD", "ibd PowerSystem (copy)", "Briefing chart 2024-03 - do not edit".
- **A Legacy Import package** of clutter from the document port: a duplicated Battery_old, a Copy of SensorSuite,
  an unused TBD Component, and a requirement-like class with no id.
- **Spaghetti.** Trace and Dependency lines make two package cycles. ObservingStation carries 11 traces to
  requirements on top of its satisfies.
- **Pasted prose** in comments: "Per SRS rev C para 3.2.1 ...".

The government port leaves the clutter out of the v2 model and raises Discrepancy Reports. The prime deletes
Copy of SensorSuite in drop 3 and the whole Legacy Import package in drop 6. The cycles stay in every drop.

Port it:

    perl bin/xmi2sysml.pl --report --out /tmp/tw --check examples/tidewater-v1/tidewater.xmi
    perl bin/reqif2sysml.pl --report --model /tmp/tw examples/tidewater-v1/tidewater.reqif
    perl bin/reqif2sysml.pl --csv --report --model /tmp/tw examples/tidewater-v1/tidewater.csv

What the port should find (`tests/xmi2sysml.t` checks it):

- 206 of 206 in-scope elements ported, 12 TODO lines: units, the interaction, the include, the state
  machine, the constraint expression, the fork, the pin, two activity edges and the profile.
- The seven project stereotypes are reported as not converted.
- TW-SYS-016 is in DOORS only, and TW-SEG-009 is in the model only.
- TW-SYS-012 has no satisfy. It is traced from the mast, which does not count.
- TW-SYS-011 and TW-SEG-002 have no verify. The stakeholder needs are verified only through what derives from them.
- TW-SYS-006 says "twice a day" in DOORS and not in the model. The trace reports it as drift.

## A layered repository

`layout.map` puts every top-level package, and each DOORS module, in a layer of the government's repo:

    perl bin/xmi2sysml.pl   --out model --layout-map examples/tidewater-v1/layout.map examples/tidewater-v1/tidewater.xmi
    perl bin/reqif2sysml.pl --out model --layout-map examples/tidewater-v1/layout.map examples/tidewater-v1/tidewater.reqif

| layer | packages |
|---|---|
| `library/` | Types, Interfaces, Tidewater (what sat outside any package) |
| `requirements/stakeholder/`, `system/`, `segment/` | the three DOORS modules |
| `requirements/model/` | Requirements, the copy the Cameo model keeps |
| `logical/` | Behavior |
| `physical/<segment>/`, `physical/allocation/` | Network, Stations, DataCenter, Operations; Allocations |
| `analysis/`, `verification/` | Analysis; Verification |
| `legacy/` | Legacy Import, until the prime deletes it |

Use the same map for every drop. Each package then keeps its path, so the converted drop merges 3-way on the
vendor branch. A package the prime adds later is not listed; it goes to `unsorted/` and the report names it.

## Later drops

The prime keeps maintaining the v1 model and delivers it again. `--drop N` writes drop N, cumulative,
with the same xmi:id for every element that survives, as Cameo keeps them:

    perl sim/tidewater-v1.pl --drop 3 /tmp/drop3

| drop | version | delivered | change requests |
|---|---|---|---|
| 1 | v1.0 | 2026-10-02 | NWM-CR-0001 baseline: the files in this folder |
| 2 | v1.1 | 2027-01-08 | NWM-CR-0012 hygrometer; NWM-CR-0013 TW-SYS-017 and its trace; NWM-CR-0014 TW-SYS-006 aligned with DOORS (DR-1) |
| 3 | v1.2 | 2027-04-02 | NWM-CR-0015 storm mode; NWM-CR-0016 fuse and TW-SEG-010; NWM-CR-0017 TW-SEG-009 deleted; NWM-CR-0018 TW-SYS-012 satisfied (DR-2); NWM-CR-0019 Copy of SensorSuite deleted (DR-5) |
| 4 | v1.3 | 2027-07-02 | NWM-CR-0020 salinity; NWM-CR-0021 drifting buoys; NWM-CR-0022 TW-SYS-016 in the model (DR-3); NWM-CR-0023 TW-SYS-002 revised |
| 5 | v1.4 | 2027-10-01 | NWM-CR-0024 EnergyBalance reserve term; NWM-CR-0025 PublishBulletin renamed IssueBulletin, with no rationale |
| 6 | v1.5 | 2028-01-07 | NWM-CR-0026 TW-SYS-019; NWM-CR-0027 requestResend; NWM-CR-0028 Legacy Import deleted (DR-5) |
| 7 | v1.6 | 2028-03-03 | NWM-CR-0029 energy balance analysis (DR-4); NWM-CR-0030 TW-SEG-002 verified; NWM-CR-0031 doc edits |

Each drop carries the prime's change requests in `CHANGES.csv` (`cr_id,title,rationale,kind,xmi_ids,requirements`)
and in its MANIFEST. Every change in a delta belongs to one CR. NWM-CR-0025 deliberately has no rationale, so
the government has to ask for one.

Compare two drops element by element before merging them:

    perl bin/xmi2sysml.pl --delta /tmp/drop2/tidewater.xmi /tmp/drop3/tidewater.xmi

With `--impact MODEL_DIR` the report also says what each change touches in the government's v2 model. When
`CHANGES.csv` sits beside the new drop's XMI, the report is grouped by change request, and the summary counts the
CRs without a rationale and any change no CR names:

    perl bin/xmi2sysml.pl --delta /tmp/drop4/tidewater.xmi /tmp/drop5/tidewater.xmi --impact model

The delta marks each change as carried, meaning re-converting the drop brings it into the v2 text, or manual,
meaning the converter does not carry it. The Storm state in drop 3 is manual: the state machine is a TODO
line in v2, so its new state never shows up in a diff of the converted text.
