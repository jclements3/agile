" Vim syntax file -- SysML v2 / KerML textual notation (tools/sysml/)
if exists('b:current_syntax') | finish | endif

syn keyword sysmlStructure  package part item attribute port interface connection allocation enum
syn keyword sysmlStructure  occurrence metadata view viewpoint rendering alias import library standard
syn keyword sysmlBehavior   action calc state constraint requirement verification analysis case use
syn keyword sysmlBehavior   transition entry exit do accept send then first perform exhibit include
syn keyword sysmlDef        def
syn keyword sysmlRelation   specializes subsets redefines references satisfy verify allocate bind connect
syn keyword sysmlRelation   flow succession expose render filter frame concern subject actor objective
syn keyword sysmlDirection  in out inout return end ref
syn keyword sysmlModifier   abstract individual private public protected readonly derived default
syn keyword sysmlModifier   ordered nonunique variant variation
syn keyword sysmlControl    if else and or xor not implies new all istype hastype as meta
syn keyword sysmlConstant   true false null
syn keyword sysmlConstraint require assume assert

syn match   sysmlOperator   ':>>\|:>\|::>\|::\|\~'
syn match   sysmlNumber     '\<\d\+\(\.\d\+\)\=\([eE][-+]\=\d\+\)\=\>'
syn match   sysmlUnit       '\[[^\]]*\]' contains=sysmlNumber
syn match   sysmlMetadata   '@\w\+'
syn match   sysmlLevel      '@L[1-9]\w*'
syn match   sysmlShortName  "<'[^']*'>"
syn match   sysmlTypeName   '\<[A-Z]\w*\>'
syn region  sysmlString     start=+"+ end=+"+ oneline
syn region  sysmlQuotedName start=+'+ end=+'+ oneline
syn keyword sysmlTodo       TODO FIXME XXX contained
syn region  sysmlDoc        start='\<doc\s*/\*' end='\*/' contains=sysmlTodo
syn region  sysmlComment    start='/\*' end='\*/' contains=sysmlTodo
syn match   sysmlComment    '//.*$' contains=sysmlTodo
syn region  sysmlBlock      start='{' end='}' transparent fold

hi def link sysmlStructure  Structure
hi def link sysmlBehavior   Statement
hi def link sysmlDef        Keyword
hi def link sysmlRelation   Keyword
hi def link sysmlDirection  StorageClass
hi def link sysmlModifier   StorageClass
hi def link sysmlControl    Conditional
hi def link sysmlConstant   Constant
hi def link sysmlConstraint Exception
hi def link sysmlOperator   Operator
hi def link sysmlNumber     Number
hi def link sysmlUnit       Special
hi def link sysmlMetadata   PreProc
hi def link sysmlLevel      Tag
hi def link sysmlShortName  Label
hi def link sysmlTypeName   Type
hi def link sysmlString     String
hi def link sysmlQuotedName String
hi def link sysmlDoc        SpecialComment
hi def link sysmlComment    Comment
hi def link sysmlTodo       Todo

let b:current_syntax = 'sysml'
