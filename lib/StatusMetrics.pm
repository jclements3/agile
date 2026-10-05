package StatusMetrics;
# The 26 status metrics (A-Z) of docs/STATUS-METRICS.html: collect a daily snapshot from a model repo and its exports,
# then build the status tables. A core-Perl port of the Python kit's collect.py; outputs are byte-identical to it.
#
#   status-metrics.pl init    --config metrics.json --xmi legacy.xmi --reqif export.reqif
#   status-metrics.pl collect --config metrics.json --as-of YYYY-MM-DD [--history history.jsonl]
#   status-metrics.pl report  --config metrics.json --history history.jsonl --out DIR
#
# init     freezes the denominators (v1 element total, DOORS requirement total).
# collect  takes one snapshot as of the end of a day and appends it to the history (JSON lines).
# report   writes status-weekly.md (A-Z by week), status-daily.csv and dashboard.json.
#
# Paths in the config are relative to the config file. Collection methods follow Appendix A of the doc.
#
# Not lib/Metrics.pm: that one is the scrum journal's thresholds. This one reads a SysML v2 text repo (git), its
# generated documents and the exports (gate.log, ci_jobs.csv, tracker/sprint-N.csv, legacy_icd.csv, runs/*/provenance.txt,
# defects.csv). It needs git on PATH and runs the config's lint_cmd and gen_cmd.
#
# JSON is read and written by a small Python-compatible codec here (objects keep their key order, json.dumps spacing,
# ensure_ascii), not JSON::PP, so history.jsonl, dashboard.json and an init'ed config are byte-identical to the
# Python kit's. A string that looks like a number (D's "tag") is a StatusMetrics::Str so it stays a JSON string.
use strict;
use warnings;
use B ();
use POSIX qw(floor);
use Time::Local qw(timegm);
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use Digest::SHA;
use Archive::Tar;

our @EXPORT = qw(collect load_cfg hash_dir parse_model run_gen json_encode json_decode oh);
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$_"} = \&{"${class}::$_"} for @want;
}

my $PAT  = qr/^\s*(part|port|interface|connection|action|item)( def)?\b/;
my $REQ  = qr/^\s*requirement\s+(\w+)\s*\{(.*)\}/;
my $SAT  = qr/^\s*satisfy\s+(\w+)\b/;
my $VER  = qr/^\s*verify\s+(\w+)\b/;
my $IFC  = qr/^\s*interface\s+(\w+)\s*\{(.*)\}/;
my $THR  = qr/^\s*metadata\s+(\w+)\s*:\s*Threat\s*\{(.*)\}/;
my $XMI_IN_SCOPE = qr/xmi:type="uml:(?:Class|Port|Property|Connector|Activity)"/;
our @ICD_FIELDS = qw(from to fromZone toZone signal rate units);
our @LETTERS = ('A' .. 'Z');
my $DASH = "\xe2\x80\x94";                    # an em dash, UTF-8 bytes (outputs are written raw)

our %NAMES = (
 A => "% under configuration control", B => "Segments gated (of {segments})",
 C => "Requirements linked (of {req_total:,})", D => "Elements in latest baseline",
 E => "Lint errors / warnings", F => "Orphan requirements", G => "Unverified requirements",
 H => "Interface mismatches caught (to date)", I => "Trace completeness %",
 J => "Labor hours saved per baseline", K => "Regeneration time (min)",
 L => "Documents generated (of {docs_total})", M => "Hand edits", N => "Lead time (days)",
 O => "Parameters sourced (of {params_total})", P => "Sim runs pinned (to date)",
 Q => "Uncovered zone crossings", R => "Unmitigated threats", S => "Reproducible baselines",
 T => "Legacy ICD discrepancies open", U => "Merges per sprint", V => "Change failure rate %",
 W => "Time to restore (h)", X => "Done % (sprint)", Y => "Blocked days (sprint)",
 Z => "Active contributors (of {team})");
my %SPRINT_METRICS = map { $_ => 1 } qw(U V X Y);

# ---------------------------------------------------------------- ordered hashes and typed scalars
{
    package StatusMetrics::OHash;             # a hash that remembers insertion order (Python dict semantics)
    sub TIEHASH  { bless { k => [], h => {} }, shift }
    sub STORE    { my ($s, $k, $v) = @_; push @{ $s->{k} }, $k unless exists $s->{h}{$k}; $s->{h}{$k} = $v }
    sub FETCH    { $_[0]{h}{ $_[1] } }
    sub EXISTS   { exists $_[0]{h}{ $_[1] } }
    sub DELETE   { my ($s, $k) = @_; return undef unless exists $s->{h}{$k}; @{ $s->{k} } = grep { $_ ne $k } @{ $s->{k} }; delete $s->{h}{$k} }
    sub CLEAR    { my $s = shift; $s->{k} = []; $s->{h} = {} }
    sub FIRSTKEY { my $s = shift; $s->{i} = 0; $s->{k}[0] }
    sub NEXTKEY  { my $s = shift; $s->{k}[ ++$s->{i} ] }
    sub SCALAR   { scalar @{ $_[0]{k} } }
}
{
    package StatusMetrics::Str;               # a string that must stay a JSON string even if it looks like a number
    use overload '""' => sub { ${ $_[0] } }, 'eq' => sub { "$_[0]" eq "$_[1]" }, fallback => 1;
    sub new { my ($c, $v) = @_; bless \$v, $c }
}
{
    package StatusMetrics::Num;               # a JSON float: kept apart so Perl's integer-preserving arithmetic can't turn 4.0 into 4
    use overload '0+' => sub { ${ $_[0] } }, '""' => sub { ${ $_[0] } }, fallback => 1;
    sub new { my ($c, $v) = @_; my $n = 0 + $v; bless \$n, $c }
}
{
    package StatusMetrics::Bool;
    use overload 'bool' => sub { ${ $_[0] } }, '""' => sub { ${ $_[0] } ? 'true' : 'false' }, fallback => 1;
    sub new { my ($c, $v) = @_; bless \$v, $c }
}

sub oh {                                      # oh(k => v, ...) -> an ordered hashref
    tie my %h, 'StatusMetrics::OHash';
    while (@_) { my $k = shift; $h{$k} = shift }
    return \%h;
}
sub str { StatusMetrics::Str->new($_[0]) }

# ---------------------------------------------------------------- JSON, Python-compatible
sub _is_num {
    my ($v) = @_;
    my $f = B::svref_2object(\$v)->FLAGS;                 # a number that was later printed keeps IOK/NOK and gains POK
    return 0 unless $f & (B::SVp_IOK | B::SVp_NOK);
    return !($f & B::SVp_POK) || $v =~ /^-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?$/;
}
sub _numeric { my ($v) = @_; return ref $v ? ref $v eq 'StatusMetrics::Num' : defined $v && _is_num($v) }
sub _py_float {                               # repr(float): shortest round-trip, Python's switch to exponent form
    my ($v) = @_;
    return 'NaN' if $v != $v;
    return $v > 0 ? 'Infinity' : '-Infinity' if $v == 9**9**9 || $v == -9**9**9;
    my $s;
    for my $p (0 .. 16) { $s = sprintf("%.${p}e", $v); last if $s + 0 == $v }
    my ($sign, $int, $frac, $exp) = $s =~ /^(-?)(\d)(?:\.(\d+))?e([-+]\d+)$/ or return "$v";
    my $digits = $int . ($frac // '');
    $digits =~ s/0+$//; $digits = '0' if $digits eq '';
    $exp += 0;
    if ($exp < -4 || $exp >= 16) {
        my $m = substr($digits, 0, 1) . (length $digits > 1 ? '.' . substr($digits, 1) : '');
        return sprintf('%s%se%s%02d', $sign, $m, $exp < 0 ? '-' : '+', abs $exp);
    }
    if ($exp < 0) { return "${sign}0." . ('0' x (-$exp - 1)) . $digits }
    my $ip = substr($digits . ('0' x ($exp + 1)), 0, $exp + 1);
    my $fp = length $digits > $exp + 1 ? substr($digits, $exp + 1) : '0';
    return "$sign$ip.$fp";
}
sub _json_str {
    my ($s) = @_;
    $s =~ s/(["\\])/\\$1/g;
    $s =~ s/\n/\\n/g; $s =~ s/\r/\\r/g; $s =~ s/\t/\\t/g; $s =~ s/\x08/\\b/g; $s =~ s/\f/\\f/g;
    $s =~ s/([\x00-\x1f\x{80}-\x{ffff}])/sprintf('\\u%04x', ord $1)/ge;
    $s =~ s/([^\x00-\x{ffff}])/my $c = ord($1) - 0x10000; sprintf('\\u%04x\\u%04x', 0xd800 + ($c >> 10), 0xdc00 + ($c & 0x3ff))/ge;
    return qq("$s");
}
sub json_encode {                              # json_encode($v [, $indent]) -> text, as Python's json.dumps(v[, indent=N])
    my ($v, $ind, $lvl) = @_;
    $lvl //= 0;
    my ($nl, $nl1, $sep) = defined $ind ? ("\n" . (' ' x ($ind * $lvl)), "\n" . (' ' x ($ind * ($lvl + 1))), ',') : ('', '', ', ');
    return 'null' unless defined $v;
    my $r = ref $v;
    if ($r eq 'HASH') {
        my @k = keys %$v;
        return '{}' unless @k;
        return '{' . join($sep, map { $nl1 . _json_str($_) . ': ' . json_encode($v->{$_}, $ind, $lvl + 1) } @k) . "$nl}";
    }
    if ($r eq 'ARRAY') {
        return '[]' unless @$v;
        return '[' . join($sep, map { $nl1 . json_encode($_, $ind, $lvl + 1) } @$v) . "$nl]";
    }
    return "$v" if $r eq 'StatusMetrics::Bool';
    return _json_str("$v") if $r eq 'StatusMetrics::Str';
    return _py_float($$v) if $r eq 'StatusMetrics::Num';
    if (_is_num($v)) {
        my $f = B::svref_2object(\$v)->FLAGS;
        return ($f & B::SVp_IOK) ? sprintf('%d', $v) : _py_float($v);
    }
    return _json_str($v);
}

sub json_decode {                              # json_decode($text) -> data; objects are ordered hashes, numbers stay numbers
    my ($t) = @_;
    pos($t) = 0;
    my $v = _jv(\$t);
    $t =~ /\G\s*/gc;
    die "json: trailing data at offset " . pos($t) . "\n" if pos($t) < length $t;
    return $v;
}
sub _jv {
    my ($r) = @_;
    $$r =~ /\G\s*/gc;
    if ($$r =~ /\G\{/gc) {
        my $h = oh();
        $$r =~ /\G\s*/gc;
        return $h if $$r =~ /\G\}/gc;
        while (1) {
            $$r =~ /\G\s*/gc;
            $$r =~ /\G"/gc or die "json: expected a key at offset " . pos($$r) . "\n";
            my $k = _js($r);
            $$r =~ /\G\s*:/gc or die "json: expected ':' at offset " . pos($$r) . "\n";
            $h->{$k} = _jv($r);
            $$r =~ /\G\s*/gc;
            next if $$r =~ /\G,/gc;
            return $h if $$r =~ /\G\}/gc;
            die "json: expected ',' or '}' at offset " . pos($$r) . "\n";
        }
    }
    if ($$r =~ /\G\[/gc) {
        my @a;
        $$r =~ /\G\s*/gc;
        return \@a if $$r =~ /\G\]/gc;
        while (1) {
            push @a, _jv($r);
            $$r =~ /\G\s*/gc;
            next if $$r =~ /\G,/gc;
            return \@a if $$r =~ /\G\]/gc;
            die "json: expected ',' or ']' at offset " . pos($$r) . "\n";
        }
    }
    if ($$r =~ /\G"/gc) {
        my $s = _js($r);
        return $s =~ /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?$/ ? str($s) : $s;
    }
    if ($$r =~ /\G(-?(?:0|[1-9]\d*))((?:\.\d+)?(?:[eE][-+]?\d+)?)/gc) { return $2 eq '' ? 0 + $1 : StatusMetrics::Num->new("$1$2") }
    return StatusMetrics::Bool->new(1) if $$r =~ /\Gtrue/gc;
    return StatusMetrics::Bool->new(0) if $$r =~ /\Gfalse/gc;
    return undef if $$r =~ /\Gnull/gc;
    return 9**9**9 if $$r =~ /\GInfinity/gc;
    return -9**9**9 if $$r =~ /\G-Infinity/gc;
    die "json: unexpected input at offset " . pos($$r) . "\n";
}
sub _js {
    my ($r) = @_;
    my $s = '';
    while (1) {
        if ($$r =~ /\G([^"\\]+)/gc) { $s .= $1; next }
        return $s if $$r =~ /\G"/gc;
        if ($$r =~ /\G\\u([0-9a-fA-F]{4})/gc) {
            my $c = hex $1;
            if ($c >= 0xd800 && $c < 0xdc00 && $$r =~ /\G\\u(d[c-f][0-9a-f]{2})/gci) { $c = 0x10000 + (($c - 0xd800) << 10) + (hex($1) - 0xdc00) }
            $s .= chr $c; next;
        }
        if ($$r =~ /\G\\(.)/gcs) { $s .= { n => "\n", r => "\r", t => "\t", b => "\x08", f => "\f" }->{$1} // $1; next }
        die "json: unterminated string\n";
    }
}

# ---------------------------------------------------------------- helpers
sub rnd { int(floor($_[0] + 0.5)) }

sub pct {                                     # round half up, but never report 100 until complete or 0 once started
    my ($n, $d) = @_;
    return 0 unless $d;
    my $r = rnd(100.0 * $n / $d);
    $r = 99 if $n < $d && $r >= 100;
    $r = 1 if $n > 0 && $r == 0;
    return $r;
}

sub _slurp { my ($p) = @_; open my $fh, '<:raw', $p or die "$p: $!\n"; local $/; my $t = <$fh>; close $fh; return $t // '' }
sub _text  { my $t = _slurp(@_); utf8::decode($t); return $t }
sub _spew  { my ($p, $t, $mode) = @_; open my $fh, ($mode // '>') . ':raw', $p or die "$p: $!\n"; print {$fh} $t; close $fh or die "$p: $!\n" }
sub _lines { my @l = split /\r\n|\r|\n/, $_[0], -1; pop @l if @l && $l[-1] eq ''; return @l }    # str.splitlines()

sub _run {                                    # _run($cwd, @cmd) -> (stdout, exit code); stderr discarded, like capture_output
    my ($cwd, @cmd) = @_;
    my $pid = open(my $fh, '-|') // die "fork: $!\n";
    if (!$pid) {
        if (defined $cwd && !chdir $cwd) { print STDERR "chdir $cwd: $!\n"; POSIX::_exit(127) }
        open STDERR, '>', File::Spec->devnull;
        exec { $cmd[0] } @cmd or do { print STDERR "exec $cmd[0]: $!\n"; POSIX::_exit(127) };
    }
    binmode $fh;
    local $/;
    my $out = <$fh> // '';
    close $fh;
    return ($out, $? >> 8);
}
sub git {
    my ($repo, @args) = @_;
    my ($out, $rc) = _run(undef, 'git', '-C', $repo, @args);
    die "git @args: exit $rc\n" if $rc;
    return $out;
}

sub _normpath {
    my ($p) = @_;
    my $abs = $p =~ m{^/};
    my @out;
    for my $c (split m{/+}, $p) {
        next if $c eq '' || $c eq '.';
        if ($c eq '..' && @out && $out[-1] ne '..') { pop @out } elsif ($c eq '..' && $abs) { } else { push @out, $c }
    }
    my $r = ($abs ? '/' : '') . join('/', @out);
    return $r eq '' ? '.' : $r;
}
sub _absdir {
    my ($path) = @_;
    my $a = File::Spec->rel2abs($path);
    $a =~ s{[^/]*$}{};
    return _normpath($a);
}

sub load_cfg {
    my ($path) = @_;
    my $cfg = json_decode(_text($path));
    my $base = _absdir($path);
    for my $k (qw(repo exports)) { my $v = "$cfg->{$k}"; $cfg->{$k} = _normpath($v =~ m{^/} ? $v : "$base/$v") }
    $cfg->{_path} = _normpath(File::Spec->rel2abs($path));
    return $cfg;
}

sub _walk {                                   # files under $root (relative paths, sorted), skipping dot entries as glob('**') does
    my ($root, $rel, $acc) = @_;
    $acc //= [];
    my $dir = defined $rel ? "$root/$rel" : $root;
    opendir my $dh, $dir or return $acc;
    my @e = sort grep { !/^\./ } readdir $dh;
    closedir $dh;
    for my $e (@e) {
        my $r = defined $rel ? "$rel/$e" : $e;
        if (-d "$root/$r") { _walk($root, $r, $acc) } elsif (-f _) { push @$acc, $r }
    }
    return $acc;
}

sub hash_dir {
    my ($d) = @_;
    my $h = Digest::SHA->new(256);
    for my $r (sort @{ _walk($d) }) { $h->add($r); $h->add(_slurp("$d/$r")) }
    return $h->hexdigest;
}

sub _attrs { my ($t) = @_; my %a; while ($t =~ /(\w+)\s*=\s*"([^"]*)"/g) { $a{$1} = $2 } return \%a }

sub parse_model {                             # parse_model([[path, text], ...]) -> the model facts the metrics need
    my ($files) = @_;
    my %m = (elements => 0, reqs => {}, sat => {}, ver => {}, ifcs => {}, threats => {});
    for my $f (@$files) {
        for my $line (_lines($f->[1])) {
            $m{elements}++ if $line =~ $PAT;
            $m{reqs}{$1} = _attrs($2)->{doorsId} // '' if $line =~ $REQ;
            $m{sat}{$1} = 1 if $line =~ $SAT;
            $m{ver}{$1} = 1 if $line =~ $VER;
            $m{ifcs}{$1} = _attrs($2) if $line =~ $IFC;
            $m{threats}{$1} = _attrs($2) if $line =~ $THR;
        }
    }
    return \%m;
}

sub tree_files {
    my ($root) = @_;
    return [ map { [ "$root/model/$_", _text("$root/model/$_") ] } grep { /\.sysml$/ } @{ _walk("$root/model") } ];
}

sub run_gen {
    my ($cfg, $src, $out) = @_;
    my @cmd = map { (my $c = "$_") =~ s/\{src\}/$src/g; $c =~ s/\{out\}/$out/g; $c } @{ $cfg->{gen_cmd} };
    my ($o, $rc) = _run($src, @cmd);
    die "gen_cmd @cmd: exit $rc\n" if $rc;
    return;
}

sub _csv_rows {                               # the csv module's default dialect: commas, "quotes", "" for a quote
    my ($t) = @_;
    my (@rows, @row, $f);
    my $q = 0;
    $f = '';
    my $started = 0;
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($q) {
            if ($t =~ /\G""/gc) { $f .= '"' }
            elsif ($t =~ /\G"/gc) { $q = 0 }
            elsif ($t =~ /\G([^"]+)/gc) { $f .= $1 }
        }
        elsif ($t =~ /\G"/gc) { $q = 1; $started = 1 }
        elsif ($t =~ /\G,/gc) { push @row, $f; $f = ''; $started = 1 }
        elsif ($t =~ /\G(?:\r\n|\n|\r)/gc) { push @row, $f if $started || $f ne '' || @row; push @rows, [@row] if @row; @row = (); $f = ''; $started = 0 }
        elsif ($t =~ /\G([^",\r\n]+)/gc) { $f .= $1; $started = 1 }
    }
    push @row, $f if $started || $f ne '' || @row;
    push @rows, [@row] if @row;
    return \@rows;
}

sub read_csv {                                # csv.DictReader: [ {header => value} ]; missing fields are undef
    my ($path) = @_;
    return [] unless -e $path;
    my $rows = _csv_rows(_text($path));
    my $hdr = shift @$rows or return [];
    return [ map { my $r = $_; my %d; @d{@$hdr} = map { $r->[$_] } 0 .. $#$hdr; \%d } @$rows ];
}

sub _ts {                                     # ISO 8601 -> (epoch seconds, the date as written); naive means UTC
    my ($s) = @_;
    my ($y, $mo, $d, $h, $mi, $se, $fr, $tz) =
        $s =~ /^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?)?\s*(Z|[-+]\d\d(?::?\d\d(?::?\d\d)?)?)?$/
        or die "bad timestamp: $s\n";
    my $t = timegm($se // 0, $mi // 0, $h // 0, $d, $mo - 1, $y) + ($fr ? "0.$fr" : 0);
    if ($tz && $tz ne 'Z') {
        my ($sg, $th, $tm, $ts) = $tz =~ /^([-+])(\d\d):?(\d\d)?:?(\d\d)?$/;
        my $off = $th * 3600 + ($tm // 0) * 60 + ($ts // 0);
        $t -= $sg eq '+' ? $off : -$off;
    }
    return wantarray ? ($t, "$y-$mo-$d") : $t;
}

sub _date_epoch { my ($s) = @_; my ($y, $m, $d) = $s =~ /^(\d{4})-(\d\d)-(\d\d)$/ or die "bad date: $s\n"; timegm(0, 0, 0, $d, $m - 1, $y) }
sub _epoch_date { my @t = gmtime $_[0]; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub _today { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub _commify { my $n = "$_[0]"; 1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/; $n }
sub _median { my @s = sort { $a <=> $b } @_; my $n = @s; $n % 2 ? $s[ ($n - 1) / 2 ] : ($s[ $n / 2 - 1 ] + $s[ $n / 2 ]) / 2 }

# ---------------------------------------------------------------- init
sub cmd_init {
    my (%a) = @_;
    my $cfg = json_decode(_text($a{config}));
    my @in = _text($a{xmi}) =~ /$XMI_IN_SCOPE/g;
    $cfg->{v1_total} = 0 + @in;
    my $n = () = _text($a{reqif}) =~ /<SPEC-OBJECT /g;
    $cfg->{req_total} = 0 + $n;
    $cfg->{frozen} = _today();
    my $out = json_encode($cfg, 2);
    utf8::encode($out);
    _spew($a{config}, $out);
    print "v1_total=$cfg->{v1_total} req_total=$cfg->{req_total}\n";
    return 0;
}

# ---------------------------------------------------------------- collect
sub collect {
    my ($cfg, $as_of) = @_;
    my ($repo, $ex) = ($cfg->{repo}, $cfg->{exports});
    my $day = _date_epoch($as_of);
    my $start = _date_epoch("$cfg->{start}");
    my $sw = $cfg->{sprint_weeks} // 2;
    my $week = floor(($day - $start) / 86400 / 7) + 1;
    my $sprint = floor(($week - 1) / $sw) + 1;
    ($week, $sprint) = (int $week, int $sprint);
    my $wk0 = _epoch_date($start + ($week - 1) * 7 * 86400);
    my $sp0 = _epoch_date($start + ($sprint - 1) * $sw * 7 * 86400);
    my $end = $day + 86399;
    my $until = '--until=' . _epoch_date($day) . 'T23:59:59+00:00';
    my $since_wk = "--since=${wk0}T00:00:00+00:00";
    my $since_sp = "--since=${sp0}T00:00:00+00:00";
    my %M;

    # model facts (A B C E F G I Q R)
    my $mdl = parse_model(tree_files($repo));
    my $el = $mdl->{elements};
    $M{A} = oh(v => pct($el, $cfg->{v1_total}), elements => $el);
    my $owners = "$repo/CODEOWNERS";
    my $gated = 0;
    if (-e $owners) { for (_lines(_text($owners))) { (my $l = $_) =~ s/^\s+|\s+$//g; $l =~ s{^/+}{}; $gated++ if index($l, 'model/') == 0 } }
    $M{B} = oh(v => $gated, total => $cfg->{segments});
    my @linked = grep { $mdl->{reqs}{$_} ne '' } keys %{ $mdl->{reqs} };
    my %doors = map { $mdl->{reqs}{$_} => 1 } @linked;
    $M{C} = oh(v => scalar(keys %doors), total => $cfg->{req_total});
    my ($lint) = _run($repo, @{ $cfg->{lint_cmd} });
    my ($err, $warn) = $lint =~ /errors=(\d+)\s+warnings=(\d+)/ ? (0 + $1, 0 + $2) : (undef, undef);
    $M{E} = oh(v => $err, w => $warn, elements => $el);
    my %orphans = map { $_ => 1 } grep { !$mdl->{sat}{$_} } @linked;
    my %unver = map { $_ => 1 } grep { !$mdl->{ver}{$_} } @linked;
    $M{F} = oh(v => scalar(keys %orphans));
    $M{G} = oh(v => scalar(keys %unver));
    my $traced = grep { !$orphans{$_} && !$unver{$_} } @linked;
    $M{I} = oh(v => pct($traced, $cfg->{req_total}));
    my @cross = grep { ($_->{fromZone} // "\0") ne ($_->{toZone} // "\0") } values %{ $mdl->{ifcs} };
    $M{Q} = oh(v => scalar(grep { !(defined $_->{secReq} && $_->{secReq} ne '') } @cross), total => scalar @cross);
    my @thr = values %{ $mdl->{threats} };
    $M{R} = oh(v => scalar(grep { !(defined $_->{mitigation} && $_->{mitigation} ne '') } @thr), total => scalar @thr);

    # baselines (D S)
    my @tags;
    for my $line (_lines(git($repo, 'for-each-ref', '--format=%(refname:short)|%(taggerdate:unix)|%(contents:subject)', 'refs/tags/baseline-*'))) {
        my ($name, $t, $subj) = split /\|/, $line, 3;
        next unless defined $t && $t ne '' && $t <= $end;
        my $num = (split /-/, $name)[1];
        die "tag $name: not baseline-<number>\n" unless defined $num && $num =~ /^\s*[-+]?\d+\s*$/;
        push @tags, [ 0 + $num, $name, $subj // '' ];
    }
    @tags = sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] } @tags;
    if (@tags) {
        my $ok = 0;
        my @latest;                           # the latest baseline's model/**.sysml, for D (one archive per tag, not one show per file)
        for my $tg (@tags) {
            my (undef, $name, $subj) = @$tg;
            my $tmp = tempdir(CLEANUP => 1);
            my $data = git($repo, 'archive', $name);
            open my $th, '<', \$data or die;
            my $tar = Archive::Tar->new;
            $tar->read($th) or die "git archive $name: " . $tar->error . "\n";
            for my $f ($tar->get_files) {
                my $p = $f->full_path;
                next if $p =~ m{(?:^|/)\.\.(?:/|$)} || $p =~ m{^/};      # the "data" filter: nothing outside the tree
                if ($f->is_dir) { make_path("$tmp/$p"); next }
                next unless $f->is_file;
                (my $d = "$tmp/$p") =~ s{/[^/]*$}{};
                make_path($d);
                _spew("$tmp/$p", $f->get_content);
                if ($tg == $tags[-1] && $p =~ m{^model/.*\.sysml$}) { my $t = $f->get_content; utf8::decode($t); push @latest, [ $p, $t ] }
            }
            my $out = "$tmp/_rebuild";
            run_gen($cfg, $tmp, $out);
            $ok++ if $subj eq 'sha256=' . hash_dir("$out/docs");
            remove_tree($tmp);
        }
        $M{D} = oh(v => parse_model(\@latest)->{elements}, tag => str("$tags[-1][0]"));
        $M{S} = oh(v => $ok, total => scalar @tags);
    }
    else {
        $M{D} = oh(v => undef, tag => undef);
        $M{S} = oh(v => undef, total => 0);
    }

    # gate log (H)
    my $caught = 0;
    my $gl = "$ex/gate.log";
    if (-e $gl) { for (_lines(_text($gl))) { my @p = split ' '; $caught++ if @p > 1 && $p[1] eq 'E-IF' && _ts($p[0]) <= $end } }
    my $reached = grep { ($_->{phase} // '') eq 'integration' && ($_->{type} // '') eq 'interface' } @{ read_csv("$ex/defects.csv") };
    $M{H} = oh(v => $caught, reached => 0 + $reached);

    # documents (J K L M O T)
    my $gdocs = "$repo/generated/docs";
    my $ndocs = 0;
    if (opendir my $dh, $gdocs) { $ndocs = grep { !/^\./ && -f "$gdocs/$_" } readdir $dh; closedir $dh }
    $M{L} = oh(v => $ndocs, total => $cfg->{docs_total});
    $M{J} = oh(v => $ndocs ? rnd($ndocs * $cfg->{hours_per_doc}) : undef);
    my @jobs = grep { _ts($_->{ts}) <= $end } @{ read_csv("$ex/ci_jobs.csv") };
    my @docs_jobs = grep { $_->{job} eq 'docs' && $_->{result} eq 'pass' } @jobs;
    $M{K} = oh(v => @docs_jobs ? rnd($docs_jobs[-1]{minutes}) : undef, old => $cfg->{old_regen_days});
    if ($ndocs) {
        my $subj = git($repo, 'log', '--no-merges', $since_wk, $until, '--format=%s', '--', 'released');
        $M{M} = oh(v => scalar(grep { index($_, 'generated') < 0 } _lines($subj)));
    }
    else { $M{M} = oh(v => undef) }
    my $ph = "$repo/generated/params/params.h";
    if (-e $ph) { $M{O} = oh(v => scalar(grep { /^#define/ } _lines(_text($ph))), total => $cfg->{params_total}) }
    else { $M{O} = oh(v => undef, total => $cfg->{params_total}) }
    my $icd = "$gdocs/icd.csv";
    if (-e $icd) {
        my $tmp = tempdir(CLEANUP => 1);
        run_gen($cfg, $repo, $tmp);
        my @a1 = _lines(_text($icd));
        my @a2 = _lines(_text("$tmp/docs/icd.csv"));
        my $n = @a1 < @a2 ? @a1 : @a2;
        my $drift = (grep { $a1[$_] ne $a2[$_] } 0 .. $n - 1) + abs(@a1 - @a2);
        remove_tree($tmp);
        my %gen = map { ($_->{id} // '') => $_ } @{ read_csv($icd) };
        my %legacy = map { ($_->{id} // '') => $_ } @{ read_csv("$ex/legacy_icd.csv") };
        my $open = 0;
        for my $k (grep { exists $legacy{$_} } keys %gen) {
            for my $f (@ICD_FIELDS) { $open++ if ($gen{$k}{$f} // "\0") ne ($legacy{$k}{$f} // "\0") }
        }
        $M{T} = oh(v => 0 + $drift, legacy => $open);
    }
    else { $M{T} = oh(v => undef, legacy => undef) }

    # git history (N U V Z)
    # lead time: for each of the last 10 merges, the merge time minus the oldest commit in h^1..h^2. One `git log` of the
    # merges' ancestry and the range walked here, rather than one `git log h^1..h^2` per merge (process starts are slow on Windows).
    my @leads;
    my @merges = map { [ split ' ' ] } grep { $_ ne '' } split /\n/, git($repo, 'log', '--first-parent', '--merges', '-n', '10', $until, '--format=%H %ct');
    if (@merges) {
        my (%par, %ct);
        for (split /\n/, git($repo, 'log', '--format=%H %ct %P', map { $_->[0] } @merges)) {
            my ($h, $t, @p) = split ' ';
            next unless defined $t;
            ($par{$h}, $ct{$h}) = (\@p, $t);
        }
        my $reach = sub {                     # commits reachable from $from, not walking into %$stop
            my ($from, $stop) = @_;
            my (%seen, @todo);
            @todo = ($from);
            while (defined(my $c = pop @todo)) { next if $seen{$c} || $stop->{$c}; $seen{$c} = 1; push @todo, @{ $par{$c} || [] } }
            return \%seen;
        };
        for my $m (@merges) {
            my ($h, $mct) = @$m;
            my ($p1, $p2) = @{ $par{$h} || [] };
            die "git log $h^1..$h^2: not a two-parent merge\n" unless defined $p2;
            my $only = $reach->($p2, $reach->($p1, {}));
            my @cts = map { $ct{$_} } keys %$only;
            if (@cts) { my $min = (sort { $a <=> $b } @cts)[0]; push @leads, ($mct - $min) / 86400 }
        }
    }
    $M{N} = oh(v => @leads ? rnd(_median(@leads)) : undef, old => $cfg->{old_lead_days});
    my @subs = _lines(git($repo, 'log', '--first-parent', '--merges', $since_sp, $until, '--format=%s'));
    $M{U} = oh(v => scalar @subs);
    my $bad = grep { /^(?:Revert|Merge fix-forward)/ } @subs;
    $M{V} = oh(v => @subs ? pct($bad, scalar @subs) : undef);
    my %ex_auth = map { ("$_" => 1) } @{ $cfg->{exclude_authors} // [] };
    my %authors = map { $_ => 1 } _lines(git($repo, 'log', '--no-merges', $until, '--format=%an', '--', 'model'));
    $M{Z} = oh(v => scalar(grep { !$ex_auth{$_} } keys %authors), total => $cfg->{team});

    # sim runs (P)
    my ($runs, $pinned) = (0, 0);
    my $rd = "$ex/runs";
    if (opendir my $dh, $rd) {
        for my $r (sort grep { !/^\./ } readdir $dh) {
            my $pv = "$rd/$r/provenance.txt";
            next unless -f $pv;
            my %kv;
            for (_lines(_text($pv))) { next unless /=/; (my $l = $_) =~ s/^\s+|\s+$//g; my ($k, $v) = split /=/, $l, 2; $kv{$k} = $v }
            die "$pv: no date\n" unless defined $kv{date};
            if (_date_epoch($kv{date}) <= $day) { $runs++; $pinned++ if defined $kv{model_baseline} && $kv{model_baseline} ne '' }
        }
        closedir $dh;
    }
    $M{P} = oh(v => $runs ? $pinned : undef, total => $runs);

    # CI restore (W): worst time from a failure on main to the next pass, this week
    my $worst;
    for my $i (0 .. $#jobs) {
        my $r = $jobs[$i];
        next unless $r->{result} eq 'fail' && $r->{branch} eq 'main';
        my ($t0, $d0) = _ts($r->{ts});
        next unless $d0 ge $wk0;
        my ($nxt) = grep { $_->{job} eq $r->{job} && $_->{result} eq 'pass' } @jobs[ $i + 1 .. $#jobs ];
        next unless $nxt;
        my $hrs = (_ts($nxt->{ts}) - $t0) / 3600;
        $worst = $hrs if !defined $worst || $hrs > $worst;
    }
    $M{W} = oh(v => defined $worst ? rnd($worst) : undef);

    # tracker (X Y)
    my $rows = read_csv("$ex/tracker/sprint-$sprint.csv");
    my $done = grep { $_->{status} eq 'done' } @$rows;
    $M{X} = oh(v => @$rows ? pct($done, scalar @$rows) : undef);
    my @blocked = grep { int($_->{blocked_days} || 0) } @$rows;
    my (%by, @order);
    for my $r (@blocked) { push @order, $r->{blocker} unless exists $by{ $r->{blocker} }; $by{ $r->{blocker} } += int $r->{blocked_days} }
    my $top;
    for my $b (@order) { $top = $b if !defined $top || $by{$b} > $by{$top} }
    my $sumb = 0; $sumb += int $_->{blocked_days} for @blocked;
    $M{Y} = oh(v => @$rows ? $sumb : undef, blocker => $top // 'none');

    my $m = oh(map { $_ => $M{$_} } sort keys %M);
    return oh(date => $as_of, week => $week, sprint => $sprint, m => $m);
}

sub cmd_collect {
    my (%a) = @_;
    my $cfg = load_cfg($a{config});
    my $line = json_encode(collect($cfg, $a{'as-of'} // _today()));
    utf8::encode($line);
    if ($a{history}) { _spew($a{history}, "$line\n", '>>') } else { binmode STDOUT; print "$line\n" }
    return 0;
}

# ---------------------------------------------------------------- report
sub _pystr {                                  # str(x) for what the history holds
    my ($v) = @_;
    return 'None' unless defined $v;
    return json_encode($v) if ref $v eq 'StatusMetrics::Num';
    return "$v" if ref $v;
    return _is_num($v) ? json_encode($v) : $v;
}

sub cell {
    my ($L, $d, $week, $sw) = @_;
    my $v = $d->{v};
    return $DASH if $SPRINT_METRICS{$L} && $week % $sw;
    $v = $d->{legacy} if $L eq 'T';
    return $DASH unless defined $v;
    return _pystr($v) . '/' . _pystr($d->{w}) if $L eq 'E';
    return _pystr($v) . ' of ' . _pystr($d->{total}) if $L =~ /^[PQRS]$/;
    return _commify(_pystr($v)) if $L =~ /^[CD]$/;
    return _pystr($v);
}

sub load_history { my ($p) = @_; return [ map { json_decode($_) } grep { /\S/ } _lines(_text($p)) ] }

sub weekly {
    my ($hist) = @_;
    my %w;
    $w{ $_->{week} } = $_ for @$hist;
    return [ map { $w{$_} } sort { $a <=> $b } keys %w ];
}

sub _name {
    my ($L, $cfg) = @_;
    (my $n = $NAMES{$L}) =~ s/\{(\w+)(:,)?\}/my $v = _pystr($cfg->{$1}); $2 ? _commify($v) : $v/ge;
    return $n;
}

sub _csv_line { join(',', map { my $f = $_; $f =~ /[",\r\n]/ ? do { $f =~ s/"/""/g; qq("$f") } : $f } @_) . "\r\n" }

sub cmd_report {
    my (%a) = @_;
    my $cfg = load_cfg($a{config});
    my $sw = $cfg->{sprint_weeks} // 2;
    my $hist = load_history($a{history});
    my $weeks = weekly($hist);
    my $out = $a{out} // '.';
    make_path($out);

    my @t = ('| | Metric | ' . join(' | ', map { "W$_->{week}" } @$weeks) . ' |', '|---|---|' . ('---|' x @$weeks));
    for my $L (@LETTERS) {
        push @t, "| $L | " . _name($L, $cfg) . ' | ' . join(' | ', map { cell($L, $_->{m}{$L}, $_->{week}, $sw) } @$weeks) . ' |';
    }
    _spew("$out/status-weekly.md", join("\n", @t) . "\n");

    my $csv = _csv_line('date', 'week', 'sprint', 'elements', @LETTERS);
    for my $e (@$hist) {
        $csv .= _csv_line($e->{date}, _pystr($e->{week}), _pystr($e->{sprint}), _pystr($e->{m}{A}{elements}), map { cell($_, $e->{m}{$_}, $sw, $sw) } @LETTERS);
    }
    _spew("$out/status-daily.csv", $csv);

    my $lastw = $weeks->[-1];
    my $prevw = @$weeks > 1 ? $weeks->[-2] : undef;
    my $tag = $lastw->{m}{D}{tag};
    my $dash = oh(sprint => 'Sprint ' . _pystr($lastw->{sprint}), date => $hist->[-1]{date},
        baseline => (defined $tag && "$tag" ne '') ? "baseline-$tag" : 'none', sel => [qw(A C H)], m => oh());
    for my $L (@LETTERS) {
        my $src = $hist->[-1]{m}{$L};
        my $d = oh(map { ($_ => $src->{$_}) } grep { defined $src->{$_} } keys %$src);
        $d->{prev} = $prevw->{m}{$L}{v} if $prevw && defined $prevw->{m}{$L}{v};
        my $key = $L eq 'T' ? 'legacy' : 'v';
        $d->{hist} = [ grep { _numeric($_) } map { $_->{m}{$L}{$key} } @$weeks ];
        delete $d->{legacy} if $L eq 'T' && !defined $d->{legacy};
        $dash->{m}{$L} = $d;
    }
    my $j = json_encode($dash, 2);
    utf8::encode($j);
    _spew("$out/dashboard.json", $j);
    printf "wrote status-weekly.md (%d weeks), status-daily.csv (%d days), dashboard.json\n", scalar @$weeks, scalar @$hist;
    return 0;
}

# ---------------------------------------------------------------- CLI
our $USAGE = <<'EOT';
usage: status-metrics.pl {init,collect,report} ...

collect the 26 status metrics (A-Z) and build the status tables.

  status-metrics.pl init    --config metrics.json --xmi legacy.xmi --reqif export.reqif
  status-metrics.pl collect --config metrics.json --as-of YYYY-MM-DD [--history history.jsonl]
  status-metrics.pl report  --config metrics.json --history history.jsonl --out DIR

init     freezes the denominators (v1 element total, DOORS requirement total).
collect  takes one snapshot as of the end of a day and appends it to the history (JSON lines).
report   writes status-weekly.md (A-Z by week), status-daily.csv and dashboard.json.

Paths in the config are relative to the config file. Collection methods follow Appendix A
of docs/STATUS-METRICS.html.
EOT

my %SPEC = (
    init    => { opts => [qw(config xmi reqif)], req => [qw(config xmi reqif)], fn => \&cmd_init },
    collect => { opts => [qw(config as-of history)], req => [qw(config)], fn => \&cmd_collect },
    report  => { opts => [qw(config history out)], req => [qw(config history)], fn => \&cmd_report },
);

sub run {                                     # run(@ARGV) -> exit code; argparse's behaviour: usage on stderr, exit 2
    my @argv = @_;
    my $usage = sub { print STDERR "usage: status-metrics.pl {init,collect,report} ...\nstatus-metrics.pl: error: $_[0]\n"; return 2 };
    if (!@argv || $argv[0] =~ /^(?:-h|--help)$/) { if (@argv) { print $USAGE; return 0 } return $usage->('the following arguments are required: cmd') }
    my $cmd = shift @argv;
    my $spec = $SPEC{$cmd} or return $usage->("argument cmd: invalid choice: '$cmd' (choose from 'init', 'collect', 'report')");
    my %ok = map { $_ => 1 } @{ $spec->{opts} };
    my %a;
    while (@argv) {
        my $o = shift @argv;
        if ($o =~ /^(?:-h|--help)$/) { print "usage: status-metrics.pl $cmd " . join(' ', map { "--$_ \U$_" } @{ $spec->{opts} }) . "\n"; return 0 }
        my ($k, $v) = $o =~ /^--([\w-]+)(?:=(.*))?$/ or return $usage->("unrecognized arguments: $o");
        my @m = grep { index($_, $k) == 0 } sort keys %ok;            # argparse accepts unique prefixes
        @m = ($k) if $ok{$k};
        return $usage->("unrecognized arguments: $o") unless @m == 1;
        $v //= shift @argv;
        return $usage->("argument --$m[0]: expected one argument") unless defined $v;
        $a{ $m[0] } = $v;
    }
    my @miss = grep { !defined $a{$_} } @{ $spec->{req} };
    return $usage->('the following arguments are required: ' . join(', ', map { "--$_" } @miss)) if @miss;
    return $spec->{fn}->(%a);
}

1;
