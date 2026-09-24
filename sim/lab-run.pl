#!/usr/bin/perl
# lab-run.pl -- N simulated townhall days against the current project, unattended, the way the architect would run them.
#
#   perl sim/lab-run.pl [--days 10] [--start YYYY-MM-DD] [--seed N] [--fix 0.7] [--perl PATH] [--report FILE]
#
# Each day: rehearsal.pl writes a realistic chat paste (mistakes seeded, some people silent); lint; lint --reply
# (the corrections); then a fraction (--fix) of the people who got an ERROR repost a clean line (a second paste
# appended to the same chat file, later message wins); lint again; answers --guess --assume; the suggested
# "done" lines are confirmed (uncommented) so points move; compile; report; commit. Weekends are skipped.
# Every step's exit code and timing are recorded; anything unexpected (a step failing, a flag that should not
# exist, a person attributed to the wrong team) is written to the report as a finding. Standalone, not part of
# the tested kit; runs against whatever project directory you are in (never data/demo: training.pl wipes it).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Time::HiRes qw(time);
use POSIX qw(strftime mktime);
use Cwd qw(getcwd);

my %o = (days => 10, seed => 1, fix => 0.7, perl => $^X);
GetOptions(\%o, 'days=i', 'start=s', 'seed=i', 'fix=f', 'perl=s', 'report=s') or exit 2;
my $KIT = "$FindBin::Bin/..";
-f 'scrum.conf' or die "run this inside a project directory (scrum.conf not found)\n";
getcwd() =~ m{/data/demo/?$} and die "not in data/demo: training.pl wipes that directory\n";

my @findings; my @log;
use IPC::Open3 qw(open3);
sub run {                                     # list form (the target Perl's path has a space in it), stdout+stderr captured; core IPC::Open3 works on cygwin Perl too
    my ($label, @cmd) = @_; my $t = time;
    my $pid = open3(my $in, my $outh, undef, @cmd); close $in;
    my $out = do { local $/; <$outh> } // ''; waitpid $pid, 0;
    my $rc = $? >> 8; push @log, sprintf("%-46s rc=%d %5.1fs", $label, $rc, time - $t); return ($rc, $out);
}
sub finding { push @findings, "@_"; print STDERR "  ! @_\n" }
sub next_day { my ($y, $m, $d) = split /-/, shift; my $t = mktime(0, 0, 12, $d, $m - 1, $y - 1900); do { $t += 86400 } while ((localtime $t)[6] =~ /^[06]$/); strftime('%Y-%m-%d', localtime $t) }

my $date = $o{start} // do { my @t = localtime; strftime('%Y-%m-%d', @t) };
$date = next_day($date) if (localtime(mktime(0, 0, 12, (split /-/, $date)[2], (split /-/, $date)[1] - 1, (split /-/, $date)[0] - 1900)))[6] =~ /^[06]$/;
my $P = $o{perl};
my @days;
for my $i (1 .. $o{days}) {
    my $seed = $o{seed} * 100 + $i;
    print "== day $i  $date\n";
    my %d = (date => $date);
    my ($rc, $out);
    ($rc, $out) = run("rehearsal", $P, "$KIT/sim/rehearsal.pl", '--date', $date, '--seed', $seed, '--mistakes', 4 + $i % 3, '--silent', 1 + $i % 2);
    finding("day $i: rehearsal failed: $out") if $rc;
    ($d{answered}, $d{silent}, $d{mistakes}) = $out =~ /\((\d+) answered, (\d+) silent, (\d+) mistakes\)/;
    ($rc, $out) = run("lint (round 1)", $P, "$KIT/bin/daily.pl", "--today=$date", 'lint');
    ($d{errors1}, $d{warn1}) = $out =~ /(\d+) errors?, (\d+) warnings?/;
    finding("day $i: lint round 1 reported nobody answered") unless $out =~ /^# \d+ answered/m && $out !~ /^# 0 answered/m;
    ($rc, $out) = run("lint --reply", $P, "$KIT/bin/daily.pl", "--today=$date", 'lint', '--reply');
    my @replies = grep { /\S/ } split /\n/, $out;
    $d{replies} = scalar @replies;
    # a fraction of the people with an ERROR repost a clean line (the lint's "repost as" example, made personal)
    my @errs = map { /^Hey (\S+)!/ ? $1 : () } grep { /Did you mean|couldn't read/ } @replies;
    my $chat = "standups/$date-chat.txt";
    my %full;                                 # first name -> the full display name as it appears in the chat headers (the reply says "Hey Bob!")
    if (open my $ch, '<', $chat) { while (<$ch>) { if (/^\[\d+:\d\d [AP]M\] (.+?)\s*$/) { my $n = $1; my ($f) = $n =~ /^(\S+)/; $full{$f} //= $n } } close $ch }
    my $n_fix = 0;
    if (@errs && open my $fh, '>>', $chat) {
        for my $first (@errs) { next if rand() > $o{fix}; my ($ex) = $out =~ /repost as: (Y did \S+ T doing \S+ B none)/; print $fh "[8:44 AM] " . ($full{$first} // $first) . "\n$ex\n" if $ex; $n_fix++ }
        close $fh;
    }
    $d{reposted} = $n_fix;
    ($rc, $out) = run("lint (round 2, after reposts)", $P, "$KIT/bin/daily.pl", "--today=$date", 'lint');
    ($d{errors2}, $d{warn2}) = $out =~ /(\d+) errors?, (\d+) warnings?/;
    finding("day $i: reposts did not reduce errors ($d{errors1} -> $d{errors2}) with $n_fix reposts") if $n_fix && defined $d{errors2} && $d{errors2} >= $d{errors1};
    ($rc, $out) = run("answers --guess --assume", $P, "$KIT/bin/daily.pl", "--today=$date", 'answers', '--guess', '--assume');
    finding("day $i: answers failed (rc=$rc): " . substr($out, 0, 300)) if $rc;
    finding("day $i: answers could not place someone in a team: $1") if $out =~ /unknown team for: (.*)/;
    $d{flags} = () = $out =~ /^  (?:RED|AMBER|INFO) /mg;
    $d{assumed} = () = $out =~ /ASSUMED/g;
    $d{done_suggested} = () = $out =~ /says (\S+) is done/g;
    # confirm the suggested lines: the architect's "yes" (uncomment done, and the four-letter words punt / hold / pass / redo / sync)
    my $su = "standups/$date.txt";
    my %words;
    if (-f $su) { local @ARGV = ($su); local $^I = ''; while (<>) { if (s/^;\s*((?:done|punt|hold|pass|redo|sync) \S+.*?)\s*;.*$/$1/) { $words{$1}++ if $1 =~ /^(punt|hold|pass|redo|sync)/ } print } }
    $d{words} = join(' ', map { "$_=$words{$_}" } sort keys %words) || '-';
    ($rc, $out) = run("compile", $P, "$KIT/bin/daily.pl", "--today=$date", 'compile');
    finding("day $i: compile failed: " . substr($out, 0, 400)) if $rc;
    ($d{transactions}) = $out =~ /\((\d+) transactions\)/;
    ($rc, $out) = run("report", $P, "$KIT/bin/daily.pl", "--today=$date", 'report');
    finding("day $i: report failed: " . substr($out, 0, 300)) if $rc;
    ($rc, $out) = run("quad", $P, "$KIT/bin/daily.pl", "--today=$date", 'quad');
    finding("day $i: quad failed (rc=$rc): " . substr($out, 0, 300)) if $rc;
    finding("day $i: a punt was confirmed but the quad shows no PUNT") if $d{words} =~ /punt=/ && $out !~ /^  PUNT /m;
    finding("day $i: a hold was confirmed but the quad shows no HOLD") if $d{words} =~ /hold=/ && $out !~ /^  HOLD /m;
    ($d{punt_rate}) = $out =~ /^  sprint \d+\s+Total\s+\d+ \/ \d+\s+(\d+)%/m;
    ($rc, $out) = run("status", $P, "$KIT/bin/daily.pl", "--today=$date", 'status');
    ($d{status}) = $out =~ /(sprint \d+: .*)/;
    ($rc, $out) = run("commit", $P, "$KIT/bin/daily.pl", "--today=$date", 'commit');
    finding("day $i: commit failed: $out") if $rc;
    push @days, \%d;
    printf "   answered %d silent %d | lint %d->%d errors, %d replies, %d reposted | flags %d (assumed %d, done %d) | words %s | %s\n",
        $d{answered} // 0, $d{silent} // 0, $d{errors1} // 0, $d{errors2} // 0, $d{replies}, $n_fix, $d{flags}, $d{assumed}, $d{done_suggested}, $d{words}, $d{status} // '';
    $date = next_day($date);
}

# ---- the report
my $rep = $o{report} // "reports/lab-run.txt";
mkdir 'reports' unless -d 'reports';
open my $r, '>', $rep or die "cannot write $rep: $!\n";
print $r "lab run: $o{days} days, seed $o{seed}, fix rate $o{fix}, perl $P\n\n";
printf $r "%-11s %4s %4s %6s %6s %5s %5s %5s %4s %s\n", 'date', 'ans', 'sil', 'err1', 'err2', 'repl', 'flags', 'assum', 'done', 'status';
printf $r "%-11s %4d %4d %6d %6d %5d %5d %5d %4d %s\n", @{$_}{qw(date answered silent errors1 errors2 replies flags assumed done_suggested)}, $_->{status} // '' for @days;
print $r "\nsteps:\n", map { "  $_\n" } @log;
print $r "\nfindings:\n", (@findings ? map { "  - $_\n" } @findings : "  none\n");
close $r;
print "wrote $rep  (" . scalar(@findings) . " findings)\n";
exit(@findings ? 1 : 0);
