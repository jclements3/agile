" Coding drills in Vim: the memory trainer and the ladder glue (logic in vim/autoload/drills.vim). Loaded by
" vim/scrum.vim. The trainer is the Vim twin of the Emacs "vanishing cues" trainer; :DrillOpen/:DrillTest/:DrillTestAll
" are the twin of the ladder's Emacs keys. Your files, the log and the trainer's progress live in the workspace
" (g:drills_work, else $DRILLS_WORK, else ~/drills-work), never in the kit.
"   :DrillTrain [N]  play (the highest unlocked level, or N)    :DrillLevel [N]  choose a level   :DrillReset  forget progress
"   in the trainer: \dc check  \dg give up  \dn next  \dl level  \dr replay  \dq quit   (Space/Enter continue after a miss)
"   \do  statement <-> your file (makes it the first time)   \dt  test this problem   \da  test everything you have
if exists('g:loaded_drills') | finish | endif
let g:loaded_drills = 1

command! -bar -nargs=? DrillTrain   call drills#Train(<q-args>)
command! -bar -nargs=? DrillLevel   call drills#Level(<q-args>)
command! -bar -nargs=0 DrillReset   call drills#Reset()
command! -bar -nargs=0 DrillAnswer  call drills#Answer()
command! -bar -nargs=0 DrillGiveUp  call drills#GiveUp()
command! -bar -nargs=0 DrillNext    call drills#Next()
command! -bar -nargs=0 DrillQuit    call drills#Quit()
command! -bar -nargs=0 DrillOpen    call drills#Open()
command! -bar -nargs=0 DrillTest    call drills#Test()
command! -bar -nargs=? DrillTestAll call drills#TestAll(<q-args>)

nnoremap <silent> <Leader>do :DrillOpen<CR>
nnoremap <silent> <Leader>dt :DrillTest<CR>
nnoremap <silent> <Leader>da :DrillTestAll<CR>
" In the trainer's buffer only (set by drills#Train): <LocalLeader>dc :DrillAnswer, <LocalLeader>dg :DrillGiveUp,
" <LocalLeader>dn :DrillNext, <LocalLeader>dl :DrillLevel, <LocalLeader>dr replay, <LocalLeader>dq :DrillQuit.
