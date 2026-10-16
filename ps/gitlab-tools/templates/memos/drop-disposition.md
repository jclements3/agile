<!--
TEMPLATE: Disposition of a prime drop (the CCB's decision on the changes in one delivery).

A change in the prime's model is not direction until it comes through the contractual channel. This memo is that
channel's record on the government side: what arrived, what it changes for the government's model, and what the
change board decided for each significant change. Without it, engineers who "update the model because the prime's
model changed" can create unfunded scope.

Where the content comes from:
  - The Prime Drop issue: version, delivery date, transmittal, sha256 check, markings.
  - The delta and impact report (`xmi2sysml.pl --delta OLD.xmi NEW.xmi --impact model`).
  - One prime-change issue per significant change, each with a disposition:: label.
Dispositions: accept / accept with cost or schedule impact / reject or clarify (goes back to the prime as a DR) /
no impact.
Render: perl $KIT/tools/memo/memo-build.pl FILE.md
-->
# <<Organization name>>

## <<Office symbol>>

## <<DD Month YYYY>>

<!-- Addressed to the record, copied to the program manager and contracts by distribution. -->
## Memorandum for Record

## From: <<Chair of the change board, e.g. Tidewater MBSE Lead>>

## Subject: Disposition of prime drop <<version>> (<<CDRL number and title>>)

## References: (a) <<CDRL and contract reference>>; (b) <<Prime Drop issue #n>>; (c) <<delta and impact report, pipeline job or file>>

<!-- Paragraph 1: what arrived, when, and that it was checked. -->
<<Drop VERSION, delivered DATE under CDRL, was received on DATE. Every file matched the sha256 recorded in its manifest.>>

<!-- Paragraph 2: what it changes, in numbers: from the delta and impact report. -->
<<Compared with drop PREVIOUS, it adds ..., removes ... and changes ... elements. For the government model it touches ... requirements, ... verification cases and ... interfaces; ... hand-made changes must be redone.>>

<!-- Paragraph 3: the disposition of each significant change, as a table. -->
<<The change board met on DATE and dispositioned the changes as follows:>>

| Change | Prime ID | Disposition | Impact | Issue |
|:-------|:---------|:------------|:-------|:------|
| <<e.g. new humidity sensor and requirement>> | <<xmi:id or change number>> | <<Accept>> | <<none>> | <<#n>> |
| <<...>> | <<...>> | <<Reject or clarify: DR-n to the prime>> | <<...>> | <<#n>> |

<!-- Paragraph 4: discrepancy reports closed or opened by this drop. -->
<<This drop closes ... and opens ... .>>

<!-- Paragraph 5: implementation: merge requests and the target sprint. -->
<<Accepted changes are implemented through merge requests citing the prime change ID, in sprint N.>>

<<The point of contact is the undersigned, at EMAIL.>>

## <<NAME>>

## <<Title, office>>
