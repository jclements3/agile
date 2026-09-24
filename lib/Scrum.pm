package Scrum;
# Multi-team scrum tracking on a Ledger.pm journal: sprint status, velocity,
# master/team/member backlogs, HTML dashboard, e-mail reports, Outlook drafts.
use strict;
use warnings;
use Time::Local qw(timegm);
use Prelude qw(sorted nub sum fmap classify maximum minimum sortOn fromListWith);
use Ledger  qw(read_journal postings format_amount amt_add parse_amount);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Scrum: unknown function '$n'\n" unless defined &{"Scrum::$n"};
        *{"${caller}::$n"} = \&{"Scrum::$n"};
    }
}

# ---------------------------------------------------------------- loading
# $s = { j, file, items => {id => item}, teams => [..], sprints => [..], current => N, today }
# item = { id, title, created, meta => {prio, epic, owner, ...}, bal => {account => points},
#          history => [ {date, payee, account, points} ], location => [accounts], state, sprint, team, points }

sub parse_meta {                              # "id: A-1, prio: 2, owner: Bob"  -> hashref
    my $c = shift;
    my %m;
    for (split /\s*,\s*/, ($c // '')) { $m{ lc $1 } = $2 if /^\s*(\w+)\s*:\s*(.*?)\s*$/ }
    \%m;
}
sub _num { my $a = shift; sum(values %{ $a // {} }) }       # points as a plain number (one commodity assumed)

sub load {
    my ($file, %opt) = @_;
    my $j = read_journal($file);
    my $s = { j => $j, file => $file, items => {}, today => $opt{today} // _today(), until => $opt{until} };   # until: ignore postings after that date (the journal as it stood then)
    _index($s);
    $s;
}

sub _index {
    my $s = shift;
    my (%items, %teams, %sprints);
    for my $p (postings($s->{j})) {
        next if $s->{until} && $p->{date} gt $s->{until};
        my $acct = $p->{account};
        $teams{$1}++   if $acct =~ /^Backlog:(?!Master)([^:]+)/;
        if ($acct =~ /^Sprint:(\d+):([^:]+)/) { $sprints{$1}++; $teams{$2}++ }
        my $meta = { %{ parse_meta($p->{txn}{comment}) }, %{ parse_meta($p->{comment}) } };
        my $id = $meta->{id} or next;
        my $it = $items{$id} //= { id => $id, created => $p->{date}, meta => {}, bal => {}, history => [],
                                  title => ($p->{payee} =~ /^\s*(?:intake|new|add)\s+\Q$id\E\s*(.*)$/i ? $1 : $p->{payee}) };
        for my $k (keys %$meta) { next if $k eq 'id'; $it->{meta}{$k} = $meta->{$k} }
        $it->{title} = $it->{meta}{title} if $it->{meta}{title};
        for my $k (qw(blocked hold)) {        # when a blocker or hold was set: the posting that carried it (cleared by the empty form)
            next unless exists $meta->{$k};
            $it->{"${k}_since"} = (defined $meta->{$k} && $meta->{$k} ne '') ? $p->{date} : undef;
        }
        my $pts = _num($p->{amount});
        if ($pts > 0) {                       # the quad's transient marks end when the work moves on: a punt ends at the next commit, a redo or pass at Done
            delete $it->{meta}{punt} if $acct =~ /:Committed$/ && !exists $meta->{punt};
            delete @{ $it->{meta} }{qw(redo pass)} if $acct =~ /:Done$/;
        }
        $it->{bal}{$acct} += $pts;
        push @{ $it->{history} }, { date => $p->{date}, payee => $p->{payee}, account => $acct, points => $pts };
    }
    for my $it (values %items) {
        my @loc = sorted(grep { $it->{bal}{$_} > 1e-9 } keys %{ $it->{bal} });
        $it->{location} = \@loc;
        $it->{points}   = sum(map { $it->{bal}{$_} } @loc);
        my $l = $loc[0] // '';
        ($it->{state}, $it->{sprint}, $it->{team}) =
            $l eq 'Backlog:Master'                     ? ('master',    undef, 'Master')
          : $l =~ /^Backlog:([^:]+)$/                  ? ('backlog',   undef, $1)
          : $l =~ /^Sprint:(\d+):([^:]+):Committed$/  ? ('committed', $1, $2)
          : $l =~ /^Sprint:(\d+):([^:]+):Done$/       ? ('done',      $1, $2)
          : $l =~ /^Sprint:(\d+):([^:]+):Carryover$/  ? ('carryover', $1, $2)
          : $l =~ /^Sprint:(\d+):([^:]+):Removed$/    ? ('removed',   $1, $2)
          : $l eq ''                                   ? ('closed',    undef, undef)
          :                                              ($l,          undef, undef);
        $it->{team} //= $it->{meta}{team};
        $it->{owner} = $it->{meta}{owner};
        $it->{blocked} = (defined $it->{meta}{blocked} && $it->{meta}{blocked} ne '') ? $it->{meta}{blocked} : undef;
        $it->{hold}    = (defined $it->{meta}{hold}    && $it->{meta}{hold}    ne '') ? $it->{meta}{hold}    : undef;   # interrupted by higher-priority work (hold ID why / resume ID)
        $it->{age}   = days_between($it->{created}, $s->{today});
    }
    $s->{items}   = \%items;
    $s->{teams}   = [ sorted(keys %teams) ];
    $s->{sprints} = [ sort { $a <=> $b } keys %sprints ];
    $s->{current} = $s->{sprints}[-1];
    $s->{capacity} = {};
    for my $t (@{ $s->{j}{periodic} }) {
        next unless $t->{period} =~ /^sprint\s+(\d+)/i;
        $s->{capacity}{$1}{ $_->{account} } = _num($_->{amount}) for grep { $_->{amount} } @{ $t->{postings} };
    }
}

sub _today { my @t = gmtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub days_between {
    my ($a, $b) = @_;
    my $t = sub { my ($y, $m, $d) = split /-/, $_[0]; timegm(0, 0, 0, $d, $m - 1, $y) };
    int(($t->($b) - $t->($a)) / 86400);
}
sub items { my ($s, %f) = @_;                 # items(state=>'backlog', team=>'Alpha', owner=>'Bob', sprint=>42, epic=>'Auth')
    my @out = @{ $s->{_memo}{items_sorted} //= [ sortOn(sub { [ $_[0]{meta}{prio} // 9999, $_[0]{created}, $_[0]{id} ] }, values %{ $s->{items} }) ] };   # sorted once per load; the filters below keep the order
    @out = grep { $_->{state} eq $f{state} } @out                             if $f{state};
    @out = grep { defined $_->{team} && $_->{team} eq $f{team} } @out         if $f{team};
    @out = grep { defined $_->{owner} && $_->{owner} eq $f{owner} } @out      if $f{owner};
    @out = grep { defined $_->{sprint} && $_->{sprint} == $f{sprint} } @out   if $f{sprint};
    @out = grep { ($_->{meta}{epic} // '') eq $f{epic} } @out                 if $f{epic};
    @out;
}

# ---------------------------------------------------------------- sprint & velocity
sub sprint_summary {                          # -> { sprint, teams => { T => {...} }, totals => {...} }   (memoised per loaded journal: velocity, roadmap and the cockpit ask for every sprint several times)
    my ($s, $n) = @_;
    $n //= $s->{current};
    return $s->{_memo}{sprint_summary}{ $n // '' } //= _sprint_summary($s, $n);
}
sub _sprint_summary {
    my ($s, $n) = @_;
    return { sprint => undef, teams => {}, totals => { team => 'Total', committed => 0, done => 0, carryover => 0, removed => 0, open => 0, capacity => 0, pct => 0, load => undef } }
        unless defined $n;                    # nothing committed yet (a fresh journal): no sprint to summarise
    my %t;
    for my $p (postings($s->{j}, account => qr/^Sprint:\Q$n\E:/)) {
        my ($team, $bucket) = $p->{account} =~ /^Sprint:\d+:([^:]+):(\w+)/ or next;
        my $pts = _num($p->{amount});
        my $r = $t{$team} //= { team => $team, committed => 0, done => 0, carryover => 0, removed => 0, open => 0 };
        $r->{committed} += $pts if $bucket eq 'Committed' && $pts > 0;
        $r->{open}      += $pts if $bucket eq 'Committed';
        $r->{done}      += $pts if $bucket eq 'Done';
        $r->{carryover} += $pts if $bucket eq 'Carryover' && $pts > 0;   # historical: stays even after moving on
        $r->{removed}   += $pts if $bucket eq 'Removed';
    }
    my %tot = (team => 'Total', committed => 0, done => 0, carryover => 0, removed => 0, open => 0, capacity => 0);
    for my $team (sorted(keys %t)) {
        my $r = $t{$team};
        $r->{capacity}   = $s->{capacity}{$n}{$team} // 0;
        $r->{pct}        = $r->{committed} ? int(100 * $r->{done} / $r->{committed} + 0.5) : 0;
        $r->{load}       = $r->{capacity} ? int(100 * $r->{committed} / $r->{capacity} + 0.5) : undef;
        $r->{open_items} = [ items($s, state => 'committed', sprint => $n, team => $team) ];
        $r->{carry_items} = [ items($s, state => 'carryover', sprint => $n, team => $team) ];
        $tot{$_} += $r->{$_} for qw(committed done carryover removed open capacity);
    }
    $tot{pct}  = $tot{committed} ? int(100 * $tot{done} / $tot{committed} + 0.5) : 0;
    $tot{load} = $tot{capacity} ? int(100 * $tot{committed} / $tot{capacity} + 0.5) : undef;
    { sprint => $n, teams => \%t, totals => \%tot };
}

sub velocity {                                # -> { team => [ {sprint, committed, done, capacity} ], avg => {team => n} }   (memoised per loaded journal)
    my ($s, %o) = @_;
    my $last = $o{last} // 3;
    return $s->{_memo}{velocity}{$last} //= _velocity($s, $last);
}
sub _velocity {
    my ($s, $last) = @_;
    my %v;
    for my $n (@{ $s->{sprints} }) {
        my $sum = sprint_summary($s, $n);
        for my $team (keys %{ $sum->{teams} }) {
            my $r = $sum->{teams}{$team};
            push @{ $v{$team} }, { sprint => $n, committed => $r->{committed}, done => $r->{done}, capacity => $r->{capacity} };
        }
    }
    my %avg;
    for my $team (keys %v) {
        my @done = map { $_->{done} } @{ $v{$team} };
        pop @done if @done > 1 && $s->{current} && $v{$team}[-1]{sprint} == $s->{current} && _in_progress($s, $team);
        @done = @done[ -$last .. -1 ] if @done > $last;
        $avg{$team} = @done ? sum(@done) / @done : 0;
    }
    { team => \%v, avg => \%avg };
}
sub _in_progress { my ($s, $team) = @_; (sprint_summary($s, $s->{current})->{teams}{$team}{open} // 0) > 0 }   # still has committed points

# ---------------------------------------------------------------- epics & tomes (from task metadata epic: / tome:)
sub epics {                                   # -> [ { epic, tome, total, done, wip, backlog, removed, pct, open, items => [...] } ] sorted by tome, epic
    my $s = shift;
    my $by = classify(sub { $_[0]{meta}{epic} // '(none)' }, items($s));
    my @out;
    for my $e (sorted(keys %$by)) {
        my @it = @{ $by->{$e} };
        my $r = { epic => $e, tome => (grep { defined } map { $_->{meta}{tome} } @it)[0] // '(none)', items => \@it, total => 0, done => 0, wip => 0, backlog => 0, removed => 0 };
        for my $it (@it) {
            my $done = sum(map { $it->{bal}{$_} } grep { /:Done$/ } keys %{ $it->{bal} });
            my $rem  = sum(map { $it->{bal}{$_} } grep { /:Removed$/ } keys %{ $it->{bal} });
            $r->{done} += $done; $r->{removed} += $rem;
            $r->{wip} += $it->{points} if $it->{state} eq 'committed' || $it->{state} eq 'carryover';
            $r->{backlog} += $it->{points} if $it->{state} eq 'backlog' || $it->{state} eq 'master';
        }
        $r->{total} = $r->{done} + $r->{wip} + $r->{backlog};
        $r->{pct} = $r->{total} ? int(100 * $r->{done} / $r->{total} + 0.5) : 0;
        $r->{open} = $r->{wip} > 0 ? 1 : 0;   # OPEN: an epic (and its tome) is open while any of its tasks is in a sprint
        push @out, $r;
    }
    sortOn(sub { [ $_[0]{tome}, $_[0]{epic} ] }, @out);
}
sub epics_text {
    my $s = shift;
    my @rows = map { [ $_->{tome}, $_->{epic}, scalar @{ $_->{items} }, $_->{total}, $_->{done}, $_->{wip}, $_->{backlog}, "$_->{pct}%" ] } epics($s);
    _table([ 'Tome', 'Epic', 'Tasks', 'Total', 'Done', 'In sprint', 'Backlog', 'Done%' ], \@rows, [ 2 .. 7 ], 'Epics by tome');
}

# ---------------------------------------------------------------- backlogs & members
sub backlog {                                 # backlog($s) master ; backlog($s, 'Alpha') team
    my ($s, $scope) = @_;
    (!$scope || lc $scope eq 'master') ? items($s, state => 'master') : items($s, state => 'backlog', team => $scope);
}
sub members {                                 # -> { name => { team, wip => [..], done => [..], backlog => [..], wip_points } }
    my ($s, $team) = @_;
    my %m;
    for my $it (values %{ $s->{items} }) {
        next unless $it->{owner};
        next if $team && ($it->{team} // '') ne $team;
        my $r = $m{ $it->{owner} } //= { name => $it->{owner}, team => $it->{team}, wip => [], done => [], backlog => [] };
        $r->{team} //= $it->{team};
        push @{ $r->{wip} },     $it if $it->{state} eq 'committed';
        push @{ $r->{done} },    $it if $it->{state} eq 'done' && $s->{current} && ($it->{sprint} // -1) == $s->{current};
        push @{ $r->{backlog} }, $it if $it->{state} eq 'backlog' || $it->{state} eq 'master';
    }
    for my $r (values %m) {
        $r->{$_} = [ sortOn(sub { [ $_[0]{meta}{prio} // 9999, $_[0]{created} ] }, @{ $r->{$_} }) ] for qw(wip done backlog);
        $r->{wip_points} = sum(map { $_->{points} } @{ $r->{wip} });
    }
    \%m;
}
sub unassigned { my ($s, $team) = @_; grep { !$_->{owner} && $_->{state} eq 'committed' && (!$team || $_->{team} eq $team) } items($s) }

# ---------------------------------------------------------------- text rendering
sub _table {                                  # _table(\@header, \@rows, \@right_align_cols, $title)
    my ($h, $rows, $right, $title) = @_;
    my %r = map { $_ => 1 } @{ $right // [] };
    my @all = ($h, @$rows);
    my @w = map { my $i = $_; maximum(map { length($_->[$i] // '') } @all) } 0 .. $#$h;
    my $line = sub { my $row = shift; join('  ', map { sprintf($r{$_} ? "%*s" : "%-*s", $w[$_], $row->[$_] // '') } 0 .. $#$h) =~ s/\s+$//r };
    (defined $title ? "$title\n" : '') . join '', map { $line->($_) . "\n" } $h, [ map { '-' x $_ } @w ], @$rows;
}
sub _item_row { my $it = shift; [ $it->{id}, $it->{points}, $it->{meta}{prio} // '', $it->{meta}{tome} // '', $it->{meta}{epic} // '', $it->{owner} // '', $it->{age}, $it->{title}, $it->{blocked} // '' ] }
my @ITEM_HDR = ('ID', 'SP', 'Prio', 'Tome', 'Epic', 'Owner', 'Age', 'Title', 'Blocked');
sub blocked {                                 # only work still in flight: a Done/Removed task keeps its last blocked: note as history but is not blocked
    my ($s, $team) = @_;
    grep { $_->{blocked} && ($_->{state} eq 'committed' || $_->{state} eq 'carryover') && (!$team || ($_->{team} // '') eq $team) } items($s);
}
my @ITEM_R   = (1, 2, 6);

sub sprint_text {
    my ($s, $n) = @_;
    my $r = sprint_summary($s, $n);
    my @rows = map { my $t = $r->{teams}{$_};
        [ $_, $t->{capacity} || '', $t->{committed}, $t->{done}, $t->{open}, $t->{carryover}, $t->{removed}, "$t->{pct}%", defined $t->{load} ? "$t->{load}%" : '' ] }
        sorted(keys %{ $r->{teams} });
    my $t = $r->{totals};
    push @rows, [ 'Total', $t->{capacity} || '', $t->{committed}, $t->{done}, $t->{open}, $t->{carryover}, $t->{removed}, "$t->{pct}%", defined $t->{load} ? "$t->{load}%" : '' ];
    my $out = _table([ 'Team', 'Cap', 'Commit', 'Done', 'Open', 'Carry', 'Removed', 'Done%', 'Load%' ], \@rows, [ 1 .. 8 ], "Teams: sprint $r->{sprint}");
    for my $team (sorted(keys %{ $r->{teams} })) {
        my @open = @{ $r->{teams}{$team}{open_items} };
        $out .= "\n$team open tasks (" . scalar(@open) . "):\n" . _table(\@ITEM_HDR, [ map { _item_row($_) } @open ], \@ITEM_R) if @open;
    }
    $out;
}
sub velocity_text {
    my ($s, %o) = @_;
    my $v = velocity($s, %o);
    my $out = '';
    for my $team (sorted(keys %{ $v->{team} })) {
        my @rows = map { [ $_->{sprint}, $_->{capacity} || '', $_->{committed}, $_->{done}, $_->{committed} ? int(100 * $_->{done} / $_->{committed} + 0.5) . '%' : '' ] } @{ $v->{team}{$team} };
        $out .= sprintf("%s  (avg velocity %.1f over last %d completed)\n", $team, $v->{avg}{$team}, $o{last} // 3)
              . _table([ 'Sprint', 'Cap', 'Commit', 'Done', 'Done%' ], \@rows, [ 0 .. 4 ]) . "\n";
    }
    $out;
}
sub backlog_text {
    my ($s, $scope) = @_;
    my @it = backlog($s, $scope);
    my $name = (!$scope || lc $scope eq 'master') ? 'Master' : $scope;
    sprintf("%s backlog: %d tasks, %d SP\n", $name, scalar @it, sum(map { $_->{points} } @it))
      . _table(\@ITEM_HDR, [ map { _item_row($_) } @it ], \@ITEM_R);
}
sub members_text {
    my ($s, $team) = @_;
    my $m = members($s, $team);
    my $out = '';
    for my $name (sorted(keys %$m)) {
        my $r = $m->{$name};
        $out .= sprintf("%s (%s)  WIP %d SP in %d tasks, done this sprint %d, queued %d\n", $name, $r->{team} // '-', $r->{wip_points},
                        scalar @{ $r->{wip} }, scalar @{ $r->{done} }, scalar @{ $r->{backlog} });
        for my $k (qw(wip done backlog)) {
            $out .= "  $k:\n" . join('', map { sprintf "    %-10s %3d  %s\n", $_->{id}, $_->{points}, $_->{title} } @{ $r->{$k} }) if @{ $r->{$k} };
        }
    }
    my @un = unassigned($s, $team);
    $out .= "UNASSIGNED committed tasks: " . join(', ', map { $_->{id} } @un) . "\n" if @un;
    $out;
}
sub _notes_text {                             # today's stand-up material, from Standup::day_notes
    my ($s, $d) = @_;
    return '' unless $d;
    my $out = '';
    for my $team (sorted(keys %{ $d->{teams} })) {
        my $t = $d->{teams}{$team};
        my @l;
        push @l, "done today: @{ $t->{done} }"      if @{ $t->{done} };
        push @l, "carried: @{ $t->{carry} }"        if @{ $t->{carry} };
        push @l, "removed: @{ $t->{drop} }"         if @{ $t->{drop} };
        push @l, "new: " . join(', ', @{ $t->{new} }) if @{ $t->{new} };
        push @l, "refined into the backlog: @{ $t->{refine} }" if $t->{refine} && @{ $t->{refine} };
        push @l, "pruned: " . join('; ', @{ $t->{prune} })  if $t->{prune} && @{ $t->{prune} };
        push @l, "absent: @{ $t->{absent} }"        if @{ $t->{absent} };
        push @l, map { "note: $_" } @{ $t->{note} };
        push @l, map { "risk: $_" } @{ $t->{risk} };
        $out .= "$team today:\n" . join('', map { "  $_\n" } @l) if @l;
    }
    $out .= "Notes:\n" . join('', map { "  $_\n" } @{ $d->{notes} }) if @{ $d->{notes} };
    $out .= "Risks:\n" . join('', map { "  $_\n" } @{ $d->{risks} }) if @{ $d->{risks} };
    $out .= "\n$d->{extra}" if $d->{extra};                # flags / AI assessment supplied by daily.pl
    $out;
}
sub email_text {
    my ($s, $n, %o) = @_;
    my $r = sprint_summary($s, $n);
    my $t = $r->{totals};
    my $u = $s->{unit} // 'SP';
    my $out = sprintf("Sprint %s status as of %s: %d/%d %s done (%d%%), %d open, %d carried over.\n\n", $r->{sprint}, $s->{today}, $t->{done}, $t->{committed}, $u, $t->{pct}, $t->{open}, $t->{carryover});
    for my $team (sorted(keys %{ $r->{teams} })) {
        my $x = $r->{teams}{$team};
        $out .= sprintf("%s: %d/%d done (%d%%), %d open%s\n", $team, $x->{done}, $x->{committed}, $x->{pct}, $x->{open},
                        defined $x->{load} ? ", load $x->{load}% of capacity" : '');
        $out .= "  open: " . join(', ', map { "$_->{id} ($_->{points})" } @{ $x->{open_items} }) . "\n" if @{ $x->{open_items} };
        my @bl = blocked($s, $team);
        $out .= "  BLOCKED: " . join('; ', map { "$_->{id} $_->{blocked}" } @bl) . "\n" if @bl;
    }
    my $notes = _notes_text($s, $o{notes});
    $out .= "\n$notes" if $notes;
    marked_text($o{marking}, $out);
}

# ---------------------------------------------------------------- brief: the BLUF-format leadership mail (one sentence + <=5 bullets, nothing else if the sprint is clean)
my %EMAIL_COLOR = (good => '#0ca30c', warning => '#c98500', critical => '#d03b3b');   # darker steps than the dashboard's -- these sit on white, not the dashboard surface
sub brief_status {                            # -> (red|amber|green, one-line headline or '' if green)
    my ($s, $n) = @_;
    my $r = sprint_summary($s, $n);
    my @bl = blocked($s);
    my @critical = grep { _load_status($r->{teams}{$_}{load}) eq 'critical' } sorted(keys %{ $r->{teams} });
    my @at_risk  = grep { _load_status($r->{teams}{$_}{load}) ne 'good' } sorted(keys %{ $r->{teams} });
    my @un = unassigned($s);
    return ('red',   sprintf('%d blocker%s, %d team%s over capacity', scalar(@bl), @bl == 1 ? '' : 's', scalar(@critical), @critical == 1 ? '' : 's'))
        if @bl >= 2 || @critical;
    return ('amber', @bl ? "1 blocker: $bl[0]{id} ($bl[0]{team}) $bl[0]{blocked}" : @at_risk ? "$at_risk[0] approaching capacity" : scalar(@un) . ' committed task(s) unassigned')
        if @bl || @at_risk || @un;
    ('green', '');
}
sub brief_subject {                           # a subject line you can read status from without opening the mail
    my ($s, $n) = @_;
    my $r = sprint_summary($s, $n);
    my ($level, $headline) = brief_status($s, $n);
    sprintf '[%s] Sprint %s, %s: %d%% done%s', uc($level), $r->{sprint}, $s->{today}, $r->{totals}{pct}, $headline ? ", $headline" : '';
}
sub _brief_bullets {                          # -> up to 5 plain-text action items, most important first
    my ($s, $r) = @_;
    my @out;
    push @out, sprintf('%s at %d%% load', $_, $r->{teams}{$_}{load}) for sort { $r->{teams}{$b}{load} <=> $r->{teams}{$a}{load} or $a cmp $b }
        grep { _load_status($r->{teams}{$_}{load}) eq 'critical' } sorted(keys %{ $r->{teams} });
    push @out, sprintf('%s (%s) blocked: %s', $_->{id}, $_->{team}, $_->{blocked}) for blocked($s);
    push @out, sprintf('%s approaching capacity (%d%%)', $_, $r->{teams}{$_}{load}) for sort { $r->{teams}{$b}{load} <=> $r->{teams}{$a}{load} or $a cmp $b }
        grep { _load_status($r->{teams}{$_}{load}) eq 'warning' } sorted(keys %{ $r->{teams} });
    my @un = unassigned($s);
    push @out, scalar(@un) . ' committed task(s) unassigned' if @un;
    my $extra = @out > 5 ? scalar(@out) - 5 : 0;
    ([ @out[ 0 .. ($extra ? 4 : $#out) ] ], $extra);
}
sub brief_text {                              # plain-text BLUF mail: one sentence, <=5 bullets, nothing else on a clean sprint
    my ($s, $n, %o) = @_;
    my $r = sprint_summary($s, $n);
    my ($level, $headline) = brief_status($s, $n);
    my $out = sprintf "%s -- Sprint %s, %s: %d%% done. %s\n", uc($level), $r->{sprint}, $s->{today}, $r->{totals}{pct}, $headline || 'On track, no blockers.';
    my ($bullets, $extra) = _brief_bullets($s, $r); my @bullets = @$bullets;
    $out .= "\n" . join('', map { "- $_\n" } @bullets) if @bullets;
    $out .= "  (+$extra more -- see the full status report)\n" if $extra;
    marked_text($o{marking}, $out);
}
sub brief_html {                              # the same BLUF mail as HTML: one colored word, one sentence, <=5 bullets -- inline styles + text only, no tables/fixed widths so it reflows on a phone; nothing to render wrong in Outlook desktop or mobile
    my ($s, $n, %o) = @_;
    my $r = sprint_summary($s, $n);
    my ($level, $headline) = brief_status($s, $n);
    my $color = $EMAIL_COLOR{ $level eq 'red' ? 'critical' : $level eq 'amber' ? 'warning' : 'good' };
    my $html = "<div style=\"font-family:Segoe UI,Arial,sans-serif;font-size:16px;line-height:1.5;max-width:480px\">\n";
    $html .= sprintf '<p style="margin:0 0 10px"><span style="display:inline-block;background:%s;color:#fff;font-weight:bold;padding:3px 10px;border-radius:4px;font-size:15px">%s</span></p>' . "\n",
        $color, uc($level);
    $html .= sprintf '<p style="margin:0 0 12px"><b>Sprint %s, %s: %d%% done.</b><br>%s</p>' . "\n",
        $r->{sprint}, $s->{today}, $r->{totals}{pct}, _h($headline || 'On track, no blockers.');
    my ($bullets, $extra) = _brief_bullets($s, $r); my @bullets = @$bullets;
    if (@bullets) {
        $html .= "<ul style=\"margin:0 0 8px;padding-left:22px\">\n" . join('', map { '<li style="margin-bottom:6px">' . _h($_) . "</li>\n" } @bullets) . "</ul>\n";
        $html .= '<p style="color:#888;font-size:13px;margin:0">+' . $extra . " more &mdash; see the full status report</p>\n" if $extra;
    }
    marked_mail_html($o{marking}, $html . "</div>\n");
}

# ---------------------------------------------------------------- markings (optional banner + block on reports, mail, PDF)
# $marking = { banner => 'INTERNAL', marking_owner => ..., marking_category => ..., marking_handling => ..., marking_poc => ... }
sub marking_lines {                           # the marking block under the banner (text lines); empty unless a banner is set
    my $c = shift;
    return () unless $c && $c->{banner};
    my @l;
    push @l, "Owner: $c->{marking_owner}"          if $c->{marking_owner};
    push @l, "Category: $c->{marking_category}"    if $c->{marking_category};
    push @l, "Handling: $c->{marking_handling}"    if $c->{marking_handling};
    push @l, "POC: $c->{marking_poc}"              if $c->{marking_poc};
    @l;
}
sub marked_text { my ($c, $body) = @_; return $body unless $c && $c->{banner}; my $b = "$c->{banner}\n"; "$b\n$body\n" . join('', map { "$_\n" } marking_lines($c)) . "\n$b" }
my $LOGO;                                     # assets/logo.svg, if the project supplies one, inlined (no src=, so the pages stay self-contained); letter counters may use currentColor
sub logo_svg {                                # -> '<svg class="logo" ...>...</svg>' or '' when the asset is absent
    return $LOGO if defined $LOGO;
    (my $f = __FILE__) =~ s{[/\\][^/\\]+$}{};
    $f .= '/../assets/logo.svg';
    $LOGO = '';
    if (open my $fh, '<', $f) { local $/; my $x = <$fh>; close $fh;
        if ($x =~ m{<svg[^>]*viewBox="([^"]+)"[^>]*>(.*)</svg>}s) { my ($vb, $body) = ($1, $2); $body =~ s/\s+/ /g; $body =~ s/ opacity="1\.000000"//g; $body =~ s/(\d+\.\d{2})\d+/$1/g;
            $LOGO = qq{<svg class="logo" viewBox="$vb" role="img" aria-label="logo">$body</svg>} } }
    $LOGO;
}
sub mark_banner_html {                         # $pos is top|bottom: in print (PDF) the CSS pins each to its page edge so the banner repeats on every page
    my ($c, $pos) = @_;
    return '' unless $c && $c->{banner};
    $pos //= 'top';
    '<p style="text-align:center;font-weight:bold;font-family:Arial,sans-serif" class="mark mark-' . $pos . '">' . _h($c->{banner}) . "</p>\n";
}
sub mark_block_html  { my $c = shift; $c && $c->{banner} && marking_lines($c) ? '<p style="font-family:Arial,sans-serif;font-size:12px" class="mark-block">' . join('<br>', map { _h($_) } marking_lines($c)) . "</p>\n" : '' }
sub marked_mail_html      { my ($c, $body) = @_; mark_banner_html($c, 'top') . $body . mark_block_html($c) . mark_banner_html($c, 'bottom') }   # mail: short, indicator at the end
sub marked_page_html { my ($c, $body) = @_; mark_banner_html($c, 'top') . mark_block_html($c) . $body . mark_banner_html($c, 'bottom') }   # documents: indicator on the first page
sub subject { my ($c, $text) = @_; ($c && $c->{subject_prefix} ? "$c->{subject_prefix} " : '') . $text }
my $MARK_PRINT_CSS = '@page{margin:16mm 12mm}@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{background:#fff;padding-top:26px;padding-bottom:26px}'
  . 'p.mark{position:fixed;left:0;right:0;margin:0;padding:2px 0;background:#fff;text-align:center}p.mark-top{top:0}p.mark-bottom{bottom:0}'
  . 'details:not([open])>*:not(summary){display:block !important}details{break-inside:avoid}}';
sub marking_check {                           # -> problems: "error: ..." must stop a send, "warn: ..." is advisory
    my ($c, %o) = @_;                         # banner (any text, e.g. INTERNAL) turns marking on; mail_domains (comma list) restricts where mail may go
    my @p;
    my $b = $c->{banner} // '';
    if ($b ne '') {
        push @p, "warn: marking_owner is empty -- say who owns the marked material" unless defined $c->{marking_owner} && $c->{marking_owner} =~ /\S/;
        push @p, "warn: marking_poc is empty -- say who to ask about it" unless defined $c->{marking_poc} && $c->{marking_poc} =~ /\S/;
        push @p, "warn: subject_prefix is empty while a banner is set -- mail subjects will not carry the marking" unless ($c->{subject_prefix} // '') =~ /\S/;
    }
    my @dom = grep { /\S/ } split /[,\s]+/, ($c->{mail_domains} // '');
    if (@dom) {
        for my $a (grep { /\S/ } map { split /[;,\s]+/, $_ } grep { defined } @{ $o{recipients} // [] }) {
            push @p, "error: recipient $a is outside mail_domains (" . join(', ', @dom) . ")" unless grep { $a =~ /[.@]\Q$_\E$/i } @dom;
        }
    }
    @p;
}

# ---------------------------------------------------------------- HTML rendering
sub _h { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
sub _htable {                                # _htable(\@header, \@rows, \@right_cols, $caption)
    my ($h, $rows, $right, $caption) = @_;
    my %r = map { $_ => 1 } @{ $right // [] };
    my $cell = sub { my ($tag, $i, $v) = @_; "<$tag" . ($r{$i} ? ' class="n"' : '') . '>' . _h($v) . "</$tag>" };
    "<table>\n" . (defined $caption ? '<caption>' . _h($caption) . "</caption>\n" : '') . "<tr>" . join('', map { $cell->('th', $_, $h->[$_]) } 0 .. $#$h) . "</tr>\n"
      . join('', map { my $row = $_; "<tr>" . join('', map { $cell->('td', $_, $row->[$_]) } 0 .. $#$h) . "</tr>\n" } @$rows) . "</table>\n";
}
sub _bar { my ($pct, $w) = @_; $w //= 140; $pct = 100 if $pct > 100;
    qq(<span class="bar" style="width:${w}px"><span style="width:$pct%"></span></span> <b>$pct%</b>) }
my %CHIP_ICON = (good => '&#10003;', warning => '&#9679;', serious => '&#9650;', critical => '&#10007;');
sub _chip { my ($level, $text) = @_; qq(<span class="chip $level">$CHIP_ICON{$level} ) . _h($text) . '</span>' }
sub _load_chip {                              # load% -> plain text (<=100), warning (100-110), critical (>110)
    my $load = shift;
    return '' unless defined $load;
    return _chip('critical', "$load% load") if $load > 110;
    return _chip('warning',  "$load% load") if $load > 100;
    "$load%";
}
sub _tile { my ($n, $label, $class) = @_; qq(<div class="tile$class"><div class="n">) . _h($n) . qq(</div><div class="l">) . _h($label) . '</div></div>' }
my $CSS = <<'CSS';
:root{--surface:#ffffff;--page:#f4f4f5;--ink:#0b0b0b;--ink2:#4a4a4c;--muted:#808082;
--grid:#e4e4e7;--baseline:#c9c9cc;--border:rgba(11,11,11,.10);
--navy:#27235d;--gold:#e6af22;--lblue:#aac1d7;--lgrey:#e4e4e7;--blue:var(--navy);--good:#0ca30c;--warning:#fab219;--serious:#ec835a;--critical:#d03b3b}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;color:var(--ink);background:var(--page);margin:0;padding:14px 18px;max-width:1900px}
h1{font-size:19px;margin:0 0 2px}
h2{font-size:15px;border-bottom:2px solid var(--ink);margin:18px 0 6px;padding-bottom:3px}
h3{font-size:13px;margin:10px 0 4px;color:var(--ink2)}
.muted{color:var(--muted)}
table{border-collapse:collapse;margin:4px 0 10px;width:100%;background:var(--surface);font-size:12px}
caption{caption-side:top;text-align:left;font-weight:600;color:var(--ink2);padding:2px 0 3px;font-size:11.5px}
.rm td.a{background:var(--blue);color:#fff;text-align:center;font-size:10.5px;font-variant-numeric:tabular-nums}
.rm td.c{background:#b7d3f6;text-align:center;font-size:10.5px;font-variant-numeric:tabular-nums}
.rm td.f{background:repeating-linear-gradient(135deg,#dcd9cf 0 3px,#f7f6f2 3px 7px)}
.rm td.cur,.rm th.cur{box-shadow:inset 0 0 0 2px var(--ink)}
.rm tr.tome td{background:var(--olive);color:#fff;font-weight:600}
th,td{border:1px solid var(--grid);padding:3px 7px;text-align:left;vertical-align:top}
th{background:var(--lgrey);font-weight:600}td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
tr:nth-child(even) td{background:#f5f4f0}
.cols{display:flex;gap:20px;flex-wrap:wrap}.cols>div{flex:1 1 280px}
.tiles{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 4px}
.tile{flex:1 1 105px;background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:6px 10px}
.tile .n{font-size:20px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}
.tile .l{font-size:10px;color:var(--ink2);text-transform:uppercase;letter-spacing:.03em}
.tile.critical .n{color:var(--critical)}.tile.warning .n{color:#9a6300}
.bar{display:inline-block;height:10px;background:var(--grid);vertical-align:middle;border-radius:5px;overflow:hidden}
.bar span{display:block;height:100%;background:var(--blue)}
.warn{color:var(--critical);font-weight:bold}
.chip{display:inline-block;padding:1px 7px;border-radius:9px;font-weight:600;font-size:10.5px;white-space:nowrap}
.chip.good{background:var(--good);color:#fff}.chip.warning{background:var(--warning);color:var(--ink)}
.chip.serious{background:var(--serious);color:var(--ink)}.chip.critical{background:var(--critical);color:#fff}
.attn{border:1px solid var(--border);border-radius:6px;background:var(--surface);padding:2px 12px;margin:6px 0 6px}
.attn .loadrow{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:6px 0;font-size:11.5px}
.attn .loadrow .chip{margin-right:2px}
.attn h2{margin:8px 0 2px}
.attn table{margin:4px 0}.attn p.ok{color:var(--ink2);padding:4px 0;font-size:12px}
details{border:1px solid var(--grid);border-radius:6px;margin:4px 0;background:var(--surface)}
details>summary{cursor:pointer;padding:5px 10px;font-weight:600}
details>summary::-webkit-details-marker{display:none}
details>table{margin:0 10px 10px;width:calc(100% - 20px)}
.topbar{display:flex;justify-content:space-between;align-items:baseline;flex-wrap:wrap;gap:10px;border-bottom:1px solid var(--grid);padding-bottom:6px;margin-bottom:0}
.topbar h1 svg.logo{height:22px;width:auto;color:#fff;vertical-align:-3px;margin-right:12px}
.topbar h1{margin:0}
.topbar .badges{display:flex;gap:8px;flex-wrap:wrap}
.ticker{color:var(--ink2);font-size:11.5px;margin:5px 0 2px;font-variant-numeric:tabular-nums}
.grid-wrap{display:flex;gap:8px;align-items:flex-start;margin:4px 0}
.section-label{writing-mode:vertical-rl;transform:rotate(180deg);font-size:10px;letter-spacing:.08em;color:var(--muted);font-weight:700;text-transform:uppercase;padding:4px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:8px;flex:1}
.card{border:1px solid var(--border);border-left:4px solid var(--baseline);border-radius:7px;background:var(--surface);padding:8px 10px}
.card.status-good{border-left-color:var(--good)}
.card.status-warning{border-left-color:var(--warning)}
.card.status-critical{border-left-color:var(--critical)}
.card-head{display:flex;justify-content:space-between;align-items:center;gap:6px;margin-bottom:1px}
.card-head h3{margin:0;font-size:13px}
.card-desc{margin:1px 0 5px;font-size:11px;color:var(--ink2)}
.facts{list-style:none;margin:5px 0;padding:0;font-size:11px;color:var(--ink2)}
.facts li{padding:0}
.tags{display:flex;flex-wrap:wrap;gap:3px;margin:6px 0 1px}
.tag{background:#eceae2;color:var(--ink2);border-radius:4px;padding:1px 6px;font-size:10px;font-weight:600}
.card details{border:0;background:transparent;margin:5px 0 0;border-radius:0}
.card details>summary{padding:2px 0;font-size:11px;font-weight:600;color:var(--blue)}
.card details>table{margin:4px 0 0;width:100%;font-size:10.5px}
.card details>table td,.card details>table th{padding:2px 5px}
CSS

# ---------------------------------------------------------------- per-member task cards (sent before / at the start of the stand-up)
sub member_card {                             # member_card($s, $name, last_b => 'text') -> text
    my ($s, $name, %o) = @_;
    my $m = members($s)->{$name} or return undef;
    my $u = $s->{unit} // 'SP';
    my $out = "$name - sprint $s->{current}" . ($m->{team} ? " ($m->{team})" : '') . "\n";
    $out .= "In progress (" . scalar(@{ $m->{wip} }) . ", $m->{wip_points} $u):\n";
    $out .= sprintf("  %-10s %3s  %s%s\n", $_->{id}, $_->{points}, $_->{title}, $_->{blocked} ? "   [BLOCKED: $_->{blocked}]" : '') for @{ $m->{wip} };
    $out .= "  (nothing committed)\n" unless @{ $m->{wip} };
    $out .= "Done this sprint: " . join(', ', map { $_->{id} } @{ $m->{done} }) . "\n" if @{ $m->{done} };
    $out .= "Queued: " . join(', ', map { "$_->{id} ($_->{points})" } @{ $m->{backlog} }) . "\n" if @{ $m->{backlog} };
    $out .= "Yesterday's blocker: $o{last_b}\n" if $o{last_b};
    $out .= "Reply in the meeting chat:  Y: <yesterday>  T: <today>  B: <blocker or none>\n";
    $out;
}
sub cards_text { my ($s, %o) = @_; join "\n", map { member_card($s, $_, %{ $o{last_b} && $o{last_b}{$_} ? { last_b => $o{last_b}{$_} } : {} }) } sorted(keys %{ members($s, $o{team}) }) }
sub teams_chat_link {                         # deep link that opens a 1:1 Teams chat with the message pre-filled (you press Send)
    my ($email, $text) = @_;
    (my $enc = $text) =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord $1)/ge;
    "https://teams.microsoft.com/l/chat/0/0?users=$email&message=$enc";
}
sub messages_html {                           # messages_html($s, $title, [ { who, text, email } ], marking => $conf): one page, a "send in Teams 1:1" link per person
    my ($s, $title, $msgs, %o) = @_;        # the link opens a private chat with the text pre-filled; you press Send. Nothing is posted by the kit.
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>" . _h($title) . " $s->{today}</title><style>$CSS pre{white-space:pre-wrap;background:#f7f7f7;padding:8px;border:1px solid #ddd;margin:2px 0 10px}
h3{margin:14px 0 2px}a.send{font-size:12px;font-weight:600;margin-left:10px}</style></head><body>\n";
    $html .= mark_banner_html($o{marking}, 'top') . mark_block_html($o{marking}) . "<h1>" . logo_svg() . _h($title) . " <span class=muted>$s->{today}</span></h1>\n";
    $html .= "<p class=muted>Each link opens a private 1:1 Teams chat with the message filled in; press Send there. The meeting chat stays clean; only the two of you see it.</p>\n";
    my $known = grep { $_->{email} } @$msgs;
    for my $m (@$msgs) {
        $html .= "<h3>" . _h($m->{who}) . ($m->{email} ? ' <a class=send href="' . _h(teams_chat_link($m->{email}, $m->{text})) . '">send in Teams (1:1)</a>' : ' <span class=muted>(no e-mail known: add to roster.txt)</span>') . "</h3>\n<pre>" . _h($m->{text}) . "</pre>\n";
    }
    $html .= sprintf "<p class=muted>e-mail known for %d/%d</p>\n", $known, scalar @$msgs;
    $html . mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}
sub cards_html {                              # one page: a card per member with a "Send in Teams" link when an e-mail is known
    my ($s, %o) = @_;
    my $emails = $o{emails} // {};
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Stand-up cards $s->{today}</title><style>$CSS pre{white-space:pre-wrap;background:#f7f7f7;padding:8px;border:1px solid #ddd}$MARK_PRINT_CSS</style></head><body>\n";
    $html .= mark_banner_html($o{marking}, 'top') . mark_block_html($o{marking}) . "<h1>Stand-up cards <span class=muted>$s->{today}</span></h1>\n";
    for my $name (sorted(keys %{ members($s, $o{team}) })) {
        my $card = member_card($s, $name, %{ $o{last_b} && $o{last_b}{$name} ? { last_b => $o{last_b}{$name} } : {} });
        my $mail = $emails->{$name};
        $html .= "<h3>" . _h($name) . ($mail ? ' <a href="' . _h(teams_chat_link($mail, $card)) . '">send in Teams</a>' : ' <span class=muted>(no e-mail known)</span>') . "</h3>\n<pre>" . _h($card) . "</pre>\n";
    }
    $html . mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}

# ---------------------------------------------------------------- planning tree: tome/epic/team (integration) and team/sprint/epic (task distribution)
sub team_plan {                               # -> { team => { sprint => { epic => [items] }, backlog => { epic => [items] } } }
    my $s = shift;
    my %plan;
    for my $it (values %{ $s->{items} }) {
        next unless $it->{team};
        my $epic = $it->{meta}{epic} // '(none)';
        if    ($it->{state} eq 'committed' || $it->{state} eq 'carryover') { push @{ $plan{ $it->{team} }{sprint}{$epic} }, $it }
        elsif ($it->{state} eq 'backlog')                                  { push @{ $plan{ $it->{team} }{backlog}{$epic} }, $it }
    }
    \%plan;
}
my @TREE_ITEM_HDR = ('ID', 'SP', 'Prio', 'Owner', 'Age', 'Title', 'Blocked');
sub _tree_item_row { my $it = shift; [ $it->{id}, $it->{points}, $it->{meta}{prio} // '', $it->{owner} // '', $it->{age}, $it->{title}, $it->{blocked} // '' ] }
sub _epic_group_html {                        # a <details> per epic with its item table, used by both tree views
    my ($epic, $items, %o) = @_;
    my $hot  = grep { $_->{blocked} } @$items;
    my $tome = (grep { defined && length } map { $_->{meta}{tome} } @$items)[0];
    sprintf "<details%s><summary>%s <span class=muted>%s</span>%s</summary>\n%s</details>\n",
        $hot ? ' open' : '', _h(defined $tome ? "$tome > $epic" : $epic), sprintf('%d task%s, %d %s', scalar(@$items), @$items == 1 ? '' : 's', sum(map { $_->{points} } @$items), $o{unit}),
        $hot ? ' ' . _chip('serious', "$hot blocked") : '',
        _htable(\@TREE_ITEM_HDR, [ map { _tree_item_row($_) } @$items ], [ 1, 2, 4 ], 'Tasks' . ($o{team} ? ": $o{team}" : '') . ($o{scope} ? ", $o{scope}" : ''));
}
sub _integration_tree_html {                  # tome -> epic -> team breakdown: where an epic touching >1 team is the coordination signal
    my $s = shift;
    my @ep = epics($s);
    my $html = '';
    my %by_tome;
    push @{ $by_tome{ $_->{tome} } }, $_ for @ep;
    for my $tome (sorted(keys %by_tome)) {
        $html .= "<details open><summary><b>" . _h($tome) . "</b> <span class=muted>" . scalar(@{ $by_tome{$tome} }) . " epics</span></summary>\n";
        for my $e (@{ $by_tome{$tome} }) {
            my %by_team;
            push @{ $by_team{ $_->{team} // '(unassigned)' } }, $_ for @{ $e->{items} };
            my $nteams = scalar keys %by_team;
            $html .= sprintf "<details style=\"margin-left:16px\"><summary>%s <span class=muted>%d%% done &middot; %d/%d/%d done/wip/backlog</span>%s</summary>\n",
                _h($e->{epic}), $e->{pct}, $e->{done}, $e->{wip}, $e->{backlog}, ($e->{open} ? ' ' . _chip('good', 'OPEN') : '') . $nteams > 1 ? ' ' . _chip('warning', "$nteams teams &mdash; integration point") : '';
            $html .= "<table><caption>Teams: " . _h("$tome > $e->{epic}") . "</caption><tr><th>Team</th><th class=n>Tasks</th><th class=n>SP</th><th class=n>Done SP</th></tr>\n";
            for my $team (sorted(keys %by_team)) {
                my @it = @{ $by_team{$team} };
                my $done = sum(map { my $it = $_; sum(map { $it->{bal}{$_} } grep { /:Done$/ } keys %{ $it->{bal} }) } @it);
                $html .= sprintf "<tr><td>%s</td><td class=n>%d</td><td class=n>%d</td><td class=n>%d</td></tr>\n", _h($team), scalar(@it), sum(map { $_->{points} } @it), $done;
            }
            $html .= "</table></details>\n";
        }
        $html .= "</details>\n";
    }
    $html || '<p class=muted>no epics yet</p>';
}
sub _team_tree_html {                         # team -> this sprint (by epic) + backlog (by epic): the working set for planning/distributing tasks
    my $s = shift;
    my $plan = team_plan($s);
    my $u = $s->{unit} // 'SP';
    my $html = '';
    for my $team (@{ $s->{teams} }) {
        my $p = $plan->{$team} // {};
        my $sp = $p->{sprint} // {}; my $bl = $p->{backlog} // {};
        my $sp_n = sum(map { scalar @$_ } values %$sp) || 0;
        my $bl_n = sum(map { scalar @$_ } values %$bl) || 0;
        $html .= sprintf "<details open><summary><b>%s</b> <span class=muted>%d in sprint &middot; %d in backlog</span></summary>\n", _h($team), $sp_n, $bl_n;
        $html .= "<h3>This sprint, by epic</h3>\n" . (%$sp ? join('', map { _epic_group_html($_, $sp->{$_}, unit => $u, team => $team, scope => 'this sprint') } sorted(keys %$sp)) : '<p class=muted>nothing committed</p>');
        $html .= "<h3>Backlog, by epic</h3>\n" . (%$bl ? join('', map { _epic_group_html($_, $bl->{$_}, unit => $u, team => $team, scope => 'backlog') } sorted(keys %$bl)) : '<p class=muted>empty</p>');
        $html .= "</details>\n";
    }
    $html;
}
sub tree_html {                               # the planning tree: integration perspective (tome/epic/team) + team perspective (team/sprint-backlog/epic)
    my ($s, %o) = @_;
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Planning tree</title><style>$CSS$MARK_PRINT_CSS</style></head><body>\n";
    $html .= mark_banner_html($o{marking}, 'top') . mark_block_html($o{marking});
    $html .= "<div class=topbar>\n<h1>" . logo_svg() . "Planning tree <span class=muted>&middot; $s->{today} &middot; " . _h($s->{file}) . "</span></h1>\n"
            . "<div class=badges>" . _chip('good', scalar(@{ $s->{teams} }) . ' teams') . _chip('good', scalar(epics($s)) . ' epics') . "</div>\n</div>\n";
    $html .= "<h2>Integration view <span class=muted>tome &rarr; epic &rarr; team</span></h2>\n<p class=muted>An epic touching more than one team is a coordination point &mdash; flagged below.</p>\n" . _integration_tree_html($s);
    $html .= "<h2>Team view <span class=muted>team &rarr; sprint / backlog &rarr; epic</span></h2>\n<p class=muted>What each team is committed to now and what's queued, grouped for planning and assignment.</p>\n" . _team_tree_html($s);
    $html . mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}

sub _tags_html { my %seen; join '', map { $seen{$_}++ ? () : qq(<span class="tag">) . _h($_) . '</span>' } grep { defined && length } map { $_->{meta}{epic} } @_ }
sub _load_status { my $load = shift; return 'good' unless defined $load; $load > 110 ? 'critical' : $load > 100 ? 'warning' : 'good' }  # single threshold, used everywhere
my @CARD_ITEM_HDR = ('ID', 'SP', 'Title', 'Blocked');
sub _card_item_row { my $it = shift; [ $it->{id}, $it->{points}, $it->{title}, $it->{blocked} // '' ] }
my $CARD_TPL = <<'HTML';
<div class="card status-%s">
  <div class="card-head"><h3>%s</h3>%s</div>
  <p class="card-desc">%d/%d %s done (%d%%) &middot; %d open</p>
  %s
  <ul class="facts"><li>Cap <b>%s</b> &middot; Commit <b>%d</b> &middot; Carry <b>%d</b> %s</li></ul>
  <div class="tags">%s</div>
  <details%s><summary>%d open tasks</summary>%s</details>
</div>
HTML
sub _team_card {
    my ($team, $x, $u) = @_;
    my @open   = @{ $x->{open_items} };
    my $hot    = grep { $_->{blocked} } @open;
    my $status = $hot ? 'critical' : _load_status($x->{load});
    my $badge  = $hot ? "$hot BLOCKED" : defined $x->{load} ? "$x->{load}% LOAD" : 'ON TRACK';
    sprintf($CARD_TPL, $status, _h($team), _chip($status, $badge), $x->{done}, $x->{committed}, $u, $x->{pct}, scalar(@open),
        _bar($x->{pct}), $x->{capacity} || '&ndash;', $x->{committed}, $x->{carryover}, $u, _tags_html(@open),
        $status eq 'critical' ? ' open' : '', scalar(@open),
        @open ? _htable(\@CARD_ITEM_HDR, [ map { _card_item_row($_) } @open ], [1], "Tasks: $team, this sprint") : '<p class=muted>none</p>');
}
sub _sprint_html {
    my ($s, $n) = @_;
    my $r = sprint_summary($s, $n);
    my $u = $s->{unit} // 'SP';
    my $html = "<h2>Sprint $r->{sprint}</h2>\n<div class=\"grid-wrap\"><div class=\"section-label\">SPRINT TEAMS</div>\n<div class=\"grid\">\n";
    $html .= _team_card($_, $r->{teams}{$_}, $u) for sorted(keys %{ $r->{teams} });
    $html .= "</div></div>\n";
    my $t = $r->{totals};
    $html .= sprintf "<p class=muted>Total &middot; %d/%d %s done (%d%%) &middot; %d open &middot; capacity %s &middot; load %s</p>\n",
        $t->{done}, $t->{committed}, $u, $t->{pct}, $t->{open}, $t->{capacity} || '&ndash;', defined $t->{load} ? "$t->{load}%" : '&ndash;';
    $html;
}
# ---------------------------------------------------------------- roadmap: epics by tome across sprints, actuals from the postings, forecast from velocity
sub _ceil { my $x = shift; my $i = int($x); $x > $i ? $i + 1 : $i }
sub roadmap {                                 # -> { sprints => [lo..hi], current, epics => [ { tome, epic, teams, first, last, end, done, total, remaining, pct, forecast_sprints, velocity, blocked, per_sprint => { N => { committed, done } } } ] }
    my $s = shift;                            # (memoised per loaded journal: the roadmap page, the dashboard and the cockpit all ask)
    return $s->{_memo}{roadmap} //= _roadmap($s);
}
sub _roadmap {
    my $s = shift;
    my $v = velocity($s);
    my $cur = $s->{current};
    my @rows;
    for my $e (epics($s)) {
        my (%ps, %teams, $blocked);
        for my $it (@{ $e->{items} }) {
            $teams{ $it->{team} }++ if $it->{team} && $it->{team} ne 'Master';
            $blocked++ if $it->{blocked} && ($it->{state} eq 'committed' || $it->{state} eq 'carryover');
            for my $h (@{ $it->{history} }) {
                next unless $h->{points} > 0 && $h->{account} =~ /^Sprint:(\d+):[^:]+:(Committed|Done)$/;
                $ps{$1}{ lc $2 } += $h->{points};
            }
        }
        my @sn = sort { $a <=> $b } keys %ps;
        my $remaining = $e->{wip} + $e->{backlog};
        my $vel = sum(map { $v->{avg}{$_} // 0 } keys %teams);
        my $fc  = $remaining <= 0 ? 0 : $vel > 0 ? _ceil($remaining / $vel) : undef;   # undef: no velocity yet, cannot forecast
        my $end = $remaining <= 0 ? $sn[-1] : (defined $fc && defined $cur ? $cur + $fc : undef);
        push @rows, { tome => $e->{tome}, epic => $e->{epic}, teams => [ sorted(keys %teams) ], first => $sn[0], last => $sn[-1], end => $end,
                      done => $e->{done}, total => $e->{total}, remaining => $remaining, pct => $e->{pct},
                      forecast_sprints => $fc, velocity => $vel, blocked => $blocked || 0, per_sprint => \%ps };
    }
    my @bounds = grep { defined } (map { ($_->{first}, $_->{end}) } @rows), $cur;
    my @sp = @bounds ? (minimum(@bounds) .. maximum(@bounds)) : ();
    { sprints => \@sp, current => $cur, epics => \@rows };
}
sub roadmap_text {
    my $s = shift;
    my $r = roadmap($s);
    my @sp = @{ $r->{sprints} };
    return "no sprints yet\n" unless @sp && @{ $r->{epics} };
    my $cur = $r->{current};
    my $out = sprintf "Roadmap: epics by tome, sprints %d-%d%s\n", $sp[0], $sp[-1], defined $cur ? " (current $cur; past it is a forecast at the teams' velocity)" : '';
    $out .= "  # done  = in progress  . forecast  ^ current sprint\n";
    my @rows = map { [ "$_->{tome} > $_->{epic}", $_ ] } @{ $r->{epics} };
    my $w = maximum(map { length $_->[0] } @rows);
    $out .= sprintf("%-*s  %s\n", $w, '', join('', map { defined $cur && $_ == $cur ? '^' : ' ' } @sp));
    for my $row (@rows) {
        my ($label, $e) = @$row;
        my $bar = join '', map {
            my $p = $e->{per_sprint}{$_};
            $p && $p->{done} ? '#' : $p && $p->{committed} ? '=' : (defined $e->{end} && defined $cur && $_ > $cur && $_ <= $e->{end}) ? '.' : ' '
        } @sp;
        my $eta = $e->{remaining} <= 0 ? 'done' : defined $e->{end} ? "ETA sprint $e->{end}" : 'no velocity yet';
        $out .= sprintf "%-*s  %s  %3d%%  %d/%d SP  %s%s\n", $w, $label, $bar, $e->{pct}, $e->{done}, $e->{total}, $eta, $e->{blocked} ? "  BLOCKED $e->{blocked}" : '';
    }
    $out;
}
sub roadmap_html {                            # one page: rows = tome > epic, columns = sprints; solid = done, light = in progress, striped = forecast
    my ($s, %o) = @_;
    my $r = roadmap($s);
    my @sp = @{ $r->{sprints} };
    my $cur = $r->{current};
    my $u = $s->{unit} // 'SP';
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Roadmap</title><style>$CSS$MARK_PRINT_CSS</style></head><body>\n";
    $html .= mark_banner_html($o{marking}, 'top') . mark_block_html($o{marking});
    $html .= "<div class=topbar>\n<h1>" . logo_svg() . "Roadmap <span class=muted>&middot; $s->{today} &middot; " . _h($s->{file}) . "</span></h1>\n<div class=badges>"
        . _chip('good', scalar(@{ $r->{epics} }) . ' epics') . (defined $cur ? _chip('good', "sprint $cur") : '') . "</div>\n</div>\n";
    if (!@sp || !@{ $r->{epics} }) { return $html . "<p class=muted>no sprints yet</p>\n" . mark_banner_html($o{marking}, 'bottom') . "</body></html>\n" }
    $html .= sprintf "<p class=muted>Sprints %d&ndash;%d. Solid = %s done in that sprint, light = in progress, striped = forecast (remaining %s &divide; the owning teams' 3-sprint velocity; optimistic, since it assumes their whole velocity). Nothing here is typed: it is derived from the journal's postings.</p>\n", $sp[0], $sp[-1], $u, $u;
    $html .= "<table class=rm><caption>Epics by tome: roadmap</caption>\n<tr><th>Tome &gt; Epic</th><th>Teams</th>"
        . join('', map { sprintf '<th class="n%s">%d</th>', (defined $cur && $_ == $cur ? ' cur' : ''), $_ } @sp)
        . "<th class=n>Done</th><th class=n>Left</th><th>ETA</th></tr>\n";
    my $last_tome = '';
    for my $e (@{ $r->{epics} }) {
        if ($e->{tome} ne $last_tome) {
            my @in = grep { $_->{tome} eq $e->{tome} } @{ $r->{epics} };
            $html .= sprintf "<tr class=tome><td colspan=\"%d\">%s <span class=muted>&middot; %d epic%s &middot; %d/%d %s done</span></td></tr>\n",
                scalar(@sp) + 5, _h($e->{tome}), scalar(@in), @in == 1 ? '' : 's', sum(map { $_->{done} } @in), sum(map { $_->{total} } @in), $u;
            $last_tome = $e->{tome};
        }
        $html .= '<tr><td>' . _h($e->{epic}) . ($e->{blocked} ? ' ' . _chip('serious', "$e->{blocked} blocked") : '') . '</td><td class=muted>' . _h(join(', ', @{ $e->{teams} })) . '</td>';
        for my $n (@sp) {
            my $p = $e->{per_sprint}{$n};
            my $cls = $p && $p->{done} ? 'a' : $p && $p->{committed} ? 'c' : (defined $e->{end} && defined $cur && $n > $cur && $n <= $e->{end}) ? 'f' : '';
            $cls .= ' cur' if defined $cur && $n == $cur;
            my $txt = $p && $p->{done} ? $p->{done} : $p && $p->{committed} ? $p->{committed} : '';
            $html .= $cls ? qq(<td class="$cls">$txt</td>) : '<td></td>';
        }
        my $eta = $e->{remaining} <= 0 ? 'done' : defined $e->{end} ? "sprint $e->{end}" : 'no velocity yet';
        $html .= sprintf "<td class=n>%d%%</td><td class=n>%d</td><td>%s</td></tr>\n", $e->{pct}, $e->{remaining}, _h($eta);
    }
    $html .= "</table>\n";
    $html . mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}
sub _attention_html {                          # "what needs the architect's attention today" — surfaced above the raw tables
    my ($s, $r) = @_;
    my @item_rows;                              # blocked/unassigned: real ID + owner, worth a table
    for my $b (blocked($s)) { push @item_rows, [ _chip('serious', 'Blocked'), _h($b->{id}), _h($b->{team} // ''), _h($b->{owner} // ''), _h($b->{blocked}) ] }
    for my $u (unassigned($s)) { push @item_rows, [ _chip('warning', 'Unassigned'), _h($u->{id}), _h($u->{team} // ''), '', 'committed with no owner' ] }
    my @load_teams;                             # team-level load: no ID/owner exists, doesn't belong in an item table
    if ($r) {
        for my $team (sorted(keys %{ $r->{teams} })) {
            my $st = _load_status($r->{teams}{$team}{load});
            push @load_teams, [ $team, $r->{teams}{$team}{load}, $st ] if $st ne 'good';
        }
    }
    my $n = @item_rows + @load_teams;
    return "<div class=\"attn\"><h2 style=\"border:0;margin-top:14px\">Needs attention</h2><p class=ok>Nothing flagged &mdash; no blockers, no unassigned commitments, no team over 100% load.</p></div>\n" unless $n;
    my $html = "<div class=\"attn\"><h2 style=\"border:0;margin-top:14px\">Needs attention <span class=muted>($n)</span></h2>\n";
    $html .= "<table><caption>Tasks needing a decision</caption><tr><th></th><th>ID</th><th>Team</th><th>Owner</th><th>Detail</th></tr>\n"
           . join('', map { '<tr><td>' . join('</td><td>', @$_) . "</td></tr>\n" } @item_rows) . "</table>\n" if @item_rows;
    $html .= '<div class="loadrow">' . join('', map { _chip($_->[2], "$_->[0] $_->[1]%") } @load_teams) . "</div>\n" if @load_teams;
    $html . "</div>\n";
}
sub dashboard_html {
    my ($s, %o) = @_;
    my $n = $o{sprint} // $s->{current};
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Scrum dashboard</title><style>$CSS$MARK_PRINT_CSS</style></head><body>\n";
    $html .= mark_banner_html($o{marking}, 'top') . mark_block_html($o{marking});

    my $r = defined $n ? sprint_summary($s, $n) : undef;
    my @bl = blocked($s); my @un = unassigned($s);
    my @at_risk = $r ? (grep { _load_status($r->{teams}{$_}{load}) ne 'good' } keys %{ $r->{teams} }) : ();
    my $risk_worst = (grep { _load_status($r->{teams}{$_}{load}) eq 'critical' } @at_risk) ? 'critical' : 'warning';
    $html .= "<div class=topbar>\n<h1>" . logo_svg() . "Scrum dashboard <span class=muted>&middot; $s->{today} &middot; " . _h($s->{file}) . "</span></h1>\n<div class=badges>\n"
        . _chip(@bl || @un || @at_risk ? 'warning' : 'good', @bl || @un || @at_risk ? 'Needs attention' : 'On track')
        . _chip('good', scalar(@{ $s->{teams} }) . ' teams')
        . "</div>\n</div>\n";
    if ($r) {
        $html .= '<p class=ticker>Load: ' . join(' &middot; ', map {
            my $x = $r->{teams}{$_}; _h($_) . ': ' . (defined $x->{load} ? "$x->{load}%" : '&ndash;')
        } sorted(keys %{ $r->{teams} })) . "</p>\n";
    }
    $html .= "<div class=tiles>\n" . join('',
        _tile(scalar @{ $s->{teams} }, 'Teams', ''),
        ($r ? _tile("$r->{totals}{pct}%", 'Done', '') : ()),
        ($r ? _tile($r->{totals}{open}, 'Open ' . ($s->{unit} // 'SP'), '') : ()),
        _tile(scalar(@bl), 'Blocked', @bl ? ' warning' : ''),
        _tile(scalar(@un), 'Unassigned', @un ? ' warning' : ''),
        _tile(scalar(@at_risk), 'At-risk teams', @at_risk ? " $risk_worst" : ''),
    ) . "</div>\n";
    $html .= _attention_html($s, $r);
    $html .= _sprint_html($s, $n) if defined $n;

    my $v = velocity($s);
    $html .= "<h2>Velocity</h2>\n<table><caption>Teams: velocity</caption><tr><th>Team</th><th class=n>Avg</th><th class=n>Latest sprint</th><th class=n>Cap</th><th class=n>Commit</th><th class=n>Done</th><th class=n>Done%</th><th>Earlier sprints</th></tr>\n";
    for my $team (sorted(keys %{ $v->{team} })) {
        my @hist = @{ $v->{team}{$team} };
        my $latest = $hist[-1];
        my $pct = sub { $_[0]{committed} ? int(100 * $_[0]{done} / $_[0]{committed} + 0.5) : 0 };
        my $older = join(', ', map { "$_->{sprint}:" . $pct->($_) . '%' } @hist[ 0 .. $#hist - 1 ]);
        $html .= sprintf "<tr><td>%s</td><td class=n>%.1f</td><td class=n>%s</td><td class=n>%s</td><td class=n>%d</td><td class=n>%d</td><td class=n>%d%%</td><td class=muted>%s</td></tr>\n",
            _h($team), $v->{avg}{$team}, $latest->{sprint}, $latest->{capacity} || '&ndash;', $latest->{committed}, $latest->{done}, $pct->($latest), _h($older);
    }
    $html .= "</table>\n";

    my @ep = epics($s);
    $html .= "<h2>Epics</h2>\n" . _htable([ 'Tome', 'Epic', 'Tasks', 'Total', 'Done', 'In sprint', 'Backlog', 'Progress' ],
        [ map { [ $_->{tome}, $_->{epic}, scalar @{ $_->{items} }, $_->{total}, $_->{done}, $_->{wip}, $_->{backlog}, "$_->{pct}%" ] } @ep ], [ 2 .. 7 ], 'Epics by tome') if @ep;
    my @master = backlog($s);
    $html .= sprintf("<h2>Master backlog <span class=muted>%d tasks, %d SP</span></h2>\n<details><summary>show %d tasks</summary>\n%s</details>\n",
        scalar @master, sum(map { $_->{points} } @master), scalar @master, _htable(\@ITEM_HDR, [ map { _item_row($_) } @master ], \@ITEM_R, 'Tasks: master backlog'));
    $html .= "<h2>Team backlogs</h2>\n<div class=cols>\n";
    for my $team (@{ $s->{teams} }) {
        my @it = backlog($s, $team);
        $html .= sprintf("<div><details><summary>%s <span class=muted>%d tasks, %d SP</span></summary>\n%s</details></div>\n", _h($team), scalar @it, sum(map { $_->{points} } @it),
                         @it ? _htable(\@ITEM_HDR, [ map { _item_row($_) } @it ], \@ITEM_R, "Tasks: $team backlog") : '<p class=muted>empty</p>');
    }
    $html .= "</div>\n";

    my $m = members($s);
    $html .= "<h2>Members</h2>\n<table>\n<caption>Members: sprint " . ($n // '?') . "</caption>\n<tr><th>Member</th><th>Team</th><th class=n>WIP SP</th><th>In progress</th><th>Done this sprint</th><th>Queued</th></tr>\n";
    for my $name (sorted(keys %$m)) {
        my $r = $m->{$name};
        my $ids = sub { join(', ', map { _h("$_->{id} ($_->{points})") } @{ $_[0] }) || '<span class=muted>-</span>' };
        $html .= sprintf "<tr><td>%s</td><td>%s</td><td class=n>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
            _h($name), _h($r->{team} // ''), $r->{wip_points}, $ids->($r->{wip}), $ids->($r->{done}), $ids->($r->{backlog});
    }
    $html .= "</table>\n";
    $html .= mark_banner_html($o{marking}, 'bottom');
    $html . "</body></html>\n";
}
sub _email_dot { my $level = shift; qq(<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:$EMAIL_COLOR{$level};margin-right:5px"></span>) }
sub _email_stat {                             # one KPI cell: big number over a small label, colored top border -- table cells + inline styles only, no grid/flex/CSS vars (Outlook's Word engine ignores all three)
    my ($n, $label, $level) = @_;
    my $color = $level ? $EMAIL_COLOR{$level} : '#888';
    qq(<td style="border-top:3px solid $color;padding:8px 14px;text-align:center">)
      . qq(<div style="font-size:22px;font-weight:bold;color:) . ($level ? $color : '#222') . qq(">) . _h($n) . '</div>'
      . qq(<div style="font-size:10px;color:#666;text-transform:uppercase;letter-spacing:.03em">) . _h($label) . '</div></td>';
}
sub email_html {                              # compact: fits an Outlook window, inline styles + tables only (no CSS grid/flex/vars/<details> -- Outlook's Word rendering engine drops all of those silently)
    my ($s, $n, %o) = @_;
    my $r = sprint_summary($s, $n);
    my $t = $r->{totals};
    my $td = 'style="border:1px solid #bbb;padding:3px 8px"';
    my $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"';
    my $html = "<div style=\"font-family:Segoe UI,Arial,sans-serif;font-size:14px\">\n";
    my $u = $s->{unit} // 'SP';
    $html .= sprintf "<p><b>Sprint %s status as of %s:</b> %d of %d %s done (%d%%), %d open, %d carried over.</p>\n", $r->{sprint}, $s->{today}, $t->{done}, $t->{committed}, $u, $t->{pct}, $t->{open}, $t->{carryover};

    my @bl = blocked($s);
    my @at_risk = grep { _load_status($r->{teams}{$_}{load}) ne 'good' } keys %{ $r->{teams} };
    $html .= '<table style="border-collapse:collapse;margin-bottom:10px"><tr>'
        . _email_stat("$t->{pct}%", 'Done', undef)
        . _email_stat($t->{open}, "Open $u", undef)
        . _email_stat(scalar(@bl), 'Blocked', @bl ? 'critical' : 'good')
        . _email_stat(scalar(@at_risk), 'At-risk teams', @at_risk ? 'warning' : 'good')
        . "</tr></table>\n";

    $html .= "<table style=\"border-collapse:collapse\">\n<tr><th $td>Team</th><th $tdn>Committed</th><th $tdn>Done</th><th $tdn>Open</th><th $tdn>Done %</th><th $tdn>Load</th></tr>\n";
    for my $team (sorted(keys %{ $r->{teams} }), 'Total') {
        my $x = $team eq 'Total' ? $t : $r->{teams}{$team};
        my $level = $team eq 'Total' ? undef : _load_status($x->{load});
        my $load_cell = !defined $x->{load} ? ''
            : $level && $level ne 'good' ? qq(<span style="background:$EMAIL_COLOR{$level};color:#fff;padding:1px 6px;border-radius:3px;font-weight:bold">$x->{load}%</span>)
            : "$x->{load}%";
        my $name = $team eq 'Total' ? _h($team) : _email_dot($level) . _h($team);
        $html .= sprintf "<tr><td $td>%s</td><td $tdn>%d</td><td $tdn>%d</td><td $tdn>%d</td><td $tdn>%d%%</td><td $tdn>%s</td></tr>\n",
            $name, $x->{committed}, $x->{done}, $x->{open}, $x->{pct}, $load_cell;
    }
    $html .= "</table>\n";
    for my $team (sorted(keys %{ $r->{teams} })) {
        my @open = @{ $r->{teams}{$team}{open_items} };
        next unless @open;
        $html .= "<p><b>" . _h($team) . " still open:</b> " . join('; ', map { _h("$_->{id} $_->{title} ($_->{points} $u" . ($_->{owner} ? ", $_->{owner})" : ')')) } @open) . "</p>\n";
    }
    $html .= '<p style="background:#fdeeee;border-left:3px solid ' . $EMAIL_COLOR{critical} . ';padding:6px 10px;color:#b00"><b>Blocked:</b> ' . join('; ', map { _h("$_->{id} ($_->{team}) $_->{blocked}") } @bl) . "</p>\n" if @bl;
    my $notes = _notes_text($s, $o{notes});
    $html .= '<pre style="font-family:Segoe UI,Arial,sans-serif;white-space:pre-wrap">' . _h($notes) . "</pre>\n" if $notes;
    marked_mail_html($o{marking}, $html . "</div>\n");
}

# ---------------------------------------------------------------- Outlook (via PowerShell COM; Windows only)
sub outlook_script {                          # PowerShell that opens a draft; body read from $html_path
    my ($html_path, %o) = @_;
    my $q = sub { my $s = shift // ''; $s =~ s/'/''/g; "'$s'" };
    join "; ",
        '$o = New-Object -ComObject Outlook.Application',
        '$m = $o.CreateItem(0)',
        '$m.To = ' . $q->($o{to}),
        '$m.CC = ' . $q->($o{cc}),
        '$m.Subject = ' . $q->($o{subject}),
        '$m.HTMLBody = [IO.File]::ReadAllText(' . $q->($html_path) . ', [Text.Encoding]::UTF8)',
        '$m.Display()';
}
sub outlook_bulk_script {                     # many plain-text mails in one PowerShell run; send => 1 sends, else Display()
    my ($mails, %o) = @_;
    my $q = sub { my $s = shift // ''; $s =~ s/'/''/g; "'$s'" };
    join "; ", '$o = New-Object -ComObject Outlook.Application',
        map { ('$m = $o.CreateItem(0)', '$m.To = ' . $q->($_->{to}), '$m.Subject = ' . $q->($_->{subject}), '$m.Body = ' . $q->($_->{body}), $o{send} ? '$m.Send()' : '$m.Display()') } @$mails;
}
sub outlook_bulk {
    my ($mails, %o) = @_;
    my $rc = system('powershell.exe', '-NoProfile', '-Command', outlook_bulk_script($mails, %o));
    die "powershell.exe failed (is this Windows with Outlook installed?)\n" if $rc != 0;
    scalar @$mails;
}
sub outlook_draft {                           # outlook_draft(html => $html, to => 'a@b', cc => '', subject => '...')
    my %o = @_;
    my $dir  = $ENV{TEMP} // $ENV{TMP} // '/tmp';
    my $path = "$dir/scrum-mail-$$.html";
    open my $fh, '>:encoding(UTF-8)', $path or die "cannot write $path: $!\n";
    print $fh $o{html};
    close $fh;
    my $win = $path;
    if ($^O eq 'msys' || $^O eq 'cygwin') { chomp(my $w = `cygpath -w "$path" 2>/dev/null` // ''); $win = $w if $w }
    my $script = outlook_script($win, %o);
    my $rc = system('powershell.exe', '-NoProfile', '-Command', $script);
    die "powershell.exe failed (is this Windows with Outlook installed?)\n" if $rc != 0;
    $path;
}

# ---------------------------------------------------------------- CLI
sub run {
    my @argv = @_;
    require Getopt::Long;
    my %o = (file => $ENV{SCRUM_FILE} // 'scrum.txt', last => 3);
    Getopt::Long::GetOptionsFromArray(\@argv, 'f|file=s' => \$o{file}, 'to=s' => \$o{to}, 'cc=s' => \$o{cc}, 'subject=s' => \$o{subject},
        'last=i' => \$o{last}, 'text' => \$o{text}, 'today=s' => \$o{today}, 'o|out=s' => \$o{out}) or return 2;
    my $cmd = shift @argv // 'sprint';
    my $s = eval { load($o{file}, today => $o{today}) };
    if (!$s) { print STDERR $@; return 1 }
    my $n = $argv[0] && $argv[0] =~ /^\d+$/ ? shift @argv : $s->{current};
    if    ($cmd eq 'sprint')    { print sprint_text($s, $n) }
    elsif ($cmd eq 'velocity')  { print velocity_text($s, last => $o{last}) }
    elsif ($cmd eq 'backlog')   { print backlog_text($s, $argv[0]) }
    elsif ($cmd eq 'members')   { print members_text($s, $argv[0]) }
    elsif ($cmd eq 'epics')     { print epics_text($s) }
    elsif ($cmd eq 'items')     { my %f; $f{state} = $argv[0] if $argv[0]; $f{team} = $argv[1] if $argv[1];
                                  print _table([ @ITEM_HDR, 'State', 'Team' ], [ map { [ @{ _item_row($_) }, $_->{state}, $_->{team} // '' ] } items($s, %f) ], \@ITEM_R) }
    elsif ($cmd eq 'dashboard') { my $out = $o{out} // $argv[0] // 'dashboard.html';
                                  open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n"; print $fh dashboard_html($s); close $fh; print "wrote $out\n" }
    elsif ($cmd eq 'roadmap')   { if ($o{out}) { open my $fh, '>:encoding(UTF-8)', $o{out} or die "cannot write $o{out}: $!\n"; print $fh roadmap_html($s); close $fh; print "wrote $o{out}\n" }
                                  else { print roadmap_text($s) } }
    elsif ($cmd eq 'tree')      { my $out = $o{out} // $argv[0] // 'tree.html';
                                  open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n"; print $fh tree_html($s); close $fh; print "wrote $out\n" }
    elsif ($cmd eq 'email')     { print $o{text} ? email_text($s, $n) : email_html($s, $n) }
    elsif ($cmd eq 'draft')     { my $p = outlook_draft(html => email_html($s, $n), to => $o{to} // '', cc => $o{cc} // '',
                                                        subject => $o{subject} // "Sprint $n status $s->{today}"); print "draft opened (body: $p)\n" }
    elsif ($cmd eq 'check')     { printf "ok: %d items, teams %s, sprints %s\n", scalar keys %{ $s->{items} }, join('/', @{ $s->{teams} }), join('/', @{ $s->{sprints} }) }
    else { print STDERR "unknown command '$cmd' (sprint velocity backlog members epics roadmap items dashboard tree email draft check)\n"; return 2 }
    0;
}

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Scrum::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Scrum::$_"} == \&{"Prelude::$_"})
          && !(defined &{"Ledger::$_"}  && \&{"Scrum::$_"} == \&{"Ledger::$_"})
    } keys %Scrum::;
}

1;

__END__

=head1 NAME

Scrum - multi-team sprint and backlog tracking on a plain-text ledger

=head1 SYNOPSIS

    perl bin/scrum.pl -f scrum.txt sprint            # current sprint, all teams
    perl bin/scrum.pl -f scrum.txt sprint 41
    perl bin/scrum.pl -f scrum.txt velocity --last 4
    perl bin/scrum.pl -f scrum.txt backlog           # master backlog
    perl bin/scrum.pl -f scrum.txt backlog Alpha     # one team's backlog
    perl bin/scrum.pl -f scrum.txt members           # per-person WIP / done / queued
    perl bin/scrum.pl -f scrum.txt items committed Bravo
    perl bin/scrum.pl -f scrum.txt dashboard -o dashboard.html    # open in Edge
    perl bin/scrum.pl -f scrum.txt email 42          # HTML status mail on stdout
    perl bin/scrum.pl -f scrum.txt email 42 --text   # plain-text version
    perl bin/scrum.pl -f scrum.txt draft 42 --to leads@example.com --cc pm@example.com
    perl bin/scrum.pl -f scrum.txt check

Set C<SCRUM_FILE> to skip C<-f>. C<--today YYYY-MM-DD> overrides the clock
(ages, "as of" dates).

=head1 THE JOURNAL

One Ledger.pm file. Story points are a commodity (C<SP>; anything works), and
every task is identified by C<id:> metadata in the posting comment. Points move
between accounts as the task moves, so the journal is the audit trail and the
dashboard is derived from it.

    Backlog:Master                             product backlog
    Backlog:<Team>                             team backlog
    Sprint:<N>:<Team>:Committed                planned into a sprint
    Sprint:<N>:<Team>:Done | Carryover | Removed
    Equity:Intake                              balancing side of new tasks

    2026-08-03 Intake AUTH-101 Login page          ; payee after the id becomes the title
        Backlog:Master          5 SP   ; id: AUTH-101, prio: 1, epic: Auth
        Equity:Intake

    2026-08-05 Refinement
        Backlog:Master         -5 SP   ; id: AUTH-101
        Backlog:Alpha           5 SP   ; id: AUTH-101

    ~ Sprint 41                                    ; capacity per team, optional
        Alpha                  10 SP
        Bravo                  12 SP

    2026-08-10 Sprint 41 planning
        Backlog:Alpha          -5 SP   ; id: AUTH-101, owner: Bob
        Sprint:41:Alpha:Committed  5 SP   ; id: AUTH-101

    2026-08-21 Sprint 41 review
        Sprint:41:Alpha:Committed -5 SP   ; id: AUTH-101
        Sprint:41:Alpha:Done       5 SP   ; id: AUTH-101

Metadata keys: C<id> (required), C<prio> (number, lower first), C<epic>,
C<owner>, C<title>, C<team>. Later values override earlier ones, so
C<owner: Ann> on a mid-sprint posting reassigns the task. Metadata on the
transaction line applies to every posting in it.

Re-estimating: post the difference (C<Sprint:42:Alpha:Committed  3 SP ; id: X>
against C<Equity:Intake>). Splitting a task: give the pieces new ids.
Descoping: move to C<Removed>. Carryover: C<Committed -> Carryover> at review,
C<Carryover -> Sprint:N+1:...:Committed> at the next planning.

C<examples/scrum.txt> is a complete two-team, two-sprint journal.

=head1 WHAT YOU GET

=head2 sprint [N]

Per team: capacity, committed, done, open, carryover, removed, done %, and
load % (committed / capacity). Then each team's open items with owner and age.

    Sprint 42
    Team   Cap  Commit  Done  Open  Carry  Removed  Done%  Load%
    -----  ---  ------  ----  ----  -----  -------  -----  -----
    Alpha   12      13     0    13      0        0     0%   108%
    Bravo   12      13     8     5      0        0    62%   108%
    Total   24      26     8    18      0        0    31%   108%

=head2 velocity [--last N]

Committed vs done per sprint per team, and the average done over the last N
completed sprints. A sprint that still has open committed points is treated as
in progress and left out of the average.

=head2 backlog [Master|Team]

Items in that backlog sorted by C<prio> then age: id, points, prio, epic,
owner, age in days, title.

=head2 epics

Roll-up by C<tome:> and C<epic:> metadata: items, total points, done, in
sprint, backlog, done %. Points removed from scope are excluded from the total.

=head2 members [Team]

Each owner's WIP (committed items and points), items done this sprint, and
items queued in backlogs, plus a warning line for committed items with no
owner.

=head2 dashboard [-o file.html]

One self-contained HTML page: current sprint with progress bars, velocity per
team, master backlog, each team backlog, member table, unassigned warning. No
scripts, no external assets; opens from a file share in Edge and prints fine.

=head2 email [N] [--text] / draft [N] --to ... [--cc ...] [--subject ...]

C<email> writes a compact status message: headline, one table, and each
team's open items with owners. HTML uses inline styles only so Outlook renders
it; C<--text> gives a plain version for chat. C<draft> creates that mail as an
Outlook draft through PowerShell COM (C<Outlook.Application>) and displays it
for you to review and send; nothing is sent automatically, and no security
prompt fires for displaying a draft. Windows with Outlook only.

=head1 LIBRARY

    use Scrum;
    my $s = load('scrum.txt');                 # or load($file, today => '2026-09-01')

    $s->{teams}      # ['Alpha', 'Bravo']      $s->{sprints}   # [41, 42]     $s->{current}  # 42
    $s->{items}{'AUTH-101'}                    # { id, title, points, state, sprint, team, owner, age, meta, history, location }

    items($s, state => 'committed', team => 'Bravo')        # sorted by prio, then age
    items($s, owner => 'Bob');  items($s, epic => 'Auth')
    backlog($s); backlog($s, 'Alpha')
    sprint_summary($s, 42)     # { sprint, teams => { Alpha => { committed, done, open, carryover, removed, capacity, pct, load, open_items, carry_items } }, totals }
    velocity($s, last => 4)    # { team => { Alpha => [ { sprint, committed, done, capacity } ] }, avg => { Alpha => 8 } }
    members($s);  members($s, 'Alpha');  unassigned($s)

    sprint_text($s, 42)  velocity_text($s)  backlog_text($s, 'Alpha')  members_text($s)
    dashboard_html($s)   email_html($s, 42)  email_text($s, 42)
    outlook_draft(html => email_html($s, 42), to => 'leads@example.com', subject => 'Sprint 42')

Item states: C<master>, C<backlog>, C<committed>, C<done>, C<carryover>,
C<removed>, C<closed> (no points anywhere). Everything is plain hashes and
arrays, so anything not covered is a few lines of L<Prelude> over
C<items($s)>.

=head1 WORKFLOW

Planning day: add the C<~ Sprint N> capacity block and one planning
transaction per team. Stand-up: move finished tasks to C<Done> as they
close (one posting pair each). Review: sweep what is left to C<Carryover> or
C<Removed>. Then C<dashboard> for yourself, C<draft> for the leads, C<git
commit>.

=head1 SEE ALSO

L<Ledger>, L<Prelude>.

=cut
