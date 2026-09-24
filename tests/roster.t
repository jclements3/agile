#!/usr/bin/perl
# perl tests/roster.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use Prelude qw(show sorted);
use Scrum;
use Roster;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $root = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

# ---- read: pipe form, old comma form, comments, BOM, trailing spaces
open my $fh, '>:encoding(UTF-8)', "$dir/roster.txt" or die;
print $fh "\x{FEFF}# name | email | team | role | org\nBob | bob\@example.com | Alpha | Dev | ACME  \n\n# old form\nAnn, ann\@example.com\nCy Diaz | | Alpha | Tester |\n";
close $fh;
my $r = read_roster("$dir/roster.txt");
S 'read both forms', '[["Bob","bob@example.com","Alpha","Dev","ACME"],["Ann","ann@example.com","","",""],["Cy Diaz","","Alpha","Tester",""]]', [ map { [ @{$_}{qw(name email team role org)} ] } @$r ];
S 'line numbers kept', '[2,5,6]', [ map { $_->{line} } @$r ];
S 'missing file is empty', '[]', read_roster("$dir/nope.txt");
S 'emails: only real addresses', '{"Ann":"ann@example.com","Bob":"bob@example.com"}', emails($r);
S 'by_team', '["?","Alpha"]', [ sorted(keys %{ by_team($r) }) ];

# ---- write: aligned, sorted by team then name; reads back identically
my $k = write_roster("$dir/out.txt", $r);
S 'write count', 3, $k;
my $back = read_roster("$dir/out.txt");
S 'round trip (sorted by team, name)', '["Ann","Bob","Cy Diaz"]', [ map { $_->{name} } @$back ];
S 'round trip fields', '["bob@example.com","Alpha","Dev","ACME"]', [ @{ $back->[1] }{qw(email team role org)} ];
has 'header comment', do { local $/; open my $f, '<', "$dir/out.txt"; <$f> }, qr/^# name\s+\| email\s+\| team\s+\| role\s+\| org/;

# ---- check against a journal
my $s = load("$root/examples/scrum.txt", today => '2026-09-01');
my @p = roster_check($s, [ { name => 'Bob', email => 'bob@example.com', team => 'Alpha', role => 'Dev', org => '', line => 1 },
                    { name => 'Jim', email => 'sam@example.com', team => 'Alpha', role => 'Solutions Architect', org => 'ACME', line => 2 },
                    { name => 'Ann', email => '', team => 'Bravo', role => '', org => '', line => 3 } ]);
my $txt = join "\n", map { "$_->{level}: $_->{text}" } @p;
has 'check', $txt, qr/warn: Ann owns tasks in the journal but is not in roster\.txt/ ? () : (), qr/warn: Ann: roster team 'Bravo' differs from the journal's 'Alpha'/, qr/info: Jim is in roster\.txt but owns no task in the journal \(fine for a Solutions Architect\)/, qr/warn: Ann: no e-mail/;
S 'no warning for a complete, matching entry', 0, scalar(grep { /Bob/ } split /\n/, $txt);
S 'duplicate names flagged', 1, scalar(grep { $_->{text} =~ /appears twice/ } roster_check($s, [ { name => 'Bob', email => 'b@example.com', team => 'Alpha', line => 1 }, { name => 'Bob', email => 'b@example.com', team => 'Alpha', line => 2 } ]));
has 'roster_text', roster_text($r), qr/^== Alpha \(2\)/m, qr/^  Bob\s+bob\@example\.com\s+Dev\s+ACME/m, qr/^== \? \(1\)/m;

# ---- daily.pl roster / invite against a temp project with the mock calendar
my $proj = tempdir(CLEANUP => 1);
my $daily = "$root/bin/daily.pl";
my $cwd = getcwd();
chdir $proj or die;
sub cli { my $out = qx("$^X" "$daily" --today=2026-09-23 @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out) = cli('init', '.');
open my $c, '>>', 'scrum.conf' or die; print $c "calendar = mock\nmarking_owner = X\nmarking_category = Engineering\nmarking_handling = internal\nmarking_poc = JC\n"; close $c;
open my $j, '>>', 'scrum.txt' or die; print $j "\n2026-09-22 Intake A-1 Task\n    Backlog:Alpha    3 SP   ; id: A-1, owner: Ann Lee\n    Equity:Intake\n"; close $j;
($rc, $out) = cli('roster');
S 'roster: none yet', 1, $rc; has 'roster hint', $out, qr/no roster\.txt yet/;
($rc, $out) = cli('roster', 'add', '"Ann Lee"', 'ann.lee@example.com', 'Alpha', 'Lead', '"ACME"');
S 'roster add', '[0,"added Ann Lee\n"]', [ $rc, $out ];
($rc, $out) = cli('roster', 'add', '"Sam Archer"', 'sam@example.com', 'Alpha', '"Solutions Architect"', 'ACME');
($rc, $out) = cli('roster');
S 'roster lists and agrees', 0, $rc; has 'roster listing', $out, qr/== Alpha \(2\)/, qr/Ann Lee\s+ann\.lee\@example\.com\s+Lead\s+ACME/, qr/2 people, 2 with e-mail, 1 teams/;
($rc, $out) = cli('roster', 'add', '"Ann Lee"', 'ann.lee@example.com', 'Bravo');
($rc, $out) = cli('roster');
S 'roster: team mismatch is a warning (rc 1)', 1, $rc; has 'mismatch text', $out, qr/roster team 'Bravo' differs from the journal's 'Alpha'/;
($rc, $out) = cli('invite', '--dry');
S 'invite --dry', 0, $rc; has 'invite dry', $out, qr/invite: Daily townhall  every weekday from 2026-09-\d\d 07:30, 60 min, Microsoft Teams Meeting/, qr/to 2 attendees: ann\.lee\@example\.com, sam\@example\.com/, qr/--dry: not created/, qr/Y did B-11   T doing B-12   B none/;
($rc, $out) = cli('invite');
S 'invite (mock calendar)', 0, $rc; has 'created', $out, qr/created mock-0/;
open $c, '>>', 'scrum.conf' or die; print $c "mail_domains = example.com\n"; close $c;
($rc, $out) = cli('roster', 'add', '"Ann Lee"', 'ann.lee@other.example', 'Alpha');
($rc, $out) = cli('invite', '--dry');
S 'invite refuses an attendee outside mail_domains (the marking gate)', 1, $rc; has 'gate text', $out, qr/refusing/;
chdir $cwd;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
