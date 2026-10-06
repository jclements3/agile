<!--
TEMPLATE: Memorandum for record (MFR).

Use it to put a decision on file: the branching model, a baseline, a waiver, a change to how the team works.
The record is the point. A year from now someone will ask "why does the model live in develop?", and this memo
answers in one page with the date and the name of the person who decided.

How to fill it in:
  - Replace every <<placeholder>>. `perl $KIT/tools/memo/memo-build.pl --check FILE` lists what is left.
  - Delete these comments or leave them: memo-build.pl strips them before rendering.
  - Every top-level paragraph is numbered 1., 2., ... by md2memo. A list right after a paragraph becomes
    a., b., ... under it. Keep each paragraph to one idea.
  - One decision per memo is easiest to cite. Several related decisions are fine as a lettered list, each with
    its reason, as below.
  - If the team keeps decision records (docs/adr/), the MFR cites them; the ADRs carry the detail, the MFR the
    authority.

Render: perl $KIT/tools/memo/memo-build.pl FILE.md   (writes FILE.pdf and FILE.txt)
-->
# <<Organization name, e.g. Tidewater Coastal Observation Program>>

## <<Office symbol, e.g. TW-SE>>

## <<DD Month YYYY>>

<!-- "Memorandum for record": addressed to the file, not to a person. -->
## Memorandum for Record

<!-- The person who decided, by title. -->
## From: <<Title of the decision maker, e.g. Tidewater MBSE Lead>>

<!-- State the decision in the subject line itself, not just the topic. -->
## Subject: <<The decision, e.g. Branching model for the Tidewater SysML v2 model>>

<!-- What the decision rests on: the directive, the plan, the decision records. Delete the line if there are none. -->
## References: (a) <<directive or plan, with its date>>; (b) <<decision record, e.g. docs/adr/0002-gitflow.md>>

<!-- Paragraph 1: what was decided, in one or two sentences. -->
<<On DD Month YYYY the decision maker decided ... >>

<!-- Paragraph 2: why. The reasons a reader in a year will need, not the whole discussion. -->
<<The reasons are:>>

- <<reason one>>
- <<reason two>>

<!-- Paragraph 3: what would make the team revisit the decision. This keeps a decision honest. -->
<<This decision will be revisited if ... >>

<!-- Paragraph 4: who is affected and what they do differently from now on. -->
<<Effective immediately, ... >>

<!-- Last paragraph: a point of contact. -->
<<The point of contact is the undersigned, at EMAIL.>>

<!-- Signature block: the name, then the title. md2memo prints both in capitals, flush left. -->
## <<NAME>>

## <<Title, office>>

<!-- Attachments: a small table, so the numbering of the paragraphs above is not continued. Delete if none. -->
| Attachment | Title |
|:-----------|:------|
| 1 | <<e.g. Decision table>> |
