" IDEF0 model syntax (tools/idef0): t model, a activity, i/c/o/m ports, < > links, ## doc, # ; comments
if exists('b:current_syntax') | finish | endif
syntax match idef0Comment  /^\s*[;#].*$/
syntax match idef0Comment  /\s\zs#[^#].*$/
syntax match idef0Doc      /^\s*\(;;\|##\).*$/
syntax match idef0Doc      /\s\zs##.*$/
syntax match idef0Model    /^\s*\zst\(#\|\a\)\ze\s/           nextgroup=idef0ModelName skipwhite
syntax match idef0ModelName /[^<>|#]\+/ contained
syntax match idef0Activity /^\s*\zsa\(#\|[1-9]\|\a\d\+\.\)\ze\s/ nextgroup=idef0ActName skipwhite
syntax match idef0ActName  /[^<>|#]\+/ contained
syntax match idef0Input    /^\s*\zsi\(#\|[1-9]\)\ze\s/
syntax match idef0Control  /^\s*\zsc\(#\|[1-9]\)\ze\s/
syntax match idef0Output   /^\s*\zso\(#\|[1-9]\)\ze\s/
syntax match idef0Mech     /^\s*\zsm\(#\|[1-9]\)\ze\s/
syntax match idef0Link     /[<>]\s*\zs[^#]\+/ contains=idef0Pipe
syntax match idef0Arrow    /[<>]\ze\s/
syntax match idef0Pipe     /|/ contained
highlight default link idef0Comment   Comment
highlight default link idef0Doc       SpecialComment
highlight default link idef0Model     Keyword
highlight default link idef0ModelName Function
highlight default link idef0Activity  Keyword
highlight default link idef0ActName   Identifier
highlight default link idef0Input     Type
highlight default link idef0Control   Constant
highlight default link idef0Output    Special
highlight default link idef0Mech      PreProc
highlight default link idef0Arrow     WarningMsg
highlight default link idef0Link      String
highlight default link idef0Pipe      Delimiter
let b:current_syntax = 'idef0'
