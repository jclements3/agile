tools/sysml/views - SysML v2 views and security checks, core Perl 5 only (Git for Windows' Perl)

Every tool here runs standalone on a model directory or files. Inside a project, model.pl runs them
on the project's model/ and passes the other options through:
  perl tools/sysml/model.pl draw tree|trace|ibd|pkg [-o FILE] [options]   sysml-{tree,trace,ibd,pkg}-svg.pl
  perl tools/sysml/model.pl plates [-o DIR] [options]                     sysml-plates.pl
  perl tools/sysml/model.pl diff OLD_DIR | diff --git OLD[..NEW]           sysml-diff.pl
  perl tools/sysml/model.pl threats [--today D]                           sysml-threats.pl
  perl tools/sysml/model.pl gate [--today D] [--strict]                   sysml-check.pl
Help: perl agile.pl help agile-sysml-views (and agile-model-draw, -plates, -diff, -threats, -gate).
library/SecMeta.sysml is the security vocabulary the checks read (copy it into model/);
library/DrawingMeta.sysml adds @Drawing for plates. binder/ holds sysml-gate.pl and sysml-trace.pl,
the two text-level checks sysml-check.pl runs first. The fallback converters v1v2.pl and doors2v2.pl
are in tools/sysml/ (the main path is bin/xmi2sysml.pl and bin/reqif2sysml.pl).
The worked example: perl tools/sysml/model.pl --root examples/halberd gate --today 2026-10-05
svg2tk.pl turns a drawer's SVG into Tk canvas primitives for the live viewer bin/sysml-view.tcl
(wish bin/sysml-view.tcl PROJECT-DIR [--view tree|trace|ibd|pkg]; in Vim: \mW, \mf, \mo).

sysml-check.pl - the validate gate in one command (start here)
  perl sysml-check.pl [--tools DIR] [--only a,b] [--svg DIR] [--today YYYY-MM-DD] [--strict] [MODEL_DIR]
  Runs the binder's sysml-gate.pl and sysml-trace.pl (found via --tools, this folder, its binder/
  folder, or ./tools), then the marking, zone and threat checks below; one line:
  check: ... -> PASS|FAIL. Accepted risks are listed but pass unless --strict. --svg DIR also
  writes the four pictures.

v1v2.pl (tools/sysml/) - SysML v1 (older Cameo, no v2 plugin) to SysML v2 text. Core Perl 5 only.

Inputs Cameo can produce without the v2 plugin:
  MODEL  UML/SysML XMI export (.xmi/.uml/.xml), or the .mdzip project file itself
  REQS   ReqIF export (.reqif/.reqifz), or a requirement table exported to CSV

  perl v1v2.pl inventory MODEL [--tsv]     counts, trace coverage, unresolved types, custom stereotypes
  perl v1v2.pl check     MODEL             pre-process lint: fix these in Cameo before converting
  perl v1v2.pl convert   MODEL -o DIR      SysML v2 text in the binder layout (model/architecture, ...)
  perl v1v2.pl reqs      REQS -o F.sysml --package NAME    requirements only

convert options
  --package 'A::B'   convert one v1 package (the P3 slice); outside references become stubs
  --prefix Halberd   prefix for top-level package names
  --marking U        add SecMeta @Marking to every root package (needs SecMeta in model/library)
  --typemap F        KEY<TAB>V2TYPE[<TAB>UNIT]; KEY = href, href fragment, xmi:id or v1 name
  --keep-names       keep v1 names (quoted where needed) instead of UpperCamel / lowerCamel
  --no-provenance    omit @V1Source { xmiId; v1Name; } on definitions and requirements

convert writes DIR/model/**.sysml, DIR/ids.tsv (xmi:id -> v2 name -> file:line) and
DIR/CONVERSION.txt (GNU-format notes pointing into the XMI; 'warning' = finish by hand).

What converts: packages, blocks, interface blocks (port defs, flow properties as directed
features), value types (ISQ quantities from "mass[kilogram]" names or unit/quantityKind),
enumerations, part/reference/value properties with multiplicity, redefinition and defaults
(with units), ports (conjugation), binary connectors, generalization, constraint block
parameters, requirements (id as short name, text as doc, nesting), satisfy, verify
(objective-only verification defs), deriveReqt/refine/trace/copy (dependencies), comments.
Reported, not converted: behaviors, use cases, item flows, allocations, instances, constraint
expressions, custom stereotypes, diagrams.

P3 workflow
  1. perl v1v2.pl inventory MODEL --tsv >> results.tsv
  2. perl v1v2.pl check MODEL            (fix in Cameo, or record as findings)
  3. perl v1v2.pl convert MODEL -o text --package 'Slice::Package' --prefix Halberd
  4. perl tools/sysml/views/sysml-check.pl text/model     (the gate: text, trace, markings, zones, threats)
  5. Pilot validate (perl tools/sysml/model.pl validate, needs Java)
  6. Time the warnings in CONVERSION.txt: that is the hand-finish cost per slice.

sysml-trace-svg.pl - requirement trace view of any SysML v2 model (not just converted ones)
  perl sysml-trace-svg.pl [-o trace.svg] [--title T] [--gaps] [--match REGEX] DIR|FILE...
  Columns: satisfying features | requirement tree with S/V status | verification cases.
  --mono draws the S/V status as shapes for black-and-white print.
  Same rules as the binder's sysml-trace.pl (leaf covered by itself or a group above; N- needs
  not judged), same leaf and gap counts. Open the SVG in a browser: hover a row or box to
  highlight its links; tooltips carry the doc text and file:line.

sysml-tree-svg.pl - part decomposition (general view), left to right
  perl sysml-tree-svg.pl [-o tree.svg] [--title T] [--root NAME]... [--all] [--depth N]
                         [--features] [--outline] [--hide-meta A,B] DIR|FILE...
  Roots: every part def with parts that is not another def's composite part type (or --root).
  Each part is expanded through its type: inherited parts (^), redefinitions (:>>) and
  in-place nested refinements applied. ref parts dashed and not expanded; recursion stopped
  and reported. --features adds attribute/port compartments; --outline flags 2-9 violations
  (G12). Metadata names (@L3System) show on the keyword line; tooltips carry doc and file:line.

sysml-pkg-svg.pl - packages, dependencies and SecMeta markings, with the marking checks (SEC-4)
  perl sysml-pkg-svg.pl [-o packages.svg] [--title T] [--nested] [--hide P,Q] [--levels U,CUI,ITAR] DIR|FILE...
  Boxes colored by effective marking (a side stripe when a package contains something higher);
  arrows from user to provider, providers on the right. Errors: root package with no @Marking,
  write-down (a lower package imports, references or specializes a higher package or element,
  element-level @Marking included). Warnings: text leakage (a higher element's name in a lower
  package's names, doc or comments) and dependency cycles. Levels come from `enum def Level`.
  Exit 1 on errors, so it can run as the marking gate. --hide keeps busy libraries (SecMeta)
  out of the picture but still checks them.

sysml-ibd-svg.pl - interconnection view, colored by trust zone, with boundary coverage (SEC-1)
  perl sysml-ibd-svg.pl [-o ibd.svg] [--title T] [--root NAME]... DIR|FILE...
  One frame per part def that owns connections (or --root): its parts (^inherited, ref dashed),
  ports on box edges (filled = conjugated), the def's own ports on the frame, and every connect,
  interface and flow (inherited included). Ends deeper than one level attach to the part box,
  labelled with the rest of the path. Zones from @TrustZone on the usage or its def, else the
  container's. Ends: 'connect a to b', or 'end ::> a.b;' lines in the connection's body. Error: a
  connection between different zones with no satisfied @SecurityRequirement whose subject is (or
  contains) the owning def, or that the connection names in attribute secReq = "req". Warning: a
  connection whose fromZone / toZone attributes disagree with its ends' zones. Note: connections
  touching the untrusted zone (derived attack surface). Exit 1 on errors.

sysml-threats.pl - threat completeness (SEC-2) and mitigation closure (SEC-3), with a threat table
  perl sysml-threats.pl [--today YYYY-MM-DD] DIR|FILE...
  Errors: a @Threat without one of the six STRIDE categories or a CAPEC-n id; a threat not named
  by a @Mitigates on a requirement that is satisfied and verified (itself or a group above);
  a @Mitigates naming an unknown threat; an expired or unsigned @RiskAcceptance. A current
  acceptance (approver set, expires >= today) turns an open threat into a warning, shown on every
  run. A threat is an element with @Threat, or one line metadata t : Threat { asset; mitigation;
  stride; capec; } (the status-metrics form); its mitigation attribute must match the @Mitigates
  (warning otherwise). --today pins the date for repeatable runs. Exit 1 on errors.

sysml-plates.pl - drawing plates from the model's views (ISO 5457 sheet, ISO 7200 title block)
  perl sysml-plates.pl [-o DIR] [--size auto|A4..A0] [--auto] [--color] [--owner T] [--creator T]
                       [--approver T] [--status T] [--rev R] [--date D] [--prefix DWG] [--source T] DIR|FILE...
  One plate per `view` usage: render asTreeDiagram / asInterconnectionDiagram / asElementTable /
  asTextualNotation (a view def named *Package* draws the package view; a RequirementUsage filter
  draws the trace view). No views (or --auto): one plate per top tree, per wired def, trace, packages.
  Sheet: frame 20 mm left / 10 mm elsewhere, centring marks, grid reference (numbers across,
  letters down, no I or O), line widths 0.7 / 0.35 / 0.18 mm, security marking top and bottom.
  Title block: security class, scale (NTS), source (git describe), legal owner, document type
  and status, technical reference, title and subtitle, created/approved by, identification
  number, revision, date, language, sheet n/N. Number = the view's short name <'DWG-001'>,
  title = its doc's first sentence; @Drawing { ... } (DrawingMeta.sysml) overrides any field.
  --size auto picks the smallest sheet keeping diagram text >= --min-text (2.0 mm). Black on
  white unless --color. Writes DIR/<number>.svg and DIR/plates.html (prints one sheet per page,
  at size; print to PDF from the browser).

doors2v2.pl (tools/sysml/) - DOORS 9 / DOORS Next modules to SysML v2 requirements
  perl doors2v2.pl -o DIR [--prefix P] [--marking L] [--tests MODULE]... [--design MODULE]...
                   [--keep ATTR]... [--map FIELD=COLUMN]... [--id-prefix PFX] [--no-provenance] EXPORT...
  EXPORT: CSV/TSV (UTF-8, UTF-16, cp1252) or ReqIF/.reqifz; several modules at once resolve links.
  Headings -> requirement groups (a heading with nothing below -> comment); information objects
  -> comments; requirements keep the DOORS ID as short name and get @DoorsObject provenance.
  Links: verify (to --tests modules) -> verification defs; satisfy from --design modules ->
  satisfy with placeholder parts to replace; satisfy between requirements, derive, refine,
  trace -> dependencies. Unresolved targets listed with their first location. Writes
  DIR/model/..., ids.tsv (DOORS ID -> v2 name) and CONVERSION.txt. Deterministic: re-run after
  each DOORS export while DOORS stays master, and review the change with sysml-diff.pl.

Comparing versions (review as diff review, PE-1)
  Both renderers take --compare OLD (a directory or files) and --changed (only what changed).
  Added = green, changed = amber, removed = red dashed ghost at its old place; tooltips say
  what changed; one GNU-format line per change is printed. Requirements match by ID (or package
  and path), parts by their path of part names from the root part def.

sysml-diff.pl - both views plus a change list for a merge request
  perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... OLD_DIR NEW_DIR
  perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... --git OLD[..NEW] [PATH...]
  --git OLD alone compares with the working tree. Writes PREFIX-tree.svg, PREFIX-trace.svg and
  PREFIX-changes.txt (locations as REV:path:line). Also runs the marking, zone and threat checks
  on both versions: findings only in the new one are "new finding", only in the old "resolved";
  writes PREFIX-packages.svg and PREFIX-ibd.svg of the new version. Exit 1 when the change adds
  a requirement gap or an error finding. --today is passed to the threat check. Run from Git Bash (uses git ls-tree / git show).

tests: bash tests/run.sh   (golden transcript; --bless after a reviewed change; tests/sysml-views.t runs it)
