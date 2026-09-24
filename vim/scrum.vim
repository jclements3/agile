" Scrum battle-rhythm bindings.  In ~/.vimrc:   source /path/to/agile/vim/scrum.vim
" Works from any directory inside the project (daily.pl finds scrum.conf upward).
let s:root = expand('<sfile>:p:h:h')
let g:scrum_daily = get(g:, 'scrum_daily', s:root . '/bin/daily.pl')
execute 'set runtimepath+=' . fnameescape(s:root . '/vim')

function! s:Daily(args) abort
  execute '!perl ' . shellescape(g:scrum_daily) . ' ' . a:args
endfunction
" ---------------------------------------------------------------- the townhall in one Vim tab, no mouse
" :STown (\sw)   chat buffer left | lint table top-right | replies bottom-right.  \sp pastes the clipboard (Ctrl-A Ctrl-C in
" the Teams chat) at the end of the chat and lints; \sy puts the replies on the clipboard for Ctrl-V into Teams; :SSend Bob
" opens the 1:1 Teams chat with Bob's reply pre-filled. Ctrl-W h/j/k/l moves between the three windows as usual.
function! s:TownDir() abort
  let l:conf = findfile('scrum.conf', '.;')
  return fnamemodify(l:conf, ':p:h')
endfunction
function! s:Town() abort
  let l:dir = s:TownDir()
  let l:chat = l:dir . '/standups/' . strftime('%Y-%m-%d') . '-chat.txt'
  tabnew
  silent execute 'edit ' . fnameescape(l:chat)
  set filetype=teamschat
  silent vertical botright new | setlocal buftype=nofile bufhidden=hide noswapfile nowrap | silent file townhall-lint
  silent belowright new       | setlocal buftype=nofile bufhidden=hide noswapfile wrap   | silent file townhall-replies
  wincmd t
  if getfsize(l:chat) > 0 | silent call s:Refresh() | endif  " the console was (re)opened mid-meeting: lint what is already there
  redraw
  echo 'townhall: \sp paste+lint  \sl lint  \sy replies to clipboard  :SSend Name  Ctrl-W h/l to move'
endfunction
function! s:Refresh() abort                     " fill the two scratch windows from the chat buffer
  let l:chat = expand('%:p')
  let l:table = systemlist('perl ' . shellescape(g:scrum_daily) . ' lint --table ' . shellescape(l:chat))
  let l:reply = systemlist('perl ' . shellescape(g:scrum_daily) . ' lint --reply --confirm ' . shellescape(l:chat))
  let l:cur = winnr()
  for [l:name, l:lines] in [['townhall-lint', map(copy(l:table), 'substitute(v:val, "\t", "  ", "g")')], ['townhall-replies', l:reply]]
    let l:w = bufwinnr(l:name)
    if l:w > 0
      execute l:w . 'wincmd w'
      setlocal modifiable | silent %delete _ | call setline(1, l:lines) | setlocal nomodifiable
    endif
  endfor
  execute l:cur . 'wincmd w'
  let l:n = len(filter(copy(l:table), 'v:val !~# "^state"')) | let l:bad = len(filter(copy(l:table), 'v:val =~# "^ERROR"'))
  echo 'lint: ' . l:n . ' answered, ' . l:bad . ' with errors'
endfunction
function! s:PasteLint() abort                   " \sp: the clipboard (the Teams chat, Ctrl-A Ctrl-C) appended to the chat buffer, saved, linted
  normal! G
  execute 'normal! "+p'
  update
  call s:Refresh()
endfunction
function! s:YankReplies() abort                 " \sy: the replies window to the clipboard, ready for Ctrl-V in the Teams chat
  let l:w = bufwinnr('townhall-replies')
  if l:w < 0 | echo 'no replies window (:STown first)' | return | endif
  let l:lines = getbufline(bufnr('townhall-replies'), 1, '$')
  let @+ = join(l:lines, "\n") . "\n"
  echo len(l:lines) . ' reply lines on the clipboard'
endfunction
function! s:Send(who) abort                     " :SSend Bob -- open the 1:1 Teams chat with Bob's reply pre-filled (needs roster.txt for the e-mail)
  let l:chat = expand('%:p')
  let l:out = systemlist('perl ' . shellescape(g:scrum_daily) . ' lint --private --confirm ' . shellescape(l:chat))
  let l:page = matchstr(join(l:out, "\n"), 'wrote \zs\S\+lint\.html')
  if l:page ==# '' | echo join(l:out, "\n") | return | endif
  for l:line in readfile(l:page)
    let l:m = matchlist(l:line, '<h3>\(.\{-}\) <a class=send href="\([^"]\+\)"')
    if !empty(l:m) && l:m[1] =~? '^' . a:who
      let l:url = substitute(l:m[2], '&amp;', '\&', 'g')
      call system('powershell.exe -NoProfile -Command Start-Process ' . shellescape(l:url))
      echo 'opened 1:1 with ' . l:m[1] . ' -- press Send in Teams'
      return
    endif
  endfor
  echo 'no 1:1 link for ' . a:who . ' (not in roster.txt with an e-mail, or no reply for them)'
endfunction
function! s:Lint() abort                        " lint the Y/T/B statuses in the current chat buffer; results in the quickfix list, :cn jumps to the person
  if bufwinnr('townhall-lint') > 0 | update | call s:Refresh() | return | endif
  update
  let l:out = systemlist('perl ' . shellescape(g:scrum_daily) . ' lint ' . shellescape(expand('%:p')))
  let l:save = &errorformat
  set errorformat=%f:%l:\ %m,%-G#%.%#
  cexpr l:out
  let &errorformat = l:save
  let l:bad = len(filter(copy(l:out), 'v:val =~# ": ERROR "'))
  if l:bad | copen | else | cclose | echo join(filter(copy(l:out), 'v:val =~# "^#"'), ' ') | endif
endfunction
function! s:Tig() abort                         " browse the project's git history in tig (Git for Windows ships it); q returns to Vim
  let l:conf = findfile('scrum.conf', '.;')
  execute '!cd ' . shellescape(fnamemodify(l:conf, ':p:h')) . ' && tig'
endfunction
function! s:Cockpit() abort                     " rebuild <kit>/dashboard.html for the current project (agile.pl beside the kit's lib/)
  let l:conf = findfile('scrum.conf', '.;')
  let l:out = systemlist('perl ' . shellescape(fnamemodify(g:scrum_daily, ':h:h') . '/agile.pl') . ' --no-open ' . shellescape(fnamemodify(l:conf, ':p:h')))
  echo join(l:out, "\n")
endfunction
function! s:New(args) abort
  let l:out = systemlist('perl ' . shellescape(g:scrum_daily) . ' new ' . a:args)
  if v:shell_error | echohl ErrorMsg | echo join(l:out, "\n") | echohl None | return | endif
  execute 'edit ' . fnameescape(l:out[-1])
  normal! G
endfunction

command! -nargs=* SNew     call s:New(<q-args>)
command!          SStatus  call s:Daily('status')
command!          SCompile call s:Daily('compile')
command!          SDry     call s:Daily('--dry compile')
command!          SReport  call s:Daily('report')
command!          SDraft   call s:Daily('draft')
command!          SAll     call s:Daily('all')
command!          SCommit  call s:Daily('commit')
command! -nargs=* SSprint  call s:Daily('sprint ' . <q-args>)
command! -nargs=* SBacklog call s:Daily('backlog ' . <q-args>)
command! -nargs=* SMembers call s:Daily('members ' . <q-args>)
command!          SBlocked call s:Daily('blocked')
command!          SRoadmap call s:Daily('roadmap')
command! -nargs=? SQuad    call s:Daily('quad <args>')
command!          SCockpit call s:Cockpit()
command!          STig     call s:Tig()
command! -nargs=+ -complete=file SDocs execute '!perl ' . shellescape(s:root . '/bin/docs2txt.pl') . ' ' . <q-args>
command!          SChat    call s:Chat()
command!          STally   call s:Daily('chat')
command!          SAnswers  call s:Daily('answers')
command!          SLint     call s:Lint()
command!          STown     call s:Town()
command! -nargs=1 SSend     call s:Send(<q-args>)
command! -nargs=* SPropose call s:Daily('propose ' . <q-args>)
command!          SLintReply call s:Daily('lint --reply ' . shellescape(expand('%:p')))
command!          SAi       call s:Daily('ai')
command!          SAiPrompt   execute 'edit ' . fnameescape(s:Reports() . '/' . strftime('%Y-%m-%d') . '-ai-prompt.txt')
command!          SAiResponse execute 'edit ' . fnameescape(s:Reports() . '/' . strftime('%Y-%m-%d') . '-ai-response.txt')
command! -nargs=1 SChatTeam call s:ChatTeam(<q-args>)
command! -nargs=* SCards   call s:Daily('cards ' . <q-args>)
command!          SJoined  call s:Daily('joined')
command!          SJournal execute 'edit ' . fnameescape(s:Journal())
function! s:Reports() abort
  let l:conf = findfile('scrum.conf', '.;')
  return fnamemodify(l:conf, ':h') . '/reports'
endfunction
function! s:ChatTeam(team) abort
  let l:conf = findfile('scrum.conf', '.;')
  execute 'edit ' . fnameescape(fnamemodify(l:conf, ':h') . '/standups/' . strftime('%Y-%m-%d') . '-' . a:team . '-chat.txt')
endfunction
function! s:Chat() abort
  let l:conf = findfile('scrum.conf', '.;')
  let l:dir  = fnamemodify(l:conf, ':h')
  execute 'edit ' . fnameescape(l:dir . '/standups/' . strftime('%Y-%m-%d') . '-chat.txt')
endfunction
function! s:Journal() abort
  let l:conf = findfile('scrum.conf', '.;')
  let l:dir = fnamemodify(l:conf, ':h')
  for l:line in readfile(l:conf)
    if l:line =~# '^\s*journal\s*='
      return l:dir . '/' . substitute(l:line, '^\s*journal\s*=\s*', '', '')
    endif
  endfor
  return l:dir . '/scrum.txt'
endfunction

nnoremap <leader>sn :SNew<CR>
nnoremap <leader>ss :SStatus<CR>
nnoremap <leader>sc :w<CR>:SCompile<CR>
nnoremap <leader>sd :w<CR>:SDry<CR>
nnoremap <leader>sr :SReport<CR>
nnoremap <leader>sa :w<CR>:SAll<CR>
nnoremap <leader>sj :SJournal<CR>
nnoremap <leader>st :w<CR>:STally<CR>
nnoremap <leader>sl :w<CR>:SLint<CR>
nnoremap <leader>sp :call <SID>PasteLint()<CR>
nnoremap <leader>sy :call <SID>YankReplies()<CR>
nnoremap <leader>sw :STown<CR>

augroup scrum_ft
  autocmd!
  autocmd BufRead,BufNewFile scrum.txt,*.ledger,*.journal set filetype=ledger
  autocmd BufRead,BufNewFile */standups/*-chat.txt set filetype=teamschat
  autocmd BufRead,BufNewFile */standups/*.txt if expand('%:t') !~# '-chat\.txt$' | set filetype=standup | endif
augroup END

" stand-up buffers: complete story ids from the journal with <C-x><C-]> style via 'complete'
augroup scrum_standup
  autocmd!
  autocmd FileType standup setlocal complete+=k iskeyword+=- commentstring=;\ %s
  autocmd FileType standup execute 'setlocal dictionary+=' . fnameescape(s:Journal())
  autocmd FileType ledger  setlocal iskeyword+=-,: commentstring=;\ %s
augroup END
