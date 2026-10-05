autocmd BufRead,BufNewFile scrum.txt,*.ledger,*.journal set filetype=ledger
autocmd BufRead,BufNewFile */standups/*-chat.txt set filetype=teamschat
autocmd BufRead,BufNewFile */standups/*.txt if expand("%:t") !~# "-chat\.txt$" | set filetype=standup | endif
autocmd BufRead,BufNewFile */reports/*-drill.txt set filetype=drill
autocmd BufRead,BufNewFile *.idef0 set filetype=idef0
autocmd BufRead,BufNewFile */quadfactory/*.txt,*/idef0/*.txt set filetype=idef0
autocmd BufRead,BufNewFile *.txt if getline(1) =~# '-\*-\s*mode:\s*idef0\s*-\*-' | set filetype=idef0 | endif
