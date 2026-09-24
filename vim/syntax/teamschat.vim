" pasted Teams chat: highlight speakers, #est/#vote markers, and the Y/T/B status lines so a bad one is visible before :SLint
if exists('b:current_syntax') | finish | endif
syntax match chatHeader  /^\s*\[\d\{1,2}:\d\{2}\(:\d\d\)\?\s*[AaPp]\?[Mm]\?\.\?\]\s*.\+$/
syntax match chatHeader  /^\s*\S.\{-}\s\+\d\{1,2}:\d\{2}\(:\d\d\)\?\s*[AaPp]\?[Mm]\?\.\?$/
syntax match chatMarker  /^\s*#\s*\(est\|estimate\|vote\|poll\)\>.*$/
syntax match chatSystem  /^\s*\(Meeting \(started\|ended\)\|.* \(joined\|left\) the meeting\.\?\|Recording.*\)$/
syntax match chatDelim   /\%(^\|\s\)\@<=[YTB]\%(\s\|$\)\@=/
syntax match chatDelim   /\%(^\|\s\)\@<=\%(Y\|T\|B\|yesterday\|today\|blockers\?\)\s*:/
syntax match chatDelimLo /\%(^\|\s\)\@<=[ytb]\%(\s\|$\)\@=/
syntax match chatId      /\<[A-Z][A-Z0-9_]\{1,9}-\d\{1,6}\>/
syntax match chatNone    /\<\%(none\|no blockers\?\|n\/a\)\>/
highlight default link chatHeader  Title
highlight default link chatMarker  Statement
highlight default link chatSystem  Comment
highlight default link chatDelim   Keyword
highlight default link chatDelimLo Todo
highlight default link chatId      Identifier
highlight default link chatNone    Comment
let b:current_syntax = 'teamschat'
