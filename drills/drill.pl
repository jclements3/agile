#!/usr/bin/perl
# drill.pl -- coding drills in core Perl: the problem ladder, the technique sections, the drill log, the refresher plan.
#
#   perl drills/drill.pl list [SECTION]          the problems (id, pattern, timebox, your status)
#   perl drills/drill.pl show ID                 a problem's statement
#   perl drills/drill.pl start ID [--fresh]      copy the stub to the workspace (~/drills-work/ID.pl), start the clock
#   perl drills/drill.pl test ID [FILE] [--ref]  run the tests against your file: pass/fail per case, elapsed time
#   perl drills/drill.pl check [SECTION|ID|t2]   test every file you have in the workspace (the binder's check.sh)
#   perl drills/drill.pl solution ID [--force]   the reference solution, only after an attempt was recorded
#   perl drills/drill.pl log [ID [MIN] [pass|fail] [NOTES]] | log --session N   the drill log (append-only)
#   perl drills/drill.pl stats                   per section: started, passed, minutes; the weakest section
#   perl drills/drill.pl next                    what to do next, by the refresher plan
#   perl drills/drill.pl phased [N|test N [FILE]|solution] [--scenario S]   the four-phase changing-requirements drill
#   perl drills/drill.pl help [COMMAND]          the help (the same text as :help agile-drills)
# Options: --dir DIR (the workspace; default $DRILLS_WORK or ~/drills-work). Logic in lib/Drills.pm. Core Perl only.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptionsFromArray);
use File::Path qw(make_path);
use File::Copy qw(copy move);
use File::Spec;
use Drills ();

my $ROOT = Drills::root();

our @PHASE_CLOCK = (
    [ '0-5',   'Ask',     'Five questions, restate the problem, write assumptions as comments. No code.' ],
    [ '5-10',  'Declare', 'State the approach and its complexity. Write the function names and two tests.' ],
    [ '10-25', 'Phase 1', 'Make it work, brute force allowed. Run the tests.' ],
    [ '25-40', 'Phase 2 and 3', 'Requirements change. Refactor, re-run the tests after each edit.' ],
    [ '40-55', 'Phase 4', 'Edge and unsolvable cases. State the contract for "no answer".' ],
    [ '55-60', 'Close',   'What you would do with more time, what you would test, where it breaks at scale.' ],
);

my %CMDS = (
    list     => \&cmd_list,
    show     => \&cmd_show,
    start    => \&cmd_start,
    test     => \&cmd_test,
    check    => \&cmd_check,
    solution => \&cmd_solution,
    log      => \&cmd_log,
    stats    => \&cmd_stats,
    next     => \&cmd_next,
    phased   => \&cmd_phased,
    help     => \&cmd_help,
);

my @a = @ARGV;
my %o;
GetOptionsFromArray(\@a, 'dir=s' => \$o{dir}, 'force' => \$o{force}, 'fresh' => \$o{fresh}, 'ref' => \$o{ref},
    'scenario=s' => \$o{scenario}, 'session=s' => \$o{session}, 'h|help' => \$o{help}) or exit 2;
my $cmd = $o{help} ? 'help' : shift(@a) // 'help';
my $WS = Drills::workspace($o{dir});
my $run = $CMDS{$cmd} or do { print STDERR "drill: unknown command '$cmd' (perl drills/drill.pl help)\n"; exit 2 };
my $rc = eval { $run->(@a) };
if (!defined $rc) { print STDERR $@ =~ /^drill:/ ? $@ : "drill: $@"; exit 1 }
exit $rc;

sub _abs { my $f = shift; File::Spec->file_name_is_absolute($f) ? $f : File::Spec->rel2abs($f) }
sub _mins { my $s = shift; my $e = Drills::_epoch($s) // return undef; int((time - $e) / 60 + 0.5) }
sub _status_word { my $s = shift or return '-'; $s->{last_result} ? ($s->{passed} ? 'passed' : 'failed') : 'started' }

sub cmd_list {
    my ($q) = @_;
    my @p = Drills::problems($ROOT);
    if (defined $q) { my $s = Drills::find_section($ROOT, $q); @p = grep { $_->{section} eq $s->{name} } @p }
    my $st = Drills::status_of(Drills::attempts($WS));
    my $sec = '';
    for my $p (@p) {
        if ($p->{section} ne $sec) {
            $sec = $p->{section};
            my $n = grep { $_->{section} eq $sec } @p;
            my $ok = grep { $_->{section} eq $sec && ($st->{ $_->{id} } && $st->{ $_->{id} }{passed}) } @p;
            printf "\n%d. %s  (%s, %d problems, %d passed)\n", $p->{level}, $p->{section_title}, $sec, $n, $ok;
        }
        printf "  %-30s %-34s %3s min  %s\n", $p->{id}, substr($p->{pattern} // '', 0, 34), $p->{timebox}, _status_word($st->{ $p->{id} });
    }
    print "\nstart one: perl drills/drill.pl start ID    (workspace: $WS)\n";
    0;
}

sub cmd_show {
    my ($q) = @_;
    defined $q or die "drill: usage: drill.pl show ID\n";
    my $p = Drills::find_problem($ROOT, $q);
    print Drills::_slurp("$p->{path}/statement.txt");
    0;
}

sub cmd_start {
    my ($q) = @_;
    defined $q or die "drill: usage: drill.pl start ID [--fresh] [--dir DIR]\n";
    my $p = Drills::find_problem($ROOT, $q);
    make_path($WS) unless -d $WS;
    my $f = "$WS/$p->{id}.pl";
    if (-e $f && $o{fresh}) {
        make_path("$WS/old");
        my $t = Drills::_now(); $t =~ s/[-: ]//g;
        move($f, "$WS/old/$p->{id}.$t.pl") or die "drill: cannot write $WS/old/$p->{id}.$t.pl: $!\n";
    }
    if (-e $f) { print "keeping your file $f (--fresh starts over; the old one goes to old/)\n" }
    else { copy("$p->{path}/stub.pl", $f) or die "drill: cannot write $f: $!\n"; print "wrote $f\n" }
    Drills::record($WS, 'start', $p->{id});
    print Drills::_slurp("$p->{path}/statement.txt");
    printf "\nclock started (timebox %s min). Edit %s, then: perl drills/drill.pl test %s\n", $p->{timebox}, $f, $p->{id};
    0;
}

sub _show_case {
    my $c = shift;
    my $mark = $c->{ok} ? 'pass' : 'FAIL';
    my $out = sprintf "  %s  %s\n", $mark, $c->{name};
    return $out if $c->{ok};
    $out .= "        error    | $c->{error}\n" if $c->{error};
    if (defined $c->{want}) {
        my $show = sub { my $x = shift // ''; $x =~ s/\n/\\n/g; length $x > 200 ? substr($x, 0, 200) . '...' : $x };
        $out .= "        input    | " . $show->($c->{input}) . "\n" if defined $c->{input};
        $out .= "        expected | " . $show->($c->{want}) . "\n";
        $out .= "        got      | " . $show->($c->{got}) . "\n" if defined $c->{got};
    }
    $out;
}
sub cmd_test {
    my ($q, $file) = @_;
    defined $q or die "drill: usage: drill.pl test ID [FILE] [--ref]\n";
    my $p = Drills::find_problem($ROOT, $q);
    $file = $o{ref} ? "$p->{path}/solution.pl" : $file // "$WS/$p->{id}.pl";
    -f $file or die "drill: no file $file (perl drills/drill.pl start $p->{id} first)\n";
    $file = _abs($file);
    my $r = Drills::run_tests($p, $file);
    if ($r->{error}) { print "  FAIL  your file does not load: $r->{error}\n" }
    print _show_case($_) for @{ $r->{cases} };
    my $st = Drills::status_of(Drills::attempts($WS))->{ $p->{id} };
    my $since = $st && $st->{last_start} ? _mins($st->{last_start}) : undef;
    my $verdict = $r->{passed} == $r->{total} && !$r->{error} ? 'pass' : 'fail';
    printf "%s: %d/%d passed in %ds%s\n", $p->{id}, $r->{passed}, $r->{total}, $r->{seconds},
        defined $since ? sprintf('; %d min since start (timebox %s)', $since, $p->{timebox}) : '';
    Drills::record($WS, 'test', $p->{id}, "$verdict $r->{passed}/$r->{total}") unless $o{ref};
    print "log it: perl drills/drill.pl log $p->{id}   (minutes and result filled in; add a note)\n" if $verdict eq 'pass' && !$o{ref};
    $verdict eq 'pass' ? 0 : 1;
}

sub cmd_check {
    my ($q) = @_;
    my @p = Drills::problems($ROOT);
    if (defined $q) {
        my @t = grep { $_->{section} eq $q } @p;                 # a section first, then a ladder tier, then ids by prefix
        @t = grep { Drills::tier($_) eq $q } @p unless @t;
        @t = grep { $_->{id} eq $q || index($_->{id}, $q) == 0 } @p unless @t;
        die "drill: no problem matches '$q' (perl drills/drill.pl list)\n" unless @t;
        @p = @t;
    }
    my ($pass, $fail, @todo) = (0, 0);
    for my $p (@p) {
        my $f = $o{ref} ? "$p->{path}/solution.pl" : "$WS/$p->{id}.pl";
        if (!-f $f) { push @todo, $p->{id}; next }
        my $r = Drills::run_tests($p, _abs($f));
        my $good = $r->{passed} == $r->{total} && !$r->{error};
        printf "  %s  %-32s %d/%d%s\n", $good ? 'pass' : 'FAIL', $p->{id}, $r->{passed}, $r->{total}, $r->{error} ? "  ($r->{error})" : '';
        $good ? $pass++ : $fail++;
        Drills::record($WS, 'test', $p->{id}, ($good ? 'pass' : 'fail') . " $r->{passed}/$r->{total}") unless $o{ref};
    }
    printf "%d passed, %d failed, %d not started (of %d)\n", $pass, $fail, scalar @todo, scalar @p;
    $fail ? 1 : 0;
}

sub cmd_solution {
    my ($q) = @_;
    defined $q or die "drill: usage: drill.pl solution ID [--force]\n";
    my $p = Drills::find_problem($ROOT, $q);
    my $st = Drills::status_of(Drills::attempts($WS))->{ $p->{id} };
    if (!$o{force} && !($st && ($st->{started} || $st->{tests}))) {
        die "drill: no attempt recorded for $p->{id} yet: perl drills/drill.pl start $p->{id} first (or --force)\n";
    }
    Drills::record($WS, 'solution', $p->{id});
    print Drills::_slurp("$p->{path}/solution.pl");
    0;
}

sub cmd_log {
    my @w = @_;
    make_path($WS) unless -d $WS;
    my $f = "$WS/log.txt";
    Drills::_append($f, $Drills::LOG_HEAD) unless -f $f;
    if (defined $o{session}) {
        $o{session} =~ /^\d+$/ or die "drill: usage: drill.pl log --session N (N = 0..7, the refresher session)\n";
        my $d = Drills::_now(); $d =~ s/ .*//;
        Drills::_append($f, sprintf $Drills::SESSION_FORM, $o{session}, $d);
        print "appended a session $o{session} form to $f: fill it in (vim + $f)\n";
        return 0;
    }
    if (!@w) {
        my @e = Drills::log_entries($WS);
        if (!@e) { print "the drill log is empty ($f). After a test: perl drills/drill.pl log ID [MIN] [pass|fail] [NOTES]\n"; return 0 }
        printf "%-10s  %-30s %4s  %-4s  %s\n", 'date', 'problem', 'min', 'pass', 'notes';
        printf "%-10s  %-30s %4s  %-4s  %s\n", $_->{date}, $_->{id}, $_->{minutes}, $_->{passed}, $_->{notes} for @e;
        my $m = 0; $m += $_->{minutes} =~ /^\d+$/ ? $_->{minutes} : 0 for @e;
        printf "%d entries, %d minutes in all. The session forms are in %s.\n", scalar @e, $m, $f;
        return 0;
    }
    my $id = shift @w;
    my $p = $id =~ /^phased/ ? { id => $id } : Drills::find_problem($ROOT, $id);
    my $st = Drills::status_of(Drills::attempts($WS))->{ $p->{id} };
    my $min = @w && $w[0] =~ /^\d+$/ ? shift @w : undef;
    die "drill: '$w[0]' is not a number of minutes (drill.pl log ID MINUTES pass|fail NOTES)\n" if !defined $min && @w && $w[0] =~ /^\d+(?:\.\d+)?m?$/ && $w[0] !~ /^\d+$/;
    my $res = @w && $w[0] =~ /^(?:pass|fail|yes|no)$/i ? lc shift @w : undef;
    $min //= $st && $st->{last_start} ? _mins($st->{last_start}) : 0;
    $res //= $st && $st->{last_result} ? $st->{last_result} : 'fail';
    $res = $res eq 'yes' ? 'pass' : $res eq 'no' ? 'fail' : $res;
    my $notes = join ' ', @w;
    $notes =~ s/\|/\//g;
    my $d = Drills::_now(); $d =~ s/ .*//;
    Drills::_append($f, "$d | $p->{id} | $min | $res | $notes\n");
    print "logged: $d | $p->{id} | $min | $res | $notes\n";
    0;
}

sub cmd_stats {
    my @p = Drills::problems($ROOT);
    my $st = Drills::status_of(Drills::attempts($WS));
    my %min; for (Drills::log_entries($WS)) { $min{ $_->{id} } += $_->{minutes} =~ /^\d+$/ ? $_->{minutes} : 0 }
    my (%s, @order);
    for my $p (@p) {
        my $x = $s{ $p->{section} } //= do { push @order, $p->{section}; { n => 0, started => 0, passed => 0, min => 0, peeked => 0, title => $p->{section_title} } };
        my $a = $st->{ $p->{id} } // {};
        $x->{n}++; $x->{started}++ if $a->{started} || $a->{tests}; $x->{passed}++ if $a->{passed}; $x->{peeked}++ if $a->{peeked};
        $x->{min} += $min{ $p->{id} } // 0;
    }
    printf "%-22s %8s %8s %8s %8s %8s\n", 'section', 'problems', 'started', 'passed', 'peeked', 'minutes';
    my ($T, $P) = (0, 0);
    for my $k (@order) { my $x = $s{$k}; printf "%-22s %8d %8d %8d %8d %8d\n", $k, @$x{qw(n started passed peeked min)}; $T += $x->{n}; $P += $x->{passed} }
    my @weak = sort { $s{$a}{passed} / $s{$a}{n} <=> $s{$b}{passed} / $s{$b}{n} } grep { $s{$_}{started} } @order;
    printf "%d of %d problems pass.%s\n", $P, $T, @weak ? sprintf(' Weakest section you have started: %s (%d of %d).', $weak[0], $s{ $weak[0] }{passed}, $s{ $weak[0] }{n}) : '';
    my @e = Drills::log_entries($WS);
    if (@e) { my %days = map { $_->{date} => 1 } @e; printf "drill log: %d entries over %d day(s); last %s %s.\n", scalar @e, scalar(keys %days), $e[-1]{date}, $e[-1]{id} }
    0;
}

sub cmd_next {
    my $n = Drills::suggest($ROOT, $WS);
    if ($n->{phased}) {
        print "next: the phased drill (session $n->{session})\n  why: $n->{why}\n  run: perl drills/drill.pl phased 1\n";
        return 0;
    }
    if (!$n->{id}) { print "next: $n->{why}\n"; return 0 }
    my $p = $n->{p};
    my $where = $p->{section} eq 'ladder' ? 'ladder ' . Drills::tier($p) : $p->{section};
    my $sess = defined $n->{session} ? ($n->{session} eq 'spare' ? ', any spare 15 minutes' : ", refresher session $n->{session}") : '';
    printf "next: %s  %s  (%s%s, timebox %s min)\n  why: %s\n  run: perl drills/drill.pl start %s\n", $p->{id}, $p->{title} // '', $where, $sess, $p->{timebox}, $n->{why}, $p->{id};
    0;
}

sub cmd_phased {
    my @w = @_;
    my @sc = Drills::scenarios($ROOT);
    my $sc = $o{scenario} // ((grep { $_ eq q(sensors) } @sc) ? q(sensors) : $sc[0]) // die "drill: phased: no scenarios under drills/phased/\n";
    grep { $_ eq $sc } @sc or die "drill: phased: no scenario '$sc' (there are: @sc)\n";
    my $dir = Drills::phased_dir($ROOT, $sc);
    my $id = "phased-$sc";
    my $file = "$WS/$id.pl";
    if (!@w) {
        print "The phased drill: one 60-minute problem that changes four times (scenario '$sc'" . (@sc > 1 ? '; also: ' . join(' ', grep { $_ ne $sc } @sc) : '') . ").\n";
        print "Set a timer, narrate the whole hour, read each phase only when the previous one passes.\n\n";
        printf "  %-6s %-14s %s\n", @$_ for @PHASE_CLOCK;
        print "\n  perl drills/drill.pl phased 1            phase 1's card; starts the clock, writes $file\n";
        print "  perl drills/drill.pl phased test 1       check your solve() against phase 1 (then 2, 3, 4)\n";
        print "  perl drills/drill.pl phased solution     the reference, after an attempt\n";
        print "  --scenario NAME picks another scenario: a second run should not be memorised.\n";
        return 0;
    }
    my $what = shift @w;
    if ($what =~ /^[1-4]$/) {
        my $card = Drills::_slurp("$dir/phase$what.txt") // die "drill: phased: no phase $what in $dir\n";
        if ($what == 1) {
            make_path($WS) unless -d $WS;
            if (!-e $file) { copy("$dir/stub.pl", $file) or die "drill: cannot write $file: $!\n"; print "wrote $file\n" }
            Drills::record($WS, 'start', $id);
            print "Before typing: five clarifying questions, out loud. Write the answers (or your assumptions) as comments.\n\n";
        }
        print $card;
        print "\nWhen it works: perl drills/drill.pl phased test $what" . ($o{scenario} ? " --scenario $sc" : '') . "\n";
        return 0;
    }
    if ($what eq 'test') {
        my $n = shift @w // die "drill: usage: drill.pl phased test N [FILE]\n";
        $n =~ /^[1-4]$/ or die "drill: phased: no phase $n (1 to 4)\n";
        my $f = $o{ref} ? "$dir/solution.pl" : shift(@w) // $file;
        -f $f or die "drill: no file $f (perl drills/drill.pl phased 1 first)\n";
        my ($ok, @rep) = Drills::phased_check($ROOT, $sc, $n, _abs($f));
        print "  $_\n" for @rep;
        print $ok ? "phase $n: PASS" . ($n < 4 ? "  -> perl drills/drill.pl phased " . ($n + 1) : '  -> close: more time, more tests, scale') . "\n" : "phase $n: not yet\n";
        Drills::record($WS, 'test', "$id-$n", $ok ? 'pass' : 'fail') unless $o{ref};
        return $ok ? 0 : 1;
    }
    if ($what eq 'solution') {
        my $st = Drills::status_of(Drills::attempts($WS))->{$id};
        die "drill: no attempt recorded for $id yet: perl drills/drill.pl phased 1 first (or --force)\n" unless $o{force} || $st;
        Drills::record($WS, 'solution', $id);
        print Drills::_slurp("$dir/solution.pl");
        return 0;
    }
    die "drill: usage: drill.pl phased [N | test N [FILE] | solution] [--scenario S]\n";
}

sub cmd_help {
    my ($c) = @_;
    require Help;
    binmode STDOUT, ':raw';
    my $h = Help::load();
    my $s = defined $c ? ($h->{tags}{"agile-drills-$c"} // Help::resolve($h, $c)) : $h->{tags}{'agile-drills'};
    if (!$s) { print "no help for '$c'. perl agile.pl help search $c\n"; return 1 }
    print Help::plain(Help::lines_of($s, own => defined $c ? 0 : 1));
    print "\nOne command: perl drills/drill.pl help COMMAND. In Vim: :help agile-drills\n" unless defined $c;
    0;
}
