DOORS -> SysML v2 in Windows PowerShell 5.1 (ps\sysml)
=====================================================

Three of the agile kit's requirement tools, ported from Perl so they run on a baseline government PC with only
Windows PowerShell 5.1 (Constrained Language Mode is fine), Excel and Teams. No Perl, Java, git or network.
Same options, same output files byte for byte, same exit codes as the Perl tools.

  reqif2sysml.cmd   DOORS ReqIF (.reqif / .reqifz) or a DOORS CSV export -> SysML v2 requirement packages,
                    one file per DOORS module, plus the trace report (status metrics C, F, G, I) against a model folder
  doors2v2.cmd      DOORS 9 / DOORS Next modules (CSV, TSV, ReqIF) -> SysML v2 packages with short-name IDs, headings
                    as groups, information objects as comments, DOORS links as satisfy / verify / dependency;
                    writes ids.tsv (the DOORS id -> SysML v2 name map) and CONVERSION.txt (what to finish by hand)
  req-recipe.cmd    grade requirement text against the requirement recipe (18 parts, 6 required), with --links for
                    trace, rationale and verification (elements 19-23); text, csv, junit or codequality output

Files: reqiflib.ps1 (shared code: the XML reader, the SysML v2 text helpers, the ReqIF/CSV loader) must stay beside
the three tools. A .reqifz needs ..\ziplib.ps1 (the kit's ps\ folder layout).

From a DOORS export to SysML v2 files
-------------------------------------
1. In DOORS, export each formal module: File > Export > ReqIF (or "Export to Spreadsheet" and save as
   CSV UTF-8). Copy the files to a work folder, e.g. Documents\hws\doors.
2. Open PowerShell in that folder:  cd $HOME\Documents\hws\doors
3. Look before converting:
     ..\..\agile\ps\sysml\reqif2sysml.cmd --report HWS-RTM-001.reqif
   (objects, requirements, headings, links, verification methods, and the file each module will become)
4. Convert:
     ..\..\agile\ps\sysml\reqif2sysml.cmd --out ..\model --layout-map layout.map HWS-RTM-001.reqif
   or, keeping DOORS IDs as short names and links as relationships:
     ..\..\agile\ps\sysml\doors2v2.cmd -o ..\v2 --prefix Halberd --tests STP --keep Priority SRS.csv STP.csv
   Read CONVERSION.txt: every "warning" line is a decision for an engineer, with file:line.
5. Grade the text:
     ..\..\agile\ps\sysml\req-recipe.cmd --format csv -o grades.csv ..\model
   Open grades.csv in Excel (one row per requirement: score, missing parts, findings).
6. Trace against the model as it grows (each new DOORS drop):
     ..\..\agile\ps\sysml\reqif2sysml.cmd --report --model ..\model HWS-RTM-001.reqif
   C linked, F orphan, G unverified, I complete, and "text differs from DOORS" (drift) per requirement.

If .ps1 files are blocked ("running scripts is disabled"), load the text instead of the file, once per window:
  function reqif2sysml { Invoke-Expression ('& {' + (Get-Content -Raw "$HOME\Documents\agile\ps\sysml\reqiflib.ps1") + "`n" + ((Get-Content -Raw "$HOME\Documents\agile\ps\sysml\reqif2sysml.ps1") -replace '\. "\$PSScriptRoot\\reqiflib.ps1"', '') + "`n} " + ($args -join ' ')) }
(the same pattern for doors2v2 and req-recipe; put quotes inside quotes for arguments with spaces).

What differs from the Perl tools
--------------------------------
- Console output: Windows PowerShell writes to the console in its code page (437 on a US PC), so non-ASCII
  characters (degree signs, en dashes, accented names) print as that code page shows them. Files are always
  written as UTF-8, byte for byte what the Perl writes. Use --out / -o and open the files.
- reqif2sysml --check runs sysml.ps1 beside these tools when it is there (instead of tools/sysml/sysml.pl); without
  it, the structural self-check (always on) is the only check, as the Perl says when sysml.pl is missing.
- req-recipe --top takes a .NET regular expression (ECMAScript mode): the usual Perl patterns work.
- Windows-1252 and ISO-8859-1 are the single-byte encodings a ReqIF declaration may name (the Perl's Encode knows
  more; DOORS writes UTF-8 or one of these).
- Getopt::Long's quirks are kept: options may be abbreviated (--rep for --report), and an ambiguous or unknown
  option is refused with the same message.
