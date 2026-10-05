" IDEF0 editing, the Vim twin of tools/idef0/idef0-mode.el. Loaded by vim/scrum.vim's runtimepath.
" A project is every *.txt and *.idef0 file in this file's directory, plus this file (a literate .md model).
"   \il  lint this file (errors to the quickfix list)  \iL  lint the project   \iv  plates as text
"   \id  dump the numbered tree                         \ik  interface table    \in  fmt --number   \iu  fmt --auto
"   \if  jump to this line's link target                \io  new sibling line   zc/zo/za fold a subtree (by indent)
" In Markdown, ```idef0 fences highlight too: let g:markdown_fenced_languages = ['idef0'] in ~/.vimrc.
" Also loaded (by vim/scrum.vim) into Markdown buffers that hold ```idef0 fences: the literate models.
if exists('b:did_idef0') | finish | endif
let b:did_idef0 = 1
if &filetype ==# 'idef0' | let b:did_ftplugin = 1 | endif
let s:tool = expand('<sfile>:p:h:h:h') . '/tools/idef0/idef0.pl'
let g:idef0_program = get(g:, 'idef0_program', 'perl ' . shellescape(s:tool))

setlocal expandtab shiftwidth=2 softtabstop=2 tabstop=2
setlocal commentstring=#\ %s comments=:##,:#,:;;,:;
setlocal foldmethod=indent foldignore= foldlevel=99
let &l:makeprg = g:idef0_program . ' lint %'
setlocal errorformat=%f:%l:\ %trror:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#

function! s:Files() abort
  let l:f = glob(expand('%:p:h') . '/*.{txt,idef0}', 0, 1)
  return index(l:f, expand('%:p')) < 0 ? l:f + [expand('%:p')] : l:f
endfunction
function! s:Project() abort
  return join(map(s:Files(), 'shellescape(v:val)'), ' ')
endfunction
function! s:Lint(files) abort
  update
  let &l:makeprg = g:idef0_program . ' lint ' . a:files
  silent make! | redraw! | botright cwindow
  if &buftype ==# 'quickfix' | wincmd p | endif   " stay in the model; the list is beside it
  let &l:makeprg = g:idef0_program . ' lint %'
  echo get(systemlist(g:idef0_program . ' lint ' . a:files), -1, '')
endfunction
function! s:Show(cmd, name) abort
  update
  let l:out = systemlist(g:idef0_program . ' ' . a:cmd . ' ' . s:Project())
  execute 'silent botright new ' . a:name
  setlocal buftype=nofile bufhidden=wipe noswapfile nowrap
  call setline(1, l:out) | setlocal nomodifiable
endfunction
function! s:Fmt(mode) abort
  update
  let l:out = system(g:idef0_program . ' fmt ' . a:mode . ' --write ' . shellescape(expand('%:p')))
  if v:shell_error | call s:Lint(shellescape(expand('%:p'))) | else | edit! | echo 'idef0 fmt ' . a:mode . ': done' | endif
endfunction
function! s:Follow() abort
  let l:m = matchlist(getline('.'), '[<>]\s*\(.\+\)$')
  if empty(l:m) | echo 'No link on this line' | return | endif
  let l:flow = trim(split(substitute(l:m[1], '\s#.*$', '', ''), '|')[-1])
  let l:pat = '^\s*[icom]\(#\|[1-9]\)\s\+\V' . escape(l:flow, '\')
  for l:f in s:Files()
    let l:n = match(readfile(l:f), l:pat)
    if l:n >= 0 | execute 'edit +' . (l:n + 1) . ' ' . fnameescape(l:f) | return | endif
  endfor
  echo 'Target ' . l:flow . ' not found'
endfunction
function! s:Sibling() abort
  let l:m = matchlist(getline('.'), '^\(\s*\)\([taicom]\)')
  call append('.', empty(l:m) ? 'a# ' : l:m[1] . l:m[2] . '# ')
  normal! j$
  startinsert!
endfunction

command! -buffer IdefLint        call s:Lint('%')
command! -buffer IdefLintProject call s:Lint(s:Project())
command! -buffer IdefPlates      call s:Show('text', 'idef0-plates')
command! -buffer IdefDump        call s:Show('dump', 'idef0-dump')
command! -buffer IdefLinks       call s:Show('links', 'idef0-links')
command! -buffer IdefNumber      call s:Fmt('--number')
command! -buffer IdefAuto        call s:Fmt('--auto')
command! -buffer IdefFollow      call s:Follow()
nnoremap <buffer> <silent> <LocalLeader>il :IdefLint<CR>
nnoremap <buffer> <silent> <LocalLeader>iL :IdefLintProject<CR>
nnoremap <buffer> <silent> <LocalLeader>iv :IdefPlates<CR>
nnoremap <buffer> <silent> <LocalLeader>id :IdefDump<CR>
nnoremap <buffer> <silent> <LocalLeader>ik :IdefLinks<CR>
nnoremap <buffer> <silent> <LocalLeader>in :IdefNumber<CR>
nnoremap <buffer> <silent> <LocalLeader>iu :IdefAuto<CR>
nnoremap <buffer> <silent> <LocalLeader>if :IdefFollow<CR>
nnoremap <buffer> <silent> <LocalLeader>io :call <SID>Sibling()<CR>
let b:undo_ftplugin = get(b:, 'undo_ftplugin', '') . (exists('b:undo_ftplugin') ? ' | ' : '') . 'setlocal et< sw< sts< ts< cms< com< fdm< fdi< fdl< mp< efm< | unlet! b:did_idef0'
