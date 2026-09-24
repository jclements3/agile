#!/usr/bin/perl
# Daily driver:  new -> (vim) -> compile -> report -> draft -> commit
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptionsFromArray);
use Cwd qw(abs_path getcwd);
use Prelude qw(sorted nub);
use Scrum;
use Standup;
use Calendar;
use Chat;
use Answers;
use Ai;
use Attendance;
use Cockpit;
use Roster ();
use File::Spec;

my %o;
GetOptionsFromArray(\@ARGV, 'c|conf=s' => \$o{conf}, 'today=s' => \$o{today}, 'dry' => \$o{dry}, 'draft' => \$o{draft},
    'to=s' => \$o{to}, 'cc=s' => \$o{cc}, 'subject=s' => \$o{subject}, 'team=s' => \$o{team}, 'send' => \$o{send}, 'force' => \$o{force}, 'guess' => \$o{guess}, 'reply' => \$o{reply}, 'assume' => \$o{assume}, 'private' => \$o{private}, 'table' => \$o{table}, 'confirm' => \$o{confirm}) or exit 2;
my $cmd = shift @ARGV // 'status';

# ---- locate project
my $conf_path = $o{conf} // find_conf();
if ($cmd eq 'init') { exit init(@ARGV) }
if (!$conf_path) { print STDERR "no scrum.conf found here or above (run: daily.pl init)\n"; exit 1 }
if (!-f $conf_path) { print STDERR "no such file: $conf_path\n"; exit 1 }
my $conf = read_conf($conf_path);
(my $base = abs_path($conf_path)) =~ s{/[^/]*$}{};
chdir $base or die "cannot chdir $base: $!\n";
my $today = $o{today} // do { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] };
my $load  = sub { my $s = load($conf->{journal}, today => $today); $s->{unit} = $conf->{unit}; $s };

my %cmds = (
    new      => \&cmd_new,     status  => \&cmd_status,  compile => \&cmd_compile, report => \&cmd_report,
    draft    => \&cmd_draft,   brief   => \&cmd_brief,   commit  => \&cmd_commit,  all     => \&cmd_all,     check   => \&cmd_check,
    attend   => \&cmd_attend,  post    => \&cmd_post,    meetings => \&cmd_meetings, chat => \&cmd_chat,
    answers  => \&cmd_answers, ai      => \&cmd_ai,     joined   => \&cmd_joined,   cards => \&cmd_cards,  lint => \&cmd_lint, propose => \&cmd_propose,
    roster   => \&cmd_roster,  invite  => \&cmd_invite,
    sprint   => sub { print sprint_text($load->(), $_[0]) },
    velocity => sub { print velocity_text($load->()) },
    backlog  => sub { print backlog_text($load->(), $_[0]) },
    members  => sub { print members_text($load->(), $_[0]) },
    epics    => sub { print epics_text($load->()) },
    roadmap  => sub { print roadmap_text($load->()) },
    blocked  => sub { my $s = $load->(); printf "%-10s %-6s %s\n", $_->{id}, $_->{team} // '', $_->{blocked} for blocked($s) },
);
if (!$cmds{$cmd}) { print STDERR "commands: init new status compile report draft brief commit all check attend post meetings chat answers lint propose roster invite ai joined cards sprint velocity backlog members epics roadmap blocked\n"; exit 2 }
exit($cmds{$cmd}->(@ARGV) // 0);

# ---------------------------------------------------------------- commands
sub cmd_new {
    my @teams = @_;
    mkdir $conf->{standups} unless -d $conf->{standups};
    my $path = "$conf->{standups}/$today.txt";
    if (-e $path) { print "exists\n$path\n"; return 0 }
    my $s = $load->();
    open my $fh, '>', $path or die "cannot write $path: $!\n";
    print $fh template($s, $today, @teams ? \@teams : undef);
    close $fh;
    print "created\n$path\n";
    0;
}
sub cmd_status {
    my $s = $load->();
    my @p = pending($conf->{standups});
    printf "journal: %s  (%d tasks, sprint %s, teams %s)\n", $conf->{journal}, scalar keys %{ $s->{items} }, $s->{current} // '?', join('/', @{ $s->{teams} });
    print @p ? "pending stand-up files:\n" . join('', map { "  $_\n" } @p) : "no pending stand-up files\n";
    my $r = sprint_summary($s);
    printf "sprint %s: %d/%d %s done (%d%%), %d open, %d blocked\n", $r->{sprint}, $r->{totals}{done}, $r->{totals}{committed}, $conf->{unit}, $r->{totals}{pct}, $r->{totals}{open}, scalar blocked($s) if defined $r->{sprint};
    0;
}
sub cmd_compile {
    my @p = pending($conf->{standups});
    if (!@p) { print "nothing to compile\n"; return 0 }
    my $rc = 0;
    for my $f (@p) {                          # oldest first; each file sees the journal as left by the previous one
        my $s  = $load->();
        my $su = read_standup($f);
        my $text = eval { $o{dry} ? compile($s, $su) : apply($s, $su, $conf->{journal}) };
        if (!defined $text) { print STDERR "$f: NOT applied\n$@"; $rc = 1; last }
        if ($o{dry}) { print "# would append for $f:\n$text"; next }
        my $n = () = $text =~ /^\d{4}-\d{2}-\d{2} /mg;
        print "applied $f ($n transactions)\n";
    }
    $rc;
}
sub _today_notes {
    my @files = grep { -f } map { "$conf->{standups}/$_" } grep { /^\Q$today\E.*\.txt$/ } do { opendir my $d, $conf->{standups} or return undef; my @f = readdir $d; closedir $d; sorted(@f) };
    @files ? day_notes(map { read_standup($_) } @files) : undef;
}
sub _extra_text {                             # today's flags + AI assessment, for the status mail
    my $s = shift;
    my $out = '';
    for my $f (_answer_files()) {
        my $rec = read_answers($f);
        my @h = history($conf->{standups}, $rec->{team}, $today, $conf->{history_days});
        my @fl = flags($s, $rec->{team}, $rec->{answers}, \@h, roster => [ _roster($s, $rec->{team}) ]);
        $out .= ($rec->{team} ? "$rec->{team} " : '') . "flags:\n" . join('', map { "  $_\n" } Answers::fold_flags(@fl)) if @fl;   # the mail: serious flags in full, routine ones as counts
    }
    my $ai = Ai::parse_response(Ai::_read("$conf->{reports}/$today-ai-response.txt"));
    $out .= ($out ? "\n" : '') . response_text($ai) if response_ok($ai);
    $out;
}
sub cmd_report {
    my $s = $load->();
    mkdir $conf->{reports} unless -d $conf->{reports};
    my $notes = _today_notes();
    $notes //= { date => $today, teams => {}, notes => [], risks => [], extra => '' };
    $notes->{extra} = _extra_text($s);
    my $n = $s->{current};
    my %out = (
        "$conf->{reports}/dashboard.html"      => dashboard_html($s, marking => $conf),
        "$conf->{reports}/tree.html"           => tree_html($s, marking => $conf),
        "$conf->{reports}/roadmap.html"        => roadmap_html($s, marking => $conf),
        "$conf->{reports}/cockpit.html"        => cockpit_html($s, marking => $conf, days => days_from_standups($s, $conf->{standups}, $conf->{history_days}),
                                                               plates => (-f "$conf->{reports}/plates.html" ? 'plates.html' : undef), plates_file => "$conf->{reports}/plates.html",
                                                               roster => Roster::read_roster('roster.txt'), readback_clean_days => $conf->{readback_clean_days} // 5,
                                                               map { (lc $_ => -f "$FindBin::Bin/../docs/$_.html" ? File::Spec->abs2rel(abs_path("$FindBin::Bin/../docs/$_.html"), abs_path($conf->{reports})) : undef) } qw(TUTORIAL TRAINING)),
        "$conf->{reports}/$today-status.html"  => email_html($s, $n, notes => $notes, marking => $conf),
        "$conf->{reports}/$today-status.txt"   => email_text($s, $n, notes => $notes, marking => $conf),
        "$conf->{reports}/$today-brief.html"   => brief_html($s, $n, marking => $conf),
        "$conf->{reports}/$today-brief.txt"    => brief_text($s, $n, marking => $conf),
    );
    for my $f (sorted(keys %out)) {
        open my $fh, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n";
        print $fh $out{$f};
        close $fh;
        print "wrote $f\n";
    }
    0;
}
sub _marking_gate {                               # print marking problems; refuse to open/send when there is an error (unless --force)
    my @recipients = @_;
    my @p = marking_check($conf, recipients => \@recipients);
    print "  marking: $_\n" for @p;
    return 1 unless grep { /^error:/ } @p;
    if ($o{force}) { print "  --force: continuing despite marking errors\n"; return 1 }
    print "refusing: fix the marking errors above, or run again with --force\n";
    0;
}
sub cmd_draft {
    my $s = $load->();
    my $notes = _today_notes();
    $notes //= { date => $today, teams => {}, notes => [], risks => [], extra => '' };
    $notes->{extra} = _extra_text($s);
    my ($to, $cc) = ($o{to} // $conf->{to}, $o{cc} // $conf->{cc});
    _marking_gate($to, $cc) or return 1;
    my $html = email_html($s, $s->{current}, notes => $notes, marking => $conf);
    my $p = outlook_draft(html => $html, to => $to, cc => $cc, subject => subject($conf, $o{subject} // "Sprint $s->{current} status $today"));
    print "draft opened in Outlook (body saved at $p)\n";
    0;
}
sub cmd_brief {                               # the terse BLUF leadership mail -- one sentence + <=5 bullets, drafted (not sent) via Outlook
    my $s = $load->();
    my ($to, $cc) = ($o{to} // $conf->{to}, $o{cc} // $conf->{cc});
    _marking_gate($to, $cc) or return 1;
    my $p = outlook_draft(html => brief_html($s, $s->{current}, marking => $conf), to => $to, cc => $cc,
                          subject => subject($conf, $o{subject} // brief_subject($s, $s->{current})));
    print "draft opened in Outlook (body saved at $p)\n";
    0;
}
sub cmd_commit {
    (qx(git rev-parse --is-inside-work-tree 2>&1) // '') =~ /true/ or do { print STDERR "not a git repository (git init first)\n"; return 1 };
    system('git', '-c', 'core.safecrlf=false', 'add', '-A') == 0 or return 1;   # no line-ending advisories on Windows checkouts; .gitattributes (eol=lf) decides
    my $out = qx(git -c core.safecrlf=false commit -q -m "standup $today" 2>&1);
    print $? == 0 ? "committed\n" : "nothing to commit\n";
    0;
}
sub cmd_all {
    my $rc = cmd_compile();
    return $rc if $rc;
    cmd_report();
    cmd_draft() if $o{draft};
    cmd_commit();
}
sub cmd_check {
    my $s = $load->();
    printf "ok: %d tasks, teams %s, sprints %s\n", scalar keys %{ $s->{items} }, join('/', @{ $s->{teams} }), join('/', @{ $s->{sprints} });
    my @p = marking_check($conf, recipients => [ $conf->{to}, $conf->{cc} ]);
    print @p ? join('', map { "marking: $_\n" } @p) : ($conf->{banner} ? "marking: ok ($conf->{banner}" . ($conf->{mail_domains} ? "; mail only to $conf->{mail_domains}" : "") . ")\n" : "marking: off (no banner in scrum.conf)\n");
    (grep { /^error:/ } @p) ? 1 : 0;
}

# ---------------------------------------------------------------- calendar
sub _cal {
    my $c = $conf->{calendar} // 'outlook';
    return Calendar->new(backend => 'mock', fixture => $conf->{calendar_fixture}) if $c eq 'mock' && $conf->{calendar_fixture};
    Calendar->new(backend => $c);
}
sub _standups { my $cal = shift; $cal->today(date => $today, match => qr/$conf->{standup_match}/i) }
sub cmd_meetings {
    my $cal = _cal();
    my @ev = $cal->today(date => $today);
    print "no meetings on $today\n" unless @ev;
    printf "%s-%s  %-40s %s%s\n", substr($_->{start}, 11, 5), substr($_->{end}, 11, 5), $_->{subject}, $_->{teams} ? 'Teams ' : '', scalar(@{ $_->{attendees} }) . ' invited' for @ev;
    0;
}
sub cmd_attend {                              # attendee responses -> today's stand-up file (comments + suggested absents) and attendance.csv
    my $s   = $load->();
    my $cal = _cal();
    my @ev  = _standups($cal);
    if (!@ev) { print "no stand-up meetings on $today (standup_match = $conf->{standup_match})\n"; return 0 }
    my $path = "$conf->{standups}/$today.txt";
    cmd_new() unless -e $path;
    my $body = do { open my $r, '<', $path or die $!; local $/; <$r> };
    my $added = '';
    for my $ev (@ev) {
        my $team = $cal->team_for($ev, $conf, $s->{teams});
        print $cal->attendance_text($ev);
        my $rows = $cal->log_attendance($conf->{attendance}, $today, $team // '?', $ev);
        printf "  -> %s (%d rows)%s\n", $conf->{attendance}, $rows, defined $team ? "" : "  [team not recognised; set team_from_subject in scrum.conf]";
        my $lines = $cal->standup_lines($ev);
        next if index($body, $lines) >= 0;                      # already there
        $added .= ($team ? "== $team\n" : '') . $lines;
    }
    if ($added) { open my $w, '>>', $path or die $!; print $w "\n; ---- calendar $today\n$added"; close $w; print "appended attendance to $path\n" }
    0;
}
sub cmd_post {                                # today's metrics text into each stand-up meeting body (--send to update attendees)
    my $s   = $load->();
    my $cal = _cal();
    my @ev  = _standups($cal);
    if (!@ev) { print "no stand-up meetings on $today\n"; return 0 }
    my $notes = _today_notes();
    for my $ev (@ev) {
        my $team = $cal->team_for($ev, $conf, $s->{teams});
        my $text = email_text($s, $s->{current}, notes => $notes, marking => $conf);
        $text = "[$team]\n$text" if $team;
        $cal->post_text($ev, $text, send => $o{send});
        printf "posted metrics to '%s' %s%s\n", $ev->{subject}, substr($ev->{start}, 11, 5), $o{send} ? ' (update sent)' : ' (saved)';
    }
    if ($cal->backend eq 'mock') { printf "mock: %s %s\n", $_->{action}, $_->{id} for $cal->actions }
    0;
}

# ---------------------------------------------------------------- meeting chat
sub cmd_chat {                                # standups/DATE-chat.txt (pasted Teams chat) -> tallies -> lines into today's stand-up file
    my $s = $load->();
    my $chat = $ARGV[0] // "$conf->{standups}/$today-chat.txt";
    if (!-e $chat) { print "no chat file: $chat  (paste the Teams meeting chat there)\n"; return 1 }
    my $text = do { open my $r, '<', $chat or die "cannot open $chat: $!\n"; local $/; <$r> };
    my ($report, $lines, $n) = report($text);
    if (!$n) { print "no #est / #vote markers in $chat\n"; return 1 }
    print $report;
    my $path = "$conf->{standups}/$today.txt";
    cmd_new() unless -e $path;
    my $body = do { open my $r, '<', $path or die $!; local $/; <$r> };
    $lines =~ s/^(est (\S+) .*)$/ $s->{items}{$2} ? $1 : "; $1   ; task not in journal yet" /gme;    # never break compile
    my (%per_team, @global);                                                                          # est lines go under the task's team section
    for my $l (split /\n/, $lines) {
        if    ($l =~ /^;?\s*est (\S+)/ && $s->{items}{$1} && $s->{items}{$1}{team} && $s->{items}{$1}{team} ne 'Master') { push @{ $per_team{ $s->{items}{$1}{team} } }, $l }
        elsif ($l =~ /^est (\S+)/) { push @global, "; $l   ; in the master backlog: move under a team section to apply" }
        else  { push @global, $l }
    }
    $lines = join('', map { "== $_\n" . join('', map { "$_\n" } @{ $per_team{$_} }) } sorted(keys %per_team)) . (@global ? "==\n" . join('', map { "$_\n" } @global) : '');
    return 0 if index($body, $lines) >= 0;
    open my $w, '>>', $path or die $!;
    print $w "\n; ---- chat $today\n$lines";
    close $w;
    print "appended to $path (uncomment the est lines you accept; note lines apply as-is)\n";
    0;
}

# ---------------------------------------------------------------- three-questions answers from chat, and the AI hand-off
sub _emails {                                 # name -> e-mail: roster.txt first (the maintained list), then today's stand-up meeting invitees (Outlook) for anyone missing
    my %emails = %{ Roster::emails(Roster::read_roster('roster.txt')) };
    my $cal = eval { _cal() };
    if ($cal) { for my $ev (eval { _standups($cal) }) { $emails{ $_->{name} } ||= $_->{email} for grep { $_->{email} && $_->{email} =~ /@/ } @{ $ev->{attendees} } } }
    %emails;
}
sub cmd_roster {                              # roster            list by team, then check against the journal
    my @a = @_;                               # roster add "Name" email Team "Role" "Org"    add or update a person (name = Teams display name)
    my $r = Roster::read_roster('roster.txt');
    if (@a && $a[0] eq 'add') {
        my (undef, $name, $email, $team, $role, $org) = @a;
        die "usage: daily.pl roster add \"Name\" email Team \"Role\" \"Org\"\n" unless $name;
        my ($x) = grep { $_->{name} eq $name } @$r;
        if ($x) { $x->{email} = $email if defined $email; $x->{team} = $team if defined $team; $x->{role} = $role if defined $role; $x->{org} = $org if defined $org; print "updated $name\n" }
        else { push @$r, { name => $name, email => $email // '', team => $team // '', role => $role // '', org => $org // '' }; print "added $name\n" }
        Roster::write_roster('roster.txt', $r);
        return 0;
    }
    if (!@$r) { print "no roster.txt yet. One line per person:  Name | email | Team | Role | Org   (name = the Teams display name)\n  or: daily.pl roster add \"Ann Lee\" ann.lee\@example.com Alpha Lead \"ACME\"\n"; return 1 }
    print Roster::roster_text($r);
    my @p = Roster::roster_check($load->(), $r);
    print "check:\n", map { sprintf "  %-5s %s\n", uc $_->{level}, $_->{text} } @p if @p;
    printf "%d people, %d with e-mail, %d teams%s\n", scalar @$r, scalar(grep { $_->{email} =~ /@/ } @$r), scalar(keys %{ Roster::by_team($r) }), (@p ? '' : ', roster and journal agree');
    scalar(grep { $_->{level} eq 'warn' } @p) ? 1 : 0;
}
sub cmd_invite {                              # invite [--dry]: the recurring townhall in Outlook/Teams, every weekday, the roster as required attendees
    my $r = Roster::read_roster('roster.txt');
    my @to = sort { $a cmp $b } nub(map { $_->{email} } grep { $_->{email} =~ /@/ } @$r);
    if (!@to) { print STDERR "no e-mails in roster.txt (daily.pl roster)\n"; return 1 }
    my $subject = $conf->{townhall_subject} || 'Daily townhall';
    my $start   = $conf->{townhall_start}   || '07:30';
    my $minutes = $conf->{townhall_minutes} || 60;
    my $loc     = $conf->{townhall_location} || 'Microsoft Teams Meeting';
    my $first   = $today; { my @t = localtime; my $dow = $t[6]; my $add = $dow == 6 ? 2 : $dow == 0 ? 1 : 0; if ($add) { my $t = time + $add * 86400; my @d = localtime $t; $first = sprintf '%04d-%02d-%02d', $d[5] + 1900, $d[4] + 1, $d[3] } }
    my $body = join "\n",
        "$subject: an open hour, every weekday $start for $minutes minutes. Join when you can, post your status on arrival, leave when you are done -- stay if you need to clear a blocker with another team.",
        '',
        'Post ONE line in the meeting chat, capital Y T B as separators, your task ids in it:',
        '    Y did B-11   T doing B-12   B none',
        'You will get a read-back (Y / T / B as I recorded it): thumbs-up if right, or repost. Corrections come to you 1:1, not to the room.',
        'The shared screen is the cockpit: statuses grow as people post; blockers are listed with owner and team -- that is the list to work in the room.',
        '',
        ($conf->{banner} ? "Marking: $conf->{banner}. This meeting and its chat are program record." : ''),
        "Attendees: " . scalar(@to) . " (roster.txt). Organiser: " . ($conf->{marking_poc} || 'the solutions architect') . '.';
    print "invite: $subject  every weekday from $first $start, $minutes min, $loc\n  to " . scalar(@to) . " attendees: " . join(', ', @to[0 .. ($#to < 5 ? $#to : 5)]) . (@to > 6 ? ', ...' : '') . "\n";
    _marking_gate(@to) or return 1;
    if ($o{dry}) { print "--dry: not created. Body:\n$body\n"; return 0 }
    my $cal = _cal();
    my $id = $cal->create(subject => $conf->{banner} ? "$conf->{banner} $subject" : $subject, start => "${first}T$start", minutes => $minutes, attendees => \@to, location => $loc, weekdays => 1, display => 1, body => $body);
    print "created $id (opened in Outlook for you to review and send)\n";
    0;
}
sub _private_page {                           # --private: reports/<date>-<kind>.html with a 1:1 Teams link per person, message pre-filled
    my ($s, $kind, $title, @msgs) = @_;
    my %emails = _emails();
    $_->{email} = $emails{ $_->{who} } for @msgs;
    mkdir $conf->{reports} unless -d $conf->{reports};
    my $f = "$conf->{reports}/$today-$kind.html";
    open my $w, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n"; print $w messages_html($s, $title, \@msgs, marking => $conf); close $w;
    printf "wrote %s  (%d people, e-mail known for %d)\n", $f, scalar @msgs, scalar grep { $_->{email} } @msgs;
    $f;
}
sub cmd_propose {                             # propose [Team] [--private]: today's status drafted from yesterday's, one paste-ready line per person (post before/during the meeting)
    my @teams = @_ ? @_ : @{ $load->()->{teams} };
    binmode STDOUT, ':utf8';
    my $s = $load->();
    my (@private, @proposals);
    for my $team (@teams) {
        my @h = history($conf->{standups}, $team, $today, $conf->{history_days});
        my @p = propose($s, $team, \@h, roster => [ _roster($s, $team) ]);
        next unless @p;
        push @proposals, @p;
        if ($o{private}) { push @private, map { { who => $_->{who}, text => "Hey " . ($_->{who} =~ /^(\S+)/)[0] . "! Your status for today, from yesterday's: Y $_->{y}" . ($_->{line} =~ / done\? / ? ' done?' : '') . " T $_->{t} B $_->{b}  -- \x{1F44D} if right, or post your own Y/T/B in the meeting chat" } } @p; next }
        print "== $team" . (@h ? "  (from $h[0]{date})" : '  (no history yet)') . "\n";
        print "$_->{line}\n" for @p;
        print "\n";
    }
    _private_page($s, 'propose', 'Proposed statuses', @private) if $o{private};
    if (@proposals) {                         # persist: a "+1" in the chat then accepts the proposal (answers / lint read this file)
        mkdir $conf->{standups} unless -d $conf->{standups};
        my $pf = "$conf->{standups}/$today-proposals.txt";
        open my $w, '>:encoding(UTF-8)', $pf or die "cannot write $pf: $!\n";
        print $w "# who\tY\tT\tB   (daily.pl propose $today; an ack in the chat -- +1, y, ok, thumbs-up -- accepts the line)\n";
        print $w join("\t", $_->{who}, $_->{y}, $_->{t}, $_->{b}), "\n" for @proposals;
        close $w; print "wrote $pf\n";
    }
    0;
}
sub cmd_lint {                                # lint [FILE|-] [--reply]: check every Y/T/B status in a pasted chat, during the meeting
    my @args = @_;                            # FILE:LINE: prefix per person (Vim quickfix); --reply prints only the lines to paste back into the chat
    binmode STDOUT, ':utf8';                  # the reply carries a thumbs-up
    my $reply = $o{reply};
    my @files = @args;
    @files = map { $_->[0] } _chat_files() unless @files;
    if (!@files) { print "no chat file for $today (standups/$today-chat.txt); or: daily.pl lint FILE | daily.pl lint -\n"; return 1 }
    my $s = $load->();
    my %known = map { $_->{id} => 1 } items($s);
    my ($ex1, $ex2) = (sorted(keys %known))[0, 1];
    my $rc = 0;
    for my $f (@files) {
        my $text = do { local $/; $f eq '-' ? <STDIN> : do { open my $r, '<', $f or die "cannot open $f: $!\n"; <$r> } };
        my @r = lint_chat($text, known => \%known, example => $ex1 // 'B-11', example2 => $ex2 // 'B-12', proposals => read_proposals("$conf->{standups}/$today-proposals.txt"));
        # --confirm: everyone hears back; a clean status comes back as "I read it as ..." for a thumbs-up -- until they have been clean for
        # readback_clean_days running (scrum.conf, default 5): then only errors and warnings, the read-back has done its teaching
        my $mature = $conf->{readback_clean_days} // 5;
        my %streak;
        if ($o{confirm} && $mature > 0) {
            for my $team (@{ $s->{teams} }) { for my $h (history($conf->{standups}, $team, $today, $mature)) { for my $a (@{ $h->{answers} }) {
                next if defined $streak{ $a->{who} } && $streak{ $a->{who} } < 0;
                my $clean = $a->{complete} && !$a->{assumed} && (@{ $a->{ids}{y} } || @{ $a->{ids}{t} });
                $streak{ $a->{who} } = $clean ? ($streak{ $a->{who} } // 0) + 1 : -1;   # -1: streak broken (newest-first history, so the first miss ends it)
            } } }
        }
        my $msg = sub { my $x = shift; $x->{reply} || ($o{confirm} && ($streak{ $x->{who} } // 0) < $mature ? $x->{confirm} : '') };
        if ($o{private}) { _private_page($s, 'lint', $o{confirm} ? 'Status read-backs' : 'Status corrections', map { { who => $_->{who}, text => $msg->($_) } } grep { $msg->($_) } @r) }
        elsif ($reply)   { print map { $msg->($_) . "\n" } grep { $msg->($_) } @r }
        elsif ($o{table}) {                   # what the parser understood: state | who | Y | T | B (tab-separated; the console and spreadsheets read it)
            print join("\t", 'state', 'who', 'Y', 'T', 'B', 'note'), "\n";
            for my $x (@r) { my $st = !$x->{ok} ? 'ERROR' : @{ $x->{warnings} } ? 'warn' : 'ok';
                my @f = !$x->{ok} && $x->{guess} ? map { "$x->{guess}{$_} ?" } qw(y t b) : map { $_ // '' } @{$x}{qw(y t b)};   # an ERROR row shows the guessed reading with a "?"
                print join("\t", $st, $x->{who}, @f, (!$x->{ok} ? join('; ', @{ $x->{errors} }) : join('; ', @{ $x->{warnings} }))), "\n" }
        }
        else             { print lint_text($f eq '-' ? 'chat' : $f, @r) }
        $rc = 1 if grep { !$_->{ok} } @r;
    }
    $rc;
}
sub _chat_files {                             # standups/DATE[-Team]-chat.txt -> ( [file, team], ... )
    opendir my $d, $conf->{standups} or return ();
    my @f = sorted(grep { /^\Q$today\E(?:-(.+?))?-chat\.txt$/ } readdir $d);
    closedir $d;
    map { [ "$conf->{standups}/$_", (/^\Q$today\E-(.+?)-chat\.txt$/ ? $1 : ($conf->{default_team} || undef)) ] } @f;
}
sub _answer_files { opendir my $d, $conf->{standups} or return (); my @f = sorted(grep { /^\Q$today\E(?:-.+?)?-answers\.txt$/ } readdir $d); closedir $d; map { "$conf->{standups}/$_" } @f }
sub _roster { my ($s, $team) = @_; my $m = members($s, $team); sorted(keys %$m) }
sub cmd_answers {                             # parse each pasted chat for Y/T/B answers -> answers file, flags, suggested lines, attendance rows
    my $s = $load->();
    my @cf = _chat_files();
    if (!@cf) { print "no chat files for $today (standups/$today-<Team>-chat.txt)\n"; return 1 }
    my $path = "$conf->{standups}/$today.txt";
    my $rc = 0;
    for my $cf (@cf) {
        my ($file, $team0) = @$cf;
        $team0 //= (@{ $s->{teams} } == 1 ? $s->{teams}[0] : undef);
        my $text = do { open my $r, '<', $file or die "cannot open $file: $!\n"; local $/; <$r> };
        my @all = parse_answers($text, guess => $o{guess}, proposals => read_proposals("$conf->{standups}/$today-proposals.txt"));   # --guess: accept the lint's "did you mean" reading where the strict one failed (they thumbed it up); a "+1" accepts the day's proposal
        if (!@all) { print "$file: no Y/T/B answers found\n"; $rc = 1; next }
        my %by;                                                          # a joint meeting: split answers by the answerer's team (journal owners)
        if (defined $team0) { $by{$team0} = \@all }
        else { for my $a (@all) { my $t = Attendance::team_of($s, $a->{who}); push @{ $by{ $t // '?' } }, $a } }
        print "  unknown team for: " . join(', ', map { $_->{who} } @{ $by{'?'} }) . "  (not an owner in the journal; assign them a task or name the team in the file name)\n" if $by{'?'};
      TEAM: for my $team (sorted(grep { $_ ne '?' } keys %by)) {
        my @ans = @{ $by{$team} };
        my $af = answers_path($conf->{standups}, $today, $team);
        open my $w, '>', $af or die "cannot write $af: $!\n"; print $w answers_text($today, $team, @ans); close $w;
        my @h  = history($conf->{standups}, $team, $today, $conf->{history_days});
        if ($o{assume}) {                     # --assume: the silent get yesterday's proposal on the record, marked assumed (visible, escalating, never done)
            my %seen = map { $_->{who} => 1 } @ans;
            my @silent = grep { !$seen{$_} } _roster($s, $team);
            my @p = grep { !$seen{ $_->{who} } } propose($s, $team, \@h, roster => \@silent);
            push @ans, map { assumed_record($_) } @p;
            open my $w2, '>', $af or die "cannot write $af: $!\n"; print $w2 answers_text($today, $team, @ans); close $w2;
            print "  assumed for the silent: " . join(', ', map { $_->{who} } @p) . "\n" if @p;
        }
        my @fl = flags($s, $team, \@ans, \@h, roster => [ _roster($s, $team) ]);
        print answers_report($team, \@ans, \@fl), "wrote $af\n";
        my $n = Calendar::log_rows($conf->{attendance}, $today, $team // '?', map { [ $_->{who}, 'answered' ] } @ans);
        print "  attendance: $n rows (answered) -> $conf->{attendance}\n" if $n;
        my $lines = suggest_lines($s, $team, \@ans, \@fl);
        next TEAM unless $lines;
        cmd_new() unless -e $path;
        my $body = do { open my $r, '<', $path or die $!; local $/; <$r> };
        next TEAM if index($body, $lines) >= 0;
        open my $a, '>>', $path or die $!;
        print $a "\n; ---- answers $today $team\n== $team\n$lines";
        close $a;
        print "  appended suggested lines to $path\n";
      }
    }
    $rc;
}
sub cmd_joined {                              # Teams attendance report downloads -> attendance.csv with join/leave/minutes
    my $s = $load->();
    my @files = @ARGV ? @ARGV : do { opendir my $d, $conf->{standups} or (); my @f = sorted(grep { /^\Q$today\E(?:-.+?)?-attendance\.(?:csv|txt|tsv)$/ } readdir $d); closedir $d; map { "$conf->{standups}/$_" } @f };
    if (!@files) { print "no attendance reports for $today (download from the meeting's Attendance tab to standups/$today-<Team>-attendance.csv)\n"; return 1 }
    for my $f (@files) {
        my ($team) = $f =~ /\Q$today\E-(.+?)-attendance\./;
        my $rep = read_report($f);
        print report_text($rep);
        my $n = log_report($conf->{attendance}, $today, $rep, team => $team, team_of => sub { Attendance::team_of($s, $_[0]) }, min_minutes => $conf->{min_minutes} // 3);
        my @unk = grep { !defined Attendance::team_of($s, $_->{name}) } @{ $rep->{participants} };
        printf "  %d rows -> %s%s\n", $n, $conf->{attendance}, !$team && @unk ? "   (team unknown for: " . join(', ', map { $_->{name} } @unk) . ")" : '';
    }
    0;
}
sub cmd_cards {                               # per-member task cards: text + html with Teams deep links; --send mails them via Outlook
    my $s = $load->();
    my %last_b;
    for my $team (@{ $s->{teams} }) { my ($h) = history($conf->{standups}, $team, $today, 1); next unless $h; $last_b{ $_->{who} } = $_->{b} for grep { $_->{blocked} } @{ $h->{answers} } }
    my %emails = _emails();
    mkdir $conf->{reports} unless -d $conf->{reports};
    my $txt = marked_text($conf, cards_text($s, team => $o{team}, last_b => \%last_b));
    my $html = cards_html($s, team => $o{team}, last_b => \%last_b, emails => \%emails, marking => $conf);
    for my $f (["$conf->{reports}/$today-cards.txt", $txt], ["$conf->{reports}/$today-cards.html", $html]) { open my $w, '>:encoding(UTF-8)', $f->[0] or die; print $w $f->[1]; close $w; print "wrote $f->[0]\n" }
    my @names = sorted(keys %{ members($s, $o{team}) });
    print "  e-mail known for " . scalar(grep { $emails{$_} } @names) . "/" . scalar(@names) . " members (from today's meeting invitees" . (-f 'roster.txt' ? ' and roster.txt' : '') . ")\n";
    if ($o{send} || $o{draft}) {
        _marking_gate(map { $emails{$_} } grep { $emails{$_} } @names) or return 1;
        my @mails = map { { to => $emails{$_}, subject => subject($conf, "Stand-up $today: your sprint $s->{current} tasks"), body => marked_text($conf, member_card($s, $_, last_b => $last_b{$_})) } } grep { $emails{$_} } @names;
        my $n = outlook_bulk(\@mails, send => $o{send});
        print $o{send} ? "sent $n mails\n" : "opened $n drafts\n";
    }
    0;
}
sub cmd_ai {                                  # build the prompt from today's answers + metrics + history; ask the configured backend
    my $s = $load->();
    my (%answers, %flags, %history);
    for my $f (_answer_files()) {
        my $rec = read_answers($f);
        my $team = $rec->{team} // '(team)';
        my @h  = history($conf->{standups}, $rec->{team}, $today, $conf->{history_days});
        my @fl = flags($s, $rec->{team}, $rec->{answers}, \@h, roster => [ _roster($s, $rec->{team}) ]);
        $answers{$team} = answers_report($rec->{team}, $rec->{answers}, []);
        $flags{$team}   = \@fl;
        $history{$team} = join("\n", map { answers_text($_->{date}, $_->{team}, @{ $_->{answers} }) } @h);
    }
    if (!%answers) { print "no answers files for $today (run: daily.pl answers)\n"; return 1 }
    my $notes = _today_notes();
    my $prompt = prompt_pack(date => $today, sprint_text => sprint_text($s), answers => \%answers, flags => \%flags, history => \%history,
                             notes => $notes ? Scrum::_notes_text($s, $notes) : '', marking => $conf);
    mkdir $conf->{reports} unless -d $conf->{reports};
    my $r = ask(conf => $conf, prompt => $prompt, out_dir => $conf->{reports}, date => $today);
    if ($r->{status} eq 'pending') { print "prompt written: $r->{prompt_file}\npaste it into your AI service, save the reply as $r->{response_file}, then: daily.pl report\n"; return 0 }
    if ($r->{status} eq 'error')   { print STDERR "AI request failed: $r->{error}"; return 1 }
    my $p = Ai::parse_response($r->{text});
    print response_ok($p) ? response_text($p) : "response saved to $r->{response_file} but no recognised sections\n";
    0;
}

# ---------------------------------------------------------------- init
sub init {
    my $dir = shift // '.';
    mkdir $dir unless -d $dir;
    chdir $dir or die "cannot chdir $dir: $!\n";
    my %files = (
        'scrum.conf' => <<'CONF',
# scrum.conf — all paths relative to this file
journal   = scrum.txt
standups  = standups
reports   = reports
unit      = SP

# e-mail defaults for daily.pl draft
to        =
cc        =
subject_prefix =                  # e.g. INTERNAL -- prepended to mail subjects when set

# stand-up answers and the AI service
history_days  = 5                 # previous days of answers used for "stuck" and "blocked N days" checks
default_team  =                   # team for standups/<date>-chat.txt without a team in the name
ai_backend    = paste             # paste | curl | mock
ai_url        =
ai_model      =
ai_key_env    =                   # name of the env var holding the API key

# the townhall (daily.pl invite creates it: every weekday, roster.txt as attendees)
townhall_subject  = Daily townhall
townhall_start    = 07:30
townhall_minutes  = 60
townhall_location = Microsoft Teams Meeting

# calendar (Outlook/Teams via PowerShell COM). calendar = mock + calendar_fixture = file.json for offline use
standup_match     = stand-?up
team_from_subject = ^(\w+)\s+stand
attendance        = attendance.csv

# marking (optional): a banner on every report, mail and PDF page, and a block under it. Leave banner empty to disable.
banner            =                 # e.g. INTERNAL, COMPANY CONFIDENTIAL
marking_owner     =                 # who owns the marked material
marking_category  =
marking_handling  =                 # e.g. do not forward outside the program
marking_poc       =
mail_domains      =                 # optional, comma-separated: mail may only go to these domains (daily.pl check enforces it)
CONF
        'scrum.txt' => <<'JOURNAL',
; Scrum journal. Conventions: perldoc lib/Scrum.pm
; Points move Backlog:Master -> Backlog:<Team> -> Sprint:<N>:<Team>:Committed -> Done | Carryover | Removed
; Every posting that moves a task carries "; id: KEY". Stand-up files write most of this for you.

; ~ Sprint 1
;     Alpha    20 SP

; 2026-01-05 Intake ABC-1 First task
;     Backlog:Alpha    5 SP   ; id: ABC-1, prio: 1, epic: Setup, owner: Someone
;     Equity:Intake

; 2026-01-06 Sprint 1 planning
;     Backlog:Alpha             -5 SP   ; id: ABC-1
;     Sprint:1:Alpha:Committed   5 SP   ; id: ABC-1
JOURNAL
        '.gitignore' => "reports/\n",
        '.gitattributes' => "* text eol=lf\n",   # the journal and stand-up files are LF text on every platform; no CRLF churn or warnings under Git for Windows
    );
    for my $f (sorted(keys %files)) {
        if (-e $f) { print "kept    $f\n"; next }
        open my $fh, '>', $f or die "cannot write $f: $!\n"; print $fh $files{$f}; close $fh;
        print "created $f\n";
    }
    mkdir $_ for grep { !-d } qw(standups reports);
    system('git', 'init', '-q') == 0 && print "git init\n" unless -d '.git';
    system('git', 'config', 'core.autocrlf', 'false') if -d '.git';
    my $vim = abs_path("$FindBin::Bin/../vim/scrum.vim");
    print <<"EOF";

Next:
  1. edit scrum.conf (recipients, markings)
  2. add tasks to scrum.txt, or use  daily.pl new  and 'new ID PTS title' lines
  3. add to ~/.vimrc:   source $vim
     then in Vim:  :SNew  :SCompile  :SReport  :SDraft  :SAll  :SStatus
EOF
    0;
}
