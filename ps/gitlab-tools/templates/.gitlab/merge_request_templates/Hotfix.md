<!-- Title: "Hotfix baseline-N: <what>". Source: hotfix/<name>. Target: main, then the back-merge to develop. -->

## What is wrong in the released baseline

<!-- The defect (#n) and who is affected: which analysis or review used the baseline. -->

Closes #

## The fix

<!-- The smallest change that corrects it. Anything larger waits for the next baseline. -->

## After merge

- [ ] Tag `baseline-N.1` on main (the tag pipeline checks the docs hash)
- [ ] Back-merge to develop (the same fix must not be lost)
- [ ] Tell the users of baseline-N

/label ~"type::defect" ~"priority::1" ~"workflow::review"
/assign_reviewer @jim
