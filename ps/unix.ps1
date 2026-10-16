<#
unix.ps1 -- the Git Bash commands the kit's documents use, as PowerShell functions. Windows PowerShell 5.1,
Constrained Language Mode safe. Dot-source it once per window:

    . .\unix.ps1                   (or add that line to your $PROFILE if profiles are allowed)

    grep [-i -n -r -l -c -v -E -F -w -o -h -H] PATTERN [FILE|DIR...]     (stdin when no files)
    diff [-u] [-U N] FILE1 FILE2   unified (-u) or normal output; exit status 0 same / 1 different
    head [-n N | -N] [FILE...]     tail [-n N | -N] [FILE...]
    wc [-l -w -c] [FILE...]        find [PATH...] [-name GLOB] [-iname GLOB] [-type f|d] [-maxdepth N]
    sort [-u -n -r -f] [FILE...]   uniq [-c -d -u] [FILE]     cat [FILE...]     tee [-a] FILE
    less [FILE]                    which NAME                 sed [-n] [-i] [-e] SCRIPT [FILE...]
    xxd [FILE]                     (sed scripts: s/RE/REPL/[gip], /RE/d, /RE/p, Nd, N,Md, $d; separated by ;)
    sha256sum | sha1sum | md5sum [-c SUMS] [FILE...]      cut -d D -f LIST | -c LIST [FILE...]
    tr [-d] [-s] SET1 [SET2]       paste [-d D] [-s] FILE...  nl [-ba] [FILE]   column -t [-s SEP] [FILE]
    seq [FIRST [INC]] LAST         tac [FILE]   basename NAME [SUFFIX]   dirname NAME   touch [-c] FILE...
    xargs [-n N] [-I STR] COMMAND [ARGS]       zip [-r] OUT.zip PATH...   unzip [-l] [-o] [-d DIR] FILE.zip
    (tar: Windows 10 and 11 ship tar.exe. Quote a comma in PowerShell: cut -d ',' -f '1,3'. Files that
    PowerShell's > wrote, UTF-16, are read too.)

They shadow PowerShell's own aliases of the same names (cat, sort, tee, diff) in this window; 'unix-off'
puts those back. Regular expressions are .NET's, which accept POSIX ERE (-E); basic (BRE) patterns are
translated (\( \) \{ \} \| \+ \? become groups, braces, alternation and quantifiers).
Text files are read as UTF-8 (a BOM is fine) and written as UTF-8 without a BOM.
diff uses pgit's xdiff (git's algorithm), so with ambiguous changes a hunk may be placed differently from GNU
diff while still being a correct, minimal diff.
#>

$script:UNIX_HERE = $PSScriptRoot
if (-not $script:UNIX_HERE) { $script:UNIX_HERE = (Get-Location).Path }
$script:UNIX_EAP = $ErrorActionPreference
if (Test-Path -LiteralPath (Join-Path $script:UNIX_HERE 'pgit.ps1')) { . (Join-Path $script:UNIX_HERE 'pgit.ps1') __lib }
$ErrorActionPreference = $script:UNIX_EAP

$script:UNIX_ALIASES = @('cat', 'sort', 'tee', 'diff')
$script:UNIX_SAVED = @{}
foreach ($a in $script:UNIX_ALIASES) {
    $al = Get-Alias -Name $a -ErrorAction SilentlyContinue
    if ($al) { $script:UNIX_SAVED[$a] = $al.Definition }
    Set-Alias -Name $a -Value ('unix-' + $a) -Option AllScope -Scope Global -Force
    Set-Alias -Name $a -Value ('unix-' + $a) -Option AllScope -Force
}
function unix-off { foreach ($k in $script:UNIX_SAVED.Keys) { Set-Alias -Name $k -Value $script:UNIX_SAVED[$k] -Option AllScope -Scope Global -Force } }

# ---------------------------------------------------------------- helpers
function U-Err([string]$m) { Write-Host $m }
function U-Lines([string]$path) {                     # a text file -> lines (no terminators); CR of CRLF dropped
    $t = U-Text $path
    if ($t -eq '') { return , ([string[]]@()) }
    if ($t.EndsWith("`r`n")) { $t = $t.Substring(0, $t.Length - 2) } elseif ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    return , ([string[]]($t -split "`r?`n"))
}
function U-Text([string]$path) {
    $b = Zl-ReadBytes $path
    if ($b.Length -ge 2 -and $b[0] -eq 255 -and $b[1] -eq 254) {   # UTF-16LE with a BOM: what PowerShell 5.1's > and Out-File write
        $c = [char[]]::new(($b.Length - 2) / 2); for ($i = 2; $i + 1 -lt $b.Length; $i += 2) { $c[($i - 2) / 2] = [char]([int]$b[$i] -bor ([int]$b[$i + 1] -shl 8)) }
        return (-join $c)
    }
    if ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) { $b = Slice $b 3 ($b.Length - 3) }
    return (Utf8Text $b)
}
function U-InputLines($in) {                          # pipeline input -> lines
    $o = @()
    foreach ($x in $in) { if ($null -eq $x) { continue }; foreach ($l in ([string]$x -split "`r?`n")) { $o += $l } }
    return , ([string[]]$o)
}
function U-Bre([string]$p) {                          # POSIX basic regex -> .NET
    $o = ''; $i = 0
    while ($i -lt $p.Length) {
        $c = $p[$i]
        if ($c -eq '\' -and $i + 1 -lt $p.Length) {
            $d = $p[$i + 1]
            if ('(){}|+?'.Contains([string]$d)) { $o += [string]$d } else { $o += '\' + [string]$d }
            $i += 2; continue
        }
        if ('(){}|+?'.Contains([string]$c)) { $o += '\' + [string]$c } else { $o += [string]$c }
        $i++
    }
    return $o
}
function U-Files($paths, [bool]$recurse) {           # expand paths (globs, dirs with -r) -> file list
    $o = @()
    foreach ($p in $paths) {
        if ($p -match '[*?\[]' -and -not (Test-Path -LiteralPath $p)) { foreach ($f in (Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue)) { $o += $f.FullName }; continue }
        if (Test-Path -LiteralPath $p -PathType Container) {
            if (-not $recurse) { U-Err "grep: ${p}: Is a directory"; continue }
            foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.git(\\|$)' })) {
                $rel = $f.FullName
                $base = (Resolve-Path -LiteralPath $p).Path
                $rel = $p.TrimEnd('\', '/') + '/' + $f.FullName.Substring($base.TrimEnd('\').Length + 1).Replace('\', '/')
                $o += $rel
            }
            continue
        }
        $o += $p
    }
    return , $o
}

# ---------------------------------------------------------------- grep
function grep {
    $global:LASTEXITCODE = 0
    $in = @($input)
    $o = NewMap; foreach ($k in @('i', 'n', 'r', 'l', 'c', 'v', 'E', 'F', 'w', 'x', 'o', 'h', 'H', 'q')) { $o[$k] = $false }
    $pat = $null; $files = @(); $pats = @(); $i = 0
    while ($i -lt $args.Count) {
        $a = [string]$args[$i]
        if ($a -ceq '-e') { $pats += [string]$args[$i + 1]; $i += 2; continue }
        if ($a -ceq '--') { $i++; while ($i -lt $args.Count) { if ($null -eq $pat -and -not $pats.Count) { $pat = [string]$args[$i] } else { $files += [string]$args[$i] }; $i++ }; break }
        if ($a -match '^-[A-Za-z]+$') { foreach ($ch in $a.Substring(1).ToCharArray()) { $k = [string]$ch; if ($k -ceq 'R') { $k = 'r' }; if ($o.ContainsKey($k)) { $o[$k] = $true } else { U-Err "grep: invalid option -- '$k'"; return } }; $i++; continue }
        if ($null -eq $pat -and -not $pats.Count) { $pat = $a } else { $files += $a }
        $i++
    }
    if ($null -ne $pat) { $pats = @($pat) + $pats }
    if (-not $pats.Count) { U-Err 'usage: grep [-i -n -r -l -c -v -E -F -w -x -o] PATTERN [FILE...]'; $global:LASTEXITCODE = 2; return }
    $rxs = @()
    foreach ($p in $pats) {
        if ($o.F) { $p = [regex]::Escape($p) } elseif (-not $o.E) { $p = U-Bre $p }
        if ($o.w) { $p = '(?<![\w])(?:' + $p + ')(?![\w])' }
        if ($o.x) { $p = '^(?:' + $p + ')$' }
        $opt = ''; if ($o.i) { $opt = '(?i)' }
        $rxs += [regex]($opt + $p)
    }
    if ($o.r -and -not $files.Count) { $files = @('.') }
    $list = U-Files $files $o.r
    $showName = ($list.Count -gt 1 -or $o.r) -and -not $o.h; if ($o.H) { $showName = $true }
    $any = $false
    $sources = @(); if ($list.Count) { $sources = $list } else { $sources = @($null) }
    foreach ($f in $sources) {
        if ($null -eq $f) { $lines = U-InputLines $in; $name = '(standard input)' }
        else { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "grep: ${f}: No such file or directory"; continue }; $lines = U-Lines $f; $name = $f }
        $cnt = 0; $ln = 0
        foreach ($l in $lines) {
            $ln++
            $hit = $false; foreach ($rx in $rxs) { if ($rx.IsMatch($l)) { $hit = $true; break } }
            if ($o.v) { $hit = -not $hit }
            if (-not $hit) { continue }
            $cnt++; $any = $true
            if ($o.q) { $global:LASTEXITCODE = 0; return }
            if ($o.l -or $o.c) { if ($o.l) { break }; continue }
            $pre = ''; if ($showName) { $pre = $name + ':' }; if ($o.n) { $pre += [string]$ln + ':' }
            if ($o.o -and -not $o.v) { foreach ($rx in $rxs) { foreach ($m in $rx.Matches($l)) { if ($m.Length) { Write-Output ($pre + $m.Value) } } } }
            else { Write-Output ($pre + $l) }
        }
        if ($o.l -and $cnt) { Write-Output $name }
        if ($o.c) { if ($showName) { Write-Output ($name + ':' + $cnt) } else { Write-Output ([string]$cnt) } }
    }
    if ($any) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
}

# ---------------------------------------------------------------- diff
function U-Stamp([string]$f) {
    $t = (Get-Item -LiteralPath $f).LastWriteTime
    return ($t.ToString('yyyy-MM-dd HH:mm:ss') + '.' + ([string]($t.Ticks % 10000000)).PadLeft(7, '0') + '00 ' + (Get-Date -Format 'zzz').Replace(':', ''))
}
function unix-diff {
    $global:LASTEXITCODE = 0
    $u = $false; $ctx = 3; $files = @(); $i = 0; $quiet = $false
    while ($i -lt $args.Count) {
        $a = [string]$args[$i]
        if ($a -ceq '-u') { $u = $true } elseif ($a -ceq '-U') { $u = $true; $ctx = [int]$args[$i + 1]; $i++ } elseif ($a -match '^-U(\d+)$') { $u = $true; $ctx = [int]$Matches[1] }
        elseif ($a -ceq '-q' -or $a -ceq '--brief') { $quiet = $true } else { $files += $a }
        $i++
    }
    if ($files.Count -ne 2) { U-Err 'usage: diff [-u] [-U N] [-q] FILE1 FILE2'; $global:LASTEXITCODE = 2; return }
    foreach ($f in $files) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "diff: ${f}: No such file or directory"; $global:LASTEXITCODE = 2; return } }
    $ab = Zl-ReadBytes $files[0]; $bb = Zl-ReadBytes $files[1]
    $recA = SplitRecs (Latin1 $ab); $recB = SplitRecs (Latin1 $bb)
    $ch = XDiff $recA $recB
    if (-not $ch.Count) { $global:LASTEXITCODE = 0; return }
    $global:LASTEXITCODE = 1
    if ($quiet) { Write-Output ("Files " + $files[0] + " and " + $files[1] + " differ"); return }
    if ((IsBinary $ab) -or (IsBinary $bb)) { Write-Output ("Binary files " + $files[0] + " and " + $files[1] + " differ"); return }
    if ($u) {
        $t = '--- ' + $files[0] + "`t" + (U-Stamp $files[0]) + "`n+++ " + $files[1] + "`t" + (U-Stamp $files[1]) + "`n"
        $script:UFUNC = $true
        $t += (-join @(Unified $recA $recB $ch $ctx))
        $t = [regex]::Replace($t, '(?m)^(@@ [^@]+ @@).*$', '$1')
        Out-Text (L1ToText $t); return
    }
    $t = ''
    foreach ($c in $ch) {
        $r1 = U-Range ($c.i1 + 1) $c.c1; $r2 = U-Range ($c.i2 + 1) $c.c2
        if ($c.c1 -eq 0) { $t += [string]$c.i1 + 'a' + $r2 + "`n" } elseif ($c.c2 -eq 0) { $t += $r1 + 'd' + [string]$c.i2 + "`n" } else { $t += $r1 + 'c' + $r2 + "`n" }
        for ($k = 0; $k -lt $c.c1; $k++) { $t += (Rec '< ' $recA[$c.i1 + $k]) }
        if ($c.c1 -and $c.c2) { $t += "---`n" }
        for ($k = 0; $k -lt $c.c2; $k++) { $t += (Rec '> ' $recB[$c.i2 + $k]) }
    }
    Out-Text (L1ToText $t)
}
function U-Range([int]$s, [int]$n) { if ($n -le 1) { return [string]$s }; return ([string]$s + ',' + [string]($s + $n - 1)) }

# ---------------------------------------------------------------- head, tail, cat, tee, wc
function U-NArg($argv, [int]$def) {
    $n = $def; $files = @(); $i = 0
    while ($i -lt $argv.Count) {
        $a = [string]$argv[$i]
        if ($a -ceq '-n') { $n = [int]$argv[$i + 1]; $i += 2; continue }
        if ($a -match '^-n(-?\d+)$') { $n = [int]$Matches[1]; $i++; continue }
        if ($a -match '^-(\d+)$') { $n = [int]$Matches[1]; $i++; continue }
        $files += $a; $i++
    }
    return @{ n = $n; files = $files }
}
function head {
    $global:LASTEXITCODE = 0
    $in = @($input); $p = U-NArg $args 10
    $srcs = @($p.files); if (-not $srcs.Count) { $srcs = @($null) }
    $k = 0
    foreach ($f in $srcs) {
        if ($null -eq $f) { $lines = U-InputLines $in } else { $lines = U-Lines $f }
        if ($srcs.Count -gt 1) { if ($k) { Write-Output '' }; Write-Output ("==> $f <==") }
        $k++
        $n = $p.n; if ($n -lt 0) { $n = $lines.Count + $n }
        for ($j = 0; $j -lt $n -and $j -lt $lines.Count; $j++) { Write-Output $lines[$j] }
    }
}
function tail {
    $global:LASTEXITCODE = 0
    $in = @($input); $p = U-NArg $args 10
    $srcs = @($p.files); if (-not $srcs.Count) { $srcs = @($null) }
    $k = 0
    foreach ($f in $srcs) {
        if ($null -eq $f) { $lines = U-InputLines $in } else { $lines = U-Lines $f }
        if ($srcs.Count -gt 1) { if ($k) { Write-Output '' }; Write-Output ("==> $f <==") }
        $k++
        $s = $lines.Count - $p.n; if ($s -lt 0) { $s = 0 }
        for ($j = $s; $j -lt $lines.Count; $j++) { Write-Output $lines[$j] }
    }
}
function unix-cat {
    $global:LASTEXITCODE = 0
    $in = @($input)
    if (-not $args.Count) { foreach ($l in (U-InputLines $in)) { Write-Output $l }; return }
    foreach ($f in $args) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "cat: ${f}: No such file or directory"; continue }
        foreach ($l in (U-Lines $f)) { Write-Output $l }
    }
}
function unix-tee {
    $global:LASTEXITCODE = 0
    $in = @($input); $app = $false; $files = @()
    foreach ($a in $args) { if ($a -ceq '-a') { $app = $true } else { $files += $a } }
    $lines = U-InputLines $in
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '' -and $in.Count -eq 0) { }
    $txt = ''; if ($lines.Count) { $txt = ($lines -join "`n") + "`n" }
    foreach ($f in $files) {
        $b = Zl-Utf8Enc $txt
        if ($app -and (Test-Path -LiteralPath $f)) { $b = CatBytes @((Zl-ReadBytes $f), $b) }
        Zl-WriteBytes $f $b
    }
    foreach ($l in $lines) { Write-Output $l }
}
function wc {
    $global:LASTEXITCODE = 0
    $in = @($input)
    $want = @{ l = $false; w = $false; c = $false }; $files = @()
    foreach ($a in $args) { if ($a -match '^-[lwcm]+$') { foreach ($ch in $a.Substring(1).ToCharArray()) { $k = [string]$ch; if ($k -eq 'm') { $k = 'c' }; $want[$k] = $true } } else { $files += $a } }
    if (-not ($want.l -or $want.w -or $want.c)) { $want.l = $true; $want.w = $true; $want.c = $true }
    $rows = @(); $tot = @(0, 0, 0); $reg = $true; $maxsize = 0
    $srcs = @($files); if (-not $srcs.Count) { $srcs = @($null); $reg = $false }
    foreach ($f in $srcs) {
        if ($null -eq $f) { $t = ''; $ls = U-InputLines $in; if ($ls.Count) { $t = ($ls -join "`n") + "`n" }; $bytes = (Zl-Utf8Enc $t).Length; $name = '' }
        else { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "wc: ${f}: No such file or directory"; continue }; $b = Zl-ReadBytes $f; $bytes = $b.Length; $t = Utf8Text $b; $name = $f; if ($bytes -gt $maxsize) { $maxsize = $bytes } }
        $l = ([regex]::Matches($t, "`n")).Count
        $w = ([regex]::Matches($t, '\S+')).Count
        $rows += , @($l, $w, $bytes, $name); $tot[0] += $l; $tot[1] += $w; $tot[2] += $bytes
    }
    if ($rows.Count -gt 1) { $rows += , @($tot[0], $tot[1], $tot[2], 'total') }
    $ncols = 0; foreach ($k in @('l', 'w', 'c')) { if ($want[$k]) { $ncols++ } }
    if ($reg) { $width = ([string]$tot[2]).Length; if ($ncols -eq 1 -and $srcs.Count -eq 1) { $width = 1 } } else { $width = 7 }
    foreach ($r in $rows) {
        $cols = @(); if ($want.l) { $cols += ([string]$r[0]).PadLeft($width) }; if ($want.w) { $cols += ([string]$r[1]).PadLeft($width) }; if ($want.c) { $cols += ([string]$r[2]).PadLeft($width) }
        $line = $cols -join ' '; if ($r[3]) { $line += ' ' + $r[3] }
        Write-Output $line
    }
}

# ---------------------------------------------------------------- find, sort, uniq, which, less, xxd
function find {
    $global:LASTEXITCODE = 0
    $paths = @(); $name = $null; $iname = $null; $type = $null; $maxd = -1; $i = 0
    while ($i -lt $args.Count) {
        $a = [string]$args[$i]
        if ($a -ceq '-name') { $name = [string]$args[$i + 1]; $i += 2; continue }
        if ($a -ceq '-iname') { $iname = [string]$args[$i + 1]; $i += 2; continue }
        if ($a -ceq '-type') { $type = [string]$args[$i + 1]; $i += 2; continue }
        if ($a -ceq '-maxdepth') { $maxd = [int]$args[$i + 1]; $i += 2; continue }
        $paths += $a; $i++
    }
    if (-not $paths.Count) { $paths = @('.') }
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { U-Err "find: '$p': No such file or directory"; continue }
        U-FindWalk $p (Get-Item -LiteralPath $p -Force) 0 $name $iname $type $maxd
    }
}
function U-FindWalk([string]$shown, $item, [int]$depth, $name, $iname, $type, [int]$maxd) {
    $isDir = $item.PSIsContainer
    $ok = $true
    $leaf = $item.Name; if ($depth -eq 0) { $leaf = $shown.TrimEnd('/', '\'); $q = $leaf.LastIndexOfAny([char[]]@('/', '\')); if ($q -ge 0) { $leaf = $leaf.Substring($q + 1) } }
    if ($name -and -not ($leaf -clike $name)) { $ok = $false }
    if ($iname -and -not ($leaf -like $iname)) { $ok = $false }
    if ($type -eq 'f' -and $isDir) { $ok = $false }
    if ($type -eq 'd' -and -not $isDir) { $ok = $false }
    if ($ok) { Write-Output $shown }
    if ($isDir -and ($maxd -lt 0 -or $depth -lt $maxd)) {
        $kids = @(Get-ChildItem -Force -LiteralPath $item.FullName -ErrorAction SilentlyContinue)
        $names = SortOrd ([string[]]@($kids | ForEach-Object { $_.Name }))
        $byName = @{}; foreach ($k in $kids) { $byName[$k.Name] = $k }
        foreach ($n in $names) { $s = $shown.TrimEnd('/') + '/' + $n; if ($shown -eq '/') { $s = '/' + $n }; U-FindWalk $s $byName[$n] ($depth + 1) $name $iname $type $maxd }
    }
}
function unix-sort {
    $global:LASTEXITCODE = 0
    $in = @($input)
    $u = $false; $n = $false; $r = $false; $f = $false; $files = @()
    foreach ($a in $args) { if ($a -match '^-[unrf]+$') { foreach ($ch in $a.Substring(1).ToCharArray()) { switch ([string]$ch) { 'u' { $u = $true } 'n' { $n = $true } 'r' { $r = $true } 'f' { $f = $true } } } } else { $files += $a } }
    $lines = @(); if ($files.Count) { foreach ($x in $files) { $lines += U-Lines $x } } else { $lines = U-InputLines $in }
    if ($n) {
        $keyed = @(); $k = 0
        foreach ($l in $lines) { $m = [regex]::Match($l, '^\s*(-?\d+(?:\.\d+)?)'); $v = [double]0; if ($m.Success) { $v = [double]$m.Groups[1].Value }; $keyed += , @($v, $l, $k); $k++ }
        $sorted = @($keyed | Sort-Object -Property @{ Expression = { $_[0] } }, @{ Expression = { $_[2] } })
        $out = @(); foreach ($x in $sorted) { $out += $x[1] }
    } else {
        $arr = [string[]]$lines
        if ($f) { $keys = [string[]]@($arr | ForEach-Object { $_.ToUpperInvariant() }); [Array]::Sort($keys, $arr, [StringComparer]::Ordinal) }
        else { [Array]::Sort($arr, [StringComparer]::Ordinal) }
        $out = $arr
    }
    if ($r) { [Array]::Reverse($out) }
    $prev = $null; $first = $true
    foreach ($l in $out) { if ($u -and -not $first -and $l -ceq $prev) { continue }; $first = $false; $prev = $l; Write-Output $l }
}
function uniq {
    $global:LASTEXITCODE = 0
    $in = @($input); $c = $false; $d = $false; $uu = $false; $files = @()
    foreach ($a in $args) { if ($a -match '^-[cdu]+$') { foreach ($ch in $a.Substring(1).ToCharArray()) { switch ([string]$ch) { 'c' { $c = $true } 'd' { $d = $true } 'u' { $uu = $true } } } } else { $files += $a } }
    if ($files.Count) { $lines = U-Lines $files[0] } else { $lines = U-InputLines $in }
    $i = 0
    while ($i -lt $lines.Count) {
        $j = $i; while ($j + 1 -lt $lines.Count -and $lines[$j + 1] -ceq $lines[$i]) { $j++ }
        $n = $j - $i + 1
        if (($d -and $n -lt 2) -or ($uu -and $n -gt 1)) { $i = $j + 1; continue }
        if ($c) { Write-Output (([string]$n).PadLeft(7) + ' ' + $lines[$i]) } else { Write-Output $lines[$i] }
        $i = $j + 1
    }
}
function which { foreach ($n in $args) { $c = Get-Command -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -eq $c) { U-Err "which: no $n"; $global:LASTEXITCODE = 1; continue }; if ($c.Path) { Write-Output $c.Path } else { Write-Output ($c.CommandType.ToString() + ': ' + $c.Name) } } }
function less {
    $global:LASTEXITCODE = 0
    $in = @($input)
    if ($args.Count) { $lines = @(); foreach ($f in $args) { $lines += U-Lines $f } } else { $lines = U-InputLines $in }
    $h = 0; try { $h = $Host.UI.RawUI.WindowSize.Height } catch { $h = 0 }
    if (-not $h -or $Host.Name -ne 'ConsoleHost') { foreach ($l in $lines) { Write-Output $l }; return }
    $page = $h - 1; $i = 0
    while ($i -lt $lines.Count) {
        $e = $i + $page; if ($e -gt $lines.Count) { $e = $lines.Count }
        for (; $i -lt $e; $i++) { Write-Host $lines[$i] }
        if ($i -ge $lines.Count) { break }
        $k = Read-Host ("-- {0}/{1} -- Enter: next page, a number: jump to line, /text: find, q: quit" -f $i, $lines.Count)
        if ($k -eq 'q') { break }
        if ($k -match '^\d+$') { $i = [int]$k - 1; if ($i -lt 0) { $i = 0 } }
        elseif ($k.StartsWith('/') -and $k.Length -gt 1) { $t = $k.Substring(1); $j = $i; while ($j -lt $lines.Count -and $lines[$j].IndexOf($t) -lt 0) { $j++ }; if ($j -lt $lines.Count) { $i = $j } else { Write-Host 'Pattern not found' } }
    }
}
function xxd {
    $global:LASTEXITCODE = 0
    $in = @($input)
    if ($args.Count) { $b = Zl-ReadBytes $args[0] } else { $t = ''; $ls = U-InputLines $in; if ($ls.Count) { $t = ($ls -join "`n") + "`n" }; $b = Zl-Utf8Enc $t }
    $o = ''
    for ($i = 0; $i -lt $b.Length; $i += 16) {
        $line = ('{0:x8}: ' -f $i); $asc = ''
        for ($k = 0; $k -lt 16; $k++) {
            if ($i + $k -lt $b.Length) { $x = $b[$i + $k]; $line += $script:HEX[$x]; if ($x -ge 32 -and $x -lt 127) { $asc += [string][char]$x } else { $asc += '.' } } else { $line += '  ' }
            if ($k % 2 -eq 1) { $line += ' ' }
        }
        $o += $line + ' ' + $asc + "`n"
    }
    Out-Text $o
}

# ---------------------------------------------------------------- sed (the common subset)
function sed {
    $global:LASTEXITCODE = 0
    $in = @($input)
    $n = $false; $inplace = $false; $scripts = @(); $files = @(); $i = 0
    while ($i -lt $args.Count) {
        $a = [string]$args[$i]
        if ($a -ceq '-n') { $n = $true } elseif ($a -ceq '-i') { $inplace = $true } elseif ($a -ceq '-E' -or $a -ceq '-r') { $script:SED_ERE = $true }
        elseif ($a -ceq '-e') { $scripts += [string]$args[$i + 1]; $i++ }
        elseif (-not $scripts.Count) { $scripts += $a } else { $files += $a }
        $i++
    }
    $cmds = @()
    foreach ($s in $scripts) { foreach ($part in (U-SedSplit $s)) { if ($part.Trim()) { $cmds += (U-SedParse $part.Trim()) } } }
    $srcs = @($files); if (-not $srcs.Count) { $srcs = @($null) }
    foreach ($f in $srcs) {
        if ($null -eq $f) { $lines = U-InputLines $in } else { $lines = U-Lines $f }
        $out = @(); $ln = 0; $last = $lines.Count
        foreach ($l in $lines) {
            $ln++; $del = $false; $printed = @()
            foreach ($c in $cmds) {
                if (-not (U-SedAddr $c $l $ln $last)) { continue }
                if ($c.op -eq 'd') { $del = $true; break }
                if ($c.op -eq 'p') { $printed += $l; continue }
                if ($c.op -eq 's') {
                    $new = $null
                    if ($c.g) { $new = $c.rx.Replace($l, $c.rep) } else { $new = $c.rx.Replace($l, $c.rep, 1) }
                    if ($new -cne $l -or $c.rx.IsMatch($l)) { if ($c.p) { $printed += $new } }
                    $l = $new
                }
            }
            $out += $printed
            if (-not $del -and -not $n) { $out += $l }
        }
        if ($inplace -and $null -ne $f) { $t = ''; if ($out.Count) { $t = ($out -join "`n") + "`n" }; Zl-WriteBytes $f (Zl-Utf8Enc $t) }
        else { foreach ($x in $out) { Write-Output $x } }
    }
}
function U-SedSplit([string]$s) {                    # split on ; outside s/// arguments
    $parts = @(); $cur = ''; $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq 's' -and ($cur.Trim() -eq '' -or $cur -match '(^|[\d$,/])\s*$') -and $i + 1 -lt $s.Length) {
            $dl = $s[$i + 1]; $cur += 's' + $dl; $i += 2; $seen = 0
            while ($i -lt $s.Length -and $seen -lt 2) { $x = $s[$i]; $cur += $x; if ($x -eq '\' -and $i + 1 -lt $s.Length) { $cur += $s[$i + 1]; $i += 2; continue }; if ($x -eq $dl) { $seen++ }; $i++ }
            continue
        }
        if ($c -eq ';' -or $c -eq "`n") { $parts += $cur; $cur = ''; $i++; continue }
        $cur += $c; $i++
    }
    $parts += $cur
    return , $parts
}
function U-SedParse([string]$p) {
    $c = @{ a1 = $null; a2 = $null; op = ''; g = $false; p = $false }
    $m = [regex]::Match($p, '^(\d+|\$|/(?:[^/\\]|\\.)*/)(?:,(\d+|\$|/(?:[^/\\]|\\.)*/))?\s*(.*)$')
    if ($m.Success -and $m.Groups[3].Value -match '^[dps]') { $c.a1 = U-SedAddrParse $m.Groups[1].Value; if ($m.Groups[2].Success) { $c.a2 = U-SedAddrParse $m.Groups[2].Value }; $p = $m.Groups[3].Value }
    if ($p -eq 'd' -or $p -eq 'p') { $c.op = $p; return $c }
    if ($p.StartsWith('s') -and $p.Length -gt 1) {
        $dl = $p[1]; $f = @(); $cur = ''; $i = 2
        while ($i -lt $p.Length) { $x = $p[$i]; if ($x -eq '\' -and $i + 1 -lt $p.Length) { if ($p[$i + 1] -eq $dl) { $cur += $dl } else { $cur += '\' + $p[$i + 1] }; $i += 2; continue }; if ($x -eq $dl) { $f += $cur; $cur = ''; $i++; continue }; $cur += $x; $i++ }
        $flags = $cur
        if ($f.Count -lt 2) { throw "sed: unterminated s command: $p" }
        $re = $f[0]; if (-not $script:SED_ERE) { $re = U-Bre $re }
        if ($flags.Contains('i') -or $flags.Contains('I')) { $re = '(?i)' + $re }
        $rep = $f[1] -replace '\$', '$$$$'
        $rep = [regex]::Replace($rep, '\\([1-9])', '$${$1}')
        $rep = $rep -replace '(?<!\\)&', '$$0'
        $rep = $rep.Replace('\&', '&').Replace('\n', "`n").Replace('\t', "`t")
        $c.op = 's'; $c.rx = [regex]$re; $c.rep = $rep; $c.g = $flags.Contains('g'); $c.p = $flags.Contains('p')
        return $c
    }
    throw "sed: unsupported command: $p (supported: s///, d, p with line, \$ or /re/ addresses)"
}
function U-SedAddrParse([string]$a) { if ($a -eq '$') { return @{ last = $true } }; if ($a -match '^\d+$') { return @{ line = [int]$a } }; $re = $a.Substring(1, $a.Length - 2); if (-not $script:SED_ERE) { $re = U-Bre $re }; return @{ rx = [regex]$re } }
function U-SedHit($ad, [string]$l, [int]$ln, [int]$last) { if ($ad.last) { return ($ln -eq $last) }; if ($ad.line) { return ($ln -eq $ad.line) }; return $ad.rx.IsMatch($l) }
function U-SedAddr($c, [string]$l, [int]$ln, [int]$last) {
    if ($null -eq $c.a1) { return $true }
    if ($null -eq $c.a2) { return (U-SedHit $c.a1 $l $ln $last) }
    if (-not $c.ContainsKey('on')) { $c.on = $false }
    if ($c.on) { if (U-SedHit $c.a2 $l $ln $last) { $c.on = $false }; return $true }
    if (U-SedHit $c.a1 $l $ln $last) { $c.on = $true; if ($c.a2.line -and $ln -ge $c.a2.line) { $c.on = $false }; return $true }
    return $false
}

# ---------------------------------------------------------------- checksums (pure PowerShell: Get-FileHash needs .NET types CLM refuses)
$script:U_M32 = [long]4294967295
$script:U_K256 = [long[]]@(1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987,
    1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882,
    2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051,
    2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556,
    883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298)
function U-Pad([byte[]]$data, [bool]$bigEndian) {     # Merkle-Damgard padding to a multiple of 64 bytes
    $n = $data.Length; $padLen = (($n + 8) -bor 63) + 1; $m = [byte[]]::new($padLen)
    if ($n -gt 0) { [Array]::Copy($data, 0, $m, 0, $n) }; $m[$n] = 0x80; [long]$bits = [long]$n * 8
    for ($i = 0; $i -lt 8; $i++) { $v = [byte](($bits -shr (8 * $i)) -band 255); if ($bigEndian) { $m[$padLen - 1 - $i] = $v } else { $m[$padLen - 8 + $i] = $v } }
    return , $m
}
function U-Sha256([byte[]]$data) {
    $m = U-Pad $data $true; $M32 = $script:U_M32; $K = $script:U_K256
    $h = [long[]]@(1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225)
    $w = [long[]]::new(64)
    for ($off = 0; $off -lt $m.Length; $off += 64) {
        for ($i = 0; $i -lt 16; $i++) { $j = $off + 4 * $i; $w[$i] = ([long]$m[$j] -shl 24) -bor ([long]$m[$j + 1] -shl 16) -bor ([long]$m[$j + 2] -shl 8) -bor [long]$m[$j + 3] }
        for ($i = 16; $i -lt 64; $i++) {
            $x = $w[$i - 15]; $ws0 = ((($x -shr 7) -bor ($x -shl 25)) -bxor (($x -shr 18) -bor ($x -shl 14)) -bxor ($x -shr 3)) -band $M32
            $x = $w[$i - 2]; $ws1 = ((($x -shr 17) -bor ($x -shl 15)) -bxor (($x -shr 19) -bor ($x -shl 13)) -bxor ($x -shr 10)) -band $M32
            $w[$i] = ($w[$i - 16] + $ws0 + $w[$i - 7] + $ws1) -band $M32
        }
        $a = $h[0]; $b = $h[1]; $c = $h[2]; $d = $h[3]; $e = $h[4]; $f = $h[5]; $g = $h[6]; $hh = $h[7]
        for ($i = 0; $i -lt 64; $i++) {
            $S1 = ((($e -shr 6) -bor ($e -shl 26)) -bxor (($e -shr 11) -bor ($e -shl 21)) -bxor (($e -shr 25) -bor ($e -shl 7))) -band $M32
            $ch = ($e -band $f) -bxor ((-bnot $e) -band $g -band $M32)
            $t1 = ($hh + $S1 + $ch + $K[$i] + $w[$i]) -band $M32
            $S0 = ((($a -shr 2) -bor ($a -shl 30)) -bxor (($a -shr 13) -bor ($a -shl 19)) -bxor (($a -shr 22) -bor ($a -shl 10))) -band $M32
            $mj = ($a -band $b) -bxor ($a -band $c) -bxor ($b -band $c)
            $t2 = ($S0 + $mj) -band $M32
            $hh = $g; $g = $f; $f = $e; $e = ($d + $t1) -band $M32; $d = $c; $c = $b; $b = $a; $a = ($t1 + $t2) -band $M32
        }
        $h[0] = ($h[0] + $a) -band $M32; $h[1] = ($h[1] + $b) -band $M32; $h[2] = ($h[2] + $c) -band $M32; $h[3] = ($h[3] + $d) -band $M32
        $h[4] = ($h[4] + $e) -band $M32; $h[5] = ($h[5] + $f) -band $M32; $h[6] = ($h[6] + $g) -band $M32; $h[7] = ($h[7] + $hh) -band $M32
    }
    return ('{0:x8}{1:x8}{2:x8}{3:x8}{4:x8}{5:x8}{6:x8}{7:x8}' -f $h[0], $h[1], $h[2], $h[3], $h[4], $h[5], $h[6], $h[7])
}
$script:U_MD5S = [int[]]@(7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21)
$script:U_MD5K = [long[]]@(3614090360, 3905402710, 606105819, 3250441966, 4118548399, 1200080426, 2821735955, 4249261313, 1770035416, 2336552879, 4294925233, 2304563134,
    1804603682, 4254626195, 2792965006, 1236535329, 4129170786, 3225465664, 643717713, 3921069994, 3593408605, 38016083, 3634488961, 3889429448,
    568446438, 3275163606, 4107603335, 1163531501, 2850285829, 4243563512, 1735328473, 2368359562, 4294588738, 2272392833, 1839030562, 4259657740,
    2763975236, 1272893353, 4139469664, 3200236656, 681279174, 3936430074, 3572445317, 76029189, 3654602809, 3873151461, 530742520, 3299628645,
    4096336452, 1126891415, 2878612391, 4237533241, 1700485571, 2399980690, 4293915773, 2240044497, 1873313359, 4264355552, 2734768916, 1309151649,
    4149444226, 3174756917, 718787259, 3951481745)   # floor(abs(sin(i+1)) * 2^32)
function U-Md5([byte[]]$data) {
    $m = U-Pad $data $false; $M32 = $script:U_M32; $SHIFT = $script:U_MD5S; $K = $script:U_MD5K
    [long]$a0 = 1732584193; [long]$b0 = 4023233417; [long]$c0 = 2562383102; [long]$d0 = 271733878
    $x = [long[]]::new(16)
    for ($off = 0; $off -lt $m.Length; $off += 64) {
        for ($i = 0; $i -lt 16; $i++) { $j = $off + 4 * $i; $x[$i] = [long]$m[$j] -bor ([long]$m[$j + 1] -shl 8) -bor ([long]$m[$j + 2] -shl 16) -bor ([long]$m[$j + 3] -shl 24) }
        $a = $a0; $b = $b0; $c = $c0; $d = $d0
        for ($i = 0; $i -lt 64; $i++) {
            if ($i -lt 16) { $f = ($b -band $c) -bor ((-bnot $b) -band $d -band $M32); $g = $i }
            elseif ($i -lt 32) { $f = ($d -band $b) -bor ((-bnot $d) -band $c -band $M32); $g = (5 * $i + 1) % 16 }
            elseif ($i -lt 48) { $f = $b -bxor $c -bxor $d; $g = (3 * $i + 5) % 16 }
            else { $f = $c -bxor ($b -bor ((-bnot $d) -band $M32)); $g = (7 * $i) % 16 }
            $f = ($f + $a + $K[$i] + $x[$g]) -band $M32
            $a = $d; $d = $c; $c = $b; $r = $SHIFT[$i]; $b = ($b + ((($f -shl $r) -bor ($f -shr (32 - $r))) -band $M32)) -band $M32
        }
        $a0 = ($a0 + $a) -band $M32; $b0 = ($b0 + $b) -band $M32; $c0 = ($c0 + $c) -band $M32; $d0 = ($d0 + $d) -band $M32
    }
    $o = ''; foreach ($v in $a0, $b0, $c0, $d0) { for ($k = 0; $k -lt 4; $k++) { $o += '{0:x2}' -f (($v -shr (8 * $k)) -band 255) } }
    return $o
}
function U-SumCmd([string]$tool, $argv, $in) {        # sha256sum / sha1sum / md5sum [-c] [FILE...]
    $global:LASTEXITCODE = 0
    $check = $false; $files = @(); foreach ($a in $argv) { if ($a -ceq '-c' -or $a -ceq '--check') { $check = $true } elseif ($a -ceq '-b' -or $a -ceq '-t') { } else { $files += [string]$a } }
    $hash = { param([byte[]]$b) switch ($tool) { 'sha256sum' { U-Sha256 $b } 'sha1sum' { Sha1Hex $b } default { U-Md5 $b } } }
    if (-not $check) {
        if (-not $files.Count) { $t = (U-InputLines $in) -join "`n"; if (@($in).Count) { $t += "`n" }; Write-Output ((& $hash (Zl-Utf8Enc $t)) + '  -'); return }
        foreach ($f in (U-Files $files $false)) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "${tool}: ${f}: No such file or directory"; $global:LASTEXITCODE = 1; continue }; Write-Output ((& $hash (Zl-ReadBytes $f)) + '  ' + $f) }
        return
    }
    $bad = 0; $missing = 0; $lines = @(); if ($files.Count) { foreach ($f in $files) { $lines += U-Lines $f } } else { $lines = U-InputLines $in }
    foreach ($l in $lines) {
        $m = [regex]::Match($l, '^([0-9a-fA-F]+) [ *](.+)$'); if (-not $m.Success) { continue }
        $f = $m.Groups[2].Value
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { U-Err "${tool}: ${f}: No such file or directory"; Write-Output "${f}: FAILED open or read"; $missing++; continue }
        if ((& $hash (Zl-ReadBytes $f)) -eq $m.Groups[1].Value.ToLower()) { Write-Output "${f}: OK" } else { Write-Output "${f}: FAILED"; $bad++ }
    }
    if ($missing) { $w = 'files'; if ($missing -eq 1) { $w = 'file' }; U-Err "${tool}: WARNING: $missing listed $w could not be read" }
    if ($bad) { $w = 'checksums'; if ($bad -eq 1) { $w = 'checksum' }; U-Err "${tool}: WARNING: $bad computed $w did NOT match" }
    if ($bad -or $missing) { $global:LASTEXITCODE = 1 }
}
function sha256sum { U-SumCmd 'sha256sum' $args @($input) }
function sha1sum { U-SumCmd 'sha1sum' $args @($input) }
function md5sum { U-SumCmd 'md5sum' $args @($input) }

# ---------------------------------------------------------------- cut, tr, paste, nl, column, seq, tac, basename, dirname, touch, xargs
function U-Sources($files, $in) { if ($files.Count) { $o = @(); foreach ($f in (U-Files $files $false)) { if ($f -eq '-') { $o += , (U-InputLines $in) } elseif (Test-Path -LiteralPath $f -PathType Leaf) { $o += , (U-Lines $f) } else { U-Err "${f}: No such file or directory"; $global:LASTEXITCODE = 1 } }; return , $o }; return , @(, (U-InputLines $in)) }
function U-List([string]$spec) {                     # cut's LIST: 1,3-5,7- -> ranges
    $r = @(); foreach ($p in ($spec -split ',')) { if ($p -match '^(\d*)-(\d*)$') { $a = 1; if ($Matches[1]) { $a = [int]$Matches[1] }; $b = 2147483647; if ($Matches[2]) { $b = [int]$Matches[2] }; $r += , @($a, $b) } elseif ($p -match '^\d+$') { $r += , @([int]$p, [int]$p) } else { throw "cut: invalid field list: $spec" } }
    return , $r
}
function U-InList([int]$k, $ranges) { foreach ($x in $ranges) { if ($k -ge $x[0] -and $k -le $x[1]) { return $true } }; return $false }
function cut {
    $global:LASTEXITCODE = 0; $in = @($input)
    $d = "`t"; $f = $null; $c = $null; $s = $false; $files = @(); $i = 0
    while ($i -lt $args.Count) {
        $a = [string]$args[$i]
        if ($a -ceq '-d') { $d = [string]$args[$i + 1]; $i += 2; continue } elseif ($a -cmatch '^-d(.+)$') { $d = $Matches[1] }
        elseif ($a -ceq '-f') { $f = [string]$args[$i + 1]; $i += 2; continue } elseif ($a -cmatch '^-f(.+)$') { $f = $Matches[1] }
        elseif ($a -ceq '-c' -or $a -ceq '-b') { $c = [string]$args[$i + 1]; $i += 2; continue } elseif ($a -cmatch '^-[cb](.+)$') { $c = $Matches[1] }
        elseif ($a -ceq '-s') { $s = $true } else { $files += $a }
        $i++
    }
    if (-not $f -and -not $c) { U-Err 'cut: you must specify a list of bytes, characters, or fields'; $global:LASTEXITCODE = 1; return }
    $ranges = U-List ($(if ($f) { $f } else { $c }))
    foreach ($lines in (U-Sources $files $in)) {
        foreach ($l in $lines) {
            if ($c) { $o = ''; for ($k = 0; $k -lt $l.Length; $k++) { if (U-InList ($k + 1) $ranges) { $o += $l[$k] } }; Write-Output $o; continue }
            if (-not $l.Contains($d)) { if (-not $s) { Write-Output $l }; continue }
            $parts = $l.Split([string[]]@($d), [StringSplitOptions]::None); $o = @()
            for ($k = 0; $k -lt $parts.Count; $k++) { if (U-InList ($k + 1) $ranges) { $o += $parts[$k] } }
            Write-Output ($o -join $d)
        }
    }
}
function U-TrSet([string]$s) {                        # tr's SET: ranges, escapes, [:class:] -> char list
    $o = @(); $i = 0
    $cls = @{ 'upper' = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'; 'lower' = 'abcdefghijklmnopqrstuvwxyz'; 'digit' = '0123456789'; 'space' = " `t`n`r`f`v"; 'blank' = " `t"; 'punct' = '!"#$%&''()*+,-./:;<=>?@[\]^_`{|}~' }
    $cls['alpha'] = $cls['upper'] + $cls['lower']; $cls['alnum'] = $cls['alpha'] + $cls['digit']
    while ($i -lt $s.Length) {
        if ($s.Substring($i) -match '^\[:([a-z]+):\]') { $o += $cls[$Matches[1]].ToCharArray(); $i += $Matches[0].Length; continue }
        $ch = $s[$i]
        if ($ch -eq '\' -and $i + 1 -lt $s.Length) { $n = $s[$i + 1]; switch -CaseSensitive ([string]$n) { 'n' { $ch = "`n" } 't' { $ch = "`t" } 'r' { $ch = "`r" } '\' { $ch = '\' } default { $ch = $n } }; $i += 2 } else { $i++ }
        if ($i + 1 -lt $s.Length -and $s[$i] -eq '-') { $hi = $s[$i + 1]; for ($k = [int]$ch; $k -le [int]$hi; $k++) { $o += [char]$k }; $i += 2; continue }
        $o += [char]$ch
    }
    return , $o
}
function tr {
    $global:LASTEXITCODE = 0; $in = @($input)
    $del = $false; $sq = $false; $sets = @(); foreach ($a in $args) { $a = [string]$a; if ($a -cmatch '^-[ds]+$') { if ($a.Contains('d')) { $del = $true }; if ($a.Contains('s')) { $sq = $true } } else { $sets += $a } }
    if (-not $sets.Count) { U-Err 'usage: tr [-d] [-s] SET1 [SET2]'; $global:LASTEXITCODE = 1; return }
    $s1 = U-TrSet $sets[0]; $s2 = @(); if ($sets.Count -gt 1) { $s2 = U-TrSet $sets[1] }
    $map = @{}; if (-not $del -and $s2.Count) { for ($k = 0; $k -lt $s1.Count; $k++) { $j = $k; if ($j -gt $s2.Count - 1) { $j = $s2.Count - 1 }; $map[[int]$s1[$k]] = $s2[$j] } }
    $dset = @{}; if ($del) { foreach ($x in $s1) { $dset[[int]$x] = 1 } }
    $sqset = @{}; if ($sq) { $last = $s1; if ($s2.Count -and -not $del) { $last = $s2 } elseif ($del -and $s2.Count) { $last = $s2 }; foreach ($x in $last) { $sqset[[int]$x] = 1 } }
    $text = (U-InputLines $in) -join "`n"; if ($in.Count) { $text += "`n" }
    $o = @(); $prev = -1
    foreach ($ch in $text.ToCharArray()) {
        $k = [int]$ch
        if ($dset.ContainsKey($k)) { continue }
        if ($map.ContainsKey($k)) { $ch = $map[$k]; $k = [int]$ch }
        if ($sq -and $k -eq $prev -and $sqset.ContainsKey($k)) { continue }
        $o += [string]$ch; $prev = $k
    }
    $t = -join $o; if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    if ($t -ne '' -or $in.Count) { foreach ($l in ($t -split "`n")) { Write-Output $l } }
}
function paste {
    $global:LASTEXITCODE = 0; $in = @($input)
    $d = "`t"; $ser = $false; $files = @(); $i = 0
    while ($i -lt $args.Count) { $a = [string]$args[$i]; if ($a -ceq '-d') { $d = [string]$args[$i + 1]; $i += 2; continue } elseif ($a -cmatch '^-d(.+)$') { $d = $Matches[1] } elseif ($a -ceq '-s') { $ser = $true } else { $files += $a }; $i++ }
    $ds = @(U-TrSet $d); if (-not $ds.Count) { $ds = @('') }
    $srcs = U-Sources $files $in
    if ($ser) { foreach ($l in $srcs) { $o = ''; for ($k = 0; $k -lt $l.Count; $k++) { if ($k) { $o += $ds[($k - 1) % $ds.Count] }; $o += $l[$k] }; Write-Output $o }; return }
    $n = 0; foreach ($l in $srcs) { if ($l.Count -gt $n) { $n = $l.Count } }
    for ($r = 0; $r -lt $n; $r++) { $o = ''; for ($k = 0; $k -lt $srcs.Count; $k++) { if ($k) { $o += $ds[($k - 1) % $ds.Count] }; if ($r -lt $srcs[$k].Count) { $o += $srcs[$k][$r] } }; Write-Output $o }
}
function nl {
    $global:LASTEXITCODE = 0; $in = @($input)
    $all = $false; $files = @(); foreach ($a in $args) { $a = [string]$a; if ($a -ceq '-ba') { $all = $true } elseif ($a -ceq '-b') { } elseif ($a -ceq 'a') { $all = $true } else { $files += $a } }
    $n = 0
    foreach ($lines in (U-Sources $files $in)) { foreach ($l in $lines) { if ($l -eq '' -and -not $all) { Write-Output (' ' * 7); continue }; $n++; Write-Output (([string]$n).PadLeft(6) + "`t" + $l) } }
}
function column {
    $global:LASTEXITCODE = 0; $in = @($input)
    $t = $false; $sep = $null; $files = @(); $i = 0
    while ($i -lt $args.Count) { $a = [string]$args[$i]; if ($a -ceq '-t') { $t = $true } elseif ($a -ceq '-s') { $sep = [string]$args[$i + 1]; $i++ } elseif ($a -cmatch '^-s(.+)$') { $sep = $Matches[1] } else { $files += $a }; $i++ }
    $rows = @(); foreach ($lines in (U-Sources $files $in)) { foreach ($l in $lines) { if ($l.Trim() -eq '') { continue }; if ($sep) { $rows += , @($l.Split($sep.ToCharArray(), [StringSplitOptions]::RemoveEmptyEntries)) } else { $rows += , @($l.Trim() -split '\s+') } } }
    if (-not $t) { foreach ($r in $rows) { Write-Output ($r -join ' ') }; return }
    $w = @{}; foreach ($r in $rows) { for ($k = 0; $k -lt $r.Count; $k++) { if (-not $w.ContainsKey($k) -or $r[$k].Length -gt $w[$k]) { $w[$k] = $r[$k].Length } } }
    foreach ($r in $rows) { $o = ''; for ($k = 0; $k -lt $r.Count; $k++) { if ($k -eq $r.Count - 1) { $o += $r[$k] } else { $o += $r[$k].PadRight($w[$k] + 2) } }; Write-Output $o }
}
function seq {
    $global:LASTEXITCODE = 0; $n = @($args | ForEach-Object { [double]$_ })
    $first = 1; $inc = 1; $last = 1
    if ($n.Count -eq 1) { $last = $n[0] } elseif ($n.Count -eq 2) { $first = $n[0]; $last = $n[1] } elseif ($n.Count -ge 3) { $first = $n[0]; $inc = $n[1]; $last = $n[2] } else { U-Err 'usage: seq [FIRST [INCREMENT]] LAST'; $global:LASTEXITCODE = 1; return }
    if ($inc -eq 0) { U-Err 'seq: invalid Zero increment value'; $global:LASTEXITCODE = 1; return }
    for ($x = $first; ($inc -gt 0 -and $x -le $last) -or ($inc -lt 0 -and $x -ge $last); $x += $inc) { Write-Output ([string]$x) }
}
function tac { $global:LASTEXITCODE = 0; $in = @($input); foreach ($lines in (U-Sources @($args) $in)) { for ($k = $lines.Count - 1; $k -ge 0; $k--) { Write-Output $lines[$k] } } }
function basename { $p = ([string]$args[0]).TrimEnd('/', '\'); if ($p -eq '') { Write-Output '/'; return }; $b = ($p -split '[/\\]')[-1]; if ($args.Count -gt 1 -and $b.EndsWith([string]$args[1]) -and $b -ne [string]$args[1]) { $b = $b.Substring(0, $b.Length - ([string]$args[1]).Length) }; Write-Output $b }
function dirname { $p = ([string]$args[0]).TrimEnd('/', '\'); $i = $p.LastIndexOf('/'); if ($p.LastIndexOf('\') -gt $i) { $i = $p.LastIndexOf('\') }; if ($i -lt 0) { Write-Output '.' } elseif ($i -eq 0) { Write-Output $p.Substring(0, 1) } else { Write-Output $p.Substring(0, $i).TrimEnd('/', '\') } }
function touch {
    $global:LASTEXITCODE = 0; $noCreate = $false
    foreach ($a in $args) { $a = [string]$a; if ($a -ceq '-c') { $noCreate = $true; continue }
        if (Test-Path -LiteralPath $a) { Set-ItemProperty -LiteralPath $a -Name LastWriteTime -Value (Get-Date) }   # the cmdlet: CLM refuses a property set
        elseif (-not $noCreate) { $d = Split-Path $a -Parent; if ($d -and -not (Test-Path -LiteralPath $d)) { U-Err "touch: cannot touch '$a': No such file or directory"; $global:LASTEXITCODE = 1; continue }; Zl-WriteBytes $a ([byte[]]::new(0)) } }
}
function xargs {                                      # xargs [-n N] [-I STR] COMMAND [ARGS]: runs PowerShell commands and the functions above
    $global:LASTEXITCODE = 0; $in = @($input)
    $n = 0; $rep = $null; $i = 0
    while ($i -lt $args.Count) { $a = [string]$args[$i]; if ($a -ceq '-n') { $n = [int]$args[$i + 1]; $i += 2; continue }; if ($a -ceq '-I') { $rep = [string]$args[$i + 1]; $i += 2; continue }; break }
    $cmd = @(); for (; $i -lt $args.Count; $i++) { $cmd += [string]$args[$i] }; if (-not $cmd.Count) { $cmd = @('Write-Output') }
    $items = @(); foreach ($l in (U-InputLines $in)) { if ($rep) { if ($l -ne '') { $items += $l } } else { foreach ($w in ($l.Trim() -split '\s+')) { if ($w -ne '') { $items += $w } } } }
    $exe = $cmd[0]; $fixed = @(); if ($cmd.Count -gt 1) { $fixed = @($cmd[1..($cmd.Count - 1)]) }
    if ($rep) { foreach ($it in $items) { $x = @($fixed | ForEach-Object { $_.Replace($rep, $it) }); & $exe @x }; return }
    if ($n -le 0) { $n = $items.Count; if ($n -lt 1) { $n = 1 } }
    for ($k = 0; $k -lt $items.Count; $k += $n) { $e = $k + $n; if ($e -gt $items.Count) { $e = $items.Count }; $chunk = @($fixed) + @($items[$k..($e - 1)]); & $exe @chunk }
}

# ---------------------------------------------------------------- zip and unzip (ziplib; tar.exe ships with Windows 10 and 11)
function unzip {
    $global:LASTEXITCODE = 0
    $list = $false; $dest = '.'; $zip = $null; $only = @(); $i = 0; $over = $false
    while ($i -lt $args.Count) { $a = [string]$args[$i]; if ($a -ceq '-l') { $list = $true } elseif ($a -ceq '-d') { $dest = [string]$args[$i + 1]; $i++ } elseif ($a -ceq '-o') { $over = $true } elseif ($a -ceq '-q') { } elseif (-not $zip) { $zip = $a } else { $only += $a }; $i++ }
    if (-not $zip) { U-Err 'usage: unzip [-l] [-o] [-d DIR] FILE.zip [MEMBER...]'; $global:LASTEXITCODE = 2; return }
    $ents = Read-ZipEntries $zip
    if ($list) {
        Write-Output '  Length      Name'; Write-Output '---------  ---------'; $tot = 0
        foreach ($e in $ents) { Write-Output (([string]$e.size).PadLeft(9) + '  ' + $e.name); $tot += $e.size }
        Write-Output '---------  -------'; Write-Output (([string]$tot).PadLeft(9) + '  ' + $ents.Count + ' files'); return
    }
    Write-Output "Archive:  $zip"
    foreach ($e in $ents) {
        if ($only.Count -and $only -notcontains $e.name) { continue }
        $out = Join-Path $dest ($e.name.Replace('/', '\'))
        if ($e.name.EndsWith('/')) { if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Force -Path $out | Out-Null }; Write-Output "   creating: $($e.name)"; continue }
        if ((Test-Path -LiteralPath $out) -and -not $over) { U-Err "unzip: $out exists (use -o to overwrite)"; $global:LASTEXITCODE = 1; continue }
        $dir = Split-Path $out -Parent; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Zl-WriteBytes $out (Read-ZipEntry $zip $e.name); Write-Output "  inflating: $($e.name)"
    }
}
function zip {
    $global:LASTEXITCODE = 0
    $rec = $false; $out = $null; $paths = @(); foreach ($a in $args) { $a = [string]$a; if ($a -ceq '-r') { $rec = $true } elseif ($a -ceq '-q') { } elseif (-not $out) { $out = $a } else { $paths += $a } }
    if (-not $out -or -not $paths.Count) { U-Err 'usage: zip [-r] OUT.zip PATH...'; $global:LASTEXITCODE = 12; return }
    $ents = @()
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            if (-not $rec) { U-Err "zip: $p is a directory (use -r)"; continue }
            $base = (Resolve-Path -LiteralPath $p).Path.TrimEnd('\')
            foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File -Force | Sort-Object FullName)) { $rel = $p.TrimEnd('\', '/').Replace('\', '/') + '/' + $f.FullName.Substring($base.Length + 1).Replace('\', '/'); $ents += @{ name = $rel; data = (Zl-ReadBytes $f.FullName) }; Write-Output "  adding: $rel" }
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) { $ents += @{ name = $p.Replace('\', '/'); data = (Zl-ReadBytes $p) }; Write-Output "  adding: $($p.Replace('\', '/'))" }
        else { U-Err "zip warning: name not matched: $p"; $global:LASTEXITCODE = 12 }
    }
    Write-Zip $out $ents
}
