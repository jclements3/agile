#!/usr/bin/perl
# sim/primer-deck.pl -- the instructor slide deck for the MBSE DevSecOps Primer: docs/src/primer/*.txt -> docs/mbse-devsecops-primer-deck.html
#
#   perl sim/primer-deck.pl                write the deck (committed beside the book)
#   perl sim/primer-deck.pl --check        build it in memory and print the module list; write nothing
#   options: --src DIR  --root DIR (where include paths start; default the kit)  --out FILE
#
# The deck is generated, never edited: it reads the book through sim/primer.pl's parser, so a change to a chapter
# changes its slides on the next run. Slide headlines and bullets come from the chapters' bridge boxes, sections,
# "You can now..." lists, captioned tables and figures; instructor notes come from the prose, the objection boxes,
# the exercises and their answers in the answers chapter. Modules follow the CORE path of a twelve-week course: week
# zero, Part I, Part II in two modules, one module per sprint chapter, the management case, and LATER as a short close.
#
# One self-contained HTML file, no JavaScript: one slide per viewport with CSS scroll snap (arrow and Page keys
# scroll natively), a slide index, notes hidden on screen and shown in the notes view (deck.html#notes, by :target)
# and in print (one slide per page with its notes, like a notes page). The cover art is referenced relatively, as
# the book's HTML does, so the deck lives in docs/ beside img/. Deterministic: the same sources give the same bytes.
#
# Standalone documentation tool -- outside the tested kit surface (lib/, bin/); tests/primer-deck.t exercises it. Core Perl.
use strict;
use warnings;
use Getopt::Long;
use File::Basename qw(dirname);
use Cwd ();

our $HERE; BEGIN { $HERE = Cwd::abs_path(dirname(__FILE__)) }
require "$HERE/primer.pl";                            # load_book, html_inline, ref_label, h, ... (package main)

package PrimerDeck;
use Cwd qw(abs_path);

my $KIT = abs_path("$main::HERE/..");
my $BOOK = 'mbse-devsecops-primer.html';              # cross-references link into the book beside the deck

# ---------------------------------------------------------------- the course: modules along the CORE path
# Chapters are named by their {#slug}; a part's chapters not named elsewhere fall into its module. LATER chapters
# (Part V and the appendices) close the course in a short module of one slide each.
my @COURSE = (
    { key => 'week0',  title => 'Week zero: why, what and how we will measure it', when => 'Week 0',
      chapters => [qw(preface vee directive)], lesson => 10 },
    { key => 'start',  title => 'Where we start: documents, Cameo and the words that change', when => 'Week 1',
      part => qr/^Part I:/, lesson => 8 },
    { key => 'hands',  title => 'Tools in hand: the shell, Vim, diagrams and git', when => 'Week 1',
      chapters => [qw(survival vim diagrams git)], lesson => 10 },
    { key => 'team',   title => 'How the team works: stories, GitLab, the pipeline and the rhythm', when => 'Week 2',
      part => qr/^Part II:/, lesson => 11 },
    (map { my $n = $_; { key => "sprint-$n", sprint => $n, when => 'Weeks ' . (2 * $n - 1) . '-' . (2 * $n) . " (sprint $n)",
                         chapters => ["sprint-$n"], lesson => { 1 => 12, 2 => 11, 3 => 12, 4 => 13, 5 => 11, 6 => 13 }->{$n} } } 1 .. 6),
    { key => 'case',   title => 'Making the case: measures, the briefing and the memo', when => 'Weeks 10-12',
      part => qr/^Part IV:/, lesson => 7 },
    { key => 'later',  title => 'Later: living with it', when => 'After week 12', later => 1,
      part => qr/^(Part V:|Appendi)/, lesson => 13 },
);
my ($MIN_CONTENT, $MAX_CONTENT, $MAX_BULLETS) = (8, 15, 6);
my %MINUTES = (title => 3, content => 3, figure => 4, table => 4, demo => 15, exercise => 10, bluf => 5, cover => 2, index => 2, close => 5);
my $SKIP_SECTION = qr/^(You can now|Exercises?\b|Applying this|Check yourself|Answers?\b|What you can do now)/i;

# ---------------------------------------------------------------- inline text: plain view, slicing, terse cuts
# A chapter's inline nodes are sliced by plain-text position so a bullet can be cut short and keep its `code` and links.
sub label { my $x = shift; $x->{text} ? plain($x->{text}) : main::ref_label($main::DOC->{slugs}{ $x->{slug} }) }
sub plain {
    join '', map {
        $_->{t} eq 'text' || $_->{t} eq 'code' ? $_->{v} : $_->{t} eq 'fn' ? '' : $_->{t} eq 'ref' ? label($_) : plain($_->{kids})
    } @{ $_[0] };
}
sub slice {                                           # nodes covering plain characters [$from, $to); refs and code stay whole
    my ($inl, $from, $to) = @_;
    my @o; my $pos = 0;
    for my $x (@$inl) {
        last if $pos >= $to;
        my $t = $x->{t};
        next if $t eq 'fn';
        my $len = length($t eq 'text' || $t eq 'code' ? $x->{v} : $t eq 'ref' ? label($x) : plain($x->{kids}));
        my ($a, $b) = ($pos, $pos + $len); $pos = $b;
        next if $b <= $from;
        if ($t eq 'text') { push @o, { %$x, v => substr($x->{v}, ($from > $a ? $from - $a : 0), ($to < $b ? $to : $b) - ($from > $a ? $from : $a)) } }
        elsif ($t eq 'bold' || $t eq 'italic') { push @o, { t => $t, kids => slice($x->{kids}, $from - $a, $to - $a) } }
        else { push @o, $x }
    }
    return \@o;
}
sub trim_nodes {                                      # strip outer white space (and a trailing separator) from sliced nodes
    my ($inl) = @_;
    my @n = @$inl;
    shift @n while @n && $n[0]{t} eq 'text' && $n[0]{v} !~ /\S/;
    $n[0] = { %{ $n[0] }, v => $n[0]{v} =~ s/^\s+//r } if @n && $n[0]{t} eq 'text';
    pop @n while @n && $n[-1]{t} eq 'text' && $n[-1]{v} !~ /\S/;
    $n[-1] = { %{ $n[-1] }, v => $n[-1]{v} =~ s/[\s,;:]+$//r =~ s/\s+--$//r } if @n && $n[-1]{t} eq 'text';
    return \@n;
}
sub sentences {                                       # [start, end) of each sentence in a plain string
    my ($p) = @_;
    my @s; my $st = 0;
    while ($p =~ /(?<!\be\.g)(?<!\bi\.e)(?<!\bvs)(?<![A-Z])[.!?]["')]?(?=\s+["(*`]?[A-Z0-9])/g) { push @s, [ $st, pos($p) ]; $st = pos($p); $st++ while substr($p, $st, 1) =~ /\s/ }
    push @s, [ $st, length $p ] if $st < length $p;
    return @s;
}
sub cut_at {                                          # where to cut a plain string to about $max characters: a sentence, a clause, a word
    my ($p, $max) = @_;
    return (length $p, 0) if length $p <= $max;
    my ($first) = sentences($p);
    return ($first->[1], 0) if $first && $first->[1] <= $max && $first->[1] >= 20;
    my $best = -1;
    while ($p =~ /( -- |; |: |, | \()/g) { my $at = pos($p) - length $1; last if $at > $max; $best = $at if $at >= ($1 eq q(, ) || $1 eq q( \() ? 50 : 25) }
    return ($best, 0) if $best > 0;
    my $at = rindex($p, q( ), $max);
    $at = $max if $at <= 10;
    my $s = substr($p, 0, $at);                      # do not end on a comma or a small word: "before every push, and..."
    $s =~ s/(?:[\s,;:]+|\s+(?:and|or|but|the|a|an|to|of|with|in|on|for|by|that|which|as|from|at|is|are))+$// while $s =~ /(?:[\s,;:]|\s(?:and|or|but|the|a|an|to|of|with|in|on|for|by|that|which|as|from|at|is|are))$/;
    return (length($s) > 10 ? length($s) : $at, 1);
}
sub strip_refs {                                      # drop parenthetical cross-references: "(Chapter 7, Vim)" belongs in the book, not on a slide
    my ($inl) = @_;
    my @n = map { { %$_ } } @$inl;
    for my $i (1 .. $#n - 1) {
        next unless $n[$i]{t} eq q(ref) && $n[$i - 1]{t} eq q(text) && $n[$i + 1]{t} eq q(text) && $n[$i - 1]{v} =~ /\($/ && $n[$i + 1]{v} =~ /^\)/;
        $n[$i - 1]{v} =~ s/\s*\($//; $n[$i + 1]{v} =~ s/^\)//; $n[$i] = { t => q(text), v => q() };
    }
    return [ grep { $_->{t} ne q(text) || length $_->{v} } @n ];
}
sub terse {                                           # inline nodes cut to one short phrase
    my ($inl, $max) = @_;
    $inl = strip_refs($inl);
    my $p = plain($inl);
    my ($at, $dots) = cut_at($p, $max // 90);
    my $n = trim_nodes(slice($inl, 0, $at));
    push @$n, { t => 'text', v => "\x{2026}" } if $dots;
    return $n;
}
sub html { my $h = main::html_inline($_[0], { doc => $main::DOC, chslug => 'x', fns => [] }); $h =~ s/href="#/href="$BOOK#/g; $h =~ s{\s*\(<a href="[^"]*">[^<]*</a>\)}{}g if $_[1]; $h }
sub esc { main::h(@_) }
sub cap1 { my $s = shift; $s =~ s/^(\s*)([a-z])/$1\u$2/; $s }
sub inl_cap1 { my $n = [ @{ $_[0] } ]; $n->[0] = { %{ $n->[0] }, v => cap1($n->[0]{v}) } if @$n && $n->[0]{t} eq 'text'; $n }
sub words { my $c = () = plain($_[0]) =~ /\S+/g; $c }

# a paragraph of notes: whole sentences up to about $max characters
sub note_para {
    my ($inl, $max) = @_;
    my $p = plain($inl);
    return html($inl) if length $p <= $max;
    my $end = 0;
    for my $s (sentences($p)) { last if $s->[1] > $max && $end; $end = $s->[1] }
    $end = $max if !$end;
    return html(trim_nodes(slice($inl, 0, $end))) . ($end < length $p ? ' [&hellip;]' : '');
}

# ---------------------------------------------------------------- reading the book
sub chapter_sections {                                # intro blocks + level-3 sections, each { head, blocks, idx }
    my ($ch) = @_;
    my @s = ({ head => undef, blocks => [], idx => 0 });
    my $i = 0;
    for my $b (@{ $ch->{blocks} }) {
        $i++;
        if ($b->{k} eq 'heading' && $b->{level} == 3) { push @s, { head => $b, blocks => [], idx => $i }; next }
        push @{ $s[-1]{blocks} }, $b;
    }
    return @s;
}
sub boxes { my ($bl, $kind) = @_; grep { $_->{k} eq 'box' && $_->{kind} eq $kind } @$bl }
sub bridge_of {                                       # { know, called, new } inline nodes from the ::: bridge box
    my ($ch) = @_;
    my ($b) = boxes($ch->{blocks}, 'bridge') or return undef;
    my %r; my $cur;
    for my $x (@{ $b->{blocks} }) {
        if ($x->{k} eq 'subhead') { $cur = { 'You know' => 'know', 'Here it is called' => 'called', 'What is new' => 'new' }->{ $x->{text} }; next }
        $r{$cur} = $x->{inl} if $cur && $x->{k} eq 'para' && !$r{$cur};
    }
    return $r{new} ? \%r : undef;
}
sub objectives_of {                                   # the chapter's "You can now..." items, as inline nodes
    my ($ch) = @_;
    my @sec = chapter_sections($ch);
    for my $s (@sec) {
        my @bl = $s->{head} && $s->{head}{plain} =~ /^You can now/ ? @{ $s->{blocks} } : ();
        push @bl, map { @{ $_->{blocks} } } grep { $_->{title} && plain($_->{title}) =~ /^You can now/ } boxes($s->{blocks}, 'note');
        for my $b (@bl) {
            return map { $_->{inl} } @{ $b->{items} } if $b->{k} eq 'list';
        }
    }
    for my $b (map { @{ $_->{blocks} } } @sec) {      # a closing paragraph "You can now X; Y; and Z."
        next unless $b->{k} eq 'para' && plain($b->{inl}) =~ /^You can now /;
        my $p = plain($b->{inl});
        my @parts; my $st = length 'You can now ';
        while ($p =~ /(; |, and |\.$)/g) { push @parts, [ $st, pos($p) - length $1 ]; $st = pos($p) }
        push @parts, [ $st, length $p ] if $st < length $p;
        return map { trim_nodes(slice($b->{inl}, @$_)) } grep { $_->[1] - $_->[0] > 8 } @parts;
    }
    return ();
}
sub answers_index {                                   # exercise slug -> the answer box in the answers chapter
    my ($doc) = @_;
    my %a;
    for my $ch (main::all_chapters($doc)) {
        my $walk; $walk = sub { for my $b (@{ $_[0] }) {
            next unless $b->{k} eq 'box';
            if ($b->{kind} eq 'answer' && $b->{title}) { my ($r) = grep { $_->{t} eq 'ref' } @{ $b->{title} }; $a{ $r->{slug} } //= $b if $r }
            $walk->($b->{blocks});
        } };
        $walk->($ch->{blocks});
    }
    return \%a;
}
sub lessons {                                         # practice lesson N -> { title, intro, check } from vim/doc/agile.txt
    my ($root) = @_;
    my $t = main::slurp_utf8("$root/vim/doc/agile.txt") // return {};
    my %l;
    while ($t =~ /^Lesson (\d+): (.*?)\s+\*agile-practice-\1\*\n(.*?)(?=^-{20,}|^Lesson \d+:)/msg) {
        my ($n, $title, $body) = ($1, $2, $3);
        my ($intro) = $body =~ /^(.*?)(?:^Task:|\z)/ms;
        my ($check) = $body =~ /^Check:\s*(.*?)(?:\n\n|\z)/ms;
        s/\s+/ /g, s/^\s+|\s+$//g for grep { defined } $intro, $check;
        $l{$n} = { title => $title, intro => $intro // '', check => $check // '' };
    }
    return \%l;
}

# ---------------------------------------------------------------- slides
#   slide = { kind, id, kicker, head (html), body (html), notes (html), mins, module }
sub list_html { my ($items, $cls) = @_; '<ul' . ($cls ? qq( class="$cls") : '') . '>' . join('', map { "<li>$_</li>" } @$items) . "</ul>\n" }
sub notes_html {
    my (%n) = @_;
    my $o = '';
    $o .= '<p class="time">' . esc($n{time}) . "</p>\n" if $n{time};
    $o .= '<h4>Talking points</h4>' . join('', map { "<p>$_</p>\n" } @{ $n{talk} }) if $n{talk} && @{ $n{talk} };
    $o .= '<h4>Likely objection</h4>' . join('', map { "<p>$_</p>\n" } @{ $n{objection} }) if $n{objection} && @{ $n{objection} };
    $o .= join '', map { "<h4>$_->[0]</h4>" . join('', map { "<p>$_</p>\n" } @{ $_->[1] }) } @{ $n{more} // [] };
    $o .= '<p class="read">Read: ' . join('; ', @{ $n{read} }) . "</p>\n" if $n{read} && @{ $n{read} };
    return $o;
}
sub mins_text { my $m = shift; $m == 1 ? 'about 1 minute' : "about $m minutes" }
sub chlink { my $ch = shift; '<a href="' . $BOOK . '#' . esc($ch->{slug}) . '">' . esc(main::ref_label({ kind => 'chapter', ch => $ch })) . '</a>' }
sub seclink { my ($ch, $b) = @_; '<a href="' . $BOOK . '#' . esc($b->{slug}) . '">' . esc(main::ref_label({ kind => 'section', b => $b, ch => $ch })) . '</a>' }

sub figure_html {                                    # an inlined SVG, its ids made unique to this slide
    my ($b, $n) = @_;
    my $svg = main::slurp_utf8($b->{full}) // '';
    $svg =~ s/<\?xml[^>]*\?>\s*//; $svg =~ s/<!DOCTYPE[^>]*>\s*//i; $svg =~ s/<!--.*?-->//gs;
    $svg =~ s/<script\b.*?<\/script>//gis;
    $svg =~ s/\b(id|xlink:href|href)="#?([^"]+)"/my ($k, $v) = ($1, $2); $k eq 'id' ? qq(id="f$n-$v") : $v =~ m{^[a-z]+:} ? qq($k="#") : qq($k="#f$n-$v")/ge;
    $svg =~ s/url\(#([^)]+)\)/url(#f$n-$1)/g;
    return qq(<figure class="fig">$svg<figcaption>Figure $b->{num}. ) . html($b->{cap}) . "</figcaption></figure>\n";
}
sub table_html {
    my ($b) = @_;
    '<table>' . '<thead><tr>' . join('', map { '<th>' . html($_) . '</th>' } @{ $b->{head} }) . '</tr></thead><tbody>'
        . join('', map { '<tr>' . join('', map { '<td' . (plain($_) =~ /^[\d.,%\$+-]+$/ ? ' class="n"' : '') . '>' . html($_) . '</td>' } @$_) . "</tr>\n" } @{ $b->{rows} })
        . "</tbody></table>\n";
}
sub small_table { my $b = shift; @{ $b->{rows} } <= 8 && @{ $b->{head} } <= 5 && !grep { grep { length(plain($_)) > 70 } @$_ } @{ $b->{rows} } }

sub talk_paras {                                      # the first few paragraphs (and quotes) of some blocks, for the notes
    my ($bl, $n, $max) = @_;
    my @t;
    for my $b (@$bl) {
        last if @t >= $n;
        if ($b->{k} eq 'para' && words($b->{inl}) > 6) { push @t, note_para($b->{inl}, $max) }
        elsif ($b->{k} eq 'quote' && @{ $b->{paras} }) { push @t, '&ldquo;' . note_para($b->{paras}[0], $max) . '&rdquo;' . ($b->{who} ? ' &mdash; ' . html($b->{who}) : '') }
    }
    return \@t;
}
sub objection_notes {
    my ($bl) = @_;
    map { '<strong>&ldquo;' . esc(plain($_->{title} // []) =~ s/^"|"$//gr) . '&rdquo;</strong> ' . join(' ', @{ talk_paras($_->{blocks}, 2, 420) }) } boxes($bl, 'objection');
}

sub section_slide {                                   # a section: its title as the kicker, a conclusion headline, terse bullets
    my ($ch, $s) = @_;
    my @paras = map { { %$_, inl => strip_refs($_->{inl}) } } grep { $_->{k} eq q(para) && words($_->{inl}) > 4 } @{ $s->{blocks} };
    my ($list) = grep { $_->{k} eq 'list' } @{ $s->{blocks} };
    my ($tbl) = grep { $_->{k} eq q(table) && !$_->{cap} && small_table($_) } @{ $s->{blocks} };   # captioned tables get slides of their own
    return undef unless @paras;
    my $first = $paras[0]{inl};
    my $fp = plain($first);
    my ($s1) = sentences($fp);
    my ($head, $rest_from);
    if ($s1 && $s1->[1] <= 130 && $s1->[1] >= 25) { $head = trim_nodes(slice($first, 0, $s1->[1])); $rest_from = $s1->[1] }
    else { $head = undef; $rest_from = 0 }
    my @bul;
    if ($list) {
        for my $it (@{ $list->{items} }) {
            last if @bul >= $MAX_BULLETS;
            my $inl = $it->{inl};
            if (@$inl && $inl->[0]{t} eq 'bold' && length(plain($inl->[0]{kids})) >= 12) { push @bul, html(trim_nodes([ @{ $inl->[0]{kids} } ]), 1) =~ s/\.$//r; next }
            push @bul, html(inl_cap1(terse($inl, 90)), 1);
        }
    }
    my ($body, $from_list);
    if (@bul >= 2) { $body = list_html(\@bul); $from_list = 1 }
    elsif ($tbl) { $body = '<div class="tbl">' . table_html($tbl) . '</div>'; $from_list = 1 }
    else {
        my @src = ([ $first, $rest_from ], map { [ $_->{inl}, 0 ] } @paras[1 .. $#paras]);
        PARA: for my $ps (@src) {
            my ($inl, $from) = @$ps;
            my $p = plain($inl);
            for my $se (sentences($p)) {
                next if $se->[0] < $from;
                last PARA if @bul >= 4;
                my $sent = trim_nodes(slice($inl, @$se));
                next if words($sent) < 5 || plain($sent) =~ /^[a-z]|:$/;
                push @bul, html(terse($sent, 90), 1);
                next PARA;                             # one bullet per paragraph: its topic sentence
            }
        }
        return undef if @bul < 2;
        $body = list_html(\@bul);
    }
    $head //= [ { t => 'text', v => $s->{head}{plain} } ];
    return { kind => 'content', kicker => esc($s->{head}{plain}), head => html($head, 1), body => $body, from_list => $from_list,
             notes_src => { talk => talk_paras($s->{blocks}, 3, 520), objection => [ objection_notes($s->{blocks}) ], read => [ seclink($ch, $s->{head}) ] },
             mins => $MINUTES{content}, order => $s->{idx} };
}

sub chapter_candidates {                              # every slide a chapter could give, with a priority tier
    my ($ch) = @_;
    my @c;
    my @sec = chapter_sections($ch);
    my $br = bridge_of($ch);
    if ($br) {
        my $intro = $sec[0];
        push @c, { tier => 1, order => 0, kind => 'content', bridge => 1, kicker => esc($ch->{plain}),
                   head => html(inl_cap1(terse($br->{new}, 140))),
                   body => '<dl class="bridge">' . ($br->{know} ? '<dt>You know</dt><dd>' . html(terse($br->{know}, 160)) . '</dd>' : '')
                         . ($br->{called} ? '<dt>Here it is called</dt><dd>' . html(terse($br->{called}, 160)) . '</dd>' : '') . "</dl>\n",
                   notes_src => { talk => talk_paras([ map { $_->{k} eq q(box) && $_->{kind} =~ /^(survival|note)$/ ? @{ $_->{blocks} } : $_ } @{ $intro->{blocks} } ], 3, 520), objection => [ objection_notes($intro->{blocks}) ], read => [ chlink($ch) ] },
                   mins => $MINUTES{content} };
    }
    for my $s (@sec) {
        my $where = $s->{head} ? seclink($ch, $s->{head}) : chlink($ch);
        for my $b (@{ $s->{blocks} }, map { @{ $_->{blocks} } } grep { $_->{k} eq 'box' && $_->{kind} ne 'answer' } @{ $s->{blocks} }) {
            if ($b->{k} eq 'figure') {
                push @c, { tier => 2, order => $s->{idx} + .5, kind => 'figure', fig => $b, kicker => esc($ch->{plain}),
                           head => html(inl_cap1(terse($b->{cap}, 110))),
                           notes_src => { talk => talk_paras($s->{blocks}, 2, 520), read => [ $where ] }, mins => $MINUTES{figure} };
            }
            if ($b->{k} eq 'table' && $b->{cap} && small_table($b)) {
                push @c, { tier => 3, order => $s->{idx} + .6, kind => 'content', kicker => esc($ch->{plain}),
                           head => html(inl_cap1(terse($b->{cap}, 110))), body => '<div class="tbl">' . table_html($b) . '</div>',
                           notes_src => { talk => talk_paras($s->{blocks}, 2, 520), read => [ $where ] }, mins => $MINUTES{table} };
            }
        }
        for my $o (grep { $_->{k} eq q(box) && $_->{kind} =~ /^(objection|sidebar)$/ } @{ $s->{blocks} }) {   # an objection the team will raise, a case study
            my @p = grep { $_->{k} eq q(para) } @{ $o->{blocks} };
            next unless $o->{title} && @p;
            my @bul = grep { length } map { my ($se) = sentences(plain($_->{inl})); $se ? html(terse(trim_nodes(slice($_->{inl}, @$se)), 95), 1) : q() } @p[0 .. ($#p < 3 ? $#p : 3)];
            my $t = esc(plain($o->{title}) =~ s/^"|"$//gr);
            push @c, { tier => 6, order => $s->{idx} + .7, kind => q(content), kicker => $o->{kind} eq q(objection) ? q(Objection) : q(Case study), head => $o->{kind} eq q(objection) ? "&ldquo;$t&rdquo;" : $t,
                       body => list_html(\@bul), notes_src => { objection => [ objection_notes([$o]) ], read => [ $where ] }, mins => $MINUTES{content} };
        }
        next unless $s->{head} && $s->{head}{plain} !~ $SKIP_SECTION;
        my @sub = ({ head => $s->{head}, blocks => [], idx => $s->{idx} });   # a section, then its ==== subsections (the sprint days)
        for my $b (@{ $s->{blocks} }) {
            if ($b->{k} eq q(heading) && $b->{level} == 4) { push @sub, { head => $b, blocks => [], idx => $s->{idx} + .01 * @sub, sub => 1 }; next }
            push @{ $sub[-1]{blocks} }, $b;
        }
        for my $x (@sub) {
            my $sl = section_slide($ch, $x) or next;
            push @c, { %$sl, tier => ($sl->{from_list} ? 4 : 5) + ($x->{sub} ? .5 : 0) };   # lists and tables before narrative, sections before days
        }
    }
    $_->{ch} = $ch for @c;
    return @c;
}

sub pick {                                            # fill a module's content slides: bridges, figures, tables, then sections round robin
    my ($chs, $max) = @_;
    my @per = map { [ chapter_candidates($_) ] } @$chs;
    my (@take, %seen);
    for my $tier (1, 2, 3, 4, 4.5, 5, 5.5, 6) {
        my $more = 1;
        while ($more) {
            $more = 0;
            for my $i (0 .. $#per) {
                last if @take >= $max;
                my ($c) = grep { $_->{tier} == $tier && !$seen{$_} } @{ $per[$i] } or next;
                $seen{$c} = 1; push @take, [ $i, $c ]; $more = 1;
            }
            last if @take >= $max;
        }
    }
    return map { $_->[1] } sort { $a->[0] <=> $b->[0] || $a->[1]{order} <=> $b->[1]{order} } @take;
}

sub runnable {                                        # short runnable commands from some chapters: [ sandbox, text ]
    my ($chs) = @_;
    my @r;
    for my $ch (@$chs) {
        my $walk; $walk = sub { for my $b (@{ $_[0] }) {
            if ($b->{k} eq 'code' && $b->{run} && $b->{run}{lang} eq 'sh') {
                my @l = grep { /\S/ && !/^\s*#/ } split /\n/, $b->{text};
                @l = map { s/^\$ //r } grep { /^\$ / } @l if $b->{run}{transcript};
                push @r, [ $b->{run}{sandbox} // 'kit', join("\n", @l), $ch ] if @l && @l <= 3 && !grep { length > 96 } @l;
            }
            $walk->($b->{blocks}) if $b->{k} eq 'box' && $b->{kind} ne 'answer';
        } };
        $walk->($ch->{blocks});
    }
    return @r;
}

sub build {
    my ($doc, $root) = @_;
    local $main::DOC = $doc;
    my %by = map { $_->{slug} => $_ } main::all_chapters($doc);
    my $ans = answers_index($doc);
    my $les = lessons($root);
    my %used = map { $_ => 1 } qw(bluf);
    $used{$_} = 1 for map { @{ $_->{chapters} // [] } } @COURSE;
    my @mods;
    for my $m (@COURSE) {
        my @chs;
        if ($m->{chapters}) { @chs = map { $by{$_} // die "primer-deck: no chapter {#$_} in the book\n" } @{ $m->{chapters} } }
        else { @chs = grep { !$used{ $_->{slug} } } map { @{ $_->{chapters} } } grep { $_->{title} =~ $m->{part} } @{ $doc->{parts} } }
        die "primer-deck: module $m->{key} has no chapters\n" unless @chs;
        my $title = $m->{title} // ($chs[0]{plain} =~ s/^Sprint \d+:\s*//r);
        $title = "Sprint $m->{sprint}: " . cap1($title) if $m->{sprint};
        push @mods, { %$m, title => $title, chs => \@chs };
    }

    my $m = $doc->{meta};
    my @slides;
    my $date = main::cover_date($m);
    push @slides, { kind => 'cover', id => 'cover', mins => $MINUTES{cover},
                    body => '<div class="band"><div class="ctitle">' . esc($m->{title}) . '</div><div class="cline">' . esc($m->{coverline} // 'A Case Study')
                          . '</div><div class="csub">' . esc($m->{subtitle} // '') . ($date ? ' <span class="cdate">&bull; ' . esc($date) . '</span>' : '')
                          . '</div><div class="cdeck">Instructor deck: ' . scalar(@mods) . " modules along the twelve-week course</div></div>\n",
                    notes => notes_html(time => 'Before the session: ' . mins_text(2),
                        talk => [ 'Present from this page in a browser, full screen (F11). One slide fills the window; the arrow keys, Page Up and Page Down and the space bar move one slide.',
                                  'Open a second window on <code>mbse-devsecops-primer-deck.html#notes</code> on the laptop screen for these notes. Reload the plain page (no <code>#notes</code>) to hide them again. Printing gives one slide per page with its notes.',
                                  'Every slide is generated from the book: the headline and bullets from a chapter, these notes from its prose, objection boxes, exercises and answers. The link under each set of notes opens the passage in the book.',
                                  'The course follows the book&rsquo;s CORE path over twelve weeks, a module at a time; the LATER chapters close it. Each module ends with a live demo on a practice lesson and an exercise.' ]) };

    # BLUF: the book's first page, before the contents
    my $bluf = $by{bluf} // die "primer-deck: no chapter {#bluf}\n";
    my ($lead) = grep { $_->{k} eq 'para' } @{ $bluf->{blocks} };
    my ($means) = grep { $_->{k} eq 'list' } @{ $bluf->{blocks} };
    my ($t1, $t2) = grep { $_->{k} eq 'table' } @{ $bluf->{blocks} };
    my $leadhead = $lead->{inl}[0]{t} eq 'bold' ? $lead->{inl}[0]{kids} : terse($lead->{inl}, 160);
    push @slides, { kind => 'bluf', id => 'bluf', kicker => 'Bottom line up front', head => html(trim_nodes([ @$leadhead ])) =~ s/\.$//r,
                    body => '<div class="cols"><div>' . list_html([ map { html(trim_nodes($_->{inl}[0]{t} eq 'bold' ? $_->{inl}[0]{kids} : terse($_->{inl}, 70))) =~ s/[.,]$//r } @{ $means->{items} } ]) . '</div>'
                          . ($t1 ? '<div class="tbl">' . table_html({ head => [ @{ $t1->{head} }[0, 2, 3, 4] ], rows => [ map { [ @$_[0, 2, 3, 4] ] } @{ $t1->{rows} } ] }) . '</div>' : '') . "</div>\n",
                    notes => notes_html(time => mins_text($MINUTES{bluf}), talk => talk_paras($bluf->{blocks}, 3, 600),
                        more => [ [ 'If asked where the numbers come from', [ map { note_para($_->{inl}, 500) } grep { $_->{k} eq 'para' } map { @{ $_->{blocks} } } boxes($bluf->{blocks}, 'note') ] ] ],
                        read => [ chlink($bluf) ]),
                    mins => $MINUTES{bluf} };

    # modules
    my $mn = 0;
    for my $mod (@mods) {
        $mn++;
        my $mid = "m$mn";
        my @content = pick($mod->{chs}, $mod->{later} ? 12 : $MAX_CONTENT);
        if ($mod->{key} eq 'week0') {                 # the ladder first: what you know, then what is new
            my ($lad) = grep { $_->{kind} eq 'figure' && $_->{fig}{path} =~ /ladder/ } @content;
            @content = ($lad, grep { $_ != $lad } @content) if $lad;
        }
        if ($mod->{later}) {                          # appendices: one shelf slide, not one per chapter
            my @app = grep { my $c = $_; grep { $_->{appendix} && grep { $_ == $c } @{ $_->{chapters} } } @{ $doc->{parts} } } @{ $mod->{chs} };
            my %app = map { $_ => 1 } @app;
            @content = grep { !$app{ $_->{ch} } } @content;
            push @content, { kind => 'content', kicker => 'Appendices', head => 'The reference shelf: look it up when the work asks for it',
                             body => list_html([ map { esc($_->{plain}) } @app[0 .. ($#app < 5 ? $#app : 5)] ]) . (@app > 6 ? '<p class="more">and ' . (@app - 6) . " more in the book</p>\n" : ''),
                             notes_src => { talk => [ 'The appendices are reference, not lessons: command and Vim quick references, rescue recipes, the error catalog, templates, checklists, the glossary, the study plan and the answers.',
                                                       'Point the team at the quick-reference cards and the rescue chapter now; they will be opened on the bad day, not read in order.' ],
                                            read => [ map { chlink($_) } @app ] },
                             mins => $MINUTES{content} } if @app;
        }
        my $nc = 0;
        for my $c (@content) {
            $nc++;
            $c->{id} = "$mid-$nc";
        }
        # objectives: the "You can now..." lists; else what is new in each chapter
        my @obj_lists = map { [ objectives_of($_) ] } @{ $mod->{chs} };
        my @obj;
        my $round = 0;
        while (@obj < $MAX_BULLETS) {
            my $got = 0;
            for my $l (@obj_lists) { next unless $l->[$round]; push @obj, $l->[$round]; $got = 1; last if @obj >= $MAX_BULLETS }
            last unless $got; $round++;
        }
        my $obj_src = @obj ? 'the chapters&rsquo; &ldquo;You can now&hellip;&rdquo; lists' : 'what is new in each chapter';
        @obj = grep { plain($_) !~ /^Nothing/ } map { $_->{new} } grep { $_ } map { bridge_of($_) } @{ $mod->{chs} } if !@obj;
        @obj = @obj[0 .. $MAX_BULLETS - 1] if @obj > $MAX_BULLETS;
        my $obj_html = list_html([ map { html(inl_cap1(terse($_, 95))) =~ s/[.;]$//r } @obj ], 'objectives');

        # the exercise: up to three, one per chapter first; notes carry the model answers
        my @ex_per = map { my $ch = $_; [ map { [ $ch, $_ ] } do { my @e; my $w; $w = sub { for (@{ $_[0] }) { push @e, $_ if $_->{k} eq 'box' && $_->{kind} eq 'exercise'; $w->($_->{blocks}) if $_->{k} eq 'box' && $_->{kind} ne 'exercise' } }; $w->($ch->{blocks}); @e } ] } @{ $mod->{chs} };
        my @ex; my $r = 0;
        while (@ex < 3) { my $got = 0; for my $l (@ex_per) { next unless $l->[$r]; push @ex, $l->[$r]; $got = 1; last if @ex >= 3 } last unless $got; $r++ }
        my $exmins = @ex ? 10 + 5 * @ex : 15;
        my @ex_items = map { my ($ch, $b) = @$_; my ($p) = grep { $_->{k} eq 'para' } @{ $b->{blocks} };
                             '<strong>' . ($b->{title} ? html($b->{title}) : "Exercise $b->{num}") . '.</strong> ' . ($p ? html(terse($p->{inl}, 110)) : '') } @ex;
        my @ex_notes = map { my ($ch, $b) = @$_;
                             my $a = $b->{slug} ? $ans->{ $b->{slug} } : undef;
                             [ 'Exercise ' . esc($b->{num}) . ($b->{title} ? ': ' . html($b->{title}) : ''),
                               [ @{ talk_paras($b->{blocks}, 1, 380) },
                                 ($a ? ('<em>Model answer:</em> ' . join(' ', @{ talk_paras([ grep { $_->{k} eq 'para' && plain($_->{inl}) !~ /^Must contain/ } @{ $a->{blocks} } ], 1, 320) }),
                                        map { '<em>' . html($_->{inl}) . '</em>' } grep { $_->{k} eq 'para' && plain($_->{inl}) =~ /^Must contain/ } @{ $a->{blocks} }) : ()),
                                 '<a href="' . $BOOK . '#' . esc($b->{slug} // $ch->{slug}) . '">' . ($b->{slug} ? "Exercise $b->{num} in the book" : esc($ch->{plain})) . '</a>' ] ] } @ex;

        # the demo: the matching practice lesson and the chapters' own runnable commands
        my $ln = $mod->{lesson};
        my $L = $les->{$ln} // { title => '', intro => '', check => '' };
        my @cmds = runnable($mod->{chs});
        my %sb; my @show;
        for my $c (@cmds) { next if $sb{ $c->[0] }++ && @show; push @show, $c; last if @show >= 3 }
        my $demo_body = '<p class="lead">' . "Practice lesson $ln" . ($L->{title} ? ': ' . esc($L->{title}) : '') . "</p>\n"
            . '<pre><code>perl agile.pl practice ' . $ln . "\nperl agile.pl practice check $ln</code></pre>\n"
            . (@show ? '<p class="sub">From the chapters, as the book runs them:</p>' . join('', map { '<figure class="cmd"><figcaption>' . esc($_->[0]) . ' &middot; ' . esc($_->[2]{plain}) . '</figcaption><pre><code>' . esc($_->[1]) . "</code></pre></figure>\n" } @show) : '');
        my $content_mins = 0; $content_mins += $_->{mins} for @content;
        my $total = $MINUTES{title} + $content_mins + $MINUTES{demo} + $exmins;

        push @slides, { kind => 'module', id => $mid, module => $mn, kicker => "Module $mn &middot; " . esc($mod->{when}),
                        head => esc($mod->{title}), body => '<p class="sub">You will be able to:</p>' . $obj_html,
                        notes => notes_html(time => 'Module: ' . mins_text($total) . " ($content_mins on the slides, $MINUTES{demo} demo, $exmins exercise); this slide " . mins_text($MINUTES{title}),
                            talk => [ "Objectives come from $obj_src. Ask who has done any of them before; their answer tells you where to slow down.",
                                      ($mod->{later} ? 'These chapters are LATER: nobody needs them in the first twelve weeks. Show where they are and what they answer, and stop.' : 'Ask the team to read the chapters before the session; the slides are the discussion, not the reading.') ],
                            read => [ map { chlink($_) } @{ $mod->{chs} } ]),
                        mins => $MINUTES{title}, title => $mod->{title}, when => $mod->{when}, count => scalar(@content) };
        for my $c (@content) {
            my $ns = $c->{notes_src} // {};
            my $body = $c->{kind} eq 'figure' ? figure_html($c->{fig}, $c->{id} =~ s/-/x/r) : $c->{body};
            push @slides, { kind => $c->{kind} eq 'figure' ? 'figure' : 'content', id => $c->{id}, module => $mn, kicker => $c->{kicker}, head => $c->{head}, body => $body,
                            notes => notes_html(time => mins_text($c->{mins}), %$ns), mins => $c->{mins} };
        }
        push @slides, { kind => 'demo', id => "$mid-demo", module => $mn, kicker => "Module $mn &middot; Live demo", head => 'Live demo: do it once, in front of them',
                        body => $demo_body,
                        notes => notes_html(time => mins_text($MINUTES{demo}) . ': 2 to set up, 10 typing, 3 for questions',
                            talk => [ 'Type, do not paste: the team should see the typing and the mistakes. Run it on the projector from a fresh sandbox.',
                                      ($L->{intro} ? esc($L->{intro}) : ()), ($L->{check} ? 'The lesson is done when: ' . esc($L->{check}) : ()),
                                      'If it goes wrong, say so and read the message aloud: the error message and the fix are the lesson.' ],
                            read => [ "<code>:help agile-practice-$ln</code>", (map { chlink($_->[2]) } @show) ]),
                        mins => $MINUTES{demo} };
        push @slides, { kind => 'exercise', id => "$mid-ex", module => $mn, kicker => "Module $mn &middot; Exercise &middot; $exmins minutes",
                        head => @ex ? 'Exercise: your turn, then compare' : 'Exercise: apply it to your own program',
                        body => (@ex ? list_html(\@ex_items, 'ex') : '<p>' . esc('Take the module\'s objectives one at a time and say, for your own program, who would do it and when.') . "</p>\n")
                              . '<p class="timing">' . (@ex ? q(5 min alone &middot; ) . ($exmins - 10) . q( min in pairs &middot; 5 min debrief) : "$exmins min: alone, then debrief") . "</p>\n",
                        notes => notes_html(time => "$exmins minutes. Let pairs pick one exercise each if time is short.", more => \@ex_notes,
                            talk => [ 'Debrief on what any good answer must contain, not on the model answer&rsquo;s wording.' ]),
                        mins => $exmins };
    }

    push @slides, { kind => 'close', id => 'close', kicker => 'Close', head => 'Twelve weeks, one model under control, a case made from measurements',
                    body => list_html([ 'Read the next module&rsquo;s chapters before the session', 'Do the practice lessons: <code>perl agile.pl practice N</code>',
                                        'Keep the book open: every slide links back to it', 'Say yes to each sprint&rsquo;s &ldquo;You can now&hellip;&rdquo; list, or raise it at the retrospective' ]),
                    notes => notes_html(time => mins_text($MINUTES{close}), talk => talk_paras([ grep { $_->{k} eq 'para' } map { @{ $_->{blocks} } } grep { $_->{head} && $_->{head}{plain} =~ /Check yourself/ } chapter_sections($by{'study-plan'} // { blocks => [] }) ], 2, 600),
                        read => [ map { chlink($by{$_}) } grep { $by{$_} } qw(study-plan playbook) ]),
                    mins => $MINUTES{close} };

    # the index: modules with their slides, and the timing
    my $total = 0; $total += $_->{mins} for @slides;
    my @mrows = grep { $_->{kind} eq 'module' } @slides;
    my $index = { kind => 'index', id => 'index', kicker => 'Slide index', head => 'Thirteen sessions along the CORE path, then the LATER shelf',
                  body => '<ol class="index">' . join('', map { my $s = $_; my $mm = 0; $mm += $_->{mins} for grep { ($_->{module} // 0) == $s->{module} } @slides;
                                  qq(<li><a href="#$s->{id}">) . esc($s->{title}) . '</a> <span class="when">' . esc($s->{when}) . " &middot; $mm min</span></li>" } @mrows) . "</ol>\n"
                        . '<p class="more"><a href="#bluf">Bottom line</a> &middot; <a href="#all">every slide</a> &middot; <a href="#notes">notes view</a> &middot; <a href="#cover">cover</a></p>' . "\n",
                  notes => notes_html(time => mins_text($MINUTES{index}) . "; the whole course is about $total minutes of sessions",
                      talk => [ 'One module per session. Week zero before the first sprint, Part I and the tools in week 1, the team&rsquo;s machinery in week 2, then one sprint module every two weeks and the management case in weeks 10-12.',
                                'The index links jump to a module; Back in the browser returns here. In the notes view, links leave the notes view: scroll instead.' ]),
                  mins => $MINUTES{index} };
    $index->{head} = scalar(@mrows) . ' sessions along the CORE path; LATER closes the course';
    splice @slides, 2, 0, $index;                     # cover, BLUF, index, modules
    my $n = 0; $_->{n} = ++$n for @slides;
    push @slides, { kind => 'all', id => 'all', n => ++$n, kicker => 'Every slide', head => 'All slides',
                    body => '<ol class="all">' . join('', map { qq(<li value="$_->{n}"><a href="#$_->{id}">) . ($_->{head} // 'Cover') . '</a></li>' } @slides) . "</ol>\n",
                    notes => notes_html(talk => [ 'The full list, for jumping to a slide during questions.' ]), mins => 0 };
    return { slides => \@slides, modules => \@mods, total => $total };
}

# ---------------------------------------------------------------- HTML
my $CSS = <<'CSS';
:root { --navy:#27235d; --gold:#e6af22; --lblue:#aac1d7;
  --bg:#ffffff; --fg:#1a1a1a; --muted:#5b5b66; --rule:#c9c9d1; --code-bg:#f4f4f6; --box-bg:#f7f7f9; --accent:#27235d; --link:#27235d; --notes-bg:#fbf6e6; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg:#16161c; --fg:#e6e6ea; --muted:#a3a3ad; --rule:#3a3a46; --code-bg:#20202a; --box-bg:#1c1c25; --accent:#aac1d7; --link:#aac1d7; --notes-bg:#23211a; } }
:root[data-theme="dark"] { --bg:#16161c; --fg:#e6e6ea; --muted:#a3a3ad; --rule:#3a3a46; --code-bg:#20202a; --box-bg:#1c1c25; --accent:#aac1d7; --link:#aac1d7; --notes-bg:#23211a; }
* { box-sizing: border-box; }
html { background: var(--bg); scroll-snap-type: y mandatory; }
body { margin: 0; background: var(--bg); color: var(--fg); font-family: Calibri, "Segoe UI", Arial, sans-serif; }
a { color: var(--link); }
#notes { position: absolute; top: 0; }
.slide { height: 100vh; scroll-snap-align: start; overflow: hidden; display: flex; flex-direction: column; font-size: clamp(15px, min(3.1vh, 1.85vw), 44px); line-height: 1.3; border-bottom: 1px solid var(--rule); }
.slide > .frame { position: relative; flex: 1; min-height: 0; overflow: hidden; display: flex; flex-direction: column; padding: 5vh 6vw 7vh; }
.slide .kicker { font-size: .62em; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); border-left: .25em solid var(--gold); padding-left: .5em; }
.slide h2 { font-size: 1.45em; line-height: 1.15; margin: .35em 0 .6em; color: var(--accent); max-width: 34em; }
.slide .body { flex: 1; min-height: 0; overflow: hidden; }
.slide ul, .slide ol { margin: .2em 0; padding-left: 1.2em; }
.slide li { margin: .35em 0; max-width: 36em; }
.slide ul.objectives li::marker { content: "\2713  "; }
.slide code { font-family: Consolas, "DejaVu Sans Mono", "Courier New", monospace; font-size: .9em; background: var(--code-bg); padding: 0 .2em; }
.slide pre { margin: .2em 0 .5em; background: var(--code-bg); border: 1px solid var(--rule); padding: .4em .7em; font-size: .7em; line-height: 1.35; overflow: hidden; white-space: pre-wrap; }
.slide pre code { background: none; padding: 0; font-size: inherit; }
.slide .num { position: absolute; right: 2.2vw; bottom: 2.2vh; font-size: .55em; color: var(--muted); }
.slide .num a { color: inherit; text-decoration: none; }
.slide p.sub, .slide p.more, .slide p.timing { color: var(--muted); font-size: .8em; margin: .4em 0 .2em; }
.slide p.timing { border-top: 1px solid var(--rule); padding-top: .4em; }
.slide p.lead { font-size: 1.05em; font-weight: 700; margin: 0 0 .4em; }
.slide figure.cmd { margin: .3em 0; } .slide figure.cmd figcaption { font-size: .6em; color: var(--muted); }
dl.bridge { display: grid; grid-template-columns: max-content 1fr; gap: .5em 1em; margin: .5em 0; font-size: .95em; }
dl.bridge dt { font-weight: 700; color: var(--muted); } dl.bridge dd { margin: 0; }
.tbl table { border-collapse: collapse; font-size: .72em; }
.tbl th, .tbl td { border: 1px solid var(--rule); padding: .25em .55em; text-align: left; vertical-align: top; }
.tbl th { background: var(--box-bg); } .tbl td.n { text-align: right; font-variant-numeric: tabular-nums; }
.cols { display: grid; grid-template-columns: 1.1fr 1fr; gap: 2vw; align-items: start; }
.cols ul { font-size: .9em; }
figure.fig { margin: 0; height: 100%; display: flex; flex-direction: column; align-items: center; }
figure.fig svg { flex: 1; min-height: 0; max-width: 100%; height: auto; max-height: 62vh; background: #fff; border: 1px solid var(--rule); padding: .3em; }
figure.fig figcaption { font-size: .6em; color: var(--muted); margin-top: .3em; }
ol.index { columns: 2; column-gap: 3vw; font-size: .82em; } ol.index li { break-inside: avoid; margin: .25em 0; }
ol.index .when { color: var(--muted); font-size: .8em; display: block; }
.slide.all { height: auto; min-height: 100vh; overflow: visible; } .slide.all > .frame { overflow: visible; } ol.all { columns: 3; font-size: .55em; }
ul.ex li { margin: .5em 0; font-size: .92em; }
.cover .body { display: flex; flex-direction: column; justify-content: flex-end; }
.cover > .frame { background: #555 center / cover no-repeat; justify-content: flex-end; padding: 0 0 6vh; color: #fff; }
.cover .band { width: 100%; background: rgba(0,0,0,.85); text-align: center; padding: 1.2em 1em 1em; border-top: 3px double #c7c7c7; border-bottom: 3px double #c7c7c7; }
.cover .ctitle { font-size: 1.9em; font-weight: 700; line-height: 1.15; }
.cover .cline { font-size: 1em; font-variant: small-caps; margin-top: .3em; }
.cover .csub { font-size: .8em; max-width: 46em; margin: .4em auto 0; }
.cover .cdate { color: #bfbfbf; margin-left: 1em; white-space: nowrap; }
.cover .cdeck { font-size: .65em; color: #d8d8d8; margin-top: .6em; letter-spacing: .04em; }
.cover .num { color: #ddd; }
.module > .frame { justify-content: center; background: var(--box-bg); }
.module h2 { font-size: 1.8em; }
aside.notes { display: none; }
#notes:target ~ main .slide > .frame { flex: 0 0 55vh; font-size: .62em; padding: 3vh 4vw 4vh; border-bottom: 1px solid var(--rule); }   /* the notes view: slide above, notes below */
#notes:target ~ main figure.fig svg { max-height: 36vh; }
#notes:target ~ main aside.notes { display: block; flex: 1; min-height: 0; overflow: auto; margin: 0; border-width: 0 0 0 .3em; }
#notes:target ~ main .slide.all { height: auto; }
aside.notes { margin-top: 1em; padding: .6em 1em; background: var(--notes-bg); border: 1px solid var(--rule); border-left: .3em solid var(--gold);
  font-family: Georgia, "Palatino Linotype", Palatino, serif; font-size: .6em; line-height: 1.45; color: var(--fg); }
aside.notes h4 { font-family: Calibri, "Segoe UI", Arial, sans-serif; font-size: .9em; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); margin: .7em 0 .2em; }
aside.notes p { margin: .3em 0; } aside.notes p.time { font-weight: 700; margin-top: 0; } aside.notes p.read { color: var(--muted); }
.cover aside.notes { text-align: left; }
@media (max-width: 700px) { .slide { font-size: 16px; height: auto; min-height: 100vh; } .slide > .frame { padding: 4vh 16px 7vh; overflow: visible; } .slide .body { overflow: visible; } .cols { grid-template-columns: 1fr; } ol.index, ol.all { columns: 1; } }
@media print {
  @page { size: letter portrait; margin: .45in; }
  html { scroll-snap-type: none; background: #fff; }
  body { color: #000; background: #fff; }
  .slide { height: auto; min-height: 0; overflow: visible; break-after: page; break-inside: avoid; border: 0; font-size: 11pt; display: block; }
  .slide > .frame, #notes:target ~ main .slide > .frame { border: 1px solid #000; aspect-ratio: 16 / 9; height: auto; padding: .25in .35in; overflow: hidden; }
  .slide .body { overflow: hidden; }
  .slide h2 { color: #000; }
  figure.fig svg { max-height: 2.4in; border: 0; }
  .slide.module > .frame { background: none; }
  .cover > .frame { background: #555 center / cover no-repeat; -webkit-print-color-adjust: exact; print-color-adjust: exact; display: flex; align-items: flex-end; padding: 0 0 .3in; }
  .slide.all > .frame { aspect-ratio: auto; } .slide.all ol.all { font-size: 7.5pt; }
  aside.notes { display: block; background: none; border: 0; border-top: 1px solid #000; padding: .1in 0 0; margin-top: .15in; font-size: 9pt; color: #000; }
  a { color: inherit; text-decoration: none; }
}
CSS

sub render {
    my ($doc, $deck) = @_;
    my $m = $doc->{meta};
    my $nall = @{ $deck->{slides} };
    my $o = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        . '<title>' . esc($m->{title}) . " instructor deck</title>\n<meta name=\"generator\" content=\"sim/primer-deck.pl\">\n<style>\n$CSS</style>\n</head>\n<body>\n"
        . "<span id=\"notes\"></span>\n<main>\n";
    for my $s (@{ $deck->{slides} }) {
        (my $head = $s->{head} // q()) =~ s/(?<!\.)\.$//;            # a headline is a statement, not a sentence: no full stop
        my $fstyle = $s->{kind} eq q(cover) ? ' style="background-image:url(img/cover-art.jpg)"' : q();
        my $mod = defined $s->{module} ? qq( data-module="$s->{module}") : '';
        my $frame = ($s->{kicker} ? '<div class="kicker">' . $s->{kicker} . "</div>\n" : '') . (defined $s->{head} ? "<h2>$head</h2>\n" : q())
            . '<div class="body">' . ($s->{body} // '') . "</div>\n"
            . qq(<div class="num"><a href="#index">$s->{n} / $nall</a></div>\n);
        $o .= qq(<section class="slide $s->{kind}" id="$s->{id}"$mod>\n<div class="frame"$fstyle>\n$frame</div>\n<aside class="notes">\n$s->{notes}</aside>\n</section>\n);
    }
    $o .= "</main>\n</body>\n</html>\n";
    return $o;
}

sub main {
    my %o = (src => "$KIT/docs/src/primer", root => $KIT, out => "$KIT/docs/mbse-devsecops-primer-deck.html");
    Getopt::Long::GetOptions(\%o, 'src=s', 'root=s', 'out=s', 'check', 'help|h') or return 2;
    if ($o{help}) { print "usage: perl sim/primer-deck.pl [--check] [--src DIR] [--root DIR] [--out FILE]\n"; return 0 }
    my $doc = main::load_book(src => $o{src}, root => $o{root});
    if (@main::ERR) { print STDERR "$_\n" for @main::ERR; print STDERR 'primer-deck: ' . @main::ERR . " problem(s) in the book's source; nothing written\n"; return 1 }
    my $deck = build($doc, $o{root});
    my $html = render($doc, $deck);
    my @mods = grep { $_->{kind} eq 'module' } @{ $deck->{slides} };
    printf "%-3s %-74s %s\n", "M$_->{module}", $_->{title} =~ s/&\w+;/-/gr, "$_->{count} content slides" for @mods;
    printf "primer-deck: %d slides in %d modules, about %d minutes of sessions\n", scalar @{ $deck->{slides} }, scalar @mods, $deck->{total};
    return 0 if $o{check};
    main::write_file($o{out}, $html);
    print "wrote $o{out}\n";
    return 0;
}

exit main() unless caller;
1;
