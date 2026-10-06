#!/usr/bin/perl
# perl tests/primer.t -- sim/primer.pl, the MBSE DevSecOps Primer's generator: the markup (every construct), HTML and
# TeX escaping, numbering and cross-references, every source problem reported at once with nothing written, and that
# the committed docs/mbse-devsecops-primer.{html,tex} are what the generator writes (once the book exists)
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $ROOT = "$FindBin::Bin/..";
require "$ROOT/sim/primer.pl";

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if (defined $got && $got eq $want) { print "ok $n - $name\n"; return 1 }
    $bad++; print "not ok $n - $name\n#   got:  " . ($got // 'undef') . "\n#   want: $want\n"; return 0 }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) or print map { "#   | $_\n" } grep { defined } (split /\n/, $text)[0 .. 5] } }
sub hasnt { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: not $re", ($text =~ $re ? 1 : 0), 0) } }
sub spew { my ($p, $t) = @_; (my $d = $p) =~ s{/[^/]*$}{}; make_path($d); open my $fh, '>:raw', $p or die "$p: $!"; print $fh $t; close $fh }
sub slurp { my $p = shift; open my $fh, '<:raw', $p or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub run { my @c = @_; my $out = qx(@{[ join ' ', map { qq("$_") } @c ]} 2>&1); return ($? >> 8, $out) }

my $TMP = tempdir(CLEANUP => 1);

# ---------------------------------------------------------------- inline markup
my $ctx = { file => 'x.txt', where => 'x.txt:1', root => $ROOT, refs => [] };
my $show; $show = sub { join '', map { $_->{t} eq 'text' ? $_->{v} : $_->{t} eq 'code' ? "<c:$_->{v}>" : $_->{t} eq 'ref' ? "<r:$_->{slug}" . ($_->{text} ? '|' . $show->($_->{text}) : '') . '>' : "<$_->{t}:" . $show->($_->{kids}) . '>' } @{ $_[0] } };
@main::ERR = ();
check_('inline: italic, bold, code', $show->(main::parse_inline('a *b* and **c d** with `e*f*` end', $ctx)), 'a <italic:b> and <bold:c d> with <c:e*f*> end');
check_('inline: literal asterisks (inside a word, before a space)', $show->(main::parse_inline('2*3 and a * b and file*.txt', $ctx)), '2*3 and a * b and file*.txt');
check_('inline: cross-references', $show->(main::parse_inline('see [[git]] and [[vim|the *Vim* chapter]]', $ctx)), 'see <r:git> and <r:vim|the <italic:Vim> chapter>');
check_('inline: footnote with brackets and markup inside', $show->(main::parse_inline('x^[a [b] **c**] y', $ctx)), 'x<fn:a [b] <bold:c>> y');
check_('inline: refs are collected for checking', join(',', map { $_->[0] } @{ $ctx->{refs} }), 'git,vim');
check_('inline: {{value}} reads JSON', $show->(main::parse_inline('{{value: tests/status-metrics/dashboard.json m.A.elements}} elements', $ctx)), '1960 elements');
check_('inline: no errors so far', scalar @main::ERR, 0);
main::parse_inline('`open {{value: nope.json a}} [[x', $ctx);
check_('inline: problems are reported, not fatal', scalar(@main::ERR) >= 1 ? 1 : 0, 1);
@main::ERR = ();

# ---------------------------------------------------------------- escaping
check_('TeX: specials escaped', main::tex_text('$5 & 10% #1 _x_ ~h ^u {b} \\z'), '\\$5 \\& 10\\% \\#1 \\_x\\_ \\textasciitilde{}h \\textasciicircum{}u \\{b\\} \\textbackslash{}z');
check_('TeX: curly quotes and apostrophes in prose', main::tex_text(qq{"a" Bob's 'b'}), "\x{201C}a\x{201D} Bob\x{2019}s \x{2018}b\x{2019}");
check_('TeX: symbols outside the text font go to the symbol font', main::tex_text("a \x{2192} b \x{2610}"), "a {\\symfont \x{2192}} b {\\symfont \x{2610}}");
check_('TeX: inline code keeps straight quotes, breaks after / and --', main::tex_code_inline(q{git push --force "a/b"}),
    '\\code{git push -\\allowbreak{}-\\allowbreak{}force \\textquotedbl{}a/\\allowbreak{}b\\textquotedbl{}}');
check_('HTML: escaped', main::h(q{<a href="x">&</a>}), '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;');
check_('grey_svg: colours become greys of the same luminance', main::grey_svg('fill="#27235d" stroke="#fff"'), 'fill="#2b2b2b" stroke="#ffffff"');
check_('CSV: quotes, embedded commas and newlines', join('|', map { join(',', @$_) } @{ main::parse_csv(qq{a,b\n"x, y","say ""hi""\nthere"\n}) }), qq{a,b|x, y,say "hi"\nthere});

# ---------------------------------------------------------------- a small book with every construct
my $SRC = "$TMP/src";
spew("$SRC/00-front.txt", "\@title: Test Book\n\@subtitle: Sub\n\@author: A\n\@edition: First\n\@copyright: Notional.\n\@dedication: For you\n\n== How to read {#how}\n\nRead [[first]].\n");
spew("$SRC/01-part-one.txt", "= Part I: One\n\nWhy this part matters.\n\n::: note\nRead it first.\n:::\n");
spew("$SRC/02-first.txt", <<'EOF');
== The first chapter {#first}

::: survival
What you have:
- Vim
What you need:
- git
:::

Text with a note.^[A footnote.] See [[sec-a]], [[ex-a]] and [[how|the guide]].

=== Section A {#sec-a}

- one
  more
  - nested
1. first

> Why change?
> -- Bob, planning

==== Sub

```sh
echo "hi"	tab
```

|| H1 | H2 ||
| a \| b | 12 |
Table: A table

|| X ||
| uncaptioned |

::: note Titled
Body.
:::
::: tip
Tip.
:::
::: warning W
Warn.
:::
::: sidebar Case
Story.
:::
::: objection We have Cameo
Why?

Answer: Because.
:::
::: exercise {#ex-a} Branch
Do it.

Hint: `git switch -c`.
:::
::: exercise
Second.
:::
::: checklist
[ ] open
[x] done
:::
::: scorecard
|| M | V ||
| TODO | 3 |
:::
::: definition
Baseline: a protected tag
  on main.
:::
{{include: tests/fixtures/reqif2sysml/courier.csv | lines 1-2}}
{{include-md: tests/fixtures/reqif2sysml/courier.csv}}
{{csv: tests/fixtures/reqif2sysml/courier.csv | Courier}}
{{figure: docs/img/halberd-tree.svg | Tree}}
{{pagebreak}}
EOF
spew("$SRC/03-part-app.txt", "= Appendices\n");
spew("$SRC/04-answers.txt", "== Answers {#answers}\n\n::: answer Exercise 1.1\nSee [[ex-a]].\n:::\n");
spew("$SRC/05-qrg-vim.txt", "== Vim card {#qrg-vim}\n\n=== Moving\n\n- `w` next word\n- `b` back\n\n```vim\n:make\n```\n");
spew("$SRC/06-qrg-git.txt", "== Git card {#qrg-git}\n\n|| Command | Does ||\n| `git status` | what changed |\nTable: Git\n");

@main::ERR = ();
my $doc = main::load_book(src => $SRC, root => $ROOT);
check_('book: no problems', join(' | ', @main::ERR), '');
my @ch = main::all_chapters($doc);
check_('book: chapters, front unnumbered, appendix lettered', join(',', map { $_->{num} // '-' } @ch), '-,1,A,B,C');
check_('book: metadata', "$doc->{meta}{title}|$doc->{meta}{subtitle}|$doc->{meta}{dedication}", 'Test Book|Sub|For you');
my ($first) = grep { $_->{slug} eq 'first' } @ch;
check_('book: block kinds in order', join(' ', map { $_->{k} } @{ $first->{blocks} }),
    'box para heading list list quote heading code table table box box box box box box box box box box code code table figure pagebreak');
my @boxes = grep { $_->{k} eq 'box' } @{ $first->{blocks} };
check_('book: box kinds', join(' ', map { $_->{kind} } @boxes), 'survival note tip warning sidebar objection exercise exercise checklist scorecard definition');
check_('book: exercises numbered per chapter, anchors', join(' ', map { "$_->{num}=$_->{slug}" } grep { $_->{kind} eq 'exercise' } @boxes), '1.1=ex-a 1.2=first--ex-2');
check_('book: objection answer is a subhead', join(' ', map { $_->{k} . ($_->{text} ? ":$_->{text}" : '') } @{ $boxes[5]{blocks} }), 'para subhead:Answer para');
check_('book: survival halves', join(' ', map { $_->{k} . ($_->{text} ? ":$_->{text}" : '') } @{ $boxes[0]{blocks} }), 'subhead:What you have list subhead:What you need list');
my @tables = grep { $_->{k} eq 'table' } @{ $first->{blocks} };
check_('book: only captioned tables are numbered', join(',', map { $_->{num} // '-' } @tables), '1.1,-,1.2');
check_('book: escaped bar in a cell', main::inline_plain($tables[0]{rows}[0][0]), 'a | b');
my ($list) = grep { $_->{k} eq 'list' } @{ $first->{blocks} };
check_('book: list continuation and nesting', main::inline_plain($list->{items}[0]{inl}) . ' / ' . main::inline_plain($list->{items}[0]{sub}[0]{items}[0]{inl}), 'one more / nested');
my ($code) = grep { $_->{k} eq 'code' && !$_->{caption} } @{ $first->{blocks} };
check_('book: code is verbatim', $code->{text}, qq{echo "hi"\ttab});
my ($inc) = grep { $_->{k} eq 'code' && ($_->{caption} // '') =~ /courier/ && !$_->{sample} } @{ $first->{blocks} };
check_('book: include with a line range', scalar(split /\n/, $inc->{text}), 2);

my $html = main::render_html($doc);
has('HTML', $html, qr/<nav class="toc">/, qr/<h1 class="part" id="part-part-i-one">Part I: One<\/h1>/,
    qr/<h2 class="chapter" id="first"><span class="num">1<\/span> The first chapter<\/h2>/, qr/<h3 id="sec-a"><span class="num">1\.1<\/span> Section A<\/h3>/,
    qr/<span class="num">Appendix A<\/span> Answers/, qr/<div class="box survival"><div class="boxtitle">Survival kit<\/div>/,
    qr/<div class="box exercise" id="ex-a"><div class="boxtitle">Exercise 1\.1: Branch<\/div>/, qr/<a href="#ex-a">Exercise 1\.1<\/a>/,
    qr/<a href="#how">the guide<\/a>/, qr/<caption>Table 1\.1\. A table<\/caption>/, qr/&#9744;<\/span> open/, qr/&#9745;<\/span> done/,
    qr/<figcaption>Figure 1\.1\. Tree<\/figcaption>/, qr/<svg/, qr/<ol class="footnotes"><li id="first-fn1">A footnote\./,
    qr/<figure class="code sample"><figcaption>tests\/fixtures/, qr/echo &quot;hi&quot;       tab/, qr/prefers-color-scheme: dark/, qr/\@media print/,
    qr/<blockquote><p>Why change\?<\/p><p class="who">&mdash; Bob, planning<\/p><\/blockquote>/, qr/<dt>Baseline<\/dt><dd>a protected tag on main\.<\/dd>/);
hasnt('HTML', $html, qr/<script/i, qr/\bsrc="http/);

# part introductions and quick reference cards
my ($p1) = @{ $doc->{parts} };
check_('part intro: blocks after the = Part line', join(' ', map { $_->{k} } @{ $p1->{intro} // [] }), 'para box');
has('HTML part intro and cards', $html, qr/<\/h1>\n<div class="partintro">\n<p>Why this part matters\.<\/p>/, qr/<section class="chapter qrg"><h2 class="chapter" id="qrg-vim">/, qr/section\.qrg \{/);

my ($tex, $figs) = main::render_tex($doc);
has('TeX', $tex, qr/^\\documentclass\[11pt,letterpaper,twoside,openany\]\{memoir\}/m, qr/\\frontmatter/, qr/\\mainmatter/, qr/\\tableofcontents\*/,
    qr/\\listoffigures\*/, qr/\\listoftables\*/, qr/\\part\{One\}/, qr/\\appendix\n\\cleardoublepage\n\\part\*\{Appendices\}/,
    qr/\\chapter\{The first chapter\}\\label\{first\}/, qr/\\section\{Section A\}\\label\{sec-a\}/, qr/\\subsection\{Sub\}/,
    qr/\\begin\{boxsurvival\}\{Survival kit\}/, qr/\\begin\{boxexercise\}\{Exercise 1\.1: Branch\}\\phantomsection\\label\{ex-a\}/,
    qr/\\hyperref\[ex-a\]\{Exercise 1\.1\}~\(p\.\\,\\pageref\*\{ex-a\}\)/, qr/\\footnote\{A footnote\.\}/, qr/\\begin\{longtable\}/,
    qr/\\caption\{A table\}/, qr/\\item\[\\checkbox\] open/, qr/\\item\[\\checkeddone\] done/, qr/\\begin\{Verbatim\}\necho "hi"       tab\n\\end\{Verbatim\}/,
    qr/\\codecaption\{GitLab Markdown: /, qr/\\IfFileExists\{fig-1-1\.pdf\}/, qr/\\speaker\{Bob, planning\}/, qr/\\boxsubhead\{Answer\}/, qr/\\end\{document\}\n\z/);
has('TeX part intro and cards', $tex, qr/\\renewcommand\*\{\\afterpartskip\}\{\\par\\vspace\{3\\onelineskip\}\}\n\\part\{One\}\n\n\\begin\{partintro\}\nWhy this part matters\./,
    qr/\\cleartorecto\n\\chapter\{Vim card\}\\label\{qrg-vim\}\n\\begin\{qrg\}\n\\begin\{multicols\}\{2\}/, qr/\\cleartorecto\n\\chapter\{Git card\}\\label\{qrg-git\}\n\\begin\{qrg\}\n\{\\small/);
# the cover (as docs/HALBERD.pdf): art, band, title, small-caps line, subtitle with the month
has('TeX cover', $tex, qr/\\frontmatter\n\\pagestyle\{empty\}\n\\IfFileExists\{cover-art\.jpg\}\{%\n\\begin\{titlingpage\}/, qr/\\includegraphics\[width=\\paperwidth\]\{cover-art\.jpg\}/,
    qr/\\fill\[black,opacity=0\.85\]/, qr/\\fontsize\{28\}\{33\}\\selectfont Test Book\}/, qr/\\scshape A Case Study\}/, qr/\{\\large Sub\}/, qr/\\usepackage\{tikz\}/);
has('HTML cover', $html, qr/<section class="cover" style="background-image:url\(img\/cover-art\.jpg\)"><div class="band"><div class="ctitle">Test Book<\/div><div class="cline">A Case Study<\/div><div class="csub">Sub<\/div>/);
@main::ERR = ();
my $cm = { title => 'MBSE-DEVSECOPS Primer', coverline => 'Field Manual', subtitle => 'x' x 90, edition => 'First edition, October 2026' };
my $cv = main::tex_cover($cm);
has('TeX cover: coverline, date from the edition, taller band for a long subtitle', $cv, qr/\\scshape Field Manual\}/, qr/\\textbullet\\ October 2026\}/, qr/rectangle \(\[yshift=2\.95in\]/);
check_('TeX cover: a long title wraps nearest the middle', main::cover_title('IAMD MBSE Integration Into DevSecOps'), 'IAMD MBSE Integration\\\\[2pt]\\fontsize{28}{33}\\selectfont Into DevSecOps');
check_('TeX: one figure to convert', scalar(@$figs) . ' ' . $figs->[0][0], '1 fig-1-1.pdf');
check_('deterministic: same source, same bytes', main::render_html(main::load_book(src => $SRC, root => $ROOT)) eq $html && (main::render_tex($doc))[0] eq $tex ? 1 : 0, 1);

# ---------------------------------------------------------------- problems: all reported, file:line, nothing written
my $BAD = "$TMP/bad";
spew("$BAD/01-part-a.txt", "= A\n");
spew("$BAD/02-c.txt", <<'EOF');
== C {#c}
= Not a part file
{{include: no/such/file.txt}}
{{figure: README.md | not svg}}
{{frobnicate: x}}
[[nowhere]] and `unclosed
::: bogus
x
:::
|| a | b ||
| 1 |
```klingon
x
```
::: note
never closed
EOF
my ($rc, $out) = run($^X, "$ROOT/sim/primer.pl", '--src', $BAD, '--html', "$TMP/bad.html", '--tex', "$TMP/bad.tex");
check_('bad source: exit 1', $rc, 1);
has('bad source', $out, qr/02-c\.txt:2: '= Part' belongs on the first line of a part file/, qr/02-c\.txt:3: \{\{include\}\}: no such file no\/such\/file\.txt/,
    qr/02-c\.txt:4: \{\{figure\}\}: README\.md is not an \.svg file/, qr/02-c\.txt:5: unknown directive \{\{frobnicate\}\}/, qr/02-c\.txt:6: unclosed `code` span/,
    qr/02-c\.txt:7: unknown box kind 'bogus'/, qr/02-c\.txt:11: table row has 1 cells, the header has 2/, qr/02-c\.txt:12: unknown code language 'klingon'/,
    qr/02-c\.txt:15: ::: note box never closed/, qr/02-c\.txt:6: \[\[nowhere\]\]: no chapter, section or exercise has that anchor/, qr/problem\(s\) in the source; nothing written/);
check_('bad source: nothing written', (-e "$TMP/bad.html" || -e "$TMP/bad.tex") ? 1 : 0, 0);

# --draft: a reference to a chapter not written yet is a warning, printed as [slug]
spew("$TMP/draft/02-c.txt", "== C {#c}\n\nSee [[later]] and [[later|the later chapter]].\n");
@main::ERR = ();
my $dd = main::load_book(src => "$TMP/draft", root => $ROOT, draft => 1);
check_('--draft: no errors, one warning per reference', scalar(@main::ERR) . ' ' . scalar(@{ $dd->{warnings} }), '0 2');
has('--draft HTML', main::render_html($dd), qr/<span class="missing">\[later\]<\/span> and <span class="missing">\[the later chapter\]<\/span>/);
has('--draft TeX', (main::render_tex($dd))[0], qr/\\textbf\{\[later\]\}/);
@main::ERR = ();
main::load_book(src => "$TMP/draft", root => $ROOT);
check_('without --draft each is an error', scalar @main::ERR, 2);

($rc, $out) = run($^X, "$ROOT/sim/primer.pl", '--check', '--src', $SRC);
check_('--check: exit 0', $rc, 0);
has('--check', $out, qr/^primer: 2 part\(s\), 5 chapter\(s\), \d+ words, \d+ code lines, \d+ tables, 1 figures, 12 boxes \(2 exercises\); about \d+ pages$/m);

# ---------------------------------------------------------------- runnable blocks, evidence directives, the number lint
my $RS = "$TMP/runs";
spew("$RS/01-part-a.txt", "= Part III: Twelve weeks\n");
spew("$RS/02-c.txt", <<'EOF');
== Sprint 1 {#s1}

```sh run sandbox=tidewater expect="^ok [0-9]+" exit=0
git status
```

```sh run
echo again
```

```vim run sandbox=scratch timeout=5
edit x.txt
```

```sh
not runnable
```

The model has {{count: tests/fixtures/reqif2sysml/courier.csv ^CD-}} DOORS rows and {{value: tests/status-metrics/dashboard.json m.A.elements}} elements.

{{value: tests/status-metrics/dashboard.json sprint}} closed with 52 TODO lines and {{n: 13}} sprints in a semester; 30 requirements were traced.

|| Measure | Value ||
| elements | {{value: tests/status-metrics/dashboard.json m.A.elements}} |
| typed | 7 merge requests |

- 4 story points carried
- Sprint 3 had no carryover
EOF
@main::ERR = ();
my $rd = main::load_book(src => $RS, root => $ROOT);
check_('runs: no problems', join(' | ', @main::ERR), '');
my @rr = main::runs($rd);
check_('runs: three runnable blocks, sandbox carried, options read', join(' ', map { "$_->{line}:$_->{lang}:$_->{sandbox}:$_->{exit}:" . ($_->{expect} // '-') . ':' . ($_->{timeout} // '-') } @rr),
    '3:sh:tidewater:0:^ok [0-9]+:- 7:sh:tidewater:0:-:- 11:vim:scratch:0:-:5');
my ($rp) = grep { $_->{k} eq 'para' } @{ (main::all_chapters($rd))[0]{blocks} };
check_('{{count}} and {{value}} inline', main::inline_plain($rp->{inl}), 'The model has 7 DOORS rows and 1960 elements.');
my ($rt) = grep { $_->{k} eq 'table' } @{ (main::all_chapters($rd))[0]{blocks} };
check_('{{value}} inside a table cell', main::inline_plain($rt->{rows}[0][1]), '1960');
my $rh = main::render_html($rd);
has('runnable blocks render like any code', $rh, qr/<figure class="code" data-run="tidewater"><pre data-lang="sh"><code>git status<\/code><\/pre><\/figure>/);
hasnt('runnable blocks render like any code', (main::render_tex($rd))[0], qr/\brun\b.*sandbox|expect=/);
check_('lint: bare numbers next to counted things, not definitions or evidence or names', join("\n", map { s/^.*?:(\d+): "(.*?)".*/$1 $2/r } @{ $rd->{lint} }),
    "21 52 TODO lines\n21 30 requirements\n23 7 merge requests\n27 4 story points");
{   # a quoted option value with backslashes keeps its key (expect="a\.b")
    @main::ERR = (); my $pr = main::parse_run('run expect="x\\.txt \"q\"\b" sandbox=kit', 'sh', 't:1');
    check_('run options: a quoted value keeps its regex escapes; only \" is unescaped', join(' ', map { "$_=$pr->{$_}" } sort keys %$pr) . ' ' . scalar(@main::ERR), 'expect=x\.txt "q"\b lang=sh sandbox=kit 0');
}
{   # a transcript (```text run): the "$ " lines run, a backslash continues a command, the output is shown only
    my $tr = main::transcript_commands("\$ ls -l drop1\ntotal 3\n-rw-r--r-- 1 bob 1 MANIFEST.txt\n\$ grep -c TW- \\\n> drop1/tidewater.csv\n30\nnot a command\n\$ pwd\n/c/Users/bob");
    check_('transcript: the commands, continuation joined', $tr, "ls -l drop1\ngrep -c TW- \\\ndrop1/tidewater.csv\npwd");
    my $TS = "$TMP/runs-t"; spew("$TS/02-c.txt", "== T {#t}\n\n```text run expect=\"OK\"\n\$ echo OK\nOK\n```\n");
    @main::ERR = (); my $td = main::load_book(src => $TS, root => $ROOT); my @tr = main::runs($td);
    check_('transcript: a runnable sh block with its commands only', join(' ', map { "$_->{lang}:$_->{text}:$_->{expect}" } @tr) . ' ' . scalar(@main::ERR), 'sh:echo OK:OK 0');
}
my ($rc0, $out0) = run($^X, "$ROOT/sim/primer.pl", '--check', '--src', $RS);
has('--check prints the lint', $out0, qr/02-c\.txt:21: "52 TODO lines" is a bare number: cite it with \{\{value: FILE KEY\}\} or \{\{count: FILE REGEX\}\}, or mark a definition with \{\{n: 52\}\}/);
($rc0, $out0) = run($^X, "$ROOT/sim/primer.pl", '--src', $RS, '--extract-runs', "$TMP/x");
check_('--extract-runs: exit 0', $rc0, 0);
check_('--extract-runs: manifest', slurp("$TMP/x/manifest.tsv") =~ /^chapter\tfile\tline\tblock\tlang\tsandbox\texit\ttimeout\texpect\tscript\ns1\t\S*02-c\.txt\t3\t1\tsh\ttidewater\t0\t\t\^ok \[0-9\]\+\ts1\/01\.sh\n.*\ts1\/03\.vim\n\z/s ? 1 : 0, 1);
check_('--extract-runs: block files and the chapter script', (slurp("$TMP/x/s1/02.sh") // '') . (slurp("$TMP/x/s1.sh") =~ /# ---- \S*02-c\.txt:3  block 1  sandbox tidewater  exit 0  expect \/\^ok / ? '+' : '-'), "echo again\n+");
spew("$RS/02-c.txt", "== C {#c}\n\n```perl run\nx\n```\n\n```sh run sandbox=moon exit=x bogus=1\ny\n```\n\n```sh fast\nz\n```\n\n```sh run expect=(\nw\n```\n\n{{count: tests/fixtures/reqif2sysml/courier.csv (}}\n");
($rc0, $out0) = run($^X, "$ROOT/sim/primer.pl", '--check', '--src', $RS);
has('bad run options', $out0, qr/02-c\.txt:3: only sh, vim and text \(a \$ transcript\) code blocks can be runnable, not 'perl'/, qr/02-c\.txt:7: unknown run option 'bogus'/,
    qr/02-c\.txt:7: unknown sandbox 'moon'/, qr/02-c\.txt:7: exit= needs a number, not 'x'/, qr/02-c\.txt:11: code block options must start with 'run'/,
    qr/02-c\.txt:15: expect= is not a regular expression/, qr/02-c\.txt:19: \{\{count\}\}: bad regular expression/);

# quoted run options keep their backslashes (only \" is an escaped quote); a bare exit in a runnable block is linted
@main::ERR = ();
my $ro = main::parse_run(q{run expect="foo\(bar\) \"q\"" exit=0}, 'sh', 'x:1');
check_('run options: backslashes kept in quoted values', $ro->{expect}, q{foo\(bar\) "q"});
check_('run options: the kept escapes still match literally', ('foo(bar) "q"' =~ /$ro->{expect}/ ? 1 : 0), 1);
spew("$TMP/ex/02-c.txt", "== C {#c}\n\n```sh run\necho a\n  exit 2\nsh -c 'exit 3' || echo \"exit status \$?\"\n```\n");
@main::ERR = ();
my $ed = main::load_book(src => "$TMP/ex", root => $ROOT);
check_('lint: a bare exit line in a runnable block, not one inside sh -c', join("\n", @{ $ed->{lint} }), qq{$ed->{shown}/02-c.txt:5: a runnable block must not 'exit' (a reader typing it closes their shell): show a failure with  cmd || echo "exit status \$?"  and expect=});

# --extract-runs with a half-written chapter: its errors are printed, the other chapters are still extracted, exit 1
spew("$TMP/ex/03-d.txt", "== D {#d}\n\n::: note\nnever closed\n");
my ($rcx, $outx) = run($^X, "$ROOT/sim/primer.pl", '--src', "$TMP/ex", '--extract-runs', "$TMP/ex-out");
check_('--extract-runs with a broken chapter: exit 1', $rcx, 1);
has('--extract-runs with a broken chapter', $outx, qr/03-d\.txt:3: ::: note box never closed/, qr/their chapters were left out/, qr/wrote 1 runnable block\(s\)/);

# @before-contents: a front-matter chapter read before the contents (the bottom line up front)
spew("$TMP/bl/00-a.txt", "\@title: T\n\n== Bottom line up front {#bluf} \@before-contents\n\nRead this first.\n\n== Preface {#preface}\n\nThen this.\n");
spew("$TMP/bl/01-part-a.txt", "= Part I: A\n");
spew("$TMP/bl/02-c.txt", "== C {#c}\n\nSee [[bluf]].\n");
@main::ERR = ();
my $bd = main::load_book(src => "$TMP/bl", root => $ROOT);
check_('@before-contents: parsed, no errors', join(',', @main::ERR) . '|' . join(',', map { "$_->{slug}=" . ($_->{before} ? 1 : 0) } @{ $bd->{front} }), '|bluf=1,preface=0');
my $bh = main::render_html($bd);
check_('@before-contents HTML: after the title page, before the contents, then the other front matter',
    join(' < ', map { my $p = index($bh, $_); $p < 0 ? "missing $_" : $p } 'class="titlepage"', 'id="bluf"', 'id="contents"', 'id="preface"') =~ /^(\d+) < (\d+) < (\d+) < (\d+)$/ && $1 < $2 && $2 < $3 && $3 < $4 ? 1 : 0, 1);
my ($bt) = main::render_tex($bd);
has('@before-contents TeX', $bt, qr/\\cleardoublepage\n\\pagestyle\{ruled\}\n\\chapter\*\{Bottom line up front\}\\label\{bluf\}\n\\markboth\{Bottom line up front\}\{Bottom line up front\}\n\nRead this first\.\n\n\\clearpage\n\\pagestyle\{ruled\}\n\\tableofcontents\*/,
    qr/\\tableofcontents\*\n.*\\chapter\{Preface\}/s);
hasnt('@before-contents TeX', $bt, qr/\\chapter\{Bottom line up front\}/);
spew("$TMP/bl/02-c.txt", "== C {#c} \@before-contents\n\nx\n");
@main::ERR = ();
main::load_book(src => "$TMP/bl", root => $ROOT);
check_('@before-contents in a part is an error', join(' ', @main::ERR) =~ /02-c\.txt:1: \@before-contents is only for front-matter chapters/ ? 1 : 0, 1);

# ---------------------------------------------------------------- the real book
my $done = -f "$ROOT/docs/mbse-devsecops-primer.html";   # while the book is being written, forward references may name chapters not written yet
($rc, $out) = run($^X, "$ROOT/sim/primer.pl", '--check', $done ? () : '--draft');
check_('docs/src/primer passes --check' . ($done ? '' : ' --draft'), $rc, 0);
print map { "#   $_\n" } split /\n/, $out if $rc;
if (-f "$ROOT/docs/mbse-devsecops-primer.html" && -f "$ROOT/docs/mbse-devsecops-primer.tex") {
    ($rc, $out) = run($^X, "$ROOT/sim/primer.pl", '--html', "$TMP/p.html", '--tex', "$TMP/p.tex");
    check_('the committed primer HTML is what sim/primer.pl writes (rerun perl sim/primer.pl)', (slurp("$TMP/p.html") // '') eq (slurp("$ROOT/docs/mbse-devsecops-primer.html") // '-') ? 1 : 0, 1);
    check_('the committed primer TeX is what sim/primer.pl writes (rerun perl sim/primer.pl)', (slurp("$TMP/p.tex") // '') eq (slurp("$ROOT/docs/mbse-devsecops-primer.tex") // '-') ? 1 : 0, 1);
} else { $n++; print "ok $n - committed primer is current # skip docs/mbse-devsecops-primer.html not written yet\n" }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
