# SysML v2 Release -- vendored subset

Source:  https://github.com/Systems-Modeling/SysML-v2-Release
Release: 2026-08 (commit fb97b754f29588b8e9c7a35f370880cd15eb29e7, 2026-09-11)
Fetched: 2026-09-30

Licence: the KerML and SysML v2 models and software in that repository are licensed
by their respective copyright holders under the Eclipse Public License 2.0 (see
LICENSE). The grammars (bnf/*.kebnf) are the textual-notation grammars of the OMG
KerML and SysML v2 specifications as published in that repository.

Contents (unmodified copies):
- bnf/KerML-textual-bnf.kebnf, bnf/SysML-textual-bnf.kebnf -- the grammars that
  tools/sysml/sysml.pl compiles into its parser;
- sysml.library/ -- the standard model library;
- examples/sysml/, examples/kerml/ -- example models, used as the parser's test corpus.

To update: fetch a newer release into this folder and re-run
'perl tools/sysml/sysml.pl corpus'.
