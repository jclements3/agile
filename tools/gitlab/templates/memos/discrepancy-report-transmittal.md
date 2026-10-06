<!--
TEMPLATE: Transmittal of discrepancy reports (DRs) to the prime contractor.

The government does not edit the prime's model. Problems found in it (requirement text that differs between DOORS
and the model, requirements nothing satisfies, missing verification, clutter) go back to the prime as discrepancy
reports, formally, through the contracting officer's representative (COR) or whoever the contract names. Each DR
stays open in GitLab (type::discrepancy, owner::prime) until a drop fixes it.

This template also shows portion marking. Tidewater is notional and unmarked; the {CUI}...{/} tags below are only
an example of how md2memo marks a portion. Tagged text makes md2memo add portion marks in the margin and banners
at the top and bottom of every page. Follow your own program's marking guide; delete the tags if nothing is marked.

How to fill it in:
  - One row per DR in the table; the detail lives in each DR issue (attach the export, or list the issue links).
  - Cite the v1 element IDs (xmi:id) the prime's modeler agreed to work from.
  - Ask for a disposition date per DR, or the drop that will carry the fix.
Render: perl $KIT/tools/memo/memo-build.pl FILE.md            (add `-- --mark` to force portion marks)
-->
# <<Organization name>>

## <<Office symbol>>

## <<DD Month YYYY>>

<!-- To the person the contract names as the channel to the prime, usually the COR or contracting officer. -->
## Memorandum for <<Contracting Officer's Representative, contract number>>

## From: <<Tidewater MBSE Lead>>

## Subject: Discrepancy reports against CDRL <<A003>> drop <<version>>

## References: (a) <<contract and CDRL>>; (b) <<model exchange agreement or ICWG charter>>; (c) <<drop disposition memo>>

<!-- Paragraph 1: what is transmitted and why. -->
<<The government's review of drop VERSION found the discrepancies listed below. Request they be transmitted to the prime for disposition.>>

<!-- Paragraph 2: the DRs. Example of a marked portion: delete the tags if your content is not marked. -->
<<The discrepancies are:>> {CUI}<<example of a marked phrase>>{/}

| DR | Element (v1 id) | Discrepancy | Requested action | Requested by |
|:---|:----------------|:------------|:-----------------|:------------:|
| <<DR-n>> | <<requirement or element, xmi:id>> | <<what is wrong, with the evidence>> | <<what the prime should do>> | <<drop or date>> |

<!-- Paragraph 3: how the government will track them. -->
<<Each discrepancy is tracked as an issue until a drop resolves it. The government will verify each fix automatically when the drop is received.>>

<<The point of contact is the undersigned, at EMAIL.>>

## <<NAME>>

## <<Title, office>>
