<!--
TEMPLATE: Progress memo (for example the twelve-week memo that goes with the December briefing).

Management reads the first paragraph and the table. Put the conclusion first, give the evidence in numbers, then
say what it means for the next milestone and what you need. Save the mechanism (pipelines, branches, YAML) for
questions. If a reader stops after paragraph 1, they should still know whether the effort is working.

The pattern: OUTCOME -> EVIDENCE (numbers, before and after) -> WHAT IT MEANS -> THE ASK.

How to fill it in:
  - Use the same four headline numbers the team reports at every review (for Tidewater: TODO lines left, verify
    coverage, open discrepancy reports and prime changes, blocked items), plus the scorecard measures agreed at the
    start. Never pick measures after the fact.
  - Every number comes from the system: the pipeline's artifacts, `gitlab.pl analytics`, the journal. Say where.
  - Report the bad numbers too. "Not new, newly visible" is honest and it builds trust.
  - Before-and-after: compare against the baseline agreed at the start, and label notional baselines as notional.
  - Draft it with `talk.pl weekly`/`talk.pl review` if the team uses them, then edit.
Render: perl $KIT/tools/memo/memo-build.pl FILE.md
-->
# <<Organization name>>

## <<Office symbol>>

## <<DD Month YYYY>>

## Memorandum for <<Program Manager, office>>

## From: <<Title, e.g. Tidewater MBSE Lead>>

<!-- The subject states the result, not the topic: "... delivered measurable progress", not "Status". -->
## Subject: <<Outcome headline, e.g. Twelve-week results: the model is under configuration control and checked on every change>>

## References: (a) <<the directive>>; (b) <<the scorecard agreed on <date>>>

<!-- Paragraph 1: the outcome in two sentences, with the single most important number. -->
<<In twelve weeks the team ... . The most important result: ... (number).>>

<!-- Paragraph 2: the evidence. The four headline numbers, then the scorecard, before and after. -->
<<The measures agreed before the work began, computed by the system:>>

| Measure | At start | Now | Target | Source |
|:--------|:--------:|:---:|:------:|:-------|
| <<TODO lines left by the converter>> | <<n>> | <<n>> | <<target>> | <<pipeline todo job>> |
| <<Verify coverage>> | <<n %>> | <<n %>> | <<target>> | <<VCRM>> |
| <<Open discrepancy reports / prime changes>> | <<n>> | <<n>> | <<target>> | <<GitLab issues>> |
| <<Blocked items>> | <<n>> | <<n>> | <<target>> | <<journal>> |
| <<Change lead time (median)>> | <<baseline, notional>> | <<n>> | <<target>> | <<gitlab.pl analytics>> |

<!-- Paragraph 3: one before-and-after story in plain words. -->
<<Before: ... took ... . Now: ... takes ... .>>

<!-- Paragraph 4: what did not go well, and what was done. Do not skip this. -->
<<What did not go well: ... . What the team did: ... .>>

<!-- Paragraph 5: what it means for the next milestone. -->
<<For NEXT MILESTONE, this means ... . The remaining risk is ... .>>

<!-- Paragraph 6: the ask, specific and dated. -->
<<Request ... by DATE.>>

<<The point of contact is the undersigned, at EMAIL.>>

## <<NAME>>

## <<Title, office>>

| Attachment | Title |
|:-----------|:------|
| 1 | <<Briefing slides or the model site address>> |
