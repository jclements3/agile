#!/usr/bin/perl
# drill-sim.pl -- stress tests for the memory drill (lib/Drill.pm): property checks over every card of real and hostile
# journals, then a simulated learner who drills for weeks while the journal changes under them.
#
#   perl sim/drill-sim.pl [--days 60] [--n 20] [--team T|all] [--seed N] [--project data/demo] [--verbose]
#
# Part 1, properties (every card of data/demo, data/history, examples/scrum.txt and a hostile journal: unicode and
# "Last, First" names, identical initials, one-word names, epics without codes, titles with pipes and quotes):
#   1. initials are unique (case-insensitive) and every card key is unique
#   2. the right answer grades ok -- as written, lower case, upper case, shuffled, comma-separated
#   3. a set answer missing one item is a miss naming it; one with an id from the deck added is a miss naming the extra
#   4. random garbage (unicode, punctuation, huge, empty) never dies or warns, and '?' / '' is never ok
#   5. a sheet answered right grades all ok; grading again changes nothing; hooks written survive a regrade
#   6. drill.txt round-trips exactly (pipes and newlines in answers and hooks are flattened, not lost)
# Part 2, a learner (recall probability rises with the Leitner box) drills --n cards a day for --days days on --project,
# one team's deck (--team, default the first team; 'all' for the whole program -- too big for 12 a day, by design);
# every few days the journal changes (a task reassigned, a new blocker, a new task in an epic). Checked every day:
#   7. every card recorded is due strictly after today, in box 0..5; a miss is always box 0, due tomorrow
#   8. a card whose answer changed comes back in the next pick marked changed, with the old answer as was
#   9. no card starves: every card is seen within ceil(cards / new-card quota) + 7 days of appearing in the deck (a third of each day is new cards)
#  10. the learner improves: the last week's accuracy beats the first week's
# Prints a summary (coverage, accuracy by week, the box histogram at the end) and exits 1 on any violation.
# Standalone, not part of the tested kit.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use File::Temp qw(tempdir);
use Prelude qw(show sorted);
use Scrum qw(load);
use Roster ();
use Drill;

my %o = (days => 60, n => 20, seed => 1, project => "$FindBin::Bin/../data/demo");
GetOptions(\%o, 'days=i', 'n=i', 'team=s', 'seed=i', 'project=s', 'verbose') or exit 2;
srand($o{seed});
my $root = "$FindBin::Bin/..";
my $tmp = tempdir(CLEANUP => 1);
my ($checks, @bad) = (0);
my @warn; local $SIG{__WARN__} = sub { push @warn, $_[0] };
sub ok { my ($cond, $what) = @_; $checks++; push @bad, $what unless $cond; print "FAIL $what\n" if !$cond && $o{verbose}; $cond }
sub any_of { $_[int rand @_] }
sub shuffle { my @a = @_; for (my $i = @a; --$i;) { my $j = int rand($i + 1); @a[$i, $j] = @a[$j, $i] } @a }
sub right { my $c = shift; $c->{mode} eq 'set' ? join(' ', @{ $c->{want} }) : $c->{want}[0] }

# ---------------------------------------------------------------- the hostile journal
my $hostile = "$tmp/hostile.txt";
{   my @p = ('Zoë Ångström', 'Archer, Sam', 'Sam Archer', 'Jo Chen', 'Jo Cole', 'Jo Chen-Cole', 'Bob', 'Bo', "O'Neil, Pat", 'Ann Lee', 'Ann Lee');
    my @t = ('Fix the | pipe', 'Say "hello" & wave', 'Ünïcödé title', 'a', 'Really long title ' x 8, 'C-3 mentions another id');
    my $j = '';
    my $i = 0;
    for my $who (@p) {
        $i++;
        my $e = $i % 3 ? "E$i Epic number $i" : 'Plain epic';
        $j .= sprintf "2026-09-01 Intake H-%d %s\n    Backlog:%s    %d SP   ; id: H-%d, epic: %s, tome: %s, owner: %s\n    Equity:Intake\n\n", $i, $t[ $i % @t ], ($i % 2 ? 'Alpha' : 'Beta Team'), $i, $i, $e, ($i % 2 ? 'T Tome' : 'Untitled tome'), $who;
    }
    $j .= "2026-09-02 Sprint 1 planning\n    Backlog:Alpha    -1 SP   ; id: H-1\n    Sprint:1:Alpha:Committed    1 SP   ; id: H-1, blocked: waiting on | vendor \"X\"\n\n";
    open my $fh, '>:encoding(UTF-8)', $hostile or die; print $fh $j; close $fh;
}

# ---------------------------------------------------------------- part 1: properties
my @journals = grep { -f $_->[1] } ([ 'demo', "$root/data/demo/scrum.txt" ], [ 'history', "$root/data/history/scrum.txt" ], [ 'examples', "$root/examples/scrum.txt" ], [ 'hostile', $hostile ]);
my @garbage = ('', ' ', '?', '??', '-', "\x{1F600}", 'A' x 5000, join(' ', map { chr(33 + int rand 94) } 1 .. 40), "\t\r\n", 'NULL undef 0 0.0', '| | |', '> hook: -', '#1 who:x');
my %card_count;
for my $jr (@journals) {
    my ($name, $file) = @$jr;
    my $s = load($file, today => '2026-09-26');
    my $roster = $name eq 'demo' && -f "$root/data/demo/roster.txt" ? Roster::read_roster("$root/data/demo/roster.txt") : [];
    my $cards = cards($s, roster => $roster);
    $card_count{$name} = scalar @$cards;
    my %people = map { $_ => 1 } map { @{ $_->{names} } } @$cards;
    my $ini = initials(keys %people);
    my %u; ok(!grep({ $u{ uc $_ }++ } values %$ini), "$name: initials unique");
    my %k; ok(!grep({ $k{ $_->{key} }++ } @$cards), "$name: card keys unique");
    my @deck = sorted(keys %{ $cards->[0]{vocab} // {} });
    for my $c (@$cards) {
        my $r = right($c);
        ok(grade($c, $r)->{ok}, "$name $c->{key}: right answer '$r'");
        ok(grade($c, lc $r)->{ok}, "$name $c->{key}: lower case");
        ok(grade($c, uc $r)->{ok}, "$name $c->{key}: upper case");
        if ($c->{mode} ne 'gist') {
            my @w = $c->{mode} eq 'set' ? @{ $c->{want} } : split ' ', $r;
            ok(grade($c, join(' ', shuffle(@w)))->{ok}, "$name $c->{key}: shuffled");
            ok(grade($c, join(', ', @w))->{ok}, "$name $c->{key}: commas");
        }
        if ($c->{mode} eq 'set') {
            if (@{ $c->{want} } > 1) {
                my @w = shuffle(@{ $c->{want} }); my $drop = shift @w;
                my $g = grade($c, join ' ', @w);
                ok(!$g->{ok} && (grep { $_ eq $drop } @{ $g->{missed} }), "$name $c->{key}: missing $drop is a miss naming it");
            }
            my %in = map { uc($_) => 1 } @{ $c->{want} };
            my @other = grep { !$in{$_} && !/ / } @deck;
            if (@other) { my $x = any_of(@other); my $g = grade($c, "$r $x"); ok(!$g->{ok} && (grep { $_ eq $x } @{ $g->{extra} }), "$name $c->{key}: extra $x is a miss naming it") }
        }
        for my $junk (map { any_of(@garbage) } 1 .. 2) {
            my $g = eval { grade($c, $junk) };
            ok($g, "$name $c->{key}: garbage did not die ($@)");
            ok(!$g->{ok}, "$name $c->{key}: blank/'?' is not ok") if $g && $junk =~ /^[\s?]*$/;
        }
    }
    # the sheet: answered right -> all ok; regrade is a no-op; a hook survives
    my @sample = (shuffle(@$cards))[0 .. ($#$cards < 24 ? $#$cards : 24)];
    my @picked = map { { %$_, status => 'new' } } @sample;
    my %by = map { $_->{key} => $_ } @$cards;
    my $sheet = sheet_text(\@picked, today => '2026-09-26');
    my $i = 0;
    my %ans = map { ++$i => right($_) } @picked;
    my $cur = 0;
    $sheet =~ s/^(#(\d+) .*\n.*\n)> $/do { $1 . '> ' . $ans{$2} }/mge;
    my $p = {};
    my ($g1, $st1) = grade_sheet($sheet, \%by, $p, '2026-09-26');
    ok($st1->{ok} == @picked && $st1->{miss} == 0, "$name: sheet answered right grades all ok ($st1->{ok}/" . scalar(@picked) . ")");
    my ($g2, $st2) = grade_sheet($g1, \%by, $p, '2026-09-26');
    ok($g2 eq $g1 && $st2->{graded} == 0, "$name: regrade is a no-op");
    (my $g3 = $g2) =~ s/^(#1 .*\n.*\n> .*\n= ok.*\n)/$1hook: a | pipe and a "quote"\n/m;
    my (undef, $st3) = grade_sheet($g3, \%by, $p, '2026-09-26');
    ok($st3->{hooks} == 1 && $p->{ $picked[0]{key} }{hook} eq 'a / pipe and a "quote"', "$name: hook saved, pipe flattened");
    # drill.txt round trip
    record($p, $_, rand() < 0.5, '2026-09-26') for @sample;
    $p->{ $sample[-1]{key} }{hook} = "multi\nline | hook";
    write_progress("$tmp/$name-drill.txt", $p);
    my $back = read_progress("$tmp/$name-drill.txt");
    ok(show($back->{ $sample[-1]{key} }{hook}) eq '"multi line / hook"', "$name: newline and pipe in a hook flattened");
    delete $_->{hook} for values %$back; my %p2 = map { $_ => { %{ $p->{$_} } } } keys %$p; delete $_->{hook} for values %p2;
    $_->{ans} =~ tr/|\n/\/ / for values %p2;
    ok(show($back) eq show(\%p2), "$name: drill.txt round-trips");
}

# ---------------------------------------------------------------- part 2: a learner over weeks, with the journal changing
my $pj = "$o{project}/scrum.txt";
my $s = load($pj, today => '2026-09-26');
my $roster = -f "$o{project}/roster.txt" ? Roster::read_roster("$o{project}/roster.txt") : [];
my $team = $o{team} // $s->{teams}[0];
$team = undef if $team eq 'all';
my $prog = {};
my (%appeared, %seen, %first_seen, @week_ok, @week_n, @events);
my $start = '2026-09-28';
my $day = 0;
my $pending_change;                            # [ key, old answer ] expected back as changed next day
my @owners = sorted(keys %{ { map { ($_->{owner} // '') => 1 } grep { $_->{owner} } values %{ $s->{items} } } });
for my $d (0 .. $o{days} - 1) {
    my $today = Drill::_add_days($start, $d);
    my $cards = cards($s, roster => $roster, team => $team);
    $appeared{ $_->{key} } //= $d for @$cards;
    my @pk = Drill::pick($cards, $prog, today => $today, n => $o{n});
    if ($pending_change) {
        my ($key, $was) = @$pending_change;
        my ($c) = grep { $_->{key} eq $key } @pk;
        ok($c && $c->{status} eq 'changed' && $c->{was} eq $was, "day $d: changed card $key back first, was '$was'");
        undef $pending_change;
    }
    for my $c (@pk) {
        my $r = $prog->{ $c->{key} };
        my $box = $r ? $r->{box} : 0;
        my $p_recall = $c->{status} eq 'changed' ? 0.5 : (0.35, 0.6, 0.75, 0.85, 0.92, 0.96)[$box];
        my $right = rand() < $p_recall;
        my $answer = $right ? right($c) : any_of('?', 'no idea', ($c->{mode} eq 'set' ? join(' ', @{ $c->{want} }[1 .. $#{ $c->{want} }]) : 'something else'));
        $answer = right($c) if $right;
        my $g = $answer =~ /^\s*\?\s*$/ ? { ok => 0 } : grade($c, $answer);
        ok($g->{ok} == ($right ? 1 : 0) || (!$right && $g->{ok}), "day $d $c->{key}: grade matches the learner") if $right;
        my $rec = record($prog, $c, $g->{ok}, $today);
        ok($rec->{due} gt $today && $rec->{box} >= 0 && $rec->{box} <= 5, "day $d $c->{key}: due after today, box in range");
        ok($rec->{box} == 0 && $rec->{due} eq Drill::_add_days($today, 1), "day $d $c->{key}: miss -> box 0, due tomorrow") unless $g->{ok};
        $first_seen{ $c->{key} } //= $d; $seen{ $c->{key} }++;
        $week_n[ int($d / 7) ]++; $week_ok[ int($d / 7) ] += $g->{ok} ? 1 : 0;
    }
    # the journal changes: every 5th day reassign a known task, every 7th block one, every 11th add a task to an epic
    if ($d % 5 == 4) {
        my ($it) = grep { $_->{owner} && $prog->{"task:$_->{id}"} && $_->{state} =~ /^(committed|backlog|master|carryover)$/ } map { $s->{items}{$_} } sorted(keys %{ $s->{items} });
        if ($it) {
            my $was = $prog->{"task:$it->{id}"}{ans};
            my ($new) = grep { $_ ne $it->{owner} } @owners;
            $it->{owner} = $it->{meta}{owner} = $new; delete $s->{_memo};
            $pending_change = [ "task:$it->{id}", $was ];
            push @events, "day $d: $it->{id} reassigned to $new";
        }
    }
    if ($d % 7 == 6) { my ($it) = grep { !$_->{blocked} && $_->{state} eq 'committed' } map { $s->{items}{$_} } sorted(keys %{ $s->{items} }); if ($it) { $it->{blocked} = 'simulated dependency'; $it->{blocked_since} = $today; delete $s->{_memo}; push @events, "day $d: $it->{id} blocked" } }
    if ($d % 11 == 10) {
        my ($e) = grep { defined } map { $_->{meta}{epic} } grep { $_->{state} eq 'backlog' } map { $s->{items}{$_} } sorted(keys %{ $s->{items} });
        if ($e) { my $id = "SIM-$d"; $s->{items}{$id} = { id => $id, title => "Simulated task $d", meta => { epic => $e, owner => $owners[0] }, state => 'backlog', team => (grep { ($_->{meta}{epic} // '') eq $e } values %{ $s->{items} })[0]{team}, owner => $owners[0], points => 3, age => 0, history => [], created => $today }; delete $s->{_memo}; push @events, "day $d: $id added to $e" }
    }
}
my $final = cards($s, roster => $roster, team => $team);
my $quota = $o{n} >= 3 ? int($o{n} / 3) : 1;
my $limit = int((@$final + $quota - 1) / $quota) + 7;
my @late = grep { my $a = $appeared{ $_->{key} } // $o{days}; $a + $limit < $o{days} && (!defined $first_seen{ $_->{key} } || $first_seen{ $_->{key} } - $a > $limit) } @$final;
ok(!@late, 'no card starves: each seen within ' . $limit . ' days of appearing' . (@late ? ' (' . scalar(@late) . ' not: ' . join(' ', map { $_->{key} } @late[0 .. ($#late < 4 ? $#late : 4)]) . ')' : ''));
my ($w1) = grep { $week_n[$_] } 0 .. $#week_n; my ($wl) = grep { $week_n[$_] && $week_n[$_] >= $o{n} * 5 } reverse 0 .. $#week_n;
ok($o{days} < 21 || (defined $wl && $week_ok[$wl] / $week_n[$wl] > $week_ok[$w1] / $week_n[$w1]), 'the learner improves week over week');
ok(!@warn, 'no warnings' . (@warn ? ": $warn[0]" : ''));

# ---------------------------------------------------------------- summary
my %box; $box{ $prog->{$_}{box} }++ for keys %$prog;
printf "drill-sim: %d checks, %d violations\n", $checks, scalar @bad;
printf "  properties: %s\n", join(', ', map { "$_ $card_count{$_} cards" } map { $_->[0] } @journals);
printf "  learner: %d days on %s%s, %d cards a day; deck %d cards, %d seen (%d%%), all by day %s\n", $o{days}, $o{project} =~ s{.*/data/}{data/}r, ($team ? " team $team" : ' (all teams)'), $o{n}, scalar @$final, scalar(keys %seen),
    100 * keys(%seen) / (@$final || 1), (sort { $b <=> $a } values %first_seen)[0] // '-';
printf "  accuracy by week: %s\n", join('  ', map { sprintf 'w%d %d%%', $_ + 1, 100 * ($week_ok[$_] // 0) / $week_n[$_] } grep { $week_n[$_] } 0 .. $#week_n);
printf "  boxes at the end: %s\n", join('  ', map { "box $_: " . ($box{$_} // 0) } 0 .. 5);
printf "  journal changes: %d (%s%s)\n", scalar @events, join('; ', @events[0 .. ($#events < 2 ? $#events : 2)]), @events > 3 ? '; ...' : '';
if (@bad) { my %k; print "  violation: $_\n" for grep { !$k{$_}++ } @bad[0 .. ($#bad < 9 ? $#bad : 9)]; exit 1 }
exit 0;
