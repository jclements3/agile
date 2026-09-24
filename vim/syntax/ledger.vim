" ledger-cli journal syntax (subset used by Ledger.pm)
if exists('b:current_syntax') | finish | endif
syntax match ledgerComment  /^[;#%|*].*$/
syntax match ledgerComment  /;.*$/ contains=ledgerMeta
syntax match ledgerMeta     /\<\w\+:\ze\s/ contained
syntax match ledgerDate     /^\d\{4}[-\/.]\d\{1,2}[-\/.]\d\{1,2}\(=\S\+\)\?/ nextgroup=ledgerStatus,ledgerPayee skipwhite
syntax match ledgerStatus   /[*!]/ contained nextgroup=ledgerPayee skipwhite
syntax match ledgerPayee    /[^;]*/ contained
syntax match ledgerPeriodic /^\~.*$/
syntax match ledgerDirective /^\(include\|account\|commodity\|payee\|tag\|year\|apply\|end\|P\)\>.*/
syntax match ledgerAccount  /^\s\+\zs[\[(]\?[A-Za-z][^;]\{-}\ze\(\s\{2,}\|\t\|$\)/
syntax match ledgerAmount   /\(\s\{2,}\|\t\)\s*\zs[-$]\?[-]\?[0-9][0-9,]*\(\.\d\+\)\?\(\s\+[A-Za-z_"][^;@=]*\)\?/
syntax match ledgerCost     /@@\?\s*[^;]*/
highlight default link ledgerComment   Comment
highlight default link ledgerMeta      Identifier
highlight default link ledgerDate      Number
highlight default link ledgerStatus    Special
highlight default link ledgerPayee     Title
highlight default link ledgerPeriodic  PreProc
highlight default link ledgerDirective PreProc
highlight default link ledgerAccount   Type
highlight default link ledgerAmount    Constant
highlight default link ledgerCost      Constant
let b:current_syntax = 'ledger'
