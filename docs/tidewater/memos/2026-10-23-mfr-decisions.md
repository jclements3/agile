<!-- Tidewater (notional). The memorandum for record of decisions D-1 to D-10 (sprint 2), from tools/gitlab/templates/memos/memorandum-for-record.md. -->
# Tidewater Coastal Observation Program

## TW-SE

## 23 October 2026

## Memorandum for Record

## From: Tidewater MBSE Lead

## Subject: Ten decisions on how the Tidewater SysML v2 model is managed

## References: (a) Program memorandum, Adoption of DevSecOps Practices for Systems Engineering Artifacts, 24 September 2026; (b) Decision records in the model repository, docs/adr/

On 23 October 2026 the MBSE lead confirmed the ten decisions below. Each has a decision record with its context and consequences in reference (b).

The decisions and their reasons are:

- D-1. The v2 model is SysML v2 textual notation in a git repository, because text can be compared, merged, checked and reviewed line by line.
- D-2. Gitflow branching: develop is the default integration branch and main holds baselines only, because day-to-day work must never wait on a release.
- D-3. Every merge is a merge commit, with no squash and no fast-forward, because the history of who changed what feeds the metrics and the audit trail.
- D-4. DOORS stays authoritative for requirement text and the model holds a converted copy, because the prime and the program manage requirements in DOORS; the pipeline reports any drift.
- D-5. Prime drops land on a vendor branch, converted and never edited by hand, and are merged into develop, so that git merges the prime's changes with the team's own.
- D-6. The team never edits the v1 model; problems in it go to the prime as discrepancy reports, because the prime owns the v1 model under the contract.
- D-7. Conversion debt, the TODO lines the converter leaves, is the primary measure of port progress, because it is computed, countable and indisputable.
- D-8. Tasks are at most 5 points and stories fit one sprint; tasks live in GitLab and stories in the journal, because small changes are reviewed properly.
- D-9. The pipeline runs on a Windows shell runner with Git for Windows' Perl, because it uses the same tools as the laptops and needs nothing new approved.
- D-10. Everything that can be a file is a file under version control, because then it can be reviewed, rebuilt and audited.

Each decision will be revisited when the condition in its decision record occurs, for example D-5 when the prime delivers SysML v2 directly.

Effective immediately, changes to these decisions are made by merge request to the decision records, approved by the MBSE lead.

The point of contact is the undersigned.

## JIM

## Tidewater MBSE Lead
