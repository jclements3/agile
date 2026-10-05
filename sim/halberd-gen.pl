#!/usr/bin/perl
# Builds data/halberd: the Halberd SysML v1 -> v2 port (Appendix C and D of docs/status-metrics.html)
# as a real kit project -- 12 weeks from Mon 2026-10-05, six two-week sprints, one standup per
# working day -- and writes docs/HALBERD.html, the public view of it.
#
# Like sim/history-gen.pl it writes real stand-up verb files and compiles them through the tested
# Standup.pm/Scrum.pm pipeline, so the journal is valid by construction. The numbers come from the
# doc's own tables (docs/src/status-metrics.md): each day's "Ported" count, each sprint's committed /
# done / carried. Tasks are cut at day boundaries so the journal reproduces every sprint total
# exactly; the generator checks that against the doc and dies on any difference.
#
# Halberd is fictional and notional, and so is every number in it.
#
# Standalone planning/simulation tool -- not part of the tested kit (lib/, bin/, tests/). Core Perl.
#
# Usage:  perl sim/halberd-gen.pl [--dir PATH] [--doc FILE] [--html FILE] [--no-html]
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use File::Path qw(remove_tree make_path);
use Prelude qw(sorted sum);
use Standup qw(parse_standup apply);
use Scrum   qw(load sprint_summary);
use Ledger ();

my $ROOT = "$FindBin::Bin/..";
my %o = (dir => "$ROOT/data/halberd", doc => "$ROOT/docs/src/status-metrics.md", html => "$ROOT/docs/HALBERD.html");
GetOptions(\%o, 'dir=s', 'doc=s', 'html=s', 'no-html') or exit 2;
$o{dir} =~ m{(^|/)data/halberd$} or die "--dir must end in data/halberd (it is wiped and rebuilt)\n";

# ---- the scenario: segments in the order they are ported (Appendix C), and which segment each working day works on
my %SEG = (E => 'Systems Engineering & Integration', V => 'Interceptor Development', B => 'Battle Management & Fire Control',
           T => 'Test & Evaluation', G => 'Government Program Office', M => 'Manufacturing & Production', L => 'Logistics & Sustainment');
my @DAYSEG = qw(EEEEE EEEEE EEVVV VVVVV VVBBB BBBBB BBTTT TTT GGGGG MMMMM MMLLL LLL);   # per week, per working day (as sim/status-metrics-sim.pl)
my $TEAM = 'Halberd';
my $WHO  = 'JC';
my $TOME = 'Halberd SysML v2 port';
my %MON  = (Oct => 10, Nov => 11, Dec => 12);

# ---- read Appendix D: daily standups (per sprint) and the sprint burn-down headlines
open my $dh, '<:encoding(UTF-8)', $o{doc} or die "cannot read $o{doc}: $!\n";
my (@days, @sprints, $part, $sp, $wk);
while (my $l = <$dh>) {
    chomp $l;
    $part = $1 if $l =~ /^#{1,2} (Appendix [A-Z]|Daily standups|Sprint burn-downs|Release burn-down)/;
    next unless defined $part;
    if ($part eq 'Daily standups') {
        $sp = $1 if $l =~ /^### Sprint (\d+)/;
        $wk = $1 if $l =~ /^\*\*Week (\d+)\*\*/;
        if (my @m = $l =~ /^\| (\w{3}) (\d\d) (\w{3}) \| ([\d,]+) \| ([\d,]+) \| (.*?) \| (.*?) \| (.*?) \|$/) {
            my ($dow, $dd, $mon, $ported, $left, $y, $t, $b) = @m;
            tr/,//d for $ported, $left;   # 1,939 -> 1939
            my %d = (dow => $dow, date => sprintf('2026-%02d-%02d', $MON{$mon}, $dd), label => "$dd $mon", ported => $ported,
                     left => $left, y => $y, t => $t, b => $b, sprint => $sp, week => $wk);
            push @days, \%d;
        }
    } elsif ($part eq 'Sprint burn-downs' && $l =~ /^Committed (\d+)\. Done (\d+)\. Carried over (\d+)\. Done % (\d+)/) {
        push @sprints, { n => @sprints + 1, committed => $1, done => $2, carried => $3, pct => $4 };
    }
}
close $dh;
@days == 56 && @sprints == 6 or die "expected 56 standups and 6 sprints in $o{doc}, found " . @days . ' and ' . @sprints . "\n";
{   # segment of each day, and sanity: Left falls by Ported every day
    my %i; my $left = 1960;
    for my $d (@days) {
        my $k = $i{ $d->{week} }++;
        $d->{seg} = substr($DAYSEG[ $d->{week} - 1 ], $k, 1) or die "no segment for $d->{date}\n";
        $left -= $d->{ported};
        $left == $d->{left} or die "$d->{date}: Left $d->{left} but 1960 - ported so far = $left\n";
    }
}

# ---- cut each sprint's commitment into tasks at day boundaries
my $idn = 0;
my $carry;                                     # the task carried out of the previous sprint
my @plan;                                      # per sprint: { tasks => [...], carry_in => task }
for my $s (@sprints) {
    my @sd = grep { $_->{sprint} == $s->{n} } @days;
    my $done = sum(map { $_->{ported} } @sd);
    $done == $s->{done} or die "sprint $s->{n}: days port $done, doc says done $s->{done}\n";
    my $c = $carry ? $carry->{pts} : 0;
    my ($cum, @cuts) = (0);
    for my $d (@sd) { $cum += $d->{ported}; push @cuts, [ $cum, $d ] if $cum > $c }
    my @tasks; my $from = $c;
    for my $cut (@cuts) {
        next if $cut->[0] <= $from;
        push @tasks, { id => 'HAL-' . ++$idn, pts => $cut->[0] - $from, seg => $cut->[1]{seg}, day => $cut->[1]{date} };
        $from = $cut->[0];
    }
    my $out;
    if ($s->{committed} > $from) {             # the committed tail nobody reached: carried into the next sprint
        $out = { id => 'HAL-' . ++$idn, pts => $s->{committed} - $from, seg => $sd[-1]{seg}, day => undef, out => 1 };
        push @tasks, $out;
    }
    if ($carry) {                              # the carried task finishes on the first day the sprint's porting covers it
        my $cum2 = 0;
        for my $d (@sd) { $cum2 += $d->{ported}; if ($cum2 >= $c) { $carry->{day} = $d->{date}; last } }
    }
    push @plan, { sprint => $s, tasks => \@tasks, carry_in => $carry, days => \@sd };
    $carry = $out;
}

# ---- write the project: scrum.conf, then one stand-up file per working day, compiled in order
remove_tree($o{dir});
make_path($o{dir}); -d $o{dir} or die "cannot create $o{dir}: $!\n";
mkdir "$o{dir}/$_" for qw(standups reports);
my $journal = "$o{dir}/scrum.txt";
_write("$o{dir}/scrum.conf", <<"EOF");
# scrum.conf -- generated by sim/halberd-gen.pl (Halberd is notional). All paths relative to this file.
journal   = scrum.txt
standups  = standups
reports   = reports
unit      = items        # v1 model items ported to SysML v2 text
default_team = $TEAM
calendar  = mock
history_days = 5
banner    =
funding   = funding.ledger          # the Funding tab: funds, burn, run-out
complete  = complete-*.csv          # percent complete per account (newest on or before today) -> earned value
EOF
_write("$o{dir}/roster.txt", "# name | email | team | role | org\n$WHO | | $TEAM | Solutions Architect | Halberd\n");
_write($journal, "; generated by sim/halberd-gen.pl -- Halberd SysML v1 -> v2 port, 12 weeks from 2026-10-05 (notional)\n");

sub title { my $t = shift; "Port $t->{pts} $SEG{ $t->{seg} } v1 items to SysML v2" }
my $s;
my $blocked;                                   # the task currently marked blocked, if any
for my $p (@plan) {
    my $n = $p->{sprint}{n};
    for my $i (0 .. $#{ $p->{days} }) {
        my $d = $p->{days}[$i];
        my $txt = "$d->{date}\nsprint $n\n== $TEAM\n";
        if ($i == 0) {                         # planning: capacity = the commitment, intake the new tasks, commit carry-in + new
            $txt .= "cap $p->{sprint}{committed}\n";
            $txt .= "commit $p->{carry_in}{id} $WHO\n" if $p->{carry_in};
            for my $t (@{ $p->{tasks} }) {
                $txt .= sprintf qq{new %s %d "%s" p:1 e:"%s %s" t:"%s" o:%s\n}, $t->{id}, $t->{pts}, title($t), $t->{seg}, $SEG{ $t->{seg} }, $TOME, $WHO;
                $txt .= "commit $t->{id} $WHO\n";
            }
        }
        my @done = map { $_->{id} } grep { ($_->{day} // '') eq $d->{date} } ($p->{carry_in} // (), @{ $p->{tasks} });
        $txt .= 'done ' . join(' ', @done) . "\n" if @done;
        my $blk = $d->{b} !~ /^None\.?$/;
        if ($blk && !$blocked) {               # the first blocked day: block the oldest task still open
            my ($open) = grep { ($_->{day} // '9') gt $d->{date} } ($p->{carry_in} // (), @{ $p->{tasks} });   # not done yet, today or before
            if ($open) { $blocked = $open; $txt .= "block $open->{id} " . _plain($d->{b}) . "\n" }
        } elsif (!$blk && $blocked) {
            $txt .= "unblock $blocked->{id}\n" if ($blocked->{day} // '9') gt $d->{date};
            undef $blocked;
        }
        if ($i == $#{ $p->{days} }) {          # sprint close: the tail goes to Carryover
            my @c = map { $_->{id} } grep { $_->{out} } @{ $p->{tasks} };
            $txt .= 'carry ' . join(' ', @c) . "\n" if @c;
            undef $blocked if $blocked && grep { $_ eq $blocked->{id} } @c;
        }
        $txt .= "note $_\n" for _notes($d);
        my $file = "$o{dir}/standups/$d->{date}.txt";
        _write($file, $txt);
        my $su = parse_standup($txt, $file);
        die "$d->{date}: " . join('; ', @{ $su->{errors} }) . "\n" if @{ $su->{errors} };
        $s = load($journal, today => $d->{date});
        $s->{unit} = 'items';          # the journal counts v1 model items, not story points (scrum.conf unit)
        apply($s, $su, $journal);
        _write("$o{dir}/standups/$d->{date}-$TEAM-answers.txt",
               "$d->{date} $TEAM\n$WHO (08:30)\n  Y: " . _plain($d->{y}) . "\n  T: " . _plain($d->{t}) . "\n  B: " . ($blk ? _plain($d->{b}) : 'none') . "\n");
    }
}
sub _notes { my $d = shift; my @n; push @n, _plain($1) if $d->{y} =~ /((?:[A-Z][^.]*?) is now gated on every merge[^.]*\.)/; @n }
sub _plain { my $t = shift; $t =~ s/\*\*//g; $t =~ s/\s+/ /g; $t }

# ---- check the compiled journal against the doc, sprint by sprint
$s = load($journal, today => $days[-1]{date});
my @rows;
for my $sp (@sprints) {
    my $r = sprint_summary($s, $sp->{n})->{totals};
    for (['committed', 'committed'], ['done', 'done'], ['carryover', 'carried'], ['pct', 'pct']) {
        $r->{ $_->[0] } == $sp->{ $_->[1] } or die "sprint $sp->{n}: journal $_->[0] $r->{$_->[0]}, doc $_->[1] $sp->{$_->[1]}\n";
    }
    push @rows, $r;
}
printf "sprint %d  committed %3d  done %3d  carried %2d  done %% %3d  (matches the doc)\n", $_->{n}, @{ $rows[ $_->{n} - 1 ] }{qw(committed done carryover pct)} for @sprints;
print "wrote $journal: " . @days . " stand-ups, $idn tasks\n";

# ---- the money: a notional FY27 funding journal beside the stand-up journal (data/halberd/funding.ledger)
# Each segment is budgeted at a notional cost per v1 item, time-phased (~ Monthly from .. to ..) over the days the
# plan works it; FY27 funding is authorized on 1 October with a 10% reserve; labor is charged weekly (timecards)
# from the items actually ported that week, with a notional cost factor (sprint 3 overran: the shared runner).
my $RATE   = 150;                                       # notional $ per v1 item ported
my @FACTOR = (1.00, 0.97, 1.12, 1.03, 0.98, 1.00);      # notional actual/plan cost per sprint
my (%seg_items, %seg_first, %seg_last);
for my $d (@days) {
    $seg_items{ $d->{seg} } += $d->{ported};
    $seg_first{ $d->{seg} } //= $d->{date};
    $seg_last{ $d->{seg} } = $d->{date};
}
$seg_items{E} += 0;
my @order = qw(E V B T G M L);
my $bac = 0; $bac += $seg_items{$_} * $RATE for @order;
my $fund = "; generated by sim/halberd-gen.pl -- Halberd FY27 funding (notional: every number is made up)\n"
         . "; Budgets are time-phased over the days each segment is worked; percent complete comes from the stand-ups.\n"
         . "; Try:  perl bin/ledger.pl -f data/halberd/funding.ledger evm --now 2026-11-30 --complete-file data/halberd/complete-2026-11-30.csv\n\n";
for my $k (@order) {
    my ($from, $to) = ($seg_first{$k}, Ledger::add_days($seg_last{$k}, 1));
    my $months = Ledger::plan_months("Monthly from $from to $to", $from, $to);
    $fund .= sprintf "~ Monthly from %s to %s\n    Expense:Labor:Halberd:%s  %s\n    Assets:Funding:Halberd\n\n",
        $from, $to, $k, _usd($seg_items{$k} * $RATE / $months);
}
$fund .= sprintf "2026-10-01 * FY27 funding authorized (BAC %s + 10%% reserve)\n    Assets:Funding:Halberd  %s\n    Equity:Appropriation:FY27\n\n", _usd($bac), _usd($bac * 1.10);
for my $w (1 .. 12) {                                           # weekly timecards, posted on the week's last working day
    my @wd = grep { $_->{week} == $w } @days;
    my %by; $by{ $_->{seg} } += $_->{ported} for @wd;
    next unless grep { $by{$_} } @order;
    my $f = $FACTOR[ $wd[0]{sprint} - 1 ];
    $fund .= "$wd[-1]{date} * Week $w labor (sprint $wd[0]{sprint})\n";
    $fund .= sprintf "    Expense:Labor:Halberd:%s  %s\n", $_, _usd($by{$_} * $RATE * $f) for grep { $by{$_} } @order;
    $fund .= "    Assets:Funding:Halberd\n\n";
}
_write("$o{dir}/funding.ledger", $fund);
for my $at (qw(2026-10-31 2026-11-30 2026-12-23)) {             # percent complete per segment at each month's status date
    my %done; $done{ $_->{seg} } += $_->{ported} for grep { $_->{date} le $at } @days;
    _write("$o{dir}/complete-$at.csv", "account,pct\n" . join('', map { sprintf "Expense:Labor:Halberd:%s,%.1f\n", $_, 100 * ($done{$_} // 0) / $seg_items{$_} } @order));
}
print "wrote $o{dir}/funding.ledger: BAC " . _usd($bac) . ", 3 percent-complete snapshots\n";
my @evm_series;                                                  # end of each week: planned, earned, actual, funds left
{
    my $fj = Ledger::read_journal("$o{dir}/funding.ledger");
    for my $w (1 .. 12) {
        my ($last) = (grep { $_->{week} == $w } @days)[-1];
        my $at = $last->{date};
        my %done; $done{ $_->{seg} } += $_->{ported} for grep { $_->{date} le $at } @days;
        my %pct = map { ("Expense:Labor:Halberd:$_" => ($done{$_} // 0) / $seg_items{$_}) } @order;
        my $e = Ledger::evm($fj, status => Ledger::add_days($at, 1), complete => \%pct);
        my ($funds) = values %{ Ledger::account_total($fj, 'Assets:Funding:Halberd', end => Ledger::add_days($at, 1)) };
        my $fc = Ledger::forecast($fj, status => Ledger::add_days($at, 1), months => 2, account => qr/^Assets:Funding/);
        push @evm_series, { date => $at, label => $last->{label}, evm => $e, funds => $funds // 0, forecast => $fc->{rows}[0] };
    }
}
sub _usd { my $v = sprintf '%.2f', shift; 1 while $v =~ s/^(-?\d+)(\d{3})/$1,$2/; "\$$v" }

exit 0 if $o{'no-html'};

# ---- docs/HTML: the public view (data/ is never committed)
require "$FindBin::Bin/halberd-render.pl";
halberd_render($o{html}, days => \@days, sprints => \@sprints, plan => \@plan, seg => \%SEG, journal_rows => \@rows, evm_series => \@evm_series, bac => $bac, authorized => $bac * 1.10);
print "wrote $o{html}\n";

sub _write { my ($f, $t) = @_; open my $fh, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh or die "cannot write $f: $!\n" }
