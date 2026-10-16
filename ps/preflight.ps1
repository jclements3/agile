<#
preflight.ps1 -- what this PC allows, and how each Halberd tool will run here.

Run it first on a new PC:   powershell -NoProfile -ExecutionPolicy Bypass -File preflight.ps1
If .ps1 files are blocked:  paste this file's text into a PowerShell window instead.

Read only: it changes nothing, starts nothing, and sends nothing. Exit 0 = the tools can run here.
#>
$ErrorActionPreference = 'Continue'
$fails = 0
function Row($what, $state, $note) { Write-Output ('{0,-28} {1,-6} {2}' -f $what, $state, $note) }

Write-Output 'Halberd tools preflight'
Write-Output ('-' * 72)
$v = $PSVersionTable.PSVersion
$ok = ($v.Major -eq 5 -and $v.Minor -ge 1) -or $v.Major -gt 5
if (-not $ok) { $fails++ }
Row 'PowerShell' $(if ($ok) { 'ok' } else { 'FAIL' }) ("$v" + $(if ($ok) { '' } else { ' (need 5.1)' }))

$mode = "$($ExecutionContext.SessionState.LanguageMode)"
$full = $mode -eq 'FullLanguage'
Row 'Language mode' 'ok' ($mode + $(if ($full) { ': every feature' } else { ': locked down (AppLocker/WDAC); the tools are built for this' }))

$pol = @{}
foreach ($p in @(Get-ExecutionPolicy -List)) { $pol["$($p.Scope)"] = "$($p.ExecutionPolicy)" }
$gp = @('MachinePolicy', 'UserPolicy') | Where-Object { $pol[$_] -and $pol[$_] -ne 'Undefined' } | Select-Object -First 1
$eff = "$(Get-ExecutionPolicy)"
if ($gp -and $pol[$gp] -in @('Restricted', 'AllSigned')) {
    Row 'Script files' 'paste' "$gp = $($pol[$gp]): .cmd/.ps1 will not start; load the text instead (README, 'If scripts are blocked')"
} else {
    Row 'Script files' 'ok' "effective policy $eff; the .cmd launchers pass -ExecutionPolicy Bypass"
}

$clip = $true; try { $null = Get-Clipboard -ErrorAction Stop } catch { $clip = $false }
Row 'Clipboard' $(if ($clip) { 'ok' } else { 'no' }) $(if ($clip) { 'paste the Teams chat, copy replies back' } else { 'Get-Clipboard refused: save the chat to a file and pass its path' })

$keys = $false
if ($full) { try { $null = $Host.UI.RawUI.KeyAvailable; $keys = $true } catch { $keys = $false } }
Row 'Single keystrokes' $(if ($keys) { 'ok' } else { 'no' }) $(if ($keys) { 'pvi full-screen mode, townhall -Gui' } else { 'pvi runs in ex (line) mode; townhall in console mode' })

$here = $PSScriptRoot; if (-not $here) { $here = (Get-Location).Path }
$tools = @('agile.ps1', 'agile-more.ps1', 'ledger.ps1', 'md2docx.ps1', 'pgit.ps1', 'unix.ps1', 'ziplib.ps1', 'pvi.ps1',
           'cockpit.ps1', 'status-metrics.ps1', 'drill.ps1', 'townhall.ps1', 'cards.ps1', 'invite.ps1', 'attend.ps1', 'scrum.ps1')
$missing = @($tools | Where-Object { -not (Test-Path -LiteralPath (Join-Path $here $_)) })
Row 'Tool files' $(if ($missing.Count) { 'warn' } else { 'ok' }) $(if ($missing.Count) { 'not beside preflight.ps1: ' + ($missing -join ' ') } else { "$($tools.Count) found in $here" })

$office = @{ Word = 'WINWORD.EXE'; Excel = 'EXCEL.EXE' }
$opens = @{ Word = 'opens the md2docx .docx files (no automation used)'; Excel = 'opens the backlog.xml and status workbooks (no automation used)' }
foreach ($k in @('Excel', 'Word')) {
    $f = @("$env:ProgramFiles\Microsoft Office\root\Office16\$($office[$k])", "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\$($office[$k])") |
         Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    Row $k $(if ($f) { 'ok' } else { 'no' }) $(if ($f) { $opens[$k] } else { 'not found: the .xml workbook and .docx need Excel/Word or a viewer' })
}
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
Row 'Edge' $(if ($edge) { 'ok' } else { 'no' }) $(if ($edge) { 'cockpit dashboard.html, status pages' } else { 'not found: open the .html files in any browser' })
$teams = Get-Process -Name 'ms-teams', 'Teams' -ErrorAction SilentlyContinue | Select-Object -First 1
Row 'Teams' $(if ($teams) { 'ok' } else { '?' }) $(if ($teams) { 'running' } else { 'not running now (needed only to paste chats and open 1:1 links)' })
$java = Get-Command java -ErrorAction SilentlyContinue
Row 'Java (SysML v2 Pilot)' $(if ($java) { 'ok' } else { 'no' }) $(if ($java) { 'the reference parse gate can run here' } else { 'parse gate reports "not run" (not run is not green): run it on the GitLab runner' })

Write-Output ('-' * 72)
if ($fails) { Write-Output "preflight: $fails blocking problem(s)"; exit 1 }
Write-Output 'preflight: ok, the tools can run here'
exit 0
