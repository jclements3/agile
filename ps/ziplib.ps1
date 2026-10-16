<#
ziplib.ps1 -- zip, zlib and deflate in Windows PowerShell 5.1, Constrained Language Mode safe.

CLM refuses System.IO.Compression and Compress-Archive (the Archive module calls .NET), so everything here is
plain PowerShell integer arithmetic: an RFC 1951 inflate (stored, fixed and dynamic Huffman blocks), CRC-32,
Adler-32, a zlib stream writer (stored blocks) and reader, and a zip reader and writer.

    . .\ziplib.ps1                                   # dot-source: defines the functions, runs nothing

    Read-ZipEntries -Path FILE                       # -> @( @{name; size; csize; method; crc; offset} ... ) in directory order
    Read-ZipEntry   -Path FILE -Name ENTRY           # -> [byte[]] (methods 0 stored, 8 deflate; CRC-32 checked)
    Write-Zip       -Path FILE -Entries ENTRIES      # stored (uncompressed) zip; ENTRIES = [ordered]@{ name = [byte[]] }
                                                     #   or an array of @{ name = 'a/b.xml'; data = [byte[]] } (order kept)
    Zl-Inflate  [byte[]]$src [int]$start             # raw deflate stream at $start -> [byte[]]
    Zl-Unzlib   [byte[]]$src                         # zlib stream (2-byte header, deflate, Adler-32) -> [byte[]]
    Zl-Zlib     [byte[]]$data                        # -> zlib stream with stored blocks (valid for git, PNG, PDF)
    Zl-Crc32    [byte[]]$data [int]$off [int]$len    # -> [long]
    Zl-Adler32  [byte[]]$data [int]$off [int]$len    # -> [long]
    Zl-ReadBytes  PATH  /  Zl-WriteBytes PATH [byte[]]

Limits: no zip64, no encryption, writes stored entries only (Word, Excel and git all accept them). Speed is that
of a PowerShell loop: inflate runs at roughly 100-300 KB/s, CRC-32 at about 1 MB/s.
#>

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
