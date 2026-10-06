# Sprint 5 review -- demo script (draft: edit before the meeting)

## 1. The question this sprint answered
"Did we do what we set out to do: Procured parts and DataCenter closed; Legacy Import untangled; trace becomes a gate?"
Answer in one line: 8 of 8 stories done, 21 of 30 requirements with a verification case.

## 2. The same four numbers as every review
- TODO lines left: 14 (down 8 from 22)
- Requirements with a verification case: 21 of 30 (70%) (no change)
- Open discrepancy reports and prime changes: 7 (up 2 from 5)
- Blocked items: 0

## 3. Show the output, not the tool
- The model site: https://tidewater.pages.gitlab.gov.example.invalid/model/
- The generated documents (docs/ on the site: part tree, trace, data exchange tables)
- 5 changes merged this sprint, 5 with green checks; show one going red to green:
    !16 Remove the Legacy Import clutter
    !17 Pipeline: The trace job becomes a ratchet: it fails an MR...
    !18 Procured parts as @Procured metadata
    !19 Level tags in DataCenter

## 4. One before-and-after
- Now: from proposing a change to the first review takes 3.3 h (median). Before: [the document-era number -- put it in a --baseline file].
- Now: from first edit to accepted change takes 3.5 h (median). Before: [the document-era number -- put it in a --baseline file].
- Before: [how long "which requirements are unverified?" used to take]. Now: the trace check answers it on every change, in about 3 min.

## 5. One safe live change (on a scratch branch, never on develop)
- Delete one satisfy line on a scratch branch and open a draft merge request: in about 3 min the trace check names the requirement that lost its design. Close the merge request afterwards.

## 6. What it means for the next milestone
- Sprint 6 starts Mon Dec 14: 14 TODO lines to go; at this sprint's pace that is about 2 more sprints.

## 7. The ask
- [A decision on ___ by ___, or help with ___. Name it, with a date.]

## 30-second version
Sprint 5: 8 of 8 stories done, 14 TODO lines left (down 8), 21 of 30 requirements with a verification case. Nothing blocks us.

## 1-sentence version
Sprint 5 moved the model forward by 8 stories and 8 TODO lines.
