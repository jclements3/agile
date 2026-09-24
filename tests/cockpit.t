#!/usr/bin/perl
# perl tests/cockpit.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP ();
use Prelude qw(show sorted);
use Scrum;
use Cockpit;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $s = load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01');
$s->{unit} = 'SP';

# ---- snapshot
my $snap = snapshot($s, days => [ { date => '2026-09-01', teams => { Alpha => { answered => 2, roster => 2, flags => [] } } } ], plates => 'plates.html', marking => { banner => 'INTERNAL', marking_poc => 'JC' });
S 'current + teams', '[42,["Alpha","Bravo"]]', [ $snap->{current}, $snap->{teams} ];
S 'sprints', '[[41,"2026-08-10","2026-08-24"],[42,"2026-08-24","2026-08-28"]]', [ map { [ $_->{n}, $_->{start}, $_->{end} ] } @{ $snap->{sprints} } ];
S 'sprint 42 totals', '[26,8,18,31,108]', [ @{ $snap->{sprints}[1]{totals} }{qw(committed done open pct load)} ];
S 'cards', '[["Alpha",13,0,"warning",1],["Bravo",13,8,"warning",1]]', [ map { [ $_->{team}, $_->{committed}, $_->{done}, $_->{status}, scalar @{ $_->{open_items} } ] } @{ $snap->{cards} } ];
S 'card open item', '["AUTH-103",13,"Bob","Auth"]', [ @{ $snap->{cards}[0]{open_items}[0] }{qw(id pts owner epic)} ];
S 'daily done on 2026-08-28', 8, $snap->{daily}{'2026-08-28'}{done};
S 'daily intake on 2026-08-03', 16, $snap->{daily}{'2026-08-03'}{intake};
S 'velocity', '[8,2]', [ $snap->{velocity}{Alpha}{avg}, $snap->{velocity}{Bravo}{avg} ];
S 'epics', '[["(none)","Auth",38,["Alpha"]],["(none)","Ops",40,["Bravo","Master"]],["(none)","Reporting",62,["Bravo"]]]', [ map { [ $_->{tome}, $_->{epic}, $_->{pct}, $_->{teams} ] } @{ $snap->{epics} } ];
S 'tree', '[["(none)",3,"Auth",3,0]]', [ map { [ $_->{tome}, scalar @{ $_->{epics} }, $_->{epics}[0]{epic}, scalar @{ $_->{epics}[0]{tasks} }, $_->{epics}[0]{integration} ] } @{ $snap->{tree} } ];
S 'integration flag', 1, $snap->{tree}[0]{epics}[1]{integration};
S 'brief', '["amber",1]', [ $snap->{brief}{level}, scalar @{ $snap->{brief}{bullets} } > 0 ? 1 : 0 ];
S 'roadmap sprints', '[41,42,43,44,45]', $snap->{roadmap}{sprints};
S 'days passthrough', '"2026-09-01"', $snap->{days}[0]{date};
S 'plates + marking', '["plates.html","INTERNAL",["POC: JC"]]', [ $snap->{plates}, $snap->{marking}{banner}, $snap->{marking}{lines} ];
S 'backlog master', '["OPS-302"]', [ map { $_->{id} } @{ $snap->{backlog}{master} } ];
my $json = JSON::PP->new->canonical->encode($snap);
S 'snapshot is JSON-clean', 1, (defined eval { JSON::PP->new->decode($json) } ? 1 : 0);

# ---- page
my $html = cockpit_html($s, marking => { banner => 'INTERNAL' }, plates => 'plates.html');
has 'cockpit page', $html, qr/^<!DOCTYPE html>/, qr/<p class="mark mark-top">INTERNAL<\/p>/, qr/<script id="snap" type="application\/json">\{/, qr/"current":42/, qr/id="tabs"/, qr/function viewDaily\(\)/, qr/function viewRoadmap\(\)/, qr/function viewGantt\(\)/, qr/\['gantt','Gantt'\]/, qr/function viewTutorial\(\)/, qr/\['tutorial','Tutorial'\]/, qr/<p class="mark mark-bottom">INTERNAL<\/p>/;
S 'tutorial path passes through', 1, (cockpit_html($s, tutorial => 'docs/TUTORIAL.html') =~ /"tutorial":"docs\/TUTORIAL.html"/ ? 1 : 0);
S 'nothing external', 1, ($html !~ m{https?://|<link |<script src} ? 1 : 0);
S 'script tag safe', 1, ($html =~ /<\/script>/ && (() = $html =~ /<script/g) == 2 ? 1 : 0);
my ($embedded) = $html =~ /<script id="snap" type="application\/json">(.*?)<\/script>/s;
S 'embedded snapshot decodes', 42, JSON::PP->new->decode($embedded)->{current};
S 'logo inlined', (-f "$FindBin::Bin/../assets/logo.svg" ? 1 : 0), ($html =~ m{<svg class="logo" viewBox="0 0 1209 317"} && $html !~ m{00C18F} ? 1 : 0);
S 'report logo inlined', (-f "$FindBin::Bin/../assets/logo.svg" ? 1 : 0), (dashboard_html($s) =~ m{<h1><svg class="logo"} ? 1 : 0);
S 'script is ASCII-clean', 1, (do { my ($js) = $html =~ m{<script>(.*)</script>}s; $js =~ /[^\x00-\x7f]/ ? 0 : 1 });
S 'no plates -> null', 1, (cockpit_html($s) =~ /"plates":null/ ? 1 : 0);
S 'build time in the header (a shared screen shows it is live)', 1, ($html =~ /built <b id="built">\d\d:\d\d<\/b>/ ? 1 : 0);
S 'people tab: roster in the snapshot, view present', '[1,1,1]', do { my $p = cockpit_html($s, roster => [ { name => 'Bob', email => 'b@example.com', team => 'Alpha', role => 'Dev', org => 'ACME' } ], readback_clean_days => 3); [ ($p =~ /"roster":\[\{"email":"b\@example.com","name":"Bob","org":"ACME","role":"Dev","team":"Alpha"\}\]/ ? 1 : 0), ($p =~ /function viewPeople\(\)/ ? 1 : 0), ($p =~ /\['people','People'\]/ ? 1 : 0) ] };
S 'snapshot keys', '["attendance","backlog","blocked","brief","cards","current","daily","days","epics","file","generated","marking","plates","plates_index","roadmap","roster","sprints","teams","training","tree","tutorial","unassigned","unit","velocity"]', [ sorted(keys %{ snapshot($s) }) ];
S 'no plates file -> empty index', '[]', plates_index(undef);
my $pl = "$FindBin::Bin/../data/demo/reports/plates.html";
if (-f $pl) {
    my $ix = plates_index($pl);
    S 'plates index first rows', '[["E0","Executive & Strategy","p.2",0],["E1","Set Direction","p.3",1]]', [ map { [ @{$_}{qw(node title page depth)} ] } @{$ix}[0,1] ];
    S 'plates index has & unescaped', 1, ((grep { $_->{title} =~ /&(?!amp;)/ } @$ix) ? 1 : 0);
    S 'plates index depth from node', '[0,1,2,3,4]', [ map { $_->{depth} } grep { $_->{node} =~ /^E(0|2|22|222|2222)$/ } @$ix ];
}

# ---- days_from_standups against a temp standups dir
use File::Temp qw(tempdir);
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/2026-09-01-Alpha-answers.txt" or die $!;
print $fh "2026-09-01 Alpha\nBob (08:31)\n  Y: finished AUTH-103, merged\n  T: start AUTH-104\n  B: none\n";
close $fh;
my $days = days_from_standups($s, $dir, 5);
S 'days_from_standups', '[["2026-09-01","Alpha",1,2]]', [ map { my $d = $_; map { [ $d->{date}, $_, $d->{teams}{$_}{answered}, $d->{teams}{$_}{roster} ] } sorted(keys %{ $d->{teams} }) } @$days ];
S 'days flags computed', 1, (scalar(@{ $days->[0]{teams}{Alpha}{flags} }) >= 1 ? 1 : 0);
S 'days carry each person\'s parsed Y/T/B', '[["Bob","finished AUTH-103, merged","start AUTH-104","none",0,0,1]]', [ map { [ @{$_}{qw(who y t b blocked assumed complete)} ] } @{ $days->[0]{teams}{Alpha}{answers} } ];
S 'daily view renders the statuses table', 1, (cockpit_html($s, days => $days) =~ /function ids\(text\)/ && cockpit_html($s, days => $days) =~ /Statuses today/ ? 1 : 0);

# ---- the script must not touch `state` before `var state = ...` runs (a top-level TypeError blanks every tab)
{ my ($js) = $html =~ m{<script>(.*)</script>}s;
  my ($before) = $js =~ /\A(.*?)^var state = /ms;
  my @bad = grep { /^(?:try\s*\{\s*)?state\./ } split /\n/, $before // '';
  S 'no top-level state use before its declaration', '[]', \@bad; }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
