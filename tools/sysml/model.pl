#!/usr/bin/env perl
# model.pl -- structure checker, tree renderer and document generator for a SysML v2 text model.
# Core Perl 5 only (runs on the Perl bundled with Git for Windows). Project-agnostic: the project is
# the nearest directory upward from the current one that holds a model/ folder (or --root DIR), and
# its sysml.conf (key = value lines) names the roots of the two trees:
#
#   noun_root     = EnterpriseDef        the part def at the top of the noun (part) tree
#   verb_root     = DefendAgainstThreat  the calc def or action def at the top of the verb (function) tree
#   title         = Halberd              used in generated document titles (default: the folder name)
#   idef0_name    = KillChain            docs/idef0/<idef0_name>.md (default KillChain)
#   model_letter  = K                    IDEF0 letter reserved for the verb root itself (default K)
#   steps         = detect:D:Detect, ... top-level verb usages -> IDEF0 model letter and label
#   control_types = TypeA, TypeB         flow types drawn as IDEF0 controls (orders, rules, authorizations)
#   alloc_prefix  = defend               the feature path that stands for the verb root in
#                                        'allocate defend.x.y to part.path;' (those become IDEF0 mechanisms)
#   acronyms      = ABC, QoS             kept whole when names are split into words
#   level_tags    = L1Enterprise, ...    the @L<n> metadata names 'new part' writes, level 1 first
#   need_prefix   = N-                   requirement ids starting with it are needs (trace status 'need')
#
#   perl tools/sysml/model.pl [--root DIR] COMMAND [options]      ('help' lists the commands)
#   perl tools/sysml/model.pl stats            size, nesting, decomposition depth, 2..9 outline check
#   perl tools/sysml/model.pl nouns [--plain]  the noun tree (parts, L1..L9)
#   perl tools/sysml/model.pl verbs [--plain]  the verb tree (functions)
#   perl tools/sysml/model.pl docs             write docs/Nouns.md, Verbs.md, idef0/, Traceability.md
#   perl tools/sysml/model.pl check            outline + level-tag check only (exit status)
#   perl tools/sysml/model.pl draw tree|trace|ibd|pkg [-o F]   an SVG view (tools/sysml/views; also plates, diff,
#                                              threats, gate: the standalone tools run on this model, options passed on)
#
# Options: --plain   human-readable names ("Beam Control Subsystem")
#          --ascii   ASCII tree glyphs instead of box-drawing characters
#
# Verbs are functions: a calc def (return : T) or an action def with one 'out result : T'. A child
# function's result is referred to as child.result in both. Diagnostics name files relative to the
# current directory (so Vim's quickfix finds them); generated docs go to <root>/docs.
#
# Exit status: 0 clean, 1 violations found, 2 usage error.
use strict;
use warnings;
use utf8;
use File::Find ();
use File::Basename qw(dirname basename);
use File::Spec;
use Cwd qw(abs_path getcwd);
my $TOOLS;
BEGIN { $TOOLS = dirname(abs_path($0)) }                     # tools/sysml: grammar, library names, hook template
use lib "$TOOLS/lib", "$TOOLS/../../lib";                    # SysML::*, then the kit's Prelude.pm
my $KIT = abs_path(File::Spec->catdir($TOOLS, File::Spec->updir, File::Spec->updir));   # the agile kit root

my @argv = @ARGV;
my $root_opt;
my %PASS = map { $_ => 1 } qw(draw plates diff threats gate);     # tools/sysml/views wrappers: what follows is the tool's (its --root too)
for (my $i = 0; $i < @argv; $i++) {
    if    ($argv[$i] =~ /^--root=(.+)/) { $root_opt = $1; splice @argv, $i--, 1 }
    elsif ($argv[$i] eq '--root')       { $root_opt = $argv[$i + 1]; splice @argv, $i--, 2 }
    elsif ($argv[$i] !~ /^--/ && $PASS{ $argv[$i] }) { last }
}

sub find_root {    # nearest directory upward from $_[0] that holds model/
    my $d = abs_path(shift);
    while (defined $d) {
        return $d if -d File::Spec->catdir($d, 'model');
        my $up = abs_path(File::Spec->catdir($d, File::Spec->updir));
        last if !defined $up || $up eq $d;
        $d = $up;
    }
    undef;
}

my $ROOT = defined $root_opt ? abs_path($root_opt) : find_root(getcwd());
my ($first_cmd) = grep { !/^--/ } @argv;
if (($first_cmd // 'help') !~ /^(help|libnames)$/ && (!defined $ROOT || !-d File::Spec->catdir($ROOT, 'model'))) {
    print STDERR "model.pl: no model/ directory ", (defined $root_opt ? "in $root_opt" : 'here or above ' . getcwd()),
                 " -- run inside a project or pass --root DIR\n";
    exit 2;
}
$ROOT //= getcwd();
my $MODEL = File::Spec->catdir($ROOT, 'model');

sub read_conf {    # key = value lines; # comments
    my $f = shift;
    my %c;
    open my $fh, '<:encoding(UTF-8)', $f or return %c;
    while (<$fh>) { s/\s+\z//; next if /^\s*(?:#|$)/; $c{$1} = $2 if /^\s*([\w.-]+)\s*=\s*(.*?)\s*$/ }
    close $fh;
    %c;
}
my %CONF = read_conf(File::Spec->catfile($ROOT, 'sysml.conf'));
sub conf_list { my $v = $CONF{ $_[0] }; defined $v && $v =~ /\S/ ? (split /\s*,\s*/, $v) : () }
my $NOUN_ROOT    = $CONF{noun_root} // 'EnterpriseDef';
my $VERB_ROOT    = $CONF{verb_root} // 'Mission';
my $TITLE        = $CONF{title} // basename($ROOT);
my $IDEF0_NAME   = $CONF{idef0_name} // 'KillChain';
my $MODEL_LETTER = $CONF{model_letter} // 'K';
my $NEED_PREFIX  = $CONF{need_prefix} // 'N-';
my $ALLOC_PREFIX = $CONF{alloc_prefix} // '';
my ($MIN, $MAX) = (2, 9);
my $ME = 'perl tools/sysml/model.pl';

my %opt = (plain => 0, ascii => 0);
my ($pass_at) = grep { $argv[$_] !~ /^--/ && $PASS{ $argv[$_] } } 0 .. $#argv;
my @args = defined $pass_at ? (grep({ !/^--(plain|ascii)$/ || !($opt{$1} = 1) } @argv[0 .. $pass_at - 1]), @argv[$pass_at .. $#argv])
                            : grep { !/^--(plain|ascii)$/ || !($opt{$1} = 1) } @argv;
my $cmd = shift(@args) // '';

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# ------------------------------------------------------------------ files
my @FILES;
File::Find::find({ no_chdir => 1, wanted => sub { push @FILES, $_ if /\.sysml\z/ && -f $_ } }, $MODEL) if -d $MODEL;
@FILES = sort @FILES;

sub rel {          # messages: relative to the current directory (absolute when that would climb out of it)
    my $a = File::Spec->rel2abs(shift);
    my $p = File::Spec->abs2rel($a);
    ($p =~ m{^\.\.(?:[/\\]|\z)} ? $a : $p) =~ s{\\}{/}gr;
}
sub rel_root { my $p = shift; File::Spec->abs2rel($p, $ROOT) =~ s{\\}{/}gr }   # inside generated files: relative to the project

sub slurp {
    my $f = shift;
    open my $fh, '<:encoding(UTF-8)', $f or die "cannot read $f: $!\n";
    local $/;
    my $t = <$fh>;
    close $fh;
    $t =~ s/\r\n?/\n/g;
    $t;
}

my %RAW  = map { $_ => slurp($_) } @FILES;
my %CODE = map { $_ => code_only($RAW{$_}) } @FILES;

sub code_only {    # comments and string contents removed, line structure kept
    my $t = shift;
    $t =~ s{/\*.*?\*/}{ "\n" x (() = $& =~ /\n/g) }gse;
    $t =~ s{//[^\n]*}{}g;
    $t =~ s/"[^"\n]*"/""/g;
    $t;
}

# body of the block whose '{' is at $open; returns (full body, direct-level text)
sub block {
    my ($t, $open) = @_;
    my ($depth, $i, $n) = (1, $open + 1, length $t);
    my $flat = '';
    while ($depth && $i < $n) {
        my $c = substr($t, $i, 1);
        if    ($c eq '{') { $flat .= '{' if $depth == 1; $depth++ }
        elsif ($c eq '}') { $depth-- }
        elsif ($depth == 1) { $flat .= $c }
        $i++;
    }
    (substr($t, $open + 1, $i - $open - 2), $flat);
}

sub last_seg { (split /::/, $_[0])[-1] }

# ------------------------------------------------------------------ parse
# %DEF{name} = { kind => part|calc|action, children => [[usage, type]...], super => [...],
#                level => n, file => f, returns => type, many => 0|1 }
# A verb's result: 'return : T' (calc def) or 'out result : T' (action def).
my $RETURN = qr/\b(?:return|out\s+(?:(?:item|attribute|part|ref)\s+)?result)\b/;
my %DEF;
for my $f (@FILES) {
    my $t = $CODE{$f};
    while ($t =~ /\b(?:abstract\s+)?(part|calc|action)\s+def\s+(\w+)\s*(?::>\s*([\w:]+))?\s*([{;])/g) {
        my ($kind, $name, $sup, $op) = ($1, $2, $3, $4);
        my $flat = '';
        if ($op eq '{') { (undef, $flat) = block($t, pos($t) - 1) }
        my @kids;
        if ($kind eq 'part') {
            while ($flat =~ /\bpart\s+(?::>>\s*)?(\w+)\s*(?::>\s*\w+\s*)?:\s*([\w:]+)/g) { my ($u, $ty) = ($1, $2); push @kids, [$u, last_seg($ty)] }
        } else {
            while ($flat =~ /\b$kind\s+(\w+)\s*:\s*([\w:]+)/g) { my ($u, $ty) = ($1, $2); push @kids, [$u, last_seg($ty)] }
        }
        my ($ret, $many) = ('', 0);
        if ($flat =~ /$RETURN\s*(?:\w+\s*)?:\s*([\w:]+)\s*(\[[^\]]*\])?/) {
            $ret = last_seg($1);
            $many = ($2 // '') =~ /\*|\.\.\s*[2-9]|\[\s*[2-9]/ ? 1 : 0;
        }
        my ($lvl) = $flat =~ /\@L(\d)/;
        $DEF{$name} = { kind => $kind, children => \@kids, super => [$sup ? last_seg($sup) : ()],
                        level => $lvl, file => $f, returns => $ret, many => $many };
    }
}

sub children {    # distinct usage names -> type, including inherited and redefined
    my ($name, %seen) = @_;
    my $d = $DEF{$name} or return ();
    return () if $seen{$name}++;
    my (@order, %type);
    for my $s (@{ $d->{super} }) {
        for my $kv (children($s, %seen)) { push @order, $kv->[0] unless exists $type{ $kv->[0] }; $type{ $kv->[0] } = $kv->[1] }
    }
    for my $kv (@{ $d->{children} }) { push @order, $kv->[0] unless exists $type{ $kv->[0] }; $type{ $kv->[0] } = $kv->[1] }
    map { [$_, $type{$_}] } @order;
}

sub level_of {
    my ($name, %seen) = @_;
    my $d = $DEF{$name} or return;
    return if $seen{$name}++;
    return $d->{level} if $d->{level};
    for my $s (@{ $d->{super} }) { my $l = level_of($s, %seen); return $l if $l }
    undef;
}

my %SUBCLASSES;
for my $n (keys %DEF) { push @{ $SUBCLASSES{$_} }, $n for @{ $DEF{$n}{super} } }

# ------------------------------------------------------------------ trees
sub glyphs { $opt{ascii} ? ('|-- ', '`-- ', '|   ', '    ', ' ^') : ("\x{251C}\x{2500}\x{2500} ", "\x{2514}\x{2500}\x{2500} ", "\x{2502}   ", '    ', "  \x{2191}") }

my @ACRONYMS = conf_list('acronyms');
my %SPELL = map { /^(\w+)=(.+)$/ ? ($1 => $2) : () } conf_list('spell');    # spell = EOIR=EO/IR, DCDC=DC-DC
s/=.*// for @ACRONYMS;
my %FRIENDLY = (Real => 'number', Boolean => 'yes/no', Integer => 'count', 'Length Value' => 'distance',
                'Time Value' => 'time', 'Speed Value' => 'speed', 'Geodetic Position' => 'position');

sub plain_name {
    my $n = shift;
    $n =~ s/Def\z// if $n ne 'Def';
    my $alt = join '|', map { quotemeta } @ACRONYMS, keys %SPELL;
    my @tok;
    $n =~ s/($alt)/push @tok, $SPELL{$1} \/\/ $1; chr(0xE000 + $#tok)/ge if $alt ne '';    # protect acronyms
    $n =~ s/(?<=[a-z0-9])(?=[A-Z\x{E000}-\x{E0FF}])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[\x{E000}-\x{E0FF}])(?=[A-Z0-9])/ /g;
    $n =~ s/([\x{E000}-\x{E0FF}])/$tok[ord($1) - 0xE000]/g;
    $n =~ s/\s+/ /g;
    $n =~ s/^ | $//g;
    $n;
}

sub label {
    my ($name, $verbs) = @_;
    my $s = $opt{plain} ? plain_name($name) : $name;
    if ($verbs && $DEF{$name} && $DEF{$name}{returns}) {
        my $r = $opt{plain} ? plain_name($DEF{$name}{returns}) : $DEF{$name}{returns};
        $r = $FRIENDLY{$r} // $r if $opt{plain};
        $s .= "  \x{2192} " . ($DEF{$name}{many} ? "list of $r" : $r) if !$opt{ascii};
        $s .= "  -> " . ($DEF{$name}{many} ? "list of $r" : $r) if $opt{ascii};
    }
    $s;
}

sub tree_lines {    # each definition expanded once; later occurrences marked
    my ($root, $verbs) = @_;
    my ($tee, $elbow, $bar, $sp, $mark) = glyphs();
    my (%expanded, @out);
    my $walk;
    $walk = sub {
        my ($n, $prefix, $last, $is_root) = @_;
        my @kids;
        my %u;
        for my $kv (children($n)) { push @kids, $kv->[1] if $DEF{ $kv->[1] } && !$u{ $kv->[1] }++ }
        my $repeat = $expanded{$n} && @kids;
        push @out, ($is_root ? '' : $prefix . ($last ? $elbow : $tee)) . label($n, $verbs) . ($repeat ? $mark : '');
        return if $repeat;
        $expanded{$n} = 1;
        my $p = $is_root ? '' : $prefix . ($last ? $sp : $bar);
        $walk->($kids[$_], $p, $_ == $#kids, 0) for 0 .. $#kids;
    };
    $walk->($root, '', 1, 1);
    @out;
}

sub depth_walk {    # longest chain and first depth of each definition (variants at same level)
    my $root = shift;
    my (%first, @longest);
    my $walk;
    $walk = sub {
        my ($n, $depth, @path) = @_;
        return if grep { $_ eq $n } @path;
        push @path, $n;
        $first{$n} = $depth if !defined $first{$n} || $depth < $first{$n};
        @longest = @path if @path > @longest;
        $walk->($_, $depth, @path[0 .. $#path - 1]) for @{ $SUBCLASSES{$n} || [] };
        $walk->($_->[1], $depth + 1, @path) for grep { $DEF{ $_->[1] } } children($n);
    };
    $walk->($root, 1);
    (\%first, \@longest);
}

# ------------------------------------------------------------------ outline rule
my $MEMBER_KW = qr/^\s*(?:(?:abstract|individual|private|public|protected)\s+)*(?:part|item|port|interface|attribute|enum|action|state|calc|constraint|requirement|verification|analysis|use\s+case|metadata|package|view|viewpoint|allocation|satisfy|allocate|concern|occurrence|connection|flow|alias)\b/m;

sub outline {
    my @bad;
    my $check = sub { my ($where, $what, $n) = @_; push @bad, [$where, $what, $n] if $n && ($n < $MIN || $n > $MAX) };
    for my $n (sort keys %DEF) {
        my $what = $DEF{$n}{kind} eq 'part' ? "part def $n: parts" : "$DEF{$n}{kind} def $n: sub-functions";
        $check->(rel($DEF{$n}{file}), $what, scalar(my @c = children($n)));
    }
    my @rules = (
        [qr/\bpackage\s+('[^']+'|\w+)\s*\{/, 'package %s: members', sub { scalar(() = $_[0] =~ /$MEMBER_KW/g) }],
        [qr/\brequirement\s+(?:<'[^']+'>\s*)?(\w+)[^{;]*\{/, 'requirement %s: sub-requirements', sub { scalar(() = $_[0] =~ /^\s*requirement\b/mg) }],
        [qr/\bstate\s+def\s+(\w+)[^{;]*\{/, 'state def %s: states', sub { scalar(() = $_[0] =~ /^\s*state\b/mg) }],
        [qr/\benum\s+def\s+(\w+)[^{;]*\{/, 'enum def %s: literals', sub { scalar(() = $_[0] =~ /\benum\s+'?\w/g) }],
    );
    for my $f (@FILES) {
        my $t = $CODE{$f};
        for my $r (@rules) {
            my ($re, $label, $count) = @$r;
            while ($t =~ /$re/g) {
                my $name = $1;
                my (undef, $flat) = block($t, pos($t) - 1);
                $check->(rel($f), sprintf($label, $name), $count->($flat));
            }
        }
    }
    my @dirs = ($MODEL);
    File::Find::find({ no_chdir => 1, wanted => sub { push @dirs, $_ if -d $_ && $_ ne $MODEL } }, $MODEL);
    for my $d (sort @dirs) {
        opendir my $dh, $d or next;
        my @e = grep { !/^\./ } readdir $dh;
        closedir $dh;
        $check->(rel($d) . '/', 'directory entries', scalar @e);
    }
    @bad;
}

sub tag_mismatches {
    my ($first) = depth_walk($NOUN_ROOT);
    grep { my $l = level_of($_->[0]); defined $l && $l != $_->[1] } map { [$_, $first->{$_}] } sort keys %$first;
}

# ------------------------------------------------------------------ commands
sub cmd_stats {
    my ($code, $comment, $blank) = (0, 0, 0);
    for my $f (@FILES) {
        my $in = 0;
        for (split /\n/, $RAW{$f}) {
            my $s = s/^\s+|\s+$//gr;
            if    ($s eq '') { $blank++ }
            elsif ($in || $s =~ m{^(/\*|//|\*|doc /\*)}) { $comment++; $in = 1 if $s =~ m{/\*} && $s !~ m{\*/}; $in = 0 if $s =~ m{\*/} }
            else { $code++; $in = 1 if $s =~ m{/\*} && $s !~ m{\*/} }
        }
    }
    my $count = sub { my $re = shift; my $n = 0; $n += () = $CODE{$_} =~ /$re/g for @FILES; $n };
    my ($maxpkg, $maxbrace, $where) = (0, 0, '');
    for my $f (@FILES) {
        my @stack;
        my $t = $CODE{$f};
        while ($t =~ /(\bpackage\s+(?:'[^']+'|\w+)\s*\{)|\{|\}/g) {
            if ($& eq '}') { pop @stack } else { push @stack, $1 ? 1 : 0 }
            my $pk = grep { $_ } @stack;
            ($maxpkg, $where) = ($pk, rel($f)) if $pk > $maxpkg;
            $maxbrace = @stack if @stack > $maxbrace;
        }
    }
    printf "== Size ==\nfiles                     %d\ntotal lines               %d\n  code (SLOC)             %d\n  comment / doc           %d\n  blank                   %d\n",
        scalar @FILES, $code + $comment + $blank, $code, $comment, $blank;
    print "\n== Elements ==\n";
    for (['packages', qr/\bpackage\s+\w+/], ['part defs (nouns)', qr/\bpart\s+def\b/], ['part usages', qr/\bpart\s+(?!def\b)/],
         ['calc defs (verbs)', qr/\bcalc\s+def\b/], ['calc usages', qr/\bcalc\s+(?!def\b)\w+\s*:/],
         ['action defs (verbs)', qr/\baction\s+def\b/], ['action usages', qr/\baction\s+(?!def\b)\w+\s*:/],
         ['item defs', qr/\bitem\s+def\b/], ['attribute defs', qr/\battribute\s+def\b/], ['port defs', qr/\bport\s+def\b/],
         ['interface defs', qr/\binterface\s+def\b/], ['enum defs', qr/\benum\s+def\b/], ['state defs', qr/\bstate\s+def\b/],
         ['requirements', qr/\brequirement\s+(?!def\b)(?:<'[^']*'>\s*)?\w+\s*[{:;]/], ['verification defs', qr/\bverification\s+def\b/],
         ['analysis defs', qr/\banalysis\s+def\b/], ['use case defs', qr/\buse\s+case\s+def\b/], ['satisfy', qr/\bsatisfy\s+[\w:.]+\s+by\b/],
         ['verify', qr/\bverify\s+[\w:.]+\s*;/], ['allocate', qr/\ballocate\s+\w/], ['interface usages', qr/\binterface\s+(?!def\b)\w+/],
         ['metadata usages', qr/(?:\bmetadata\s+(?!def\b)\w+\s*:|\@[A-Za-z_]\w*)/]) {
        printf "%-26s%d\n", $_->[0], $count->($_->[1]);
    }
    printf "\n== Nesting ==\nmax package nesting       %d   (%s)\nmax brace nesting         %d\n", $maxpkg, $where, $maxbrace;
    for ([$NOUN_ROOT, 'Nouns (parts)'], [$VERB_ROOT, 'Verbs (functions)']) {
        my ($root, $title) = @$_;
        my ($first, $longest) = depth_walk($root);
        my %per;
        $per{ $first->{$_} }++ for keys %$first;
        printf "\n== %s from %s ==\ndepth                     %d levels\nlongest chain             %s\ndefinitions per level     %s\n",
            $title, $root, scalar @$longest, join(' > ', @$longest), join(', ', map { "L$_=$per{$_}" } sort { $a <=> $b } keys %per);
    }
    return report();
}

sub report {
    my @mm = tag_mismatches();
    printf "\n== Level tags ==\n\@L tag mismatches         %d\n", scalar @mm;
    printf "  %s: tagged L%d, first reached at L%d\n", $_->[0], level_of($_->[0]), $_->[1] for @mm;
    my @bad = outline();
    printf "\n== Outline (%d..%d children per parent) ==\nviolations                %d\n", $MIN, $MAX, scalar @bad;
    printf "  %3d  %s  (%s)\n", $_->[2], $_->[1], $_->[0] for sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @bad;
    (@mm || @bad) ? 1 : 0;
}

sub write_doc {
    my ($path, $title, $intro, @lines) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "cannot write $path: $!\n";
    print {$fh} "<!-- Generated by: $ME docs -- do not edit by hand. -->\n\n# $title\n\n$intro\n\n```\n", join("\n", @lines), "\n```\n";
    close $fh;
    print 'wrote ', rel($path), ' (', scalar @lines, " lines)\n";
}

sub cmd_docs {
    my $docs = File::Spec->catdir($ROOT, 'docs');
    mkdir $docs unless -d $docs;
    local $opt{plain} = 1;
    local $opt{ascii} = 0;
    my ($nfirst, $nlong) = depth_walk($NOUN_ROOT);
    my ($vfirst, $vlong) = depth_walk($VERB_ROOT);
    write_doc(File::Spec->catfile($docs, 'Nouns.md'), "$TITLE — the Nouns (what the system is made of)",
        "Every thing in the $TITLE enterprise, from the whole enterprise (top)\n"
        . "down to its smallest modeled parts, " . scalar(@$nlong) . " levels deep. Each item is made of the items indented beneath it;\n"
        . "no item has fewer than 2 or more than 9 parts. \x{2191} marks an item already broken down earlier in the tree.",
        tree_lines($NOUN_ROOT, 0));
    my @top = map { lc words($_->[0]) } children($VERB_ROOT);
    write_doc(File::Spec->catfile($docs, 'Verbs.md'), "$TITLE — the Verbs (what the system does)",
        "Everything the enterprise does, as functions: each takes information in and\n"
        . "hands one result on (\x{2192}). A function is made of the functions indented beneath it, "
        . scalar(@$vlong) . " levels deep,\nwith 2 to 9 steps at each level. The top level: " . join(', ', @top) . '.',
        tree_lines($VERB_ROOT, 1));
    cmd_idef0();
}

# ------------------------------------------------------------------ IDEF0
# The verb tree rendered as an IDEF0 model for agile's tools/idef0/idef0.pl:
#   activity   = a calc def or action def (function), in composition order
#   input  (i) = a parameter, named after the flow wired into it
#   control(c) = a parameter whose type is a rule/order (control_types in sysml.conf) or that has a
#                default value (a policy constant such as a threshold)
#   output (o) = the function's result
#   mechanism  = the part the function is allocated to (inherited from the parent)
my %CONTROL_TYPES = map { $_ => 1 } conf_list('control_types');
my %GENERIC_TYPES = map { $_ => 1 } qw(Real Boolean Integer String TimeValue LengthValue SpeedValue GeodeticPosition);
my (%STEP_LABEL, @STEP_LETTERS);    # steps = usage:Letter:Label, ...
for (conf_list('steps')) { my ($u, $l, $label) = split /\s*:\s*/, $_, 3; push @STEP_LETTERS, $u => $l; $STEP_LABEL{$u} = $label if defined $label }

my %VERB;    # name => { params => [[name, type, many, default]], uses => [[usage, type, {param => expr}]], doc, return_expr }
sub parse_verbs {
    return if %VERB;
    for my $f (@FILES) {
        my ($t, $raw) = ($CODE{$f}, $RAW{$f});
        while ($t =~ /\b(calc|action)\s+def\s+(\w+)[^{;]*\{/g) {
            my ($kind, $name) = ($1, $2);
            my ($body, $flat) = block($t, pos($t) - 1);
            my @params;
            while ($flat =~ /(?:^|[;}]|\bdoc\b)\s*in\s+(?:(?:item|attribute|part|ref)\s+)?(\w+)\s*:\s*([\w:]+)\s*(\[[^\]]*\])?\s*(default)?/mg) {   # one-line defs too
                my ($pn, $pt, $mult, $def) = ($1, $2, $3 // '', $4);
                push @params, [$pn, last_seg($pt), ($mult =~ /\*|\.\.\s*[2-9]|\[\s*[2-9]/ ? 1 : 0), ($def ? 1 : 0)];
            }
            my @uses;
            while ($body =~ /\b$kind\s+(\w+)\s*:\s*([\w:]+)\s*(\{|;)/g) {
                my ($u, $ty, $op) = ($1, last_seg($2), $3);
                my %bind;
                if ($op eq '{') {
                    my ($b) = block($body, pos($body) - 1);
                    $bind{$1} = $2 while $b =~ /\bin\s+(\w+)\s*=\s*([^;]+);/g;
                }
                push @uses, [$u, $ty, \%bind];
            }
            my $doc = '';
            if ($raw =~ /\b$kind\s+def\s+\Q$name\E\b/g) {
                my $head = substr($raw, pos($raw), 1500);
                $head =~ s/\n\s*(?:in|out|return|calc|action)\b.*//s;
                ($doc) = $head =~ m{doc\s*/\*\s*(.*?)\s*\*/}s;
                $doc = join ' ', map { s/^\s*\*?\s*//r } split /\n/, $doc // '';
                pos($raw) = 0;
            }
            my ($rexpr) = $flat =~ /($RETURN[^;]*;)/;
            $VERB{$name} = { params => \@params, uses => \@uses, doc => $doc, return_expr => $rexpr };
        }
    }
}

sub words { my $s = join ' ', map { ucfirst } split / /, plain_name(ucfirst shift); $s }

sub plural {
    my $s = shift;
    return $s =~ s/is\z/es/r if $s =~ /is\z/;
    return $s =~ s/y\z/ies/r if $s =~ /[^aeiou]y\z/;
    return $s if $s =~ /s\z/;
    "${s}s";
}

sub type_flow { my ($type, $many) = @_; my $n = plain_name($type); $many ? plural($n) : $n }

sub out_name {    # name of the flow a usage produces
    my ($usage, $type) = @_;
    my $d = $DEF{$type} or return words($usage);
    my ($rt, $many) = ($d->{returns}, $d->{many});
    return words($usage) if $GENERIC_TYPES{$rt} || $rt eq '';
    my @ins = @{ $VERB{$type}{params} };
    return words($usage) . ' ' . type_flow($rt, $many) if grep { $_->[1] eq $rt && $_->[2] == $many } @ins;   # transform
    return words($usage) if grep { $_->[1] eq $rt } @ins;                                                       # pick one of many
    return words($usage) . ' ' . type_flow($rt, $many) if $opt{tuple}{$usage};                                  # one of several parallel results
    type_flow($rt, $many);
}

sub target_name {    # plain name of the part at the end of an allocation path
    my @seg = split /\./, shift;
    shift @seg if @seg && !grep { $_->[0] eq $seg[0] } children($NOUN_ROOT);    # the context's name for the enterprise
    my $type = $NOUN_ROOT;
    for my $s (@seg) {
        my ($kv) = grep { $_->[0] eq $s } children($type);
        return words($s) unless $kv;
        $type = $kv->[1];
    }
    plain_name($type);
}

sub allocations {
    my %m;
    return \%m if $ALLOC_PREFIX eq '';
    for my $f (@FILES) {
        push @{ $m{$1} }, target_name($2) while $CODE{$f} =~ /\ballocate\s+\Q$ALLOC_PREFIX\E\.?([\w.]*)\s+to\s+([\w.]+)\s*;/g;
    }
    \%m;
}

sub sibling_names {    # flow names produced by the child functions of a verb
    my $type = shift;
    my $v = $VERB{$type};
    my ($ret) = grep { $_ } map { /$RETURN[^=]*=\s*\(([^)]*)\)/ ? $1 : () } ($v->{return_expr} // '');
    local $opt{tuple} = { map { $_ => 1 } ($ret // '') =~ /(\w+)\.result/g };
    map { $_->[0] => out_name($_->[0], $_->[1]) } @{ $v->{uses} };
}

sub spine {    # deepest composition path as [node id, name] pairs
    my ($type, $node) = @_;
    my @best;
    my $i = 0;
    for my $u (@{ $VERB{$type}{uses} || [] }) {
        $i++;
        my @p = spine($u->[1], "$node$i");
        @best = @p if @p > @best;
    }
    ([$node, plain_name($type)], @best);
}

sub wrap_doc { my ($text, $pre, $w) = @_; my (@l, $cur); for (split ' ', $text) { if (defined $cur && length($cur) + length($_) + 1 > $w) { push @l, $cur; undef $cur } $cur = defined $cur ? "$cur $_" : $_ } push @l, $cur if defined $cur; map { "$pre$_" } @l }

my %STEP_LETTER = @STEP_LETTERS;
sub step_letters {    # every top-level step gets a letter: from 'steps', else its first free capital
    parse_verbs();
    my %used = map { $_ => 1 } values(%STEP_LETTER), $MODEL_LETTER;
    for my $u (map { $_->[0] } @{ $VERB{$VERB_ROOT}{uses} || [] }) {
        next if $STEP_LETTER{$u};
        my ($l) = grep { !$used{$_} } (map { uc } split //, $u), 'A' .. 'Z';
        $STEP_LETTER{$u} = $l;
        $used{$l} = 1;
    }
}

sub activity_ports {    # IDEF0 ports of one function instance, named in its parent's context
    my ($type, $bind, $parent_flows, $siblings) = @_;
    my $v = $VERB{$type} or return ([], {});
    my (@ports, %seen, %flows);
    for my $p (@{ $v->{params} }) {
        my ($pn, $pt, $many, $def) = @$p;
        my $expr = $bind->{$pn};
        my @names;
        if (defined $expr) {
            my $e = $expr;
            while ($e =~ s/\b(?:\w+::)?(\w+)\.result\b//) { push @names, $siblings->{$1} if $siblings->{$1} }
            while ($e =~ /\b(?:\w+::)?(\w+)(?:\.(\w+))?/g) {
                my ($id, $field) = ($1, $2);
                next unless exists $parent_flows->{$id};
                my $pf = $parent_flows->{$id};
                push @names, ref $pf ? ($pf->{ $field // '' } // ()) : $pf;
            }
        } else {
            push @names, $def ? words($pn) : type_flow($pt, $many);
        }
        my $tag = ($def && !defined $expr) || $CONTROL_TYPES{$pt} ? 'c' : 'i';
        $flows{$pn} = $names[0] // type_flow($pt, $many);
        for my $n (@names) { push @ports, [$tag, $n] unless $seen{"$tag$n"}++ }
    }
    (\@ports, \%flows);
}

sub port_lines {
    my ($pad, $ports, $out, $mech, $links) = @_;
    $links //= {};
    my $l = sub { my $k = shift; exists $links->{$k} ? " $links->{$k}" : '' };
    ((map { "${pad}i# $_->[1]" . $l->("in $_->[1]") } grep { $_->[0] eq 'i' } @$ports),
     (map { "${pad}c# $_->[1]" . $l->("in $_->[1]") } grep { $_->[0] eq 'c' } @$ports),
     "${pad}o# $out" . $l->("out $out"),
     (map { "${pad}m# $_" } @$mech));
}

sub doc_lines {
    my ($pad, $v) = @_;
    wrap_doc($v->{doc} // '', "$pad## ", 88);
}

sub idef0_lines {    # one activity (usage) and its descendants, indented under its model
    my ($usage, $type, $bind, $parent_flows, $siblings, $path, $mech, $indent, $links) = @_;
    my $v = $VERB{$type} or return ();
    my $pad = '  ' x $indent;
    my @mech = @{ allocations()->{$path} || $mech };
    my ($ports, $flows) = activity_ports($type, $bind, $parent_flows, $siblings);
    my @out = ("${pad}a# " . plain_name($type), doc_lines("$pad  ", $v),
               port_lines("$pad  ", $ports, $siblings->{$usage} // out_name($usage, $type), \@mech, $links));
    my %sib = sibling_names($type);
    push @out, idef0_lines($_->[0], $_->[1], $_->[2], $flows, \%sib, "$path.$_->[0]", \@mech, $indent + 1) for @{ $v->{uses} };
    @out;
}

sub cmd_idef0 {
    parse_verbs();
    step_letters();
    my $dir = File::Spec->catdir($ROOT, 'docs', 'idef0');
    mkdir File::Spec->catdir($ROOT, 'docs');
    mkdir $dir;
    my $md = File::Spec->catfile($dir, "$IDEF0_NAME.md");
    my $root = $VERB{$VERB_ROOT} or do { print STDERR "idef0: no calc def or action def named '$VERB_ROOT' (verb_root in sysml.conf)\n"; return 1 };

    # root context: the fields of the root's input record (an item def) are the external flows
    my ($in_type) = map { $_->[1] } @{ $root->{params} };
    my %rec;
    for my $f (@FILES) {
        next unless $CODE{$f} =~ /\bitem\s+def\s+\Q$in_type\E\s*\{/g;
        my (undef, $flat) = block($CODE{$f}, pos($CODE{$f}) - 1);
        while ($flat =~ /\b(?:item|attribute)\s+(\w+)\s*:\s*([\w:]+)\s*(\[[^\]]*\])?/g) {
            my ($fname, $ftype, $mult) = ($1, $2, $3 // '');
            $rec{$fname} = type_flow(last_seg($ftype), ($mult =~ /\*/ ? 1 : 0));
        }
    }
    my %root_flows = map { $_->[0] => \%rec } @{ $root->{params} };
    my %root_sib = sibling_names($VERB_ROOT);
    my $alloc = allocations();
    my @steps = @{ $root->{uses} };

    # model-level (A-0) ports of every step, and which step feeds each flow
    my (%ports, %flows, %producer_of);
    for my $u (@steps) {
        my ($un, $ut, $b) = @$u;
        ($ports{$un}, $flows{$un}) = activity_ports($ut, $b, \%root_flows, \%root_sib);
        $producer_of{ $root_sib{$un} } = $un;
    }
    # hand-offs between steps are linked at level-1 activities (what idef0-backlog.pl turns into
    # interface tasks): the child that produces step A's result -> the children of step B that use it
    my %step = map { $_->[0] => $_ } @steps;
    my %alinks;    # alinks{step}{child usage}{"in Flow" | "out Flow"} = link text
    my %first_consumer;
    for my $u (@steps) {
        my ($bn, $bt, $bb) = @$u;
        for my $p (@{ $VERB{$bt}{params} }) {
            my $pn = $p->[0];
            my ($an) = grep { $step{$_} && $_ ne $bn } (($bb->{$pn} // '') =~ /\b(\w+)\.result\b/g);
            next unless $an;
            my $at = $step{$an}[1];
            my ($prod) = ($VERB{$at}{return_expr} // '') =~ /\b(\w+)\.result\b/;
            next unless $prod;
            my ($pu) = grep { $_->[0] eq $prod } @{ $VERB{$at}{uses} };
            my $flow = $root_sib{$an};
            for my $c (@{ $VERB{$bt}{uses} }) {
                next unless grep { /(?<![\w.])(?:\w+::)?\Q$pn\E\b(?!\.result)/ } values %{ $c->[2] };
                $alinks{$bn}{ $c->[0] }{"in $flow"} = "< $STEP_LETTER{$an}|" . plain_name($pu->[1]) . "|$flow";
                $first_consumer{$an} //= [$bn, $c];
            }
            my ($fb, $fc) = @{ $first_consumer{$an} || [] };
            $alinks{$an}{$prod}{"out $flow"} //= "> $STEP_LETTER{$fb}|" . plain_name($fc->[1]) . "|$flow" if $fc;
        }
    }
    my @md;
    my $root_file = rel_root($DEF{$VERB_ROOT}{file});
    push @md, "<!-- Generated by: $ME idef0 -- do not edit by hand.",
        "     Source of truth: the verb tree under $VERB_ROOT ($root_file) and its allocate statements.",
        "     Build (from the agile kit root):",
        "             perl tools/idef0/idef0.pl lint $IDEF0_NAME.md",
        "             perl tools/idef0/idef0.pl html $IDEF0_NAME.md > plates.html",
        "             perl tools/idef0/idef0.pl links $IDEF0_NAME.md > INTERFACES -->", '',
        "# $TITLE " . words($IDEF0_NAME) . ' — IDEF0 model set', '',
        "The $TITLE verbs drawn as IDEF0 plates: one model per top-level step of $VERB_ROOT, so each step",
        'can be owned by one team. Every box is a function from `model/`; a box is decomposed',
        'on its own plate when the function is composed of smaller functions (2 to 9 per plate).', '',
        '- **Inputs** (left): the data a function transforms, named after the flow wired into it.',
        '- **Controls** (top): orders, authorizations and rules (the `control_types` of `sysml.conf`),',
        '  plus policy constants (parameters with default values, such as thresholds).',
        '- **Output** (right): the one result the function returns.',
        '- **Mechanism** (bottom): the part (noun) that performs the function, from the model\'s',
        "  `allocate` statements; a function without its own allocation inherits its parent's.",
        '- **Model line** (`t`): the step\'s own inputs, controls and output (its A-0 context). Hand-offs',
        '  between steps are cross-model links (`<` comes from, `>` goes to), listed in `INTERFACES`.', '';
    for my $u (@steps) {
        my ($un, $ut, $b) = @$u;
        my $v = $VERB{$ut};
        my $L = $STEP_LETTER{$un} // uc substr($un, 0, 1);
        my $label = $STEP_LABEL{$un} // words($un);
        my $title = $label eq plain_name($ut) ? $label : "$label — " . plain_name($ut);
        my @mech = @{ $alloc->{$un} || $alloc->{''} || [plain_name($NOUN_ROOT)] };
        my @in  = map { my $f = $_->[1]; my ($src) = grep { $root_sib{$_} eq $f && $_ ne $un } map { $_->[0] } @steps;
                        $f . ($src ? " (from $STEP_LETTER{$src})" : '') } @{ $ports{$un} };
        my @to = sort grep { $_ ne $un && grep { $_->[1] eq $root_sib{$un} } @{ $ports{$_} } } map { $_->[0] } @steps;
        push @md, "## Model $L — $title", '';
        push @md, wrap_doc($v->{doc}, '', 88), '' if $v->{doc};
        push @md, 'SPINE: ' . join(' -> ', map { "$_->[0] $_->[1]" } grep { $_->[0] ne $L } spine($ut, $L)) . '.', '';
        push @md, 'Team: ' . ($STEP_LABEL{$un} // words($un)) . '. Performed by: ' . join(', ', @mech) . '.', '';
        push @md, 'Interfaces: takes ' . join('; ', @in) . '. Hands on ' . $root_sib{$un}
            . (@to ? ' to ' . join(', ', map { "$STEP_LETTER{$_} " . ($STEP_LABEL{$_} // $_) } @to) : '') . '.', '';
        my %sib = sibling_names($ut);
        push @md, '```idef0', "t$L $title", doc_lines('', $v),
            port_lines('  ', $ports{$un}, $root_sib{$un}, \@mech);
        push @md, idef0_lines($_->[0], $_->[1], $_->[2], $flows{$un}, \%sib, "$un.$_->[0]", \@mech, 1, $alinks{$un}{ $_->[0] })
            for @{ $v->{uses} };
        push @md, '```', '';
    }
    open my $fh, '>:encoding(UTF-8)', $md or die "cannot write $md: $!\n";
    print {$fh} join("\n", @md);
    close $fh;
    print 'wrote ', rel($md), "\n";

    my $tool = File::Spec->catfile($KIT, 'tools', 'idef0', 'idef0.pl');
    my $q = sub { '"' . $_[0] . '"' };
    my $run = sub { my @a = @_; my $cmd = join ' ', map { $q->($_) } $^X, $tool, @a; scalar `$cmd` };
    my $lint = `${\ $q->($^X)} ${\ $q->($tool)} lint ${\ $q->($md)} 2>&1`;
    print $lint;
    my $status = $? >> 8;
    my $save = sub {
        my ($path, $text) = @_;
        open my $oh, '>:raw', $path or die "cannot write $path: $!\n";
        print {$oh} $text;
        close $oh;
        print 'wrote ', rel($path), "\n";
    };
    $save->(File::Spec->catfile($dir, 'plates.html'), $run->('html', $md));
    $save->(File::Spec->catfile($dir, 'INTERFACES'), $run->('links', $md));
    my $svg = File::Spec->catdir($dir, 'svg');
    mkdir $svg;
    unlink glob(File::Spec->catfile($svg, '*.svg'));
    for my $u (@steps) {
        my $L = $STEP_LETTER{ $u->[0] };
        $save->(File::Spec->catfile($svg, "plate-${L}0.svg"), $run->('svg', "${L}0", $md));
    }
    unlink File::Spec->catfile($dir, "plate-${MODEL_LETTER}0.svg");
    $status;
}

# ------------------------------------------------------------------ shared helpers for editing tools
sub mask {    # same length as the input; comments and string contents blanked, so offsets match RAW
    my $t = shift;
    $t =~ s{/\*.*?\*/}{ $& =~ s/[^\n]/ /gr }gse;
    $t =~ s{//[^\n]*}{ ' ' x length $& }ge;
    $t =~ s{"[^"\n]*"}{ '"' . (' ' x (length($&) - 2)) . '"' }ge;
    $t;
}
my %MASK = map { $_ => mask($RAW{$_}) } @FILES;

sub line_col {
    my ($text, $pos) = @_;
    my $before = substr($text, 0, $pos);
    my $line = 1 + ($before =~ tr/\n//);
    my $col = $pos - (rindex($before, "\n") + 1) + 1;
    ($line, $col);
}

sub close_of {    # offset of the '}' matching the '{' at $open
    my ($t, $open) = @_;
    my ($depth, $i) = (1, $open + 1);
    while ($depth && $i < length $t) { my $c = substr($t, $i++, 1); $depth++ if $c eq '{'; $depth-- if $c eq '}' }
    $i - 1;
}

sub write_file {    # keeps the file's original line endings
    my ($f, $text) = @_;
    open my $in, '<:raw', $f or die "cannot read $f: $!\n";
    my $orig = do { local $/; <$in> };
    close $in;
    $text =~ s/\n/\r\n/g if $orig =~ /\r\n/;
    open my $out, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n";
    print {$out} $text;
    close $out;
}

sub diag { my ($f, $pos, $sev, $msg) = @_; my ($l, $c) = line_col($RAW{$f}, $pos); sprintf "%s:%d:%d: %s: %s", rel($f), $l, $c, $sev, $msg }

my %LIBRARY;
sub library_names {
    return \%LIBRARY if %LIBRARY;
    my $f = File::Spec->catfile($TOOLS, 'sysml-library-names.txt');
    if (open my $fh, '<:encoding(UTF-8)', $f) { while (<$fh>) { s/\s+\z//; next if /^#/ || $_ eq ''; s/^'|'$//g; $LIBRARY{$_} = 1 } }
    \%LIBRARY;
}

# ------------------------------------------------------------------ lint
my %KEYWORD = map { $_ => 1 } qw(about abstract accept action actor after alias all allocate allocation analysis and as
    assert assign assume at attribute bind binding by calc case comment concern connect connection constant constraint
    crosses decide def default defined dependency derived do doc else end entry enum event exhibit exit expose false
    filter first flow for fork frame from hastype if implies import in include individual inout interface istype item
    join language library locale loop merge message meta metadata new nonunique not null objective occurrence of or
    ordered out package parallel part perform port private protected public readonly redefines ref references render
    rendering rep require requirement return satisfy send snapshot specializes stakeholder standard state subject
    subsets succession terminate then this timeslice to transition true until use variant variation verification
    verify via view viewpoint when while xor);

sub grammar_diags {    # syntax errors from the parser generated from the official SysML v2 grammar
    require SysML::Grammar; require SysML::Lexer; require SysML::Parser; require Prelude;
    my $bnf = File::Spec->catdir($TOOLS, 'vendor', 'sysml-v2-release', 'bnf');
    my $g = SysML::Grammar::load('sysml', $bnf);
    return ("tools/sysml/sysml.pl: error: cannot load grammar: $g->[1]") if Prelude::isErr($g);
    $g = Prelude::unwrap($g);
    my ($scan, $recognize) = (SysML::Lexer::scanner($g), SysML::Parser::recognizer($g));
    map {
        my $f = $_;
        my $toks = $scan->($RAW{$f});
        if (Prelude::isErr($toks)) { (diag($f, $toks->[1][0], 'error', $toks->[1][1])) }
        else {
            my $r = $recognize->(Prelude::unwrap($toks));
            if (Prelude::isOk($r)) { () }
            else {
                my $e = $r->[1];
                my @exp = @{ $e->{expected} };
                my $exp = @exp > 6 ? join(', ', @exp[0 .. 5]) . ', ...' : join(', ', @exp);
                (diag($f, $e->{found} ? $e->{found}[2] : length $RAW{$f}, 'error',
                      'syntax: ' . ($e->{found} ? "unexpected '$e->{found}[1]'" : 'unexpected end of file')
                      . (@exp ? "; expected $exp" : '')));
            }
        }
    } @FILES;
}

sub cmd_lint {
    parse_verbs();
    my $lib = library_names();
    my (%declared);
    my @diags = grep({ $_ eq '--no-grammar' } @args) ? () : grammar_diags();
    for my $f (@FILES) {
        my $t = $MASK{$f};
        $declared{$1} = 1 while $t =~ /\b(?:def|package)\s+(?:<[^>]*>\s*)?(\w+)/g;
        $declared{$1} = 1 while $t =~ /\battribute\s+<[^>]*>\s*(\w+)/g;
    }
    my $known = sub { my $n = (split /::/, shift)[-1]; $n =~ s/^'|'$//g; $declared{$n} || $lib->{$n} };
    for my $f (@FILES) {
        my $t = $MASK{$f};
        # 1. balanced brackets
        my @stack;
        while ($t =~ /([{}()\[\]])/g) {
            my ($c, $p) = ($1, pos($t) - 1);
            if ($c =~ /[{(\[]/) { push @stack, [$c, $p]; next }
            my $want = { '}' => '{', ')' => '(', ']' => '[' }->{$c};
            if (!@stack || $stack[-1][0] ne $want) { push @diags, diag($f, $p, 'error', "unmatched '$c'"); last }
            pop @stack;
        }
        push @diags, diag($f, $_->[1], 'error', "'$_->[0]' is never closed") for @stack;
        # 2. reserved words used as names
        while ($t =~ /\b(?:part|item|attribute|port|calc|action|state|requirement|interface|connection|allocation|view|viewpoint|metadata|occurrence|constraint|analysis|verification|package|enum|in|out|inout|then|def|ref)\s+(?:<'[^']*'>\s*)?([A-Za-z_]\w*)\s*[:;{=\[]/g) {
            push @diags, diag($f, $-[1], 'error', "'$1' is a SysML keyword and cannot be a name (rename it, or quote it as '$1')") if $KEYWORD{$1};
        }
        # 3. unresolved types and specializations
        while ($t =~ /(?<!:):(?![:>=])\s*~?((?:[A-Za-z_]\w*|'[^']+')(?:::(?:[A-Za-z_]\w*|'[^']+'))*)/g) {
            push @diags, diag($f, $-[1], 'error', "unresolved type '$1'") unless $known->($1);
        }
        while ($t =~ /\bdef\s+\w+\s*:>\s*([\w:]+)/g) {
            push @diags, diag($f, $-[1], 'error', "unresolved supertype '$1'") unless $known->($1);
        }
        # 4. imports
        while ($t =~ /\bimport\s+((?:[\w']+)(?:::[\w']+)*?)(?:::\*\*?)?\s*;/g) {
            my ($imp, $at) = ($1, $-[1]);
            for my $seg (split /::/, $imp) {
                next if $known->($seg);
                push @diags, diag($f, $at, 'error', "import of unknown package '$seg'");
                last;
            }
        }
        # 5. duplicate member names in a package
        while ($t =~ /\bpackage\s+(\w+)\s*\{/g) {
            my ($pkg, $open) = ($1, pos($t) - 1);
            my (undef, $flat) = block($t, $open);
            my %seen;
            while ($flat =~ /^\s*(?:(?:abstract|individual|private|public)\s+)*(?:part|item|port|interface|attribute|enum|action|state|calc|constraint|requirement|verification|analysis|metadata|package|view|viewpoint|allocation|occurrence|connection)\s+(?:def\s+)?(?:<'[^']*'>\s*)?(\w+)/mg) {
                push @diags, diag($f, $open, 'error', "package $pkg: duplicate member '$1'") if $seen{$1}++ && $1 ne 'def';
            }
        }
        # 6. bindings that silently refer to the child's own parameter
        while ($t =~ /\b(?:calc|action)\s+(\w+)\s*:\s*([\w:]+)\s*\{/g) {
            my ($u, $ty, $open) = ($1, last_seg($2), pos($t) - 1);
            my $v = $VERB{$ty} or next;
            my %own = map { $_->[0] => 1 } @{ $v->{params} };
            my $body = substr($t, $open, close_of($t, $open) - $open);
            while ($body =~ /\bin\s+(\w+)\s*=\s*([^;]+);/g) {
                my ($pn, $expr, $at) = ($1, $2, $open + $-[2]);
                while ($expr =~ /(?<![\w.:])([A-Za-z_]\w*)\b(?!\s*::)/g) {
                    next unless $own{$1};
                    push @diags, diag($f, $at, 'warning',
                        "in '$u : $ty', '$1' in the binding of '$pn' means ${ty}'s own parameter '$1'; qualify it (Parent::$1)");
                }
            }
        }
    }
    my %u;
    @diags = grep { !$u{$_}++ } @diags;
    print "$_\n" for @diags;
    my $errors = grep { /: error: / } @diags;
    my $warnings = grep { /: warning: / } @diags;
    printf "lint: %d file(s), %d error(s), %d warning(s)\n", scalar @FILES, $errors, $warnings;
    # the machine-readable line the status-metrics collector reads (lint_cmd): elements as its PAT counts them
    my $elements = 0;
    $elements += () = $RAW{$_} =~ /^\s*(?:part|port|interface|connection|action|item)(?: def)?\b/mg for @FILES;
    printf "elements=%d errors=%d warnings=%d\n", $elements, $errors, $warnings;
    $errors ? 1 : 0;
}

# ------------------------------------------------------------------ validate (optional: needs Java)
sub find_in_path {
    my @names = @_;
    for my $d (File::Spec->path) { for my $n (@names) { my $p = File::Spec->catfile($d, $n); return $p if -f $p && -x _ } }
    undef;
}

sub cmd_validate {
    require IPC::Open3;
    my $java = $ENV{JAVA_HOME} ? File::Spec->catfile($ENV{JAVA_HOME}, 'bin', $^O =~ /MSWin/ ? 'java.exe' : 'java') : undef;
    $java = find_in_path('java', 'java.exe') unless $java && -f $java;
    my @jar_dirs = grep { defined && -d } ($ENV{SYSML_HOME}, $TOOLS,
        File::Spec->catdir($ENV{HOME} // '', 'miniconda3', 'share', 'jupyter', 'kernels', 'sysml'));
    my ($jar) = $ENV{SYSML_JAR} // (map { glob(File::Spec->catfile($_, '*sysml*all.jar')) } @jar_dirs);
    my $lib = $ENV{SYSML_LIBRARY} // ($jar ? File::Spec->catdir(dirname($jar), 'sysml.library') : undef);
    $lib = File::Spec->catdir($TOOLS, 'vendor', 'sysml-v2-release', 'sysml.library') if $jar && !($lib && -d $lib);
    if (!$java || !$jar || !-f $jar || !$lib || !-d $lib) {
        print "validate: skipped -- needs Java plus the SysML v2 Pilot jar and its sysml.library.\n",
              "  java:    ", ($java // 'not found (set JAVA_HOME or put java on PATH)'), "\n",
              "  jar:     ", ($jar // 'not found (set SYSML_JAR, or copy *sysml*all.jar to tools/sysml/)'), "\n",
              "  library: ", ($lib && -d $lib ? $lib : 'not found (set SYSML_LIBRARY, or put sysml.library next to the jar)'), "\n",
              "  '$ME lint' still checks syntax, names, types and imports without Java.\n";
        return 3;
    }
    # The Pilot REPL evaluates one line per input: send the whole model as a single line.
    my ($unit, @map) = ('');
    for my $f (@FILES) {
        # drop // comments (on one line they would swallow everything after them), keeping strings and /* */
        (my $src = $RAW{$f}) =~ s{("[^"\n]*")|//\*.*?\*/|(/\*.*?\*/)|//[^\n]*}{ defined $1 ? $1 : defined $2 ? $2 : '' }gse;
        my @lines = split /\n/, $src;
        for my $i (0 .. $#lines) {
            my $l = $lines[$i];
            next if $l !~ /\S/;
            push @map, [length($unit) + 1, $f, $i + 1];
            $unit .= $l . ' ';
        }
    }
    print "validate: compiling ", scalar @FILES, " files with the Pilot engine (", basename($jar), ") ...\n";
    my $pid = IPC::Open3::open3(my $in, my $out, undef, $java, '-cp', $jar, 'org.omg.sysml.interactive.SysMLInteractive', $lib);
    binmode $in, ':encoding(UTF-8)';
    print {$in} $unit, "\n";
    close $in;
    my $buf = '';
    my $done = 0;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 600;
        while (sysread($out, my $chunk, 65536)) { $buf .= $chunk; if ($buf =~ /(?:^|\n)\s*2>/) { $done = 1; last } }
        alarm 0;
    };
    kill 'KILL', $pid;
    waitpid $pid, 0;
    if (!$done) { print "validate: the Pilot engine did not finish\n$buf\n"; return 1 }
    if ($ENV{SYSML_DEBUG}) { open my $dbg, ">:raw", "validate-debug.txt"; print {$dbg} $buf; close $dbg }
    $buf =~ s/\r//g;
    my $locate = sub {
        my $col = shift;
        my $hit = $map[0];
        for (@map) { last if $_->[0] > $col; $hit = $_ }
        (rel($hit->[1]), $hit->[2], $col - $hit->[0] + 1);
    };
    my ($errors, $warnings) = (0, 0);
    for my $line (split /\n/, $buf) {
        next unless $line =~ /(ERROR|WARNING):(.*?)\s*\(\S+ line : \d+ column : (\d+)\)/;
        my ($sev, $msg, $col) = ($1, $2, $3);
        my ($f, $l, $c) = $locate->($col);
        printf "%s:%d:%d: %s: %s\n", $f, $l, $c, lc $sev, $msg;
        $sev eq 'ERROR' ? $errors++ : $warnings++;
    }
    printf "validate: %d file(s), %d error(s), %d warning(s)\n", scalar @FILES, $errors, $warnings;
    $errors ? 1 : 0;
}

# ------------------------------------------------------------------ new: scaffold a noun or verb
my @LEVEL_TAG = (undef, conf_list('level_tags'));
@LEVEL_TAG = (undef, qw(L1Enterprise L2Segment L3System L4Subsystem L5Assembly L6Subassembly L7Component L8Part L9Piece)) if @LEVEL_TAG < 2;

sub cmd_new {
    my ($kind, $name, %o) = (shift @args, shift @args);
    while (@args) { my $k = shift @args; $k =~ s/^--//; $o{$k} = shift @args }
    my $usage_help = "usage: $ME new part NAME --in PARENT [--usage NAME] [--doc TEXT]\n"
                   . "       $ME new verb NAME --in PARENT [--usage NAME] [--takes 'x:Type,y:Type'] [--returns Type] [--doc TEXT]\n";
    if (!$kind || $kind !~ /^(part|verb)$/ || !$name || !$o{in}) { print STDERR $usage_help; return 2 }
    if ($name !~ /^[A-Z]\w*$/) { print STDERR "new: NAME must be a PascalCase identifier\n"; return 2 }
    if ($DEF{$name}) { print STDERR "new: '$name' already exists in ", rel($DEF{$name}{file}), "\n"; return 1 }
    my $parent = $DEF{ $o{in} };
    my $want = $kind eq 'part' ? 'part' : ($parent && $parent->{kind} eq 'action') ? 'action' : 'calc';   # a verb is born the kind of its parent
    if (!$parent || $parent->{kind} ne $want) { print STDERR "new: no ", ($kind eq 'part' ? 'part def' : 'calc def or action def'), " named '$o{in}'\n"; return 1 }
    my $f = $parent->{file};
    my ($raw, $mt) = ($RAW{$f}, $MASK{$f});
    $mt =~ /\b$want\s+def\s+\Q$o{in}\E\b[^{;]*\{/g or do { print STDERR "new: cannot find '$o{in}' in ", rel($f), "\n"; return 1 };
    my $open = pos($mt) - 1;
    my $close = close_of($mt, $open);
    my $line_start = rindex($raw, "\n", $open) + 1;
    my ($indent) = substr($raw, $line_start) =~ /^([ \t]*)/;
    my $usage = $o{usage} // lcfirst $name;
    my $doc = $o{doc} // 'TODO: describe what this ' . ($kind eq 'part' ? 'part is.' : 'function computes.');
    my ($use_line, $def_text);
    if ($kind eq 'part') {
        my $lvl = level_of($o{in});
        my $tag = $lvl && $lvl < 9 && $LEVEL_TAG[$lvl + 1] ? "\@$LEVEL_TAG[$lvl + 1]; " : '';
        $use_line = "$indent    part $usage : $name;\n";
        $def_text = "\n$indent" . "part def $name {\n$indent    $tag\n$indent    doc /* $doc */\n$indent}\n";
        $def_text =~ s/ +\n/\n/g;
    } else {
        my @takes = map { [split /\s*:\s*/, $_, 2] } grep { /\S/ } split /\s*,\s*/, ($o{takes} // '');
        my $ret = $o{returns} // 'Real';
        $use_line = "$indent    $want $usage : $name"
            . (@takes ? " {\n" . join('', map { "$indent        in $_->[0] = $o{in}::$_->[0];  // TODO: bind\n" } @takes) . "$indent    }\n" : ";\n");
        $def_text = "\n$indent" . "$want def $name {\n$indent    doc /* $doc */\n"
            . join('', map { "$indent    in $_->[0] : $_->[1];\n" } @takes)
            . "$indent    " . ($want eq 'action' ? 'out result' : 'return') . " : $ret;\n$indent}\n";
    }
    if (rindex($raw, "\n", $close) < $open) {    # one-line definition: expand it so the child goes inside
        my @stmts = split_statements(substr($raw, $open + 1, $close - $open - 1), substr($mt, $open + 1, $close - $open - 1));
        my $expanded = "{\n" . join('', map { "$indent    $_\n" } @stmts) . "$indent}";
        $raw = substr($raw, 0, $open) . $expanded . substr($raw, $close + 1);
        $mt = mask($raw);
        $close = close_of($mt, $open);
    }
    my $close_line_end = index($raw, "\n", $close);
    $close_line_end = length $raw if $close_line_end < 0;
    my $close_line_start = rindex($raw, "\n", $close) + 1;
    my $new = substr($raw, 0, $close_line_start) . $use_line . substr($raw, $close_line_start, $close_line_end + 1 - $close_line_start)
            . $def_text . substr($raw, $close_line_end + 1);
    write_file($f, $new);
    printf "new: added %s def %s and usage '%s' to %s in %s\n", $want, $name, $usage, $o{in}, rel($f);
    my $kids = scalar(my @c = children($o{in})) + 1;
    print "new: $o{in} now has $kids child(ren)", ($kids < $MIN ? " -- add a sibling (2..9 rule)" : $kids > $MAX ? " -- too many, group them (2..9 rule)" : ''), "\n";
    print "new: run '$ME check' and '$ME docs'\n";
    0;
}

sub split_statements {    # top-level statements of a block body: split at ';' and after '}' at depth 0
    my ($text, $masked) = @_;
    my @out;
    my ($start, $depth) = (0, 0);
    for my $i (0 .. length($masked) - 1) {
        my $c = substr($masked, $i, 1);
        if    ($c eq '{') { $depth++ }
        elsif ($c eq '}') { $depth--; if (!$depth) { push @out, substr($text, $start, $i + 1 - $start); $start = $i + 1 } }
        elsif ($c eq ';' && !$depth) { push @out, substr($text, $start, $i + 1 - $start); $start = $i + 1 }
    }
    push @out, substr($text, $start);
    grep { /\S/ } map { s/^\s+|\s+$//gr } @out;
}

# ------------------------------------------------------------------ rename
sub cmd_rename {
    my ($old, $new) = (shift @args, shift @args);
    my $write = grep { $_ eq '--write' } @args;
    my $any = grep { $_ eq '--any' } @args;
    if (!$old || !$new || $new !~ /^[A-Za-z_]\w*$/) { print STDERR "usage: $ME rename OLD NEW [--write] [--any]\n"; return 2 }
    my $is_def = grep { $MASK{$_} =~ /\bdef\s+\Q$old\E\b/ } @FILES;
    if (!$is_def && !$any) { print STDERR "rename: '$old' is not a definition name (use --any to rename any identifier)\n"; return 1 }
    if (grep { $MASK{$_} =~ /\b(?:def|package)\s+\Q$new\E\b/ } @FILES) { print STDERR "rename: '$new' already exists\n"; return 1 }
    if ($KEYWORD{$new}) { print STDERR "rename: '$new' is a SysML keyword\n"; return 1 }
    my $total = 0;
    for my $f (@FILES) {
        my $n = () = $RAW{$f} =~ /\b\Q$old\E\b/g;
        next unless $n;
        $total += $n;
        printf "%-60s %3d\n", rel($f), $n;
        write_file($f, $RAW{$f} =~ s/\b\Q$old\E\b/$new/gr) if $write;
    }
    print $write ? "rename: $total occurrence(s) of '$old' renamed to '$new'; now run check and docs\n"
                 : "rename: $total occurrence(s) found; add --write to apply\n";
    0;
}

# ------------------------------------------------------------------ tags (for vim: Ctrl-] jumps to a definition)
sub cmd_tags {
    my @tags;
    for my $f (@FILES) {
        my $t = $MASK{$f};
        my $r = rel_root($f);    # the tags file sits in the project root
        my $add = sub { my ($name, $pos, $kind) = @_; my ($l) = line_col($RAW{$f}, $pos); push @tags, "$name\t$r\t$l;\"\t$kind" };
        $add->($1, $-[1], 'n') while $t =~ /\bpackage\s+(\w+)/g;
        $add->($2, $-[2], { part => 'd', calc => 'f', action => 'f' }->{$1} // substr($1, 0, 1)) while $t =~ /\b(part|calc|item|attribute|port|interface|enum|state|action|requirement|verification|analysis|constraint|metadata|allocation|view|viewpoint|use\s+case)\s+def\s+(\w+)/g;
        $add->($1, $-[1], 'r') while $RAW{$f} =~ /\brequirement\s+<'([^']+)'>/g;
        $add->($1, $-[1], 'r') while $t =~ /\brequirement\s+(?!def\b)(\w+)\s*[{:;]/g;
        $add->($1, $-[1], 'r') while $RAW{$f} =~ /\brequirement\s+[^\n]*?\bdoorsId\s*=\s*"([^"]+)"/g;    # Ctrl-] on a DOORS id too
        while ($t =~ /^\s*(?:part|calc|action|item|port)\s+(?!def\b)(\w+)\s*:/mg) { $add->($1, $-[1], 'u') }
    }
    my %u;
    @tags = sort grep { !$u{$_}++ } @tags;
    my $out = File::Spec->catfile($ROOT, 'tags');
    open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n";
    print {$fh} "!_TAG_FILE_FORMAT\t2\t//\n!_TAG_FILE_SORTED\t1\t/0=unsorted, 1=sorted/\n", map { "$_\n" } @tags;
    close $fh;
    print "tags: wrote ", scalar @tags, " tags to tags (in vim: Ctrl-] on a name, Ctrl-T to go back)\n";
    0;
}

# ------------------------------------------------------------------ trace: requirement -> satisfy -> verify
sub cmd_trace {
    my (@reqs, %by_path);
    for my $f (@FILES) {
        my ($t, $raw) = ($MASK{$f}, $RAW{$f});
        my @found;
        # requirement <'ID'> name ... { ... }   or   requirement name ... { attribute doorsId = "ID"; ... }
        while ($t =~ /\brequirement\s+(?!def\b)(?:<'([^']+)'>\s*)?(\w+)[^{;]*\{/g) {
            my ($id, $name, $open) = ($1, $2, pos($t) - 1);
            my $close = close_of($t, $open);
            my ($door) = substr($raw, $open, $close - $open) =~ /\bdoorsId\s*=\s*"([^"]+)"/;
            push @found, { id => $id // $door // $name, name => $name, open => $open, close => $close, file => $f };
        }
        for my $r (@found) {
            my ($par) = sort { $b->{open} <=> $a->{open} } grep { $_->{open} < $r->{open} && $_->{close} > $r->{close} } @found;
            $r->{parent} = $par;
            my $head = substr($raw, $r->{open}, $r->{close} - $r->{open});
            $head =~ s/\brequirement\b.*//s;
            ($r->{doc}) = $head =~ m{doc\s*/\*\s*(.*?)\s*\*/}s;
            $r->{doc} = join ' ', map { s/^\s*\*?\s*//r } split /\n/, $r->{doc} // '';
        }
        for my $r (@found) {
            my @p = ($r->{name});
            for (my $q = $r->{parent}; $q; $q = $q->{parent}) { unshift @p, $q->{name} }
            $r->{path} = join '.', @p;
            $r->{depth} = $#p;
            $r->{leaf} = !grep { ($_->{parent} // 0) == $r } @found;
            $by_path{ $r->{path} } = $r;
            push @reqs, $r;
        }
    }
    my (%sat, %ver);
    for my $f (@FILES) {
        my $t = $MASK{$f};
        push @{ $sat{ last_seg($1) } }, $2 while $t =~ /\bsatisfy\s+([\w:.]+)\s+by\s+([\w.]+)\s*;/g;
        while ($t =~ /\bverification\s+def\s+(\w+)[^{;]*\{/g) {
            my ($vname, $open) = ($1, pos($t) - 1);
            my $body = substr($t, $open, close_of($t, $open) - $open);
            my ($method) = substr($RAW{$f}, $open, length $body) =~ /(?:method\s*=\s*VerificationMethod|kind\s*=\s*VerificationMethodKind)::'?(\w+)/;
            push @{ $ver{ last_seg($1) } }, $vname . ($method ? " ($method)" : '') while $body =~ /\bverify\s+([\w:.]+)\s*;/g;
        }
    }
    my @rows;
    my ($missing_sat, $missing_ver) = (0, 0);
    for my $r (sort { $a->{file} cmp $b->{file} || $a->{open} <=> $b->{open} } @reqs) {
        my @sp = split /\./, $r->{path};
        my @s = map { @{ $sat{ join '.', @sp[0 .. $_] } || [] } } 0 .. $#sp;
        my @v = @{ $ver{ $r->{path} } || [] };
        my $status = !$r->{leaf} ? 'group' : !@s ? 'not satisfied' : !@v ? 'not verified' : 'ok';
        $status = 'need' if $NEED_PREFIX ne '' && index($r->{id}, $NEED_PREFIX) == 0;
        $missing_sat++ if $status eq 'not satisfied';
        $missing_ver++ if $status eq 'not verified';
        (my $txt = $r->{doc}) =~ s/\|/\\|/g;
        push @rows, sprintf "| %s%s | %s | %s | %s | %s |", ('&nbsp;&nbsp;' x $r->{depth}), $r->{id}, $txt,
            (@s ? join(', ', map { my %u; $_ } do { my %u; grep { !$u{$_}++ } @s }) : ''), join(', ', @v), $status;
    }
    mkdir File::Spec->catdir($ROOT, 'docs');
    my $doc = File::Spec->catfile($ROOT, 'docs', 'Traceability.md');
    open my $fh, '>:encoding(UTF-8)', $doc or die "cannot write $doc: $!\n";
    print {$fh} "<!-- Generated by: $ME trace -- do not edit by hand. -->\n\n# $TITLE Requirements Traceability\n\n",
        "Each requirement, what satisfies it (inherited from its specification), and which verification\n",
        "cases verify it. Status: ok, not verified, not satisfied, group (has sub-requirements), need.\n\n",
        "| ID | Requirement | Satisfied by | Verified by | Status |\n|---|---|---|---|---|\n", join("\n", @rows), "\n";
    close $fh;
    my $leaves = grep { $_->{leaf} && !($NEED_PREFIX ne '' && index($_->{id}, $NEED_PREFIX) == 0) } @reqs;
    printf "trace: %d requirements (%d leaf), %d not satisfied, %d not verified -> %s\n",
        scalar @reqs, $leaves, $missing_sat, $missing_ver, rel($doc);
    print "  $_\n" for map { /\| (?:&nbsp;)*(\S+) \|.*\| (not \w+) \|$/ ? "$1: $2" : () } @rows;
    ($missing_sat || $missing_ver) && grep({ $_ eq '--strict' } @args) ? 1 : 0;
}

# ------------------------------------------------------------------ backlog: hand the IDEF0 set to the agile app
sub cmd_backlog {
    my ($agile) = map { /^--agile=(.+)/ ? $1 : () } @args;
    @args = grep { !/^--agile=/ } @args;
    $agile //= $ENV{AGILE_HOME} // $KIT;    # default: the kit this tool lives in
    my $bridge = $agile ? File::Spec->catfile($agile, 'sim', 'idef0-backlog.pl') : undef;
    if (!$bridge || !-f $bridge) {
        print STDERR "backlog: cannot find the agile kit (sim/idef0-backlog.pl). Use --agile=DIR or set AGILE_HOME.\n";
        return 2;
    }
    my $md = File::Spec->catfile($ROOT, 'docs', 'idef0', "$IDEF0_NAME.md");
    cmd_idef0() unless -f $md;
    chdir $agile or die "cannot cd to $agile: $!\n";
    system($^X, $bridge, $md, @args) == 0 ? 0 : 1;
}

# ------------------------------------------------------------------ pre-commit
sub cmd_precommit {
    my $bad = 0;
    print "== lint\n";  $bad |= cmd_lint();
    print "== check\n"; $bad |= report();
    print "== docs\n";
    { local *STDOUT; open STDOUT, '>', File::Spec->devnull; cmd_docs(); cmd_trace() }
    # stale = regenerated docs differ from what is staged, or new generated files are not yet added
    my $stale = `git -C "$ROOT" diff --name-only -- docs` . `git -C "$ROOT" ls-files --others --exclude-standard -- docs`;
    if ($stale =~ /\S/) {
        print "generated docs were out of date and have been regenerated:\n$stale",
              "review them, 'git add docs', and commit again\n";
        $bad = 1;
    } else { print "docs up to date\n" }
    $bad ? 1 : 0;
}

sub cmd_install_hooks {
    my $src = File::Spec->catfile($TOOLS, 'pre-commit');    # a template: @MODEL_PL@ and @ROOT@ are filled in here
    chomp(my $git = `git -C "$ROOT" rev-parse --absolute-git-dir 2>&1`);
    if ($? || !-d $git) { print STDERR "install-hooks: $ROOT is not inside a git working tree\n"; return 1 }
    my $hooks = File::Spec->catdir($git, 'hooks');
    mkdir $hooks;
    my $dst = File::Spec->catfile($hooks, 'pre-commit');
    open my $in, '<:raw', $src or die "cannot read $src: $!\n";
    my $hook = do { local $/; <$in> };
    close $in;
    my $self = abs_path($0);
    $hook =~ s/\@MODEL_PL\@/$self/g;
    $hook =~ s/\@ROOT\@/$ROOT/g;
    open my $out, '>:raw', $dst or die "cannot write $dst: $!\n";
    print {$out} $hook;
    close $out;
    chmod 0755, $dst;
    print "install-hooks: installed ", rel($dst), " (runs '$ME --root ", rel($ROOT), " precommit')\n";
    0;
}

sub cmd_libnames {
    my $dir = shift @args or do { print STDERR "usage: $ME libnames PATH/TO/sysml.library\n"; return 2 };
    my %n;
    File::Find::find({ no_chdir => 1, wanted => sub {
        return unless /\.(?:sysml|kerml)\z/;
        my $t = code_only(slurp($_));
        $n{$1} = 1 while $t =~ /\b(?:package|(?:\w+\s+)?def|datatype|class|struct|assoc|function|behavior|predicate|interaction|metaclass|classifier|type|feature|step|expr|bool|inv|connector|succession|binding|metadata|alias)\s+(?:<[^>]*>\s*)?('[^']+'|[A-Za-z_]\w*)/g;
    } }, $dir);
    delete @n{qw(def abstract private public all specializes subsets redefines typed in out inout ref end)};
    my $f = File::Spec->catfile($TOOLS, 'sysml-library-names.txt');
    open my $fh, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n";
    print {$fh} "# SysML v2 / KerML standard library names (packages and definitions), extracted from the\n",
        "# SysML v2 Pilot implementation's sysml.library (refresh: $ME libnames DIR).\n",
        "# Used by '$ME lint' to resolve library types offline.\n", map { "$_\n" } sort keys %n;
    close $fh;
    print "libnames: wrote ", scalar(keys %n), " names to tools/sysml/sysml-library-names.txt\n";
    0;
}

# ------------------------------------------------------------------ views: tools/sysml/views on this project's model/
# Each wrapper runs one standalone tool with the model directory (relative to the current directory, so
# diagnostics land in Vim's quickfix list) and passes every other option through; the exit status is the tool's.
my $VIEWS = File::Spec->catdir($TOOLS, 'views');
sub run_view {
    my ($script, @a) = @_;
    my $p = File::Spec->catfile($VIEWS, $script);
    if (!-f $p) { print STDERR "model.pl: $p is missing (the tools/sysml/views toolkit)\n"; return 2 }
    system($^X, $p, @a);
    $? == -1 ? 2 : $? >> 8;
}
sub has_opt { my ($re, @a) = @_; scalar grep { /^(?:$re)(?:=|\z)/ } @a }
my %DRAW = (tree => ['sysml-tree-svg.pl', 'part decomposition'], trace => ['sysml-trace-svg.pl', 'requirement trace'],
            ibd => ['sysml-ibd-svg.pl', 'interconnection and trust zones'], pkg => ['sysml-pkg-svg.pl', 'packages and markings']);
sub cmd_draw {
    my $kind = shift(@args) // '';
    my $d = $DRAW{$kind} or do { print STDERR "usage: $ME draw tree|trace|ibd|pkg [-o FILE] [tool options]\n"; return 2 };
    my @a = @args;
    unshift @a, '-o', "$kind.svg" unless has_opt('-o|--o', @a);
    unshift @a, '--title', "$TITLE: $d->[1]" unless has_opt('--title', @a);
    run_view($d->[0], @a, rel($MODEL));
}
sub cmd_plates {
    my @a = @args;
    unshift @a, '-o', 'plates' unless has_opt('-o|--o', @a);
    run_view('sysml-plates.pl', @a, rel($MODEL));
}
sub cmd_diff {      # diff OLD_DIR [NEW_DIR] | diff --git OLD[..NEW] [PATH...]: the new side defaults to this model
    my @a = @args;
    my (@pos, %val);
    for (my $i = 0; $i < @a; $i++) {
        if ($a[$i] =~ /^(?:-o|--o|--root|--git|--today)\z/) { $val{ $a[$i] } = $a[ $i + 1 ]; $i++ }
        elsif ($a[$i] !~ /^-/) { push @pos, $a[$i] }
    }
    if (defined $val{'--git'}) { push @a, rel($MODEL) unless @pos }
    elsif (@pos == 1) { push @a, rel($MODEL) }
    run_view('sysml-diff.pl', @a);
}
sub cmd_threats { run_view('sysml-threats.pl', @args, rel($MODEL)) }
sub cmd_gate { run_view('sysml-check.pl', '--tools', File::Spec->catdir($VIEWS, 'binder'), @args, rel($MODEL)) }

my @HELP = (
    [check    => 'the 2..9 outline rule and @L level tags (exit 1 on any violation)'],
    [lint     => 'SysML checks without Java: grammar-exact syntax (tools/sysml/sysml.pl), unresolved types, imports, duplicates, self-bindings'],
    [validate => 'full compile with the SysML v2 Pilot engine (needs Java + the Pilot jar; skipped otherwise)'],
    [stats    => 'size, nesting, noun and verb depth, outline check'],
    [nouns    => 'print the noun tree            (--plain for plain words, --ascii for plain consoles)'],
    [verbs    => 'print the verb tree'],
    [docs     => 'regenerate docs/: Nouns.md, Verbs.md, idef0/, Traceability.md'],
    [idef0    => "regenerate docs/idef0/ only: $IDEF0_NAME.md, plates.html, INTERFACES, svg/ (agile's tools/idef0/idef0.pl)"],
    [trace    => 'requirement -> satisfied by -> verified by matrix to docs/Traceability.md (--strict: exit 1 on gaps)'],
    [new      => "scaffold: new part NAME --in PARENT | new verb NAME --in PARENT [--takes 'x:T,..'] [--returns T]"],
    [rename   => 'rename OLD NEW [--write] -- a definition, everywhere (dry run unless --write)'],
    [tags     => 'write a vim tags file: Ctrl-] jumps to any definition or requirement ID'],
    [backlog  => 'run the kit\'s sim/idef0-backlog.pl on the IDEF0 set: a planning stand-up file on stdout (--agile=DIR or AGILE_HOME for another kit)'],
    [precommit       => 'lint + check + generated docs up to date (what the git hook runs)'],
    ['install-hooks' => 'install the git pre-commit hook for this project'],
    [libnames => 'refresh tools/sysml/sysml-library-names.txt from a sysml.library directory'],
    [draw     => 'draw tree|trace|ibd|pkg [-o FILE] [options]: an SVG view of the model (tools/sysml/views; default KIND.svg here)'],
    [plates   => 'drawing plates (ISO title block) from the model\'s views, or --auto (default -o plates)'],
    [diff     => 'diff OLD_DIR [NEW_DIR] | diff --git OLD[..NEW] [PATH]: changes as colored views + a change list (new side: this model)'],
    [threats  => 'the threat table: STRIDE + CAPEC on every threat, each mitigated by a satisfied and verified requirement [--today D]'],
    [gate     => 'the validate gate in one line: text, trace, markings, zones, threats -> PASS|FAIL [--today D] [--strict] [--svg DIR]'],
);

my %CMD = (
    stats => \&cmd_stats,
    check => \&report,
    nouns => sub { print "$_\n" for tree_lines($NOUN_ROOT, 0); 0 },
    verbs => sub { print "$_\n" for tree_lines($VERB_ROOT, 1); 0 },
    docs  => sub { my $s = cmd_docs(); cmd_trace(); $s },
    idef0 => \&cmd_idef0,
    lint  => \&cmd_lint,
    validate => \&cmd_validate,
    new   => \&cmd_new,
    rename => \&cmd_rename,
    tags  => \&cmd_tags,
    trace => \&cmd_trace,
    backlog => \&cmd_backlog,
    precommit => \&cmd_precommit,
    'install-hooks' => \&cmd_install_hooks,
    libnames => \&cmd_libnames,
    draw  => \&cmd_draw,
    plates => \&cmd_plates,
    diff  => \&cmd_diff,
    threats => \&cmd_threats,
    gate  => \&cmd_gate,
    help  => sub { print "$ME [--root DIR] COMMAND [options]\n\n", map { sprintf "  %-14s %s\n", @$_ } @HELP; 0 },
);
if (!$CMD{$cmd}) {
    print STDERR "$ME [--root DIR] COMMAND [options]\n\n", map { sprintf "  %-14s %s\n", @$_ } @HELP;
    exit 2;
}
exit $CMD{$cmd}->();
