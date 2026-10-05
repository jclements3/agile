package Drills;
# Coding drills: interview-style practice problems in core Perl, the drill log and the refresher plan of the binder's
# coding-drills chapter. The front end is drills/drill.pl; the Vim memory trainer is vim/plugin/drills.vim.
#
#   drills/<NN-section>/section.txt               "Title: ..." then a short description; a section is a trainer level
#   drills/<NN-section>/<dir>/statement.txt        header lines (Title, LeetCode, Origin, Pattern, Timebox, Kind, Call),
#                                                  a blank line, then the contract and examples in this kit's own words
#   drills/<NN-section>/<dir>/tests.pl             a Perl hash: { fn | class | stdio, cmp, call, check, cases => [...] }
#   drills/<NN-section>/<dir>/solution.pl          the reference: a comment block (pattern, why, complexity, edge cases,
#                                                  Perl idioms), then the code
#   drills/<NN-section>/<dir>/stub.pl              the signature and an empty body: what `start` copies
#   drills/phased/<scenario>/                      the four-phase changing-requirements drill (phase1..4.txt, data.pl,
#                                                  solution.pl)
#
# A problem's id is its directory name without a leading "NN-" (two-sum, p23-longest-unique). The workspace (default
# ~/drills-work, or $DRILLS_WORK, or --dir) holds the learner's files <id>.pl, attempts.txt (start/test/solution
# events, append-only) and log.txt (the drill log, append-only). Nothing is written inside the kit.
#
# Tests run in a child perl per problem (function and class kinds) or per case (stdio kind), each case under a
# time limit, so a learner's die, exit or endless loop is reported as a failed case, never a crash of drill.pl.
# Core Perl only (5.10+).
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Spec;
use File::Path qw(make_path);
use File::Copy qw(copy move);
use Time::Local qw(timelocal);

our $VERSION = '1.00';

sub root { require Cwd; Cwd::abs_path(File::Spec->catdir(dirname(File::Spec->rel2abs(__FILE__)), File::Spec->updir)) }
sub drills_dir { my $r = shift // root(); "$r/drills" }
sub workspace { my $d = shift; $d //= $ENV{DRILLS_WORK} // (($ENV{HOME} // '.') . '/drills-work'); $d =~ s{[\\/]+$}{}; $d }

sub _slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t =~ s/\r\n/\n/g; $t }
sub _spit { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "drill: cannot write $f: $!\n"; print $fh $t; close $fh or die "drill: cannot write $f: $!\n" }
sub _append { my ($f, $t) = @_; open my $fh, '>>:raw', $f or die "drill: cannot write $f: $!\n"; print $fh $t; close $fh or die "drill: cannot write $f: $!\n" }
sub _ls { my ($d, $re) = @_; opendir my $dh, $d or return (); my @f = sort grep { !/^\./ && $_ =~ $re } readdir $dh; closedir $dh; @f }
sub _now { my @t = localtime; sprintf '%04d-%02d-%02d %02d:%02d:%02d', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0] }
sub _epoch { my $s = shift; my ($y, $m, $d, $H, $M, $S) = $s =~ /^(\d{4})-(\d\d)-(\d\d)(?: (\d\d):(\d\d):(\d\d))?/ or return undef; timelocal($S // 0, $M // 0, $H // 12, $d, $m - 1, $y) }

# ---------------------------------------------------------------- the problem set
sub parse_statement {                                            # text -> { header fields (lower-case keys), body }
    my $t = shift // '';
    my %h;
    my ($head, $body) = split /\n\s*\n/, $t, 2;
    for (split /\n/, $head // '') { $h{ lc $1 } = $2 if /^([A-Za-z][\w-]*):\s*(.*?)\s*$/ }
    $h{body} = $body // '';
    \%h;
}
sub sections {                                                   # -> ( { dir, name, n, title, about, path }, ... ) in level order
    my $d = drills_dir(shift);
    my @s;
    for my $sd (_ls($d, qr/^\d\d-[\w-]+$/)) {
        next unless -d "$d/$sd";
        my $t = _slurp("$d/$sd/section.txt") // '';
        my ($title) = $t =~ /^Title:\s*(.+?)\s*$/m;
        (my $about = $t) =~ s/^Title:.*\n?//m;
        $about =~ s/^\s+|\s+$//g;
        (my $name = $sd) =~ s/^\d\d-//;
        push @s, { dir => $sd, name => $name, n => scalar(@s) + 1, title => $title // $name, about => $about, path => "$d/$sd" };
    }
    @s;
}
sub problems {                                                   # -> ( problem, ... ) in section then directory order
    my $r = shift;
    my @p;
    for my $s (sections($r)) {
        my $order = 0;
        for my $pd (_ls($s->{path}, qr/^[\w-]+$/)) {
            my $path = "$s->{path}/$pd";
            next unless -f "$path/statement.txt";
            my $st = parse_statement(_slurp("$path/statement.txt"));
            (my $id = $pd) =~ s/^\d\d-//;
            push @p, { %$st, id => $id, dir => $pd, path => $path, section => $s->{name}, section_title => $s->{title},
                       level => $s->{n}, order => ++$order, kind => lc($st->{kind} // 'function'), timebox => $st->{timebox} // 10 };
        }
    }
    @p;
}
sub find_problem {                                               # (root, query) -> problem; dies with the candidates when ambiguous
    my ($r, $q) = @_;
    my @all = problems($r);
    my $want = $q;
    $want =~ s{\.pl$}{}; $want =~ s{.*/}{} if $want =~ m{/};
    my @hit = grep { $_->{id} eq $want || $_->{dir} eq $want } @all;
    @hit = grep { index($_->{id}, $want) == 0 } @all unless @hit;
    @hit = grep { $_->{id} =~ /^\Q$want\E(?:-|$)/ || $_->{id} =~ /-\Q$want\E$/ } @all unless @hit;
    die "drill: no problem matches '$q' (perl drills/drill.pl list)\n" unless @hit;
    die "drill: '$q' matches several problems: " . join(' ', map { $_->{id} } @hit[0 .. ($#hit < 7 ? $#hit : 7)]) . "\n" if @hit > 1;
    $hit[0];
}
sub find_section {
    my ($r, $q) = @_;
    my @s = sections($r);
    my @hit = grep { $_->{name} eq $q || $_->{dir} eq $q || $_->{n} eq $q } @s;
    @hit = grep { index($_->{name}, $q) == 0 } @s unless @hit;
    die "drill: no section '$q' (perl drills/drill.pl list shows them)\n" unless @hit == 1;
    $hit[0];
}
sub tier { my $p = shift; $p->{section} eq 'ladder' && $p->{id} =~ /^p(\d)\d/ ? "t$1" : '' }

# ---------------------------------------------------------------- comparing results
sub _num { my $x = shift; return 0 unless defined $x && !ref $x; $x =~ /^\s*[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?\s*$/ }
sub canon {                                                      # a value as one comparable string
    my $x = shift;
    return 'undef' unless defined $x;
    my $r = ref $x;
    if ($r eq 'ARRAY') { return '[' . join(', ', map { canon($_) } @$x) . ']' }
    if ($r eq 'HASH' || ($r && $r ne 'CODE' && $r ne 'SCALAR' && $r ne 'REF' && eval { my %c = %$x; 1 })) {
        return '{' . join(', ', map { canon_key($_) . ' => ' . canon($x->{$_}) } sort keys %$x) . '}';
    }
    if ($r eq 'SCALAR' || $r eq 'REF') { return '\\' . canon($$x) }
    return "<$r>" if $r;
    if (_num($x)) { my $n = 0 + $x; $n = 0 if $n == 0; return $n == int($n) && abs($n) < 1e15 ? sprintf('%d', $n) : sprintf('%.10g', $n) }
    my $s = $x; $s =~ s/(["\\])/\\$1/g; $s =~ s/\n/\\n/g; $s =~ s/\t/\\t/g; $s =~ s/\r/\\r/g;
    qq("$s");
}
sub canon_key { my $k = shift; _num($k) ? canon($k) : $k =~ /^\w+$/ ? $k : canon($k) }
sub _sorted { my $x = shift; ref $x eq 'ARRAY' ? [ sort { canon($a) cmp canon($b) } @$x ] : $x }
sub _float_eq {
    my ($g, $w, $eps) = @_;
    return !defined $g if !defined $w;
    return 0 if !defined $g;
    if (ref $w eq 'ARRAY') { return 0 unless ref $g eq 'ARRAY' && @$g == @$w; for (0 .. $#$w) { return 0 unless _float_eq($g->[$_], $w->[$_], $eps) } return 1 }
    if (ref $w eq 'HASH') { return 0 unless ref $g eq 'HASH' && canon([ sort keys %$g ]) eq canon([ sort keys %$w ]); for (keys %$w) { return 0 unless _float_eq($g->{$_}, $w->{$_}, $eps) } return 1 }
    return abs($g - $w) <= $eps * (1 + abs $w) if _num($g) && _num($w);
    canon($g) eq canon($w);
}
sub same {                                                       # (got, want, cmp) -> true when the result is right
    my ($got, $want, $cmp) = @_;
    $cmp //= 'exact';
    return (!!$got) == (!!$want) && (!ref $got || !defined $got) if $cmp eq 'bool';
    return _float_eq($got, $want, 1e-6) if $cmp eq 'float';
    if ($cmp eq 'unordered') { return canon(_sorted($got)) eq canon(_sorted($want)) }
    if ($cmp eq 'nested') {
        my $n = sub { my $x = shift; ref $x eq 'ARRAY' ? _sorted([ map { _sorted($_) } @$x ]) : $x };
        return canon($n->($got)) eq canon($n->($want));
    }
    canon($got) eq canon($want);
}

# ---------------------------------------------------------------- helpers the tests may use (linked lists and trees)
sub list_from { my $a = shift; my $head; for my $v (reverse @{ $a // [] }) { $head = { val => $v, next => $head } } $head }
sub list_to { my $n = shift; my @v; my $guard = 0; while ($n && $guard++ < 100000) { push @v, $n->{val}; $n = $n->{next} } \@v }
sub tree_from {                                                  # level order with undef for a missing child: [3, 9, 20, undef, undef, 15, 7]
    my $a = shift // [];
    return undef unless @$a && defined $a->[0];
    my @v = @$a;
    my $root = { val => shift(@v), left => undef, right => undef };
    my @q = ($root);
    while (@q && @v) {
        my $n = shift @q;
        for my $side (qw(left right)) {
            last unless @v;
            my $x = shift @v;
            next unless defined $x;
            $n->{$side} = { val => $x, left => undef, right => undef };
            push @q, $n->{$side};
        }
    }
    $root;
}
sub tree_to {                                                    # the inverse: level order, trailing undefs dropped
    my $root = shift;
    return [] unless $root;
    my (@out, @q) = ();
    @q = ($root);
    while (@q) { my $n = shift @q; if ($n) { push @out, $n->{val}; push @q, $n->{left}, $n->{right} } else { push @out, undef } }
    pop @out while @out && !defined $out[-1];
    \@out;
}
sub tree_find { my ($n, $v) = @_; return undef unless $n; return $n if $n->{val} == $v; tree_find($n->{left}, $v) // tree_find($n->{right}, $v) }

# ---------------------------------------------------------------- running the tests
sub _clone { my $x = shift; my $r = ref $x; return $x unless $r; return [ map { _clone($_) } @$x ] if $r eq 'ARRAY'; return { map { ($_ => _clone($x->{$_})) } keys %$x } if $r eq 'HASH'; $x }
sub load_tests {
    my $f = shift;
    my $spec = do $f;
    die "drill: cannot load tests $f: " . ($@ || $! || 'it does not return a hash') . "\n" unless ref $spec eq 'HASH';
    $spec;
}
sub _capture {                                                   # (\@cmd, stdin file or undef, seconds) -> (exit, stdout, stderr, timed out)
    my ($cmd, $in, $secs) = @_;
    require File::Temp;
    require POSIX;
    my ($ofh, $ofile) = File::Temp::tempfile('drill-out-XXXXXX', TMPDIR => 1, UNLINK => 1);
    my ($efh, $efile) = File::Temp::tempfile('drill-err-XXXXXX', TMPDIR => 1, UNLINK => 1);
    close $ofh; close $efh;
    my $pid = fork;
    return (255, '', "cannot fork: $!", 0) unless defined $pid;
    if (!$pid) {
        open STDIN, '<', (defined $in ? $in : File::Spec->devnull) or POSIX::_exit(126);
        open STDOUT, '>', $ofile or POSIX::_exit(126);
        open STDERR, '>', $efile or POSIX::_exit(126);
        exec @$cmd or do { require POSIX; POSIX::_exit(127) };
    }
    my $t0 = time;
    my ($done, $late) = (0, 0);
    while (!$done) {
        my $w = waitpid($pid, POSIX::WNOHANG());
        if ($w == $pid || $w < 0) { $done = 1; last }
        if (time - $t0 > $secs) { kill 'KILL', $pid; waitpid($pid, 0); $late = 1; last }
        select(undef, undef, undef, 0.02);
    }
    my $rc = $late ? 124 : $? >> 8;
    my $out = _slurp($ofile) // '';
    my $err = _slurp($efile) // '';
    unlink $ofile, $efile;
    ($rc, $out, $err, $late);
}
sub norm_out { my $t = shift // ''; $t =~ s/\r//g; my @l = map { my $x = $_; $x =~ s/\s+$//; $x } split /\n/, $t, -1; pop @l while @l && $l[-1] eq ''; join "\n", @l }
sub _esc { my $t = shift // ''; $t =~ s/\\/\\\\/g; $t =~ s/\t/\\t/g; $t =~ s/\n/\\n/g; $t =~ s/\r/\\r/g; $t }
sub _unesc { my $t = shift // ''; $t =~ s/\\(.)/$1 eq 'n' ? "\n" : $1 eq 't' ? "\t" : $1 eq 'r' ? "\r" : $1/ge; $t }

sub run_tests {                                                  # (problem, file) -> { cases => [ {name, ok, got, want, error} ], passed, total, seconds, error }
    my ($p, $file, %o) = @_;
    my $spec = load_tests("$p->{path}/tests.pl");
    my $t0 = time;
    my @res;
    my $limit = $o{timeout} // $spec->{timeout} // 5;
    if ($spec->{stdio}) {
        require File::Temp;
        my $timeouts = 0;
        for my $c (@{ $spec->{cases} }) {
            my ($name, $in, $want, $opt) = @$c;
            if ($timeouts) { push @res, { name => $name, ok => 0, error => 'not run: an earlier case timed out' }; next }
            my ($ifh, $ifile) = File::Temp::tempfile('drill-in-XXXXXX', TMPDIR => 1, UNLINK => 1);
            binmode $ifh; print $ifh $in; close $ifh;
            my ($rc, $out, $err, $late) = _capture([ $^X, $file ], $ifile, $limit);
            unlink $ifile;
            my %r = (name => $name, got => norm_out($out), want => norm_out($want), input => $in);
            my $want_rc = $opt && defined $opt->{exit} ? $opt->{exit} : 0;
            if ($late) { $r{error} = "timeout after ${limit}s"; $timeouts++ }
            elsif ($rc != $want_rc && !($opt && defined $opt->{exit}) ) { my @e = grep { /\S/ } split /\n/, $err; $r{error} = "exit $rc: " . ($e[-1] // 'no message on stderr') }
            $r{ok} = !$r{error} && $r{got} eq $r{want} && ($rc == $want_rc) ? 1 : 0;
            $r{error} //= "exit status $rc, want $want_rc" if !$r{ok} && $r{got} eq $r{want} && $rc != $want_rc;
            push @res, \%r;
        }
    }
    else {
        my ($rc, $out, $err, $late) = _capture([ $^X, '-I' . root() . '/lib', '-MDrills', '-e', 'exit Drills::_child(@ARGV)', $file, "$p->{path}/tests.pl", $limit ], undef, $limit * (@{ $spec->{cases} } + 2) + 5);
        my %seen;
        for my $line (split /\n/, $out) {
            my ($tag, $name, @f) = split /\t/, $line, -1;
            next unless defined $name;
            if ($tag eq 'load') { return { cases => [], passed => 0, total => scalar @{ $spec->{cases} }, seconds => time - $t0, error => _unesc($name) } }
            next unless $tag =~ /^(?:ok|fail|error)$/;
            $seen{ _unesc($name) } = 1;
            push @res, $tag eq 'error' ? { name => _unesc($name), ok => 0, error => _unesc($f[0]), want => _unesc($f[1]) }
                                       : { name => _unesc($name), ok => $tag eq 'ok' ? 1 : 0, got => _unesc($f[0]), want => _unesc($f[1]) };
        }
        for my $c (@{ $spec->{cases} }) {                        # a case the child never reported: it died or hung there
            next if $seen{ $c->[0] };
            my @e = grep { /\S/ } split /\n/, $err;
            push @res, { name => $c->[0], ok => 0, error => $late ? 'timeout' : 'not run: ' . ($e[-1] // "exit $rc") };
        }
    }
    my $pass = grep { $_->{ok} } @res;
    { cases => \@res, passed => $pass, total => scalar @res, seconds => time - $t0 };
}
sub _child {                                                     # inside the child perl: load the learner's file, run every case
    my ($file, $tests, $limit) = @_;
    $| = 1;
    my $spec = eval { load_tests($tests) } or do { print "load\t" . _esc($@) . "\n"; return 0 };
    no warnings 'once';
    *CORE::GLOBAL::exit = sub { die 'exit(' . (@_ ? $_[0] : 0) . ") called: return a value instead\n" };   # a learner's exit must not end the run
    my $ok = eval { package main; no strict; no warnings; local @ARGV = (); local *STDIN; open STDIN, '<', File::Spec->devnull; my $r = do $file; die $@ if $@; die "cannot read $file: $!\n" if !defined $r && $!; 1 };
    if (!$ok) { my $e = $@ // 'unknown error'; $e =~ s/\s+$//; print "load\t" . _esc($e) . "\n"; return 0 }
    my $fn;
    if ($spec->{fn}) {
        $fn = main->can($spec->{fn});
        if (!$fn) { print "load\t" . _esc("$file does not define sub $spec->{fn}") . "\n"; return 0 }
    }
    if ($spec->{class} && !$spec->{class}->can('new')) { print "load\t" . _esc("$file does not define package $spec->{class} with sub new") . "\n"; return 0 }
    local $SIG{ALRM} = sub { die "timeout after ${limit}s\n" };
    my $timeouts = 0;
    for my $c (@{ $spec->{cases} }) {
        my ($name, $args, $want) = @$c;
        if ($timeouts) { print join("\t", 'error', _esc($name), 'not run: an earlier case timed out', _esc(canon($want))), "\n"; next }
        my @a = @{ _clone($args) };
        my $got;
        my $ran = eval {
            alarm $limit;
            if ($spec->{class}) {
                my ($obj, @out);
                for my $op (@a) {
                    my ($m, @x) = @$op;
                    if ($m eq 'new') { $obj = $spec->{class}->new(@x); push @out, undef }
                    else { push @out, scalar $obj->$m(@x) }
                }
                $got = \@out;
            }
            elsif ($spec->{call}) { $got = $spec->{call}->($fn, @a) }
            else { $got = $fn->(@a) }
            alarm 0;
            1;
        };
        alarm 0;
        if (!$ran) { my $e = $@ // 'died'; $e =~ s/\s+$//; $e =~ s/ at \S+ line \d+\.?$//; $timeouts++ if $e =~ /^timeout after/; print join("\t", 'error', _esc($name), _esc($e), _esc(canon($want))), "\n"; next }
        my $good = $spec->{check} ? eval { $spec->{check}->($got, $want, @{ _clone($args) }) } : same($got, $want, $spec->{cmp});
        print join("\t", $good ? 'ok' : 'fail', _esc($name), _esc(canon($got)), _esc(canon($want))), "\n";
    }
    0;
}

# ---------------------------------------------------------------- the workspace: attempts and the drill log
sub attempts {                                                   # -> ( { time, what, id, result }, ... ) oldest first
    my $ws = shift;
    my @a;
    for (split /\n/, _slurp("$ws/attempts.txt") // '') {
        next if /^\s*(?:#|$)/;
        my ($t, $what, $id, $res) = split /\t/;
        push @a, { time => $t, what => $what, id => $id, result => $res // '' } if defined $id;
    }
    @a;
}
sub record { my ($ws, $what, $id, $res) = @_; make_path($ws) unless -d $ws; _append("$ws/attempts.txt", join("\t", _now(), $what, $id, defined $res ? $res : ()) . "\n") }
sub status_of {                                                  # attempts -> { id => { started, last_start, tests, passed, last_result, last_pass } }
    my %s;
    for my $a (@_) {
        my $s = $s{ $a->{id} } //= {};
        if ($a->{what} eq 'start') { $s->{started}++; $s->{last_start} = $a->{time} }
        elsif ($a->{what} eq 'test') {
            $s->{tests}++;
            $s->{last_result} = $a->{result} =~ /^pass/ ? 'pass' : 'fail';
            $s->{last_test} = $a->{time};
            if ($s->{last_result} eq 'pass') { $s->{passed}++; $s->{last_pass} = $a->{time} }
        }
        elsif ($a->{what} eq 'solution') { $s->{peeked}++ }
    }
    \%s;
}
sub log_entries {
    my $ws = shift;
    my @e;
    for (split /\n/, _slurp("$ws/log.txt") // '') {
        next if /^\s*(?:#|$)/;
        my @f = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $_, 5;
        push @e, { date => $f[0], id => $f[1], minutes => $f[2], passed => $f[3], notes => $f[4] // '' } if @f >= 4;
    }
    @e;
}
our $LOG_HEAD = "# drill log: date | problem | minutes | passed | notes   (append-only; perl drills/drill.pl log)\n";
our $SESSION_FORM = <<'FORM';

SESSION %s   DATE %s   TIME SPENT ______

DONE (problems, phases, tiers)
  -
SLOWEST OR WEAKEST THING TODAY (a pattern, an idiom, a parse; be specific)
  -
LOOKUPS I NEEDED (idioms or functions I could not type from memory)
  -
NARRATION CHECK (did I talk the whole time? where did I go silent?)
  -
QUESTIONS CHECK (did I ask five before typing? which did I forget?)
  -
ONE THING TO REDO NEXT SESSION
  -
FORM

# ---------------------------------------------------------------- the refresher plan
our @SESSIONS = (
    [ 0, 'setup: the workspace, the habits, drill.pl test proven on p00' ],
    [ 1, 'foundations: the toolbelt from memory, ladder t0 and t1' ],
    [ 2, 'parsing shapes and the core patterns: ladder t2' ],
    [ 3, 'the first phased drill, timed, then reviewed' ],
    [ 4, 'the hard classics (ladder t3) and a rebuild of the weakest pattern' ],
    [ 5, 'the pro tier (ladder t4) and a second phased drill with fresh data' ],
    [ 6, 'taper: recall only (the Vim trainer, the complexity table), no new material' ],
    [ 7, 'teach-back: one t2 or t3 problem with a colleague' ],
);
our %TIER_SESSION = (t0 => 1, t1 => 1, t2 => 2, t3 => 4, t4 => 5, t5 => 'spare');
sub suggest {                                                    # (root, workspace) -> { id, why, session } or a phase/plan hint
    my ($r, $ws) = @_;
    my @p = problems($r);
    my $st = status_of(attempts($ws));
    my @phased = grep { $_->{id} =~ /^phased-/ && $_->{what} eq 'test' && $_->{result} =~ /^pass/ } attempts($ws);
    my %phase_runs; $phase_runs{ $_->{time} =~ /^(\S+)/ ? $1 : '' }++ for @phased;
    my $runs = keys %phase_runs;
    my @redo = grep { my $s = $st->{ $_->{id} }; $s && $s->{last_result} && $s->{last_result} eq 'fail' } @p;
    my $passed = sub { my $s = $st->{ $_[0]{id} }; $s && $s->{passed} };
    my @ladder = grep { $_->{section} eq 'ladder' } @p;
    my $done_tier = sub { my $t = shift; !grep { tier($_) eq $t && !$passed->($_) } @ladder };
    if (@redo) { my $x = $redo[0]; return { id => $x->{id}, p => $x, why => 'its last test failed: finish it first (the log\'s "one thing to redo")' } }
    for my $t (qw(t0 t1 t2 t3 t4)) {
        if ($t eq 't3' && $done_tier->('t2') && $runs < 1) { return { phased => 1, why => 'ladder t0-t2 pass: session 3 is the first phased drill', session => 3 } }
        my ($x) = grep { tier($_) eq $t && !$passed->($_) } @ladder;
        return { id => $x->{id}, p => $x, why => "the first unsolved ladder problem (tier $t)", session => $TIER_SESSION{$t} } if $x;
    }
    return { phased => 1, why => 'the whole ladder t0-t4 passes: session 5 runs the phased drill again with fresh data', session => 5 } if $runs < 2;
    my ($f) = grep { tier($_) eq 't5' && !$passed->($_) } @ladder;
    return { id => $f->{id}, p => $f, why => 'the field drills (t5) are the work itself: all eight before the weekly rotation', session => 'spare' } if $f;
    my %sec;                                                     # the weakest section: the lowest share passed (unstarted sections count)
    for my $x (@p) { my $s = $sec{ $x->{section} } //= { n => 0, ok => 0, first => undef, level => $x->{level} }; $s->{n}++; if ($passed->($x)) { $s->{ok}++ } else { $s->{first} //= $x } }
    my @weak = sort { $sec{$a}{ok} / $sec{$a}{n} <=> $sec{$b}{ok} / $sec{$b}{n} || $sec{$a}{level} <=> $sec{$b}{level} } grep { $sec{$_}{first} } keys %sec;
    if (@weak) { my $s = $sec{ $weak[0] }; return { id => $s->{first}{id}, p => $s->{first}, why => sprintf('the weakest section: %s (%d of %d pass)', $weak[0], $s->{ok}, $s->{n}) } }
    my ($old) = sort { ($st->{ $a->{id} }{last_pass} // '') cmp ($st->{ $b->{id} }{last_pass} // '') || $a->{level} <=> $b->{level} } @p;
    return { id => $old->{id}, p => $old, why => 'everything passes: re-solve the one passed longest ago, cold, from a blank file (--fresh)' } if $old;
    { why => 'no problems found under drills/' };
}

# ---------------------------------------------------------------- the phased drill
sub phased_dir { my ($r, $s) = @_; drills_dir($r) . "/phased/$s" }
sub scenarios { my $d = drills_dir(shift) . '/phased'; grep { -f "$d/$_/data.pl" } _ls($d, qr/^[\w-]+$/) }
sub phased_check {                                               # (root, scenario, phase, file) -> (ok, @report lines)
    my ($r, $sc, $n, $file) = @_;
    my $dir = phased_dir($r, $sc);
    my ($rc, $out, $err, $late) = _capture([ $^X, '-I' . root() . '/lib', '-MDrills', '-e', 'exit Drills::_phased_child(@ARGV)', $file, "$dir/data.pl", $n ], undef, 30);
    my @l = split /\n/, $out;
    if ($late) { push @l, 'timeout after 30s' }
    elsif (!grep { /^(?:PASS|not yet)$/ } @l) { my @e = grep { /\S/ } split /\n/, $err; push @l, 'crashed: ' . ($e[-1] // "exit $rc"), 'not yet' }
    ((grep { $_ eq 'PASS' } @l) ? 1 : 0, grep { $_ ne 'PASS' && $_ ne 'not yet' } @l);
}
sub _phased_child {
    my ($file, $data, $n) = @_;
    $| = 1;
    my $d = do $data or do { print "cannot load $data: ", ($@ || $!), "\nnot yet\n"; return 0 };
    my $ok = eval { package main; no strict; no warnings; my $r = do $file; die $@ if $@; 1 };
    if (!$ok) { my $e = $@; $e =~ s/\s+$//; print "your file does not load: $e\nnot yet\n"; return 0 }
    my $solve = main->can('solve') or do { print "your file has no sub solve\nnot yet\n"; return 0 };
    my $pass = $d->{check}->($solve, $n, sub { print @_, "\n" });
    print $pass ? "PASS\n" : "not yet\n";
    0;
}

1;
