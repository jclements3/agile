# Markings

[[_TOC_]]

> [!warning]
> This page is a template. Your security officer and your program's classification guide decide the markings, not
> this file. Fill in the blanks with them before the first commit that holds real model content.

## What the repository may hold

| Question | Answer for this project |
|---|---|
| Highest marking allowed in this repository | <!-- e.g. CUI --> |
| Network and GitLab instance approved for it | <!-- name of the enclave / instance --> |
| Who approved it, and when | <!-- the security officer, a date, a reference --> |
| What must never be committed | <!-- e.g. performance values above the guide's thresholds, credentials, personal data --> |

If a change would push the model above the allowed marking, **stop**: do not commit it, and talk to the security
officer. Removing a committed secret or marked text from git history is hard. Keeping it out is easy.

## How markings appear in the model

- Each package carries its marking as metadata, so the tools can check it:
  ```sysml
  package Stations {
      @Marking { level = Level::U; }
  }
  ```
- `model.pl draw pkg` and the `gate` check that no package holds a higher marking than its owner allows (no
  write-down), and draw each package's marking.
- Generated documents and memos carry the banner from the project's settings. Never hand-type a banner.

## Where marked material can and cannot go

| Place | Allowed? |
|---|---|
| The model repository, this GitLab | up to the marking above |
| The project's Pages site | <!-- usually the same as the repository; check the instance's rules --> |
| Issues, merge request descriptions, comments | the same as the repository. Quote ids, not marked text, when you can. |
| A local AI assistant on your laptop | only what your laptop is approved for, and only if the assistant was approved |
| E-mail, chat, a briefing | by your organization's rules for that channel, not by this repository's |

## Review

The [review checklist](review-checklist.md) asks every reviewer to check markings. A merge request that adds a
package without a marking, or raises one, needs the security officer's comment before it merges.
