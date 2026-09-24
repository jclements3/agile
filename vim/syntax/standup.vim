" stand-up note syntax (Standup.pm)
if exists('b:current_syntax') | finish | endif
syntax case ignore
syntax match standupComment  /[;#].*$/
syntax match standupCompiled /\%1l^#\s*compiled.*$/
syntax match standupDate     /^\d\{4}-\d\{2}-\d\{2}$/
syntax match standupTeam     /^==\+\s*\S\+.*$/
syntax match standupSprint   /^sprint\s\+\d\+$/
syntax keyword standupMove   done carry drop commit nextgroup=standupId skipwhite
syntax keyword standupEdit   new new! est assign block unblock hold resume cap nextgroup=standupId skipwhite
syntax keyword standupText   note risk absent
syntax match   standupId     /[A-Za-z][A-Za-z0-9_]*-\d\+/ contained
syntax match   standupMeta   /\<[peo]:\S\+/
highlight default link standupComment  Comment
highlight default link standupCompiled DiffAdd
highlight default link standupDate     Number
highlight default link standupTeam     Title
highlight default link standupSprint   PreProc
highlight default link standupMove     Statement
highlight default link standupEdit     Type
highlight default link standupText     Special
highlight default link standupId       Identifier
highlight default link standupMeta     Constant
let b:current_syntax = 'standup'
