#!/usr/bin/perl
# perl t/attendance.t  — Attendance.pm, daily.pl joined/cards, joint-meeting answers, chat est placement
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(getcwd);
use Prelude qw(show fmap sorted);
use Scrum;
use Attendance;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $root = "$FindBin::Bin/..";
my $s = load("$root/examples/scrum.txt", today => '2026-09-23');

# ---- helpers
S 'hm', '["09:00","13:05","00:30","12:15","13:05",undef]', [ map { hm($_) } '9/23/26, 9:00:15 AM', '9/23/26, 1:05:10 PM', '12:30:00 AM', '12:15 PM', '2026-09-23T13:05:15', 'x' ];
S 'minutes', '[62,14.9,0.8,14.9,120,0]', [ map { minutes($_) } '1h 2m 3s', '14m 55s', '45s', '0:14:55', '2h', '' ];

# ---- UTF-16 tab report (the Teams download)
my $rep = read_report("$root/examples/attendance-2026-09-23-Alpha.csv");
S 'summary', '["Alpha Stand-up","9/23/26, 9:00:12 AM","9/23/26, 9:16:40 AM"]', [ @{$rep}{qw(title start end)} ];
S 'participants', '[["JC","08:58","09:16",18.6,"jc@example.com","Organizer"],["Ann Smith","09:00","09:15",14.9,"ann@example.com","Presenter"],["Bob Jones","09:01","09:03",1.4,"bob@example.com","Presenter"],["Zed Unknown","09:02","09:10",8,"zed@example.com","Attendee"]]',
  [ map { [ @{$_}{qw(name join leave minutes email role)} ] } @{ $rep->{participants} } ];
S 'activities ignored', 4, scalar @{ $rep->{participants} };
# UTF-8 comma variant with quotes
my $csv = parse_report(qq{1. Summary\nMeeting title,"Bravo, Stand-up"\n\n2. Participants\nName,First Join,Last Leave,In-Meeting Duration,Email,Role\n"Park, Cy",9/23/26 9:20:05 AM,9/23/26 9:34:00 AM,13m 55s,cy\@x.example,Presenter\nDee,,,0s,dee\@x.example,Attendee\n});
S 'csv variant', '["Bravo, Stand-up",[["Park, Cy","09:20","09:34",13.9],["Dee",undef,undef,0]]]', [ $csv->{title}, [ map { [ @{$_}{qw(name join leave minutes)} ] } @{ $csv->{participants} } ] ];
S 'decode utf8 bom', '"abc"', decode_bytes("\xEF\xBB\xBFabc");
S 'rows', '[["JC","present"],["Ann Smith","present"],["Bob Jones","brief"],["Zed Unknown","present"]]', [ map { [ @$_[0, 1] ] } rows($rep) ];
S 'rows threshold', 2, scalar grep { $_->[1] eq 'brief' } rows($rep, min_minutes => 10);
S 'team_of', '["Alpha","Alpha","Bravo",undef]', [ map { team_of($s, $_) } 'Ann', 'Ann Smith', 'Cy Park', 'Zed Unknown' ];
has 'report_text', report_text($rep), qr/^Alpha Stand-up  9\/23\/26, 9:00:12 AM - 9\/23\/26, 9:16:40 AM$/m, qr/^  Bob Jones              09:01  09:03    1\.4 min$/m;
my $dir = tempdir(CLEANUP => 1);
S 'log_report', 4, log_report("$dir/a.csv", '2026-09-23', $rep, team => 'Alpha');
S 'log idempotent', 0, log_report("$dir/a.csv", '2026-09-23', $rep, team => 'Alpha');
check 'csv rows', do { open my $f, '<', "$dir/a.csv"; local $/; <$f> }, "date,team,name,status,join,leave,minutes\n2026-09-23,Alpha,JC,present,08:58,09:16,18.6\n2026-09-23,Alpha,Ann Smith,present,09:00,09:15,14.9\n2026-09-23,Alpha,Bob Jones,brief,09:01,09:03,1.4\n2026-09-23,Alpha,Zed Unknown,present,09:02,09:10,8\n";
S 'log team_of', '["?","Alpha","Alpha","?"]', do { log_report("$dir/b.csv", '2026-09-23', $rep, team_of => sub { team_of($s, $_[0]) }); open my $f, '<', "$dir/b.csv"; my @l = <$f>; [ map { (split /,/)[1] } @l[1 .. 4] ] };

# ---- cards
my $card = member_card($s, 'Bob', last_b => 'cert');
check 'member_card', $card, "Bob - sprint 42 (Alpha)\nIn progress (1, 13 SP):\n  AUTH-103    13  SSO\nYesterday's blocker: cert\nReply in the meeting chat:  Y: <yesterday>  T: <today>  B: <blocker or none>\n";
S 'member_card unknown', 'undef', member_card($s, 'Nobody');
has 'cards_text', cards_text($s, team => 'Bravo'), qr/^Cy - sprint 42 \(Bravo\)/m, qr/Done this sprint: RPT-201/, qr/^Dee - sprint 42/m;
S 'cards_text one team', 0, (cards_text($s, team => 'Bravo') =~ /^Bob - / ? 1 : 0);
S 'teams_chat_link', '"https://teams.microsoft.com/l/chat/0/0?users=a@x.example&message=Hi%20Bob%3A%0A5%20SP"', teams_chat_link('a@x.example', "Hi Bob:\n5 SP");
my $ch = cards_html($s, emails => { Bob => 'bob@x.example' }, marking => { banner => 'INTERNAL' });
has 'cards_html', $ch, qr/<h3>Bob <a href="https:\/\/teams\.microsoft\.com\/l\/chat\/0\/0\?users=bob\@x\.example&amp;message=Bob%20-%20sprint/, qr/<h3>Ann <span class=muted>\(no e-mail known\)/, qr/>INTERNAL<\/p>/;
has 'bulk script', Scrum::outlook_bulk_script([ { to => 'a@x', subject => "S'1", body => 'B' }, { to => 'b@x', subject => 'S2', body => 'C' } ], send => 1),
    qr/^\$o = New-Object -ComObject Outlook\.Application; \$m = \$o\.CreateItem\(0\); \$m\.To = 'a\@x'; \$m\.Subject = 'S''1'; \$m\.Body = 'B'; \$m\.Send\(\); \$m = \$o\.CreateItem\(0\); \$m\.To = 'b\@x'; .*\$m\.Send\(\)$/;
has 'bulk script display', Scrum::outlook_bulk_script([ { to => 'a@x', subject => 's', body => 'b' } ]), qr/\$m\.Display\(\)$/;

# ---- daily.pl: joined, cards, joint-meeting answers, chat est placement
my $proj = tempdir(CLEANUP => 1);
{
    my $cwd = getcwd;
    chdir $proj or die;
    qx("$^X" "$root/bin/daily.pl" init .);
    copy("$root/examples/scrum.txt", 'scrum.txt') or die $!;
    open my $cf, '>>', 'scrum.conf' or die; print $cf "calendar = mock\ncalendar_fixture = $root/examples/cal-fixture.json\nteam_from_subject = ^(\\w+)\\s+stand\n"; close $cf;
    sub dcli { my $o = qx("$^X" "$root/bin/daily.pl" @_ 2>&1); ($? >> 8, $o) }
    my ($rc, $o);
    ($rc, $o) = dcli('--today', '2026-09-23', 'joined');
    S 'joined none', '[1,1]', [ $rc, ($o =~ /no attendance reports for 2026-09-23/ ? 1 : 0) ];
    copy("$root/examples/attendance-2026-09-23-Alpha.csv", 'standups/2026-09-23-Alpha-attendance.csv') or die $!;
    ($rc, $o) = dcli('--today', '2026-09-23', 'joined');
    has 'joined', $o, qr/^Alpha Stand-up  9\/23\/26/m, qr/Bob Jones\s+09:01  09:03    1\.4 min/, qr/4 rows -> attendance\.csv/;
    S 'joined csv', '["2026-09-23,Alpha,Bob Jones,brief,09:01,09:03,1.4"]', [ grep { /Bob Jones/ } map { chomp; $_ } do { open my $f, '<', 'attendance.csv'; <$f> } ];
    open my $j, '>', 'standups/2026-09-23-attendance.csv' or die; print $j "2. Participants\nName,First Join,Last Leave,In-Meeting Duration,Email,Role\nCy Park,9/23/26 9:20:05 AM,9/23/26 9:34:00 AM,13m 55s,cy\@x.example,Presenter\nZed,9/23/26 9:20:05 AM,9/23/26 9:34:00 AM,13m 55s,z\@x.example,Attendee\n"; close $j;
    ($rc, $o) = dcli('--today', '2026-09-23', 'joined');
    has 'joined joint meeting', $o, qr/team unknown for: Zed/;
    S 'joined joint csv', '["2026-09-23,Bravo,Cy Park,present,09:20,09:34,13.9","2026-09-23,?,Zed,present,09:20,09:34,13.9"]', [ grep { /Cy Park|,Zed,/ } map { chomp; $_ } do { open my $f, '<', 'attendance.csv'; <$f> } ];

    ($rc, $o) = dcli('--today', '2026-09-23', 'cards');
    has 'cards', $o, qr/wrote reports\/2026-09-23-cards\.txt/, qr/e-mail known for 4\/4 members \(from today's meeting invitees\)/;
    has 'cards html links', do { open my $f, '<', 'reports/2026-09-23-cards.html'; local $/; <$f> }, qr/users=ann\@example\.com&amp;message=Ann%20-%20sprint%2042/, qr/users=dee\@example\.com/;
    ($rc, $o) = dcli('--today', '2026-09-23', 'cards', '--team', 'Bravo');
    S 'cards one team', 0, (do { open my $f, '<', 'reports/2026-09-23-cards.txt'; local $/; <$f> } =~ /^Ann - / ? 1 : 0);
    open my $ro, '>', 'roster.txt' or die; print $ro "# name, email\nZed, zed\@x.example\nAnn, ann2\@x.example\n"; close $ro;
    ($rc, $o) = dcli('--today', '2026-09-23', 'cards');
    has 'roster used', do { open my $f, '<', 'reports/2026-09-23-cards.html'; local $/; <$f> }, qr/users=ann2\@x\.example/;

    # joint meeting: one chat, answers split by the answerer's team; est/vote lines placed under the story's team
    open my $c, '>', 'standups/2026-09-23-chat.txt' or die; print $c "[9:02 AM] Ann\nY: AUTH-103 done\nT: AUTH-103\nB: none\n[9:02 AM] Cy\nY: RPT-202\nT: RPT-202\nB: waiting on cert\n[9:03 AM] Zed\nY: x\nT: y\nB: -\n[9:05 AM] JC\n#est OPS-302\n[9:05 AM] Ann\n3\n[9:05 AM] Cy\n3\n[9:06 AM] JC\n#vote Demo Friday? y/n\n[9:06 AM] Ann\ny\n[9:06 AM] Cy\ny\n"; close $c;
    ($rc, $o) = dcli('--today', '2026-09-23', 'answers');
    has 'joint answers', $o, qr/unknown team for: Zed/, qr/^Alpha stand-up answers: 1 people, 0 blocked$/m, qr/^Bravo stand-up answers: 1 people, 1 blocked$/m, qr/wrote standups\/2026-09-23-Alpha-answers\.txt/, qr/wrote standups\/2026-09-23-Bravo-answers\.txt/;
    my $su = do { open my $f, '<', 'standups/2026-09-23.txt'; local $/; <$f> };
    has 'joint answers lines', $su, qr/; ---- answers 2026-09-23 Alpha\n== Alpha\n; done AUTH-103   ; Ann say done/, qr/; ---- answers 2026-09-23 Bravo\n== Bravo\nrisk Cy: waiting on cert/;
    ($rc, $o) = dcli('--today', '2026-09-23', 'chat');
    $su = do { open my $f, '<', 'standups/2026-09-23.txt'; local $/; <$f> };
    has 'joint chat est under team', $su, qr/; ---- chat 2026-09-23\n==\n; est OPS-302 3   ; consensus: Ann 3, Cy 3   ; in the master backlog/;   # no team yet -> global, commented
    has 'joint chat vote global', $su, qr/^note vote Demo Friday\? -> y \(y 2\)$/m;
    require Standup;
    S 'joint file parses', '[]', Standup::read_standup('standups/2026-09-23.txt')->{errors};
    ($rc, $o) = dcli('--today', '2026-09-23', 'compile');
    S 'joint compiles', 0, $rc;
    chdir $cwd;
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
