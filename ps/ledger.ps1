<#
ledger.ps1 -- the agile kit's ledger (bin/ledger.pl + lib/Ledger.pm) in Windows PowerShell 5.1.

Plain-text double-entry accounting on the ledger-cli file format: the scrum journal (scrum.txt), and
funding, hours or money files. Balance, register, budget, earned value (EVM) and funding run-out.
Runs on a locked-down laptop: no install, no admin, no network, no COM, and it works under Constrained
Language Mode (AppLocker/WDAC). Output is byte for byte what perl bin/ledger.pl prints.

  ledger.cmd [-f FILE] [OPTIONS] COMMAND [ACCOUNT-REGEX...]
  . .\ledger.ps1 __lib      (library: every function is Lg*-prefixed so it never clashes with agile.ps1; plus FundingSnapshot)
  powershell -NoProfile -ExecutionPolicy Bypass -File ledger.ps1 [-f FILE] [OPTIONS] COMMAND [ACCOUNT-REGEX...]

  bal | reg | budget | evm | forecast | csv | check | accounts | payees     (ledger.cmd help [COMMAND])
#>
$ErrorActionPreference = 'Stop'
$script:LG_ARGV = @(foreach ($x in $args) { [string]$x })
$script:LG_INV = [cultureinfo]::InvariantCulture
$script:LG_PREC = [hashtable]::new()                     # commodity => decimals seen (case-sensitive keys, as in Perl)

$script:LG_HELP_MAIN = @'
ledger.cmd

    ledger.cmd [-f FILE] [OPTIONS] COMMAND [ACCOUNT-REGEX...]

A plain-text double-entry ledger (ledger-cli format), used for the scrum
journal and for anything else: money, hours, funding. -f FILE (or
$LEDGER_FILE; default ledger.txt). Account regexes after the command are
ORed, case-insensitive: bal groceries repairs.
-p PERIOD (2026, 2026-09, 2026-Q3)  -b DATE (from)  -e DATE (before)
--depth N  -C cleared only  -R real only  -E show zeros  --payee RE
-M, --monthly  month by month (bal, reg, budget)
--now YYYY-MM-DD   the status date of evm and forecast (through the end of
                   that day; default today)
--months N     forecast's burn window (default 3)
--complete ACCOUNT=PCT  --complete-file FILE   evm's percent complete
help: ledger.cmd help [COMMAND].

bal [ACCOUNT...]
The balance tree. ledger.cmd -f scrum.txt bal Sprint:42 shows a sprint.

reg [ACCOUNT...]
One line per posting with a running balance.

budget [-p PERIOD]
The ~ periodic budget entries against the actuals (default: this month).

-M, --monthly
With bal: an account by month table with a Total. With reg: one line per
account per month with a running total. With budget: Month, Account,
Budget, Actual, Remaining for each month.

evm [--complete ACCT=PCT]... [--complete-file F] [--now D]
Earned value per account: Account, %done, BAC, BCWS (planned), BCWP (earned
= BAC x percent complete), ACWP (actual), CV, SV, CPI, SPI, EAC, VAC, and a
Total. Needs dated budgets: "~ Monthly from YYYY-MM-DD to YYYY-MM-DD" (or
"until"). Percent complete: --complete ACCOUNT=PCT, repeatable, PCT as
0-100, 0.x or 55%; or --complete-file FILE, CSV lines "account,pct" (a
header and # comments are allowed). An account's percent covers its
sub-accounts. --now sets the status date (default today).

forecast [--months 3] [--now D] [ACCOUNT...]
Funding run-out per account: Account, Balance, Burn/month (the average
monthly spend over the last N whole months), Months left, Runs out.
forecast --months 2 Assets limits it to the funding accounts.

csv
Postings as CSV: date,status,payee,account,amount,commodity.

check
Parse and verify every transaction balances: "ok: N transactions".

accounts
payees
The distinct account or payee names.

One command: ledger.cmd help COMMAND.
'@

# ================================================================ output
function LgOut-Text([string]$t) {                       # print text that ends in newlines, line for line
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}
function LgOut-Err([string]$t) {                        # Perl's STDERR
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host $l -ForegroundColor Yellow }
}
function LgDie([string]$msg) { throw "DIE:$msg" }        # Perl's die: message to STDERR, exit 255
function LgDieErrno([string]$msg) { throw "DIE2:$msg" }  # die right after a failed open: Perl exits with errno (ENOENT = 2)

# ================================================================ lists (CLM: no ArrayList; a hashtable keyed 0..n-1 appends in O(1))
function LgNewList { @{} }
function LgPush($l, $x) { $l[$l.Count] = $x }
function LgToArray($l) { , @(for ($i = 0; $i -lt $l.Count; $i++) { , $l[$i] }) }

# ================================================================ numbers
function LgTrunc($x) { $d = [double]$x; $r = [long]$d; if ($d -ge 0) { if ($r -gt $d) { $r-- } } else { if ($r -lt $d) { $r++ } }; $r }   # Perl int()
function LgFloorDiv([long]$a, [long]$b) { $q = LgTrunc ($a / $b); if ($q * $b -gt $a) { $q-- }; $q }
function LgPerlMod([long]$a, [long]$b) { $r = $a % $b; if ($r -lt 0) { $r += $b }; $r }               # Perl % with a positive right side
function LgPow10([int]$p) { $x = 1.0; for ($i = 0; $i -lt $p; $i++) { $x *= 10 }; $x }
function LgFmtF($v, [int]$p) {                          # sprintf("%.pf", v): exact ties to even, as C and Perl do
    $d = [double]$v; $neg = $d -lt 0; if ($neg) { $d = -$d }
    $s = $d.ToString('G17', $script:LG_INV)
    $exp = 0
    if ($s.Contains('E')) { $parts = $s.Split('E'); $s = $parts[0]; $exp = [int]$parts[1] }
    $ip = $s; $fp = ''
    if ($s.Contains('.')) { $parts = $s.Split('.'); $ip = $parts[0]; $fp = $parts[1] }
    $digits = $ip + $fp; $point = $ip.Length + $exp
    if ($point -le 0) { $digits = ('0' * (1 - $point)) + $digits; $point = 1 }
    if ($point -gt $digits.Length) { $digits = $digits + ('0' * ($point - $digits.Length)) }
    $intD = $digits.Substring(0, $point); $fracD = $digits.Substring($point)
    if ($fracD.Length -le $p) { $fracD = $fracD + ('0' * ($p - $fracD.Length)) }
    else {
        $keep = $intD + $fracD.Substring(0, $p); $r = [int][string]$fracD[$p]; $rest = $fracD.Substring($p + 1)
        $last = [int][string]$keep[$keep.Length - 1]
        $up = ($r -gt 5) -or ($r -eq 5 -and (($rest -cmatch '[1-9]') -or ($last % 2) -eq 1))
        if ($up) {
            $chars = $keep.ToCharArray(); $k = $chars.Length - 1; $carry = $true
            while ($carry -and $k -ge 0) {
                if ([string]$chars[$k] -ceq '9') { $chars[$k] = [char]'0'; $k-- } else { $chars[$k] = [char]([int]$chars[$k] + 1); $carry = $false }
            }
            $keep = -join $chars; if ($carry) { $keep = '1' + $keep }
        }
        $intD = $keep.Substring(0, $keep.Length - $p); $fracD = $keep.Substring($keep.Length - $p)
    }
    $intD = $intD.TrimStart('0'); if ($intD -eq '') { $intD = '0' }
    $out = $intD; if ($p -gt 0) { $out = "$intD.$fracD" }
    if ($neg) { $out = "-$out" }
    $out
}
function LgNumStr($v) {                                 # a number as Perl prints it (%.15g)
    $d = [double]$v
    if ($d -lt 1e15 -and $d -gt -1e15 -and $d -eq [double][long]$d) { return ([long]$d).ToString($script:LG_INV) }
    $d.ToString('G15', $script:LG_INV).Replace('E', 'e')
}
function LgPad([string]$s, [int]$w) { $s.PadLeft($w) }     # %*s
function LgPadR([string]$s, [int]$w) { $s.PadRight($w) }   # %-*s
function LgTruthy($x) {                                # Perl truth: undef, '', '0' and 0 are false
    if ($null -eq $x) { return $false }
    if ($x -is [string]) { return -not ($x -ceq '' -or $x -ceq '0') }
    if ($x -is [int] -or $x -is [long] -or $x -is [double]) { return $x -ne 0 }
    $true
}
function LgSW([string]$s, [string]$p) { $s.Length -ge $p.Length -and $s.Substring(0, $p.Length) -ceq $p }   # ordinal StartsWith

# ================================================================ ordering (Prelude::compare / sorted: a stable merge sort)
$script:LG_NUMRE = '^\s*[-+]?(?:(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*$'
function LgIsNum($x) {
    if ($null -eq $x) { return $false }
    if ($x -is [double] -or $x -is [int] -or $x -is [long]) { return $true }
    ($x -is [string]) -and ($x -cmatch $script:LG_NUMRE)
}
function LgCmp($x, $y) {
    if ((LgIsNum $x) -and (LgIsNum $y)) { $a = [double]$x; $b = [double]$y; if ($a -lt $b) { return -1 }; if ($a -gt $b) { return 1 }; return 0 }
    $c = [string]::CompareOrdinal([string]$x, [string]$y)
    if ($c -lt 0) { -1 } elseif ($c -gt 0) { 1 } else { 0 }
}
function LgSortWith($list, [scriptblock]$cmp) {
    $src = @($list); $n = $src.Count
    if ($n -lt 2) { return , $src }
    $w = 1
    while ($w -lt $n) {
        $src = @(for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
                $mid = $lo + $w; if ($mid -gt $n) { $mid = $n }
                $hi = $lo + 2 * $w; if ($hi -gt $n) { $hi = $n }
                $i = $lo; $j = $mid
                while ($i -lt $mid -and $j -lt $hi) {
                    if ((& $cmp $src[$j] $src[$i]) -lt 0) { , $src[$j]; $j++ } else { , $src[$i]; $i++ }
                }
                while ($i -lt $mid) { , $src[$i]; $i++ }
                while ($j -lt $hi) { , $src[$j]; $j++ }
            })
        $w *= 2
    }
    , $src
}
function LgSorted($list) { LgSortWith $list { param($a, $b) LgCmp $a $b } }
function LgSLt([string]$a, [string]$b) { [string]::CompareOrdinal($a, $b) -lt 0 }    # Perl lt / gt / ge on strings
function LgSGt([string]$a, [string]$b) { [string]::CompareOrdinal($a, $b) -gt 0 }
function LgSGe([string]$a, [string]$b) { [string]::CompareOrdinal($a, $b) -ge 0 }
function LgNub($list) { $seen = [hashtable]::new(); , @(foreach ($x in @($list)) { if (-not $seen.ContainsKey($x)) { $seen[$x] = 1; $x } }) }
function LgMaximum($list) { $m = $null; $first = $true; foreach ($x in @($list)) { if ($first -or (LgCmp $x $m) -ge 0) { $m = $x; $first = $false } }; $m }
function LgKeys($h) { , @(foreach ($k in $h.Keys) { $k }) }

# ================================================================ amounts  {commodity => number}
function LgNewAmt { [hashtable]::new() }
function LgParseAmount($s) {                            # "$-1,234.56"  "-12.5 USD"  '10 "big thing"'  -> amount or $null
    if ($null -eq $s -or $s -notmatch '\S') { return $null }
    $s = $s.Trim()
    if ($s -cnotmatch '^(-)?\s*([^\s\d\-+.,"]+)?\s*(-)?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*([A-Za-z]\w*|"[^"]*")?$') { return $null }
    $m = $Matches
    $c = ''; if ($null -ne $m[2]) { $c = $m[2] } elseif ($null -ne $m[5]) { $c = $m[5] }
    $c = $c -creplace '^"|"$', ''
    $n = $m[4] -creplace ',', ''
    $dec = 0; if ($n -cmatch '\.(\d+)') { $dec = $Matches[1].Length }
    if (-not $script:LG_PREC.ContainsKey($c) -or $dec -gt $script:LG_PREC[$c]) { $script:LG_PREC[$c] = $dec }
    $v = [double]$n
    if ($null -ne $m[1] -or $null -ne $m[3]) { $v = - $v }
    $a = LgNewAmt; $a[$c] = $v; $a
}
function LgAmtAdd($x, $y) { $r = LgNewAmt; foreach ($k in $x.Keys) { $r[$k] = [double]$x[$k] }; foreach ($k in $y.Keys) { if ($r.ContainsKey($k)) { $r[$k] = $r[$k] + $y[$k] } else { $r[$k] = 0.0 + $y[$k] } }; $r }
function LgAmtNeg($x) { $r = LgNewAmt; foreach ($k in $x.Keys) { $r[$k] = - $x[$k] }; $r }
function LgAmtSub($x, $y) { LgAmtAdd $x (LgAmtNeg $y) }
function LgAmtScale($x, $k) { $r = LgNewAmt; foreach ($c in $x.Keys) { $r[$c] = $x[$c] * $k }; $r }
function LgTol { $p = 2; foreach ($v in $script:LG_PREC.Values) { if ($v -gt $p) { $p = $v } }; 0.5 * (1.0 / (LgPow10 $p)) }
function LgAmtZero($x) { $t = LgTol; foreach ($v in $x.Values) { if ((LgAbs $v) -gt $t) { return $false } }; $true }
function LgAbs($v) { if ($v -lt 0) { - $v } else { $v } }
function LgCommas([string]$s) { do { $o = $s; $s = $s -creplace '^(-?\d+)(\d{3})', '$1,$2' } while ($s -cne $o); $s }
function LgFormatAmount($a) {                           # {'$'=>-42.17} -> "$-42.17"; {USD=>5}->"5.00 USD"; {}->"0"
    $t = LgTol
    $parts = @(foreach ($c in (LgSorted (LgKeys $a))) {
            $v = $a[$c]
            if ((LgAbs $v) -lt $t) { continue }
            $p = 2; if ($script:LG_PREC.ContainsKey($c)) { $p = $script:LG_PREC[$c] }
            $n = LgCommas (LgFmtF $v $p)
            if ($c -eq '') { $n } elseif ($c -cmatch '^[A-Za-z]') { "$n $c" } elseif ($c -cmatch '\s') { "$n `"$c`"" } else { "$c$n" }
        })
    if ($parts.Count) { $parts -join ', ' } else { '0' }
}
function LgNum1($x) { foreach ($c in (LgSorted (LgKeys $x))) { return , @($x[$c], $c) }; , @(0, $null) }   # _num: the first commodity's value

# ================================================================ dates
function LgD2([int]$n) { ([string]$n).PadLeft(2, '0') }
function LgD4([int]$n) { ([string]$n).PadLeft(4, '0') }
function LgNormDate($d) {                               # 2026/9/3 -> 2026-09-03 ; $null if not a date
    if ($null -eq $d -or $d -cnotmatch '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$') { return $null }
    $m = [int]$Matches[2]; $dd = [int]$Matches[3]
    if ($m -lt 1 -or $m -gt 12 -or $dd -lt 1 -or $dd -gt 31) { return $null }
    $Matches[1] + '-' + ([string]$m).PadLeft(2, '0') + '-' + ([string]$dd).PadLeft(2, '0')
}
function LgAddMonths($y, $m, $k) { $m = [long]$m + $k - 1; , @(([long]$y + (LgTrunc ($m / 12))), ((LgPerlMod $m 12) + 1)) }
function LgPeriodRange([string]$p) {                    # '2026' | '2026-09' | '2026-Q3' -> (begin, end)  end exclusive
    if ($p -cmatch '^(\d{4})$') { $y = [int]$Matches[1]; return , @("$(LgD4 $y)-01-01", "$(LgD4 ($y + 1))-01-01") }
    if ($p -cmatch '^(\d{4})[-/]?(\d{1,2})$') {
        $y = [int]$Matches[1]; $m = [int]$Matches[2]; $n = LgAddMonths $y $m 1
        return , @("$(LgD4 $y)-$(LgD2 $m)-01", "$(LgD4 $n[0])-$(LgD2 $n[1])-01")
    }
    if ($p -cmatch '^(\d{4})[-/]?[Qq]([1-4])$') {
        $y = [int]$Matches[1]; $m = ([int]$Matches[2] - 1) * 3 + 1; $n = LgAddMonths $y $m 3
        return , @("$(LgD4 $y)-$(LgD2 $m)-01", "$(LgD4 $n[0])-$(LgD2 $n[1])-01")
    }
    LgDie "bad period '$p' (want YYYY, YYYY-MM or YYYY-Qn)`n"
}
function LgYmd([string]$d) { $x = $d.Split('-'); , @([long]$x[0], [long]$x[1], [long]$x[2]) }
function LgMonthsBetween($b, $e) {
    $x = LgYmd $b; $y = LgYmd $e
    $n = ($y[0] * 12 + $y[1]) - ($x[0] * 12 + $x[1])
    if ($y[2] -gt $x[2]) { $n++ }
    if ($n -lt 1) { 1 } else { $n }
}
function LgTodayYmd { $t = Get-Date; "$(LgD4 $t.Year)-$(LgD2 $t.Month)-$(LgD2 $t.Day)" }
function LgThisMonth { $t = Get-Date; "$(LgD4 $t.Year)-$(LgD2 $t.Month)" }
function LgNextMonth([string]$d) { $y = [long]$d.Substring(0, 4); $m = [long]$d.Substring(5, 2); $n = LgAddMonths $y $m 1; "$(LgD4 $n[0])-$(LgD2 $n[1])-01" }
function LgMonthStarts($b, $e) {                        # ('2026-10-05', '2027-01-01') -> ('2026-10-01', '2026-11-01', '2026-12-01')
    $s = $b.Substring(0, 8) + '01'
    , @(while ((LgSLt $s $e)) { $s; $s = LgNextMonth $s })
}
function LgDayNumber([string]$d) {                      # days since 1970-01-01 (civil calendar)
    $x = LgYmd $d; $y = $x[0]; $m = $x[1]; $dd = $x[2]
    if ($m -le 2) { $y-- }
    $era = LgFloorDiv $y 400; $yoe = $y - $era * 400
    $mp = $m + 9; if ($m -gt 2) { $mp = $m - 3 }
    $doy = (LgFloorDiv (153 * $mp + 2) 5) + $dd - 1
    $doe = $yoe * 365 + (LgFloorDiv $yoe 4) - (LgFloorDiv $yoe 100) + $doy
    $era * 146097 + $doe - 719468
}
function LgAddDays([string]$d, $n) {
    $z = (LgDayNumber $d) + [long]$n + 719468
    $era = LgFloorDiv $z 146097; $doe = $z - $era * 146097
    $yoe = LgFloorDiv ($doe - (LgFloorDiv $doe 1460) + (LgFloorDiv $doe 36524) - (LgFloorDiv $doe 146096)) 365
    $y = $yoe + $era * 400
    $doy = $doe - (365 * $yoe + (LgFloorDiv $yoe 4) - (LgFloorDiv $yoe 100))
    $mp = LgFloorDiv (5 * $doy + 2) 153
    $dd = $doy - (LgFloorDiv (153 * $mp + 2) 5) + 1
    $m = $mp - 9; if ($mp -lt 10) { $m = $mp + 3 }
    if ($m -le 2) { $y++ }
    "$(LgD4 $y)-$(LgD2 $m)-$(LgD2 $dd)"
}
function LgMonthFraction($ms, $b, $e) {                 # the share of the month starting ms inside [b, e)
    $me = LgNextMonth $ms
    $lo = $ms; if ($null -ne $b -and (LgSGt $b $ms)) { $lo = $b }
    $hi = $me; if ($null -ne $e -and (LgSLt $e $me)) { $hi = $e }
    if (LgSGe $lo $hi) { return 0 }
    ((LgDayNumber $hi) - (LgDayNumber $lo)) / [double]((LgDayNumber $me) - (LgDayNumber $ms))
}
function LgPeriodicWindow([string]$p) {                 # 'Monthly from 2026-10-01 to 2027-01-01' -> (kind, from, to)
    $kind = ''; if ($p -match '^(\w+)') { $kind = $Matches[1].ToLowerInvariant() }
    $from = $null; if ($p -match '\bfrom\s+(\d[\d/.-]*)') { $from = LgNormDate $Matches[1] }
    $to = $null; if ($p -match '\b(?:to|until)\s+(\d[\d/.-]*)') { $to = LgNormDate $Matches[1] }
    , @($kind, $from, $to)
}
function LgPlanMonths($period, $beg, $end, $whole) {
    $w = LgPeriodicWindow $period; $from = $w[1]; $to = $w[2]
    if (-not ($from -or $to)) { if ($null -ne $whole) { return $whole }; return (LgMonthsBetween $beg $end) }
    $lo = $from; if (-not $from -or (LgSGt $beg $from)) { $lo = $beg }
    $hi = $to; if (-not $to -or (LgSLt $end $to)) { $hi = $end }
    if (LgSGe $lo $hi) { return 0 }
    $s = 0; foreach ($ms in (LgMonthStarts $lo $hi)) { $s = $s + (LgMonthFraction $ms $lo $hi) }; $s
}

# ================================================================ reading
function LgReadText([string]$path) {                    # the file as text, or $null; a UTF-8 BOM dropped; Windows-1252 when not UTF-8
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    if ($t.Contains([string][char]0xFFFD)) { $t = Get-Content -LiteralPath $path -Raw -Encoding Default; if ($null -eq $t) { $t = '' } }
    $t
}
function LgReadJournal([string]$file) {
    $text = LgReadText $file
    if ($null -eq $text) { throw "JOURNAL:cannot open ${file}: No such file or directory`n" }
    $j = @{ txns = (LgNewList); periodic = (LgNewList); prices = (LgNewList); errors = (LgNewList) }
    LgParseInto $j $text $file
    $j.txns = LgToArray $j.txns; $j.periodic = LgToArray $j.periodic; $j.prices = LgToArray $j.prices; $j.errors = LgToArray $j.errors
    LgBalanceAll $j
    if ($j.errors.Count) { throw ("JOURNAL:" + (@(foreach ($e in $j.errors) { "$e`n" }) -join '')) }
    # postings() sorts by date every time: sort once (stable), dates being normalised strings
    $byDate = @{}; $dates = LgNewList
    foreach ($t in $j.txns) { if (-not $byDate.ContainsKey($t.date)) { $byDate[$t.date] = LgNewList; LgPush $dates $t.date }; LgPush $byDate[$t.date] $t }
    $ds = LgSortWith (LgToArray $dates) { param($a, $b) [string]::CompareOrdinal($a, $b) }
    $j.sorted = @(foreach ($d in $ds) { $l = $byDate[$d]; for ($i = 0; $i -lt $l.Count; $i++) { , $l[$i] } })
    $j
}
function LgTrim($s) { if ($null -eq $s) { return '' }; $s -creplace '^\s+|\s+$', '' }
function LgParseInto($j, [string]$text, [string]$file) {
    $lines = @($text -split "\r?\n")
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '') {    # Perl's split drops trailing empty fields
        $k = $lines.Count; while ($k -gt 0 -and $lines[$k - 1] -eq '') { $k-- }
        if ($k -eq 0) { $lines = @() } else { $lines = $lines[0..($k - 1)] }
    }
    $n = $lines.Count; $i = 0
    while ($i -lt $n) {
        $ln = $i + 1; $line = $lines[$i]; $i++
        if ($line -cmatch '^\s*$' -or $line -cmatch '^[;#%|*]') { continue }
        if ($line -cmatch '^\s') { LgPush $j.errors "${file}:${ln}: unexpected indented line"; continue }
        $b0 = $i
        while ($i -lt $n -and $lines[$i] -cmatch '^\s+\S') { $i++ }
        $block = @(for ($q = $b0; $q -lt $i; $q++) { , @(($q + 1), $lines[$q]) })
        if ($line -cmatch '^(\d[\d/.-]*)(?:=(\d[\d/.-]*))?\s+(?:([*!])\s+)?(.*?)\s*(?:;(.*))?$') {
            $m = $Matches
            $date = LgNormDate $m[1]
            if (-not $date) { LgPush $j.errors "${file}:${ln}: bad date '$($m[1])'"; continue }
            $st = ''; if ($null -ne $m[3]) { $st = $m[3] }
            $t = @{ date = $date; status = $st; payee = $m[4]; comment = (LgTrim $m[5]); line = $ln; file = $file; postings = @(); period = $null }
            LgParsePostings $t $block $j $file
            $j.txns[$j.txns.Count] = $t
        }
        elseif ($line -cmatch '^~\s*(.*?)\s*$') {
            $t = @{ period = $Matches[1]; line = $ln; file = $file; postings = @() }
            LgParsePostings $t $block $j $file
            LgPush $j.periodic $t
        }
        elseif ($line -cmatch '^P\s+(\S+)\s+(?:\d\d:\d\d(?::\d\d)?\s+)?(\S+)\s+(.*)$') {
            $pd = $Matches[1]; $pc = $Matches[2]; $amt = LgParseAmount $Matches[3]
            $nd = LgNormDate $pd; if (-not $nd) { $nd = $pd }
            if ($amt) { LgPush $j.prices @{ date = $nd; commodity = $pc; price = $amt } }
        }
        elseif ($line -cmatch '^!?include\s+(.+?)\s*$') {
            $inc = $Matches[1]
            $dir = $file -creplace '[^/\\]*$', ''
            if ($dir -ne '' -and $inc -cnotmatch '^(/|[A-Za-z]:)') { $inc = "$dir$inc" }
            $t = LgReadText $inc
            if ($null -ne $t) { LgParseInto $j $t $inc } else { LgPush $j.errors "${file}:${ln}: cannot include '$inc': No such file or directory" }
        }
        elseif ($line -cmatch '^comment\b') {
            while ($i -lt $n -and $lines[$i] -cnotmatch '^end comment\b') { $i++ }
            $i++
        }
        elseif ($line -cmatch '^=' -or $line -cmatch '^(?:account|commodity|payee|tag|year|Y|apply|end|bucket|A|N|D|C|alias|define|assert|check)\b') { continue }
        else { LgPush $j.errors "${file}:${ln}: unrecognised line: $line" }
    }
}
function LgParsePostings($t, $block, $j, $file) {
    $ps = @{}
    foreach ($b in $block) {
        $ln = $b[0]; $body = $b[1].TrimStart()
        $cmt = ''
        $sc = $body.IndexOf(';')
        if ($sc -ge 0) { $cmt = $body.Substring($sc + 1).Trim(); $body = $body.Substring(0, $sc).TrimEnd() }
        if ($body -eq '') { continue }
        $acct = $body; $rest = $null
        if ($body -cmatch '^(.*?)(?:\s{2,}|\t)\s*(.*)$') { $acct = $Matches[1]; $rest = $Matches[2] }
        $virtual = ''                                  # Perl's 0: not virtual
        if ($acct.StartsWith('(') -or $acct.StartsWith('[')) {
            if ($acct -cmatch '^\((.*)\)$') { $acct = $Matches[1]; $virtual = 'unbalanced' }
            elseif ($acct -cmatch '^\[(.*)\]$') { $acct = $Matches[1]; $virtual = 'balanced' }
        }
        $acct = $acct.Trim()
        $amount = $null; $cost = $null
        if ($null -ne $rest -and $rest -cmatch '\S') {
            if ($rest.Contains('=')) { $rest = $rest -creplace '\s*=.*$', '' }
            if ($rest.Contains('@')) { $null = $rest -cmatch '^(.*?)\s*(?:(@@?)\s*(.*))?$'; $amt_s = $Matches[1]; $at = $Matches[2]; $price_s = $Matches[3] }
            else { $amt_s = $rest.TrimEnd(); $at = $null; $price_s = $null }
            $amount = LgParseAmount $amt_s
            if (-not $amount) { LgPush $j.errors "${file}:${ln}: bad amount '$amt_s'"; continue }
            if ($at) {
                $p = LgParseAmount $price_s
                if (-not $p) { LgPush $j.errors "${file}:${ln}: bad price '$price_s'"; continue }
                $qc = @($amount.Keys)[0]; $pc = @($p.Keys)[0]
                $cost = LgNewAmt
                if ($at -ceq '@') { $cost[$pc] = $amount[$qc] * $p[$pc] }
                else { $sg = 1; if ($amount[$qc] -lt 0) { $sg = -1 }; $cost[$pc] = $sg * $p[$pc] }
            }
        }
        $ps[$ps.Count] = @{ account = $acct; amount = $amount; cost = $cost; virtual = $virtual; comment = $cmt; line = $ln }
    }
    $t.postings = @(for ($q = 0; $q -lt $ps.Count; $q++) { $ps[$q] })
}
function LgBalanceAll($j) {
    $errs = LgNewList; foreach ($e in $j.errors) { LgPush $errs $e }
    $tol = LgTol
    foreach ($t in @($j.txns) + @($j.periodic)) {
        $sum = [hashtable]::new(); $elided = @{}
        foreach ($p in $t.postings) {
            if ($p.virtual -ceq 'unbalanced') { continue }
            if ($p.amount) {
                $x = $p.amount; if ($p.cost) { $x = $p.cost }
                foreach ($c in $x.Keys) { if ($sum.ContainsKey($c)) { $sum[$c] = $sum[$c] + $x[$c] } else { $sum[$c] = 0.0 + $x[$c] } }
            }
            else { $elided[$elided.Count] = $p }
        }
        if ($elided.Count -gt 1) { LgPush $errs "$($t.file):$($t.line): more than one posting without an amount"; continue }
        if ($elided.Count -eq 1) { $elided[0].amount = LgAmtNeg $sum; continue }
        if ($null -ne $t.period -and $t.period -cne '' -and $t.period -cne '0') { continue }
        $off = $false; foreach ($v in $sum.Values) { if ($v -gt $tol -or $v -lt - $tol) { $off = $true } }
        if ($off) { LgPush $errs "$($t.file):$($t.line): transaction does not balance (off by $(LgFormatAmount $sum))" }
    }
    $j.errors = LgToArray $errs
}

# ================================================================ queries
# Postings($j, @{ begin; end; period; account (regex); payee (regex); cleared; real })
function LgPostings($j, $f) {
    $beg = $f.begin; $end = $f.end
    if (LgTruthy $f.period) { $r = LgPeriodRange $f.period; $beg = $r[0]; $end = $r[1] }
    , @(foreach ($t in $j.sorted) {
            if ($beg -and (LgSLt $t.date $beg)) { continue }
            if ($end -and (LgSGe $t.date $end)) { continue }
            if ($f.cleared -and $t.status -cne '*') { continue }
            if ($null -ne $f.payee -and $t.payee -notmatch $f.payee) { continue }
            foreach ($p in $t.postings) {
                if ($f.real -and $p.virtual -cne '') { continue }
                if ($null -ne $f.account -and $p.account -notmatch $f.account) { continue }
                @{ date = $t.date; payee = $t.payee; status = $t.status; account = $p.account; amount = $p.amount; virtual = $p.virtual; comment = $p.comment }
            }
        })
}
function LgBalances($ps) {                              # account => amount, own postings only
    $b = [hashtable]::new()
    foreach ($p in $ps) { $cur = $b[$p.account]; if ($null -eq $cur) { $cur = LgNewAmt }; $b[$p.account] = LgAmtAdd $cur $p.amount }
    $b
}
function LgBalanceTree($own) {                          # every account and every ancestor, totals rolled up
    $t = [hashtable]::new()
    foreach ($a in $own.Keys) {
        $parts = $a.Split(':'); $node = ''
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($i -eq 0) { $node = $parts[0] } else { $node = $node + ':' + $parts[$i] }
            $cur = $t[$node]; if ($null -eq $cur) { $cur = LgNewAmt }; $t[$node] = LgAmtAdd $cur $own[$a]
        }
    }
    $t
}
function LgRegister($ps) { $run = LgNewAmt; , @(foreach ($p in $ps) { $run = LgAmtAdd $run $p.amount; $r = $p.Clone(); $r.running = $run; $r }) }
function LgPrefixed([string]$acct, [string]$a) { ($acct -ceq $a) -or (LgSW $acct "${a}:") }
function LgBudget($j, $f) {
    if (LgTruthy $f.period) { $r = LgPeriodRange $f.period; $beg = $r[0]; $end = $r[1] } else { $beg = $f.begin; $end = $f.end }
    if (-not ($beg -and $end)) { LgDie "budget: need period or begin+end`n" }
    $months = LgMonthsBetween $beg $end
    $planned = [hashtable]::new()
    foreach ($t in $j.periodic) {
        $k = $null
        if ($t.period -match '^month') { $k = 1 } elseif ($t.period -match '^year') { $k = 1 / 12 } elseif ($t.period -match '^week') { $k = 52 / 12 }
        if ($null -eq $k) { continue }
        $span = LgPlanMonths $t.period $beg $end $months
        foreach ($p in $t.postings) {
            if (-not $p.amount) { continue }
            $a = $p.amount
            if ($a[@($a.Keys)[0]] -lt 0 -and $p.account -match '^(Assets|Liabilities|Equity|Income)\b') { continue }
            $cur = $planned[$p.account]; if ($null -eq $cur) { $cur = LgNewAmt }
            $planned[$p.account] = LgAmtAdd $cur (LgAmtScale $a ($k * $span))
        }
    }
    $accts = LgSorted (LgKeys $planned)
    $ps = LgPostings $j @{ begin = $beg; end = $end; real = 1 }
    $actual = [hashtable]::new(); $unb = LgNewAmt
    $roots = [hashtable]::new(); foreach ($a in $accts) { $roots[$a.Split(':')[0]] = 1 }
    foreach ($p in $ps) {
        $hit = $false
        foreach ($a in $accts) {
            if (LgPrefixed $p.account $a) { $cur = $actual[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $actual[$a] = LgAmtAdd $cur $p.amount; $hit = $true; break }
        }
        if ($hit) { continue }
        if ($roots.ContainsKey($p.account.Split(':')[0])) { $unb = LgAmtAdd $unb $p.amount }
    }
    $rows = @(foreach ($a in $accts) {
            $bud = $planned[$a]; $act = $actual[$a]; if ($null -eq $act) { $act = LgNewAmt }
            @{ account = $a; budget = $bud; actual = $act; remaining = (LgAmtSub $bud $act) }
        })
    @{ rows = $rows; unbudgeted = $unb; months = $months; begin = $beg; end = $end }
}

# ================================================================ reports (return text)
function LgLeaf([string]$a) { $x = $a.Split(':'); $x[$x.Count - 1] }
function LgReportBal($j, $f) {
    $depth = $f.depth
    $ps = LgPostings $j $f
    $own = LgBalances $ps
    $tree = LgBalanceTree $own
    $kids = [hashtable]::new()
    foreach ($k in $tree.Keys) {
        $par = ''; if ($k -cmatch '^(.*):[^:]+$') { $par = $Matches[1] }
        if (-not $kids.ContainsKey($par)) { $kids[$par] = LgNewList }
        LgPush $kids[$par] $k
    }
    $lines = LgNewList
    $script:LG_walk = {
        param($node, $level, $shown)
        $label = $shown
        while ($kids.ContainsKey($node) -and $kids[$node].Count -eq 1 -and (LgAmtZero $(if ($own.ContainsKey($node)) { $own[$node] } else { LgNewAmt }))) {
            $only = $kids[$node][0]
            $label = $label + ':' + (LgLeaf $only)
            $node = $only
        }
        if ($null -ne $depth -and $level -ge $depth) { return }
        if ((LgAmtZero $tree[$node]) -and -not $f.empty) { return }
        LgPush $lines @((LgFormatAmount $tree[$node]), (('  ' * $level) + $label))
        if ($kids.ContainsKey($node)) { foreach ($c in (LgSorted (LgToArray $kids[$node]))) { & $script:LG_walk $c ($level + 1) (LgLeaf $c) } }
    }
    $total = LgNewAmt
    if ($kids.ContainsKey('')) { foreach ($root in (LgSorted (LgToArray $kids['']))) { & $script:LG_walk $root 0 $root; $total = LgAmtAdd $total $tree[$root] } }
    $lines = LgToArray $lines
    $w = LgMaximum (@(20) + @(foreach ($l in $lines) { $l[0].Length }))
    (@(foreach ($l in $lines) { (LgPad $l[0] $w) + '  ' + $l[1] + "`n" }) -join '') + ('-' * $w) + "`n" + (LgPad (LgFormatAmount $total) $w) + "`n"
}
function LgReportReg($j, $f) {
    $rows = LgRegister (LgPostings $j $f)
    if (-not $rows.Count) { return '' }
    $wp = LgMaximum @(foreach ($r in $rows) { $r.payee.Length }); if ($wp -gt 30) { $wp = 30 }
    $wa = LgMaximum @(foreach ($r in $rows) { $r.account.Length })
    $out = @(foreach ($r in $rows) { $py = $r.payee; if ($py.Length -gt 30) { $py = $py.Substring(0, 30) }; , @($r.date, $py, $r.account, (LgFormatAmount $r.amount), (LgFormatAmount $r.running)) })
    $w1 = LgMaximum @(foreach ($o in $out) { $o[3].Length }); $w2 = LgMaximum @(foreach ($o in $out) { $o[4].Length })
    (@(foreach ($o in $out) { $o[0] + ' ' + (LgPadR $o[1] $wp) + ' ' + (LgPadR $o[2] $wa) + ' ' + (LgPad $o[3] $w1) + ' ' + (LgPad $o[4] $w2) + "`n" }) -join '')
}
function LgReportBudget($j, $f) {
    $r = LgBudget $j $f
    $rows = LgNewList
    foreach ($x in $r.rows) { LgPush $rows @($x.account, (LgFormatAmount $x.budget), (LgFormatAmount $x.actual), (LgFormatAmount $x.remaining)) }
    $tb = LgNewAmt; $ta = LgNewAmt
    foreach ($x in $r.rows) { $tb = LgAmtAdd $tb $x.budget; $ta = LgAmtAdd $ta $x.actual }
    if (-not (LgAmtZero $r.unbudgeted)) { LgPush $rows @('Unbudgeted', '', (LgFormatAmount $r.unbudgeted), '') }
    $rows = LgToArray $rows
    $ta = LgAmtAdd $ta $r.unbudgeted
    $tot = @('Total', (LgFormatAmount $tb), (LgFormatAmount $ta), (LgFormatAmount (LgAmtSub $tb $ta)))
    $hd = @('Account', 'Budget', 'Actual', 'Remaining')
    $all = @(, $hd) + $rows + @(, $tot)
    $w = @(foreach ($i in 0..3) { LgMaximum @(foreach ($x in $all) { $x[$i].Length }) })
    $line = { param($x) (LgPadR $x[0] $w[0]) + '  ' + (LgPad $x[1] $w[1]) + '  ' + (LgPad $x[2] $w[2]) + '  ' + (LgPad $x[3] $w[3]) + "`n" }
    $mo = 's'; if ($r.months -eq 1) { $mo = '' }
    $hdr = "Budget for $($r.begin) to $($r.end) ($($r.months) month$mo)`n"
    $hdr + (& $line $hd) + (@(foreach ($x in $rows) { & $line $x }) -join '') + ('-' * ($w[0] + $w[1] + $w[2] + $w[3] + 6)) + "`n" + (& $line $tot)
}
function LgCsvQ([string]$s) { if ($s -cmatch "[`",`n]") { '"' + $s.Replace('"', '""') + '"' } else { $s } }
function LgToCsv($ps) {
    $out = @("date,status,payee,account,amount,commodity`n")
    $out += @(foreach ($p in $ps) { foreach ($c in (LgSorted (LgKeys $p.amount))) { (@($p.date, $p.status, (LgCsvQ $p.payee), (LgCsvQ $p.account), (LgNumStr $p.amount[$c]), (LgCsvQ $c)) -join ',') + "`n" } })
    $out -join ''
}

# ---------------------------------------------------------------- per month (-M)
function LgRange2($j, $f) {                              # the report window: --period, --begin/--end, else first posting .. day after the last
    if (LgTruthy $f.period) { return (LgPeriodRange $f.period) }
    if (-not $j.sorted.Count) { return , @() }
    $b = $f.begin; if ($null -eq $b) { $b = $j.sorted[0].date }
    $e = $f.end; if ($null -eq $e) { $e = LgAddDays $j.sorted[$j.sorted.Count - 1].date 1 }
    , @($b, $e)
}
function LgAtDepth([string]$a, $d) {
    if ($null -eq $d) { return $a }
    $x = $a.Split(':'); (@(for ($i = 0; $i -lt $d -and $i -lt $x.Count; $i++) { $x[$i] }) -join ':')
}
function LgTable($rows) {                               # first column left, the rest right-aligned; trailing spaces dropped
    $w = @{}
    foreach ($r in $rows) { for ($i = 0; $i -lt $r.Count; $i++) { $l = ([string]$r[$i]).Length; if (-not $w.ContainsKey($i) -or $l -gt $w[$i]) { $w[$i] = $l } } }
    (@(foreach ($r in $rows) {
            $cells = @(for ($i = 0; $i -lt $r.Count; $i++) { if ($i -eq 0) { LgPadR ([string]$r[0]) $w[0] } else { LgPad ([string]$r[$i]) $w[$i] } })
            ($cells -join '  ') -creplace '\s+$', ''
        }) | ForEach-Object { $_ + "`n" }) -join ''
}
function LgSubF($f, $b, $e) { $g = $f.Clone(); $g.begin = $b; $g.end = $e; $g.period = $null; $g }
function LgReportBalMonthly($j, $f) {
    $r = LgRange2 $j $f; if (-not $r.Count) { return '' }
    $ms = LgMonthStarts $r[0] $r[1]
    $cell = [hashtable]::new(); $tot = [hashtable]::new()
    foreach ($p in (LgPostings $j (LgSubF $f $r[0] $r[1]))) {
        $a = LgAtDepth $p.account $f.depth; $m = $p.date.Substring(0, 7)
        if (-not $cell.ContainsKey($a)) { $cell[$a] = [hashtable]::new(); $tot[$a] = LgNewAmt }
        $cur = $cell[$a][$m]; if ($null -eq $cur) { $cur = LgNewAmt }
        $cell[$a][$m] = LgAmtAdd $cur $p.amount
        $tot[$a] = LgAmtAdd $tot[$a] $p.amount
    }
    $rows = LgNewList
    LgPush $rows (@('Account') + @(foreach ($x in $ms) { $x.Substring(0, 7) }) + @('Total'))
    foreach ($a in (LgSorted (LgKeys $cell))) {
        $nz = $false; foreach ($v in $cell[$a].Values) { if (-not (LgAmtZero $v)) { $nz = $true } }
        if ((LgAmtZero $tot[$a]) -and -not $f.empty -and -not $nz) { continue }
        LgPush $rows (@($a) + @(foreach ($x in $ms) { $c = $cell[$a][$x.Substring(0, 7)]; if ($c -and -not (LgAmtZero $c)) { LgFormatAmount $c } else { '' } }) + @(LgFormatAmount $tot[$a]))
    }
    LgTable (LgToArray $rows)
}
function LgReportRegMonthly($j, $f) {
    $r = LgRange2 $j $f; if (-not $r.Count) { return '' }
    $m = [hashtable]::new()
    foreach ($p in (LgPostings $j (LgSubF $f $r[0] $r[1]))) {
        $a = LgAtDepth $p.account $f.depth; $k = $p.date.Substring(0, 7)
        if (-not $m.ContainsKey($k)) { $m[$k] = [hashtable]::new() }
        $cur = $m[$k][$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $m[$k][$a] = LgAmtAdd $cur $p.amount
    }
    $run = LgNewAmt
    $rows = LgNewList; LgPush $rows @('Month', 'Account', 'Amount', 'Running')
    foreach ($k in (LgSorted (LgKeys $m))) { foreach ($a in (LgSorted (LgKeys $m[$k]))) { $run = LgAmtAdd $run $m[$k][$a]; LgPush $rows @($k, $a, (LgFormatAmount $m[$k][$a]), (LgFormatAmount $run)) } }
    $rows = LgToArray $rows
    $w = @(foreach ($i in 0..3) { LgMaximum @(foreach ($x in $rows) { $x[$i].Length }) })
    (@(foreach ($x in $rows) { ((LgPadR $x[0] $w[0]) + '  ' + (LgPadR $x[1] $w[1]) + '  ' + (LgPad $x[2] $w[2]) + '  ' + (LgPad $x[3] $w[3])) -creplace '\s+$', '' }) | ForEach-Object { $_ + "`n" }) -join ''
}
function LgReportBudgetMonthly($j, $f) {
    $r = LgRange2 $j $f; if (-not $r.Count) { return '' }
    $rows = LgNewList; LgPush $rows @('Month', 'Account', 'Budget', 'Actual', 'Remaining')
    foreach ($ms in (LgMonthStarts $r[0] $r[1])) {
        $b = LgBudget $j @{ begin = $ms; end = (LgNextMonth $ms) }
        foreach ($row in $b.rows) {
            if ($null -ne $f.account -and $row.account -notmatch $f.account) { continue }
            if ((LgAmtZero $row.budget) -and (LgAmtZero $row.actual)) { continue }
            LgPush $rows @($ms.Substring(0, 7), $row.account, (LgFormatAmount $row.budget), (LgFormatAmount $row.actual), (LgFormatAmount $row.remaining))
        }
    }
    $rows = LgToArray $rows
    $w = @(foreach ($i in 0..4) { LgMaximum @(foreach ($x in $rows) { $x[$i].Length }) })
    (@(foreach ($x in $rows) { (LgPadR $x[0] $w[0]) + '  ' + (LgPadR $x[1] $w[1]) + '  ' + (LgPad $x[2] $w[2]) + '  ' + (LgPad $x[3] $w[3]) + '  ' + (LgPad $x[4] $w[4]) + "`n" }) -join '')
}

# ---------------------------------------------------------------- earned value and funding run-out
function LgReadComplete($pairs, $file) {
    $c = [hashtable]::new()
    $put = {
        param($a, $v, $where)
        $a = LgTrim $a; $v = LgTrim $v
        $v = $v -creplace '%$', ''
        if ($v -cnotmatch '^\d+(?:\.\d+)?$') { LgDie "${where}: percent complete for '$a' is not a number: '$v'`n" }
        $n = [double]$v
        if ($n -le 1 -and $v.Contains('.')) { $n = $n * 100; $v = LgNumStr $n }
        if ($n -gt 100) { LgDie "${where}: percent complete for '$a' is over 100: $v`n" }
        $c[$a] = $n / 100
    }
    foreach ($x in @($pairs)) {
        if ($null -eq $x) { continue }
        if ($x -cnotmatch '^(.+)=(.*)$') { LgDie "--complete wants ACCOUNT=PCT, got '$x'`n" }
        & $put $Matches[1] $Matches[2] '--complete'
    }
    if ($null -ne $file) {
        $t = LgReadText $file
        if ($null -eq $t) { LgDieErrno "cannot read ${file}: No such file or directory`n" }
        $ln = 0
        foreach ($l in @($t -split "\r?\n")) {
            $ln++
            if ($l -cmatch '^\s*(#|;|$)' -or ($ln -eq 1 -and $l -match '^\s*account\s*,')) { continue }
            if ($l -cnotmatch '^(.*),\s*([^,]*)$') { LgDie "${file}:${ln}: want 'account,pct'`n" }
            & $put $Matches[1] $Matches[2] "${file}:${ln}"
        }
    }
    $c
}
function LgPctFor($c, [string]$a) {
    $best = $null
    foreach ($k in $c.Keys) { if (LgPrefixed $a $k) { if ($null -eq $best -or $k.Length -gt $best.Length) { $best = $k } } }
    if ($null -eq $best) { $null } else { $c[$best] }
}
function LgEvmRow($a, $c, $bac, $bcws, $bcwp, $acwp, $pct) {
    $r = @{ account = $a; commodity = $c; bac = $bac; bcws = $bcws; bcwp = $bcwp; acwp = $acwp; pct = $pct; cv = $null; sv = $null; cpi = $null; spi = $null; eac = $null; etc = $null; vac = $null }
    if ($null -ne $bcwp) {
        $r.cv = $bcwp - $acwp
        $r.sv = $bcwp - $bcws
        if ($acwp) { $r.cpi = $bcwp / $acwp }
        if ($bcws) { $r.spi = $bcwp / $bcws }
        if ($r.cpi) { $r.eac = $bac / $r.cpi }
        if ($null -ne $r.eac) { $r.etc = $r.eac - $acwp; $r.vac = $bac - $r.eac }
    }
    $r
}
function LgEvm($j, $f) {
    $status = $f.status; if ($null -eq $status) { $status = LgTodayYmd }
    $bac = [hashtable]::new(); $pv = [hashtable]::new()
    foreach ($t in $j.periodic) {
        $w = LgPeriodicWindow $t.period; $kind = $w[0]; $from = $w[1]; $to = $w[2]
        $k = $null
        if ($kind -cmatch '^month') { $k = 1 } elseif ($kind -cmatch '^year') { $k = 1 / 12 } elseif ($kind -cmatch '^week') { $k = 52 / 12 }
        if ($null -eq $k) { continue }
        if (-not ($from -and $to)) { LgDie "evm: budget '~ $($t.period)' ($($t.file):$($t.line)) needs 'from DATE to DATE' to give a budget at completion`n" }
        $all = LgPlanMonths $t.period $from $to $null
        $now = 0; if (-not ((LgSLt $status $from) -or $status -ceq $from)) { $e = $to; if (LgSLt $status $to) { $e = $status }; $now = LgPlanMonths $t.period $from $e $null }
        foreach ($p in $t.postings) {
            if (-not $p.amount) { continue }
            $n = (LgNum1 $p.amount)[0]
            if ($n -lt 0) { continue }
            if ($null -ne $f.account -and $p.account -notmatch $f.account) { continue }
            $a = $p.account
            $cur = $bac[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $bac[$a] = LgAmtAdd $cur (LgAmtScale $p.amount ($k * $all))
            $cur = $pv[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $pv[$a] = LgAmtAdd $cur (LgAmtScale $p.amount ($k * $now))
        }
    }
    $accts = LgSorted (LgKeys $bac)
    $ac = [hashtable]::new()
    foreach ($p in (LgPostings $j @{ end = $status; real = 1 })) {
        foreach ($a in $accts) { if (LgPrefixed $p.account $a) { $cur = $ac[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $ac[$a] = LgAmtAdd $cur $p.amount; break } }
    }
    $complete = $f.complete; if ($null -eq $complete) { $complete = [hashtable]::new() }
    $rows = @(foreach ($a in $accts) {
            $x = LgNum1 $bac[$a]; $b = $x[0]; $c = $x[1]
            $bcws = (LgNum1 $pv[$a])[0]
            $acv = $ac[$a]; if ($null -eq $acv) { $acv = LgNewAmt }; $acwp = (LgNum1 $acv)[0]
            $pct = LgPctFor $complete $a
            $bcwp = $null; if ($null -ne $pct) { $bcwp = $b * $pct }
            LgEvmRow $a $c $b $bcws $bcwp $acwp $pct
        })
    $total = $null
    if ($rows.Count) {
        $c = $rows[0].commodity
        $tb = 0; $tw = 0; $tp = 0; $ta = 0; $known = $true
        foreach ($r in $rows) { $tb = $tb + $r.bac; $tw = $tw + $r.bcws; $ta = $ta + $r.acwp; if ($null -ne $r.bcwp) { $tp = $tp + $r.bcwp } else { $known = $false } }
        $tbcwp = $null; $tpct = $null
        if ($known) { $tbcwp = $tp; if ($tb) { $tpct = $tp / $tb } }
        $total = LgEvmRow 'Total' $c $tb $tw $tbcwp $ta $tpct
    }
    @{ status = $status; rows = $rows; total = $total }
}
function LgReportEvm($j, $f) {
    $e = LgEvm $j $f
    if (-not $e.rows.Count) { return "no dated budgets (~ Monthly from DATE to DATE) to measure against`n" }
    $m = { param($v, $c) if ($null -eq $v) { '-' } else { if ($null -eq $c) { $c = '$' }; $x = LgNewAmt; $x[$c] = $v; LgFormatAmount $x } }
    $x2 = { param($v) if ($null -eq $v) { '-' } else { LgFmtF $v 2 } }
    $rows = LgNewList
    LgPush $rows @('Account', '%done', 'BAC', 'BCWS', 'BCWP', 'ACWP', 'CV', 'SV', 'CPI', 'SPI', 'EAC', 'VAC')
    foreach ($r in @($e.rows) + @($e.total)) {
        $c = $r.commodity
        $pc = '-'; if ($null -ne $r.pct) { $pc = (LgFmtF (100 * $r.pct) 0) + '%' }
        LgPush $rows @($r.account, $pc, (& $m $r.bac $c), (& $m $r.bcws $c), (& $m $r.bcwp $c), (& $m $r.acwp $c), (& $m $r.cv $c), (& $m $r.sv $c), (& $x2 $r.cpi), (& $x2 $r.spi), (& $m $r.eac $c), (& $m $r.vac $c))
    }
    $missing = @($e.rows | Where-Object { $null -eq $_.pct }).Count
    $tail = ''
    if ($missing) { $s = 's'; if ($missing -eq 1) { $s = '' }; $tail = "($missing account$s without a percent complete: give --complete ACCOUNT=PCT or --complete-file)`n" }
    "Earned value as of $($e.status)`n" + (LgTable (LgToArray $rows)) + $tail
}
function LgForecast($j, $f) {
    $status = $f.status; if ($null -eq $status) { $status = LgTodayYmd }
    $n = $f.months; if ($null -eq $n) { $n = 3 }
    $win_end = $status.Substring(0, 8) + '01'
    $y = [long]$win_end.Substring(0, 4); $mm = [long]$win_end.Substring(5, 2)
    $x = LgAddMonths $y $mm (- [long]$n)
    $win_beg = "$(LgD4 $x[0])-$(LgD2 $x[1])-01"
    $bal = [hashtable]::new(); $burn = [hashtable]::new(); $first = [hashtable]::new()
    $ps = LgPostings $j @{ end = $status; real = 1 }
    foreach ($p in $ps) {
        if ($null -ne $f.account) { if ($f.cs) { if ($p.account -cnotmatch $f.account) { continue } } elseif ($p.account -notmatch $f.account) { continue } }
        $a = LgAtDepth $p.account $f.depth
        $cur = $bal[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $bal[$a] = LgAmtAdd $cur $p.amount
        if ((LgSGe $p.date $win_beg) -and (LgSLt $p.date $win_end) -and (LgNum1 $p.amount)[0] -lt 0) { $cur = $burn[$a]; if ($null -eq $cur) { $cur = LgNewAmt }; $burn[$a] = LgAmtAdd $cur $p.amount }
    }
    foreach ($p in $ps) { $a = LgAtDepth $p.account $f.depth; if (-not $first.ContainsKey($a)) { $first[$a] = $p.date.Substring(0, 8) + '01' } }
    $wm = LgMonthStarts $win_beg $win_end
    $rows = @(foreach ($a in (LgSorted (LgKeys $bal))) {
            $bx = LgNum1 $bal[$a]; $b = $bx[0]; $c = $bx[1]
            $bu = $burn[$a]; if ($null -eq $bu) { $bu = LgNewAmt }; $u = (LgNum1 $bu)[0]
            $k = @($wm | Where-Object { LgSGe $_ $first[$a] }).Count
            $rate = 0; if ($k) { $rate = (- $u) / $k }
            $r = @{ account = $a; commodity = $c; balance = $b; burn = $rate; months = $null; runout = $null }
            if ($rate -gt 0 -and $b -gt 0) { $r.months = $b / $rate; $r.runout = LgAddDays $status (LgTrunc ($r.months * 30.4375 + 0.5)) }
            $r
        })
    @{ status = $status; months = $n; window = @($win_beg, $win_end); rows = $rows }
}
function LgReportForecast($j, $f) {
    $r = LgForecast $j $f
    $rows = LgNewList; LgPush $rows @('Account', 'Balance', 'Burn/month', 'Months left', 'Runs out')
    foreach ($x in $r.rows) {
        $c = $x.commodity; if ($null -eq $c) { $c = '' }
        $ba = LgNewAmt; $ba[$c] = $x.balance
        $bu = 'not burning'; if ($x.burn -gt 0) { $bb = LgNewAmt; $bb[$c] = $x.burn; $bu = LgFormatAmount $bb }
        $mo = '-'; if ($null -ne $x.months) { $mo = LgFmtF $x.months 1 }
        $ro = '-'; if ($null -ne $x.runout) { $ro = $x.runout }
        LgPush $rows @($x.account, (LgFormatAmount $ba), $bu, $mo, $ro)
    }
    "Funding run-out as of $($r.status) (burn = average monthly spend, $($r.window[0]) to $($r.window[1]))`n" + (LgTable (LgToArray $rows))
}
function LgReplaceFirst([string]$text, [string]$re, [string]$with) {     # Perl s/re/with/ (the first match only)
    $parts = $text -csplit $re, 2
    if ($parts.Count -lt 2) { return $text }
    $parts[0] + $with + $parts[1]
}

# ================================================================ command line (Getopt::Long semantics)
$script:LG_OPTS = @(
    @{ names = @('f', 'file'); key = 'file'; arg = 's' }, @{ names = @('b', 'begin'); key = 'begin'; arg = 's' },
    @{ names = @('e', 'end'); key = 'end'; arg = 's' }, @{ names = @('p', 'period'); key = 'period'; arg = 's' },
    @{ names = @('depth'); key = 'depth'; arg = 'i' }, @{ names = @('C', 'cleared'); key = 'cleared'; arg = '' },
    @{ names = @('R', 'real'); key = 'real'; arg = '' }, @{ names = @('E', 'empty'); key = 'empty'; arg = '' },
    @{ names = @('payee'); key = 'payee'; arg = 's' }, @{ names = @('M', 'monthly'); key = 'monthly'; arg = '' },
    @{ names = @('now'); key = 'now'; arg = 's' }, @{ names = @('months'); key = 'months'; arg = 'i' },
    @{ names = @('complete'); key = 'complete'; arg = 'l' }, @{ names = @('complete-file'); key = 'complete_file'; arg = 's' }
)
function LgFindOpt([string]$name) {                     # exact (case-sensitive), else a unique prefix: -> option, or an error text
    foreach ($o in $script:LG_OPTS) { foreach ($n in $o.names) { if ($n -ceq $name) { return @{ opt = $o; name = $n } } } }
    $hits = LgNewList
    foreach ($o in $script:LG_OPTS) { foreach ($n in $o.names) { if (LgSW $n $name) { LgPush $hits @{ opt = $o; name = $n } } } }
    $hits = LgToArray $hits
    $distinct = LgNub @(foreach ($h in $hits) { $h.opt.key })
    if ($distinct.Count -eq 1) { return $hits[0] }
    if ($hits.Count -gt 1) { return @{ err = "Option $name is ambiguous ($((LgSorted @(foreach ($h in $hits) { $h.name })) -join ', '))" } }
    @{ err = "Unknown option: $name" }
}
function LgGetOpts($argv) {                             # -> @{ o; rest; ok }
    $o = @{ file = $env:LEDGER_FILE; complete = $null }
    if ($null -eq $o.file) { $o.file = 'ledger.txt' }
    $rest = LgNewList; $ok = $true; $cl = LgNewList
    $i = 0; $n = $argv.Count
    while ($i -lt $n) {
        $a = $argv[$i]; $i++
        if ($a -ceq '--') { while ($i -lt $n) { LgPush $rest $argv[$i]; $i++ }; break }
        if ($a -cnotmatch '^--?(.+)$' -or $a -ceq '-') { LgPush $rest $a; continue }
        $body = $Matches[1]; $val = $null; $hasVal = $false
        if ($body -cmatch '^([^=]+)=(.*)$') { $body = $Matches[1]; $val = $Matches[2]; $hasVal = $true }
        $hit = LgFindOpt $body
        if ($hit.err) { LgOut-Err $hit.err; $ok = $false; continue }
        $opt = $hit.opt
        if ($opt.arg -eq '') {
            if ($hasVal) { LgOut-Err "Option $($hit.name) does not take an argument"; $ok = $false; continue }
            $o[$opt.key] = 1; continue
        }
        if (-not $hasVal) {
            if ($i -ge $n) { LgOut-Err "Option $($hit.name) requires an argument"; $ok = $false; continue }
            $val = $argv[$i]; $i++
        }
        if ($opt.arg -eq 'i') {
            if ($val -cnotmatch '^[-+]?\d+$') { LgOut-Err "Value `"$val`" invalid for option $($hit.name) (number expected)"; $ok = $false; continue }
            $o[$opt.key] = [int]$val
        }
        elseif ($opt.arg -eq 'l') { LgPush $cl $val }
        else { $o[$opt.key] = $val }
    }
    if ($cl.Count) { $o.complete = LgToArray $cl }
    @{ o = $o; rest = (LgToArray $rest); ok = $ok }
}

function LgRun($argv) {
    $g = LgGetOpts $argv
    if (-not $g.ok) { $script:RC = 2; return }
    $o = $g.o; $rest = @($g.rest)
    $cmd = 'bal'; if ($rest.Count) { $cmd = $rest[0]; if ($rest.Count -gt 1) { $rest = $rest[1..($rest.Count - 1)] } else { $rest = @() } }
    $f = @{ begin = $null; end = $null; period = $null; depth = $null; cleared = $null; real = $null; empty = $null; payee = $null; account = $null }
    foreach ($k in 'begin', 'end', 'period', 'depth', 'cleared', 'real', 'empty') { if ($null -ne $o[$k]) { $f[$k] = $o[$k] } }
    if (LgTruthy $f.begin) { $x = LgNormDate $f.begin; if ($null -eq $x) { LgDie "bad --begin`n" }; $f.begin = $x }
    if (LgTruthy $f.end) { $x = LgNormDate $f.end; if ($null -eq $x) { LgDie "bad --end`n" }; $f.end = $x }
    if ($null -ne $o.payee) { $f.payee = $o.payee }
    if ($rest.Count) { $f.account = $rest -join '|' }
    try { $j = LgReadJournal $o.file }
    catch {
        $msg = $_.Exception.Message
        if ($msg.StartsWith('JOURNAL:')) { LgOut-Err $msg.Substring(8); $script:RC = 1; return }
        throw
    }
    $now = $null
    if ($null -ne $o.now) { $now = LgNormDate $o.now; if ($null -eq $now) { LgDie "bad --now (want YYYY-MM-DD)`n" } }
    if ($null -ne $now) { $status = LgAddDays $now 1 } else { $status = LgAddDays (LgTodayYmd) 1 }
    $isBal = $cmd -ceq 'bal' -or $cmd -ceq 'balance'; $isReg = $cmd -ceq 'reg' -or $cmd -ceq 'register'
    if ($o.monthly -and $isBal) { LgOut-Text (LgReportBalMonthly $j $f) }
    elseif ($o.monthly -and $isReg) { LgOut-Text (LgReportRegMonthly $j $f) }
    elseif ($o.monthly -and $cmd -ceq 'budget') { LgOut-Text (LgReportBudgetMonthly $j $f) }
    elseif ($isBal) { LgOut-Text (LgReportBal $j $f) }
    elseif ($isReg) { LgOut-Text (LgReportReg $j $f) }
    elseif ($cmd -ceq 'budget') { if (-not ((LgTruthy $f.period) -or ((LgTruthy $f.begin) -and (LgTruthy $f.end)))) { $f.period = LgThisMonth }; LgOut-Text (LgReportBudget $j $f) }
    elseif ($cmd -ceq 'evm') {
        $c = LgReadComplete $o.complete $o.complete_file
        $g2 = $f.Clone(); $g2.status = $status; $g2.complete = $c
        LgOut-Text (LgReplaceFirst (LgReportEvm $j $g2) 'as of \S+' ('as of ' + (LgAddDays $status -1)))
    }
    elseif ($cmd -ceq 'forecast') {
        $g2 = $f.Clone(); $g2.status = $status; $g2.months = $o.months
        LgOut-Text (LgReplaceFirst (LgReportForecast $j $g2) 'run-out as of \S+' ('run-out as of ' + (LgAddDays $status -1)))
    }
    elseif ($cmd -ceq 'csv') { LgOut-Text (LgToCsv (LgPostings $j $f)) }
    elseif ($cmd -ceq 'check') { LgOut-Text "ok: $($j.txns.Count) transactions, $($j.periodic.Count) budget entries`n" }
    elseif ($cmd -ceq 'accounts') { foreach ($x in (LgSorted (LgNub @(foreach ($p in (LgPostings $j $f)) { $p.account })))) { Write-Output $x } }
    elseif ($cmd -ceq 'payees') { foreach ($x in (LgSorted (LgNub @(foreach ($p in (LgPostings $j $f)) { $p.payee })))) { Write-Output $x } }
    else { LgOut-Err "unknown command '$cmd' (bal reg budget evm forecast csv check accounts payees)"; $script:RC = 2 }
}

function LgShowHelp($topics) {
    $main = ($script:LG_HELP_MAIN -replace "`r", '')
    if (-not $topics.Count) { LgOut-Text ($main + "`n"); return }
    $t = $topics[0]
    $alias = @{ balance = 'bal'; register = 'reg'; payees = 'accounts' }
    $key = $t; if ($alias.ContainsKey($t)) { $key = $alias[$t] }
    $heads = @{ bal = 'bal [ACCOUNT...]'; reg = 'reg [ACCOUNT...]'; budget = 'budget [-p PERIOD]'; monthly = '-M, --monthly'; evm = 'evm [--complete'; forecast = 'forecast [--months'; csv = 'csv'; check = 'check'; accounts = 'accounts' }
    if ($key -cmatch '^[a-z]+$' -and $heads.ContainsKey($key)) {
        foreach ($para in ($main -split "`n`n")) { if (LgSW $para $heads[$key]) { LgOut-Text ($para + "`n"); return } }
    }
    LgOut-Text "no help for '$($topics -join ' ')'. ledger.cmd help`n"
    $script:RC = 1
}


# ================================================================ the cockpit's Funding data (lib/Cockpit.pm funding_snapshot)
# FundingSnapshot($ledgerFile, $completeGlobOrNull, $today) -> $null (no file, or no transactions) | @{ error } | @{
#   status = today; file; points = @( @{ date; funds; spent } ... weekly from the first transaction, then today );
#   forecast = @{ account; commodity; balance; burn; months; runout } (the Assets row at depth 1, 2-month burn) or $null;
#   evm = $null | @{ error } | @{ status (today+1); complete_file; rows = @( row ... ); total = row }
#     row = @{ account; commodity; pct; bac; bcws; bcwp; acwp; cv; sv; cpi; spi; eac; etc; vac }   ($null where Perl has undef/no key)
# }. funds = the Assets balance, spent = the cumulative Expense balance; the newest percent-complete file dated on or
# before today (complete-YYYY-MM-DD.csv) feeds earned value.
function FundingSnapshot($file, $glob, [string]$today) {
    if ($null -eq $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try { $j = LgReadJournal $file }
    catch { $m = $_.Exception.Message; if ($m.StartsWith('JOURNAL:')) { $m = $m.Substring(8) }; return @{ error = $m } }
    $status = LgAddDays $today 1
    if (-not $j.sorted.Count) { return $null }
    $one = {
        param($acct, $end)
        $t = LgBalanceTree (LgBalances (LgPostings $j @{ end = $end; real = 1 }))
        $v = 0; if ($t.ContainsKey($acct)) { foreach ($x in $t[$acct].Values) { $v = $x; break } }; $v
    }
    $points = LgNewList
    $at = $j.sorted[0].date
    while ((LgSLt $at $status)) {
        $e = LgAddDays $at 1
        LgPush $points @{ date = $at; funds = (& $one 'Assets' $e); spent = (& $one 'Expense' $e) }
        $at = LgAddDays $at 7
    }
    if (-not $points.Count -or $points[$points.Count - 1].date -cne $today) { LgPush $points @{ date = $today; funds = (& $one 'Assets' $status); spent = (& $one 'Expense' $status) } }
    $fc = LgForecast $j @{ status = $status; months = 2; account = '^Assets'; cs = $true; depth = 1 }
    $complete = $null; $evm = $null
    if ($null -ne $glob) {
        $dir = $glob -creplace '[^/\\]*$', ''
        $files = @(Get-ChildItem -Path $glob -File -ErrorAction SilentlyContinue | ForEach-Object { $dir + $_.Name })
        $files = LgSortWith $files { param($a, $b) [string]::CompareOrdinal($a, $b) }
        foreach ($c in $files) { $dt = $null; if ($c -cmatch '(\d{4}-\d{2}-\d{2})') { $dt = $Matches[1] }; if (-not $dt -or -not (LgSGt $dt $today)) { $complete = $c } }
    }
    if ($complete -and $j.periodic.Count) {
        try {
            $e = LgEvm $j @{ status = $status; complete = (LgReadComplete @() $complete) }
            $evm = @{ status = $e.status; rows = $e.rows; total = $e.total; complete_file = $complete }
        }
        catch { $m = $_.Exception.Message; $m = $m -creplace '^DIE2?:', ''; $evm = @{ error = $m } }
    }
    $row = $null; if ($fc.rows.Count) { $row = $fc.rows[0] }
    @{ status = $today; file = $file; points = (LgToArray $points); forecast = $row; evm = $evm }
}

# ================================================================ main
if ($script:LG_ARGV.Count -and $script:LG_ARGV[0] -ceq '__lib') { return }
$script:RC = 0   # . .\ledger.ps1 __lib : the functions (all Lg*, plus FundingSnapshot), no command
if ($script:LG_ARGV.Count -and $script:LG_ARGV[0] -cin 'help', '--help', '-h') {
    $rest = @(); if ($script:LG_ARGV.Count -gt 1) { $rest = $script:LG_ARGV[1..($script:LG_ARGV.Count - 1)] }
    LgShowHelp $rest
}
else {
    try { LgRun $script:LG_ARGV }
    catch {
        $msg = $_.Exception.Message
        if ($msg.StartsWith('DIE:')) { LgOut-Err $msg.Substring(4); $script:RC = 255 }
        elseif ($msg.StartsWith('DIE2:')) { LgOut-Err $msg.Substring(5); $script:RC = 2 }
        else { LgOut-Err $msg; $script:RC = 255 }
    }
}
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
