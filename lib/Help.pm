package Help;
# Offline help for the kit, from ONE source: the Vim help files in vim/doc/ (agile.txt, agile-errors.txt).
# The same text is read four ways:
#   in Vim                 :help agile, :help :STown, :help agile-err-...   (vim/scrum.vim runs :helptags)
#   on the command line    perl agile.pl help [TOPIC | search WORDS | error "MESSAGE"]; daily.pl/scrum.pl/ledger.pl help
#   as a page              docs/HELP.html            (perl agile.pl help --html)
#   as a binder chapter    docs/help/quickref.md     (perl agile.pl help --md; pandoc-friendly Markdown)
# Core Perl only (5.10+). No state: every call parses the files again (they are small).
#
# Source conventions (a subset of Vim's help format):
#   *tag*          a tag; a line ending in tags is a heading (title = the text before them, or the next line)
#   |tag|          a link to a tag
#   ====...        (78 '=') a chapter: its heading is the next heading line, level 1
#   ----...        (78 '-') a section: level 2; any other heading is level 3
#   a line ending in " >" starts an example; indented lines follow; a line starting with "<" (or not indented) ends it
#   Pattern: GLOB  (error catalog) a message the entry explains; * matches anything
#   Internal: GLOB (error catalog) an internal-invariant message: listed, not explained
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

our $VERSION = '1.00';
my $TAGRE = qr/(?:^|(?<=\s))\*([^*\s|]+)\*(?=\s|$)/;    # what Vim's :helptags accepts
my $LINKRE = qr/(?:^|(?<=[\s(]))\|([^"*|\s]+)\|(?=[\s.,;:)]|$)/;

sub root { require Cwd; my $d = dirname(File::Spec->rel2abs(__FILE__)); Cwd::abs_path(File::Spec->catdir($d, File::Spec->updir)) }
sub doc_files { my $r = shift // root(); grep { -f } map { "$r/vim/doc/$_" } qw(agile.txt agile-errors.txt) }

# ---------------------------------------------------------------- parse
sub load {
    my %o = @_;
    my @files = $o{files} ? @{ $o{files} } : doc_files($o{root});
    my (@sec, %tags, @all);
    for my $f (@files) {
        open my $fh, '<:raw', $f or die "help: cannot read $f: $!\n";
        my @l = map { s/\r?\n\z//; $_ } <$fh>;
        close $fh;
        (my $base = $f) =~ s{.*/}{};
        my $lvl = 3;
        my $ex = 0;
        for my $i (0 .. $#l) {
            my $line = $l[$i];
            if ($ex) { $ex = 0 if $line =~ /^</ || ($line =~ /^\S/) }
            if ($line =~ /^={20,}\s*$/) { $lvl = 1; next }
            if ($line =~ /^-{20,}\s*$/) { $lvl = 2 if $lvl != 1; next }
            my @t = $ex ? () : ($line =~ /$TAGRE/g);
            if (@t && $line =~ /\*\s*$/ && $i > 0) {             # a heading: tags at the end of the line (not the file's first line)
                (my $title = $line) =~ s/$TAGRE//g;
                $title =~ s/^\s+|\s+$//g;
                if (@sec && $sec[-1]{src} == \@l && $sec[-1]{last_head} == $i - 1) {   # consecutive heading lines are one section: :STown / \sw
                    push @{ $sec[-1]{tags} }, @t; $sec[-1]{last_head} = $i;
                    for (@t) { $tags{$_} //= $sec[-1] }
                    next;
                }
                my $start = $i;
                if ($title eq '' && $l[$i - 1] =~ /\S/ && $l[$i - 1] !~ /^(?:={20,}|-{20,})\s*$/) { $start = $i - 1; ($title = $l[$i - 1]) =~ s/^\s+|\s+$//g }   # a long first line, its tags on the next
                if ($title eq '') { for my $j ($i + 1 .. $#l) { next if $l[$j] =~ /^\s*$/; last if $l[$j] =~ $TAGRE && $l[$j] =~ /\*\s*$/; ($title = $l[$j]) =~ s/^\s+|\s+$//g; last } }
                my $s = { file => $base, line => $start + 1, start => $start, level => $lvl, tags => [ @t ], title => $title, src => \@l, last_head => $i };
                push @sec, $s;
                $lvl = 3;
                for (@t) { $tags{$_} //= $s }
            }
            elsif (@t) { push @all, @t }                         # the file tag on line 1
            $ex = 1 if !$ex && $line =~ /(?:^|\s)>$/;
        }
    }
    for my $k (0 .. $#sec) {                                     # a section runs to the next heading of the same or a higher level
        my $s = $sec[$k];
        my $end = scalar @{ $s->{src} };
        for my $m ($k + 1 .. $#sec) {
            my $n = $sec[$m];
            last if $n->{src} != $s->{src} && do { $end = scalar @{ $s->{src} }; 1 };
            if ($n->{level} <= $s->{level}) { $end = $n->{start}; last }
        }
        my $stop = $end;                                         # do not swallow the separator line that opens the next chapter
        $stop-- while $stop > $s->{start} + 1 && $s->{src}[$stop - 1] =~ /^(?:={20,}|-{20,})?\s*$/;
        $s->{end} = $stop;
        my $next = $k < $#sec && $sec[$k + 1]{src} == $s->{src} ? $sec[$k + 1]{start} : scalar @{ $s->{src} };
        my $own = $next;                                         # the heading's own text, up to the next heading of any level
        $own-- while $own > $s->{start} + 1 && $s->{src}[$own - 1] =~ /^(?:={20,}|-{20,})?\s*$/;
        $s->{own_end} = $own;
    }
    { sections => \@sec, tags => \%tags, filetags => \@all, files => \@files };
}

sub lines_of { my ($s, %o) = @_; my $e = $o{own} ? $s->{own_end} : $s->{end}; @{ $s->{src} }[ $s->{start} .. $e - 1 ] }
sub section_text { my ($s, %o) = @_; join '', map { "$_\n" } lines_of($s, %o) }

# ---------------------------------------------------------------- plain text (the CLI)
sub plain {                                                      # Vim help markup -> plain text
    my @out;
    my $ex = 0;
    for my $line (@_) {
        my $l = $line;
        if ($ex && ($l =~ /^</ || $l =~ /^\S/)) { $ex = 0; $l =~ s/^<//; next if $l =~ /^\s*$/ && $line =~ /^<\s*$/ }
        if (!$ex) {
            if ($l =~ /\*\s*$/ && $l =~ $TAGRE) { $l =~ s/\s*$TAGRE//g; next if $l =~ /^\s*$/ }   # heading tags; a tag-only line goes
            $l =~ s/$LINKRE/$1/g;
            $l =~ s/`([^`]+)`/$1/g;
        }
        if (!$ex && $l =~ s/(^|\s)>$//) { $ex = 1 }
        $l =~ s/\s+$//;
        push @out, $l;
    }
    shift @out while @out && $out[0] eq '';
    pop @out while @out && $out[-1] eq '';
    my $t = join("\n", @out);
    $t =~ s/\n{3,}/\n\n/g;
    "$t\n";
}

# ---------------------------------------------------------------- lookup
my @PREFIX = ('', 'agile-', 'agile-daily-', 'agile-howto-', 'agile-verb-', 'agile-conf-', 'agile-scrum-', 'agile-ledger-',
              'agile-err-', 'agile-practice-', 'agile-idef0-', ':', ':S', ':Idef');
sub resolve {                                                    # name -> section (exact tag, then common prefixes, then any case)
    my ($h, $name) = @_;
    return undef unless defined $name && length $name;
    $name =~ s/^\s+|\s+$//g;
    $name =~ s/^\|(.*)\|$/$1/;
    $name =~ s/^\*(.*)\*$/$1/;
    my @try = ($name, $name =~ /\s/ ? join('-', split ' ', lc $name) : ());
    for my $n (@try) { for my $p (@PREFIX) { return $h->{tags}{"$p$n"} if $h->{tags}{"$p$n"} } }
    my %lc = map { (lc $_ => $h->{tags}{$_}) } keys %{ $h->{tags} };
    for my $n (@try) { for my $p (@PREFIX) { return $lc{ lc "$p$n" } if $lc{ lc "$p$n" } } }
    if ($name =~ /^(?:<leader>|<localleader>)(\w+)$/i) { return resolve($h, "\\$1") }
    undef;
}

sub _words { my $t = lc shift; $t =~ s/[^a-z0-9_:\\\-]+/ /g; grep { length > 1 } map { my $w = $_; $w =~ s/[:-]+$//; $w =~ s/^-+//; $w } split ' ', $t }
sub search {                                                     # -> ( [score, section, snippet], ... ) best first; every word must appear
    my ($h, @q) = @_;
    my @w = map { _words($_) } @q;
    return () unless @w;
    my @hits;
    for my $s (@{ $h->{sections} }) {
        my $body = lc join("\n", lines_of($s, own => 1));
        my $tags = lc join(' ', @{ $s->{tags} });
        my $title = lc $s->{title};
        my ($score, $all) = (0, 1);
        for my $w (@w) {
            my $n = () = $body =~ /\Q$w\E/g;
            $all = 0, last unless $n;
            $score += ($tags =~ /(?:^|[\s\-:])\Q$w\E(?:$|[\s\-])/ ? 12 : $tags =~ /\Q$w\E/ ? 6 : 0) + ($title =~ /\b\Q$w\E/ ? 5 : 0) + ($n > 5 ? 5 : $n);
        }
        next unless $all;
        $score -= 8 if $s->{file} =~ /errors/ && !grep { /err|error|fail|cannot|refus/ } @w;   # the catalog is for pasted messages
        my ($snip) = grep { my $l = lc $_; !grep { index($l, $_) < 0 } @w } map { my $x = $_; $x =~ s/^\s+//; $x } lines_of($s, own => 1);
        $snip //= '';
        $snip =~ s/\s*$TAGRE//g; $snip =~ s/$LINKRE/$1/g;
        push @hits, [ $score, $s, substr($snip, 0, 70) ];
    }
    sort { $b->[0] <=> $a->[0] || $a->[1]{file} cmp $b->[1]{file} || $a->[1]{line} <=> $b->[1]{line} } @hits;
}

# ---------------------------------------------------------------- the error catalog
sub catalog {                                                    # -> ( {tag, title, section, patterns => [...]}, ... ), and internal globs
    my $h = shift;
    my (@e, @internal);
    for my $s (@{ $h->{sections} }) {
        my @t = grep { /^agile-err-/ } @{ $s->{tags} } or next;
        my (@p, @i);
        for (lines_of($s, own => 1)) { push @p, $1 if /^\s*Pattern:\s+(.+?)\s*$/; push @i, $1 if /^\s*Internal:\s+(.+?)\s*$/ }
        push @internal, @i;
        push @e, { tag => $t[0], title => $s->{title}, section => $s, patterns => \@p } if @p;
    }
    wantarray ? @e : \@e;
}
sub internal_patterns { my $h = shift; my @i; for my $s (@{ $h->{sections} }) { next unless grep { /^agile-err-/ } @{ $s->{tags} }; for (lines_of($s, own => 1)) { push @i, $1 if /^\s*Internal:\s+(.+?)\s*$/ } } @i }
sub glob_re { my $g = shift; my @p = split /\*/, $g, -1; my $re = join '.*?', map { quotemeta } @p; qr/$re/s }
sub _lit { my $g = shift; $g =~ s/\*//g; length $g }
sub _clean_msg {
    my $m = shift // '';
    $m =~ s/\r//g;
    $m =~ s/ at \S+ line \d+\.?\s*$//mg;                         # "... at bin/x.pl line 12." (a die without a newline)
    $m =~ s/^\s+|\s+$//g;
    $m =~ s/[ \t]+/ /g;
    $m;
}
sub error_match {                                                # -> (best entry, $how) ; how = 'pattern' | 'closest' ; or () when nothing is close
    my ($h, $msg) = @_;
    my @cat = catalog($h);
    my @lines = grep { length } map { _clean_msg($_) } split /\n/, _clean_msg($msg);
    @lines = (_clean_msg($msg)) unless @lines;
    my ($best, $bs);
    for my $line (@lines) {
        for my $e (@cat) { for my $p (@{ $e->{patterns} }) {
            next unless $line =~ glob_re($p);
            my $sc = _lit($p);
            ($best, $bs) = ($e, $sc) if !defined $bs || $sc > $bs;
        } }
        last if $best;                                           # the first line that matches wins (the headline of a pasted block)
    }
    return ($best, 'pattern') if $best;
    my %q = map { $_ => 1 } _words($msg);
    return () unless %q;
    my @r = sort { $b->[0] <=> $a->[0] } map { my $e = $_; my %w = map { $_ => 1 } _words(join ' ', $e->{title}, @{ $e->{patterns} }); [ scalar(grep { $w{$_} } keys %q), $e ] } @cat;
    return () unless @r && $r[0][0] >= 2;
    ($r[0][1], 'closest', map { $_->[1] } grep { $_->[0] >= 2 } @r[1 .. ($#r < 2 ? $#r : 2)]);
}

# ---------------------------------------------------------------- the command line
sub index_text {
    my $h = shift;
    my $out = "Offline help for the agile kit. The source is vim/doc/agile.txt (in Vim: :help agile).\n\n"
            . "  perl agile.pl help TOPIC          one section: a command, verb, key, scrum.conf key, runbook\n"
            . "  perl agile.pl help search WORDS   sections that mention every word, best first\n"
            . "  perl agile.pl help error \"MSG\"    paste an error message: what it means and the fix\n"
            . "  perl agile.pl practice            hands-on lessons in a sandbox project\n"
            . "  perl bin/daily.pl help [CMD]      (also scrum.pl, ledger.pl) that tool's section\n"
            . "  docs/HELP.html                    the same text as one printable page\n";
    my @top = grep { $_->{level} == 1 && $_->{file} eq 'agile.txt' && $_->{tags}[0] ne 'agile-contents' } @{ $h->{sections} };
    for my $c (@top) {
        $out .= "\n" . $c->{title} . "   (" . _short($c->{tags}[0]) . ")\n";
        my @in = grep { $_->{src} == $c->{src} && $_->{start} > $c->{start} && $_->{start} < $c->{end} } @{ $h->{sections} };
        my @kids = grep { $_->{level} == 2 } @in;
        my $wrap = sub {
            my $line = '      '; my $o = '';
            for my $w (map { my $t = _short($_->{tags}[0]); $t =~ s/^(?:daily|verb|conf|scrum|ledger|idef0)-//; $t } @_) {
                if (length($line) + length($w) > 77) { $o .= "$line\n"; $line = '      ' }
                $line .= "$w ";
            }
            $line =~ s/\s+$//;
            $o . ($line =~ /\S/ ? "$line\n" : '');
        };
        my @loose = grep { my $x = $_; $x->{level} == 3 && !grep { $x->{start} > $_->{start} && $x->{start} < $_->{end} } @kids } @in;
        $out .= "  " . join(' ', map { _short($_->{tags}[0]) } @loose) . "\n" if @loose && @loose <= 3;
        $out .= $wrap->(@loose) if @loose > 3;
        for my $k (@kids) {
            $out .= sprintf "  %-28s %s\n", _short($k->{tags}[0]), $k->{title};
            $out .= $wrap->(grep { $_->{level} == 3 && $_->{start} > $k->{start} && $_->{start} < $k->{end} } @in);
        }
    }
    $out .= "\nTroubleshooting: perl agile.pl help error \"MESSAGE\", or perl agile.pl help errors (the catalog).\n";
    $out;
}
sub _short { my $t = shift; $t =~ s/^agile-//; $t }

sub cli {                                                        # perl agile.pl help ... -> exit status
    my @a = @_;
    shift @a if @a && $a[0] =~ /^(?:help|--help|-h)$/;
    binmode STDOUT, ':raw';
    my $h = eval { load() } or do { print STDERR $@ || "help: no help files in vim/doc/\n"; return 1 };
    if (!@a) { print index_text($h); return 0 }
    my $what = shift @a;
    if ($what eq '--html') { my $out = shift(@a) // root() . '/docs/HELP.html'; _write($out, html($h)); print "wrote $out\n"; return 0 }
    if ($what eq '--md')   { my $out = shift(@a) // root() . '/docs/help/quickref.md'; _write($out, markdown($h)); print "wrote $out\n"; return 0 }
    if ($what eq '--check') { my $r = audit($h); print $r->{text}; return $r->{problems} ? 1 : 0 }
    if ($what eq '--tags')  { print map { "$_\n" } sort keys %{ $h->{tags} }; return 0 }
    if ($what eq 'errors' && !@a) {                              # the catalog as a list
        print "The error catalog (vim/doc/agile-errors.txt). One entry: perl agile.pl help TAG; a message: perl agile.pl help error \"MSG\"\n";
        for my $s (grep { $_->{file} eq 'agile-errors.txt' } @{ $h->{sections} }) {
            if ($s->{level} == 1) { print "\n$s->{title}\n"; next }
            printf "  %-30s %s\n", $s->{tags}[0], $s->{title};
        }
        return 0;
    }
    if ($what eq 'search') {
        if (!@a) { print STDERR "usage: perl agile.pl help search WORDS\n"; return 2 }
        my @hits = search($h, @a);
        if (!@hits) { print "nothing mentions all of: @a\n"; return 1 }
        my $n = @hits > 12 ? 12 : @hits;
        print "sections mentioning @a (best first; perl agile.pl help TAG shows one):\n";
        printf "  %-30s %s\n%s", $_->[1]{tags}[0], $_->[1]{title}, ($_->[2] ne '' && $_->[2] ne $_->[1]{title} ? "  " . (' ' x 30) . " | $_->[2]\n" : '') for @hits[0 .. $n - 1];
        print "  ... and " . (@hits - $n) . " more\n" if @hits > $n;
        return 0;
    }
    if ($what eq 'error' || $what eq 'err') {
        my $msg = @a ? join(' ', @a) : do { local $/; my $in = <STDIN>; $in // '' };
        if ($msg !~ /\S/) { print STDERR "usage: perl agile.pl help error \"PASTED MESSAGE\"   (or pipe it in)\n"; return 2 }
        my ($e, $how, @more) = error_match($h, $msg);
        if (!$e) { print "no catalog entry matches that message.\ntry: perl agile.pl help search WORDS   (a few distinctive words from it)\n"; return 1 }
        print $how eq 'pattern' ? "" : "no exact match; the closest entry:\n\n";
        print plain(lines_of($e->{section}, own => 1));
        print "\n(in Vim: :help $e->{tag})\n";
        print "also close: " . join(', ', map { $_->{tag} } @more) . "\n" if @more;
        return 0;
    }
    my $name = join ' ', $what, @a;
    my $s = resolve($h, $name);
    if ($s) { print plain(lines_of($s)); return 0 }
    my @hits = search($h, $what, @a);
    print "no topic '$name'.", (@hits ? " Closest:\n" . join('', map { sprintf "  %-30s %s\n", $_->[1]{tags}[0], $_->[1]{title} } @hits[0 .. ($#hits < 7 ? $#hits : 7)]) : " Try: perl agile.pl help search WORDS\n");
    1;
}
sub tool_cli {                                                   # daily.pl / scrum.pl / ledger.pl help [CMD]
    my ($tool, @a) = @_;
    shift @a if @a && $a[0] =~ /^(?:help|--help|-h)$/;
    binmode STDOUT, ':raw';
    my $h = eval { load() } or do { print STDERR $@ || "help: no help files in vim/doc/\n"; return 1 };
    my $s = @a ? ($h->{tags}{"agile-$tool-$a[0]"} // resolve($h, join ' ', @a)) : $h->{tags}{"agile-$tool"};
    if (!$s) { print "no help for '@a'. perl agile.pl help search @a\n"; return 1 }
    print plain(lines_of($s, own => !@a && $tool ne 'ledger' && $tool ne 'scrum' ? 1 : 0));
    print "\nOne command: perl bin/$tool.pl help COMMAND. Everything: perl agile.pl help\n" unless @a;
    0;
}
sub _write { my ($f, $t) = @_; my $d = dirname($f); mkdir $d unless -d $d; open my $fh, '>:raw', $f or die "help: cannot write $f: $!\n"; print $fh $t; close $fh or die "help: cannot write $f: $!\n" }

# ---------------------------------------------------------------- HTML (docs/HELP.html)
sub _esc { my $t = shift; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t }
sub anchor { my $t = shift; $t =~ s/([^A-Za-z0-9_-])/sprintf '_%02X', ord $1/ge; "t-$t" }
sub _inline_html {                                               # escaped text with |links| and *tags* made into anchors
    my ($h, $t) = @_;
    $t = _esc($t);
    $t =~ s{(?:^|(?<=[\s(]))\|([^"*|\s]+)\|(?=[\s.,;:)]|$)}{ my $x = $1; my $raw = $x; $raw =~ s/&amp;/&/g; $raw =~ s/&lt;/</g; $raw =~ s/&gt;/>/g; $h->{tags}{$raw} ? '<a href="#' . anchor($raw) . '">' . $x . '</a>' : $x }ge;
    $t =~ s{`([^`]+)`}{<code>$1</code>}g;
    $t;
}
sub _blocks {                                                    # body lines -> ( [kind, @lines] ): 'p' prose, 'pre' aligned text or an example
    my @l = @_;
    my (@b, $ex);
    for my $line (@l) {
        my $x = $line;
        if ($ex) {
            if ($x =~ /^</ || $x =~ /^\S/) { $ex = 0; $x =~ s/^<//; next if $x =~ /^\s*$/ }
            else { push @{ $b[-1] }, $x; next }
        }
        if ($x =~ s/(^|\s)>$//) {
            if ($x =~ /\S/) { if (@b && $b[-1][0] eq 'p' && $x =~ /^ {1,3}\S/) { push @{ $b[-1] }, $x } else { push @b, [ 'p', $x ] } }
            push @b, [ 'ex' ];
            $ex = 1; next;
        }
        if ($x =~ /^\s*$/) { push @b, [ 'gap' ]; next }
        my $kind = ($x =~ /^ {4}|^\t/ || $x =~ /\S {2,}\S/ || $x =~ /\t/) ? 'pre' : 'p';   # up to 3 spaces of indent is a list item's continuation
        my $item = $x =~ /^(?:\d+\.|-)\s/;
        my $after_cont = $kind eq 'p' && @b && $b[-1][0] eq 'p' && $b[-1][-1] =~ /^ / && $x =~ /^\S/;   # column 0 after a list item's continuation: a new paragraph
        if (@b && $b[-1][0] eq $kind && !($kind eq 'p' && ($item || $after_cont))) { push @{ $b[-1] }, $x } else { push @b, [ $kind, $x ] }
    }
    grep { $_->[0] ne 'gap' && @$_ > 1 } @b;
}
sub _detab { my $l = shift; 1 while $l =~ s/^([^\t]*)\t/$1 . (' ' x (8 - length($1) % 8))/e; $l }
sub _section_html {
    my ($h, $s) = @_;
    my $tag = $s->{tags}[0];
    my $hn = $s->{level} == 1 ? 'h2' : $s->{level} == 2 ? 'h3' : 'h4';
    my $ids = join '', map { '<span id="' . anchor($_) . '"></span>' } @{ $s->{tags} }[ 1 .. $#{ $s->{tags} } ];
    my $out = "<$hn id=\"" . anchor($tag) . "\">$ids" . _esc($s->{title}) . ' <span class=tag>' . _esc(join ' ', @{ $s->{tags} }) . "</span></$hn>\n";
    my @body = lines_of($s, own => 1);
    shift @body;                                                 # the heading line
    shift @body if $s->{src}[ $s->{start} ] =~ /^\s*(?:\*[^*\s]+\*\s*)+$/ && @body && $body[0] =~ /^\S/ && do { (my $t = $body[0]) =~ s/^\s+|\s+$//g; $t eq $s->{title} };   # a title on the line after a tag-only line
    for my $b (_blocks(map { _detab($_) } @body)) {
        my ($kind, @l) = @$b;
        if ($kind eq 'p') { $out .= '<p>' . _inline_html($h, join ' ', map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } @l) . "</p>\n" }
        else {
            my $min = 99; for (@l) { next unless /\S/; my ($i) = /^( *)/; $min = length $i if length $i < $min }
            $out .= '<pre' . ($kind eq 'ex' ? ' class=ex' : '') . '>' . join("\n", map { my $x = $_; $x = substr($x, $min) if length($x) >= $min; $x =~ s/\s+$//; _inline_html($h, $x) } @l) . "</pre>\n";
        }
    }
    $out;
}
sub html {
    my $h = shift;
    my @sec = @{ $h->{sections} };
    my @main = grep { $_->{file} eq 'agile.txt' } @sec;
    my @err  = grep { $_->{file} eq 'agile-errors.txt' } @sec;
    my @howto = grep { $_->{level} == 2 && $_->{tags}[0] =~ /^agile-howto-/ } @main;
    my @chap = grep { $_->{level} == 1 && $_->{tags}[0] ne 'agile-contents' } @main;
    my $toc = '';
    for my $c (@chap) {
        $toc .= '<li><a href="#' . anchor($c->{tags}[0]) . '">' . _esc($c->{title}) . "</a>";
        my @kids = $c->{tags}[0] eq 'agile-howto' ? () : grep { $_->{level} == 2 && $_->{src} == $c->{src} && $_->{start} > $c->{start} && $_->{start} < $c->{end} } @main;
        $toc .= '<ul>' . join('', map { '<li><a href="#' . anchor($_->{tags}[0]) . '">' . _esc($_->{title}) . '</a></li>' } @kids) . '</ul>' if @kids;
        $toc .= "</li>\n";
    }
    my $howto = join '', map { '<li><a href="#' . anchor($_->{tags}[0]) . '">' . _esc($_->{title}) . "</a></li>\n" } @howto;
    my $errs = join '', map { '<li><a href="#' . anchor($_->{tags}[0]) . '">' . _esc($_->{title}) . "</a></li>\n" } grep { $_->{level} == 2 || $_->{level} == 1 } @err;
    my $body = join '', map { ($_->{level} == 1 ? "<hr>\n" : '') . _section_html($h, $_) } grep { $_->{tags}[0] ne 'agile-contents' && $_->{tags}[0] ne 'agile' } @main, @err;
    <<"HTML";
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Help: the agile kit</title>
<!-- GENERATED by perl agile.pl help --html from vim/doc/agile.txt and vim/doc/agile-errors.txt. Do not edit: edit the source and regenerate. -->
<style>
  body { font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: 10.5pt; color: #1a1a1a;
         max-width: 1000px; margin: 1.5em auto; padding: 0 1.5em; line-height: 1.4; }
  h1 { font-size: 18pt; border-bottom: 2px solid #444; padding-bottom: 0.2em; margin-bottom: 0.3em; }
  h2 { font-size: 14pt; margin: 1.4em 0 0.3em; border-bottom: 1px solid #999; padding-bottom: 0.1em; }
  h3 { font-size: 12pt; margin: 1.1em 0 0.2em; }
  h4 { font-size: 10.5pt; margin: 0.9em 0 0.1em; }
  .tag { font-family: Consolas, "Courier New", monospace; font-size: 8.5pt; color: #777; font-weight: normal; }
  code, pre { font-family: Consolas, "Courier New", monospace; font-size: 9.5pt; }
  code { background: #f0f0f0; padding: 0 0.25em; border-radius: 2px; }
  pre { background: #f7f7f7; border: 1px solid #e2e2e2; padding: 0.35em 0.7em; margin: 0.3em 0; white-space: pre-wrap; }
  pre.ex { background: #f1f4f8; border-color: #d4dce6; }
  p { margin: 0.3em 0; }
  hr { border: 0; border-top: 2px solid #444; margin: 2em 0 0; }
  .cols { column-count: 2; column-gap: 2.2em; }
  .note { color: #555; font-size: 9.5pt; }
  ul { margin: 0.2em 0; }
  a { color: #1a4f8b; }
  \@media (max-width: 760px) { .cols { column-count: 1; } }
  \@media print { body { margin: 0; max-width: none; font-size: 9pt; } a { color: inherit; text-decoration: none; }
                 h2 { break-before: page; } h3, h4 { break-after: avoid; } pre { break-inside: avoid; } .cols { column-count: 2; } }
</style>
</head>
<body>
<h1>Help: the agile kit</h1>
<p>Everything here works offline with Git for Windows alone: its Perl and its Vim. The same text is in Vim
(<code>:help agile</code>) and on the command line (<code>perl agile.pl help TOPIC</code>,
<code>perl agile.pl help search WORDS</code>, <code>perl agile.pl help error "MESSAGE"</code>).
Hands-on lessons: <code>perl agile.pl practice</code>.</p>
<p class=note>Generated from <code>vim/doc/agile.txt</code> and <code>vim/doc/agile-errors.txt</code>
by <code>perl agile.pl help --html</code>. Edit the source, not this page.</p>
<h2 id="start-howto">How do I...?</h2>
<div class=cols><ul>
$howto</ul></div>
<h2 id="start-reference">Reference</h2>
<div class=cols><ul>
$toc</ul></div>
<h2 id="start-trouble">Troubleshooting</h2>
<p>Paste the message: <code>perl agile.pl help error "cannot write reports/x.html: Permission denied"</code>, or find it below.</p>
<div class=cols><ul>
$errs</ul></div>
$body
</body>
</html>
HTML
}

# ---------------------------------------------------------------- Markdown quick reference (the binder chapter)
our @QUICKREF_TOP = qw(agile-quickref-commands agile-verbs agile-ytb agile-vim-keys agile-vim-idef0);   # after the runbooks
our @QUICKREF_ERRORS = qw(agile-err-no-scrum-conf agile-err-not-applied agile-err-unknown-task agile-err-not-committed
    agile-err-not-in-backlog agile-err-task-exists agile-err-unknown-verb agile-err-needs-team agile-err-no-sprint
    agile-err-no-date agile-err-unbalanced agile-err-journal-line agile-err-lint-no-ytb agile-err-lint-dup-delim
    agile-err-lint-order agile-err-already-compiled agile-err-marking-refused agile-err-powershell agile-err-cannot-write
    agile-err-not-git agile-err-no-chat-file agile-err-idef0-broken-link);
sub _md_body {
    my ($h, $s) = @_;
    my @body = lines_of($s, own => 1);
    shift @body;
    shift @body if $s->{src}[ $s->{start} ] =~ /^\s*(?:\*[^*\s]+\*\s*)+$/ && @body && do { (my $t = $body[0]) =~ s/^\s+|\s+$//g; $t eq $s->{title} };
    my $out = '';
    for my $b (_blocks(map { _detab($_) } @body)) {
        my ($kind, @l) = @$b;
        if ($kind eq 'p') {
            my $t = join ' ', map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } @l;
            $t =~ s/$LINKRE/`$1`/g;                              # a help topic: perl agile.pl help TOPIC
            $t = join '', map { /^`/ ? $_ : do { (my $x = $_) =~ s/([*_\\<>\[\]])/\\$1/g; $x } } split /(`[^`]*`)/, $t;   # pandoc: no accidental emphasis or HTML
            $out .= "$t\n\n";
        } else {
            my $min = 99; for (@l) { next unless /\S/; my ($i) = /^( *)/; $min = length $i if length $i < $min }
            $out .= "```\n" . join("\n", map { my $x = $_; $x = substr($x, $min) if length($x) >= $min; $x =~ s/\s+$//; $x =~ s/$LINKRE/$1/g; $x } @l) . "\n```\n\n";
        }
    }
    $out;
}
sub markdown {
    my $h = shift;
    my @main = grep { $_->{file} eq 'agile.txt' } @{ $h->{sections} };
    my @howto = grep { $_->{level} == 2 && $_->{tags}[0] =~ /^agile-howto-/ } @main;
    my $md = "# Quick reference: the agile kit\n\n"
           . "This chapter is generated from the kit's own help (vim/doc/agile.txt) by `perl agile.pl help --md`; "
           . "the same text is in Vim (`:help agile`), on the command line (`perl agile.pl help TOPIC`) and in docs/HELP.html. "
           . "It is the part you need at the keyboard: the runbooks, the commands and keys used every day, and the errors people actually hit. "
           . "A name in code type such as `agile-daily-compile` is a help topic: `perl agile.pl help agile-daily-compile` prints it.\n\n"
           . "## How do I...?\n\n";
    for my $s (@howto) { $md .= "### " . _md_title($s->{title}) . "\n\n" . _md_body($h, $s) }
    $md .= "## The commands and keys used every day\n\n";
    for my $t (@QUICKREF_TOP) { my $s = $h->{tags}{$t} or next; $md .= "### " . _md_title($s->{title}) . "\n\n" . _md_body($h, $s) }
    $md .= "## When something goes wrong\n\n"
         . "Paste any message into `perl agile.pl help error \"MESSAGE\"` for the full catalog; these are the ones met most often.\n\n";
    for my $t (@QUICKREF_ERRORS) { my $s = $h->{tags}{$t} or next; $md .= "### " . _md_title($s->{title}) . "\n\n" . _md_body($h, $s) }
    $md =~ s/\n{3,}/\n\n/g;
    $md;
}
sub _md_title { my $t = shift; $t =~ s/([*_\\<>\[\]`])/\\$1/g; $t }

# ---------------------------------------------------------------- audit: what the help must cover (tests/help.t, perl agile.pl help --check)
sub _slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub required_tags {                                              # -> ( [tag, why], ... ) from the code itself, so a new command without help fails the test
    my $r = shift // root();
    my @req;
    my $d = _slurp("$r/bin/daily.pl") // '';
    if ($d =~ /my %cmds = \((.*?)\n\);/s) { my $t = $1; push @req, map { [ "agile-daily-$_", "daily.pl $_" ] } ($t =~ /(\w+)\s*=>\s*(?:\\&|sub\b)/g) }
    push @req, [ 'agile-daily-init', 'daily.pl init' ], [ 'agile-daily-help', 'daily.pl help' ];
    my $sc = _slurp("$r/lib/Scrum.pm") // '';
    if ($sc =~ /\nsub run \{(.*?)\n\}/s) { my $t = $1; push @req, map { [ "agile-scrum-$_", "scrum.pl $_" ] } ($t =~ /\$cmd eq '(\w+)'/g) }
    my $lg = _slurp("$r/lib/Ledger.pm") // '';
    if ($lg =~ /\nsub run \{(.*?)\n\}/s) { my $t = $1; push @req, map { [ "agile-ledger-$_", "ledger.pl $_" ] } ($t =~ /\$cmd eq '(\w+)'/g);
        push @req, [ 'agile-ledger-monthly', 'ledger.pl -M/--monthly' ] if $t =~ /monthly/ }
    my $v = _slurp("$r/vim/scrum.vim") // '';
    push @req, map { [ ":$_", ":$_ (vim/scrum.vim)" ] } ($v =~ /^command!.*?\s(S\w+)\s/mg);
    push @req, map { [ "\\$_", "\\$_ (vim/scrum.vim)" ] } ($v =~ /^nnoremap\s+<leader>(\w+)/mg);
    my $f = _slurp("$r/vim/ftplugin/idef0.vim") // '';
    push @req, map { [ ":$_", ":$_ (vim/ftplugin/idef0.vim)" ] } ($f =~ /^command!.*?\s(Idef\w+)\s/mg);
    push @req, map { [ "\\$_", "\\$_ (vim/ftplugin/idef0.vim)" ] } ($f =~ /<LocalLeader>(\w+)\s/g);
    my $sy = _slurp("$r/vim/ftplugin/sysml.vim") // '';
    push @req, map { [ ":$_", ":$_ (vim/ftplugin/sysml.vim)" ] } ($sy =~ /^command!.*?\s(Sys\w+)\s/mg);
    push @req, map { [ "\\$_", "\\$_ (vim/ftplugin/sysml.vim)" ] } ($sy =~ /<LocalLeader>(\w+)\s/g);
    my $st = _slurp("$r/lib/Standup.pm") // '';
    my %verb;
    $verb{$_} = 1 for ($st =~ /\$verb eq '([\w!]+)'/g);
    for my $alt ($st =~ /\$verb =~ \/\^\(([\w|]+)\)\$\//g) { $verb{$_} = 1 for split /\|/, $alt }
    push @req, map { [ "agile-verb-$_", "stand-up verb $_" ] } sort keys %verb;
    push @req, [ 'agile-verb-sprint', 'stand-up line sprint N' ];
    my %conf;
    if ($st =~ /my %DEFAULT = \((.*?)\);/s) { $conf{$_} = 1 for ($1 =~ /(\w+)\s*=>/g) }
    if ($d =~ /'scrum\.conf' => <<'CONF',\n(.*?)\nCONF/s) { $conf{$_} = 1 for ($1 =~ /^(\w+)\s*=/mg) }
    for my $src ($d, _slurp("$r/agile.pl") // '') { $conf{$_} = 1 for ($src =~ /\$conf->\{(\w+)\}/g) }
    my $ai = _slurp("$r/lib/Ai.pm") // ''; $conf{$_} = 1 for ($ai =~ /\$c->\{(ai_\w+)\}/g);
    if (my $dc = _slurp("$r/data/demo/scrum.conf")) { $conf{$_} = 1 for ($dc =~ /^\s*(\w+)\s*=/mg) }
    push @req, map { [ "agile-conf-$_", "scrum.conf key $_" ] } sort keys %conf;
    my %pending = ('bin/status-metrics.pl' => 'agile-status-metrics', 'bin/xmi2sysml.pl' => 'agile-xmi2sysml', 'bin/reqif2sysml.pl' => 'agile-reqif2sysml',
                   'tools/sysml/sysml.pl' => 'agile-sysml', 'tools/sysml/model.pl' => 'agile-model-pl');
    for my $p (sort keys %pending) { push @req, [ $pending{$p}, "$p exists" ] if -f "$r/$p" }
    my %seen; grep { !$seen{ $_->[0] }++ } @req;
}

our @MESSAGE_FILES = (qw(agile.pl tools/idef0/idef0.pl tools/memo/md2memo.pl tools/sysml/sysml.pl tools/sysml/model.pl));
our %PENDING_FILES = ();                                         # files whose catalog sections are still placeholders: none
sub message_files {
    my $r = shift // root();
    my @f = ((map { "bin/$_" } _ls("$r/bin", qr/\.pl$/)), (map { "lib/$_" } _ls("$r/lib", qr/\.pm$/)), @MESSAGE_FILES);
    grep { -f "$r/$_" && !$PENDING_FILES{$_} } @f;
}
sub _ls { my ($d, $re) = @_; opendir my $dh, $d or return (); my @f = sort grep { $_ =~ $re } readdir $dh; closedir $dh; @f }

sub extract_messages {                                           # -> ( {file, line, sample}, ... ): the literal text of every die/warn/STDERR/error push in a file
    my ($r, $rel) = @_;
    my $text = _slurp("$r/$rel") // return ();
    $text =~ s/\r//g;
    $text =~ s/\n__END__\n.*//s;
    $text =~ s/\n=(?:head|pod|over|item|begin|cut)\b.*?\n=cut\b[^\n]*//sg;
    my @l = split /\n/, $text, -1;
    my @out;
    for my $i (0 .. $#l) {
        my $line = $l[$i];
        next if $line =~ /^\s*#/;
        my $code = _code_only($line);
        while ($code =~ /(?<![\$\@%{'"\w>:-])(die|warn)\b(?!\s*=>)|print\s+STDERR\b|\$err->\(|\berr\(\$diags,|push\s+\@(?:err|errors|e|w|warn|warnings|p)\s*,|push\s+\@\{\s*\$\w+->\{errors\}\s*\}\s*,/g) {
            my $kw = $&;
            my $pos = pos($code);
            my $rest = substr($line, $pos) . "\n" . join("\n", @l[ $i + 1 .. ($i + 4 > $#l ? $#l : $i + 4) ]);
            $rest =~ s/^\s*\(// if $kw =~ /^(?:die|warn)$/;
            if ($kw =~ /^err\(/) { $rest = _skip_args($rest, 1) }
            if ($kw eq '$err->(' && $rest =~ /^\s*\$\w+\s*,/) { $rest = _skip_args($rest, 1) }
            if ($kw =~ /^push/ && $rest =~ /^\s*\{/) { next unless $rest =~ /text\s*=>\s*(.*)/s; $rest = $1 }
            for my $m (_samples($rest)) { push @out, { file => $rel, line => $i + 1, sample => $m, kw => $kw } }
        }
    }
    @out;
}
sub _code_only {                                                 # blank out string contents and comments, keep columns
    my $l = shift;
    my $out = '';
    my $q;
    for (my $i = 0; $i < length $l; $i++) {
        my $c = substr($l, $i, 1);
        if ($q) { if ($c eq '\\') { $out .= '  '; $i++; next } $q = undef if $c eq $q; $out .= $c eq "'" || $c eq '"' ? $c : ' '; next }
        if ($c eq '"' || $c eq "'") { $q = $c; $out .= $c; next }
        if ($c eq '#' && $i > 0 && substr($l, $i - 1, 1) =~ /\s/) { last }
        $out .= $c;
    }
    $out;
}
sub _skip_args { my ($s, $n) = @_; my $d = 0; my $i = 0; my $q; my $seen = 0;
    for ($i = 0; $i < length $s; $i++) { my $c = substr($s, $i, 1);
        if ($q) { $i++, next if $c eq '\\'; $q = undef if $c eq $q; next }
        if ($c eq '"' || $c eq "'") { $q = $c; next }
        $d++ if $c =~ /[({\[]/; $d-- if $c =~ /[)}\]]/;
        if ($c eq ',' && $d == 0) { $seen++; return substr($s, $i + 1) if $seen == $n } }
    '' }
sub _dq {                                                        # a double-quoted literal -> text with * for each interpolation
    my $s = shift;
    $s =~ s/\@\{\[.*?\]\}/\x01/g;
    $s =~ s/\$\{[^}]*\}/\x01/g;
    $s =~ s/\$(?:[!\@0\$]|\d+|\w+(?:::\w+)*)(?:(?:->)?(?:\{[^}]*\}|\[[^\]]*\]))*/\x01/g;
    $s =~ s/\@\w+/\x01/g;
    $s =~ s/\\x\{[0-9A-Fa-f]+\}/?/g;
    $s =~ s/\\[nr]/ /g; $s =~ s/\\t/ /g;
    $s =~ s/\\(.)/$1/g;
    $s =~ s/\x01/*/g;
    $s;
}
sub _samples {                                                   # the message(s) at the start of an expression
    my $s = shift;
    my (@msgs, $cur);
    $cur = '';
    my $d = 0;
    my $i = 0;
    my $n = length $s;
    my $flush = sub { my $m = $cur; $cur = ''; $m =~ s/\*+/*/g; $m =~ s/^\s+|\s+$//g; (my $lit = $m) =~ s/[*\s]//g; push @msgs, $m if length $lit >= 5 };
    while ($i < $n) {
        my $c = substr($s, $i, 1);
        if ($c =~ /\s/) { $i++; next }
        if ($c eq '"' || $c eq "'") {
            my $j = $i + 1; my $lit = '';
            while ($j < $n) { my $x = substr($s, $j, 1); if ($x eq '\\') { $lit .= substr($s, $j, 2); $j += 2; next } last if $x eq $c; $lit .= $x; $j++ }
            $cur .= $c eq '"' ? _dq($lit) : do { (my $t = $lit) =~ s/\\(['\\])/$1/g; $t };
            $i = $j + 1; next;
        }
        if ($c eq '.' && substr($s, $i, 2) ne '..') { $i++; next }
        if ($c eq ';' || $c eq ',' || $c =~ /[)}\]]/) { last }
        if (substr($s, $i) =~ /^(?:if|unless|or|and|for|foreach|while)\b/ || substr($s, $i, 2) =~ /^(?:\|\||&&|\/\/)$/) { last }
        if ($c eq '?' || $c eq ':') { $flush->(); $i++; next }
        if (substr($s, $i) =~ /^(?:==|!=|<=|>=|=~|!~|<|>|\+|-|\*|\/|x\b)/ && $cur eq '') { $i += length $&; next }
        # an atom: a variable, a call, a bracketed expression
        my $start = $i; my $dd = 0; my $q;
        while ($i < $n) {
            my $x = substr($s, $i, 1);
            if ($q) { $i++ if $x eq '\\'; $q = undef if $x eq $q; $i++; next }
            if ($x eq '"' || $x eq "'") { if ($dd) { $q = $x; $i++; next } last }
            if ($x =~ /[({\[]/) { $dd++; $i++; next }
            if ($x =~ /[)}\]]/) { last if !$dd; $dd--; $i++; next }
            last if !$dd && ($x =~ /[\s;,?.]/ || ($x eq ':' && substr($s, $i, 2) ne '::'));
            $i += $x eq ':' ? 2 : 1;
        }
        $i = $start + 1 if $i == $start;
        $cur .= '*';
    }
    $flush->();
    @msgs;
}

sub audit {                                                      # -> { problems => N, text, missing => [...], uncatalogued => [...], badlinks => [...], dup => [...] }
    my ($h, %o) = @_;
    my $r = $o{root} // root();
    $h //= load(root => $r);
    my @missing = grep { !$h->{tags}{ $_->[0] } } required_tags($r);
    my @cat = catalog($h);
    my @internal = @{ $o{internal} // [ internal_patterns($h) ] };
    my (@unc, $n);
    for my $f (message_files($r)) {
        for my $m (extract_messages($r, $f)) {
            $n++;
            (my $probe = $m->{sample}) =~ s/\*/X/g;
            next if grep { $probe =~ glob_re($_) && _lit($_) >= 4 } @internal;
            next if grep { my $e = $_; grep { $probe =~ glob_re($_) } @{ $e->{patterns} } } @cat;
            push @unc, $m;
        }
    }
    my (@bad, %count);
    for my $s (@{ $h->{sections} }) { $count{$_}++ for @{ $s->{tags} } }
    my @dup = grep { $count{$_} > 1 } sort keys %count;
    for my $f (@{ $h->{files} }) {
        open my $fh, '<:raw', $f or next; my @l = <$fh>; close $fh;
        my $ex = 0;
        for my $i (0 .. $#l) {
            my $x = $l[$i]; $x =~ s/\r?\n\z//;
            if ($ex) { if ($x =~ /^</ || $x =~ /^\S/) { $ex = 0 } else { next } }
            for my $t ($x =~ /$LINKRE/g) { push @bad, "$f:" . ($i + 1) . ": |$t|" unless $h->{tags}{$t} || $t =~ /^(?:help|helptags|:help|:helptags)$/ }
            $ex = 1 if $x =~ /(?:^|\s)>$/;
        }
    }
    my $text = sprintf "help: %d tags, %d sections, %d catalog entries (%d patterns), %d internal patterns\n", scalar(keys %{ $h->{tags} }), scalar @{ $h->{sections} }, scalar @cat, scalar(map { @{ $_->{patterns} } } @cat), scalar @internal;
    $text .= sprintf "required tags: %d, missing %d\n", scalar(required_tags($r)), scalar @missing;
    $text .= "  missing: $_->[0]   ($_->[1])\n" for @missing;
    $text .= sprintf "messages in code: %d, not in the catalog %d\n", $n // 0, scalar @unc;
    $text .= "  $_->{file}:$_->{line}: $_->{sample}\n" for @unc;
    $text .= "  broken link $_\n" for @bad;
    $text .= "  duplicate tag $_\n" for @dup;
    { problems => @missing + @unc + @bad + @dup, text => $text, missing => \@missing, uncatalogued => \@unc, badlinks => \@bad, dup => \@dup, messages => $n // 0 };
}

1;
