#!/usr/bin/env perl
# talk.pl -- drafts the words for a stand-up, a sprint review demo, or a weekly note to management, from what GitLab
# (and, optionally, the kit's journal) already knows. It DRAFTS ONLY: it prints text for a person to read, edit and
# say; it never posts, comments, labels or changes anything (every GitLab call it makes is a read).
#
# Why: engineers who know exactly what they did often say it as mechanism ("fixed lint warnings on the connector
# ends") or say nothing. Management hears progress as outcome -> one number -> next step or ask. talk.pl starts the
# sentence in that shape so the person only has to correct it.
#
#   perl tools/gitlab/talk.pl [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME] COMMAND ...
#     standup --as USER [--date D] [--journal DIR] [--prefix TW-] [--why]
#             one terse Y/T/B line in the kit's format (daily.pl lint passes it), outcome first, one number;
#             a blocked issue (label workflow::blocked) becomes an ask
#     review  --sprint N [--baseline FILE] [--metrics FILE] [--journal DIR] [--md]
#             a sprint-review demo script: the question, four headline numbers with change (TODO lines; requirements
#             with a verification case, from the trace -- not the VCRM's passing results, shown apart; open DRs and
#             prime changes; blocked items), what to show, one
#             before/after, a safe live change, what it means for the next milestone, the ask; 30-second and
#             1-sentence versions
#     weekly  [--date D] [--baseline FILE] [--metrics FILE] [--md]
#             a plain-language weekly note: headline = conclusion, three numbers, risks, asks (pairs with daily.pl quad)
#     translate FILE|- [--glossary FILE] [--md]
#             lists jargon with plain alternatives and hints, flags "so what?" sentences (no number, no outcome, long,
#             passive) with a template SUGGESTION; never rewrites your sentences (only safe noun-for-noun swaps)
#     help
#   Environment: GITLAB_LOCAL, GITLAB_URL, GITLAB_PROJECT, TALK_PREFIX (the story id prefix, e.g. TW-). --curl CMD replaces curl (tests).
#
# Where the numbers come from: issues, merge requests, pipelines and milestones (any GitLab tier, read-only). The
# pipeline's metrics reports (todo_lines, trace_*, vcrm_verified_pct, recipe_findings, from ci/job.pl) are read from
# the local emulator's pipelines, and on a real GitLab from the develop pipeline's artifacts (todo.metrics, trace.metrics,
# vcrm.metrics, recipe.metrics via the jobs API; latest values only, so no "change since"). --metrics FILE overrides both.
# A --baseline file holds the document-era numbers you want to compare with, one per line:
#     review_hours = 360 | a document review cycle: 3 weeks of comments on a Word file
#     lead_hours   = 552 | a change through the CCB: 23 working days
#     trace_hours  = 16  | answering "which requirements are unverified?" from spreadsheets
# Core Perl. Exit 0, 2 on a usage error.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long qw(GetOptionsFromArray);
use Time::Local qw(timegm);
use GitLab;

binmode STDOUT, ':utf8';
my @DOW = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MON = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub usage { print STDERR "usage: talk.pl [--local DIR | --url URL] [--project GROUP/NAME] standup|review|weekly|translate|help ...\n"; exit 2 }
sub help {
    open my $fh, '<', __FILE__ or die "talk: cannot read " . __FILE__ . ": $!\n";
    while (<$fh>) { last if /^use strict/; next if /^#!/; s/^# ?//; print }
    exit 0;
}

# ---------------------------------------------------------------- small helpers
sub ep { my $s = shift; return undef unless defined $s && $s =~ /^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?/;   # ISO -> epoch (UTC)
         my $t = timegm($6 // 0, $5 // 0, $4 // 0, $3, $2 - 1, $1);
         $t -= ($1 eq '-' ? -1 : 1) * ($2 * 3600 + $3 * 60) if $s =~ /([+-])(\d\d):?(\d\d)$/;
         $t }
sub day { my $t = shift; my @g = gmtime $t; sprintf '%04d-%02d-%02d', $g[5] + 1900, $g[4] + 1, $g[3] }
sub dow { $DOW[ (gmtime(ep($_[0])))[6] ] }
sub nice_date { my @g = gmtime(ep($_[0])); "$DOW[$g[6]] $MON[$g[4]] $g[3]" }
sub prev_workday { my $t = ep(shift); do { $t -= 86400 } while ((gmtime $t)[6] == 0 || (gmtime $t)[6] == 6); day($t) }
sub short { my ($t, $n) = @_; $n //= 40; $t //= ''; $t =~ s/\s+/ /g; $t =~ s/^\s+|\s+$//g; return $t if length $t <= $n;
            my $c = substr($t, 0, $n); $c =~ s/\s+\S*$//; $c . '...' }
sub lcfirst_word { my $t = shift; $t =~ s/^([A-Z])(?=[a-z])/lc $1/e; $t }
sub plural { my ($n, $w) = @_; return "$n $w" if $n == 1; $w =~ s/([^aeiou])y$/$1ie/; "$n ${w}s" }
sub labels_of { my $x = shift; [ map { ref $_ ? $_->{name} : $_ } @{ $x->{labels} // [] } ] }
sub has_label { my ($x, $l) = @_; scalar grep { $_ eq $l } @{ labels_of($x) } }
sub assigned_to { my ($x, $u) = @_; scalar grep { lc($_->{username} // '') eq lc $u } @{ $x->{assignees} // [] } }
sub in_window { my ($ts, $from, $to) = @_; my $t = ep($ts); defined $t && $t >= $from && $t < $to }
sub median { my @v = sort { $a <=> $b } grep { defined } @_; return undef unless @v; @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2 }
sub r1 { my $v = shift; defined $v ? 0 + sprintf('%.1f', $v) : undef }
sub fmt_hours { my $h = shift; return '-' unless defined $h; $h >= 48 ? sprintf('%.1f days', $h / 24) : $h >= 1 ? sprintf('%.1f h', $h) : sprintf('%d min', $h * 60 + 0.5) }

# ---------------------------------------------------------------- connection and project data
sub connect_gl {
    my ($o) = @_;
    my $local = $o->{local} // ($o->{url} ? undef : $ENV{GITLAB_LOCAL});
    my $url = $o->{url} // ($local ? undef : $ENV{GITLAB_URL});
    my $gl = defined $local ? GitLab->new(local => $local, freeze => 1)
           : defined $url ? GitLab->new(url => $url, token_env => $o->{'token-env'} // 'GITLAB_TOKEN', ($o->{curl} ? (curl => [ split ' ', $o->{curl} ]) : ()))
           : die "talk: give --local DIR (the emulator) or --url URL (or GITLAB_LOCAL / GITLAB_URL)\n";
    my $p = $o->{project} // $ENV{GITLAB_PROJECT} // die "talk: give --project GROUP/NAME (or GITLAB_PROJECT)\n";
    ($gl, $p);
}
sub load_data {                               # everything the drafts read, once
    my ($gl, $p) = @_;
    my %d = (issues => $gl->issues($p, state => 'all'), mrs => $gl->mrs($p, state => 'all'),
             pipelines => $gl->pipelines($p), milestones => $gl->milestones($p));
    $d{project} = eval { $gl->project($p) } // {};
    $d{default} = $d{project}{default_branch} // 'develop';
    $d{issue_by} = { map { $_->{iid} => $_ } @{ $d{issues} } };
    $d{pages} = eval { $gl->pages($p) };
    ($d{gl}, $d{p}) = ($gl, $p);
    if (!$gl->is_local) {                     # REST: pipeline records carry no reports; read the metrics artifacts the jobs keep
        my ($last) = sort { ($b->{updated_at} // $b->{created_at} // '') cmp ($a->{updated_at} // $a->{created_at} // '') }
                     grep { ($_->{ref} // '') eq $d{default} && ($_->{status} // '') eq 'success' } @{ $d{pipelines} };
        my %m;
        for my $job (qw(todo trace vcrm recipe)) {
            my $txt = eval { $gl->job_artifact($p, ref => $d{default}, job => $job, path => "$job.metrics") } // next;
            while ($txt =~ /^([A-Za-z_][\w:]*)\s+(-?[\d.]+)/mg) { $m{$1} = $2 }
        }
        $last->{reports}{metrics} = \%m if $last && %m;   # the latest values only: REST keeps no per-pipeline history here
    }
    \%d;
}
sub story_of {                                # an issue -> its story issue (itself if it is a story; "Part of #N" for a task)
    my ($d, $i) = @_;
    return $i if !$i || has_label($i, 'type::story');
    my ($n) = ($i->{description} // '') =~ /Part of #(\d+)/i;
    $n && $d->{issue_by}{$n} ? $d->{issue_by}{$n} : $i;
}
sub closes_of {                            # the issues a merge request is about: "Closes #N", "Part of #N", feature/<N>-...
    my $m = shift;
    my %n;
    $n{$1} = 1 while ($m->{description} // '') =~ /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|part of)\s+#(\d+)/gi;
    $n{$1} = 1 if ($m->{source_branch} // '') =~ m{^(?:feature|hotfix)/(\d+)-};
    sort { $a <=> $b } keys %n;
}
sub sid { my ($o, $i) = @_; $i ? "$o->{prefix}$i->{iid}" : undef }
sub tasks_of { my ($d, $story) = @_; grep { my $s = story_of($d, $_); $s && $s->{iid} == $story->{iid} && $_->{iid} != $story->{iid} } @{ $d->{issues} } }

sub metrics_series {                          # [ { t, metrics } ] from default-branch pipelines with a metrics report, oldest first
    my ($d, $o) = @_;
    return $d->{series} if $d->{series};
    my @s = sort { $a->{t} <=> $b->{t} } map { +{ t => ep($_->{finished_at} // $_->{updated_at} // $_->{created_at}), metrics => $_->{reports}{metrics} } }
            grep { ref $_->{reports} eq 'HASH' && ref $_->{reports}{metrics} eq 'HASH' && ($_->{ref} // '') eq $d->{default} } @{ $d->{pipelines} };
    if ($o->{metrics}) {                      # --metrics FILE: the latest values (a real GitLab: the jobs' metrics artifacts)
        open my $fh, '<', $o->{metrics} or die "talk: cannot read $o->{metrics}: $!\n";
        my %m; while (<$fh>) { $m{$1} = $2 if /^([A-Za-z_][\w:]*)\s+(-?[\d.]+)/ } close $fh;
        push @s, { t => (@s ? $s[-1]{t} : 0), metrics => \%m };   # at the latest pipeline's time: it replaces the latest values
    }
    $d->{series} = \@s;
}
sub metric_at {                               # the metric's value in the latest report at or before t
    my ($series, $name, $t) = @_;
    my $v;
    for my $x (@$series) { last if $x->{t} > $t; $v = $x->{metrics}{$name} if defined $x->{metrics}{$name} }
    $v;
}
sub cases_at {                                # requirements with a verification case (the trace): (n, total) -- the headline measure
    my ($s, $t) = @_;
    my ($tot, $unv) = (metric_at($s, 'trace_total', $t), metric_at($s, 'trace_unverified', $t));
    $tot && defined $unv ? ($tot - $unv, $tot) : (undef, undef);
}
sub results_at {                              # requirements with a passing recorded result (the VCRM): (n, total) -- a different measure
    my ($s, $t) = @_;
    my ($n, $tot) = (metric_at($s, 'vcrm_verified', $t), metric_at($s, 'vcrm_requirements', $t));
    $tot && defined $n ? ($n, $tot) : (undef, undef);
}
sub of_pct { my ($n, $tot) = @_; defined $n ? sprintf('%d of %d (%s%%)', $n, $tot, r1(100 * $n / $tot)) : undef }
sub read_baseline {
    my $f = shift or return {};
    open my $fh, '<', $f or die "talk: cannot read $f: $!\n";
    my %b;
    while (my $l = <$fh>) { next if $l =~ /^\s*(#|$)/; $b{$1} = { value => $2, label => $3 // $1 } if $l =~ /^\s*(\w+)\s*=\s*([\d.]+)\s*(?:\|\s*(.*?))?\s*$/ }
    close $fh;
    \%b;
}

# ---------------------------------------------------------------- the journal (optional)
sub journal_items {                           # --journal DIR -> [ items ], or () when there is none
    my ($dir) = @_;
    return () unless $dir;
    my $conf = "$dir/scrum.conf";
    my $file = "$dir/scrum.txt";
    if (open my $fh, '<', $conf) { while (<$fh>) { $file = "$dir/$1" if /^\s*journal\s*=\s*(\S+)/ } close $fh }
    -f $file or die "talk: no journal at $file\n";
    require Scrum;
    my $s = Scrum::load($file);
    values %{ $s->{items} };
}
sub prefix_of {
    my ($o, @items) = @_;
    return $o->{prefix} if defined $o->{prefix};
    return $ENV{TALK_PREFIX} if defined $ENV{TALK_PREFIX} && length $ENV{TALK_PREFIX};
    my %c; $c{$_}++ for map { $_->{id} =~ /^([A-Z][A-Z0-9_]*-)\d+$/ ? "$1" : () } @items;
    my ($best) = sort { $c{$b} <=> $c{$a} || $a cmp $b } keys %c;
    return $best if $best;
    my ($g) = split m{/}, $o->{project} // $ENV{GITLAB_PROJECT} // 'X';
    uc(substr($g, 0, 2)) . '-';
}

# ---------------------------------------------------------------- standup
sub cmd_standup {
    my ($gl, $p, $o) = @_;
    my $u = $o->{as} // die "talk: standup needs --as USER\n";
    my @items = journal_items($o->{journal});
    $o->{prefix} = prefix_of($o, @items);
    my $d = load_data($gl, $p);
    my $date = $o->{date} // day($gl->epoch);
    $date =~ /^\d{4}-\d\d-\d\d$/ or die "talk: --date is YYYY-MM-DD, not '$date'\n";
    my $since = prev_workday($date);
    my ($from, $to) = (ep($since), ep($date));          # yesterday = from the last working day's start to today's start
    my @why;

    # what the person did since the last working day
    my @closed = grep { $_->{state} eq 'closed' && assigned_to($_, $u) && in_window($_->{closed_at}, $from, $to) } @{ $d->{issues} };
    my @merged = grep { ($_->{author}{username} // '') eq $u && $_->{state} eq 'merged' && in_window($_->{merged_at}, $from, $to) } @{ $d->{mrs} };
    my @opened = grep { ($_->{author}{username} // '') eq $u && in_window($_->{created_at}, $from, $to) && $_->{state} ne 'merged' } @{ $d->{mrs} };
    my @reviewed = grep { ($_->{author}{username} // '') ne $u && (grep { (($_->{author}{username} // '') eq $u && in_window($_->{created_at}, $from, $to))
                                                                        } @{ $_->{notes} // [] }) || grep { ($_->{user}{username} // '') eq $u && in_window($_->{approved_at}, $from, $to) } @{ $_->{approved_by} // [] } } @{ $d->{mrs} };

    # the story the day was about: the one with the most closed tasks / merged MRs
    my %score;
    $score{ story_of($d, $_)->{iid} } += 2 for @closed;
    for my $m (@merged, @opened) { $score{ story_of($d, $d->{issue_by}{$_})->{iid} } += 1 for grep { $d->{issue_by}{$_} } closes_of($m) }
    my ($top) = sort { $score{$b} <=> $score{$a} || $a <=> $b } keys %score;
    my $story = defined $top ? $d->{issue_by}{$top} : undef;

    my ($y, $num);
    if ($story) {
        my @tasks = tasks_of($d, $story);
        my $done = grep { $_->{state} eq 'closed' } @tasks;
        my $title = short($story->{title}, 38);
        my $series = metrics_series($d, $o);
        my ($t0, $t1) = (metric_at($series, 'todo_lines', $from - 1), metric_at($series, 'todo_lines', $to - 1));
        if (@merged && defined $t0 && defined $t1 && $t1 < $t0) {
            $num = sprintf '%d TODOs closed, %d left', $t0 - $t1, $t1;
            push @why, "todo_lines on $d->{default}: $t0 -> $t1";
        } elsif ($story->{state} eq 'closed' && in_window($story->{closed_at}, $from, $to)) {
            $num = 'done' . (@tasks ? sprintf(' (%s)', plural(scalar @tasks, 'task')) : '');
        } elsif (@tasks && $done) {
            $num = sprintf '%d of %d tasks done', $done, scalar @tasks;
        } elsif (@merged) {
            $num = plural(scalar @merged, 'change') . ' merged, checks green';
        } elsif (my @mine_open = grep { my $m = $_; grep { $d->{issue_by}{$_} && story_of($d, $d->{issue_by}{$_})->{iid} == $story->{iid} } closes_of($m) } @opened) {
            $num = join(', ', map { "!$_->{iid}" } @mine_open) . ' up for review';
        } elsif (@tasks) {
            $num = sprintf '%d of %d tasks done', $done, scalar @tasks;
        } else {
            $num = plural(scalar @closed, 'item') . ' closed';
        }
        $y = sid($o, $story) . " $title: $num.";
        push @why, (map { "#$_->{iid} closed" } @closed), (map { "!$_->{iid} merged" } @merged), (map { "!$_->{iid} opened" } @opened);
    }
    if (@reviewed) {
        my $r = 'Reviewed ' . join(', ', map { "!$_->{iid}" } @reviewed[0 .. ($#reviewed < 2 ? $#reviewed : 2)]) . '.';
        $y = defined $y ? "$y $r" : "$r";
        push @why, map { "reviewed !$_->{iid}" } @reviewed;
    }
    if (defined $y && $y !~ /\Q$o->{prefix}\E\d/) {      # reviews only: name the story the reviewed change belongs to
        my ($m) = @reviewed;
        my ($n) = closes_of($m);
        my $s = $n && $d->{issue_by}{$n} ? story_of($d, $d->{issue_by}{$n}) : undef;
        $y = $s ? sid($o, $s) . " $y" : $y;
    }
    $y //= 'none';

    # today: the person's open task in progress, else the next one in the current sprint
    my @mine = grep { $_->{state} eq 'opened' && assigned_to($_, $u) && !has_label($_, 'workflow::blocked') && !has_label($_, 'type::story') } @{ $d->{issues} };
    my ($cur) = grep { ($_->{start_date} // '') le $date && ($_->{due_date} // '9999') ge $date } @{ $d->{milestones} };
    my @pick = sort { has_label($b, 'workflow::in-progress') <=> has_label($a, 'workflow::in-progress')
                      || (($cur && $b->{milestone} && $b->{milestone}{title} eq $cur->{title}) ? 1 : 0) <=> (($cur && $a->{milestone} && $a->{milestone}{title} eq $cur->{title}) ? 1 : 0)
                      || ($a->{due_date} // '9999') cmp ($b->{due_date} // '9999') || $a->{iid} <=> $b->{iid} } @mine;
    my $t = 'none';
    if (my $task = $pick[0]) {
        my $s = story_of($d, $task);
        my $by = $task->{due_date} // ($task->{milestone} ? (map { $_->{due_date} } grep { $_->{title} eq $task->{milestone}{title} } @{ $d->{milestones} })[0] : undef);
        my $when = !$by ? '' : (ep($by) - ep($date) <= 6 * 86400 && ep($by) >= ep($date)) ? ', by ' . dow($by) : ', by ' . substr(nice_date($by), 4);
        $t = sid($o, $s) . ' ' . lcfirst_word(short($task->{title}, 50)) . $when;
        push @why, "today: #$task->{iid}" . ($s->{iid} != $task->{iid} ? " (story #$s->{iid})" : '');
    } elsif (@items) {                        # nothing open in GitLab: the person's committed stories in the journal
        my ($name) = grep { defined } (map { $_->{name} } grep { $_ } eval { $gl->{st}{users}{$u} }), ucfirst $u;
        my ($it) = sort { $a->{id} cmp $b->{id} } grep { ($_->{state} // '') eq 'committed' && lc($_->{owner} // '') =~ /^\Q${\ lc $name}\E|^\Q$u\E/ } @items;
        $t = "$it->{id} " . lcfirst_word(short($it->{title}, 50)) if $it;
    }

    # blockers: an issue labeled workflow::blocked becomes an ask
    my @blk = grep { $_->{state} eq 'opened' && assigned_to($_, $u) && has_label($_, 'workflow::blocked') } @{ $d->{issues} };
    my $b = 'none';
    if (my $x = $blk[0]) {
        my ($why, $need) = blocker_reason($x, $d);
        $b = sid($o, story_of($d, $x)) . ' ' . lcfirst_word(short($x->{title}, 40)) . " blocked: $why -- need: $need";
        push @why, "blocked: #$x->{iid}";
    }
    $t .= '.' unless $t eq 'none' || $t =~ /\.$/;
    my $line = "Y $y T $t B $b";
    my $lint = eval { require Answers; Answers::lint_message($line, example => "$o->{prefix}12") };
    print "$line\n";
    print "# draft for $u on " . nice_date($date) . " (since " . nice_date($since) . "): edit it, then post it yourself\n";
    print "# from: " . join(', ', @why) . "\n" if $o->{why} && @why;
    if ($lint) { print '# lint: ' . ($lint->{ok} && !@{ $lint->{warnings} } ? 'ok' : join('; ', @{ $lint->{errors} }, @{ $lint->{warnings} })) . "\n" }
    print "# no number in Y: add one (how many, how much, by when)\n" if $y ne 'none' && $y !~ /\d.*\d|\d\D*$/ && ($y =~ s/\Q$o->{prefix}\E\d+//r) !~ /\d/;
    0;
}
sub blocker_reason {                          # (issue, data) -> (why, need): from "Blocked by: ..." / "need: ..." in its notes or description
    my ($x, $d) = @_;
    my $notes = $x->{notes} // ($d && $d->{gl} ? $d->{notes}{ $x->{iid} } //= (eval { $d->{gl}->issue_notes($d->{p}, $x->{iid}) } // []) : []);
    my @texts = ((reverse map { $_->{body} // '' } grep { !$_->{system} } @$notes), $x->{description} // '');
    my ($why, $need);
    for my $t (@texts) {
        $need //= $1 if $t =~ /\bneed(?:ed|s)?\s*:\s*([^\n.]+)/i;
        $why //= $1 if $t =~ /\b(?:blocked by|waiting (?:on|for))\s*:?\s*([^\n.]+?)(?:\s*--|\s+need:|[\n.]|$)/i;
    }
    ($why // 'see the issue', $need // 'help to unblock it');
}

# ---------------------------------------------------------------- review
sub sprint_bounds {
    my ($d, $n) = @_;
    my @ms = sort { ($a->{start_date} // '') cmp ($b->{start_date} // '') } grep { ($_->{title} // '') =~ /\bSprint\s*\d+$/i } @{ $d->{milestones} };
    my ($m) = grep { $_->{title} =~ /\bSprint\s*\Q$n\E$/i } @ms;
    $m or die "talk: no milestone 'Sprint $n'\n";
    my ($prev) = grep { $_->{title} =~ /\bSprint\s*\Q@{[ $n - 1 ]}\E$/i } @ms;
    my ($next) = grep { ($_->{start_date} // '') gt ($m->{due_date} // '') } @ms;
    my $start = ep($m->{start_date} // die "talk: milestone '$m->{title}' has no start date\n");
    my $end = ep($m->{due_date} // die "talk: milestone '$m->{title}' has no due date\n") + 3 * 86400;   # the weekend after the due Friday
    ($m, $prev, $next, $start, $end);
}
sub headline {                                # the four numbers at time t: TODO lines, coverage, open DRs/prime changes, blocked
    my ($d, $series, $t) = @_;
    my ($cn, $ct) = cases_at($series, $t);
    my ($rn, $rt) = results_at($series, $t);
    my $open = sub { my $i = shift; my $c = ep($i->{created_at}); defined $c && $c <= $t && (!$i->{closed_at} || ep($i->{closed_at}) > $t) };
    my $drs = grep { $open->($_) && (has_label($_, 'type::discrepancy') || has_label($_, 'prime-change')) } @{ $d->{issues} };
    my $blk = grep { $_->{state} eq 'opened' && has_label($_, 'workflow::blocked') } @{ $d->{issues} };
    { todo => metric_at($series, 'todo_lines', $t), cases => $cn, cases_tot => $ct, res => $rn, res_tot => $rt, drs => $drs, blocked => $blk };
}
sub change { my ($now, $was, $better_down) = @_; return '' unless defined $now && defined $was; my $c = $now - $was; return ' (no change)' if !$c;
             sprintf ' (%s%s from %s)', $c > 0 ? 'up ' : 'down ', abs(0 + sprintf('%.1f', $c)), $was }
sub cmd_review {
    my ($gl, $p, $o) = @_;
    my $n = $o->{sprint} // die "talk: review needs --sprint N\n";
    $n =~ /^\d+$/ or die "talk: --sprint is a number, not '$n'\n";
    my $d = load_data($gl, $p);
    my ($m, $prev, $next, $start, $end) = sprint_bounds($d, $n);
    my $series = metrics_series($d, $o);
    my $base = read_baseline($o->{baseline});
    my ($h, $hp) = (headline($d, $series, $end), headline($d, $series, $start - 1));

    my $goal = (grep { /\?\s*$/ } map { s/^\s*(?:[-*]\s*)?\*{0,2}(?:goal|question)\s*:?\s*\*{0,2}\s*:?\s*//ir } split /\n/, $m->{description} // '')[0];
    my ($gline) = map { s/^\s*(?:\*\*)?goal(?:\*\*)?\s*:\s*//ir } grep { /^\s*(?:\*\*)?goal/i } split /\n/, $m->{description} // '';
    my $question = $goal // ($gline ? "Did we do what we set out to do: $gline?" : "What did Sprint $n change for the model, and how do we know?");

    my @merged = grep { $_->{state} eq 'merged' && in_window($_->{merged_at}, $start, $end) } @{ $d->{mrs} };
    my @green = grep { my $pl = $_->{head_pipeline}; !$pl || ($pl->{status} // 'success') eq 'success' } @merged;
    my @stories = grep { has_label($_, 'type::story') && $_->{milestone} && $_->{milestone}{title} eq $m->{title} } @{ $d->{issues} };
    my $sdone = grep { $_->{state} eq 'closed' } @stories;
    my $an = eval { $gl->analytics($p, since => day($start), until => day($end - 86400), by => 'sprint') } // {};
    my ($rev, $lead, $plmin) = ($an->{mrs}{review_median}, $an->{dora}{lead_median}, $an->{ci}{median_minutes});
    my $pages = ref $d->{pages} eq 'HASH' ? $d->{pages}{url} : undef;
    my %jobs; for my $pl (grep { ($_->{ref} // '') eq $d->{default} } @{ $d->{pipelines} }) { $jobs{ $_->{name} } = 1 for grep { ($_->{status} // '') eq 'success' } @{ $pl->{jobs} // [] } }

    my @out;
    my $H = $o->{md} ? sub { "## $_[0]" } : sub { uc $_[0] };
    push @out, ($o->{md} ? "# " : '') . "Sprint $n review -- demo script (draft: edit before the meeting)", '';
    push @out, $H->('1. The question this sprint answered'), "\"$question\"", sprintf('Answer in one line: %d of %d stories done%s.', $sdone, scalar @stories,
        defined $h->{cases} ? sprintf(', %d of %d requirements with a verification case', $h->{cases}, $h->{cases_tot}) : ''), '';
    push @out, $H->('2. The same four numbers as every review');
    push @out, sprintf('- TODO lines left: %s%s', $h->{todo} // 'n/a (no todo metrics yet)', change($h->{todo}, $hp->{todo})),
               sprintf('- Requirements with a verification case: %s%s', of_pct($h->{cases}, $h->{cases_tot}) // 'n/a (no trace metrics yet)', change($h->{cases}, $hp->{cases})),
               (defined $h->{res} ? sprintf('    (a different measure: requirements with a passing recorded result, from the VCRM: %d of %d%s)', $h->{res}, $h->{res_tot}, change($h->{res}, $hp->{res})) : ()),
               sprintf('- Open discrepancy reports and prime changes: %d%s', $h->{drs}, change($h->{drs}, $hp->{drs})),
               sprintf('- Blocked items: %d', $h->{blocked}), '';
    push @out, $H->('3. Show the output, not the tool');
    push @out, '- The model site: ' . ($pages // '(not published yet: the pages job on the default branch publishes it)');
    push @out, "- The verification matrix (vcrm.html on the site, from the vcrm job)" if $jobs{vcrm};
    push @out, "- The generated documents (docs/ on the site: part tree, trace, data exchange tables)" if $jobs{docs} || $jobs{pages};
    push @out, sprintf('- %s merged this sprint, %d with green checks; show one going red to green:', plural(scalar @merged, 'change'), scalar @green);
    push @out, map { "    !$_->{iid} " . short($_->{title}, 60) } @green[0 .. ($#green < 3 ? $#green : 3)];
    push @out, '';
    push @out, $H->('4. One before-and-after');
    my @ba;
    for ([ review_hours => 'from proposing a change to the first review', $rev ], [ lead_hours => 'from first edit to accepted change', $lead ]) {
        my ($k, $what, $now) = @$_;
        next unless defined $now;
        push @ba, $base->{$k} ? sprintf('- Before: %s took %s (%s). Now: %s, median this sprint.', $what, fmt_hours($base->{$k}{value}), $base->{$k}{label}, fmt_hours($now))
                              : sprintf('- Now: %s takes %s (median). Before: [the document-era number -- put it in a --baseline file].', $what, fmt_hours($now));
    }
    push @ba, sprintf('- Before: %s. Now: the trace check answers it on every change, in about %s.', $base->{trace_hours} ? "$base->{trace_hours}{label}, $base->{trace_hours}{value} h" : '[how long "which requirements are unverified?" used to take]', fmt_hours(($plmin // 4) / 60)) if $jobs{trace} || $jobs{vcrm};
    push @out, @ba ? @ba : ('- [Before: ... Now: ... -- one number each, from a --baseline file and analytics]'), '';
    push @out, $H->('5. One safe live change (on a scratch branch, never on develop)');
    push @out, $jobs{trace} || $jobs{vcrm}
        ? sprintf('- Delete one satisfy line on a scratch branch and open a draft merge request: in about %s the trace check names the requirement that lost its design. Close the merge request afterwards.', fmt_hours(($plmin // 4) / 60))
        : sprintf('- Misspell one part type on a scratch branch and open a draft merge request: in about %s the lint check points at the line. Close the merge request afterwards.', fmt_hours(($plmin // 4) / 60));
    push @out, '';
    push @out, $H->('6. What it means for the next milestone');
    push @out, $next ? sprintf('- %s starts %s: %s', $next->{title}, nice_date($next->{start_date}),
                               defined $h->{todo} ? "$h->{todo} TODO lines to go; at this sprint's pace that is " . pace($h->{todo}, $hp->{todo}) . '.' : '[what this sprint makes possible next]')
                     : '- [the next milestone and what this sprint makes possible]', '';
    push @out, $H->('7. The ask');
    my @blk = grep { $_->{state} eq 'opened' && has_label($_, 'workflow::blocked') } @{ $d->{issues} };
    push @out, @blk ? (map { my ($w, $nd) = blocker_reason($_, $d); "- Need: $nd (#$_->{iid} " . short($_->{title}, 40) . " is blocked: $w)" } @blk)
                    : ('- [A decision on ___ by ___, or help with ___. Name it, with a date.]');
    push @out, '';
    my $s30 = sprintf('Sprint %d: %d of %d stories done%s%s. %s', $n, $sdone, scalar @stories,
                      defined $h->{todo} ? ", $h->{todo} TODO lines left" . (defined $hp->{todo} && $hp->{todo} > $h->{todo} ? sprintf(' (down %d)', $hp->{todo} - $h->{todo}) : '') : '',
                      defined $h->{cases} ? ", $h->{cases} of $h->{cases_tot} requirements with a verification case" : '', @blk ? 'We need help with ' . plural(scalar @blk, 'blocked item') . '.' : 'Nothing blocks us.');
    push @out, $H->('30-second version'), $s30, '';
    push @out, $H->('1-sentence version'), sprintf('Sprint %d moved the model forward by %s%s.', $n, plural($sdone, 'story'),
        defined $h->{todo} && defined $hp->{todo} && $hp->{todo} > $h->{todo} ? sprintf(' and %d TODO lines', $hp->{todo} - $h->{todo}) : '');
    print join("\n", @out), "\n";
    0;
}
sub pace { my ($now, $was) = @_; return 'unknown pace' unless defined $was && $was > $now; my $s = $now / ($was - $now); sprintf('about %s', $s <= 1 ? 'one more sprint' : sprintf('%d more sprints', int($s + 0.999))) }

# ---------------------------------------------------------------- weekly
sub cmd_weekly {
    my ($gl, $p, $o) = @_;
    my $d = load_data($gl, $p);
    my $date = $o->{date} // day($gl->epoch);
    $date =~ /^\d{4}-\d\d-\d\d$/ or die "talk: --date is YYYY-MM-DD, not '$date'\n";
    my $t = ep($date) + 86399;
    my $wd = ((gmtime ep($date))[6] + 6) % 7;            # Monday = 0
    my $mon = ep($date) - $wd * 86400;
    my $series = metrics_series($d, $o);
    my ($h, $hp) = (headline($d, $series, $t), headline($d, $series, $mon - 1));
    my @done = grep { has_label($_, 'type::story') && $_->{state} eq 'closed' && in_window($_->{closed_at}, $mon, $t + 1) } @{ $d->{issues} };
    my @merged = grep { $_->{state} eq 'merged' && in_window($_->{merged_at}, $mon, $t + 1) } @{ $d->{mrs} };
    my ($cur) = grep { ($_->{start_date} // '') le $date && ($_->{due_date} // '9999') ge $date } @{ $d->{milestones} };
    my ($on, $why) = ('On track', '');
    if ($cur && $cur->{start_date} && $cur->{due_date}) {
        my @st = grep { has_label($_, 'type::story') && $_->{milestone} && $_->{milestone}{title} eq $cur->{title} } @{ $d->{issues} };
        my $pts = 0; my $dn = 0; for (@st) { my $w = $_->{weight} || 1; $pts += $w; $dn += $w if $_->{state} eq 'closed' }
        my $frac = (ep($date) - ep($cur->{start_date}) + 86400) / (ep($cur->{due_date}) - ep($cur->{start_date}) + 86400);
        if ($pts && $frac > 0.5 && $dn / $pts < 0.8 * $frac) { ($on, $why) = ('At risk', sprintf(' -- %d%% of the sprint is done with %d%% of the time gone', 100 * $dn / $pts, 100 * $frac)) }
    }
    $on = 'Needs help' if $h->{blocked} && $on eq 'At risk';
    my $last = (grep { ($_->{ref} // '') eq $d->{default} } sort { ep($a->{created_at}) <=> ep($b->{created_at}) } @{ $d->{pipelines} })[-1];
    my @risk;
    push @risk, "The automated checks on the shared model are failing since " . nice_date($last->{created_at}) . '.' if $last && ($last->{status} // '') eq 'failed';
    push @risk, map { my ($w) = blocker_reason($_, $d); "#$_->{iid} " . short($_->{title}, 50) . " is blocked: $w." } grep { $_->{state} eq 'opened' && has_label($_, 'workflow::blocked') } @{ $d->{issues} };
    push @risk, map { "Discrepancy report #$_->{iid} to the prime is " . int(($t - ep($_->{created_at})) / 86400) . ' days old.' }
                grep { $_->{state} eq 'opened' && has_label($_, 'type::discrepancy') && $t - ep($_->{created_at}) > 14 * 86400 } @{ $d->{issues} };
    my @asks = map { my (undef, $nd) = blocker_reason($_, $d); "$nd (#$_->{iid})" } grep { $_->{state} eq 'opened' && has_label($_, 'workflow::blocked') } @{ $d->{issues} };
    my $H = $o->{md} ? sub { "## $_[0]" } : sub { "$_[0]:" };
    my @nums = (sprintf('%s finished this week (%s accepted into the model)', plural(scalar @done, 'story'), plural(scalar @merged, 'change')),
                defined $h->{todo} ? sprintf('%d TODO lines left to port by hand%s', $h->{todo}, change($h->{todo}, $hp->{todo})) : (),
                defined $h->{cases} ? sprintf('Requirements with a verification case: %s%s', of_pct($h->{cases}, $h->{cases_tot}), change($h->{cases}, $hp->{cases})) : (),
                sprintf('%d open discrepancy reports and prime changes', $h->{drs}));
    my @out = (($o->{md} ? '# ' : '') . sprintf('Weekly note, week of %s -- %s%s', substr(nice_date(day($mon)), 4), $on, $why), '');
    my $todo_bit = defined $h->{todo} && defined $hp->{todo} && $hp->{todo} > $h->{todo} ? sprintf(', and the hand-port list fell from %d to %d', $hp->{todo}, $h->{todo}) : '';
    push @out, sprintf('%s: %s finished this week%s.', $on, plural(scalar @done, 'story'), $todo_bit), '';
    push @out, $H->('The numbers'), map({ "- $_" } @nums[0 .. ($#nums < 2 ? $#nums : 2)]),
        (defined $h->{res} ? sprintf('- Separately: %d of %d requirements have a passing recorded result (VCRM)', $h->{res}, $h->{res_tot}) : ()), '';
    push @out, $H->('Risks'), (@risk ? map { "- $_" } @risk : '- None this week.'), '';
    push @out, $H->('Asks'), (@asks ? map { "- $_" } @asks : '- None this week.'), '';
    push @out, '(The weekly quad -- daily.pl quad -- has the detail; this note is the headline.)';
    print join("\n", @out), "\n";
    0;
}

# ---------------------------------------------------------------- translate
# translate never rewrites a sentence. It (1) lists each jargon term with a plain alternative and a hint on how to say
# it, (2) flags "so what?" sentences, (3) for a flagged sentence offers a SUGGESTION built only from the template
# Done: <outcome> (<number>). Next: <outcome>. Need: <ask> -- the sentence's own ids and numbers filled in, the rest
# left as [brackets] for the person to fill. The plain version swaps only nouns for nouns (singular for singular,
# plural for plural), and only terms whose swap reads as English wherever the noun stands.
# [ term regex, plain alternative, hint, noun swap (singular, plural) or undef ]
my @GLOSSARY = (
    [ 'merge requests?|MRs?', 'proposed change', 'say what the change does for the model', [ 'proposed change', 'proposed changes' ] ],
    [ 'pull requests?', 'proposed change', 'say what the change does for the model', [ 'proposed change', 'proposed changes' ] ],
    [ 'VCRMs?', 'verification matrix', 'say how many requirements are verified', [ 'verification matrix', 'verification matrices' ] ],
    [ 'DRs?', 'discrepancy report', "say what the prime must fix and by when", [ 'discrepancy report', 'discrepancy reports' ] ],
    [ 'prime drops?', "prime model update", "say what the update changes for us", [ 'prime model update', 'prime model updates' ] ],
    [ 'TODO lines?|TODOs?', 'hand-port item', 'say how many are closed and how many are left', [ 'hand-port item', 'hand-port items' ] ],
    [ 'artifacts?', 'generated report', 'name the report (trace report, data exchange table ...)', [ 'generated report', 'generated reports' ] ],
    [ 'runners?', 'check machine', 'say what it lets the team do (run the checks on every change)', [ 'check machine', 'check machines' ] ],
    [ 'code ?owners', 'approvers for that part of the model', 'name the person who approves', undef ],
    [ 'green pipelines?|(?:the )?pipeline (?:is|was) green', 'all automated checks passed', 'say what that proves (e.g. "no grammar or lint errors")', undef ],
    [ 'red pipelines?|(?:the )?pipeline (?:is|was) red', 'an automated check failed', 'say what the check caught and when it will be fixed', undef ],
    [ 'CI/CD pipelines?|CI pipelines?|pipelines?|CI', 'automated checks', 'say which check and what it caught or confirmed', undef ],
    [ 'trace coverage', 'requirements linked to a design and a test', 'give it as "X of Y requirements"', undef ],
    [ 'SIL', 'testing with simulated hardware', 'say what was tested and the result', undef ],
    [ 'HIL', 'testing with real hardware', 'say what was tested and the result', undef ],
    [ 'baselines?|tags?', 'frozen, approved version', 'name the version and what it is for', undef ],
    [ 'lint (?:errors?|warnings?|failures?)|grammar errors?|validation failures?', 'errors the automated checks found', 'say how many, and that they were caught before review', undef ],
    [ 'technical debt|refactor(?:ing|ed)?', 'cleanup that keeps future changes cheap', 'say what gets cheaper (e.g. "one edit instead of ten")', undef ],
    [ 'rebas(?:e|ed|ing)', 'brought my change up to date', 'say what it achieved, or leave it out: nobody needs to hear it', undef ],
    [ 'feature branch(?:es)?|branch(?:es)?', 'private working copy of the model', 'usually leave it out: say what the change does', undef ],
    [ 'commit(?:s|ted)?', 'saved change', 'usually leave it out: say what the change does', undef ],
    [ 'merg(?:e|ed|ing)', 'accepted into the shared model', 'say what is now in the model', undef ],
    [ 'vendor branch', "the prime's model as delivered", "say \"the prime's delivery\"", undef ],
    [ 'orphans?', 'requirements nothing in the design satisfies', 'give it as "N requirements have no design"', undef ],
    [ 'drift', 'wording that differs between DOORS and the model', 'say which requirement and who fixes it', undef ],
    [ '\.gitlab-ci\.yml|YAML', 'the list of automated checks', 'usually leave it out', undef ],
);
my $OUTCOME = qr/\b(done|fail(?:ed|s)?|close[sd]?|closing|caught|ready|passed|merged|accepted|saved|reduced|increased|cut|up|down|complete|completed|decided|fixed|finished|delivered|approved|published|found|verified|green|blocked|need|needs|by (?:mon|tue|wed|thu|fri|\w+ \d))\b/i;
my $REF = qr/(?:\b[A-Z][A-Z0-9_]{0,9}-\d+\b|[!#]\d+\b)/;
sub plain_swap {                              # noun-for-noun swaps only; code, ids and references untouched
    my ($text, $g) = @_;
    my @kept;
    $text =~ s/(`[^`]*`|$REF)/push @kept, $1; "\x00$#kept\x00"/ge;
    for my $e (grep { $_->[3] } @$g) {
        my ($re, undef, undef, $sw) = @$e;
        $text =~ s{\b($re)\b}{ my $w = $1; my $pl = $w =~ /s$/ && $w !~ /^(?:VCRM|DR|MR)$/i ? 1 : 0; my $r = $sw->[$pl]; $w =~ /^[A-Z][a-z]/ ? ucfirst $r : $r }gie;
    }
    $text =~ s/\x00(\d+)\x00/$kept[$1]/g;
    $text;
}
sub suggestion {                              # the template, filled only with what the sentence itself contains
    my ($s, $terms) = @_;
    my @refs = $s =~ /($REF)/g;
    my ($num) = $s =~ /\b(\d[\d.,]*%?(?:\s+(?:of\s+\d+\s+)?[A-Za-z][\w-]*(?:\s+(?:lines?|items?))?)?)/;
    $num = plain_swap($num, \@GLOSSARY) if defined $num;
    my @nouns = map { $_->[1] } grep { $_->[3] } @$terms;        # only noun terms name the topic
    my $topic = @nouns ? join(', ', @nouns[0 .. ($#nouns < 1 ? $#nouns : 1)]) : '';
    my $done = 'Done: ' . (@refs ? "$refs[0] " : '') . '[what is now true' . ($topic ? " -- topic: $topic" : '') . ']'
             . ' (' . ($num // '[one number: how many, how much]') . ').';
    "SUGGESTION: $done Next: [outcome, by a day]. Need: [an ask, or none].";
}
sub cmd_translate {
    my ($o, $src) = @_;
    defined $src or die "talk: translate needs FILE or - (standard input)\n";
    my $text = do { local $/; if ($src eq '-') { <STDIN> } else { open my $fh, '<', $src or die "talk: cannot read $src: $!\n"; my $t = <$fh>; close $fh; $t } } // '';
    my @g = @GLOSSARY;
    if ($o->{glossary}) {                     # TERM = plain alternative | hint
        open my $fh, '<', $o->{glossary} or die "talk: cannot read $o->{glossary}: $!\n";
        my @mine; while (my $l = <$fh>) { next if $l =~ /^\s*(#|$)/; push @mine, [ quotemeta($1), $2, $3 // 'say what it achieved', undef ] if $l =~ /^\s*(.+?)\s*=\s*([^|]+?)\s*(?:\|\s*(.+?))?\s*$/ } close $fh;
        @g = (@mine, @g);
    }
    my (@sents, %seen, @terms);
    for my $sent (grep { /\w/ } split /(?<=[.!?])\s+|\n+/, $text) {
        (my $s = $sent) =~ s/^\s+|\s+$//g;
        (my $scan = $s) =~ s/`[^`]*`|$REF/ /g;
        my @here;
        my $rest = $scan;
        for my $e (@g) {                      # longest phrases first (list order); a matched span is not matched again
            while ($rest =~ /\b($e->[0])\b/i) { my $w = $1; push @here, [ $w, $e->[1], $e->[2], $e->[3] ]; push @terms, [ $w, $e->[1], $e->[2] ] unless $seen{ lc $w }++; $rest =~ s/\b\Q$w\E\b/ /i }
        }
        my @why;
        push @why, 'no number' unless $s =~ /\d/;
        push @why, 'no outcome (done, caught, ready, decided ... or an ask)' unless $s =~ $OUTCOME;
        my $wc = () = $s =~ /\S+/g;
        push @why, "long ($wc words): split it" if $wc > 30;
        push @why, 'passive: say who did what' if $s =~ /\b(?:is|was|are|were|being|been)\s+(?:being\s+)?\w+ed\b/i && $s !~ /\bblocked\b/i;
        push @sents, { s => $s, why => \@why, terms => \@here };
    }
    my $plain = plain_swap($text, \@g);
    my ($h1, $li) = $o->{md} ? ("## ", '- ') : ('', '  ');
    my @out;
    push @out, "${h1}Jargon to replace" . ($o->{md} ? '' : ':');
    push @out, @terms ? map { sprintf '%s"%s" -> %s. Hint: %s.', $li, $_->[0], $_->[1], $_->[2] } @terms : "${li}none found";
    push @out, '', "${h1}So what? -- sentences to rework" . ($o->{md} ? '' : ':');
    my $k = 0;
    my @bad = grep { @{ $_->{why} } } @sents;
    for my $x (@sents) {
        $k++;
        next unless @{ $x->{why} };
        push @out, sprintf('%s%d. "%s" -- %s', $li, $k, $x->{s}, join('; ', @{ $x->{why} })), $li . '   ' . suggestion($x->{s}, $x->{terms});
    }
    push @out, "${li}none: every sentence has a number and an outcome" unless @bad;
    push @out, '', "${h1}Plain version (nouns swapped only; your sentences otherwise unchanged)" . ($o->{md} ? '' : ':'), $plain =~ s/\s+$//r;
    push @out, '', (@bad ? 'Rework the flagged sentences, then say it.' : 'Ready to say.');
    print join("\n", @out), "\n";
    0;
}

# ---------------------------------------------------------------- main
my @args = @ARGV;
my %o;
Getopt::Long::Configure(qw(pass_through require_order));
GetOptionsFromArray(\@args, \%o, 'local=s', 'url=s', 'token-env=s', 'project=s', 'curl=s') or usage();
my $cmd = shift @args // usage();
help() if $cmd =~ /^(help|-h|--help)$/;
Getopt::Long::Configure(qw(no_pass_through permute));
my %c;
GetOptionsFromArray(\@args, \%c, 'as=s', 'date=s', 'journal=s', 'prefix=s', 'why', 'sprint=s', 'baseline=s', 'metrics=s', 'md', 'glossary=s')
    or usage();
%o = (%o, %c);
exit cmd_translate(\%o, $args[0]) if $cmd eq 'translate';
my %run = (standup => \&cmd_standup, review => \&cmd_review, weekly => \&cmd_weekly);
my $f = $run{$cmd} or do { print STDERR "talk: unknown command '$cmd' (standup, review, weekly, translate, help)\n"; exit 2 };
@args and do { print STDERR "talk: unexpected argument '$args[0]'\n"; exit 2 };
my ($gl, $p) = eval { connect_gl(\%o) } or do { print STDERR $@; exit 2 };
my $rc = eval { $f->($gl, $p, \%o) };
if (!defined $rc) { print STDERR $@; exit 2 }
exit $rc;
