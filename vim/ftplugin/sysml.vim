" SysML v2 editing (tools/sysml/): 4-space indent, // comments, checks into the quickfix list.
" Works from any buffer inside a project: the project is the nearest directory upward holding model/.
"   \ml :SysLint      lint the whole model (errors to the quickfix list, :cn / :cp)
"   \mk :SysCheck     the 2..9 outline rule and @L level tags
"   \mx :SysSyntax    this file only, against the official grammar (tools/sysml/sysml.pl check)
"   \mv :SysValidate  full compile with the Pilot engine (needs Java; skipped cleanly otherwise)
"   \md :SysDocs      regenerate docs/ (nouns, verbs, IDEF0 set, traceability)
"   \mr :SysTrace     the traceability matrix, in a split
"   \mn :SysNouns  \mb :SysVerbs   the part tree / the function tree, in a split
"   \mt :SysTags      write the tags file: Ctrl-] on a name or a DOORS id jumps to it, Ctrl-T back
if exists('b:did_ftplugin') | finish | endif
let b:did_ftplugin = 1

setlocal expandtab shiftwidth=4 softtabstop=4 tabstop=8
setlocal commentstring=//\ %s comments=s1:/*,mb:*,ex:*/,://
setlocal iskeyword+=-
setlocal tags+=./tags;,tags
setlocal foldmethod=syntax foldlevel=99
compiler sysml

let s:tools = expand('<sfile>:p:h:h:h') . '/tools/sysml'
function! s:Root() abort
  let l:m = finddir('model', expand('%:p:h') . ';')
  return l:m ==# '' ? '' : fnamemodify(l:m, ':p:h:h')
endfunction
function! s:Model(args) abort
  let l:r = s:Root()
  if l:r ==# '' | echoerr 'SysML: no model/ directory above this file' | return '' | endif
  return 'perl ' . shellescape(s:tools . '/model.pl') . ' --root ' . shellescape(l:r) . ' ' . a:args
endfunction
function! s:Make(args) abort
  update
  compiler sysml
  execute 'silent make! ' . a:args | redraw! | botright cwindow
  if &buftype ==# 'quickfix' | wincmd p | endif
endfunction
function! s:Syntax() abort
  update
  let l:mp = &l:makeprg
  let &l:makeprg = 'perl ' . shellescape(s:tools . '/sysml.pl') . ' check %'
  silent make! | redraw! | botright cwindow
  if &buftype ==# 'quickfix' | wincmd p | endif
  let &l:makeprg = l:mp
endfunction
function! s:Show(args, name) abort
  let l:cmd = s:Model(a:args)
  if l:cmd ==# '' | return | endif
  let l:out = systemlist(l:cmd)
  execute 'silent botright new ' . a:name
  setlocal buftype=nofile bufhidden=wipe noswapfile nowrap
  call setline(1, l:out) | setlocal nomodifiable
endfunction
function! s:Run(args) abort
  let l:cmd = s:Model(a:args)
  if l:cmd !=# '' | echo join(systemlist(l:cmd), "\n") | endif
endfunction

command! -buffer SysLint     call s:Make('lint')
command! -buffer SysCheck    call s:Make('check')
command! -buffer SysValidate call s:Make('validate')
command! -buffer SysSyntax   call s:Syntax()
command! -buffer SysDocs     call s:Run('docs')
command! -buffer SysTags     call s:Run('tags')
function! s:Trace() abort
  call s:Run('trace')
  if s:Root() !=# '' | execute 'botright split ' . fnameescape(s:Root() . '/docs/Traceability.md') | endif
endfunction
command! -buffer SysTrace    call s:Trace()
command! -buffer SysNouns    call s:Show('nouns --plain', 'sysml-nouns')
command! -buffer SysVerbs    call s:Show('verbs --plain', 'sysml-verbs')
nnoremap <buffer> <silent> <LocalLeader>ml :SysLint<CR>
nnoremap <buffer> <silent> <LocalLeader>mk :SysCheck<CR>
nnoremap <buffer> <silent> <LocalLeader>mx :SysSyntax<CR>
nnoremap <buffer> <silent> <LocalLeader>mv :SysValidate<CR>
nnoremap <buffer> <silent> <LocalLeader>md :SysDocs<CR>
nnoremap <buffer> <silent> <LocalLeader>mr :SysTrace<CR>
nnoremap <buffer> <silent> <LocalLeader>mn :SysNouns<CR>
nnoremap <buffer> <silent> <LocalLeader>mb :SysVerbs<CR>
nnoremap <buffer> <silent> <LocalLeader>mt :SysTags<CR>

let b:undo_ftplugin = 'setl et< sw< sts< ts< cms< com< isk< tags< fdm< fdl< mp< efm<'
