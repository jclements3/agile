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
"   \mw \mq \mi \mp :SysDraw tree|trace|ibd|pkg   draw a view (tools/sysml/views) to KIND.svg in the current
"                    directory; g:sysml_svg_viewer (e.g. 'explorer.exe' or 'xdg-open') opens it
"   \mg :SysGate      the validate gate (text, trace, markings, zones, threats): findings to the quickfix list
"   \mW :SysView      the live viewer (bin/sysml-view.tcl, Tk) for this project, in the background (g:sysml_wish)
"   \mf               show the name under the cursor (or the enclosing def) in the viewer (~/.sysml-view/focus)
"   \mo               open the file:line last clicked in the viewer (~/.sysml-view/jump)
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
function! s:Draw(kind) abort
  let l:cmd = s:Model('draw ' . a:kind)
  if l:cmd ==# '' | return | endif
  update
  let l:out = systemlist(l:cmd)
  echo join(l:out, "\n")
  let l:svg = fnamemodify(a:kind . '.svg', ':p')
  if exists('g:sysml_svg_viewer') && filereadable(l:svg)
    call system(g:sysml_svg_viewer . ' ' . shellescape(l:svg))
  endif
endfunction
command! -buffer -nargs=1 -complete=customlist,s:DrawKinds SysDraw call s:Draw(<q-args>)
function! s:DrawKinds(A, L, P) abort
  return filter(['tree', 'trace', 'ibd', 'pkg'], 'v:val =~# "^" . a:A')
endfunction
command! -buffer SysGate     call s:Make('gate')
" the live viewer: bin/sysml-view.tcl talks to Vim through two files in ~/.sysml-view
let s:state = expand('~/.sysml-view')
if !exists('s:view_fns')    " defined once: \mo edits a .sysml file, which sources this file again while s:Jump runs
let s:view_fns = 1
function! s:View() abort
  let l:r = s:Root()
  if l:r ==# '' | echoerr 'SysML: no model/ directory above this file' | return | endif
  update
  let l:wish = get(g:, 'sysml_wish', 'wish')
  let l:tcl = fnamemodify(s:tools, ':h:h') . '/bin/sysml-view.tcl'
  if has('win32')
    execute 'silent !start "" ' . shellescape(l:wish) . ' ' . shellescape(l:tcl) . ' ' . shellescape(l:r)
  else
    execute 'silent !' . shellescape(l:wish) . ' ' . shellescape(l:tcl) . ' ' . shellescape(l:r) . ' >/dev/null 2>&1 &'
  endif
  redraw!
endfunction
function! s:Focus() abort
  let l:w = expand('<cword>')
  if l:w !~# '^\h\w*$' || l:w =~# '^\(part\|port\|item\|action\|def\|package\|requirement\|interface\|attribute\|private\|import\|doc\)$'
    let l:n = search('\<def\s\+\zs\h\w*', 'bnW')
    let l:w = l:n ? matchstr(getline(l:n), '\<def\s\+\zs\h\w*') : ''
  endif
  if l:w ==# '' | echo 'SysML: no name under the cursor' | return | endif
  call mkdir(s:state, 'p')
  call writefile([l:w], s:state . '/focus')
  echo 'sysml-view: focus ' . l:w
endfunction
function! s:Jump() abort
  let l:f = s:state . '/jump'
  if !filereadable(l:f) | echo 'SysML: nothing clicked in the viewer yet' | return | endif
  let l:m = matchlist(get(readfile(l:f), 0, ''), '^\(.\{-}\):\(\d\+\)$')
  if empty(l:m) | echo 'SysML: ' . l:f . ' holds no file:line' | return | endif
  execute 'edit +' . l:m[2] . ' ' . fnameescape(l:m[1])
endfunction
endif
command! -buffer SysView     call s:View()
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
nnoremap <buffer> <silent> <LocalLeader>mw :SysDraw tree<CR>
nnoremap <buffer> <silent> <LocalLeader>mq :SysDraw trace<CR>
nnoremap <buffer> <silent> <LocalLeader>mi :SysDraw ibd<CR>
nnoremap <buffer> <silent> <LocalLeader>mp :SysDraw pkg<CR>
nnoremap <buffer> <silent> <LocalLeader>mg :SysGate<CR>
nnoremap <buffer> <silent> <LocalLeader>mW :SysView<CR>
nnoremap <buffer> <silent> <LocalLeader>mf :call <SID>Focus()<CR>
nnoremap <buffer> <silent> <LocalLeader>mo :call <SID>Jump()<CR>

let b:undo_ftplugin = 'setl et< sw< sts< ts< cms< com< isk< tags< fdm< fdl< mp< efm<'
