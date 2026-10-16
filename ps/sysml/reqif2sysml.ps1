<#
reqif2sysml.ps1 -- DOORS requirements (ReqIF .reqif/.reqifz, or a DOORS CSV export) -> SysML v2 requirement
definitions, one file per DOORS module (SPECIFICATION), plus the trace report behind status metrics C/F/G/I.
A port of the kit's bin/reqif2sysml.pl + lib/Reqif.pm to Windows PowerShell 5.1 (Constrained Language Mode safe):
same options, same output bytes, same exit codes.

  reqif2sysml.cmd --report export.reqif                     # counts only
  reqif2sysml.cmd --out model export.reqif                  # writes model\<segment>\<Module>.sysml
  reqif2sysml.cmd --out model --layout '_reqs/{pkg}.sysml' export.reqifz
  reqif2sysml.cmd --out model --layout-map layout.map export.reqif
  reqif2sysml.cmd --report --model model export.reqif       # + linked / orphan / unverified against model\
  reqif2sysml.cmd --csv --col "id=Object Identifier" --col "text=Object Text" --col "level=Object Level" --out model module.csv

Options: --req-style usage|def, --id-attr NAME, --vm-attr NAME, --text-attr NAME, --heading-attr NAME, --id-prefix P,
--attr NAME (repeatable), --name PKG, --sep C, --stdout, --check (also runs sysml.ps1 beside this script, when present).
A .reqifz needs ziplib.ps1 one folder up (the kit's ps\ folder). Exit: 0 ok, 1 self-check problems, 2 usage/input.
#>
. "$PSScriptRoot\reqiflib.ps1"

function Main($argv) {
    $g = GetOpt $argv @('out=s', 'layout=s', 'layout-map=s', 'report', 'stdout', 'req-style=s', 'name=s', 'check', 'csv', 'col=s%', 'sep=s',
        'id-attr=s', 'vm-attr=s', 'text-attr=s', 'heading-attr=s', 'id-prefix=s', 'attr=s@', 'model=s', 'help|h')
    if (-not $g.ok) { ErrLines $g.err; $script:RC = 2; return }
    $o = $g.opts; $args1 = @($g.args)
    if (-not $o.ContainsKey('layout')) { $o['layout'] = '{seg}/{pkg}.sysml' }
    if (-not $o.ContainsKey('req-style')) { $o['req-style'] = 'usage' }
    if ($o['help'] -or $args1.Count -ne 1) {
        ErrLines ("usage: reqif2sysml.pl [--report] [--model DIR] [--out DIR [--layout '{seg}/{pkg}.sysml' | --layout-map FILE] | --stdout]`n" +
                  "                      [--csv [--col id=NAME --col text=NAME --col heading=NAME --col level=NAME --col vm=NAME] [--sep C]]`n" +
                  "                      [--req-style usage|def] [--id-attr NAME] [--vm-attr NAME] [--id-prefix P] [--attr NAME]... FILE`n")
        if ($o['help']) { $script:RC = 0 } else { $script:RC = 2 }; return
    }
    if ($o['req-style'] -cnotmatch '^(def|usage)$') { ErrLines "reqif2sysml: --req-style is def or usage`n"; $script:RC = 255; return }
    $file = $args1[0]
    $sep = $o['sep']; if ($sep -ceq '\t') { $sep = "`t" }
    $lo = @{ id_attr = $o['id-attr']; vm_attr = $o['vm-attr']; text_attr = $o['text-attr']; heading_attr = $o['heading-attr']
             id_prefix = $o['id-prefix']; name = $o['name']; sep = $sep; cols = $(if ($o.ContainsKey('col')) { $o['col'] } else { NewH }) }
    $d = $null
    try { if ($o['csv'] -or (RTI $file '\.csv$')) { $d = LoadCsv $file $lo } else { $d = LoadReqif $file $lo } }
    catch { ErrLines ("reqif2sysml: " + $_.Exception.Message); $script:RC = 2; return }
    $lm = $null
    if ($o.ContainsKey('layout-map')) {
        try { $lm = ReadLayoutMap $o['layout-map'] } catch { ErrLines ("reqif2sysml: --layout-map " + $_.Exception.Message); $script:RC = 2; return }
    }
    $out = RConvert $d @{ req_style = $o['req-style']; layout = $o['layout']; name = $o['name']; extra_attrs = @($o['attr']); layout_map = $lm }
    $files = $out.files
    $bad = if (@($out.problems).Count) { 1 } else { 0 }
    if ($o['out']) {
        foreach ($f in (SortedKeys $files)) {
            $p = "$($o['out'])/$f"
            $dd = RR $p '/[^/]*$' ''
            MkPath $dd
            try { WriteBytes $p $files[$f] } catch { ErrLines "reqif2sysml: ${p}: $($_.Exception.Message)"; $script:RC = 255; return }
        }
        if ($o['check']) {
            $chk = Join-Path $PSScriptRoot 'sysml.ps1'
            if (Test-Path -LiteralPath $chk) {
                $list = @(foreach ($f in (SortedKeys $files)) { "$($o['out'])/$f" })
                & $chk check @list
                if ($LASTEXITCODE) { $bad = 1 }
            } else { ErrLines "reqif2sysml: sysml.ps1 not found beside this script; structural self-check only" }
        }
    }
    if ($o['stdout']) { foreach ($f in (SortedKeys $files)) { OutLines ("// file: $f`n" + $files[$f]) } }
    $r = $out.report; $c = $r.counts
    if ($o['report']) {
        OutLines (ReportText $out)
        if ($o['model']) { OutLines (TraceText (RTrace $d $out $o['model'])) }
    } elseif ($o['out'] -or $o['stdout']) {
        $pr = @($out.problems)
        ErrLines ("reqif2sysml: $($r.objects) objects, $($c.requirements) requirements ($($c.with_vm) with a verification method), $($c.headings) headings, " +
                  "$($r.relations) links, $($files.Count) file(s), self-check " + $(if ($pr.Count) { "$($pr.Count) problem(s)" } else { 'ok' }))
        foreach ($x in $pr) { ErrLines "  $x" }
        foreach ($x in @($r.layout)) { ErrLines "  $x" }
        if ($o['model']) { ErrLines (TraceText (RTrace $d $out $o['model'])) }
    } elseif ($o['model']) {
        OutLines ((ReportText $out) + (TraceText (RTrace $d $out $o['model'])))
    } else { ErrLines "reqif2sysml: nothing to do: give --out DIR, --stdout, --report or --model DIR"; $script:RC = 2; return }
    $script:RC = $bad; return
}

$script:RC = 0
Main $args
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
