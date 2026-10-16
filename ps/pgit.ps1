<#
pgit.ps1 -- git for a PowerShell-only PC. Windows PowerShell 5.1, Constrained Language Mode safe, one file.

A git-compatible version control tool that works on a real .git directory with LOOSE objects: it writes blobs,
trees, commits and tags as zlib streams (stored deflate blocks) named by their SHA-1, and the .git/index in
version 2, so git and GitLab read the repository as it is. It reads what git wrote once the repository is
unpacked (no pack files: see 'pgit help packs'). Merges are fast-forward only; git's merge commits are read.

  pgit help                       the commands
  powershell -NoProfile -ExecutionPolicy Bypass -File pgit.ps1 status      (or pgit.cmd status)

When .ps1 files are blocked by policy, load the text once per window and call it as a function:
  function pgit { Invoke-Expression ('& {' + (Get-Content -Raw "$HOME\Documents\agile\pgit.ps1") + "`n} " + ($args -join ' ')) }

Library mode for other tools: . .\pgit.ps1 __lib   then
  Get-PgitCommit REPO SHA           -> @{sha; tree; parents; author; author_name; author_email; author_time; author_tz;
                                        committer; committer_time; committer_tz; message}
  Get-PgitLog REPO [REF|'--all'] [MAX] -> those, newest first in git log's default order
  Resolve-PgitRef REPO NAME         -> object id (40 hex)
  Get-PgitTreeFiles REPO TREE-ISH   -> @( @{path; mode; sha} ) sorted as git sorts paths
  Get-PgitBlob REPO SHA             -> [byte[]]
  Get-PgitRefs REPO [PREFIX]        -> @{ 'refs/heads/main' = sha; ... }
#>

# ================================================================ ziplib.ps1 (copied in by build.sh; keep the two in step)

function Zl-ReadBytes([string]$Path) {
    $x = Get-Content -LiteralPath $Path -Encoding Byte -ReadCount 0 -ErrorAction Stop
    if ($null -eq $x) { return , ([byte[]]::new(0)) }
    return , ([byte[]]$x)
}

function Zl-WriteBytes([string]$Path, [byte[]]$Bytes) {
    if ($null -eq $Bytes) { $Bytes = [byte[]]::new(0) }
    Set-Content -LiteralPath $Path -Value $Bytes -Encoding Byte -ErrorAction Stop
}

$script:ZL_CRC = $null
function Zl-Crc32([byte[]]$d, [int]$off = 0, [int]$len = -1) {
    if ($len -lt 0) { $len = $d.Length - $off }
    if ($null -eq $script:ZL_CRC) {
        $t = [long[]]::new(256)
        for ($n = 0; $n -lt 256; $n++) {
            [long]$c = $n
            for ($k = 0; $k -lt 8; $k++) { if (($c -band 1) -ne 0) { $c = 3988292384 -bxor ($c -shr 1) } else { $c = $c -shr 1 } }
            $t[$n] = $c
        }
        $script:ZL_CRC = $t
    }
    $t = $script:ZL_CRC
    [long]$c = 4294967295
    $e = $off + $len
    for ($i = $off; $i -lt $e; $i++) { $c = $t[($c -bxor $d[$i]) -band 255] -bxor ($c -shr 8) }
    return ($c -bxor 4294967295)
}

function Zl-Adler32([byte[]]$d, [int]$off = 0, [int]$len = -1) {
    if ($len -lt 0) { $len = $d.Length - $off }
    [long]$a = 1; [long]$b = 0
    $i = $off; $e = $off + $len
    while ($i -lt $e) {
        $stop = $i + 5552; if ($stop -gt $e) { $stop = $e }
        for (; $i -lt $stop; $i++) { $a += $d[$i]; $b += $a }
        $a = $a % 65521; $b = $b % 65521
    }
    return (($b -shl 16) -bor $a)
}

function Zl-Zlib([byte[]]$d) {
    $n = $d.Length
    $nb = ($n - ($n % 65535)) / 65535; if (($n % 65535) -ne 0 -or $nb -eq 0) { $nb++ }
    $o = [byte[]]::new(2 + 5 * $nb + $n + 4)
    $o[0] = 0x78; $o[1] = 0x01
    $p = 2; $src = 0
    for ($k = 0; $k -lt $nb; $k++) {
        $len = $n - $src; if ($len -gt 65535) { $len = 65535 }
        if ($k -eq $nb - 1) { $o[$p] = 1 } else { $o[$p] = 0 }
        $o[$p + 1] = $len -band 255; $o[$p + 2] = ($len -shr 8) -band 255
        $nl = 65535 - $len
        $o[$p + 3] = $nl -band 255; $o[$p + 4] = ($nl -shr 8) -band 255
        $p += 5
        if ($len -gt 0) { [Array]::Copy($d, $src, $o, $p, $len) }
        $p += $len; $src += $len
    }
    $ad = Zl-Adler32 $d 0 $n
    $o[$p] = ($ad -shr 24) -band 255; $o[$p + 1] = ($ad -shr 16) -band 255; $o[$p + 2] = ($ad -shr 8) -band 255; $o[$p + 3] = $ad -band 255
    return , $o
}

function Zl-Unzlib([byte[]]$s) {
    if ($s.Length -lt 2 -or ($s[0] -band 15) -ne 8 -or ((($s[0] * 256) + $s[1]) % 31) -ne 0) { throw 'not a zlib stream' }
    if (($s[1] -band 32) -ne 0) { throw 'zlib preset dictionary not supported' }
    return , (Zl-Inflate $s 2)
}

# ---------------------------------------------------------------- inflate (RFC 1951)
# Huffman tables: a 10-bit lookup (entry = symbol * 16 + length, 0 = longer code) and, for longer codes, the
# canonical count/symbol arrays decoded bit by bit (zlib's puff.c).
function Zl-Huff([int[]]$lens, [int]$n) {
    $cnt = [int[]]::new(16)
    for ($i = 0; $i -lt $n; $i++) { $cnt[$lens[$i]]++ }
    $cnt[0] = 0
    $offs = [int[]]::new(17)
    for ($l = 1; $l -le 15; $l++) { $offs[$l + 1] = $offs[$l] + $cnt[$l] }
    $sym = [int[]]::new($n + 1)
    $o2 = [int[]]::new(17); for ($l = 0; $l -le 16; $l++) { $o2[$l] = $offs[$l] }
    for ($i = 0; $i -lt $n; $i++) { $l = $lens[$i]; if ($l -ne 0) { $sym[$o2[$l]] = $i; $o2[$l]++ } }
    $next = [int[]]::new(16)
    $code = 0
    for ($l = 1; $l -le 15; $l++) { $code = ($code + $cnt[$l - 1]) -shl 1; $next[$l] = $code }
    $tbl = [int[]]::new(1024)
    for ($i = 0; $i -lt $n; $i++) {
        $l = $lens[$i]
        if ($l -eq 0) { continue }
        $c = $next[$l]; $next[$l]++
        if ($l -gt 10) { continue }
        $r = 0
        for ($k = 0; $k -lt $l; $k++) { $r = ($r -shl 1) -bor (($c -shr $k) -band 1) }
        $step = 1 -shl $l
        $v = $i * 16 + $l
        for ($k = $r; $k -lt 1024; $k += $step) { $tbl[$k] = $v }
    }
    return @{ tbl = $tbl; cnt = $cnt; sym = $sym }
}

$script:ZL_FIXED = $null
$script:ZL_LBASE = [int[]](3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
$script:ZL_LEXT = [int[]](0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0)
$script:ZL_DBASE = [int[]](1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577)
$script:ZL_DEXT = [int[]](0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13)
$script:ZL_CLORD = [int[]](16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15)

function Zl-Inflate([byte[]]$s, [int]$p = 0) {
    $out = [byte[]]::new(16384); $op = 0
    [long]$bb = 0; $bc = 0
    $sl = $s.Length
    $lbase = $script:ZL_LBASE; $lext = $script:ZL_LEXT; $dbase = $script:ZL_DBASE; $dext = $script:ZL_DEXT
    $final = 0
    while ($final -eq 0) {
        while ($bc -lt 3) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
        $final = [int]($bb -band 1); $type = [int](($bb -shr 1) -band 3); $bb = $bb -shr 3; $bc -= 3
        if ($type -eq 0) {
            $drop = $bc % 8; $bc -= $drop
            $p -= ($bc -shr 3); $bb = 0; $bc = 0
            if ($p + 4 -gt $sl) { throw 'inflate: truncated stored block' }
            $len = [int]$s[$p] -bor ([int]$s[$p + 1] -shl 8)
            $nlen = [int]$s[$p + 2] -bor ([int]$s[$p + 3] -shl 8)
            if (($len -bxor 65535) -ne $nlen) { throw 'inflate: stored block length check failed' }
            $p += 4
            if ($p + $len -gt $sl) { throw 'inflate: truncated stored block' }
            if ($op + $len -gt $out.Length) { $nw = [byte[]]::new(2 * $out.Length + $len); [Array]::Copy($out, 0, $nw, 0, $op); $out = $nw }
            if ($len -gt 0) { [Array]::Copy($s, $p, $out, $op, $len) }
            $op += $len; $p += $len
            continue
        }
        if ($type -eq 1) {
            if ($null -eq $script:ZL_FIXED) {
                $ll = [int[]]::new(288)
                for ($i = 0; $i -lt 144; $i++) { $ll[$i] = 8 }; for (; $i -lt 256; $i++) { $ll[$i] = 9 }
                for (; $i -lt 280; $i++) { $ll[$i] = 7 }; for (; $i -lt 288; $i++) { $ll[$i] = 8 }
                $dl = [int[]]::new(30); for ($i = 0; $i -lt 30; $i++) { $dl[$i] = 5 }
                $script:ZL_FIXED = @((Zl-Huff $ll 288), (Zl-Huff $dl 30))
            }
            $LH = $script:ZL_FIXED[0]; $DH = $script:ZL_FIXED[1]
        } elseif ($type -eq 2) {
            while ($bc -lt 14) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
            $nlen = [int]($bb -band 31) + 257; $bb = $bb -shr 5
            $ndist = [int]($bb -band 31) + 1; $bb = $bb -shr 5
            $ncode = [int]($bb -band 15) + 4; $bb = $bb -shr 4; $bc -= 14
            if ($nlen -gt 286 -or $ndist -gt 30) { throw 'inflate: bad dynamic block counts' }
            $cl = [int[]]::new(19)
            for ($i = 0; $i -lt $ncode; $i++) {
                while ($bc -lt 3) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
                $cl[$script:ZL_CLORD[$i]] = [int]($bb -band 7); $bb = $bb -shr 3; $bc -= 3
            }
            $CLH = Zl-Huff $cl 19
            $ctbl = $CLH.tbl
            $lens = [int[]]::new($nlen + $ndist)
            $i = 0
            while ($i -lt $nlen + $ndist) {
                while ($bc -lt 15) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
                $e = $ctbl[[int]($bb -band 1023)]
                if ($e -eq 0) { throw 'inflate: bad code-length code' }
                $sym = $e -shr 4; $l = $e -band 15; $bb = $bb -shr $l; $bc -= $l
                if ($sym -lt 16) { $lens[$i] = $sym; $i++; continue }
                if ($sym -eq 16) {
                    if ($i -eq 0) { throw 'inflate: repeat with no previous length' }
                    $prev = $lens[$i - 1]; $rep = 3 + [int]($bb -band 3); $bb = $bb -shr 2; $bc -= 2
                } elseif ($sym -eq 17) { $prev = 0; $rep = 3 + [int]($bb -band 7); $bb = $bb -shr 3; $bc -= 3 }
                else { $prev = 0; $rep = 11 + [int]($bb -band 127); $bb = $bb -shr 7; $bc -= 7 }
                if ($i + $rep -gt $nlen + $ndist) { throw 'inflate: too many lengths' }
                for ($k = 0; $k -lt $rep; $k++) { $lens[$i] = $prev; $i++ }
            }
            if ($lens[256] -eq 0) { throw 'inflate: no end-of-block code' }
            $ll = [int[]]::new($nlen); [Array]::Copy($lens, 0, $ll, 0, $nlen)
            $dl = [int[]]::new($ndist); [Array]::Copy($lens, $nlen, $dl, 0, $ndist)
            $LH = Zl-Huff $ll $nlen; $DH = Zl-Huff $dl $ndist
        } else { throw 'inflate: invalid block type 3' }

        $ltbl = $LH.tbl; $lcnt = $LH.cnt; $lsym = $LH.sym
        $dtbl = $DH.tbl; $dcnt = $DH.cnt; $dsym = $DH.sym
        while ($true) {
            while ($bc -lt 15) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
            $e = $ltbl[[int]($bb -band 1023)]
            if ($e -ne 0) { $sym = $e -shr 4; $l = $e -band 15; $bb = $bb -shr $l; $bc -= $l }
            else {
                $code = 0; $first = 0; $index = 0; $sym = -1
                for ($l = 1; $l -le 15; $l++) {
                    $code = $code -bor [int]($bb -band 1); $bb = $bb -shr 1; $bc--
                    $count = $lcnt[$l]
                    if ($code - $count -lt $first) { $sym = $lsym[$index + ($code - $first)]; break }
                    $index += $count; $first += $count; $first = $first -shl 1; $code = $code -shl 1
                }
                if ($sym -lt 0) { throw 'inflate: bad literal/length code' }
            }
            if ($sym -lt 256) {
                if ($op -ge $out.Length) { $nw = [byte[]]::new(2 * $out.Length); [Array]::Copy($out, 0, $nw, 0, $op); $out = $nw }
                $out[$op] = $sym; $op++
                continue
            }
            if ($sym -eq 256) { break }
            $sym -= 257
            if ($sym -ge 29) { throw 'inflate: bad length symbol' }
            while ($bc -lt 15) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
            $x = $lext[$sym]
            $len = $lbase[$sym] + [int]($bb -band ((1 -shl $x) - 1)); $bb = $bb -shr $x; $bc -= $x
            while ($bc -lt 15) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
            $e = $dtbl[[int]($bb -band 1023)]
            if ($e -ne 0) { $ds = $e -shr 4; $l = $e -band 15; $bb = $bb -shr $l; $bc -= $l }
            else {
                $code = 0; $first = 0; $index = 0; $ds = -1
                for ($l = 1; $l -le 15; $l++) {
                    $code = $code -bor [int]($bb -band 1); $bb = $bb -shr 1; $bc--
                    $count = $dcnt[$l]
                    if ($code - $count -lt $first) { $ds = $dsym[$index + ($code - $first)]; break }
                    $index += $count; $first += $count; $first = $first -shl 1; $code = $code -shl 1
                }
                if ($ds -lt 0 -or $ds -ge 30) { throw 'inflate: bad distance code' }
            }
            while ($bc -lt 15) { if ($p -lt $sl) { $bb = $bb -bor ([long]$s[$p] -shl $bc) }; $p++; $bc += 8 }
            $x = $dext[$ds]
            $dist = $dbase[$ds] + [int]($bb -band ((1 -shl $x) - 1)); $bb = $bb -shr $x; $bc -= $x
            if ($dist -gt $op) { throw 'inflate: distance too far back' }
            if ($op + $len -gt $out.Length) { $nw = [byte[]]::new(2 * $out.Length + $len); [Array]::Copy($out, 0, $nw, 0, $op); $out = $nw }
            $from = $op - $dist
            if ($dist -ge $len) { [Array]::Copy($out, $from, $out, $op, $len); $op += $len }
            else { for ($k = 0; $k -lt $len; $k++) { $out[$op] = $out[$from + $k]; $op++ } }
        }
        if ($p - ($bc -shr 3) -gt $sl) { throw 'inflate: unexpected end of data' }
    }
    $script:ZL_END = $p - ($bc -shr 3)                # the first byte after the deflate data (a pack reader needs it)
    $r = [byte[]]::new($op)
    if ($op -gt 0) { [Array]::Copy($out, 0, $r, 0, $op) }
    return , $r
}

# ---------------------------------------------------------------- zip
function Zl-U16([byte[]]$b, [int]$i) { return ([int]$b[$i] -bor ([int]$b[$i + 1] -shl 8)) }
function Zl-U32([byte[]]$b, [int]$i) { return ([long]$b[$i] -bor ([long]$b[$i + 1] -shl 8) -bor ([long]$b[$i + 2] -shl 16) -bor ([long]$b[$i + 3] -shl 24)) }

function Zl-Utf8Dec([byte[]]$b, [int]$off, [int]$len, [bool]$utf8 = $true) {
    $c = [char[]]::new($len); $n = 0; $i = $off; $e = $off + $len
    while ($i -lt $e) {
        $x = [int]$b[$i]
        if ($x -lt 128 -or -not $utf8) { $c[$n] = [char]$x; $n++; $i++; continue }
        $cp = -1; $need = 0
        if (($x -band 224) -eq 192) { $cp = $x -band 31; $need = 1 } elseif (($x -band 240) -eq 224) { $cp = $x -band 15; $need = 2 } elseif (($x -band 248) -eq 240) { $cp = $x -band 7; $need = 3 }
        $ok = ($cp -ge 0) -and ($i + $need -lt $e)
        if ($ok) { for ($k = 1; $k -le $need; $k++) { if ($i + $k -ge $e -or ([int]$b[$i + $k] -band 192) -ne 128) { $ok = $false; break }; $cp = ($cp -shl 6) -bor ([int]$b[$i + $k] -band 63) } }
        if (-not $ok) { $c[$n] = [char]$x; $n++; $i++; continue }
        if ($cp -ge 65536) {
            if ($n + 2 -gt $c.Length) { $nc = [char[]]::new($c.Length + 8); [Array]::Copy($c, 0, $nc, 0, $n); $c = $nc }
            $cp -= 65536; $c[$n] = [char](55296 + ($cp -shr 10)); $c[$n + 1] = [char](56320 + ($cp -band 1023)); $n += 2
        } else { $c[$n] = [char]$cp; $n++ }
        $i += $need + 1
    }
    if ($n -eq 0) { return '' }
    return (-join $c[0..($n - 1)])
}

function Zl-Utf8Enc([string]$s) {
    if ($s -notmatch '[^\x00-\x7F]') { return , ([byte[]][char[]]$s) }
    $o = [byte[]]::new(4 * $s.Length); $n = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $cp = [int]$s[$i]
        if ($cp -ge 55296 -and $cp -le 56319 -and $i + 1 -lt $s.Length) {
            $lo = [int]$s[$i + 1]
            if ($lo -ge 56320 -and $lo -le 57343) { $cp = 65536 + (($cp - 55296) -shl 10) + ($lo - 56320); $i++ }
        }
        if ($cp -lt 128) { $o[$n] = $cp; $n++ }
        elseif ($cp -lt 2048) { $o[$n] = 192 -bor ($cp -shr 6); $o[$n + 1] = 128 -bor ($cp -band 63); $n += 2 }
        elseif ($cp -lt 65536) { $o[$n] = 224 -bor ($cp -shr 12); $o[$n + 1] = 128 -bor (($cp -shr 6) -band 63); $o[$n + 2] = 128 -bor ($cp -band 63); $n += 3 }
        else { $o[$n] = 240 -bor ($cp -shr 18); $o[$n + 1] = 128 -bor (($cp -shr 12) -band 63); $o[$n + 2] = 128 -bor (($cp -shr 6) -band 63); $o[$n + 3] = 128 -bor ($cp -band 63); $n += 4 }
    }
    $r = [byte[]]::new($n); [Array]::Copy($o, 0, $r, 0, $n)
    return , $r
}

$script:ZL_CACHE = @{}
function Zl-ZipBytes([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $it = Get-Item -LiteralPath $full
    $key = $full + '|' + $it.Length + '|' + $it.LastWriteTimeUtc.Ticks
    if (-not $script:ZL_CACHE.ContainsKey($key)) { $script:ZL_CACHE = @{}; $script:ZL_CACHE[$key] = (Zl-ReadBytes $full) }
    return , $script:ZL_CACHE[$key]
}

function Read-ZipEntries([string]$Path) {
    $b = Zl-ZipBytes $Path
    $n = $b.Length
    $eocd = -1
    $lim = $n - 65557; if ($lim -lt 0) { $lim = 0 }
    for ($i = $n - 22; $i -ge $lim; $i--) {
        if ($b[$i] -eq 0x50 -and $b[$i + 1] -eq 0x4b -and $b[$i + 2] -eq 5 -and $b[$i + 3] -eq 6) { $eocd = $i; break }
    }
    if ($eocd -lt 0) { throw "not a zip file (no end of central directory): $Path" }
    $count = Zl-U16 $b ($eocd + 10)
    $cdoff = Zl-U32 $b ($eocd + 16)
    if ($count -eq 65535 -or $cdoff -eq 4294967295) { throw "zip64 is not supported: $Path" }
    $list = @()
    $p = [int]$cdoff
    for ($k = 0; $k -lt $count; $k++) {
        if ((Zl-U32 $b $p) -ne 33639248) { throw "bad central directory entry $k in $Path" }
        $flags = Zl-U16 $b ($p + 8)
        $nl = Zl-U16 $b ($p + 28); $el = Zl-U16 $b ($p + 30); $cl = Zl-U16 $b ($p + 32)
        $ename = Zl-Utf8Dec $b ($p + 46) $nl (($flags -band 2048) -ne 0)
        $list += @{ name = $ename; method = (Zl-U16 $b ($p + 10)); crc = (Zl-U32 $b ($p + 16)); csize = (Zl-U32 $b ($p + 20));
                    size = (Zl-U32 $b ($p + 24)); offset = (Zl-U32 $b ($p + 42)); flags = $flags }
        $p += 46 + $nl + $el + $cl
    }
    return , $list
}

function Read-ZipEntry([string]$Path, [string]$Name) {
    $b = Zl-ZipBytes $Path
    $ent = $null
    foreach ($e in (Read-ZipEntries $Path)) { if ($e.name -ceq $Name) { $ent = $e; break } }
    if ($null -eq $ent) { throw "no entry '$Name' in $Path" }
    if (($ent.flags -band 1) -ne 0) { throw "entry '$Name' is encrypted" }
    $p = [int]$ent.offset
    if ((Zl-U32 $b $p) -ne 67324752) { throw "bad local header for '$Name'" }
    $data = $p + 30 + (Zl-U16 $b ($p + 26)) + (Zl-U16 $b ($p + 28))
    if ($ent.method -eq 0) {
        $out = [byte[]]::new([int]$ent.size)
        if ($ent.size -gt 0) { [Array]::Copy($b, $data, $out, 0, [int]$ent.size) }
    } elseif ($ent.method -eq 8) {
        $out = Zl-Inflate $b $data
    } else { throw "entry '$Name' uses compression method $($ent.method) (only 0 stored and 8 deflate)" }
    if ($out.Length -ne $ent.size) { throw "entry '$Name': size $($out.Length), directory says $($ent.size)" }
    $crc = Zl-Crc32 $out 0 $out.Length
    if ($crc -ne $ent.crc) { throw ("entry '$Name': CRC-32 {0:x8}, directory says {1:x8}" -f $crc, $ent.crc) }
    return , $out
}

function Write-Zip([string]$Path, $Entries) {
    $items = @()
    if ($Entries -is [System.Collections.IDictionary]) { foreach ($k in $Entries.Keys) { $items += @{ name = [string]$k; data = $Entries[$k] } } }
    else { foreach ($e in $Entries) { $items += @{ name = [string]$e.name; data = $e.data } } }
    $now = Get-Date
    $dtime = ($now.Hour -shl 11) -bor ($now.Minute -shl 5) -bor ([int](($now.Second - ($now.Second % 2)) / 2))
    $ddate = (($now.Year - 1980) -shl 9) -bor ($now.Month -shl 5) -bor $now.Day
    $parts = @(); $central = @(); $off = 0
    foreach ($it in $items) {
        $data = $it.data
        if ($null -eq $data) { $data = [byte[]]::new(0) }
        if ($data -is [string]) { $data = Zl-Utf8Enc $data }
        $data = [byte[]]$data
        $nm = Zl-Utf8Enc ($it.name -replace '\\', '/')
        $crc = Zl-Crc32 $data 0 $data.Length
        $flag = 0; if ($it.name -match '[^\x00-\x7F]') { $flag = 2048 }
        $h = [byte[]]::new(30 + $nm.Length)
        $c = [byte[]]::new(46 + $nm.Length)
        $vals = @( @(0, 4, 67324752), @(4, 2, 20), @(6, 2, $flag), @(8, 2, 0), @(10, 2, $dtime), @(12, 2, $ddate), @(14, 4, $crc),
                   @(18, 4, $data.Length), @(22, 4, $data.Length), @(26, 2, $nm.Length), @(28, 2, 0) )
        foreach ($v in $vals) { for ($k = 0; $k -lt $v[1]; $k++) { $h[$v[0] + $k] = ($v[2] -shr (8 * $k)) -band 255 } }
        [Array]::Copy($nm, 0, $h, 30, $nm.Length)
        $cv = @( @(0, 4, 33639248), @(4, 2, 20), @(6, 2, 20), @(8, 2, $flag), @(10, 2, 0), @(12, 2, $dtime), @(14, 2, $ddate),
                 @(16, 4, $crc), @(20, 4, $data.Length), @(24, 4, $data.Length), @(28, 2, $nm.Length), @(30, 2, 0), @(32, 2, 0),
                 @(34, 2, 0), @(36, 2, 0), @(38, 4, 0), @(42, 4, $off) )
        foreach ($v in $cv) { for ($k = 0; $k -lt $v[1]; $k++) { $c[$v[0] + $k] = ($v[2] -shr (8 * $k)) -band 255 } }
        [Array]::Copy($nm, 0, $c, 46, $nm.Length)
        $parts += , $h; $parts += , $data; $central += , $c
        $off += $h.Length + $data.Length
    }
    $cdsize = 0; foreach ($c in $central) { $cdsize += $c.Length }
    $end = [byte[]]::new(22)
    $ev = @( @(0, 4, 101010256), @(8, 2, $items.Count), @(10, 2, $items.Count), @(12, 4, $cdsize), @(16, 4, $off) )
    foreach ($v in $ev) { for ($k = 0; $k -lt $v[1]; $k++) { $end[$v[0] + $k] = ($v[2] -shr (8 * $k)) -band 255 } }
    $total = $off + $cdsize + 22
    $o = [byte[]]::new($total); $q = 0
    foreach ($x in ($parts + $central + , $end)) { if ($x.Length -gt 0) { [Array]::Copy($x, 0, $o, $q, $x.Length) }; $q += $x.Length }
    Zl-WriteBytes $Path $o
}

# ================================================================ pgit core (after ziplib)
$ErrorActionPreference = 'Stop'
function NewMap() { return [hashtable]::new([StringComparer]::Ordinal) }
$script:HEX = [string[]]::new(256); for ($i = 0; $i -lt 256; $i++) { $script:HEX[$i] = '{0:x2}' -f $i }
$script:HEXV = @{}; for ($i = 0; $i -lt 16; $i++) { $script:HEXV[('{0:x}' -f $i)] = $i; $script:HEXV[('{0:X}' -f $i)] = $i }
$script:EPOCH = 621355968000000000
$script:OBJ = (NewMap); $script:OBJN = 0
$script:TREEFLAT = (NewMap)
$script:ZERO = '0000000000000000000000000000000000000000'
$script:XINDENT = $true

function Die([string]$m, [int]$code = 128) { throw ('PGITDIE:' + $code + ':' + $m) }
function Out-Text([string]$t) {
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}
function Out-Err([string]$t) {
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host $l }
}

# ---------------------------------------------------------------- bytes and text
function Slice([byte[]]$b, [int]$off, [int]$len) { $r = [byte[]]::new($len); if ($len -gt 0) { [Array]::Copy($b, $off, $r, 0, $len) }; return , $r }
function CatBytes($parts) {
    $n = 0; foreach ($p in $parts) { $n += $p.Length }
    $o = [byte[]]::new($n); $i = 0
    foreach ($p in $parts) { if ($p.Length -gt 0) { [Array]::Copy($p, 0, $o, $i, $p.Length) }; $i += $p.Length }
    return , $o
}
function Latin1([byte[]]$b) { if ($null -eq $b -or $b.Length -eq 0) { return '' }; return (-join [char[]]$b) }
function Latin1Bytes([string]$s) { if ($s.Length -eq 0) { return , ([byte[]]::new(0)) }; return , ([byte[]][char[]]$s) }
function Utf8Text([byte[]]$b) {                        # bytes -> string (UTF-8, invalid bytes kept as Latin-1)
    if ($null -eq $b -or $b.Length -eq 0) { return '' }
    $hi = $false; foreach ($x in $b) { if ($x -ge 128) { $hi = $true; break } }
    if (-not $hi) { return (-join [char[]]$b) }
    return (Zl-Utf8Dec $b 0 $b.Length $true)
}
function L1ToText([string]$s) {                       # a Latin-1 byte string (diff output) -> display text
    if ($s -notmatch '[^\x00-\x7F]') { return $s }
    return (Utf8Text (Latin1Bytes $s))
}
function Hex([byte[]]$b, [int]$off, [int]$len) { $h = $script:HEX; $s = ''; for ($i = 0; $i -lt $len; $i++) { $s += $h[$b[$off + $i]] }; return $s }
function HexBytes([string]$h) {
    $o = [byte[]]::new(20); $v = $script:HEXV
    for ($i = 0; $i -lt 20; $i++) { $o[$i] = $v[[string]$h[2 * $i]] * 16 + $v[[string]$h[2 * $i + 1]] }
    return , $o
}
function OctMode([string]$s) { $v = 0; foreach ($c in $s.ToCharArray()) { $v = $v * 8 + ([int]$c - 48) }; return $v }
function ModeStr([int]$m) { $s = ''; if ($m -eq 0) { return '0' }; while ($m -gt 0) { $s = [string]($m % 8) + $s; $m = ($m - ($m % 8)) / 8 }; return $s }
function BE32([byte[]]$b, [int]$i) { return (([long]$b[$i] -shl 24) -bor ([long]$b[$i + 1] -shl 16) -bor ([long]$b[$i + 2] -shl 8) -bor [long]$b[$i + 3]) }
function PutBE32([byte[]]$b, [int]$i, [long]$v) { $b[$i] = ($v -shr 24) -band 255; $b[$i + 1] = ($v -shr 16) -band 255; $b[$i + 2] = ($v -shr 8) -band 255; $b[$i + 3] = $v -band 255 }
function IsBinary([byte[]]$b) { $n = $b.Length; if ($n -gt 8000) { $n = 8000 }; if ($n -eq 0) { return $false }; return ([Array]::IndexOf($b, [byte]0, 0, $n) -ge 0) }
function SortOrd([string[]]$a) { if ($null -eq $a -or $a.Count -lt 2) { return , ([string[]]$a) }; $c = [string[]]$a.Clone(); [Array]::Sort($c, [StringComparer]::Ordinal); return , $c }
function ByteKey([string]$s) { if ($s -notmatch '[^\x00-\x7F]') { return $s }; return (Latin1 (Zl-Utf8Enc $s)) }
function SortPaths($paths) {                          # git order: by UTF-8 bytes
    $keys = (NewMap); $ks = [string[]]::new(@($paths).Count); $i = 0
    foreach ($p in $paths) { $k = ByteKey $p; $keys[$k] = $p; $ks[$i] = $k; $i++ }
    if ($ks.Count -gt 1) { [Array]::Sort($ks, [StringComparer]::Ordinal) }
    $o = [string[]]::new($ks.Count); for ($i = 0; $i -lt $ks.Count; $i++) { $o[$i] = $keys[$ks[$i]] }
    return , $o
}

function Sha1Hex([byte[]]$data) {
    $n = $data.Length
    $padLen = (($n + 8) -bor 63) + 1
    $m = [byte[]]::new($padLen)
    if ($n -gt 0) { [Array]::Copy($data, 0, $m, 0, $n) }
    $m[$n] = 0x80
    [long]$bits = [long]$n * 8
    for ($i = 0; $i -lt 8; $i++) { $m[$padLen - 1 - $i] = [byte](($bits -shr (8 * $i)) -band 255) }
    [long]$h0 = 1732584193; [long]$h1 = 4023233417; [long]$h2 = 2562383102; [long]$h3 = 271733878; [long]$h4 = 3285377520
    $w = [long[]]::new(80)
    $M32 = [long]4294967295
    for ($off = 0; $off -lt $padLen; $off += 64) {
        for ($i = 0; $i -lt 16; $i++) { $j = $off + 4 * $i; $w[$i] = ([long]$m[$j] -shl 24) -bor ([long]$m[$j + 1] -shl 16) -bor ([long]$m[$j + 2] -shl 8) -bor [long]$m[$j + 3] }
        for ($i = 16; $i -lt 80; $i++) { $x = $w[$i - 3] -bxor $w[$i - 8] -bxor $w[$i - 14] -bxor $w[$i - 16]; $w[$i] = (($x -shl 1) -bor ($x -shr 31)) -band $M32 }
        $a = $h0; $b = $h1; $c = $h2; $d = $h3; $e = $h4
        for ($i = 0; $i -lt 20; $i++) { $t = ((($a -shl 5) -bor ($a -shr 27)) + (($b -band $c) -bor ((-bnot $b) -band $d)) + $e + 1518500249 + $w[$i]) -band $M32; $e = $d; $d = $c; $c = (($b -shl 30) -bor ($b -shr 2)) -band $M32; $b = $a; $a = $t }
        for (; $i -lt 40; $i++) { $t = ((($a -shl 5) -bor ($a -shr 27)) + ($b -bxor $c -bxor $d) + $e + 1859775393 + $w[$i]) -band $M32; $e = $d; $d = $c; $c = (($b -shl 30) -bor ($b -shr 2)) -band $M32; $b = $a; $a = $t }
        for (; $i -lt 60; $i++) { $t = ((($a -shl 5) -bor ($a -shr 27)) + (($b -band $c) -bor ($b -band $d) -bor ($c -band $d)) + $e + 2400959708 + $w[$i]) -band $M32; $e = $d; $d = $c; $c = (($b -shl 30) -bor ($b -shr 2)) -band $M32; $b = $a; $a = $t }
        for (; $i -lt 80; $i++) { $t = ((($a -shl 5) -bor ($a -shr 27)) + ($b -bxor $c -bxor $d) + $e + 3395469782 + $w[$i]) -band $M32; $e = $d; $d = $c; $c = (($b -shl 30) -bor ($b -shr 2)) -band $M32; $b = $a; $a = $t }
        $h0 = ($h0 + $a) -band $M32; $h1 = ($h1 + $b) -band $M32; $h2 = ($h2 + $c) -band $M32; $h3 = ($h3 + $d) -band $M32; $h4 = ($h4 + $e) -band $M32
    }
    return ('{0:x8}{1:x8}{2:x8}{3:x8}{4:x8}' -f $h0, $h1, $h2, $h3, $h4)
}

# ---------------------------------------------------------------- repository
function Set-Repo([string]$start) {
    if (-not $start) { $start = (Get-Location).Path }
    $d = (Resolve-Path -LiteralPath $start -ErrorAction Stop).Path
    if ($d.EndsWith('\') -and $d.Length -gt 3) { $d = $d.Substring(0, $d.Length - 1) }
    $cwd = $d
    $ceil = @(); if ($env:GIT_CEILING_DIRECTORIES) { foreach ($c in ($env:GIT_CEILING_DIRECTORIES -split ';')) { if ($c) { $ceil += $c.TrimEnd('\').ToLower() } } }
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $d '.git') -PathType Container) { break }
        $parent = Split-Path $d -Parent
        if ($parent -and $ceil -contains $parent.TrimEnd('\').ToLower()) { Die 'not a git repository (or any parent up to the ceiling directory): .git' }
        if (-not $parent -or $parent -eq $d) { Die 'not a git repository (or any of the parent directories): .git' }
        $d = $parent
    }
    if ($d.EndsWith('\')) { $d = $d.Substring(0, $d.Length - 1) }
    if ($script:ROOT -ne $d) { $script:OBJ = (NewMap); $script:OBJN = 0; $script:TREEFLAT = (NewMap); $script:CONF = $null; $script:PACKIDX = (NewMap); $script:PACKOBJ = (NewMap) }
    $script:ROOT = $d
    $script:GITDIR = $d + '\.git'
    $script:PREFIX = ''
    if ($cwd.Length -gt $d.Length) { $script:PREFIX = $cwd.Substring($d.Length + 1).Replace('\', '/') }
}
function Full([string]$rel) { if ($rel -eq '') { return $script:ROOT }; return ($script:ROOT + '\' + $rel.Replace('/', '\')) }
function GitPath([string]$rel) { return ($script:GITDIR + '\' + $rel.Replace('/', '\')) }
function ReadText([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }; return (Utf8Text (Zl-ReadBytes $p)) }
function WriteText([string]$p, [string]$t) {
    $dir = Split-Path $p -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Zl-WriteBytes $p (Zl-Utf8Enc $t)
}
function EnsureDir([string]$dir) { if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null } }

# ---------------------------------------------------------------- objects
function ObjPath([string]$id) { return ($script:GITDIR + '\objects\' + $id.Substring(0, 2) + '\' + $id.Substring(2)) }
function HasObject([string]$id) { return ($script:OBJ.ContainsKey($id) -or (Test-Path -LiteralPath (ObjPath $id) -PathType Leaf) -or (PackHas $script:GITDIR $id)) }
function HashObject([string]$type, [byte[]]$body) {
    $full = CatBytes @((Latin1Bytes ($type + ' ' + $body.Length)), ([byte[]](, 0)), $body)
    return @{ id = (Sha1Hex $full); full = $full }
}
function WriteObject([string]$type, [byte[]]$body) {
    $h = HashObject $type $body
    $p = ObjPath $h.id
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        EnsureDir (Split-Path $p -Parent)
        Zl-WriteBytes $p (Zl-Zlib $h.full)
    }
    return $h.id
}
function ReadObject([string]$id) {
    if ($script:OBJ.ContainsKey($id)) { return $script:OBJ[$id] }
    $p = ObjPath $id
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        $o = PackFind $script:GITDIR $id                   # pgit reads packs; what it writes is loose
        if ($null -eq $o) { Die "object $id not found" }
    } else {
        $raw = Zl-Unzlib (Zl-ReadBytes $p)
        $z = [Array]::IndexOf($raw, [byte]0)
        $hdr = Latin1 (Slice $raw 0 $z)
        $sp = $hdr.IndexOf(' ')
        $o = @{ type = $hdr.Substring(0, $sp); body = (Slice $raw ($z + 1) ($raw.Length - $z - 1)) }
    }
    if ($script:OBJN -gt 4000) { $script:OBJ = (NewMap); $script:OBJN = 0 }
    $script:OBJ[$id] = $o; $script:OBJN++
    return $o
}
function ReadBlob([string]$id) { $o = ReadObject $id; if ($o.type -ne 'blob') { Die "$id is a $($o.type), not a blob" }; return , $o.body }

$script:ABBR = (NewMap)
function Abbrev([string]$id, [int]$min = 7) {
    if ($id -eq $script:ZERO) { return $id.Substring(0, $min) }
    $dir = $script:GITDIR + '\objects\' + $id.Substring(0, 2)
    if (-not $script:ABBR.ContainsKey($dir)) {
        $script:ABBR[$dir] = @(Get-ChildItem -LiteralPath $dir -Name -ErrorAction SilentlyContinue)
    }
    $names = $script:ABBR[$dir]
    $pk = @(); foreach ($x in (PackList $script:GITDIR)) { foreach ($h in (IdxPrefix $x $id.Substring(0, 4))) { if ($h -ne $id) { $pk += $h.Substring(2) } } }
    if ($pk.Count) { $names = @($names) + $pk }
    $n = $min
    while ($n -lt 40) {
        $pre = $id.Substring(2, $n - 2); $c = 0
        foreach ($x in $names) { if ($x.StartsWith($pre)) { $c++ } }
        if ($c -le 1) { break }
        $n++
    }
    return $id.Substring(0, $n)
}

# ---------------------------------------------------------------- refs
function PackedRefs() {
    $m = (NewMap)
    $t = ReadText (GitPath 'packed-refs')
    if ($null -eq $t) { return $m }
    $last = $null
    foreach ($l in ($t -split "`n")) {
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        if ($l.StartsWith('^')) { if ($last) { $m[$last + '^{}'] = $l.Substring(1).Trim() }; continue }
        $sp = $l.IndexOf(' '); if ($sp -lt 0) { continue }
        $last = $l.Substring($sp + 1).Trim(); $m[$last] = $l.Substring(0, $sp)
    }
    return $m
}
function ReadRef([string]$nm) {                   # full ref name (HEAD, refs/...) -> id or $null; follows symbolic refs
    for ($depth = 0; $depth -lt 10; $depth++) {
        $p = GitPath $nm
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $t = (ReadText $p).Trim()
            if ($t.StartsWith('ref: ')) { $nm = $t.Substring(5).Trim(); continue }
            return $t
        }
        $pr = PackedRefs
        if ($pr.ContainsKey($nm)) { return $pr[$nm] }
        return $null
    }
    return $null
}
function HeadRef() {                                  # 'refs/heads/x' or $null when detached
    $t = (ReadText (GitPath 'HEAD'))
    if ($null -eq $t) { Die 'HEAD is missing' }
    $t = $t.Trim()
    if ($t.StartsWith('ref: ')) { return $t.Substring(5).Trim() }
    return $null
}
function HeadCommit() { return (ReadRef 'HEAD') }
function UpdateRef([string]$nm, [string]$id) { WriteText (GitPath $nm) ($id + "`n") }
function SetHead([string]$refOrId) {
    if ($refOrId.StartsWith('refs/')) { WriteText (GitPath 'HEAD') ("ref: $refOrId`n") } else { WriteText (GitPath 'HEAD') ($refOrId + "`n") }
}
function DeleteRef([string]$nm) {
    $p = GitPath $nm
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    $t = ReadText (GitPath 'packed-refs')
    if ($null -ne $t) {
        $out = @(); $skip = $false
        foreach ($l in ($t -split "`n")) {
            if ($l -eq '') { continue }
            if ($l.StartsWith('^')) { if (-not $skip) { $out += $l }; continue }
            $skip = $l.EndsWith(' ' + $nm)
            if (-not $skip) { $out += $l }
        }
        WriteText (GitPath 'packed-refs') (($out -join "`n") + "`n")
    }
}
function ListRefs([string]$RefPrefix) {                 # @{ 'refs/heads/x' = id } loose + packed
    $m = (NewMap)
    $pr = PackedRefs
    foreach ($k in $pr.Keys) { if ($k.StartsWith($RefPrefix) -and -not $k.EndsWith('^{}')) { $m[$k] = $pr[$k] } }
    $base = GitPath $RefPrefix
    if (Test-Path -LiteralPath $base) {
        foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($script:GITDIR.Length + 1).Replace('\', '/')
            $m[$rel] = (ReadText $f.FullName).Trim()
        }
    }
    return $m
}

function PeelTo([string]$id, [string]$want) {        # follow tags (and commit->tree) to an object of type $want
    for ($i = 0; $i -lt 20; $i++) {
        $o = ReadObject $id
        if ($want -eq '' -or $o.type -eq $want) { return $id }
        if ($o.type -eq 'tag') { $id = ([regex]'(?m)^object ([0-9a-f]{40})').Match((Latin1 $o.body)).Groups[1].Value; if ($want -eq 'any') { return $id }; continue }
        if ($o.type -eq 'commit' -and $want -eq 'tree') { return (ParseCommit $id).tree }
        Die "$id is a $($o.type), not a $want"
    }
    Die "${id}: too many tag levels"
}

function Rev([string]$spec, [bool]$quiet = $false) {   # a revision -> object id
    $s = $spec
    if ($s -eq '@') { $s = 'HEAD' }
    $peel = $null
    $m = [regex]::Match($s, '\^\{(\w*)\}$')
    if ($m.Success) { $peel = $m.Groups[1].Value; if ($peel -eq '') { $peel = 'any' }; $s = $s.Substring(0, $s.Length - $m.Length) }
    $nav = [regex]::Match($s, '((?:[~^][0-9]*)+)$')
    $ops = ''
    if ($nav.Success -and $nav.Length -lt $s.Length) { $ops = $nav.Value; $s = $s.Substring(0, $s.Length - $nav.Length) }
    $id = $null
    if ($s -match '^[0-9a-f]{40}$') { $id = $s }
    else {
        foreach ($cand in @($s, "refs/$s", "refs/tags/$s", "refs/heads/$s", "refs/remotes/$s", "refs/remotes/$s/HEAD")) {
            if ($cand -cnotmatch '^[A-Z_]+$' -and -not $cand.StartsWith('refs/')) { continue }
            $id = ReadRef $cand
            if ($id) { break }
        }
        if (-not $id -and $s -match '^[0-9a-f]{4,39}$') {
            $dir = $script:GITDIR + '\objects\' + $s.Substring(0, 2)
            $hits = @(Get-ChildItem -LiteralPath $dir -Name -ErrorAction SilentlyContinue | Where-Object { $_.StartsWith($s.Substring(2)) } | ForEach-Object { $s.Substring(0, 2) + $_ })
            foreach ($x in (PackList $script:GITDIR)) { foreach ($h in (IdxPrefix $x $s)) { if ($hits -notcontains $h) { $hits += $h } } }
            if ($hits.Count -gt 1) { Die "short object ID $s is ambiguous" }
            if ($hits.Count -eq 1) { $id = $hits[0] }
        }
    }
    if (-not $id) { if ($quiet) { return $null }; Die "ambiguous argument '$spec': unknown revision or path not in the working tree.`nUse '--' to separate paths from revisions, like this:`n'git <command> [<revision>...] -- [<file>...]'" }
    if ($ops) {
        foreach ($op in [regex]::Matches($ops, '([~^])([0-9]*)')) {
            $n = 1; if ($op.Groups[2].Value -ne '') { $n = [int]$op.Groups[2].Value }
            $id = PeelTo $id 'commit'
            if ($op.Groups[1].Value -eq '~') {
                for ($k = 0; $k -lt $n; $k++) { $c = ParseCommit $id; if ($c.parents.Count -eq 0) { if ($quiet) { return $null }; Die "ambiguous argument '$spec': unknown revision or path not in the working tree.`nUse '--' to separate paths from revisions, like this:`n'git <command> [<revision>...] -- [<file>...]'" }; $id = $c.parents[0] }
            } else {
                if ($n -eq 0) { continue }
                $c = ParseCommit $id
                if ($c.parents.Count -lt $n) { if ($quiet) { return $null }; Die "ambiguous argument '$spec': unknown revision or path not in the working tree.`nUse '--' to separate paths from revisions, like this:`n'git <command> [<revision>...] -- [<file>...]'" }
                $id = $c.parents[$n - 1]
            }
        }
    }
    if ($peel) { $id = PeelTo $id $peel }
    return $id
}
function RevCommit([string]$spec) { return (PeelTo (Rev $spec) 'commit') }

# ---------------------------------------------------------------- commits, tags, trees
function ParsePerson([string]$l) {
    $m = [regex]::Match($l, '^(.*) <([^>]*)> (-?\d+) ([+-]\d{4})$')
    if (-not $m.Success) { return @{ name = $l; email = ''; time = [long]0; tz = '+0000'; raw = $l } }
    return @{ name = $m.Groups[1].Value; email = $m.Groups[2].Value; time = [long]$m.Groups[3].Value; tz = $m.Groups[4].Value; raw = $l }
}
function ParseCommit([string]$id) {
    $o = ReadObject $id
    if ($o.type -ne 'commit') { Die "$id is a $($o.type), not a commit" }
    $t = Utf8Text $o.body
    $i = $t.IndexOf("`n`n")
    if ($i -lt 0) { $head = $t; $msg = '' } else { $head = $t.Substring(0, $i); $msg = $t.Substring($i + 2) }
    $c = @{ id = $id; tree = ''; parents = @(); author = $null; committer = $null; message = $msg; raw = $t }
    foreach ($l in ($head -split "`n")) {
        if ($l.StartsWith(' ')) { continue }
        $sp = $l.IndexOf(' '); if ($sp -lt 0) { continue }
        $k = $l.Substring(0, $sp); $v = $l.Substring($sp + 1)
        if ($k -eq 'tree') { $c.tree = $v } elseif ($k -eq 'parent') { $c.parents += $v }
        elseif ($k -eq 'author') { $c.author = ParsePerson $v } elseif ($k -eq 'committer') { $c.committer = ParsePerson $v }
    }
    return $c
}
function ParseTag([string]$id) {
    $t = Utf8Text (ReadObject $id).body
    $i = $t.IndexOf("`n`n"); if ($i -lt 0) { $head = $t; $msg = '' } else { $head = $t.Substring(0, $i); $msg = $t.Substring($i + 2) }
    $g = @{ id = $id; message = $msg; tagger = $null }
    foreach ($l in ($head -split "`n")) {
        $sp = $l.IndexOf(' '); if ($sp -lt 0) { continue }
        $k = $l.Substring(0, $sp); $v = $l.Substring($sp + 1)
        if ($k -eq 'tagger') { $g.tagger = ParsePerson $v } else { $g[$k] = $v }
    }
    return $g
}
function ParseTree([string]$id) {
    $o = ReadObject $id
    if ($o.type -ne 'tree') { Die "$id is a $($o.type), not a tree" }
    $b = $o.body; $n = $b.Length; $i = 0; $list = @()
    while ($i -lt $n) {
        $sp = [Array]::IndexOf($b, [byte]32, $i)
        $z = [Array]::IndexOf($b, [byte]0, $sp)
        $mode = Latin1 (Slice $b $i ($sp - $i))
        $nm = Zl-Utf8Dec $b ($sp + 1) ($z - $sp - 1) $true
        $list += @{ mode = $mode; name = $nm; id = (Hex $b ($z + 1) 20); tree = ($mode -eq '40000') }
        $i = $z + 21
    }
    return , $list
}
function FlattenTree([string]$id) {                  # tree id -> @{ path = @{ mode (int); id } } (cached)
    if ($script:TREEFLAT.ContainsKey($id)) { return $script:TREEFLAT[$id] }
    $m = (NewMap)
    $st = @{}; $sp = 0
    $st[$sp] = @{ id = $id; pre = '' }; $sp++
    while ($sp -gt 0) {
        $sp--; $top = $st[$sp]
        foreach ($e in (ParseTree $top.id)) {
            $p = $e.name; if ($top.pre) { $p = $top.pre + '/' + $e.name }
            if ($e.tree) { $st[$sp] = @{ id = $e.id; pre = $p }; $sp++ } elseif ($e.mode -ne '160000') { $m[$p] = @{ mode = (OctMode $e.mode); id = $e.id } }
        }
    }
    $script:TREEFLAT[$id] = $m
    return $m
}
function CommitFiles([string]$commit) { if (-not $commit) { return (NewMap) }; return (FlattenTree (ParseCommit $commit).tree) }

function WriteTreeFromMap($map) {                   # @{ path = @{mode; id} } -> tree id (writes every subtree)
    $treeRoot = @{ f = (NewMap); d = (NewMap) }
    foreach ($p in $map.Keys) {
        $parts = $p.Split('/'); $node = $treeRoot
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            if (-not $node.d.ContainsKey($parts[$i])) { $node.d[$parts[$i]] = @{ f = (NewMap); d = (NewMap) } }
            $node = $node.d[$parts[$i]]
        }
        $node.f[$parts[$parts.Count - 1]] = $map[$p]
    }
    return (WriteTreeNode $treeRoot)
}
function WriteTreeNode($node) {
    $items = (NewMap); $keys = @()
    foreach ($k in $node.f.Keys) { $kk = ByteKey $k; $items[$kk] = @{ name = $k; mode = (ModeStr $node.f[$k].mode); id = $node.f[$k].id }; $keys += $kk }
    foreach ($k in $node.d.Keys) { $kk = (ByteKey $k) + '/'; $items[$kk] = @{ name = $k; mode = '40000'; id = (WriteTreeNode $node.d[$k]) }; $keys += $kk }
    $parts = @()
    foreach ($k in (SortOrd ([string[]]$keys))) {
        $it = $items[$k]
        $parts += , (Latin1Bytes ($it.mode + ' ')); $parts += , (Zl-Utf8Enc $it.name); $parts += , ([byte[]](, 0)); $parts += , (HexBytes $it.id)
    }
    return (WriteObject 'tree' (CatBytes $parts))
}

# ---------------------------------------------------------------- index (.git/index, version 2)
function ReadIndex() {
    $p = GitPath 'index'
    $ix = @{ entries = (NewMap); mtime = [long]0; unmerged = (NewMap) }
    $script:IXUM = $ix.unmerged
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $ix }
    $fi = Get-Item -LiteralPath $p
    $t = $fi.LastWriteTimeUtc.Ticks - $script:EPOCH
    $ix.mtime = [long](($t - ($t % 10000000)) / 10000000)
    $b = Zl-ReadBytes $p
    if ($b.Length -lt 12 -or (Latin1 (Slice $b 0 4)) -ne 'DIRC') { Die 'index file is corrupt' }
    $ver = BE32 $b 4; $n = BE32 $b 8
    if ($ver -eq 4) { Die 'index version 4 is not supported (git config index.version 2; git update-index --index-version 2)' }
    $q = 12
    for ($k = 0; $k -lt $n; $k++) {
        $flags = ([int]$b[$q + 60] -shl 8) -bor [int]$b[$q + 61]
        $nb = $q + 62
        if ($ver -ge 3 -and ($flags -band 16384) -ne 0) { $nb += 2 }
        $nl = $flags -band 4095
        if ($nl -eq 4095) { $nl = [Array]::IndexOf($b, [byte]0, $nb) - $nb }
        $pth = Zl-Utf8Dec $b $nb $nl $true
        $stage = ($flags -shr 12) -band 3
        $e = @{ path = $pth; cs = (BE32 $b $q); cns = (BE32 $b ($q + 4)); ms = (BE32 $b ($q + 8)); mns = (BE32 $b ($q + 12));
                dev = (BE32 $b ($q + 16)); ino = (BE32 $b ($q + 20)); mode = [int](BE32 $b ($q + 24)); uid = (BE32 $b ($q + 28));
                gid = (BE32 $b ($q + 32)); size = (BE32 $b ($q + 36)); id = (Hex $b ($q + 40) 20) }
        if ($stage -eq 0) { $ix.entries[$pth] = $e } else { $ix.conflict = $true; if (-not $ix.unmerged.ContainsKey($pth)) { $ix.unmerged[$pth] = @{} }; $ix.unmerged[$pth][$stage] = $e }
        $len = ($nb - $q) + $nl
        $q += ($len + 8) - (($len + 8) % 8)
    }
    return $ix
}
function WriteIndex($ents, $um = $null) {              # stage-0 entries; conflict stages ($um, else those last read) stay unless resolved
    if ($null -eq $um) { $um = $script:IXUM }; if ($null -eq $um) { $um = (NewMap) }
    $rows = @()
    $keys = (NewMap); foreach ($k in $ents.Keys) { $keys[$k] = 1 }; foreach ($k in $um.Keys) { if (-not $ents.ContainsKey($k)) { $keys[$k] = 1 } }
    foreach ($p in (SortPaths @($keys.Keys))) {
        if ($ents.ContainsKey($p)) { $rows += , @($p, 0, $ents[$p]) }
        else { foreach ($stg in 1, 2, 3) { if ($um[$p].ContainsKey($stg)) { $rows += , @($p, $stg, $um[$p][$stg]) } } }
    }
    $parts = @()
    $hdr = [byte[]]::new(12); $hdr[0] = 68; $hdr[1] = 73; $hdr[2] = 82; $hdr[3] = 67
    PutBE32 $hdr 4 2; PutBE32 $hdr 8 $rows.Count
    $parts += , $hdr
    foreach ($row in $rows) {
        $p = $row[0]; $e = $row[2]
        $nm = Zl-Utf8Enc $p
        $len = 62 + $nm.Length
        $tot = ($len + 8) - (($len + 8) % 8)
        $r = [byte[]]::new($tot)
        PutBE32 $r 0 $e.cs; PutBE32 $r 4 $e.cns; PutBE32 $r 8 $e.ms; PutBE32 $r 12 $e.mns
        PutBE32 $r 16 $e.dev; PutBE32 $r 20 $e.ino; PutBE32 $r 24 $e.mode; PutBE32 $r 28 $e.uid; PutBE32 $r 32 $e.gid
        PutBE32 $r 36 ($e.size -band 4294967295)
        [Array]::Copy((HexBytes $e.id), 0, $r, 40, 20)
        $fl = $nm.Length; if ($fl -gt 4095) { $fl = 4095 }
        $fl = $fl -bor ($row[1] -shl 12)
        $r[60] = ($fl -shr 8) -band 255; $r[61] = $fl -band 255
        [Array]::Copy($nm, 0, $r, 62, $nm.Length)
        $parts += , $r
    }
    $body = CatBytes $parts
    $all = CatBytes @($body, (HexBytes (Sha1Hex $body)))
    Zl-WriteBytes (GitPath 'index') $all
}
function StatEntry([string]$pth, $fi, [string]$id, [int]$mode) {
    $t = $fi.LastWriteTimeUtc.Ticks - $script:EPOCH
    $s = [long](($t - ($t % 10000000)) / 10000000); $ns = [long](($t % 10000000) * 100)
    return @{ path = $pth; cs = $s; cns = $ns; ms = $s; mns = $ns; dev = 0; ino = 0; mode = $mode; uid = 0; gid = 0; size = [long]$fi.Length; id = $id }
}
function StatSame($e, $fi, [long]$ixmtime) {
    $t = $fi.LastWriteTimeUtc.Ticks - $script:EPOCH
    $s = [long](($t - ($t % 10000000)) / 10000000); $ns = [long](($t % 10000000) * 100)
    if ($e.size -ne ([long]$fi.Length -band 4294967295)) { return $false }
    if ($e.ms -ne $s -or $e.mns -ne $ns) { return $false }
    if ($s -ge $ixmtime) { return $false }            # racily clean: check the content
    return $true
}
function HashFile([string]$full) { return (HashObject 'blob' (Zl-ReadBytes $full)).id }

# ---------------------------------------------------------------- ignore rules and the worktree walk
function GlobRx([string]$g) {
    $o = ''; $i = 0; $n = $g.Length
    while ($i -lt $n) {
        $c = $g[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $n -and $g[$i + 1] -eq '*') {
                $atStart = ($i -eq 0 -or $g[$i - 1] -eq '/'); $j = $i + 2
                if ($atStart -and $j -lt $n -and $g[$j] -eq '/') { $o += '(?:.*/)?'; $i = $j + 1; continue }
                if ($atStart -and $j -eq $n) { $o += '.*'; $i = $j; continue }
                $o += '[^/]*'; $i = $j; continue
            }
            $o += '[^/]*'; $i++; continue
        }
        if ($c -eq '?') { $o += '[^/]'; $i++; continue }
        if ($c -eq '[') {
            $j = $g.IndexOf(']', $i + 2)
            if ($j -gt 0) {
                $cls = $g.Substring($i + 1, $j - $i - 1)
                if ($cls.StartsWith('!')) { $cls = '^' + $cls.Substring(1) }
                $o += '[' + $cls.Replace('\', '\\') + ']'; $i = $j + 1; continue
            }
        }
        if ($c -eq '\' -and $i + 1 -lt $n) { $o += [regex]::Escape([string]$g[$i + 1]); $i += 2; continue }
        $o += [regex]::Escape([string]$c); $i++
    }
    return $o
}
function ParseIgnore([string]$text, [string]$base) {
    $rules = @()
    if ($null -eq $text) { return , $rules }
    foreach ($l in ($text -split "`n")) {
        $l = $l.TrimEnd("`r")
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        $l = $l -replace '(?<!\\)\s+$', ''
        if ($l -eq '') { continue }
        $neg = $false
        if ($l.StartsWith('!')) { $neg = $true; $l = $l.Substring(1) } elseif ($l.StartsWith('\!') -or $l.StartsWith('\#')) { $l = $l.Substring(1) }
        $dirOnly = $false
        if ($l.EndsWith('/')) { $dirOnly = $true; $l = $l.TrimEnd('/') }
        $anch = $l.Contains('/')
        if ($l.StartsWith('/')) { $l = $l.Substring(1) }
        $rules += @{ rx = [regex]('^' + (GlobRx $l) + '$'); neg = $neg; dir = $dirOnly; anch = $anch; base = $base }
    }
    return , $rules
}
function IsIgnored([string]$rel, [bool]$isDir, $rules) {
    $res = $false
    foreach ($r in $rules) {
        $sub = $rel
        if ($r.base) { if (-not $rel.StartsWith($r.base + '/')) { continue }; $sub = $rel.Substring($r.base.Length + 1) }
        if ($r.dir -and -not $isDir) { continue }
        if ($r.anch) { $tgt = $sub } else { $i = $sub.LastIndexOf('/'); $tgt = $sub.Substring($i + 1) }
        if ($r.rx.IsMatch($tgt)) { $res = -not $r.neg }
    }
    return $res
}
function BaseRules() { return (ParseIgnore (ReadText (GitPath 'info/exclude')) '') }
function Walk([string]$rel, $rules, $files, [bool]$noIgnore = $false) {   # fills $files[rel] = FileInfo (non-ignored)
    $full = Full $rel
    $items = @(Get-ChildItem -Force -LiteralPath $full -ErrorAction SilentlyContinue)
    foreach ($it in $items) { if ($it.Name -eq '.gitignore' -and -not $it.PSIsContainer) { $rules = $rules + (ParseIgnore (ReadText $it.FullName) $rel) } }
    foreach ($it in $items) {
        $r = $it.Name; if ($rel) { $r = $rel + '/' + $it.Name }
        if ($it.PSIsContainer) {
            if ($rel -eq '' -and $it.Name -eq '.git') { continue }
            if (Test-Path -LiteralPath ($it.FullName + '\.git')) { continue }   # a nested repository
            if (-not $noIgnore -and (IsIgnored $r $true $rules)) { continue }
            Walk $r $rules $files $noIgnore
        } else {
            if (-not $noIgnore -and (IsIgnored $r $false $rules)) { continue }
            $files[$r] = $it
        }
    }
}
function Worktree([string]$under = '') { $f = (NewMap); Walk $under (BaseRules) $f; return $f }

# ---------------------------------------------------------------- pathspecs
function NormPath([string]$p) {
    $parts = @(); foreach ($x in ($p -split '[\\/]')) { if ($x -eq '' -or $x -eq '.') { continue }; if ($x -eq '..') { if ($parts.Count) { if ($parts.Count -eq 1) { $parts = @() } else { $parts = $parts[0..($parts.Count - 2)] } } else { Die "'$p' is outside repository" }; continue }; $parts += $x }
    return ($parts -join '/')
}
function Specs($args2) {                             # command-line paths -> repo-relative specs
    $o = @()
    foreach ($a in $args2) {
        $p = $a
        if ($p -match '^[A-Za-z]:[\\/]' ) {
            if (-not $p.ToLower().StartsWith($script:ROOT.ToLower())) { Die "'$a' is outside repository" }
            $p = $p.Substring($script:ROOT.Length)
            $o += (NormPath $p); continue
        }
        if ($script:PREFIX) { $p = $script:PREFIX + '/' + $p }
        $o += (NormPath $p)
    }
    return , $o
}
function SpecMatch([string]$pth, $specs) {
    if ($null -eq $specs -or $specs.Count -eq 0) { return $true }
    foreach ($s in $specs) {
        if ($s -eq '') { return $true }
        if ($s -match '[*?\[]') { if ($pth -clike $s) { return $true }; continue }
        if ($pth -ceq $s -or $pth.StartsWith($s + '/')) { return $true }
    }
    return $false
}
function RelOut([string]$pth) {                      # a repo path shown relative to the current directory
    $pre = $script:PREFIX
    if (-not $pre) { return $pth }
    $a = $pre.Split('/'); $b = $pth.Split('/')
    $i = 0; while ($i -lt $a.Count -and $i -lt $b.Count - 1 -and $a[$i] -ceq $b[$i]) { $i++ }
    $up = @(); for ($k = $i; $k -lt $a.Count; $k++) { $up += '..' }
    $rest = @(); for ($k = $i; $k -lt $b.Count; $k++) { $rest += $b[$k] }
    return (($up + $rest) -join '/')
}
function QuotePath([string]$p) {                     # core.quotePath: C-style quoting of unusual bytes
    if ($p -notmatch '[^\x20-\x21\x23-\x5B\x5D-\x7E]') { return $p }
    $b = Zl-Utf8Enc $p; $o = '"'
    foreach ($x in $b) {
        if ($x -eq 34) { $o += '\"' } elseif ($x -eq 92) { $o += '\\' } elseif ($x -eq 9) { $o += '\t' } elseif ($x -eq 10) { $o += '\n' }
        elseif ($x -eq 13) { $o += '\r' } elseif ($x -eq 7) { $o += '\a' } elseif ($x -eq 8) { $o += '\b' } elseif ($x -eq 11) { $o += '\v' } elseif ($x -eq 12) { $o += '\f' }
        elseif ($x -lt 32 -or $x -ge 127) { $o += '\' + (ModeStr $x).PadLeft(3, '0') } else { $o += [string][char]$x }
    }
    return $o + '"'
}

# ---------------------------------------------------------------- config
function ConfigFiles() {
    $f = @()
    $h = $env:USERPROFILE; if (-not $h) { $h = $env:HOME }
    if ($h) { $f += ($h + '\.gitconfig') }
    if ($script:GITDIR) { $f += (GitPath 'config') }
    return , $f
}
function ParseConfig([string]$file) {
    $m = @(); $t = ReadText $file
    if ($null -eq $t) { return , $m }
    $sec = ''
    foreach ($l in ($t -split "`n")) {
        $l = $l.Trim()
        if ($l -eq '' -or $l.StartsWith('#') -or $l.StartsWith(';')) { continue }
        $s = [regex]::Match($l, '^\[\s*([A-Za-z0-9.-]+)(?:\s+"(.*)")?\s*\]$')
        if ($s.Success) { $sec = $s.Groups[1].Value.ToLower(); if ($s.Groups[2].Success) { $sec += '.' + $s.Groups[2].Value }; continue }
        $kv = [regex]::Match($l, '^([A-Za-z0-9-]+)\s*(?:=\s*(.*))?$')
        if ($kv.Success) {
            $v = 'true'; if ($kv.Groups[2].Success) { $v = $kv.Groups[2].Value.Trim(); if ($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) } }
            $m += @{ key = ($sec + '.' + $kv.Groups[1].Value.ToLower()); value = $v }
        }
    }
    return , $m
}
function ConfigKey([string]$k) { $i = $k.LastIndexOf('.'); $j = $k.IndexOf('.'); if ($i -eq $j) { return $k.ToLower() }; return ($k.Substring(0, $j).ToLower() + $k.Substring($j, $i - $j) + $k.Substring($i).ToLower()) }
function GetConfig([string]$key) {
    $key = ConfigKey $key; $v = $null
    foreach ($f in (ConfigFiles)) { foreach ($e in (ParseConfig $f)) { if ($e.key -ceq $key) { $v = $e.value } } }
    return $v
}
function SetConfig([string]$key, [string]$value, [string]$file, [bool]$unset = $false) {
    $i = $key.LastIndexOf('.'); if ($i -lt 1) { Die "key does not contain a section: $key" }
    $secFull = $key.Substring(0, $i); $nm = $key.Substring($i + 1)
    $j = $secFull.IndexOf('.')
    if ($j -ge 0) { $hdr = '[' + $secFull.Substring(0, $j).ToLower() + ' "' + $secFull.Substring($j + 1) + '"]'; $secKey = $secFull.Substring(0, $j).ToLower() + '.' + $secFull.Substring($j + 1) }
    else { $hdr = '[' + $secFull.ToLower() + ']'; $secKey = $secFull.ToLower() }
    $t = ReadText $file; if ($null -eq $t) { $t = '' }
    $lines = [string[]]($t -split "`n"); if ($t -eq '') { $lines = @() }
    $out = @(); $sec = ''; $done = $false; $lastInSec = -1
    for ($k = 0; $k -lt $lines.Count; $k++) {
        $l = $lines[$k]
        $s = [regex]::Match($l.Trim(), '^\[\s*([A-Za-z0-9.-]+)(?:\s+"(.*)")?\s*\]$')
        if ($s.Success) { $sec = $s.Groups[1].Value.ToLower(); if ($s.Groups[2].Success) { $sec += '.' + $s.Groups[2].Value } }
        elseif ($sec -ceq $secKey) {
            $kv = [regex]::Match($l.Trim(), '^([A-Za-z0-9-]+)\s*(=|$)')
            if ($kv.Success -and $kv.Groups[1].Value.ToLower() -eq $nm.ToLower()) {
                if (-not $unset -and -not $done) { $out += ("`t" + $nm + ' = ' + $value) }
                $done = $true; continue
            }
        }
        $out += $l
        if ($sec -ceq $secKey -and $l.Trim() -ne '') { $lastInSec = $out.Count - 1 }
    }
    if (-not $done -and -not $unset) {
        if ($lastInSec -ge 0) { $new = @(); for ($k = 0; $k -lt $out.Count; $k++) { $new += $out[$k]; if ($k -eq $lastInSec) { $new += ("`t" + $nm + ' = ' + $value) } }; $out = $new }
        else { while ($out.Count -and $out[$out.Count - 1] -eq '') { $out = @($out[0..($out.Count - 2)]) }; $out += $hdr; $out += ("`t" + $nm + ' = ' + $value) }
    }
    while ($out.Count -and $out[$out.Count - 1] -eq '') { if ($out.Count -eq 1) { $out = @() } else { $out = @($out[0..($out.Count - 2)]) } }
    WriteText $file (($out -join "`n") + "`n")
}

# ---------------------------------------------------------------- people and dates
function NowStamp() {
    $t = (Get-Date).ToUniversalTime().Ticks - $script:EPOCH
    $u = [long](($t - ($t % 10000000)) / 10000000)
    $z = (Get-Date -Format 'zzz').Replace(':', '')
    return "$u $z"
}
function ParseDateEnv([string]$d) {
    if (-not $d) { return (NowStamp) }
    $m = [regex]::Match($d.Trim(), '^@?(\d+)(?:\s+([+-]\d{4}))?$')
    if ($m.Success) { $z = '+0000'; if ($m.Groups[2].Success) { $z = $m.Groups[2].Value }; return ($m.Groups[1].Value + ' ' + $z) }
    $m = [regex]::Match($d.Trim(), '^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d)(?::(\d\d))?\s*(Z|[+-]\d\d:?\d\d)?$')
    if (-not $m.Success) { Die "invalid date format: $d" }
    $z = $m.Groups[7].Value; if (-not $z -or $z -eq 'Z') { if ($z -eq 'Z') { $z = '+0000' } else { $z = (Get-Date -Format 'zzz') } }
    $z = $z.Replace(':', '')
    $sec = 0; if ($m.Groups[6].Success) { $sec = [int]$m.Groups[6].Value }
    $dt = [datetime]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, $sec)
    $off = ([int]$z.Substring(1, 2) * 60 + [int]$z.Substring(3, 2)) * 60; if ($z[0] -eq '-') { $off = -$off }
    $u = [long](($dt.Ticks - $script:EPOCH - ($dt.Ticks - $script:EPOCH) % 10000000) / 10000000) - $off
    return "$u $z"
}
function Ident([string]$who) {                         # 'AUTHOR' or 'COMMITTER' -> 'Name <email> time tz'
    $n = (Get-Item -LiteralPath ("env:GIT_" + $who + "_NAME") -ErrorAction SilentlyContinue).Value
    $e = (Get-Item -LiteralPath ("env:GIT_" + $who + "_EMAIL") -ErrorAction SilentlyContinue).Value
    $d = (Get-Item -LiteralPath ("env:GIT_" + $who + "_DATE") -ErrorAction SilentlyContinue).Value
    if (-not $n) { $n = GetConfig 'user.name' }
    if (-not $e) { $e = GetConfig 'user.email' }
    if (-not $n -or -not $e) {
        Die ("Author identity unknown`n`n*** Please tell me who you are.`n`nRun`n`n  pgit config --global user.email ""you@example.com""`n  pgit config --global user.name ""Your Name""`n")
    }
    return "$n <$e> " + (ParseDateEnv $d)
}
$script:DOW = @('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat')
$script:MON = @('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
function GitDate([long]$u, [string]$tz) {
    $off = ([int]$tz.Substring(1, 2) * 60 + [int]$tz.Substring(3, 2)) * 60; if ($tz[0] -eq '-') { $off = -$off }
    $dt = [datetime]::new(1970, 1, 1).AddSeconds($u + $off)
    return ('{0} {1} {2} {3} {4} {5}' -f $script:DOW[[int]$dt.DayOfWeek], $script:MON[$dt.Month - 1], $dt.Day, $dt.ToString('HH:mm:ss'), $dt.Year, $tz)
}
function CleanMessage([string]$m) {
    $lines = @(); foreach ($l in ($m -replace "`r", '' -split "`n")) { $lines += $l.TrimEnd() }
    $out = @(); $blank = $false
    foreach ($l in $lines) { if ($l -eq '') { if ($out.Count) { $blank = $true } } else { if ($blank) { $out += '' }; $blank = $false; $out += $l } }
    if (-not $out.Count) { return '' }
    return (($out -join "`n") + "`n")
}

# ---------------------------------------------------------------- diff (a port of git's xdiff: Myers, compaction, indent heuristic)
function SplitRecs([string]$t) { if ($t -eq '') { return , ([string[]]@()) }; $ms = [regex]::Matches($t, '[^\n]*\n|[^\n]+$'); $r = [string[]]::new($ms.Count); for ($i = 0; $i -lt $ms.Count; $i++) { $r[$i] = $ms[$i].Value }; return , $r }
function XGetIndent([string]$s) {
    $ret = 0
    foreach ($c in $s.ToCharArray()) {
        if ($c -eq ' ') { $ret++ } elseif ($c -eq "`t") { $ret += 8 - ($ret % 8) }
        elseif ($c -eq "`n" -or $c -eq "`r" -or $c -eq "`v" -or $c -eq "`f") { }
        else { return $ret }
        if ($ret -ge 200) { return 200 }
    }
    return -1
}
function XScoreSplit($recs, [int]$n, [int]$split, $sc) {
    if ($split -ge $n) { $eof = 1; $ind = -1 } else { $eof = 0; $ind = XGetIndent $recs[$split] }
    $preb = 0; $prei = -1
    for ($i = $split - 1; $i -ge 0; $i--) { $prei = XGetIndent $recs[$i]; if ($prei -ne -1) { break }; $preb++; if ($preb -eq 20) { $prei = 0; break } }
    $postb = 0; $posti = -1
    for ($i = $split + 1; $i -lt $n; $i++) { $posti = XGetIndent $recs[$i]; if ($posti -ne -1) { break }; $postb++; if ($postb -eq 20) { $posti = 0; break } }
    if ($prei -eq -1 -and $preb -eq 0) { $sc[1] += 1 }
    if ($eof) { $sc[1] += 21 }
    $pb = 0; if ($ind -eq -1) { $pb = 1 + $postb }
    $tb = $preb + $pb
    $sc[1] += -30 * $tb; $sc[1] += 6 * $pb
    if ($ind -ne -1) { $indent = $ind } else { $indent = $posti }
    $any = ($tb -ne 0)
    $sc[0] += $indent
    if ($indent -eq -1) { } elseif ($prei -eq -1) { }
    elseif ($indent -gt $prei) { if ($any) { $sc[1] += 10 } else { $sc[1] += -4 } }
    elseif ($indent -eq $prei) { }
    else {
        if ($posti -ne -1 -and $posti -gt $indent) { if ($any) { $sc[1] += 17 } else { $sc[1] += 24 } }
        else { if ($any) { $sc[1] += 17 } else { $sc[1] += 23 } }
    }
}
function XCompact($ha, $chg, [int]$n, $hao, $chgo, [int]$no, $recs) {
    # rc / rco: change flags with a sentinel at index 0 (record i is at i + 1)
    $gs = 0; $ge = 0; while ($chg[$ge + 1]) { $ge++ }
    $os = 0; $oe = 0; while ($chgo[$oe + 1]) { $oe++ }
    while ($true) {
        if ($ge -ne $gs) {
            do {
                $size = $ge - $gs
                $endMatch = -1
                while ($gs -gt 0 -and $ha[$gs - 1] -eq $ha[$ge - 1]) {
                    $gs--; $chg[$gs + 1] = 1; $ge--; $chg[$ge + 1] = 0
                    while ($chg[$gs]) { $gs-- }
                    if ($os -eq 0) { throw 'xdiff: group sync broken sliding up' }
                    $oe = $os - 1; $os = $oe; while ($chgo[$os]) { $os-- }
                }
                $earliest = $ge
                if ($oe -gt $os) { $endMatch = $ge }
                while ($true) {
                    if ($ge -lt $n -and $ha[$gs] -eq $ha[$ge]) {
                        $chg[$gs + 1] = 0; $gs++; $chg[$ge + 1] = 1; $ge++
                        while ($chg[$ge + 1]) { $ge++ }
                    } else { break }
                    if ($oe -eq $no) { throw 'xdiff: group sync broken sliding down' }
                    $os = $oe + 1; $oe = $os; while ($chgo[$oe + 1]) { $oe++ }
                    if ($oe -gt $os) { $endMatch = $ge }
                }
            } while ($size -ne $ge - $gs)
            if ($ge -eq $earliest) { }
            elseif ($endMatch -ne -1) {
                while ($oe -eq $os) {
                    if (-not ($gs -gt 0 -and $ha[$gs - 1] -eq $ha[$ge - 1])) { throw 'xdiff: match disappeared' }
                    $gs--; $chg[$gs + 1] = 1; $ge--; $chg[$ge + 1] = 0; while ($chg[$gs]) { $gs-- }
                    $oe = $os - 1; $os = $oe; while ($chgo[$os]) { $os-- }
                }
            } elseif ($script:XINDENT) {                    # git diff's indent heuristic (merges diff without it: xdl_opts 0)
                $shift = $earliest
                if ($ge - $size - 1 -gt $shift) { $shift = $ge - $size - 1 }
                if ($ge - 100 -gt $shift) { $shift = $ge - 100 }
                $best = -1; $bi = 0; $bp = 0
                for (; $shift -le $ge; $shift++) {
                    $sc = [int[]]@(0, 0)
                    XScoreSplit $recs $n $shift $sc
                    XScoreSplit $recs $n ($shift - $size) $sc
                    if ($best -eq -1) { $cmp = -1 }
                    else { $ci = 0; if ($sc[0] -gt $bi) { $ci = 1 } elseif ($sc[0] -lt $bi) { $ci = -1 }; $cmp = 60 * $ci + ($sc[1] - $bp) }
                    if ($cmp -le 0) { $bi = $sc[0]; $bp = $sc[1]; $best = $shift }
                }
                while ($ge -gt $best) {
                    $gs--; $chg[$gs + 1] = 1; $ge--; $chg[$ge + 1] = 0; while ($chg[$gs]) { $gs-- }
                    $oe = $os - 1; $os = $oe; while ($chgo[$os]) { $os-- }
                }
            }
        }
        if ($ge -eq $n) { break }
        $gs = $ge + 1; $ge = $gs; while ($chg[$ge + 1]) { $ge++ }
        if ($oe -eq $no) { throw 'xdiff: group sync broken moving to next group' }
        $os = $oe + 1; $oe = $os; while ($chgo[$oe + 1]) { $oe++ }
    }
}
function XDiff([string[]]$recA, [string[]]$recB) {
    $n1 = $recA.Count; $n2 = $recB.Count
    $cls = (NewMap); $cnt1 = (NewMap); $cnt2 = (NewMap)
    $ha1 = [int[]]::new($n1); $ha2 = [int[]]::new($n2)
    for ($i = 0; $i -lt $n1; $i++) { $k = $recA[$i]; if (-not $cls.ContainsKey($k)) { $cls[$k] = $cls.Count }; $c = $cls[$k]; $ha1[$i] = $c; $cnt1[$c] = 1 + [int]$cnt1[$c] }
    for ($i = 0; $i -lt $n2; $i++) { $k = $recB[$i]; if (-not $cls.ContainsKey($k)) { $cls[$k] = $cls.Count }; $c = $cls[$k]; $ha2[$i] = $c; $cnt2[$c] = 1 + [int]$cnt2[$c] }
    $rc1 = [int[]]::new($n1 + 2); $rc2 = [int[]]::new($n2 + 2)
    # trim ends
    $lim = $n1; if ($n2 -lt $lim) { $lim = $n2 }
    $i = 0; while ($i -lt $lim -and $ha1[$i] -eq $ha2[$i]) { $i++ }
    $ds = $i
    $lim -= $i; $i = 0; while ($i -lt $lim -and $ha1[$n1 - 1 - $i] -eq $ha2[$n2 - 1 - $i]) { $i++ }
    $de1 = $n1 - $i - 1; $de2 = $n2 - $i - 1
    # discard records that do not match (xdl_cleanup_records)
    $dis1 = [int[]]::new($n1 + 1); $dis2 = [int[]]::new($n2 + 1)
    $ml = 1; $t = $n1; while ($t -gt 0) { $ml = $ml * 2; $t = $t -shr 2 }; if ($ml -gt 1024) { $ml = 1024 }
    for ($i = $ds; $i -le $de1; $i++) { $nm = [int]$cnt2[$ha1[$i]]; if ($nm -eq 0) { $dis1[$i] = 0 } elseif ($nm -ge $ml) { $dis1[$i] = 2 } else { $dis1[$i] = 1 } }
    $ml = 1; $t = $n2; while ($t -gt 0) { $ml = $ml * 2; $t = $t -shr 2 }; if ($ml -gt 1024) { $ml = 1024 }
    for ($i = $ds; $i -le $de2; $i++) { $nm = [int]$cnt1[$ha2[$i]]; if ($nm -eq 0) { $dis2[$i] = 0 } elseif ($nm -ge $ml) { $dis2[$i] = 2 } else { $dis2[$i] = 1 } }
    $r1 = [int[]]::new($n1 + 1); $h1 = [int[]]::new($n1 + 1); $m1 = 0
    for ($i = $ds; $i -le $de1; $i++) {
        if ($dis1[$i] -eq 1 -or ($dis1[$i] -eq 2 -and -not (XMMatch $dis1 $i $ds $de1))) { $r1[$m1] = $i; $h1[$m1] = $ha1[$i]; $m1++ } else { $rc1[$i + 1] = 1 }
    }
    $r2 = [int[]]::new($n2 + 1); $h2 = [int[]]::new($n2 + 1); $m2 = 0
    for ($i = $ds; $i -le $de2; $i++) {
        if ($dis2[$i] -eq 1 -or ($dis2[$i] -eq 2 -and -not (XMMatch $dis2 $i $ds $de2))) { $r2[$m2] = $i; $h2[$m2] = $ha2[$i]; $m2++ } else { $rc2[$i + 1] = 1 }
    }
    # Myers, divide and conquer on the kept records (xdl_recs_cmp / xdl_split, minimal)
    $koff = $m2 + 1; $kn = $m1 + $m2 + 3
    $kf = [long[]]::new($kn + 1); $kb = [long[]]::new($kn + 1)
    $LMAX = [long]9223372036854775807
    $st = @{}; $sp = 0
    $st[$sp] = [int[]]@(0, $m1, 0, $m2); $sp++
    while ($sp -gt 0) {
        $sp--; $top = $st[$sp]
        $o1 = $top[0]; $l1 = $top[1]; $o2 = $top[2]; $l2 = $top[3]
        while ($o1 -lt $l1 -and $o2 -lt $l2 -and $h1[$o1] -eq $h2[$o2]) { $o1++; $o2++ }
        while ($o1 -lt $l1 -and $o2 -lt $l2 -and $h1[$l1 - 1] -eq $h2[$l2 - 1]) { $l1--; $l2-- }
        if ($o1 -eq $l1) { for (; $o2 -lt $l2; $o2++) { $rc2[$r2[$o2] + 1] = 1 }; continue }
        if ($o2 -eq $l2) { for (; $o1 -lt $l1; $o1++) { $rc1[$r1[$o1] + 1] = 1 }; continue }
        $dmin = $o1 - $l2; $dmax = $l1 - $o2; $fmid = $o1 - $o2; $bmid = $l1 - $l2
        $odd = ($fmid - $bmid) -band 1
        $fmin = $fmid; $fmax = $fmid; $bmin = $bmid; $bmax = $bmid
        $kf[$fmid + $koff] = $o1; $kb[$bmid + $koff] = $l1
        $s1 = -1; $s2 = -1
        while ($true) {
            if ($fmin -gt $dmin) { $fmin--; $kf[$fmin - 1 + $koff] = -1 } else { $fmin++ }
            if ($fmax -lt $dmax) { $fmax++; $kf[$fmax + 1 + $koff] = -1 } else { $fmax-- }
            for ($d = $fmax; $d -ge $fmin; $d -= 2) {
                if ($kf[$d - 1 + $koff] -ge $kf[$d + 1 + $koff]) { $i1 = $kf[$d - 1 + $koff] + 1 } else { $i1 = $kf[$d + 1 + $koff] }
                $i2 = $i1 - $d
                while ($i1 -lt $l1 -and $i2 -lt $l2 -and $h1[$i1] -eq $h2[$i2]) { $i1++; $i2++ }
                $kf[$d + $koff] = $i1
                if ($odd -and $bmin -le $d -and $d -le $bmax -and $kb[$d + $koff] -le $i1) { $s1 = $i1; $s2 = $i2; break }
            }
            if ($s1 -ge 0) { break }
            if ($bmin -gt $dmin) { $bmin--; $kb[$bmin - 1 + $koff] = $LMAX } else { $bmin++ }
            if ($bmax -lt $dmax) { $bmax++; $kb[$bmax + 1 + $koff] = $LMAX } else { $bmax-- }
            for ($d = $bmax; $d -ge $bmin; $d -= 2) {
                if ($kb[$d - 1 + $koff] -lt $kb[$d + 1 + $koff]) { $i1 = $kb[$d - 1 + $koff] } else { $i1 = $kb[$d + 1 + $koff] - 1 }
                $i2 = $i1 - $d
                while ($i1 -gt $o1 -and $i2 -gt $o2 -and $h1[$i1 - 1] -eq $h2[$i2 - 1]) { $i1--; $i2-- }
                $kb[$d + $koff] = $i1
                if (-not $odd -and $fmin -le $d -and $d -le $fmax -and $i1 -le $kf[$d + $koff]) { $s1 = $i1; $s2 = $i2; break }
            }
            if ($s1 -ge 0) { break }
        }
        $st[$sp] = [int[]]@($s1, $l1, $s2, $l2); $sp++
        $st[$sp] = [int[]]@($o1, $s1, $o2, $s2); $sp++
    }
    XCompact $ha1 $rc1 $n1 $ha2 $rc2 $n2 $recA
    XCompact $ha2 $rc2 $n2 $ha1 $rc1 $n1 $recB
    $ch = @()
    $i1 = $n1; $i2 = $n2
    while ($i1 -ge 0 -or $i2 -ge 0) {
        $a1 = 0; if ($i1 -ge 0) { $a1 = $rc1[$i1] }; $a2 = 0; if ($i2 -ge 0) { $a2 = $rc2[$i2] }
        if ($a1 -or $a2) {
            $e1 = $i1; while ($i1 -gt 0 -and $rc1[$i1]) { $i1-- }
            $e2 = $i2; while ($i2 -gt 0 -and $rc2[$i2]) { $i2-- }
            $ch = , @{ i1 = $i1; i2 = $i2; c1 = $e1 - $i1; c2 = $e2 - $i2 } + $ch
        }
        $i1--; $i2--
    }
    return , $ch
}
function XMMatch($dis, [int]$i, [int]$s, [int]$e) {
    if ($i - $s -gt 100) { $s = $i - 100 }
    if ($e - $i -gt 100) { $e = $i + 100 }
    $r = 1; $rd0 = 0; $rp0 = 1
    for (; ($i - $r) -ge $s; $r++) { if ($dis[$i - $r] -eq 0) { $rd0++ } elseif ($dis[$i - $r] -eq 2) { $rp0++ } else { break } }
    if ($rd0 -eq 0) { return $false }
    $r = 1; $rd1 = 0; $rp1 = 1
    for (; ($i + $r) -le $e; $r++) { if ($dis[$i + $r] -eq 0) { $rd1++ } elseif ($dis[$i + $r] -eq 2) { $rp1++ } else { break } }
    if ($rd1 -eq 0) { return $false }
    $rd1 += $rd0; $rp1 += $rp0
    return ($rp1 * 4 -lt ($rp1 + $rd1))
}
function FuncLine([string]$rec) {
    if ($rec.Length -eq 0) { return $null }
    $c = [int]$rec[0]
    if (-not (($c -ge 65 -and $c -le 90) -or ($c -ge 97 -and $c -le 122) -or $c -eq 95 -or $c -eq 36)) { return $null }
    $l = $rec; if ($l.Length -gt 80) { $l = $l.Substring(0, 80) }
    return ($l -replace '[ \t\n\r\v\f]+$', '')
}
function Unified([string[]]$recA, [string[]]$recB, $ch, [int]$ctx) {   # -> Latin-1 text of the hunks
    $n1 = $recA.Count; $n2 = $recB.Count
    $func = ''; $fprev = -1
    $k = 0
    while ($k -lt $ch.Count) {
        $first = $k; $last = $k
        while ($last + 1 -lt $ch.Count) { $nx = $ch[$last + 1]; $pv = $ch[$last]; if ($nx.i1 - ($pv.i1 + $pv.c1) -gt 2 * $ctx) { break }; $last++ }
        $x = $ch[$first]; $y = $ch[$last]
        $s1 = $x.i1 - $ctx; if ($s1 -lt 0) { $s1 = 0 }
        $s2 = $x.i2 - $ctx; if ($s2 -lt 0) { $s2 = 0 }
        $lc = $ctx
        if ($n1 - ($y.i1 + $y.c1) -lt $lc) { $lc = $n1 - ($y.i1 + $y.c1) }
        if ($n2 - ($y.i2 + $y.c2) -lt $lc) { $lc = $n2 - ($y.i2 + $y.c2) }
        $e1 = $y.i1 + $y.c1 + $lc; $e2 = $y.i2 + $y.c2 + $lc
        for ($l = $s1 - 1; $l -ne $fprev -and $l -ge 0 -and $l -lt $n1; $l--) { $f = FuncLine $recA[$l]; if ($null -ne $f) { $func = $f; break } }
        $fprev = $s1 - 1
        $c1 = $e1 - $s1; $c2 = $e2 - $s2
        $h = '@@ -'; if ($c1 -eq 0) { $h += [string]$s1 } else { $h += [string]($s1 + 1) }; if ($c1 -ne 1) { $h += ',' + $c1 }
        $h += ' +'; if ($c2 -eq 0) { $h += [string]$s2 } else { $h += [string]($s2 + 1) }; if ($c2 -ne 1) { $h += ',' + $c2 }
        $h += ' @@'; if ($func) { $h += ' ' + $func }
        ($h + "`n")
        for (; $s2 -lt $x.i2; $s2++) { (Rec ' ' $recB[$s2]) }
        $s1 = $x.i1; $s2 = $x.i2
        for ($j = $first; $j -le $last; $j++) {
            $c = $ch[$j]
            for (; $s1 -lt $c.i1 -and $s2 -lt $c.i2; $s1++, $s2++) { (Rec ' ' $recB[$s2]) }
            for ($s1 = $c.i1; $s1 -lt $c.i1 + $c.c1; $s1++) { (Rec '-' $recA[$s1]) }
            for ($s2 = $c.i2; $s2 -lt $c.i2 + $c.c2; $s2++) { (Rec '+' $recB[$s2]) }
            $s1 = $c.i1 + $c.c1; $s2 = $c.i2 + $c.c2
        }
        for ($s2 = $y.i2 + $y.c2; $s2 -lt $e2; $s2++) { (Rec ' ' $recB[$s2]) }
        $k = $last + 1
    }
}
function Rec([string]$p, [string]$r) { if ($r.EndsWith("`n")) { return ($p + $r) }; return ($p + $r + "`n\ No newline at end of file`n") }

# ---------------------------------------------------------------- file pairs and patches
# side: @{ path; mode (int, 0 = absent); id; file (worktree full path, or $null) }
function SideBytes($s) { if ($s.file) { return , (Zl-ReadBytes $s.file) }; if ($s.mode -eq 0) { return , ([byte[]]::new(0)) }; return , (ReadBlob $s.id) }
function SideId($s) { if ($s.mode -eq 0) { return $script:ZERO }; if (-not $s.id) { $s.id = (HashObject 'blob' (SideBytes $s)).id }; return $s.id }
function PairPatch($pr, [int]$ctx, $stat) {
    $a = $pr.a; $b = $pr.b
    $ap = $a.path; if ($a.mode -eq 0) { $ap = $b.path }
    $bp = $b.path; if ($b.mode -eq 0) { $bp = $a.path }
    $qa = QuotePath ('a/' + $ap); $qb = QuotePath ('b/' + $bp)
    $o = "diff --git $qa $qb`n"
    $aid = SideId $a; $bid = SideId $b
    if ($a.mode -eq 0) { $o += 'new file mode ' + (ModeStr $b.mode) + "`n" }
    elseif ($b.mode -eq 0) { $o += 'deleted file mode ' + (ModeStr $a.mode) + "`n" }
    else {
        if ($a.mode -ne $b.mode) { $o += 'old mode ' + (ModeStr $a.mode) + "`nnew mode " + (ModeStr $b.mode) + "`n" }
        if ($pr.st -eq 'R') { $o += "similarity index $($pr.score)%`nrename from " + (QuotePath $a.path) + "`nrename to " + (QuotePath $b.path) + "`n" }
    }
    if ($aid -eq $bid) { return $o }
    $idx = 'index ' + (Abbrev $aid) + '..' + (Abbrev $bid)
    if ($a.mode -ne 0 -and $b.mode -ne 0 -and $a.mode -eq $b.mode) { $idx += ' ' + (ModeStr $a.mode) }
    $o += $idx + "`n"
    $ab = SideBytes $a; $bb = SideBytes $b
    $la = '--- ' + $qa; if ($qa.Contains(' ')) { $la += "`t" }; if ($a.mode -eq 0) { $la = '--- /dev/null' }
    $lb = '+++ ' + $qb; if ($qb.Contains(' ')) { $lb += "`t" }; if ($b.mode -eq 0) { $lb = '+++ /dev/null' }
    if ((IsBinary $ab) -or (IsBinary $bb)) {
        $x = $qa; if ($a.mode -eq 0) { $x = '/dev/null' }; $y = $qb; if ($b.mode -eq 0) { $y = '/dev/null' }
        return ($o + "Binary files $x and $y differ`n")
    }
    $recA = SplitRecs (Latin1 $ab); $recB = SplitRecs (Latin1 $bb)
    $ch = XDiff $recA $recB
    if ($ch.Count -eq 0) { return $o }
    return ($o + "$la`n$lb`n" + (-join @(Unified $recA $recB $ch $ctx)))
}
function PairStat($pr) { $a = $pr.a; $b = $pr.b; if ((SideId $a) -eq (SideId $b)) { return @(0, 0) }; $ab = SideBytes $a; $bb = SideBytes $b; if ((IsBinary $ab) -or (IsBinary $bb)) { return @(0, 0) }; $ch = XDiff (SplitRecs (Latin1 $ab)) (SplitRecs (Latin1 $bb)); $i = 0; $d = 0; foreach ($c in $ch) { $i += $c.c2; $d += $c.c1 }; return @($i, $d) }

function DiffMaps($mapA, $mapB, $specs, [bool]$renames, $wtFiles) {   # maps path -> @{mode; id[; file]} -> sorted pairs
    $pairs = @(); $adds = @(); $dels = @()
    $all = (NewMap); foreach ($k in $mapA.Keys) { $all[$k] = 1 }; foreach ($k in $mapB.Keys) { $all[$k] = 1 }
    foreach ($p in $all.Keys) {
        if (-not (SpecMatch $p $specs)) { continue }
        $x = $mapA[$p]; $y = $mapB[$p]
        $sa = @{ path = $p; mode = 0; id = $null; file = $null }; if ($x) { $sa.mode = $x.mode; $sa.id = $x.id; $sa.file = $x.file }
        $sb = @{ path = $p; mode = 0; id = $null; file = $null }; if ($y) { $sb.mode = $y.mode; $sb.id = $y.id; $sb.file = $y.file }
        if ($x -and $y) {
            if ($x.id -and $y.id -and $x.id -eq $y.id -and $x.mode -eq $y.mode) { continue }
            if ($x.mode -eq $y.mode -and (SideId $sa) -eq (SideId $sb)) { continue }
            $pairs += @{ st = 'M'; a = $sa; b = $sb; key = $p }
        } elseif ($x) { $dels += @{ st = 'D'; a = $sa; b = $sb; key = $p } }
        else { $adds += @{ st = 'A'; a = $sa; b = $sb; key = $p } }
    }
    if ($renames -and $adds.Count -and $dels.Count) {
        $byId = (NewMap)
        foreach ($d in $dels) { $id = SideId $d.a; if (-not $byId.ContainsKey($id)) { $byId[$id] = @() }; $byId[$id] += $d }
        $used = (NewMap); $keepAdds = @()
        foreach ($ad in ($adds | Sort-Object { ByteKey $_.key })) {
            $id = SideId $ad.b; $cand = $null
            if ($byId.ContainsKey($id)) {
                $bn = $ad.b.path.Substring($ad.b.path.LastIndexOf('/') + 1)
                foreach ($d in $byId[$id]) { if ($used.ContainsKey($d.key)) { continue }; if ($null -eq $cand) { $cand = $d }; if ($d.a.path.Substring($d.a.path.LastIndexOf('/') + 1) -ceq $bn) { $cand = $d; break } }
            }
            if ($cand) { $used[$cand.key] = 1; $pairs += @{ st = 'R'; a = $cand.a; b = $ad.b; key = $ad.key; score = 100 } } else { $keepAdds += $ad }
        }
        $adds = $keepAdds; $kd = @(); foreach ($d in $dels) { if (-not $used.ContainsKey($d.key)) { $kd += $d } }; $dels = $kd
        if ($adds.Count -and $dels.Count -and ($adds.Count * $dels.Count) -le 1000000) {
            # inexact renames, git's way: chunk hashes (diffcore-delta), score = copied bytes * 60000 / larger size, >= 50%
            $cand = @(); $sh = (NewMap); $sz = (NewMap)
            foreach ($ad in $adds) {
                if (($ad.b.mode -band 61440) -ne 32768) { continue }
                $bb = SideBytes $ad.b; $bs = $bb.Length
                foreach ($d in $dels) {
                    if (($d.a.mode -band 61440) -ne 32768) { continue }
                    if (-not $sz.ContainsKey($d.key)) { $sz[$d.key] = (SideBytes $d.a) }
                    $ab = $sz[$d.key]; $as = $ab.Length
                    $mx = $as; $mn = $bs; if ($bs -gt $as) { $mx = $bs; $mn = $as }
                    if ($mx * 30000 -lt ($mx - $mn) * 60000) { continue }
                    if (-not $bs) { continue }
                    if (-not $sh.ContainsKey('a:' + $d.key)) { $sh['a:' + $d.key] = (SpanHash $ab) }
                    if (-not $sh.ContainsKey('b:' + $ad.key)) { $sh['b:' + $ad.key] = (SpanHash $bb) }
                    $hs = $sh['a:' + $d.key]; $hd = $sh['b:' + $ad.key]; $sc = 0
                    foreach ($k in $hs.Keys) { if ($hd.ContainsKey($k)) { $x = $hs[$k]; $y = $hd[$k]; if ($x -lt $y) { $sc += $x } else { $sc += $y } } }
                    $score = [long](($sc * 60000 - (($sc * 60000) % $mx)) / $mx)
                    if ($score -lt 30000) { continue }
                    $ns = 0; if ($d.a.path.Substring($d.a.path.LastIndexOf('/') + 1) -ceq $ad.b.path.Substring($ad.b.path.LastIndexOf('/') + 1)) { $ns = 1 }
                    $cand += @{ score = $score; ns = $ns; add = $ad; del = $d }
                }
            }
            $cand = @($cand | Sort-Object -Property @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.ns }; Descending = $true })
            $usedA = (NewMap); $usedD = (NewMap)
            foreach ($c in $cand) {
                if ($usedA.ContainsKey($c.add.key) -or $usedD.ContainsKey($c.del.key)) { continue }
                $usedA[$c.add.key] = 1; $usedD[$c.del.key] = 1
                $pairs += @{ st = 'R'; a = $c.del.a; b = $c.add.b; key = $c.add.key; score = [int](($c.score * 100 - (($c.score * 100) % 60000)) / 60000) }
            }
            $ka = @(); foreach ($x in $adds) { if (-not $usedA.ContainsKey($x.key)) { $ka += $x } }; $adds = $ka
            $kd = @(); foreach ($x in $dels) { if (-not $usedD.ContainsKey($x.key)) { $kd += $x } }; $dels = $kd
        }
    }
    $pairs = $pairs + $adds + $dels
    $keys = (NewMap); foreach ($pp in $pairs) { $keys[(ByteKey $pp.key)] = $pp }
    $o = @(); foreach ($k in (SortOrd ([string[]]@($keys.Keys)))) { $o += $keys[$k] }
    return , $o
}
function SpanHash([byte[]]$b) {                       # git diffcore-delta: byte counts per chunk hash (chunks end at LF or 64 bytes)
    $h = @{}; $n = 0; [long]$a1 = 0; [long]$a2 = 0; $blen = $b.Length; $mask = [long]4294967295
    $txt = -not (IsBinary $b)
    for ($i = 0; $i -lt $blen; $i++) {
        $c = [long]$b[$i]
        if ($txt -and $c -eq 13 -and $i + 1 -lt $blen -and $b[$i + 1] -eq 10) { continue }
        $o1 = $a1
        $a1 = ((($a1 -shl 7) -band $mask) -bxor ($a2 -shr 25))
        $a2 = ((($a2 -shl 7) -band $mask) -bxor ($o1 -shr 25))
        $a1 = ($a1 + $c) -band $mask
        $n++
        if ($n -lt 64 -and $c -ne 10) { continue }
        $hv = [int]((($a1 + $a2 * 97) -band $mask) % 107927)
        $h[$hv] = [int]$h[$hv] + $n
        $n = 0; $a1 = 0; $a2 = 0
    }
    return $h
}
function IndexMap($ix) { $m = (NewMap); foreach ($k in $ix.entries.Keys) { $e = $ix.entries[$k]; $m[$k] = @{ mode = $e.mode; id = $e.id } }; return $m }
function WorkMap($ix, [bool]$refresh = $false) {     # tracked files as they are in the worktree: path -> @{mode; id; file}
    $m = (NewMap); $dirty = $false
    foreach ($k in @($ix.entries.Keys)) {
        $e = $ix.entries[$k]; $f = Full $k
        $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($null -eq $fi -or $fi.PSIsContainer) { continue }
        if (StatSame $e $fi $ix.mtime) { $m[$k] = @{ mode = $e.mode; id = $e.id; file = $f }; continue }
        $id = HashFile $f
        if ($id -eq $e.id -and $refresh) { $ix.entries[$k] = StatEntry $k $fi $id $e.mode; $dirty = $true }
        $m[$k] = @{ mode = $e.mode; id = $id; file = $f }
    }
    if ($dirty) { try { WriteIndex $ix.entries } catch { } }
    return $m
}

# ---------------------------------------------------------------- history walk
function WalkLog($starts, [int]$limit = -1) {          # commits newest first by committer date (git log's default order)
    $q = @(); $seen = (NewMap); $out = @()
    foreach ($s in $starts) { if (-not $seen.ContainsKey($s)) { $seen[$s] = 1; $q = InsertByDate $q (ParseCommit $s) } }
    while ($q.Count) {
        $c = $q[0]; if ($q.Count -eq 1) { $q = @() } else { $q = @($q[1..($q.Count - 1)]) }
        $out += $c
        if ($limit -ge 0 -and $out.Count -ge $limit) { break }
        foreach ($p in $c.parents) { if (-not $seen.ContainsKey($p)) { $seen[$p] = 1; $q = InsertByDate $q (ParseCommit $p) } }
    }
    return , $out
}
function InsertByDate($q, $c) {
    $t = $c.committer.time; $i = 0
    while ($i -lt $q.Count -and $q[$i].committer.time -ge $t) { $i++ }
    if ($i -eq 0) { return , (@(, $c) + $q) }
    if ($i -ge $q.Count) { return , ($q + @(, $c)) }
    return , ($q[0..($i - 1)] + @(, $c) + $q[$i..($q.Count - 1)])
}
function Decorations() {
    $d = (NewMap)
    $head = HeadCommit; $hr = HeadRef
    foreach ($kv in (ListRefs 'refs/heads/').GetEnumerator()) { $n = $kv.Key.Substring(11); if (-not $d.ContainsKey($kv.Value)) { $d[$kv.Value] = @() }; if ($hr -eq $kv.Key) { $d[$kv.Value] = @("HEAD -> $n") + $d[$kv.Value] } else { $d[$kv.Value] += $n } }
    foreach ($kv in (ListRefs 'refs/tags/').GetEnumerator()) { $id = PeelTo $kv.Value 'commit'; if (-not $d.ContainsKey($id)) { $d[$id] = @() }; $d[$id] += ('tag: ' + $kv.Key.Substring(10)) }
    if ($head -and -not $hr) { if (-not $d.ContainsKey($head)) { $d[$head] = @() }; $d[$head] = @('HEAD') + $d[$head] }
    return $d
}
function Subject([string]$msg) { $p = ($msg -split "`n`n")[0]; return (($p -split "`n" | Where-Object { $_ -ne '' }) -join ' ') }
function CommitHeader($c, $deco) {
    $o = 'commit ' + $c.id
    if ($deco -and $deco.ContainsKey($c.id)) { $o += ' (' + ($deco[$c.id] -join ', ') + ')' }
    $o += "`n"
    if ($c.parents.Count -gt 1) { $o += 'Merge: ' + (($c.parents | ForEach-Object { Abbrev $_ }) -join ' ') + "`n" }
    $o += 'Author: ' + $c.author.name + ' <' + $c.author.email + ">`n"
    $o += 'Date:   ' + (GitDate $c.author.time $c.author.tz) + "`n`n"
    $m = $c.message; if ($m.EndsWith("`n")) { $m = $m.Substring(0, $m.Length - 1) }
    foreach ($l in ($m -split "`n")) { $o += '    ' + $l + "`n" }
    return $o
}
function CommitPatch($c, [int]$ctx) {
    if ($c.parents.Count -gt 1) { return '' }
    $old = (NewMap); if ($c.parents.Count) { $old = CommitFiles $c.parents[0] }
    $new = FlattenTree $c.tree
    $o = ''
    foreach ($pr in (DiffMaps $old $new @() $true $null)) { $o += PairPatch $pr $ctx $null }
    return $o
}

# ---------------------------------------------------------------- library API (for other tools: . .\pgit.ps1 __lib)
function Convert-PgitCommit($c) {
    return @{ sha = $c.id; tree = $c.tree; parents = @($c.parents); author = ($c.author.name + ' <' + $c.author.email + '>'); author_name = $c.author.name; author_email = $c.author.email
              author_time = $c.author.time; author_tz = $c.author.tz; committer = ($c.committer.name + ' <' + $c.committer.email + '>'); committer_time = $c.committer.time
              committer_tz = $c.committer.tz; message = $c.message }
}
function Get-PgitCommit([string]$Repo, [string]$Sha) { Set-Repo $Repo; return (Convert-PgitCommit (ParseCommit (RevCommit $Sha))) }
function Get-PgitLog([string]$Repo, [string]$Ref = 'HEAD', [int]$Max = -1) {
    Set-Repo $Repo
    $starts = @(); foreach ($r in @($Ref)) { if ($r -eq '--all') { foreach ($v in (ListRefs 'refs/').Values) { try { $starts += (PeelTo $v 'commit') } catch { } }; $h = HeadCommit; if ($h) { $starts += $h } } else { $starts += (RevCommit $r) } }
    $o = @(); foreach ($c in (WalkLog $starts $Max)) { $o += (Convert-PgitCommit $c) }
    return , $o
}
function Resolve-PgitRef([string]$Repo, [string]$Name) { Set-Repo $Repo; return (Rev $Name) }
function Get-PgitTreeFiles([string]$Repo, [string]$TreeOrCommit) {
    Set-Repo $Repo
    $m = FlattenTree (PeelTo (Rev $TreeOrCommit) 'tree')
    $o = @(); foreach ($p in (SortPaths @($m.Keys))) { $o += @{ path = $p; mode = (ModeStr $m[$p].mode); sha = $m[$p].id } }
    return , $o
}
function Get-PgitBlob([string]$Repo, [string]$Sha) { Set-Repo $Repo; return , (ReadBlob (Rev $Sha)) }
function Get-PgitRefs([string]$Repo, [string]$RefPrefix = 'refs/') { Set-Repo $Repo; return (ListRefs $RefPrefix) }

# ---------------------------------------------------------------- three-way merge (a port of git's xdiff/xmerge.c: level ZEALOUS, style merge)
function XEolCrlf($recs, [int]$i) {                     # is_eol_crlf: 1 CRLF, 0 LF, -1 cannot tell
    $n = $recs.Count
    if ($i -lt $n - 1) { $r = $recs[$i]; return [int]($r.Length -gt 1 -and [int]$r[$r.Length - 2] -eq 13) }
    if ($n -eq 0) { return -1 }
    $r = $recs[$i]
    if ($r.Length -and [int]$r[$r.Length - 1] -eq 10) { return [int]($r.Length -gt 1 -and [int]$r[$r.Length - 2] -eq 13) }
    if ($i -eq 0) { return -1 }
    $r = $recs[$i - 1]; return [int]($r.Length -gt 1 -and [int]$r[$r.Length - 2] -eq 13)
}
function XNeedsCr($r0, $r1, $r2, $m) {
    $i = 0; if ($m.i1) { $i = $m.i1 - 1 }; $nc = XEolCrlf $r1 $i
    if ($nc) { $i = 0; if ($m.i2) { $i = $m.i2 - 1 }; $nc = XEolCrlf $r2 $i }
    if ($nc) { $nc = XEolCrlf $r0 0 }
    if ($nc -lt 0) { return 0 }; return $nc
}
function XCopy($recs, [int]$i, [int]$count, [int]$needsCr, [bool]$addNl) {   # xdl_recs_copy -> one string
    if ($count -lt 1) { return '' }
    $s = (Slice2 $recs $i $count) -join ''
    if ($addNl) { $l = $recs[$i + $count - 1]; if ($l.Length -eq 0 -or [int]$l[$l.Length - 1] -ne 10) { if ($needsCr) { $s += "`r" }; $s += "`n" } }
    return $s
}
function Slice2($a, [int]$off, [int]$len) { if ($len -le 0) { return , ([string[]]@()) }; $r = [string[]]::new($len); [Array]::Copy([string[]]$a, $off, $r, 0, $len); return , $r }
function XAppendMerge($ms, [int]$mode, [int]$i0, [int]$c0, [int]$i1, [int]$c1, [int]$i2, [int]$c2) {
    $n = $ms.l.Count
    if ($n) {
        $m = $ms.l[$n - 1]
        if ($i1 -le $m.i1 + $m.c1 -or $i2 -le $m.i2 + $m.c2) {
            if ($mode -ne $m.mode) { $m.mode = 0 }
            $m.c0 = $i0 + $c0 - $m.i0; $m.c1 = $i1 + $c1 - $m.i1; $m.c2 = $i2 + $c2 - $m.i2
            return
        }
    }
    $ms.l += , @{ mode = $mode; i0 = $i0; c0 = $c0; i1 = $i1; c1 = $c1; i2 = $i2; c2 = $c2 }
}
function XHasAlnum($recs, [int]$i, [int]$n) { for ($k = 0; $k -lt $n; $k++) { if ($recs[$i + $k] -cmatch '[A-Za-z0-9]') { return $true } }; return $false }
# XMerge base ours theirs (Latin-1 strings of the file bytes) -> @{ text; conflicts }
function XMerge([string]$t0, [string]$t1, [string]$t2, [string]$name1, [string]$name2, [int]$markerSize = 7) {
    $r0 = SplitRecs $t0; $r1 = SplitRecs $t1; $r2 = SplitRecs $t2
    $saveInd = $script:XINDENT; $script:XINDENT = $false
    try {
        $x1 = XDiff $r0 $r1; $x2 = XDiff $r0 $r2
        if (-not $x1.Count) { return @{ text = $t2; conflicts = 0 } }
        if (-not $x2.Count) { return @{ text = $t1; conflicts = 0 } }
        $ms = @{ l = @() }; $a = 0; $b = 0
        while ($a -lt $x1.Count -and $b -lt $x2.Count) {
            $s1 = $x1[$a]; $s2 = $x2[$b]
            if ($s1.i1 + $s1.c1 -lt $s2.i1) {
                XAppendMerge $ms 1 $s1.i1 $s1.c1 $s1.i2 $s1.c2 ($s2.i2 - $s2.i1 + $s1.i1) $s1.c1; $a++; continue
            }
            if ($s2.i1 + $s2.c1 -lt $s1.i1) {
                XAppendMerge $ms 2 $s2.i1 $s2.c1 ($s1.i2 - $s1.i1 + $s2.i1) $s2.c1 $s2.i2 $s2.c2; $b++; continue
            }
            $same = ($s1.i1 -eq $s2.i1 -and $s1.c1 -eq $s2.c1 -and $s1.c2 -eq $s2.c2)
            if ($same) { for ($k = 0; $k -lt $s1.c2; $k++) { if ($r1[$s1.i2 + $k] -cne $r2[$s2.i2 + $k]) { $same = $false; break } } }
            if (-not $same) {
                $off = $s1.i1 - $s2.i1; $ffo = $off + $s1.c1 - $s2.c1
                $i0 = $s1.i1; $i1 = $s1.i2; $i2 = $s2.i2
                if ($off -gt 0) { $i0 -= $off; $i1 -= $off } else { $i2 += $off }
                $c0 = $s1.i1 + $s1.c1 - $i0; $c1 = $s1.i2 + $s1.c2 - $i1; $c2 = $s2.i2 + $s2.c2 - $i2
                if ($ffo -lt 0) { $c0 -= $ffo; $c1 -= $ffo } else { $c2 += $ffo }
                XAppendMerge $ms 0 $i0 $c0 $i1 $c1 $i2 $c2
            }
            $e1 = $s1.i1 + $s1.c1; $e2 = $s2.i1 + $s2.c1
            if ($e1 -ge $e2) { $b++ }
            if ($e2 -ge $e1) { $a++ }
        }
        for (; $a -lt $x1.Count; $a++) { $s1 = $x1[$a]; XAppendMerge $ms 1 $s1.i1 $s1.c1 $s1.i2 $s1.c2 ($s1.i1 + $r2.Count - $r0.Count) $s1.c1 }
        for (; $b -lt $x2.Count; $b++) { $s2 = $x2[$b]; XAppendMerge $ms 2 $s2.i1 $s2.c1 ($s2.i1 + $r1.Count - $r0.Count) $s2.c1 $s2.i2 $s2.c2 }
        # xdl_refine_conflicts: diff the two sides of each conflict, keep only what differs
        $ref = @()
        foreach ($m in $ms.l) {
            if ($m.mode -ne 0 -or $m.c1 -eq 0 -or $m.c2 -eq 0) { $ref += , $m; continue }
            $xs = XDiff (Slice2 $r1 $m.i1 $m.c1) (Slice2 $r2 $m.i2 $m.c2)
            if (-not $xs.Count) { $m.mode = 4; $ref += , $m; continue }
            $b1 = $m.i1; $b2 = $m.i2
            foreach ($x in $xs) { $ref += , @{ mode = 0; i0 = $m.i0; c0 = $m.c0; i1 = $x.i1 + $b1; c1 = $x.c1; i2 = $x.i2 + $b2; c2 = $x.c2 } }
        }
        # xdl_simplify_non_conflicts: conflicts 3 or fewer lines apart become one
        $l = @(); foreach ($m in $ref) { $l += , $m }
        $k = 0
        while ($k + 1 -lt $l.Count) {
            $m = $l[$k]; $nx = $l[$k + 1]
            $begin = $m.i1 + $m.c1; $end = $nx.i1
            if ($m.mode -ne 0 -or $nx.mode -ne 0 -or ($end - $begin -gt 3)) { $k++; continue }
            $m.c1 = $nx.i1 + $nx.c1 - $m.i1; $m.c2 = $nx.i2 + $nx.c2 - $m.i2
            $nl = @(); for ($q = 0; $q -lt $l.Count; $q++) { if ($q -ne $k + 1) { $nl += , $l[$q] } }; $l = $nl
        }
        # xdl_fill_merge_buffer
        $out = ''; $i = 0; $nconf = 0
        foreach ($m in $l) {
            if ($m.mode -eq 0) {
                $nconf++
                $cr = XNeedsCr $r0 $r1 $r2 $m; $eol = "`n"; if ($cr) { $eol = "`r`n" }
                $out += XCopy $r1 $i ($m.i1 - $i) 0 $false
                $out += ('<' * $markerSize); if ($name1) { $out += ' ' + $name1 }; $out += $eol
                $out += XCopy $r1 $m.i1 $m.c1 $cr $true
                $out += ('=' * $markerSize) + $eol
                $out += XCopy $r2 $m.i2 $m.c2 $cr $true
                $out += ('>' * $markerSize); if ($name2) { $out += ' ' + $name2 }; $out += $eol
            } elseif ($m.mode -band 3) {
                $out += XCopy $r1 $i ($m.i1 - $i) 0 $false
                if ($m.mode -band 1) { $cr = XNeedsCr $r0 $r1 $r2 $m; $out += XCopy $r1 $m.i1 $m.c1 $cr (($m.mode -band 2) -ne 0) }
                if ($m.mode -band 2) { $out += XCopy $r2 $m.i2 $m.c2 0 $false }
            } else { continue }
            $i = $m.i1 + $m.c1
        }
        $out += XCopy $r1 $i ($r1.Count - $i) 0 $false
        return @{ text = $out; conflicts = $nconf }
    } finally { $script:XINDENT = $saveInd }
}

# ---------------------------------------------------------------- merge state and merge bases
function MergeHead() { $t = ReadText (GitPath 'MERGE_HEAD'); if (-not $t) { return $null }; return (($t -split "`n")[0]).Trim() }
function ClearMergeState() { foreach ($f in 'MERGE_HEAD', 'MERGE_MSG', 'MERGE_MODE', 'AUTO_MERGE') { $p = GitPath $f; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } }
function Ancestors([string]$id) {                     # every commit reachable from $id (itself included)
    $seen = (NewMap); $st = @($id)
    while ($st.Count) { $c = $st[$st.Count - 1]; if ($st.Count -eq 1) { $st = @() } else { $st = $st[0..($st.Count - 2)] }; if ($seen.ContainsKey($c)) { continue }; $seen[$c] = 1; foreach ($p in (ParseCommit $c).parents) { if (-not $seen.ContainsKey($p)) { $st += $p } } }
    return $seen
}
function MergeBases([string]$a, [string]$b) {         # the best common ancestors: common commits that are no common commit's parent
    $aa = Ancestors $a; $bb = Ancestors $b
    $common = (NewMap); foreach ($k in $aa.Keys) { if ($bb.ContainsKey($k)) { $common[$k] = 1 } }
    $par = (NewMap); foreach ($k in $common.Keys) { foreach ($p in (ParseCommit $k).parents) { $par[$p] = 1 } }
    $best = @(); foreach ($k in $common.Keys) { if (-not $par.ContainsKey($k)) { $best += $k } }
    return , $best
}

# ---------------------------------------------------------------- pack files (read: .idx v2 + .pack, deltas) and git bundles
$script:PACKIDX = (NewMap); $script:PACKOBJ = (NewMap); $script:PACKOBJN = 0
function PackList([string]$gd) {                       # the packs of a git directory, their indexes read once
    if ($script:PACKIDX.ContainsKey($gd)) { return , $script:PACKIDX[$gd] }
    $l = @()
    foreach ($f in @(Get-ChildItem -LiteralPath ($gd + '\objects\pack') -Filter '*.idx' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $b = Zl-ReadBytes $f.FullName
        if ($b.Length -lt 1072 -or $b[0] -ne 255 -or $b[1] -ne 116 -or $b[2] -ne 79 -or $b[3] -ne 99 -or (BE32 $b 4) -ne 2) { Die "pack index $($f.Name) is not version 2: on a machine with git, git index-pack --index-version=2 it" }
        $l += , @{ idx = $b; n = [int](BE32 $b 1028); pack = ($f.FullName.Substring(0, $f.FullName.Length - 4) + '.pack'); data = $null }
    }
    $script:PACKIDX[$gd] = $l
    return , $l
}
function IdxFind($pk, [string]$id) {                   # binary search in an .idx v2 -> pack offset, or -1
    $b = $pk.idx; $first = $script:HEXV[[string]$id[0]] * 16 + $script:HEXV[[string]$id[1]]
    $lo = 0; if ($first -gt 0) { $lo = [int](BE32 $b (8 + 4 * ($first - 1))) }; $hi = [int](BE32 $b (8 + 4 * $first)) - 1
    while ($lo -le $hi) {
        $mid = [int](($lo + $hi) / 2); if ($mid -gt $hi) { $mid = $hi }
        $c = [string]::CompareOrdinal((Hex $b (1032 + 20 * $mid) 20), $id)
        if ($c -eq 0) {
            $o = BE32 $b (1032 + 24 * $pk.n + 4 * $mid)
            if ($o -band 2147483648) { $k = $o -band 2147483647; $q = 1032 + 28 * $pk.n + 8 * $k; $o = ((BE32 $b $q) -shl 32) -bor (BE32 $b ($q + 4)) }
            return [long]$o
        }
        if ($c -lt 0) { $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    return -1
}
function IdxPrefix($pk, [string]$pre) {                # every id in an .idx that starts with $pre (4+ hex digits)
    $b = $pk.idx; $first = $script:HEXV[[string]$pre[0]] * 16 + $script:HEXV[[string]$pre[1]]
    $lo = 0; if ($first -gt 0) { $lo = [int](BE32 $b (8 + 4 * ($first - 1))) }; $hi = [int](BE32 $b (8 + 4 * $first)) - 1
    $o = @(); for ($k = $lo; $k -le $hi; $k++) { $h = Hex $b (1032 + 20 * $k) 20; if ($h.StartsWith($pre)) { $o += $h } }
    return , $o
}
function PackHas([string]$gd, [string]$id) { foreach ($pk in (PackList $gd)) { if ((IdxFind $pk $id) -ge 0) { return $true } }; return $false }
function PackFind([string]$gd, [string]$id) {          # -> @{ type; body } or $null
    foreach ($pk in (PackList $gd)) { $off = IdxFind $pk $id; if ($off -ge 0) { return (PackEntry $gd $pk $off) } }
    return $null
}
$script:PACKTYPES = @('', 'commit', 'tree', 'blob', 'tag')
function PackEntry([string]$gd, $pk, [long]$off) {     # one pack entry at $off, deltas applied
    $key = $pk.pack + '@' + $off
    if ($script:PACKOBJ.ContainsKey($key)) { return $script:PACKOBJ[$key] }
    if ($null -eq $pk.data) { $pk.data = Zl-ReadBytes $pk.pack }
    $d = $pk.data; $p = [int]$off
    $c = [int]$d[$p]; $type = ($c -shr 4) -band 7; $p++
    while ($c -band 128) { $c = [int]$d[$p]; $p++ }
    $r = $null
    if ($type -ge 1 -and $type -le 4) { $r = @{ type = $script:PACKTYPES[$type]; body = (Zl-Inflate $d ($p + 2)) } }
    elseif ($type -eq 6) {
        $c = [int]$d[$p]; $p++; [long]$ofs = $c -band 127
        while ($c -band 128) { $c = [int]$d[$p]; $p++; $ofs = (($ofs + 1) -shl 7) -bor ($c -band 127) }
        $base = PackEntry $gd $pk ($off - $ofs)
        $r = @{ type = $base.type; body = (DeltaApply $base.body (Zl-Inflate $d ($p + 2))) }
    }
    elseif ($type -eq 7) {
        $bid = Hex $d $p 20; $p += 20
        $base = GdObject $gd $bid; if ($null -eq $base) { Die "pack: delta base $bid is missing" }
        $r = @{ type = $base.type; body = (DeltaApply $base.body (Zl-Inflate $d ($p + 2))) }
    }
    else { Die "pack: unknown entry type $type at offset $off in $($pk.pack)" }
    if ($script:PACKOBJN -gt 2000) { $script:PACKOBJ = (NewMap); $script:PACKOBJN = 0 }
    $script:PACKOBJ[$key] = $r; $script:PACKOBJN++
    return $r
}
function DeltaApply([byte[]]$src, [byte[]]$delta) {    # git's delta format: sizes, then copy (from the base) and insert ops
    $p = 0; $s = 0; $sh = 0; do { $c = [int]$delta[$p]; $p++; $s = $s -bor (($c -band 127) -shl $sh); $sh += 7 } while ($c -band 128)
    $n = 0; $sh = 0; do { $c = [int]$delta[$p]; $p++; $n = $n -bor (($c -band 127) -shl $sh); $sh += 7 } while ($c -band 128)
    if ($s -ne $src.Length) { Die 'pack: a delta does not fit its base' }
    $out = [byte[]]::new($n); $o = 0
    while ($p -lt $delta.Length) {
        $op = [int]$delta[$p]; $p++
        if ($op -band 128) {
            [long]$co = 0; $cs = 0
            if ($op -band 1) { $co = $co -bor [long]$delta[$p]; $p++ }; if ($op -band 2) { $co = $co -bor ([long]$delta[$p] -shl 8); $p++ }
            if ($op -band 4) { $co = $co -bor ([long]$delta[$p] -shl 16); $p++ }; if ($op -band 8) { $co = $co -bor ([long]$delta[$p] -shl 24); $p++ }
            if ($op -band 16) { $cs = $cs -bor [int]$delta[$p]; $p++ }; if ($op -band 32) { $cs = $cs -bor ([int]$delta[$p] -shl 8); $p++ }
            if ($op -band 64) { $cs = $cs -bor ([int]$delta[$p] -shl 16); $p++ }
            if ($cs -eq 0) { $cs = 65536 }
            [Array]::Copy($src, [int]$co, $out, $o, $cs); $o += $cs
        } elseif ($op -gt 0) { [Array]::Copy($delta, $p, $out, $o, $op); $p += $op; $o += $op }
        else { Die 'pack: bad delta opcode 0' }
    }
    if ($o -ne $n) { Die 'pack: a delta made the wrong size' }
    return , $out
}
function GdObject([string]$gd, [string]$id) {          # an object of any git directory: loose, else packed -> @{ type; body } or $null
    $p = $gd + '\objects\' + $id.Substring(0, 2) + '\' + $id.Substring(2)
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        $raw = Zl-Unzlib (Zl-ReadBytes $p); $z = [Array]::IndexOf($raw, [byte]0); $hdr = Latin1 (Slice $raw 0 $z)
        return @{ type = $hdr.Substring(0, $hdr.IndexOf(' ')); body = (Slice $raw ($z + 1) ($raw.Length - $z - 1)) }
    }
    return (PackFind $gd $id)
}

# a git bundle: "# v2 git bundle", prerequisites (-id), refs (id name), a blank line, then a pack
function BundleRead([string]$file) {                   # -> @{ refs (name -> id, in order); prereq; packAt; bytes }
    $b = Zl-ReadBytes $file
    $hdrEnd = -1; for ($i = 0; $i + 1 -lt $b.Length -and $i -lt 4194304; $i++) { if ($b[$i] -eq 10 -and $b[$i + 1] -eq 10) { $hdrEnd = $i; break } }
    if ($hdrEnd -lt 0) { Die "$file is not a git bundle" }
    $lines = (Latin1 (Slice $b 0 $hdrEnd)) -split "`n"
    if ($lines[0] -cne '# v2 git bundle' -and $lines[0] -cne '# v3 git bundle') { Die "$file is not a git bundle (no '# v2 git bundle' line)" }
    $refs = (NewMap); $order = @(); $pre = @()
    foreach ($l in ($lines | Select-Object -Skip 1)) { if ($l -eq '' -or $l.StartsWith('@')) { continue }; if ($l.StartsWith('-')) { $pre += $l.Substring(1, 40); continue }; $refs[$l.Substring(41)] = $l.Substring(0, 40); $order += $l.Substring(41) }
    return @{ refs = $refs; order = $order; prereq = $pre; packAt = ($hdrEnd + 2); bytes = $b }
}
function UnpackPack([byte[]]$d, [int]$at, [string]$gd) {   # every object of a pack stream -> loose objects in $gd; returns the count
    if ((Latin1 (Slice $d $at 4)) -cne 'PACK') { Die 'not a pack (no PACK signature)' }
    $n = [int](BE32 $d ($at + 8)); $p = $at + 12
    $ents = @(); $byOff = @{}
    for ($k = 0; $k -lt $n; $k++) {
        $start = $p; $c = [int]$d[$p]; $type = ($c -shr 4) -band 7; $p++
        while ($c -band 128) { $c = [int]$d[$p]; $p++ }
        $e = @{ start = $start; type = $type; base = $null; bid = $null }
        if ($type -eq 6) { $c = [int]$d[$p]; $p++; [long]$ofs = $c -band 127; while ($c -band 128) { $c = [int]$d[$p]; $p++; $ofs = (($ofs + 1) -shl 7) -bor ($c -band 127) }; $e.base = $start - $ofs }
        elseif ($type -eq 7) { $e.bid = Hex $d $p 20; $p += 20 }
        $e.data = Zl-Inflate $d ($p + 2); $p = $script:ZL_END + 4
        $ents += , $e; $byOff[[string]$start] = $e
    }
    $done = @{}; $byId = @{}; $count = 0
    $resolve = {
        param($e)
        if ($e.obj) { return $e.obj }
        if ($e.type -ge 1 -and $e.type -le 4) { $e.obj = @{ type = $script:PACKTYPES[$e.type]; body = $e.data } }
        elseif ($e.type -eq 6) { $bo = & $resolve $byOff[[string]$e.base]; $e.obj = @{ type = $bo.type; body = (DeltaApply $bo.body $e.data) } }
        else { $bo = $null; if ($byId.ContainsKey($e.bid)) { $bo = $byId[$e.bid] } else { $bo = GdObject $gd $e.bid }; if ($null -eq $bo) { return $null }; $e.obj = @{ type = $bo.type; body = (DeltaApply $bo.body $e.data) } }
        return $e.obj
    }
    for ($round = 0; $round -lt 3; $round++) {          # REF_DELTA bases may come later in the pack
        foreach ($e in $ents) {
            if ($e.written) { continue }
            $o = & $resolve $e; if ($null -eq $o) { continue }
            $h = HashObject $o.type $o.body; $byId[$h.id] = $o
            $op = $gd + '\objects\' + $h.id.Substring(0, 2) + '\' + $h.id.Substring(2)
            if (-not (Test-Path -LiteralPath $op -PathType Leaf)) { EnsureDir (Split-Path $op -Parent); Zl-WriteBytes $op (Zl-Zlib $h.full); $count++ }
            $e.written = $true; $e.data = $null
        }
    }
    foreach ($e in $ents) { if (-not $e.written) { Die 'the pack refers to objects that are not here (a thin pack): fetch the commits it builds on first' } }
    return $count
}

# ================================================================ commands
function Opt([string[]]$names, [bool]$takesValue = $false) {   # removes an option from $script:OPTARGS; returns its value / $true / $null
    $a = @($script:OPTARGS); $out = @(); $val = $null; $i = 0
    while ($i -lt $a.Count) {
        $x = [string]$a[$i]
        if ($x -eq '--') { $out += $a[$i..($a.Count - 1)]; break }
        $hit = $false
        foreach ($n in $names) {
            if ($x -ceq $n) { $hit = $true; if ($takesValue) { if ($i + 1 -ge $a.Count) { Die "option '$n' requires a value" }; $val = [string]$a[$i + 1]; $i++ } else { $val = $true }; break }
            if ($takesValue -and $n.StartsWith('--') -and $x.StartsWith($n + '=')) { $hit = $true; $val = $x.Substring($n.Length + 1); break }
            if ($takesValue -and -not $n.StartsWith('--') -and $x.StartsWith($n) -and $x.Length -gt $n.Length) { $hit = $true; $val = $x.Substring($n.Length); break }
        }
        if (-not $hit) { $out += $x }
        $i++
    }
    $script:OPTARGS = $out
    return $val
}
function SplitDashes($a) { $before = @(); $after = @(); $seen = $false; foreach ($x in $a) { if (-not $seen -and $x -eq '--') { $seen = $true; continue }; if ($seen) { $after += $x } else { $before += $x } }; return @(, $before) + @(, $after) }

function Cmd-Init($a) {
    $script:OPTARGS = @($a)
    $b = Opt @('-b', '--initial-branch') $true
    $q = Opt @('-q', '--quiet')
    $bare = Opt @('--bare')
    $a = $script:OPTARGS
    $dir = (Get-Location).Path; if ($a.Count) { $dir = $a[0]; if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $dir = (Resolve-Path -LiteralPath $dir).Path }
    $g = $dir.TrimEnd('\') + '\.git'; if ($bare) { $g = $dir.TrimEnd('\') }
    $re = Test-Path -LiteralPath ($g + '\HEAD')
    foreach ($d in @('objects\info', 'objects\pack', 'refs\heads', 'refs\tags', 'info')) { EnsureDir ($g + '\' + $d) }
    if (-not $re) {
        if (-not $b) { $script:GITDIR = $null; $b = GetConfig 'init.defaultBranch'; if (-not $b) { $b = 'main' } }
        WriteText ($g + '\HEAD') "ref: refs/heads/$b`n"
        if ($bare) { WriteText ($g + '\config') "[core]`n`trepositoryformatversion = 0`n`tfilemode = false`n`tbare = true`n`tsymlinks = false`n`tignorecase = true`n" }
        else { WriteText ($g + '\config') "[core]`n`trepositoryformatversion = 0`n`tfilemode = false`n`tbare = false`n`tlogallrefupdates = true`n`tsymlinks = false`n`tignorecase = true`n" }
        WriteText ($g + '\description') "Unnamed repository; edit this file 'description' to name the repository.`n"
        WriteText ($g + '\info\exclude') "# git ls-files --others --exclude-from=.git/info/exclude`n# Lines that start with '#' are comments.`n"
    }
    if (-not $q) { $w = 'Git'; if ($re) { Out-Text "Reinitialized existing $w repository in $g\" } else { Out-Text "Initialized empty $w repository in $g\" } }
}

function Cmd-Add($a) {
    $script:OPTARGS = @($a)
    $all = Opt @('-A', '--all')
    $force = Opt @('-f', '--force')
    $upd = Opt @('-u', '--update')
    $a = $script:OPTARGS
    $a = (SplitDashes $a); $a = $a[0] + $a[1]
    if (-not $a.Count -and -not $all -and -not $upd) { Out-Err "Nothing specified, nothing added.`nMaybe you wanted to say 'pgit add .'?"; return }
    $specs = Specs $a; if ((-not $a.Count) -and ($all -or $upd)) { $specs = @('') }
    $ix = ReadIndex
    $wt = (NewMap)
    if ($force) { Walk '' @() $wt $true } else { $wt = Worktree }
    $matched = (NewMap)
    foreach ($s in $specs) { $matched[$s] = $false }
    $n = 0
    if (-not $upd) {
        foreach ($p in $wt.Keys) {
            if (-not (SpecMatch $p $specs)) { continue }
            foreach ($s in $specs) { if (SpecMatch $p @($s)) { $matched[$s] = $true } }
            $fi = $wt[$p]; $e = $ix.entries[$p]
            if ($e -and (StatSame $e $fi $ix.mtime)) { continue }
            $id = WriteObject 'blob' (Zl-ReadBytes $fi.FullName)
            $mode = 33188; if ($e) { $mode = $e.mode }
            $ix.entries[$p] = StatEntry $p $fi $id $mode; $n++
        }
    }
    foreach ($p in @($ix.entries.Keys)) {
        if (-not (SpecMatch $p $specs)) { continue }
        foreach ($s in $specs) { if (SpecMatch $p @($s)) { $matched[$s] = $true } }
        $f = Full $p
        $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($null -eq $fi) { $ix.entries.Remove($p); $n++; continue }
        if ($upd -or -not $wt.ContainsKey($p)) {
            $e = $ix.entries[$p]
            if (StatSame $e $fi $ix.mtime) { continue }
            $id = WriteObject 'blob' (Zl-ReadBytes $f)
            $ix.entries[$p] = StatEntry $p $fi $id $e.mode; $n++
        }
    }
    foreach ($p in @($ix.unmerged.Keys)) {
        if (-not (SpecMatch $p $specs) -or $wt.ContainsKey($p)) { continue }
        foreach ($s in $specs) { if (SpecMatch $p @($s)) { $matched[$s] = $true } }
        if (-not (Test-Path -LiteralPath (Full $p) -PathType Leaf)) { $ix.unmerged.Remove($p) }
    }
    foreach ($s in $specs) {
        if ($matched[$s]) { continue }
        $f = Full $s
        if ($s -and (Test-Path -LiteralPath $f)) { Die ("The following paths are ignored by one of your .gitignore files:`n$s`nUse -f if you really want to add them.") 1 }
        if ($s -and -not $upd) { Die "pathspec '$s' did not match any files" }
    }
    WriteIndex $ix.entries
}

function Cmd-Rm($a) {
    $script:OPTARGS = @($a)
    $cached = Opt @('--cached')
    $rec = Opt @('-r')
    $force = Opt @('-f', '--force')
    $quiet = Opt @('-q', '--quiet')
    $a = $script:OPTARGS
    $a = (SplitDashes $a); $a = $a[0] + $a[1]
    if (-not $a.Count) { Die 'No pathspec was given. Which files should I remove?' }
    $specs = Specs $a
    $ix = ReadIndex
    $hit = @()
    foreach ($s in $specs) {
        $m = @(@($ix.entries.Keys) + @($ix.unmerged.Keys) | Where-Object { SpecMatch $_ @($s) })
        if (-not $m.Count) { Die "pathspec '$s' did not match any files" }
        if (-not $rec -and -not ($m.Count -eq 1 -and $m[0] -ceq $s) -and -not ($s -match '[*?\[]')) { Die "not removing '$s' recursively without -r" }
        $hit += $m
    }
    foreach ($p in (SortPaths ($hit | Select-Object -Unique))) {
        if (-not $quiet) { Out-Text "rm '$p'" }
        $ix.entries.Remove($p); $ix.unmerged.Remove($p)
        if (-not $cached) { $f = Full $p; if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }; PruneDirs (Split-Path $f -Parent) }
    }
    WriteIndex $ix.entries
}
function PruneDirs([string]$d) {
    while ($d -and $d.Length -gt $script:ROOT.Length) {
        if (@(Get-ChildItem -Force -LiteralPath $d -ErrorAction SilentlyContinue).Count) { break }
        Remove-Item -LiteralPath $d -Force; $d = Split-Path $d -Parent
    }
}

function Cmd-Mv($a) {
    if ($a.Count -ne 2) { Die 'usage: pgit mv <source> <destination>' 129 }
    $sp = Specs $a; $src = $sp[0]; $dst = $sp[1]
    $ix = ReadIndex
    if (Test-Path -LiteralPath (Full $dst) -PathType Container) { $dst = ($dst + '/' + $src.Substring($src.LastIndexOf('/') + 1)).TrimStart('/') }
    $moves = @()
    if ($ix.entries.ContainsKey($src)) { $moves += , @($src, $dst) }
    else { foreach ($p in $ix.entries.Keys) { if ($p.StartsWith($src + '/')) { $moves += , @($p, $dst + $p.Substring($src.Length)) } } }
    if (-not $moves.Count) { Die "not under version control, source=$src, destination=$dst" }
    foreach ($mv in $moves) {
        $f1 = Full $mv[0]; $f2 = Full $mv[1]
        EnsureDir (Split-Path $f2 -Parent)
        Move-Item -LiteralPath $f1 -Destination $f2
        $e = $ix.entries[$mv[0]]; $ix.entries.Remove($mv[0])
        $fi = Get-Item -LiteralPath $f2 -Force
        $ix.entries[$mv[1]] = StatEntry $mv[1] $fi $e.id $e.mode
        PruneDirs (Split-Path $f1 -Parent)
    }
    WriteIndex $ix.entries
}

function StatusData() {
    $ix = ReadIndex
    $head = HeadCommit
    $hm = CommitFiles $head
    $im = IndexMap $ix
    $wt = Worktree
    $um = $ix.unmerged
    $staged = DiffMaps $hm $im @() $true $null
    $staged = @($staged | Where-Object { -not $um.ContainsKey($_.key) -and -not ($_.a -and $um.ContainsKey([string]$_.a.path)) })
    $wm = (NewMap); $refreshed = $false
    foreach ($k in @($ix.entries.Keys)) {
        $e = $ix.entries[$k]
        $fi = $wt[$k]
        if ($null -eq $fi) { $fi = Get-Item -LiteralPath (Full $k) -Force -ErrorAction SilentlyContinue; if ($fi -and $fi.PSIsContainer) { $fi = $null } }
        if ($null -eq $fi) { continue }
        if (StatSame $e $fi $ix.mtime) { $wm[$k] = @{ mode = $e.mode; id = $e.id }; continue }
        $id = HashFile $fi.FullName
        if ($id -eq $e.id) { $ix.entries[$k] = StatEntry $k $fi $id $e.mode; $refreshed = $true }
        $wm[$k] = @{ mode = $e.mode; id = $id; file = $fi.FullName }
    }
    if ($refreshed) { try { WriteIndex $ix.entries $um } catch { } }
    $unstaged = DiffMaps $im $wm @() $false $null
    $tdirs = (NewMap)
    foreach ($k in $ix.entries.Keys) { $p = $k; while ($p.Contains('/')) { $p = $p.Substring(0, $p.LastIndexOf('/')); $tdirs[$p] = 1 } }
    $un = (NewMap)
    foreach ($p in $wt.Keys) {
        if ($ix.entries.ContainsKey($p) -or $um.ContainsKey($p)) { continue }
        $top = $p; $q = $p
        while ($q.Contains('/')) { $q = $q.Substring(0, $q.LastIndexOf('/')); if (-not $tdirs.ContainsKey($q)) { $top = $q + '/' } }
        $un[$top] = 1
    }
    $unm = @(); foreach ($k in (SortPaths @($um.Keys))) { $unm += , @{ key = $k; code = (UnmergedCode $um[$k]) } }
    return @{ head = $head; staged = $staged; unstaged = $unstaged; untracked = (SortPaths @($un.Keys)); unmerged = $unm; merging = [bool](MergeHead); pick = (PickState) }
}
function TrackingText([string]$br, [string]$head) {   # git status: where the branch stands against its upstream
    $up = Upstream $br; if (-not $up) { return '' }
    $nm = $up.track.Substring(13)
    $tid = ReadRef $up.track
    if (-not $tid) { return "Your branch is based on '$nm', but the upstream is gone.`n  (use ""pgit branch --unset-upstream"" to fixup)`n" }
    if ($tid -eq $head) { return "Your branch is up to date with '$nm'.`n" }
    $ha = Ancestors $head; $ta = Ancestors $tid
    $ahead = 0; foreach ($k in $ha.Keys) { if (-not $ta.ContainsKey($k)) { $ahead++ } }
    $behind = 0; foreach ($k in $ta.Keys) { if (-not $ha.ContainsKey($k)) { $behind++ } }
    $c = { param($n) if ($n -eq 1) { '1 commit' } else { "$n commits" } }
    if ($behind -eq 0) { return "Your branch is ahead of '$nm' by $(& $c $ahead).`n  (use ""pgit push"" to publish your local commits)`n" }
    if ($ahead -eq 0) { return "Your branch is behind '$nm' by $(& $c $behind), and can be fast-forwarded.`n  (use ""pgit pull"" to update your local branch)`n" }
    return "Your branch and '$nm' have diverged,`nand have $ahead and $behind different commits each, respectively.`n  (use ""pgit pull"" to merge the remote branch into yours)`n"
}
function UnmergedCode($st) {                          # stages present -> git's two-letter code
    $k = ''; foreach ($n in 1, 2, 3) { if ($st.ContainsKey($n)) { $k += [string]$n } }
    switch ($k) { '123' { 'UU' } '23' { 'AA' } '12' { 'UD' } '13' { 'DU' } '1' { 'DD' } '2' { 'AU' } '3' { 'UA' } default { 'UU' } }
}
$script:UNMLABEL = @{ 'UU' = 'both modified:'; 'AA' = 'both added:'; 'UD' = 'deleted by them:'; 'DU' = 'deleted by us:'; 'DD' = 'both deleted:'; 'AU' = 'added by us:'; 'UA' = 'added by them:' }
function StLabel($pr) { switch ($pr.st) { 'A' { 'new file:   ' } 'D' { 'deleted:    ' } 'R' { 'renamed:    ' } default { if ($pr.a.mode -ne $pr.b.mode -and $pr.a.id -eq $pr.b.id) { 'modified:   ' } else { 'modified:   ' } } } }
function Cmd-Status($a) {
    $script:OPTARGS = @($a)
    $short = Opt @('-s', '--short')
    $porc = Opt @('--porcelain')
    $a = $script:OPTARGS
    $d = StatusData
    if ($short -or $porc) {
        $rows = (NewMap)
        foreach ($pr in $d.staged) { $rows[$pr.key] = @($pr.st, ' ', $pr) }
        foreach ($pr in $d.unstaged) { if ($rows.ContainsKey($pr.key)) { $rows[$pr.key][1] = $pr.st } else { $rows[$pr.key] = @(' ', $pr.st, $pr) } }
        foreach ($u in $d.unmerged) { $rows[$u.key] = @($u.code.Substring(0, 1), $u.code.Substring(1), @{ key = $u.key }) }
        $o = ''
        foreach ($k in (SortPaths @($rows.Keys))) {
            $r = $rows[$k]; $pr = $r[2]
            $pth = $k; if (-not $porc) { $pth = RelOut $k }
            if ($r[0] -eq 'R') { $from = $pr.a.path; if (-not $porc) { $from = RelOut $from }; $o += 'R' + $r[1] + ' ' + (QuotePath $from) + ' -> ' + (QuotePath $pth) + "`n" }
            else { $o += $r[0] + $r[1] + ' ' + (QuotePath $pth) + "`n" }
        }
        foreach ($u in $d.untracked) { $p = $u; if (-not $porc) { $p = RelOut $u; if ($u.EndsWith('/') -and -not $p.EndsWith('/')) { $p += '/' } }; $o += '?? ' + (QuotePath $p) + "`n" }
        Out-Text $o; return
    }
    $hr = HeadRef
    $o = ''
    if ($hr) { $o += 'On branch ' + $hr.Substring(11) + "`n" } else { $o += 'HEAD detached at ' + (Abbrev $d.head) + "`n" }
    $trk = ''; if ($hr -and $d.head) { $trk = TrackingText $hr.Substring(11) $d.head }
    if ($trk) { $o += $trk + "`n" }                      # git: each block and section ends with a blank line
    if (-not $d.head) { $o += "`nNo commits yet`n`n" }
    if ($d.unmerged.Count -and $d.merging) { $o += "You have unmerged paths.`n  (fix conflicts and run ""pgit commit"")`n  (use ""pgit merge --abort"" to abort the merge)`n`n" }
    elseif ($d.merging) { $o += "All conflicts fixed but you are still merging.`n  (use ""pgit commit"" to conclude merge)`n`n" }
    elseif ($d.pick) {
        $pv = 'cherry-pick'; $pw = 'cherry-picking'; if ($d.pick.kind -eq 'REVERT_HEAD') { $pv = 'revert'; $pw = 'reverting' }
        $o += "You are currently $pw commit $(Abbrev $d.pick.id).`n"
        if ($d.unmerged.Count) { $o += "  (fix conflicts and run ""pgit $pv --continue"")`n" } else { $o += "  (all conflicts fixed: run ""pgit $pv --continue"")`n" }
        $o += "  (use ""pgit $pv --skip"" to skip this patch)`n  (use ""pgit $pv --abort"" to cancel the $pv operation)`n`n"
    }
    $quietHints = $d.merging -or ($d.pick -and $d.pick.kind -eq 'CHERRY_PICK_HEAD')   # git's FROM_MERGE / FROM_CHERRY_PICK
    if ($d.staged.Count) {
        $o += "Changes to be committed:`n"
        if ($quietHints) { } elseif ($d.head) { $o += "  (use ""pgit restore --staged <file>..."" to unstage)`n" } else { $o += "  (use ""pgit rm --cached <file>..."" to unstage)`n" }
        foreach ($pr in $d.staged) { $line = "`t" + (StLabel $pr); if ($pr.st -eq 'R') { $line += (QuotePath (RelOut $pr.a.path)) + ' -> ' + (QuotePath (RelOut $pr.b.path)) } else { $line += QuotePath (RelOut $pr.key) }; $o += $line + "`n" }
        $o += "`n"
    }
    if ($d.unmerged.Count) {
        $o += "Unmerged paths:`n"
        if (-not $quietHints) { if ($d.head) { $o += "  (use ""pgit restore --staged <file>..."" to unstage)`n" } else { $o += "  (use ""pgit rm --cached <file>..."" to unstage)`n" } }
        $codes = @($d.unmerged | ForEach-Object { $_.code })
        if ($codes -contains 'DD' -and -not @($codes | Where-Object { $_ -ne 'DD' }).Count) { $o += "  (use ""pgit rm <file>..."" to mark resolution)`n" }
        elseif (@($codes | Where-Object { $_ -ne 'UU' -and $_ -ne 'AA' }).Count) { $o += "  (use ""pgit add/rm <file>..."" as appropriate to mark resolution)`n" }
        else { $o += "  (use ""pgit add <file>..."" to mark resolution)`n" }
        foreach ($u in $d.unmerged) { $lb = $script:UNMLABEL[$u.code]; $o += "`t" + $lb + (' ' * (17 - $lb.Length)) + (QuotePath (RelOut $u.key)) + "`n" }
        $o += "`n"
    }
    if ($d.unstaged.Count) {
        $o += "Changes not staged for commit:`n"
        if (@($d.unstaged | Where-Object { $_.st -eq 'D' }).Count) { $o += "  (use ""pgit add/rm <file>..."" to update what will be committed)`n" } else { $o += "  (use ""pgit add <file>..."" to update what will be committed)`n" }
        $o += "  (use ""pgit restore <file>..."" to discard changes in working directory)`n"
        foreach ($pr in $d.unstaged) { $o += "`t" + (StLabel $pr) + (QuotePath (RelOut $pr.key)) + "`n" }
        $o += "`n"
    }
    if ($d.untracked.Count) {
        $o += "Untracked files:`n  (use ""pgit add <file>..."" to include in what will be committed)`n"
        foreach ($u in $d.untracked) { $p = RelOut $u; if ($u.EndsWith('/') -and -not $p.EndsWith('/')) { $p += '/' }; $o += "`t" + (QuotePath $p) + "`n" }
        $o += "`n"
    }
    if ($d.merging -and -not $d.unmerged.Count) { }
    elseif (-not $d.staged.Count) {
        if ($d.unstaged.Count -or $d.unmerged.Count) { $o += "no changes added to commit (use ""pgit add"" and/or ""pgit commit -a"")`n" }
        elseif ($d.untracked.Count) { $o += "nothing added to commit but untracked files present (use ""pgit add"" to track)`n" }
        elseif (-not $d.head) { $o += "nothing to commit (create/copy files and use ""pgit add"" to track)`n" }
        else { $o += "nothing to commit, working tree clean`n" }
    }
    Out-Text $o
}

function Cmd-Commit($a) {
    $x = @(); foreach ($t in $a) { $t = [string]$t; if ($t -cmatch '^-[aqsvn]+m?$' -and $t.Length -gt 2) { foreach ($ch in $t.Substring(1).ToCharArray()) { $x += ('-' + $ch) } } else { $x += $t } }; $a = $x   # -am, -qam: git's bundled short options
    $script:OPTARGS = @($a)
    $msgs = @()
    $b = $a; $rest = @(); $i = 0
    while ($i -lt $b.Count) { $x = [string]$b[$i]; if ($x -ceq '-m' -or $x -ceq '--message') { $msgs += [string]$b[$i + 1]; $i += 2; continue }; if ($x.StartsWith('-m') -and $x.Length -gt 2 -and $x -notmatch '^-m[a-z]') { $msgs += $x.Substring(2); $i++; continue }; if ($x.StartsWith('--message=')) { $msgs += $x.Substring(10); $i++; continue }; $rest += $x; $i++ }
    $a = $rest
    $file = Opt @('-F', '--file') $true
    $all = Opt @('-a', '--all')
    $empty = Opt @('--allow-empty')
    $amend = Opt @('--amend')
    $quiet = Opt @('-q', '--quiet')
    $null = Opt @('--no-edit')
    $a = $script:OPTARGS
    if ($file) { $msgs += (ReadText $file) }
    $mhead = MergeHead
    if ($mhead -and $amend) { Die 'You are in the middle of a merge -- cannot amend.' }
    if ($all) {
        $ix = ReadIndex
        foreach ($k in @($ix.unmerged.Keys)) {
            $f = Full $k; $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            if ($fi -and -not $fi.PSIsContainer) { $st = $ix.unmerged[$k]; $mode = 33188; foreach ($n in 2, 3, 1) { if ($st.ContainsKey($n)) { $mode = $st[$n].mode; break } }; $ix.entries[$k] = StatEntry $k $fi (WriteObject 'blob' (Zl-ReadBytes $f)) $mode }
            $ix.unmerged.Remove($k)
        }
        foreach ($k in @($ix.entries.Keys)) {
            $e = $ix.entries[$k]; $f = Full $k
            $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            if ($null -eq $fi) { $ix.entries.Remove($k); continue }
            if (StatSame $e $fi $ix.mtime) { continue }
            $id = WriteObject 'blob' (Zl-ReadBytes $f); $ix.entries[$k] = StatEntry $k $fi $id $e.mode
        }
        WriteIndex $ix.entries
    }
    $ix0 = ReadIndex
    if ($ix0.unmerged.Count) {
        $ul = ''; foreach ($k in (SortPaths @($ix0.unmerged.Keys))) { $ul += "U`t" + $k + "`n" }
        Die ($script:RAW + "error: Committing is not possible because you have unmerged files.`nhint: Fix them up in the work tree, and then use 'pgit add/rm <file>'`nhint: as appropriate to mark resolution and make a commit.`nfatal: Exiting because of an unresolved conflict.`n" + $ul)
    }
    $head = HeadCommit
    $parents = @(); if ($head) { $parents = @($head) }
    $old = $null
    if ($amend) { if (-not $head) { Die 'You have nothing to amend.' }; $old = ParseCommit $head; $parents = $old.parents; if (-not $msgs.Count) { $msgs = @($old.message) } }
    if ($mhead) { $parents += $mhead; if (-not $msgs.Count) { $msgs = @(ReadText (GitPath 'MERGE_MSG')) } }   # concluding a merge: MERGE_MSG as git commit --no-edit
    $pst = PickState
    if (-not $msgs.Count -and (Test-Path -LiteralPath (GitPath 'MERGE_MSG'))) { $msgs = @(ReadText (GitPath 'MERGE_MSG')) }   # git commit takes a pending MERGE_MSG
    if (-not $msgs.Count) {                            # git says 'nothing to commit' before it wants a message
        if (-not $amend -and -not $empty -and -not $mhead -and $head -and (WriteTreeFromMap (IndexMap (ReadIndex))) -eq (ParseCommit $head).tree) { Cmd-Status @(); $script:RC = 1; return }
        Die 'no commit message: use -m "message" (pgit has no editor)' 1
    }
    $msg = CleanMessage ($msgs -join "`n`n")
    if (-not $msg) { Die 'Aborting commit due to empty commit message.' 1 }
    $ix = ReadIndex
    $tree = WriteTreeFromMap (IndexMap $ix)
    $ptree = $null; if ($parents.Count) { $ptree = (ParseCommit $parents[0]).tree }
    if (-not $amend -and -not $empty -and -not $mhead -and $ptree -eq $tree) { Cmd-Status @(); $script:RC = 1; return }
    if (-not $amend -and -not $empty -and -not $head -and $ix.entries.Count -eq 0) { Cmd-Status @(); $script:RC = 1; return }
    $au = Ident 'AUTHOR'
    if ($pst -and $pst.kind -eq 'CHERRY_PICK_HEAD') { $au = (ParseCommit $pst.id).author.raw }
    $reset = Opt @('--reset-author')
    if ($amend -and -not $reset) { $au = $old.author.raw }   # git keeps the amended commit's author and date (GIT_AUTHOR_* do not apply)
    $cm = Ident 'COMMITTER'
    $t = "tree $tree`n"; foreach ($p in $parents) { $t += "parent $p`n" }
    $t += "author $au`ncommitter $cm`n`n" + $msg
    $id = WriteObject 'commit' (Zl-Utf8Enc $t)
    $hr = HeadRef
    if ($hr) { UpdateRef $hr $id } else { SetHead $id }
    if ($mhead) { ClearMergeState }
    if ($pst) { ClearPickState }
    $mmf = GitPath 'MERGE_MSG'; if (Test-Path -LiteralPath $mmf) { Remove-Item -LiteralPath $mmf -Force }
    if ($quiet) { return }
    $where = 'detached HEAD'; if ($hr) { $where = $hr.Substring(11) }
    if ($mhead) { Out-Text ('[' + $where + ' ' + (Abbrev $id) + '] ' + (Subject $msg)); return }
    if (-not $parents.Count) { $where += ' (root-commit)' }
    $o = '[' + $where + ' ' + (Abbrev $id) + '] ' + (Subject $msg) + "`n"
    if ($amend -or ($pst -and $pst.kind -eq 'CHERRY_PICK_HEAD')) {     # git: the author came from elsewhere, so show it and its date
        $ap = ParsePerson $au; $me = ParsePerson $cm
        if ($ap.name -cne $me.name -or $ap.email -cne $me.email) { $o += ' Author: ' + $ap.name + ' <' + $ap.email + ">`n" }
        $o += ' Date: ' + (GitDate $ap.time $ap.tz) + "`n"
    }
    $prev = (NewMap); if ($parents.Count) { $prev = CommitFiles $parents[0] }
    $o += (Summary (DiffMaps $prev (FlattenTree $tree) @() $true $null))
    Out-Text $o
}
function Summary($pairs) {
    $files = $pairs.Count; $ins = 0; $del = 0; $lines = ''
    foreach ($pr in $pairs) {
        $st = PairStat $pr; $ins += $st[0]; $del += $st[1]
        if ($pr.st -eq 'A') { $lines += ' create mode ' + (ModeStr $pr.b.mode) + ' ' + (QuotePath $pr.b.path) + "`n" }
        elseif ($pr.st -eq 'D') { $lines += ' delete mode ' + (ModeStr $pr.a.mode) + ' ' + (QuotePath $pr.a.path) + "`n" }
        elseif ($pr.st -eq 'R') { $lines += ' rename ' + (PrettyRename $pr.a.path $pr.b.path) + " ($($pr.score)%)`n" }
        elseif ($pr.a.mode -ne $pr.b.mode) { $lines += ' mode change ' + (ModeStr $pr.a.mode) + ' => ' + (ModeStr $pr.b.mode) + ' ' + (QuotePath $pr.b.path) + "`n" }
    }
    if (-not $files) { $s = " 0 files changed`n" }
    else {
        if ($files -eq 1) { $s = " 1 file changed" } else { $s = " $files files changed" }
        if ($ins -or $del -eq 0) { if ($ins -eq 1) { $s += ', 1 insertion(+)' } else { $s += ", $ins insertions(+)" } }
        if ($del -or $ins -eq 0) { if ($del -eq 1) { $s += ', 1 deletion(-)' } else { $s += ", $del deletions(-)" } }
        $s += "`n"
    }
    return $s + $lines
}
function DiffStat($pairs) {                          # git's --stat (80 columns, as when not on a terminal)
    $rows = @(); $maxLen = 0; $maxCh = 0; $binW = 0; $ins = 0; $del = 0
    foreach ($pr in $pairs) {
        if ($pr.st -eq 'R') { $nm = PrettyRename $pr.a.path $pr.b.path } else { $nm = QuotePath $pr.key }
        $ab = SideBytes $pr.a; $bb = SideBytes $pr.b
        if ((IsBinary $ab) -or (IsBinary $bb)) {
            $rows += @{ name = $nm; bin = $true; old = $ab.Length; new = $bb.Length }
            $l = 4 + ([string]$bb.Length).Length + 4 + ([string]$ab.Length).Length + 6; if ($l -gt $binW) { $binW = $l }
        } else {
            $st = @(0, 0); if ((SideId $pr.a) -ne (SideId $pr.b)) { $ch = XDiff (SplitRecs (Latin1 $ab)) (SplitRecs (Latin1 $bb)); foreach ($x in $ch) { $st[0] += $x.c2; $st[1] += $x.c1 } }
            $rows += @{ name = $nm; bin = $false; add = $st[0]; del = $st[1] }
            $ins += $st[0]; $del += $st[1]
            if ($st[0] + $st[1] -gt $maxCh) { $maxCh = $st[0] + $st[1] }
        }
        if ($nm.Length -gt $maxLen) { $maxLen = $nm.Length }
    }
    if (-not $rows.Count) { return '' }
    $width = 80; $numW = ([string]$maxCh).Length
    if ($width -lt 16 + 6 + $numW) { $width = 16 + 6 + $numW }
    if ($maxCh + 4 -gt $binW) { $gw = $maxCh } else { $gw = $binW - 4 }
    $nw = $maxLen
    if ($nw + $numW + 6 + $gw -gt $width) {
        $lim = [int](($width * 3 - (($width * 3) % 8)) / 8) - $numW - 6
        if ($gw -gt $lim) { $gw = $lim; if ($gw -lt 6) { $gw = 6 } }
        if ($nw -gt $width - $numW - 6 - $gw) { $nw = $width - $numW - 6 - $gw } else { $gw = $width - $numW - 6 - $nw }
    }
    $o = ''
    foreach ($r in $rows) {
        $nm = $r.name
        if ($nm.Length -gt $nw) { $nm = '...' + $nm.Substring($nm.Length - $nw + 3); $sl = $nm.IndexOf('/'); if ($sl -ge 0) { $nm = '...' + $nm.Substring($sl) } }
        $o += ' ' + $nm.PadRight($nw)
        if ($r.bin) { $o += ' | Bin ' + $r.old + ' -> ' + $r.new + " bytes`n"; continue }
        $a = $r.add; $d = $r.del; $tot = $a + $d
        $o += ' | ' + ([string]$tot).PadLeft($numW); if ($tot) { $o += ' ' }
        if ($gw -le $maxCh -and $maxCh -gt 0) {
            $t = 0; if ($tot) { $t = 1 + [int](($tot * ($gw - 1) - (($tot * ($gw - 1)) % $maxCh)) / $maxCh) }
            if ($t -lt 2 -and $a -and $d) { $t = 2 }
            if ($a -lt $d) { $sa = 0; if ($a) { $sa = 1 + [int](($a * ($gw - 1) - (($a * ($gw - 1)) % $maxCh)) / $maxCh) }; $a = $sa; $d = $t - $a }
            else { $sd = 0; if ($d) { $sd = 1 + [int](($d * ($gw - 1) - (($d * ($gw - 1)) % $maxCh)) / $maxCh) }; $d = $sd; $a = $t - $d }
        }
        $o += ('+' * $a) + ('-' * $d) + "`n"
    }
    $files = $rows.Count
    if ($files -eq 1) { $s = ' 1 file changed' } else { $s = " $files files changed" }
    if ($ins -or $del -eq 0) { if ($ins -eq 1) { $s += ', 1 insertion(+)' } else { $s += ", $ins insertions(+)" } }
    if ($del -or $ins -eq 0) { if ($del -eq 1) { $s += ', 1 deletion(-)' } else { $s += ", $del deletions(-)" } }
    return ($o + $s + "`n")
}
function PrettyRename([string]$a, [string]$b) {
    if ((QuotePath $a) -ne $a -or (QuotePath $b) -ne $b) { return ((QuotePath $a) + ' => ' + (QuotePath $b)) }
    $la = $a.Length; $lb = $b.Length
    $pfx = 0; $i = 0
    while ($i -lt $la -and $i -lt $lb -and $a[$i] -ceq $b[$i]) { if ($a[$i] -eq '/') { $pfx = $i + 1 }; $i++ }
    $sfx = 0; $adj = 0; if ($pfx) { $adj = 1 }
    $oa = $la; $ob = $lb
    while ($pfx - $adj -le $oa -and $pfx - $adj -le $ob) {
        $ca = ''; if ($oa -lt $la) { $ca = [string]$a[$oa] }; $cb = ''; if ($ob -lt $lb) { $cb = [string]$b[$ob] }
        if ($ca -cne $cb) { break }
        if ($ca -eq '/') { $sfx = $la - $oa }
        $oa--; $ob--
        if ($oa -lt 0 -or $ob -lt 0) { break }
    }
    $am = $la - $pfx - $sfx; if ($am -lt 0) { $am = 0 }
    $bm = $lb - $pfx - $sfx; if ($bm -lt 0) { $bm = 0 }
    $o = ''
    if ($pfx + $sfx) { $o += $a.Substring(0, $pfx) + '{' }
    $o += $a.Substring($pfx, $am) + ' => ' + $b.Substring($pfx, $bm)
    if ($pfx + $sfx) { $o += '}' + $a.Substring($la - $sfx, $sfx) }
    return $o
}

function Cmd-Log($a) {
    $script:OPTARGS = @($a)
    $one = Opt @('--oneline')
    $all = Opt @('--all')
    $patch = Opt @('-p', '--patch', '-u')
    $lstat = Opt @('--stat')
    $deco = Opt @('--decorate')
    $n = Opt @('-n', '--max-count') $true
    $fmt = Opt @('--format', '--pretty') $true
    $a = $script:OPTARGS
    $rest = @(); foreach ($x in $a) { if ($x -match '^-(\d+)$') { $n = $Matches[1] } else { $rest += $x } }
    $sd = SplitDashes $rest; $revs = $sd[0]; $specs = Specs $sd[1]
    $maxCount = -1; if ($null -ne $n) { $maxCount = [int]$n }
    $starts = @()
    if ($all) { foreach ($v in (ListRefs 'refs/').Values) { try { $starts += (PeelTo $v 'commit') } catch { } }; $h = HeadCommit; if ($h) { $starts += $h } }
    foreach ($r in $revs) { $starts += (RevCommit $r) }
    if (-not $starts.Count) { $h = HeadCommit; if (-not $h) { $hr = HeadRef; Die ("your current branch '" + $hr.Substring(11) + "' does not have any commits yet") }; $starts = @($h) }
    $cs = WalkLog ($starts | Select-Object -Unique) -1
    if ($specs.Count) {
        $keep = @()
        foreach ($c in $cs) {
            $old = (NewMap); if ($c.parents.Count) { $old = CommitFiles $c.parents[0] }
            if ((DiffMaps $old (FlattenTree $c.tree) $specs $false $null).Count) { $keep += $c }
        }
        $cs = $keep
    }
    if ($maxCount -ge 0 -and $cs.Count -gt $maxCount) { if ($maxCount -eq 0) { $cs = @() } else { $cs = $cs[0..($maxCount - 1)] } }
    $dd = $null; if ($deco) { $dd = Decorations }
    $o = ''; $first = $true
    foreach ($c in $cs) {
        if ($fmt) { $o += (Format-Commit $c $fmt) + "`n"; continue }
        if ($one) {
            $o += (Abbrev $c.id)
            if ($dd -and $dd.ContainsKey($c.id)) { $o += ' (' + ($dd[$c.id] -join ', ') + ')' }
            $o += ' ' + (Subject $c.message) + "`n"
            if ($patch) { $pp = CommitPatch $c 3; if ($pp) { $o += $pp } }
            continue
        }
        if (-not $first) { $o += "`n" }; $first = $false
        $o += CommitHeader $c $dd
        if ($lstat) { $st = CommitStat $c; if ($st) { $o += "`n" + $st } }
        if ($patch) { $pp = CommitPatch $c 3; if ($pp) { $o += "`n" + $pp } }
    }
    Out-Text (L1ToText $o)
}
function Format-Commit($c, [string]$f) {
    if ($f.StartsWith('format:')) { $f = $f.Substring(7) } elseif ($f.StartsWith('tformat:')) { $f = $f.Substring(8) }
    if ($f -eq 'oneline') { return ($c.id + ' ' + (Subject $c.message)) }
    $o = ''; $i = 0
    foreach ($m in [regex]::Matches($f, '%(an|ae|at|ad|cn|ce|ct|cd|H|h|T|t|P|p|s|b|B|n|%|x[0-9a-fA-F]{2})')) {
        $o += $f.Substring($i, $m.Index - $i); $i = $m.Index + $m.Length
        switch -CaseSensitive ($m.Groups[1].Value) {
            'H' { $o += $c.id } 'h' { $o += (Abbrev $c.id) } 'T' { $o += $c.tree } 't' { $o += (Abbrev $c.tree) }
            'P' { $o += ($c.parents -join ' ') } 'p' { $o += (($c.parents | ForEach-Object { Abbrev $_ }) -join ' ') }
            'an' { $o += $c.author.name } 'ae' { $o += $c.author.email } 'at' { $o += [string]$c.author.time } 'ad' { $o += (GitDate $c.author.time $c.author.tz) }
            'cn' { $o += $c.committer.name } 'ce' { $o += $c.committer.email } 'ct' { $o += [string]$c.committer.time } 'cd' { $o += (GitDate $c.committer.time $c.committer.tz) }
            's' { $o += (Subject $c.message) } 'n' { $o += "`n" } '%' { $o += '%' } 'B' { $o += $c.message }
            'b' { $bm = [regex]::Match($c.message, '^\n*(?:[^\n]+\n?)*\n*'); $o += $c.message.Substring($bm.Length) }
            default { $v = $m.Groups[1].Value; $o += [string][char](16 * $script:HEXV[[string]$v[1]] + $script:HEXV[[string]$v[2]]) }
        }
    }
    return ($o + $f.Substring($i))
}

function CommitStat($c) {
    if ($c.parents.Count -gt 1) { return '' }
    $old = (NewMap); if ($c.parents.Count) { $old = CommitFiles $c.parents[0] }
    return (DiffStat (DiffMaps $old (FlattenTree $c.tree) @() $true $null))
}
function Cmd-Show($a) {
    $script:OPTARGS = @($a)
    $stat = Opt @('--stat')
    $a = $script:OPTARGS
    $sd = SplitDashes $a; $revs = $sd[0]; if (-not $revs.Count) { $revs = @('HEAD') }
    $o = ''
    foreach ($r in $revs) {
        $colon = $r.IndexOf(':')
        if ($colon -ge 0) {
            $tid = PeelTo (Rev $r.Substring(0, $colon)) 'tree'; $pth = $r.Substring($colon + 1)
            $m = FlattenTree $tid
            if (-not $m.ContainsKey($pth)) { Die "path '$pth' does not exist in '$($r.Substring(0, $colon))'" }
            $o += Latin1 (ReadBlob $m[$pth].id); continue
        }
        $id = Rev $r
        $gobj = ReadObject $id
        if ($gobj.type -eq 'tag') {
            $g = ParseTag $id
            $o += 'tag ' + $g.tag + "`n"
            if ($g.tagger) { $o += 'Tagger: ' + $g.tagger.name + ' <' + $g.tagger.email + ">`nDate:   " + (GitDate $g.tagger.time $g.tagger.tz) + "`n" }
            $o += "`n" + (L1Bytes $g.message) + "`n"
            $id = PeelTo $id 'any'; $gobj = ReadObject $id
            if ($gobj.type -ne 'commit') { $o += (ShowObj $id $gobj); continue }
        }
        if ($gobj.type -eq 'commit') {
            $c = ParseCommit $id
            $o += Latin1 (Zl-Utf8Enc (CommitHeader $c $null))
            if ($stat) { $o += "`n" + (CommitStat $c); continue }
            if ($c.parents.Count -gt 1) { $o += "`n"; continue }     # git's empty combined diff still ends with a blank line
            $pp = CommitPatch $c 3; if ($pp) { $o += "`n" + $pp }
        } else { $o += (ShowObj $id $gobj) }
    }
    Out-Text (L1ToText $o)
}
function L1Bytes([string]$s) { return (Latin1 (Zl-Utf8Enc $s)) }
function ShowObj($id, $gobj) {
    if ($gobj.type -eq 'blob') { return (Latin1 $gobj.body) }
    if ($gobj.type -eq 'tree') { $o = "tree $id`n`n"; foreach ($e in (ParseTree $id)) { $n = $e.name; if ($e.tree) { $n += '/' }; $o += (L1Bytes $n) + "`n" }; return $o }
    return (Latin1 $gobj.body)
}

function Cmd-Diff($a) {
    $script:OPTARGS = @($a)
    $cached = Opt @('--cached', '--staged')
    $u = Opt @('-U', '--unified') $true
    $nameOnly = Opt @('--name-only')
    $nameStatus = Opt @('--name-status')
    $stat = Opt @('--stat')
    $a = $script:OPTARGS
    $ctx = 3; if ($null -ne $u) { $ctx = [int]$u }
    $sd = SplitDashes $a; $revs = @(); $paths = @()
    foreach ($x in $sd[0]) { if ($x -match '\.\.') { $revs += ($x -split '\.\.\.?') } elseif ((Rev $x $true)) { $revs += $x } elseif (Test-Path -LiteralPath $x) { $paths += $x } else { $null = Rev $x } }
    $specs = Specs ($paths + $sd[1])
    $ix = ReadIndex
    if ($revs.Count -eq 2) { $mapA = CommitFiles (RevCommit $revs[0]); $mapB = CommitFiles (RevCommit $revs[1]); $ren = $true }
    elseif ($cached) { $c = $null; if ($revs.Count) { $c = RevCommit $revs[0] } else { $c = HeadCommit }; $mapA = CommitFiles $c; $mapB = IndexMap $ix; $ren = $true }
    elseif ($revs.Count -eq 1) { $mapA = CommitFiles (RevCommit $revs[0]); $mapB = WorkMap $ix $true; $ren = $false }
    else { $mapA = IndexMap $ix; $mapB = WorkMap $ix $true; $ren = $false }
    $pairs = DiffMaps $mapA $mapB $specs $ren $null
    $pairs = @($pairs | Where-Object { -not $ix.unmerged.ContainsKey($_.key) })
    $o = ''
    if ($revs.Count -lt 2) { foreach ($k in (SortPaths @($ix.unmerged.Keys))) { if (SpecMatch $k $specs) { $o += "* Unmerged path $k`n" } } }
    if ($nameOnly) { foreach ($pr in $pairs) { $o += (QuotePath $pr.key) + "`n" }; Out-Text $o; return }
    if ($nameStatus) { foreach ($pr in $pairs) { if ($pr.st -eq 'R') { $o += "R100`t" + (QuotePath $pr.a.path) + "`t" + (QuotePath $pr.b.path) + "`n" } else { $o += $pr.st + "`t" + (QuotePath $pr.key) + "`n" } }; Out-Text $o; return }
    if ($stat) { Out-Text (DiffStat $pairs); return }
    foreach ($pr in $pairs) { $o += PairPatch $pr $ctx $null }
    Out-Text (L1ToText $o)
}

function Cmd-Branch($a) {
    $script:OPTARGS = @($a)
    $del = Opt @('-d', '--delete')
    $delForce = Opt @('-D')
    $mv = Opt @('-m', '--move')
    $a = $script:OPTARGS
    $hr = HeadRef
    if ($del -or $delForce) {
        foreach ($b in $a) {
            $id = ReadRef "refs/heads/$b"
            if (-not $id) { Die "branch '$b' not found." 1 }
            if ($hr -eq "refs/heads/$b") { Die "Cannot delete branch '$b' checked out at '$script:ROOT'" 1 }
            if (-not $delForce) { $h = HeadCommit; $reach = $false; if ($h) { foreach ($c in (WalkLog @($h) -1)) { if ($c.id -eq $id) { $reach = $true; break } } }; if (-not $reach) { Die "error: The branch '$b' is not fully merged.`nIf you are sure you want to delete it, run 'pgit branch -D $b'." 1 } }
            DeleteRef "refs/heads/$b"
            Out-Text "Deleted branch $b (was $(Abbrev $id))."
        }
        return
    }
    if ($mv) {
        if ($a.Count -eq 1) { $old = $hr.Substring(11); $new = $a[0] } else { $old = $a[0]; $new = $a[1] }
        $id = ReadRef "refs/heads/$old"; if (-not $id) { Die "branch '$old' not found" }
        UpdateRef "refs/heads/$new" $id; DeleteRef "refs/heads/$old"
        if ($hr -eq "refs/heads/$old") { SetHead "refs/heads/$new" }
        return
    }
    if ($a.Count) {
        $nm = $a[0]; if (-not (ValidRef $nm)) { Die "'$nm' is not a valid branch name." }
        if (ReadRef "refs/heads/$nm") { Die "A branch named '$nm' already exists." }
        $start = 'HEAD'; if ($a.Count -gt 1) { $start = $a[1] }
        UpdateRef "refs/heads/$nm" (RevCommit $start); return
    }
    $o = ''
    $h = HeadCommit
    if (-not $hr -and $h) { $o += '* (HEAD detached at ' + (Abbrev $h) + ")`n" }
    $refs = ListRefs 'refs/heads/'
    foreach ($k in (SortPaths @($refs.Keys))) { if ($k -eq $hr) { $o += '* ' } else { $o += '  ' }; $o += $k.Substring(11) + "`n" }
    Out-Text $o
}
function ValidRef([string]$n) { return ($n -and $n -notmatch '(^[-.]|\.\.|[\s~^:?*\[\\]|@\{|\.lock$|/$|\.$|//)') }

function Cmd-Tag($a) {
    $script:OPTARGS = @($a)
    $ann = Opt @('-a', '--annotate')
    $msg = Opt @('-m', '--message') $true
    $del = Opt @('-d', '--delete')
    $force = Opt @('-f', '--force')
    $list = Opt @('-l', '--list')
    $a = $script:OPTARGS
    if ($del) { foreach ($t in $a) { $id = ReadRef "refs/tags/$t"; if (-not $id) { Die "tag '$t' not found." 1 }; DeleteRef "refs/tags/$t"; Out-Text "Deleted tag '$t' (was $(Abbrev $id))" }; return }
    if ($list -or -not $a.Count) {
        $refs = ListRefs 'refs/tags/'; $o = ''
        foreach ($k in (SortPaths @($refs.Keys))) { $n = $k.Substring(10); if ($a.Count -and -not ($n -clike $a[0])) { continue }; $o += $n + "`n" }
        Out-Text $o; return
    }
    $nm = $a[0]; if (-not (ValidRef $nm)) { Die "'$nm' is not a valid tag name." }
    if ((ReadRef "refs/tags/$nm") -and -not $force) { Die "tag '$nm' already exists" }
    $target = 'HEAD'; if ($a.Count -gt 1) { $target = $a[1] }
    $id = Rev $target
    if ($ann -or $null -ne $msg) {
        if ($null -eq $msg) { Die 'no tag message: use -m "message" (pgit has no editor)' }
        $type = (ReadObject $id).type
        $t = "object $id`ntype $type`ntag $nm`ntagger " + (Ident 'COMMITTER') + "`n`n" + (CleanMessage $msg)
        $id = WriteObject 'tag' (Zl-Utf8Enc $t)
    }
    UpdateRef "refs/tags/$nm" $id
}

function ApplyTree($fromMap, $toMap, $ix, [bool]$force, [bool]$hard) {   # move index and worktree from one tree to another
    $all = (NewMap); foreach ($k in $fromMap.Keys) { $all[$k] = 1 }; foreach ($k in $toMap.Keys) { $all[$k] = 1 }; foreach ($k in $ix.entries.Keys) { if ($hard) { $all[$k] = 1 } }
    $changes = @(); $conflicts = @()
    foreach ($p in $all.Keys) {
        $x = $fromMap[$p]; $y = $toMap[$p]; $e = $ix.entries[$p]
        $same = ($x -and $y -and $x.id -eq $y.id -and $x.mode -eq $y.mode) -or (-not $x -and -not $y)
        if ($same -and -not $hard) { continue }
        if (-not $force) {
            $f = Full $p
            $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            $idxDiff = ($e -and (-not $x -or $e.id -ne $x.id)) -or (-not $e -and $x)
            $wtDiff = $false
            if ($e) { if ($null -eq $fi) { $wtDiff = $true } elseif (-not (StatSame $e $fi $ix.mtime)) { $wtDiff = ((HashFile $f) -ne $e.id) } }
            elseif ($fi -and -not $fi.PSIsContainer -and $y) { $wtDiff = ((HashFile $f) -ne $y.id); if ($wtDiff) { $conflicts += $p; continue } }
            if ($idxDiff -or $wtDiff) {
                $atTarget = $y -and $e -and $e.id -eq $y.id -and -not $wtDiff
                if (-not $atTarget -and -not (-not $y -and -not $e)) { $conflicts += $p; continue }
            }
        }
        $changes += $p
    }
    if ($conflicts.Count) {
        Die ("Your local changes to the following files would be overwritten by checkout:`n" + ((SortPaths $conflicts | ForEach-Object { "`t" + $_ }) -join "`n") + "`nPlease commit your changes or stash them before you switch branches.`nAborting") 1
    }
    foreach ($p in $changes) {
        $y = $toMap[$p]; $f = Full $p
        if ($y) {
            $e = $ix.entries[$p]; $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            $need = $true
            if ($e -and $fi -and -not $fi.PSIsContainer -and $e.id -eq $y.id -and (StatSame $e $fi $ix.mtime)) { $need = $false }
            if ($need -and $fi -and -not $fi.PSIsContainer -and $hard -and (HashFile $f) -eq $y.id) { $need = $false }
            if ($need) { EnsureDir (Split-Path $f -Parent); Zl-WriteBytes $f (ReadBlob $y.id) }
            $fi = Get-Item -LiteralPath $f -Force
            $ix.entries[$p] = StatEntry $p $fi $y.id $y.mode
        } else {
            if ($ix.entries.ContainsKey($p)) { $ix.entries.Remove($p) }
            if (Test-Path -LiteralPath $f -PathType Leaf) { Remove-Item -LiteralPath $f -Force; PruneDirs (Split-Path $f -Parent) }
        }
    }
    WriteIndex $ix.entries
}
function Cmd-Checkout($a, [bool]$switch = $false) {
    $script:OPTARGS = @($a)
    $newb = Opt @('-b', '-c', '--create') $true
    $newbReset = Opt @('-B', '-C') $true
    $force = Opt @('-f', '--force')
    $det = Opt @('--detach')
    $quiet = Opt @('-q', '--quiet')
    $a = $script:OPTARGS
    $sd = SplitDashes $a
    if ($sd[1].Count -or ($sd[0].Count -gt 1 -and -not $switch)) {
        $src = $null; $paths = $sd[1]
        if ($sd[1].Count) { if ($sd[0].Count) { $src = $sd[0][0] } } else { $src = $sd[0][0]; $paths = $sd[0][1..($sd[0].Count - 1)] }
        Restore-Paths (Specs $paths) $src (-not $src) $true $true
        if (-not $sd[1].Count -and -not $quiet) { CheckoutCount $src }   # git counts only without '--'
        return
    }
    if ($newbReset) { $newb = $newbReset }
    $target = 'HEAD'; if ($sd[0].Count) { $target = $sd[0][0] }
    if (-not $newb -and -not $det -and $sd[0].Count -and -not (ReadRef "refs/heads/$target") -and -not $switch) {
        if (-not (Rev $target $true)) { if (Test-Path -LiteralPath (Full (Specs @($target))[0])) { Restore-Paths (Specs @($target)) $null $true $true $true; if (-not $quiet) { CheckoutCount $null }; return } }
    }
    $ix = ReadIndex
    if ($ix.unmerged.Count) { $l = ''; foreach ($k in (SortPaths @($ix.unmerged.Keys))) { $l += "${k}: needs merge`n" }; Die ($script:RAW + "error: you need to resolve your current index first`n" + $l) 1 }
    $head = HeadCommit
    $hr = HeadRef
    $isBranch = (-not $newb) -and (-not $det) -and [bool](ReadRef "refs/heads/$target")
    if ($switch -and -not $isBranch -and -not $newb -and -not $det) { Die "a branch is expected, got '$target'" }
    $tid = RevCommit $target
    if ($newb -and (ReadRef "refs/heads/$newb") -and -not $newbReset) { Die "A branch named '$newb' already exists." }
    if ($isBranch -and $hr -eq "refs/heads/$target") { Out-Err "Already on '$target'"; return }
    ApplyTree (CommitFiles $head) (CommitFiles $tid) $ix ([bool]$force) ([bool]$force)
    if ($newb) { UpdateRef "refs/heads/$newb" $tid; SetHead "refs/heads/$newb"; if (-not $quiet) { Out-Err "Switched to a new branch '$newb'" } }
    elseif ($isBranch) { SetHead "refs/heads/$target"; if (-not $quiet) { Out-Err "Switched to branch '$target'" } }
    else { SetHead $tid; if (-not $quiet) { Out-Err ("Note: switching to '$target'. You are in 'detached HEAD' state.`nHEAD is now at " + (Abbrev $tid) + ' ' + (Subject (ParseCommit $tid).message)) } }
}
function CheckoutCount([string]$src) {
    $n = $script:RESTORED; $w = 'paths'; if ($n -eq 1) { $w = 'path' }
    if ($src) { Out-Err "Updated $n $w from $(Abbrev (ParseCommit (RevCommit $src)).tree)" } else { Out-Err "Updated $n $w from the index" }
}
function Restore-Paths($specs, [string]$source, [bool]$fromIndex, [bool]$worktree, [bool]$staged = $false) {
    $script:RESTORED = 0
    $ix = ReadIndex
    if ($fromIndex) { $bad = ''; foreach ($k in (SortPaths @($ix.unmerged.Keys))) { if (SpecMatch $k $specs) { $bad += "error: path '$k' is unmerged`n" } }; if ($bad) { Die ($script:RAW + $bad) 1 } }
    if ($fromIndex) { $src = IndexMap $ix } else { $src = CommitFiles (RevCommit $source) }
    $hit = 0
    $cand = (NewMap); foreach ($k in $src.Keys) { $cand[$k] = 1 }; foreach ($k in $ix.entries.Keys) { $cand[$k] = 1 }
    foreach ($p in $cand.Keys) {
        if (-not (SpecMatch $p $specs)) { continue }
        $hit++
        $y = $src[$p]; $f = Full $p
        if ($staged -and -not $fromIndex) {
            if ($y) { $e = $ix.entries[$p]; $st = @{ path = $p; cs = 0; cns = 0; ms = 0; mns = 0; dev = 0; ino = 0; mode = $y.mode; uid = 0; gid = 0; size = 0; id = $y.id }; if ($e -and $e.id -eq $y.id) { $st = $e }; $ix.entries[$p] = $st }
            elseif ($ix.entries.ContainsKey($p)) { $ix.entries.Remove($p) }
        }
        if ($worktree) {
            if ($y) { if (-not (Test-Path -LiteralPath $f -PathType Leaf) -or (HashFile $f) -ne $y.id) { $script:RESTORED++ }; EnsureDir (Split-Path $f -Parent); Zl-WriteBytes $f (ReadBlob $y.id); if ($staged -or $fromIndex) { $fi = Get-Item -LiteralPath $f -Force; if ($ix.entries.ContainsKey($p) -and $ix.entries[$p].id -eq $y.id) { $ix.entries[$p] = StatEntry $p $fi $y.id $y.mode } } }
            elseif (Test-Path -LiteralPath $f -PathType Leaf) { Remove-Item -LiteralPath $f -Force }
        }
    }
    if (-not $hit) { Die "pathspec '$($specs -join ' ')' did not match any file(s) known to pgit" 1 }
    WriteIndex $ix.entries
}
function Cmd-Restore($a) {
    $script:OPTARGS = @($a)
    $staged = Opt @('-S', '--staged')
    $wt = Opt @('-W', '--worktree')
    $src = Opt @('-s', '--source') $true
    $a = $script:OPTARGS
    $sd = SplitDashes $a; $paths = $sd[0] + $sd[1]
    if (-not $paths.Count) { Die 'you must specify path(s) to restore' }
    $specs = Specs $paths
    if (-not $staged) { $wt = $true }
    if ($staged -and -not $src) { $src = 'HEAD' }
    if ($staged -and -not $wt) {
        $ix = ReadIndex; $hm = (NewMap); if (HeadCommit) { $hm = CommitFiles (RevCommit $src) }
        foreach ($p in @($ix.entries.Keys) + @($hm.Keys) | Select-Object -Unique) {
            if (-not (SpecMatch $p $specs)) { continue }
            $y = $hm[$p]
            if ($y) { $e = $ix.entries[$p]; if (-not ($e -and $e.id -eq $y.id)) { $ix.entries[$p] = @{ path = $p; cs = 0; cns = 0; ms = 0; mns = 0; dev = 0; ino = 0; mode = $y.mode; uid = 0; gid = 0; size = 0; id = $y.id } } }
            else { $ix.entries.Remove($p) }
        }
        WriteIndex $ix.entries; return
    }
    Restore-Paths $specs $src (-not $src) $true ([bool]$staged)
}
function ConflictMap($ix) {                            # the index as a path map, conflicted paths at their stage 2 (else 3, 1)
    $m = IndexMap $ix
    foreach ($k in $ix.unmerged.Keys) { foreach ($n in 2, 3, 1) { if ($ix.unmerged[$k].ContainsKey($n)) { $e = $ix.unmerged[$k][$n]; $m[$k] = @{ mode = $e.mode; id = $e.id }; break } } }
    return $m
}
function Cmd-Reset($a) {
    $script:OPTARGS = @($a)
    $hard = Opt @('--hard')
    $soft = Opt @('--soft')
    $null = Opt @('--mixed')
    $q = Opt @('-q', '--quiet')
    $a = $script:OPTARGS
    $sd = SplitDashes $a; $target = 'HEAD'; $paths = $sd[1]
    if ($sd[0].Count) { if (Rev $sd[0][0] $true) { $target = $sd[0][0]; if ($sd[0].Count -gt 1) { $paths += $sd[0][1..($sd[0].Count - 1)] } } else { $paths += $sd[0] } }
    if ($paths.Count) { Cmd-Restore (@('--staged', '--source', $target, '--') + $paths); return }
    $tid = RevCommit $target
    $hr = HeadRef; $head = HeadCommit
    $ix = ReadIndex
    if ($soft -and (MergeHead)) { Die 'Cannot do a soft reset in the middle of a merge.' }
    if ($hard) { ApplyTree (ConflictMap $ix) (CommitFiles $tid) $ix $true $true; $script:IXUM = (NewMap); $ix = ReadIndex; WriteIndex $ix.entries (NewMap) }
    elseif (-not $soft) {
        $m = CommitFiles $tid; $new = (NewMap)
        foreach ($p in $m.Keys) { $e = $ix.entries[$p]; if ($e -and $e.id -eq $m[$p].id) { $new[$p] = $e } else { $new[$p] = @{ path = $p; cs = 0; cns = 0; ms = 0; mns = 0; dev = 0; ino = 0; mode = $m[$p].mode; uid = 0; gid = 0; size = 0; id = $m[$p].id } } }
        WriteIndex $new (NewMap)
    }
    if (-not $soft) { ClearMergeState }
    if ($head) { WriteText (GitPath 'ORIG_HEAD') ($head + "`n") }
    if ($hr) { UpdateRef $hr $tid } else { SetHead $tid }
    if ($hard -and -not $q) { Out-Text ('HEAD is now at ' + (Abbrev $tid) + ' ' + (Subject (ParseCommit $tid).message)) }
    elseif (-not $hard -and -not $soft -and -not $q) {
        $d = StatusData
        $o = ''; foreach ($pr in $d.unstaged) { $o += $pr.st + "`t" + $pr.key + "`n" }
        if ($o) { Out-Text ("Unstaged changes after reset:`n" + $o) }
    }
}

$script:RAW = [string][char]1; $script:NONL = [string][char]2   # Die markers: no 'fatal: ' prefix / no final newline
function MergeWhat([string]$arg) {                     # how git names what is merged: branch / tag / remote-tracking branch / commit
    if (ReadRef "refs/heads/$arg") { return "branch '$arg'" }
    if (ReadRef "refs/tags/$arg") { return "tag '$arg'" }
    if (ReadRef "refs/remotes/$arg") { return "remote-tracking branch '$arg'" }
    return "commit '$arg'"
}
function MergeMsg([string]$arg) {
    $m = 'Merge ' + (MergeWhat $arg); $hr = HeadRef
    if ($hr) { $b = $hr.Substring(11); if ($b -cne 'main' -and $b -cne 'master') { $m += " into $b" } } else { $m += ' into HEAD' }
    return $m
}
function SameEnt($x, $y) { if (-not $x -and -not $y) { return $true }; if (-not $x -or -not $y) { return $false }; return ($x.id -eq $y.id -and $x.mode -eq $y.mode) }
# TreeMerge: three path maps -> @{ result (clean paths); wt (path -> @{mode; id} left in the worktree for conflicts); stages; msgs; conflicts }
function TreeMerge($bm, $om, $tm, [string]$name2, [string]$name1 = 'HEAD') {
    $all = (NewMap); foreach ($m in $bm, $om, $tm) { foreach ($k in $m.Keys) { $all[$k] = 1 } }
    $res = (NewMap); $wt = (NewMap); $stages = (NewMap); $msgs = @(); $conf = @()
    foreach ($p in (SortPaths @($all.Keys))) {
        $b = $bm[$p]; $o = $om[$p]; $t = $tm[$p]
        if (SameEnt $o $t) { if ($o) { $res[$p] = $o }; continue }
        if (SameEnt $b $o) { if ($t) { $res[$p] = $t }; continue }
        if (SameEnt $b $t) { if ($o) { $res[$p] = $o }; continue }
        $st = @{}
        if ($b) { $st[1] = $b }; if ($o) { $st[2] = $o }; if ($t) { $st[3] = $t }
        if ($o -and $t) {
            $kind = 'content'; if (-not $b) { $kind = 'add/add' }
            $bb = [byte[]]::new(0); if ($b) { $bb = ReadBlob $b.id }
            $ob = ReadBlob $o.id; $tb = ReadBlob $t.id
            $mode = $o.mode; if ($b -and $b.mode -eq $o.mode) { $mode = $t.mode }
            if ((IsBinary $bb) -or (IsBinary $ob) -or (IsBinary $tb)) {
                $msgs += "warning: Cannot merge binary files: $p ($name1 vs. $name2)"; $msgs += "Auto-merging $p"
                $msgs += "CONFLICT ($kind): Merge conflict in $p"; $wt[$p] = $o; $stages[$p] = $st; $conf += $p; continue
            }
            $msgs += "Auto-merging $p"
            $r = XMerge (Latin1 $bb) (Latin1 $ob) (Latin1 $tb) (L1Bytes $name1) (L1Bytes $name2)
            $id = WriteObject 'blob' (Latin1Bytes $r.text)
            if ($r.conflicts -gt 0) { $msgs += "CONFLICT ($kind): Merge conflict in $p"; $wt[$p] = @{ mode = $mode; id = $id }; $stages[$p] = $st; $conf += $p }
            else { $res[$p] = @{ mode = $mode; id = $id } }
            continue
        }
        if ($o) { $msgs += "CONFLICT (modify/delete): $p deleted in $name2 and modified in $name1.  Version $name1 of $p left in tree."; $wt[$p] = $o }
        else { $msgs += "CONFLICT (modify/delete): $p deleted in $name1 and modified in $name2.  Version $name2 of $p left in tree."; $wt[$p] = $t }
        $stages[$p] = $st; $conf += $p
    }
    $final = (NewMap); foreach ($k in $res.Keys) { $final[$k] = $res[$k] }; foreach ($k in $wt.Keys) { $final[$k] = $wt[$k] }
    foreach ($k in $final.Keys) { $q = $k; while ($q.Contains('/')) { $q = $q.Substring(0, $q.LastIndexOf('/')); if ($final.ContainsKey($q)) { Die "pgit cannot merge this: '$q' is a file on one side and a directory on the other. Merge on a machine with git (or GitLab), then bring the result back." } } }
    return @{ result = $res; wt = $wt; final = $final; stages = $stages; msgs = $msgs; conflicts = $conf }
}
function MergeLocalCheck($headMap, $final, $ix, [string]$verb) {   # refuse when the merge would overwrite local work (as git does)
    $dirty = @(); $untracked = @()
    foreach ($p in @($headMap.Keys) + @($final.Keys) | Select-Object -Unique) {
        if (SameEnt $headMap[$p] $final[$p]) { continue }
        $f = Full $p; $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        $e = $ix.entries[$p]
        if ($e) { if ($null -eq $fi) { if ($final[$p]) { $dirty += $p } } elseif (-not $fi.PSIsContainer -and -not (StatSame $e $fi $ix.mtime) -and (HashFile $f) -ne $e.id) { $dirty += $p } }
        elseif ($fi -and -not $fi.PSIsContainer -and $final[$p]) { if ((HashFile $f) -ne $final[$p].id) { $untracked += $p } }
    }
    if ($dirty.Count) { Die ($script:RAW + "error: Your local changes to the following files would be overwritten by ${verb}:`n" + ((SortPaths $dirty | ForEach-Object { "`t" + $_ }) -join "`n") + "`nPlease commit your changes or stash them before you ${verb}.`nAborting`n") }
    if ($untracked.Count) { Die ($script:RAW + "error: The following untracked working tree files would be overwritten by ${verb}:`n" + ((SortPaths $untracked | ForEach-Object { "`t" + $_ }) -join "`n") + "`nPlease move or remove them before you ${verb}.`nAborting`n") }
}
function ApplyMergeResult($headMap, $tm) {             # worktree and index to the merge result; conflict paths get stages 1-3
    $ix = ReadIndex
    ApplyTree $headMap $tm.final $ix $true $false
    $ix = ReadIndex
    $um = (NewMap)
    foreach ($p in $tm.stages.Keys) {
        $um[$p] = @{}
        foreach ($stg in $tm.stages[$p].Keys) { $x = $tm.stages[$p][$stg]; $um[$p][$stg] = @{ path = $p; cs = 0; cns = 0; ms = 0; mns = 0; dev = 0; ino = 0; mode = $x.mode; uid = 0; gid = 0; size = 0; id = $x.id } }
        if ($ix.entries.ContainsKey($p)) { $ix.entries.Remove($p) }
    }
    WriteIndex $ix.entries $um
}
function UnmergedCheck([string]$verb) {
    $ix = ReadIndex
    if ($ix.unmerged.Count) { Die ($script:RAW + "error: $verb is not possible because you have unmerged files.`nhint: Fix them up in the work tree, and then use 'pgit add/rm <file>'`nhint: as appropriate to mark resolution and make a commit.`nfatal: Exiting because of an unresolved conflict.`n") }
}
function Cmd-Merge($a) {
    $script:OPTARGS = @($a)
    $ffOnly = Opt @('--ff-only'); $null = Opt @('--ff'); $noFf = Opt @('--no-ff')
    $noCommit = Opt @('--no-commit'); $null = Opt @('--commit'); $null = Opt @('--no-edit'); $null = Opt @('-e', '--edit')
    $abort = Opt @('--abort'); $cont = Opt @('--continue'); $quiet = Opt @('-q', '--quiet')
    $msg = Opt @('-m', '--message') $true
    $a = $script:OPTARGS
    if ($abort) {
        if (-not (MergeHead)) { Die 'There is no merge to abort (MERGE_HEAD missing).' }
        $ix = ReadIndex; $head = HeadCommit
        ApplyTree (ConflictMap $ix) (CommitFiles $head) $ix $true $true
        $script:IXUM = (NewMap); $ix = ReadIndex; WriteIndex $ix.entries (NewMap)
        ClearMergeState; return
    }
    if ($cont) {
        if (-not (MergeHead)) { Die 'There is no merge in progress (MERGE_HEAD missing).' }
        Cmd-Commit @('--no-edit'); return
    }
    if (-not $a.Count) { Die 'No remote for the current branch.' }
    UnmergedCheck 'Merging'
    if (MergeHead) { Die "You have not concluded your merge (MERGE_HEAD exists).`nPlease, commit your changes before you merge." }
    $arg = $a[0]
    $tid = $null; $rid = Rev $arg $true; if ($rid) { $tid = PeelTo $rid 'commit' }
    if (-not $tid) { Out-Err "merge: $arg - not something we can merge"; $script:RC = 1; return }
    $head = HeadCommit
    if (-not $head) {                                 # unborn branch: take theirs
        $ix = ReadIndex; ApplyTree (NewMap) (CommitFiles $tid) $ix $false $false
        $hr = HeadRef; UpdateRef $hr $tid; return
    }
    if ($head -eq $tid) { if (-not $quiet) { Out-Text 'Already up to date.' }; return }
    $bases = MergeBases $head $tid
    if ($bases -contains $tid) { if (-not $quiet) { Out-Text 'Already up to date.' }; return }
    WriteText (GitPath 'ORIG_HEAD') ($head + "`n")
    if (($bases -contains $head) -and -not $noFf) {   # fast-forward
        $ix = ReadIndex
        ApplyTree (CommitFiles $head) (CommitFiles $tid) $ix $false $false
        $hr = HeadRef; if ($hr) { UpdateRef $hr $tid } else { SetHead $tid }
        if ($quiet) { return }
        $prs = DiffMaps (CommitFiles $head) (CommitFiles $tid) @() $true $null
        $sm = (Summary $prs); $sm = $sm.Substring($sm.IndexOf("`n") + 1)
        Out-Text ('Updating ' + (Abbrev $head) + '..' + (Abbrev $tid) + "`nFast-forward`n" + (DiffStat $prs) + $sm); return
    }
    if ($ffOnly) { Die 'Not possible to fast-forward, aborting.' }
    if ($bases.Count -gt 1) { Die "pgit cannot merge this: the two histories have $($bases.Count) merge bases (a criss-cross merge). Merge on a machine with git (or GitLab), then bring the result back." }
    $ix = ReadIndex; $hm = CommitFiles $head
    $staged = @(); foreach ($pr in (DiffMaps $hm (IndexMap $ix) @() $false $null)) { $staged += $pr.key }
    if ($staged.Count) { Die ($script:RAW + $script:NONL + "Your local changes to the following files would be overwritten by merge:`n" + ((SortPaths $staged | ForEach-Object { '  ' + $_ }) -join "`n")) }
    $bm = (NewMap); if ($bases.Count) { $bm = CommitFiles $bases[0] }
    $tm = TreeMerge $bm $hm (CommitFiles $tid) $arg
    MergeLocalCheck $hm $tm.final $ix 'merge'
    if (-not $msg) { $msg = MergeMsg $arg }
    ApplyMergeResult $hm $tm
    if (-not $quiet) { foreach ($l in $tm.msgs) { if ($l.StartsWith('warning: ')) { Out-Err $l } else { Out-Text $l } } }
    WriteText (GitPath 'MERGE_HEAD') ($tid + "`n")
    $mode = ''; if ($noFf) { $mode = 'no-ff' }; WriteText (GitPath 'MERGE_MODE') $mode
    WriteText (GitPath 'AUTO_MERGE') ((WriteTreeFromMap $tm.final) + "`n")
    if ($tm.conflicts.Count) {
        $mm = $msg + "`n`n# Conflicts:`n"; foreach ($c in $tm.conflicts) { $mm += "#`t$c`n" }
        WriteText (GitPath 'MERGE_MSG') $mm
        Out-Text 'Automatic merge failed; fix conflicts and then commit the result.'; $script:RC = 1; return
    }
    WriteText (GitPath 'MERGE_MSG') ($msg + "`n")
    if ($noCommit) { Out-Err 'Automatic merge went well; stopped before committing as requested'; return }
    $tree = WriteTreeFromMap $tm.final
    $t = "tree $tree`nparent $head`nparent $tid`nauthor $(Ident 'AUTHOR')`ncommitter $(Ident 'COMMITTER')`n`n" + (CleanMessage $msg)
    $id = WriteObject 'commit' (Zl-Utf8Enc $t)
    $hr = HeadRef; if ($hr) { UpdateRef $hr $id } else { SetHead $id }
    ClearMergeState
    if ($quiet) { return }
    $prs = DiffMaps $hm (FlattenTree $tree) @() $true $null
    $sm = (Summary $prs); $sm = $sm.Substring($sm.IndexOf("`n") + 1)
    Out-Text ("Merge made by the 'ort' strategy.`n" + (DiffStat $prs) + $sm)
}

function Cmd-RevParse($a) {
    $o = ''
    $short = $false; $abbrevRef = $false; $verify = $false; $q = $false
    foreach ($x in $a) {
        switch -CaseSensitive ($x) {
            '--show-toplevel' { $o += $script:ROOT.Replace('\', '/') + "`n"; continue }
            '--git-dir' { $o += ($script:GITDIR.Replace('\', '/')) + "`n"; continue }
            '--is-inside-work-tree' { $o += "true`n"; continue }
            '--short' { $short = $true; continue }
            '--abbrev-ref' { $abbrevRef = $true; continue }
            '--verify' { $verify = $true; continue }
            '-q' { $q = $true; continue }
            '--quiet' { $q = $true; continue }
            default {
                if ($x -match '^--short=(\d+)$') { $short = [int]$Matches[1]; continue }
                if ($abbrevRef) { if ($x -eq 'HEAD') { $hr = HeadRef; if ($hr) { $o += $hr.Substring(11) + "`n" } else { $o += "HEAD`n" } } else { $o += $x + "`n" }; continue }
                $id = Rev $x $true
                if (-not $id) { if ($q) { $script:RC = 1; continue }; Out-Err ("fatal: ambiguous argument '$x': unknown revision or path not in the working tree.`nUse '--' to separate paths from revisions, like this:`n'git <command> [<revision>...] -- [<file>...]'"); Out-Text $x; $script:RC = 128; return }
                if ($short) { $n = 7; if ($short -is [int]) { $n = $short }; $o += (Abbrev $id $n) + "`n" } else { $o += $id + "`n" }
            }
        }
    }
    Out-Text $o
}
function Cmd-CatFile($a) {
    $script:OPTARGS = @($a)
    $t = Opt @('-t'); $p = Opt @('-p'); $s = Opt @('-s'); $e = Opt @('-e')
    $a = $script:OPTARGS
    if (-not $a.Count) { Die 'usage: pgit cat-file (-t | -s | -p | -e) <object>' 129 }
    $spec = $a[$a.Count - 1]
    if ($e) { if (Rev $spec $true) { return }; $script:RC = 1; return }
    $id = Rev $spec
    $o = ReadObject $id
    if ($t) { Out-Text $o.type; return }
    if ($s) { Out-Text ([string]$o.body.Length); return }
    if ($p) {
        if ($o.type -eq 'tree') { $out = ''; foreach ($x in (ParseTree $id)) { $ty = 'blob'; if ($x.tree) { $ty = 'tree' } elseif ($x.mode -eq '160000') { $ty = 'commit' }; $out += $x.mode.PadLeft(6, '0') + " $ty " + $x.id + "`t" + (QuotePath $x.name) + "`n" }; Out-Text $out; return }
        Out-Text (L1ToText (Latin1 $o.body)); return
    }
    if ($a.Count -ge 2) { $o2 = ReadObject (Rev $a[1]); Out-Text (L1ToText (Latin1 $o2.body)); return }
    Die 'usage: pgit cat-file (-t | -s | -p | -e) <object>' 129
}
function Cmd-LsFiles($a) {
    $script:OPTARGS = @($a)
    $s = Opt @('-s', '--stage')
    $a = $script:OPTARGS
    $specs = Specs $a
    $ix = ReadIndex; $o = ''
    $keys = (NewMap); foreach ($k in $ix.entries.Keys) { $keys[$k] = 1 }; foreach ($k in $ix.unmerged.Keys) { $keys[$k] = 1 }
    foreach ($p in (SortPaths @($keys.Keys))) {
        if (-not (SpecMatch $p $specs)) { continue }
        $rows = @(); if ($ix.entries.ContainsKey($p)) { $rows += , @(0, $ix.entries[$p]) } else { foreach ($n in 1, 2, 3) { if ($ix.unmerged[$p].ContainsKey($n)) { $rows += , @($n, $ix.unmerged[$p][$n]) } } }
        foreach ($r in $rows) { $e = $r[1]; if ($s) { $o += (ModeStr $e.mode) + ' ' + $e.id + ' ' + $r[0] + "`t" + (QuotePath (RelOut $p)) + "`n" } else { $o += (QuotePath (RelOut $p)) + "`n" } }
    }
    Out-Text $o
}
function Cmd-LsTree($a) {
    $script:OPTARGS = @($a)
    $r = Opt @('-r'); $t = Opt @('-t'); $n = Opt @('--name-only', '--name-status')
    $a = $script:OPTARGS
    if (-not $a.Count) { Die 'usage: pgit ls-tree [-r] [-t] [--name-only] <tree-ish> [<path>...]' 129 }
    $tid = PeelTo (Rev $a[0]) 'tree'
    $paths = @(); if ($a.Count -gt 1) { $paths = $a[1..($a.Count - 1)] }
    $o = ''
    $stack = @(, @($tid, ''))
    $rows = @()
    $walk = { param($id, $pre) foreach ($e in (ParseTree $id)) { $p = $e.name; if ($pre) { $p = $pre + '/' + $e.name }; $ty = 'blob'; if ($e.tree) { $ty = 'tree' } elseif ($e.mode -eq '160000') { $ty = 'commit' }
            if ($paths.Count -and -not ($paths | Where-Object { $p -ceq $_ -or $p.StartsWith($_ + '/') -or $_.StartsWith($p + '/') })) { continue }
            if ($e.tree -and ($r -or ($paths | Where-Object { $_.StartsWith($p + '/') }))) { if ($t) { $script:LSROWS += , @($e.mode, $ty, $e.id, $p) }; & $walk $e.id $p } else { $script:LSROWS += , @($e.mode, $ty, $e.id, $p) } } }
    $script:LSROWS = @()
    & $walk $tid ''
    foreach ($x in $script:LSROWS) { if ($n) { $o += (QuotePath $x[3]) + "`n" } else { $o += $x[0].PadLeft(6, '0') + ' ' + $x[1] + ' ' + $x[2] + "`t" + (QuotePath $x[3]) + "`n" } }
    Out-Text $o
}
function Cmd-HashObject($a) { $w = Opt @('-w'); foreach ($f in $a) { $b = Zl-ReadBytes $f; if ($w) { Out-Text (WriteObject 'blob' $b) } else { Out-Text (HashObject 'blob' $b).id } } }
    $script:OPTARGS = @($a)
    $a = $script:OPTARGS
function Cmd-Config($a) {
    $script:OPTARGS = @($a)
    $glob = Opt @('--global')
    $list = Opt @('-l', '--list')
    $unset = Opt @('--unset')
    $get = Opt @('--get')
    $a = $script:OPTARGS
    $file = GitPath 'config'
    if ($glob) { $h = $env:USERPROFILE; if (-not $h) { $h = $env:HOME }; $file = $h + '\.gitconfig' }
    if ($list) { $o = ''; $fs = ConfigFiles; if ($glob) { $fs = @($file) }; foreach ($f in $fs) { foreach ($e in (ParseConfig $f)) { $o += $e.key + '=' + $e.value + "`n" } }; Out-Text $o; return }
    if ($unset) { SetConfig $a[0] '' $file $true; return }
    if ($a.Count -eq 1) { $v = $null; if ($glob) { foreach ($e in (ParseConfig $file)) { if ($e.key -ceq (ConfigKey $a[0])) { $v = $e.value } } } else { $v = GetConfig $a[0] }; if ($null -eq $v) { $script:RC = 1; return }; Out-Text $v; return }
    if ($a.Count -ge 2) { SetConfig $a[0] (($a[1..($a.Count - 1)]) -join ' ') $file; return }
    Die 'usage: pgit config [--global] <name> [<value>] | --list | --unset <name>' 129
}
function Cmd-Fsck($a) {
    $bad = 0; $n = 0
    foreach ($d in (Get-ChildItem -LiteralPath ($script:GITDIR + '\objects') -Directory | Where-Object { $_.Name -match '^[0-9a-f]{2}$' })) {
        foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File)) {
            $id = $d.Name + $f.Name; $n++
            try { $raw = Zl-Unzlib (Zl-ReadBytes $f.FullName); $got = Sha1Hex $raw; if ($got -ne $id) { Out-Text "error: ${id}: hash mismatch ($got)"; $bad++ } } catch { Out-Text "error: ${id}: $($_.Exception.Message)"; $bad++ }
        }
    }
    $packFiles = @(Get-ChildItem -LiteralPath ($script:GITDIR + '\objects\pack') -Filter '*.pack' -ErrorAction SilentlyContinue)
    Out-Text "checked $n loose objects, $bad bad" ; if ($packFiles.Count) { Out-Text "note: $($packFiles.Count) pack file(s) not checked (pgit reads packs but checks loose objects only)" }
    if ($bad) { $script:RC = 1 }
}

# ---------------------------------------------------------------- remotes: folders and shares (no network; git's file:// semantics)
function RemoteGitDir([string]$url) {                 # a remote URL (a folder, a UNC share, a .bundle file) -> its git directory, 'bundle:FILE', or $null
    $p = $url; if ($p.StartsWith('file://')) { $p = $p.Substring(7) }
    $p = $p.Replace('/', '\')
    if (Test-Path -LiteralPath $p -PathType Leaf) { $h = Latin1 (Slice (Zl-ReadBytes $p) 0 16); if ($h -ceq '# v2 git bundle' + "`n" -or $h -ceq '# v3 git bundle' + "`n") { return ('bundle:' + (Resolve-Path -LiteralPath $p).Path) } }
    foreach ($c in @($p, ($p + '.git'))) {
        if ((Test-Path -LiteralPath ($c + '\HEAD') -PathType Leaf) -and (Test-Path -LiteralPath ($c + '\objects') -PathType Container)) { return (Resolve-Path -LiteralPath $c).Path.TrimEnd('\') }
        if (Test-Path -LiteralPath ($c + '\.git\HEAD') -PathType Leaf) { return ((Resolve-Path -LiteralPath $c).Path.TrimEnd('\') + '\.git') }
    }
    return $null
}
function UrlOf([string]$path) {                      # as git records a local URL: absolute, not normalized; forward slashes (no config escapes)
    $p = $path.Replace('/', '\')
    if (-not ($p -match '^[A-Za-z]:\\' -or $p.StartsWith('\\'))) { $p = (Get-Location).Path.TrimEnd('\') + '\' + $p }
    return $p.TrimEnd('\').Replace('\', '/')
}
function ShowUrl([string]$url) { $u = $url.TrimEnd('/'); if ($u.EndsWith('/.git')) { $u = $u.Substring(0, $u.Length - 5) } elseif ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }; return $u }
function GdRefs([string]$gd) {                        # every ref of another repository: loose + packed (refs/heads, refs/tags)
    $m = (NewMap)
    if ($gd.StartsWith('bundle:')) { $bd = BundleRead $gd.Substring(7); foreach ($k in $bd.order) { if ($k.StartsWith('refs/heads/') -or $k.StartsWith('refs/tags/')) { $m[$k] = $bd.refs[$k] } }; return $m }
    $t = ReadText ($gd + '\packed-refs')
    if ($t) { foreach ($l in ($t -split "`n")) { if ($l -eq '' -or $l.StartsWith('#') -or $l.StartsWith('^')) { continue }; $sp = $l.IndexOf(' '); if ($sp -gt 0) { $m[$l.Substring($sp + 1).Trim()] = $l.Substring(0, $sp) } } }
    foreach ($pre in 'refs\heads', 'refs\tags') {
        $base = $gd + '\' + $pre
        if (Test-Path -LiteralPath $base) { foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) { $m[$f.FullName.Substring($gd.Length + 1).Replace('\', '/')] = (ReadText $f.FullName).Trim() } }
    }
    return $m
}
function GdHead([string]$gd) {
    if ($gd.StartsWith('bundle:')) {                   # a bundle's HEAD: the branch it points at (main, master first)
        $bd = BundleRead $gd.Substring(7); if (-not $bd.refs.ContainsKey('HEAD')) { return $null }
        foreach ($k in @('refs/heads/main', 'refs/heads/master') + @($bd.order)) { if ($k.StartsWith('refs/heads/') -and $bd.refs[$k] -eq $bd.refs['HEAD']) { return $k } }
        return $null
    }
    $t = ReadText ($gd + '\HEAD'); if ($t -and $t.Trim().StartsWith('ref: ')) { return $t.Trim().Substring(5) }; return $null }
function GdObjPath([string]$gd, [string]$id) { return ($gd + '\objects\' + $id.Substring(0, 2) + '\' + $id.Substring(2)) }
function GdHas([string]$gd, [string]$id) { return ((Test-Path -LiteralPath (GdObjPath $gd $id) -PathType Leaf) -or (PackHas $gd $id)) }
function GdRead([string]$gd, [string]$id) {          # loose or packed; -> @{ type; body }
    $o = GdObject $gd $id
    if ($null -eq $o) { Die "object $id is missing from $gd" }
    return $o
}
function CopyObjects([string]$from, [string]$to, $wants) {   # copy what $to lacks of everything reachable from $wants; returns the count
    if ($from.StartsWith('bundle:')) { $bd = BundleRead $from.Substring(7); foreach ($q in $bd.prereq) { if (-not (GdHas $to $q)) { Die "the bundle needs commit $q, which this repository does not have" } }; return (UnpackPack $bd.bytes $bd.packAt $to) }
    if ($to.StartsWith('bundle:')) { Die 'a bundle is read-only: make a new one with pgit bundle create' }
    $st = @($wants | Where-Object { $_ }); $seen = (NewMap); $n = 0
    while ($st.Count) {
        $id = $st[$st.Count - 1]; if ($st.Count -eq 1) { $st = @() } else { $st = $st[0..($st.Count - 2)] }
        if ($seen.ContainsKey($id)) { continue }; $seen[$id] = 1
        if (GdHas $to $id) { continue }                 # present: so is everything it reaches (git's connectivity rule)
        $o = GdRead $from $id
        $dst = GdObjPath $to $id; EnsureDir (Split-Path $dst -Parent)
        $lp = GdObjPath $from $id; if (Test-Path -LiteralPath $lp -PathType Leaf) { Zl-WriteBytes $dst (Zl-ReadBytes $lp) } else { Zl-WriteBytes $dst (Zl-Zlib (HashObject $o.type $o.body).full) }; $n++
        if ($o.type -eq 'commit') {
            foreach ($l in ((Latin1 $o.body) -split "`n")) { if ($l -eq '') { break }; if ($l.StartsWith('tree ') -or $l.StartsWith('parent ')) { $st += $l.Substring($l.IndexOf(' ') + 1) } }
        } elseif ($o.type -eq 'tag') {
            $l = ((Latin1 $o.body) -split "`n")[0]; if ($l.StartsWith('object ')) { $st += $l.Substring(7) }
        } elseif ($o.type -eq 'tree') {
            $b = $o.body; $q = 0
            while ($q -lt $b.Length) {
                $sp = [Array]::IndexOf($b, [byte]32, $q); $z = [Array]::IndexOf($b, [byte]0, $sp)
                $mode = Latin1 (Slice $b $q ($sp - $q)); $cid = Hex $b ($z + 1) 20
                if ($mode -ne '160000') { $st += $cid }
                $q = $z + 21
            }
        }
    }
    return $n
}
function GdAncestor([string]$gd, [string]$anc, [string]$tip) {   # is $anc reachable from $tip in $gd?
    $st = @($tip); $seen = (NewMap)
    while ($st.Count) {
        $id = $st[$st.Count - 1]; if ($st.Count -eq 1) { $st = @() } else { $st = $st[0..($st.Count - 2)] }
        if ($id -eq $anc) { return $true }
        if ($seen.ContainsKey($id) -or -not (GdHas $gd $id)) { continue }; $seen[$id] = 1
        $o = GdRead $gd $id; if ($o.type -ne 'commit') { continue }
        foreach ($l in ((Latin1 $o.body) -split "`n")) { if ($l -eq '') { break }; if ($l.StartsWith('parent ')) { $st += $l.Substring(7) } }
    }
    return $false
}
function GdPeel([string]$gd, [string]$id) { for ($k = 0; $k -lt 10; $k++) { if (-not (GdHas $gd $id)) { return $id }; $o = GdRead $gd $id; if ($o.type -ne 'tag') { return $id }; $id = ((Latin1 $o.body) -split "`n")[0].Substring(7) }; return $id }
function RemoteUrl([string]$name) { $u = GetConfig "remote.$name.url"; if (-not $u) { Die "'$name' does not appear to be a git repository`nfatal: Could not read from remote repository.`n`nPlease make sure you have the correct access rights`nand the repository exists." }; return $u }
function RemoteDir([string]$name, [string]$url) { $gd = RemoteGitDir $url; if (-not $gd) { Die "'$url' does not appear to be a git repository`nfatal: Could not read from remote repository.`n`nPlease make sure you have the correct access rights`nand the repository exists." }; return $gd }
function Upstream([string]$branch) {                   # @{ remote; merge (refs/heads/x); track (refs/remotes/r/x) } or $null
    $r = GetConfig "branch.$branch.remote"; $m = GetConfig "branch.$branch.merge"
    if (-not $r -or -not $m) { return $null }
    $short = $m; if ($m.StartsWith('refs/heads/')) { $short = $m.Substring(11) }
    return @{ remote = $r; merge = $m; short = $short; track = "refs/remotes/$r/$short" }
}
function RemoveConfigSection([string]$file, [string]$secKey) {
    $t = ReadText $file; if ($null -eq $t) { return }
    $out = @(); $skip = $false
    foreach ($l in ($t -split "`n")) {
        $s = [regex]::Match($l.Trim(), '^\[\s*([A-Za-z0-9.-]+)(?:\s+"(.*)")?\s*\]$')
        if ($s.Success) { $k = $s.Groups[1].Value.ToLower(); if ($s.Groups[2].Success) { $k += '.' + $s.Groups[2].Value }; $skip = ($k -ceq $secKey) }
        if (-not $skip) { $out += $l }
    }
    while ($out.Count -and $out[$out.Count - 1] -eq '') { if ($out.Count -eq 1) { $out = @() } else { $out = @($out[0..($out.Count - 2)]) } }
    WriteText $file (($out -join "`n") + "`n")
}
function Cmd-Remote($a) {
    $script:OPTARGS = @($a); $v = Opt @('-v', '--verbose'); $a = $script:OPTARGS
    $names = @(); foreach ($e in (ParseConfig (GitPath 'config'))) { if ($e.key -match '^remote\.(.+)\.url$') { $names += $Matches[1] } }
    $names = SortOrd $names
    if (-not $a.Count) { $o = ''; foreach ($n in $names) { if ($v) { $u = GetConfig "remote.$n.url"; $o += "$n`t$u (fetch)`n$n`t$u (push)`n" } else { $o += "$n`n" } }; Out-Text $o; return }
    switch ($a[0]) {
        'add' {
            if ($a.Count -lt 3) { Die 'usage: pgit remote add <name> <url>' 129 }
            $n = $a[1]; if ($names -contains $n) { Die "remote $n already exists." 3 }
            $u = $a[2].Replace('\', '/')                      # as typed, as git keeps it
            SetConfig "remote.$n.url" $u (GitPath 'config'); SetConfig "remote.$n.fetch" "+refs/heads/*:refs/remotes/$n/*" (GitPath 'config')
        }
        { $_ -eq 'remove' -or $_ -eq 'rm' } {
            $n = $a[1]; if ($names -notcontains $n) { Die "No such remote: '$n'" 2 }
            RemoveConfigSection (GitPath 'config') "remote.$n"
            foreach ($k in @((ListRefs "refs/remotes/$n/").Keys)) { DeleteRef $k }
            $d = GitPath "refs/remotes/$n"; if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
            foreach ($e in (ParseConfig (GitPath 'config'))) { if ($e.key -match '^branch\.(.+)\.remote$' -and $e.value -ceq $n) { $b = $Matches[1]; SetConfig "branch.$b.remote" '' (GitPath 'config') $true; SetConfig "branch.$b.merge" '' (GitPath 'config') $true } }
        }
        'get-url' { Out-Text (RemoteUrl $a[1]) }
        'set-url' { $null = RemoteUrl $a[1]; $u = $a[2].Replace('\', '/'); SetConfig "remote.$($a[1]).url" $u (GitPath 'config') }
        default { Die "unknown subcommand: $($a[0])" 129 }
    }
}
function FetchLine([string]$flag, [string]$summary, [string]$from, [string]$to, [int]$w, [string]$why = '') {
    $l = ' ' + $flag + ' ' + $summary.PadRight(17) + ' ' + $from.PadRight($w) + ' -> ' + $to; if ($why) { $l += '  ' + $why }; return $l
}
function DoFetch([string]$name, [bool]$quiet) {        # -> @{ url; updated (ref -> id) }
    $url = RemoteUrl $name; $gd = RemoteDir $name $url
    $rr = GdRefs $gd
    $heads = SortPaths @($rr.Keys | Where-Object { $_.StartsWith('refs/heads/') })
    $wants = @(); foreach ($k in $heads) { $wants += $rr[$k] }
    $null = CopyObjects $gd $script:GITDIR $wants
    $lines = @(); $fh = @(); $fhm = @()
    $hr = HeadRef; $up = $null; if ($hr) { $up = Upstream $hr.Substring(11) }
    foreach ($k in $heads) {
        $b = $k.Substring(11); $loc = "refs/remotes/$name/$b"; $old = ReadRef $loc; $new = $rr[$k]
        $desc = "branch '$b' of $(ShowUrl $url)"
        if ($up -and $up.remote -ceq $name -and $up.merge -ceq $k) { $fhm += "$new`t`t$desc" } else { $fh += "$new`tnot-for-merge`t$desc" }
        if ($old -eq $new) { continue }
        if (-not $old) { $lines += , @('*', '[new branch]', $b, "$name/$b", '') }
        elseif ((MergeBases $old $new) -contains $old) { $lines += , @(' ', ((Abbrev $old) + '..' + (Abbrev $new)), $b, "$name/$b", '') }
        else { $lines += , @('+', ((Abbrev $old) + '...' + (Abbrev $new)), $b, "$name/$b", '(forced update)') }
        UpdateRef $loc $new
    }
    foreach ($k in (SortPaths @($rr.Keys | Where-Object { $_.StartsWith('refs/tags/') }))) {   # tags that point into what we have
        $t = $k.Substring(10); if (ReadRef $k) { continue }
        $target = GdPeel $gd $rr[$k]
        if (-not (HasObject $target)) { continue }
        $null = CopyObjects $gd $script:GITDIR @($rr[$k]); UpdateRef $k $rr[$k]
        $lines += , @('*', '[new tag]', $t, $t, ''); $fh += "$($rr[$k])`tnot-for-merge`ttag '$t' of $(ShowUrl $url)"
    }
    WriteText (GitPath 'FETCH_HEAD') ((@($fhm) + @($fh) | ForEach-Object { $_ + "`n" }) -join '')
    if ($lines.Count -and -not $quiet) {
        $w = 10; foreach ($l in $lines) { if ($l[2].Length -gt $w) { $w = $l[2].Length } }
        $o = 'From ' + (ShowUrl $url) + "`n"; foreach ($l in $lines) { $o += (FetchLine $l[0] $l[1] $l[2] $l[3] $w $l[4]) + "`n" }
        Out-Err $o
    }
    return @{ url = $url }
}
function Cmd-Fetch($a) {
    $script:OPTARGS = @($a); $q = Opt @('-q', '--quiet'); $all = Opt @('--all'); $null = Opt @('--tags'); $null = Opt @('-p', '--prune'); $a = $script:OPTARGS
    $names = @()
    if ($all) { foreach ($e in (ParseConfig (GitPath 'config'))) { if ($e.key -match '^remote\.(.+)\.url$') { $names += $Matches[1] } } }
    elseif ($a.Count) { $names = @($a[0]) }
    else { $hr = HeadRef; $up = $null; if ($hr) { $up = Upstream $hr.Substring(11) }; if ($up) { $names = @($up.remote) } else { $names = @('origin') } }
    foreach ($n in $names) { $null = DoFetch $n ([bool]$q) }
}
function Cmd-Pull($a) {
    $script:OPTARGS = @($a); $q = Opt @('-q', '--quiet'); $ffOnly = Opt @('--ff-only'); $noReb = Opt @('--no-rebase'); $reb = Opt @('-r', '--rebase'); $noFf = Opt @('--no-ff'); $a = $script:OPTARGS
    if ($reb -or (GetConfig 'pull.rebase') -eq 'true') { Die 'pgit cannot rebase. Use pgit pull --no-rebase (a merge), or rebase on a machine with git.' }
    $hr = HeadRef; if (-not $hr) { Die "You are not currently on a branch.`nPlease specify which branch you want to merge with." }
    $br = $hr.Substring(11); $up = Upstream $br
    if ($a.Count) { $rem = $a[0]; $mb = $br; if ($a.Count -gt 1) { $mb = $a[1] }; $track = "refs/remotes/$rem/$mb" }
    elseif ($up) { $rem = $up.remote; $mb = $up.short; $track = $up.track }
    else { Die ($script:RAW + "There is no tracking information for the current branch.`nPlease specify which branch you want to merge with.`nSee git-pull(1) for details.`n`n    pgit pull <remote> <branch>`n`nIf you wish to set tracking information for this branch you can do so with:`n`n    pgit branch --set-upstream-to=origin/<branch> $br`n") 1 }
    $f = DoFetch $rem ([bool]$q)
    $tid = ReadRef $track
    if (-not $tid) { Die "couldn't find remote ref $mb" 1 }
    $head = HeadCommit
    $msg = "Merge branch '$mb' of $(ShowUrl $f.url)"; if ($br -cne 'main' -and $br -cne 'master') { $msg += " into $br" }
    if ($head) {
        $bases = MergeBases $head $tid
        $diverged = -not ($bases -contains $head) -and -not ($bases -contains $tid)
        $ffc = GetConfig 'pull.ff'
        if ($diverged -and ($ffOnly -or $ffc -eq 'only')) { Die 'Not possible to fast-forward, aborting.' }
        if ($diverged -and -not $noReb -and -not $noFf -and $null -eq (GetConfig 'pull.rebase') -and -not $ffc) {
            Die ($script:RAW + "hint: You have divergent branches and need to specify how to reconcile them.`nhint: You can do so by running one of the following commands sometime before`nhint: your next pull:`nhint: `nhint:   pgit config pull.rebase false  # merge (the default strategy)`nhint:   pgit config pull.rebase true   # rebase`nhint:   pgit config pull.ff only       # fast-forward only`nhint: `nhint: You can replace ""pgit config"" with ""pgit config --global"" to set a default`nhint: preference for all repositories. You can also pass --rebase, --no-rebase,`nhint: or --ff-only on the command line to override the configured default per`nhint: invocation.`nfatal: Need to specify how to reconcile divergent branches.`n")
        }
    }
    $ma = @('-m', $msg); if ($q) { $ma += '-q' }; if ($noFf) { $ma += '--no-ff' }
    Cmd-Merge ($ma + @($tid))
}
function Cmd-Push($a) {
    $script:OPTARGS = @($a); $u = Opt @('-u', '--set-upstream'); $force = Opt @('-f', '--force'); $tags = Opt @('--tags'); $q = Opt @('-q', '--quiet'); $del = Opt @('-d', '--delete'); $a = $script:OPTARGS
    $hr = HeadRef; $br = $null; if ($hr) { $br = $hr.Substring(11) }
    $up = $null; if ($br) { $up = Upstream $br }
    $rem = 'origin'; if ($a.Count) { $rem = $a[0] } elseif ($up) { $rem = $up.remote }
    $url = RemoteUrl $rem; $gd = RemoteDir $rem $url
    $specs = @()
    if ($a.Count -gt 1) { foreach ($x in $a[1..($a.Count - 1)]) { if ($x.Contains(':')) { $specs += , @($x.Split(':')[0], $x.Split(':')[1]) } else { $specs += , @($x, $x) } } }
    elseif (-not $tags) {
        if (-not $br) { Die "You are not currently on a branch.`nTo push the history leading to the current (detached HEAD)`nstate now, use`n`n    pgit push $rem HEAD:<name-of-remote-branch>`n" }
        if ($up -and $up.remote -ceq $rem) { $specs += , @($br, $up.short) }
        elseif ($u -or ($up -and $up.remote -cne $rem)) { $specs += , @($br, $br) }
        else { Die "The current branch $br has no upstream branch.`nTo push the current branch and set the remote as upstream, use`n`n    pgit push --set-upstream $rem $br`n`n" }
    }
    $rr = GdRefs $gd
    $lines = @(); $rejected = @(); $fetchFirst = $false; $nonFf = $false; $done = @()
    $rhead = GdHead $gd; $bare = -not ($gd.EndsWith('\.git'))
    foreach ($sp in $specs) {
        $src = $sp[0]; $dst = $sp[1]; if (-not $dst.StartsWith('refs/')) { if ($src -and (ReadRef "refs/tags/$src") -and -not (ReadRef "refs/heads/$src")) { $dst = "refs/tags/$dst" } else { $dst = "refs/heads/$dst" } }
        $short = $dst -replace '^refs/(heads|tags)/', ''
        if ($del) { if ($rr.ContainsKey("refs/heads/$src")) { Remove-Item -LiteralPath ($gd + '\refs\heads\' + $src.Replace('/', '\')) -Force -ErrorAction SilentlyContinue; $lines += (' - [deleted]         ' + $src); DeleteRef "refs/remotes/$rem/$src" }; continue }
        $id = Rev $src; $old = $rr[$dst]
        $sname = $src; if ($src -eq 'HEAD' -and $br) { $sname = $br }
        if ($old -eq $id) { continue }
        if ($old -and $dst.StartsWith('refs/heads/') -and -not $force) {
            if (-not (HasObject $old)) { $lines += (' ! [rejected]        ' + $sname + ' -> ' + $short + ' (fetch first)'); $rejected += $dst; $fetchFirst = $true; continue }
            if (-not ((MergeBases $old $id) -contains $old)) { $lines += (' ! [rejected]        ' + $sname + ' -> ' + $short + ' (non-fast-forward)'); $rejected += $dst; $nonFf = $true; continue }
        }
        if ($old -and $dst.StartsWith('refs/tags/') -and -not $force) { $lines += (' ! [rejected]        ' + $sname + ' -> ' + $short + ' (already exists)'); $rejected += $dst; continue }
        if (-not $bare -and $rhead -ceq $dst) { Die ($script:RAW + "To $url`n ! [remote rejected] $sname -> $short (branch is currently checked out)`nerror: failed to push some refs to '$url'`nhint: The folder is a working copy with $short checked out: push to a bare repository instead`nhint: (pgit init --bare, or pgit clone --bare), the shared copy every member pushes to.`n") 1 }
        $null = CopyObjects $script:GITDIR $gd @($id)
        $rf = $gd + '\' + $dst.Replace('/', '\'); EnsureDir (Split-Path $rf -Parent); Zl-WriteBytes $rf (Zl-Utf8Enc ($id + "`n"))
        if ($dst.StartsWith('refs/heads/')) { UpdateRef "refs/remotes/$rem/$short" $id }
        if (-not $old) { if ($dst.StartsWith('refs/tags/')) { $lines += (' * [new tag]         ' + $sname + ' -> ' + $short) } else { $lines += (' * [new branch]      ' + $sname + ' -> ' + $short) } }
        elseif ($force -and -not ((MergeBases $old $id) -contains $old)) { $lines += (' + ' + ((Abbrev $old) + '...' + (Abbrev $id)).PadRight(17) + ' ' + $sname + ' -> ' + $short + ' (forced update)') }
        else { $lines += ('   ' + ((Abbrev $old) + '..' + (Abbrev $id)).PadRight(17) + ' ' + $sname + ' -> ' + $short) }
        $done += $dst
    }
    if ($tags) {
        foreach ($k in (SortPaths @((ListRefs 'refs/tags/').Keys))) {
            if ($rr.ContainsKey($k)) { continue }
            $id = ReadRef $k; $null = CopyObjects $script:GITDIR $gd @($id)
            $rf = $gd + '\' + $k.Replace('/', '\'); EnsureDir (Split-Path $rf -Parent); Zl-WriteBytes $rf (Zl-Utf8Enc ($id + "`n"))
            $t = $k.Substring(10); $lines += (' * [new tag]         ' + $t + ' -> ' + $t)
        }
    }
    if (-not $lines.Count) { Out-Err 'Everything up-to-date' }
    elseif (-not $q -or $rejected.Count) { Out-Err ("To $url`n" + ($lines -join "`n")) }
    if ($u -and $br -and -not $rejected.Count) {
        foreach ($sp in $specs) { if ($sp[0] -ceq $br -or $sp[0] -eq 'HEAD') { SetConfig "branch.$br.remote" $rem (GitPath 'config'); SetConfig "branch.$br.merge" ("refs/heads/" + $sp[1]) (GitPath 'config'); Out-Text "Branch '$br' set up to track remote branch '$($sp[1])' from '$rem'." } }
    }
    if ($rejected.Count) {
        $h = "error: failed to push some refs to '$url'`n"
        if ($fetchFirst) { $h += "hint: Updates were rejected because the remote contains work that you do`nhint: not have locally. This is usually caused by another repository pushing`nhint: to the same ref. You may want to first integrate the remote changes`nhint: (e.g., 'pgit pull ...') before pushing again.`nhint: See the 'Note about fast-forwards' in 'git push --help' for details.`n" }
        elseif ($nonFf) { $h += "hint: Updates were rejected because the tip of your current branch is behind`nhint: its remote counterpart. Integrate the remote changes (e.g.`nhint: 'pgit pull ...') before pushing again.`nhint: See the 'Note about fast-forwards' in 'git push --help' for details.`n" }
        Out-Err $h; $script:RC = 1
    }
}
function Cmd-Clone($a) {
    $script:OPTARGS = @($a); $bare = Opt @('--bare'); $b = Opt @('-b', '--branch') $true; $q = Opt @('-q', '--quiet'); $a = $script:OPTARGS
    if (-not $a.Count) { Die 'You must specify a repository to clone.' 129 }
    $src = $a[0]; $sgd = RemoteGitDir $src
    if (-not $sgd) { Die "repository '$src' does not exist" }
    $dir = $null; if ($a.Count -gt 1) { $dir = $a[1] } else { $dir = Split-Path ($src.Replace('/', '\').TrimEnd('\')) -Leaf; if ($dir -eq '.git') { $dir = Split-Path (Split-Path ($src.Replace('/', '\').TrimEnd('\')) -Parent) -Leaf }; if ($dir.EndsWith('.bundle')) { $dir = $dir.Substring(0, $dir.Length - 7) }; if ($bare) { if (-not $dir.EndsWith('.git')) { $dir += '.git' } } elseif ($dir.EndsWith('.git')) { $dir = $dir.Substring(0, $dir.Length - 4) } }
    if ((Test-Path -LiteralPath $dir) -and @(Get-ChildItem -LiteralPath $dir -Force).Count) { Die "destination path '$dir' already exists and is not an empty directory." }
    if (-not $q) { if ($bare) { Out-Err "Cloning into bare repository '$dir'..." } else { Out-Err "Cloning into '$dir'..." } }
    $url = UrlOf $src
    $rr = GdRefs $sgd; $rhead = GdHead $sgd
    $ia = @('-q'); if ($bare) { $ia += '--bare' }
    if ($rhead -and -not $b) { $ia += @('-b', $rhead.Substring(11)) } elseif ($b) { $ia += @('-b', $b) }
    $ia += $dir; Cmd-Init $ia
    $full = (Resolve-Path -LiteralPath $dir).Path.TrimEnd('\')
    if ($bare) { $script:ROOT = $full; $script:GITDIR = $full } else { $script:ROOT = $full; $script:GITDIR = $full + '\.git' }
    $script:PREFIX = ''; $script:OBJ = (NewMap); $script:OBJN = 0; $script:TREEFLAT = (NewMap)
    $null = CopyObjects $sgd $script:GITDIR @($rr.Values)
    $script:PACKIDX = (NewMap)
    if ($bare) {
        SetConfig 'remote.origin.url' $url (GitPath 'config')
        foreach ($k in $rr.Keys) { UpdateRef $k $rr[$k] }
    } else {
        SetConfig 'remote.origin.url' $url (GitPath 'config'); SetConfig 'remote.origin.fetch' '+refs/heads/*:refs/remotes/origin/*' (GitPath 'config')
        foreach ($k in $rr.Keys) { if ($k.StartsWith('refs/heads/')) { UpdateRef ("refs/remotes/origin/" + $k.Substring(11)) $rr[$k] } elseif ($k.StartsWith('refs/tags/')) { UpdateRef $k $rr[$k] } }
        $want = $null; if ($b) { $want = "refs/heads/$b" } elseif ($rhead) { $want = $rhead }
        if ($want -and $rr.ContainsKey($want)) { WriteText (GitPath 'refs/remotes/origin/HEAD') ("ref: refs/remotes/origin/" + $want.Substring(11) + "`n") }
        if ($want) {
            $bn = $want.Substring(11)
            SetConfig "branch.$bn.remote" 'origin' (GitPath 'config'); SetConfig "branch.$bn.merge" $want (GitPath 'config')
            if ($rr.ContainsKey($want)) {
                UpdateRef $want $rr[$want]
                $ix = ReadIndex; ApplyTree (NewMap) (CommitFiles $rr[$want]) $ix $true $false
            } elseif ($b) { Die "Remote branch $b not found in upstream origin" }
        }
    }
    if (-not $rr.Count -and -not $q) { Out-Err 'warning: You appear to have cloned an empty repository.' }
    if (-not $q) { Out-Err 'done.' }
}

# ---------------------------------------------------------------- stash (git's layout: refs/stash + its reflog; w commit = HEAD + i commit)
function StashList() {                                 # newest first: @{ id; msg; line }
    $t = ReadText (GitPath 'logs/refs/stash'); $out = @()
    if ($t) { foreach ($l in ($t -split "`n")) { if ($l -eq '') { continue }; $tab = $l.IndexOf("`t"); $f = $l.Substring(0, $tab) -split ' '; $out = , @{ id = $f[1]; msg = $l.Substring($tab + 1); line = $l } + $out } }
    return , $out
}
function StashWrite($list) {                           # newest first -> refs/stash and logs/refs/stash
    if (-not $list.Count) { foreach ($f in 'refs/stash', 'logs/refs/stash') { $p = GitPath $f; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }; return }
    $lines = @(); $prev = $script:ZERO
    for ($k = $list.Count - 1; $k -ge 0; $k--) { $e = $list[$k]; $tab = $e.line.IndexOf("`t"); $f = $e.line.Substring(0, $tab) -split ' ', 3; $lines += ($prev + ' ' + $e.id + ' ' + $f[2] + "`t" + $e.msg); $prev = $e.id }
    WriteText (GitPath 'logs/refs/stash') (($lines -join "`n") + "`n")
    UpdateRef 'refs/stash' $list[0].id
}
function StashPick($list, $a) {                        # 'stash@{N}' or 'N' -> index into the list
    $n = 0
    if ($a.Count) { $m = [regex]::Match([string]$a[0], '^(?:stash@\{)?(\d+)\}?$'); if (-not $m.Success) { Die "'$($a[0])' is not a stash-like commit" }; $n = [int]$m.Groups[1].Value }
    if (-not $list.Count) { Die ($script:RAW + "No stash entries found.`n") 1 }
    if ($n -ge $list.Count) { Die "log for 'stash' only has $($list.Count) entries" }
    return $n
}
function Cmd-Stash($a) {
    $sub = 'push'; if ($a.Count -and -not ([string]$a[0]).StartsWith('-')) { $sub = [string]$a[0]; if ($a.Count -gt 1) { $a = @($a[1..($a.Count - 1)]) } else { $a = @() } }
    $script:OPTARGS = @($a); $msg = Opt @('-m', '--message') $true; $q = Opt @('-q', '--quiet'); $patch = Opt @('-p', '--patch'); $a = $script:OPTARGS
    if (@('push', 'save', 'apply', 'pop') -contains $sub) { UnmergedCheckStash }
    switch ($sub) {
        { $_ -eq 'push' -or $_ -eq 'save' } {
            if ($sub -eq 'save' -and $a.Count) { $msg = $a -join ' ' }
            $d = StatusData
            if (-not $d.staged.Count -and -not $d.unstaged.Count) { Out-Text 'No local changes to save'; return }
            $head = HeadCommit; if (-not $head) { Die 'You do not have the initial commit yet' }
            $hr = HeadRef; $bn = '(no branch)'; if ($hr) { $bn = $hr.Substring(11) }
            $hc = ParseCommit $head; $what = (Abbrev $head) + ' ' + (Subject $hc.message)
            $ix = ReadIndex; $im = IndexMap $ix
            $itree = WriteTreeFromMap $im
            $wm = (NewMap); foreach ($k in $im.Keys) { $wm[$k] = $im[$k] }
            foreach ($k in @($ix.entries.Keys)) { $f = Full $k; $fi = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; if ($null -eq $fi -or $fi.PSIsContainer) { $wm.Remove($k); continue }; if (-not (StatSame $ix.entries[$k] $fi $ix.mtime)) { $wm[$k] = @{ mode = $ix.entries[$k].mode; id = (WriteObject 'blob' (Zl-ReadBytes $f)) } } }
            $wtree = WriteTreeFromMap $wm
            $who = Ident 'COMMITTER'; $au = Ident 'AUTHOR'
            $icm = WriteObject 'commit' (Zl-Utf8Enc ("tree $itree`nparent $head`nauthor $au`ncommitter $who`n`nindex on ${bn}: $what`n"))
            $title = "WIP on ${bn}: $what"; if ($msg) { $title = "On ${bn}: $msg" }
            $wcm = WriteObject 'commit' (Zl-Utf8Enc ("tree $wtree`nparent $head`nparent $icm`nauthor $au`ncommitter $who`n`n$title"))   # git: no final newline here
            $list = StashList; StashWrite (@(, @{ id = $wcm; msg = $title; line = ($script:ZERO + ' ' + $wcm + ' ' + $who + "`t" + $title) }) + $list)
            ApplyTree (IndexMap $ix) (CommitFiles $head) $ix $true $true
            if (-not $q) { Out-Text "Saved working directory and index state $title" }
        }
        'list' { $o = ''; $list = StashList; for ($k = 0; $k -lt $list.Count; $k++) { $o += "stash@{$k}: " + $list[$k].msg + "`n" }; Out-Text $o }
        'show' {
            $list = StashList; $n = StashPick $list $a; $w = ParseCommit $list[$n].id
            $prs = DiffMaps (CommitFiles $w.parents[0]) (FlattenTree $w.tree) @() $true $null
            if ($patch) { $o = ''; foreach ($pr in $prs) { $o += PairPatch $pr 3 $null }; Out-Text (L1ToText $o) } else { Out-Text (DiffStat $prs) }
        }
        { $_ -eq 'apply' -or $_ -eq 'pop' } {
            $list = StashList; $n = StashPick $list $a; $wid = $list[$n].id; $w = ParseCommit $wid
            $ix = ReadIndex; $om = IndexMap $ix; $bm = CommitFiles $w.parents[0]; $wm = FlattenTree $w.tree
            $tm = TreeMerge $bm $om $wm 'Stashed changes' 'Updated upstream'
            try { MergeLocalCheck $om $tm.final $ix 'merge' }
            catch { $m = $_.Exception.Message; Out-Err $m.Substring($m.IndexOf(':', 8) + 2); Cmd-Status @(); if ($sub -eq 'pop') { Out-Text 'The stash entry is kept in case you need it again.' }; $script:RC = 1; return }
            ApplyMergeResult $om $tm
            if (-not $q) { foreach ($l in $tm.msgs) { Out-Text $l } }
            if ($tm.conflicts.Count) { Cmd-Status @(); if ($sub -eq 'pop') { Out-Text 'The stash entry is kept in case you need it again.' }; $script:RC = 1; return }
            $added = (NewMap); foreach ($k in $wm.Keys) { if (-not $bm.ContainsKey($k)) { $added[$k] = 1 } }
            $ix = ReadIndex                              # without --index: the index goes back to what it was, plus the stash's new files
            foreach ($k in @($tm.final.Keys) + @($om.Keys) | Select-Object -Unique) {
                if ($added.ContainsKey($k)) { continue }
                if (SameEnt $om[$k] $tm.final[$k]) { continue }
                if ($om[$k]) { $x = $om[$k]; $ix.entries[$k] = @{ path = $k; cs = 0; cns = 0; ms = 0; mns = 0; dev = 0; ino = 0; mode = $x.mode; uid = 0; gid = 0; size = 0; id = $x.id } } else { $ix.entries.Remove($k) }
            }
            WriteIndex $ix.entries
            if (-not $q) { Cmd-Status @() }
            if ($sub -eq 'pop') { $rest = @(); for ($k = 0; $k -lt $list.Count; $k++) { if ($k -ne $n) { $rest += , $list[$k] } }; StashWrite $rest; if (-not $q) { Out-Text "Dropped refs/stash@{$n} ($wid)" } }
        }
        'drop' { $list = StashList; $n = StashPick $list $a; $wid = $list[$n].id; $rest = @(); for ($k = 0; $k -lt $list.Count; $k++) { if ($k -ne $n) { $rest += , $list[$k] } }; StashWrite $rest; if (-not $q) { Out-Text "Dropped refs/stash@{$n} ($wid)" } }
        'clear' { StashWrite @() }
        default { Die "unknown subcommand: $sub" 129 }
    }
}
function UnmergedCheckStash() { $ix = ReadIndex; if ($ix.unmerged.Count) { $l = ''; foreach ($k in (SortPaths @($ix.unmerged.Keys))) { $l += "${k}: needs merge`n" }; Die ($script:RAW + $l) 1 } }

# ---------------------------------------------------------------- cherry-pick and revert (one commit; the sequencer's single-pick behaviour)
function PickState() { foreach ($k in 'CHERRY_PICK_HEAD', 'REVERT_HEAD') { $t = ReadText (GitPath $k); if ($t) { return @{ kind = $k; id = $t.Trim() } } }; return $null }
function ClearPickState() { foreach ($f in 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'MERGE_MSG', 'AUTO_MERGE') { $p = GitPath $f; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } }
function PickSummary([string]$id, $au) {              # the sequencer's commit summary: Author when it differs, always Date
    $c = ParseCommit $id; $hr = HeadRef; $where = 'detached HEAD'; if ($hr) { $where = $hr.Substring(11) }
    $o = '[' + $where + ' ' + (Abbrev $id) + '] ' + (Subject $c.message) + "`n"
    $me = ParsePerson (Ident 'COMMITTER')
    if ($c.author.name -cne $me.name -or $c.author.email -cne $me.email) { $o += ' Author: ' + $c.author.name + ' <' + $c.author.email + ">`n" }
    $o += ' Date: ' + (GitDate $c.author.time $c.author.tz) + "`n"
    $o += Summary (DiffMaps (CommitFiles $c.parents[0]) (FlattenTree $c.tree) @() $true $null)
    Out-Text $o
}
function Cmd-Pick($a, [bool]$revert) {
    $verb = 'cherry-pick'; $ing = 'Cherry-picking'; if ($revert) { $verb = 'revert'; $ing = 'Reverting' }
    $script:OPTARGS = @($a); $abort = Opt @('--abort'); $cont = Opt @('--continue'); $skip = Opt @('--skip'); $noCommit = Opt @('-n', '--no-commit'); $null = Opt @('--no-edit'); $a = $script:OPTARGS
    $st = PickState
    if ($abort -or $skip) {
        if (-not $st) { Die ($script:RAW + "error: no cherry-pick or revert in progress`nfatal: $verb failed`n") }
        $ix = ReadIndex; ApplyTree (ConflictMap $ix) (CommitFiles (HeadCommit)) $ix $true $true
        $script:IXUM = (NewMap); $ix = ReadIndex; WriteIndex $ix.entries (NewMap); ClearPickState; return
    }
    if ($cont) {
        if (-not $st) { Die ($script:RAW + "error: no cherry-pick or revert in progress`nfatal: $verb failed`n") }
        $ix = ReadIndex
        if ($ix.unmerged.Count) { $ul = ''; foreach ($k in (SortPaths @($ix.unmerged.Keys))) { $ul += "U`t$k`n" }; Die ($script:RAW + "error: Committing is not possible because you have unmerged files.`nhint: Fix them up in the work tree, and then use 'pgit add/rm <file>'`nhint: as appropriate to mark resolution and make a commit.`nfatal: Exiting because of an unresolved conflict.`n" + $ul) }
        if ((WriteTreeFromMap (IndexMap $ix)) -eq (ParseCommit (HeadCommit)).tree) {
            $pv = 'cherry-pick'; if ($st.kind -eq 'REVERT_HEAD') { $pv = 'revert' }
            Out-Err "The previous $pv is now empty, possibly due to conflict resolution.`nIf you wish to commit it anyway, use:`n`n    pgit commit --allow-empty`n`nOtherwise, please use 'pgit $pv --skip'"
            Cmd-Status @(); $script:RC = 1; return
        }
        $msg = ReadText (GitPath 'MERGE_MSG'); $msg = (($msg -split "`n") | Where-Object { -not $_.StartsWith('#') }) -join "`n"   # --continue strips the comments
        PickCommit $st.id ([bool]($st.kind -eq 'REVERT_HEAD')) (CleanMessage $msg); return
    }
    if (-not $a.Count) { Die 'empty commit set passed' }
    $ix = ReadIndex
    if ($ix.unmerged.Count) { Die ($script:RAW + "error: $ing is not possible because you have unmerged files.`nhint: Fix them up in the work tree, and then use 'pgit add/rm <file>'`nhint: as appropriate to mark resolution and make a commit.`nfatal: Exiting because of an unresolved conflict.`n") }
    if ($st) { Die ($script:RAW + "error: $verb is already in progress`nhint: try ""pgit $verb (--continue | --abort | --skip)""`nfatal: $verb failed`n") }
    $rid = Rev $a[0] $true; if (-not $rid) { Die "bad revision '$($a[0])'" }
    $cid = PeelTo $rid 'commit'; $c = ParseCommit $cid
    if ($c.parents.Count -gt 1) { Die ($script:RAW + "error: commit $cid is a merge but no -m option was given.`nfatal: $verb failed`n") }
    $head = HeadCommit; $hm = CommitFiles $head
    $staged = DiffMaps $hm (IndexMap $ix) @() $false $null
    if ($staged.Count) { Die ($script:RAW + "error: your local changes would be overwritten by $verb.`nhint: commit your changes or stash them to proceed.`nfatal: $verb failed`n") }
    $pm = (NewMap); if ($c.parents.Count) { $pm = CommitFiles $c.parents[0] }
    $cm = FlattenTree $c.tree; $subj = Subject $c.message; $ab = Abbrev $cid
    if ($revert) { $tm = TreeMerge $cm $hm $pm "parent of $ab ($subj)"; $msg = "Revert ""$subj""`n`nThis reverts commit $cid.`n" }
    else { $tm = TreeMerge $pm $hm $cm "$ab ($subj)"; $msg = $c.message }
    MergeLocalCheck $hm $tm.final $ix 'merge'
    ApplyMergeResult $hm $tm
    foreach ($l in $tm.msgs) { if ($l.StartsWith('warning: ')) { Out-Err $l } else { Out-Text $l } }
    $stateFile = 'CHERRY_PICK_HEAD'; if ($revert) { $stateFile = 'REVERT_HEAD' }
    if ($tm.conflicts.Count) {
        $mm = $msg + "`n# Conflicts:`n"; foreach ($k in $tm.conflicts) { $mm += "#`t$k`n" }
        WriteText (GitPath 'MERGE_MSG') $mm; WriteText (GitPath $stateFile) ($cid + "`n"); WriteText (GitPath 'AUTO_MERGE') ((WriteTreeFromMap $tm.final) + "`n")
        $w = 'apply'; if ($revert) { $w = 'revert' }
        Out-Err ("error: could not $w $ab... $subj`nhint: After resolving the conflicts, mark them with`nhint: ""pgit add/rm <pathspec>"", then run`nhint: ""pgit $verb --continue"".`nhint: You can instead skip this commit with ""pgit $verb --skip"".`nhint: To abort and get back to the state before ""pgit $verb"",`nhint: run ""pgit $verb --abort"".")
        $script:RC = 1; return
    }
    if ($noCommit) { return }
    if ((WriteTreeFromMap $tm.final) -eq (ParseCommit $head).tree) {
        if ($revert) { WriteText (GitPath 'MERGE_MSG') $msg; Cmd-Status @(); $script:RC = 1; return }   # git: an empty revert leaves only MERGE_MSG behind
        WriteText (GitPath 'MERGE_MSG') $msg; WriteText (GitPath $stateFile) ($cid + "`n")
        Out-Err "The previous $verb is now empty, possibly due to conflict resolution.`nIf you wish to commit it anyway, use:`n`n    pgit commit --allow-empty`n`nOtherwise, please use 'pgit $verb --skip'"
        Cmd-Status @(); $script:RC = 1; return
    }
    PickCommit $cid $revert $msg
}
function PickCommit([string]$cid, [bool]$revert, [string]$msg) {
    $c = ParseCommit $cid; $head = HeadCommit
    $ix = ReadIndex; $tree = WriteTreeFromMap (IndexMap $ix)
    $au = Ident 'AUTHOR'; if (-not $revert) { $au = $c.author.raw }
    $t = "tree $tree`nparent $head`nauthor $au`ncommitter $(Ident 'COMMITTER')`n`n" + $msg
    $id = WriteObject 'commit' (Zl-Utf8Enc $t)
    $hr = HeadRef; if ($hr) { UpdateRef $hr $id } else { SetHead $id }
    ClearPickState
    PickSummary $id $au
}

# ---------------------------------------------------------------- bundle: one file that carries a repository (Teams, mail, a USB stick)
function PackWrite($ids) {                             # a pack (no deltas) holding these objects -> bytes
    $parts = @(); $hdr = [byte[]]::new(12); $hdr[0] = 80; $hdr[1] = 65; $hdr[2] = 67; $hdr[3] = 75; PutBE32 $hdr 4 2; PutBE32 $hdr 8 $ids.Count; $parts += , $hdr
    $tnum = @{ 'commit' = 1; 'tree' = 2; 'blob' = 3; 'tag' = 4 }
    foreach ($id in $ids) {
        $o = ReadObject $id; $n = [long]$o.body.Length
        $h = @(); $c = ($tnum[$o.type] -shl 4) -bor ($n -band 15); $n = $n -shr 4
        while ($n -gt 0) { $h += ($c -bor 128); $c = $n -band 127; $n = $n -shr 7 }; $h += $c
        $parts += , ([byte[]]$h); $parts += , (Zl-Zlib $o.body)
    }
    $body = CatBytes $parts
    return , (CatBytes @($body, (HexBytes (Sha1Hex $body))))
}
function Reachable($tips) {                            # every object reachable from these ids, commits first
    $seen = (NewMap); $order = @(); $st = @($tips)
    while ($st.Count) {
        $id = $st[$st.Count - 1]; if ($st.Count -eq 1) { $st = @() } else { $st = $st[0..($st.Count - 2)] }
        if ($seen.ContainsKey($id)) { continue }; $seen[$id] = 1; $order += $id
        $o = ReadObject $id
        if ($o.type -eq 'commit') { $c = ParseCommit $id; $st += $c.tree; foreach ($p in $c.parents) { $st += $p } }
        elseif ($o.type -eq 'tag') { $st += (ParseTag $id).object }
        elseif ($o.type -eq 'tree') { $b = $o.body; $q = 0; while ($q -lt $b.Length) { $sp = [Array]::IndexOf($b, [byte]32, $q); $z = [Array]::IndexOf($b, [byte]0, $sp); if ((Latin1 (Slice $b $q ($sp - $q))) -ne '160000') { $st += (Hex $b ($z + 1) 20) }; $q = $z + 21 } }
    }
    return , $order
}
function Cmd-Bundle($a) {
    if (-not $a.Count) { Die 'usage: pgit bundle create FILE (--all | REF...) | pgit bundle verify FILE | pgit bundle list-heads FILE' 129 }
    $sub = $a[0]; $rest = @(); if ($a.Count -gt 1) { $rest = @($a[1..($a.Count - 1)]) }
    switch ($sub) {
        'create' {
            if ($rest.Count -lt 2) { Die 'usage: pgit bundle create FILE (--all | REF...)' 129 }
            $file = $rest[0]; $want = @($rest[1..($rest.Count - 1)])
            $refs = @()
            if ($want -contains '--all') { $h = HeadCommit; if ($h) { $refs += , @('HEAD', $h) }; foreach ($pre in 'refs/heads/', 'refs/remotes/', 'refs/tags/') { foreach ($k in (SortPaths @((ListRefs $pre).Keys))) { if ($k.EndsWith('/HEAD')) { continue }; $refs += , @($k, (ReadRef $k)) } } }
            else { foreach ($w in $want) { if ($w -eq 'HEAD') { $refs += , @('HEAD', (HeadCommit)) } elseif (ReadRef "refs/heads/$w") { $refs += , @("refs/heads/$w", (ReadRef "refs/heads/$w")) } elseif (ReadRef "refs/tags/$w") { $refs += , @("refs/tags/$w", (ReadRef "refs/tags/$w")) } elseif ($w.StartsWith('refs/') -and (ReadRef $w)) { $refs += , @($w, (ReadRef $w)) } else { Die "bad revision '$w'" } } }
            if (-not $refs.Count) { Die 'Refusing to create empty bundle.' }
            $ids = Reachable @($refs | ForEach-Object { $_[1] })
            $hdr = "# v2 git bundle`n"; foreach ($r in $refs) { $hdr += $r[1] + ' ' + $r[0] + "`n" }; $hdr += "`n"
            Zl-WriteBytes $file (CatBytes @((Latin1Bytes $hdr), (PackWrite $ids)))
            Out-Err "Total $($ids.Count) (delta 0), reused 0 (delta 0), pack-reused 0"
        }
        'verify' {
            $bd = BundleRead $rest[0]; $miss = @(); foreach ($q in $bd.prereq) { if (-not (HasObject $q)) { $miss += $q } }
            if ($miss.Count) { Out-Err ("error: Repository lacks these prerequisite commits:`n" + (($miss | ForEach-Object { "error: $_" }) -join "`n")); $script:RC = 1; return }
            $o = "The bundle contains $(if ($bd.order.Count -eq 1) { 'this ref' } else { "these $($bd.order.Count) refs" }):`n"; foreach ($k in $bd.order) { $o += $bd.refs[$k] + ' ' + $k + "`n" }
            if ($bd.prereq.Count) { $o += "The bundle requires these $($bd.prereq.Count) refs:`n" + (($bd.prereq | ForEach-Object { "$_`n" }) -join '') } else { $o += "The bundle records a complete history.`n" }
            Out-Text $o; Out-Err "$($rest[0]) is okay"
        }
        'list-heads' { $bd = BundleRead $rest[0]; $o = ''; foreach ($k in $bd.order) { $o += $bd.refs[$k] + ' ' + $k + "`n" }; Out-Text $o }
        default { Die "unknown subcommand: $sub" 129 }
    }
}

$script:USAGE = @"
pgit.ps1 -- git for a PowerShell-only PC (Windows PowerShell 5.1, Constrained Language Mode safe)

Works on a real .git directory: real git (or GitLab) reads what pgit writes; pgit reads what git writes, packs
included (new objects are written loose). A repository travels as a folder, a shared folder or a .bundle file.

  pgit init [--bare] [-b BRANCH] [DIR]    pgit clone [--bare] [-b BRANCH] FOLDER|SHARE|FILE.bundle [DIR]
  pgit status [-s | --porcelain]          pgit add [-A] [-f] [-u] PATH...   pgit rm [--cached] [-r] PATH...   pgit mv SRC DST
  pgit commit -m MSG [-a] [--amend] [--allow-empty] [--no-edit]     (-am "msg" works)
  pgit log [--oneline] [-n N] [-p] [--all] [--decorate] [--format=FMT] [REV...] [-- PATH...]
  pgit show [REV | REV:PATH]...           pgit diff [--cached] [REV [REV]] [-U N] [--stat|--name-only|--name-status] [-- PATH...]
  pgit branch [-d|-D|-m] [NAME [START]]   pgit tag [-a -m MSG | -d] [NAME [REV]]
  pgit checkout [-b NEW] [--detach] REV | pgit checkout [REV] -- PATH...   pgit switch [-c NEW] BRANCH
  pgit restore [--staged] [--source REV] PATH...     pgit reset [--hard|--soft] [REV] [-- PATH...]
  pgit merge [--no-ff|--ff-only] [--no-commit] [-m MSG] REV | --abort | --continue   (three-way, conflict markers)
  pgit cherry-pick REV | --continue | --skip | --abort     pgit revert REV | --continue | --skip | --abort
  pgit stash [push [-m MSG]] | list | show [-p] | apply | pop | drop [stash@{N}] | clear
  pgit remote [-v] | add NAME URL | remove NAME | get-url NAME | set-url NAME URL    (URL: a folder, \\server\share\x.git, a .bundle)
  pgit fetch [REMOTE | --all]             pgit pull [--no-rebase|--ff-only] [REMOTE [BRANCH]]
  pgit push [-u] [--tags] [-f] [--delete] [REMOTE [BRANCH|SRC:DST]...]   (to a bare repository: pgit init --bare)
  pgit bundle create FILE (--all | REF...) | verify FILE | list-heads FILE      one file for Teams, mail or a USB stick
  pgit rev-parse [--short] [--abbrev-ref] [--show-toplevel] REV...   pgit cat-file -t|-s|-p|-e OBJ
  pgit ls-files [-s]   pgit ls-tree [-r] [-t] [--name-only] TREE-ISH   pgit hash-object [-w] FILE   pgit fsck
  pgit config [--global] [--list | --unset] NAME [VALUE]               pgit help packs

Not here: rebase, blame, log --graph, reflog, diff --cc during a conflict (pgit prints "* Unmerged path"), renames
inside a merge (seen as delete + add), criss-cross merges (several merge bases), network URLs (http, ssh).
Identity: pgit config --global user.name "First Last"; pgit config --global user.email "you@example.mil"
(or GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL / GIT_AUTHOR_DATE and the GIT_COMMITTER_ ones, as git reads them).
"@
$script:PACKS = @"
pgit reads pack files (.git/objects/pack/*.pack with version-2 .idx, deltas included) and git bundles, so a
repository cloned or made by git works here as it is, and so does: pgit clone repo.bundle. What pgit writes is
loose objects (one zlib file per object), which git and GitLab read as they are. A bundle pgit makes
(pgit bundle create repo.bundle --all) is uncompressed-delta and larger than git's; git clones it as usual.
"@

function Pgit-Main($argv) {
    $script:RC = 0
    $cmd = 'help'; $rest = @()
    if ($argv.Count) { $cmd = [string]$argv[0]; if ($argv.Count -gt 1) { $rest = @($argv[1..($argv.Count - 1)] | ForEach-Object { [string]$_ }) } }
    try {
        switch -CaseSensitive ($cmd) {
            { $_ -in 'help', '-h', '--help', '/?' } { if ($rest.Count -and $rest[0] -eq 'packs') { Out-Text $script:PACKS } else { Out-Text $script:USAGE }; break }
            'version' { Out-Text 'pgit version 1.0 (git-compatible loose-object repositories)'; break }
            '--version' { Out-Text 'pgit version 1.0 (git-compatible loose-object repositories)'; break }
            'init' { $script:GITDIR = $null; Cmd-Init $rest; break }
            'clone' { $script:GITDIR = $null; Cmd-Clone $rest; break }
            default {
                Set-Repo $null
                switch -CaseSensitive ($cmd) {
                    'add' { Cmd-Add $rest; break }
                    'rm' { Cmd-Rm $rest; break }
                    'mv' { Cmd-Mv $rest; break }
                    'status' { Cmd-Status $rest; break }
                    'commit' { Cmd-Commit $rest; break }
                    'log' { Cmd-Log $rest; break }
                    'show' { Cmd-Show $rest; break }
                    'diff' { Cmd-Diff $rest; break }
                    'branch' { Cmd-Branch $rest; break }
                    'tag' { Cmd-Tag $rest; break }
                    'checkout' { Cmd-Checkout $rest $false; break }
                    'switch' { Cmd-Checkout $rest $true; break }
                    'restore' { Cmd-Restore $rest; break }
                    'reset' { Cmd-Reset $rest; break }
                    'merge' { Cmd-Merge $rest; break }
                    'rev-parse' { Cmd-RevParse $rest; break }
                    'cat-file' { Cmd-CatFile $rest; break }
                    'ls-files' { Cmd-LsFiles $rest; break }
                    'ls-tree' { Cmd-LsTree $rest; break }
                    'hash-object' { Cmd-HashObject $rest; break }
                    'config' { Cmd-Config $rest; break }
                    'fsck' { Cmd-Fsck $rest; break }
                    'remote' { Cmd-Remote $rest; break }
                    'fetch' { Cmd-Fetch $rest; break }
                    'pull' { Cmd-Pull $rest; break }
                    'push' { Cmd-Push $rest; break }
                    'stash' { Cmd-Stash $rest; break }
                    'cherry-pick' { Cmd-Pick $rest $false; break }
                    'revert' { Cmd-Pick $rest $true; break }
                    'bundle' { Cmd-Bundle $rest; break }
                    default { Die "'$cmd' is not a pgit command. See 'pgit help'." 1 }
                }
            }
        }
    } catch {
        $m = $_.Exception.Message
        if ($m.StartsWith('PGITDIE:')) {
            $rest2 = $m.Substring(8); $c = $rest2.IndexOf(':')
            $code = [int]$rest2.Substring(0, $c); $msg = $rest2.Substring($c + 1)
            if ($msg.StartsWith($script:RAW)) { $msg = $msg.Substring(1); if ($msg.StartsWith($script:NONL)) { Write-Host -NoNewline $msg.Substring(1) } else { Out-Err $msg } }
            elseif ($code -eq 128) { Out-Err ('fatal: ' + $msg) } else { Out-Err $msg }
            $script:RC = $code
        } else { Out-Err ('fatal: ' + $m); if ($env:PGIT_DEBUG) { Out-Err $_.ScriptStackTrace }; $script:RC = 128 }
    }
}

# ---------------------------------------------------------------- main
if ($args.Count -and $args[0] -ceq '__lib') { return }
Pgit-Main $args
$exitCode = $script:RC
if ($PSCommandPath) { exit $exitCode }
$global:LASTEXITCODE = $exitCode
