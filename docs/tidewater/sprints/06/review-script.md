# Sprint 6 review -- demo script (draft: edit before the meeting)

## 1. The question this sprint answered
"Did we do what we set out to do: Behavior started; Operations closed; the data exchange table; interim baseline-0 for the program review?"
Answer in one line: 7 of 8 stories done, 21 of 30 requirements with a verification case.

## 2. The same four numbers as every review
- TODO lines left: 5 (down 9 from 14)
- Requirements with a verification case: 21 of 30 (70%) (no change)
    (a different measure: requirements with a passing recorded result, from the VCRM: 2 of 30)
- Open discrepancy reports and prime changes: 7 (no change)
- Blocked items: 0

## 3. Show the output, not the tool
- The model site: https://tidewater.pages.gitlab.gov.example.invalid/model/
- The verification matrix (vcrm.html on the site, from the vcrm job)
- The generated documents (docs/ on the site: part tree, trace, data exchange tables)
- 8 changes merged this sprint, 8 with green checks; show one going red to green:
    !21 Level tags in Operations
    !22 Inspection verdicts, signed
    !23 Fork, pin and flows in ObserveCoast
    !24 Document what crosses each interface

## 4. One before-and-after
- Now: from proposing a change to the first review takes 3.3 h (median). Before: [the document-era number -- put it in a --baseline file].
- Now: from first edit to accepted change takes 3.5 h (median). Before: [the document-era number -- put it in a --baseline file].
- Before: [how long "which requirements are unverified?" used to take]. Now: the trace check answers it on every change, in about 2 min.

## 5. One safe live change (on a scratch branch, never on develop)
- Delete one satisfy line on a scratch branch and open a draft merge request: in about 2 min the trace check names the requirement that lost its design. Close the merge request afterwards.

## 6. What it means for the next milestone
- Sprint 7 starts Mon Dec 28: 5 TODO lines to go; at this sprint's pace that is about one more sprint.

## 7. The ask
- [A decision on ___ by ___, or help with ___. Name it, with a date.]

## 30-second version
Sprint 6: 7 of 8 stories done, 5 TODO lines left (down 9), 21 of 30 requirements with a verification case. Nothing blocks us.

## 1-sentence version
Sprint 6 moved the model forward by 7 stories and 9 TODO lines.
