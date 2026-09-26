" memory drill sheet syntax (Drill.pm)
if exists('b:current_syntax') | finish | endif
syntax match drillComment /^;.*$/
syntax match drillKey     /^#\d\+ .*$/ contains=drillStatus
syntax match drillStatus  /  (\(new\|changed\).*)$/ contained
syntax match drillAnswer  /^>.*$/
syntax match drillOk      /^= ok.*$/
syntax match drillMiss    /^= \(miss\|gone\).*$/
syntax match drillHook    /^hook:/
highlight default link drillComment Comment
highlight default link drillKey     Comment
highlight default link drillStatus  Todo
highlight default link drillAnswer  Identifier
highlight default link drillOk      DiffAdd
highlight default link drillMiss    DiffDelete
highlight default link drillHook    Special
let b:current_syntax = 'drill'
