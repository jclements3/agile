<!-- Tidewater (notional). The change board's disposition of prime drop v1.1, from
     tools/gitlab/templates/memos/drop-disposition.md. Issue numbers #84 (DR-1) and #131 (the prime-tbd assumption) are real issues from the simulation's sprint 6; the
     drop-2 intake issues come after sprint 6 and are marked "planned". -->
# Tidewater Coastal Observation Program

## TW-SE

## 13 January 2027

## Memorandum for Record

## From: Tidewater MBSE Lead, Chair of the Model Change Board

## Subject: Disposition of prime drop v1.1 (CDRL A003, System Model)

## References: (a) CDRL A003, System Model; (b) Prime Drop issue for v1.1 (planned: opened at intake on 11 January 2027); (c) Delta and impact report for drops v1.0 to v1.1, pipeline delta job

Drop v1.1, delivered 8 January 2027 under CDRL A003, was received on 11 January 2027. Every file matched the sha256 recorded in its manifest.

Compared with drop v1.0, it adds 7 elements, removes none and changes 1. For the government model it adds one requirement, TW-SYS-017, changes the text of TW-SYS-006, and touches one verification case, TestStationObservations; no hand-made change has to be redone.

The change board met on 13 January 2027 and dispositioned the changes as follows:

| Change | Prime ID | Disposition | Impact | Issue |
|:-------|:---------|:------------|:-------|:------|
| New hygrometer in the sensor suite | Hygrometer, part hygrometer | Accept | none | #131, the December working assumption, confirmed |
| New requirement TW-SYS-017, relative humidity | TW-SYS-017 | Accept; verified by TestStationObservations | none | planned: opened at intake |
| TW-SYS-006 text now matches DOORS | TW-SYS-006 | Accept; closes DR-1 | none | #84 (DR-1) |

This drop closes DR-1 (#84), the TW-SYS-006 text drift, and confirms the government's working assumption about the hygrometer interface recorded in December (#131). It opens no new discrepancy reports.

Accepted changes are implemented through merge requests citing the prime change ID, in sprint 8.

The point of contact is the undersigned.

## JIM

## Tidewater MBSE Lead
