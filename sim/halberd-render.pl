# halberd-render.pl -- docs/HALBERD.html for sim/halberd-gen.pl (required from there, not run on its own).
# One self-contained page: the plan, the release and sprint burn-downs as inline SVG, and every daily
# standup. Core Perl; the same plain style as the other docs/*.html.
use strict;
use warnings;
use List::Util ();

sub _h { my $t = shift // ''; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t }
sub _md { my $t = _h(shift); $t =~ s{\*\*(.+?)\*\*}{<strong>$1</strong>}g; $t }     # the doc's cells use **bold** only
sub _c { my $n = shift; 1 while $n =~ s/^(\d+)(\d{3})/$1,$2/; $n }

sub _burn_svg {                                # lines: actual (left) and ideal, over labelled days
    my ($title, $labels, $actual, $ideal) = @_;
    my ($w, $h, $l, $r, $t, $bm) = (640, 220, 46, 12, 22, 34);
    my $max = List::Util::max(@$actual, @$ideal) || 1;
    my $x = sub { $l + $_[0] * ($w - $l - $r) / (@$labels - 1) };
    my $y = sub { $t + ($h - $t - $bm) * (1 - $_[0] / $max) };
    my $pts = sub { join ' ', map { sprintf '%.1f,%.1f', $x->($_), $y->($_[0][$_]) } 0 .. $#{ $_[0] } };
    my $svg = qq{<svg viewBox="0 0 $w $h" width="$w" height="$h" role="img" aria-label="} . _h($title) . qq{" style="max-width:100%;height:auto">\n};
    for my $f (0, 0.5, 1) {
        my $v = int($max * $f + 0.5);
        $svg .= sprintf qq{<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#ddd"/><text x="%d" y="%.1f" font-size="10" text-anchor="end" fill="#555">%s</text>\n}, $l, $w - $r, $y->($v), $y->($v), $l - 4, $y->($v) + 3, _c($v);
    }
    for my $i (0 .. $#$labels) {
        next unless $i == 0 || $i == $#$labels || $i % 2 == 0;
        $svg .= sprintf qq{<text x="%.1f" y="%d" font-size="10" text-anchor="middle" fill="#555">%s</text>\n}, $x->($i), $h - $bm + 14, _h($labels->[$i]);
    }
    $svg .= sprintf qq{<polyline points="%s" fill="none" stroke="#999" stroke-width="1.5" stroke-dasharray="4 3"/>\n}, $pts->($ideal);
    $svg .= sprintf qq{<polyline points="%s" fill="none" stroke="#1f4e79" stroke-width="2.2"/>\n}, $pts->($actual);
    $svg .= sprintf qq{<circle cx="%.1f" cy="%.1f" r="3" fill="#1f4e79"/>\n}, $x->($_), $y->($actual->[$_]) for 0 .. $#$actual;
    $svg .= qq{<text x="$l" y="13" font-size="11" fill="#1a1a1a">} . _h($title) . qq{ &#8212; <tspan fill="#1f4e79">actual</tspan>, <tspan fill="#777">ideal (dashed)</tspan></text>\n</svg>};
    $svg;
}

sub _bars_svg {                                # release burn-down: items left at the start and after each sprint
    my ($labels, $vals) = @_;
    my ($w, $h, $l, $t, $b) = (640, 200, 46, 14, 30);
    my $max = $vals->[0] || 1; my $bw = ($w - $l - 10) / @$vals;
    my $svg = qq{<svg viewBox="0 0 $w $h" width="$w" height="$h" role="img" aria-label="Release burn-down" style="max-width:100%;height:auto">\n};
    for my $i (0 .. $#$vals) {
        my $bh = ($h - $t - $b) * $vals->[$i] / $max; my $x0 = $l + $i * $bw + 6;
        $svg .= sprintf qq{<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#1f4e79"/>\n}, $x0, $h - $b - $bh, $bw - 12, $bh;
        $svg .= sprintf qq{<text x="%.1f" y="%.1f" font-size="10" text-anchor="middle" fill="#333">%s</text>\n}, $x0 + ($bw - 12) / 2, $h - $b - $bh - 3, _c($vals->[$i]);
        $svg .= sprintf qq{<text x="%.1f" y="%d" font-size="10" text-anchor="middle" fill="#555">%s</text>\n}, $x0 + ($bw - 12) / 2, $h - $b + 14, $labels->[$i];
    }
    "$svg</svg>";
}

sub _multi_svg {                               # several lines over the same x labels; series: [ [name, colour, dash, [values]] ]
    my ($title, $labels, $series, $fmt) = @_;
    my ($w, $h, $l, $r, $t, $bm) = (720, 260, 70, 12, 30, 34);
    my $max = List::Util::max(map { @{ $_->[3] } } @$series) || 1;
    my $x = sub { $l + $_[0] * ($w - $l - $r) / (@$labels - 1) };
    my $y = sub { $t + ($h - $t - $bm) * (1 - $_[0] / $max) };
    my $svg = qq{<svg viewBox="0 0 $w $h" width="$w" height="$h" role="img" aria-label="} . _h($title) . qq{" style="max-width:100%;height:auto">\n};
    for my $f (0, 0.25, 0.5, 0.75, 1) {
        my $v = $max * $f;
        $svg .= sprintf qq{<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#e2e2e2"/><text x="%d" y="%.1f" font-size="10" text-anchor="end" fill="#555">%s</text>\n}, $l, $w - $r, $y->($v), $y->($v), $l - 4, $y->($v) + 3, $fmt->($v);
    }
    for my $i (0 .. $#$labels) {
        next unless $i % 2 == 1 || $i == $#$labels;
        $svg .= sprintf qq{<text x="%.1f" y="%d" font-size="10" text-anchor="middle" fill="#555">%s</text>\n}, $x->($i), $h - $bm + 14, _h($labels->[$i]);
    }
    my $lx = $l;
    for my $s (@$series) {
        my ($name, $col, $dash, $v) = @$s;
        $svg .= sprintf qq{<polyline points="%s" fill="none" stroke="%s" stroke-width="2"%s/>\n}, join(' ', map { sprintf '%.1f,%.1f', $x->($_), $y->($v->[$_]) } 0 .. $#$v), $col, $dash ? qq{ stroke-dasharray="$dash"} : '';
        $svg .= sprintf qq{<line x1="%d" x2="%d" y1="14" y2="14" stroke="%s" stroke-width="2"%s/><text x="%d" y="18" font-size="11" fill="#1a1a1a">%s</text>\n}, $lx, $lx + 18, $col, $dash ? qq{ stroke-dasharray="$dash"} : '', $lx + 22, _h($name);
        $lx += 30 + 7 * length $name;
    }
    "$svg</svg>";
}
sub _usd0 { my $v = sprintf '%.0f', shift; my $neg = $v < 0; $v = abs $v; 1 while $v =~ s/^(\d+)(\d{3})/$1,$2/; ($neg ? '-' : '') . "\$$v" }

sub halberd_render {
    my ($file, %a) = @_;
    my ($days, $sprints, $plan, $seg, $rows) = @a{qw(days sprints plan seg journal_rows)};
    my @order = qw(E V B T G M L);
    my %seg_pts; my %seg_tasks;
    for my $p (@$plan) { for my $t (@{ $p->{tasks} }) { $seg_pts{ $t->{seg} } += $t->{pts}; $seg_tasks{ $t->{seg} }++ } }
    my %first; my %last;
    for my $d (@$days) { $first{ $d->{seg} } //= $d->{date}; $last{ $d->{seg} } = $d->{date} }

    my $o = <<'HEAD';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>IAMD MBSE SysEng Integration Into DevSecOps Notional Plan</title>
<style>
  body { font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: 11pt; color: #1a1a1a;
         max-width: 1100px; margin: 2em auto; padding: 0 1.5em; line-height: 1.5; }
  h1 { font-size: 20pt; border-bottom: 2px solid #444; padding-bottom: 0.2em; }
  h2 { font-size: 15pt; margin-top: 2em; border-bottom: 1px solid #999; padding-bottom: 0.15em; }
  h3 { font-size: 12.5pt; margin-top: 1.5em; }
  code, pre { font-family: Consolas, "Courier New", monospace; font-size: 10pt; }
  pre { background: #f4f4f4; border: 1px solid #ddd; padding: 0.8em 1em; overflow-x: auto; }
  code { background: #f4f4f4; padding: 0.1em 0.3em; }
  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 10pt; }
  th, td { border: 1px solid #bbb; padding: 0.4em 0.6em; text-align: left; vertical-align: top; }
  th { background: #e8e8e8; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  tr:nth-child(even) td { background: #fafafa; }
  tr.blk td { background: #fff4e5; }
  .note { color: #555; font-size: 10pt; }
</style>
</head>
<body>
HEAD
    $o .= <<'INTRO';
<h1>IAMD MBSE SysEng Integration Into DevSecOps Notional Plan</h1>
<p class='note' style='margin-top:-0.6em'>Halberd: a 12-week SysML v1 to v2 port, run on the agile kit</p>

<p><strong>Halberd is fictional and notional, and so is every number here.</strong> Its legacy SysML v1 model
holds 1,960 in-scope items across 7 organizations, and 1,450 DOORS requirements. One solutions architect
ports it to SysML v2 text under a DevSecOps pipeline, one segment at a time, starting Monday 5 October 2026:
two-week sprints, a baseline tagged every 4 weeks, a standup every working day, and the status meeting hears
the alphabet &mdash; the 26 metrics A&ndash;Z of <a href="STATUS-METRICS.html">STATUS-METRICS.html</a>.
Thanksgiving and 24&ndash;25 December are holidays, so this is 56 working days.</p>

<p>This page is the public view. The project itself is a real kit project, built by compiling one stand-up
file per day through the kit's own ledger (<code>lib/Standup.pm</code>, <code>lib/Scrum.pm</code>,
<code>lib/Ledger.pm</code>); <code>data/</code> is never committed, so rebuild it with one command:</p>
<pre>perl sim/halberd-gen.pl                                   # data/halberd: journal, 56 stand-ups, answers; and this page
perl bin/ledger.pl -f data/halberd/scrum.txt bal Sprint:3   # the ledger: 330 items done in sprint 3
perl bin/scrum.pl  -f data/halberd/scrum.txt items done Halberd
perl agile.pl --today 2026-11-05 data/halberd              # the cockpit on a blocked day
perl bin/status-metrics.pl ...                             # the A-Z collector: see STATUS-METRICS.html, Appendix A</pre>
<p>The metric dashboard, prefilled with Halberd's end-of-sprint-6 numbers, is
<a href="STATUS-DASHBOARD.html">STATUS-DASHBOARD.html</a>; the weekly A&ndash;Z snapshot is Appendix C of
<a href="STATUS-METRICS.html">STATUS-METRICS.html</a>.</p>
INTRO

    $o .= "<h2>Backlog: segments as epics</h2>\n<p>Tome <em>Halberd SysML v2 port</em>. Each task ports a day's worth of v1 items, in items (the journal's unit); the epics are the 7 segments, in the order they are ported.</p>\n";
    $o .= "<table><tr><th>Epic</th><th>Segment</th><th class='n'>v1 items</th><th class='n'>Tasks</th><th>Worked</th></tr>\n";
    for my $k (@order) {
        $o .= sprintf "<tr><td>%s</td><td>%s</td><td class='n'>%s</td><td class='n'>%d</td><td>%s to %s</td></tr>\n", $k, _h($seg->{$k}), _c($seg_pts{$k} // 0), $seg_tasks{$k} // 0, $first{$k}, $last{$k};
    }
    $o .= "</table>\n<p class='note'>A carried task counts in the segment being worked when it was committed; the 7 rows add up to all 1,960 items.</p>\n";

    my @left = (1960); push @left, $left[-1] - $_->{done} for @$sprints;
    $o .= "<h2>Release burn-down</h2>\n" . _bars_svg([ 'Start', map { "S$_->{n}" } @$sprints ], \@left);
    $o .= "\n<table><tr><th>Sprint</th><th>Dates</th><th class='n'>Committed</th><th class='n'>Done</th><th class='n'>Carried over</th><th class='n'>Done % (X)</th><th class='n'>v1 items left</th></tr>\n";
    for my $i (0 .. $#$sprints) {
        my ($sp, $r) = ($sprints->[$i], $rows->[$i]);
        my @sd = grep { $_->{sprint} == $sp->{n} } @$days;
        $o .= sprintf "<tr><td>%d</td><td>%s to %s</td><td class='n'>%d</td><td class='n'>%d</td><td class='n'>%d</td><td class='n'>%d</td><td class='n'>%s</td></tr>\n",
            $sp->{n}, $sd[0]{date}, $sd[-1]{date}, @{$r}{qw(committed done carryover pct)}, _c($left[ $i + 1 ]);
    }
    $o .= "</table>\n<p class='note'>Committed, done, carried and done % are computed from the compiled journal by <code>Scrum::sprint_summary</code>, the same code the kit's reports use; the generator stops if any of them differs from the doc.</p>\n";

    if (my $es = $a{evm_series}) {               # ---- the money
        my @lab = map { $_->{label} } @$es;
        my $tot = sub { my $k = shift; [ map { $_->{evm}{total}{$k} // 0 } @$es ] };
        $o .= "<h2>Funding and earned value</h2>\n<p>A notional FY27 funding journal sits beside the stand-up journal, in the same ledger format:"
            . " <code>data/halberd/funding.ledger</code>. Each segment is budgeted at a notional \$150 per v1 item, time-phased over the days the plan works it"
            . " (<code>~ Monthly from &hellip; to &hellip;</code>); " . _usd0($a{authorized}) . " is authorized on 1 October (budget at completion " . _usd0($a{bac})
            . " plus a 10% reserve); labor posts weekly from the items actually ported, and sprint 3 overran while it waited on the shared runner."
            . " Percent complete comes from the stand-ups, so earned value is computed, not estimated.</p>\n";
        $o .= "<pre>perl bin/ledger.pl -f data/halberd/funding.ledger bal -M Expense --depth 3            # spend by month\n"
            . "perl bin/ledger.pl -f data/halberd/funding.ledger budget -M -b 2026-10-01 -e 2027-01-01 # budget vs actual by month\n"
            . "perl bin/ledger.pl -f data/halberd/funding.ledger evm --now 2026-11-30 --complete-file data/halberd/complete-2026-11-30.csv\n"
            . "perl bin/ledger.pl -f data/halberd/funding.ledger forecast --now 2026-11-30 --months 2 Assets   # when the money runs out</pre>\n";
        $o .= _multi_svg('Cumulative cost, end of each week', \@lab,
            [ [ 'Planned (BCWS)', '#999', '5 4', $tot->('bcws') ], [ 'Earned (BCWP)', '#1f4e79', '', $tot->('bcwp') ], [ 'Actual (ACWP)', '#c0504d', '', $tot->('acwp') ] ], \&_usd0) . "\n";
        $o .= _multi_svg('Funds remaining, end of each week', \@lab, [ [ 'Funds remaining', '#2e7d4f', '', [ map { $_->{funds} } @$es ] ] ], \&_usd0) . "\n";
        my @months = grep { my $i = $_; $i == $#$es || substr($es->[$i]{date}, 0, 7) ne substr($es->[ $i + 1 ]{date}, 0, 7) } 0 .. $#$es;
        for my $i (@months) {
            my $e = $es->[$i]{evm};
            $o .= "<h3>Earned value at $es->[$i]{date}</h3>\n<table><tr><th>Segment</th><th class='n'>% done</th><th class='n'>BAC</th><th class='n'>BCWS</th><th class='n'>BCWP</th><th class='n'>ACWP</th><th class='n'>CV</th><th class='n'>SV</th><th class='n'>CPI</th><th class='n'>SPI</th><th class='n'>EAC</th></tr>\n";
            my %ord = (E => 1, V => 2, B => 3, T => 4, G => 5, M => 6, L => 7);
            for my $r ((sort { ($ord{ substr($a->{account}, -1) } // 9) <=> ($ord{ substr($b->{account}, -1) } // 9) } @{ $e->{rows} }), $e->{total}) {
                my $name = $r->{account} =~ /:(\w)$/ ? "$1 " . _h($seg->{$1}) : '<strong>Total</strong>';
                $o .= sprintf "<tr><td>%s</td><td class='n'>%.0f%%</td>%s<td class='n'>%s</td><td class='n'>%s</td><td class='n'>%s</td></tr>\n", $name, 100 * ($r->{pct} // 0),
                    join('', map { "<td class='n'>" . (defined $r->{$_} ? _usd0($r->{$_}) : '-') . '</td>' } qw(bac bcws bcwp acwp cv sv)),
                    defined $r->{cpi} ? sprintf('%.2f', $r->{cpi}) : '-', defined $r->{spi} ? sprintf('%.2f', $r->{spi}) : '-', defined $r->{eac} ? _usd0($r->{eac}) : '-';
            }
            my $f = $es->[$i]{forecast};
            $o .= "</table>\n" . ($f && $f->{burn} > 0 && ($e->{total}{pct} // 0) < 1 ? sprintf("<p>Funds remaining %s; average burn over the last two months %s a month; at that rate the money lasts %.1f more months (to %s).</p>\n",
                _usd0($f->{balance}), _usd0($f->{burn}), $f->{months} // 0, $f->{runout} // '-') : '');
        }
        my $last = $es->[-1];
        $o .= sprintf "<p>At the finish: %s spent against a %s budget (CPI %.2f); %s of the %s authorized is left, so the overrun came out of the reserve.</p>\n",
            _usd0($last->{evm}{total}{acwp}), _usd0($a{bac}), $last->{evm}{total}{cpi}, _usd0($last->{funds}), _usd0($a{authorized});
        $o .= "<p class='note'>CPI = earned / actual (above 1 is under cost); SPI = earned / planned (above 1 is ahead). EAC = BAC / CPI. All of it from <code>Ledger::evm</code> and <code>Ledger::forecast</code>, the same code as <code>bin/ledger.pl evm</code> and <code>forecast</code>.</p>\n";
    }

    $o .= "<h2>Sprints: burn-down and daily standups</h2>\n<p>Each standup answers yesterday, today and blockers, in the alphabet. Blocked days are shaded.</p>\n";
    for my $p (@$plan) {
        my $sp = $p->{sprint}; my @sd = @{ $p->{days} };
        my @act = ($sp->{committed}); my $cum = 0;
        push @act, $sp->{committed} - ($cum += $_->{ported}) for @sd;
        $act[-1] = $sp->{carried};
        my @ideal = map { $sp->{committed} * (1 - $_ / @sd) } 0 .. @sd;
        $o .= sprintf "<h3>Sprint %d: %s to %s</h3>\n<p>Committed %d. Done %d. Carried over %d. Done %% %d (X).%s</p>\n",
            $sp->{n}, $sd[0]{date}, $sd[-1]{date}, @{$sp}{qw(committed done carried pct)},
            $p->{carry_in} ? " Includes $p->{carry_in}{id}, $p->{carry_in}{pts} items carried in from sprint " . ($sp->{n} - 1) . '.' : '';
        $o .= _burn_svg("Sprint $sp->{n} burn-down (committed items left)", [ 'Start', map { $_->{label} } @sd ], \@act, \@ideal) . "\n";
        $o .= "<table><tr><th>Day</th><th class='n'>Ported</th><th class='n'>Left</th><th>Yesterday</th><th>Today</th><th>Blockers</th></tr>\n";
        for my $d (@sd) {
            my $blk = $d->{b} !~ /^None\.?$/;
            $o .= sprintf "<tr%s><td>%s&nbsp;%s</td><td class='n'>%d</td><td class='n'>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
                $blk ? " class='blk'" : '', $d->{dow}, $d->{label}, $d->{ported}, _c($d->{left}), _md($d->{y}), _md($d->{t}), _md($d->{b});
        }
        $o .= "</table>\n";
    }
    $o .= "<hr><p class='note'>Generated by <code>sim/halberd-gen.pl</code> from <code>docs/src/status-metrics.md</code>. Edit the doc or the generator, not this page.</p>\n</body>\n</html>\n";
    open my $fh, '>:encoding(UTF-8)', $file or die "cannot write $file: $!\n";
    print $fh $o; close $fh or die "cannot write $file: $!\n";
}
1;
