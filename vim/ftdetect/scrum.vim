autocmd BufRead,BufNewFile scrum.txt,*.ledger,*.journal set filetype=ledger
autocmd BufRead,BufNewFile */standups/*-chat.txt set filetype=teamschat
autocmd BufRead,BufNewFile */standups/*.txt if expand("%:t") !~# "-chat\.txt$" | set filetype=standup | endif
autocmd BufRead,BufNewFile */reports/*-drill.txt set filetype=drill
