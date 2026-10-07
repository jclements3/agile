#!/usr/bin/perl
# perl tests/primer-deck.t -- sim/primer-deck.pl, the instructor deck generated from the primer: it builds the same
# bytes twice; one self-contained page (no script, nothing fetched from outside, every link resolves); the cover and
# the BLUF first; every module has objectives, 8-15 content slides, a live demo and an exercise; every slide has
# notes; the screen, notes and print views are in the CSS; and the committed deck is current (once it is committed)
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
binmode STDOUT, q(:utf8);
no warnings q(once);

my $ROOT = "$FindBin::Bin/..";
require "$ROOT/sim/primer-deck.pl";                   # also loads sim/primer.pl (package main)

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if (defined $got && $got eq $want) { print "ok $n - $name\n"; return 1 }
    $bad++; print "not ok $n - $name\n#   got:  " . ($got // 'undef') . "\n#   want: $want\n"; return 0 }
sub slurp { my $p = shift; open my $fh, '<:raw', $p or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub run { my @c = @_; my $out = qx(@{[ join ' ', map { qq("$_") } @c ]} 2>&1); return ($? >> 8, $out) }
sub list { my ($name, @bad) = @_; check_($name, scalar(@bad), 0) or print map { "#   | $_\n" } @bad[0 .. ($#bad < 9 ? $#bad : 9)] }

my $TMP = tempdir(CLEANUP => 1);

# ---------------------------------------------------------------- the text helpers
{
    local $main::DOC = { slugs => {} };
    my $t = sub { PrimerDeck::plain(PrimerDeck::terse([ { t => 'text', v => $_[0] } ], $_[1])) };
    check_('terse: short text is kept whole', $t->('Every change is checked.', 90), 'Every change is checked.');
    check_('terse: cut at the first sentence', $t->('The pipeline checks every change. It runs in minutes on the runner, and nobody waits for a board.', 60), 'The pipeline checks every change.');
    check_('terse: cut at a clause, never mid-word', $t->('The converter keeps every element it cannot map -- as a TODO line that names the v1 element and its id', 70), 'The converter keeps every element it cannot map');
    check_('terse: a word cut is marked', $t->('aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk', 30), "aaaa bbbb cccc dddd eeee ffff\x{2026}");
    my $inl = [ { t => 'text', v => 'Run ' }, { t => 'code', v => 'model.pl lint' }, { t => 'text', v => ' before every push, and read the summary line it prints at the end of its report.' } ];
    check_('terse: code spans stay whole', PrimerDeck::html(PrimerDeck::terse($inl, 40)), "Run <code>model.pl lint</code> before every push\x{2026}");
    my $r = PrimerDeck::strip_refs([ { t => 'text', v => 'The layout is fixed (' }, { t => 'ref', slug => 'x', text => [ { t => 'text', v => 'Chapter 7' } ] }, { t => 'text', v => ') at the first import.' } ]);
    check_('strip_refs: a parenthetical cross-reference leaves the slide text', PrimerDeck::plain($r), 'The layout is fixed at the first import.');
    check_('sentences: abbreviations do not end a sentence', scalar(my @s = PrimerDeck::sentences('Use a tool, e.g. Vim. Then save it.')), 2);
}

# ---------------------------------------------------------------- the real deck
my ($rc, $out) = run($^X, "$ROOT/sim/primer-deck.pl", '--check', '--out', "$TMP/never.html");
check_('--check builds the deck and writes nothing', ($rc == 0 && !-e "$TMP/never.html") ? 1 : 0, 1) or print map { "#   $_\n" } split /\n/, $out;
check_('--check prints the module list', $out =~ /^M1 .*\nprimer-deck: \d+ slides in \d+ modules/ms ? 1 : 0, 1);
($rc, $out) = run($^X, "$ROOT/sim/primer-deck.pl", '--out', "$TMP/a.html");
check_('the deck builds', $rc, 0) or print map { "#   $_\n" } split /\n/, $out;
run($^X, "$ROOT/sim/primer-deck.pl", '--out', "$TMP/b.html");
my $html = slurp("$TMP/a.html") // '';
check_('the deck builds deterministically (same bytes twice)', $html eq (slurp("$TMP/b.html") // '-') ? 1 : 0, 1);
utf8::decode($html);

# self-contained: no script, nothing loaded from elsewhere
check_('no <script>', $html =~ /<script\b/i ? 1 : 0, 0);
check_('no event handlers or javascript: links', $html =~ /\son[a-z]+\s*=|javascript:/i ? 1 : 0, 0);
check_('no <link>, <iframe>, <object>, <embed> or @import', $html =~ /<(link|iframe|object|embed)\b|\@import/i ? 1 : 0, 0);
my %id; $id{$1}++ while $html =~ /\sid="([^"]+)"/g;
my (@ext, @dangling);
while ($html =~ /\s(?:src|href|xlink:href)\s*=\s*"([^"]*)"|url\(\s*['"]?([^'")]*)/g) {
    my $u = $1 // $2;
    if    ($u =~ /^#(.+)$/)                              { push @dangling, $u unless $id{$1} }
    elsif ($u eq '#')                                     { }
    elsif ($u =~ m{^mbse-devsecops-primer\.html#[\w-]+$}) { }
    elsif ($u =~ m{^[\w./-]+$} && $u !~ m{(^|/)\.\.(/|$)}) { push @ext, "$u (not in docs/)" unless -f "$ROOT/docs/$u" }
    else                                                  { push @ext, $u }
}
list('nothing is fetched from outside the page (only docs/ files, by relative path)', @ext);
list('every in-page link has its target', @dangling);
list('ids are unique', grep { $id{$_} > 1 } sort keys %id);
my $doc = main::load_book(src => "$ROOT/docs/src/primer", root => $ROOT);
my @nolink; while ($html =~ /href="mbse-devsecops-primer\.html#([\w-]+)"/g) { push @nolink, $1 unless $doc->{slugs}{$1} }
list('every link into the book names an anchor the book has', @nolink);

# the slides
my @slides; while ($html =~ /(<section class="slide (\w+)" id="([^"]+)"([^>]*)>(.*?)<\/section>)/sg) { push @slides, { kind => $2, id => $3, attr => $4, inner => $5 } }
check_('the deck has slides', @slides > 50 ? 1 : 0, 1);
check_('the cover comes first, with the book\'s cover art and title', ($slides[0]{kind} eq 'cover' && $slides[0]{inner} =~ /url\(img\/cover-art\.jpg\)/ && $slides[0]{inner} =~ /class="ctitle">MBSE-DEVSECOPS Primer</) ? 1 : 0, 1);
check_('the BLUF follows the cover', $slides[1]{kind}, 'bluf');
check_('the BLUF headline is the book\'s, with the number from the evidence', $slides[1]{inner} =~ /<h2>\d+% of the work the team finished/ ? 1 : 0, 1);
check_('a slide index', scalar(grep { $_->{kind} eq 'index' && $_->{inner} =~ /<ol class="index">/ } @slides), 1);
list('every slide has instructor notes', map { $_->{id} } grep { my ($t) = $_->{inner} =~ /<aside class="notes">(.*?)<\/aside>/s; !defined $t || ($t =~ s/<[^>]+>//gr) !~ /\w{3,}.*\w{3,}/s } @slides);
my $total = @slides; my $k = 0;
list('slides are numbered 1..N in order', map { $_->{id} } grep { $k++; $_->{inner} !~ /<div class="num"><a href="#index">$k \/ $total<\/a><\/div>/ } @slides);
list('at most 6 bullets in any list on a slide', map { $_->{id} } grep { my ($f) = $_->{inner} =~ /<div class="frame"[^>]*>(.*?)<aside/s; $_->{kind} !~ /^(index|all)$/ && grep { (() = /<li>/g) > 6 } ($f // '') =~ /<ul[^>]*>(.*?)<\/ul>/sg } @slides);

# modules: objectives, 8 to 15 content slides, a live demo, an exercise
my %mod;
for my $s (@slides) { my ($m) = $s->{attr} =~ /data-module="(\d+)"/ or next; push @{ $mod{$m} }, $s }
check_('modules along the course (week zero, Part I, Part II, six sprints, the case, LATER)', scalar(keys %mod), 12);
for my $m (sort { $a <=> $b } keys %mod) {
    my @s = @{ $mod{$m} };
    my ($t) = grep { $_->{kind} eq 'module' } @s;
    my $later = $t && $t->{inner} =~ /<h2>Later:/;
    my $nc = grep { $_->{kind} eq 'content' || $_->{kind} eq 'figure' } @s;
    my @demo = grep { $_->{kind} eq 'demo' } @s;
    my @ex = grep { $_->{kind} eq 'exercise' } @s;
    check_("module $m: a title slide with learning objectives", ($t && $t->{inner} =~ /<ul class="objectives">(?:<li>.+?<\/li>){1,6}<\/ul>/s) ? 1 : 0, 1);
    check_("module $m: " . ($later ? '3-12' : '8-15') . " content slides ($nc)", ($later ? $nc >= 3 && $nc <= 12 : $nc >= 8 && $nc <= 15) ? 1 : 0, 1);
    check_("module $m: a live-demo slide with a practice lesson", (@demo == 1 && $demo[0]{inner} =~ /perl agile\.pl practice \d+/ && $demo[0]{inner} =~ /agile-practice-\d+/) ? 1 : 0, 1);
    check_("module $m: an exercise slide with timing, model answers in the notes", (@ex == 1 && $ex[0]{inner} =~ /class="timing">\d+ min/ && $ex[0]{inner} =~ /\d+ minutes/) ? 1 : 0, 1);
    check_("module $m: title, content, demo, exercise in that order", join(q(,), map { $_->{kind} =~ s/figure/content/r } @s) =~ s/(content,)+/content,/r, q(module,content,demo,exercise));
}
check_('exercise notes carry model answers from the answers chapter', scalar(() = $html =~ /<em>Model answer:<\/em>/g) >= 20 ? 1 : 0, 1);
check_('figures are inlined SVG, not images', ($html =~ /<figure class="fig"><svg/ && $html !~ /<img\b/) ? 1 : 0, 1);
my %fid; my $dup = 0; while ($html =~ /<svg.*?<\/svg>/sg) { my $svg = $&; while ($svg =~ /\sid="([^"]+)"/g) { $dup++ if $fid{$1}++ } }
check_('inlined figures do not share ids', $dup, 0);

# the views: screen (scroll snap), notes (#notes, no script), print (a slide per page with its notes), light and dark
check_('screen: one slide per viewport with scroll snap', ($html =~ /scroll-snap-type:\s*y mandatory/ && $html =~ /\.slide \{ height: 100vh; scroll-snap-align: start;/) ? 1 : 0, 1);
check_('notes: hidden on screen, shown by the #notes fragment', ($html =~ /aside\.notes \{ display: none; \}/ && $html =~ /<span id="notes"><\/span>\n<main>/ && $html =~ /#notes:target ~ main aside\.notes \{ display: block;/) ? 1 : 0, 1);
check_('print: a slide per page, notes shown', ($html =~ /\@media print \{.*break-after: page;.*aside\.notes \{ display: block;/s) ? 1 : 0, 1);
check_('light and dark tokens', ($html =~ /\@media \(prefers-color-scheme: dark\) \{ :root:not\(\[data-theme="light"\]\)/ && $html =~ /:root\[data-theme="dark"\]/) ? 1 : 0, 1);
check_('a title', $html =~ /<title>MBSE-DEVSECOPS Primer instructor deck<\/title>/ ? 1 : 0, 1);

# ---------------------------------------------------------------- the committed deck
my $committed = `git -C "$ROOT" ls-files docs/mbse-devsecops-primer-deck.html 2>/dev/null`;
if ($committed =~ /\S/) {
    check_('the committed deck is what sim/primer-deck.pl writes (rerun perl sim/primer-deck.pl)', (slurp("$TMP/a.html") // '') eq (slurp("$ROOT/docs/mbse-devsecops-primer-deck.html") // '-') ? 1 : 0, 1);
} else { $n++; print "ok $n - committed deck is current # skip docs/mbse-devsecops-primer-deck.html not committed yet\n" }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
