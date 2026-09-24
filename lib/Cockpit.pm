package Cockpit;
# The architect's full-screen working page: one self-contained HTML file with a JSON snapshot of
# everything Scrum.pm computes, and vanilla-JavaScript views over it (daily, weekly, sprint,
# monthly/semester/annual roll-ups, backlog tree, roadmap, IDEF0 plates). No libraries, no
# network, nothing external; the JavaScript only presents -- every number is computed here in
# Perl from the journal. This is the screen you keep open; the no-JS reports (dashboard.html,
# tree.html, roadmap.html, the mails) remain what leaves your desk.
use strict;
use warnings;
use JSON::PP ();
use Prelude qw(sorted sum maximum minimum);
use Ledger  qw(postings);
use Scrum;
use Answers qw(read_answers flags history);
use Quad;

sub days_from_standups {                      # days_from_standups($s, $standups_dir, $history_days) -> [ { date, teams => { T => { answered, roster, flags => [{level, who, text}] } } } ]
    my ($s, $dir, $hd) = @_;                  # flags are re-derived against the journal as it is now, not as it was that day
    my %by;
    for my $f (sort glob("$dir/*-answers.txt")) {
        my $rec = eval { read_answers($f) } or next;
        my $team = $rec->{team} or next;
        my ($date) = ($rec->{date} // $f) =~ /(\d{4}-\d{2}-\d{2})/ or next;
        my @h = history($dir, $team, $date, $hd // 5);
        my @roster = sorted(keys %{ members($s, $team) });
        my @fl = flags($s, $team, $rec->{answers}, \@h, roster => \@roster);
        $by{$date}{$team} = { answered => scalar @{ $rec->{answers} }, roster => scalar @roster, flags => [ map { { level => $_->{level}, who => $_->{who}, text => $_->{text} } } @fl ],
                              answers => [ map { { who => $_->{who}, time => $_->{time}, y => $_->{y}, t => $_->{t}, b => $_->{b}, blocked => $_->{blocked} ? 1 : 0, assumed => $_->{assumed} ? 1 : 0, complete => $_->{complete} ? 1 : 0 } } @{ $rec->{answers} } ] };   # what each person said, as parsed
    }
    [ map { { date => $_, teams => $by{$_} } } sorted(keys %by) ];
}
sub plates_index {                            # plates_index($plates_html_file) -> [ { node, title, page, depth } ] from the toolkit's node index table
    my $file = shift;
    return [] unless defined $file && -f $file;
    open my $fh, '<', $file or return [];
    local $/; my $html = <$fh>; close $fh;
    my @ix;
    while ($html =~ m{<tr><td><a href='#plate-([\w-]+)'>[^<]*</a></td><td[^>]*>([^<]*)</td><td><a href='#plate-[\w-]+'>(p\.\d+)</a></td></tr>}g) {
        my ($node, $title, $page) = ($1, $2, $3);
        $title =~ s/&amp;/&/g;
        push @ix, { node => $node, title => $title, page => $page, depth => ($node =~ /^\w0$/ ? 0 : length($node) - 1) };   # G0 top, G1 level 1, G12 level 2 ...
    }
    \@ix;
}
our $VERSION = '1.00';
our @EXPORT;
our ($CSS_, $JS_);                            # the page's stylesheet and script, defined below the code that embeds them

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Cockpit: unknown function '$n'\n" unless defined &{"Cockpit::$n"};
        *{"${caller}::$n"} = \&{"Cockpit::$n"};
    }
}

# ---------------------------------------------------------------- the snapshot
sub _item { my $it = shift; { id => $it->{id}, title => $it->{title}, pts => $it->{points}, owner => $it->{owner}, team => $it->{team}, state => $it->{state},
                              sprint => $it->{sprint}, blocked => $it->{blocked}, age => $it->{age}, prio => $it->{meta}{prio}, epic => $it->{meta}{epic}, tome => $it->{meta}{tome} } }
sub _st { my $x = shift; my $l = $x->{load}; !defined $l ? 'good' : $l > 110 ? 'critical' : $l > 100 ? 'warning' : 'good' }

sub snapshot {                                # snapshot($s, days => [...], attendance => [...], plates => 'plates.html', marking => $conf) -> hashref (JSON-ready)
    my ($s, %o) = @_;
    my $cur = $s->{current};
    my $u = $s->{unit} // 'SP';

    # sprint date ranges and per-day flows, from the postings themselves
    my (%span, %daily);
    for my $p (postings($s->{j})) {
        my $a = $p->{account};
        my $pts = 0 + ($p->{amount} ? (values %{ $p->{amount} })[0] // 0 : 0);
        if ($a =~ /^Sprint:(\d+):/) { my $n = $1; $span{$n}{start} = $p->{date} if !$span{$n}{start} || $p->{date} lt $span{$n}{start}; $span{$n}{end} = $p->{date} if !$span{$n}{end} || $p->{date} gt $span{$n}{end} }
        $daily{ $p->{date} }{done}      += $pts if $a =~ /:Done$/ && $pts > 0;
        $daily{ $p->{date} }{committed} += $pts if $a =~ /:Committed$/ && $pts > 0;
        $daily{ $p->{date} }{intake}    += $pts if $a =~ /^Backlog:/ && $pts > 0 && ($p->{payee} // '') =~ /^\s*(?:intake|new|add)\b/i;
        $daily{ $p->{date} }{removed}   += $pts if $a =~ /:Removed$/ && $pts > 0;
    }

    my @sprints;
    for my $n (@{ $s->{sprints} }) {
        my $r = sprint_summary($s, $n);
        my %teams;
        for my $t (keys %{ $r->{teams} }) { my $x = $r->{teams}{$t}; $teams{$t} = { map { $_ => $x->{$_} } qw(capacity committed done open carryover removed pct load) } }
        push @sprints, { n => $n, start => $span{$n}{start}, end => $span{$n}{end}, totals => { map { $_ => $r->{totals}{$_} } qw(capacity committed done open carryover removed pct load) }, teams => \%teams };
    }

    my @cards;
    my $r = defined $cur ? sprint_summary($s, $cur) : undef;
    if ($r) {
        for my $team (sorted(keys %{ $r->{teams} })) {
            my $x = $r->{teams}{$team};
            my @open = @{ $x->{open_items} };
            my %ep; $ep{$_}++ for grep { defined && length } map { $_->{meta}{epic} } @open;
            my $hot = grep { $_->{blocked} } @open;
            push @cards, { team => $team, (map { $_ => $x->{$_} } qw(capacity committed done open carryover pct load)), status => $hot ? 'critical' : _st($x), blocked => $hot,
                           epics => [ sorted(keys %ep) ], open_items => [ map { _item($_) } @open ] };
        }
    }

    my $v = velocity($s);
    my %vel = map { $_ => { avg => $v->{avg}{$_}, rows => $v->{team}{$_} } } keys %{ $v->{team} };

    my @epics = map { { tome => $_->{tome}, epic => $_->{epic}, n => scalar @{ $_->{items} }, total => $_->{total}, done => $_->{done}, wip => $_->{wip}, backlog => $_->{backlog}, removed => $_->{removed}, pct => $_->{pct},
                        teams => [ sorted(keys %{{ map { ($_->{team} // '?') => 1 } @{ $_->{items} } }}) ] } } epics($s);

    my $prev = load($s->{file}, today => Quad::add_days($s->{today}, -7), until => Quad::add_days($s->{today}, -7));
    my %quad = (all => quad($s, prev => $prev), teams => { map { my $t = $_; ($t => quad($s, team => $t, prev => $prev)) } @{ $s->{teams} } });
    my $rm = roadmap($s);
    { my %last;                               # last dated Sprint posting per epic: the Gantt's "actual to" when later than today
      for my $it (items($s)) { my $k = ($it->{meta}{tome} // '(none)') . "\0" . ($it->{meta}{epic} // '(none)');
          for my $p (@{ $it->{history} }) { next unless $p->{account} =~ /^Sprint:/; $last{$k} = $p->{date} if !$last{$k} || $p->{date} gt $last{$k} } }
      $_->{last_activity} = $last{ "$_->{tome}\0$_->{epic}" } for @{ $rm->{epics} }; }
    my @tree;
    { my %by; push @{ $by{ $_->{tome} } }, $_ for epics($s);
      for my $tome (sorted(keys %by)) {
          push @tree, { tome => $tome, open => ((grep { $_->{open} } @{ $by{$tome} }) ? 1 : 0), epics => [ map { my $e = $_; my @t = sorted(keys %{{ map { ($_->{team} // '?') => 1 } @{ $e->{items} } }});
                            { epic => $e->{epic}, pct => $e->{pct}, total => $e->{total}, done => $e->{done}, teams => \@t, integration => (@t > 1 ? 1 : 0), open => $e->{open},
                              tasks => [ map { _item($_) } @{ $e->{items} } ] } } @{ $by{$tome} } ] };
      } }

    my ($level, $headline) = defined $cur ? brief_status($s, $cur) : ('green', '');
    my ($bul) = defined $cur ? Scrum::_brief_bullets($s, $r) : ([]);

    my %marking = $o{marking} ? (banner => $o{marking}{banner} // '', lines => [ marking_lines($o{marking}) ]) : (banner => '', lines => []);
    {
        generated => $s->{today}, file => $s->{file}, unit => $u, current => $cur, teams => $s->{teams}, marking => \%marking,
        sprints => \@sprints, cards => \@cards, daily => \%daily, days => $o{days} // [], attendance => $o{attendance} // [],
        blocked => [ map { _item($_) } blocked($s) ], unassigned => [ map { _item($_) } unassigned($s) ],
        velocity => \%vel, epics => \@epics, roadmap => $rm, tree => \@tree,
        quad => \%quad,                       # the weekly quad (Quad.pm): all teams and one per team
        quad_page => $o{quad_page},          # the printable one-page quad written by daily.pl report, relative to this page (or undef)
        brief => { level => $level, headline => $headline, bullets => $bul },
        plates => $o{plates}, plates_index => plates_index($o{plates_file}), tutorial => $o{tutorial}, training => $o{training},
        roster => $o{roster} // [],           # roster.txt: name, email, team, role, org (Roster::read_roster) -- the People tab
        backlog => { master => [ map { _item($_) } backlog($s) ], teams => { map { my $t = $_; ($t => [ map { _item($_) } backlog($s, $t) ]) } @{ $s->{teams} } } },
    };
}

# ---------------------------------------------------------------- the page
sub cockpit_html {
    my ($s, %o) = @_;
    my $snap = snapshot($s, %o);
    my $json = JSON::PP->new->canonical->allow_blessed->convert_blessed->encode($snap);
    $json =~ s{</script}{<\\/script}gi;
    my $banner = Scrum::_h($snap->{marking}{banner});
    my $title  = 'Cockpit &middot; ' . Scrum::_h($s->{today}) . ' &middot; ' . Scrum::_h($s->{file});
    my $built  = do { my @t = localtime; sprintf '%02d:%02d', $t[2], $t[1] };   # when this page was built: on a shared screen, the proof it is live
    my $logo   = Scrum::logo_svg();
    my $block  = join '<br>', map { Scrum::_h($_) } @{ $snap->{marking}{lines} };   # designation indicator: cover only (print page 1) and the banner's tooltip; the footer is the banner alone
    my $tip    = @{ $snap->{marking}{lines} } ? ' title="' . Scrum::_h(join "\n", @{ $snap->{marking}{lines} }) . '"' : '';
    my $html = <<"HTML";
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cockpit</title>
<style>
$CSS_
</style></head>
<body>
<p class="mark mark-top"$tip>$banner</p>
<div class="mark-cover">$block</div>
<div id="app">
<header id="top">
  <div class="brand">$logo$title <span id="brief-chip" class="chip good">&nbsp;</span></div>
  <nav id="tabs"></nav>
  <div class="tools"><label><input type="checkbox" id="auto"> auto-reload 20 s</label> <span class="muted">built <b id="built">$built</b> &middot; F5 after <code>daily.pl report</code></span></div>
</header>
<main id="view"></main>
</div>
<p class="mark mark-bottom">$banner</p>
<script id="snap" type="application/json">$json</script>
<script>
$JS_
</script>
</body></html>
HTML
    $html;
}

$CSS_ = <<'CSS';
:root{--surface:#ffffff;--page:#f4f4f5;--ink:#0b0b0b;--ink2:#4a4a4c;--muted:#808082;--grid:#e4e4e7;--border:rgba(11,11,11,.12);
--navy:#27235d;--red:#d6292e;--grey:#808082;--lgrey:#e4e4e7;--olive:#6b7436;--gold:#e6af22;--lblue:#aac1d7;--beige:#e8ddd6;--blue:var(--navy);--blue2:var(--lblue);--good:#0ca30c;--warning:#fab219;--serious:#ec835a;--critical:#d03b3b;--orange:#e6af22;--aqua:#1baf7a;--violet:#4a3aa7}
*{box-sizing:border-box}html,body{height:100%}
body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;color:var(--ink);background:var(--page);margin:0;display:flex;flex-direction:column}
p.mark{margin:0;text-align:center;font-weight:bold;font-family:Arial,sans-serif;padding:2px 0;background:#fff;border-bottom:1px solid var(--grid)}
p.mark-bottom{border-top:1px solid var(--grid);border-bottom:0}
#app{flex:1;display:flex;flex-direction:column;min-height:0}
#top{display:flex;align-items:center;gap:18px;padding:6px 16px;background:var(--navy);color:#fff;border-bottom:3px solid var(--gold);flex-wrap:wrap}
.brand{font-size:16px;font-weight:700}.brand .chip{margin-left:8px;vertical-align:middle}
.brand svg.logo{height:24px;width:auto;color:var(--navy);vertical-align:-6px;margin-right:12px}
#tabs{display:flex;gap:2px;flex-wrap:wrap}#tabs button{font:inherit;padding:6px 12px;border:1px solid transparent;background:transparent;border-radius:6px 6px 0 0;cursor:pointer;color:#d9d8e6}#tabs button:hover{color:#fff}
#tabs button.on{background:var(--page);border-color:var(--page);color:var(--navy);font-weight:600}
.tools{margin-left:auto;font-size:12px;color:#d9d8e6}.tools code{color:#fff}
#view{flex:1;overflow:auto;padding:12px 16px}
.mark-cover{display:none}
h2{font-size:15px;margin:14px 0 6px;border-bottom:2px solid var(--ink);padding-bottom:3px}h3{font-size:13px;margin:10px 0 4px;color:var(--ink2)}
.muted{color:var(--muted)}
table{border-collapse:collapse;background:var(--surface);font-size:12px;margin:4px 0 10px}
th,td{border:1px solid var(--grid);padding:3px 7px;text-align:left;vertical-align:top}th{background:var(--lgrey);font-weight:600;position:sticky;top:0}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}caption{caption-side:top;text-align:left;font-weight:600;color:var(--ink2);padding:2px 0 3px;font-size:11.5px}
.tiles{display:flex;gap:8px;flex-wrap:wrap;margin:6px 0}
.tile{flex:1 1 120px;background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:6px 10px}
.tile .n{font-size:22px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}.tile .l{font-size:10px;color:var(--ink2);text-transform:uppercase;letter-spacing:.03em}
.tile.critical .n{color:var(--critical)}.tile.warning .n{color:#9a6300}
.chip{display:inline-block;padding:1px 8px;border-radius:9px;font-weight:600;font-size:11px;white-space:nowrap;vertical-align:middle}
.chip.good{background:var(--good);color:#fff}.chip.warning{background:var(--warning);color:var(--ink)}.chip.serious{background:var(--serious);color:var(--ink)}.chip.critical{background:var(--critical);color:#fff}
.chip.info{background:#e6e4dc;color:var(--ink2)}.tag{display:inline-block;background:#eceae2;color:var(--ink2);border-radius:4px;padding:1px 6px;font-size:10px;font-weight:600;margin:1px 2px 1px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:8px}
.card{border:1px solid var(--border);border-left:4px solid var(--good);border-radius:7px;background:var(--surface);padding:8px 10px}
.card.warning{border-left-color:var(--warning)}.card.critical{border-left-color:var(--critical)}
.card h4{margin:0 0 2px;font-size:13px;display:flex;justify-content:space-between;align-items:center;gap:6px}.card .d{font-size:11px;color:var(--ink2)}
.bar{display:inline-block;height:9px;width:100%;background:var(--grid);border-radius:5px;overflow:hidden;vertical-align:middle}.bar span{display:block;height:100%;background:var(--blue)}
.cols{display:flex;gap:16px;flex-wrap:wrap}.cols>div{flex:1 1 380px;min-width:0}
.brief{border:1px solid var(--border);border-radius:8px;background:var(--surface);padding:10px 14px;margin:6px 0 10px}
.brief .lvl{font-size:15px;font-weight:700}.brief ul{margin:6px 0 0;padding-left:20px}
.period{display:flex;gap:6px;align-items:center;margin:4px 0 8px;font-size:12px}.period button{font:inherit;font-size:12px;padding:3px 9px;border:1px solid var(--grid);background:var(--surface);border-radius:4px;cursor:pointer}
.period button.on{background:var(--ink);color:#fff;border-color:var(--ink)}
svg.chart{width:100%;height:170px;background:var(--surface);border:1px solid var(--grid);border-radius:6px}
.cal{display:grid;grid-template-columns:repeat(26,1fr);gap:3px;margin:4px 0}.cell{border-radius:3px;padding:3px 2px;text-align:center;color:#fff;font-size:10px;line-height:1.2}.cell b{display:block;font-size:11px}
.tree details{border:1px solid var(--grid);border-radius:6px;margin:4px 0;background:var(--surface)}.tree summary{cursor:pointer;padding:5px 10px;font-weight:600}
.tree .epic{margin:2px 0 2px 16px}.tree .epic summary{font-weight:500}.tree table{margin:0 10px 8px}
.filter{display:flex;gap:8px;align-items:center;margin:4px 0 8px;flex-wrap:wrap}.filter input{font:inherit;padding:4px 8px;border:1px solid var(--grid);border-radius:4px;min-width:220px}
.rm td.a{background:var(--blue);color:#fff;text-align:center;font-size:10.5px}.rm td.c{background:var(--blue2);text-align:center;font-size:10.5px}
.rm td.f{background:repeating-linear-gradient(135deg,#dcd9cf 0 3px,#f7f6f2 3px 7px)}.rm td.cur,.rm th.cur{box-shadow:inset 0 0 0 2px var(--ink)}.rm tr.tome td{background:var(--olive);color:#fff;font-weight:600}
.plates-wrap{display:flex;gap:10px;height:calc(100vh - 120px)}.plates-toc{flex:0 0 300px;overflow:auto;border:1px solid var(--grid);border-radius:6px;background:var(--surface);font-size:12px;padding:4px 0}
.plates-toc a{display:block;padding:3px 10px;color:var(--ink);text-decoration:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.plates-toc a:hover{background:var(--lgrey)}.plates-toc a.on{background:var(--blue);color:#fff}
.plates-toc a.d0{font-weight:700;margin-top:4px;border-top:1px solid var(--grid);padding-top:6px}.plates-toc a.d1{padding-left:22px}.plates-toc a.d2{padding-left:34px}.plates-toc a.d3{padding-left:46px}.plates-toc a.d4{padding-left:58px}.plates-toc a.d5{padding-left:70px}
.plates-toc a .pg{color:var(--ink2);font-size:10.5px;margin-left:4px}.plates-toc a.on .pg{color:var(--lblue)}.plates-toc a .n{display:inline-block;min-width:44px;font-family:Consolas,monospace}
iframe.plates{flex:1 1 auto;min-width:0;height:100%;border:1px solid var(--grid);background:#fff}
svg.gantt{width:100%;height:auto;background:var(--surface);border:1px solid var(--grid);border-radius:6px;display:block}
.tut-wrap{display:flex;gap:10px;height:calc(100vh - 160px)}.tut-wrap iframe.plates{flex:1 1 50%;min-width:0;height:100%}.tut-wrap.tutorial iframe.plates,.tut-wrap.replay iframe.plates{flex-basis:100%}
a.btn{font:inherit;font-size:12px;padding:3px 10px;border:1px solid var(--navy);background:var(--navy);color:#fff;border-radius:4px;text-decoration:none;margin-left:auto}a.btn+a.btn{margin-left:8px}
table.statuses{margin:4px 0 10px}table.statuses td:nth-child(2),table.statuses td:nth-child(3),table.statuses td:nth-child(4){max-width:420px}table.statuses tr.assumed td{color:var(--ink2);font-style:italic}b.id{color:var(--navy);font-weight:600}
.quad{display:grid;grid-template-columns:1fr 1fr;gap:10px}.quad .q{border:1px solid var(--grid);border-top:4px solid var(--navy);border-radius:6px;background:var(--surface);padding:6px 10px}.quad h3{margin:2px 0 4px}.quad h4{margin:6px 0 2px;font-size:12px;color:var(--olive)}.quad table{width:100%}
.qtag{display:inline-block;min-width:38px;text-align:center;border-radius:3px;padding:0 4px;font-size:10px;font-weight:700;color:#fff;background:var(--muted)}.qtag.DONE{background:var(--good)}.qtag.OPEN{background:var(--navy)}.qtag.WAIT{background:var(--critical)}.qtag.HOLD{background:#c98500}.qtag.PUNT{background:var(--critical)}.qtag.DROP{background:#555}
.qmark{display:inline-block;border:1px solid var(--olive);color:var(--olive);border-radius:3px;padding:0 3px;font-size:9px;margin-left:3px}.quad td.ok{color:var(--good);font-weight:700}.quad td.late{color:var(--critical);font-weight:700}.quad td.slip{color:#c98500;font-weight:700}
@media(max-width:900px){.quad{grid-template-columns:1fr}}
.legend{font-size:11px;color:var(--ink2);margin:2px 0 8px}.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 3px 0 8px;vertical-align:-1px}
@page{margin:14mm 10mm}
@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{display:block;background:#fff}#top,.tools,#tabs,.period,.filter{display:none !important}#view{overflow:visible;padding:0}
  p.mark{position:fixed;left:0;right:0}p.mark-top{top:0}p.mark-bottom{bottom:0}body{padding:26px 0}.mark-cover{display:block;font-size:11px;padding:4px 16px}th{position:static}iframe.plates{display:none}details:not([open])>*:not(summary){display:block !important}}
CSS

$JS_ = <<'JS';
var S = JSON.parse(document.getElementById('snap').textContent);
var TABS = [['daily','Daily'],['weekly','Weekly'],['quad','Quad'],['sprint','Sprint'],['month','Monthly'],['semester','Semester'],['annual','Annual'],['backlog','Backlog'],['roadmap','Roadmap'],['gantt','Gantt'],['people','People'],['plates','Plates'],['tutorial','Tutorial']];
var PERIOD = {month:2, semester:13, annual:26, all:9999};
var COLOR = {green:'#0ca30c', amber:'#c98500', red:'#d03b3b', good:'#0ca30c', warning:'#fab219', critical:'#d03b3b', serious:'#ec835a'};
function h(s){ return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function chip(level, text){ return '<span class="chip ' + level + '">' + h(text) + '</span>'; }
function tile(n, label, cls){ return '<div class="tile ' + (cls||'') + '"><div class="n">' + n + '</div><div class="l">' + h(label) + '</div></div>'; }
function pct(a, b){ return b ? Math.round(100 * a / b) : 0; }
function fmtDate(d){ return d || '\u2014'; }
function lastSprints(k){ var sp = S.sprints.slice(); return sp.slice(Math.max(0, sp.length - k)); }
function loadStatus(l){ return l == null ? 'good' : l > 110 ? 'critical' : l > 100 ? 'warning' : 'good'; }
function itemsTable(items, caption, cols){
  cols = cols || ['id','pts','prio','tome','epic','owner','team','age','title','blocked'];
  var head = {id:'ID',pts:S.unit,prio:'Prio',tome:'Tome',epic:'Epic',owner:'Owner',team:'Team',age:'Age',title:'Title',blocked:'Blocked',state:'State',sprint:'Sprint'};
  var num = {pts:1,prio:1,age:1,sprint:1};
  var s = '<table>' + (caption ? '<caption>' + h(caption) + '</caption>' : '') + '<tr>' + cols.map(function(c){ return '<th' + (num[c]?' class=n':'') + '>' + head[c] + '</th>'; }).join('') + '</tr>';
  items.forEach(function(it){ s += '<tr>' + cols.map(function(c){ return '<td' + (num[c]?' class=n':'') + '>' + h(it[c]) + '</td>'; }).join('') + '</tr>'; });
  return s + '</table>';
}
// ---- tiny SVG charts: bars (one or two series) and a line, no libraries
function barChart(labels, series, opts){
  opts = opts || {}; var W = 800, H = 170, L = 36, B = 22, T = 10;
  var max = Math.max(1, Math.max.apply(null, series.map(function(sr){ return Math.max.apply(null, sr.values.concat([0])); })));
  var n = labels.length, gw = (W - L - 8) / Math.max(n, 1), bw = Math.max(2, (gw - 4) / series.length);
  var s = '<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">';
  [0, .5, 1].forEach(function(f){ var y = T + (H - T - B) * (1 - f); s += '<line x1="' + L + '" y1="' + y + '" x2="' + W + '" y2="' + y + '" stroke="#e4e4e7"/><text x="' + (L - 4) + '" y="' + (y + 4) + '" font-size="10" text-anchor="end" fill="#808082">' + Math.round(max * f) + '</text>'; });
  labels.forEach(function(lb, i){
    series.forEach(function(sr, j){ var v = sr.values[i] || 0, bh = (H - T - B) * v / max, x = L + i * gw + 2 + j * bw, y = H - B - bh;
      s += '<rect x="' + x + '" y="' + y + '" width="' + (bw - 1) + '" height="' + bh + '" fill="' + sr.color + '" rx="2"><title>' + h(lb) + ' ' + h(sr.name) + ': ' + v + '</title></rect>'; });
    if (n <= 30 || i % Math.ceil(n / 26) === 0) s += '<text x="' + (L + i * gw + gw / 2) + '" y="' + (H - 6) + '" font-size="9" text-anchor="middle" fill="#52514e">' + h(lb) + '</text>';
  });
  if (opts.line){ var pts = opts.line.map(function(v, i){ return (L + i * gw + gw / 2) + ',' + (H - B - (H - T - B) * Math.min(v, max) / max); }).join(' ');
    s += '<polyline points="' + pts + '" fill="none" stroke="' + (opts.lineColor || '#0b0b0b') + '" stroke-width="2"/>'; }
  return s + '</svg>';
}
function lineChart(labels, values, opts){
  opts = opts || {}; var W = 800, H = 170, L = 36, B = 22, T = 10, max = Math.max(opts.max || 1, Math.max.apply(null, values.concat([0])));
  var n = labels.length, gw = (W - L - 8) / Math.max(n, 1);
  var s = '<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">';
  [0, .5, 1].forEach(function(f){ var y = T + (H - T - B) * (1 - f); s += '<line x1="' + L + '" y1="' + y + '" x2="' + W + '" y2="' + y + '" stroke="#e4e4e7"/><text x="' + (L - 4) + '" y="' + (y + 4) + '" font-size="10" text-anchor="end" fill="#808082">' + Math.round(max * f) + (opts.pct ? '%' : '') + '</text>'; });
  if (opts.threshold != null){ var ty = H - B - (H - T - B) * opts.threshold / max; s += '<line x1="' + L + '" y1="' + ty + '" x2="' + W + '" y2="' + ty + '" stroke="#c98500" stroke-dasharray="4 3"/>'; }
  var pts = values.map(function(v, i){ return (L + i * gw + gw / 2) + ',' + (H - B - (H - T - B) * v / max); });
  s += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="#27235d" stroke-width="2"/>';
  values.forEach(function(v, i){ var xy = pts[i].split(','); s += '<circle cx="' + xy[0] + '" cy="' + xy[1] + '" r="3" fill="#27235d"><title>' + h(labels[i]) + ': ' + v + (opts.pct ? '%' : '') + '</title></circle>';
    if (n <= 30 || i % Math.ceil(n / 26) === 0) s += '<text x="' + xy[0] + '" y="' + (H - 6) + '" font-size="9" text-anchor="middle" fill="#52514e">' + h(labels[i]) + '</text>'; });
  return s + '</svg>';
}
// ---- views
function ids(text){ return h(text || '').replace(/\b([A-Z][A-Z0-9_]{0,9}-\d{1,6})\b/g, '<b class="id">$1</b>'); }   // task ids stand out: they are what the kit tracks
function viewDaily(){
  var b = S.brief, lvl = b.level, today = S.generated, d = S.daily[today] || {};
  var day = S.days.filter(function(x){ return x.date === today; })[0];
  var flags = [], answered = 0, roster = 0;
  if (day){ Object.keys(day.teams).forEach(function(t){ var x = day.teams[t]; answered += x.answered; roster += x.roster || 0; x.flags.forEach(function(f){ flags.push({team:t, level:f.level, who:f.who, text:f.text}); }); }); }
  var s = '<div class="brief"><span class="lvl" style="color:' + COLOR[lvl] + '">' + lvl.toUpperCase() + '</span> &mdash; ' + (S.current != null ? 'Sprint ' + S.current + ', ' : '') + h(today) + '. ' + h(b.headline || 'On track, no blockers.') +
    (b.bullets.length ? '<ul>' + b.bullets.map(function(x){ return '<li>' + h(x) + '</li>'; }).join('') + '</ul>' : '') + '</div>';
  s += '<div class="tiles">' + tile(d.done || 0, S.unit + ' done today') + tile(d.intake || 0, S.unit + ' intake today') + tile(S.blocked.length, 'Blocked', S.blocked.length ? 'critical' : '') +
       tile(flags.filter(function(f){ return f.level !== 'info'; }).length, 'Flags', flags.length ? 'warning' : '') + tile(day ? answered + (roster ? ' / ' + roster : '') : '\u2014', 'Answered in chat') + tile(S.unassigned.length, 'Unassigned', S.unassigned.length ? 'warning' : '') + '</div>';
  // what everyone said, as the parser read it: one row per person, by team; the ids are what the kit tracks
  if (day) {
    s += '<h2>Statuses today <span class="muted">what each person said, as parsed (Y = yesterday, T = today, B = blockers)</span></h2>';
    Object.keys(day.teams).sort().forEach(function(t){ var x = day.teams[t]; if (!x.answers || !x.answers.length) return;
      s += '<table class="statuses"><caption>' + h(t) + ' \u2014 ' + x.answers.length + ' of ' + (x.roster || '?') + '</caption><tr><th>Who</th><th>Y</th><th>T</th><th>B</th><th></th></tr>' +
        x.answers.slice().sort(function(p, q){ return (p.time || '') < (q.time || '') ? -1 : (p.time || '') > (q.time || '') ? 1 : 0; }).map(function(a){ var st = a.assumed ? chip('warning', 'assumed') : a.blocked ? chip('serious', 'blocked') : !a.complete ? chip('warning', 'incomplete') : '';
          return '<tr' + (a.assumed ? ' class="assumed"' : '') + '><td>' + h(a.who) + (a.time ? ' <span class="muted">' + h(a.time) + '</span>' : '') + '</td><td>' + ids(a.y) + '</td><td>' + ids(a.t) + '</td><td>' + ids(a.b) + '</td><td>' + st + '</td></tr>'; }).join('') + '</table>'; });
  }
  s += '<div class="cols"><div><h2>Flags today</h2>';
  s += flags.length ? '<table><tr><th></th><th>Team</th><th>Who</th><th>Flag</th></tr>' + flags.sort(function(a, b){ return ({red:0, amber:1, info:2}[a.level] || 3) - ({red:0, amber:1, info:2}[b.level] || 3); })
        .map(function(f){ return '<tr><td>' + chip({red:'critical', amber:'warning', info:'info'}[f.level] || 'info', f.level) + '</td><td>' + h(f.team) + '</td><td>' + h(f.who) + '</td><td>' + h(f.text) + '</td></tr>'; }).join('') + '</table>'
      : '<p class="muted">No answers recorded for ' + h(today) + ' (run daily.pl answers after the townhall).</p>';
  s += '</div><div><h2>Blocked now</h2>' + (S.blocked.length ? itemsTable(S.blocked, null, ['id','team','owner','title','blocked']) : '<p class="muted">Nothing blocked.</p>');
  s += '<h2>Load by team</h2><table><tr><th>Team</th><th class=n>Cap</th><th class=n>Commit</th><th class=n>Done</th><th class=n>Open</th><th class=n>Load</th></tr>' + S.cards.map(function(c){ return '<tr><td>' + h(c.team) + '</td><td class=n>' + h(c.capacity) + '</td><td class=n>' + c.committed + '</td><td class=n>' + c.done + '</td><td class=n>' + c.open + '</td><td class=n>' + (c.load == null ? '\u2014' : chip(loadStatus(c.load) === 'good' ? 'info' : loadStatus(c.load), c.load + '%')) + '</td></tr>'; }).join('') + '</table></div></div>';
  return s;
}
function workdaysBack(n){ var out = [], d = new Date(S.generated + 'T12:00:00'); while (out.length < n){ var wd = d.getDay(); if (wd !== 0 && wd !== 6) out.unshift(d.toISOString().slice(0, 10)); d.setDate(d.getDate() - 1); } return out; }
function viewWeekly(){
  var days = workdaysBack(5);
  var rows = days.map(function(dt){ var d = S.daily[dt] || {}, day = S.days.filter(function(x){ return x.date === dt; })[0], fl = {red:0, amber:0}, ans = 0;
    if (day) Object.keys(day.teams).forEach(function(t){ ans += day.teams[t].answered; day.teams[t].flags.forEach(function(f){ if (fl[f.level] != null) fl[f.level]++; }); });
    return {date:dt, done:d.done || 0, intake:d.intake || 0, committed:d.committed || 0, answered:day ? ans : null, red:fl.red, amber:fl.amber}; });
  var s = '<h2>This week <span class="muted">last five workdays to ' + h(S.generated) + '</span></h2>';
  s += '<div class="tiles">' + tile(rows.reduce(function(a, r){ return a + r.done; }, 0), S.unit + ' done') + tile(rows.reduce(function(a, r){ return a + r.intake; }, 0), S.unit + ' intake') + tile(rows.reduce(function(a, r){ return a + r.red; }, 0), 'Red flags', 'critical') + tile(rows.reduce(function(a, r){ return a + r.amber; }, 0), 'Amber flags', 'warning') + '</div>';
  s += barChart(rows.map(function(r){ return r.date.slice(5); }), [{name:'done', values:rows.map(function(r){ return r.done; }), color:'#27235d'}, {name:'intake', values:rows.map(function(r){ return r.intake; }), color:'#e6af22'}]);
  s += '<div class="legend"><i style="background:#27235d"></i>done <i style="background:#e6af22"></i>intake</div>';
  s += '<table><tr><th>Day</th><th class=n>Done</th><th class=n>Intake</th><th class=n>Committed</th><th class=n>Answered</th><th class=n>Red</th><th class=n>Amber</th></tr>' + rows.map(function(r){ return '<tr><td>' + h(r.date) + '</td><td class=n>' + r.done + '</td><td class=n>' + r.intake + '</td><td class=n>' + r.committed + '</td><td class=n>' + (r.answered == null ? '\u2014' : r.answered) + '</td><td class=n>' + r.red + '</td><td class=n>' + r.amber + '</td></tr>'; }).join('') + '</table>';
  s += '<h2>Velocity <span class="muted">3-sprint average per team</span></h2><table><tr><th>Team</th><th class=n>Avg</th>' + lastSprints(4).map(function(sp){ return '<th class=n>S' + sp.n + '</th>'; }).join('') + '</tr>' +
    S.teams.map(function(t){ var v = S.velocity[t] || {avg:0, rows:[]}; return '<tr><td>' + h(t) + '</td><td class=n>' + (Math.round(v.avg * 10) / 10) + '</td>' + lastSprints(4).map(function(sp){ var r = v.rows.filter(function(x){ return x.sprint == sp.n; })[0]; return '<td class=n>' + (r ? r.done + '/' + r.committed : '') + '</td>'; }).join('') + '</tr>'; }).join('') + '</table>';
  return s;
}
function viewSprint(){
  if (S.current == null) return '<p class="muted">No sprint yet.</p>';
  var sp = S.sprints.filter(function(x){ return x.n == S.current; })[0], t = sp.totals;
  var s = '<h2>Sprint ' + S.current + ' <span class="muted">' + h(fmtDate(sp.start)) + ' &ndash; ' + h(fmtDate(sp.end)) + '</span></h2>';
  s += '<div class="tiles">' + tile(t.pct + '%', 'Done') + tile(t.done + '/' + t.committed, S.unit + ' done / committed') + tile(t.open, 'Open ' + S.unit) + tile(t.carryover, 'Carried') + tile(S.blocked.length, 'Blocked', S.blocked.length ? 'critical' : '') + tile(t.load == null ? '\u2014' : t.load + '%', 'Load', loadStatus(t.load) === 'good' ? '' : loadStatus(t.load)) + '</div>';
  // burn: cumulative done by date within the sprint's span vs a straight line to committed
  var dates = Object.keys(S.daily).filter(function(d){ return sp.start && d >= sp.start && (!sp.end || d <= sp.end || d <= S.generated); }).sort(), cum = 0, series = [];
  dates.forEach(function(d){ cum += (S.daily[d].done || 0); series.push(cum); });
  if (dates.length){ var ideal = dates.map(function(_, i){ return Math.round(t.committed * (i + 1) / Math.max(dates.length, 1)); });
    s += '<h3>Burn-up: ' + S.unit + ' done, cumulative (line = straight-line plan to ' + t.committed + ')</h3>' + barChart(dates.map(function(d){ return d.slice(5); }), [{name:'done', values:series, color:'#27235d'}], {line:ideal, lineColor:'#c98500'}); }
  s += '<h2>Teams</h2><div class="grid">' + S.cards.map(function(c){ var badge = c.blocked ? chip('critical', c.blocked + ' BLOCKED') : c.load == null ? chip('info', 'no cap') : chip(loadStatus(c.load) === 'good' ? 'good' : loadStatus(c.load), c.load + '% LOAD');
    return '<div class="card ' + c.status + '"><h4>' + h(c.team) + badge + '</h4><div class="d">' + c.done + '/' + c.committed + ' ' + S.unit + ' done (' + c.pct + '%) &middot; ' + c.open_items.length + ' open</div><span class="bar"><span style="width:' + Math.min(100, c.pct) + '%"></span></span>' +
      '<div class="d">Cap <b>' + h(c.capacity || '\u2014') + '</b> &middot; Carry <b>' + c.carryover + '</b></div><div>' + c.epics.map(function(e){ return '<span class="tag">' + h(e) + '</span>'; }).join('') + '</div>' +
      '<details' + (c.status === 'critical' ? ' open' : '') + '><summary>' + c.open_items.length + ' open tasks</summary>' + itemsTable(c.open_items, null, ['id','pts','owner','title','blocked']) + '</details></div>'; }).join('') + '</div>';
  if (S.unassigned.length) s += '<h2>Unassigned</h2>' + itemsTable(S.unassigned, null, ['id','team','pts','title']);
  return s;
}
function viewPeriod(kind){
  var k = state.period || (kind === 'month' ? 2 : kind === 'semester' ? 13 : 26), sps = lastSprints(k), done = sum(sps, 'done'), com = sum(sps, 'committed');
  function sum(a, f){ return a.reduce(function(x, sp){ return x + (sp.totals[f] || 0); }, 0); }
  var intake = 0, removed = 0; if (sps.length){ var from = sps[0].start || '0000', to = S.generated; Object.keys(S.daily).forEach(function(d){ if (d >= from && d <= to){ intake += S.daily[d].intake || 0; removed += S.daily[d].removed || 0; } }); }
  var labels = {month:'Month', semester:'Semester', annual:'Annual'};
  var s = '<h2>' + labels[kind] + ' roll-up <span class="muted">' + sps.length + ' sprint' + (sps.length === 1 ? '' : 's') + (sps.length ? ', ' + h(fmtDate(sps[0].start)) + ' &ndash; ' + h(fmtDate(sps[sps.length - 1].end)) : '') + '</span></h2>';
  s += '<div class="period">Sprints: ' + [[2, '2'], [6, '6'], [13, '13'], [26, '26'], [9999, 'all']].map(function(p){ return '<button class="' + (k === p[0] ? 'on' : '') + '" onclick="state.period=' + p[0] + ';render()">' + p[1] + '</button>'; }).join('') + '</div>';
  if (!sps.length) return s + '<p class="muted">No sprints in range.</p>';
  var pred = pct(done, com);
  s += '<div class="tiles">' + tile(done, S.unit + ' done') + tile(com, S.unit + ' committed') + tile(pred + '%', 'Predictability', pred < 80 ? 'warning' : '') + tile(intake, S.unit + ' intake') + tile(sum(sps, 'carryover'), 'Carried') + tile(removed, 'Removed') + tile(intake > done ? 'intake > done' : 'done \u2265 intake', 'Backlog trend', intake > done ? 'warning' : '') + '</div>';
  s += '<div class="cols"><div><h3>Done vs committed per sprint</h3>' + barChart(sps.map(function(sp){ return 'S' + sp.n; }), [{name:'committed', values:sps.map(function(sp){ return sp.totals.committed; }), color:'#e6af22'}, {name:'done', values:sps.map(function(sp){ return sp.totals.done; }), color:'#27235d'}]) +
       '<div class="legend"><i style="background:#e6af22"></i>committed <i style="background:#27235d"></i>done</div></div>';
  s += '<div><h3>Predictability per sprint (dashed = 80%)</h3>' + lineChart(sps.map(function(sp){ return 'S' + sp.n; }), sps.map(function(sp){ return sp.totals.pct; }), {max:100, pct:true, threshold:80}) + '</div></div>';
  if (kind === 'annual'){ s += '<h3>Calendar: one cell per sprint, colored by done %</h3><div class="cal">' + sps.map(function(sp){ var p = sp.totals.pct, c = p >= 80 ? COLOR.green : p >= 60 ? COLOR.amber : COLOR.red;
      return '<div class="cell" style="background:' + c + '" title="Sprint ' + sp.n + ': ' + sp.totals.done + '/' + sp.totals.committed + ' ' + S.unit + ', ' + h(fmtDate(sp.end)) + '"><b>' + sp.n + '</b>' + p + '%</div>'; }).join('') + '</div>'; }
  s += '<h3>Teams over the period</h3><table><tr><th>Team</th><th class=n>Committed</th><th class=n>Done</th><th class=n>Pred.</th><th class=n>Carried</th><th class=n>Avg velocity</th></tr>' + S.teams.map(function(t){ var c = 0, d = 0, cr = 0; sps.forEach(function(sp){ var x = sp.teams[t]; if (x){ c += x.committed; d += x.done; cr += x.carryover; } });
      var p = pct(d, c); return '<tr><td>' + h(t) + '</td><td class=n>' + c + '</td><td class=n>' + d + '</td><td class=n>' + (c ? chip(p >= 80 ? 'good' : p >= 60 ? 'warning' : 'critical', p + '%') : '\u2014') + '</td><td class=n>' + cr + '</td><td class=n>' + (S.velocity[t] ? Math.round(S.velocity[t].avg * 10) / 10 : '') + '</td></tr>'; }).join('') + '</table>';
  s += '<h3>Epics by tome</h3><table><tr><th>Tome</th><th>Epic</th><th>Teams</th><th class=n>Tasks</th><th class=n>Total</th><th class=n>Done</th><th class=n>In sprint</th><th class=n>Backlog</th><th class=n>Done %</th></tr>' + S.epics.map(function(e){ return '<tr><td>' + h(e.tome) + '</td><td>' + h(e.epic) + (e.teams.length > 1 ? ' ' + chip('warning', e.teams.length + ' teams') : '') + '</td><td class="muted">' + h(e.teams.join(', ')) + '</td><td class=n>' + e.n + '</td><td class=n>' + e.total + '</td><td class=n>' + e.done + '</td><td class=n>' + e.wip + '</td><td class=n>' + e.backlog + '</td><td class=n>' + e.pct + '%</td></tr>'; }).join('') + '</table>';
  return s;
}
function viewBacklog(){
  var q = (state.q || '').toLowerCase(), team = state.team || '';
  var s = '<h2>Backlog tree <span class="muted">tome &gt; epic &gt; task; an epic touching more than one team is an integration point</span></h2>';
  s += '<div class="filter"><input placeholder="filter: id, title, owner, epic\u2026" value="' + h(state.q || '') + '" oninput="state.q=this.value;render()"> Team: <select onchange="state.team=this.value;render()"><option value="">all</option>' + S.teams.map(function(t){ return '<option' + (t === team ? ' selected' : '') + '>' + h(t) + '</option>'; }).join('') + '</select>' +
    ' <label><input type="checkbox" ' + (state.openOnly ? 'checked' : '') + ' onchange="state.openOnly=this.checked;render()"> open work only</label></div>';
  var shown = 0;
  s += '<div class="tree">' + S.tree.map(function(tm){
    var eps = tm.epics.map(function(e){ var tasks = e.tasks.filter(function(t){ return (!team || t.team === team) && (!state.openOnly || (t.state === 'committed' || t.state === 'carryover' || t.state === 'backlog' || t.state === 'master')) && (!q || [t.id, t.title, t.owner, e.epic, tm.tome, t.team].join(' ').toLowerCase().indexOf(q) >= 0); });
      if (!tasks.length) return ''; shown += tasks.length;
      return '<details class="epic"' + (q || team ? ' open' : '') + '><summary>' + h(e.epic) + (e.open ? ' <span class="qtag OPEN">OPEN</span>' : '') + ' <span class="muted">' + e.done + '/' + e.total + ' ' + S.unit + ' (' + e.pct + '%) &middot; ' + tasks.length + ' task' + (tasks.length === 1 ? '' : 's') + '</span> ' + e.teams.map(function(t){ return '<span class="tag">' + h(t) + '</span>'; }).join('') + (e.integration ? ' ' + chip('warning', 'integration point') : '') + '</summary>' + itemsTable(tasks, null, ['id','pts','prio','owner','team','state','sprint','title','blocked']) + '</details>'; }).join('');
    if (!eps) return '';
    return '<details open><summary>' + h(tm.tome) + ' <span class="muted">' + tm.epics.length + ' epics</span></summary>' + eps + '</details>'; }).join('') + '</div>';
  s += '<h3>Master backlog <span class="muted">' + S.backlog.master.length + ' tasks</span></h3>' + (S.backlog.master.length ? itemsTable(S.backlog.master, null, ['id','pts','prio','tome','epic','owner','age','title']) : '<p class="muted">empty</p>');
  return s.replace('Backlog tree <span', 'Backlog tree <span class="muted">(' + shown + ' tasks shown)</span> <span');
}
function viewRoadmap(){
  var r = S.roadmap, sp = r.sprints, cur = r.current;
  if (!sp.length) return '<p class="muted">No sprints yet.</p>';
  var s = '<h2>Roadmap <span class="muted">epics by tome across sprints; solid = done, light = in progress, striped = forecast at the owning teams\' velocity</span></h2>';
  s += '<table class="rm"><tr><th>Tome &gt; Epic</th><th>Teams</th>' + sp.map(function(n){ return '<th class="n' + (n === cur ? ' cur' : '') + '">' + n + '</th>'; }).join('') + '<th class=n>Done</th><th class=n>Left</th><th>ETA</th></tr>';
  var last = '';
  r.epics.forEach(function(e){ if (e.tome !== last){ s += '<tr class="tome"><td colspan="' + (sp.length + 5) + '">' + h(e.tome) + '</td></tr>'; last = e.tome; }
    s += '<tr><td>' + h(e.epic) + (e.blocked ? ' ' + chip('serious', e.blocked + ' blocked') : '') + '</td><td class="muted">' + h(e.teams.join(', ')) + '</td>';
    sp.forEach(function(n){ var p = e.per_sprint[n], cls = p && p.done ? 'a' : p && p.committed ? 'c' : (e.end != null && cur != null && n > cur && n <= e.end) ? 'f' : ''; if (n === cur) cls += ' cur';
      s += cls ? '<td class="' + cls + '">' + (p && p.done ? p.done : p && p.committed ? p.committed : '') + '</td>' : '<td></td>'; });
    var eta = e.remaining <= 0 ? 'done' : e.end != null ? 'sprint ' + e.end : 'no velocity yet';
    s += '<td class=n>' + e.pct + '%</td><td class=n>' + e.remaining + '</td><td>' + h(eta) + '</td></tr>'; });
  return s + '</table>';
}
// ---- gantt: the roadmap on a calendar axis. Sprint n's dates come from the journal; sprints past the last
// one are extrapolated at 14 days. Actual = first sprint touched .. today (navy); forecast = today .. ETA (gold, hatched).
function sprintDates(){
  var known = S.sprints.filter(function(x){ return x.start; }), map = {};
  known.forEach(function(x){ map[x.n] = {start: x.start, end: x.end}; });
  var base = known.length ? known[known.length - 1] : null;
  return function(n){
    if (map[n]) return map[n];
    if (!base) return null;
    var d = new Date(base.start + 'T00:00:00'); d.setDate(d.getDate() + 14 * (n - base.n));
    var e = new Date(d); e.setDate(e.getDate() + 13);
    return {start: iso(d), end: iso(e), extrapolated: true};
  };
}
function iso(d){ return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
function dayN(s){ return Math.round(new Date(s + 'T00:00:00').getTime() / 864e5); }
function viewGantt(){
  var r = S.roadmap, cur = r.current, sd = sprintDates();
  if (!r.sprints.length || !sd(r.sprints[0])) return '<p class="muted">No sprints with dates yet.</p>';
  var today = S.generated, lastN = r.sprints[r.sprints.length - 1];
  r.epics.forEach(function(e){ if (e.end != null && e.end > lastN) lastN = e.end; });
  var t0 = dayN(sd(r.sprints[0]).start), t1 = dayN(sd(lastN).end) + 1, span = t1 - t0;
  var L = 280, W = 1400, rowH = 22, top = 34, rows = [], last = '';
  r.epics.forEach(function(e){ if (e.tome !== last){ rows.push({tome: e.tome, epics: []}); last = e.tome; } rows[rows.length - 1].epics.push(e); });
  var n = rows.reduce(function(a, t){ return a + 1 + t.epics.length; }, 0), H = top + n * rowH + 24;
  var R = 110, x = function(d){ return L + (dayN(d) - t0) / span * (W - L - R); }, xe = function(d){ return L + (dayN(d) + 1 - t0) / span * (W - L - R); };
  var s = '<h2>Gantt <span class="muted">epics by tome on the calendar; navy = actual to date, gold = forecast to the ETA at the owning teams\' velocity, &#9670; = ETA, red edge = blocked</span></h2>';
  s += '<svg class="gantt" viewBox="0 0 ' + W + ' ' + H + '" font-family="Segoe UI,Arial,sans-serif" font-size="11">';
  s += '<defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="#f6e7b8"/><line x1="0" y1="0" x2="0" y2="6" stroke="#e6af22" stroke-width="2"/></pattern></defs>';
  var every = Math.max(1, Math.ceil((lastN - r.sprints[0] + 1) / 24));   // label every k-th sprint so the axis stays legible over two years
  for (var k = r.sprints[0]; k <= lastN; k++) { var d = sd(k); if (!d) break;
    s += '<rect x="' + x(d.start) + '" y="0" width="' + (xe(d.end) - x(d.start)) + '" height="' + H + '" fill="' + (k % 2 ? '#fff' : '#f4f4f5') + '"' + (k === cur ? ' stroke="#0b0b0b" stroke-width="1.5"' : '') + '/>'; }
  for (var k2 = r.sprints[0]; k2 <= lastN; k2++) { var d2 = sd(k2); if (!d2) break;               // labels after all bands, so no band paints over a label
    if ((k2 - r.sprints[0]) % every === 0 || k2 === cur) s += '<text x="' + (x(d2.start) + 4) + '" y="13" font-weight="600" fill="' + (d2.extrapolated ? '#808082' : '#0b0b0b') + '">S' + k2 + '</text><text x="' + (x(d2.start) + 4) + '" y="26" fill="#808082">' + d2.start.slice(5) + '</text>'; }
  var y = top;
  rows.forEach(function(t){
    var a = null, b = null;
    t.epics.forEach(function(e){ var f = sd(e.first || r.sprints[0]), g = sd(e.end != null ? e.end : (e.last || cur)); if (f && (!a || f.start < a)) a = f.start; if (g && (!b || g.end > b)) b = g.end; });
    s += '<rect x="0" y="' + y + '" width="' + W + '" height="' + rowH + '" fill="#e4e4e7" opacity=".6"/><text x="6" y="' + (y + 15) + '" font-weight="700">' + h(t.tome) + '</text>';
    if (a && b) s += '<rect x="' + x(a) + '" y="' + (y + 8) + '" width="' + Math.max(2, xe(b) - x(a)) + '" height="6" rx="3" fill="#6b7436"/>';
    y += rowH;
    t.epics.forEach(function(e){
      var f = sd(e.first || cur), done = e.remaining <= 0, eta = e.end != null ? sd(e.end) : null;
      s += '<text x="18" y="' + (y + 15) + '">' + h(e.epic.length > 40 ? e.epic.slice(0, 39) + '\u2026' : e.epic) + '</text>';
      var tip = '<title>' + h(e.epic) + '\n' + h(e.teams.join(', ')) + '\n' + e.done + '/' + e.total + ' ' + S.unit + ' (' + e.pct + '%), ' + e.remaining + ' left' + (eta ? '\nETA sprint ' + e.end + ' (' + eta.end + ')' : '') + (e.blocked ? '\n' + e.blocked + ' blocked' : '') + '</title>';
      if (f) {
        var far = e.last_activity && e.last_activity > today ? e.last_activity : today;   // journal may run past today (planned days)
        var aEnd = done ? (e.last_activity || sd(e.last || cur).end) : (far < f.start ? f.start : far);
        var stroke = e.blocked ? ' stroke="#d6292e" stroke-width="2"' : '';
        s += '<g>' + tip + '<rect x="' + x(f.start) + '" y="' + (y + 5) + '" width="' + Math.max(3, x(aEnd) - x(f.start)) + '" height="12" rx="2" fill="#27235d"' + stroke + '/>';
        if (!done && eta && eta.end > aEnd) s += '<rect x="' + x(aEnd) + '" y="' + (y + 5) + '" width="' + Math.max(2, xe(eta.end) - x(aEnd)) + '" height="12" rx="2" fill="url(#hatch)"' + stroke + '/>';
        var mx = done ? x(aEnd) : eta ? xe(eta.end) : null;
        if (mx != null) s += '<path d="M' + mx + ' ' + (y + 5) + ' l6 6 l-6 6 l-6 -6 z" fill="' + (done ? '#0ca30c' : '#e6af22') + '" stroke="#0b0b0b" stroke-width=".8"/>';
        s += '<text x="' + ((mx != null ? mx : x(aEnd)) + 9) + '" y="' + (y + 15) + '" fill="#4a4a4c">' + e.pct + '%' + (e.end == null && !done ? ' \u00b7 no velocity yet' : '') + '</text></g>';
      } else s += '<text x="' + (L + 4) + '" y="' + (y + 15) + '" fill="#808082">not started</text>';
      y += rowH; }); });
  var tx = x(today); if (tx >= L && tx <= W) s += '<line x1="' + tx + '" y1="' + (top - 4) + '" x2="' + tx + '" y2="' + H + '" stroke="#d6292e" stroke-width="1.5"/><text x="' + (tx + 3) + '" y="' + (H - 6) + '" fill="#d6292e" font-size="10">today ' + today + '</text>';
  return s + '</svg>';
}
function viewTutorial(){                       // two panels: the Vim tutorial (left) and the training replay (right); Both / Tutorial / Replay is remembered
  if (!S.tutorial && !S.training) return '<p class="muted">docs/TUTORIAL.html and docs/TRAINING.html not found beside the kit.</p>';
  if (!state.tut) { try { state.tut = localStorage.getItem('cockpit-tut') || 'both'; } catch (e) { state.tut = 'both'; } }
  var lay = state.tut; if (!S.training && lay !== 'tutorial') lay = 'tutorial'; if (!S.tutorial && lay !== 'replay') lay = 'replay';
  var sw = [['both','Both'],['tutorial','Tutorial'],['replay','Replay']].map(function(o){ return '<button class="' + (lay === o[0] ? 'on' : '') + '" onclick="tutLayout(\'' + o[0] + '\')">' + o[1] + '</button>'; }).join('');
  var links = '<div class="filter"><span class="period">' + sw + '</span><span class="muted">Left: updating the data in Vim &mdash; two files, ten verbs, one keystroke to compile. Right: one sprint of the same commands, run for real against data/demo.</span>' +
    (S.tutorial ? '<a class="btn" href="' + h(S.tutorial) + '" target="_blank">Tutorial in its own tab &#8599;</a>' : '') +
    (S.training ? '<a class="btn" href="' + h(S.training) + '" target="_blank">Replay in its own tab &#8599;</a>' : '') + '</div>';
  var f = function(src, title){ return '<iframe class="plates" title="' + title + '" src="' + h(src) + '"></iframe>'; };
  return links + '<div class="tut-wrap ' + lay + '">' + (S.tutorial && lay !== 'replay' ? f(S.tutorial, 'Tutorial') : '') + (S.training && lay !== 'tutorial' ? f(S.training, 'Training replay') : '') + '</div>';
}
function tutLayout(l){ state.tut = l; try { localStorage.setItem('cockpit-tut', l); } catch (e) {} render(); }
// ---- people: the roster with today's answer and each person's clean streak (consecutive days with a complete status carrying a task id)
function viewQuad(){
  if (!S.quad) return '<p class="muted">No quad in this snapshot.</p>';
  var q = state.quadTeam && S.quad.teams[state.quadTeam] ? S.quad.teams[state.quadTeam] : S.quad.all, m = q.metrics;
  var TR = {improving:'\u2197 improving', degrading:'\u2198 degrading', same:'\u2192 no change', 'new':'first week'}, AR = {pushed:'\u2192 pushed right', pulled:'\u2190 pulled left', same:'= no change', 'new':'+ new'};
  var s = '<h2>Weekly quad' + (q.team ? ' \u00b7 ' + h(q.team) : '') + ' <span class="muted">as of ' + h(q.as_of) + (q.sprint != null ? ' \u00b7 sprint ' + q.sprint : '') + '</span></h2>';
  s += '<div class="filter">Team: <select onchange="state.quadTeam=this.value;render()"><option value="">all</option>' + S.teams.map(function(t){ return '<option' + (state.quadTeam === t ? ' selected' : '') + '>' + h(t) + '</option>'; }).join('') + '</select>' + (S.quad_page ? ' <a class="btn" href="' + h(S.quad_page) + '" target="_blank">printable page</a>' : '') + '</div>';
  s += '<div class="tiles">' + tile(m.sprint.pct + '%', 'Sprint progress \u00b7 ' + TR[m.sprint.trend] + (m.sprint.prev_pct != null ? ' (was ' + m.sprint.prev_pct + '%)' : ''), m.sprint.trend === 'degrading' ? 'warning' : '') +
    tile(m.ontime.week_ontime + '/' + m.ontime.week_total, 'On time this week') + tile(m.ontime.sprint_ontime + '/' + m.ontime.sprint_total, 'On time this sprint', m.ontime.sprint_total && m.ontime.sprint_ontime / m.ontime.sprint_total < 0.8 ? 'warning' : '') + '</div>';
  s += '<div class="quad">';
  s += '<div class="q"><h3>Technical priorities</h3>' + (q.priorities.length ? '<table><tr><th></th><th>ID</th><th>Task</th>' + (q.team ? '' : '<th>Team</th>') + '<th>Owner</th><th class=n>' + h(S.unit) + '</th></tr>' +
    (function(rows){ if (rows.length <= 12) return rows.map(row).join(''); var d = rows.filter(function(p){ return p.tag === 'DONE'; }); return rows.filter(function(p){ return p.tag !== 'DONE'; }).map(row).join('') + (d.length ? '<tr><td><span class="qtag DONE">DONE</span></td><td colspan=' + (q.team ? 4 : 5) + '><span class="muted">' + d.length + ' done: </span>' + d.map(function(p){ return h(p.id); }).join(', ') + '</td></tr>' : ''); })(q.priorities) + '</table>' + (q.todo_more ? '<p class="muted">+' + q.todo_more + ' more on the TODO list</p>' : '') : '<p class="muted">nothing in the sprint or on the TODO list</p>') +
    '<div class="legend">TODO on the backlog \u00b7 OPEN in the sprint \u00b7 DONE \u00b7 WAIT blocked outside the team \u00b7 HOLD interrupted \u00b7 PUNT too hard as written, back to TODO \u00b7 DROP should not be done \u00b7 REDO demo found it wrong \u00b7 PASS moved to the right team \u00b7 SYNC shared DONE across teams</div></div>';
  function row(p){ return '<tr><td><span class="qtag ' + p.tag + '">' + p.tag + '</span></td><td><b class="id">' + h(p.id) + '</b></td><td>' + h(p.title) + p.marks.map(function(k){ return '<span class="qmark">' + h(k) + '</span>'; }).join('') + (p.why ? ' <span class="muted">' + h(p.why) + '</span>' : '') + '</td>' + (q.team ? '' : '<td>' + h(p.team || '') + '</td>') + '<td>' + h(p.owner || '\u2014') + '</td><td class=n>' + h(p.pts) + '</td></tr>'; }
  s += '<div class="q"><h3>Watch items / PM help needed</h3>' + (q.watch.length ? '<table><tr><th></th><th>ID</th><th>Team</th><th>Owner</th><th>Item</th></tr>' +
    q.watch.map(function(w){ return '<tr><td>' + chip(w.kind === 'PM' ? 'critical' : 'warning', '(' + w.kind + ')') + '</td><td><b class="id">' + h(w.id) + '</b></td><td>' + h(w.team || '') + '</td><td>' + h(w.owner || '\u2014') + '</td><td>' + h(w.text) + '</td></tr>'; }).join('') + '</table>' : '<p class="muted">nothing to watch</p>') +
    '<div class="legend">(PM) the program manager needs to help remove a blocker \u00b7 (WI) the program manager needs to be aware</div></div>';
  s += '<div class="q"><h3>Schedule milestones</h3>' + q.horizons.map(function(hz){ var rows = q.milestones[hz] || []; return '<h4>' + hz + ' days out</h4>' + (rows.length ? '<table>' + rows.map(function(e){ return '<tr><td class=n>' + e.priority + '.</td><td>' + h(e.tome) + ' <span class="muted">&gt;</span> ' + h(e.epic) + '</td><td>' + chip(e.severity === 'good' ? 'good' : e.severity, AR[e.trend]) + '</td><td class=n>' + e.pct + '%</td><td class=n>ETA ' + h(e.eta) + '</td><td>' + (e.blocked ? chip('critical', e.blocked + ' blocked') : '') + '</td></tr>'; }).join('') + '</table>' : '<p class="muted">\u2014</p>') + (q.milestones_more && q.milestones_more[hz] ? '<p class="muted">+' + q.milestones_more[hz] + ' more epics in this window</p>' : ''); }).join('') +
    '<div class="legend">ETA = remaining \u00f7 the owning teams\u2019 velocity, against last week\u2019s ETA</div></div>';
  s += '<div class="q"><h3>Accomplishments <span class="muted">since ' + h(q.since) + '</span></h3>' + ((q.accomplishments.length || q.slipped.length) ? '<table>' +
    q.accomplishments.map(function(a){ return '<tr><td class="' + (a.ontime ? 'ok' : 'late') + '">' + (a.ontime ? '\u2713' : '\u2717') + '</td><td><b class="id">' + h(a.id) + '</b></td><td>' + h(a.title) + '</td><td>' + h(a.owner || '\u2014') + '</td><td class=n>' + h(a.pts) + '</td></tr>'; }).join('') +
    q.slipped.map(function(a){ return '<tr><td class="slip">!</td><td><b class="id">' + h(a.id) + '</b></td><td colspan=3>' + h(a.title) + ' <span class="muted">' + h(a.why) + '</span></td></tr>'; }).join('') + '</table>' : '<p class="muted">nothing finished this week</p>') +
    '<div class="legend">\u2713 on time \u00b7 \u2717 late (carried over, or rework after the demo) \u00b7 ! a priority that slipped this week</div></div>';
  return s + '</div>';
}
function viewPeople(){
  if (!S.roster.length) return '<p class="muted">No roster.txt in the project. One line per person: <code>Name | email | Team | Role | Org</code> (name as Teams shows it), or <code>daily.pl roster add ...</code></p>';
  var today = S.generated, byDay = {};
  S.days.forEach(function(d){ byDay[d.date] = d; });
  var dates = S.days.map(function(d){ return d.date; }).sort();
  function rec(date, who){ var d = byDay[date]; if (!d) return null; var r = null; Object.keys(d.teams).forEach(function(t){ (d.teams[t].answers || []).forEach(function(a){ if (a.who === who) r = a; }); }); return r; }
  function clean(a){ return a && a.complete && !a.assumed && /\b[A-Z][A-Z0-9_]{0,9}-\d{1,6}\b/.test((a.y || '') + ' ' + (a.t || '')); }
  var teams = {};
  S.roster.forEach(function(p){ (teams[p.team || '?'] = teams[p.team || '?'] || []).push(p); });
  var s = '<h2>People <span class="muted">roster.txt: ' + S.roster.length + ' people, ' + Object.keys(teams).length + ' teams; streak = consecutive days with a complete status carrying a task id (read-backs stop at ' + (S.readback_clean_days || 5) + ')</span></h2>';
  Object.keys(teams).sort().forEach(function(t){
    s += '<table class="statuses"><caption>' + h(t) + ' \u2014 ' + teams[t].length + '</caption><tr><th>Who</th><th>Role</th><th>Org</th><th>E-mail</th><th>Today</th><th class=n>Streak</th></tr>';
    teams[t].sort(function(a, b){ return a.name < b.name ? -1 : 1; }).forEach(function(p){
      var a = rec(today, p.name), st = 0;
      for (var i = dates.length - 1; i >= 0; i--) { var r = rec(dates[i], p.name); if (clean(r)) st++; else break; }
      var td = !byDay[today] ? '<span class="muted">\u2014</span>' : a ? (a.assumed ? chip('warning', 'assumed') : a.blocked ? chip('serious', 'blocked') : clean(a) ? chip('good', 'ok') : chip('warning', 'no id')) : chip('critical', 'silent');
      s += '<tr><td>' + h(p.name) + '</td><td>' + h(p.role) + '</td><td>' + h(p.org) + '</td><td class="muted">' + h(p.email) + '</td><td>' + td + '</td><td class=n>' + st + (st >= (S.readback_clean_days || 5) ? ' <span class="muted">mature</span>' : '') + '</td></tr>'; });
    s += '</table>'; });
  return s;
}
function viewPlates(){
  if (!S.plates) return '<p class="muted">No plates rendered. Run <code>idef2html MODEL.md &gt; reports/plates.html</code> (the training replay does this) and regenerate.</p>';
  var toc = (S.plates_index || []).map(function(p){
    return '<a href="#" class="d' + Math.min(5, p.depth) + (state.plate === p.node ? ' on' : '') + '" onclick="return plate(\'' + p.node + '\')" title="' + h(p.node + ' ' + p.title) + '"><span class="n">' + h(p.node) + '</span>' + h(p.title) + '<span class="pg">' + h(p.page) + '</span></a>'; }).join('');
  var top = '<a href="#" class="d0' + (state.plate ? '' : ' on') + '" onclick="return plate(null)"><span class="n">p.1</span>Node index &amp; interfaces</a>';
  return '<div class="plates-wrap"><nav class="plates-toc">' + top + toc + '</nav><iframe class="plates" id="plates" src="' + h(S.plates + (state.plate ? '#plate-' + state.plate : '')) + '"></iframe></div>';
}
function plate(node){                         // pick a plate: scroll the iframe to it (same-origin) or reload it at the anchor (file:// blocks cross-frame access)
  state.plate = node; var f = document.getElementById('plates'); var url = S.plates + (node ? '#plate-' + node : '#top');
  try { f.contentWindow.location.replace(url); } catch (e) { f.src = url; }
  var nav = document.querySelector('.plates-toc'); nav.querySelectorAll('a').forEach(function(a){ a.classList.remove('on'); });
  var i = 0; (S.plates_index || []).some(function(p, k){ if (p.node === node) { i = k + 1; return true; } }); nav.querySelectorAll('a')[i].classList.add('on');
  return false;
}
// ---- app
var state = {tab: (location.hash || '#daily').slice(1), period: null, q: '', team: '', openOnly: true, plate: null};
var VIEWS = {daily:viewDaily, weekly:viewWeekly, quad:viewQuad, sprint:viewSprint, month:function(){ return viewPeriod('month'); }, semester:function(){ return viewPeriod('semester'); }, annual:function(){ return viewPeriod('annual'); }, backlog:viewBacklog, roadmap:viewRoadmap, gantt:viewGantt, people:viewPeople, plates:viewPlates, tutorial:viewTutorial};
function render(){
  document.getElementById('tabs').innerHTML = TABS.map(function(t){ return '<button class="' + (state.tab === t[0] ? 'on' : '') + '" onclick="go(\'' + t[0] + '\')">' + t[1] + '</button>'; }).join('');
  var view = document.getElementById('view'); try { view.innerHTML = (VIEWS[state.tab] || viewDaily)(); } catch (e) { view.innerHTML = '<p class="muted">view error: ' + h(e.message) + '</p>'; }
  var chipEl = document.getElementById('brief-chip'); chipEl.className = 'chip ' + ({green:'good', amber:'warning', red:'critical'}[S.brief.level] || 'good'); chipEl.textContent = S.brief.level.toUpperCase() + (S.current != null ? ' \u00b7 sprint ' + S.current : '');
}
function go(tab){ state.tab = tab; state.period = null; location.hash = tab; render(); }
window.addEventListener('hashchange', function(){ state.tab = (location.hash || '#daily').slice(1); render(); });
document.getElementById('auto').checked = localStorage.getItem('cockpit-auto') === '1';
document.getElementById('auto').onchange = function(){ localStorage.setItem('cockpit-auto', this.checked ? '1' : '0'); };
setInterval(function(){ if (localStorage.getItem('cockpit-auto') === '1') location.reload(); }, 20000);   // a shared screen during the open hour: grows within a paste's latency
if (location.protocol.indexOf('http') === 0){ var rb = document.createElement('button'); rb.textContent = 'Rebuild reports'; rb.style.cssText = 'font:inherit;margin-left:10px;padding:3px 10px;border:1px solid #27235d;background:#27235d;color:#fff;border-radius:4px;cursor:pointer';
  rb.onclick = function(){ rb.textContent = 'Rebuilding\u2026'; location.href = '/rebuild' + location.hash; }; document.querySelector('.tools').appendChild(rb); }
render();
JS

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Cockpit::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Cockpit::$_"} == \&{"Prelude::$_"})
          && !(defined &{"Scrum::$_"}   && \&{"Cockpit::$_"} == \&{"Scrum::$_"})
          && !(defined &{"Ledger::$_"}  && \&{"Cockpit::$_"} == \&{"Ledger::$_"})
    } keys %Cockpit::;
}

1;
