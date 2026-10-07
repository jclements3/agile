#!/usr/bin/env perl
# req-recipe.pl -- grade requirement statements against the requirement recipe: one sentence per requirement,
# built from up to 18 parts, six of them required. Core Perl 5 only (runs on Git for Windows' Perl).
#
#   perl tools/sysml/req-recipe.pl [--format text|csv|junit|codequality] [--require classification]
#                                  [--links [--baseline] [--top REGEX]...]
#                                  [--strict] [--tag NAME]... [--only ID]... [-o FILE] INPUT...
#
# INPUT: .sysml files or folders of them (requirement doc text, doorsId, title; optional metadata), DOORS
# exports (.reqif, .reqifz, .csv, read with lib/Reqif.pm), or a plain .txt file (one requirement per paragraph,
# its ID in parentheses at the end). Exit 0, or 1 with --strict when any requirement has a finding or a missing
# required part, or 2 on bad usage or an unreadable input. The last line is always
#   requirements=N findings=F missing=M
# so a pipeline can ratchet on it (fail only when F or M grows against the target branch).
#
# The recipe (each part numbered; * = required):
#   (Classification*) While|Upon <preconditions>, the <specification target*>, for the <allocated function>,
#   shall|will|should|may <target verb*> <precise objects*> with|such that <modifications> in accordance with
#   <specification> (<document number>) <section>, except <exceptions>. Note: <informational statements>
#   (<requirement ID*>) [<tags>]
# Classification is required only with --require classification (a notional or unmarked project leaves it off).
#
# Heuristics (best effort -- the decomposition is a reading aid, the findings are the point):
#   - a leading "(U)", "(U//FOUO)", "(CUI)", "(S//NF)" ... is the classification; a trailing "[MC, SC]" the tags;
#     a trailing "(NC_112358)" the ID (or the doorsId / DOORS identifier when the text carries none);
#     so a statement must not end on a parenthesised document number: put the section or a Note: after it;
#   - "Note:" starts the informational statements;
#   - the first shall/will/should/may/must is the operative verb; the clauses before it (split at commas) are
#     state (while, when, during), trigger (upon, on, every, after, before, if, once, at), exceptions (except ...),
#     the allocated function ("for the X function") and, last, the specification target;
#   - after it: the target verb ("not" kept), the precise objects up to the first modifier word (to, within, with,
#     such that, at least, no more than, less than, every, per, at, by, from, for, on, in, under, over, into, via,
#     after, before, between), then modifier/modification pairs; "in accordance with" carries the specification,
#     a parenthesised document number and "Section n.n"; "except ..." the exceptions.
# Findings (severity): missing required part (major); weak target verb -- provide, have, be, establish, be capable
# of, be able to (the recipe's list) and support, allow, enable, handle, ensure, facilitate, accommodate, permit
# (the kit's additions) (major); more than one operative verb or sentence (major); passive "shall be ...ed"
# (minor); a performance verb with no measurable threshold (minor); a reference without document number or section
# (minor); vague words -- as appropriate, as required, etc., and/or, user-friendly, fast, quickly, easy, adequate,
# sufficient, robust, flexible, timely, approximately, optimize, minimize, maximize (minor); "must" instead of
# "shall", or will/should/may as the operative verb (info); a tag other than SC, SR, MC, RMF (minor).
# Score: 100 minus 20 per missing part, 15 per major, 8 per minor, 3 per info finding (0 at the lowest).
#
# --links adds the recipe's relationship attributes, elements 19-23, read from the whole input set (they are links,
# not words in the sentence):
#   19 Parent Trace        a #derivation connection with this requirement as its #derive end, or an attribute
#                          derivedFrom = "DECISION-ID" (a derived requirement, traced to the trade study or design
#                          record that created it); required except for top-level requirements -- by default those in
#                          a package named like "Stakeholder Needs" (or with attribute level = "top"); --top REGEX
#                          (matched against the id, the name and the package path) replaces that default
#   20 Rationale           attribute rationale = "...", @Rationale metadata, or a comment starting "Rationale:";
#                          required. A requirement with a number needs a rationale that names its source (a budget or
#                          allocation, an analysis, a trade study, a standard, a direction, or an id)
#   21 Verification Method attribute verificationMethod = "Test|Analysis|Demonstration|Inspection"; required for shall
#   22 Verification Case   a verify relationship (in a verification def or usage) naming the requirement
#   23 Satisfied By        satisfy REQ by ELEMENT
#   22 and 23 are required "by the baseline" set in the SEP: without --baseline an open one is an info finding, with
#   --baseline (run it on the baseline's merge request) it is a missing part. Plain-text inputs carry the fields as
#   "Parent: ID  Rationale: ...  Verification: METHOD by CASE  Satisfied by: ELEMENT" after the statement.
# The completeness checks: orphan (no parent), childless (a top-level requirement with no children and nothing that
# satisfies it), unjustified threshold, unverified, unsatisfied, unmitigated safety tag (an SC or SR tag with no
# attribute hazard = "..."); a Note: that carries a rationale or the verification approach is a minor finding. With
# --links the text report ends with a line "links: orphan=N childless=N unjustified=N unverified=N unsatisfied=N
# unmitigated=N" before the summary line.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Getopt::Long qw(GetOptionsFromArray);
use Digest::MD5 qw(md5_hex);

my @PARTS = ('Classification', 'State', 'Trigger', 'Preconditions', 'Specification Target', 'Allocated Function',
             'Operative Verb', 'Target Verb', 'Precise Object(s)', 'Modifier(s)', 'Modification(s)', 'Specification',
             'Document Number', 'Section Number', 'Exception(s)', 'Informational Statement(s)', 'Requirement ID',
             'Requirement Tags');
my @REQUIRED = ('Specification Target', 'Operative Verb', 'Target Verb', 'Precise Object(s)', 'Requirement ID');
my @LINK_PARTS = ('Parent Trace', 'Rationale', 'Verification Method', 'Verification Case', 'Satisfied By');   # recipe elements 19-23
my %METHOD = map { lc($_) => $_ } qw(Test Analysis Demonstration Inspection);
our $LINKS = 0;                                  # --links: report elements 19-23 too
our @WEAK_RECIPE = qw(provide have be establish);
our @WEAK_KIT    = qw(support allow enable handle ensure facilitate accommodate permit);
my %WEAK = map { $_ => 'the recipe' } @WEAK_RECIPE;
$WEAK{$_} = "the kit's list" for @WEAK_KIT;
my %KNOWN_TAG = map { $_ => 1 } qw(SC SR MC RMF);
my @VAGUE = ('as appropriate', 'as required', 'as needed', 'etc', 'and/or', 'user-friendly', 'user friendly', 'fast',
             'quickly', 'easy', 'easily', 'adequate', 'sufficient', 'robust', 'flexible', 'timely', 'approximately',
             'optimize', 'minimize', 'maximize', 'state-of-the-art', 'if possible', 'in time');
my %PERF_VERB = map { $_ => 1 } qw(send transmit report respond update publish sample measure maintain detect retry
    deliver recover acquire charge receive);   # actions whose requirement needs a number: a rate, a latency, an accuracy
my @MODS = ('such that', 'in less than', 'less than', 'no more than', 'at least', 'at a rate of', 'within', 'with',
            'to', 'every', 'per', 'at', 'by', 'from', 'for', 'on', 'in', 'under', 'over', 'into', 'onto', 'via',
            'through', 'after', 'before', 'between', 'once');
my $MODRE = join '|', map { (my $m = $_) =~ s/ /\\s+/g; $m } @MODS;
my %SEV_COST = (missing => 20, major => 15, minor => 8, info => 3);

exit main(@ARGV) unless caller;

sub usage { print STDERR "usage: req-recipe.pl [--format text|csv|junit|codequality] [--require classification] [--links [--baseline] [--top REGEX]...] [--strict] [--tag NAME]... [--only ID]... [-o FILE] INPUT...\n"; 2 }

sub main {
    my @args = @_;
    my %o = (format => 'text', tag => [], only => [], require => [], top => []);
    GetOptionsFromArray(\@args, \%o, 'format=s', 'require=s@', 'strict', 'tag=s@', 'only=s@', 'o=s', 'links', 'baseline', 'top=s@', 'help|h') or return usage();
    if ($o{help}) { print "usage: req-recipe.pl [--format text|csv|junit|codequality] [--require classification] [--links [--baseline] [--top REGEX]...] [--strict] [--tag NAME]... [--only ID]... [-o FILE] INPUT...\n"; return 0 }
    return usage() unless @args;
    if ($o{format} !~ /^(text|csv|junit|codequality)$/) { print STDERR "req-recipe: --format is text, csv, junit or codequality, not '$o{format}'\n"; return 2 }
    for my $r (@{ $o{require} }) { if ($r ne 'classification') { print STDERR "req-recipe: --require takes 'classification', not '$r'\n"; return 2 } }
    $KNOWN_TAG{ uc $_ } = 1 for @{ $o{tag} };
    if (($o{baseline} || @{ $o{top} }) && !$o{links}) { print STDERR "req-recipe: --baseline and --top go with --links\n"; return 2 }
    for my $t (@{ $o{top} }) { if (!eval { qr/$t/; 1 }) { print STDERR "req-recipe: --top '$t' is not a valid regular expression\n"; return 2 } }
    local $LINKS = $o{links} ? 1 : 0;
    my @reqs;
    for my $in (@args) {
        my $got = eval { read_input($in) };
        if (!defined $got) { (my $e = $@) =~ s/\s+$//; print STDERR "req-recipe: $e\n"; return 2 }
        push @reqs, @$got;
    }
    if (@{ $o{only} }) { my %w = map { $_ => 1 } @{ $o{only} }; @reqs = grep { $w{ $_->{id} // '' } } @reqs }
    my $idx = $o{links} ? link_index(\@args, \@reqs) : undef;
    my @graded = map { grade($_, require_class => scalar(grep { $_ eq 'classification' } @{ $o{require} }),
                             ($idx ? (links => $idx, baseline => $o{baseline}, top => $o{top}) : ())) } @reqs;
    my $out = $o{format} eq 'csv' ? to_csv(\@graded) : $o{format} eq 'junit' ? to_junit(\@graded)
            : $o{format} eq 'codequality' ? to_codequality(\@graded) : to_text(\@graded);
    my ($n, $f, $m) = totals(\@graded);
    my $summary = "requirements=$n findings=$f missing=$m\n";
    $summary = link_counts(\@graded) . $summary if $o{links};
    if (defined $o{o}) {
        open my $fh, '>:raw', $o{o} or do { print STDERR "req-recipe: cannot write $o{o}: $!\n"; return 2 };
        print $fh $out; close $fh;
        print $summary;
    } else {
        print $out;
        print $summary if $o{format} eq 'text';
        print STDERR $summary unless $o{format} eq 'text';
    }
    return ($o{strict} && ($f || $m)) ? 1 : 0;
}

sub totals { my $g = shift; my ($f, $m) = (0, 0); for (@$g) { $f += @{ $_->{findings} }; $m += @{ $_->{missing} } } (scalar(@$g), $f, $m) }

# ---------------------------------------------------------------- inputs -> [ { id, title, text, file, line, class, tags } ]
sub read_input {
    my ($in) = @_;
    die "cannot read $in: no such file or folder\n" unless -e $in;
    return read_sysml_dir($in) if -d $in;
    return read_sysml($in) if $in =~ /\.sysml$/i;
    if ($in =~ /\.reqifz?$/i || $in =~ /\.csv$/i) {
        require Reqif;
        my $d = $in =~ /\.csv$/i ? Reqif::load_csv($in) : Reqif::load_reqif($in);
        my @r;
        for my $oid (@{ $d->{order} }) {
            my $x = $d->{objects}{$oid};
            next unless defined $x->{text} && $x->{text} =~ /\S/;
            push @r, { id => $x->{id}, title => $x->{name}, text => $x->{text}, file => $in, line => 1, source => 'doors' };
        }
        return \@r;
    }
    return read_text($in);
}
sub slurp { my $f = shift; open my $fh, '<:raw', $f or die "cannot read $f: $!\n"; local $/; my $t = <$fh>; close $fh; $t =~ s/\r\n?/\n/g; $t }
sub read_sysml_dir {
    my ($d) = @_;
    my @f;
    my $w; $w = sub { my $x = shift; opendir my $dh, $x or return; for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$x/$e"; -d $p ? $w->($p) : $e =~ /\.sysml$/ && push @f, $p } closedir $dh };
    $w->($d);
    [ map { @{ read_sysml($_) } } @f ];
}
sub package_paths {                              # the enclosing package path of every line ('A::B')
    my ($lines) = @_;
    my (@stack, @path, $depth);
    $depth = 0;
    for my $l (@$lines) {
        push @path, join('::', map { $_->[0] } @stack);
        (my $code = $l) =~ s{/\*.*?\*/}{}g;
        $code =~ s{//.*}{};
        my $pk = $code =~ /\bpackage\s+('[^']*'|\w+)\s*\{/ ? $1 : undef;
        for my $ch ($code =~ /([{}])/g) {
            if ($ch eq '{') { $depth++; if (defined $pk) { (my $n = $pk) =~ s/^'|'$//g; push @stack, [ $n, $depth ]; undef $pk } }
            else { pop @stack if @stack && $stack[-1][1] == $depth; $depth-- }
        }
    }
    \@path;
}
sub read_sysml {
    my ($f) = @_;
    my @lines = split /\n/, slurp($f), -1;
    my $paths = package_paths(\@lines);
    my @r;
    for (my $i = 0; $i < @lines; $i++) {
        next unless $lines[$i] =~ /^\s*requirement\s+(?:def\s+)?('[^']*'|\w+)/ && $1 ne 'def';
        my ($name, $start) = ($1, $i);
        my ($block, $depth, $seen) = ('', 0, 0);
        for (my $j = $i; $j < @lines; $j++) {           # the requirement's body: braces balanced (doc comments skipped)
            my $l = $lines[$j];
            $block .= "$l\n";
            (my $code = $l) =~ s{/\*.*?\*/}{}g;
            $code =~ s{//.*}{};
            $depth += () = $code =~ /\{/g; $seen ||= $depth > 0;
            $depth -= () = $code =~ /\}/g;
            if (($seen && $depth <= 0) || (!$seen && $code =~ /;\s*$/)) { $i = $j; last }
        }
        my ($doc) = $block =~ m{\bdoc\s*/\*\s*(.*?)\s*\*/}s;
        next unless defined $doc;
        $doc =~ s/^\s*\*\s?//mg; $doc =~ s/\s+/ /g; $doc =~ s/\* \//*\//g;
        my ($id) = $block =~ /\bdoorsId\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        my ($title) = $block =~ /\btitle\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        my ($cls) = $block =~ /\bclassification\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        ($cls) = $block =~ /\@Marking\s*\{\s*level\s*=\s*(?:\w+::)*(\w+)/ unless defined $cls;
        my @tags = map { split /[\s,;]+/ } ($block =~ /\btags\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/g);
        push @tags, $1 while $block =~ /\@(SC|SR|MC|RMF)\b/g;
        (my $n = $name) =~ s/^'|'$//g;
        my %lk;
        ($lk{method}) = $block =~ /\bverificationMethod\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        ($lk{rationale}) = $block =~ /\brationale\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        ($lk{rationale}) = $block =~ /\@Rationale\s*\{[^}]*?(?:text|explanation)\s*=\s*"([^"]*)"/ unless defined $lk{rationale};
        ($lk{rationale}) = $block =~ m{\bcomment\b[^/]*/\*\s*Rationale:\s*(.*?)\s*\*/}s unless defined $lk{rationale};
        ($lk{derived_from}) = $block =~ /\bderivedFrom\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        ($lk{level}) = $block =~ /\blevel\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/;
        my @hz = map { split /[\s,;]+/ } ($block =~ /\bhazards?\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/g);
        $lk{hazards} = \@hz;
        defined $lk{$_} && $lk{$_} =~ s/\s+/ /g for qw(rationale);
        push @r, { id => $id // $n, title => $title, text => $doc, file => $f, line => $start + 1, source => 'sysml',
                   class => $cls, tags => \@tags, id_from_attr => defined $id ? 1 : 0, name => $n, pkg => $paths->[$start], link => \%lk };
    }
    \@r;
}
sub read_text {
    my ($f) = @_;
    my $t = slurp($f);
    my (@r, $line);
    my $n = 1;
    for my $para (split /\n[ \t]*\n/, $t) {
        my $lines = () = $para =~ /\n/g;
        (my $p = $para) =~ s/\s+/ /g; $p =~ s/^ | $//g;
        my %lk;
        if ($p =~ s/\s*\b((?:Parent|Rationale|Verification|Satisfied by):.*)$//i) {   # the relationship fields (19-23) after the statement
            my $fl = $1;
            my @parts = split /\s*\b(Parent|Rationale|Verification|Satisfied by):\s*/i, " $fl";
            shift @parts;
            while (my ($k, $v) = splice @parts, 0, 2) {
                $v //= ''; $v =~ s/[\s.]+$//; $k = lc $k;
                if    ($k eq 'parent')       { $lk{parents} = [ grep { length } split /[\s,;]+/, $v ] }
                elsif ($k eq 'rationale')    { $lk{rationale} = $v }
                elsif ($k eq 'verification') { ($lk{method}, my $case) = $v =~ /^(\w+)(?:\s+by\s+(.+))?$/i; $lk{cases} = [ grep { length } split /[\s,;]+/, $case // '' ] }
                elsif ($k eq 'satisfied by') { (my $sb = $v) =~ s/\s*\(.*$//; $lk{satisfiers} = [ grep { length } split /[\s,;]+/, $sb ] }
            }
        }
        if ($p eq '' && %lk && @r && $r[-1]{source} eq 'text') { my $prev = $r[-1]{link} //= {}; $prev->{$_} = $lk{$_} for keys %lk }
        elsif ($p ne '' && $p !~ /^#/) { push @r, { text => $p, file => $f, line => $n + (($para =~ /^(\n*)/)[0] =~ tr/\n//), source => 'text', (%lk ? (link => \%lk) : ()) } }
        $n += $lines + 2;
    }
    \@r;
}

# ---------------------------------------------------------------- links (recipe elements 19-23) across the input set
sub ref_name { my $r = shift; $r =~ s/^\s+|\s+$//g; my @seg = split /::|\./, $r; my $n = $seg[-1] // $r; $n =~ s/^'|'$//g; $n }
sub sysml_files_of {
    my @f;
    for my $in (@_) {
        if (-d $in) { my $w; $w = sub { my $x = shift; opendir my $dh, $x or return; for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$x/$e"; -d $p ? $w->($p) : $e =~ /\.sysml$/ && push @f, $p } closedir $dh }; $w->($in) }
        elsif ($in =~ /\.sysml$/i && -f $in) { push @f, $in }
    }
    @f;
}
sub link_index {                                  # name or id -> { parents, children, satisfiers, cases }
    my ($inputs, $reqs) = @_;
    my %ix;
    my $at = sub { $ix{ $_[0] } //= { parents => [], children => 0, satisfiers => [], cases => [] } };
    for my $f (sysml_files_of(@$inputs)) {
        my $t = slurp($f);
        $t =~ s{/\*.*?\*/}{ }gs; $t =~ s{//[^\n]*}{}g;
        while ($t =~ /#derivation\s+connection\b[^{;]*\{(.*?)\}/sg) {
            my $body = $1;
            my @orig = map { ref_name($_) } $body =~ /\bend\s+#original\s*::>\s*([^;]+);/g;
            my @der  = map { ref_name($_) } $body =~ /\bend\s+#derive\s*::>\s*([^;]+);/g;
            for my $d (@der) { push @{ $at->($d)->{parents} }, @orig }
            $at->($_)->{children} += @der for @orig;
        }
        while ($t =~ /\bsatisfy\s+(?:requirement\s+)?([\w':.]+?)(?:\s+by\s+([\w':.]+))?\s*;/g) {
            push @{ $at->(ref_name($1))->{satisfiers} }, defined $2 ? ref_name($2) : '(its owner)';
        }
        my $case = '(a verification)';
        while ($t =~ /\bverification\s+(?:def\s+)?('[^']*'|\w+)|\bverify\s+(?:requirement\s+)?([\w':.]+)\s*;/g) {
            if (defined $1) { ($case = $1) =~ s/^'|'$//g; next }
            push @{ $at->(ref_name($2))->{cases} }, $case;
        }
    }
    for my $r (@$reqs) {                          # plain-text requirements carry their links as fields
        my $lk = $r->{link} or next;
        my $id = $r->{id} // parse($r->{text})->{'Requirement ID'} // next;
        push @{ $at->($id)->{parents} }, @{ $lk->{parents} // [] };
        $at->($_)->{children}++ for @{ $lk->{parents} // [] };
        push @{ $at->($id)->{cases} }, @{ $lk->{cases} // [] };
        push @{ $at->($id)->{satisfiers} }, @{ $lk->{satisfiers} // [] };
    }
    for my $v (values %ix) { my %s; $v->{$_} = [ grep { !$s{"$_\0"}++ } @{ $v->{$_} } ] for qw(parents satisfiers cases) }
    \%ix;
}
sub link_counts {
    my ($g) = @_;
    my %c = map { $_ => 0 } qw(orphan childless unjustified unverified unsatisfied unmitigated);
    for my $r (@$g) { $c{$_}++ for keys %{ $r->{link_fail} // {} } }
    'links: ' . join(' ', map { "$_=$c{$_}" } qw(orphan childless unjustified unverified unsatisfied unmitigated)) . "\n";
}

# ---------------------------------------------------------------- parse one statement into the recipe's parts
sub parse {
    my ($text) = @_;
    my %p;
    my $s = $text // '';
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    if ($s =~ s/^\(\s*([A-Z]{1,4}(?:\/\/?[A-Z][A-Z\-]*)*)\s*\)\s*//) { $p{'Classification'} = $1 }
    if ($s =~ s/\s*\[([A-Za-z]{1,6}(?:\s*[,;\/ ]\s*[A-Za-z]{1,6})*)\]\s*\.?\s*$//) { $p{'Requirement Tags'} = [ map { uc } split /[\s,;\/]+/, $1 ] }
    if ($s =~ s/\s*\(([A-Za-z][A-Za-z0-9]*(?:[-_.][A-Za-z0-9]+)+)\)\s*\.?\s*$//) { $p{'Requirement ID'} = $1 }
    if ($s =~ s/\s*\bNote:\s*(.*)$//i) { (my $n = $1) =~ s/\s*\.?\s*$//; $p{'Informational Statement(s)'} = $n if $n ne '' }
    $s =~ s/\s*\.\s*$//;
    my $sentences = 1 + (() = $s =~ /(?<!\be\.g)(?<!\bi\.e)(?<!\bSec)(?<!\bNo)(?<!\bpara)(?<!\bFig)(?<!\bvs)(?<!\bapprox)\.\s+(?=[A-Z])/g);
    $p{_sentences} = $sentences;
    my @ops = $s =~ /\b(shall|will|should|may|must)\b/gi;
    $p{_ops} = [ map { lc } @ops ];
    return \%p unless $s =~ /^(.*?)\b(shall|will|should|may|must)\b\s*(.*)$/i;
    my ($pre, $op, $post) = ($1, lc $2, $3);
    $p{'Operative Verb'} = $op;
    $pre =~ s/[\s,]+$//;
    # context clauses before the verb
    my @cl = split_commas($pre);
    if (@cl == 1 && $cl[0] =~ /^(while|when|during|upon|on|every|after|before|if|once|at)\b\s*(.*?)\s+((?:the|each|every|all|any|a|an)\s+\S.*)$/i) {
        @cl = ("$1 $2", $3);                       # "While in observing mode the station" without a comma
    }
    my (@state, @trigger, @exc);
    my $subject;
    my ($last) = grep { !/^for\s+(?:the\s+)?.+?\s+function$/i } reverse @cl;   # the subject: the last clause that is not the allocated function
    $last //= '';
    for my $c (@cl) {
        if ($c eq $last && @cl) { $subject = defined $subject ? "$subject, $c" : $c; next }
        if    ($c =~ /^(while|when|during)\b\s*(.*)$/i)                     { push @state, $c }
        elsif ($c =~ /^(upon|on|every|after|before|if|once|at)\b\s*(.*)$/i)  { push @trigger, $c }
        elsif ($c =~ /^except\b\s*(.*)$/i)                                    { push @exc, $1 }
        elsif ($c =~ /^for\s+(?:the\s+)?(.+?)\s+function$/i)                  { $p{'Allocated Function'} = $1 }
        else  { $subject = defined $subject ? "$subject, $c" : $c }
    }
    $p{'State'} = join('; ', @state) if @state;
    $p{'Trigger'} = join('; ', @trigger) if @trigger;
    if (@state || @trigger) {
        my @pc = map { (my $x = $_) =~ s/^(while|when|during|upon|on|every|after|before|if|once|at)\s+//i; $x } (@state, @trigger);
        $p{'Preconditions'} = join '; ', @pc;
    }
    if (defined $subject && $subject =~ /\S/) { (my $t = $subject) =~ s/^(the|each|every|all|any|a|an)\s+//i; $p{'Specification Target'} = $t; $p{_subject} = $subject }
    # after the verb
    my $neg = $post =~ s/^not\s+//i ? 'not ' : '';
    my $tv;
    if    ($post =~ s/^(be\s+capable\s+of|be\s+able\s+to|have\s+the\s+(?:capability|ability)\s+to)\s+//i) { $tv = lc $1; $tv =~ s/\s+/ /g }
    elsif ($post =~ s/^(\w+)\s*//) { $tv = lc $1 }
    if (defined $tv) {
        $p{'Target Verb'} = $neg . $tv;
        $p{_verb} = $tv;
        if ($tv eq 'be' && $post =~ /^(\w+(?:ed|en)|kept|made|held|sent|built|set|put|found|shown|done|led|run|met|paid|brought|caught|left|lost|split|cut|shut|spread)\b/i) { $p{_passive} = $1 }
        $p{_inner_verb} = lc $1 if $tv =~ /^(?:be capable of|be able to|have the \w+ to)$/ && $post =~ /^(\w+)/;
    }
    if ($post =~ s/,?\s*\bin\s+accordance\s+with\s+(.*?)(?=,?\s*\bexcept\b|$)//i) {
        my $spec = $1;
        if ($spec =~ s/\s*\b(?:Section|Sec\.?|para(?:graph)?\.?|§)\s*(\d+(?:\.\d+)*)\b//i) { $p{'Section Number'} = $1 }
        if ($spec =~ s/\s*\(([A-Za-z0-9][\w\-.\/]*\d[\w\-.\/]*)\)//) { $p{'Document Number'} = $1 }
        $spec =~ s/^\s*(the\s+)?|\s*[,.]?\s*$//gi;
        $p{'Specification'} = $spec if $spec ne '';
    }
    if ($post =~ s/,?\s*\bexcept\b\s*(.*)$//i) { push @exc, $1 }
    $p{'Exception(s)'} = join('; ', map { (my $x = $_) =~ s/[,.\s]+$//; $x } @exc) if @exc;
    $post =~ s/[,\s]+$//;
    # precise objects, then modifier / modification pairs
    my ($obj, @mods) = ($post);
    if ($post =~ /^(.+?)\s+\b($MODRE)\b\s+(.*)$/i) {
        ($obj, my ($kw, $rest)) = ($1, lc $2, $3);
        while (defined $kw) {
            if ($rest =~ /^(.+?)\s+\b($MODRE)\b\s+(.*)$/i) { push @mods, [ $kw, $1 ]; ($kw, $rest) = (lc $2, $3) }
            else { push @mods, [ $kw, $rest ]; undef $kw }
        }
    }
    $obj =~ s/[,\s]+$//;
    $p{'Precise Object(s)'} = $obj if $obj =~ /\S/;
    if (@mods) { $p{'Modifier(s)'} = join('; ', map { $_->[0] } @mods); $p{'Modification(s)'} = join('; ', map { $_->[1] } @mods) }
    $p{_main} = $s;
    \%p;
}
sub split_commas {                              # split at commas outside parentheses
    my ($t) = @_;
    my @out; my ($cur, $d) = ('', 0);
    for my $ch (split //, $t) {
        if ($ch eq '(') { $d++ } elsif ($ch eq ')') { $d-- if $d }
        if ($ch eq ',' && !$d) { push @out, $cur; $cur = ''; next }
        $cur .= $ch;
    }
    push @out, $cur;
    grep { $_ ne '' } map { (my $x = $_) =~ s/^\s+|\s+$//g; $x } @out;
}

# ---------------------------------------------------------------- grade
sub grade {
    my ($r, %o) = @_;
    my $p = parse($r->{text});
    $p->{'Requirement ID'} //= $r->{id} if defined $r->{id} && $r->{id} ne '';
    $p->{'Classification'} //= $r->{class} if defined $r->{class};
    push @{ $p->{'Requirement Tags'} }, map { uc } @{ $r->{tags} } if $r->{tags} && @{ $r->{tags} };
    my (@missing, @f);
    my @req = @REQUIRED;
    unshift @req, 'Classification' if $o{require_class};
    for my $k (@req) { push @missing, $k unless defined $p->{$k} && (ref $p->{$k} ? @{ $p->{$k} } : $p->{$k} =~ /\S/) }
    my $add = sub { push @f, { sev => $_[0], msg => $_[1] } };
    my $tv = $p->{_verb} // '';
    if ($tv =~ /^(be capable of|be able to|have the \w+ to)$/) {
        $add->(major => "weak target verb '$tv'" . (defined $p->{_inner_verb} ? " $p->{_inner_verb}" : '') . ": state the action itself ('shall " . ($p->{_inner_verb} // 'VERB') . "'), with its threshold");
    } elsif ($WEAK{$tv}) {
        $add->(major => "weak target verb '$tv' ($WEAK{$tv}): rarely verifiable -- name the concrete action (send, store, measure, report ...)") unless $tv eq 'be' && $p->{_passive};
    }
    $add->(minor => "passive voice 'shall be $p->{_passive}': make the specification target the one that acts") if $p->{_passive};
    my @ops = @{ $p->{_ops} // [] };
    $add->(major => scalar(@ops) . " operative verbs (" . join(', ', @ops) . "): one requirement per statement -- split it") if @ops > 1;
    $add->(major => "$p->{_sentences} sentences: a requirement is a single sentence (move the rest to a Note: or a new requirement)") if ($p->{_sentences} // 1) > 1;
    my $op = $p->{'Operative Verb'} // '';
    $add->(info => "'must' as the operative verb: the recipe uses shall (requisite), will, should or may") if $op eq 'must';
    $add->(info => "'will' states a fact about an external actor, not a requirement on the specification target") if $op eq 'will';
    $add->(info => "'should' is a design guideline, not a requirement") if $op eq 'should';
    $add->(info => "'may' grants permission (design space), not a requirement") if $op eq 'may';
    my $main = $p->{_main} // '';
    my ($after) = $main =~ /\b(?:shall|will|should|may|must)\b(.*)$/i; $after //= '';
    if ($PERF_VERB{$tv} || $PERF_VERB{ $p->{_inner_verb} // '' }) {
        $add->(minor => "'$tv' with no measurable threshold (a number with a unit, within, every, at least, no more than ...)")
            unless $after =~ /\d/ || $after =~ /\b(within|every|per|at least|no more than|less than|twice|once|hourly|daily)\b/i;
    }
    $add->(minor => "a reference without " . join(' or ', (!defined $p->{'Document Number'} ? 'a document number' : ()), (!defined $p->{'Section Number'} ? 'a section' : ())) . ": cite both")
        if defined $p->{'Specification'} && (!defined $p->{'Document Number'} || !defined $p->{'Section Number'});
    for my $v (@VAGUE) {
        my $re = join '\s+', map { quotemeta } split / /, $v;
        $add->(minor => "vague wording '$v': replace it with a measurable criterion") if $main =~ /(?<![\w-])$re(?![\w-])/i;
    }
    for my $t (@{ $p->{'Requirement Tags'} // [] }) { $add->(minor => "unknown tag '$t' (known: " . join(', ', sort keys %KNOWN_TAG) . ")") unless $KNOWN_TAG{$t} }
    my %fail;
    if (my $ix = $o{links}) {                       # recipe elements 19-23
        my $lk = $r->{link} // {};
        my $id = $p->{'Requirement ID'} // $r->{id} // '';
        my %e = (parents => [], children => 0, satisfiers => [], cases => []);
        for my $k (grep { defined && length } $r->{name}, $id, $r->{id}) {
            my $x = $ix->{$k} or next;
            push @{ $e{$_} }, @{ $x->{$_} } for qw(parents satisfiers cases);
            $e{children} += $x->{children};
        }
        my %s; $e{$_} = [ grep { !$s{"$_\0"}++ } @{ $e{$_} } ] for qw(parents satisfiers cases);
        my $where = join '::', grep { defined && length } $r->{pkg}, $r->{name} // $id;
        my $top = @{ $o{top} // [] } ? (grep { $id =~ /$_/ || ($r->{name} // '') =~ /$_/ || ($r->{pkg} // '') =~ /$_/ } @{ $o{top} }) ? 1 : 0
                : (($lk->{level} // '') =~ /^top/i || ($r->{pkg} // '') =~ /stakeholder|\bneeds\b/i) ? 1 : 0;
        # 19 parent trace
        if (@{ $e{parents} }) { $p->{'Parent Trace'} = join ', ', @{ $e{parents} } }
        elsif (defined $lk->{derived_from} && $lk->{derived_from} =~ /\S/) {
            $p->{'Parent Trace'} = "derived from $lk->{derived_from}";
            $add->(info => "derived requirement (from $lk->{derived_from}): it needs its own review, not a parent's");
        }
        elsif ($top) { $p->{'Parent Trace'} = '(top level)' }
        else { push @missing, 'Parent Trace'; $fail{orphan} = 1 }
        if ($top && !$e{children} && !@{ $e{satisfiers} }) {
            $add->(minor => "childless: a top-level requirement with no derived requirement and nothing that satisfies it"); $fail{childless} = 1;
        }
        # 20 rationale
        my $rat = $lk->{rationale};
        if (defined $rat && $rat =~ /\S/) {
            $p->{'Rationale'} = $rat;
            if ($main =~ /\d/ && $rat !~ /\b(budget|allocat\w*|analys[ie]s|trade|study|standard|direction|directed|specif\w*|measured|survey|test(?:ed)?)\b/i
                && $rat !~ /\b[A-Z][A-Z0-9]*[-_][A-Z0-9][\w-]*\b/) {
                $add->(minor => "unjustified threshold: the statement has a number and the rationale names no source (a budget, an analysis, a trade study, a standard, a direction, or an id)");
                $fail{unjustified} = 1;
            }
        } else {
            push @missing, 'Rationale';
            $fail{unjustified} = 1 if $main =~ /\d/;
        }
        # 21 verification method (shall statements)
        my $m = $lk->{method};
        if (defined $m && $m =~ /\S/) {
            if ($METHOD{ lc $m }) { $p->{'Verification Method'} = $METHOD{ lc $m } }
            else { $p->{'Verification Method'} = $m; $add->(major => "verification method '$m': use Test, Analysis, Demonstration or Inspection"); $fail{unverified} = 1 }
        } elsif ($op eq 'shall') { push @missing, 'Verification Method'; $fail{unverified} = 1 }
        # 22 verification case, 23 satisfied by -- required by the baseline
        if (@{ $e{cases} }) { $p->{'Verification Case'} = join ', ', @{ $e{cases} } }
        elsif ($op eq 'shall') {
            $fail{unverified} = 1;
            if ($o{baseline}) { push @missing, 'Verification Case' } else { $add->(info => "no verification case yet (required by the baseline; --baseline makes it missing)") }
        }
        if (@{ $e{satisfiers} }) { $p->{'Satisfied By'} = join ', ', @{ $e{satisfiers} } }
        elsif (!$top) {
            $fail{unsatisfied} = 1;
            if ($o{baseline}) { push @missing, 'Satisfied By' } else { $add->(info => "nothing satisfies it yet (required by the design baseline; --baseline makes it missing)") }
        }
        # safety tags need a hazard; the Note: must not carry the rationale or the verification
        my @safety = grep { /^(SC|SR)$/ } @{ $p->{'Requirement Tags'} // [] };
        if (@safety && !@{ $lk->{hazards} // [] }) {
            $add->(major => "unmitigated safety tag ($safety[0]): link the hazard it mitigates (attribute hazard = \"HAZ-...\")"); $fail{unmitigated} = 1;
        }
        my $note = $p->{'Informational Statement(s)'} // '';
        $add->(minor => "the Note: carries a rationale or the verification approach: move it to the Rationale or Verification field")
            if $note =~ /\b(because|rationale|so that we|verified by|verification|will be tested|to be tested)\b/i;
    }
    my $score = 100 - $SEV_COST{missing} * @missing;
    $score -= $SEV_COST{ $_->{sev} } for @f;
    $score = 0 if $score < 0;
    return { %$r, id => $p->{'Requirement ID'} // $r->{id} // '?', parts => $p, missing => \@missing, findings => \@f, score => $score, link_fail => \%fail };
}

# ---------------------------------------------------------------- output
sub part_text { my $v = shift; ref $v ? join(', ', @$v) : $v }
sub to_text {
    my ($g) = @_;
    my $o = '';
    for my $r (@$g) {
        $o .= sprintf "%s  score %d  %s:%d%s\n", $r->{id}, $r->{score}, $r->{file}, $r->{line}, defined $r->{title} ? "  ($r->{title})" : '';
        $o .= "  $r->{text}\n";
        for my $k (@PARTS, ($LINKS ? @LINK_PARTS : ())) {
            my $v = $r->{parts}{$k};
            next unless defined $v && (ref $v ? @$v : 1);
            $o .= sprintf "    %-27s %s\n", $k, part_text($v);
        }
        $o .= "    missing: " . join(', ', @{ $r->{missing} }) . "\n" if @{ $r->{missing} };
        $o .= sprintf "    %-6s %s\n", $_->{sev}, $_->{msg} for @{ $r->{findings} };
        $o .= "\n";
    }
    $o;
}
sub csvq { my $v = shift // ''; $v =~ s/"/""/g; qq("$v") }
sub to_csv {
    my ($g) = @_;
    my @cols = (@PARTS, ($LINKS ? @LINK_PARTS : ()));
    my $o = join(',', 'id', 'score', 'missing', 'findings', 'file', 'line', 'text', @cols) . "\r\n";
    for my $r (@$g) {
        $o .= join(',', map { csvq($_) } $r->{id}, $r->{score}, join('; ', @{ $r->{missing} }),
            join('; ', map { "$_->{sev}: $_->{msg}" } @{ $r->{findings} }), $r->{file}, $r->{line}, $r->{text},
            map { my $v = $r->{parts}{$_}; defined $v ? part_text($v) : '' } @cols) . "\r\n";
    }
    $o;
}
sub xmlq { my $t = shift // ''; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t }
sub to_junit {
    my ($g) = @_;
    my $bad = grep { @{ $_->{missing} } || @{ $_->{findings} } } @$g;
    my $o = qq(<?xml version="1.0" encoding="UTF-8"?>\n<testsuites>\n<testsuite name="requirement recipe" tests=") . scalar(@$g) . qq(" failures="$bad">\n);
    for my $r (@$g) {
        $o .= qq(  <testcase classname="recipe" name=") . xmlq("$r->{id}") . qq(" file=") . xmlq($r->{file}) . qq(">);
        if (@{ $r->{missing} } || @{ $r->{findings} }) {
            my @m = ((map { "missing: $_" } @{ $r->{missing} }), map { "$_->{sev}: $_->{msg}" } @{ $r->{findings} });
            $o .= qq(\n    <failure message=") . xmlq("score $r->{score}: $m[0]") . qq(">) . xmlq(join("\n", $r->{text}, @m)) . qq(</failure>\n  );
        }
        $o .= "</testcase>\n";
    }
    $o . "</testsuite>\n</testsuites>\n";
}
sub jstr { my $t = shift // ''; $t =~ s/\\/\\\\/g; $t =~ s/"/\\"/g; $t =~ s/\n/\\n/g; $t =~ s/\t/\\t/g; $t =~ s/([\x00-\x1f])/sprintf('\\u%04x', ord $1)/ge; qq("$t") }
sub to_codequality {
    my ($g) = @_;
    my @items;
    my %CQ = (missing => 'major', major => 'major', minor => 'minor', info => 'info');
    for my $r (@$g) {
        my @m = ((map { [ missing => "missing required part: $_" ] } @{ $r->{missing} }), map { [ $_->{sev}, $_->{msg} ] } @{ $r->{findings} });
        for my $x (@m) {
            my $desc = "$r->{id}: $x->[1]";
            push @items, '  {"description": ' . jstr($desc) . ', "check_name": "requirement-recipe", "fingerprint": ' . jstr(md5_hex("$r->{file}\0$r->{id}\0$x->[1]"))
                . ', "severity": ' . jstr($CQ{ $x->[0] }) . ', "location": {"path": ' . jstr($r->{file}) . ', "lines": {"begin": ' . ($r->{line} + 0) . '}}}';
        }
    }
    "[\n" . join(",\n", @items) . (@items ? "\n" : '') . "]\n";
}
