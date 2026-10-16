<#
sysml-lib.ps1 -- the agile kit's tools/sysml/lib/SysML (Grammar.pm, Lexer.pm, Parser.pm) in Windows PowerShell 5.1,
Constrained Language Mode safe. Dot-source it: . "$PSScriptRoot\sysml-lib.ps1"

  GrammarLoad 'sysml'|'kerml'      -> grammar @{ rules; order; keywords; symbols; start } (published KEBNF + errata)
  NewScanner $g; Scan $text        -> @{ ok; tokens = @( @(kind, text, offset) ... ) } or @{ ok = $false; offset; message }
  NewRecognizer $g; Recognize $tok -> @{ ok } or @{ ok = $false; at; found; expected }
  LineCol $text $offset            -> @(line, column)

The recognizer is the Perl one (list of successes, packrat memo, FIRST sets, left recursion by growing the seed),
evaluated on sets of positions per grammar node instead of one closure call per position: PowerShell calls cost
~75 us under CLM, and the same sets come out. Syntax only: it is not the OMG reference parser (see README).
#>

# ================================================================ helpers
function SL_NewH { , [hashtable]::new([System.StringComparer]::Ordinal) }
function SL_Read([string]$path) {                                # UTF-8 text with CRLF/CR -> LF, as the Perl reads it
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { $t = '' }
    if ($t.Length -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $t.Replace("`r`n", "`n").Replace("`r", "`n")
}
function SL_GrammarDir {
    $d = Join-Path $PSScriptRoot 'grammar'
    if (Test-Path -LiteralPath (Join-Path $d 'SysML-textual-bnf.kebnf')) { return $d }
    Join-Path $PSScriptRoot '..\..\tools\sysml\vendor\sysml-v2-release\bnf'
}
$script:SL_TOKEN_RULE = @{ NAME = 'name'; DECIMAL_VALUE = 'int'; EXPONENTIAL_VALUE = 'exp'; STRING_VALUE = 'string'; REGULAR_COMMENT = 'comment' }
$script:SL_KIND_TEXT = @{ name = 'a name'; int = 'a number'; exp = 'a number'; string = 'a string'; comment = 'a comment /* */' }

# ================================================================ KEBNF expression parser (Grammar.pm's combinators)
$script:SL_WS = [regex]::new('\G\s*')
$script:SL_RX_LIT = [regex]::new("\G'[^']*'")
$script:SL_RX_ID = [regex]::new('\G[A-Za-z_]\w*')
$script:SL_RX_IDENT = [regex]::new('\G[A-Za-z_]\w*(?!\s*(?:\+=|\?=|=(?!=)|:\s*\w+\s*=))')
$script:SL_RX_ACTION = [regex]::new('\G\{[^}]*\}')
$script:SL_RX_ASSIGN = [regex]::new('\G[A-Za-z_]\w*\s*(?:\+=|\?=|=)')
$script:SL_RX_POST = [regex]::new('\G[?*+]')

function SL_Skip { $m = $script:SL_WS.Match($script:SL_S, $script:SL_I); $script:SL_I += $m.Length }
function SL_Lit([string]$c) {
    SL_Skip
    if ($script:SL_I + $c.Length -le $script:SL_S.Length -and $script:SL_S.Substring($script:SL_I, $c.Length) -ceq $c) { $script:SL_I += $c.Length; return $true }
    $false
}
function SL_Rx($re) {                                           # matched text or $null; position advances on success
    SL_Skip
    $m = $re.Match($script:SL_S, $script:SL_I)
    if (-not $m.Success) { return $null }
    $script:SL_I += $m.Length
    $m.Value
}
function SL_Xref {
    $save = $script:SL_I
    if ((SL_Lit '[') -and $null -ne (SL_Rx $script:SL_RX_ID) -and (SL_Lit ']')) { return $true }
    $script:SL_I = $save; $false
}
function SL_Primary {                                          # Expr or $null
    $save = $script:SL_I
    $v = SL_Rx $script:SL_RX_LIT
    if ($null -ne $v) { return , @('lit', $v.Substring(1, $v.Length - 2)) }
    $script:SL_I = $save
    if ((SL_Lit '~') -and (SL_Xref)) { return , @('xref', 1) }
    $script:SL_I = $save
    if (SL_Xref) { return , @('xref', 0) }
    $script:SL_I = $save
    if ($null -ne (SL_Rx $script:SL_RX_ACTION)) { return , @(, 'empty') }
    $script:SL_I = $save
    if (SL_Lit '(') {
        $g = SL_Alternation
        if (SL_Lit ')') { return , $g }
    }
    $script:SL_I = $save
    $v = SL_Rx $script:SL_RX_IDENT
    if ($null -ne $v) { return , @('ref', $v) }
    $script:SL_I = $save
    $null
}
function SL_Element {
    $save = $script:SL_I
    $a = SL_Rx $script:SL_RX_ASSIGN
    if ($null -eq $a) { $script:SL_I = $save }
    $p = SL_Primary
    if ($null -eq $p) { $script:SL_I = $save; return $null }
    $s2 = $script:SL_I
    $post = SL_Rx $script:SL_RX_POST
    if ($null -eq $post) { $script:SL_I = $s2; return , $p }
    if ($post -ceq '?') { return , @('opt', $p) }
    if ($post -ceq '*') { return , @('star', $p) }
    , @('plus', $p)
}
function SL_Sequence {
    $e = @()
    while ($true) {
        $s = $script:SL_I
        $x = SL_Element
        if ($null -eq $x -or $script:SL_I -eq $s) { $script:SL_I = $s; break }
        $e += , $x
    }
    if ($e.Count -eq 1) { return , $e[0] }
    , (@(, 'seq') + $e)
}
function SL_Alternation {
    $first = SL_Sequence
    $rest = @()
    while ($true) {
        $s = $script:SL_I
        if (-not (SL_Lit '|')) { $script:SL_I = $s; break }
        $rest += , (SL_Sequence)
    }
    if ($rest.Count) { return , (@('alt', $first) + $rest) }
    , $first
}
function SL_ParseExpr([string]$text) {                           # @{ ok; expr | error }
    $script:SL_S = $text; $script:SL_I = 0
    $e = SL_Alternation
    $rest = ($script:SL_S.Substring($script:SL_I) -creplace '^\s+|\s+$', '')
    if ($rest.Length) { return @{ ok = $false; error = "unconsumed input: $rest" } }
    @{ ok = $true; expr = $e }
}

function SL_Literals($e) {                                       # Expr -> literal texts in order
    $k = $e[0]
    if ($k -ceq 'lit') { return $e[1] }
    if ($k -ceq 'ref' -or $k -ceq 'xref' -or $k -ceq 'empty') { return }
    for ($i = 1; $i -lt $e.Count; $i++) { SL_Literals $e[$i] }
}
function SL_ReadFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ ok = $false; error = "cannot read ${path}: No such file or directory" } }
    $text = SL_Read $path
    $lines = $text -split "`n"
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    $rules = @()
    foreach ($l in $lines) {
        if ($l -cmatch '^\s*//') { continue }
        $m = [regex]::Match($l, '^([A-Za-z_]\w*)\s*(?::\s*(\w+))?\s*=(.*)$')
        if ($m.Success) { $rules += , @($m.Groups[1].Value, $m.Groups[3].Value) }
        elseif ($rules.Count -and $l -cmatch '\S') { $rules[$rules.Count - 1][1] += " $l" }
    }
    $map = SL_NewH; $order = @()
    foreach ($r in $rules) {
        $body = $r[1] -creplace '^\s+|\s+$', ''
        $pe = SL_ParseExpr $body
        if (-not $pe.ok) { return @{ ok = $false; error = "${path}: rule $($r[0]): $($pe.error)" } }
        $map[$r[0]] = $pe.expr; $order += , $r[0]
    }
    $kw = @(); $sy = @()
    if ($map.ContainsKey('RESERVED_KEYWORD')) { $kw = @(SL_Literals $map['RESERVED_KEYWORD']) }
    if ($map.ContainsKey('RESERVED_SYMBOL')) {
        $raw = @(SL_Literals $map['RESERVED_SYMBOL'])
        $sy = @(for ($len = 64; $len -ge 1; $len--) { foreach ($x in $raw) { if ($x.Length -eq $len) { $x } } })   # longest first, stable
    }
    @{ ok = $true; rules = $map; order = $order; keywords = $kw; symbols = $sy }
}
function GrammarLoad([string]$lang) {
    $dir = SL_GrammarDir
    $files = @("$dir/KerML-textual-bnf.kebnf", "$dir/KerML-errata.kebnf")
    if ($lang -ceq 'sysml') { $files += @("$dir/SysML-textual-bnf.kebnf", "$dir/SysML-errata.kebnf") }
    $g = @{ rules = (SL_NewH); order = @(); keywords = @(); symbols = @() }
    $seen = SL_NewH
    foreach ($f in $files) {
        $r = SL_ReadFile $f
        if (-not $r.ok) { throw $r.error }
        foreach ($k in $r.rules.Keys) { $g.rules[$k] = $r.rules[$k] }
        $g.order = @($g.order + $r.order | Where-Object { if ($seen.ContainsKey($_)) { $false } else { $seen[$_] = 1; $true } })
        if ($r.keywords.Count) { $g.keywords = $r.keywords }
        if ($r.symbols.Count) { $g.symbols = $r.symbols }
    }
    $g.start = 'RootNamespace'
    $g
}
# ---- grammar cache: grammar\<lang>.cache, the parsed rules and the FIRST-set fixpoint as text (US-separated
# fields), so a run does not re-parse 3,400 lines of KEBNF and redo the fixpoint (~20 s in CLM). Rebuilt when a
# source file's size changes; if the folder is read-only the grammar is simply built each run.
$script:SL_US = [string][char]31
function SL_ExprFields($e) {                                     # prefix form: kind [value | count children...]
    $k = $e[0]
    if ($k -ceq 'lit' -or $k -ceq 'ref') { return @($k, $e[1]) }
    if ($k -ceq 'xref') { return @($k, [string]$e[1]) }
    if ($k -ceq 'empty') { return @(, 'empty') }
    $o = @($k, [string]($e.Count - 1))
    for ($i = 1; $i -lt $e.Count; $i++) { $o += (SL_ExprFields $e[$i]) }
    $o
}
function SL_FieldsExpr($f) {                                     # uses $script:SL_FI as the read position
    $k = $f[$script:SL_FI]; $script:SL_FI++
    if ($k -ceq 'lit' -or $k -ceq 'ref') { $v = $f[$script:SL_FI]; $script:SL_FI++; return , @($k, $v) }
    if ($k -ceq 'xref') { $v = [int]$f[$script:SL_FI]; $script:SL_FI++; return , @($k, $v) }
    if ($k -ceq 'empty') { return , @(, 'empty') }
    $n = [int]$f[$script:SL_FI]; $script:SL_FI++
    $o = @(, $k)
    for ($i = 0; $i -lt $n; $i++) { $o += , (SL_FieldsExpr $f) }
    , $o
}
function SL_Stamp([string]$lang) {
    $dir = SL_GrammarDir
    $names = @('KerML-textual-bnf.kebnf', 'KerML-errata.kebnf')
    if ($lang -ceq 'sysml') { $names += @('SysML-textual-bnf.kebnf', 'SysML-errata.kebnf') }
    (@(foreach ($n in $names) { $p = Join-Path $dir $n; if (Test-Path -LiteralPath $p) { [string](Get-Item -LiteralPath $p).Length } else { 'none' } })) -join ','
}
function SL_Fixpoint($g) {                                       # rule -> @(first-set, nullable)
    $script:SL_R = SL_NewH
    foreach ($r in $g.rules.Keys) { if (-not $script:SL_TOKEN_RULE.ContainsKey($r)) { $script:SL_R[$r] = @((SL_NewH), 0) } }
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($r in @($script:SL_R.Keys)) {
            $n = SL_First $g.rules[$r]
            $o = $script:SL_R[$r]
            if ($n[1] -eq $o[1] -and $n[0].Count -eq $o[0].Count) { continue }
            $script:SL_R[$r] = $n; $changed = $true
        }
    }
    , $script:SL_R
}
function GrammarLoadCached([string]$lang) {                       # grammar with .first (the fixpoint) attached
    $cache = Join-Path (SL_GrammarDir) "$lang.cache"
    $stamp = SL_Stamp $lang
    $US = $script:SL_US
    if (Test-Path -LiteralPath $cache) {
        $lines = Get-Content -LiteralPath $cache -Encoding UTF8
        if ($lines.Count -and $lines[0] -ceq "SLCACHE 1 $stamp") {
            $g = @{ rules = (SL_NewH); order = @(); keywords = @(); symbols = @(); start = 'RootNamespace' }
            $first = SL_NewH
            foreach ($l in $lines) {
                $f = $l.Split($US)
                $t = $f[0]
                if ($t -ceq 'R') { $script:SL_FI = 2; $g.rules[$f[1]] = SL_FieldsExpr $f }
                elseif ($t -ceq 'F') { $h = SL_NewH; for ($i = 3; $i -lt $f.Count; $i++) { $h[$f[$i]] = 1 }; $first[$f[1]] = @($h, [int]$f[2]) }
                elseif ($t -ceq 'K') { $g.keywords = @($f | Select-Object -Skip 1) }
                elseif ($t -ceq 'S') { $g.symbols = @($f | Select-Object -Skip 1) }
                elseif ($t -ceq 'O') { $g.order = @($f | Select-Object -Skip 1) }
                elseif ($t -ceq 'G') { $g.start = $f[1] }
            }
            $g.first = $first
            return $g
        }
    }
    $g = GrammarLoad $lang
    $g.first = SL_Fixpoint $g
    $out = @("SLCACHE 1 $stamp", ("G$US" + $g.start), ((@('K') + $g.keywords) -join $US), ((@('S') + $g.symbols) -join $US), ((@('O') + $g.order) -join $US))
    foreach ($r in $g.rules.Keys) { $out += ((@('R', $r) + (SL_ExprFields $g.rules[$r])) -join $US) }
    foreach ($r in $g.first.Keys) { $v = $g.first[$r]; $out += ((@('F', $r, [string]$v[1]) + @($v[0].Keys)) -join $US) }
    try { Set-Content -LiteralPath $cache -Value $out -Encoding UTF8 } catch { }
    $g
}

function SL_Refs($e) {
    $k = $e[0]
    if ($k -ceq 'ref') { return $e[1] }
    if ($k -ceq 'xref') { return 'QualifiedName' }
    if ($k -ceq 'lit' -or $k -ceq 'empty') { return }
    for ($i = 1; $i -lt $e.Count; $i++) { SL_Refs $e[$i] }
}
function GrammarUndefined($g) {                                  # names referenced but never defined (Perl: hash order)
    $seen = SL_NewH; $out = @()
    foreach ($r in $g.rules.Values) {
        foreach ($n in @(SL_Refs $r)) {
            if (-not $g.rules.ContainsKey($n) -and -not $script:SL_TOKEN_RULE.ContainsKey($n) -and -not $seen.ContainsKey($n)) { $seen[$n] = 1; $out += $n }
        }
    }
    , $out
}

# ================================================================ lexer
function NewScanner($g) {
    $script:SL_KW = SL_NewH
    foreach ($k in $g.keywords) { $script:SL_KW[$k] = 1 }
    $sym = (@($g.symbols | ForEach-Object { [regex]::Escape($_) })) -join '|'
    $pat = '\G(?:(?<ws>[ \t\f\r\n]+)|(?<note>//\*.*?\*/|//[^\r\n]*)|(?<comment>/\*.*?\*/)|(?<string>"(?:[^"\\]|\\.)*")|(?<qname>''(?:[^''\\]|\\.)*'')|(?<exp>\d+[eE][-+]?\d+)|(?<int>\d+)|(?<name>[A-Za-z_][A-Za-z0-9_]*)|(?<sym>' + $sym + '))'
    $script:SL_TOKRE = [regex]::new($pat, [System.Text.RegularExpressions.RegexOptions]::Singleline)
}
function Scan([string]$text) {
    $toks = @{}; $n = 0; $at = 0; $len = $text.Length
    $kinds = @('ws', 'note', 'comment', 'string', 'qname', 'exp', 'int', 'name', 'sym')
    while ($at -lt $len) {
        $m = $script:SL_TOKRE.Match($text, $at)
        if (-not $m.Success -or $m.Index -ne $at) {
            return @{ ok = $false; offset = $at; message = 'unexpected character ' + $text.Substring($at, 1) }
        }
        $kind = $null
        foreach ($k in $kinds) { if ($m.Groups[$k].Success) { $kind = $k; break } }
        $s = $m.Value
        if ($kind -ceq 'ws' -or $kind -ceq 'note') { }
        elseif ($kind -ceq 'qname') { $toks[$n] = @('name', $s, $at); $n++ }
        elseif ($kind -ceq 'name' -and $script:SL_KW.ContainsKey($s)) { $toks[$n] = @('kw', $s, $at); $n++ }
        else { $toks[$n] = @($kind, $s, $at); $n++ }
        $at += $s.Length
        if ($s.Length -eq 0) { return @{ ok = $false; offset = $at; message = 'unexpected character ' + $text.Substring($at, 1) } }
    }
    @{ ok = $true; tokens = @(for ($i = 0; $i -lt $n; $i++) { , $toks[$i] }) }
}
function LineCol([string]$text, [int]$at) {
    $before = $text.Substring(0, $at)
    $line = 1 + ($before.Length - $before.Replace("`n", '').Length)
    @($line, ($at - $before.LastIndexOf("`n")))
}

# ================================================================ recognizer
# Nodes: @{ k = 0 lit | 1 tok | 2 ref | 3 empty | 4 seq | 5 alt | 6 opt | 7 star | 8 plus; t; c; fs; nul; desc }
function SL_First($e) {                                          # @(fs hashtable, nullable)
    $k = $e[0]
    if ($k -ceq 'lit') { $h = SL_NewH; $h['t:' + $e[1]] = 1; return , @($h, 0) }
    if ($k -ceq 'ref' -and $script:SL_TOKEN_RULE.ContainsKey($e[1])) { $h = SL_NewH; $h['k:' + $script:SL_TOKEN_RULE[$e[1]]] = 1; return , @($h, 0) }
    if ($k -ceq 'ref' -or $k -ceq 'xref') {
        $nm = if ($k -ceq 'xref') { 'QualifiedName' } else { $e[1] }
        if ($script:SL_R.ContainsKey($nm)) { return , $script:SL_R[$nm] }
        return , @((SL_NewH), 0)
    }
    if ($k -ceq 'empty') { return , @((SL_NewH), 1) }
    $fs = @(for ($i = 1; $i -lt $e.Count; $i++) { , (SL_First $e[$i]) })
    if ($k -ceq 'alt') {
        $h = SL_NewH; $nul = 0
        foreach ($f in $fs) { foreach ($x in $f[0].Keys) { $h[$x] = 1 }; if ($f[1]) { $nul = 1 } }
        return , @($h, $nul)
    }
    if ($k -ceq 'opt' -or $k -ceq 'star') { return , @($fs[0][0], 1) }
    if ($k -ceq 'plus') { return , $fs[0] }
    $acc = @((SL_NewH), 1)                                       # seq
    foreach ($f in $fs) {
        if ($acc[1]) { $h = SL_NewH; foreach ($x in $acc[0].Keys) { $h[$x] = 1 }; foreach ($x in $f[0].Keys) { $h[$x] = 1 }; $acc = @($h, $f[1]) }
    }
    , $acc
}
function SL_KeyText([string]$k) { if ($k.StartsWith('t:')) { "'" + $k.Substring(2) + "'" } else { $script:SL_KIND_TEXT[$k.Substring(2)] } }
function SL_Node($e) {                                           # compile an Expr to a node (FIRST data attached)
    $k = $e[0]
    if ($k -ceq 'lit') { return @{ k = 0; t = $e[1]; what = "'" + $e[1] + "'" } }
    if ($k -ceq 'ref' -and $script:SL_TOKEN_RULE.ContainsKey($e[1])) { $kd = $script:SL_TOKEN_RULE[$e[1]]; return @{ k = 1; t = $kd; what = $script:SL_KIND_TEXT[$kd] } }
    if ($k -ceq 'ref' -or $k -ceq 'xref') {
        $nm = if ($k -ceq 'xref') { 'QualifiedName' } else { $e[1] }
        if (-not $script:SL_G.rules.ContainsKey($nm)) { throw "grammar: undefined rule $nm`n" }
        $f = $script:SL_R[$nm]
        return @{ k = 2; t = $nm; rid = (SL_RuleId $nm); fs = $f[0]; nul = $f[1]; desc = @(foreach ($x in $f[0].Keys) { SL_KeyText $x }) }
    }
    if ($k -ceq 'empty') { return @{ k = 3 } }
    $c = @(for ($i = 1; $i -lt $e.Count; $i++) { SL_Node $e[$i] })
    if ($k -ceq 'seq') { return @{ k = 4; c = $c } }
    if ($k -ceq 'alt') {
        for ($i = 1; $i -lt $e.Count; $i++) {
            $f = SL_First $e[$i]; $n = $c[$i - 1]
            $n.afs = $f[0]; $n.anul = $f[1]; $n.adesc = @(foreach ($x in $f[0].Keys) { SL_KeyText $x })
        }
        return @{ k = 5; c = $c }
    }
    if ($k -ceq 'opt') { return @{ k = 6; c = $c } }
    if ($k -ceq 'star') { return @{ k = 7; c = $c } }
    if ($k -ceq 'plus') { return @{ k = 8; c = $c } }
    throw "grammar: unknown expression kind $k`n"
}
function NewRecognizer($g) {
    $script:SL_G = $g
    if ($g.first) { $script:SL_R = $g.first } else { $null = SL_Fixpoint $g }
    $script:SL_BODY = SL_NewH                                    # rule -> node, compiled on first use
    $script:SL_RIDS = SL_NewH
    $script:SL_START = SL_Node @('ref', $g.start)
}
function SL_RuleId([string]$nm) {                                # memo key = rule id + position (positions < 1e7)
    $r = $script:SL_RIDS[$nm]
    if ($null -eq $r) { $r = [long]($script:SL_RIDS.Count + 1) * 10000000; $script:SL_RIDS[$nm] = $r }
    $r
}

function SL_Uniq($a) {                                           # sorted unique ints
    if ($a.Count -lt 2) { return , @($a) }
    $h = @{}; foreach ($x in $a) { $h[[int]$x] = 1 }
    $u = @($h.Keys)
    for ($i = 1; $i -lt $u.Count; $i++) { $v = $u[$i]; $j = $i - 1; while ($j -ge 0 -and $u[$j] -gt $v) { $u[$j + 1] = $u[$j]; $j-- }; $u[$j + 1] = $v }
    , $u
}
function SL_Expect($p, $desc) {
    if ($p -ge $script:SL_FAR) {
        if ($p -gt $script:SL_FAR) { $script:SL_FAR = $p; $script:SL_EXP = SL_NewH }
        foreach ($d in $desc) { $script:SL_EXP[$d] = 1 }
    }
}
# Tokens carry precomputed FIRST-set keys: @(kind, text, offset, 'k:kind', 't:text', text-is-a-keyword-or-symbol)
# Ev: a node applied to a SET of positions (sorted unique) -> the set of end positions. Terminals, rule memo hits and
# FIRST-set tests are inline: every PowerShell call costs ~75 us under CLM.
function SL_Ev($n, $ps) {
    $k = $n.k
    if ($k -le 1) {
        $out = @(); $tk = $script:SL_TOK; $nt = $script:SL_NT; $nt0 = $n.t
        foreach ($p in $ps) {
            if ($p -lt $nt) {
                $t = $tk[$p]
                if ($k -eq 0) { if ($t[5] -and $t[1] -ceq $nt0) { $out += ($p + 1); continue } }
                elseif ($t[0] -ceq $nt0) { $out += ($p + 1); continue }
            }
            if ($p -ge $script:SL_FAR) {
                if ($p -gt $script:SL_FAR) { $script:SL_FAR = $p; $script:SL_EXP = SL_NewH }
                $script:SL_EXP[$n.what] = 1
            }
        }
        return , $out
    }
    if ($k -eq 2) {
        $out = @(); $fs = $n.fs; $nul = $n.nul; $base = $n.rid; $memo = $script:SL_MEMO; $tk = $script:SL_TOK; $nt = $script:SL_NT
        foreach ($p in $ps) {
            if (-not $nul) {
                $ok = $false
                if ($p -lt $nt) { $t = $tk[$p]; $ok = $fs.ContainsKey($t[3]) -or ($t[5] -and $fs.ContainsKey($t[4])) }
                if (-not $ok) {
                    if ($p -ge $script:SL_FAR) {
                        if ($p -gt $script:SL_FAR) { $script:SL_FAR = $p; $script:SL_EXP = SL_NewH }
                        foreach ($d in $n.desc) { $script:SL_EXP[$d] = 1 }
                    }
                    continue
                }
            }
            $key = $base + $p
            $m = $memo[$key]
            if ($null -ne $m) { if ($script:SL_BUSY.ContainsKey($key)) { $script:SL_AGAIN[$key] = 1 }; $out += $m; continue }
            $out += (SL_Rule $n $p)
        }
        if ($out.Count -gt 1 -and $ps.Count -gt 1) { return , (SL_Uniq $out) }
        return , $out
    }
    if ($k -eq 3) { return , $ps }
    if ($k -eq 4) {
        $cur = $ps
        foreach ($c in $n.c) {
            $cur = SL_Ev $c $cur
            if (-not $cur.Count) { break }
        }
        return , $cur
    }
    if ($k -eq 5) {
        $out = @(); $tk = $script:SL_TOK; $nt = $script:SL_NT; $parts = 0
        foreach ($c in $n.c) {
            if ($c.anul) { $go = $ps }
            else {
                $go = @(); $fs = $c.afs
                foreach ($p in $ps) {
                    $ok = $false
                    if ($p -lt $nt) { $t = $tk[$p]; $ok = $fs.ContainsKey($t[3]) -or ($t[5] -and $fs.ContainsKey($t[4])) }
                    if ($ok) { $go += $p }
                    elseif ($p -ge $script:SL_FAR) {
                        if ($p -gt $script:SL_FAR) { $script:SL_FAR = $p; $script:SL_EXP = SL_NewH }
                        foreach ($d in $c.adesc) { $script:SL_EXP[$d] = 1 }
                    }
                }
            }
            if ($go.Count) { $r = SL_Ev $c $go; if ($r.Count) { $out += $r; $parts++ } }
        }
        if ($parts -gt 1 -or $out.Count -gt 1) { return , (SL_Uniq $out) }
        return , $out
    }
    $f = $n.c[0]
    if ($k -eq 6) { $r = SL_Ev $f $ps; if (-not $r.Count) { return , $ps }; return , (SL_Uniq (@($ps) + $r)) }
    if ($k -eq 7) { return , (SL_Star $f $ps) }
    $once = SL_Ev $f $ps                                          # plus
    if (-not $once.Count) { return , @() }
    , (SL_Star $f $once)
}
function SL_Star($f, $start) {
    $seen = @{}; foreach ($x in $start) { $seen[[int]$x] = 1 }
    $frontier = $start
    while ($frontier.Count) {
        $next = SL_Ev $f $frontier
        $nf = @(); foreach ($x in $next) { if (-not $seen.ContainsKey([int]$x)) { $seen[[int]$x] = 1; $nf += $x } }
        $frontier = $nf
    }
    if ($seen.Count -eq 1) { return , @($start) }
    , (SL_Uniq @($seen.Keys))
}
function SL_Rule($n, [int]$p) {                                  # $n: the ref node (rule name, rule id)
    $key = $n.rid + $p
    $script:SL_MEMO[$key] = @()
    $script:SL_BUSY[$key] = 1
    $made = $script:SL_MADE[$p]; if ($null -eq $made) { $made = @(); $script:SL_MADE[$p] = $made }
    $mark = $made.Count
    $name = $n.t
    $body = $script:SL_BODY[$name]
    if ($null -eq $body) { $body = SL_Node $script:SL_G.rules[$name]; $script:SL_BODY[$name] = $body }
    $r = SL_Ev $body @($p)
    while ($script:SL_AGAIN.ContainsKey($key)) {
        $script:SL_AGAIN.Remove($key)
        $lst = $script:SL_MADE[$p]
        for ($i = $mark; $i -lt $lst.Count; $i++) { $script:SL_MEMO.Remove($lst[$i]) }
        $script:SL_MADE[$p] = @(for ($i = 0; $i -lt $mark; $i++) { $lst[$i] })
        $had = @{}; foreach ($x in $script:SL_MEMO[$key]) { $had[[int]$x] = 1 }
        $grew = $false; foreach ($x in $r) { if (-not $had.ContainsKey([int]$x)) { $grew = $true; break } }
        if (-not $grew) { break }
        $script:SL_MEMO[$key] = @($r)
        $r = SL_Uniq (@($r) + (SL_Ev $body @($p)))
    }
    $script:SL_BUSY.Remove($key)
    $script:SL_MEMO[$key] = $r
    $script:SL_MADE[$p] = @($script:SL_MADE[$p]) + $key
    , $r
}
function Recognize($tokens) {
    $script:SL_TOK = @(foreach ($t in $tokens) { , @($t[0], $t[1], $t[2], ('k:' + $t[0]), ('t:' + $t[1]), ($t[0] -cne 'string' -and $t[0] -cne 'comment')) })
    $script:SL_NT = $script:SL_TOK.Count
    $script:SL_MEMO = @{}; $script:SL_FAR = -1; $script:SL_EXP = SL_NewH
    $script:SL_BUSY = @{}; $script:SL_AGAIN = @{}; $script:SL_MADE = @{}
    $ends = SL_Rule $script:SL_START 0
    foreach ($e in $ends) { if ($e -eq $script:SL_NT) { return @{ ok = $true } } }
    $at = if ($script:SL_FAR -lt 0) { 0 } else { $script:SL_FAR }
    $max = if ($ends.Count) { $ends[$ends.Count - 1] } else { 0 }
    if ($max -gt $at) { $at = $max }
    $found = if ($at -lt $script:SL_NT) { $tokens[$at] } else { $null }
    $exp = SL_SortOrd @($script:SL_EXP.Keys)
    @{ ok = $false; at = $at; found = $found; expected = $exp }
}
function SL_SortOrd($a) {                                        # Perl sort: byte order
    $u = @($a)
    for ($i = 1; $i -lt $u.Count; $i++) { $v = $u[$i]; $j = $i - 1; while ($j -ge 0 -and [string]::CompareOrdinal($u[$j], $v) -gt 0) { $u[$j + 1] = $u[$j]; $j-- }; $u[$j + 1] = $v }
    , $u
}

# ================================================================ the checker (sysml.pl's checker + failure_message)
$script:SL_CHECKERS = @{}
function SL_Checker([string]$lang) {
    if (-not $script:SL_CHECKERS.ContainsKey($lang)) {
        $g = GrammarLoadCached $lang
        $script:SL_CHECKERS[$lang] = $g
    }
    $g = $script:SL_CHECKERS[$lang]
    NewScanner $g
    NewRecognizer $g
}
function CheckText([string]$lang, [string]$text) {
    # @{ ok; tokens } | @{ ok = $false; lex = $true; offset; message } | @{ ok = $false; lex = $false; found (text or $null); offset; expected }
    if ($script:SL_CUR -cne $lang) { SL_Checker $lang; $script:SL_CUR = $lang }
    $s = Scan $text
    if (-not $s.ok) { return @{ ok = $false; lex = $true; offset = $s.offset; message = $s.message } }
    $r = Recognize $s.tokens
    if ($r.ok) { return @{ ok = $true; tokens = @($s.tokens).Count } }
    if ($null -ne $r.found) { return @{ ok = $false; lex = $false; found = $r.found[1]; offset = $r.found[2]; expected = $r.expected } }
    @{ ok = $false; lex = $false; found = $null; offset = $text.Length; expected = $r.expected }
}
function FailMessage($r, [int]$max, [string]$prefix) {           # sysml.pl: 8 expected, no prefix; model.pl lint: 6, 'syntax: '
    if ($r.lex) { return $r.message }
    $exp = @($r.expected)
    $ex = if ($exp.Count -gt $max) { ((@($exp | Select-Object -First $max)) -join ', ') + ', ...' } else { $exp -join ', ' }
    $msg = $prefix + $(if ($null -ne $r.found) { "unexpected '" + $r.found + "'" } else { 'unexpected end of file' })
    if ($exp.Count) { $msg += "; expected $ex" }
    $msg
}

# ---- per-file result cache: re-checking an unchanged file (same path, size, write time, grammar) reuses its result.
# Kept in %TEMP%\agile-sysml-check.cache; delete the file to force a full re-check. Results are identical either way.
$script:SL_RC = $null
function SL_CacheFile { $d = $env:TEMP; if (-not $d) { $d = $env:TMP }; if (-not $d) { return $null }; Join-Path $d 'agile-sysml-check2.cache' }
function SL_CacheKey([string]$path, [string]$lang) {
    $it = Get-Item -LiteralPath $path
    (@($it.FullName, [string]$it.Length, [string]$it.LastWriteTimeUtc.Ticks, $lang, (SL_Stamp $lang))) -join '|'
}
function SL_CacheGet([string]$key) {
    if ($null -eq $script:SL_RC) {
        $script:SL_RC = SL_NewH
        $f = SL_CacheFile
        if ($f -and (Test-Path -LiteralPath $f)) {
            foreach ($l in (Get-Content -LiteralPath $f -Encoding UTF8)) { $x = $l.Split($script:SL_US); if ($x.Count -ge 7) { $script:SL_RC[$x[0]] = $x } }
        }
    }
    $script:SL_RC[$key]
}
function SL_CachePut([string]$key, $r) {
    if ($r.ok) { $rec = @($key, '1', [string]$r.tokens, '', '', '', '') }
    elseif ($r.lex) { $rec = @($key, '0', '', 'L', [string]$r.offset, $r.message, '') }
    else { $rec = @($key, '0', '', 'P', [string]$r.offset, $(if ($null -ne $r.found) { $r.found } else { '' }), $(if ($null -ne $r.found) { '1' } else { '0' })) + @($r.expected) }
    $script:SL_RC[$key] = $rec
    $f = SL_CacheFile
    if ($f) { try { Add-Content -LiteralPath $f -Value ($rec -join $script:SL_US) -Encoding UTF8 } catch { } }
}
function CheckPath([string]$path, [string]$lang, [string]$text) {   # CheckText through the result cache
    $key = SL_CacheKey $path $lang
    $c = SL_CacheGet $key
    if ($null -ne $c -and $c.Count -ge 7) {
        if ($c[1] -ceq '1') { return @{ ok = $true; tokens = [int]$c[2] } }
        if ($c[3] -ceq 'L') { return @{ ok = $false; lex = $true; offset = [int]$c[4]; message = $c[5] } }
        $found = if ($c[6] -ceq '1') { $c[5] } else { $null }
        return @{ ok = $false; lex = $false; found = $found; offset = [int]$c[4]; expected = @($c | Select-Object -Skip 7) }
    }
    $r = CheckText $lang $text
    SL_CachePut $key $r
    $r
}
