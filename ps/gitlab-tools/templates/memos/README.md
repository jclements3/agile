# Memo templates

DoD-style memoranda written in Markdown in Vim and rendered to PDF and text with the kit's `tools/memo/md2memo.pl`.
Each template carries its guidance as `<!-- ... -->` comments. `tools/memo/memo-build.pl` strips the comments,
checks the header lines, warns about unfilled `<<placeholders>>`, and writes `NAME.pdf` and `NAME.txt`.

| Template | Use it when |
|---|---|
| `memorandum-for-record.md` | a decision must be on file: a branching model, a baseline, a waiver |
| `request-for-enablers.md` | the team needs time, hardware, licenses or approvals, by a date |
| `progress-memo.md` | management needs measured progress: the twelve-week memo, a quarterly memo |
| `drop-disposition.md` | the CCB has dispositioned the changes in a prime drop |
| `discrepancy-report-transmittal.md` | discrepancy reports go to the prime through the contracting channel |

## Writing one

```sh
cp docs/memos/templates/progress-memo.md docs/memos/2026-12-24-twelve-week-progress.md   # in a repo made by kickoff.pl scaffold
#  (outside one: cp $KIT/tools/gitlab/templates/memos/progress-memo.md ...)
vim docs/memos/2026-12-24-twelve-week-progress.md
perl $KIT/tools/memo/memo-build.pl --check docs/memos/2026-12-24-twelve-week-progress.md   # what is still to fill in
perl $KIT/tools/memo/memo-build.pl docs/memos/2026-12-24-twelve-week-progress.md           # .pdf and .txt beside it
```

From Vim, on the memo you are editing:

```vim
:w | !perl $KIT/tools/memo/memo-build.pl %
```

Open the `.pdf` in the browser, or read the text in a split with `:vsplit %:r.txt`.

## Keep memos in the model repository

Put memos under `docs/memos/`, named `YYYY-MM-DD-slug.md`. A memo then goes through a merge request like any model
change. A code owner reviews the wording, the pipeline can check it with `memo-build.pl --check`, and the signed
version is the one on `develop`.

Commit only the `.md` file. The `.pdf` is rebuilt from it, and the signed PDF goes to the records system the program
uses. Memos about marked content follow the same marking rules as the model. Tidewater is notional, so its memos
are unmarked, and `discrepancy-report-transmittal.md` shows `{CUI}` tags only as an example.

## What md2memo cannot express yet

- Header lines are `##` headings, so md2memo prints them in capitals. The references and the signer's title therefore come out in capitals too.
- The office symbol and the date go on separate lines: md2memo cannot set a date flush right.
- The signature block is flush left, not starting at the center.
- Attachments are a small table, because a list after the signature would continue the paragraph numbering.
