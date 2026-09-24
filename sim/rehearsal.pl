#!/usr/bin/perl
# rehearsal.pl -- a realistic Teams meeting-chat paste for practising the townhall loop without a team.
#
#   perl sim/rehearsal.pl [--date YYYY-MM-DD] [--seed N] [--mistakes N] [--silent N] [--out FILE]
#
# Reads the project's journal (finds scrum.conf upward from the current directory, like daily.pl) and writes
# what the Teams chat would look like after a townhall: one status per person in the roster, in the formats
# people really use, seeded with the usual mistakes -- lowercase delimiters, a second 'b' as a word, prose with
# no task id, an unknown id, someone answering for a colleague, a #est round in the middle, reactions, join/leave
# noise -- and N silent people. Prints an answer key to stderr: who is wrong and why, so you can check what
# lint and answers make of it. Standalone, not part of the tested kit.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Prelude qw(sorted);
use Scrum;
use Standup qw(read_conf);

my %o = (seed => 1, mistakes => 4, silent => 1);
GetOptions(\%o, 'date=s', 'seed=i', 'mistakes=i', 'silent=i', 'out=s') or exit 2;
srand($o{seed});

my $conf_path = _find_conf() or die "no scrum.conf here or above\n";
(my $base = $conf_path) =~ s{/[^/]*$}{};
my $conf = read_conf($conf_path);
my $today = $o{date} // do { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] };
my $s = load("$base/$conf->{journal}", today => $today);
my $n = $s->{current} // die "no current sprint in the journal: plan one first (commit lines in a stand-up file)\n";

my %people;                                    # who -> [ up to two tasks to talk about ]: everyone on the roster answers every day, whatever the state of their work --
my $m = members($s);                           # committed first, then queued, then finished (a person whose sprint work is done still reports, and talks about what is next)
for my $w (keys %$m) { my @it = (@{ $m->{$w}{wip} }, @{ $m->{$w}{backlog} }, @{ $m->{$w}{done} }); $people{$w} = [ @it[0 .. ($#it < 1 ? $#it : 1)] ] if @it }
my @who = sorted(keys %people) or die "nobody owns a task in the journal\n";
my @all_ids = map { $_->{id} } items($s);

my @lines = ("Meeting started", "Sam Archer joined the meeting.");
my @key;
my $hm = 8 * 60 + 31;
sub stamp { my $m = $hm++; sprintf '[%d:%02d AM]', int($m / 60), $m % 60 }
my @silent = @who[0 .. $o{silent} - 1]; @silent = () if $o{silent} <= 0;
my %silent = map { $_ => 1 } @silent;
my @mistake_pool = qw(lowercase_ambiguous prose_no_id unknown_id wrong_owner missing_b labels_only_y);
my %mistake; for my $w (grep { !$silent{$_} } @who) { last if keys %mistake >= $o{mistakes}; $mistake{$w} = $mistake_pool[ keys(%mistake) % @mistake_pool ] }

my $i = 0;
for my $w (@who) {
    next if $silent{$w};
    my @it = @{ $people{$w} };
    my ($a, $b) = ($it[0], $it[1] // $it[0]);
    my $m = $mistake{$w} // '';
    my $line;
    if    ($m eq 'lowercase_ambiguous') { $line = "y finished $a->{id} t will b in the lab on $b->{id} b none"; push @key, "$w: ERROR -- second lowercase b is a word; lint should say 'B' appears 2 times and guess Y finished $a->{id} / T will b in the lab on $b->{id} / B none" }
    elsif ($m eq 'prose_no_id')        { $line = "Y wrapped up the review T more of the same B none"; push @key, "$w: warn -- no task id in Y or T" }
    elsif ($m eq 'unknown_id')         { $line = "Y $a->{id} done T ZZ-999 B none"; push @key, "$w: warn -- ZZ-999 is not in the journal; and a 'done' claim on $a->{id} for you to confirm" }
    elsif ($m eq 'wrong_owner')        { my ($other) = grep { $_->{owner} && $_->{owner} ne $w } items($s, state => 'committed', sprint => $n); $line = "Y $a->{id} T " . ($other ? $other->{id} : $b->{id}) . " B none"; push @key, "$w: info -- working " . ($other ? "$other->{id} which is owned by $other->{owner}" : 'own task') }
    elsif ($m eq 'missing_b')          { $line = "Y $a->{id} T $b->{id}"; push @key, "$w: ERROR -- no B found" }
    elsif ($m eq 'labels_only_y')      { $line = "Y: $a->{id} in progress"; push @key, "$w: incomplete -- only Y given (answers flags incomplete)" }
    else {
        my $style = $i++ % 4;
        $line = $style == 0 ? "Y $a->{id} T $b->{id} B none"
              : $style == 1 ? "Y: $a->{id} nearly done\nT: $b->{id}\nB: none"
              : $style == 2 ? "$w Y finished $a->{id} T start $b->{id} B none"
              :               "yesterday: $a->{id}  today: $b->{id}  blockers: waiting on ICD from SEI";
        push @key, "$w: ok" . ($style == 3 ? ' -- blocked (waiting on ICD), expect a block flag' : '');
    }
    push @lines, stamp() . " $w", $line;
    push @lines, "\x{1F44D} 2" if rand() < 0.3;
}
# a #est round in the middle, a reply to it, someone leaving
my $at = scalar @lines;                        # insert the round between two complete messages: just before the third header line, never between a header and its status
my @hdr = grep { $lines[$_] =~ /^\[\d+:\d\d [AP]M\] / } 0 .. $#lines;
$at = $hdr[2] if @hdr > 2;
splice @lines, $at, 0, stamp() . " Sam Archer", "#est $all_ids[0]", stamp() . " $who[-1]", "5";
push @lines, "$who[-1] left the meeting.", "Meeting ended";

my $text = join("\n", @lines) . "\n";
my $out = $o{out} // "$base/$conf->{standups}/$today-chat.txt";
mkdir "$base/$conf->{standups}" unless -d "$base/$conf->{standups}";
open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n"; print $fh $text; close $fh;
print "wrote $out  (" . scalar(grep { !$silent{$_} } @who) . " answered, " . scalar(@silent) . " silent, " . scalar(keys %mistake) . " mistakes)\n";
print STDERR "answer key:\n", map { "  $_\n" } @key, (map { "$_: SILENT -- expect 'no answers in chat' (or an assumed status with --assume)" } @silent);
print "next: perl bin/daily.pl lint   |   lint --reply   |   answers   |   answers --assume\n";

sub _find_conf { require Cwd; my $d = Cwd::getcwd(); while (1) { return "$d/scrum.conf" if -f "$d/scrum.conf"; my $up = $d =~ s{/[^/]+$}{}r; last if $up eq $d || $up eq ''; $d = $up } undef }
