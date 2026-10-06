# Sprint 3 review -- demo script (draft: edit before the meeting)

## 1. The question this sprint answered
"Did we do what we set out to do: Network closed; DOORS in the model; the trace report on every change?"
Answer in one line: 6 of 6 stories done, 21 of 30 requirements with a verification case.

## 2. The same four numbers as every review
- TODO lines left: 50 (down 2 from 52)
- Requirements with a verification case: 21 of 30 (70%)
- Open discrepancy reports and prime changes: 0 (no change)
- Blocked items: 0

## 3. Show the output, not the tool
- The model site: (not published yet: the pages job on the default branch publishes it)
- The generated documents (docs/ on the site: part tree, trace, data exchange tables)
- 4 changes merged this sprint, 4 with green checks; show one going red to green:
    !8 Level tags in Network
    !9 Replace the Include TODO with an include use case
    !10 Prime drop v1.0 with the DOORS modules
    !11 Pipeline: Adds the trace report (report only for now) and...

## 4. One before-and-after
- Now: from proposing a change to the first review takes 4.1 h (median). Before: [the document-era number -- put it in a --baseline file].
- Now: from first edit to accepted change takes 4.2 h (median). Before: [the document-era number -- put it in a --baseline file].
- Before: [how long "which requirements are unverified?" used to take]. Now: the trace check answers it on every change, in about 2 min.

## 5. One safe live change (on a scratch branch, never on develop)
- Delete one satisfy line on a scratch branch and open a draft merge request: in about 2 min the trace check names the requirement that lost its design. Close the merge request afterwards.

## 6. What it means for the next milestone
- Sprint 4 starts Mon Nov 16: 50 TODO lines to go; at this sprint's pace that is about 25 more sprints.

## 7. The ask
- [A decision on ___ by ___, or help with ___. Name it, with a date.]

## 30-second version
Sprint 3: 6 of 6 stories done, 50 TODO lines left (down 2), 21 of 30 requirements with a verification case. Nothing blocks us.

## 1-sentence version
Sprint 3 moved the model forward by 6 stories and 2 TODO lines.
