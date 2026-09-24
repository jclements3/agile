#!/usr/bin/perl
# perl t/calendar.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Prelude qw(show fmap);
use Calendar;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub dies_like { my ($name, $re, $code) = @_; eval { $code->(); 1 } ? check($name, 'lived', "died matching $re") : check($name, ($@ =~ $re ? 1 : "no match: $@"), 1) }

my $root = "$FindBin::Bin/..";
my $dir  = tempdir(CLEANUP => 1);

# ---- mock backend from fixture
my $cal = Calendar->new(backend => 'mock', fixture => "$root/examples/cal-fixture.json");
S 'backend', '"mock"', $cal->backend;
S 'events day', '["Alpha Stand-up","Bravo Stand-up","Program sync"]', [ fmap(sub { $_[0]{subject} }, $cal->events(from => '2026-09-23', to => '2026-09-23')) ];
S 'events range', 4, scalar(() = $cal->events(from => '2026-09-23', to => '2026-09-24'));
S 'events match', '["Alpha Stand-up","Bravo Stand-up"]', [ fmap(sub { $_[0]{subject} }, $cal->today(date => '2026-09-23', match => qr/stand-?up/i)) ];
S 'events none', '[]', [ $cal->events(from => '2026-01-01', to => '2026-01-01') ];
my ($alpha, $bravo, $pgm) = $cal->today(date => '2026-09-23');
S 'normalised', '["EV-ALPHA-0923","2026-09-23T09:00:00","2026-09-23T09:15:00",1,1]', [ @{$alpha}{qw(id start end teams recurring)} ];
S 'attendee codes -> names', '[["JC","required","organizer"],["Ann","required","accepted"],["Eve","optional","no response"],["Room 204","resource","accepted"]]',
  [ map { [ @{$_}{qw(name type response)} ] } @{ $alpha->{attendees} }[0, 1, 3, 4] ];
S 'attendee strings kept', '["Cy","required","tentative"]', [ @{ $bravo->{attendees}[1] }{qw(name type response)} ];
S 'teams from body', 1, $bravo->{teams};
S 'not teams', '[0,0]', [ $pgm->{teams}, $pgm->{recurring} ];
S 'find by id', '"Bravo Stand-up"', $cal->find('EV-BRAVO-0923', from => '2026-09-23', to => '2026-09-23')->{subject};
S 'find by subject', '"EV-ALPHA-0923"', $cal->find('alpha', from => '2026-09-23', to => '2026-09-23')->{id};
S 'find none', 'undef', $cal->find('nope', from => '2026-09-23', to => '2026-09-23');

# ---- attendance
my $a = $cal->attendance($alpha);
S 'attendance', '{"accepted":["Ann","Bob"],"all":4,"declined":[],"no response":["Eve"],"none":[],"organizer":["JC"],"tentative":[]}', $a;
S 'attendance resource excluded', 0, scalar grep { $_ eq 'Room 204' } map { @$_ } grep { ref } values %$a;
check 'attendance_text', $cal->attendance_text($bravo), "09:20  Bravo Stand-up  (3 invited)\n  tentative:   Cy\n  declined:    Dee\n";
check 'standup_lines', $cal->standup_lines($bravo), "; 09:20  Bravo Stand-up  (3 invited)\n;   tentative:   Cy\n;   declined:    Dee\n; absent Dee   ; declined in calendar\n";
my $csv = "$dir/att.csv";
S 'log_attendance', 3, $cal->log_attendance($csv, '2026-09-23', 'Alpha', $alpha);
S 'log idempotent', 0, $cal->log_attendance($csv, '2026-09-23', 'Alpha', $alpha);
S 'log other team', 2, $cal->log_attendance($csv, '2026-09-23', 'Bravo', $bravo);
check 'csv content', do { open my $f, '<', $csv; local $/; <$f> }, "date,team,name,status\n2026-09-23,Alpha,Ann,accepted\n2026-09-23,Alpha,Bob,accepted\n2026-09-23,Alpha,Eve,no response\n2026-09-23,Bravo,Cy,tentative\n2026-09-23,Bravo,Dee,declined\n";
S 'team_for regex', '"Bravo"', $cal->team_for($bravo, { team_from_subject => '^(\w+)\s+stand' });
S 'team_for known', '"Alpha"', $cal->team_for($alpha, {}, [ 'Alpha', 'Bravo' ]);
S 'team_for none', 'undef', $cal->team_for($pgm, { team_from_subject => '^(\w+)\s+stand' }, [ 'Alpha' ]);

# ---- writing (mock)
S 'post_text', 1, $cal->post_text($alpha, "metrics\nline2");
has 'post body appended', $alpha->{body}, qr/Daily stand-up\..*\nmetrics\nline2$/s;
$cal->post_text($alpha, 'fresh', replace => 1, send => 1);
S 'post replace', '"fresh"', $alpha->{body};
my $id = $cal->create(subject => 'Charlie Stand-up', start => '2026-10-01T09:40', attendees => [ 'x@y.example' ], weekdays => 1);
S 'create id', '"mock-4"', $id;
S 'create visible', '["Charlie Stand-up","2026-10-01T09:40:00",1,["x@y.example"]]', do { my $e = $cal->find($id, from => '2026-10-01', to => '2026-10-01'); [ @{$e}{qw(subject start recurring)}, [ map { $_->{name} } @{ $e->{attendees} } ] ] };
S 'actions', '[["post","EV-ALPHA-0923",0,0],["post","EV-ALPHA-0923",1,1],["create",undef,undef,undef]]', [ map { [ @{$_}{qw(action id send replace)} ] } $cal->actions ];
dies_like 'create needs subject', qr/need subject and start/, sub { $cal->create(start => 'x') };

# ---- PowerShell builders
my $ps = Calendar::ps_list_events('2026-09-23', '2026-09-24');
has 'ps_list', $ps, qr/^\[Console\]::OutputEncoding = \[Text\.Encoding\]::UTF8/, qr/New-Object -ComObject Outlook\.Application/, qr/GetDefaultFolder\(9\)/,
    qr/IncludeRecurrences = \$true/, qr/Restrict\("\[Start\] >= '09\/23\/2026 00:00' AND \[Start\] <= '09\/24\/2026 23:59'"\)/,
    qr/response = \$rc\.MeetingResponseStatus/, qr/ConvertTo-Json -InputObject @\(\$out\) -Depth 5 -Compress/;
S 'ps no stray placeholders', 0, scalar(() = $ps =~ /__\w+__/g);
my $pp = Calendar::ps_post_text("AB'C", '2026-09-23T09:00:00', "it's done\nline2");
has 'ps_post', $pp, qr/GetItemFromID\('AB''C'\)/, qr/GetOccurrence\(\[datetime\]'2026-09-23T09:00:00'\)/, qr/\$a\.Body = \$a\.Body \+ "`r`n" \+ 'it''s done\nline2'/, qr/^\$a\.Save\(\)$/m;
has 'ps_post send/replace', Calendar::ps_post_text('X', 'S', 'T', send => 1, replace => 1), qr/^\$a\.Body = 'T'$/m, qr/^\$a\.Send\(\)$/m;
my $pc = Calendar::ps_create(undef, subject => 'Alpha Stand-up', start => '2026-10-01T09:00', minutes => 20, attendees => [ 'a@x.example', 'b@x.example' ], weekdays => 1, body => "Daily.");
has 'ps_create', $pc, qr/CreateItem\(1\)/, qr/\$a\.Subject = 'Alpha Stand-up'/, qr/\$a\.Start = \[datetime\]'2026-10-01T09:00'/, qr/\$a\.Duration = 20/, qr/MeetingStatus = 1/,
    qr/Recipients\.Add\('a\@x\.example'\) \| Out-Null\n\$a\.Recipients\.Add\('b\@x\.example'\)/, qr/RecurrenceType = 1; \$p\.DayOfWeekMask = 62/, qr/^\$a\.Display\(\)$/m;
has 'ps_create nodisplay', Calendar::ps_create(undef, subject => 's', start => 't', display => 0), qr/^\$a\.Save\(\)$/m;
S 'ps_create no recur', 0, scalar(() = Calendar::ps_create(undef, subject => 's', start => 't') =~ /RecurrencePattern/g);
S 'ps_encode', '"JABhAA=="', Calendar::ps_encode('$a');       # UTF-16LE base64 of "$a"

# ---- runner through a fake powershell.exe
my $log = "$dir/ps.log";
local $ENV{FAKE_PS_LOG}  = $log;
local $ENV{FAKE_PS_JSON} = '[{"id":"E1","subject":"Alpha Stand-up","start":"2026-09-23T09:00:00","end":"2026-09-23T09:15:00","body":"x","recurring":true,"attendees":[{"name":"Ann","email":"a","type":1,"response":3}]}]';
my $real = Calendar->new(backend => 'outlook', ps_cmd => [ $^X, "$FindBin::Bin/fake-ps.pl" ]);
S 'outlook backend', '"outlook"', $real->backend;
my @ev = $real->events(from => '2026-09-23', to => '2026-09-23');
S 'runner decode', '[["E1","Alpha Stand-up",1,[["Ann","required","accepted"]]]]', [ map { [ $_->{id}, $_->{subject}, $_->{recurring}, [ map { [ @{$_}{qw(name type response)} ] } @{ $_->{attendees} } ] ] } @ev ];
has 'runner script delivered', do { open my $f, '<', $log; local $/; <$f> }, qr/Restrict\("\[Start\] >= '09\/23\/2026 00:00'/;
$ENV{FAKE_PS_JSON} = '{"ok":true,"id":"E1"}';
S 'runner post', 1, $real->post_text($ev[0], 'metrics');
has 'runner post script', do { open my $f, '<', $log; local $/; <$f> }, qr/GetItemFromID\('E1'\)/, qr/'metrics'/;
$ENV{FAKE_PS_JSON} = 'garbage';
dies_like 'bad json', qr/bad JSON from PowerShell/, sub { $real->events(from => '2026-09-23') };
$ENV{FAKE_PS_RC} = 3;
dies_like 'ps failure', qr/powershell failed \(rc=3\)/, sub { $real->events(from => '2026-09-23') };
delete $ENV{FAKE_PS_RC};

# ---- cal.pl
my $bin = "$root/bin/cal.pl";
sub cli { my $out = qx("$^X" "$bin" @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out);
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", '--date', '2026-09-23', 'list');
has 'cli list', $out, qr/^2026-09-23 09:00-09:15  Alpha Stand-up\s+Teams recurring  \[5 attendees\]$/m, qr/Program sync\s+\[0 attendees\]/;
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", '--date', '2026-09-23', 'attend', 'stand', '--csv', "$dir/c2.csv");
has 'cli attend', $out, qr/accepted:    Ann, Bob/, qr/logged 3 rows to/, qr/logged 2 rows to/;
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", '--date', '2026-09-23', 'post', 'bravo', '--text', 'hello');
has 'cli post', $out, qr/posted 5 chars to 'Bravo Stand-up' at 2026-09-23T09:20:00 \(saved\)/, qr/mock actions:\n  post EV-BRAVO-0923/;
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", '--date', '2026-09-23', 'dump');
has 'cli dump json', $out, qr/^\[\s*\{/, qr/"response" : "accepted"/;
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", 'ps');
has 'cli ps', $out, qr/Outlook\.Application/;
($rc, $out) = cli('--mock', "$root/examples/cal-fixture.json", 'nope');
S 'cli bad', 2, $rc;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
