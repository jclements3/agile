#!/usr/bin/perl
# agile-workbook.pl -- the kit as one Excel workbook, for a laptop where only Office (no macros), Teams and Outlook run.
#
#   perl tools/office/agile-workbook.pl [-o agile.xlsx]                         an empty workbook
#   perl tools/office/agile-workbook.pl --from data/demo [--since YYYY-MM-DD] [--today YYYY-MM-DD] -o demo.xlsx
#
# The model is the kit's, flattened for a spreadsheet: Items (the backlog, one row per task) and Log (append-only events,
# one row per stand-up verb: commit/carry/done/block/unblock/hold/resume/punt/redo/pass/drop/est/note/sync). Every state,
# metric, flag, burndown, velocity, the quad and the stand-up lint are formulas over those two tables -- nothing is
# typed twice and nothing needs a macro. Formulas stick to Excel 2010+ functions (no dynamic arrays, no LET/LAMBDA),
# so the file works on any Office a government laptop is likely to have.
# --from reads a kit project (its scrum.txt and roster.txt) and writes its journal as Items + Log: the same history,
# so a team can move over without retyping. Core Perl only (IO::Compress::Zip), like the rest of the kit.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long;
use IO::Compress::Zip qw($ZipError);
use Time::Local qw(timegm);
use Encode ();

my %o = (out => 'agile.xlsx');
GetOptions(\%o, 'from=s', 'since=s', 'today=s', 'out|o=s', 'rows=i', 'help|h') or die "usage: agile-workbook.pl [--from DIR] [--since DATE] [--today DATE] [-o FILE.xlsx]\n";
if ($o{help}) { print "usage: agile-workbook.pl [--from DIR|JOURNAL] [--since YYYY-MM-DD] [--today YYYY-MM-DD] [-o FILE.xlsx]\n"; exit 0 }

# ---------------------------------------------------------------- dates
sub serial { my ($y, $m, $d) = (shift // '') =~ /^(\d{4})-(\d\d)-(\d\d)/ or return undef; int((timegm(0, 0, 12, $d, $m - 1, $y) - timegm(0, 0, 12, 30, 11, 1899)) / 86400) }

# ---------------------------------------------------------------- 1. the data: from a kit project, or empty
my (@items, @log, @roster, @teams, %epic, $sprint1, $asof);
if ($o{from}) { import_project($o{from}) }
$o{rows} //= 1;

sub import_project {
    my $from = shift;
    require Scrum;
    my $journal = -d $from ? "$from/scrum.txt" : $from;
    my $dir = -d $from ? $from : ($from =~ m{^(.*)/[^/]+$} ? $1 : '.');
    -f $journal or die "agile-workbook: no journal at $journal\n";
    my $s = Scrum::load($journal);
    my (%it, @order, %txn_seen);
    my @post = Scrum::journal_postings($s);
    # group postings by transaction, in journal order
    my (@txns, %tix);
    for my $p (@post) { my $k = "$p->{txn}"; push @txns, $k unless exists $tix{$k}; push @{ $tix{$k} }, $p }
    my %cap;
    for my $k (@txns) {
        my @ps = @{ $tix{$k} };
        my %by;
        for my $p (@ps) {
            my $meta = { %{ Scrum::parse_meta($p->{txn}{comment}) }, %{ Scrum::parse_meta($p->{comment}) } };
            my $id = $meta->{id} or next;
            push @{ $by{$id} }, [ $p, $meta ];
        }
        for my $id (sort { $by{$a}[0][0]{txn}{line} <=> $by{$b}[0][0]{txn}{line} || $a cmp $b } keys %by) {
            my $date = $by{$id}[0][0]{date};
            my $payee = $by{$id}[0][0]{payee};
            my $x = $it{$id};
            if (!$x) {
                (my $title = $payee) =~ s/^\s*(?:intake|new|add)\s+\Q$id\E\s*//i;
                $x = $it{$id} = { ID => $id, Title => $title, Added => $date, bal => {}, total => 0, loc => '', into => undef, blocked => 0, held => 0 };
                push @order, $id;
            }
            my %meta = map { %{ $_->[1] } } @{ $by{$id} };
            $x->{$_->[0]} //= $meta{ $_->[1] } for [Tome => 'tome'], [Epic => 'epic'], [Owner => 'owner'], [Prio => 'prio'];
            $x->{Owner} = $meta{owner} if defined $meta{owner} && $meta{owner} ne '';
            my $new = !$x->{seen}++;
            for my $pm (@{ $by{$id} }) {
                my ($p, $m) = @$pm;
                my $pts = Scrum::_num($p->{amount});
                $x->{bal}{ $p->{account} } += $pts;
                next unless $pts > 0;
                my $acct = $p->{account};
                my $prev = $x->{loc};
                if ($acct =~ /^Sprint:(\d+):([^:]+):Committed$/) {
                    my ($n, $team) = ($1, $2);
                    $x->{Team} //= $team;
                    if    ($prev =~ /:Done$/)                       { push @log, [ $date, $id, 'redo', $n, $m->{redo} // '' ] }
                    elsif ($prev =~ /:Carryover$/)                  { push @log, [ $date, $id, 'commit', $n, '' ] if ($x->{into} // 0) != $n }
                    else                                            { push @log, [ $date, $id, 'commit', $n, '' ] }
                    $x->{into} = $n;
                } elsif ($acct =~ /^Sprint:(\d+):([^:]+):Done$/) {
                    push @log, [ $date, $id, 'done', '', defined $m->{sync} && $m->{sync} ne '' ? "sync $m->{sync}" : '' ];
                } elsif ($acct =~ /^Sprint:(\d+):([^:]+):Carryover$/) {
                    push @log, [ $date, $id, 'carry', $1 + 1, '' ];
                    $x->{into} = $1 + 1;
                } elsif ($acct =~ /^Sprint:(\d+):([^:]+):Removed$/) {
                    push @log, [ $date, $id, 'drop', '', '' ];
                } elsif ($acct =~ /^Backlog:([^:]+)$/ && $1 ne 'Master') {
                    my $team = $1;
                    if (!defined $x->{Team} || $x->{Team} eq 'Master') { $x->{Team} = $team }
                    elsif (defined $m->{punt} && $m->{punt} ne '')     { push @log, [ $date, $id, 'punt', '', $m->{punt} ] }
                    elsif ($team ne ($x->{cur} // $x->{Team}))          { push @log, [ $date, $id, 'pass', $team, $m->{pass} // '' ] }
                    elsif ($prev =~ /^Sprint:/)                          { push @log, [ $date, $id, 'punt', '', 'back to the backlog' ] }
                    $x->{cur} = $team;
                } elsif ($acct eq 'Backlog:Master') { $x->{Team} //= 'Master' }
                $x->{loc} = $acct unless $acct =~ /^Equity:/;
            }
            if (exists $meta{blocked}) {
                my $on = defined $meta{blocked} && $meta{blocked} ne '';
                if ($on && !$x->{blocked}) { push @log, [ $date, $id, 'block', '', $meta{blocked} ] }
                elsif (!$on && $x->{blocked}) { push @log, [ $date, $id, 'unblock', '', '' ] }
                $x->{blocked} = $on;
            }
            if (exists $meta{hold}) {
                my $on = defined $meta{hold} && $meta{hold} ne '';
                if ($on && !$x->{held}) { push @log, [ $date, $id, 'hold', '', $meta{hold} ] }
                elsif (!$on && $x->{held}) { push @log, [ $date, $id, 'resume', '', '' ] }
                $x->{held} = $on;
            }
            my $total = 0;   # the positive non-Equity balances are the task's points
            for my $a (keys %{ $x->{bal} }) { $total += $x->{bal}{$a} if $a !~ /^Equity:/ && $x->{bal}{$a} > 0 }
            if ($new) { $x->{Points} = $total }
            elsif ($total != $x->{total} && $total > 0) { push @log, [ $date, $id, 'est', $total, '' ] }
            $x->{total} = $total;
        }
    }
    my $first;
    for my $l (@log) { $first = $l->[0] if $l->[2] eq 'commit' && $l->[3] == 1 && (!$first || $l->[0] lt $first) }
    $first //= (sort map { $_->[0] } @log)[0] // $s->{today};
    $sprint1 = $first;
    $asof = $o{today} // (sort map { $_->[0] } @log)[-1] // $s->{today};
    my %keep = map { $_ => 1 } @order;
    if ($o{since}) { %keep = (); $keep{ $_->[1] } = 1 for grep { $_->[0] ge $o{since} } @log; $keep{$_} = 1 for grep { $it{$_}{Added} ge $o{since} } @order }
    @items = map { $it{$_} } grep { $keep{$_} } @order;
    @log = grep { $keep{ $_->[1] } } @log;
    $_->{Team} = '' for grep { ($_->{Team} // '') eq 'Master' } @items;
    for my $x (@items) { next unless $x->{Epic}; $epic{ $x->{Epic} } //= { Tome => $x->{Tome} // '' } }
    # the people: roster.txt (Name | email | Team | Role | Org), else the owners with their most frequent team
    if (open my $fh, '<:encoding(UTF-8)', "$dir/roster.txt") {
        while (<$fh>) { s/\r?\n$//; next if /^\s*(#|$)/; my @f = map { s/^\s+|\s+$//gr } split /\|/; push @roster, [ @f[0 .. 4] ] if $f[0] }
    }
    if (!@roster) {
        my %t; $t{ $_->{Owner} }{ $_->{Team} // '' }++ for grep { $_->{Owner} } @items;
        for my $n (sort keys %t) { my ($team) = sort { $t{$n}{$b} <=> $t{$n}{$a} || $a cmp $b } keys %{ $t{$n} }; push @roster, [ $n, '', $team, '', '' ] }
    }
    my %tm; $tm{ $_->{Team} }++ for grep { $_->{Team} } @items;
    for my $t (sort keys %tm) {
        my ($n) = sort { $b <=> $a } grep { $s->{capacity}{$_}{$t} } keys %{ $s->{capacity} };
        push @teams, [ $t, $n ? $s->{capacity}{$n}{$t} : '' ];
    }
}

# ---------------------------------------------------------------- 2. a small xlsx writer: shared strings, styles, tables, charts
my (@sst, %sst);
sub sidx { my $s = shift; $sst{$s} //= do { push @sst, $s; $#sst } }
sub xe { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g; $s }
sub colname { my $i = shift; my $s = ''; while ($i > 0) { my $m = ($i - 1) % 26; $s = chr(65 + $m) . $s; $i = int(($i - 1) / 26) } $s }   # 1 -> A
sub colnum { my $c = uc shift; my $n = 0; $n = $n * 26 + ord($_) - 64 for split //, $c; $n }

my (@fonts, %fonts, @fills, %fills, @xfs, %xfs, @numfmts, %numfmt, @dxfs);
@fonts = ('<font><sz val="10"/><name val="Calibri"/><family val="2"/></font>'); $fonts{ $fonts[0] } = 0;
@fills = ('<fill><patternFill patternType="none"/></fill>', '<fill><patternFill patternType="gray125"/></fill>');
my %NUMFMT_BUILTIN = ('General' => 0, '0' => 1, '0%' => 9);
sub style {                                   # style(b => 1, color => 'RRGGBB', fill => 'RRGGBB', fmt => 'yyyy-mm-dd', size => 14, wrap => 1, align => 'center', i => 1) -> xf index
    my %s = @_;
    my $font = '<font>' . ($s{b} ? '<b/>' : '') . ($s{i} ? '<i/>' : '') . '<sz val="' . ($s{size} // 10) . '"/>' . ($s{color} ? qq(<color rgb="FF$s{color}"/>) : '') . '<name val="Calibri"/><family val="2"/></font>';
    my $fi = $fonts{$font} //= do { push @fonts, $font; $#fonts };
    my $fill = $s{fill} ? qq(<fill><patternFill patternType="solid"><fgColor rgb="FF$s{fill}"/><bgColor indexed="64"/></patternFill></fill>) : '';
    my $li = $fill ? ($fills{$fill} //= do { push @fills, $fill; $#fills }) : 0;
    my $fmt = $s{fmt} // 'General';
    my $ni = $NUMFMT_BUILTIN{$fmt} // ($numfmt{$fmt} //= do { push @numfmts, $fmt; 163 + @numfmts });
    my $al = ($s{wrap} || $s{align} || $s{valign}) ? '<alignment' . ($s{align} ? qq( horizontal="$s{align}") : '') . ($s{valign} ? qq( vertical="$s{valign}") : '') . ($s{wrap} ? ' wrapText="1"' : '') . '/>' : '';
    my $xf = qq(<xf numFmtId="$ni" fontId="$fi" fillId="$li" borderId="0" xfId="0") . ($ni ? ' applyNumberFormat="1"' : '') . ($fi ? ' applyFont="1"' : '') . ($li ? ' applyFill="1"' : '')
           . ($al ? qq( applyAlignment="1">$al</xf>) : '/>');
    $xfs{$xf} //= do { push @xfs, $xf; $#xfs };
}
style();                                       # xf 0: the default
sub dxf { my %s = @_; push @dxfs, '<dxf>' . ($s{color} || $s{b} ? '<font>' . ($s{b} ? '<b/>' : '') . ($s{color} ? qq(<color rgb="FF$s{color}"/>) : '') . '</font>' : '')
                                   . ($s{fill} ? qq(<fill><patternFill><bgColor rgb="FF$s{fill}"/></patternFill></fill>) : '') . '</dxf>'; $#dxfs }

my ($NAVY, $RED, $GREY, $LGREY, $OLIVE, $GOLD, $LBLUE, $BEIGE, $GREEN, $AMBER) = qw(27235D D6292E 808082 E4E4E7 6B7436 E6AF22 AAC1D7 E8DDD6 0CA30C C98500);
my %ST = (
    title => style(b => 1, size => 16, color => $NAVY),
    h2    => style(b => 1, size => 12, color => $NAVY),
    hdr   => style(b => 1, color => 'FFFFFF', fill => $NAVY),
    hdrcalc => style(b => 1, color => "FFFFFF", fill => $GREY),
    label => style(b => 1),
    note  => style(i => 1, color => $GREY),
    wrapnote => style(i => 1, color => $GREY, wrap => 1, valign => 'top'),
    input => style(fill => 'FFF7D6'),
    inputd => style(fill => 'FFF7D6', fmt => 'yyyy-mm-dd'),
    inputp => style(fill => 'FFF7D6', fmt => '0%'),
    date  => style(fmt => 'yyyy-mm-dd'),
    day   => style(fmt => 'ddd d mmm'),
    pct   => style(fmt => '0%'),
    num1  => style(fmt => '0.0'),
    big   => style(b => 1, size => 14, color => $NAVY),
    bigpct => style(b => 1, size => 14, color => $NAVY, fmt => '0%'),
    calc  => style(color => '333333'),
    qhead => style(b => 1, color => 'FFFFFF', fill => $NAVY, size => 11),
    qhead2 => style(b => 1, color => 'FFFFFF', fill => $OLIVE, size => 11),
    wrap  => style(wrap => 1, valign => 'top'),
);
my %DX = (red => dxf(fill => 'F8D7D8', color => '9C0006'), amber => dxf(fill => 'FFEB9C', color => '7A5200'), green => dxf(fill => 'D9F2D9', color => '0B5D0B'),
          grey => dxf(color => "A0A0A0"), hide => dxf(color => "FFFFFF"), bold => dxf(b => 1), wait => dxf(fill => 'F8D7D8', color => '9C0006', b => 1), done => dxf(color => '0B5D0B'),
          hold => dxf(fill => 'FFEB9C', color => '7A5200'), drop => dxf(color => 'A0A0A0'));

my (@sheets, %sheet);
sub sheet { my ($name, %a) = @_; my $sh = { name => $name, cells => {}, cols => [], merges => [], dv => [], cf => [], tables => [], charts => [], %a }; push @sheets, $sh; $sheet{$name} = $sh; $sh }
sub put {                                      # put(SHEET, 'B4', value | \'formula', style)
    my ($sh, $ref, $v, $st) = @_;
    my ($c, $r) = $ref =~ /^([A-Z]+)(\d+)$/ or die "bad ref $ref";
    $sh->{cells}{$r}{ colnum($c) } = [ $v, $st // 0 ];
}
sub width { my ($sh, %w) = @_; push @{ $sh->{cols} }, map { [ colnum($_), $w{$_} ] } sort { colnum($a) <=> colnum($b) } keys %w }

# a table: columns [name, width, formula-or-undef, style]; formulas use [@Col] for this row and are written to every row
sub table {
    my ($sh, $name, $top, $cols, $rows, %a) = @_;      # $top: 'A1'; $rows: arrayref of arrayrefs (input columns only, in order)
    my ($c0, $r0) = $top =~ /^([A-Z]+)(\d+)$/;
    my $c0n = colnum($c0);
    my $n = @$rows || $a{blank} || 1;
    my $last = $r0 + $n;
    my %w;
    for my $i (0 .. $#$cols) {
        my ($cn, $wd, $f, $st) = @{ $cols->[$i] };
        my $col = colname($c0n + $i);
        $w{$col} = $wd;
        put($sh, "$col$r0", $cn, defined $f ? $ST{hdrcalc} : $ST{hdr});
        for my $k (0 .. $n - 1) {
            my $r = $r0 + 1 + $k;
            if (defined $f) { put($sh, "$col$r", \ tref($name, $f), $st // $ST{calc}) }
            else { my $v = $rows->[$k] ? $rows->[$k][$i] : undef; put($sh, "$col$r", $v, $st) if defined $v && $v ne '' or $st }
        }
    }
    width($sh, %w);
    push @{ $sh->{tables} }, { name => $name, ref => "$top:" . colname($c0n + $#$cols) . $last, cols => $cols };
    $last;
}
sub tref { my ($t, $f) = @_; $f =~ s/\[@\[([^\]]+)\]\]/${t}[[#This Row],[$1]]/g; $f =~ s/\[@([^\]\[]+)\]/${t}[[#This Row],[$1]]/g; $f }

sub cf { my ($sh, $sqref, $formula, $dx) = @_; push @{ $sh->{cf} }, [ $sqref, $formula, $dx ] }
sub dv { my ($sh, $sqref, $list, %a) = @_; push @{ $sh->{dv} }, [ $sqref, $list, \%a ] }

# ---------------------------------------------------------------- 3. the sheets
my $RCAP = 1500;                               # stand-up paste rows
my $PCAP = 150;                                # people in the lint table

# ---- Start: settings, thresholds, verbs, how to use
my $st = sheet('Start', tab => $NAVY);
put($st, 'B1', 'Agile kit -- Excel edition', $ST{title});
put($st, 'B2', 'Yellow cells are yours to type in. Everything else is a formula over the Items and Log tables. No macros.', $ST{note});
put($st, 'B3', 'Settings', $ST{h2});
my @set = (['Sprint 1 starts', $sprint1 ? serial($sprint1) : serial(Scrum_today()), $ST{inputd}, 'Sprint1'],
           ['Sprint length (calendar days)', 14, $ST{input}, 'SprintDays'],
           ['As of (blank = today)', $asof ? serial($asof) : undef, $ST{inputd}, 'AsOfInput'],
           ['Points unit', 'SP', $ST{input}, 'Unit'],
           ['Project', $o{from} ? ($o{from} =~ s{/+$}{}r =~ s{.*/}{}r) : '', $ST{input}, 'Project'],
           ['Stand-up date (blank = as of)', undef, $ST{inputd}, 'StandupInput']);
my %names;
my $r = 4;
for my $x (@set) { put($st, "B$r", $x->[0], $ST{label}); put($st, "C$r", $x->[1], $x->[2]); $names{ $x->[3] } = "Start!\$C\$$r"; $r++ }
$r++;
put($st, "B$r", 'Now', $ST{h2}); $r++;
my @now = (['Current sprint', 'CurSprint', 0], ['Sprint starts', 'SprintStart', $ST{day}], ['Sprint ends', 'SprintEnd', $ST{day}],
           ['Working day of sprint', 'DayOfSprint&" of "&SprintWorkdays', 0], ['As of', 'AsOf', $ST{day}]);
for my $x (@now) { put($st, "B$r", $x->[0], $ST{label}); put($st, "C$r", \ $x->[1], $x->[2] || $ST{big}); $r++ }
$r++;
put($st, "B$r", 'Thresholds (WORKFLOW section 6)', $ST{h2}); $r++;
my @thr = (['Blocked: amber after (days)', 3, 'BlockAmber'], ['Blocked: red after (days)', 5, 'BlockRed'], ['Team load: high', 1.10, 'LoadHigh', 1],
           ['Team load: low', 0.70, 'LoadLow', 1], ['Progress by working day 8', 0.60, 'Day8Pct', 1], ['Predictability: at least', 0.80, 'PredictMin', 1],
           ['Carryover: at most', 0.20, 'CarryMax', 1], ['Punt rate: at most', 0.20, 'PuntMax', 1], ['On-time delivery: at least', 0.80, 'OnTimeMin', 1],
           ['Same person, share of team points (bus factor)', 0.40, 'BusMax', 1], ['Backlog age: flag after (days)', 90, 'AgeMax']);
for my $x (@thr) { put($st, "B$r", $x->[0], $ST{label}); put($st, "C$r", $x->[1], $x->[3] ? $ST{inputp} : $ST{input}); $names{ $x->[2] } = "Start!\$C\$$r"; $r++ }
$r++;
put($st, "B$r", 'Verbs (the Log table\'s third column)', $ST{h2}); $r++;
my $vtop = $r;
my @verbs = (['commit', 'sprint N (blank = the sprint of the date)', 'OPEN', 'into a sprint at planning'],
             ['carry',  'sprint N', 'OPEN', 'not done at sprint end: into the next sprint'],
             ['done',   '', 'DONE', 'finished, meets the Definition of Done'],
             ['block',  '', '', 'blocked from outside the team: why in Note (shows as WAIT)'],
             ['unblock','', '', 'the blocker is gone'],
             ['hold',   '', 'HOLD', 'interrupted by higher-priority work: why in Note'],
             ['resume', '', 'OPEN', 'back from hold'],
             ['punt',   '', 'TODO', 'too hard as written: back to the team backlog, why in Note'],
             ['redo',   'sprint N', 'OPEN', 'the demo found it wrong: back into a sprint'],
             ['pass',   'team', 'TODO', 'another team should do it: into their backlog'],
             ['drop',   '', 'DROP', 'should not be done'],
             ['est',    'points', '', 're-estimate: the new size'],
             ['sync',   'other ID', '', 'coordinated across teams (a note)'],
             ['note',   '', '', 'anything worth keeping']);
put($st, "B$r", 'Verb', $ST{hdr}); put($st, "C$r", 'Arg', $ST{hdr}); put($st, "D$r", 'State after', $ST{hdr}); put($st, "E$r", 'Meaning', $ST{hdr}); $r++;
for my $v (@verbs) { put($st, "B$r", $v->[0], $ST{label}); put($st, "C$r", $v->[1]); put($st, "D$r", $v->[2]); put($st, "E$r", $v->[3]); $r++ }
$names{Verbs} = "Start!\$B\$" . ($vtop + 1) . ":\$D\$" . ($r - 1);
$names{VerbList} = "Start!\$B\$" . ($vtop + 1) . ":\$B\$" . ($r - 1);
$r++;
put($st, "B$r", 'Every day', $ST{h2}); $r++;
for my $l ('1. Townhall: copy the Teams meeting chat (Ctrl+A, Ctrl+C in the chat) and paste it into Standup!A6.',
           '2. Lint: read the flags, copy the Reply column back into the chat, copy suggested rows (Date..Note) into the Log.',
           '3. Log: type what happened -- one row per verb (done, block, hold, punt ...). Never edit old rows; add new ones.',
           '4. Look: Quad (the weekly page), Health (thresholds), Teams, Burndown, Velocity. File > Print or paste into Outlook.',
           '5. Dashboard: open agile-dashboard.html in Edge and load this file for charts you can copy into mail or slides.',
           'Sprint planning: add Items, then a commit row per task. Sprint end: a carry row for each unfinished task.',
           'The Items and Log tables grow when you type on the row just below them. Keep column order; add columns to the right.') {
    put($st, "B$r", $l); $r++;
}
width($st, A => 2, B => 44, C => 40, D => 12, E => 60);

# defined names that are formulas
%names = (%names,
    CurSprint => 'MAX(1,INT((AsOf-Sprint1)/SprintDays)+1)',
    SprintStart => 'Sprint1+(CurSprint-1)*SprintDays',
    SprintEnd => 'SprintStart+SprintDays-1',
    DayOfSprint => 'NETWORKDAYS(SprintStart,AsOf)',
    SprintWorkdays => 'NETWORKDAYS(SprintStart,SprintEnd)',
    StandupDate => 'IF(' . $names{StandupInput} . '="",AsOf,' . $names{StandupInput} . ')',
    TeamList => 'Teams[Team]',
    PeopleList => 'Roster[Name]',
);
$names{AsOf} = 'IF(' . $names{AsOfInput} . '="",TODAY(),' . $names{AsOfInput} . ')';

# ---- Items: the backlog
my $it = sheet('Items', tab => $NAVY, freeze => 'B2');
my $ids = '(Log[ID]=[@ID])';
my @icols = (
    ['ID', 11], ['Title', 40], ['Tome', 18], ['Epic', 24], ['Team', 12], ['Owner', 16], ['Points', 7], ['Prio', 5], ['Added', 11, undef, $ST{date}],
    ['Pts', 6, 'IF([@ID]="","",IFERROR(VALUE(LOOKUP(2,1/(' . $ids . '*(Log[Verb]="est")),Log[Arg])),N([@Points])))'],
    ['Cur team', 12, 'IF([@ID]="","",IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Verb]="pass")),Log[Arg])&"",[@Team]&""))'],
    ['Sprint', 7, 'IF([@ID]="","",IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Into]<>"")),Log[Into]),""))'],
    ['Blocked', 8, 'IF([@ID]="","",IF(IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Blk]<>"")),Log[Blk]),0)=1,"Y",""))'],
    ['State', 8, 'IF([@ID]="","",SUBSTITUTE(IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[State]<>"")),Log[State]),"TODO"),"OPEN",IF([@Blocked]="Y","WAIT","OPEN")))'],
    ['Blocked since', 12, 'IF([@State]<>"WAIT","",1000000-MAX(INDEX((1000000-Log[Date])*' . $ids . '*(Log[Verb]="block")*(Log[Date]>=IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Verb]="unblock")),Log[Date]),0)),0)))', $ST{date}],
    ['Days blocked', 8, 'IF([@State]<>"WAIT","",AsOf-[@[Blocked since]])'],
    ['Blocker', 30, 'IF([@State]<>"WAIT","",IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Verb]="block")),Log[Note])&"",""))'],
    ['Carried', 7, 'IF([@ID]="","",COUNTIFS(Log[ID],[@ID],Log[Verb],"carry"))'],
    ['Punts', 6, 'IF([@ID]="","",COUNTIFS(Log[ID],[@ID],Log[Verb],"punt"))'],
    ['Done on', 11, 'IF([@State]<>"DONE","",IFERROR(LOOKUP(2,1/(' . $ids . '*(Log[Verb]="done")),Log[Date]),""))', $ST{date}],
    ['In sprint', 8, 'IF([@ID]="","",IF(AND([@Sprint]=CurSprint,OR([@State]="OPEN",[@State]="WAIT",[@State]="HOLD",[@State]="DONE")),1,0))'],
    ['Age', 6, 'IF(OR([@ID]="",[@Added]=""),"",AsOf-[@Added])'],
    ['KeyTP', 6, 'IF([@[In sprint]]=1,(IF([@Prio]="",9,N([@Prio]))*10+(IF([@State]="DONE",1,0)))*100000+ROW(),"")'],
    ['KeyWatch', 6, 'IF(AND([@[In sprint]]=1,OR([@State]="WAIT",[@State]="HOLD")),(1000-N([@[Days blocked]]))*100000+ROW(),IF(AND([@[In sprint]]=1,[@Owner]="",[@State]<>"DONE"),2000*100000+ROW(),""))'],
    ['KeyAcc', 6, 'IF(AND([@State]="DONE",N([@[Done on]])>AsOf-7),(200000-N([@[Done on]]))*100000+ROW(),"")'],
);
my @irows = map { my $x = $_; [ $x->{ID}, $x->{Title}, $x->{Tome}, $x->{Epic}, $x->{Team}, $x->{Owner}, $x->{Points}, $x->{Prio}, serial($x->{Added}) ] } @items;
my $ilast = table($it, 'Items', 'A1', \@icols, \@irows, blank => 1);
$it->{hidecols} = [ map { colnum($_) } qw(W X Y) ];
cf($it, "N2:N$ilast", 'N2="WAIT"', $DX{wait}); cf($it, "N2:N$ilast", 'N2="DONE"', $DX{done}); cf($it, "N2:N$ilast", 'N2="HOLD"', $DX{hold});
cf($it, "N2:N$ilast", 'OR(N2="DROP",N2="TODO")', $DX{grey});
cf($it, "P2:P$ilast", 'AND(P2<>"",P2>BlockRed)', $DX{red}); cf($it, "P2:P$ilast", 'AND(P2<>"",P2>BlockAmber)', $DX{amber});
cf($it, "F2:F$ilast", 'AND($U2=1,$F2="",$N2<>"DONE")', $DX{amber});
dv($it, "E2:E5000", 'TeamList'); dv($it, "F2:F5000", 'PeopleList');

# ---- Log: the journal
my $lg = sheet('Log', tab => $NAVY, freeze => 'A2');
my @lcols = (
    ['Date', 11, undef, $ST{date}], ['ID', 11], ['Verb', 9], ['Arg', 8], ['Note', 44],
    ['Check', 14, 'IF([@ID]="","",IF(ISNA(MATCH([@ID],Items[ID],0)),"unknown ID",IF(ISNA(MATCH([@Verb],VerbList,0)),"unknown verb",IF([@Date]="","no date",""))))'],
    ['State', 7, 'IF([@ID]="","",IFERROR(VLOOKUP([@Verb],Verbs,3,FALSE)&"",""))'],
    ['Sprint', 7, 'IF([@Date]="","",INT(([@Date]-Sprint1)/SprintDays)+1)'],
    ['Into', 6, 'IF(OR([@Verb]="commit",[@Verb]="carry",[@Verb]="redo"),IF([@Arg]="",[@Sprint],N([@Arg])),"")'],
    ['Blk', 5, 'IF([@Verb]="block",1,IF(OR([@Verb]="unblock",[@Verb]="done",[@Verb]="drop",[@Verb]="punt",[@Verb]="pass"),0,""))'],
    ['Pts', 6, 'IF([@ID]="",0,IFERROR(INDEX(Items[Pts],MATCH([@ID],Items[ID],0))*1,0))'],
    ['Team', 12, 'IF([@ID]="","",IFERROR(INDEX(Items[Cur team],MATCH([@ID],Items[ID],0))&"",""))'],
    ['Burn', 6, 'IF(OR([@Verb]="done",[@Verb]="punt",[@Verb]="drop",[@Verb]="pass"),[@Pts],0)'],
);
my @lrows = map { [ serial($_->[0]), $_->[1], $_->[2], $_->[3] eq '' ? undef : $_->[3], $_->[4] ] } @log;
my $llast = table($lg, 'Log', 'A1', \@lcols, \@lrows, blank => 1);
cf($lg, "F2:F$llast", 'F2<>""', $DX{red});
dv($lg, "C2:C20000", 'VerbList'); dv($lg, "B2:B20000", 'IDList', soft => 1);
$names{IDList} = 'Items[ID]';

# ---- Teams
my $tm = sheet('Teams', tab => $OLIVE, freeze => 'B2');
my $tf = '[@Team]';
my @tcols = (
    ['Team', 14], ['Capacity', 9],
    ['Committed', 10, 'IF([@Team]="","",SUMIFS(Items[Pts],Items[Cur team],[@Team],Items[In sprint],1))'],
    ['Done', 8, 'IF([@Team]="","",SUMIFS(Items[Pts],Items[Cur team],[@Team],Items[In sprint],1,Items[State],"DONE"))'],
    ['Remaining', 10, 'IF([@Team]="","",[@Committed]-[@Done])'],
    ['Pct done', 8, 'IF(N([@Committed])=0,"",[@Done]/[@Committed])', $ST{pct}],
    ['Load', 8, 'IF(N([@Capacity])=0,"",[@Committed]/[@Capacity])', $ST{pct}],
    ['Blocked', 8, 'IF([@Team]="","",COUNTIFS(Items[Cur team],[@Team],Items[In sprint],1,Items[State],"WAIT"))'],
    ['Unassigned', 10, 'IF([@Team]="","",COUNTIFS(Items[Cur team],[@Team],Items[In sprint],1,Items[Owner],"",Items[State],"<>DONE"))'],
    ['Velocity', 10, 'IF([@Team]="","",SUMIFS(Log[Pts],Log[Verb],"done",Log[Team],[@Team],Log[Sprint],">="&(CurSprint-3),Log[Sprint],"<"&CurSprint)/3)', $ST{num1}],
    ['Backlog', 9, 'IF([@Team]="","",SUMIFS(Items[Pts],Items[Cur team],[@Team],Items[State],"TODO"))'],
    ['Sprints of backlog', 9, 'IF(N([@[Velocity]])=0,"",[@Backlog]/[@[Velocity]])', $ST{num1}],
    ['Flags', 40, 'IF([@Team]="","",TRIM(IF(AND([@Load]<>"",N([@Load])>LoadHigh),"over capacity; ","")&IF(AND([@Load]<>"",N([@Load])<LoadLow),"under capacity; ","")&IF([@Blocked]>0,[@Blocked]&" blocked; ","")&IF([@Unassigned]>0,[@Unassigned]&" unassigned; ","")&IF(AND(DayOfSprint>=8,[@[Pct done]]<>"",N([@[Pct done]])<Day8Pct),"behind at day "&DayOfSprint&"; ","")))'],
);
my $tlast = table($tm, 'Teams', 'A1', \@tcols, [ map { [ @$_ ] } @teams ], blank => 1);
cf($tm, "G2:G$tlast", 'AND(G2<>"",OR(G2>LoadHigh,G2<LoadLow))', $DX{amber});
cf($tm, "H2:H$tlast", 'N(H2)>0', $DX{red});
cf($tm, "M2:M$tlast", 'M2<>""', $DX{amber});
put($tm, 'O1', 'Type the teams and their capacity (points per sprint). Capacity drives Load.', $ST{note});

# ---- Roster
my $ro = sheet('Roster', tab => $OLIVE, freeze => 'B2');
my @rcols = (
    ['Name', 20], ['Email', 26], ['Team', 12], ['Role', 16], ['Org', 12],
    ['In sprint', 9, 'IF([@Name]="","",SUMIFS(Items[Pts],Items[Owner],[@Name],Items[In sprint],1))'],
    ['Open', 6, 'IF([@Name]="","",COUNTIFS(Items[Owner],[@Name],Items[In sprint],1,Items[State],"<>DONE"))'],
    ['Done', 6, 'IF([@Name]="","",SUMIFS(Items[Pts],Items[Owner],[@Name],Items[In sprint],1,Items[State],"DONE"))'],
    ['Blocked', 8, 'IF([@Name]="","",COUNTIFS(Items[Owner],[@Name],Items[In sprint],1,Items[State],"WAIT"))'],
    ['Team share', 10, 'IF([@Name]="","",IFERROR([@[In sprint]]/SUMIFS(Items[Pts],Items[Cur team],[@Team],Items[In sprint],1),""))', $ST{pct}],
);
my $rlast = table($ro, 'Roster', 'A1', \@rcols, [ map { [ @$_ ] } @roster ], blank => 1);
cf($ro, "J2:J$rlast", 'AND(J2<>"",J2>BusMax)', $DX{amber});
cf($ro, "I2:I$rlast", 'N(I2)>0', $DX{red});
dv($ro, "C2:C2000", 'TeamList');

# ---- Epics
my $ep = sheet('Epics', tab => $OLIVE, freeze => 'B2');
my @ecols = (
    ['Epic', 30], ['Tome', 22], ['Target', 11, undef, $ST{date}],
    ['Team', 12, 'IF([@Epic]="","",IFERROR(INDEX(Items[Cur team],MATCH([@Epic],Items[Epic],0))&"",""))'],
    ['Points', 8, 'IF([@Epic]="","",SUMIFS(Items[Pts],Items[Epic],[@Epic],Items[State],"<>DROP"))'],
    ['Done', 7, 'IF([@Epic]="","",SUMIFS(Items[Pts],Items[Epic],[@Epic],Items[State],"DONE"))'],
    ['Pct done', 8, 'IF(N([@Points])=0,"",[@Done]/[@Points])', $ST{pct}],
    ['Open', 6, 'IF([@Epic]="","",COUNTIFS(Items[Epic],[@Epic],Items[State],"<>DONE",Items[State],"<>DROP"))'],
    ['Blocked', 8, 'IF([@Epic]="","",COUNTIFS(Items[Epic],[@Epic],Items[State],"WAIT"))'],
    ['ETA', 11, 'IF(OR([@Epic]="",N([@Points])=0),"",IF([@Done]>=[@Points],"",AsOf+ROUNDUP(([@Points]-[@Done])/MAX(1,IFERROR(INDEX(Teams[Velocity],MATCH([@Team],Teams[Team],0)),1)),0)*SprintDays))', $ST{date}],
    ['Due', 11, 'IF([@Epic]="","",IF([@Target]<>"",[@Target],[@ETA]))', $ST{date}],
    ['Status', 9, 'IF([@Epic]="","",IF(AND(N([@Points])>0,[@Done]>=[@Points]),"DONE",IF([@Target]="",IF([@ETA]="","","forecast"),IF([@Target]<AsOf,"LATE",IF([@ETA]>[@Target],"AT RISK","on track")))))'],
    ['KeyMS', 6, 'IF(OR([@Due]="",[@Status]="DONE"),"",IF([@Due]<=AsOf+90,N([@Due])*100000+ROW(),""))'],
);
my @erows = map { [ $_, $epic{$_}{Tome}, undef ] } sort keys %epic;
my $elast = table($ep, 'Epics', 'A1', \@ecols, \@erows, blank => 1);
$ep->{hidecols} = [ colnum('M') ];
cf($ep, "L2:L$elast", 'OR(L2="LATE",L2="AT RISK")', $DX{red}); cf($ep, "L2:L$elast", 'L2="DONE"', $DX{done});
put($ep, 'O1', 'Target is yours (a date the epic is promised by). ETA = remaining points / the team\'s 3-sprint velocity.', $ST{note});

# ---- Standup: paste the Teams chat
my $su = sheet('Standup', tab => $GOLD, freeze => 'A6');
put($su, 'A1', 'Stand-up: paste the Teams chat into A6 (Ctrl+V). One line per row; Y: / T: / B: lines under each name.', $ST{h2});
put($su, 'A2', 'Date', $ST{label}); put($su, 'B2', \ 'StandupDate', $ST{day});
put($su, 'A3', 'Names come from the Roster. "[8:31 AM] Ann Lee", "Ann Lee (08:31)" and "Ann Lee" on its own line all start a person.', $ST{note});
put($su, 'A5', 'Chat (paste here)', $ST{hdr}); put($su, 'B5', 'Name', $ST{hdr}); put($su, 'C5', 'Speaker', $ST{hdr}); put($su, 'D5', 'Tag', $ST{hdr}); put($su, 'E5', 'Text', $ST{hdr});
for my $r (6 .. $RCAP + 5) {
    my $t = "TRIM(A$r)";
    my $nm = "IF(LEFT($t,1)=\"[\",TRIM(MID($t,FIND(\"]\",$t&\"]\")+1,200)),$t)";
    $nm = "IF(RIGHT($nm,1)=\")\",TRIM(LEFT($nm,FIND(\"(\",$nm&\"(\")-1)),$nm)";
    put($su, "B$r", \ "IF(A$r=\"\",\"\",IF(COUNTIF(Roster[Name],$nm)>0,$nm,\"\"))", $ST{calc});
    put($su, "C$r", \ ($r == 6 ? "B$r" : "IF(B$r<>\"\",B$r,C" . ($r - 1) . ')'), $ST{calc});
    my $u = "UPPER(TRIM(A$r))";
    put($su, "D$r", \ "IF(A$r=\"\",\"\",IF(OR(LEFT($u,2)=\"Y:\",LEFT($u,10)=\"YESTERDAY:\"),\"Y\",IF(OR(LEFT($u,2)=\"T:\",LEFT($u,6)=\"TODAY:\"),\"T\",IF(OR(LEFT($u,2)=\"B:\",LEFT($u,8)=\"BLOCKER:\",LEFT($u,9)=\"BLOCKERS:\",LEFT($u,8)=\"BLOCKED:\"),\"B\",\"\"))))", $ST{calc});
    put($su, "E$r", \ "IF(D$r=\"\",\"\",TRIM(MID(A$r,FIND(\":\",A$r)+1,500)))", $ST{calc});
}
width($su, A => 60, B => 18, C => 18, D => 5, E => 50);
$names{ChatPaste} = "Standup!\$A\$6:\$A\$" . ($RCAP + 5);
$names{ChatSpeaker} = "Standup!\$C\$6:\$C\$" . ($RCAP + 5);
$names{ChatTag} = "Standup!\$D\$6:\$D\$" . ($RCAP + 5);
$names{ChatText} = "Standup!\$E\$6:\$E\$" . ($RCAP + 5);
if ($o{from}) {                                # the demo: the last stand-up chat of the project, ready to lint
    my $dir = -d $o{from} ? $o{from} : '.';
    my ($chat) = reverse sort glob("$dir/standups/*-chat.txt");
    if ($chat && open my $fh, '<:encoding(UTF-8)', $chat) {
        my $r = 6; while (my $l = <$fh>) { $l =~ s/\r?\n$//; last if $r > $RCAP + 5; put($su, "A$r", $l) if length $l; $r++ }
        my ($d) = $chat =~ m{(\d{4}-\d\d-\d\d)-chat\.txt$};
        put($st, substr($names{StandupInput}, 6) =~ s/\$//gr, serial($d), $ST{inputd}) if $d;
    }
}

# ---- Lint: one row per roster person
my $li = sheet('Lint', tab => $GOLD, freeze => 'B5');
put($li, 'A1', 'Lint: who answered, what is missing, what to paste back', $ST{h2});
put($li, 'A2', 'Reply: copy the Reply column into the chat. Suggest: copy Date..Note into the Log when it is right (never applied for you).', $ST{note});
my @lh = ('Name', 'Team', 'Lines', 'Y', 'T', 'B', 'Ids in T', 'Yours in T', 'Blocker', 'Done id', 'Flags', 'Reply', 'Date', 'ID', 'Verb', 'Note');
put($li, colname($_ + 1) . '4', $lh[$_], $_ >= 12 ? $ST{qhead2} : $ST{hdr}) for 0 .. $#lh;
sub cleanf { my $x = shift; '" "&SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(' . $x . ',","," "),"."," "),";"," "),":"," "),"("," "),")"," "),"/"," ")&" "' }
sub firstid { my ($x, $extra) = @_; 'IFERROR(INDEX(Items[ID],MATCH(1,INDEX((Items[ID]<>"")' . ($extra // '') . '*ISNUMBER(SEARCH(" "&Items[ID]&" ",' . cleanf($x) . ')),0),0)),"")' }
for my $r (5 .. $PCAP + 4) {
    my $k = $r - 4;
    my $fix = "IF(AND(N(C$r)>0,D$r=\"\"),\"no Y; \",\"\")&IF(AND(N(C$r)>0,E$r=\"\"),\"no T; \",\"\")&IF(AND(N(C$r)>0,F$r=\"\"),\"no B; \",\"\")&IF(AND(E$r<>\"\",G$r=0),\"no task id in T; \",\"\")&IF(AND(G$r>0,H$r=0),\"T names no task of yours in this sprint; \",\"\")";
    my $pick = sub { my $tag = shift; "IF(A$r=\"\",\"\",IFERROR(INDEX(ChatText,MATCH(1,INDEX((ChatSpeaker=A$r)*(ChatTag=\"$tag\"),0),0)),\"\"))" };
    my %f = (
        A => "IFERROR(INDEX(Roster[Name],$k)&\"\",\"\")",
        B => "IF(A$r=\"\",\"\",INDEX(Roster[Team],$k)&\"\")",
        C => "IF(OR(A$r=\"\",COUNTA(ChatPaste)=0),\"\",COUNTIF(ChatSpeaker,A$r))",   # no chat pasted: nobody is silent
        D => $pick->('Y'), E => $pick->('T'), F => $pick->('B'),
        G => "IF(E$r=\"\",0,SUMPRODUCT((Items[ID]<>\"\")*ISNUMBER(SEARCH(\" \"&Items[ID]&\" \"," . cleanf("E$r") . "))))",
        H => "IF(E$r=\"\",0,SUMPRODUCT((Items[ID]<>\"\")*(Items[Owner]=A$r)*(Items[In sprint]=1)*ISNUMBER(SEARCH(\" \"&Items[ID]&\" \"," . cleanf("E$r") . "))))",
        I => "IF(F$r=\"\",\"\",IF(OR(LOWER(TRIM(F$r))={\"none\",\"no\",\"nothing\",\"n/a\",\"na\",\"-\",\"nope\",\"no blockers\",\"none.\",\"nil\"}),\"\",\"Y\"))",
        J => "IF(D$r=\"\",\"\",IF(OR(ISNUMBER(SEARCH({\"done\",\"finished\",\"completed\",\"closed\",\"merged\"},D$r))),". firstid("D$r", "*(Items[State]<>\"DONE\")") . ",\"\"))",
        K => "IF(A$r=\"\",\"\",TRIM(IF(C$r=0,\"silent; \",\"\")&$fix&IF(I$r=\"Y\",\"blocker: \"&F$r&\"; \",\"\")))",
        L => "IF(A$r=\"\",\"\",IF(C$r=0,\"@\"&A$r&\" please post Y: / T: / B: for today.\",IF(TRIM($fix)=\"\",\"\",\"@\"&A$r&\" please fix: \"&TRIM($fix))))",
        N => "IF(J$r<>\"\",J$r,IF(I$r=\"Y\",IF(" . firstid("F$r") . "<>\"\"," . firstid("F$r") . "," . firstid("E$r", "*(Items[Owner]=A$r)") . "),\"\"))",
        O => "IF(N$r=\"\",\"\",IF(J$r<>\"\",\"done\",\"block\"))",
        P => "IF(O$r=\"block\",F$r,\"\")",
        M => "IF(N$r=\"\",\"\",StandupDate)",
    );
    for my $c (sort keys %f) { put($li, "$c$r", \ $f{$c}, $c eq 'M' ? $ST{date} : $c =~ /^[DEFKL]$/ ? $ST{wrap} : $ST{calc}) }
}
width($li, A => 18, B => 11, C => 6, D => 26, E => 26, F => 18, G => 7, H => 8, I => 7, J => 9, K => 34, L => 40, M => 11, N => 10, O => 7, P => 24);
my $lend = $PCAP + 4;
cf($li, "K5:K$lend", 'LEFT(K5,6)="silent"', $DX{red});
cf($li, "K5:K$lend", 'K5<>""', $DX{amber});
cf($li, "A5:A$lend", 'AND(A5<>"",C5=0)', $DX{grey});

# ---- Burndown
my $bd = sheet('Burndown', tab => $RED);
put($bd, 'A1', 'Burndown', $ST{title});
put($bd, 'A3', 'Sprint (blank = current)', $ST{label}); put($bd, 'B3', undef, $ST{input});
put($bd, 'A4', 'Team (blank = all)', $ST{label}); put($bd, 'B4', undef, $ST{input});
dv($bd, 'B4', 'TeamList');
put($bd, 'D3', 'Sprint', $ST{label}); put($bd, 'E3', \ 'IF(B3="",CurSprint,B3)', $ST{big});
put($bd, 'D4', 'Committed', $ST{label}); put($bd, 'E4', \ 'SUMIFS(Log[Pts],Log[Into],E3,Log[Team],IF(B4="","*",B4))', $ST{big});
put($bd, 'F3', 'Done', $ST{label}); put($bd, 'G3', \ 'SUMIFS(Log[Pts],Log[Verb],"done",Log[Sprint],E3,Log[Team],IF(B4="","*",B4))', $ST{big});
put($bd, 'F4', 'Progress', $ST{label}); put($bd, 'G4', \ 'IF(E4=0,"",G3/E4)', $ST{bigpct});
my @bh = ('Date', 'Day', 'Ideal', 'Remaining', 'Scope');
put($bd, colname($_ + 1) . '6', $bh[$_], $ST{hdr}) for 0 .. $#bh;
my $team = 'IF($B$4="","*",$B$4)';
for my $d (0 .. 27) {                          # up to a 28-day sprint; rows past SprintDays stay blank
    my $r = 7 + $d;
    put($bd, "A$r", \ "IF($d>=SprintDays,\"\",Sprint1+(\$E\$3-1)*SprintDays+$d)", $ST{day});
    put($bd, "B$r", \ "IF(A$r=\"\",\"\",$d+1)", $ST{calc});
    put($bd, "E$r", \ "IF(A$r=\"\",NA(),SUMIFS(Log[Pts],Log[Into],\$E\$3,Log[Date],\"<=\"&A$r,Log[Team],$team))", $ST{calc});
    put($bd, "C$r", \ "IF(A$r=\"\",NA(),\$E\$4*(1-$d/MAX(1,SprintDays-1)))", $ST{num1});
    put($bd, "D$r", \ "IF(OR(A$r=\"\",A$r>AsOf),NA(),E$r-SUMIFS(Log[Burn],Log[Sprint],\$E\$3,Log[Date],\"<=\"&A$r,Log[Team],$team))", $ST{calc});
}
cf($bd, "C7:E34", "ISNA(C7)", $DX{hide});
width($bd, A => 24, B => 8, C => 8, D => 11, E => 8, F => 10, G => 10);
push @{ $bd->{charts} }, { type => 'line', title => 'Burndown', from => [ 'G', 6 ], to => [ 'Q', 26 ], cat => 'Burndown!$A$7:$A$34',
                           series => [ [ 'Burndown!$C$6', 'Burndown!$C$7:$C$34', $GREY, 1 ], [ 'Burndown!$D$6', 'Burndown!$D$7:$D$34', $NAVY ], [ 'Burndown!$E$6', 'Burndown!$E$7:$E$34', $GOLD, 1 ] ], datefmt => 'd mmm' };

# ---- Velocity
my $ve = sheet('Velocity', tab => $RED);
put($ve, 'A1', 'Velocity and predictability', $ST{title});
put($ve, 'A3', 'Team (blank = all)', $ST{label}); put($ve, 'B3', undef, $ST{input}); dv($ve, 'B3', 'TeamList');
my @vh = ('Sprint', 'Starts', 'Committed', 'Done', 'Carried', 'Punted', 'Predictability', 'Carryover', 'Punt rate');
put($ve, colname($_ + 1) . '5', $vh[$_], $ST{hdr}) for 0 .. $#vh;
my $vt = 'IF($B$3="","*",$B$3)';
for my $k (0 .. 11) {
    my $r = 6 + $k;
    put($ve, "A$r", \ "IF(MAX(1,CurSprint-11)+$k>CurSprint,\"\",MAX(1,CurSprint-11)+$k)", $ST{label});
    put($ve, "B$r", \ "IF(A$r=\"\",\"\",Sprint1+(A$r-1)*SprintDays)", $ST{date});
    put($ve, "C$r", \ "IF(A$r=\"\",\"\",SUMIFS(Log[Pts],Log[Into],A$r,Log[Team],$vt))", $ST{calc});
    put($ve, "D$r", \ "IF(A$r=\"\",\"\",SUMIFS(Log[Pts],Log[Verb],\"done\",Log[Sprint],A$r,Log[Team],$vt))", $ST{calc});
    put($ve, "E$r", \ "IF(A$r=\"\",\"\",SUMIFS(Log[Pts],Log[Verb],\"carry\",Log[Into],A$r+1,Log[Team],$vt))", $ST{calc});
    put($ve, "F$r", \ "IF(A$r=\"\",\"\",SUMIFS(Log[Pts],Log[Verb],\"punt\",Log[Sprint],A$r,Log[Team],$vt))", $ST{calc});
    put($ve, "G$r", \ "IF(OR(A$r=\"\",N(C$r)=0),\"\",D$r/C$r)", $ST{pct});
    put($ve, "H$r", \ "IF(OR(A$r=\"\",N(C$r)=0),\"\",E$r/C$r)", $ST{pct});
    put($ve, "I$r", \ "IF(OR(A$r=\"\",N(C$r)=0),\"\",F$r/C$r)", $ST{pct});
}
put($ve, 'A19', 'Average done, last 3 finished sprints', $ST{label}); put($ve, 'D19', \ 'IF(CurSprint<2,"",SUMIFS(D6:D17,A6:A17,">="&(CurSprint-3),A6:A17,"<"&CurSprint)/MIN(3,CurSprint-1))', $ST{num1});
put($ve, 'A20', 'The current sprint is the last row and is still running.', $ST{note});
cf($ve, 'G6:G17', 'AND(G6<>"",G6<PredictMin)', $DX{amber});
cf($ve, 'H6:H17', 'AND(H6<>"",H6>CarryMax)', $DX{amber});
cf($ve, 'I6:I17', 'AND(I6<>"",I6>PuntMax)', $DX{amber});
width($ve, A => 10, B => 11, C => 10, D => 8, E => 8, F => 8, G => 13, H => 10, I => 10);
push @{ $ve->{charts} }, { type => 'bar', title => 'Committed vs done', from => [ 'K', 4 ], to => [ 'U', 22 ], cat => 'Velocity!$A$6:$A$17',
                           series => [ [ 'Velocity!$C$5', 'Velocity!$C$6:$C$17', $GOLD ], [ 'Velocity!$D$5', 'Velocity!$D$6:$D$17', $NAVY ] ] };

# ---- Quad: the weekly page
my $qd = sheet('Quad', tab => $GOLD, landscape => 1);
put($qd, 'A1', \ '"Weekly quad -- "&IF(Project="","",Project&" -- ")&"sprint "&CurSprint&", day "&DayOfSprint&" of "&SprintWorkdays&" -- "&TEXT(AsOf,"ddd d mmm yyyy")', $ST{title});
put($qd, 'A2', 'Sprint progress', $ST{label});
put($qd, 'C2', \ 'IFERROR(SUMIFS(Items[Pts],Items[In sprint],1,Items[State],"DONE")/SUMIFS(Items[Pts],Items[In sprint],1),"")', $ST{bigpct});
put($qd, 'F2', 'On-time delivery', $ST{label});
put($qd, 'H2', \ 'IFERROR(COUNTIFS(Items[In sprint],1,Items[State],"DONE",Items[Carried],0)/COUNTIFS(Items[In sprint],1,Items[State],"DONE"),"")', $ST{bigpct});
my $Q = 12;
my @quad = (
    [ 'A', 4, 'Technical priorities (this sprint)', 'Items[KeyTP]', 'Items', [ ['ID', 'Items[ID]'], ['State', 'Items[State]'], ['Title', 'Items[Title]'], ['Owner', 'Items[Owner]'] ] ],
    [ 'F', 4, 'Watch items (blocked, held, unassigned)', 'Items[KeyWatch]', 'Items', [ ['ID', 'Items[ID]'], ['State', 'Items[State]'], ['Why', 'Items[Blocker]'], ['Days', 'Items[Days blocked]'] ] ],
    [ 'A', 19, '30 / 60 / 90 milestones', 'Epics[KeyMS]', 'Epics', [ ['Epic', 'Epics[Epic]'], ['Status', 'Epics[Status]'], ['Due', 'Epics[Due]'], ['Pct done', 'Epics[Pct done]'] ] ],
    [ 'F', 19, 'Accomplishments (done in the last 7 days)', 'Items[KeyAcc]', 'Items', [ ['ID', 'Items[ID]'], ['Done on', 'Items[Done on]'], ['Title', 'Items[Title]'], ['Owner', 'Items[Owner]'] ] ],
);
for my $q (@quad) {
    my ($c, $r0, $title, $key, $tbl, $cols) = @$q;
    my $cn = colnum($c);
    put($qd, "$c$r0", $title, $ST{qhead}); put($qd, colname($cn + $_) . $r0, undef, $ST{qhead}) for 1 .. 3;
    put($qd, colname($cn + $_) . ($r0 + 1), $cols->[$_][0], $ST{label}) for 0 .. 3;
    for my $k (1 .. $Q) {
        my $r = $r0 + 1 + $k;
        my $row = "MOD(SMALL($key,$k),100000)-ROW($tbl\[#Headers])";
        for my $i (0 .. 3) {
            my $fmt = $cols->[$i][0] eq 'Due' || $cols->[$i][0] eq 'Done on' ? $ST{date} : $cols->[$i][0] eq 'Pct done' ? $ST{pct} : $ST{calc};
            my $txt = $fmt == $ST{calc} ? "&\"\"" : "";
            put($qd, colname($cn + $i) . $r, \ "IFERROR(INDEX($cols->[$i][1],$row)$txt,\"\")", $fmt);
        }
    }
    cf($qd, colname($cn + 1) . ($r0 + 2) . ':' . colname($cn + 1) . ($r0 + 1 + $Q), colname($cn + 1) . ($r0 + 2) . '="WAIT"', $DX{wait});
    cf($qd, colname($cn + 1) . ($r0 + 2) . ':' . colname($cn + 1) . ($r0 + 1 + $Q), colname($cn + 1) . ($r0 + 2) . '="DONE"', $DX{done});
    cf($qd, colname($cn + 1) . ($r0 + 2) . ':' . colname($cn + 1) . ($r0 + 1 + $Q), 'OR(' . colname($cn + 1) . ($r0 + 2) . '="LATE",' . colname($cn + 1) . ($r0 + 2) . '="AT RISK")', $DX{red});
}
put($qd, 'A34', 'Punted, last 4 sprints', $ST{label}); put($qd, 'C34', \ 'SUMIFS(Log[Pts],Log[Verb],"punt",Log[Sprint],">"&(CurSprint-4))', $ST{calc});
put($qd, 'F34', 'Blocked > ' . 3 . ' days', $ST{label}); put($qd, 'H34', \ 'COUNTIFS(Items[State],"WAIT",Items[Days blocked],">"&BlockAmber)', $ST{calc});
width($qd, A => 10, B => 11, C => 40, D => 16, E => 3, F => 10, G => 11, H => 34, I => 12);

# ---- Health: the thresholds
my $he = sheet('Health', tab => $RED);
put($he, 'A1', 'Health: every metric against its threshold', $ST{title});
put($he, 'A2', 'RED and AMBER need an action; the action is in the last column (WORKFLOW section 6).', $ST{note});
my @hh = ('Metric', 'Value', 'Level', 'Action');
put($he, colname($_ + 1) . '4', $hh[$_], $ST{hdr}) for 0 .. 3;
my @checks = (
    ['Blocked past the red line (tasks)', 'COUNTIFS(Items[State],"WAIT",Items[Days blocked],">"&BlockRed)', 'IF(B5>0,"RED","OK")', 'Escalate to the PM today; name an owner for the outside dependency.'],
    ['Blocked past the amber line (tasks)', 'COUNTIFS(Items[State],"WAIT",Items[Days blocked],">"&BlockAmber)', 'IF(B6>0,"AMBER","OK")', 'Raise at the townhall; swarm or re-plan.'],
    ['Teams over capacity', 'COUNTIFS(Teams[Load],">"&LoadHigh)', 'IF(B7>0,"AMBER","OK")', 'Move work out at the next refinement.'],
    ['Teams under capacity', 'COUNTIFS(Teams[Load],"<"&LoadLow,Teams[Load],">0")', 'IF(B8>0,"AMBER","OK")', 'Pull ready work from the backlog.'],
    ['Sprint progress (from working day 8)', 'IFERROR(SUMIFS(Items[Pts],Items[In sprint],1,Items[State],"DONE")/SUMIFS(Items[Pts],Items[In sprint],1),0)', 'IF(DayOfSprint<8,"OK",IF(B9<Day8Pct,"AMBER","OK"))', 'Cut scope with the teams now, not on day 14.'],
    ['Unassigned tasks in the sprint', 'COUNTIFS(Items[In sprint],1,Items[Owner],"",Items[State],"<>DONE")', 'IF(B10>0,"AMBER","OK")', 'Every committed task has one owner.'],
    ['Predictability, last finished sprint', "IFERROR(INDEX(Velocity!\$G\$6:\$G\$17,MATCH(CurSprint-1,Velocity!\$A\$6:\$A\$17,0)),\"\")", 'IF(B11="","OK",IF(B11<PredictMin,"AMBER","OK"))', 'Commit to the 3-sprint velocity, not the hope.'],
    ['Carryover, last finished sprint', "IFERROR(INDEX(Velocity!\$H\$6:\$H\$17,MATCH(CurSprint-1,Velocity!\$A\$6:\$A\$17,0)),\"\")", 'IF(B12="","OK",IF(B12>CarryMax,"AMBER","OK"))', 'Smaller tasks; split at refinement.'],
    ['Punt rate, last finished sprint', "IFERROR(INDEX(Velocity!\$I\$6:\$I\$17,MATCH(CurSprint-1,Velocity!\$A\$6:\$A\$17,0)),\"\")", 'IF(B13="","OK",IF(B13>PuntMax,"AMBER","OK"))', 'The Definition of Ready is not holding: rewrite before planning.'],
    ['Epics late or at risk', 'COUNTIF(Epics[Status],"LATE")+COUNTIF(Epics[Status],"AT RISK")', 'IF(B14>0,"RED","OK")', 'Re-plan the epic or move its target with the sponsor.'],
    ['People over the bus-factor share', 'COUNTIFS(Roster[Team share],">"&BusMax)', 'IF(B15>0,"AMBER","OK")', 'Pair or hand over; one person should not hold the team.'],
    ['Backlog tasks older than the age limit', 'COUNTIFS(Items[State],"TODO",Items[Age],">"&AgeMax)', 'IF(B16>0,"AMBER","OK")', 'Refine or drop old backlog.'],
    ['Silent at the last stand-up (people)', 'COUNTIF(Lint!K5:K' . $lend . ',"silent*")', 'IF(B17>0,"AMBER","OK")', 'A 1:1 message; three days running is a conversation.'],
    ['Log rows that do not check', 'COUNTIF(Log[Check],"?*")', 'IF(B18>0,"RED","OK")', 'Fix the ID or verb in the Log (Check column).'],
);
my $hr = 5;
for my $c (@checks) { put($he, "A$hr", $c->[0], $ST{label}); put($he, "B$hr", \ $c->[1], $c->[0] =~ /progress|Predictability|Carryover|Punt rate/ ? $ST{pct} : $ST{calc}); put($he, "C$hr", \ $c->[2], $ST{label}); put($he, "D$hr", $c->[3], $ST{note}); $hr++ }
cf($he, "C5:C" . ($hr - 1), 'C5="RED"', $DX{red}); cf($he, "C5:C" . ($hr - 1), 'C5="AMBER"', $DX{amber}); cf($he, "C5:C" . ($hr - 1), 'C5="OK"', $DX{green});
width($he, A => 40, B => 10, C => 9, D => 70);

# ---------------------------------------------------------------- 4. write the package
sub cellxml {
    my ($ref, $cell) = @_;
    my ($v, $s) = @$cell;
    my $sa = $s ? qq( s="$s") : '';
    return qq(<c r="$ref"$sa/>) unless defined $v;
    return qq(<c r="$ref"$sa><f>) . xe($$v) . '</f></c>' if ref $v;
    return qq(<c r="$ref"$sa><v>$v</v></c>) if $v =~ /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/ && $v !~ /^0\d/;
    qq(<c r="$ref"$sa t="s"><v>) . sidx($v) . '</v></c>';
}
my (%files, @ct, $ntab, $nchart) = ((), (), 0, 0);
my @order = ('[Content_Types].xml', '_rels/.rels', 'docProps/app.xml', 'docProps/core.xml', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/sharedStrings.xml');
my $X = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n";
my $NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
my $RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
my %TAB = do { my $k = 0; map { ($_ => $k++) } qw(Start Quad Health Standup Lint Log Items Teams Roster Epics Burndown Velocity) };
@sheets = sort { $TAB{ $a->{name} } <=> $TAB{ $b->{name} } } @sheets;   # the tabs in the order of a day's work
for my $i (0 .. $#sheets) {
    my $sh = $sheets[$i];
    my $n = $i + 1;
    my @rels;
    my $x = $X . "<worksheet $NS>";
    $x .= '<sheetPr>' . ($sh->{tab} ? qq(<tabColor rgb="FF$sh->{tab}"/>) : '') . ($sh->{landscape} ? '<pageSetUpPr fitToPage="1"/>' : '') . '</sheetPr>';
    $x .= '<sheetViews><sheetView workbookViewId="0"' . ($i == 0 ? ' tabSelected="1"' : '') . ' showGridLines="' . ($sh->{name} =~ /^(Start|Quad|Health|Burndown|Velocity)$/ ? 0 : 1) . '">';
    if (my $fz = $sh->{freeze}) {
        my ($c, $r) = $fz =~ /^([A-Z]+)(\d+)$/; my ($xs, $ys) = (colnum($c) - 1, $r - 1);
        $x .= '<pane' . ($xs ? qq( xSplit="$xs") : '') . ($ys ? qq( ySplit="$ys") : '') . qq( topLeftCell="$fz" activePane=") . ($xs && $ys ? 'bottomRight' : $ys ? 'bottomLeft' : 'topRight') . '" state="frozen"/>';
    }
    $x .= '</sheetView></sheetViews><sheetFormatPr defaultRowHeight="13.8"/>';
    my %hide = map { $_ => 1 } @{ $sh->{hidecols} // [] };
    my %cw = map { $_->[0] => $_->[1] } @{ $sh->{cols} };
    $cw{$_} //= 9 for keys %hide;
    $x .= '<cols>' . join('', map { qq(<col min="$_" max="$_" width="$cw{$_}" customWidth="1") . ($hide{$_} ? ' hidden="1"' : '') . '/>' } sort { $a <=> $b } keys %cw) . '</cols>' if %cw;
    $x .= '<sheetData>';
    for my $r (sort { $a <=> $b } keys %{ $sh->{cells} }) {
        my $row = $sh->{cells}{$r};
        $x .= qq(<row r="$r">) . join('', map { cellxml(colname($_) . $r, $row->{$_}) } sort { $a <=> $b } keys %$row) . '</row>';
    }
    $x .= '</sheetData>';
    my $prio = 1;
    for my $c (@{ $sh->{cf} }) { $x .= qq(<conditionalFormatting sqref="$c->[0]"><cfRule type="expression" dxfId="$c->[2]" priority=") . $prio++ . '"><formula>' . xe($c->[1]) . '</formula></cfRule></conditionalFormatting>' }
    if (@{ $sh->{dv} }) {
        $x .= '<dataValidations count="' . @{ $sh->{dv} } . '">';
        $x .= qq(<dataValidation type="list" allowBlank="1" showErrorMessage=") . ($_->[2]{soft} ? 0 : 1) . qq(" errorStyle="warning" sqref="$_->[0]"><formula1>$_->[1]</formula1></dataValidation>) for @{ $sh->{dv} };
        $x .= '</dataValidations>';
    }
    $x .= '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>';
    $x .= '<pageSetup orientation="' . ($sh->{landscape} ? 'landscape' : 'portrait') . '"' . ($sh->{landscape} ? ' fitToWidth="1" fitToHeight="1"' : '') . '/>';
    if (@{ $sh->{charts} }) {
        my $dn = $n;
        push @rels, [ "$RELS/drawing", "../drawings/drawing$dn.xml" ];
        $x .= '<drawing r:id="rId' . @rels . '"/>';
        my $d = $X . '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">';
        my @drels;
        for my $ch (@{ $sh->{charts} }) {
            $nchart++;
            push @drels, [ "$RELS/chart", "../charts/chart$nchart.xml" ];
            my ($fc, $fr) = @{ $ch->{from} }; my ($tc, $tr) = @{ $ch->{to} };
            $d .= '<xdr:twoCellAnchor><xdr:from><xdr:col>' . (colnum($fc) - 1) . '</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>' . ($fr - 1) . '</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
                . '<xdr:to><xdr:col>' . (colnum($tc) - 1) . '</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>' . ($tr - 1) . '</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
                . qq(<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="$nchart" name="Chart $nchart"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>)
                . '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
                . qq(<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="$RELS" r:id="rId) . @drels . '"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>';
            $files{"xl/charts/chart$nchart.xml"} = chartxml($ch);
            push @order, "xl/charts/chart$nchart.xml";
            push @ct, [ "/xl/charts/chart$nchart.xml", 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml' ];
        }
        $d .= '</xdr:wsDr>';
        $files{"xl/drawings/drawing$dn.xml"} = $d;
        $files{"xl/drawings/_rels/drawing$dn.xml.rels"} = relsxml(@drels);
        push @order, "xl/drawings/drawing$dn.xml", "xl/drawings/_rels/drawing$dn.xml.rels";
        push @ct, [ "/xl/drawings/drawing$dn.xml", 'application/vnd.openxmlformats-officedocument.drawing+xml' ];
    }
    if (@{ $sh->{tables} }) {
        my @ids;
        for my $t (@{ $sh->{tables} }) {
            $ntab++;
            push @rels, [ "$RELS/table", "../tables/table$ntab.xml" ];
            push @ids, scalar @rels;
            my $tx = $X . qq(<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="$ntab" name="$t->{name}" displayName="$t->{name}" ref="$t->{ref}" totalsRowShown="0">)
                   . qq(<autoFilter ref="$t->{ref}"/><tableColumns count=") . @{ $t->{cols} } . '">';
            my $ci = 0;
            for my $c (@{ $t->{cols} }) {
                $ci++;
                $tx .= qq(<tableColumn id="$ci" name=") . xe($c->[0]) . '"' . (defined $c->[2] ? '><calculatedColumnFormula>' . xe(tref($t->{name}, $c->[2])) . '</calculatedColumnFormula></tableColumn>' : '/>');
            }
            $tx .= '</tableColumns><tableStyleInfo name="TableStyleLight9" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/></table>';
            $files{"xl/tables/table$ntab.xml"} = $tx;
            push @order, "xl/tables/table$ntab.xml";
            push @ct, [ "/xl/tables/table$ntab.xml", 'application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml' ];
        }
        $x .= '<tableParts count="' . @ids . '">' . join('', map { qq(<tablePart r:id="rId$_"/>) } @ids) . '</tableParts>';
    }
    $x .= '</worksheet>';
    $files{"xl/worksheets/sheet$n.xml"} = $x;
    push @order, "xl/worksheets/sheet$n.xml";
    push @ct, [ "/xl/worksheets/sheet$n.xml", 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml' ];
    if (@rels) { $files{"xl/worksheets/_rels/sheet$n.xml.rels"} = relsxml(@rels); push @order, "xl/worksheets/_rels/sheet$n.xml.rels" }
}
sub relsxml { my $i = 0; $X . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' . join('', map { $i++; qq(<Relationship Id="rId$i" Type="$_->[0]" Target="$_->[1]"/>) } @_) . '</Relationships>' }

sub chartxml {
    my $ch = shift;
    my $sp = sub { my ($c, $line, $dash) = @_; $line ? '<c:spPr><a:ln w="' . ($dash ? 19050 : 31750) . '" cap="rnd"><a:solidFill><a:srgbClr val="' . $c . '"/></a:solidFill>' . ($dash ? '<a:prstDash val="dash"/>' : '') . '<a:round/></a:ln></c:spPr>'
                                         : qq(<c:spPr><a:solidFill><a:srgbClr val="$c"/></a:solidFill></c:spPr>) };
    my $txt = '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="900"><a:solidFill><a:srgbClr val="595959"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr>';
    my $i = 0;
    my $ser = join '', map {
        my ($name, $vals, $color, $dash) = @$_;
        my $s = qq(<c:ser><c:idx val="$i"/><c:order val="$i"/><c:tx><c:strRef><c:f>$name</c:f></c:strRef></c:tx>);
        $i++;
        $ch->{type} eq 'line'
          ? $s . $sp->($color, 1, $dash) . '<c:marker><c:symbol val="none"/></c:marker>' . qq(<c:cat><c:numRef><c:f>$ch->{cat}</c:f></c:numRef></c:cat><c:val><c:numRef><c:f>$vals</c:f></c:numRef></c:val><c:smooth val="0"/></c:ser>)
          : $s . $sp->($color) . '<c:invertIfNegative val="0"/>' . qq(<c:cat><c:numRef><c:f>$ch->{cat}</c:f></c:numRef></c:cat><c:val><c:numRef><c:f>$vals</c:f></c:numRef></c:val></c:ser>)
    } @{ $ch->{series} };
    my $body = $ch->{type} eq 'line'
        ? '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>' . $ser . '<c:marker val="1"/><c:axId val="5001"/><c:axId val="5002"/></c:lineChart>'
        : '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/><c:varyColors val="0"/>' . $ser . '<c:gapWidth val="80"/><c:axId val="5001"/><c:axId val="5002"/></c:barChart>';
    my $fmt = $ch->{datefmt} ? qq(<c:numFmt formatCode="$ch->{datefmt}" sourceLinked="0"/>) : '<c:numFmt formatCode="General" sourceLinked="1"/>';
    $X . qq(<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$RELS">)
       . '<c:roundedCorners val="0"/><c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1200" b="1"/></a:pPr><a:r><a:rPr lang="en-US" sz="1200" b="1"><a:solidFill><a:srgbClr val="27235D"/></a:solidFill></a:rPr><a:t>'
       . xe($ch->{title}) . '</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/><c:plotArea><c:layout/>' . $body
       . '<c:catAx><c:axId val="5001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>' . $fmt . '<c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
       . '<c:spPr><a:ln><a:solidFill><a:srgbClr val="BFBFBF"/></a:solidFill></a:ln></c:spPr>' . $txt . '<c:crossAx val="5002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
       . '<c:valAx><c:axId val="5002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:majorGridlines><c:spPr><a:ln><a:solidFill><a:srgbClr val="E4E4E7"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>'
       . '<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:spPr><a:ln><a:noFill/></a:ln></c:spPr>' . $txt . '<c:crossAx val="5001"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>'
       . '</c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/>' . $txt . '</c:legend><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>';
}

# workbook, names, styles, strings
my $wb = $X . "<workbook $NS>" . '<workbookPr defaultThemeVersion="124226"/><bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="15000" activeTab="0"/></bookViews><sheets>'
       . join('', map { '<sheet name="' . xe($sheets[$_]{name}) . '" sheetId="' . ($_ + 1) . '" r:id="rId' . ($_ + 1) . '"/>' } 0 .. $#sheets) . '</sheets><definedNames>';
$wb .= '<definedName name="' . $_ . '">' . xe($names{$_}) . '</definedName>' for sort { lc $a cmp lc $b } grep { $_ !~ /Input$/ } keys %names;
$wb .= '<definedName name="_xlnm.Print_Area" localSheetId="' . (grep { $sheets[$_]{name} eq 'Quad' } 0 .. $#sheets)[0] . '">Quad!$A$1:$I$34</definedName>';
$wb .= '</definedNames><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>';
$files{'xl/workbook.xml'} = $wb;
$files{'xl/_rels/workbook.xml.rels'} = relsxml((map { [ "$RELS/worksheet", "worksheets/sheet$_.xml" ] } 1 .. @sheets), [ "$RELS/styles", 'styles.xml' ], [ "$RELS/sharedStrings", 'sharedStrings.xml' ]);
$files{'xl/styles.xml'} = $X . '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    . (@numfmts ? '<numFmts count="' . @numfmts . '">' . join('', map { '<numFmt numFmtId="' . (164 + $_) . '" formatCode="' . xe($numfmts[$_]) . '"/>' } 0 .. $#numfmts) . '</numFmts>' : '')
    . '<fonts count="' . @fonts . '">' . join('', @fonts) . '</fonts><fills count="' . @fills . '">' . join('', @fills) . '</fills>'
    . '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    . '<cellXfs count="' . @xfs . '">' . join('', @xfs) . '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    . '<dxfs count="' . @dxfs . '">' . join('', @dxfs) . '</dxfs><tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/></styleSheet>';
$files{'xl/sharedStrings.xml'} = $X . '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="' . @sst . '" uniqueCount="' . @sst . '">'
    . join('', map { '<si><t xml:space="preserve">' . xe($_) . '</t></si>' } @sst) . '</sst>';
$files{'_rels/.rels'} = relsxml([ "$RELS/officeDocument", 'xl/workbook.xml' ], [ 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties', 'docProps/core.xml' ],
                                [ "$RELS/extended-properties", 'docProps/app.xml' ]);
$files{'docProps/app.xml'} = $X . '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Microsoft Excel</Application></Properties>';
$files{'docProps/core.xml'} = $X . '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    . '<dc:title>Agile kit -- Excel edition</dc:title><dc:creator>agile kit</dc:creator></cp:coreProperties>';
$files{'[Content_Types].xml'} = $X . '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
    . '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    . '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    . '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
    . '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    . '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    . join('', map { qq(<Override PartName="$_->[0]" ContentType="$_->[1]"/>) } @ct) . '</Types>';

my $z;
for my $name (@order) {                        # a fixed time: the same data gives the same bytes
    my %zo = (Name => $name, Time => 315532800, Minimal => 1, ExtAttr => 0);
    if (!$z) { $z = IO::Compress::Zip->new($o{out}, %zo) or die "agile-workbook: cannot write $o{out}: $ZipError\n" } else { $z->newStream(%zo) }
    $z->print(Encode::encode('UTF-8', $files{$name}));
}
$z->close;
printf "%s: %d items, %d log rows, %d people, %d teams, %d epics\n", $o{out}, scalar @items, scalar @log, scalar @roster, scalar @teams, scalar keys %epic;

sub Scrum_today { my @t = gmtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
