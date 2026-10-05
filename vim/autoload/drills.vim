" Coding drills in Vim: the memory trainer ("vanishing cues") and the ladder glue. Commands in vim/plugin/drills.vim.
"
" The trainer: every section of drills/ is a level, every reference solution (drills/*/*/solution.pl, its comment
" block stripped) a card. A card shows the first line of a solution -- usually `sub two_sum {` -- and you type the
" rest. Each card is a cycle of g:drills_fade_steps reps: rep 1 shows the whole solution to copy, each rep after
" shows it with more tokens blanked out, the last rep shows nothing. Only that blind rep counts. A wrong answer on
" a hinted rep repeats the rep; giving up on a hinted rep fades further. A level is cleared only when every card's
" blind rep was right first try; that unlocks the next level. Progress (the highest unlocked level) is kept in the
" workspace, trainer.txt, never in the kit. Comments, blank lines, spacing and indentation are ignored when checking.
"
" The ladder glue: :DrillOpen jumps between a problem's statement and your file in the workspace (making it with
" drill.pl start the first time); :DrillTest runs drill.pl test on it; :DrillTestAll runs drill.pl check.
" Works in Vim 8.2+ (Git for Windows ships Vim 9). Legacy Vim script, no +python.

let s:root = expand('<sfile>:p:h:h:h')
let s:marker = '>>> type the answer below this line; everything above it is ignored'
let s:g = {'state': 'idle'}

" ---------------------------------------------------------------- settings
function! drills#Root() abort
  return get(g:, 'drills_root', s:root)
endfunction
function! drills#Work() abort
  let l:d = get(g:, 'drills_work', $DRILLS_WORK !=# '' ? $DRILLS_WORK : expand('~') . '/drills-work')
  return substitute(l:d, '[\\/]\+$', '', '')
endfunction
function! s:Steps() abort
  return max([1, get(g:, 'drills_fade_steps', 5)])
endfunction
function! s:Drill(args) abort
  return 'perl ' . shellescape(drills#Root() . '/drills/drill.pl') . ' --dir ' . shellescape(drills#Work()) . ' ' . a:args
endfunction

" ---------------------------------------------------------------- cards
function! drills#Strip(lines) abort
  " A solution file -> the card: the leading comment block, use strict/warnings and the closing 1; removed.
  let l:out = []
  let l:head = 1
  for l:l in a:lines
    if l:head && (l:l =~# '^\s*#' || l:l =~# '^\s*$') | continue | endif
    let l:head = 0
    if l:l =~# '^\s*use \(strict\|warnings\)\s*;\s*$' | continue | endif
    call add(l:out, substitute(l:l, '\r$', '', ''))
  endfor
  while !empty(l:out) && l:out[-1] =~# '^\s*\(1;\)\=\s*$' | call remove(l:out, -1) | endwhile
  while !empty(l:out) && l:out[0] =~# '^\s*$' | call remove(l:out, 0) | endwhile
  return l:out
endfunction
function! drills#Cards(...) abort
  " -> [ {'name': 'arrays-hashing', 'title': 'Arrays and hashing', 'cards': [ {'id', 'prompt', 'code'} ]} ]
  let l:base = (a:0 ? a:1 : drills#Root()) . '/drills'
  let l:levels = []
  for l:sec in sort(glob(l:base . '/[0-9][0-9]-*', 0, 1))
    if !isdirectory(l:sec) | continue | endif
    let l:name = substitute(fnamemodify(l:sec, ':t'), '^\d\d-', '', '')
    let l:title = l:name
    if filereadable(l:sec . '/section.txt')
      let l:t = matchstr(get(readfile(l:sec . '/section.txt', '', 1), 0, ''), '^Title:\s*\zs.*')
      if l:t !=# '' | let l:title = l:t | endif
    endif
    let l:cards = []
    for l:sol in sort(glob(l:sec . '/*/solution.pl', 0, 1))
      let l:code = drills#Strip(readfile(l:sol))
      if empty(l:code) | continue | endif
      let l:id = substitute(fnamemodify(l:sol, ':h:t'), '^\d\d-', '', '')
      call add(l:cards, {'id': l:id, 'prompt': l:code[0], 'code': l:code})
    endfor
    if !empty(l:cards) | call add(l:levels, {'name': l:name, 'title': l:title, 'cards': l:cards}) | endif
  endfor
  return l:levels
endfunction

" ---------------------------------------------------------------- checking: comments, blank lines and spacing ignored
function! drills#StripComment(line) abort
  " The code part of a Perl line: a # that starts the line or follows a blank, outside quotes ($# and s#..# stay).
  let l:q = ''
  let l:i = 0
  let l:n = strlen(a:line)
  while l:i < l:n
    let l:c = a:line[l:i]
    if l:q !=# ''
      if l:c ==# '\' | let l:i += 2 | continue | endif
      if l:c ==# l:q | let l:q = '' | endif
    elseif l:c ==# '"' || l:c ==# "'"
      let l:q = l:c
    elseif l:c ==# '#' && (l:i == 0 || a:line[l:i - 1] =~# '\s')
      return strpart(a:line, 0, l:i)
    endif
    let l:i += 1
  endwhile
  return a:line
endfunction
function! drills#Normalize(code) abort
  " Text or a list of lines -> one string: comments, blank lines and every space or tab removed.
  let l:lines = type(a:code) == type([]) ? a:code : split(a:code, "\n", 1)
  let l:out = []
  for l:l in l:lines
    let l:s = substitute(drills#StripComment(substitute(l:l, '\r$', '', '')), '\s\+', '', 'g')
    if l:s !=# '' | call add(l:out, l:s) | endif
  endfor
  return join(l:out, "\n")
endfunction
function! drills#Same(answer, code) abort
  return drills#Normalize(a:answer) ==# drills#Normalize(a:code)
endfunction

" ---------------------------------------------------------------- fading: full text, then more tokens blanked, then blind
function! s:Rank(seed, i) abort
  " A fixed pseudo-random number in [0, 1000) per token, so a token blanked at one rep stays blanked at the next.
  let l:x = (a:seed * 7919 + a:i * 104729 + 12345) % 2147483647
  for l:k in range(3)
    let l:x = (l:x * 48271) % 2147483647
  endfor
  return l:x % 1000
endfunction
function! drills#Seed(text) abort
  let l:s = 0
  for l:i in range(strlen(a:text))
    let l:s = (l:s * 31 + char2nr(a:text[l:i])) % 1000003
  endfor
  return l:s
endfunction
function! drills#Fade(lines, step, steps, ...) abort
  " The hint for rep STEP of STEPS: rep 1 the lines as they are, the last rep [] (blind); in between a growing
  " share, (STEP-1)/(STEPS-1), of the tokens (words, numbers, runs of punctuation) replaced by underscores of the
  " same length. Indentation and the line structure stay, so the shape of the solution is always visible.
  if a:steps <= 1 || a:step >= a:steps | return [] | endif
  if a:step <= 1 | return copy(a:lines) | endif
  let l:share = (a:step - 1) * 1000 / (a:steps - 1)
  let l:seed = a:0 ? a:1 : drills#Seed(join(a:lines, "\n"))
  let l:out = []
  let l:i = 0
  for l:l in a:lines
    let l:ind = matchstr(l:l, '^\s*')
    let l:rest = strpart(l:l, strlen(l:ind))
    let l:new = ''
    while l:rest !=# ''
      let l:sp = matchstr(l:rest, '^\s\+')
      if l:sp !=# '' | let l:new .= l:sp | let l:rest = strpart(l:rest, strlen(l:sp)) | continue | endif
      let l:tok = matchstr(l:rest, '^\(\w\+\|[^[:space:][:alnum:]_]\+\)')
      if l:tok ==# '' | let l:tok = l:rest[0] | endif
      let l:new .= s:Rank(l:seed, l:i) < l:share ? repeat('_', strchars(l:tok)) : l:tok
      let l:rest = strpart(l:rest, strlen(l:tok))
      let l:i += 1
    endwhile
    call add(l:out, l:ind . l:new)
  endfor
  return l:out
endfunction

" ---------------------------------------------------------------- progress (in the workspace, never in the kit)
function! drills#ProgressFile() abort
  return drills#Work() . '/trainer.txt'
endfunction
function! drills#Unlocked() abort
  let l:f = drills#ProgressFile()
  if !filereadable(l:f) | return 1 | endif
  for l:l in readfile(l:f)
    let l:m = matchstr(l:l, '^unlocked\s\+\zs\d\+')
    if l:m !=# '' | return max([1, str2nr(l:m)]) | endif
  endfor
  return 1
endfunction
function! drills#SaveProgress(n) abort
  let l:d = drills#Work()
  if !isdirectory(l:d) | call mkdir(l:d, 'p') | endif
  call writefile(['# the Vim drill trainer: the highest unlocked level (:DrillReset forgets it)', 'unlocked ' . a:n], drills#ProgressFile())
endfunction

" ---------------------------------------------------------------- the game
function! drills#State() abort
  return s:g
endfunction
function! s:Shuffle(list) abort
  let l:v = copy(a:list)
  if !get(g:, 'drills_shuffle', 1) | return l:v | endif
  let l:seed = str2nr(matchstr(reltimestr(reltime()), '\d\+$')) + localtime()
  for l:i in range(len(l:v) - 1, 1, -1)
    let l:seed = (l:seed * 1103515245 + 12345) % 2147483648
    let l:j = l:seed % (l:i + 1)
    let [l:v[l:i], l:v[l:j]] = [l:v[l:j], l:v[l:i]]
  endfor
  return l:v
endfunction
function! drills#Train(...) abort
  " :DrillTrain [N] -- play the highest unlocked level, or level N if it is unlocked.
  let l:levels = drills#Cards()
  if empty(l:levels) | echoerr 'drills: no solutions found under ' . drills#Root() . '/drills' | return | endif
  let s:g = {'levels': l:levels, 'unlocked': min([drills#Unlocked(), len(l:levels)]), 'state': 'idle'}
  let l:n = a:0 && a:1 !=# '' ? str2nr(a:1) : s:g.unlocked
  if l:n < 1 || l:n > s:g.unlocked
    echohl ErrorMsg | echo 'drills: level ' . l:n . ' is not unlocked yet (1-' . s:g.unlocked . ')' | echohl None
    let l:n = s:g.unlocked
  endif
  call s:OpenBuffer()
  call s:StartLevel(l:n)
endfunction
function! drills#Level(...) abort
  " :DrillLevel [N] -- choose any unlocked level.
  if !has_key(s:g, 'levels') | call drills#Train(a:0 ? a:1 : '') | return | endif
  let l:top = s:g.unlocked
  let l:n = a:0 && a:1 !=# '' ? str2nr(a:1) : str2nr(input('Level (1-' . l:top . '): ', l:top))
  if l:n < 1 || l:n > l:top
    echohl ErrorMsg | echo 'drills: level ' . l:n . ' is not unlocked yet (1-' . l:top . ')' | echohl None | return
  endif
  call s:OpenBuffer()
  call s:StartLevel(l:n)
endfunction
function! drills#Reset(...) abort
  " :DrillReset -- forget all progress: every level but the first locked again.
  if !(a:0 && a:1) && confirm('Forget all drill trainer progress?', "&Yes\n&No", 2) != 1 | return | endif
  call drills#SaveProgress(1)
  let s:g.unlocked = 1
  echo 'drills: progress reset (level 1 unlocked)'
endfunction
function! s:OpenBuffer() abort
  let l:w = bufwinnr('drill-trainer')
  if l:w > 0
    execute l:w . 'wincmd w'
  elseif bufexists('drill-trainer')
    execute 'buffer ' . bufnr('drill-trainer')
  else
    silent enew
    silent file drill-trainer
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted filetype=perl
  setlocal expandtab shiftwidth=4 softtabstop=4 autoindent nofoldenable
  nnoremap <buffer> <silent> <LocalLeader>dc :DrillAnswer<CR>
  nnoremap <buffer> <silent> <LocalLeader>dg :DrillGiveUp<CR>
  nnoremap <buffer> <silent> <LocalLeader>dn :DrillNext<CR>
  nnoremap <buffer> <silent> <LocalLeader>dl :DrillLevel<CR>
  nnoremap <buffer> <silent> <LocalLeader>dr :call drills#Replay()<CR>
  nnoremap <buffer> <silent> <LocalLeader>dq :DrillQuit<CR>
  inoremap <buffer> <silent> <C-g><C-g> <Esc>:DrillAnswer<CR>
endfunction
function! s:MenuKeys(on) abort
  " Between cards and levels the buffer is read-only and Space/Enter continue, l chooses a level, r replays, q quits.
  for l:k in ['<Space>', '<CR>', 'l', 'r', 'q', 'n']
    silent! execute 'nunmap <buffer> ' . l:k
  endfor
  if a:on
    nnoremap <buffer> <silent> <Space> :DrillNext<CR>
    nnoremap <buffer> <silent> <CR> :DrillNext<CR>
    nnoremap <buffer> <silent> l :DrillLevel<CR>
    nnoremap <buffer> <silent> r :call drills#Replay()<CR>
    nnoremap <buffer> <silent> n :DrillTrain<CR>
    nnoremap <buffer> <silent> q :DrillQuit<CR>
  endif
endfunction
function! s:StartLevel(n) abort
  let l:lv = s:g.levels[a:n - 1]
  let s:g.level = a:n
  let s:g.queue = s:Shuffle(l:lv.cards)
  let s:g.total = len(s:g.queue)
  let s:g.hits = 0
  let s:g.misses = []
  call s:DealCard()
endfunction
function! drills#Replay() abort
  if has_key(s:g, 'level') | call s:StartLevel(s:g.level) | endif
endfunction
function! s:DealCard() abort
  let s:g.item = remove(s:g.queue, 0)
  let s:g.round = 1
  call s:DealRound()
endfunction
function! s:Blind() abort
  return s:Steps() <= 1 || s:g.round >= s:Steps()
endfunction
function! s:Bar(fraction) abort
  let l:w = 20
  let l:f = float2nr(round(a:fraction * l:w))
  return '[' . repeat('#', l:f) . repeat('.', l:w - l:f) . ']'
endfunction
function! s:Overall() abort
  let l:n = len(s:g.levels)
  let l:in = s:g.total ? 1.0 * (s:g.total - len(s:g.queue)) / s:g.total : 0.0
  let l:f = ((s:g.unlocked - 1) + l:in) / l:n
  return l:f > 1.0 ? 1.0 : l:f
endfunction
function! s:Header() abort
  let l:f = s:Overall()
  return printf('Drill trainer %s %d%%  level %d/%d %s  card %d/%d %s  rep %d/%d  correct %d  missed %d',
        \ s:Bar(l:f), float2nr(round(100 * l:f)), s:g.level, len(s:g.levels), s:g.levels[s:g.level - 1].title,
        \ s:g.total - len(s:g.queue), s:g.total, get(get(s:g, 'item', {}), 'id', ''), s:g.round, s:Steps(), s:g.hits, len(s:g.misses))
endfunction
function! s:Write(lines, modifiable) abort
  setlocal modifiable noreadonly
  silent %delete _
  call setline(1, a:lines)
  if !a:modifiable | setlocal nomodifiable | endif
endfunction
function! s:DealRound() abort
  let s:g.state = 'typing'
  let l:lines = [s:Header()]
  if s:Blind()
    call add(l:lines, 'Finish the definition from memory.   \dc check (or Ctrl-G Ctrl-G in insert)   \dg give up   \dq quit')
  else
    call add(l:lines, 'Retype the definition shown below.   \dc check (or Ctrl-G Ctrl-G in insert)   \dg give up   \dq quit')
    call add(l:lines, '')
    let l:hint = drills#Fade(s:g.item.code, s:g.round, s:Steps(), drills#Seed(s:g.item.id))
    call extend(l:lines, map(l:hint, '"  | " . v:val'))
  endif
  call extend(l:lines, ['', s:marker, s:g.item.prompt, ''])
  call s:MenuKeys(0)
  call s:Write(l:lines, 1)
  normal! G
  if !get(g:, 'drills_headless', 0) | startinsert | endif
endfunction
function! drills#Attempt() abort
  " The typed answer: every line below the marker (the prompt line included).
  let l:all = getline(1, '$')
  let l:i = index(l:all, s:marker)
  return l:i < 0 ? [] : l:all[l:i + 1 :]
endfunction
function! drills#Answer() abort
  " :DrillAnswer (\dc) -- check the answer typed under the prompt. Right: straight on, no review. Wrong: the solution.
  if s:g.state !=# 'typing' | echo 'drills: no card on the table (:DrillTrain)' | return | endif
  if drills#Same(drills#Attempt(), s:g.item.code)
    call s:Advance()
  else
    call s:ShowResult(0)
  endif
endfunction
function! drills#GiveUp() abort
  " :DrillGiveUp (\dg) -- show the solution; on the blind rep it counts as a miss.
  if s:g.state !=# 'typing' | echo 'drills: no card on the table (:DrillTrain)' | return | endif
  call s:ShowResult(1)
endfunction
function! s:Advance() abort
  if s:Blind()
    let s:g.hits += 1
    if empty(s:g.queue) | call s:LevelEnd() | else | call s:DealCard() | endif
  else
    let s:g.round += 1
    call s:DealRound()
  endif
endfunction
function! s:ShowResult(gaveup) abort
  let s:g.state = 'shown'
  let s:g.gaveup = a:gaveup
  if s:Blind() | call add(s:g.misses, s:g.item.id) | endif
  let l:lines = getline(1, '$') + ['', a:gaveup ? 'Gave up. The solution is:' : 'Miss. The solution is:', ''] + map(copy(s:g.item.code), '"  " . v:val')
  if !a:gaveup && !s:Blind()
    call add(l:lines, '') | call add(l:lines, 'Space  try this rep again     q  quit')
  elseif s:Blind()
    call add(l:lines, '') | call add(l:lines, empty(s:g.queue) ? 'Space  level result     q  quit' : 'Space  next card     q  quit')
  else
    call add(l:lines, '') | call add(l:lines, 'Space  next rep, less shown     q  quit')
  endif
  call s:Write(l:lines, 0)
  call s:MenuKeys(1)
  stopinsert
  normal! G
endfunction
function! drills#Next() abort
  " :DrillNext (\dn, Space) -- after a miss: retry the rep, fade further, the next card, the level result, the next level.
  if s:g.state ==# 'shown'
    if !s:g.gaveup && !s:Blind()
      call s:DealRound()
    elseif s:Blind()
      if empty(s:g.queue) | call s:LevelEnd() | else | call s:DealCard() | endif
    else
      let s:g.round += 1
      call s:DealRound()
    endif
  elseif s:g.state ==# 'level-end'
    call s:StartLevel(min([s:g.unlocked, len(s:g.levels)]))
  elseif s:g.state ==# 'won'
    call drills#Level()
  else
    echo 'drills: type the answer, then \dc'
  endif
endfunction
function! s:LevelEnd() abort
  let l:n = s:g.total
  let l:nl = len(s:g.levels)
  let l:perfect = s:g.hits == l:n
  let l:last = s:g.level == l:nl
  let l:next = s:g.level + 1
  if l:perfect && !l:last && l:next > s:g.unlocked
    let s:g.unlocked = l:next
    call drills#SaveProgress(l:next)
  endif
  if l:perfect && l:last
    let s:g.state = 'won'
    let l:lines = ['', printf('   *** LEVEL %d CLEARED -- %d/%d ***', s:g.level, l:n, l:n), '',
          \ printf('   Every solution typed from memory. All %d levels cleared.', l:nl), '', '   l  replay any level     n  new game     q  quit']
  elseif l:perfect
    let s:g.state = 'level-end'
    let l:lines = ['', printf('   *** LEVEL %d CLEARED -- %d/%d perfect ***', s:g.level, l:n, l:n), '',
          \ printf('   Level %d unlocked: %s (%d cards)', l:next, s:g.levels[l:next - 1].title, len(s:g.levels[l:next - 1].cards)), '',
          \ printf('   Space  play level %d     r  replay level %d     l  choose level     q  quit', l:next, s:g.level)]
  else
    let s:g.state = 'level-end'
    let l:lines = ['', printf('   Level %d: %d/%d.  Missed: %s', s:g.level, s:g.hits, l:n, join(s:g.misses, ', ')), '',
          \ '   A perfect score is needed to clear the level.', '',
          \ printf('   Space  try level %d again     l  choose level     q  quit', s:g.level)]
  endif
  call s:Write([s:Header()] + l:lines, 0)
  call s:MenuKeys(1)
  stopinsert
endfunction
function! drills#Quit() abort
  " :DrillQuit (\dq) -- leave the trainer; cleared levels are already saved.
  let s:g.state = 'idle'
  if bufname('%') ==# 'drill-trainer'
    if winnr('$') > 1 | close | else | enew | endif
  endif
endfunction

" ---------------------------------------------------------------- the ladder glue (the Vim twin of the ladder's Emacs keys)
function! drills#IdOf(path) abort
  " A statement, test or solution file under drills/, or a workspace file ID.pl -> the problem id (or '').
  let l:p = fnamemodify(a:path, ':p')
  if l:p =~# '[\\/]drills[\\/]\d\d-[^\\/]\+[\\/][^\\/]\+[\\/][^\\/]\+$'
    return substitute(fnamemodify(l:p, ':h:t'), '^\d\d-', '', '')
  endif
  return fnamemodify(l:p, ':t:r')
endfunction
function! drills#Statement(id) abort
  let l:hit = glob(drills#Root() . '/drills/[0-9][0-9]-*/*' . a:id . '/statement.txt', 0, 1)
  call filter(l:hit, 'substitute(fnamemodify(v:val, ":h:t"), "^\\d\\d-", "", "") ==# a:id')
  return empty(l:hit) ? '' : l:hit[0]
endfunction
function! drills#Open() abort
  " :DrillOpen (\do) -- statement <-> your file. The first time, drill.pl start makes the file and starts the clock.
  let l:id = drills#IdOf(expand('%:p'))
  let l:st = drills#Statement(l:id)
  if l:st ==# '' | echo 'drills: this file is not a drills problem (open drills/<section>/<problem>/statement.txt)' | return | endif
  if expand('%:p') =~# '[\\/]drills[\\/]\d\d-'
    let l:mine = drills#Work() . '/' . l:id . '.pl'
    if !filereadable(l:mine)
      let l:out = systemlist(s:Drill('start ' . shellescape(l:id)))
      if v:shell_error | echo join(l:out, "\n") | return | endif
    endif
    execute 'edit ' . fnameescape(l:mine)
  else
    execute 'edit ' . fnameescape(l:st)
  endif
endfunction
function! s:Show(cmd, name) abort
  silent! update
  let l:out = systemlist(a:cmd)
  let l:w = bufwinnr(a:name)
  if l:w > 0 | execute l:w . 'wincmd w' | else | execute 'silent botright new ' . a:name | endif
  setlocal buftype=nofile bufhidden=wipe noswapfile nowrap modifiable
  silent %delete _
  call setline(1, l:out)
  setlocal nomodifiable
  wincmd p
  echo get(l:out, -1, '')
endfunction
function! drills#Test() abort
  " :DrillTest (\dt) -- drill.pl test on the problem in this buffer (your file, or the statement's problem).
  let l:id = drills#IdOf(expand('%:p'))
  if drills#Statement(l:id) ==# '' | echo 'drills: this file is not a drills problem' | return | endif
  let l:file = expand('%:p') =~# '[\\/]drills[\\/]\d\d-' ? '' : ' ' . shellescape(expand('%:p'))
  call s:Show(s:Drill('test ' . shellescape(l:id) . l:file), 'drill-test')
endfunction
function! drills#TestAll(...) abort
  " :DrillTestAll [SECTION|tN] (\da) -- drill.pl check: every file of yours in the workspace.
  call s:Show(s:Drill('check' . (a:0 && a:1 !=# '' ? ' ' . shellescape(a:1) : '')), 'drill-test')
endfunction
