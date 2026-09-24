#!/usr/bin/perl
# Training replay: runs one full two-week sprint against the demo project, for real --
# every daily.pl command and every git command actually executes -- narrated step by step
# as a solutions architect's day, and recorded into a playable HTML terminal animation.
#
# The product is DroneCorp, a notional racing-drone company: the ten-model IDEF0
# decomposition in tools/idef0/examples/dronecorp (fictional; no real company data).
# The backlog is derived from the model (sim/idef0-backlog.pl): model -> tome and team,
# level-1 activity -> epic, leaf activity -> task, cross-model interface -> an interface
# task in the destination team under the source epic. Teams, people and every task in the
# replay come from that compiled journal, not from a script.
#
#   perl sim/training.pl              # live, paced, in the terminal (Git Bash)
#   perl sim/training.pl --fast       # no pauses; still writes the HTML replay
#
# Runs against data/demo (reset to a clean `daily.pl init` first). Refuses to touch any
# directory not named "demo" unless --force is given: it wipes the journal.
# Standalone training tool -- not part of the tested kit. Pure core Perl, no CPAN.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Cwd qw(abs_path);
use File::Path qw(remove_tree make_path);
use Scrum qw(load items members);

my $KIT   = abs_path("$FindBin::Bin/..");
my $MODEL = "$KIT/tools/idef0/examples/dronecorp/dronecorp.md";
my %o = (dir => "$KIT/data/demo", html => "$KIT/docs/TRAINING.html", pause => 1.4, cap => 24);
GetOptions(\%o, 'dir=s', 'html=s', 'fast', 'force', 'pause=f', 'cap=i') or exit 2;
$o{pause} = 0 if $o{fast};
die "refusing to reset '$o{dir}': not named 'demo' (use --force)\n" unless $o{force} || $o{dir} =~ m{/demo/?$};

my @days   = ('2026-09-23', '2026-09-24', '2026-09-25', '2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06');
my @daynum = (1, 2, 3, 6, 7, 8, 9, 10, 13, 14);
my @wd     = qw(Wed Thu Fri Mon Tue Wed Thu Fri Mon Tue);
my @done_plan = (3, 6, 9, 8, 5, 9, 7, 'carry', 4, 10, 6, 'carry', 5, 8, 3, 9, 7, 11, 6, 'carry', 4, 8, 10, 5);   # workday a task is reported finished, cycled over the committed tasks

# ---------------------------------------------------------------- replay plumbing
my @rec;                                      # recorded steps for the HTML replay
my $today;
sub say  { my $t = shift; print "$t\n"; }
sub banner {
    my ($i, $title) = @_;
    my $b = sprintf "Day %d  %s %s  --  %s", $daynum[$i], $wd[$i], $days[$i], $title;
    print "\n", '=' x 78, "\n$b\n", '=' x 78, "\n";
    push @rec, { kind => 'day', text => $b };
}
sub narrate { my $t = shift; print "\n  $t\n"; push @rec, { kind => 'note', text => $t }; select(undef, undef, undef, $o{pause} * 0.6) if $o{pause} }
$ENV{$_} = q{Solutions Architect} for qw(GIT_AUTHOR_NAME GIT_COMMITTER_NAME); $ENV{$_} = q{sa@example.com} for qw(GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL);   # demo commits carry a neutral author
sub run {                                     # run($shown_command, $real_command, $max_lines) -> output; records both
    my ($shown, $real, $max) = @_;
    $real //= $shown;
    $max //= 28;
    print "\n\$ $shown\n";
    my $out = qx($real 2>&1);
    $out =~ s{\Q$KIT\E}{~/agile}g; $out =~ s{\b$ENV{USER}\b}{user}g if $ENV{USER};   # the recording is published: no local paths or user names
    my @l = split /\n/, $out;
    my $shown_out = @l > $max ? join("\n", @l[0 .. $max - 3]) . "\n... (" . (@l - $max + 2) . " more lines)" : $out;
    print $shown_out, "\n";
    push @rec, { kind => 'cmd', cmd => $shown, out => $shown_out };
    select(undef, undef, undef, $o{pause}) if $o{pause};
    $out;
}
sub daily { my ($cmd, $shown, $max) = @_; run($shown // "daily.pl $cmd", "perl \"$KIT/bin/daily.pl\" --today=$today $cmd", $max) }
sub write_file { my ($f, $t) = @_; open my $w, '>', $f or die "cannot write $f: $!\n"; print $w $t; close $w }
sub append_file { my ($f, $t) = @_; open my $w, '>>', $f or die "cannot append $f: $!\n"; print $w $t; close $w }
sub vim {                                     # a hand edit, shown as what you'd type in Vim
    my ($shown, $narration, $do) = @_;
    narrate($narration);
    print "\n  [vim] $shown\n";
    my $out = $do->() // '';
    print "$out\n" if $out;
    push @rec, { kind => 'vim', cmd => $shown, out => $out };
    select(undef, undef, undef, $o{pause}) if $o{pause};
}
sub head_tail { my ($t, $n) = @_; my @l = split /\n/, $t; @l <= $n ? $t : join("\n", @l[0 .. $n - 1]) . "\n... (" . (@l - $n) . " more lines)" }

# ---------------------------------------------------------------- reset the demo project
remove_tree($o{dir}) if -d $o{dir};
make_path($o{dir}); -d $o{dir} or die "cannot mkdir $o{dir}: $!\n";   # data/ itself is git-ignored, so a fresh clone has no parent directory
chdir $o{dir} or die "cannot chdir $o{dir}: $!\n";
say "Training replay: DroneCorp, one sprint, run for real in $o{dir}";
say "Every command below actually executes. Press Ctrl-C to stop." unless $o{fast};

# ================================================================ Day 1: the model, the backlog, planning
$today = $days[0];
banner(0, 'The model, the backlog, sprint planning');
narrate('A project is a directory. daily.pl init creates scrum.conf, an empty journal (scrum.txt), standups/, reports/, and a git repo.');
run('daily.pl init', "perl \"$KIT/bin/daily.pl\" init .");
vim('vim scrum.conf', 'Point the calendar at the offline fixture so nothing touches Outlook during training; an INTERNAL banner with owner and POC, and mail_domains so mail stays in the company.', sub {
    my $c = do { local $/; open my $r, '<', 'scrum.conf' or die; <$r> };
    $c =~ s/^to\s*=.*$/to        = leads\@example.com/m;
    $c =~ s/^(# calendar.*)$/$1\ncalendar          = mock\ncalendar_fixture  = $KIT\/examples\/cal-fixture.json/m;
    $c =~ s/^marking_owner\s*=.*$/marking_owner = ACME Program Office/m;
    $c =~ s/^marking_category\s*=.*$/marking_category      = CTI/m;
    $c =~ s/^marking_handling\s*=.*$/marking_handling = do not forward outside the program/m;
    $c =~ s/^marking_poc\s*=.*$/marking_poc           = S. Archer, Solutions Architect/m;
    write_file('scrum.conf', $c);
    "calendar = mock, to = leads\@example.com, marking_owner/category/distribution/poc filled";
});
narrate('daily.pl check validates the markings before anything leaves your desk: banner set with owner and POC, every recipient inside mail_domains.');
daily('check');

narrate('The product is DroneCorp, a notional racing-drone company: a ten-model IDEF0 decomposition, one model per department (tools/idef0/examples/dronecorp/dronecorp.md). Fictional, no real company data. The toolkit lints it and renders the plates; the plates are the design the teams build to. Research & Development is the architect\'s own department.');
run('idef0lint dronecorp.md', "perl \"$KIT/tools/idef0/idef0.pl\" lint \"$MODEL\"");
run('idef2html dronecorp.md > reports/plates.html', "perl \"$KIT/tools/idef0/idef0.pl\" html \"$MODEL\" > reports/plates.html && ls -l reports/plates.html");
narrate('The interface table is the architect\'s territory: every cross-model flow is a contract between two departments -- the Strategic Plan from Executive to every department, Spot Orders from Sales to Production, Delivery Orders from Sales to Logistics.');
run('idef0 links dronecorp.md | head -8', "perl \"$KIT/tools/idef0/idef0.pl\" links \"$MODEL\" | head -8");
vim(':SDocs grep -i "strategic plan" dronecorp.md', 'Specs and deliverables arrive as PDF and Word. bin/docs2txt.pl (:SDocs in Vim) reads them as text through the converters Git for Windows already ships -- pdftotext, docx2txt, antiword, odt2txt -- so a spec is grepped like the journal. Here it finds every mention of one interface flow in the model source.', sub {
    qx(perl "$KIT/bin/docs2txt.pl" grep -i "strategic plan" "$MODEL" 2>&1 | sed "s#.*/##" | head -8);
});
narrate('The backlog is derived from the model, not typed: model -> tome and team, level-1 activity -> epic, leaf activity -> task, cross-model link -> an interface task owned by the DESTINATION team under the SOURCE epic. That is what makes an epic span teams -- the tree will flag those as integration points. With --commit each team plans its top tasks up to capacity.');
vim('sim/idef0-backlog.pl dronecorp.md --cap ' . $o{cap} . ' --commit > standups/' . $today . '.txt', 'Sizes come from the decomposition depth (an undecomposed level-1 activity is 8, a deep leaf is 3); priorities likewise. Typed once, here, and never again.', sub {
    my $t = qx(perl "$KIT/sim/idef0-backlog.pl" "$MODEL" --cap $o{cap} --commit --date $today);
    write_file("standups/$today.txt", $t);
    my @l = split /\n/, $t;
    sprintf "%d lines: %d new, %d interface tasks, %d commit lines\n%s", scalar @l, scalar(grep { /^new / } @l), scalar(grep { /^new IF-/ } @l), scalar(grep { /^commit / } @l), head_tail($t, 10);
});
narrate('Always dry-run first: the compiler validates every line and shows the ledger postings it would append. A typo anywhere rejects the whole file.');
daily('--dry compile', 'daily.pl --dry compile', 22);
narrate(':SCompile -- the file is appended to the journal as double-entry postings and marked compiled. Points now sit in Backlog:<Team> or Sprint:1:<Team>:Committed; that account IS the state.');
daily('compile');
daily('status');
narrate('Epics by tome, straight from the model. The planning tree (reports/tree.html) shows the same hierarchy with the integration points flagged.');
daily('epics', undef, 44);
narrate('The roadmap: epics by tome across sprints. Nothing is done yet and there is no velocity, so no forecast -- by sprint 3 it will have one.');
daily('roadmap', undef, 44);
narrate('The reports are derived from the journal, never typed: dashboard, planning tree, roadmap, status mail, and the one-screen leadership brief.');
daily('report');
narrate('Commit the day. daily.pl commit is just git add -A + git commit; the journal and stand-up notes are the audit trail.');
daily('commit');
run('git log --oneline');

# ---------------------------------------------------------------- the world, read back from the compiled journal
my $s = load('scrum.txt', today => $today);
my @teams = @{ $s->{teams} };
my (%story, %people);
my $k = 0;
for my $it (sort { $a->{team} cmp $b->{team} || $a->{id} cmp $b->{id} } items($s, state => 'committed', sprint => 1)) {
    $story{ $it->{id} } = { team => $it->{team}, owner => $it->{owner}, pts => $it->{points}, title => $it->{title}, done_day => $done_plan[ $k++ % @done_plan ], finished => 0 };
}
$people{$_} = [ sort keys %{ members($s, $_) } ] for @teams;              # everyone on a team's roster answers, not just this sprint's task owners
my ($blk_id) = grep { /^IF-/ } sort keys %story;                          # the scripted blocker: an interface task waiting on its source team
my ($blk_flow, $blk_src) = $story{$blk_id}{title} =~ /^Interface: (.+) from (\w+) to \w+$/;
my $blk_who = $story{$blk_id}{owner};
$story{$blk_id}{done_day} = 9;                                            # blocked Days 3-7, unblocked Day 8, finished Day 9
my $silent_who = $people{ $teams[-1] }[0];                                # someone goes quiet on Day 9
my ($est_id) = grep { !/^IF-/ && ($story{$_}{done_day} eq 'carry' || $story{$_}{done_day} > 9) } sort keys %story;   # a task that grew: re-estimated in chat on Day 9, still open then
($est_id) = grep { !/^IF-/ } sort keys %story unless $est_id;
my $est_team = $story{$est_id}{team};
my %blocked_since;

# ================================================================ Days 2..13: the daily townhall
for my $i (1 .. 8) {
    $today = $days[$i];
    my $d = $daynum[$i];
    banner($i, $d == 3 || $d == 10 ? 'Townhall + weekly status mail' : $d == 8 ? 'Townhall + mid-sprint health check' : $d == 9 ? 'Townhall + refinement' : 'Townhall');

    narrate('08:15 -- daily.pl cards: each person gets their own card (their tasks, blockers, the Y/T/B reminder) before the call. The cards are the agenda.');
    daily('cards');
    run("head -9 reports/$today-cards.txt");

    # ---- the townhall chat (what people typed in Teams, 08:30-08:45)
    my $chat = "Meeting started\n";
    my ($h, $min) = (8, 31);
    for my $team (@teams) {
        for my $who (@{ $people{$team} // [] }) {
            next if $who eq $silent_who && $d == 9;
            my @mine = sort grep { $story{$_}{owner} eq $who } keys %story;
            my ($cur) = grep { !$story{$_}{finished} } @mine;
            my ($y, $t, $b) = ('', '', 'none');
            for my $id (@mine) {
                my $st = $story{$id};
                if (!$st->{finished} && $st->{done_day} ne 'carry' && $st->{done_day} <= $i + 1) { $y = "finished $id, merged"; $st->{finished} = 1; ($cur) = grep { !$story{$_}{finished} } @mine; last }
            }
            my @filler = ('code review', 'demo prep', 'refinement notes', 'pairing on the carryover');
            $y ||= $cur ? "worked on $cur" : $filler[ ($i - 1) % @filler ];
            $t = $cur ? "continue $cur" : $filler[ $i % @filler ];
            if ($who eq $blk_who) {
                if    ($d == 3)                 { $b = "waiting on $blk_src for the $blk_flow interface, $blk_id"; $blocked_since{$blk_id} = $i }
                elsif ($d >= 6 && $d <= 7)      { $b = "still waiting on $blk_src for $blk_flow, $blk_id" }
                elsif ($d == 8 && $blocked_since{$blk_id}) { $b = "$blk_flow arrived from $blk_src, unblocked"; delete $blocked_since{$blk_id} }
            }
            $chat .= sprintf "[%d:%02d AM] %s\nY: %s\nT: %s\nB: %s\n", $h, $min, $who, $y, $t, $b;
            if (++$min >= 60) { $min = 0; $h++ }
        }
    }
    if ($d == 9) {                                # refinement day: an estimate round in chat on a task that grew
        my @voters = @{ $people{$est_team} }[ 0 .. ($#{ $people{$est_team} } < 3 ? $#{ $people{$est_team} } : 3) ];
        $chat .= "[8:58 AM] JC\n#est $est_id $story{$est_id}{title} grew -- re-estimate\n" . join('', map { "[8:59 AM] $_\n8\n" } @voters);
    }
    narrate("08:30-08:45 -- the townhall. Everyone types Y/T/B into the one Teams chat; the chat is the record. Afterwards: select all, copy, paste into standups/$today-chat.txt (:SChat).");
    write_file("standups/$today-chat.txt", $chat);
    run("head -14 standups/$today-chat.txt");

    narrate(':SAnswers -- parses Y/T/B per person, splits them to teams by who owns what in the journal, logs attendance, and writes FLAGS: silent people, blockers, "done" claims. You read the flags, not the chat.');
    daily('answers', undef, 240);
    if ($d == 9) {
        narrate(':STally -- the #est round is tallied (consensus or median with outliers) and an est line is written into the stand-up file, ready if there was consensus.');
        daily('chat');
    }
    if ($d == 8) {
        narrate('Day 8 health check: load, blocked age, burn vs plan. daily.pl blocked is the escalation list; three days is your cue to act -- and an interface blocker is yours, not the team lead\'s.');
        daily('blocked');
        daily('sprint', undef, 16);
    }
    if ($d == 9) {
        my $s9 = load('scrum.txt', today => $today);
        my ($prune_id) = map { $_->{id} } sort { ($b->{meta}{prio} // 0) <=> ($a->{meta}{prio} // 0) || $a->{id} cmp $b->{id} } grep { $_->{id} !~ /^IF-/ } items($s9, state => 'backlog', team => $est_team);   # the team's lowest-priority backlog leaf
        vim('append refinement lines', "Refinement (Day 9): the architect writes an enabler into the MASTER backlog (== Master), $est_team pulls it with refine, and a stale leaf is pruned with a reason. Not committed -- sized and queued for planning.", sub {
            my $t = "\n; ---- refinement $today\n== Master\nnew M-1 5 Enabler: telemetry data contract spike p:1 e:\"A1 Enablers\" t:\"A Architectural runway\" o:\"JC\"\n== $est_team\nrefine M-1\n"
                  . ($prune_id ? "prune $prune_id superseded by the M-1 spike\n" : '');
            append_file("standups/$today.txt", $t);
            $t;
        });
    }
    narrate("What answers (and chat) appended to today's stand-up file -- suggestions, not decisions:");
    run("tail -12 standups/$today.txt") if -e "standups/$today.txt";
    vim('confirm the suggested lines (uncomment done / unblock)', 'The suggestions are commented out on purpose: you confirm a "done" claim or an unblock by uncommenting it. block lines apply as-is. absent stays commented until you have checked.', sub {
        my $f = "standups/$today.txt";
        qx(perl "$KIT/bin/daily.pl" --today=$today new 2>&1) unless -e $f;   # a quiet day: answers had nothing to suggest, so no file yet
        my $t = do { local $/; open my $r, '<', $f or die; <$r> };
        $t =~ s/^; (done|unblock) /$1 /mg;
        write_file($f, $t);
        my @kept = $t =~ /^((?:done|unblock|block|refine|prune|est) .*)$/mg;
        @kept ? join("\n", map { "  $_" } @kept) : '  (nothing to confirm today)';
    });
    narrate(':SCompile -- apply today. Done points move to Sprint:1:<Team>:Done; a block is a zero-point posting that flags the task until unblock.');
    daily('compile');
    narrate(':SReport -- dashboard, tree, roadmap, the status mail, and the brief regenerate from the journal. The brief is what leadership gets:');
    daily('report');
    run("cat reports/$today-brief.txt");
    if ($d == 3 || $d == 10) {
        narrate('Friday: the weekly mail to leadership is the same brief plus velocity and the blocked list. daily.pl draft / daily.pl brief open it in Outlook -- skipped here so training does not open a mail client.');
        daily('velocity', undef, 16);
        narrate('The quad is the one-page weekly status: Technical Priorities tagged TODO/OPEN/DONE/WAIT/HOLD/PUNT/DROP, Watch Items the PM must help with (PM) or know about (WI), Schedule Milestones 30/60/90 days out with pushed-right / pulled-left arrows against last week, and Accomplishments marked on time or late. report wrote it as reports/<date>-quad.html; this is the text form.');
        daily('quad', undef, 40);
    }
    narrate('Commit the day. One commit per townhall: the diff IS the history of what changed.');
    daily('commit');
    run('git log --oneline -3') if $d == 2 || $d == 8 || $d == 13;
    run('git show --stat HEAD | head -12') if $d == 6;
}

# ================================================================ Day 14: review, retro, close
$today = $days[9];
banner(9, 'Review / demo, retro, sprint close');
narrate('Review is the opposite of the townhall: 60-90 minutes, cameras on, demos against the plates. The journal entry for it is one done / carry sweep afterwards -- whatever is still committed goes to Done or Carryover. Partial credit does not exist.');
vim(':SNew then the review sweep', 'Anything still open is either done or carried, explicitly. Carryover is visible forever.', sub {
    qx(perl "$KIT/bin/daily.pl" --today=$today new 2>&1);
    my %left;
    for my $id (keys %story) { push @{ $left{ $story{$id}{team} } }, $id unless $story{$id}{finished} }
    my $t = '';
    for my $team (@teams) {
        my @done  = sort grep { $story{$_}{done_day} ne 'carry' } @{ $left{$team} // [] };
        my @carry = sort grep { $story{$_}{done_day} eq 'carry' } @{ $left{$team} // [] };
        $t .= "== $team\n" . (@done ? 'done ' . join(' ', @done) . "\n" : '') . (@carry ? 'carry ' . join(' ', @carry) . "\n" : '') if @done || @carry;
    }
    append_file("standups/$today.txt", "\n; ---- review sweep $today\n$t");
    $t;
});
daily('compile');
narrate('The sprint report: done vs committed per team, velocity, epic burn, and now a roadmap with a real forecast. All derived; nothing retyped.');
daily('sprint 1', undef, 16);
daily('velocity', undef, 16);
daily('roadmap', undef, 44);
daily('report');
run("cat reports/$today-brief.txt");
narrate('Close the sprint in git: commit and tag. git log of scrum.txt + standups/ is the audit trail your successor inherits.');
vim(':STig', 'Before the commit, review what the sprint appended: :STig opens tig (Git for Windows ships it) on the project -- j/k walk the commits, Enter shows the diff, q returns to Vim. tig is interactive so the replay shows the equivalent git log; the point is that you look before you commit.', sub {
    qx(git log --oneline --stat -3 2>&1 | head -16);
});
daily('commit');
run('git tag sprint-1');
run('git log --oneline --decorate');
run('git diff --stat $(git rev-list --max-parents=0 HEAD) sprint-1 | tail -3');
narrate('Next: Day 1 of sprint 2 is planning again -- cap lines, commit the carryover (commit ID finds it in last sprint\'s Carryover account), pull refined work from the backlog, including M-1. The rhythm repeats; the roadmap forecast tightens as velocity settles.');

# ================================================================ the HTML replay
write_html($o{html}, \@rec);
say "\nwrote $o{html}";

sub write_html {
    my ($path, $steps) = @_;
    my $esc = sub { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s };
    my $json = '[' . join(",\n", map {
        my $r = $_;
        my $j = sub { my $s = shift // ''; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\n/\\n/g; $s =~ s/<\/script/<\\\/script/gi; "\"$s\"" };
        '{"kind":' . $j->($r->{kind}) . ',"text":' . $j->($r->{text}) . ',"cmd":' . $j->($r->{cmd}) . ',"out":' . $j->($r->{out}) . '}'
    } @$steps) . ']';
    my $static = join '', map {
        $_->{kind} eq 'day'  ? '<h2>' . $esc->($_->{text}) . "</h2>\n"
      : $_->{kind} eq 'note' ? '<p class=note>' . $esc->($_->{text}) . "</p>\n"
      : '<pre class=term>' . ($_->{kind} eq 'vim' ? '<span class=vim>[vim] ' : '<span class=prompt>$ ') . $esc->($_->{cmd}) . "</span>\n" . $esc->($_->{out}) . "</pre>\n"
    } @$steps;
    my $logo = Scrum::logo_svg();
    my $html = <<"HTML";
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Training replay</title>
<style>
:root{--ink:#0b0b0b;--ink2:#4a4a4c;--muted:#808082;--grid:#e4e4e7;--surface:#ffffff;--page:#f4f4f5;--navy:#27235d;--gold:#e6af22;--blue:var(--navy);--good:#0ca30c}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;font-size:14px;color:var(--ink);background:var(--page);margin:0;padding:18px 22px;max-width:1100px}
h1{font-size:20px;margin:0 0 4px;color:var(--navy)}h1 svg.logo{height:24px;width:auto;color:#fff;vertical-align:-4px;margin-right:12px}h2{font-size:15px;margin:22px 0 6px;border-bottom:2px solid var(--navy);padding-bottom:3px}
a.doc{color:var(--navy);font-weight:600}
.muted{color:var(--muted)}.note{color:var(--ink2);margin:10px 0 6px;max-width:900px}
.term{background:#1a1a19;color:#e6e4dc;font-family:Consolas,"Courier New",monospace;font-size:12.5px;line-height:1.4;padding:10px 14px;border-radius:6px;white-space:pre-wrap;margin:4px 0 12px;min-height:1.6em}
.prompt{color:#7cc4ff;font-weight:bold}.vim{color:#8ee18a;font-weight:bold}
#ctl{position:sticky;top:0;background:var(--page);padding:8px 0;border-bottom:1px solid var(--grid);margin-bottom:8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
button{font:inherit;padding:4px 12px;border:1px solid var(--grid);background:var(--surface);border-radius:4px;cursor:pointer}
button.primary{background:var(--blue);color:#fff;border-color:var(--blue)}
#prog{flex:1;height:6px;background:var(--grid);border-radius:3px;overflow:hidden;min-width:120px}#prog div{height:100%;background:var(--blue);width:0}
#stage h2{margin-top:10px}
.static{display:none}
details.role{border:1px solid var(--grid);border-radius:6px;background:var(--surface);margin:10px 0 14px}
details.role>summary{cursor:pointer;padding:6px 12px}
.roletext{padding:0 14px 8px;max-width:900px}
.roletext table{border-collapse:collapse;margin:8px 0}.roletext th,.roletext td{border:1px solid var(--grid);padding:3px 8px;text-align:left}
</style></head><body>
<h1>$logo Training replay <span class=muted>&middot; DroneCorp, one sprint, run for real against data/demo</span></h1>
<p class=muted>Recorded from <code>sim/training.pl</code>: every command actually executed. Play it, or step through with the buttons / arrow keys. The hands-on companion is <a class=doc href="TUTORIAL.html">TUTORIAL.html</a>: updating the data in Vim (the same commands, explained verb by verb). Both are the Tutorial tab of the cockpit. Days are in the sprint calendar of WORKFLOW.html &sect;3. The product is DroneCorp, a notional racing-drone company modeled in IDEF0 (<code>tools/idef0/examples/dronecorp</code>); the backlog is derived from it.</p>

<details class=role open><summary><b>The role: what a Solutions Architect does</b></summary>
<div class=roletext>
<p>A Solutions Architect is the person who owns the technical shape of a whole solution across multiple
agile teams. They make the cross-cutting decisions no single team can make alone, and they keep those
decisions just far enough ahead of delivery that teams aren't blocked.</p>
<p>It sits between two other architecture roles:</p>
<table>
<tr><th>Role</th><th>Scope</th></tr>
<tr><td>Enterprise Architect</td><td>Portfolio-wide: technology strategy, standards, platforms</td></tr>
<tr><td><b>Solutions Architect</b></td><td>One solution, often a system of systems built by several teams or trains</td></tr>
<tr><td>System Architect</td><td>One system or team-of-teams (an Agile Release Train)</td></tr>
</table>
<p>What they do day to day:</p>
<ul>
<li><b>Intentional architecture:</b> they define the high-level structure, interfaces and non-functional
  requirements (performance, security, safety, certification) that let many teams build independently
  without integration collapse.</li>
<li><b>Architectural runway:</b> they make sure enough enabling infrastructure exists ahead of feature work,
  typically a few program increments out, but not a big design up front.</li>
<li><b>Enablers:</b> they write and prioritize technical backlog items (spikes, infrastructure, refactors)
  alongside business features.</li>
<li><b>Interfaces and integration:</b> they own the contracts between subsystems and suppliers. In an IDEF0
  model these are exactly the cross-model links, like DroneCorp's interface table.</li>
<li><b>Trade-offs:</b> they balance cost, schedule, risk and technical debt with product management and
  systems engineering.</li>
<li><b>Coaching, not dictating:</b> in agile the architecture emerges partly from teams, so they guide and
  negotiate rather than hand down finished designs.</li>
</ul>
<p>The agile distinction is that a traditional architect produces a complete design that teams then
implement. An agile Solutions Architect does "just enough, just in time": set the guardrails and
interfaces, then let design detail emerge in the teams.</p>
<p>In SAFe, the most common framework in aerospace and defense, the title is formally "Solution
Architect". It appears at the Large Solution level alongside the Solution Train Engineer (the process
lead) and Solution Management (the content owner). Those three roughly form the technical, process and
business leadership of a large system build.</p>
<p>Outside SAFe, "Solutions Architect" is also a pre-sales title at vendors like AWS. That role designs
customer deployments with the vendor's products, which is a different job.</p>
</div>
</details>
<div id=ctl><button class=primary id=play>Play</button><button id=prev>&larr; Prev</button><button id=next>Next &rarr;</button><span id=pos class=muted></span><div id=prog><div></div></div><label class=muted><input type=checkbox id=fast> fast</label></div>
<div id=stage></div>
<noscript><div class="static" style="display:block">$static</div></noscript>
<script>
var S=$json;
var i=-1,playing=false,timer=null,typing=null;
var stage=document.getElementById('stage'),pos=document.getElementById('pos'),bar=document.querySelector('#prog div');
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function render(k,typed){
  var s=S[k],el;
  if(s.kind==='day'){el=document.createElement('h2');el.textContent=s.text}
  else if(s.kind==='note'){el=document.createElement('p');el.className='note';el.textContent=s.text}
  else{el=document.createElement('pre');el.className='term';
    var p='<span class="'+(s.kind==='vim'?'vim':'prompt')+'">'+(s.kind==='vim'?'[vim] ':'\$ ')+'</span>';
    if(typed&&!document.getElementById('fast').checked){el.innerHTML=p;stage.appendChild(el);typeInto(el,p,s);return el}
    el.innerHTML=p+esc(s.cmd)+'\\n'+esc(s.out)}
  stage.appendChild(el);return el}
function typeInto(el,p,s){var n=0;clearInterval(typing);typing=setInterval(function(){n++;el.innerHTML=p+esc(s.cmd.slice(0,n));if(n>=s.cmd.length){clearInterval(typing);setTimeout(function(){el.innerHTML=p+esc(s.cmd)+'\\n'+esc(s.out);el.scrollIntoView({block:'end'});if(playing)schedule()},250)}},28)}
function show(k,typed){if(k<0||k>=S.length)return;var el=render(k,typed);i=k;pos.textContent=(k+1)+' / '+S.length;bar.style.width=(100*(k+1)/S.length)+'%';el.scrollIntoView({block:'end'});
  if(playing&&!(S[k].kind==='cmd'||S[k].kind==='vim')||document.getElementById('fast').checked)schedule()}
function delay(k){var s=S[k];if(document.getElementById('fast').checked)return 250;if(s.kind==='day')return 1400;if(s.kind==='note')return 900+s.text.length*22;return 800+Math.min(s.out.length,900)*4}
function schedule(){clearTimeout(timer);if(!playing)return;if(i+1>=S.length){playing=false;document.getElementById('play').textContent='Replay';return}timer=setTimeout(function(){show(i+1,true)},delay(i<0?0:i))}
function reset(){stage.innerHTML='';i=-1}
document.getElementById('play').onclick=function(){if(i+1>=S.length){reset()}playing=!playing;this.textContent=playing?'Pause':'Play';if(playing)schedule();else{clearTimeout(timer);clearInterval(typing)}};
document.getElementById('next').onclick=function(){playing=false;document.getElementById('play').textContent='Play';clearTimeout(timer);clearInterval(typing);show(i+1,false)};
document.getElementById('prev').onclick=function(){playing=false;document.getElementById('play').textContent='Play';clearTimeout(timer);clearInterval(typing);var k=i-1;reset();for(var j=0;j<=k;j++)show(j,false)};
document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'||e.key===' '){e.preventDefault();document.getElementById('next').click()}if(e.key==='ArrowLeft'){e.preventDefault();document.getElementById('prev').click()}});
</script>
</body></html>
HTML
    open my $w, '>:encoding(UTF-8)', $path or die "cannot write $path: $!\n";
    print $w $html;
    close $w;
}
