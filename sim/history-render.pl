# Renders HISTORY.html from the per-sprint snapshots collected by history-gen.pl.
# Loaded by `require` -- defines history_render(\@history, $out_path, \%meta).
# Self-contained HTML: no JavaScript, no external resources. Print-friendly on
# purpose (the intended end use is Print -> Save as PDF for an exit report or
# performance review): <details> sections are forced open when printed, and each
# year starts on a new page.
use strict;
use warnings;

my %COLOR = (green => '#0ca30c', amber => '#c98500', red => '#d03b3b');
sub _h { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
sub _pct { my ($a, $b) = @_; $b ? int(100 * $a / $b + 0.5) : 0 }

my $CSS = <<'CSS';
:root{--ink:#0b0b0b;--ink2:#4a4a4c;--muted:#808082;--grid:#e4e4e7;--surface:#ffffff;--page:#f4f4f5;--border:rgba(11,11,11,.10)}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;color:var(--ink);background:var(--page);margin:0;padding:18px 22px;max-width:1500px}
h1{font-size:22px;margin:0 0 2px}h1 svg.logo{height:26px;width:auto;color:#fff;vertical-align:-4px;margin-right:14px}h2{font-size:16px;border-bottom:2px solid var(--ink);margin:26px 0 8px;padding-bottom:3px}
h3{font-size:13px;margin:12px 0 4px;color:var(--ink2)}
.muted{color:var(--muted)}
table{border-collapse:collapse;margin:4px 0 10px;background:var(--surface);font-size:12px}
th,td{border:1px solid var(--grid);padding:3px 7px;text-align:left;vertical-align:top}
th{background:#e4e4e7;font-weight:600}td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
caption{caption-side:top;text-align:left;font-weight:600;color:var(--ink2);padding:2px 0 3px;font-size:11.5px}
.tiles{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}
.tile{flex:1 1 130px;background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:8px 12px}
.tile .n{font-size:22px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}
.tile .l{font-size:10px;color:var(--ink2);text-transform:uppercase;letter-spacing:.03em}
.chip{display:inline-block;padding:1px 8px;border-radius:9px;font-weight:600;font-size:11px;color:#fff;white-space:nowrap}
.cal{display:grid;grid-template-columns:repeat(26,1fr);gap:3px;margin:6px 0 4px}
.cell{border-radius:3px;padding:4px 2px;text-align:center;color:#fff;font-size:10px;line-height:1.2;font-variant-numeric:tabular-nums}
.cell b{display:block;font-size:12px}
.yearlabel{font-weight:700;font-size:12px;margin:10px 0 2px;color:var(--ink2)}
.spark{display:grid;gap:2px;margin:4px 0 10px}
.spark div{height:14px;border-radius:2px}
details{border:1px solid var(--grid);border-radius:6px;margin:5px 0;background:var(--surface)}
details>summary{cursor:pointer;padding:6px 10px;font-weight:600;list-style:none}
details>summary::-webkit-details-marker{display:none}
details>div{padding:0 12px 10px}
.year{page-break-before:always}
.year.first{page-break-before:auto}
@page{margin:16mm 12mm}
@media print{
  body{background:#fff;padding:26px 0}
  details>summary{cursor:default}
  details:not([open])>*:not(summary){display:block !important}
  details{break-inside:avoid}
  p.mark{position:fixed;left:0;right:0;margin:0;padding:2px 0;background:#fff;text-align:center}
  p.mark-top{top:0}p.mark-bottom{bottom:0}
}
CSS

sub history_render {
    my ($hist, $out, $meta) = @_;
    my @h = @$hist;
    my @teams = @{ $meta->{teams} };
    my $n = scalar @h;

    # ---- roll-ups
    my $total_done = 0; my $total_committed = 0; my $total_blocked = 0; my %level_count;
    $total_done += $_->{totals}{done}, $total_committed += $_->{totals}{committed}, $total_blocked += scalar @{ $_->{blocked} }, $level_count{ $_->{level} }++ for @h;
    my $half = int($n / 2);
    my $pred = sub { my @xs = @_; @xs ? int(100 * sum_(map { $_->{totals}{done} } @xs) / (sum_(map { $_->{totals}{committed} } @xs) || 1) + 0.5) : 0 };
    my $pred_y1 = $pred->(@h[ 0 .. $half - 1 ]);
    my $pred_y2 = $pred->(@h[ $half .. $n - 1 ]);

    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Sprint history</title><style>$CSS</style></head><body>\n";
    $html .= Scrum::mark_banner_html($meta->{marking}, 'top') . Scrum::mark_block_html($meta->{marking});   # markings from the project's scrum.conf, if any
    $html .= "<h1>" . Scrum::logo_svg() . "Sprint history <span class=muted>&middot; $h[0]{plan_date} to $h[-1]{close_date}</span></h1>\n";
    $html .= sprintf "<p class=muted>%d teams &middot; %d two-week sprints &middot; simulated from real stand-up files compiled through the kit's own pipeline (seed %d). Every number below was computed by the same Scrum.pm code that runs in production.</p>\n", scalar @teams, $n, $meta->{seed};

    # ---- KPI tiles
    $html .= "<div class=tiles>\n"
        . _tile($n, 'Sprints') . _tile($total_done, 'SP delivered') . _tile("$pred_y1% &rarr; $pred_y2%", "Predictability, 1st half \x{2192} 2nd half")
        . _tile($total_blocked, 'Blocker-sprints') . _tile(($level_count{green} // 0) . '/' . ($level_count{amber} // 0) . '/' . ($level_count{red} // 0), 'Sprints green / amber / red')
        . "</div>\n";

    # ---- the calendar: one cell per sprint, colored by the status that would have been reported at review
    $html .= "<h2>Calendar <span class=muted>one cell per sprint, colored by reported status at review</span></h2>\n";
    my $per_year = 26;
    for my $y (0 .. int(($n - 1) / $per_year)) {
        my @yr = @h[ $y * $per_year .. ($y * $per_year + $per_year - 1 > $n - 1 ? $n - 1 : $y * $per_year + $per_year - 1) ];
        $html .= "<div class=yearlabel>Year " . ($y + 1) . " <span class=muted>$yr[0]{plan_date} &ndash; $yr[-1]{close_date}</span></div>\n<div class=cal>\n";
        for my $r (@yr) {
            $html .= sprintf qq(<div class=cell style="background:%s" title="%s"><b>%d</b>%d%%</div>\n),
                $COLOR{ $r->{level} }, _h("Sprint $r->{sprint}: $r->{totals}{done}/$r->{totals}{committed} SP done, closed $r->{close_date}" . ($r->{headline} ? " -- $r->{headline}" : '')), $r->{sprint}, $r->{totals}{pct};
        }
        $html .= "</div>\n";
    }

    # ---- trend strip: predictability per sprint as a color, then per-team improvement table
    $html .= "<h2>Trend <span class=muted>predictability per sprint, then per team first half vs second half</span></h2>\n<div class=spark style=\"grid-template-columns:repeat($n,1fr)\">\n";
    for my $r (@h) {
        my $p = $r->{totals}{pct};
        my $c = $p >= 80 ? $COLOR{green} : $p >= 60 ? $COLOR{amber} : $COLOR{red};
        $html .= qq(<div style="background:$c" title="Sprint $r->{sprint}: $p%"></div>\n);
    }
    $html .= "</div>\n";
    $html .= "<table><caption>Teams: predictability, SP delivered, velocity, blockers</caption><tr><th>Team</th><th class=n>Pred. 1st half</th><th class=n>Pred. 2nd half</th><th class=n>SP delivered</th><th class=n>Avg velocity (last 3)</th><th class=n>Sprints with a blocker</th></tr>\n";
    for my $team (@teams) {
        my ($d1, $c1, $d2, $c2, $dt, $bl) = (0, 0, 0, 0, 0, 0);
        for my $i (0 .. $n - 1) {
            my $x = $h[$i]{teams}{$team} or next;
            if ($i < $half) { $d1 += $x->{done}; $c1 += $x->{committed} } else { $d2 += $x->{done}; $c2 += $x->{committed} }
            $dt += $x->{done};
            $bl++ if grep { ($_->{team} // '') eq $team } @{ $h[$i]{blocked} };
        }
        $html .= sprintf "<tr><td>%s</td><td class=n>%d%%</td><td class=n>%d%%</td><td class=n>%d</td><td class=n>%.1f</td><td class=n>%d</td></tr>\n",
            _h($team), _pct($d1, $c1), _pct($d2, $c2), $dt, $h[-1]{velocity_avg}{$team} // 0, $bl;
    }
    $html .= "</table>\n";
    if ($meta->{punt_rate} && @{ $meta->{punt_rate} }) {   # the four-letter words over the two years: punt rate by half-year (tasks punted back to TODO / tasks committed)
        my @tot = grep { $_->{team} eq 'Total' } @{ $meta->{punt_rate} };
        @tot = @{ $meta->{punt_rate} } unless @tot;
        my %q; for my $r (@tot) { my $k = int(($r->{sprint} - 1) / 13); $q{$k}{committed} += $r->{committed}; $q{$k}{punted} += $r->{punted} }
        my $w = $meta->{words} // {};
        $html .= "<table><caption>Punt rate by half-year: tasks punted back to TODO (too hard as written) / tasks committed" . ($w->{punts} ? " &middot; $w->{punts} punts, $w->{redos} redos after demos, $w->{syncs} sync pairs over the run" : '') . "</caption><tr><th>Half-year</th><th class=n>Committed</th><th class=n>Punted</th><th class=n>Rate</th></tr>\n";
        $html .= sprintf("<tr><td>H%d</td><td class=n>%d</td><td class=n>%d</td><td class=n>%d%%</td></tr>\n", $_ + 1, $q{$_}{committed}, $q{$_}{punted}, _pct($q{$_}{punted}, $q{$_}{committed})) for sort { $a <=> $b } keys %q;
        $html .= "</table>\n";
    }

    # ---- per-sprint detail, by year
    for my $y (0 .. int(($n - 1) / $per_year)) {
        my @yr = @h[ $y * $per_year .. ($y * $per_year + $per_year - 1 > $n - 1 ? $n - 1 : $y * $per_year + $per_year - 1) ];
        $html .= '<div class="year' . ($y == 0 ? ' first' : '') . '"><h2>Year ' . ($y + 1) . " <span class=muted>sprint by sprint &mdash; what would have gone to leadership at each review</span></h2>\n";
        for my $r (@yr) {
            my $t = $r->{totals};
            $html .= sprintf qq(<details><summary><span class=chip style="background:%s">%s</span> &nbsp;Sprint %d <span class=muted>%s &ndash; %s &middot; %d/%d SP done (%d%%)%s</span></summary>\n<div>\n),
                $COLOR{ $r->{level} }, uc $r->{level}, $r->{sprint}, $r->{plan_date}, $r->{close_date}, $t->{done}, $t->{committed}, $t->{pct},
                $r->{headline} ? ' &middot; ' . _h($r->{headline}) : '';
            $html .= "<table><caption>Teams: sprint $r->{sprint}</caption><tr><th>Team</th><th class=n>Cap</th><th class=n>Committed</th><th class=n>Done</th><th class=n>Carried</th><th class=n>Done %</th><th class=n>Load</th></tr>\n";
            for my $team (@teams) {
                my $x = $r->{teams}{$team} or next;
                $html .= sprintf "<tr><td>%s</td><td class=n>%s</td><td class=n>%d</td><td class=n>%d</td><td class=n>%d</td><td class=n>%d%%</td><td class=n>%s</td></tr>\n",
                    _h($team), $x->{capacity} || '&ndash;', $x->{committed}, $x->{done}, $x->{carryover}, $x->{pct}, defined $x->{load} ? "$x->{load}%" : '&ndash;';
            }
            $html .= "</table>\n";
            $html .= '<p><b>Still blocked at review:</b> ' . join('; ', map { _h("$_->{id} ($_->{team}) $_->{blocked}") } @{ $r->{blocked} }) . "</p>\n" if @{ $r->{blocked} };
            $html .= "</div></details>\n";
        }
        $html .= "</div>\n";
    }

    $html .= Scrum::mark_banner_html($meta->{marking}, 'bottom') . "</body></html>\n";
    open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n";
    print $fh $html;
    close $fh;
    1;
}
sub _tile { my ($n, $label) = @_; qq(<div class=tile><div class=n>$n</div><div class=l>) . _h($label) . '</div></div>' }
sub sum_ { my $t = 0; $t += $_ for @_; $t }

1;
