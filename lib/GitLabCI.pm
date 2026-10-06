package GitLabCI;
# .gitlab-ci.yml, offline: a YAML-subset reader, GitLab's job selection (workflow:rules, rules, only/except, extends,
# default, hidden jobs, stages) and a local runner that executes the selected jobs in a shell, stage by stage.
#
#   my $ci   = GitLabCI::load($path_or_text, file => 'name for messages');   # dies "FILE:LINE: message"
#   my $data = GitLabCI::parse_yaml($text);                                   # YAML subset -> Perl data
#   my $ok   = GitLabCI::eval_if($expr, \%vars);                              # a `rules:if` expression
#   my $plan = GitLabCI::plan($ci, vars => \%vars, changed => \@paths);       # which jobs a pipeline would get
#   my $res  = GitLabCI::run($ci, dir => $worktree, vars => \%vars, changed => \@paths, log_dir => $dir,
#                            manual => 0, cache => \%cache, tree => $tree_sha, clock => sub { epoch }, shell => 'sh');
#   exit GitLabCI::cli(@ARGV);                                                # `gitlab.pl ci ...`
#
# YAML subset: block maps and lists, plain / 'single' / "double" scalars, | and > block scalars (with -/+ and an
# indentation digit), flow [a, "b"] and {a: 1} (nested, may span lines), comments, anchors &x, aliases *x, the merge
# key <<: *x, and GitLab's !reference [job, key]. Scalars stay strings (true is "true"); null, ~ and empty are undef.
#
# Includes: local files (a path, a list, or maps with local:, leading / = repository root, globs such as
# .gitlab/ci/*.yml) are read and merged as GitLab does -- included files first, nested includes depth-first, the
# including file's keys deep-merged over them; include:rules (if, exists, changes; when always|never) are evaluated with
# the pipeline's variables, so plan() rebuilds a configuration that has them. At most 100 files; cycles are errors.
# Every job remembers its file(s) ({file}). Paths are relative to load(..., root => DIR), by default the directory of
# the loaded file. template:, project:, remote: and component: includes and trigger: jobs are listed as skipped
# ("runs on GitLab only"); image:, services:, tags:, cache:, retry:, timeout: and interruptible: are ignored. A job runs `sh -e` on before_script + script in the job's directory, after_script in a second shell.
#
# Variable precedence (low to high): global variables:, job variables:, the matching rule's variables:, the
# caller's vars (project / predefined / --var). $VAR references inside YAML variable values are expanded once.
use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use File::Find ();
use File::Basename qw(dirname);
use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(refaddr blessed);
use Time::HiRes ();
use Getopt::Long qw(GetOptionsFromArray);
use Cwd qw(getcwd abs_path);
use IO::Handle;

# ================================================================ YAML subset
my %ORDER;                                     # refaddr(map) -> [keys in file order], for the last parse
our $LAST_ROOT_ORDER;

sub parse_yaml {
    my ($text, $file) = @_;
    $file //= 'yaml';
    $text //= '';
    $text =~ s/^\xEF\xBB\xBF//;
    $text =~ s/\r\n?/\n/g;
    my @raw = split /\n/, $text, -1;
    my @L;
    for my $i (0 .. $#raw) {
        my ($ind) = $raw[$i] =~ /^( *)/;
        push @L, { n => $i + 1, indent => length $ind, raw => $raw[$i], text => substr($raw[$i], length $ind) };
    }
    %ORDER = ();
    my $p = { L => \@L, i => 0, file => $file, anchors => {} };
    _skip_blank($p);
    if ($p->{i} < @L && $L[ $p->{i} ]{indent} == 0 && $L[ $p->{i} ]{text} =~ /^---\s*(?:#.*)?$/) { $p->{i}++; _skip_blank($p) }
    return undef if $p->{i} >= @L;
    my $v = _node($p, $L[ $p->{i} ]{indent});
    _skip_blank($p);
    if ($p->{i} < @L) {
        my $l = $L[ $p->{i} ];
        _err($p, $l, 'unexpected content (bad indentation?)') unless $l->{text} =~ /^(?:\.\.\.|---)\s*$/;
    }
    $LAST_ROOT_ORDER = ref $v eq 'HASH' ? $ORDER{ refaddr $v } : undef;
    return $v;
}

sub _err { my ($p, $l, $msg) = @_; die "$p->{file}:" . ($l ? $l->{n} : scalar @{ $p->{L} }) . ": $msg\n" }

sub _skip_blank {
    my ($p) = @_;
    my $L = $p->{L};
    while ($p->{i} < @$L) {
        my $l = $L->[ $p->{i} ];
        if ($l->{text} =~ /^\t/ && $l->{text} =~ /\S/ && $l->{text} !~ /^\s*#/) { _err($p, $l, 'tabs are not allowed in indentation') }
        last if _strip($l->{text}) ne '';
        $p->{i}++;
    }
}

sub _strip {                                   # drop a trailing comment (a # at the start or after whitespace, outside quotes)
    my ($s) = @_;
    my $q = '';
    for (my $k = 0; $k < length $s; $k++) {
        my $c = substr($s, $k, 1);
        if ($q) {
            if ($q eq '"' && $c eq '\\') { $k++; next }
            if ($c eq $q) {
                if ($q eq "'" && substr($s, $k + 1, 1) eq "'") { $k++; next }
                $q = '';
            }
            next;
        }
        if (($c eq '"' || $c eq "'") && substr($s, 0, $k) =~ /(?:^|[\[\{,]|[:\-?]\s)\s*$/) { $q = $c; next }
        if ($c eq '#' && ($k == 0 || substr($s, $k - 1, 1) =~ /\s/)) { $s = substr($s, 0, $k); last }
    }
    $s =~ s/\s+$//;
    return $s;
}

my $KEY_RE = qr/^(?:"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s\-\[\]{},#&*!|>'"%@`?](?:[^:]|:(?!\s|$))*?|-[^\s:](?:[^:]|:(?!\s|$))*?)\s*:(?=\s|$)/;
sub _is_key { $_[0] =~ $KEY_RE }
sub _split_key {
    my ($t) = @_;
    $t =~ /^("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|.*?)\s*:(?=\s|$)\s*(.*)$/ or return;
    my ($k, $rest) = ($1, $2);
    if    ($k =~ /^"(.*)"$/s) { $k = _unescape($1) }
    elsif ($k =~ /^'(.*)'$/s) { ($k = $1) =~ s/''/'/g }
    return ($k, $rest);
}

sub _node {                                    # the node whose first line is the current one, at indent $ind
    my ($p, $ind) = @_;
    my $l = $p->{L}[ $p->{i} ];
    my $t = _strip($l->{text});
    return _list($p, $ind) if $t =~ /^-(?:\s|$)/;
    return _map($p, $ind) if _is_key($t);
    $p->{i}++;
    return _value($p, $t, $l, $ind - 1);
}

sub _map {
    my ($p, $ind) = @_;
    my $L = $p->{L};
    my (%h, @order, @merges);
    while (1) {
        _skip_blank($p);
        last if $p->{i} >= @$L;
        my $l = $L->[ $p->{i} ];
        last if $l->{indent} < $ind;
        _err($p, $l, 'bad indentation') if $l->{indent} > $ind;
        my $t = _strip($l->{text});
        last if $ind == 0 && $t =~ /^(?:---|\.\.\.)$/;
        _err($p, $l, "expected 'key: value', found '$t'") unless _is_key($t);
        my ($k, $rest) = _split_key($t);
        $p->{i}++;
        my $v = _after_key($p, $rest, $l, $ind);
        if ($k eq '<<') {
            for my $m (ref $v eq 'ARRAY' ? @$v : ($v)) { _err($p, $l, 'the merge key << needs a map (or a list of maps)') unless ref $m eq 'HASH'; push @merges, $m }
            next;
        }
        _err($p, $l, "duplicate key '$k'") if exists $h{$k};
        $h{$k} = $v;
        push @order, $k;
    }
    for my $m (@merges) {
        for my $k (sort keys %$m) { next if exists $h{$k}; $h{$k} = $m->{$k}; push @order, $k }
    }
    $ORDER{ refaddr \%h } = \@order;
    return \%h;
}

sub _list {
    my ($p, $ind) = @_;
    my $L = $p->{L};
    my @a;
    while (1) {
        _skip_blank($p);
        last if $p->{i} >= @$L;
        my $l = $L->[ $p->{i} ];
        last if $l->{indent} < $ind;
        _err($p, $l, 'bad indentation') if $l->{indent} > $ind;
        last unless $l->{text} =~ /^-(\s+|$)/;
        my $gap = length $1;
        if (_strip(substr($l->{text}, 1)) eq '') {     # "-" alone: the item is the block below (or null)
            $p->{i}++;
            _skip_blank($p);
            if ($p->{i} < @$L && $L->[ $p->{i} ]{indent} > $ind) { push @a, _node($p, $L->[ $p->{i} ]{indent}) }
            else { push @a, undef }
            next;
        }
        $l->{indent} += 1 + $gap;                       # "- x: 1" is a map at the column of x
        $l->{text} = substr($l->{text}, 1 + $gap);
        push @a, _node($p, $l->{indent});
    }
    return \@a;
}

sub _after_key {                               # the value after "key:" ($rest on the same line, or the block below)
    my ($p, $rest, $l, $ind) = @_;
    return _value($p, $rest, $l, $ind) if $rest ne '';
    my $L = $p->{L};
    _skip_blank($p);
    return undef if $p->{i} >= @$L;
    my $n = $L->[ $p->{i} ];
    return _node($p, $n->{indent}) if $n->{indent} > $ind;
    return _list($p, $ind) if $n->{indent} == $ind && $n->{text} =~ /^-(?:\s|$)/;   # key:\n- a  (a list at the key's indent)
    return undef;
}

sub _value {                                   # an inline value $s (comment already stripped); $ind = the parent's indent
    my ($p, $s, $l, $ind) = @_;
    if ($s =~ /^&([^\s\[\]{},]+)\s*(.*)$/) {
        my ($name, $rest) = ($1, $2);
        my $v = $rest eq '' ? _after_key($p, '', $l, $ind) : _value($p, $rest, $l, $ind);
        $p->{anchors}{$name} = $v;
        return $v;
    }
    if ($s =~ /^\*([^\s\[\]{},]+)$/) {
        exists $p->{anchors}{$1} or _err($p, $l, "unknown alias *$1");
        return _clone($p->{anchors}{$1});
    }
    if ($s =~ /^!reference\s*(.*)$/) {
        my $ref = _flow_value($p, $1, $l);
        _err($p, $l, '!reference needs a list: !reference [job, key]') unless ref $ref eq 'ARRAY' && @$ref;
        return bless { path => $ref, line => $l->{n}, file => $p->{file} }, 'GitLabCI::Ref';
    }
    $s =~ s/^!!?\w+\s+// if $s =~ /^!/;        # other tags (!!str ...): ignored
    if ($s =~ /^([|>])([+-]?)([1-9]?)([+-]?)$/) { return _block($p, $ind, $1, $2 || $4, $3) }
    return _flow_value($p, $s, $l) if $s =~ /^[\[\{]/;
    if ($s =~ /^"/) {
        $s =~ /^"((?:[^"\\]|\\.)*)"(.*)$/ or _err($p, $l, 'unterminated "string"');
        _err($p, $l, "unexpected text after a quoted string: '$2'") if $2 ne '';
        return _unescape($1);
    }
    if ($s =~ /^'/) {
        $s =~ /^'((?:[^']|'')*)'(.*)$/ or _err($p, $l, "unterminated 'string'");
        _err($p, $l, "unexpected text after a quoted string: '$2'") if $2 ne '';
        (my $v = $1) =~ s/''/'/g;
        return $v;
    }
    my $L = $p->{L};                           # a plain scalar, maybe continued on more-indented lines
    while ($p->{i} < @$L) {
        my $n = $L->[ $p->{i} ];
        my $t = _strip($n->{text});
        if ($t eq '') {
            my $j = $p->{i}; $j++ while $j < @$L && _strip($L->[$j]{text}) eq '';
            last unless $j < @$L && $L->[$j]{indent} > $ind && !_is_key(_strip($L->[$j]{text}));
            $p->{i} = $j; next;
        }
        last unless $n->{indent} > $ind;
        last if _is_key($t) || $t =~ /^-(?:\s|$)/;
        $s .= " $t";
        $p->{i}++;
    }
    return _plain($s);
}

sub _plain { my ($s) = @_; $s =~ s/^\s+|\s+$//g; return undef if $s eq '' || $s eq '~' || $s eq 'null' || $s eq 'Null' || $s eq 'NULL'; $s }

sub _unescape {
    my ($s) = @_;
    my %E = (n => "\n", t => "\t", r => "\r", '0' => "\0", e => "\e", a => "\a", b => "\b", '"' => '"', '\\' => '\\', '/' => '/', ' ' => ' ');
    $s =~ s{\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|.)}{
        my $e = $1;
        $e =~ /^x(..)$/ ? chr(hex $1)
      : $e =~ /^u(....)$/ ? do { my $c = chr(hex $1); utf8::encode($c); $c }
      : exists $E{$e} ? $E{$e} : "\\$e"
    }ge;
    return $s;
}

sub _block {
    my ($p, $ind, $style, $chomp, $digit) = @_;
    my $L = $p->{L};
    my (@lines, $cind);
    $cind = $ind + $digit if $digit;
    while ($p->{i} < @$L) {
        my $raw = $L->[ $p->{i} ]{raw};
        if ($raw =~ /^\s*$/) { push @lines, ''; $p->{i}++; next }
        my ($sp) = $raw =~ /^( *)/;
        my $n = length $sp;
        last if $n <= $ind;
        $cind //= $n;
        last if $n < $cind;
        push @lines, substr($raw, $cind);
        $p->{i}++;
    }
    my $trail = 0;
    while (@lines && $lines[-1] eq '') { pop @lines; $trail++ }
    my $body;
    if ($style eq '|') { $body = join "\n", @lines }
    else {
        $body = '';
        my $prev = 0;                          # 0 nothing / blank, 1 a text line, 2 a more-indented line
        for my $x (@lines) {
            if ($x eq '') { $body .= "\n"; $prev = 0; next }
            if ($x =~ /^\s/) { $body .= "\n" if $prev; $body .= $x; $prev = 2; next }
            $body .= $prev == 1 ? ' ' : $prev == 2 ? "\n" : '';
            $body .= $x;
            $prev = 1;
        }
    }
    return '' if !@lines && $chomp ne '+';
    return $body if $chomp eq '-';
    return $body . "\n" x (1 + $trail) if $chomp eq '+';
    return @lines ? "$body\n" : '';
}

sub _flow_value {                              # [..] / {..} possibly spanning lines; also used for !reference
    my ($p, $s, $l) = @_;
    my $L = $p->{L};
    while (_flow_depth($s) > 0) {
        _err($p, $l, 'unterminated flow collection ([ or { never closed)') if $p->{i} >= @$L;
        my $t = _strip($L->[ $p->{i} ]{text});
        $p->{i}++;
        $s .= " $t";
    }
    my $pos = 0;
    my $v = _fnode($p, $l, \$s, \$pos, '');
    my $rest = substr($s, $pos);
    $rest =~ s/^\s+//;
    _err($p, $l, "unexpected text after a flow collection: '$rest'") if $rest ne '';
    return $v;
}
sub _flow_depth {
    my ($s) = @_;
    my ($d, $q) = (0, '');
    for (my $k = 0; $k < length $s; $k++) {
        my $c = substr($s, $k, 1);
        if ($q) { if ($q eq '"' && $c eq '\\') { $k++; next } $q = '' if $c eq $q; next }
        if ($c eq '"' || $c eq "'") { $q = $c; next }
        $d++ if $c eq '[' || $c eq '{';
        $d-- if $c eq ']' || $c eq '}';
    }
    return $d;
}
sub _fnode {                                   # one flow node at $$pos; $stop = extra terminator chars for plain scalars
    my ($p, $l, $s, $pos, $stop) = @_;
    my $ws = sub { substr($$s, $$pos) =~ /^(\s*)/; $$pos += length $1 };
    $ws->();
    my $c = substr($$s, $$pos, 1);
    if ($c eq '[') {
        $$pos++;
        my @a;
        while (1) {
            $ws->();
            _err($p, $l, 'unterminated [ list') if $$pos >= length $$s;
            if (substr($$s, $$pos, 1) eq ']') { $$pos++; last }
            push @a, _fnode($p, $l, $s, $pos, '');
            $ws->();
            my $d = substr($$s, $$pos, 1);
            if    ($d eq ',') { $$pos++ }
            elsif ($d eq ']') { $$pos++; last }
            else { _err($p, $l, "expected ',' or ']' in a flow list, found '" . substr($$s, $$pos, 10) . "'") }
        }
        return \@a;
    }
    if ($c eq '{') {
        $$pos++;
        my (%h, @order);
        while (1) {
            $ws->();
            _err($p, $l, 'unterminated { map') if $$pos >= length $$s;
            if (substr($$s, $$pos, 1) eq '}') { $$pos++; last }
            my $k = _fnode($p, $l, $s, $pos, ':');
            $ws->();
            my $v;
            if (substr($$s, $$pos, 1) eq ':') { $$pos++; $ws->(); my $d = substr($$s, $$pos, 1); $v = ($d eq ',' || $d eq '}') ? undef : _fnode($p, $l, $s, $pos, '') }
            $k //= '';
            if ($k eq '<<' && ref $v eq 'HASH') { for (sort keys %$v) { next if exists $h{$_}; $h{$_} = $v->{$_}; push @order, $_ } }
            else { push @order, $k unless exists $h{$k}; $h{$k} = $v }
            $ws->();
            my $d = substr($$s, $$pos, 1);
            if    ($d eq ',') { $$pos++ }
            elsif ($d eq '}') { $$pos++; last }
            else { _err($p, $l, "expected ',' or '}' in a flow map, found '" . substr($$s, $$pos, 10) . "'") }
        }
        $ORDER{ refaddr \%h } = \@order;
        return \%h;
    }
    if ($c eq '"') {
        substr($$s, $$pos) =~ /^"((?:[^"\\]|\\.)*)"/ or _err($p, $l, 'unterminated "string"');
        $$pos += length($1) + 2;
        return _unescape($1);
    }
    if ($c eq "'") {
        substr($$s, $$pos) =~ /^'((?:[^']|'')*)'/ or _err($p, $l, "unterminated 'string'");
        $$pos += length($1) + 2;
        (my $v = $1) =~ s/''/'/g;
        return $v;
    }
    if ($c eq '*') {
        substr($$s, $$pos) =~ /^\*([^\s\[\]{},]+)/;
        $$pos += 1 + length $1;
        exists $p->{anchors}{$1} or _err($p, $l, "unknown alias *$1");
        return _clone($p->{anchors}{$1});
    }
    my $re = $stop eq ':' ? qr/^((?:[^,\[\]{}:]|:(?!\s|[,\]}]|$))*)/ : qr/^((?:[^,\[\]{}:]|:(?!\s|[,\]}]|$))*)/;
    substr($$s, $$pos) =~ $re;
    my $t = $1 // '';
    $$pos += length $t;
    return _plain($t);
}

sub _clone {
    my ($v) = @_;
    return { map { $_ => _clone($v->{$_}) } keys %$v } if ref $v eq 'HASH';
    return [ map { _clone($_) } @$v ] if ref $v eq 'ARRAY';
    return $v;
}

# ================================================================ rules:if expressions
sub eval_if {
    my ($expr, $vars) = @_;
    $vars //= {};
    my $s = defined $expr ? "$expr" : '';
    my $pos = 0;
    my $fail = sub { my $at = substr($s, $pos); die "rules:if: cannot read '$s' at '" . ($at eq '' ? 'the end' : $at) . "'\n" };
    my $ws = sub { substr($s, $pos) =~ /^(\s*)/; $pos += length $1 };
    my $peek = sub { $ws->(); my ($re) = @_; substr($s, $pos) =~ /^(?:$re)/ };
    my $take = sub { $ws->(); my ($re) = @_; if (substr($s, $pos) =~ /^($re)/) { $pos += length $1; return $1 } return undef };
    my ($or, $and, $unary, $primary, $operand, $regex);
    $operand = sub {                          # -> [kind, value]: kind var|str|null|re
        if (defined(my $t = $take->(qr/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/))) {
            (my $n = $t) =~ s/^\$\{?|\}$//g;
            return [ 'var', $vars->{$n} ];
        }
        if (defined(my $t = $take->(qr/"(?:[^"\\]|\\.)*"/))) { return [ 'str', _unescape(substr($t, 1, -1)) ] }
        if (defined(my $t = $take->(qr/'(?:[^'\\]|\\.)*'/))) { (my $v = substr($t, 1, -1)) =~ s/\\'/'/g; return [ 'str', $v ] }
        if (defined $take->(qr/null\b/)) { return [ 'null', undef ] }
        if (defined(my $r = $regex->())) { return [ 're', $r ] }
        $fail->();
    };
    $regex = sub {
        $ws->();
        return undef unless substr($s, $pos) =~ m{^/((?:[^/\\]|\\.)*)/([a-z]*)};
        my ($pat, $fl) = ($1, $2);
        $pos += length($pat) + 2 + length $fl;
        return _regex($pat, $fl, $s);
    };
    $primary = sub {
        if (defined $take->(qr/\(/)) {
            my $v = $or->();
            defined $take->(qr/\)/) or $fail->();
            return $v;
        }
        my $l = $operand->();
        if (defined(my $op = $take->(qr/==|!=|=~|!~/))) {
            my $r;
            if ($op eq '=~' || $op eq '!~') {
                my $re = $regex->();
                if (!defined $re) {
                    my $o = $operand->();
                    my $v = $o->[1];
                    $re = !defined $v ? undef : $v =~ m{^/(.*)/([a-z]*)$}s ? _regex($1, $2, $s) : _regex(quotemeta $v, '', $s);
                }
                my $m = defined $l->[1] && defined $re && $l->[1] =~ $re ? 1 : 0;
                return $op eq '=~' ? $m : !$m ? 1 : 0;
            }
            $r = $operand->();
            my ($a, $b) = ($l->[1], $r->[1]);
            my $eq = (!defined $a && !defined $b) ? 1 : (defined $a && defined $b && "$a" eq "$b") ? 1 : 0;
            return $op eq '==' ? $eq : $eq ? 0 : 1;
        }
        return (defined $l->[1] && $l->[1] ne '') ? 1 : 0 if $l->[0] eq 'var';
        return (defined $l->[1] && $l->[1] ne '') ? 1 : 0 if $l->[0] eq 'str';
        return 0;
    };
    $unary = sub { return $primary->() unless defined $take->(qr/!(?![=~])/); return $unary->() ? 0 : 1 };
    $and = sub {
        my $v = $unary->();
        while (defined $take->(qr/&&/)) { my $r = $unary->(); $v = $v && $r ? 1 : 0 }
        return $v;
    };
    $or = sub {
        my $v = $and->();
        while (defined $take->(qr/\|\|/)) { my $r = $and->(); $v = $v || $r ? 1 : 0 }
        return $v;
    };
    my $v = $or->();
    $ws->();
    $fail->() if $pos < length $s;
    return $v;
}
sub _regex {
    my ($pat, $fl, $expr) = @_;
    $fl =~ tr/imsx//cd;
    my $re = eval { $fl ? qr/(?$fl)$pat/ : qr/$pat/ };
    die "rules:if: bad regular expression /$pat/ in '$expr'\n" unless $re;
    return $re;
}

# ================================================================ globs
sub _glob_re {
    my ($g) = @_;
    $g =~ s{^\./}{};
    $g .= '**' if $g =~ m{/$};
    my $re = '';
    while ($g =~ /\G(\*\*\/?|\*|\?|\{([^}]*)\}|\[[^\]]*\]|.)/gcs) {
        my $t = $1;
        if    ($t =~ /^\*\*/) { $re .= $t =~ m{/$} ? '(?:.*/)?' : '.*' }
        elsif ($t eq '*')     { $re .= '[^/]*' }
        elsif ($t eq '?')     { $re .= '[^/]' }
        elsif ($t =~ /^\{/)   { $re .= '(?:' . join('|', map { quotemeta } split /,/, $2, -1) . ')' }
        elsif ($t =~ /^\[/)   { $re .= $t }
        else                  { $re .= quotemeta $t }
    }
    return qr/^$re$/;
}
sub _expand {                                  # $VAR / ${VAR} -> value ('' when unset)
    my ($s, $vars) = @_;
    return $s unless defined $s;
    $s =~ s/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/my $v = $vars->{ $1 \/\/ $2 }; defined $v ? $v : ''/ge;
    return $s;
}
sub _files {                                   # every file under $dir, relative, / separated (no .git)
    my ($dir) = @_;
    my @f;
    return () unless defined $dir && -d $dir;
    my $base = abs_path($dir);
    File::Find::find({ no_chdir => 1, wanted => sub {
        if (-d $_ && $_ =~ m{(?:^|/)\.git$}) { $File::Find::prune = 1; return }
        return unless -f $_;
        (my $r = $_) =~ s{^\Q$base\E/?}{};
        push @f, $r;
    } }, $base);
    return sort @f;
}
sub _globs_hit {                               # any of @paths matches any of @globs (a file under a matching dir counts)
    my ($globs, $paths, $vars) = @_;
    my @re = map { _glob_re(_expand($_, $vars)) } grep { defined } @$globs;
    for my $f (@$paths) {
        my @cand = ($f);
        my $d = $f; push @cand, $d while $d =~ s{/[^/]*$}{};
        for my $c (@cand) { for my $re (@re) { return 1 if $c =~ $re } }
    }
    return 0;
}

# ================================================================ the pipeline definition
my %GLOBAL = map { $_ => 1 } qw(image services stages types variables default workflow include before_script after_script cache spec);
my %WHEN = map { $_ => 1 } qw(on_success on_failure always manual delayed never);

sub load {
    my ($src, %o) = @_;
    my ($text, $file, $root);
    if (defined $src && $src !~ /\n/ && length $src && -f $src) {
        open my $fh, '<:raw', $src or die "cannot read $src: $!\n";
        local $/; $text = <$fh>; close $fh;
        $file = $o{file} // $src;
        $root = $o{root} // dirname(abs_path($src) // $src);
    } else { $text = $src // ''; $file = $o{file} // '.gitlab-ci.yml'; $root = $o{root} // getcwd }
    return _build({ text => $text, file => $file, root => $root }, $o{vars} // {}, $o{changed});
}

# ---- includes: local files are read and merged the way GitLab does; everything else runs on GitLab only
my $MAX_INCLUDES = 100;
sub _key_lines {                               # top-level key -> line number in this file's text
    my ($text) = @_;
    my (%line, $n);
    $n = 0;
    for my $l (split /\r?\n/, $text) {
        $n++;
        $line{$1} //= $n if $l =~ /^([^\s#'"\-][^:]*?)\s*:(?:\s|$)/;
        $line{$1} //= $n if $l =~ /^["']([^"']+)["']\s*:(?:\s|$)/;
    }
    return \%line;
}
sub _include_desc {
    my ($inc) = @_;
    return $inc =~ m{^https?://} ? "remote: $inc" : "local: $inc" unless ref $inc;
    return "$inc" unless ref $inc eq 'HASH';
    join ', ', map { $_ eq 'rules' ? '(conditional: rules)' : "$_: " . (ref $inc->{$_} ? join(' ', grep { !ref } _list_of($inc->{$_})) : $inc->{$_} // '') } sort keys %$inc;
}
sub _compose {                                 # one file and what it includes -> (merged data, key order); origins in $st
    my ($st, $file, $text, $stack) = @_;
    my $data = parse_yaml($text, $file);
    my $order = $LAST_ROOT_ORDER // [];
    $data //= {};
    die "$file:1: the top level must be a map of keys\n" unless ref $data eq 'HASH';
    my $lines = _key_lines($text);
    my $from = "$file:" . ($lines->{include} // 1);
    my ($acc, @acc_order, %seen) = ({});
    for my $inc (_list_of($data->{include})) {
        my $local;
        if (!ref $inc) { $local = $inc unless $inc =~ m{^https?://} }
        elsif (ref $inc eq 'HASH' && exists $inc->{local} && !exists $inc->{project}) { $local = $inc->{local} }
        elsif (ref $inc ne 'HASH') { die "$from: include: an item must be a path or a map (local:, template:, project:, remote:, component:)\n" }
        if (!defined $local) { push @{ $st->{remote} }, _include_desc($inc); next }
        die "$from: include: local: needs a path\n" if ref $local || $local eq '';
        if (ref $inc eq 'HASH' && defined $inc->{rules}) {
            die "$from: include: rules must be a list of maps\n" if ref $inc->{rules} ne 'ARRAY' || grep { ref $_ ne 'HASH' } @{ $inc->{rules} };
            $st->{conditional} = 1;
            my ($m) = grep { _rule_match($_, $st->{vars}, { dir => $st->{root}, changed => $st->{changed} }) } @{ $inc->{rules} };
            my $when = $m ? ($m->{when} // 'always') : 'never';
            die "$from: include: rules: when must be always or never, got '$when'\n" unless $when eq 'always' || $when eq 'never';
            next if $when eq 'never';
        }
        (my $path = $local =~ /\$/ ? _expand($local, $st->{vars}) : $local) =~ s{^/+}{};
        $path =~ s{^\./}{};
        my @files;
        if ($path =~ /[*?\[{]/) {
            $st->{all_files} //= [ _files($st->{root}) ];
            my $re = _glob_re($path);
            @files = grep { $_ =~ $re && /\.ya?ml$/ } @{ $st->{all_files} };
        } else {
            die "$from: include: local file '$path' must end in .yml or .yaml\n" unless $path =~ /\.ya?ml$/;
            die "$from: include: local file '$path' does not exist (paths start at the repository root)\n" unless -f File::Spec->catfile($st->{root}, split m{/}, $path);
            @files = ($path);
        }
        for my $f (@files) {
            if (grep { $_ eq $f } @$stack, $file) { die "$from: include: cycle " . join(' -> ', @$stack, $file, $f) . "\n" }
            next if $seen{$f}++;
            die "$from: include: more than $MAX_INCLUDES included files\n" if ++$st->{nfiles} > $MAX_INCLUDES;
            push @{ $st->{included} }, $f;
            my ($d, $ord) = _compose($st, $f, _slurp(File::Spec->catfile($st->{root}, split m{/}, $f)), [ @$stack, $file ]);
            $acc = _deep_merge($acc, $d);
            my %have = map { $_ => 1 } @acc_order;
            push @acc_order, grep { !$have{$_} } @$ord;
        }
    }
    my %own = %$data;
    delete $own{include};
    push @{ $st->{origin}{$_} }, [ $file, $lines->{$_} // 1 ] for grep { $_ ne 'include' } @$order;
    $acc = _deep_merge($acc, \%own);
    my %have = map { $_ => 1 } @acc_order;
    push @acc_order, grep { !$have{$_} && $_ ne 'include' } @$order;
    return ($acc, \@acc_order);
}

sub _build {
    my ($top, $vars, $changed) = @_;
    my $st = { root => $top->{root}, vars => $vars, changed => $changed, remote => [], included => [], origin => {}, nfiles => 0, conditional => 0 };
    my ($data, $order) = _compose($st, $top->{file}, $top->{text}, []);
    my $file = $top->{file};
    my $ci = { file => $file, text => $top->{text}, data => $data, origin => $st->{origin}, jobs => {}, order => [],
               includes => $st->{remote}, included => $st->{included}, conditional => $st->{conditional}, src => $top };
    _resolve_refs($ci, $data);
    my $st_ = $data->{stages} // $data->{types};
    die _at($ci, 'stages') . ": stages must be a list\n" if defined $st_ && ref $st_ ne 'ARRAY';
    my @stages = grep { defined && $_ ne '.pre' && $_ ne '.post' } @{ $st_ // [qw(build test deploy)] };
    $ci->{stages} = [ '.pre', @stages, '.post' ];
    $ci->{variables} = _vars($data->{variables}, $ci, 'variables');
    my $wf = ref $data->{workflow} eq 'HASH' ? $data->{workflow}{rules} : undef;
    die _at($ci, 'workflow') . ": workflow:rules must be a list of maps\n" if defined $wf && (ref $wf ne 'ARRAY' || grep { ref $_ ne 'HASH' } @$wf);
    $ci->{workflow} = $wf;
    $ci->{default} = ref $data->{default} eq 'HASH' ? $data->{default} : {};
    for my $name (@$order) {
        next if $GLOBAL{$name} || $name =~ /^\./;
        my $j = $data->{$name};
        die _at($ci, $name) . ": job '$name' must be a map of keys\n" unless ref $j eq 'HASH';
        my $full = _extends($ci, $name, {}, 0);
        $ci->{jobs}{$name} = _job($ci, $name, $full);
        $ci->{jobs}{$name}{file} = _from($ci, $name);
        push @{ $ci->{order} }, $name;
    }
    return $ci;
}

sub _at { my ($ci, $name) = @_; my $o = ($ci->{origin}{$name} // [])->[0]; $o ? "$o->[0]:$o->[1]" : "$ci->{file}:1" }
sub _from { my ($ci, $name) = @_; my %s; join ' + ', grep { !$s{$_}++ } map { $_->[0] } @{ $ci->{origin}{$name} // [] } }

sub _resolve_refs {                            # !reference [job, key, ...] -> the referenced value
    my ($ci, $node, $depth) = @_;
    $depth //= 0;
    die "$ci->{file}: !reference nested too deeply (a cycle?)\n" if $depth > 20;
    my $fix = sub {
        my ($v) = @_;
        return $v unless blessed $v && $v->isa('GitLabCI::Ref');
        my $cur = $ci->{data};
        for my $k (@{ $v->{path} }) {
            die(($v->{file} // $ci->{file}) . ":$v->{line}: !reference [" . join(", ", @{ $v->{path} }) . "] not found\n") unless ref $cur eq "HASH" && exists $cur->{$k};
            $cur = $cur->{$k};
        }
        my $c = _clone($cur);
        _resolve_refs($ci, $c, $depth + 1) if ref $c;
        return $c;
    };
    if (ref $node eq 'HASH') { for my $k (keys %$node) { $node->{$k} = $fix->($node->{$k}); _resolve_refs($ci, $node->{$k}, $depth) if ref $node->{$k} } }
    elsif (ref $node eq 'ARRAY') { for my $i (0 .. $#$node) { $node->[$i] = $fix->($node->[$i]); _resolve_refs($ci, $node->[$i], $depth) if ref $node->[$i] } }
}

sub _list_of { my ($v) = @_; return () unless defined $v; return @$v if ref $v eq 'ARRAY'; return ($v) }
sub _true { my ($v) = @_; defined $v && !ref $v && $v =~ /^(?:true|yes|on|1)$/i ? 1 : 0 }
sub _has_map { my ($v) = @_; return undef unless ref $v; if (ref $v eq 'HASH') { my ($k) = sort keys %$v; return defined $k ? "$k: ..." : '{}' } for (@$v) { my $r = _has_map($_); return $r if $r } undef }
sub _flat { my @o; for my $x (@_) { push @o, ref $x eq 'ARRAY' ? _flat(@$x) : defined $x ? ("$x") : () } @o }

sub _vars {
    my ($v, $ci, $where) = @_;
    return {} unless defined $v;
    die _at($ci, $where) . ": $where must be a map\n" unless ref $v eq 'HASH';
    my %o;
    for my $k (keys %$v) {
        my $x = $v->{$k};
        $x = $x->{value} if ref $x eq 'HASH';
        $o{$k} = defined $x && !ref $x ? "$x" : '';
    }
    return \%o;
}

sub _deep_merge {                              # $b over $a: maps merge recursively, lists and scalars are replaced
    my ($a, $b) = @_;
    my %r = %{ _clone($a) };
    for my $k (keys %$b) {
        if (ref $r{$k} eq 'HASH' && ref $b->{$k} eq 'HASH') { $r{$k} = _deep_merge($r{$k}, $b->{$k}) }
        else { $r{$k} = _clone($b->{$k}) }
    }
    return \%r;
}

sub _extends {
    my ($ci, $name, $seen, $depth) = @_;
    my $j = $ci->{data}{$name};
    die _at($ci, $name) . ": extends: '$name' is not defined\n" unless ref $j eq 'HASH';
    die _at($ci, $name) . ": extends: circular chain through '$name'\n" if $seen->{$name};
    die _at($ci, $name) . ": extends: more than 11 levels at '$name'\n" if $depth > 11;
    my @parents = _list_of($j->{extends});
    return _clone($j) unless @parents;
    my $acc = {};
    for my $par (@parents) {
        die _at($ci, $name) . ": job '$name' extends '$par', which is not defined\n" unless ref $ci->{data}{$par} eq 'HASH';
        $acc = _deep_merge($acc, _extends($ci, $par, { %$seen, $name => 1 }, $depth + 1));
    }
    my %own = %$j;
    delete $own{extends};
    my $r = _deep_merge($acc, \%own);
    delete $r->{extends};
    return $r;
}

sub _inherits {                                # does job $j take default:/global $key? (inherit:default true|false|list)
    my ($j, $key) = @_;
    my $inh = ref $j->{inherit} eq 'HASH' ? $j->{inherit}{default} : undef;
    return 1 unless defined $inh;
    return grep({ $_ eq $key } @$inh) ? 1 : 0 if ref $inh eq 'ARRAY';
    return _true($inh);
}

sub _job {
    my ($ci, $name, $j) = @_;
    my $at = _at($ci, $name);
    my %n = (name => $name);
    my $stage = $j->{stage} // 'test';
    die "$at: job '$name': stage '$stage' is not in stages (" . join(', ', @{ $ci->{stages} }) . ")\n" unless grep { $_ eq $stage } @{ $ci->{stages} };
    $n{stage} = $stage;
    $n{trigger} = exists $j->{trigger} ? 1 : 0;
    for my $k (qw(script before_script after_script)) {
        my $bad = _has_map($j->{$k}) or next;
        die "$at: job '$name': a $k line is a map ($bad) -- quote a command that contains ': '\n";
    }
    $n{script} = [ _flat($j->{script}) ];
    die "$at: job '$name' has no script (or trigger)\n" if !@{ $n{script} } && !$n{trigger};
    for my $k (qw(before_script after_script)) {
        my $v = exists $j->{$k} ? $j->{$k}
              : _inherits($j, $k) ? ($ci->{default}{$k} // $ci->{data}{$k}) : undef;
        $n{ $k eq 'before_script' ? 'before' : 'after' } = [ _flat($v) ];
    }
    $n{variables} = _vars($j->{variables}, $ci, $name);
    my $iv = ref $j->{inherit} eq 'HASH' ? $j->{inherit}{variables} : undef;
    $n{global_vars} = !defined $iv ? 1 : ref $iv eq 'ARRAY' ? $iv : _true($iv);
    if (defined $j->{rules}) {
        die "$at: job '$name': rules must be a list of maps\n" if ref $j->{rules} ne 'ARRAY' || grep { ref $_ ne 'HASH' } @{ $j->{rules} };
        die "$at: job '$name': rules cannot be used with only/except\n" if defined $j->{only} || defined $j->{except};
        $n{rules} = $j->{rules};
        for my $r (@{ $j->{rules} }) { die "$at: job '$name': unknown when '$r->{when}' in rules\n" if defined $r->{when} && !$WHEN{ $r->{when} } }
    }
    $n{only} = $j->{only};
    $n{except} = $j->{except};
    my $when = $j->{when} // 'on_success';
    die "$at: job '$name': unknown when '$when'\n" unless $WHEN{$when};
    $n{when} = $when;
    $n{allow_failure} = $j->{allow_failure};
    my $art = $j->{artifacts};
    $n{artifacts} = ref $art eq 'HASH' ? [ _flat($art->{paths}) ] : [];
    $n{artifacts_when} = ref $art eq 'HASH' ? ($art->{when} // 'on_success') : 'on_success';
    $n{needs} = [ map { ref $_ eq 'HASH' ? $_->{job} : $_ } _list_of($j->{needs}) ];
    return \%n;
}

# ================================================================ which jobs a pipeline gets
my %REFWORD = (merge_requests => 'merge_request_event', schedules => 'schedule', pushes => 'push', web => 'web', api => 'api',
               triggers => 'trigger', pipelines => 'pipeline', chat => 'chat', external => 'external',
               external_pull_requests => 'external_pull_request_event');

sub _rule_match {
    my ($r, $vars, $o) = @_;
    return 0 if exists $r->{if} && !eval_if($r->{if}, $vars);
    if (exists $r->{changes} && defined $o->{changed}) {
        my $c = $r->{changes};
        my @g = ref $c eq 'HASH' ? _list_of($c->{paths}) : _list_of($c);
        return 0 unless _globs_hit(\@g, $o->{changed}, $vars);
    }
    if (exists $r->{exists}) {
        my $e = $r->{exists};
        my @g = ref $e eq 'HASH' ? _list_of($e->{paths}) : _list_of($e);
        $o->{_files} //= [ _files($o->{dir}) ];
        return 0 unless _globs_hit(\@g, $o->{_files}, $vars);
    }
    return 1;
}

sub _only_match {                              # only:/except: spec matches this pipeline?
    my ($spec, $vars, $o) = @_;
    $spec = { refs => $spec } if ref $spec ne 'HASH';
    my $src = $vars->{CI_PIPELINE_SOURCE} // 'push';
    my $mr = $src eq 'merge_request_event';
    my $ref = $vars->{CI_COMMIT_REF_NAME} // $vars->{CI_COMMIT_TAG} // $vars->{CI_COMMIT_BRANCH};
    if (defined $spec->{refs}) {
        my $hit = 0;
        for my $w (_list_of($spec->{refs})) {
            next unless defined $w;
            if    ($w eq 'branches') { $hit = 1 if !$mr && defined $vars->{CI_COMMIT_BRANCH} && !defined $vars->{CI_COMMIT_TAG} }
            elsif ($w eq 'tags')     { $hit = 1 if defined $vars->{CI_COMMIT_TAG} && $vars->{CI_COMMIT_TAG} ne '' }
            elsif ($REFWORD{$w})     { $hit = 1 if $src eq $REFWORD{$w} }
            elsif ($w =~ m{^/(.*)/([a-z]*)$}s) { $hit = 1 if !$mr && defined $ref && $ref =~ _regex($1, $2, $w) }
            else                     { $hit = 1 if !$mr && defined $ref && $ref eq $w }
            last if $hit;
        }
        return 0 unless $hit;
    }
    if (defined $spec->{variables}) { return 0 unless grep { eval_if($_, $vars) } _list_of($spec->{variables}) }
    if (defined $spec->{changes} && defined $o->{changed}) {
        my $c = $spec->{changes};
        return 0 unless _globs_hit([ ref $c eq 'HASH' ? _list_of($c->{paths}) : _list_of($c) ], $o->{changed}, $vars);
    }
    return 1;
}

sub plan {
    my ($ci, %o) = @_;
    $ci = _build($ci->{src}, { %{ $o{vars} // {} } }, $o{changed}) if $ci->{conditional} && $ci->{src};   # include:rules need this pipeline's variables
    my %v = (%{ $ci->{variables} }, %{ $o{vars} // {} });
    my (@jobs, @skipped);
    push @skipped, map { { name => "include: $_", reason => 'include: runs on GitLab only' } } @{ $ci->{includes} };
    my $res = { jobs => \@jobs, skipped => \@skipped, stages => $ci->{stages} };
    if ($ci->{workflow}) {
        my ($m) = grep { _rule_match($_, \%v, \%o) } @{ $ci->{workflow} };
        my $why = !$m ? 'workflow:rules: no rule matched' : ($m->{when} // '') eq 'never' ? 'workflow:rules: when never' : undef;
        if ($why) { push @skipped, map { { name => $_, reason => $why } } @{ $ci->{order} }; $res->{workflow} = 'blocked'; return $res }
        %v = (%v, %{ _vars($m->{variables}, $ci, 'workflow') });
        %v = (%v, %{ $o{vars} // {} });
    }
    my %sel = map { $_ => 1 } @{ $o{only_jobs} // [] };
    my %idx; @idx{ @{ $ci->{stages} } } = 0 .. $#{ $ci->{stages} };
    my $k = 0;
    for my $name (@{ $ci->{order} }) {
        my $j = $ci->{jobs}{$name};
        $k++;
        my $skip = sub { push @skipped, { name => $name, reason => $_[0] } };
        $skip = sub { push @skipped, { name => $name, reason => $_[0], file => $j->{file} } };
        if (%sel && !$sel{$name}) { $skip->('not selected (--job)'); next }
        if ($j->{trigger}) { $skip->('trigger: runs on GitLab only'); next }
        my %jv = (%v, %{ $j->{variables} }, %{ $o{vars} // {} });
        my ($when, $af, %rv, $reason);
        if ($j->{rules}) {
            my $i = 0;
            my ($m) = grep { $i++; _rule_match($_, \%jv, \%o) } @{ $j->{rules} };
            if (!$m) { $skip->('rules: no rule matched'); next }
            $when = $m->{when} // 'on_success';
            if ($when eq 'never') { $skip->("rules: rule $i says when: never"); next }
            $af = exists $m->{allow_failure} ? $m->{allow_failure} : $j->{allow_failure};
            %rv = %{ _vars($m->{variables}, $ci, $name) };
            $reason = "rules: rule $i matched";
        } elsif (defined $j->{only} || defined $j->{except}) {
            if (defined $j->{only} && !_only_match($j->{only}, \%jv, \%o)) { $skip->('only: not this pipeline'); next }
            if (defined $j->{except} && _only_match($j->{except}, \%jv, \%o)) { $skip->('except: this pipeline is excluded'); next }
            $when = $j->{when};
            $reason = 'only/except';
        } else {
            if (($jv{CI_PIPELINE_SOURCE} // '') =~ /^(?:merge_request_event|external_pull_request_event)$/) {
                $skip->('no rules or only/except: not added to merge request pipelines'); next;
            }
            $when = $j->{when};
            $reason = 'no rules: branch and tag pipelines';
        }
        if ($when eq 'never') { $skip->('when: never'); next }
        $af //= $j->{allow_failure} // ($when eq 'manual' && !$j->{rules} ? 'true' : undef);
        push @jobs, { name => $name, stage => $j->{stage}, when => $when eq 'delayed' ? 'on_success' : $when,
                      allow_failure => $af, script => $j->{script}, before => $j->{before}, after => $j->{after},
                      variables => { %{ $j->{variables} }, %rv }, global_vars => $j->{global_vars},
                      artifacts => $j->{artifacts}, artifacts_when => $j->{artifacts_when}, needs => $j->{needs},
                      reason => $reason, file => $j->{file}, _k => $k };
    }
    @jobs = sort { $idx{ $a->{stage} } <=> $idx{ $b->{stage} } || $a->{_k} <=> $b->{_k} } @jobs;
    delete $_->{_k} for @jobs;
    return $res;
}

# ================================================================ running a pipeline
sub _safe { my ($n) = @_; $n =~ s/[^A-Za-z0-9._-]+/_/g; $n }
sub _allowed {
    my ($af, $exit) = @_;
    return scalar grep({ $_ == $exit } _list_of($af->{exit_codes})) ? 1 : 0 if ref $af eq 'HASH';
    return _true($af);
}
sub _sq { my ($s) = @_; $s =~ s/'/'\\''/g; "'$s'" }

sub _sh {                                      # run $shell -e $file in $dir with %$env, output to $log; -> exit code
    my ($shell, $file, $dir, $env, $log, $mode) = @_;
    STDOUT->flush; STDERR->flush;
    open my $out, $mode, $log or die "cannot write $log: $!\n";
    open my $oldout, '>&', \*STDOUT or die "cannot save STDOUT: $!\n";
    open my $olderr, '>&', \*STDERR or die "cannot save STDERR: $!\n";
    open STDOUT, '>&', $out or die "cannot redirect STDOUT: $!\n";
    open STDERR, '>&', $out or die "cannot redirect STDERR: $!\n";
    my $cwd = getcwd;
    my $rc;
    if (chdir $dir) {
        local %ENV = %$env;
        $rc = system($shell, '-e', $file);
        chdir $cwd;
    } else { print $out "cannot chdir to $dir: $!\n"; $rc = 1 << 8 }
    STDOUT->flush; STDERR->flush;
    open STDOUT, '>&', $oldout or die "cannot restore STDOUT: $!\n";
    open STDERR, '>&', $olderr or die "cannot restore STDERR: $!\n";
    close $out;
    return 127 if $rc == -1;
    return 128 + ($rc & 127) if $rc & 127;
    return $rc >> 8;
}

sub _script_text {
    my (@cmds) = @_;
    my $t = '';
    for my $c (@cmds) {
        my ($first) = split /\n/, $c;
        $first //= '';
        $t .= 'printf "%s\n" ' . _sq('$ ' . $first . ($c =~ /\n./ ? ' # collapsed multi-line command' : '')) . "\n$c\n";
    }
    return $t;
}

sub _write { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
sub _slurp { my ($f) = @_; open my $fh, '<:raw', $f or return ''; local $/; my $t = <$fh>; close $fh; $t // '' }

sub _copy_artifacts {
    my ($dir, $paths, $dest, $vars) = @_;
    my @files = _files($dir);
    my $n = 0;
    for my $f (@files) {
        next unless _globs_hit($paths, [$f], $vars);
        my $to = File::Spec->catfile($dest, split m{/}, $f);
        make_path(dirname($to));
        copy(File::Spec->catfile($dir, split m{/}, $f), $to) and $n++;
    }
    return $n;
}

sub _run_job {
    my ($ci, $j, %o) = @_;
    my $dir = $o{dir};
    my $clock = $o{clock};
    my $gv = $j->{global_vars};
    my %g = ref $gv eq 'ARRAY' ? (map { exists $ci->{variables}{$_} ? ($_ => $ci->{variables}{$_}) : () } @$gv) : $gv ? %{ $ci->{variables} } : ();
    my %yaml = (%g, %{ $j->{variables} });
    my %vars = (%yaml, %{ $o{vars} // {} });
    for my $k (keys %yaml) { $vars{$k} = _expand($vars{$k}, \%vars) unless exists(($o{vars} // {})->{$k}) }
    my %env = (%ENV, %vars, CI => 'true', GITLAB_CI => 'true', CI_JOB_NAME => $j->{name}, CI_JOB_STAGE => $j->{stage},
               CI_PROJECT_DIR => $dir, CI_BUILDS_DIR => dirname($dir));
    my $log = File::Spec->catfile($o{log_dir}, _safe($j->{name}) . '.log');
    my $key;
    if ($o{cache} && defined $o{tree}) {
        $key = join "\0", $j->{name}, $o{tree}, md5_hex(join "\n", @{ $j->{before} }, '--', @{ $j->{script} }, '--', @{ $j->{after} }, '--',
                                                           (map { "$_=$vars{$_}" } sort keys %yaml),
                                                           # the pipeline's context: the same tree checked as a branch push and as a merge request
                                                           # (or a tag, a schedule, a trigger) is a different check -- ratchets read the merge base
                                                           map { "$_=" . ($vars{$_} // '') } qw(CI_PIPELINE_SOURCE CI_COMMIT_TAG CI_MERGE_REQUEST_DIFF_BASE_SHA FULL));
        if (my $c = $o{cache}{$key}) {
            _write($log, $c->{log_text});
            if ($c->{artifacts} && -d $c->{artifacts}) {
                my $dest = File::Spec->catdir($o{log_dir}, 'artifacts', _safe($j->{name}));
                _copy_artifacts($c->{artifacts}, ['**'], $dest, {}) if $c->{artifacts} ne $dest;
            }
            return { name => $j->{name}, stage => $j->{stage}, status => $c->{status}, started => $clock->(),
                     duration => $c->{duration}, log => $log, exit => $c->{exit}, cached => 1 };
        }
    }
    my $sf = File::Spec->catfile($o{log_dir}, _safe($j->{name}) . '.sh');
    _write($sf, _script_text(@{ $j->{before} }, @{ $j->{script} }));
    my $started = $clock->();
    my $t0 = Time::HiRes::time();
    my $exit = _sh($o{shell}, $sf, $dir, \%env, $log, '>');
    my $status = $exit == 0 ? 'success' : _allowed($j->{allow_failure}, $exit) ? 'allowed_failure' : 'failed';
    if (@{ $j->{after} }) {
        my $af = File::Spec->catfile($o{log_dir}, _safe($j->{name}) . '.after.sh');
        _write($af, _script_text(@{ $j->{after} }));
        _sh($o{shell}, $af, $dir, { %env, CI_JOB_STATUS => $status eq 'success' ? 'success' : 'failed' }, $log, '>>');
    }
    my $dur = Time::HiRes::time() - $t0;
    my $art;
    if (@{ $j->{artifacts} }) {
        my $w = $j->{artifacts_when};
        if ($w eq 'always' || ($w eq 'on_success' && $status ne 'failed') || ($w eq 'on_failure' && $status eq 'failed')) {
            $art = File::Spec->catdir($o{log_dir}, 'artifacts', _safe($j->{name}));
            _copy_artifacts($dir, $j->{artifacts}, $art, \%vars);
        }
    }
    my $r = { name => $j->{name}, stage => $j->{stage}, status => $status, started => $started,
              duration => 0 + sprintf('%.3f', $dur), log => $log, exit => $exit, cached => 0 };
    $o{cache}{$key} = { status => $status, duration => $r->{duration}, exit => $exit, log_text => _slurp($log), artifacts => $art } if $key;
    return $r;
}

sub _run_parallel {                            # a stage's jobs side by side (fork), results in plan order; new cache entries merged back
    my ($ci, $jobs, $o) = @_;
    require Storable; require POSIX;
    my $max = $o->{parallel};
    my $tmp = tempdir('gitlab-ci-par-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my (@r, %pid, @queue);
    @queue = (0 .. $#$jobs);
    my $start = sub {
        my $i = shift;
        STDOUT->flush; STDERR->flush;
        my $pid = fork;
        if (!defined $pid) { $r[$i] = _run_job($ci, $jobs->[$i], %$o); return }   # no fork here: run it in turn
        if (!$pid) {
            my %before = map { $_ => 1 } keys %{ $o->{cache} // {} };
            my $res = eval { _run_job($ci, $jobs->[$i], %$o) } // { name => $jobs->[$i]{name}, stage => $jobs->[$i]{stage}, status => 'failed',
                started => $o->{clock}->(), duration => 0, log => undef, exit => 1, cached => 0, error => "$@" };
            my %new = map { $_ => $o->{cache}{$_} } grep { !$before{$_} } keys %{ $o->{cache} // {} };
            Storable::nstore({ r => $res, cache => \%new }, "$tmp/$i.sto");
            POSIX::_exit(0);
        }
        $pid{$pid} = $i;
    };
    while (@queue || %pid) {
        $start->(shift @queue) while @queue && keys(%pid) < $max;
        last unless %pid;
        my $pid = waitpid(-1, 0);
        last if $pid <= 0;
        my $i = delete $pid{$pid} // next;
        my $got = eval { Storable::retrieve("$tmp/$i.sto") };
        if ($got) { $r[$i] = $got->{r}; $o->{cache}{$_} = $got->{cache}{$_} for keys %{ $got->{cache} } }
        else { $r[$i] = { name => $jobs->[$i]{name}, stage => $jobs->[$i]{stage}, status => 'failed', started => $o->{clock}->(), duration => 0, log => undef, exit => 1, cached => 0 } }
    }
    @r;
}

sub run {
    my ($ci, %o) = @_;
    $o{clock} //= sub { time };
    $o{shell} //= 'sh';
    $o{dir} = abs_path($o{dir} // getcwd) // $o{dir};
    $o{log_dir} //= tempdir('gitlab-ci-XXXXXX', TMPDIR => 1, CLEANUP => 0);
    make_path($o{log_dir});
    my $plan = plan($ci, %o);
    my $res = { status => 'skipped', started => $o{clock}->(), duration => 0, jobs => [], skipped => $plan->{skipped}, log_dir => $o{log_dir} };
    return $res unless @{ $plan->{jobs} };
    my $failed = 0;
    for my $stage (@{ $plan->{stages} }) {
        my $stage_failed = 0;
        my (@run, @slot);                      # the stage's runnable jobs; with parallel => N they run side by side, like N runners
        for my $j (grep { $_->{stage} eq $stage } @{ $plan->{jobs} }) {
            my $go = $j->{when} eq 'always' ? 1 : $j->{when} eq 'on_failure' ? $failed : $j->{when} eq 'manual' ? ($o{manual} && !$failed) : !$failed;
            if (!$go) {
                push @{ $res->{jobs} }, { name => $j->{name}, stage => $stage, status => $j->{when} eq 'manual' && !$o{manual} ? 'manual' : 'skipped',
                                          started => $o{clock}->(), duration => 0, log => undef, exit => undef, cached => 0 };
                next;
            }
            push @{ $res->{jobs} }, undef;
            push @slot, $#{ $res->{jobs} };
            push @run, $j;
        }
        my @r = ($o{parallel} // 1) > 1 && @run > 1 ? _run_parallel($ci, \@run, \%o) : map { _run_job($ci, $_, %o) } @run;
        for my $i (0 .. $#run) {
            $res->{jobs}[ $slot[$i] ] = $r[$i];
            $res->{duration} += $r[$i]{duration};
            $stage_failed = 1 if $r[$i]{status} eq 'failed';
        }
        $failed ||= $stage_failed;
    }
    $res->{duration} = 0 + sprintf('%.3f', $res->{duration});
    $res->{status} = $failed ? 'failed' : (grep { $_->{status} =~ /^(?:success|allowed_failure)$/ } @{ $res->{jobs} }) ? 'success' : 'skipped';
    return $res;
}

# ================================================================ gitlab.pl ci
my $USAGE = <<'EOF';
usage: gitlab.pl ci [--file .gitlab-ci.yml] [--event push|merge_request_event|tag|schedule|web|trigger]
                    [--branch B] [--target B] [--tag T] [--var K=V]... [--job NAME]... [--manual]
                    [--logs DIR] [--list]
Runs the pipeline of the current git repository locally, the way GitLab would select its jobs for that event.
  --event    pipeline source (default push); tag sets CI_COMMIT_TAG (from --tag or the tag on HEAD)
  --branch   the branch (default: the current one); --target the merge request target (default: CI_DEFAULT_BRANCH)
  --var      a CI/CD variable (repeat); --job run only these jobs; --manual also run manual jobs
  --list     show which jobs the pipeline would get, and why the others are left out, without running anything
EOF

sub _git_out {                                 # (stdout, exit) of git -C $dir ARGS, stderr discarded
    my ($dir, @args) = @_;
    STDERR->flush;
    open my $olderr, '>&', \*STDERR or return ('', 1);
    open STDERR, '>', File::Spec->devnull;
    my $out = '';
    my $ok = open my $fh, '-|', 'git', '-C', $dir, @args;
    if ($ok) { local $/; $out = <$fh> // ''; close $fh }
    my $rc = $ok ? $? >> 8 : 1;
    open STDERR, '>&', $olderr;
    $out =~ s/\s+$//;
    return ($out, $rc);
}

sub cli {
    my @a = @_;
    my %o = (file => '.gitlab-ci.yml', event => 'push');
    my (@var, @job);
    my $bad = 0;
    {
        local $SIG{__WARN__} = sub { print STDERR "gitlab.pl ci: $_[0]"; $bad = 1 };
        GetOptionsFromArray(\@a, \%o, 'file=s', 'event=s', 'branch=s', 'target=s', 'tag=s', 'var=s' => \@var, 'job=s' => \@job,
                            'manual', 'list', 'logs=s', 'help|h') or $bad = 1;
    }
    if ($o{help}) { print $USAGE; return 0 }
    if ($bad) { print STDERR $USAGE; return 2 }
    if (@a) { print STDERR "gitlab.pl ci: unexpected argument '$a[0]'\n$USAGE"; return 2 }
    my %EV = map { $_ => 1 } qw(push merge_request_event tag schedule web api trigger);
    unless ($EV{ $o{event} }) { print STDERR "gitlab.pl ci: unknown --event '$o{event}' (push, merge_request_event, tag, schedule, web, trigger)\n"; return 2 }
    my %cv;
    for my $kv (@var) {
        unless ($kv =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s) { print STDERR "gitlab.pl ci: --var needs KEY=VALUE, got '$kv'\n"; return 2 }
        $cv{$1} = $2;
    }
    my ($top, $rc) = _git_out(getcwd, 'rev-parse', '--show-toplevel');
    if ($rc || $top eq '') { print STDERR "gitlab.pl ci: not inside a git work tree\n"; return 2 }
    my $file = -f $o{file} ? $o{file} : File::Spec->catfile($top, $o{file});
    unless (-f $file) { print STDERR "gitlab.pl ci: no $o{file} here or at the top of the work tree (pass --file)\n"; return 2 }
    my $ci = eval { load($file, file => $o{file}, root => $top) };
    unless ($ci) { print STDERR $@; return 2 }

    my %v;
    my ($sha) = _git_out($top, 'rev-parse', 'HEAD');
    my ($def) = _git_out($top, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD');
    $def =~ s{^origin/}{};
    $def = 'main' if $def eq '';
    my $branch = $o{branch};
    if (!defined $branch) { my ($b) = _git_out($top, 'rev-parse', '--abbrev-ref', 'HEAD'); $branch = $b eq 'HEAD' || $b eq '' ? undef : $b }
    my ($title) = _git_out($top, 'log', '-1', '--format=%s');
    my ($msg) = _git_out($top, 'log', '-1', '--format=%B');
    (my $path = $top) =~ s{.*/}{};
    %v = (CI_COMMIT_SHA => $sha, CI_COMMIT_SHORT_SHA => substr($sha, 0, 8), CI_DEFAULT_BRANCH => $def, CI_PROJECT_DIR => $top,
          CI_PROJECT_NAME => $path, CI_PROJECT_PATH => "local/$path", CI_PIPELINE_ID => 1, CI_PIPELINE_IID => 1,
          CI_COMMIT_TITLE => $title, CI_COMMIT_MESSAGE => $msg, CI_SERVER => 'yes', CI_SERVER_HOST => 'localhost');
    my $changed;
    if ($o{event} eq 'merge_request_event') {
        unless (defined $branch) { print STDERR "gitlab.pl ci: a merge request pipeline needs a branch (check one out or pass --branch)\n"; return 2 }
        my $target = $o{target} // $def;
        %v = (%v, CI_PIPELINE_SOURCE => 'merge_request_event', CI_COMMIT_REF_NAME => $branch, CI_MERGE_REQUEST_IID => 1,
              CI_MERGE_REQUEST_SOURCE_BRANCH_NAME => $branch, CI_MERGE_REQUEST_TARGET_BRANCH_NAME => $target,
              CI_MERGE_REQUEST_EVENT_TYPE => 'detached');
        for my $ref ($target, "origin/$target") {
            my ($d, $r) = _git_out($top, 'diff', '--name-only', "$ref...HEAD");
            if (!$r) { $changed = [ grep { $_ ne '' } split /\n/, $d ]; last }
        }
    } elsif ($o{event} eq 'tag') {
        my $tag = $o{tag};
        if (!defined $tag) { ($tag) = _git_out($top, 'describe', '--exact-match', '--tags', 'HEAD') }
        if (!defined $tag || $tag eq '') { print STDERR "gitlab.pl ci: --event tag needs --tag T (HEAD has no tag)\n"; return 2 }
        %v = (%v, CI_PIPELINE_SOURCE => 'push', CI_COMMIT_TAG => $tag, CI_COMMIT_REF_NAME => $tag);
    } else {
        unless (defined $branch) { print STDERR "gitlab.pl ci: HEAD is detached: pass --branch B\n"; return 2 }
        %v = (%v, CI_PIPELINE_SOURCE => $o{event}, CI_COMMIT_BRANCH => $branch, CI_COMMIT_REF_NAME => $branch);
        if ($o{event} eq 'push') {
            my ($d, $r) = _git_out($top, 'diff', '--name-only', 'HEAD~1', 'HEAD');
            $changed = $r ? [ grep { $_ ne '' } split /\n/, (_git_out($top, 'ls-files'))[0] ] : [ grep { $_ ne '' } split /\n/, $d ];
        }
    }
    %v = (%v, %cv);
    my %ro = (vars => \%v, changed => $changed, dir => $top, only_jobs => (@job ? \@job : undef));
    if ($o{list}) {
        my $p = plan($ci, %ro);
        my $w = 4; for (@{ $p->{jobs} }, @{ $p->{skipped} }) { my $l = length($_->{file} // '-'); $w = $l if $l > $w }
        printf "%-24s %-10s %-10s %-${w}s  %s\n", $_->{name}, $_->{stage}, $_->{when}, $_->{file} // '-', $_->{reason} for @{ $p->{jobs} };
        printf "%-24s %-10s %-10s %-${w}s  %s\n", $_->{name}, '-', 'skipped', $_->{file} // '-', $_->{reason} for @{ $p->{skipped} };
        printf "included: %s\n", join(', ', @{ $ci->{included} }) if @{ $ci->{included} };
        printf "pipeline: %d job%s\n", scalar @{ $p->{jobs} }, @{ $p->{jobs} } == 1 ? '' : 's';
        return 0;
    }
    my $res = run($ci, %ro, manual => $o{manual}, log_dir => $o{logs});
    for my $j (@{ $res->{jobs} }) {
        printf "%-24s %-10s %-16s %6.1fs%s\n", $j->{name}, $j->{stage}, $j->{status}, $j->{duration}, $j->{cached} ? ' (cached)' : '';
        if ($j->{status} eq 'failed' && $j->{log}) {
            my @l = split /\n/, _slurp($j->{log});
            print map { "    | $_\n" } @l[ ($#l > 14 ? $#l - 14 : 0) .. $#l ];
        }
    }
    printf "%-24s %-10s %-16s %s\n", $_->{name}, '-', 'not run', $_->{reason} for grep { $_->{reason} =~ /GitLab only/ } @{ $res->{skipped} };
    printf "pipeline: %s (%d job%s)\nlogs: %s\n", $res->{status}, scalar @{ $res->{jobs} }, @{ $res->{jobs} } == 1 ? '' : 's', $res->{log_dir};
    return $res->{status} eq 'failed' ? 1 : 0;
}

1;
