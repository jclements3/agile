<!-- Tidewater (notional). The twelve-week progress memo for the December program management review, from
     tools/gitlab/templates/memos/progress-memo.md. Values are from the simulation's sprint-6 evidence:
     docs/tidewater/sprints/06/scorecard.json and analytics.txt, measured at the review on 24 December 2026. -->
# Tidewater Coastal Observation Program

## TW-SE

## 24 December 2026

## Memorandum for Tidewater Program Manager

## From: Tidewater MBSE Lead

## Subject: Twelve-week results: the Tidewater model is under configuration control and checked on every change

## References: (a) Program memorandum, Adoption of DevSecOps Practices for Systems Engineering Artifacts, 24 September 2026; (b) Twelve-week scorecard, agreed 1 October 2026

In twelve weeks the team moved the Tidewater system model from SysML v1 into SysML v2 text under configuration control in GitLab, and every change to it is now checked automatically and reviewed before it is accepted. The most important result: 47 of the 52 conversion items are closed. The 5 left are behavior and analysis items the team writes by hand.

The measures agreed before the work began, computed by the system:

| Measure | At start | Now | Target | Source |
|:--------|:--------:|:---:|:------:|:-------|
| Conversion items (TODO lines) left | 52 | 5 | structure closed | pipeline todo job |
| Requirements with a verification | 21 of 30 | 21 of 30 | every gap owned | trace job |
| Open discrepancy reports to the prime | 0 | 7 | every gap reported | GitLab issues |
| Blocked items | 0 | 0 | none older than 3 days | journal |
| Changes gated (pipeline and code-owner review) | not measured | 26 of 27 | 100% | GitLab |
| Change lead time, median | 23 working days (notional) | 3.5 hours | under 3 working days | gitlab.pl analytics |
| Review turnaround, median | 3 weeks per package (notional) | 3.3 hours | under 1 working day | gitlab.pl analytics |
| Package dependency cycles | 2 | 1 | none | pipeline |
| Team morale (pulse, 1 to 5) | 1.9 | 4.1 | 3.5 and rising | retrospectives |

Before: finding where the prime's DOORS text and the model disagreed was never done systematically, and a model review was a sixty-slide briefing of screenshots that took three weeks. Now: the pipeline compares every requirement's text on every change in under a minute, and the model site is current every night.

What did not go well: in sprint 3 a hand edit broke the grammar check and the runner hardening waited on the ISSM with no date set, and the pulse survey dipped from 2.4 to 2.2. The one ungated change was the first one, merged before the pipeline existed. Verification coverage stayed at 21 of 30, because the gaps are the prime's to fix; they are reported as discrepancy reports. What the team did: it fixed the edit on its branch before it reached the model, asked the ISSM for dated review slots, and kept reporting the low numbers.

For the next milestone, the January drop from the prime, this means the team can show what the drop changes for the government model within a day of receiving it. The remaining risk is behavior modeling, which the converter does not carry and the team writes by hand.

Request approval of the second runner machine and of the GitLab tier decision by 15 January 2027, as asked in the memorandum of 21 October 2026.

The point of contact is the undersigned.

## JIM

## Tidewater MBSE Lead

| Attachment | Title |
|:-----------|:------|
| 1 | December program management review briefing |
| 2 | The model site, published by the pipeline |
