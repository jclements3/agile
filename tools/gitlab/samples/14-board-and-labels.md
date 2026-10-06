# The board and the labels

## Board: "Sprint" (Plan > Issue boards)

Scope: milestone = the current sprint. Lists, left to right, are scoped labels, so moving a card swaps the label:

| Open | ~"workflow::ready" | ~"workflow::in-progress" | ~"workflow::review" | ~"workflow::blocked" | Closed |
|---|---|---|---|---|---|
| not yet ready | can be pulled | someone is on it | an MR is open | see the last comment | done |

Swimlanes (Premium): by epic. On Free, a second board "Epics" with one list per ~"epic::…" label.

## Board: "Prime" (discrepancy reports)

Scope: label ~"owner::prime". Lists: ~"severity::1", ~"severity::2", ~"severity::3". Jim reviews it before each drop.

## Label legend

| Label | Meaning |
|---|---|
| ~"type::story" | fits in one sprint; several tasks |
| ~"type::task" | under a week (≤ 5 points); one MR |
| ~"type::epic" | under a semester; several stories (Free tier stand-in for a group epic) |
| ~"type::drop" | intake of one prime drop |
| ~"type::discrepancy" | a DR to the prime; closed by the drop that fixes it |
| ~"type::defect" | wrong in the government model or the pipeline |
| ~"tome::port" | year-scale grouping: the port |
| ~"epic::structure" | semester-scale grouping: the structure port |
| ~"owner::prime" / ~"owner::gov" | who fixes it |
| ~"area::stations" | which package; matches a CODEOWNERS section |
| ~"area::interface" | a defect between packages (status metric H) |
| ~"phase::port" | found during the port |
| ~"priority::1" | do first |
