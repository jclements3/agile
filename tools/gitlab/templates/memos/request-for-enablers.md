<!--
TEMPLATE: Request for enablers.

Use it when the team needs something it cannot give itself: protected training time, runner hardware, a license,
a tool approval, a person. A transition that is mandated without its enablers is a schedule risk. This memo
states that plainly, and it gives management something specific to approve.

The rule for every ask: WHAT, WHY (the outcome it buys, in management's terms), BY WHEN, and WHAT HAPPENS IF NOT.
"We're not ready" sounds like foot-dragging. "We need X by date Y, or the trace report slips two weeks" is an
engineering position management can act on.

How to fill it in:
  - Replace every <<placeholder>>; `memo-build.pl --check FILE` lists what is left.
  - Put the asks in a table: management reads the table first.
  - Lead with the outcome the asks protect, not with the asks.
  - Offer a fallback for each ask. It shows you have thought about the trade.
Render: perl $KIT/tools/memo/memo-build.pl FILE.md
-->
# <<Organization name>>

## <<Office symbol>>

## <<DD Month YYYY>>

<!-- The person who can approve the asks. -->
## Memorandum for <<Program Manager, office>>

## From: <<Title, e.g. Tidewater MBSE Lead>>

<!-- The subject names the outcome, not "resources". -->
## Subject: <<Enablers needed to OUTCOME by DATE>>

## References: (a) <<the directive>>; (b) <<the plan or scorecard the asks protect>>

<!-- Paragraph 1: the outcome and where the team stands, with one number. -->
<<The team is on track to ... by ... . Today ... (one number).>>

<!-- Paragraph 2: the asks, as a table with dates. Keep it to the few that matter. -->
<<To keep that date, the team needs the following decisions:>>

| # | Ask | Why (the outcome it buys) | Needed by | If not |
|:-:|:----|:--------------------------|:---------:|:-------|
| 1 | <<e.g. four protected hours a week per person for training>> | <<e.g. the team learns while delivering>> | <<date>> | <<e.g. the TODO burn-down slows by about a third>> |
| 2 | <<e.g. a second runner machine>> | <<e.g. no merge waits when the first is down>> | <<date>> | <<e.g. one outage blocks every merge>> |
| 3 | <<e.g. ISSM approval of a tool>> | <<...>> | <<date>> | <<...>> |

<!-- Paragraph 3: what the team is doing meanwhile, so management sees the asks are not excuses. -->
<<Until then, the team will ... >>

<!-- Paragraph 4: the decision requested and by when. Name it. -->
<<Request a decision on items 1 to 3 by DATE.>>

<<The point of contact is the undersigned, at EMAIL.>>

## <<NAME>>

## <<Title, office>>
