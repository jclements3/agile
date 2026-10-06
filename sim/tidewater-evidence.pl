#!/usr/bin/perl
# sim/tidewater-evidence.pl RUN_DIR [--out docs/tidewater] [--sprints 6] -- copy the book's evidence out of a Tidewater run.
#
# RUN_DIR is what `perl sim/tidewater-sim.pl --dir RUN_DIR --sprints N` built (data/tidewater by default). This script
# copies into OUT (docs/tidewater by default, committed) only what the primer cites, and normalizes it so that two runs
# of the same sources give identical bytes:
#
#   OUT/sprints/NN/...      each sprint's evidence as the run wrote it (plan, kickoff, stand-up chat + lint + talk.pl
#                           drafts, poker rounds, refinement, review, review script, retro, quotes, quads, analytics,
#                           morale.json, scorecard.json, pipeline logs, converter/trace/VCRM/recipe reports, samples/ of
#                           the real issue and MR Markdown); NN = 00 (week zero) .. the last sprint asked for
#   OUT/sprints/NN/exports/ `gitlab.pl export` of that sprint (ci_jobs.csv, mrs.csv, issues.csv, defects.csv, tracker/)
#   OUT/journal/            the kit journal at the end of the run (scrum.txt, scrum.conf, roster.txt)
#   OUT/samples/            a curated set: one real example of each GitLab Markdown field (the list is %SAMPLES below)
#   OUT/README.md           an index: every file, one line on what it shows
#
# Normalized: the run directory -> data/tidewater; the kit root -> $KIT; random temp names (/tmp/ci-trace-Ab3dE9) ->
# /tmp/ci-trace-XXXXXX; the perl binary -> perl; this machine's host and user names -> runner / user. Only the
# directories this script owns are replaced (sprints/, journal/, samples/, README.md); memos/ and views/ belong to
# other tools and are left alone.
#
# Exit 0 when written; 1 when a curated sample is missing (the rest is still written); 2 on usage errors.
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path remove_tree);
use File::Find ();
use File::Spec;
use Cwd qw(abs_path);
use Getopt::Long;

my $ROOT = abs_path("$FindBin::Bin/..");
my %o = (out => "$ROOT/docs/tidewater", sprints => 6);
GetOptions(\%o, 'out=s', 'sprints=i', 'quiet', 'only=s') or usage();
usage() if defined $o{only} && $o{only} ne 'work-split';
my $RUN = shift // ($o{only} ? '' : usage());
$o{only} or -d "$RUN/sprints" or die "tidewater-evidence: $RUN has no sprints/ (run perl sim/tidewater-sim.pl --dir $RUN --sprints $o{sprints} first)\n";
$RUN = abs_path($RUN) if length $RUN;
sub usage { print STDERR "usage: tidewater-evidence.pl RUN_DIR [--out DIR] [--sprints N] [--quiet]\n       tidewater-evidence.pl --only work-split [--out DIR] [--sprints N]   (recompute work-split.json from the evidence already in DIR)\n"; exit 2 }

# ---------------------------------------------------------------- normalization
my $host = do { my $h = `hostname 2>/dev/null` // ''; chomp $h; $h };
my $user = $ENV{USER} // $ENV{USERNAME} // '';
sub norm {
    my ($t) = @_;
    my ($run, $kit) = ($RUN, $ROOT);
    for my $p ([ $run, 'data/tidewater' ], [ $kit, '$KIT' ]) {      # longest first: the run may live inside the kit
        my ($from, $to) = @$p;
        $t =~ s/\Q$from\E/$to/g;
        (my $win = $from) =~ s{^/mnt/([a-z])/}{\U$1\E:/};           # the same path as Git for Windows prints it
        $t =~ s/\Q$win\E/$to/gi if $win ne $from;
        (my $cyg = $from) =~ s{^/mnt/([a-z])/}{/$1/};
        $t =~ s/\Q$cyg\E/$to/g if $cyg ne $from;
    }
    $t =~ s{((?:/tmp|/var/tmp|[A-Za-z]:/[^\s"']*?/Temp)/[A-Za-z][A-Za-z0-9.]*-)[A-Za-z0-9_]{4,}\b}{$1XXXXXX}g;   # File::Temp names
    $t =~ s{(/tmp/)tmp[A-Za-z0-9_]{6,}}{$1tmpXXXXXX}g;
    $t =~ s{(?<![\w/])/usr/(?:local/)?bin/perl\b}{perl}g;
    $t =~ s{\bC:/Program Files/Git/usr/bin/perl\.exe\b}{perl}g;
    $t =~ s/\b\Q$host\E\b/runner/g if length $host > 2;
    $t =~ s{/home/\Q$user\E\b}{/home/user}g if length $user > 1;
    $t;
}

sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t // '' }
sub spew { my ($f, $t) = @_; (my $d = $f) =~ s{/[^/]+$}{}; make_path($d) unless -d $d; open my $fh, '>:raw', $f or die "tidewater-evidence: cannot write $f: $!\n"; print $fh $t; close $fh }
sub files_under { my $d = shift; my @f; return () unless -d $d;
    File::Find::find({ no_chdir => 1, wanted => sub { push @f, $File::Find::name if -f $_ } }, $d); sort @f }
sub copy_norm { my ($from, $to) = @_; my $t = slurp($from); defined $t or die "tidewater-evidence: cannot read $from: $!\n";
    spew($to, binary($from, $t) ? $t : norm($t)) }
sub binary { my ($name, $t) = @_; return 1 if $name =~ /\.(?:png|jpg|jpeg|gif|pdf|zip|gz|tar)$/i; return $t =~ /\x00/ ? 1 : 0 }

# ---------------------------------------------------------------- copy
make_path($o{out}); my $OUT = abs_path($o{out});
if ($o{only}) { write_work_split(); print "tidewater-evidence: wrote work-split.json from the evidence in $OUT\n" unless $o{quiet}; exit 0 }
if ($o{only}) { write_work_split(); print "tidewater-evidence: wrote work-split.json from the evidence in $OUT\n" unless $o{quiet}; exit 0 }
my @sprints = grep { -d sprintf("$RUN/sprints/%02d", $_) } 0 .. $o{sprints};
remove_tree("$OUT/$_") for qw(sprints journal samples);
my $n = 0;
for my $s (@sprints) {
    my $src = sprintf "$RUN/sprints/%02d", $s;
    for my $f (files_under($src)) { (my $rel = $f) =~ s{^\Q$src\E/}{}; copy_norm($f, sprintf("$OUT/sprints/%02d/%s", $s, $rel)); $n++ }
    my $ex = sprintf "$RUN/exports/sprint-%02d", $s;
    for my $f (files_under($ex)) { (my $rel = $f) =~ s{^\Q$ex\E/}{}; copy_norm($f, sprintf("$OUT/sprints/%02d/exports/%s", $s, $rel)); $n++ }
}
if (-f "$RUN/checks.txt" && grep { $_ == 6 } @sprints) { copy_norm("$RUN/checks.txt", "$OUT/sprints/checks-s1-s6.txt"); $n++ }   # the run's own consistency checks
for my $f (qw(scrum.txt scrum.conf roster.txt)) { next unless -f "$RUN/journal/$f"; copy_norm("$RUN/journal/$f", "$OUT/journal/$f"); $n++ }

# ---------------------------------------------------------------- curated samples: one real example of each GitLab Markdown field
# name in samples/ => [ what it shows, candidate paths under sprints/ (first that exists wins; globs allowed) ]
my @SAMPLES = (
    [ 'story-issue.md',        'a story issue: the Story template filled in, labels, milestone, its tasks', '01/samples/story-TW-4.md', '0*/samples/story-TW-*.md' ],
    [ 'task-issue.md',         'a task issue: estimate, "Part of", quick actions, closed by a merge request', '01/samples/task-11.md', '0*/samples/task-*.md' ],
    [ 'merge-request.md',      'a merge request: the Default template filled in, "Closes #N", pipeline and approvals', '02/samples/mr-4.md', '0*/samples/mr-*.md' ],
    [ 'mr-review-thread.md',   'a merge request with a review thread (line comment, request changes, resolved)', '~(?i)request(?:ed)? changes', '~(?i)```suggestion', '0[3-6]/samples/mr-*.md' ],
    [ 'milestone.md',          'a sprint milestone description: goal, capacity, dates', '06/samples/milestone.md', '0*/samples/milestone.md' ],
    [ 'prime-drop-issue.md',   'the Prime Drop issue: transmittal record, sha256 check, checklist', 'state:issue:type::drop' ],
    [ 'discrepancy-report.md', 'a discrepancy report to the prime (DR)', '0*/samples/discrepancy-report-DR-1.md', '0*/samples/*discrepancy*.md' ],
    [ 'release-notes.md',      'the release notes of baseline-0', 'state:release:baseline-0', '06/samples/release-*.md', '0*/samples/release*.md' ],
    [ 'wiki-home.md',          'the wiki Home page', '0*/samples/wiki-home.md' ],
    [ 'wiki-definition-of-done.md', 'the Definition of Done wiki page', '0*/samples/wiki-definition-of-done.md' ],
    [ 'wiki-glossary.md',      'the glossary wiki page (systems engineering <-> GitLab)', '0*/samples/wiki-glossary.md' ],
);
my @missing;
for my $s (@SAMPLES) {
    my ($name, $what, @cand) = @$s;
    my ($text, $hit);
    for my $c (@cand) {                    # state:KIND:WHAT (from the emulator), ~REGEX (a sample whose text matches), or a path glob
        if ($c =~ /^state:(\w+):(.+)$/) { $text = state_sample($1, $2); last if defined $text; next }
        my @g = $c =~ /^~(.*)/s ? do { my $re = qr/$1/; grep { (slurp($_) // '') =~ $re } sort glob("$OUT/sprints/*/samples/*.md") }
                                : grep { -f } sort glob("$OUT/sprints/$c");          # glob returns a wildcard-free name even when absent
        if (@g) { $hit = $g[0]; last }
    }
    if (defined $text) { spew("$OUT/samples/$name", norm($text)); $s->[3] = 'the GitLab emulator state, data/tidewater/gitlab/gitlab.json'; $s->[1] = $what; $n++; next }
    if (!$hit) { push @missing, $name; next }
    spew("$OUT/samples/$name", slurp($hit));
    (my $from = $hit) =~ s{^\Q$OUT\E/}{};
    $s->[3] = $from;                                                # where it came from, for the index
    $s->[1] = $what;
    $n++;
}

my $STATE;
sub state {                                                         # the emulator's saved state (JSON::PP is core since 5.14)
    return $STATE if $STATE;
    my $t = slurp("$RUN/gitlab/gitlab.json") // return undef;
    require JSON::PP; $STATE = eval { JSON::PP->new->decode($t) } // return undef;
}
sub _thread { my $notes = shift; join '', map { "\n**\@$_->{author}{username}** ($_->{created_at})" . ($_->{system} ? ' [system]' : '') . ":\n$_->{body}\n" } @{ $notes // [] } }
sub state_sample {                                                  # (kind, what) -> Markdown text, as sim/tidewater-sim.pl writes samples
    my ($kind, $what) = @_;
    my $s = state() // return undef;
    my ($p) = sort { $a->{id} <=> $b->{id} } values %{ $s->{projects} // {} };
    return undef unless $p;
    if ($kind eq 'issue') {                                         # the first issue carrying the label
        my ($i) = sort { $a->{iid} <=> $b->{iid} } grep { my $l = $_->{labels} // []; grep { $_ eq $what } @$l } @{ $p->{issues} // [] };
        return undef unless $i;
        return "# #$i->{iid} $i->{title}\n\nLabels: " . join(', ', map { "~\"$_\"" } @{ $i->{labels} }) . "\n\n$i->{description}\n\n---- comments\n" . _thread($i->{notes});
    }
    if ($kind eq 'release') {
        my ($r) = grep { ($_->{tag_name} // '') eq $what } @{ $p->{releases} // [] };
        return undef unless $r;
        my $links = join '', map { "- [$_->{name}]($_->{url})\n" } @{ $r->{assets}{links} // [] };
        my $ms = join ', ', map { ref $_ ? $_->{title} : $_ } @{ $r->{milestones} // [] };
        return "# Release $r->{name}\n\nTag: `$r->{tag_name}`" . ($r->{released_at} ? ", released $r->{released_at}" : '') . ($ms ? ". Milestones: $ms" : '') . "\n\n"
             . ($r->{description} // '') . ($links ? "\n\n## Assets\n\n$links" : '') . "\n";
    }
    undef;
}

# ---------------------------------------------------------------- work-split.json: where the team spent its time (the primer's BLUF)
# Same keys as sim/tidewater-split.pl (which writes the PLAN). Read only from the evidence in OUT, so it can be recomputed
# from a frozen copy with --only work-split:
#   points    DONE points per work type: each sprint's plan.txt gives every task's points and its story's work type
#             (engineering, platform, learning); a task counts in the sprint whose day-log.txt says "closed #N"; a carried
#             task ("carried #A to #B") keeps A's points and type. committed = the plan's tasks, as planned.
#             points are always POINTS (sums); engineering/platform/learning/overhead are always PERCENT of those points.
#   meetings  sprints/NN/meetings.csv (date,meeting,start,end,attendees): hours per PERSON (Jim, Bob, Tom only; visitors
#             do not count against the team's time), averaged over the sprints. A kickoff that includes the stand-up is a
#             kickoff. time.* = percent of paid hours (3 people x 80 h per sprint) over the sprints in the evidence.
sub write_work_split {
    my $ws = work_split() // return;
    require JSON::PP;
    spew("$OUT/work-split.json", JSON::PP->new->canonical->pretty->encode($ws));
}
sub work_split {
    my @sp = sort { $a <=> $b } map { m{/(\d\d)$} ? $1 + 0 : () } grep { -d } glob("$OUT/sprints/[0-9][0-9]");
    @sp = grep { $_ >= 1 && $_ <= $o{sprints} } @sp;
    return undef unless @sp;
    my $TEAM = qr/^(?:Jim|Bob|Tom)$/;
    my ($PEOPLE, $SPRINT_H, $POINT_H) = (3, 80, 8);
    my (%task, %comm, %closed_in, %carried, %hdr);
    for my $s (@sp) {
        my $p = slurp(sprintf("$OUT/sprints/%02d/plan.txt", $s)) // '';
        if ($p =~ /^Committed: ([\d.]+) points.*?: (.+)$/m) { my ($cp, $mix) = ($1, $2); $hdr{$s}{points} = $cp + 0; $hdr{$s}{$1} = $2 + 0 while $mix =~ /(engineering|platform|learning) ([\d.]+)/g }   # as committed at kickoff (a carried task is listed again below it)
        my $work;
        for my $l (split /\n/, $p) {
            if ($l =~ /^TW-\d+\s+E\d+\s+[\d.]+ pts?\s+(\w+)/) { $work = $1 }
            elsif ($work && $l =~ /^\s+#(\d+)\s+([\d.]+) pts?\b/) { my ($iid, $pts) = ($1, $2); $task{$iid} //= [ $pts, $work ]; $comm{$s}{$work} += $pts }
        }
        my $log = slurp(sprintf("$OUT/sprints/%02d/day-log.txt", $s)) // '';
        $closed_in{$1} //= $s while $log =~ /\bclosed #(\d+)\b/g;
        $carried{$2} = $1 while $log =~ /\bcarried #(\d+) to #(\d+)/g;
    }
    my %done;
    for my $iid (keys %closed_in) {
        my $from = $iid; my %seen; $from = $carried{$from} while !$task{$from} && $carried{$from} && !$seen{$from}++;
        my $t = $task{$from} // next;
        $done{ $closed_in{$iid} }{ $t->[1] } += $t->[0];
    }
    my $pct = sub { my ($n, $d) = @_; $d ? sprintf('%.0f', 100 * $n / $d) + 0 : 0 };
    my $tot = sub { my $h = shift // {}; my $t = 0; $t += $_ for values %$h; $t };
    my (%out, %sum, %sum6);
    for my $s (@sp) {
        my $d = $done{$s} // {}; my $t = $tot->($d);
        $out{$s} = { points => $t + 0, (map { $_ => $pct->($d->{$_} // 0, $t) } qw(engineering platform learning)),
                     overhead => $pct->(($d->{platform} // 0) + ($d->{learning} // 0), $t),
                     committed => ($hdr{$s} ? { (map { $_ => 0 } qw(engineering platform learning)), %{ $hdr{$s} } } : { points => $tot->($comm{$s}) + 0, map { $_ => ($comm{$s}{$_} // 0) + 0 } qw(engineering platform learning) }) };
        $sum{$_} += $d->{$_} for keys %$d;
        if ($s <= 6) { $sum6{$_} += $d->{$_} for keys %$d }
    }
    my $agg = sub { my $h = shift; my $t = $tot->($h); +{ points => $t + 0, map { $_ => $pct->($h->{$_} // 0, $t) } qw(engineering platform learning) } };
    my %ph; my $nsp = 0;                                            # meetings: person-hours by kind
    for my $s (@sp) {
        my $csv = slurp(sprintf("$OUT/sprints/%02d/meetings.csv", $s));
        next unless defined $csv && length $csv;
        $nsp++;
        my @rows = grep { /\S/ } split /\n/, $csv; shift @rows;
        for my $l (@rows) {
            my ($date, $what, $a, $b, $who) = split /,/, $l, 5;
            next unless defined $who && $a =~ /^(\d+):(\d+)$/;
            my $m0 = $1 * 60 + $2; $b =~ /^(\d+):(\d+)$/ or next; my $m1 = $1 * 60 + $2;
            my $n = grep { /$TEAM/ } map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /;/, $who;
            my $kind = $what =~ /kickoff/i ? 'kickoff' : $what =~ /stand-?up/i ? 'standup' : $what =~ /refine/i ? 'refinement'
                     : $what =~ /review|demo/i ? 'review' : $what =~ /retro/i ? 'retro' : 'other';
            $ph{$kind} += ($m1 - $m0) / 60 * $n;
        }
    }
    my %cer = map { $_ => $nsp ? sprintf('%.2f', ($ph{$_} // 0) / $PEOPLE / $nsp) + 0 : 0 } qw(standup kickoff refinement review retro);
    my $ct = 0; $ct += $_ for values %cer; $ct = sprintf('%.2f', $ct) + 0;
    my $paid = @sp * $PEOPLE * $SPRINT_H;
    my $meet = 0; $meet += ($ph{$_} // 0) for qw(standup kickoff refinement review retro);
    my %time = map { $_ => $pct->(($sum{$_} // 0) * $POINT_H, $paid) } qw(engineering platform learning);
    $time{ceremonies} = $pct->($meet, $paid);
    $time{other} = 100 - $time{engineering} - $time{platform} - $time{learning} - $time{ceremonies};
    my $span = "sprints $sp[0]-$sp[-1]";
    return {
        source => "the simulation run (sim/tidewater-sim.pl --sprints $o{sprints}), read from the evidence in docs/tidewater by sim/tidewater-evidence.pl: "
                . "points are DONE points (a task counts in the sprint whose day log closes it; points and work type from that sprint's plan); "
                . "engineering/platform/learning/overhead are percent of those points; meetings from sprints/NN/meetings.csv, hours per person for Jim, Bob "
                . "and Tom; time.* is percent of paid hours (3 people x 80 h per sprint). Only $span ran, so s1_39 covers $span until the later sprints are simulated.",
        sprints => \%out,
        s1_6 => $agg->(\%sum6),
        s1_39 => $agg->(\%sum),
        ceremony_hours => { %cer, total => $ct, share_of_sprint => $pct->($ct, $SPRINT_H) },
        time => \%time,
    };
}
write_work_split(); $n++;

# ---------------------------------------------------------------- index
my @RULES = (                                                       # [ regex on the path under OUT, description ]
    [ qr{^sprints/00/week-zero\.txt$}, 'week zero (29 Sep - 2 Oct 2026): what happened before sprint 1, with hours' ],
    [ qr{/plan\.txt$}, "the sprint's plan: stories, tasks, points, owners, work type" ],
    [ qr{/kickoff\.txt$}, 'the sprint kickoff: goal, capacity, what was committed' ],
    [ qr{/refinement\.txt$}, 'backlog refinement on day 9: new stories, Definition of Ready, estimates' ],
    [ qr{/poker-(\d{4}-\d\d-\d\d)\.txt$}, 'planning poker rounds (#est in the meeting chat, tallied by the kit) on $1' ],
    [ qr{/standups/(\d{4}-\d\d-\d\d)-chat\.txt$}, 'the stand-up statuses as pasted from the meeting chat, $1' ],
    [ qr{/standups/(\d{4}-\d\d-\d\d)-lint\.txt$}, 'the kit\'s lint of that day\'s statuses, $1' ],
    [ qr{/standups/(\d{4}-\d\d-\d\d)-(?:talk|draft)[^/]*$}, 'talk.pl drafts of the stand-up lines (before people edited them), $1' ],
    [ qr{/standups/[^/]+$}, 'a stand-up record' ],
    [ qr{/review-script\.md$}, 'the demo script for the sprint review (drafted with talk.pl review, then edited)' ],
    [ qr{/review\.txt$}, 'the sprint review: what was shown, feedback from management' ],
    [ qr{/retro\.txt$}, 'the retrospective: start / stop / continue, actions' ],
    [ qr{/quotes\.txt$}, 'things people said this sprint (dated)' ],
    [ qr{/quad-(\d{4}-\d\d-\d\d)\.txt$}, 'the weekly status quad for management (daily.pl quad), $1' ],
    [ qr{/analytics\.txt$}, 'gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues' ],
    [ qr{/morale\.json$}, 'the pulse survey at the retrospective: five questions, each person\'s answers, the mean' ],
    [ qr{/checks-s1-s6\.txt$}, 'the simulation\'s consistency checks over sprints 1-6' ],
    [ qr{/scorecard\.json$}, 'the twelve-week scorecard measures at the end of the sprint' ],
    [ qr{/day-log\.txt$}, 'day by day: what happened in GitLab and the journal' ],
    [ qr{/pipelines/mr(\d+)-first-(\d+)\.log$}, 'the first pipeline of merge request !$1 (pipeline #$2): every job log' ],
    [ qr{/pipelines/mr(\d+)-fixed-(\d+)\.log$}, 'merge request !$1 after the fix (pipeline #$2)' ],
    [ qr{/pipelines/mr(\d+)-([a-z0-9-]+?)-(\d+)\.log$}, 'merge request !$1, $2 (pipeline #$3)' ],
    [ qr{/pipelines/nightly-rerun-(\d{4}-\d\d-\d\d)-(\d+)\.log$}, 'the nightly scheduled pipeline re-run on $1 (pipeline #$2)' ],
    [ qr{/pipelines/nightly-(\d{4}-\d\d-\d\d)-(\d+)\.log$}, 'the nightly scheduled pipeline of $1 (pipeline #$2)' ],
    [ qr{/pipelines/[^/]+\.log$}, 'a pipeline log' ],
    [ qr{/samples/story-(TW-\d+)\.md$}, 'story $1 as GitLab shows it (the real issue Markdown)' ],
    [ qr{/samples/task-(\d+)\.md$}, 'task #$1 as GitLab shows it' ],
    [ qr{/samples/mr-(\d+)\.md$}, 'merge request !$1: description, reports, approvals, review notes' ],
    [ qr{/samples/milestone\.md$}, "the sprint's milestone description" ],
    [ qr{/samples/wiki-([a-z0-9-]+)\.md$}, 'the wiki page "$1"' ],
    [ qr{/samples/issue-prime-tbd\.md$}, 'the prime-tbd issue: work going ahead on an assumption about the next drop' ],
    [ qr{/samples/discrepancy-report-(DR-\d+)\.md$}, 'discrepancy report $1 to the prime, as GitLab shows it' ],
    [ qr{/samples/release-([\w.-]+)\.md$}, 'the release $1: notes, assets, milestones' ],
    [ qr{/samples/[^/]+\.md$}, 'a GitLab issue, merge request or page as Markdown' ],
    [ qr{/exports/ci_jobs\.csv$}, 'gitlab.pl export: every CI job (the status-metrics format)' ],
    [ qr{/exports/mrs\.csv$}, 'gitlab.pl export: merge requests with lead times' ],
    [ qr{/exports/issues\.csv$}, 'gitlab.pl export: issues' ],
    [ qr{/exports/defects\.csv$}, 'gitlab.pl export: defects and discrepancy reports' ],
    [ qr{/exports/tracker/}, 'gitlab.pl export: the sprint tracker for status metrics' ],
    [ qr{/doctor-(\w+)\.txt$}, q{kickoff.pl doctor on $1's laptop} ],
    [ qr{/drop1-xmi2sysml-report\.txt$}, 'xmi2sysml --report on prime drop 1: what converted, what is a TODO' ],
    [ qr{/drop1-reqif2sysml-report\.txt$}, 'reqif2sysml --report on drop 1: the DOORS modules' ],
    [ qr{/drop1-trace\.txt$}, 'the first trace of DOORS against the model: C/F/G/I and the drift' ],
    [ qr{/drop\d+-delta\.txt$}, 'the drop delta (xmi2sysml --delta) used in the vendor-branch merge' ],
    [ qr{/recipe-doors\.txt$}, 'the requirements recipe (req-recipe.pl) on the DOORS text' ],
    [ qr{/local-ci-draft\.txt$}, 'the draft pipeline run locally with gitlab.pl ci before the runner existed' ],
    [ qr{/protect-proof\.txt$}, 'proof that a direct push to a protected branch is refused' ],
    [ qr{/setup\.txt$}, 'gitlab.pl setup applying project.conf: labels, milestones, protections, schedules' ],
    [ qr{/day-in-life/todo-list\.txt$}, "Bob's GitLab To-Do list on 2026-12-17" ],
    [ qr{/day-in-life/incident\.md$}, 'the failed nightly of 2026-12-17: the issue opened from it' ],
    [ qr{/day-in-life/}, "Bob's day, 2026-12-17" ],
    [ qr{/weekly-note-(\d{4}-\d\d-\d\d)\.md$}, 'the weekly note to management (drafted with talk.pl weekly), $1' ],
    [ qr{/doc-stages\.txt$}, 'the document review stages (doc:: labels) of the sprint-6 documents, day by day' ],
    [ qr{/briefing[^/]*$}, 'the twelve-week management briefing' ],
    [ qr{^journal/scrum\.txt$}, 'the kit journal (ledger of story points) at the end of the run' ],
    [ qr{^journal/scrum\.conf$}, "the journal's configuration" ],
    [ qr{^journal/roster\.txt$}, 'the roster: Jim, Bob, Tom' ],
);
my @lines;
for my $f (files_under($OUT)) {
    (my $rel = $f) =~ s{^\Q$OUT\E/}{};
    next unless $rel =~ m{^(?:sprints|journal|samples)/};
    my $desc;
    if ($rel =~ m{^samples/(.+)$}) { my ($s) = grep { $_->[0] eq $1 } @SAMPLES; $desc = $s ? "$s->[1] (from $s->[3])" : 'a sample' }
    else {
        for my $r (@RULES) { my ($re, $d) = @$r; if (my @m = $rel =~ $re) { $desc = $d; $desc =~ s{\$(\d)}{$m[$1 - 1] // ''}ge; last } }
        $desc //= 'evidence';
    }
    push @lines, "| `$rel` | $desc |";
}
my $readme = "# Tidewater evidence for the primer\n\n"
  . "Copied by `perl sim/tidewater-evidence.pl RUN_DIR` from a run of `perl sim/tidewater-sim.pl --sprints $o{sprints}`. Tidewater is "
  . "fictional, civilian and notional. Every file below was produced by running the kit (the GitLab emulator, the pipeline, gitflow, the "
  . "converters, the journal); none was written by hand. Paths are normalized (`data/tidewater`, `\$KIT`, `/tmp/...-XXXXXX`) so two runs "
  . "give the same bytes; `tests/tidewater.t` checks that this copy is what the current sources produce.\n\n"
  . "`memos/` and `views/` beside this file are written by other tools (`tools/memo/memo-build.pl`, `sim/tidewater-views.pl`).\n\n"
  . "| File | What it shows |\n|---|---|\n" . join("\n", @lines) . "\n";
spew("$OUT/README.md", $readme);
$n++;

printf "tidewater-evidence: %d file(s) from %s into %s (sprints %s)\n", $n, 'data/tidewater', ($OUT eq "$ROOT/docs/tidewater" ? 'docs/tidewater' : $OUT), join(',', map { sprintf '%02d', $_ } @sprints) unless $o{quiet};
if (@missing) { print STDERR "tidewater-evidence: no sample found for: @missing\n"; exit 1 }
exit 0;
