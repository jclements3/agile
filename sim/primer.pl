#!/usr/bin/perl
# sim/primer.pl -- the MBSE DevSecOps Primer: docs/src/primer/*.txt -> docs/mbse-devsecops-primer.{html,tex,pdf}
#
#   perl sim/primer.pl                     write the HTML and the TeX (both committed)
#   perl sim/primer.pl --pdf               also build the PDF with XeLaTeX + latexmk (committed; the target laptop has neither)
#   perl sim/primer.pl --check             validate the source only: markup, includes, cross-references; print a summary
#   options: --src DIR  --html FILE  --tex FILE  --pdf-out FILE  --root DIR (where include paths start; default the kit)
#
# The source is one file per chapter, rendered in file-name order; the markup is documented in docs/src/primer/README.txt.
# Evidence (pipeline logs, issue Markdown, CSV tables, SVG figures, JSON values) is pulled in with {{...}} directives, so
# the book quotes real files rather than copies. Every problem in the source is collected and reported together, as
# FILE:LINE: message, and nothing is written. Output is deterministic: the same sources give the same bytes.
#
# Standalone documentation tool -- outside the tested kit surface (lib/, bin/); tests/primer.t exercises it. Core Perl.
use strict;
use warnings;
use FindBin;
use Getopt::Long;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Spec;
use Cwd qw(abs_path);
use JSON::PP ();

my $KIT = abs_path("$FindBin::Bin/..");

# ================================================================ the source model
#   doc  = { meta => {title, subtitle, author, edition, ...}, front => [ chapter ], parts => [ part ] }
#   part = { title, appendix => 0|1, chapters => [ chapter ] }
#   chapter = { title(inline), plain, slug, num (1.. or A..; undef in the front matter), blocks => [ block ], file }
#   block kinds: para, heading(level 3|4), list, quote, code, table, box, figure, pagebreak, subhead, checklist, deflist
our @ERR;
sub err { my ($where, $msg) = @_; push @ERR, "$where: $msg" }

my %KINDS = map { $_ => 1 } qw(note tip warning sidebar objection exercise answer checklist scorecard definition survival);
my %LANGS = map { $_ => 1 } ('', qw(sysml sh yaml md text perl csv diff json html tex vim));
my %BOXTITLE = (note => 'Note', tip => 'Tip', warning => 'Warning', sidebar => 'Case study', objection => 'Objection',
                exercise => 'Exercise', answer => 'Answer', checklist => 'Checklist', scorecard => 'Scorecard',
                definition => 'Definitions', survival => 'Survival kit');
my %EXT_LANG = (sysml => 'sysml', yml => 'yaml', yaml => 'yaml', md => 'md', pl => 'perl', pm => 'perl', t => 'perl',
                csv => 'csv', sh => 'sh', diff => 'diff', patch => 'diff', json => 'json', html => 'html', tex => 'tex',
                vim => 'vim', txt => 'text', log => 'text', conf => 'text');

sub slugify { my $s = lc shift; $s =~ s/<[^>]*>//g; $s =~ s/[^a-z0-9]+/-/g; $s =~ s/^-+|-+$//g; length $s ? $s : 'x' }
sub slurp_raw { my $p = shift; open my $fh, '<:raw', $p or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub slurp_utf8 { my $p = shift; my $t = slurp_raw($p); return undef unless defined $t; utf8::decode($t); $t =~ s/\r\n?/\n/g; $t }

sub resolve_path {                                    # include paths are relative to --root (the kit); no escaping it
    my ($root, $p) = @_;
    return undef if !defined $p || $p eq '' || $p =~ m{(^|/)\.\.(/|$)} || File::Spec->file_name_is_absolute($p);
    return "$root/$p";
}

# ---------------------------------------------------------------- inline markup
#   text, code, bold, italic, ref {slug, text}, fn {kids}, value {text}
sub parse_inline {
    my ($s, $ctx) = @_;
    my @out; my $buf = '';
    my $flush = sub { if (length $buf) { push @out, { t => 'text', v => $buf }; $buf = '' } };
    my $i = 0; my $n = length $s;
    while ($i < $n) {
        my $c = substr($s, $i, 1);
        if ($c eq '`') {
            my $j = index($s, '`', $i + 1);
            if ($j < 0) { err($ctx->{where}, "unclosed `code` span"); $buf .= substr($s, $i); last }
            $flush->(); push @out, { t => 'code', v => substr($s, $i + 1, $j - $i - 1) }; $i = $j + 1; next;
        }
        if (substr($s, $i, 2) eq '[[') {
            my $j = index($s, ']]', $i + 2);
            if ($j < 0) { err($ctx->{where}, "unclosed [[cross-reference"); $buf .= substr($s, $i); last }
            my ($slug, $text) = split /\|/, substr($s, $i + 2, $j - $i - 2), 2;
            $slug =~ s/^\s+|\s+$//g;
            $flush->(); push @out, { t => 'ref', slug => $slug, text => defined $text ? parse_inline($text, $ctx) : undef, where => $ctx->{where} };
            push @{ $ctx->{refs} }, [ $slug, $ctx->{where} ];
            $i = $j + 2; next;
        }
        if (substr($s, $i, 2) eq '^[') {                 # a footnote: balanced brackets, inline markup inside
            my ($d, $j) = (1, $i + 2);
            while ($j < $n && $d) { my $ch = substr($s, $j, 1); $d++ if $ch eq '['; $d-- if $ch eq ']'; $j++ }
            if ($d) { err($ctx->{where}, "unclosed ^[footnote]"); $buf .= substr($s, $i); last }
            $flush->(); push @out, { t => 'fn', kids => parse_inline(substr($s, $i + 2, $j - $i - 3), $ctx) }; $i = $j; next;
        }
        if (substr($s, $i, 2) eq '{{') {
            my $j = index($s, '}}', $i + 2);
            my $body = $j < 0 ? '' : substr($s, $i + 2, $j - $i - 2);
            if ($j >= 0 && $body =~ /^\s*value:\s*(\S+)\s+(\S+)\s*$/) {
                $flush->(); push @out, { t => 'text', v => json_value($1, $2, $ctx), ev => 1 }; $i = $j + 2; next;
            }
            if ($j >= 0 && $body =~ /^\s*count:\s*(\S+)\s+(.+?)\s*$/) {
                $flush->(); push @out, { t => 'text', v => count_lines($1, $2, $ctx), ev => 1 }; $i = $j + 2; next;
            }
            if ($j >= 0 && $body =~ /^\s*n:\s*(.+?)\s*$/) {           # a number that is a definition, not evidence
                $flush->(); push @out, { t => 'text', v => $1, ev => 1 }; $i = $j + 2; next;
            }
            err($ctx->{where}, 'unknown inline directive {{' . ($j < 0 ? substr($s, $i + 2, 20) : $body) . '}} (inline: {{value: FILE KEY}}, {{count: FILE REGEX}}, {{n: NUMBER}})');
            $buf .= '{{'; $i += 2; next;
        }
        if (substr($s, $i, 2) eq '**') {
            my $j = index($s, '**', $i + 2);
            if ($j > $i + 2) { $flush->(); push @out, { t => 'bold', kids => parse_inline(substr($s, $i + 2, $j - $i - 2), $ctx) }; $i = $j + 2; next }
            $buf .= '**'; $i += 2; next;
        }
        if ($c eq '*') {                                  # *italic*: opens before a non-space, not inside a word; closes after a non-space
            my $prev = $i ? substr($s, $i - 1, 1) : ' ';
            if ($prev !~ /[A-Za-z0-9]/ && $i + 1 < $n && substr($s, $i + 1, 1) !~ /[\s*]/) {
                my $j = $i + 1;
                while (($j = index($s, '*', $j)) >= 0) {
                    my $nx = $j + 1 < $n ? substr($s, $j + 1, 1) : ' ';
                    last if substr($s, $j - 1, 1) !~ /\s/ && $nx !~ /[A-Za-z0-9]/;
                    $j++;
                }
                if ($j > $i + 1) { $flush->(); push @out, { t => 'italic', kids => parse_inline(substr($s, $i + 1, $j - $i - 1), $ctx) }; $i = $j + 1; next }
            }
            $buf .= '*'; $i++; next;
        }
        $buf .= $c; $i++;
    }
    $flush->();
    return \@out;
}
sub inline_plain { join '', map { $_->{t} eq 'text' || $_->{t} eq 'code' ? $_->{v} : $_->{t} eq 'fn' ? '' : $_->{t} eq 'ref' ? ($_->{text} ? inline_plain($_->{text}) : $_->{slug}) : inline_plain($_->{kids}) } @{ $_[0] } }

# {{count: FILE REGEX}}: how many lines of FILE match REGEX (Perl syntax)
sub count_lines {
    my ($path, $re, $ctx) = @_;
    my $full = resolve_path($ctx->{root}, $path);
    if (!$full || !-f $full) { err($ctx->{where}, "{{count}}: no such file $path"); return '?' }
    my $rx = eval { qr/$re/ };
    if (!$rx) { err($ctx->{where}, "{{count}}: bad regular expression /$re/"); return '?' }
    my $t = slurp_utf8($full);
    return scalar grep { $_ =~ $rx } split /\n/, $t;
}

# ```sh run sandbox=NAME expect=REGEX exit=N: a code block the primer-runs test executes (sh and vim; and text, read as a
# transcript: its "$ " lines are the commands, run as sh, the rest is shown output the expect= regex stands in for)
my %RUN_KEYS = map { $_ => 1 } qw(sandbox expect exit timeout cwd);
sub parse_run {
    my ($info, $lang, $where) = @_;
    return undef if $info eq '';
    my @w; my $s = $info;
    while ($s =~ s/^\s*(\w+)=(?:"((?:[^"\\]|\\.)*)"|(\S+))// || $s =~ s/^\s*(\w+)//) { my ($k, $q, $p) = ($1, $2, $3); push @w, [ $k, defined $q ? $q =~ s/\\"/"/gr : $p ] }
    if ($s =~ /\S/) { err($where, "cannot read the code block options '$info'"); return undef }
    my ($first, @kv) = @w;
    if (!$first || $first->[0] ne 'run' || defined $first->[1]) { err($where, "code block options must start with 'run' (```$lang run sandbox=... expect=... exit=N)"); return undef }
    if ($lang ne 'sh' && $lang ne 'vim' && $lang ne 'text') { err($where, "only sh, vim and text (a \$ transcript) code blocks can be runnable, not '$lang'"); return undef }
    my %r = ($lang eq 'text' ? (lang => 'sh', transcript => 1) : (lang => $lang));
    for my $kv (@kv) {
        my ($k, $v) = @$kv;
        if (!$RUN_KEYS{$k} || !defined $v) { err($where, "unknown run option '$k' (sandbox=, cwd=, expect=, exit=, timeout=)"); next }
        $r{$k} = $v;
    }
    if (defined $r{sandbox} && $r{sandbox} !~ /^(kit|scratch|tidewater(-\d+)?|practice-\d+)$/) { err($where, "unknown sandbox '$r{sandbox}' (kit, scratch, tidewater, tidewater-N, practice-N)") }
    if (defined $r{exit} && $r{exit} !~ /^\d+$/) { err($where, "exit= needs a number, not '$r{exit}'") }
    if (defined $r{timeout} && $r{timeout} !~ /^\d+$/) { err($where, "timeout= needs seconds, not '$r{timeout}'") }
    if (defined $r{expect} && !eval { qr/$r{expect}/; 1 }) { err($where, "expect= is not a regular expression: $r{expect}") }
    return \%r;
}

my %JSON_CACHE;
sub json_value {
    my ($path, $key, $ctx) = @_;
    my $full = resolve_path($ctx->{root}, $path);
    if (!$full || !-f $full) { err($ctx->{where}, "{{value}}: no such file $path"); return '?' }
    my $d = $JSON_CACHE{$full} //= eval { JSON::PP->new->utf8->decode(slurp_raw($full)) } // do { err($ctx->{where}, "{{value}}: $path is not JSON"); return '?' };
    for my $k (split /\./, $key) {
        if    (ref $d eq 'HASH' && exists $d->{$k})               { $d = $d->{$k} }
        elsif (ref $d eq 'ARRAY' && $k =~ /^\d+$/ && $k < @$d)    { $d = $d->[$k] }
        else { err($ctx->{where}, "{{value}}: no key $key in $path"); return '?' }
    }
    if (ref $d) { err($ctx->{where}, "{{value}}: $key in $path is not a single value"); return '?' }
    return defined $d ? "$d" : 'null';
}

# ---------------------------------------------------------------- blocks
sub parse_csv {
    my ($t) = @_;
    my (@rows, @row); my ($f, $q) = ('', 0);
    my $n = length $t;
    for (my $i = 0; $i < $n; $i++) {
        my $c = substr($t, $i, 1);
        if ($q) { if ($c eq '"') { if (substr($t, $i + 1, 1) eq '"') { $f .= '"'; $i++ } else { $q = 0 } } else { $f .= $c } next }
        if    ($c eq '"') { $q = 1 }
        elsif ($c eq ',') { push @row, $f; $f = '' }
        elsif ($c eq "\n") { push @row, $f; push @rows, [@row]; @row = (); $f = '' }
        else  { $f .= $c }
    }
    push @row, $f if length $f || @row;
    push @rows, [@row] if @row;
    return [ grep { @$_ > 1 || (defined $_->[0] && $_->[0] ne '') } @rows ];
}

# parse_blocks(\@lines, $ctx, $kind): @lines = [ text, lineno ]; $kind = the enclosing box kind (or '')
sub parse_blocks {
    my ($L, $ctx, $kind) = @_;
    my @b; my @para;
    my $at = sub { "$ctx->{file}:$_[0]" };
    my $flush = sub {
        return unless @para;
        my $text = join ' ', map { my $t = $_->[0]; $t =~ s/^\s+|\s+$//g; $t } @para;
        local $ctx->{where} = $at->($para[0][1]);
        if ($kind && $text =~ /^(Answer|What you have|What you need|Hint|Solution):\s*(.*)$/s) {
            push @b, { k => 'subhead', text => $1 };
            push @b, { k => 'para', inl => parse_inline($2, $ctx) } if length $2;
        } else { push @b, { k => 'para', inl => parse_inline($text, $ctx), no => $para[0][1] } }
        @para = ();
    };
    my $i = 0;
    while ($i < @$L) {
        my ($line, $no) = @{ $L->[$i] };
        local $ctx->{where} = $at->($no);
        if ($line =~ /^\s*$/) { $flush->(); $i++; next }
        if ($line =~ /^```\s*(\S*)\s*(.*?)\s*$/) {                                # fenced code (```sh run sandbox=... expect=... exit=N)
            $flush->();
            my ($lang, $info) = ($1, $2); my @c; $i++;
            my $run = parse_run($info, $lang, $at->($no));
            while ($i < @$L && $L->[$i][0] !~ /^```\s*$/) { push @c, $L->[$i][0]; $i++ }
            if ($i >= @$L) { err($at->($no), "code block never closed (```)"); last }
            err($at->($no), "unknown code language '$lang' (" . join(', ', grep { length } sort keys %LANGS) . ")") unless $LANGS{$lang};
            push @b, { k => 'code', lang => $lang, text => join("\n", @c), no => $no, ($run ? (run => $run) : ()) };
            $i++; next;
        }
        if ($line =~ /^(={1,4})\s+(.*?)\s*$/) {                                  # headings
            $flush->();
            my ($lvl, $t) = (length $1, $2);
            my $before = $t =~ s/\s+\@before-contents\s*$// ? 1 : 0;     # == Title {#slug} @before-contents: read before the contents
            my $slug; $slug = $1 if $t =~ s/\s*\{#([A-Za-z0-9][\w-]*)\}\s*$//;
            if ($kind) { err($at->($no), "a heading inside a ::: box") }
            elsif ($lvl == 1) { push @b, { k => 'part', title => $t, no => $no } }
            elsif ($lvl == 2) { push @b, { k => 'chapter', title => $t, slug => $slug, no => $no, before => $before } }
            elsif ($before) { err($at->($no), '@before-contents belongs on a == chapter heading') }
            else { push @b, { k => 'heading', level => $lvl, inl => parse_inline($t, $ctx), plain => $t, slug => $slug, no => $no } }
            $i++; next;
        }
        if ($line =~ /^:::\s*(\S+)\s*(.*?)\s*$/) {                               # boxes
            $flush->();
            my ($k, $title) = (lc $1, $2);
            my $slug; $slug = $1 if $title =~ s/^\{#([A-Za-z0-9][\w-]*)\}\s*//;
            err($at->($no), "a ::: box inside a ::: box") if $kind;
            err($at->($no), "unknown box kind '$k' (" . join(', ', sort keys %KINDS) . ")") unless $KINDS{$k};
            my @in; $i++; my $fence = 0;
            while ($i < @$L) {
                my $l = $L->[$i][0];
                $fence = !$fence if $l =~ /^```/;
                last if !$fence && $l =~ /^:::\s*$/;
                push @in, $L->[$i]; $i++;
            }
            if ($i >= @$L) { err($at->($no), "::: $k box never closed (a line with only :::)"); last }
            push @b, { k => 'box', kind => $k, title => length $title ? parse_inline($title, $ctx) : undef,
                       slug => $slug, blocks => parse_blocks(\@in, $ctx, $k), no => $no };
            $i++; next;
        }
        if ($line =~ /^\{\{\s*([\w-]+)\s*(?::\s*(.*?))?\s*\}\}\s*$/ && $1 !~ /^(value|count|n)$/) {   # block directives (inline ones start a paragraph)
            $flush->();
            push @b, directive($1, $2, $ctx);
            $i++; next;
        }
        if ($line =~ /^\|\|(.*)\|\|\s*$/) {                                      # tables
            $flush->();
            my @head = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $1, -1;
            my @rows; $i++;
            while ($i < @$L && $L->[$i][0] =~ /^\|(.*)\|\s*$/) {
                my @r = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /(?<!\\)\|/, $1, -1;
                s/\\\|/|/g for @r;
                err($at->($L->[$i][1]), "table row has " . @r . " cells, the header has " . @head) if @r != @head;
                push @rows, \@r; $i++;
            }
            my $cap;
            if ($i < @$L && $L->[$i][0] =~ /^Table:\s*(.+?)\s*$/) { $cap = $1; $i++ }
            push @b, { k => 'table', no => $no, head => [ map { parse_inline($_, $ctx) } @head ],
                       rows => [ map { [ map { parse_inline($_, $ctx) } @$_ ] } @rows ], cap => defined $cap ? parse_inline($cap, $ctx) : undef };
            next;
        }
        if ($line =~ /^>/) {                                                    # quoted speech
            $flush->();
            my @q;
            while ($i < @$L && $L->[$i][0] =~ /^>\s?(.*)$/) { push @q, $1; $i++ }
            my $who; $who = pop(@q) =~ s/^--\s*//r if @q && $q[-1] =~ /^--\s/;
            my @paras; my $cur = '';
            for (@q, '') { if (/^\s*$/) { push @paras, $cur if length $cur; $cur = '' } else { $cur .= (length $cur ? ' ' : '') . $_ } }
            push @b, { k => 'quote', paras => [ map { parse_inline($_, $ctx) } @paras ], who => defined $who ? parse_inline($who, $ctx) : undef };
            next;
        }
        if ($kind eq 'checklist' && $line =~ /^\s*\[( |x|X)\]\s+(.*)$/) {        # checklist items
            $flush->();
            my @it;
            while ($i < @$L && $L->[$i][0] =~ /^\s*\[( |x|X)\]\s+(.*)$/) { push @it, { done => $1 ne ' ', inl => parse_inline($2, $ctx) }; $i++ }
            push @b, { k => 'checklist', items => \@it }; next;
        }
        if ($kind eq 'definition' && !@para && $line =~ /^(\S[^:]*?):\s+(.*)$/) {  # term: text (+ indented continuation lines)
            my @d;
            while ($i < @$L && $L->[$i][0] =~ /^(\S[^:]*?):\s+(.*)$/) {
                my ($term, $text) = ($1, $2); $i++;
                while ($i < @$L && $L->[$i][0] =~ /^\s+(\S.*)$/) { $text .= " $1"; $i++ }
                push @d, { term => parse_inline($term, $ctx), inl => parse_inline($text, $ctx) };
            }
            push @b, { k => 'deflist', items => \@d }; next;
        }
        if ($line =~ /^(\s*)(-|\d+\.)\s+(.*)$/ && !@para) {                    # lists
            my $list = parse_list($L, \$i, $ctx, length $1);
            push @b, $list; next;
        }
        if ($line =~ /^\s*(?:-|\d+\.)\s/ && @para) { $flush->(); next }          # a list right after a paragraph line
        push @para, $L->[$i]; $i++;
    }
    $flush->();
    return \@b;
}

sub parse_list {                                      # items at indent $ind; deeper indents nest; continuation lines join
    my ($L, $ip, $ctx, $ind) = @_;
    my ($first) = $L->[$$ip][0] =~ /^\s*(-|\d+\.)\s/;
    my $list = { k => 'list', ordered => ($first ne '-' ? 1 : 0), items => [] };
    while ($$ip < @$L) {
        my ($line, $no) = @{ $L->[$$ip] };
        last if $line =~ /^\s*$/;
        my ($sp, $mk, $text) = $line =~ /^(\s*)(-|\d+\.)\s+(.*)$/;
        if (defined $mk) {
            my $d = length $sp;
            last if $d < $ind;
            if ($d > $ind) {
                if (!@{ $list->{items} }) { err("$ctx->{file}:$no", 'a nested list item with no parent item'); $$ip++; next }
                push @{ $list->{items}[-1]{sub} }, parse_list($L, $ip, $ctx, $d); next;
            }
            if (($mk ne '-') != $list->{ordered}) { last }
            push @{ $list->{items} }, { text => $text, no => $no, sub => [] };
            $$ip++; next;
        }
        if ($line =~ /^\s+(\S.*)$/ && @{ $list->{items} }) { $list->{items}[-1]{text} .= " $1"; $$ip++; next }
        last;
    }
    for my $it (@{ $list->{items} }) { local $ctx->{where} = "$ctx->{file}:$it->{no}"; $it->{inl} = parse_inline($it->{text}, $ctx) }
    return $list;
}

sub directive {
    my ($name, $arg, $ctx) = @_;
    my $w = $ctx->{where};
    my @a = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $arg // '', -1;
    if ($name eq 'pagebreak') { err($w, '{{pagebreak}} takes no argument') if defined $arg && length $arg; return { k => 'pagebreak' } }
    if ($name eq 'value') { err($w, '{{value: ...}} is inline: use it inside a paragraph'); return { k => 'pagebreak', skip => 1 } }
    my $path = $a[0] // '';
    my $full = resolve_path($ctx->{root}, $path);
    my $ok = $full && -f $full;
    if (!$KINDS{$name} && $name !~ /^(include|include-md|csv|figure)$/) { err($w, "unknown directive {{$name}} (include, include-md, csv, figure, value, pagebreak)"); return { k => 'pagebreak', skip => 1 } }
    if (!$ok) { err($w, "{{$name}}: no such file " . ($path eq '' ? '(no path given)' : $path)); return { k => 'pagebreak', skip => 1 } }
    if ($name eq 'include' || $name eq 'include-md') {
        my $t = slurp_utf8($full); $t =~ s/\n\z//;
        my @lines = split /\n/, $t, -1;
        if (defined $a[1] && length $a[1]) {
            if ($a[1] =~ /^lines\s+(\d+)\s*-\s*(\d+)$/ && $1 >= 1 && $2 >= $1) {
                err($w, "{{$name}}: $path has " . @lines . " lines, asked for $1-$2") if $2 > @lines;
                @lines = @lines[ $1 - 1 .. ($2 > @lines ? $#lines : $2 - 1) ];
            } else { err($w, "{{$name}}: '$a[1]' is not 'lines N-M'") }
        }
        my ($ext) = $path =~ /\.(\w+)$/;
        return { k => 'code', lang => ($name eq 'include-md' ? 'md' : $EXT_LANG{ lc($ext // '') } // 'text'), text => join("\n", @lines),
                 caption => $path, sample => $name eq 'include-md' ? 1 : 0 };
    }
    if ($name eq 'csv') {
        my $rows = parse_csv(slurp_utf8($full));
        if (!@$rows) { err($w, "{{csv}}: $path is empty"); return { k => 'pagebreak', skip => 1 } }
        my $head = shift @$rows;
        return { k => 'table', head => [ map { [ { t => 'text', v => $_ } ] } @$head ],
                 rows => [ map { my $r = $_; [ map { [ { t => 'text', v => $r->[$_] // '' } ] } 0 .. $#$head ] } @$rows ],
                 cap => defined $a[1] && length $a[1] ? parse_inline($a[1], $ctx) : undef, src => $path };
    }
    if ($name eq 'figure') {
        err($w, "{{figure}}: $path is not an .svg file") unless $path =~ /\.svg$/i;
        return { k => 'figure', path => $path, full => $full, cap => parse_inline($a[1] // '', $ctx) };
    }
}

# ---------------------------------------------------------------- the book: files -> parts -> chapters, numbering
sub load_book {
    my (%o) = @_;
    my $src = $o{src}; my $root = $o{root};
    my $shown = do { my $a = abs_path($src) // $src; my $r = abs_path($root) // $root; $a =~ s{^\Q$r\E/}{}; $a };   # messages name files relative to the kit
    opendir my $dh, $src or die "primer: cannot read $src: $!\n";
    my @files = sort grep { /^\d+[a-z]?-.*\.txt$/ } readdir $dh;
    closedir $dh;
    @ERR = ();
    my $doc = { meta => {}, front => [], parts => [], shown => $shown };
    my (@refs, $part, $chapter);
    for my $f (@files) {
        my $text = slurp_utf8("$src/$f");
        my $ctx = { file => "$shown/$f", root => $root, refs => \@refs, where => "$shown/$f" };
        my @lines; my $n = 0;
        for my $l (split /\n/, $text) {
            $n++;
            if ($l =~ /^@(\w+):\s*(.*?)\s*$/) { my ($k, $v) = ($1, $2); $doc->{meta}{$k} = defined $doc->{meta}{$k} && $k =~ /^(copyright|dedication|notice)$/ ? "$doc->{meta}{$k}\n$v" : $v; next }
            push @lines, [ $l, $n ];
        }
        my $blocks = parse_blocks(\@lines, $ctx, '');
        my $is_part = $f =~ /^\d+[a-z]?-part-/;
        my $seen_text = 0;
        for my $b (@$blocks) {
            if ($b->{k} eq 'part') {
                err("$src/$f:$b->{no}", "'= Part' belongs on the first line of a part file (NN-part-*.txt)") if !$is_part || $seen_text;
                $part = { title => $b->{title}, appendix => ($b->{title} =~ /^Appendi/i ? 1 : 0), chapters => [] };
                push @{ $doc->{parts} }, $part; $chapter = undef; $seen_text = 1; next;
            }
            $seen_text = 1;
            if ($b->{k} eq 'chapter') {
                $chapter = { title => parse_inline($b->{title}, { %$ctx, where => "$src/$f:$b->{no}" }), plain => $b->{title}, slug => $b->{slug},
                             file => $f, blocks => [], front => $part ? 0 : 1, before => $b->{before} };
                err("$shown/$f:$b->{no}", '@before-contents is only for front-matter chapters (before the first part)') if $part && $b->{before};
                $chapter->{plain} =~ s/[`*]//g;
                push @{ $part ? $part->{chapters} : $doc->{front} }, $chapter; next;
            }
            if (!$chapter) { if ($part && !@{ $part->{chapters} }) { push @{ $part->{intro} }, $b unless $b->{k} eq 'pagebreak' && $b->{skip}; next }   # a part file may carry an introduction
                err("$shown/$f", 'text before the first == chapter heading') unless $b->{k} eq 'pagebreak' && $b->{skip}; next }
            push @{ $chapter->{blocks} }, $b;
        }
    }
    err($src, 'no chapters found (files NN-name.txt with == headings)') unless @{ $doc->{front} } || grep { @{ $_->{chapters} } } @{ $doc->{parts} };
    # numbering: chapters 1.. across parts (A.. after the Appendices part), sections N.M, subsections N.M.K,
    # exercises N.k, tables and figures N.k (only captioned tables are numbered, as in LaTeX)
    my %slug; my $cn = 0; my $an = 0;
    my $reg = sub { my ($s, $what, $where) = @_; if ($slug{$s}) { err($where, "duplicate anchor {#$s}") } else { $slug{$s} = $what } };
    for my $ch (@{ $doc->{front} }, map { @{ $_->{chapters} } } @{ $doc->{parts} }) {
        my ($p) = grep { grep { $_ == $ch } @{ $_->{chapters} } } @{ $doc->{parts} };
        $ch->{num} = $ch->{front} ? undef : $p->{appendix} ? chr(ord('A') + $an++) : ++$cn;
        $ch->{slug} //= 'ch-' . slugify($ch->{plain});
        $reg->($ch->{slug}, { kind => 'chapter', ch => $ch }, $ch->{file});
        my ($s, $ss, $ex, $tb, $fg) = (0, 0, 0, 0, 0);
        my $walk; $walk = sub {
            for my $b (@{ $_[0] }) {
                if ($b->{k} eq 'heading') {
                    if ($b->{level} == 3) { $s++; $ss = 0; $b->{num} = defined $ch->{num} ? "$ch->{num}.$s" : undef }
                    else { $ss++; $b->{num} = defined $ch->{num} ? "$ch->{num}.$s.$ss" : undef }
                    $b->{slug} //= "$ch->{slug}--" . slugify($b->{plain});
                    $reg->($b->{slug}, { kind => 'section', b => $b, ch => $ch }, "$ch->{file}:$b->{no}");
                }
                if ($b->{k} eq 'box') {
                    if ($b->{kind} eq 'exercise') { $ex++; $b->{num} = (defined $ch->{num} ? $ch->{num} : '0') . ".$ex"; $b->{slug} //= "$ch->{slug}--ex-$ex" }
                    $reg->($b->{slug}, { kind => 'exercise', b => $b, ch => $ch }, "$ch->{file}:$b->{no}") if $b->{slug};
                    $walk->($b->{blocks});
                }
                if ($b->{k} eq 'table' && $b->{cap}) { $tb++; $b->{num} = (defined $ch->{num} ? $ch->{num} : '0') . ".$tb" }
                if ($b->{k} eq 'figure') { $fg++; $b->{num} = (defined $ch->{num} ? $ch->{num} : '0') . ".$fg" }
            }
        };
        $walk->($ch->{blocks});
    }
    for my $r (grep { !$slug{ $_->[0] } } @refs) {
        if ($o{draft}) { push @{ $doc->{warnings} }, "$r->[1]: [[$r->[0]]]: not written yet (--draft prints it as [$r->[0]])" }
        else { err($r->[1], "[[$r->[0]]]: no chapter, section or exercise has that anchor") }
    }
    $doc->{slugs} = \%slug;
    $doc->{lint} = [ number_lint($doc) ];
    for my $r (runs($doc)) {                       # reader safety: a reader who types `exit N` closes their own shell
        next unless $r->{lang} eq 'sh';
        my $k = 0;
        for my $l (split /\n/, $r->{text}) { $k++; push @{ $doc->{lint} }, "$r->{file}:" . ($r->{line} + $k) . ": a runnable block must not 'exit' (a reader typing it closes their shell): show a failure with  cmd || echo \"exit status \$?\"  and expect=" if $l =~ /^\s*exit(\s|;|$)/ }
    }
    $doc->{meta}{title} //= 'MBSE DevSecOps Primer';
    return $doc;
}

# --check: in the case chapters (Part III and IV) a number next to a counted thing should come from the evidence
# ({{value}}, {{count}}) or be marked as a definition ({{n: 52}}); a bare one is probably typed by hand and will drift
my $COUNTED = qr/(?:TODO(?:\s+lines?)?|requirements?|(?:story\s+)?points?|sprints|merge\s+requests?|MRs?|pipelines?|jobs?|issues?|tasks?|stories|defects?|discrepanc(?:y|ies)|DRs?|elements?|diagrams?|commits?|conflicts?|baselines?|findings?|errors?|warnings?|hours|minutes|percent)\b/i;
sub number_lint {
    my ($doc) = @_;
    my @w;
    my $text; $text = sub { join '', map { $_->{t} eq 'text' ? ($_->{ev} ? '#EV#' : $_->{v}) : $_->{t} eq 'code' ? '#CODE#' : $_->{kids} ? $text->($_->{kids}) : '' } @{ $_[0] } };
    for my $p (grep { $_->{title} =~ /^Part\s+(III|IV)\b/i } @{ $doc->{parts} }) {
        for my $ch (@{ $p->{chapters} }) {
            my $walk; $walk = sub {
                my ($bl, $no) = @_;
                for my $b (@$bl) {
                    my $at = $b->{no} // ($b->{k} eq 'list' ? $b->{items}[0]{no} : undef) // $no;
                    my @inl = $b->{k} eq 'para' ? ($b->{inl}) : $b->{k} eq 'list' ? (map { $_->{inl} } list_items($b)) : $b->{k} eq 'table' ? (map { @$_ } @{ $b->{rows} }) : ();
                    for my $inl (@inl) {
                        my $t = $text->($inl);
                        while ($t =~ /(?<![\w.#$-])(\d[\d,]*(?:\.\d+)?%?)\s+((?:[A-Za-z-]+\s+){0,2}?)($COUNTED)/g) {
                            push @w, "$doc->{shown}/$ch->{file}" . ($at ? ":$at" : '') . ": \"$1 $2$3\" is a bare number: cite it with {{value: FILE KEY}} or {{count: FILE REGEX}}, or mark a definition with {{n: $1}}";
                        }
                    }
                    $walk->($b->{blocks}, $at) if $b->{k} eq 'box';
                }
            };
            $walk->($ch->{blocks}, undef);
        }
    }
    return @w;
}
sub list_items { my $l = shift; map { ($_, map { list_items($_) } @{ $_->{sub} }) } @{ $l->{items} } }

sub all_chapters { my $d = shift; (@{ $d->{front} }, map { @{ $_->{chapters} } } @{ $d->{parts} }) }

# ================================================================ HTML
sub h { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }

sub html_inline {
    my ($nodes, $st) = @_;
    my $o = '';
    for my $x (@$nodes) {
        my $t = $x->{t};
        if    ($t eq 'text')   { $o .= h($x->{v}) }
        elsif ($t eq 'code')   { $o .= '<code>' . h($x->{v}) . '</code>' }
        elsif ($t eq 'bold')   { $o .= '<strong>' . html_inline($x->{kids}, $st) . '</strong>' }
        elsif ($t eq 'italic') { $o .= '<em>' . html_inline($x->{kids}, $st) . '</em>' }
        elsif ($t eq 'ref') {
            my $tg = $st->{doc}{slugs}{ $x->{slug} };
            if (!$tg) { $o .= '<span class="missing">[' . ($x->{text} ? html_inline($x->{text}, $st) : h($x->{slug})) . ']</span>'; next }
            $o .= '<a href="#' . h($x->{slug}) . '">' . ($x->{text} ? html_inline($x->{text}, $st) : h(ref_label($tg))) . '</a>';
        }
        elsif ($t eq 'fn') {
            my $n = push @{ $st->{fns} }, html_inline($x->{kids}, $st);
            my $id = "$st->{chslug}-fn$n";
            $o .= qq(<sup class="fn"><a id="$id-r" href="#$id">$n</a></sup>);
        }
    }
    $o;
}
sub ref_label {                                       # the visible text of [[slug]]
    my $tg = shift; return '?' unless $tg;
    return ($tg->{ch}{num} ? ($tg->{ch}{front} ? '' : (($tg->{ch}{num} =~ /^[A-Z]$/ ? 'Appendix ' : 'Chapter ') . "$tg->{ch}{num}, ")) : '') . $tg->{ch}{plain} if $tg->{kind} eq 'chapter';
    return ($tg->{b}{num} ? "Section $tg->{b}{num}, " : '') . $tg->{b}{plain} if $tg->{kind} eq 'section';
    return "Exercise $tg->{b}{num}" if $tg->{kind} eq 'exercise' && $tg->{b}{kind} eq 'exercise';
    return 'the ' . lc($BOXTITLE{ $tg->{b}{kind} }) . ' box';
}

sub html_blocks {
    my ($bl, $st) = @_;
    my $o = '';
    for my $b (@$bl) {
        my $k = $b->{k};
        if ($k eq 'para') { $o .= '<p>' . html_inline($b->{inl}, $st) . "</p>\n" }
        elsif ($k eq 'heading') {
            my $tag = $b->{level} == 3 ? 'h3' : 'h4';
            $o .= qq(<$tag id=") . h($b->{slug}) . '">' . (defined $b->{num} ? qq(<span class="num">$b->{num}</span> ) : '') . html_inline($b->{inl}, $st) . "</$tag>\n";
        }
        elsif ($k eq 'subhead') { $o .= '<p class="subhead">' . h($b->{text}) . "</p>\n" }
        elsif ($k eq 'list') { $o .= html_list($b, $st) }
        elsif ($k eq 'quote') {
            $o .= '<blockquote>' . join('', map { '<p>' . html_inline($_, $st) . '</p>' } @{ $b->{paras} })
                . ($b->{who} ? '<p class="who">&mdash; ' . html_inline($b->{who}, $st) . '</p>' : '') . "</blockquote>\n";
        }
        elsif ($k eq 'code') {
            $o .= '<figure class="code' . ($b->{sample} ? ' sample' : '') . '"' . ($b->{run} ? ' data-run="' . h($b->{run}{sandbox} // '') . '"' : '') . '>' . ($b->{caption} ? '<figcaption>' . h($b->{caption}) . '</figcaption>' : '')
                . '<pre' . ($b->{lang} ? ' data-lang="' . h($b->{lang}) . '"' : '') . '><code>' . h(expand_tabs($b->{text})) . "</code></pre></figure>\n";
        }
        elsif ($k eq 'table') {
            $o .= '<div class="tbl"><table>' . ($b->{cap} ? '<caption>' . (defined $b->{num} ? "Table $b->{num}. " : '') . html_inline($b->{cap}, $st) . '</caption>' : '')
                . '<thead><tr>' . join('', map { '<th>' . html_inline($_, $st) . '</th>' } @{ $b->{head} }) . '</tr></thead><tbody>'
                . join('', map { '<tr>' . join('', map { '<td' . (inline_plain($_) =~ /^[\d.,%\$+-]+$/ ? ' class="n"' : '') . '>' . html_inline($_, $st) . '</td>' } @$_) . "</tr>\n" } @{ $b->{rows} })
                . "</tbody></table></div>\n";
        }
        elsif ($k eq 'figure') {
            my $svg = slurp_utf8($b->{full}) // '';
            $svg =~ s/<\?xml[^>]*\?>\s*//; $svg =~ s/<!DOCTYPE[^>]*>\s*//i;
            $o .= qq(<figure class="fig" id="fig-$b->{num}">$svg<figcaption>Figure $b->{num}. ) . html_inline($b->{cap}, $st) . "</figcaption></figure>\n";
        }
        elsif ($k eq 'pagebreak') { $o .= qq(<div class="pagebreak"></div>\n) unless $b->{skip} }
        elsif ($k eq 'checklist') {
            $o .= '<ul class="checklist">' . join('', map { '<li><span class="cb">' . ($_->{done} ? '&#9745;' : '&#9744;') . '</span> ' . html_inline($_->{inl}, $st) . '</li>' } @{ $b->{items} }) . "</ul>\n";
        }
        elsif ($k eq 'deflist') {
            $o .= '<dl>' . join('', map { '<dt>' . html_inline($_->{term}, $st) . '</dt><dd>' . html_inline($_->{inl}, $st) . '</dd>' } @{ $b->{items} }) . "</dl>\n";
        }
        elsif ($k eq 'box') {
            my $title = box_title_html($b, $st);
            $o .= qq(<div class="box $b->{kind}") . ($b->{slug} ? ' id="' . h($b->{slug}) . '"' : '') . qq(><div class="boxtitle">$title</div>\n)
                . html_blocks($b->{blocks}, $st) . "</div>\n";
        }
    }
    $o;
}
sub box_title_html {
    my ($b, $st) = @_;
    my $pre = $b->{kind} eq 'exercise' ? "Exercise $b->{num}" : $BOXTITLE{ $b->{kind} };
    return $b->{title} ? html_inline($b->{title}, $st) : 'Answer' if $b->{kind} eq 'answer';
    return h($pre) . ($b->{title} ? ': ' . html_inline($b->{title}, $st) : '');
}
sub html_list {
    my ($l, $st) = @_;
    my $tag = $l->{ordered} ? 'ol' : 'ul';
    "<$tag>" . join('', map { '<li>' . html_inline($_->{inl}, $st) . join('', map { html_list($_, $st) } @{ $_->{sub} }) . '</li>' } @{ $l->{items} }) . "</$tag>\n";
}
sub expand_tabs { my $t = shift; join "\n", map { 1 while s/^([^\t]*)\t/$1 . ' ' x (8 - length($1) % 8)/e; $_ } split /\n/, $t, -1 }

my $CSS = <<'CSS';
:root { --navy:#27235d; --red:#d6292e; --grey:#808082; --lgrey:#e4e4e7; --olive:#6b7436; --gold:#e6af22; --lblue:#aac1d7; --beige:#e8ddd6;
  --bg:#ffffff; --fg:#1a1a1a; --muted:#5b5b66; --rule:#c9c9d1; --code-bg:#f4f4f6; --box-bg:#f7f7f9; --title-bg:#e9e9ef; --link:#27235d; --side-bg:#f3f3f6; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg:#16161c; --fg:#e6e6ea; --muted:#a3a3ad; --rule:#3a3a46; --code-bg:#20202a; --box-bg:#1c1c25; --title-bg:#2a2a38; --link:#aac1d7; --side-bg:#1b1b23; } }
:root[data-theme="dark"] { --bg:#16161c; --fg:#e6e6ea; --muted:#a3a3ad; --rule:#3a3a46; --code-bg:#20202a; --box-bg:#1c1c25; --title-bg:#2a2a38; --link:#aac1d7; --side-bg:#1b1b23; }
* { box-sizing: border-box; }
html { background: var(--bg); }
body { margin: 0; background: var(--bg); color: var(--fg); font-family: Georgia, "Palatino Linotype", Palatino, "Book Antiqua", serif;
  font-size: 12pt; line-height: 1.55; }
nav.toc { position: fixed; top: 0; left: 0; bottom: 0; width: 290px; overflow-y: auto; background: var(--side-bg); border-right: 1px solid var(--rule);
  padding: 1.2em 1em 2em; font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: 10pt; line-height: 1.35; }
nav.toc .book { font-weight: 700; color: var(--navy); font-size: 11pt; margin-bottom: .8em; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) nav.toc .book { color: var(--lblue); } }
:root[data-theme="dark"] nav.toc .book { color: var(--lblue); }
nav.toc ul { list-style: none; margin: 0; padding: 0; }
nav.toc li.part { margin-top: .9em; font-weight: 700; text-transform: uppercase; font-size: 8.5pt; letter-spacing: .04em; color: var(--muted); }
nav.toc li.ch { margin: .25em 0 .25em .2em; }
nav.toc a { color: var(--fg); text-decoration: none; }
nav.toc a:hover { text-decoration: underline; }
main { margin-left: 290px; padding: 2em 3em 4em; max-width: 1010px; }
@media (max-width: 900px) { nav.toc { position: static; width: auto; border-right: 0; border-bottom: 1px solid var(--rule); max-height: 40vh; }
  main { margin-left: 0; padding: 1em 16px 3em; } }
a { color: var(--link); }
h1, h2, h3, h4, .boxtitle, caption, figcaption, .subhead, .who { font-family: Calibri, "Segoe UI", Arial, sans-serif; }
.cover { position: relative; height: 92vh; min-height: 520px; background: #555 center / cover no-repeat; margin: -2em -3em 2em; display: flex; align-items: flex-end; padding-bottom: 4vh; }
.cover .band { width: 100%; background: rgba(0,0,0,.85); color: #fff; text-align: center; padding: 1.4em 1em 1.2em; font-family: Calibri, "Segoe UI", Arial, sans-serif;
  border-top: 3px double #c7c7c7; border-bottom: 3px double #c7c7c7; }
.cover .ctitle { font-size: 30pt; font-weight: 700; line-height: 1.15; }
.cover .cline { font-size: 15pt; font-variant: small-caps; margin-top: .3em; }
.cover .csub { font-size: 13pt; max-width: 46em; margin: .4em auto 0; }
.cover .cdate { font-size: 11pt; color: #bfbfbf; margin-left: 1em; white-space: nowrap; }
@media (max-width: 900px) { .cover { margin: -1em -16px 1.5em; } .cover .ctitle { font-size: 22pt; } }
@media print { .cover { height: 10in; margin: 0; break-after: page; -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
.titlepage { border-bottom: 3px solid var(--navy); padding: 2em 0 1.5em; margin-bottom: 2em; }
.titlepage h1 { font-size: 30pt; margin: 0 0 .2em; color: var(--navy); border: 0; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .titlepage h1 { color: var(--lblue); } }
:root[data-theme="dark"] .titlepage h1 { color: var(--lblue); }
.titlepage .subtitle { font-size: 15pt; color: var(--muted); }
.titlepage .meta { margin-top: 1.5em; color: var(--muted); }
.frontnote { font-size: 10pt; color: var(--muted); border-top: 1px solid var(--rule); padding-top: .8em; }
.dedication { text-align: center; font-style: italic; margin: 2em 0; }
h1.part { font-size: 22pt; color: var(--navy); border-top: 3px solid var(--navy); padding-top: .4em; margin-top: 3em; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) h1.part { color: var(--lblue); border-color: var(--lblue); } }
:root[data-theme="dark"] h1.part { color: var(--lblue); border-color: var(--lblue); }
h2.chapter { font-size: 19pt; margin-top: 2.5em; border-bottom: 1px solid var(--rule); padding-bottom: .2em; }
h2.chapter .num, h3 .num, h4 .num { color: var(--muted); margin-right: .3em; }
h3 { font-size: 14pt; margin-top: 1.8em; }
h4 { font-size: 12pt; margin-top: 1.4em; }
p { margin: .6em 0; }
code { font-family: Consolas, "DejaVu Sans Mono", "Courier New", monospace; font-size: 10pt; background: var(--code-bg); padding: .05em .3em; border-radius: 2px; }
figure { margin: 1em 0; }
figure.code pre { margin: 0; background: var(--code-bg); border: 1px solid var(--rule); padding: .7em 1em; overflow-x: auto; font-size: 9.5pt; line-height: 1.4; }
figure.code pre code { background: none; padding: 0; font-size: inherit; }
figure.code figcaption { font-size: 9pt; color: var(--muted); margin-bottom: .2em; }
figure.sample figcaption::before { content: "GitLab Markdown: "; }
figure.fig { text-align: center; }
figure.fig svg { max-width: 100%; height: auto; }
figcaption { font-size: 10pt; color: var(--muted); }
.tbl { overflow-x: auto; margin: 1em 0; }
table { border-collapse: collapse; font-size: 10pt; font-family: Calibri, "Segoe UI", Arial, sans-serif; }
caption { caption-side: top; text-align: left; font-size: 10pt; color: var(--muted); padding-bottom: .3em; }
th { border-top: 1.5px solid var(--fg); border-bottom: 1px solid var(--fg); text-align: left; padding: .35em .7em; vertical-align: bottom; }
td { border-bottom: 1px solid var(--rule); padding: .3em .7em; vertical-align: top; }
tbody tr:last-child td { border-bottom: 1.5px solid var(--fg); }
td.n { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
blockquote { margin: 1em 2em; font-style: italic; }
blockquote .who { font-style: normal; text-align: right; color: var(--muted); font-size: 10pt; }
.box { border: 1px solid var(--rule); background: var(--bg); margin: 1.2em 0; padding: 0 1em .5em; }
section.qrg { font-size: 10pt; line-height: 1.35; }
section.qrg h3 { font-size: 11pt; margin: 1em 0 .3em; }
section.qrg p, section.qrg li { margin: .2em 0; }
section.qrg figure.code pre { font-size: 8.5pt; padding: .4em .6em; }
section.qrg table { width: 100%; font-size: 9pt; }
section.qrg td, section.qrg th { padding: .15em .4em; }
@media (min-width: 1100px) { section.qrg ul, section.qrg ol { columns: 2; column-gap: 2em; } }
@media print { section.qrg { break-before: page; font-size: 9pt; } section.qrg h2.chapter { margin-top: 0; } }
.partintro { max-width: 46em; margin: 0 0 2em; color: var(--muted); }
.box .boxtitle { margin: 0 -1em .5em; padding: .3em 1em; background: var(--title-bg); font-weight: 700; font-size: 10pt; }
.box.warning { border: 2px solid var(--fg); }
.box.sidebar { border: 0; border-left: 4px solid var(--grey); background: var(--box-bg); }
.box.sidebar .boxtitle { background: none; padding-left: 1em; }
.box.objection .boxtitle { background: var(--lgrey); color: #1a1a1a; }
.box.survival { border: 1.5px solid var(--fg); }
.box.survival .boxtitle { background: var(--fg); color: var(--bg); }
.box.scorecard { border: 1.5px solid var(--navy); }
.box.exercise .boxtitle { background: none; border-bottom: 1px solid var(--rule); }
.subhead { font-weight: 700; font-size: 10pt; margin: .8em 0 .2em; }
ul.checklist { list-style: none; padding-left: .3em; }
ul.checklist .cb { font-family: "DejaVu Sans", "Segoe UI Symbol", sans-serif; }
dl dt { font-weight: 700; margin-top: .5em; }
dl dd { margin-left: 1.5em; }
.footnotes { border-top: 1px solid var(--rule); margin-top: 2em; font-size: 9.5pt; color: var(--muted); }
sup.fn a { text-decoration: none; }
.contents ul { list-style: none; padding-left: 1.2em; }
.contents > ul { padding-left: 0; }
.contents li.part { margin-top: .8em; font-weight: 700; }
@media print {
  nav.toc { display: none; } main { margin: 0; padding: 0; max-width: none; } body { font-size: 11pt; }
  h1.part, h2.chapter { break-before: page; } .pagebreak { break-after: page; }
  .box, figure, table { break-inside: avoid; } a { color: inherit; text-decoration: none; }
}
CSS

sub render_html {
    my ($doc) = @_;
    my $m = $doc->{meta};
    my $st = { doc => $doc };
    my $toc = '<nav class="toc"><div class="book">' . h($m->{title}) . "</div><ul>\n";
    my $contents = qq(<div class="contents"><h2 class="chapter" id="contents">Contents</h2><ul>\n);
    my $chlabel = sub { my $c = shift; defined $c->{num} ? "$c->{num}&nbsp; " : '' };
    for my $c (@{ $doc->{front} }) { $toc .= '<li class="ch"><a href="#' . h($c->{slug}) . '">' . h($c->{plain}) . "</a></li>\n" }
    for my $p (@{ $doc->{parts} }) {
        my $pid = 'part-' . slugify($p->{title});
        $toc .= qq(<li class="part"><a href="#$pid">) . h($p->{title}) . "</a></li>\n";
        $contents .= qq(<li class="part"><a href="#$pid">) . h($p->{title}) . "</a><ul>\n";
        for my $c (@{ $p->{chapters} }) {
            $toc .= '<li class="ch"><a href="#' . h($c->{slug}) . '">' . $chlabel->($c) . h($c->{plain}) . "</a></li>\n";
            $contents .= '<li><a href="#' . h($c->{slug}) . '">' . $chlabel->($c) . h($c->{plain}) . '</a>';
            my @s = grep { $_->{k} eq 'heading' && $_->{level} == 3 } @{ $c->{blocks} };
            $contents .= '<ul>' . join('', map { '<li><a href="#' . h($_->{slug}) . '">' . (defined $_->{num} ? "$_->{num}&nbsp; " : '') . h($_->{plain}) . '</a></li>' } @s) . '</ul>' if @s;
            $contents .= "</li>\n";
        }
        $contents .= "</ul></li>\n";
    }
    $toc .= "</ul></nav>\n"; $contents .= "</ul></div>\n";
    my $date = cover_date($m);
    my $body = '<section class="cover" style="background-image:url(img/cover-art.jpg)"><div class="band"><div class="ctitle">' . h($m->{title}) . '</div>'
        . '<div class="cline">' . h($m->{coverline} // 'A Case Study') . '</div><div class="csub">' . h($m->{subtitle} // '')
        . ($date ? ' <span class="cdate">&bull; ' . h($date) . '</span>' : '') . "</div></div></section>\n";   # the HTML lives in docs/, beside img/
    $body .= '<div class="titlepage"><h1>' . h($m->{title}) . '</h1>'
        . ($m->{subtitle} ? '<div class="subtitle">' . h($m->{subtitle}) . '</div>' : '')
        . '<div class="meta">' . join('<br>', map { h($_) } grep { defined && length } @$m{qw(author edition)}) . '</div></div>' . "\n";
    $body .= '<div class="frontnote">' . join('', map { '<p>' . h($_) . '</p>' } split /\n/, $m->{copyright}) . "</div>\n" if $m->{copyright};
    $body .= '<div class="dedication">' . join('<br>', map { h($_) } split /\n/, $m->{dedication}) . "</div>\n" if $m->{dedication};
    my $contents_at = length $body;                 # the contents go here, after any @before-contents chapter
    my $chapter = sub {
        my $c = shift;
        local $st->{fns} = []; local $st->{chslug} = $c->{slug};
        my $x = '<section class="chapter' . ($c->{slug} =~ /^qrg-/ ? ' qrg' : '') . '"><h2 class="chapter" id="' . h($c->{slug}) . '">'
              . (defined $c->{num} ? '<span class="num">' . ($c->{num} =~ /^[A-Z]$/ ? 'Appendix ' : '') . "$c->{num}</span> " : '')
              . html_inline($c->{title}, $st) . "</h2>\n" . html_blocks($c->{blocks}, $st);
        if (@{ $st->{fns} }) {
            $x .= '<ol class="footnotes">' . join('', map { my $id = "$c->{slug}-fn" . ($_ + 1); qq(<li id="$id">$st->{fns}[$_] <a href="#$id-r">&#8617;</a></li>) } 0 .. $#{ $st->{fns} }) . "</ol>\n";
        }
        $x . "</section>\n";
    };
    substr($body, $contents_at, 0) = join('', map { $chapter->($_) } grep { $_->{before} } @{ $doc->{front} }) . $contents;   # the bottom line up front, before the contents
    $body .= $chapter->($_) for grep { !$_->{before} } @{ $doc->{front} };
    for my $p (@{ $doc->{parts} }) {
        $body .= '<h1 class="part" id="part-' . slugify($p->{title}) . '">' . h($p->{title}) . "</h1>\n";
        if ($p->{intro}) { local $st->{fns} = []; local $st->{chslug} = 'part-' . slugify($p->{title}); $body .= qq(<div class="partintro">\n) . html_blocks($p->{intro}, $st) . "</div>\n" }
        $body .= $chapter->($_) for @{ $p->{chapters} };
    }
    return qq(<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>)
         . h($m->{title}) . qq(</title>\n<style>\n$CSS</style>\n</head>\n<body>\n$toc<main>\n$body</main>\n</body>\n</html>\n);
}

# ================================================================ LaTeX
sub tex_text {                                        # prose -> TeX: escapes, curly quotes, symbols outside the text font
    my ($s, %o) = @_;
    $s =~ s/\\/\x01/g;
    $s =~ s/([{}\$&#_%])/\\$1/g;
    $s =~ s/~/\\textasciitilde{}/g;
    $s =~ s/\^/\\textasciicircum{}/g;
    $s =~ s/\x01/\\textbackslash{}/g;
    unless ($o{straight}) {
        $s =~ s/(^|[\s(\[{\x{2014}\/-])"/$1\x{201C}/g; $s =~ s/"/\x{201D}/g;
        $s =~ s/(^|[\s(\[{\x{2014}\/-])'/$1\x{2018}/g; $s =~ s/'/\x{2019}/g;
    } else { $s =~ s/"/\\textquotedbl{}/g; $s =~ s/'/\\textquotesingle{}/g }
    $s =~ s/\.\.\./\\ldots{}/g;
    $s =~ s/([\x{2190}-\x{21FF}\x{2200}-\x{22FF}\x{2300}-\x{23FF}\x{2460}-\x{27BF}\x{2B00}-\x{2BFF}])/{\\symfont $1}/g;
    $s =~ s/</\\textless{}/g; $s =~ s/>/\\textgreater{}/g;
    $s;
}
sub tex_code_inline {                                 # `code` -> \code{...} with break points after / . _ - : =
    my $s = tex_text(shift, straight => 1);
    $s =~ s{(/|\.|\\_|-|:|=|,)}{$1\\allowbreak{}}g;
    $s =~ s{([a-z0-9])(?=[A-Z])}{$1\\allowbreak{}}g;            # camelCase: ObservingStation
    $s =~ s{(?<![\\A-Za-z0-9])([A-Za-z0-9]{20,})}{ join "\\allowbreak{}", $1 =~ /(.{1,12})/g }ge;   # last resort: very long runs (not macro names)
    $s =~ s/--/-{}-/g;
    "\\code{$s}";
}
sub tex_inline {
    my ($nodes, $st) = @_;
    my $o = '';
    for my $x (@$nodes) {
        my $t = $x->{t};
        if    ($t eq 'text')   { $o .= tex_text($x->{v}) }
        elsif ($t eq 'code')   { $o .= tex_code_inline($x->{v}) }
        elsif ($t eq 'bold')   { $o .= '\\textbf{' . tex_inline($x->{kids}, $st) . '}' }
        elsif ($t eq 'italic') { $o .= '\\emph{' . tex_inline($x->{kids}, $st) . '}' }
        elsif ($t eq 'fn')     { $o .= '\\footnote{' . tex_inline($x->{kids}, $st) . '}' }
        elsif ($t eq 'ref') {
            my $tg = $st->{doc}{slugs}{ $x->{slug} };
            if (!$tg) { $o .= '\\textbf{[' . ($x->{text} ? tex_inline($x->{text}, $st) : tex_text($x->{slug})) . ']}'; next }
            my $txt = $x->{text} ? tex_inline($x->{text}, $st) : tex_text(ref_label($tg));
            $o .= "\\hyperref[$x->{slug}]{$txt}~(p.\\,\\pageref*{$x->{slug}})";
        }
    }
    $o;
}
sub tex_title { my ($nodes, $st) = @_; my $r = tex_inline($nodes, $st); my $p = tex_text(inline_plain($nodes)); $r eq $p ? $r : "\\texorpdfstring{$r}{$p}" }

sub tex_blocks {
    my ($bl, $st) = @_;
    my $o = '';
    for my $b (@$bl) {
        my $k = $b->{k};
        if ($k eq 'para') { $o .= tex_inline($b->{inl}, $st) . "\n\n" }
        elsif ($k eq 'heading') {
            my $cmd = $b->{level} == 3 ? 'section' : 'subsection';
            $cmd .= '*' unless defined $b->{num};
            $o .= "\\$cmd\{" . tex_title($b->{inl}, $st) . "}\\label{$b->{slug}}\n\n";
        }
        elsif ($k eq 'subhead') { $o .= "\\boxsubhead{" . tex_text($b->{text}) . "}\n" }
        elsif ($k eq 'list') { $o .= tex_list($b, $st) }
        elsif ($k eq 'quote') {
            $o .= "\\begin{speech}\n" . join("\n\n", map { tex_inline($_, $st) } @{ $b->{paras} })
                . ($b->{who} ? "\n\\speaker{" . tex_inline($b->{who}, $st) . "}" : '') . "\n\\end{speech}\n\n";
        }
        elsif ($k eq 'code') {
            my $t = expand_tabs($b->{text});
            $t =~ s/^\n+//; $t =~ s/\s+\z//;
            $t = ' ' if $t eq '';
            $o .= ($b->{caption} ? '\\codecaption{' . ($b->{sample} ? 'GitLab Markdown: ' : '') . tex_text($b->{caption}, straight => 1) . "}\n" : '')
                . "\\begin{Verbatim}\n$t\n\\end{Verbatim}\n\n";
        }
        elsif ($k eq 'table') { $o .= tex_table($b, $st) }
        elsif ($k eq 'figure') {
            my $n = $b->{num} =~ s/\./-/gr;
            $o .= "\\begin{figure}[htbp]\n\\centering\n\\IfFileExists{fig-$n.pdf}{\\includegraphics[width=\\linewidth,height=0.7\\textheight,keepaspectratio]{fig-$n.pdf}}"
                . "{\\fbox{\\parbox{0.8\\linewidth}{\\centering\\small (figure " . tex_text($b->{path}, straight => 1) . " not converted: rsvg-convert was not found)}}}\n"
                . '\\caption{' . tex_inline($b->{cap}, $st) . "}\n\\end{figure}\n\n";
            push @{ $st->{figures} }, [ "fig-$n.pdf", $b->{full} ];
        }
        elsif ($k eq 'pagebreak') { $o .= "\\clearpage\n\n" unless $b->{skip} }
        elsif ($k eq 'checklist') {
            $o .= "\\begin{itemize}[label={},leftmargin=1.6em,itemsep=2pt]\n"
                . join('', map { '\\item[' . ($_->{done} ? '\\checkeddone' : '\\checkbox') . '] ' . tex_inline($_->{inl}, $st) . "\n" } @{ $b->{items} }) . "\\end{itemize}\n";
        }
        elsif ($k eq 'deflist') {
            $o .= "\\begin{description}[style=nextline,leftmargin=1.5em,font=\\normalfont\\bfseries]\n"
                . join('', map { '\\item[' . tex_inline($_->{term}, $st) . '] ' . tex_inline($_->{inl}, $st) . "\n" } @{ $b->{items} }) . "\\end{description}\n";
        }
        elsif ($k eq 'box') {
            my $title = $b->{kind} eq 'exercise' ? "Exercise $b->{num}" . ($b->{title} ? ': ' . tex_inline($b->{title}, $st) : '')
                      : $b->{kind} eq 'answer' ? ($b->{title} ? tex_inline($b->{title}, $st) : 'Answer')
                      : $BOXTITLE{ $b->{kind} } . ($b->{title} ? ': ' . tex_inline($b->{title}, $st) : '');
            my $inner = tex_blocks($b->{blocks}, $st); $inner =~ s/\s+\z//;
            $o .= "\\begin{box$b->{kind}}{$title}" . ($b->{slug} ? "\\phantomsection\\label{$b->{slug}}" : '') . "\n$inner\n\\end{box$b->{kind}}\n\n";
        }
    }
    $o;
}
sub tex_list {
    my ($l, $st) = @_;
    my $env = $l->{ordered} ? 'enumerate' : 'itemize';
    "\\begin{$env}\n" . join('', map { '\\item ' . tex_inline($_->{inl}, $st) . "\n" . join('', map { tex_list($_, $st) } @{ $_->{sub} }) } @{ $l->{items} }) . "\\end{$env}\n";
}
sub tex_table {
    my ($b, $st) = @_;
    my $nc = @{ $b->{head} };
    my @w = (1) x $nc;                                # column widths from content length (capped), as fractions of the line
    for my $r ($b->{head}, @{ $b->{rows} }) { for my $c (0 .. $nc - 1) { my $l = length inline_plain($r->[$c] // []); $l = 60 if $l > 60; $w[$c] = $l if $l > $w[$c] } }
    my @num = map { my $c = $_; (grep { inline_plain($_->[$c] // []) !~ /^[\d.,%\$+ -]*$/ } @{ $b->{rows} }) ? 0 : 1 } 0 .. $nc - 1;
    # each column at least as wide as its longest word (inline code breaks, so code counts 10 chars at most), the rest
    # shared in proportion to content length; fractions of the line after the column gaps
    my $cw = ($nc >= 4 ? 4.6 : 5.1) / 455;                   # one character, as a fraction of the text width (footnotesize / small)
    my @min = (1) x $nc;
    for my $r ($b->{head}, @{ $b->{rows} }) { for my $c (0 .. $nc - 1) {
        for my $x (@{ $r->[$c] // [] }) { for my $wd (split /\s+/, inline_plain([$x])) { my $l = length $wd; $l = 10 if $x->{t} eq 'code' && $l > 10; $l *= 1.12 if $r == $b->{head}; $min[$c] = $l if $l > $min[$c] } } } }
    my $avail = 0.985 - $nc * 0.024;
    my @f = map { ($min[$_] + 1) * $cw } 0 .. $nc - 1;
    my $rest = $avail; $rest -= $_ for @f;
    if ($rest > 0) { my $tot = 0; $tot += $_ for @w; $f[$_] += $rest * $w[$_] / $tot for 0 .. $nc - 1 }
    else { my $s = 0; $s += $_ for @f; $_ *= $avail / $s for @f }
    my $spec = join '', map { sprintf('>{%s}p{%.3f\\linewidth}', $num[$_] ? '\\raggedleft\\arraybackslash' : '\\raggedright\\arraybackslash', $f[$_]) } 0 .. $nc - 1;
    my $row = sub { join(' & ', map { tex_inline($_, $st) } @{ $_[0] }) . " \\\\\n" };
    my $o = "{" . ($nc >= 4 ? '\\footnotesize' : '\\small') . "\\setlength{\\tabcolsep}{0.012\\linewidth}\\setlength{\\emergencystretch}{2em}\n\\begin{longtable}{\@{}$spec\@{}}\n";
    $o .= '\\caption{' . tex_inline($b->{cap}, $st) . "}\\\\\n" if $b->{cap};
    $o .= "\\toprule\n" . '\\bfseries ' . join(' & \\bfseries ', map { tex_inline($_, $st) } @{ $b->{head} }) . " \\\\\n\\midrule\n\\endfirsthead\n";
    $o .= "\\toprule\n" . '\\bfseries ' . join(' & \\bfseries ', map { tex_inline($_, $st) } @{ $b->{head} }) . " \\\\\n\\midrule\n\\endhead\n";
    $o .= "\\bottomrule\n\\endlastfoot\n";
    $o .= $row->($_) for @{ $b->{rows} };
    $o .= "\\end{longtable}}\n\n";
    $o;
}

my $PREAMBLE = <<'TEX';
\documentclass[11pt,letterpaper,twoside,openany]{memoir}
\usepackage{fontspec}
\defaultfontfeatures[\rmfamily,\sffamily]{Ligatures=TeX}
\setmainfont{texgyrepagella}[Extension=.otf, UprightFont=*-regular, BoldFont=*-bold, ItalicFont=*-italic, BoldItalicFont=*-bolditalic]
\setsansfont{texgyreheros}[Extension=.otf, UprightFont=*-regular, BoldFont=*-bold, ItalicFont=*-italic, BoldItalicFont=*-bolditalic, Scale=MatchLowercase]
\setmonofont{DejaVuSansMono}[Extension=.ttf, BoldFont=*-Bold, ItalicFont=*-Oblique, BoldItalicFont=*-BoldOblique, Scale=0.84, Ligatures=NoCommon]
\newfontfamily\symfont{DejaVuSans}[Extension=.ttf, Scale=0.9]
\newfontfamily\coverfont{LibertinusSans}[Extension=.otf, UprightFont=*-Regular, BoldFont=*-Bold, ItalicFont=*-Italic, BoldItalicFont=*-Bold]   % the cover, as docs/HALBERD.pdf
\usepackage{microtype}
\usepackage{xcolor,graphicx,array,booktabs,longtable,calc}
\usepackage{tikz}
\usepackage[shortlabels]{enumitem}
\setlist{itemsep=1pt,topsep=4pt,parsep=0pt}
\usepackage{fvextra}
\fvset{breaklines=true,breakanywhere=true,breaksymbolleft={},breakanywheresymbolpre={},fontsize=\footnotesize,
       frame=single,framerule=0.4pt,rulecolor=\color{black!45},framesep=2.5mm,xleftmargin=0pt,tabsize=8}
\usepackage[most]{tcolorbox}
\usepackage[hidelinks,bookmarksnumbered,pdfusetitle]{hyperref}
\usepackage{bookmark}
% ---- page layout: Letter, generous margins, running heads (memoir "ruled")
\setlrmarginsandblock{1.15in}{1in}{*}
\setulmarginsandblock{1in}{1in}{*}
\setheadfoot{\onelineskip}{2\onelineskip}
\setheaderspaces{*}{1.5\onelineskip}{*}
\checkandfixthelayout
\setsecnumdepth{subsection}
\settocdepth{section}
\maxsecnumdepth{subsection}
\pagestyle{ruled}
\makeevenhead{ruled}{\small\thepage}{}{\small\sffamily\leftmark}
\makeoddhead{ruled}{\small\sffamily\rightmark}{}{\small\thepage}
\nouppercaseheads
% ---- chapter and part styles: black and white, sans heads
\makechapterstyle{primer}{%
  \renewcommand*{\chapterheadstart}{\vspace*{2\onelineskip}}
  \renewcommand*{\chapnamefont}{\normalfont\sffamily\small\MakeUppercase}
  \renewcommand*{\chapnumfont}{\normalfont\sffamily\fontsize{40}{40}\selectfont\color{black!70}}
  \renewcommand*{\chaptitlefont}{\normalfont\sffamily\bfseries\huge\raggedright}
  \renewcommand*{\printchaptername}{\chapnamefont\chaptername}
  \renewcommand*{\chapternamenum}{\par\vspace{2pt}}
  \renewcommand*{\printchapternum}{\chapnumfont\thechapter}
  \renewcommand*{\afterchapternum}{\par\vspace{6pt}}
  \renewcommand*{\printchaptertitle}[1]{\chaptitlefont ##1\par\vspace{4pt}{\color{black!60}\rule{\textwidth}{0.6pt}}}
  \renewcommand*{\afterchaptertitle}{\par\vspace{2\onelineskip}}}
\chapterstyle{primer}
\renewcommand*{\partnamefont}{\normalfont\sffamily\Large\MakeUppercase}
\renewcommand*{\partnumfont}{\normalfont\sffamily\Large}
\renewcommand*{\parttitlefont}{\normalfont\sffamily\bfseries\Huge}
\setsecheadstyle{\normalfont\sffamily\bfseries\Large\raggedright}
\setsubsecheadstyle{\normalfont\sffamily\bfseries\large\raggedright}
\setsubsubsecheadstyle{\normalfont\sffamily\bfseries\raggedright}
\captionnamefont{\sffamily\bfseries\small}
\captiontitlefont{\sffamily\small}
\setlength{\LTcapwidth}{\linewidth}
\setlength{\parskip}{0.35\onelineskip}
\setlength{\parindent}{0pt}
\setlength{\footmarkwidth}{1.2em}\setlength{\footmarksep}{-1.2em}\setlength{\footparindent}{1em}
\footmarkstyle{\textsuperscript{#1}\,}
% ---- inline code, speech, checkboxes
\newenvironment{partintro}{\begin{adjustwidth}{0.08\textwidth}{0.08\textwidth}\small\raggedright}{\end{adjustwidth}}
\setlength{\emergencystretch}{3em}
\usepackage{multicol}
\newenvironment{qrg}{\footnotesize\setlength{\parskip}{2pt}\setlist{itemsep=0pt,topsep=1pt}\fvset{fontsize=\scriptsize}\setlength{\abovecaptionskip}{2pt}\setsecheadstyle{\normalfont\sffamily\bfseries\normalsize\raggedright}\setbeforesecskip{-1.2ex}\setaftersecskip{0.6ex}\setbeforesubsecskip{-1ex}\setaftersubsecskip{0.4ex}\setlength{\columnsep}{1.4em}}{}
\tolerance=2000
\hbadness=10000
\newcommand{\code}[1]{\texttt{#1}}
\newcommand{\checkbox}{{\symfont\char"2610}}
\newcommand{\checkeddone}{{\symfont\char"2611}}
\newcommand{\codecaption}[1]{\par\vspace{2pt}\noindent{\sffamily\footnotesize\color{black!70}#1}\par\nopagebreak\vspace{-4pt}}
\newenvironment{speech}{\begin{quote}\itshape}{\end{quote}}
\newcommand{\speaker}[1]{\par\hfill{\normalfont\small\sffamily --- #1}}
\newcommand{\boxsubhead}[1]{\par\smallskip\noindent{\sffamily\bfseries\small #1}\par\nopagebreak}
% ---- boxes, one style per kind (black and white)
\tcbset{pbox/.style={enhanced,breakable,sharp corners,colback=white,colframe=black!65,boxrule=0.6pt,
  left=7pt,right=7pt,top=5pt,bottom=5pt,fonttitle=\sffamily\bfseries\small\raggedright,coltitle=black,colbacktitle=black!10,
  titlerule=0.4pt,toptitle=2pt,bottomtitle=2pt,before skip=10pt,after skip=10pt,parbox=false}}
\newtcolorbox{boxnote}[1]{pbox,title={#1}}
\newtcolorbox{boxtip}[1]{pbox,colbacktitle=black!4,title={#1}}
\newtcolorbox{boxwarning}[1]{pbox,colframe=black,boxrule=1.2pt,colbacktitle=black!18,title={#1}}
\newtcolorbox{boxsidebar}[1]{pbox,colback=black!4,frame hidden,borderline west={3pt}{0pt}{black!60},
  colbacktitle=black!4,titlerule=0pt,title={#1}}
\newtcolorbox{boxobjection}[1]{pbox,colbacktitle=black!25,boxrule=0.8pt,title={#1}}
\newtcolorbox{boxexercise}[1]{pbox,colframe=black!40,colbacktitle=white,titlerule=0.3pt,title={#1}}
\newtcolorbox{boxanswer}[1]{pbox,colframe=black!30,colbacktitle=black!4,title={#1}}
\newtcolorbox{boxchecklist}[1]{pbox,title={#1}}
\newtcolorbox{boxscorecard}[1]{pbox,colframe=black,boxrule=1pt,colbacktitle=black!15,title={#1}}
\newtcolorbox{boxdefinition}[1]{pbox,colbacktitle=black!6,title={#1}}
\newtcolorbox{boxsurvival}[1]{pbox,colframe=black,boxrule=1pt,colbacktitle=black,coltitle=white,title={#1}}
\setpnumwidth{2.8em}\setrmarg{3.8em}                 % roman page numbers (xxxviii) fit the contents and lists
\renewcommand{\cftpartfont}{\sffamily\bfseries}
\renewcommand{\cftchapterfont}{\sffamily\bfseries}
TEX

# the cover: the same design as docs/HALBERD.pdf (sim/halberd-latex.pl) -- full-page art, an 85% black band with
# double rules, the title, a small-caps line and the subtitle with the month; the band grows when the subtitle wraps
sub cover_date { my $m = shift; my ($d) = ($m->{edition} // '') =~ /([A-Z][a-z]+ \d{4})/; $d // '' }
sub cover_title {                                     # two lines when long, split nearest the middle (as the Halberd cover)
    my $t = shift;
    return tex_text($t) if length $t <= 24 || $t !~ / /;
    my @w = split / /, $t; my ($best, $bi) = (1e9, 1);
    for my $i (1 .. $#w) { my $d = abs(length(join ' ', @w[0 .. $i - 1]) - length(join ' ', @w[$i .. $#w])); ($best, $bi) = ($d, $i) if $d < $best }
    return tex_text(join ' ', @w[0 .. $bi - 1]) . '\\\\[2pt]\\fontsize{28}{33}\\selectfont ' . tex_text(join ' ', @w[$bi .. $#w]);
}
sub tex_cover {
    my ($m) = @_;
    my $long = length($m->{subtitle} // '') > 60;                     # \large in 0.8\paperwidth holds about 75 characters a line
    my ($top, $inner, $ty) = $long ? ('2.95in', '2.89in', '2.30in') : ('2.55in', '2.49in', '1.85in');
    my $date = cover_date($m);
    return "\\IfFileExists{cover-art.jpg}{%\n\\begin{titlingpage}\n\\thispagestyle{empty}\n\\begin{tikzpicture}[remember picture,overlay]\n"
      . "  \\fill[white] (current page.south west) rectangle (current page.north east);\n"
      . "  \\begin{scope}\n    \\clip (current page.south west) rectangle (current page.north east);\n"
      . "    \\node[inner sep=0pt,anchor=center] at (current page.center) {\\includegraphics[width=\\paperwidth]{cover-art.jpg}};\n  \\end{scope}\n"
      . "  \\fill[black,opacity=0.85] ([yshift=0.45in]current page.south west) rectangle ([yshift=$top]current page.south east);\n"
      . "  \\draw[white!78!black,line width=1.2pt] ([yshift=$top]current page.south west) -- ([yshift=$top]current page.south east);\n"
      . "  \\draw[white!78!black,line width=1.2pt] ([yshift=0.45in]current page.south west) -- ([yshift=0.45in]current page.south east);\n"
      . "  \\draw[white!55!black,line width=0.4pt] ([yshift=$inner]current page.south west) -- ([yshift=$inner]current page.south east);\n"
      . "  \\draw[white!55!black,line width=0.4pt] ([yshift=0.51in]current page.south west) -- ([yshift=0.51in]current page.south east);\n"
      . "  \\node[white,font=\\coverfont\\bfseries,align=center] (t) at ([yshift=$ty]current page.south)\n"
      . "    {\\fontsize{28}{33}\\selectfont " . cover_title($m->{title}) . "};\n"
      . "  \\node[white,font=\\coverfont,anchor=north] (s) at ([yshift=-0.10in]t.south) {\\Large\\scshape " . tex_text($m->{coverline} // 'A Case Study') . "};\n"
      . "  \\node[white,font=\\coverfont,anchor=north,align=center,text width=0.8\\paperwidth] at ([yshift=-0.10in]s.south)\n"
      . "    {\\large " . tex_text($m->{subtitle} // '') . ($date ? " \\quad{\\normalsize\\color{white!75!black}\\textbullet\\ " . tex_text($date) . "}" : '') . "};\n"
      . "\\end{tikzpicture}\n\\end{titlingpage}\n}{}\n";
}

sub render_tex {
    my ($doc) = @_;
    my $m = $doc->{meta};
    my $st = { doc => $doc, figures => [] };
    my $o = "% generated by sim/primer.pl from docs/src/primer/ -- do not edit; edit the source and rerun\n$PREAMBLE";
    $o .= '\\title{' . tex_text($m->{title}) . "}\n\\author{" . tex_text($m->{author} // '') . "}\n\\date{" . tex_text($m->{edition} // '') . "}\n";
    $o .= "\\begin{document}\n\\frontmatter\n\\pagestyle{empty}\n";
    $o .= tex_cover($m);
    $o .= "\\begin{titlingpage}\n\\vspace*{0.18\\textheight}\n{\\sffamily\\bfseries\\fontsize{34}{40}\\selectfont " . tex_text($m->{title}) . "\\par}\n\\vspace{1.2em}\n{\\color{black!60}\\rule{\\textwidth}{1pt}}\\par\\vspace{1em}\n"
        . ($m->{subtitle} ? "{\\sffamily\\Large " . tex_text($m->{subtitle}) . "\\par}\n" : '')
        . "\\vfill\n{\\sffamily\\large " . tex_text($m->{author} // '') . "\\par}\\vspace{0.5em}\n{\\sffamily " . tex_text($m->{edition} // '') . "\\par}\n\\end{titlingpage}\n";
    if ($m->{copyright}) {
        $o .= "\\clearpage\n\\vspace*{\\fill}\n{\\small\n" . join("\n\n", map { tex_text($_) } split /\n/, $m->{copyright}) . "\n\\par}\n";
    }
    $o .= "\\clearpage\n\\vspace*{0.3\\textheight}\n\\begin{center}\\itshape\n" . join("\\\\\n", map { tex_text($_) } split /\n/, $m->{dedication}) . "\n\\end{center}\n" if $m->{dedication};
    my ($nf, $nt) = (0, 0);
    my $cnt; $cnt = sub { for (@{ $_[0] }) { $nf++ if $_->{k} eq 'figure'; $nt++ if $_->{k} eq 'table' && $_->{cap}; $cnt->($_->{blocks}) if $_->{k} eq 'box' } };
    $cnt->($_->{blocks}) for all_chapters($doc);
    for my $c (grep { $_->{before} } @{ $doc->{front} }) {    # read first: right after the title pages, on a right-hand page, unnumbered
        my $t = tex_title($c->{title}, $st);
        $o .= "\\cleardoublepage\n\\pagestyle{ruled}\n\\chapter*{$t}\\label{$c->{slug}}\n\\markboth{$t}{$t}\n\n" . tex_blocks($c->{blocks}, $st);
    }
    $o .= "\\clearpage\n\\pagestyle{ruled}\n\\tableofcontents*\n" . ($nf ? "\\clearpage\n\\listoffigures*\n" : '') . ($nt ? "\\clearpage\n\\listoftables*\n" : '');
    for my $c (grep { !$_->{before} } @{ $doc->{front} }) {
        $o .= "\\chapter{" . tex_title($c->{title}, $st) . "}\\label{$c->{slug}}\n\n" . tex_blocks($c->{blocks}, $st);
    }
    my $main = 0;
    for my $p (@{ $doc->{parts} }) {
        if (!$main++) { $o .= "\\mainmatter\n" }
        (my $pt = $p->{title}) =~ s/^Part\s+[IVXLC\d]+\s*[:.]\s*//;      # memoir prints "Part I" itself
        my $intro = $p->{intro} ? tex_blocks($p->{intro}, $st) : '';
        $o .= "\\renewcommand*{\\afterpartskip}{\\par\\vspace{3\\onelineskip}}\n" if length $intro;   # the introduction goes on the part page
        if ($p->{appendix}) { $o .= "\\appendix\n\\cleardoublepage\n\\part*{" . tex_text($pt) . "}\n\\addcontentsline{toc}{part}{" . tex_text($pt) . "}\n\n" }
        else { $o .= "\\part{" . tex_text($pt) . "}\n\n" }
        $o .= "\\begin{partintro}\n$intro\\end{partintro}\n\\renewcommand*{\\afterpartskip}{\\vfil\\newpage}\n\\clearpage\n\n" if length $intro;
        for my $c (@{ $p->{chapters} }) {
            if ($c->{slug} =~ /^qrg-/) { $o .= tex_qrg($c, $st); next }
            $o .= "\\chapter{" . tex_title($c->{title}, $st) . "}\\label{$c->{slug}}\n\n" . tex_blocks($c->{blocks}, $st);
        }
    }
    $o .= "\\end{document}\n";
    return ($o, $st->{figures});
}

# a quick reference card (an appendix chapter whose slug starts with qrg-): starts on a right-hand page so it prints
# alone; dense: footnotesize, tight spacing, full-width tables; two columns when it holds only lists, short
# paragraphs, code and headings (longtable cannot live in multicols)
sub tex_qrg {
    my ($c, $st) = @_;
    my $cols = !grep { $_->{k} =~ /^(table|figure|box)$/ } @{ $c->{blocks} };
    my $body = tex_blocks($c->{blocks}, $st);
    return "\\cleartorecto\n\\chapter{" . tex_title($c->{title}, $st) . "}\\label{$c->{slug}}\n"
         . "\\begin{qrg}\n" . ($cols ? "\\begin{multicols}{2}\n$body\\end{multicols}\n" : $body) . "\\end{qrg}\n\n";
}

sub grey_svg {                                        # colours -> greys of the same luminance (the PDF is black and white)
    my $t = shift;
    $t =~ s{#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b}{
        my $h = $1; $h = join '', map { "$_$_" } split //, $h if length $h == 3;
        my ($r, $g, $b) = map { hex } $h =~ /(..)(..)(..)/;
        sprintf '#%02x%02x%02x', (int(0.299 * $r + 0.587 * $g + 0.114 * $b + 0.5)) x 3
    }ge;
    $t;
}

sub build_pdf {
    my ($tex, $figs, $out, $keep) = @_;
    for my $tool (qw(xelatex latexmk)) {
        my $found = grep { -x "$_/$tool" } split /:/, $ENV{PATH} // '';
        die "primer: --pdf needs $tool (XeLaTeX + latexmk); the HTML and TeX were written\n" unless $found;
    }
    my $dir = $keep // tempdir(CLEANUP => 1);
    if ($keep) { require File::Path; File::Path::make_path($dir) }
    copy("$KIT/docs/img/cover-art.jpg", "$dir/cover-art.jpg") if -f "$KIT/docs/img/cover-art.jpg";   # the cover art (absent: no cover page)
    my $rsvg = grep { -x "$_/rsvg-convert" } split /:/, $ENV{PATH} // '';
    for my $f (@$figs) {
        my ($name, $svg) = @$f;
        if (!$rsvg) { warn "primer: rsvg-convert not found: figure $svg left out of the PDF\n"; next }
        my $g = "$dir/grey-$name.svg";
        open my $fh, '>:raw', $g or die "primer: cannot write $g: $!\n"; print $fh grey_svg(slurp_raw($svg)); close $fh;
        system('rsvg-convert', '-f', 'pdf', '-o', "$dir/$name", $g) == 0 or warn "primer: rsvg-convert failed on $svg\n";
    }
    open my $fh, '>:raw', "$dir/primer.tex" or die "primer: cannot write $dir/primer.tex: $!\n";
    print $fh $tex; close $fh;
    my $log = "$dir/build.log";
    my $rc = system("cd '$dir' && latexmk -xelatex -interaction=nonstopmode -halt-on-error primer.tex > build.log 2>&1");
    if ($rc != 0 || !-f "$dir/primer.pdf") {
        my $l = slurp_raw("$dir/primer.log") // slurp_raw($log) // '';
        my @e = grep { /^!|Error/ } split /\n/, $l;
        die "primer: the PDF build failed:\n" . join("\n", @e[0 .. ($#e < 15 ? $#e : 15)]) . "\n(full log: rerun with --keep DIR and read DIR/primer.log)\n";
    }
    copy("$dir/primer.pdf", $out) or die "primer: cannot write $out: $!\n";
    return $dir;
}

# a transcript block (```text run): the lines that start with "$ " are the commands; a command ending in a backslash
# continues on the next line (a leading "> " prompt there is dropped); everything else is output, shown, not run
sub transcript_commands {
    my ($t) = @_;
    my (@c, $cont);
    for my $l (split /\n/, $t) {
        if ($cont) { (my $x = $l) =~ s/^> //; $c[-1] .= "\n$x"; $cont = $x =~ /\\$/; next }
        next unless $l =~ /^\$ (.*)$/;
        push @c, $1; $cont = $1 =~ /\\$/;
    }
    return join("\n", @c);
}

# the runnable blocks, chapter by chapter in reading order; a block without sandbox= uses the previous block's in the
# same chapter (the first defaults to scratch), so a chapter reads as one session in each sandbox
# the source files with errors (from @ERR's FILE:LINE prefixes): their chapters are left out of runs
sub error_files { my %f; for (@_) { $f{$1} = 1 if /^(.+?\.txt)(?::\d+)?:/ } \%f }

sub runs {
    my ($doc, $skip) = @_;
    my @r;
    for my $ch (all_chapters($doc)) {
        next if $skip && $skip->{"$doc->{shown}/$ch->{file}"};
        my ($sb, $k, $cw) = ('scratch', 0, undef);
        my $walk; $walk = sub { for my $b (@{ $_[0] }) {
            if ($b->{k} eq 'code' && $b->{run}) {
                if (defined $b->{run}{sandbox} && $b->{run}{sandbox} ne $sb) { $cw = undef }   # cwd= is sticky within one sandbox
                $sb = $b->{run}{sandbox} // $sb;
                $cw = $b->{run}{cwd} // $cw;
                push @r, { chapter => $ch->{slug}, file => "$doc->{shown}/$ch->{file}", line => $b->{no}, block => ++$k, lang => $b->{run}{lang},
                            sandbox => $sb, exit => $b->{run}{exit} // 0, cwd => $cw, expect => $b->{run}{expect}, timeout => $b->{run}{timeout}, text => ($b->{run}{transcript} ? transcript_commands($b->{text}) : $b->{text}) };
            }
            $walk->($b->{blocks}) if $b->{k} eq 'box';
        } };
        $walk->($ch->{blocks});
    }
    return @r;
}

# --extract-runs DIR: DIR/manifest.tsv (one line per block) and DIR/<chapter>/NN.sh|NN.vim, plus DIR/<chapter>.sh, the
# chapter's blocks in order as one readable script
sub extract_runs {
    my ($doc, $dir, $skip) = @_;
    require File::Path;
    File::Path::make_path($dir);
    my @r = runs($doc, $skip);
    my $man = "chapter\tfile\tline\tblock\tlang\tsandbox\texit\ttimeout\texpect\tscript\n";
    my %whole;
    for my $x (@r) {
        File::Path::make_path("$dir/$x->{chapter}");
        my $rel = sprintf '%s/%02d.%s', $x->{chapter}, $x->{block}, $x->{lang};
        write_file("$dir/$rel", "$x->{text}\n");
        (my $e = $x->{expect} // '') =~ s/[\t\n]/ /g;
        $man .= join("\t", @$x{qw(chapter file line block lang sandbox exit)}, $x->{timeout} // '', $e, $rel) . "\n";
        $whole{ $x->{chapter} } .= "# ---- $x->{file}:$x->{line}  block $x->{block}  sandbox $x->{sandbox}  exit $x->{exit}" . (defined $x->{expect} ? "  expect /$x->{expect}/" : '') . "\n"
            . ($x->{lang} eq 'vim' ? join('', map { "# vim: $_\n" } split /\n/, $x->{text}) : "$x->{text}\n") . "\n";
    }
    write_file("$dir/manifest.tsv", $man);
    write_file("$dir/$_.sh", "#!/bin/sh\n# runnable blocks of chapter $_, in reading order (generated by sim/primer.pl --extract-runs)\n\n$whole{$_}") for sort keys %whole;
    return scalar @r;
}

sub summary {
    my $doc = shift;
    my ($words, $code, $boxes, $ex, $tables, $figs) = (0, 0, 0, 0, 0, 0);
    my $walk; $walk = sub {
        for my $b (@{ $_[0] }) {
            if ($b->{k} eq 'para') { $words += scalar(() = inline_plain($b->{inl}) =~ /\S+/g) }
            elsif ($b->{k} eq 'list') { my $lw; $lw = sub { for (@{ $_[0]{items} }) { $words += scalar(() = inline_plain($_->{inl}) =~ /\S+/g); $lw->($_) for @{ $_->{sub} } } }; $lw->($b) }
            elsif ($b->{k} eq 'code') { $code += 1 + ($b->{text} =~ tr/\n//) }
            elsif ($b->{k} eq 'table') { $tables++; $words += 3 * @{ $b->{rows} } * @{ $b->{head} } }
            elsif ($b->{k} eq 'figure') { $figs++ }
            elsif ($b->{k} eq 'box') { $boxes++; $ex++ if $b->{kind} eq 'exercise'; $walk->($b->{blocks}) }
        }
    };
    $walk->($_->{blocks}) for all_chapters($doc);
    my $pages = int($words / 380 + $code / 28 + $figs + $boxes * 0.15 + $tables * 0.25 + 0.5) + 6;   # calibrated on a 186-page build
    sprintf "primer: %d part(s), %d chapter(s), %d words, %d code lines, %d tables, %d figures, %d boxes (%d exercises); about %d pages\n",
        scalar @{ $doc->{parts} }, scalar(my @all = all_chapters($doc)), $words, $code, $tables, $figs, $boxes, $ex, $pages;
}

sub write_file { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "primer: cannot write $p: $!\n"; my $b = $t; utf8::encode($b); print $fh $b; close $fh }

sub main {
    my %o = (src => "$KIT/docs/src/primer", html => "$KIT/docs/mbse-devsecops-primer.html", tex => "$KIT/docs/mbse-devsecops-primer.tex",
             'pdf-out' => "$KIT/docs/mbse-devsecops-primer.pdf", root => $KIT);
    GetOptions(\%o, 'draft', 'extract-runs=s', 'src=s', 'html=s', 'tex=s', 'pdf', 'pdf-out=s', 'check', 'keep=s', 'root=s', 'help|h') or return 2;
    if ($o{help}) { print "usage: perl sim/primer.pl [--check] [--draft] [--extract-runs DIR] [--pdf] [--src DIR] [--html FILE] [--tex FILE] [--pdf-out FILE] [--keep DIR] [--root DIR]\n"; return 0 }
    my $doc = load_book(src => $o{src}, root => $o{root}, draft => $o{draft});
    if (@ERR && defined $o{'extract-runs'}) {       # a half-written chapter must not stop the others from being tested
        print STDERR "$_\n" for @ERR;
        my $bad = error_files(@ERR);
        my $n = extract_runs($doc, $o{'extract-runs'}, $bad);
        print STDERR 'primer: ' . @ERR . ' problem(s) in ' . join(', ', sort keys %$bad) . "; their chapters were left out\n";
        print "wrote $n runnable block(s) to $o{'extract-runs'}/manifest.tsv\n";
        return 1;
    }
    if (@ERR) { print STDERR "$_\n" for @ERR; print STDERR 'primer: ' . @ERR . " problem(s) in the source; nothing written\n"; return 1 }
    print STDERR "$_\n" for @{ $doc->{warnings} // [] };
    if ($o{check}) { print STDERR "$_\n" for @{ $doc->{lint} } }
    if (defined $o{'extract-runs'}) { my $n = extract_runs($doc, $o{'extract-runs'}); print "wrote $n runnable block(s) to $o{'extract-runs'}/manifest.tsv\n"; return 0 }
    print summary($doc);
    return 0 if $o{check};
    write_file($o{html}, render_html($doc));
    my ($tex, $figs) = render_tex($doc);
    write_file($o{tex}, $tex);
    print "wrote $o{html}\nwrote $o{tex}\n";
    if ($o{pdf}) { my $b = $tex; utf8::encode($b); build_pdf($b, $figs, $o{'pdf-out'}, $o{keep}); print "wrote $o{'pdf-out'}\n" }
    return 0;
}

exit main() unless caller;
1;
