" SysML v2 model checks for :make, from anywhere inside a project (the nearest directory upward
" holding model/; tools/sysml/model.pl finds it the same way):
"   :make lint       grammar-exact syntax, unresolved types, imports, duplicates, self-bindings
"   :make check      the 2..9 outline rule and @L level tags
"   :make validate   full compile with the SysML v2 Pilot engine (needs Java; skipped otherwise)
" Outside a project, :make checks this file's syntax only (tools/sysml/sysml.pl check).
if exists('current_compiler') | finish | endif
let current_compiler = 'sysml'
let s:tools = expand('<sfile>:p:h:h:h') . '/tools/sysml'
let s:model = finddir('model', expand('%:p:h') . ';')
if s:model !=# ''
  let s:root = fnamemodify(s:model, ':p:h:h')
  execute 'CompilerSet makeprg=' . escape('perl ' . shellescape(s:tools . '/model.pl') . ' --root ' . shellescape(s:root), ' \|"')
else
  execute 'CompilerSet makeprg=' . escape('perl ' . shellescape(s:tools . '/sysml.pl') . ' check %', ' \|"')
endif
" file:line:col: error: message (lint, validate, sysml.pl)   and   file:line: message
CompilerSet errorformat=%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %trror:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#
