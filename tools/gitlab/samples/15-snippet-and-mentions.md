# References and mentions, in any Markdown field

| You type | GitLab shows | Meaning |
|---|---|---|
| `#18` | a link to issue 18 with its title on hover | an issue in this project |
| `#18+` | the link plus the issue's title inline | same, expanded |
| `!19` | a link to merge request 19 | an MR |
| `%"Sprint 4"` | a link to the milestone | a sprint |
| `~"epic::structure"` | the label chip | a label |
| `@bob` | a mention; Bob is notified | a person |
| `@tidewater/model-team` | a group mention | everyone in the group |
| `tidewater/model#18` | a cross-project issue link | another project's issue |
| `3c9e1a2` | a link to the commit | a commit |
| `baseline-1` (in a release) | plain text; use `[baseline-1](../-/tags/baseline-1)` | a tag |
| `[[_TOC_]]` | a table of contents | in descriptions and wiki pages |
| `- [ ] item` | a checkbox, counted in the issue list ("2 of 5 checklist items") | a task list |
| `> [!note]` | a blue alert box | also `[!tip]`, `[!important]`, `[!caution]`, `[!warning]` |
| `<details><summary>…</summary>…</details>` | a collapsible section | long logs |
| ` ```mermaid ` | a rendered diagram | flowchart, gitGraph, gantt, sequenceDiagram |
| ` ```suggestion:-0+1 ` | an "Apply suggestion" button (MR diffs only) | a proposed change |
| `[^1]` and `[^1]: text` | a footnote | references in wiki pages |

Quick actions (a line of their own, in a description or comment):

```text
/label ~"type::story" ~"epic::structure"      /unlabel ~"workflow::blocked"
/milestone %"Sprint 4"                         /assign @bob   /assign_reviewer @jim
/estimate 2d    /spend 4h                      /relate #8 #11
/close    /reopen    /approve    /merge        /draft    /ready
```
