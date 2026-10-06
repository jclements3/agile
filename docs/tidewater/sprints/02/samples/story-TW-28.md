# Import drop 1 through the vendor branch, in layers

## Why

The prime will deliver again; importing through vendor/prime with a fixed layout map lets git merge each later drop into our edited copy.

## What "done" looks like

- [ ] The layout map is decided and committed
- [ ] vendor/prime holds the converter output of drop 1
- [ ] The merge MR is on develop, outline count recorded
- [ ] The pipeline is green on every MR of this story

## Tasks

| Task | Points | Who |
|---|---|---|
| #39 Decide the layered layout; the layout map | 1 | @bob |
| #40 Import drop 1 onto vendor/prime | 1 | @tom |
| #41 Review and merge the drop-1 MR; record the outline count | 2 | @bob |

## Notes

Epic E5 (Drop 1 intake and first import), tome T2 (Port Tidewater v1 to SysML v2). Journal id **TW-28**.
