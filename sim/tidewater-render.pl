# sim/tidewater-render.pl -- docs/TIDEWATER.html: the Tidewater run at a glance. One page, no JavaScript, nothing external.
#
#   perl sim/tidewater-render.pl [--evidence docs/tidewater] [--out docs/TIDEWATER.html]
#       from the committed evidence (sim/tidewater-evidence.pl): every number is read from docs/tidewater/sprints/NN/
#       (plan.txt, scorecard.json, morale.json), so the page and the book cite the same files; tests/tidewater.t checks
#       the committed page is what this writes. Grows with the evidence: 6 sprints now, 39 when the full run is copied.
#   require "sim/tidewater-render.pl"; tidewater_render($path, score => ..., ...)
#       the in-process form sim/tidewater-sim.pl calls at the end of a full 39-sprint run.
use strict;
use warnings;
no warnings 'once';                              # %main::TW_EPIC comes from sim/tidewater-plan.pl when loaded

sub _tw_h { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
sub _tw_v { my $v = shift; defined $v && $v ne '' ? _tw_h($v) : '&ndash;' }
sub _tw_bars {                                   # a small inline SVG bar chart: [label, value] -> svg
    my ($title, $rows, %o) = @_;
    my $max = 1; for (@$rows) { $max = $_->[1] if defined $_->[1] && $_->[1] > $max }
    my $n = @$rows || 1; my $w = 640; my $bw = ($w - 60) / $n;
    my $s = qq(<svg viewBox="0 0 $w 190" width="$w" height="190" role="img" aria-label=") . _tw_h($title) . qq(" style="max-width:100%;height:auto">\n);
    for my $i (0 .. $#$rows) {
        my ($l, $v) = @{ $rows->[$i] }; $v //= 0;
        my $h = 150 * $v / $max; my $x = 50 + $i * $bw;
        $s .= sprintf qq(<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>\n), $x, 160 - $h, $bw * 0.8, $h, $o{color} // '#1f4e79';
        $s .= sprintf qq(<text x="%.1f" y="176" font-size="9" text-anchor="middle">%s</text>\n), $x + $bw * 0.4, _tw_h($l) if $n <= 20 || $i % 3 == 0;
    }
    $s .= qq(<text x="4" y="12" font-size="10">) . _tw_h($title) . qq( (max $max)</text>\n</svg>\n);
}

sub tidewater_render {
    my ($path, %a) = @_;
    my %S = %{ $a{score} };
    my @n = sort { $a <=> $b } grep { $S{$_}{card} } keys %S;
    my $c = sub { $S{ $_[0] }{card} };
    my $h = <<'HEAD';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tidewater Run</title>
<style>
  :root { --fg:#1a1a1a; --bg:#ffffff; --muted:#555; --rule:#bbb; --head:#e8e8e8; --zebra:#fafafa; --code:#f4f4f4; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --fg:#e6e6e6; --bg:#16181c; --muted:#a0a0a0; --rule:#444; --head:#2a2d33; --zebra:#1d2026; --code:#23262c; } }
  body { font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: 11pt; color: var(--fg); background: var(--bg);
         max-width: 1100px; margin: 2em auto; padding: 0 16px; line-height: 1.5; }
  h1 { font-size: 20pt; border-bottom: 2px solid var(--rule); padding-bottom: 0.2em; }
  h2 { font-size: 15pt; margin-top: 2em; border-bottom: 1px solid var(--rule); padding-bottom: 0.15em; }
  code, pre { font-family: Consolas, "Courier New", monospace; font-size: 10pt; background: var(--code); }
  pre { padding: 0.8em 1em; overflow-x: auto; }
  .wrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 10pt; }
  th, td { border: 1px solid var(--rule); padding: 0.35em 0.5em; text-align: left; vertical-align: top; }
  th { background: var(--head); } td.n, th.n { text-align: right; white-space: nowrap; }
  tr:nth-child(even) td { background: var(--zebra); }
  .note { color: var(--muted); font-size: 10pt; }
  svg text { fill: var(--fg); }
</style>
</head>
<body>
HEAD
    $h .= "<h1>Tidewater: MBSE in GitLab, sprint by sprint</h1>\n";
    $h .= "<p><strong>Tidewater is fictional, civilian and notional, and so is every number here.</strong> Three government systems engineers, Jim, Bob and Tom, "
        . "port a prime contractor's SysML v1 model of a coastal weather-observation network to SysML v2 text in GitLab, then keep it current with the prime's drops, "
        . "for $a{sprints} two-week sprints from 5 October 2026. Everything on this page was produced by running the kit: the GitLab emulator, the pipeline, gitflow, the "
        . "converters, the journal. The book <a href=\"mbse-devsecops-primer.html\">MBSE-DEVSECOPS Primer</a> tells the first twelve weeks; the evidence it quotes is in "
        . "<code>docs/tidewater/</code>.</p>\n<pre>perl sim/tidewater-sim.pl                 # data/tidewater (wiped and rebuilt), docs/tidewater/, this page\n"
        . "perl sim/tidewater-sim.pl --sprints 6     # the first twelve weeks only</pre>\n";
    $h .= "<h2>Checks</h2>\n<pre>" . _tw_h($a{checks}) . "</pre>\n";
    # sprint table
    $h .= "<h2>Sprints</h2>\n<div class=\"wrap\"><table><tr><th class=n>Sprint</th><th>Goal</th><th class=n>Capacity</th><th class=n>Committed</th><th class=n>Done</th>"
        . "<th class=n>Engineering</th><th class=n>Platform</th><th class=n>Learning</th><th class=n>Merges</th><th class=n>TODO lines</th><th class=n>MR lead (h)</th><th class=n>Morale</th></tr>\n";
    for my $n (@n) {
        my $x = $c->($n); my $w = $x->{work_mix};
        my ($g) = map { $_->{goal} } grep { $_->{n} == $n } @{ $a{plan} };
        $h .= sprintf "<tr><td class=n>%d</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td></tr>\n",
            $n, _tw_h($g), _tw_v($S{$n}{capacity}), _tw_v($x->{'11_delivery'}{committed}), _tw_v($x->{'11_delivery'}{done}), _tw_v($w->{engineering}), _tw_v($w->{platform}), _tw_v($w->{learning}),
            _tw_v($x->{merges}), _tw_v($x->{'1_todo_lines'}), _tw_v($x->{'2_lead_time_hours'}), _tw_v($x->{'12_morale'});
    }
    $h .= "</table></div>\n";
    $h .= "<h2>The port burn-down</h2>\n<p>TODO lines the converter left, on <code>develop</code> at the end of each sprint (decision D-7: the port's progress measure).</p>\n"
        . _tw_bars('TODO lines on develop', [ map { [ $_, $c->($_)->{'1_todo_lines'} ] } @n ]);
    $h .= "<h2>Work mix</h2>\n<p>Share of committed points that is engineering with the model, rather than the platform or learning.</p>\n"
        . _tw_bars('engineering share of committed points, %', [ map { my $w = $c->($_)->{work_mix}; [ $_, $w->{committed} ? int(100 * $w->{engineering} / $w->{committed} + 0.5) : 0 ] } @n ], color => '#2c7a3f');
    $h .= "<h2>Morale</h2>\n<p>The five-question pulse survey (1 to 5), mean of the three, at each retrospective.</p>\n"
        . _tw_bars('pulse survey mean', [ map { [ $_, $c->($_)->{'12_morale'} ] } @n ], color => '#7a5a1f');
    # the scorecard of the last sprint shown
    my $L = $n[-1]; my $x = $c->($L);
    $h .= "<h2>The scorecard at sprint $L</h2>\n<table><tr><th>Measure</th><th>Value</th></tr>\n";
    for my $k (sort { ($a =~ /^(\d+)/)[0] <=> ($b =~ /^(\d+)/)[0] } grep { /^\d+_/ } keys %$x) {
        my $v = $x->{$k}; $v = ref $v eq 'HASH' ? join(', ', map { "$_ " . ($v->{$_} // '-') } sort keys %$v) : $v;
        (my $name = $k) =~ s/^\d+_//; $name =~ s/_/ /g;
        $h .= "<tr><td>" . _tw_h($name) . "</td><td>" . _tw_v($v) . "</td></tr>\n";
    }
    $h .= "</table>\n<p class=note>Document-era baselines (notional, reconstructed): a requirement change through the CCB took 23 working days; "
        . "\"which requirements are unverified?\" took 2 days of spreadsheet work; a model review took 3 weeks of screenshots.</p>\n";
    # drops
    if (@{ $a{drops} // [] }) {
        $h .= "<h2>Prime drops</h2>\n<table><tr><th>Drop</th><th class=n>Sprint taken</th><th>Merged</th><th class=n>Conflicts</th><th class=n>Outline allowance</th><th class=n>MR</th></tr>\n";
        $h .= sprintf "<tr><td>%s</td><td class=n>%s</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>!%s</td></tr>\n", map { _tw_v($_) } @$_{qw(version sprint merged conflicts outline mr)} for @{ $a{drops} };
        $h .= "</table>\n";
    }
    # backlog by epic
    my %ep;
    for my $st (@{ $a{stories} }) { my $e = $ep{ $st->{epic} } //= { stories => 0, pts => 0, done => 0, first => 99, last => 0 };
        $e->{stories}++; $e->{pts} += $st->{pts}; $e->{done} += $st->{pts} if $st->{done_d}; $e->{first} = $st->{sprint} if $st->{sprint} < $e->{first}; $e->{last} = $st->{sprint} if $st->{sprint} > $e->{last} }
    $h .= "<h2>Backlog by epic</h2>\n<table><tr><th>Tome</th><th>Epic</th><th class=n>Stories</th><th class=n>Points</th><th class=n>Done</th><th>Sprints</th></tr>\n";
    for my $e (sort { ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0] } keys %ep) {
        my ($tome, $title) = @{ $main::TW_EPIC{$e} // [ '', '' ] };
        $h .= sprintf "<tr><td>%s</td><td>%s %s</td><td class=n>%d</td><td class=n>%.1f</td><td class=n>%.1f</td><td>%d&ndash;%d</td></tr>\n", _tw_h($tome), _tw_h($e), _tw_h($title), @{ $ep{$e} }{qw(stories pts done first last)};
    }
    $h .= "</table>\n<p class=note>Sizes: a task is at most 5 points (one point = one ideal person-day); a story fits one sprint; an epic fits a semester (13 sprints); a tome fits a year.</p>\n";
    $h .= "<h2>The first twelve weeks, as evidence</h2>\n<p>Each sprint's kickoff, stand-ups (chat, lint, talk.pl drafts), poker rounds, pipeline logs, the real Markdown of its issues and merge requests, "
        . "review, retrospective, quad, scorecard and pulse survey are in <code>docs/tidewater/sprints/NN/</code>.</p>\n<ul>\n"
        . join('', map { sprintf "<li><a href=\"tidewater/sprints/%02d/kickoff.txt\">Sprint %d</a>: %s</li>\n", $_->{n}, $_->{n}, _tw_h($_->{goal}) } grep { $_->{n} <= 6 } @{ $a{plan} })
        . "</ul>\n</body>\n</html>\n";
    open my $fh, '>:raw', $path or die "cannot write $path: $!\n"; print $fh $h; close $fh;
    print "wrote $path\n";
}

# ---------------------------------------------------------------- from the committed evidence (standalone)
sub _tw_slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t // '' }
sub _tw_json { my $t = _tw_slurp(shift) // return undef; require JSON::PP; eval { JSON::PP->new->decode($t) } }
sub _tw_plan {                                     # plan.txt -> { goal, capacity, committed, mix => {...}, stories => [ {id, epic, pts, work, title, tasks => [...]} ] }
    my $t = _tw_slurp(shift) // return undef;
    my %p = (stories => []);
    ($p{goal}) = $t =~ /^Goal: (.+)$/m;
    ($p{capacity}) = $t =~ /^Capacity: ([\d.]+)/m;
    if ($t =~ /^Committed: ([\d.]+) points in (\d+) stor\w+ \((\d+)% of capacity\): (.+)$/m) {
        @p{qw(committed nstories pct)} = ($1, $2, $3);
        my $mix = $4; $p{mix}{$1} = $2 while $mix =~ /(engineering|platform|learning) ([\d.]+)/g;
    }
    my $cur;
    for my $l (split /\n/, $t) {
        if ($l =~ /^(TW-\d+)\s+(E\d+)\s+([\d.]+) pts?\s+(\w+)\s+(.+)$/) { push @{ $p{stories} }, $cur = { id => $1, epic => $2, pts => $3, work => $4, title => $5, tasks => [] } }
        elsif ($cur && $l =~ /^\s+#(\d+)\s+([\d.]+) pts?\s+(\w+)\s+(\S+) \.\. (\S+)\s+(.+)$/) { push @{ $cur->{tasks} }, { iid => $1, pts => $2, who => $3, from => $4, to => $5, title => $6 } }
    }
    \%p;
}
sub tidewater_render_evidence {
    my (%o) = @_;
    my $ev = $o{evidence}; my $out = $o{out};
    my @n = sort { $a <=> $b } map { /(\d+)$/ ? $1 + 0 : () } grep { -d && m{/\d\d$} } glob("$ev/sprints/[0-9][0-9]");
    my @sp = grep { $_ >= 1 } @n;
    die "tidewater-render: no sprints in $ev/sprints (run perl sim/tidewater-evidence.pl first)\n" unless @sp;
    my (%plan, %card, %mood);
    for my $s (@sp) { my $d = sprintf "$ev/sprints/%02d", $s; $plan{$s} = _tw_plan("$d/plan.txt"); $card{$s} = _tw_json("$d/scorecard.json"); $mood{$s} = _tw_json("$d/morale.json") }
    my $rel = sub { my $f = shift; (my $r = $f) =~ s{^\Q$ev\E}{tidewater}; $r };          # links relative to docs/
    my $ln = sub { my ($f, $text) = @_; -f $f ? '<a href="' . _tw_h($rel->($f)) . '">' . _tw_h($text) . '</a>' : _tw_h($text) };
    my $h = <<'HEAD';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tidewater Run</title>
<style>
  :root { --fg:#1a1a1a; --bg:#ffffff; --muted:#555; --rule:#bbb; --head:#e8e8e8; --zebra:#fafafa; --code:#f4f4f4; --bar:#1f4e79; --bar2:#2c7a3f; --bar3:#7a5a1f; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --fg:#e6e6e6; --bg:#16181c; --muted:#a0a0a0; --rule:#444; --head:#2a2d33; --zebra:#1d2026; --code:#23262c; --bar:#6fa8dc; --bar2:#7fc28f; --bar3:#d1a85a; } }
  :root[data-theme="dark"] { --fg:#e6e6e6; --bg:#16181c; --muted:#a0a0a0; --rule:#444; --head:#2a2d33; --zebra:#1d2026; --code:#23262c; --bar:#6fa8dc; --bar2:#7fc28f; --bar3:#d1a85a; }
  body { font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: 11pt; color: var(--fg); background: var(--bg);
         max-width: 1100px; margin: 2em auto; padding: 0 16px; line-height: 1.5; }
  h1 { font-size: 20pt; border-bottom: 2px solid var(--rule); padding-bottom: 0.2em; }
  h2 { font-size: 15pt; margin-top: 2em; border-bottom: 1px solid var(--rule); padding-bottom: 0.15em; }
  code, pre { font-family: Consolas, "Courier New", monospace; font-size: 10pt; background: var(--code); }
  pre { padding: 0.8em 1em; overflow-x: auto; }
  .wrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 10pt; }
  th, td { border: 1px solid var(--rule); padding: 0.35em 0.5em; text-align: left; vertical-align: top; }
  th { background: var(--head); } td.n, th.n { text-align: right; white-space: nowrap; }
  tr:nth-child(even) td { background: var(--zebra); }
  .note { color: var(--muted); font-size: 10pt; }
  details { margin: 0.3em 0 0.3em 1em; } summary { cursor: pointer; }
  svg text { fill: var(--fg); } svg .bar { fill: var(--bar); } svg .bar2 { fill: var(--bar2); } svg .bar3 { fill: var(--bar3); }
  @media print { details { display: block; } details > * { display: block; } }
</style>
</head>
<body>
HEAD
    my $last = $sp[-1];
    $h .= "<h1>Tidewater: MBSE in GitLab, sprint by sprint</h1>\n"
        . "<p><strong>Tidewater is fictional, civilian and notional, and so is every number here.</strong> Three government systems engineers, Jim, Bob and Tom, "
        . "port a prime contractor's SysML v1 model of a coastal weather-observation network to SysML v2 text in GitLab, then keep it current with the prime's drops. "
        . "This page covers sprints 1&ndash;$last (from 5 October 2026). Every number on it is read from the evidence in <code>docs/tidewater/</code>, which a run of the kit "
        . "produced: the GitLab emulator, the pipeline, gitflow, the converters, the journal. The book <a href=\"mbse-devsecops-primer.html\">MBSE-DEVSECOPS Primer</a> "
        . "tells these weeks; <a href=\"tidewater/README.md\">docs/tidewater/README.md</a> lists every evidence file.</p>\n"
        . "<pre>perl sim/tidewater-sim.pl --dir RUN/data/tidewater --sprints 6 --no-docs   # the run\n"
        . "perl sim/tidewater-evidence.pl RUN/data/tidewater                           # its evidence into docs/tidewater/\n"
        . "perl sim/tidewater-render.pl                                                # this page</pre>\n";
    # sprint table
    $h .= "<h2>Sprints</h2>\n<div class=\"wrap\"><table><tr><th class=n>Sprint</th><th>Goal</th><th class=n>Capacity</th><th class=n>Committed</th><th class=n>Done</th>"
        . "<th class=n>Engineering</th><th class=n>Platform</th><th class=n>Learning</th><th class=n>Merges</th><th class=n>TODO lines</th><th class=n>MR lead (h)</th><th class=n>Morale</th></tr>\n";
    for my $s (@sp) {
        my ($p, $c) = ($plan{$s} // {}, $card{$s} // {});
        my $d = sprintf "$ev/sprints/%02d", $s;
        $h .= sprintf "<tr><td class=n>%s</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td></tr>\n",
            $ln->("$d/kickoff.txt", $s), _tw_h($p->{goal}), _tw_v($p->{capacity}), _tw_v($p->{committed}), _tw_v($c->{'11_delivery'}{done}),
            _tw_v($p->{mix}{engineering}), _tw_v($p->{mix}{platform}), _tw_v($p->{mix}{learning}), _tw_v($c->{merges}), _tw_v($c->{'1_todo_lines'}),
            _tw_v($c->{'2_lead_time_hours'}), _tw_v($c->{'12_morale'} // ($mood{$s} // {})->{mean});
    }
    $h .= "</table></div>\n<p class=note>Points are ideal person-days. Capacity is the three people's points less holidays and leave; learning is budgeted as stories "
        . "(<code>work::learning</code>), so it is visible and shrinks as the team gains skill. A blank cell: the sprint's scorecard is not in the evidence yet.</p>\n";
    my @have = grep { $card{$_} } @sp;
    $h .= "<h2>The port burn-down</h2>\n<p>TODO lines the converter left, on <code>develop</code> at the end of each sprint (decision D-7: the port's progress measure).</p>\n"
        . _tw_bars('TODO lines on develop', [ map { [ $_, $card{$_}{'1_todo_lines'} ] } @have ]);
    $h .= "<h2>Work mix</h2>\n<p>Committed points by kind of work. The platform and learning share falls as the team gets its tools and skills in place.</p>\n<table><tr><th class=n>Sprint</th><th class=n>Engineering %</th><th class=n>Platform %</th><th class=n>Learning %</th></tr>\n";
    for my $s (@sp) { my $m = ($plan{$s} // {})->{mix} // {}; my $t = 0; $t += $_ for values %$m; next unless $t;
        $h .= sprintf "<tr><td class=n>%d</td>%s</tr>\n", $s, join '', map { sprintf '<td class=n>%d</td>', int(100 * ($m->{$_} // 0) / $t + 0.5) } qw(engineering platform learning) }
    $h .= "</table>\n";
    # trace and verification
    $h .= "<h2>Trace and verification</h2>\n<p>DOORS against the model at the end of each sprint: C requirements linked, F orphans (nothing satisfies), G unverified, I traced end to end, drift (text differs).</p>\n"
        . "<table><tr><th class=n>Sprint</th><th class=n>C linked</th><th class=n>F orphans</th><th class=n>G unverified</th><th class=n>I complete</th><th class=n>Drift</th><th class=n>DRs opened</th><th class=n>DRs closed</th></tr>\n";
    for my $s (@have) { my $t = $card{$s}{'5_trace'} // {}; my $dr = $card{$s}{'6_drs'} // {};
        $h .= sprintf "<tr><td class=n>%d</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td></tr>\n", $s, map { _tw_v($_) } @$t{qw(C F G I drift)}, @$dr{qw(opened closed)} }
    $h .= "</table>\n";
    # pipelines and merge requests
    $h .= "<h2>Pipelines and merge requests</h2>\n<table><tr><th class=n>Sprint</th><th class=n>Merges</th><th class=n>First pipeline passed</th><th class=n>develop pipelines</th><th class=n>passing</th><th class=n>Worst restore (h)</th><th class=n>MR lead (h)</th><th class=n>Review turnaround (h)</th><th class=n>Gated</th></tr>\n";
    for my $s (@have) { my $c = $card{$s}; my $f = $c->{first_pipeline_pass} // {}; my $ph = $c->{'8_pipeline_health'} // {};
        $h .= sprintf "<tr><td class=n>%d</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td></tr>\n", $s,
            _tw_v($c->{merges}), (defined $f->{mrs} ? "$f->{passed} of $f->{mrs}" : '&ndash;'), _tw_v($ph->{develop_pipelines}), _tw_v($ph->{passing}), _tw_v($ph->{worst_restore_hours}),
            _tw_v($c->{'2_lead_time_hours'}), _tw_v($c->{'10_review_turnaround_hours'}), _tw_v($c->{'3_gated_changes'}) }
    $h .= "</table>\n";
    # morale
    $h .= "<h2>Morale</h2>\n<p>The five-question pulse survey (1 to 5) at each retrospective, mean of the three.</p>\n"
        . _tw_bars('pulse survey mean', [ map { [ $_, ($mood{$_} // {})->{mean} ] } grep { $mood{$_} } @sp ], color => '#7a5a1f');
    my ($qm) = grep { $mood{$_} && $mood{$_}{questions} } reverse @sp;
    if ($qm) {
        $h .= "<table><tr><th>Question</th>" . join('', map { "<th class=n>S$_</th>" } grep { $mood{$_} } @sp) . "</tr>\n";
        my @q = @{ $mood{$qm}{questions} };
        for my $i (0 .. $#q) {
            $h .= '<tr><td>' . _tw_h($q[$i]) . '</td>' . join('', map { my $a = $mood{$_}{answers} // {}; my @v = grep { defined } map { $a->{$_}[$i] } sort keys %$a;
                my $m; if (@v) { $m = 0; $m += $_ for @v; $m /= @v } sprintf '<td class=n>%s</td>', defined $m ? sprintf('%.1f', $m) : '&ndash;' } grep { $mood{$_} } @sp) . "</tr>\n";
        }
        $h .= "</table>\n";
    }
    # the scorecard of the last sprint with one
    if (@have) {
        my $L = $have[-1]; my $x = $card{$L};
        $h .= "<h2>The scorecard at sprint $L</h2>\n<table><tr><th>Measure</th><th>Value</th></tr>\n";
        for my $k (sort { ($a =~ /^(\d+)/)[0] <=> ($b =~ /^(\d+)/)[0] } grep { /^\d+_/ } keys %$x) {
            my $v = $x->{$k}; $v = ref $v eq 'HASH' ? join(', ', map { "$_ " . ($v->{$_} // '-') } sort keys %$v) : $v;
            (my $name = $k) =~ s/^\d+_//; $name =~ s/_/ /g;
            $h .= '<tr><td>' . _tw_h($name) . '</td><td>' . _tw_v($v) . "</td></tr>\n";
        }
        my $b = $x->{document_era_baseline_notional} // {};
        $h .= "</table>\n<p class=note>Document-era baselines (notional, reconstructed): a requirement change through the CCB took " . _tw_v($b->{ccb_change_working_days})
            . " working days; \"which requirements are unverified?\" took " . _tw_v($b->{unverified_question_days}) . " days of spreadsheet work; a model review took "
            . _tw_v($b->{model_review_weeks}) . " weeks of screenshots; drift between DOORS and the model was found " . _tw_v($b->{drift_found}) . ".</p>\n";
    }
    # the backlog tree: tome > epic > story > task
    no warnings 'once';
    my %TE;                                                        # epic -> [tome, title] from the plan's table when available
    { no strict 'refs'; %TE = %{"main::TW_EPIC"} }
    if (!%TE && -f "$o{root}/sim/tidewater-plan.pl") { local @ARGV; eval { package main; require "$o{root}/sim/tidewater-plan.pl"; 1 }; no strict 'refs'; %TE = %{"main::TW_EPIC"} }
    my %TOME; { no strict 'refs'; %TOME = %{"main::TW_TOME"} }
    my (%by);
    for my $s (@sp) { for my $st (@{ ($plan{$s} // {})->{stories} // [] }) { my $tome = ($TE{ $st->{epic} } // [ '?' ])->[0]; push @{ $by{$tome}{ $st->{epic} } }, [ $s, $st ] } }
    $h .= "<h2>The backlog: tome &gt; epic &gt; story &gt; task</h2>\n<p class=note>Sizes: a task is at most 5 points; a story fits one sprint; an epic fits a semester (13 sprints); a tome fits a year. Stories are the journal's items; tasks live in GitLab.</p>\n";
    for my $tome (sort keys %by) {
        my $tp = 0; my $tn = 0; for my $e (values %{ $by{$tome} }) { for (@$e) { $tp += $_->[1]{pts}; $tn++ } }
        $h .= sprintf "<details open><summary><b>%s %s</b> <span class=note>%d stories, %.1f points</span></summary>\n", _tw_h($tome), _tw_h($TOME{$tome} // ''), $tn, $tp;
        for my $e (sort { ($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0] } keys %{ $by{$tome} }) {
            my @st = @{ $by{$tome}{$e} }; my $ep = 0; $ep += $_->[1]{pts} for @st;
            my @sps = map { $_->[0] } @st;
            $h .= sprintf "<details><summary>%s %s <span class=note>%d stories, %.1f points, sprints %d&ndash;%d</span></summary>\n<ul>\n", _tw_h($e), _tw_h(($TE{$e} // [ '', '' ])->[1]), scalar(@st), $ep, $sps[0], $sps[-1];
            for (@st) { my ($s, $x) = @$_;
                my $sample = sprintf "$ev/sprints/%02d/samples/story-%s.md", $s, $x->{id};
                $h .= sprintf "<li>%s, sprint %d, %s points, %s: %s<ul>%s</ul></li>\n", $ln->($sample, $x->{id}), $s, $x->{pts}, _tw_h($x->{work}), _tw_h($x->{title}),
                    join('', map { sprintf "<li>%s %s pt, %s, %s&ndash;%s: %s</li>", $ln->(sprintf("$ev/sprints/%02d/samples/task-%d.md", $s, $_->{iid}), "#$_->{iid}"), $_->{pts}, _tw_h($_->{who}), $_->{from}, $_->{to}, _tw_h($_->{title}) } @{ $x->{tasks} }) }
            $h .= "</ul>\n</details>\n";
        }
        $h .= "</details>\n";
    }
    # evidence by sprint
    $h .= "<h2>The evidence, sprint by sprint</h2>\n<ul>\n";
    for my $s (@n) {
        my $d = sprintf "$ev/sprints/%02d", $s;
        my @l = grep { -f $_->[0] } ([ "$d/week-zero.txt", 'week zero' ], [ "$d/kickoff.txt", 'kickoff' ], [ "$d/plan.txt", 'plan' ], [ "$d/day-log.txt", 'day by day' ],
            [ "$d/refinement.txt", 'refinement' ], [ "$d/review.txt", 'review' ], [ "$d/review-script.md", 'demo script' ], [ "$d/retro.txt", 'retrospective' ],
            [ "$d/analytics.txt", 'analytics' ], [ "$d/scorecard.json", 'scorecard' ], [ "$d/morale.json", 'pulse survey' ]);
        my @quad = map { [ $_, 'quad ' . (m{quad-(\S+)\.txt$})[0] ] } sort glob("$d/quad-*.txt");
        my $ns = () = glob("$d/samples/*.md"); my $np = () = glob("$d/pipelines/*.log"); my $nu = () = glob("$d/standups/*-chat.txt");
        $h .= sprintf "<li><b>%s</b>%s: %s%s</li>\n", $s ? "Sprint $s" : 'Week zero', ($plan{$s} && $plan{$s}{goal} ? ' (' . _tw_h($plan{$s}{goal}) . ')' : ''),
            join(', ', map { $ln->(@$_) } @l, @quad), ($ns || $np || $nu ? sprintf('; %d stand-ups, %d pipeline logs, %d GitLab samples in <code>%s/</code>', $nu, $np, $ns, _tw_h($rel->($d))) : '');
    }
    my @samples = sort glob("$ev/samples/*.md");
    $h .= "</ul>\n<p>One real example of each GitLab Markdown field: " . join(', ', map { (my $b = $_) =~ s{.*/}{}; $ln->($_, $b) } @samples) . ".</p>\n" if @samples;
    $h .= "</body>\n</html>\n";
    open my $fh, '>:raw', $out or die "tidewater-render: cannot write $out: $!\n"; print $fh $h; close $fh;
    return $out;
}

if (!caller) {                                     # perl sim/tidewater-render.pl [--evidence DIR] [--out FILE]
    no warnings 'once';
    require Getopt::Long; require FindBin; require Cwd;
    my $root = Cwd::abs_path("$FindBin::Bin/..");
    my %o = (evidence => "$root/docs/tidewater", out => "$root/docs/TIDEWATER.html", root => $root);
    Getopt::Long::GetOptions(\%o, 'evidence=s', 'out=s', 'quiet') or do { print STDERR "usage: tidewater-render.pl [--evidence DIR] [--out FILE] [--quiet]\n"; exit 2 };
    my $w = tidewater_render_evidence(%o);
    print "wrote $w\n" unless $o{quiet};
    exit 0;
}

1;
