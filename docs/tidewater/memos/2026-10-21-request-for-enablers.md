<!-- Tidewater (notional). Jim's request for enablers in sprint 2, written from tools/gitlab/templates/memos/request-for-enablers.md. -->
# Tidewater Coastal Observation Program

## TW-SE

## 21 October 2026

## Memorandum for Tidewater Program Manager

## From: Tidewater MBSE Lead

## Subject: Enablers needed to brief measured results at the December program management review

## References: (a) Program memorandum, Adoption of DevSecOps Practices for Systems Engineering Artifacts, 24 September 2026; (b) Twelve-week scorecard and plan, 2 October 2026

The team is on track for the December briefing. Drop 1 of the prime's model is received, checked against its manifest and converted: the converter left 52 items that need a person, and the drop goes onto the integration branch this sprint. The first pipeline is written and runs locally; it checks every change once the runner below is in place.

To keep that date, the team needs the following decisions:

| # | Ask | Why (the outcome it buys) | Needed by | If not |
|:-:|:----|:--------------------------|:---------:|:-------|
| 1 | Four protected hours a week per person for training, through 18 December | the team learns while it delivers | 26 Oct | the conversion burn-down slows by about a third |
| 2 | A two-hour review slot with the ISSM for the runner and repository security description | the toolchain is approved for program data | 6 Nov | secret detection and runner hardening stay unapproved |
| 3 | Keep one Cameo seat, for reading the prime's drops only | each drop can be opened when its XMI export is in question | 30 Nov | a drop with a bad export cannot be checked |
| 4 | A second runner machine on the program network | no merge waits when the first runner is down | 8 Jan | one runner outage blocks every merge |
| 5 | A decision on the GitLab tier that enforces code-owner approval rules | approvals enforced by the platform, not by habit | 15 Jan | approvals rely on the team's discipline alone |

Until then, the team will keep the review rule by agreement, run the pipeline on the single runner, and read drops from their XMI exports.

Request a decision on items 1 and 2 by 26 October, and on items 3 to 5 at the November program management review.

The point of contact is the undersigned.

## JIM

## Tidewater MBSE Lead
