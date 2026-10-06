#!/usr/bin/perl
# tools/gitlab/pages-index.pl -- the front page of the model's GitLab Pages site (the `pages` job).
#
#   pages-index.pl [--title T] [--commit SHA] [--date D] DIR
#
# DIR is the folder the pages job publishes (public/). The job first copies or writes into it:
#   docs/*.md               the generated model docs (model.pl docs)       -> each also written as docs/<name>.html
#   views/*.svg             the model views (model.pl draw tree|trace|pkg) -> shown on the page
#   trace.txt               reqif2sysml.pl --report --model output         -> the requirement trace summary
#   todo-burndown.csv       date,todo_lines per merge to the default branch -> the port burn-down chart
# and this script writes DIR/index.html: one self-contained page (no scripts, nothing external) for readers who never
# open the repository -- the program office, the prime, the review board. Missing inputs are left out of the page.
#
# Core Perl, standalone.
use strict;
use warnings;
use Getopt::Long;

my %o = (title => 'Tidewater model', commit => $ENV{CI_COMMIT_SHORT_SHA} // '', date => $ENV{CI_COMMIT_TIMESTAMP} // '');
GetOptions(\%o, 'title=s', 'commit=s', 'date=s') or die "usage: pages-index.pl [--title T] [--commit SHA] [--date D] DIR\n";
my $dir = shift @ARGV or die "usage: pages-index.pl [--title T] [--commit SHA] [--date D] DIR\n";
-d $dir or die "pages-index: $dir is not a directory\n";

sub esc { my ($t) = @_; $t //= ''; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t }
sub slurp { my ($p) = @_; open my $fh, '<', $p or return undef; local $/; my $t = <$fh>; close $fh; $t =~ s/\r\n/\n/g; $t }
sub spew { my ($p, $t) = @_; open my $fh, '>', $p or die "pages-index: cannot write $p: $!\n"; binmode $fh; print $fh $t; close $fh }
sub ls { my ($d, $re) = @_; opendir my $dh, $d or return (); my @f = sort grep { $_ =~ $re } readdir $dh; closedir $dh; @f }

my $css = 'body{font-family:Calibri,"Segoe UI",Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;max-width:1100px;margin:2em auto;padding:0 16px;line-height:1.5}'
        . 'h1{font-size:18pt;border-bottom:3px solid #27235d;padding-bottom:.2em}h2{font-size:14pt;margin-top:1.8em;border-bottom:1px solid #999}'
        . 'pre{background:#f4f4f4;border:1px solid #ddd;padding:.8em 1em;overflow-x:auto;font-size:9.5pt}table{border-collapse:collapse}'
        . 'th,td{border:1px solid #bbb;padding:.3em .6em;text-align:left}th{background:#e4e4e7}.muted{color:#555;font-size:9.5pt}'
        . 'img{max-width:100%;border:1px solid #ddd;margin:.5em 0}a{color:#27235d}';
sub page { my ($title, $body) = @_; qq(<!DOCTYPE html>\n<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">\n<title>) . esc($title) . qq(</title><style>$css</style></head>\n<body>\n$body\n</body></html>\n) }

my $body = '<h1>' . esc($o{title}) . "</h1>\n<p class=muted>Built by the pipeline from the default branch"
         . ($o{commit} ? ' at commit <code>' . esc($o{commit}) . '</code>' : '') . ($o{date} ? ', ' . esc($o{date}) : '')
         . ". Everything here is generated from the model; nothing is typed by hand.</p>\n";

# the port burn-down
if (defined(my $csv = slurp("$dir/todo-burndown.csv"))) {
    my @pts = map { [ split /,/ ] } grep { /^\d{4}-\d\d-\d\d,\d+$/ } split /\n/, $csv;
    if (@pts) {
        my ($w, $h, $l, $b) = (760, 220, 50, 30);
        my $max = 1; $max < $_->[1] and $max = $_->[1] for @pts;
        my $n = @pts;
        my @xy = map { [ $l + ($n == 1 ? 0 : $_ * ($w - $l - 10) / ($n - 1)), 10 + ($h - $b - 10) * (1 - $pts[$_][1] / $max) ] } 0 .. $#pts;
        my $svg = qq(<svg viewBox="0 0 $w $h" role="img" aria-label="TODO lines remaining over time" font-family="Calibri,Arial,sans-serif" font-size="11">)
                . qq(<line x1="$l" y1="10" x2="$l" y2="@{[ $h - $b ]}" stroke="#808082"/><line x1="$l" y1="@{[ $h - $b ]}" x2="@{[ $w - 10 ]}" y2="@{[ $h - $b ]}" stroke="#808082"/>)
                . qq(<text x="@{[ $l - 6 ]}" y="14" text-anchor="end">$max</text><text x="@{[ $l - 6 ]}" y="@{[ $h - $b ]}" text-anchor="end">0</text>)
                . qq(<text x="$l" y="@{[ $h - 10 ]}">) . esc($pts[0][0]) . qq(</text><text x="@{[ $w - 10 ]}" y="@{[ $h - 10 ]}" text-anchor="end">) . esc($pts[-1][0]) . '</text>'
                . qq(<polyline fill="none" stroke="#27235d" stroke-width="2.5" points=") . join(' ', map { sprintf '%.1f,%.1f', @$_ } @xy) . '"/>'
                . qq(<circle cx="$xy[-1][0]" cy="$xy[-1][1]" r="4" fill="#27235d"/></svg>);
        $body .= "<h2>Port burn-down</h2>\n<p>Converter TODO lines left in the model, at each merge to the default branch. "
               . "Now <b>$pts[-1][1]</b>, from $max at the start.</p>\n$svg\n";
    }
}

# requirement trace
if (defined(my $tr = slurp("$dir/trace.txt"))) {
    my @rows;
    for my $re ([ 'Requirements linked to the model', qr/^C requirements linked.*?(\d+ of \d+)/m ], [ 'Orphans (nothing satisfies them)', qr/^F orphan requirements.*?(\d+)\s*$/m ],
                [ 'Unverified (nothing verifies them)', qr/^G unverified requirements.*?(\d+)\s*$/m ], [ 'Trace completeness', qr/^I trace completeness.*?([\d.]+%)/m ],
                [ 'Text differs from DOORS', qr/^text differs from DOORS\s+(\d+)/m ]) {
        push @rows, '<tr><td>' . esc($re->[0]) . '</td><td>' . esc($1) . "</td></tr>\n" if $tr =~ $re->[1];
    }
    $body .= "<h2>Requirement trace</h2>\n<p>DOORS (the prime's requirements, as delivered) against the model.</p>\n"
           . (@rows ? "<table>\n<tr><th>Measure</th><th>Now</th></tr>\n" . join('', @rows) . "</table>\n" : '')
           . '<details><summary>The full report</summary><pre>' . esc($tr) . "</pre></details>\n";
}

# model views
if (my @svg = ls("$dir/views", qr/\.svg$/)) {
    $body .= "<h2>Model views</h2>\n";
    for my $f (@svg) { (my $t = $f) =~ s/\.svg$//; $body .= '<h3>' . esc($t) . qq(</h3>\n<a href="views/) . esc($f) . qq("><img src="views/) . esc($f) . qq(" alt="model view: ) . esc($t) . qq("></a>\n) }
}

# generated docs: each .md also as a readable .html
if (my @md = ls("$dir/docs", qr/\.md$/)) {
    $body .= "<h2>Generated model documents</h2>\n<ul>\n";
    for my $f (@md) {
        (my $h = $f) =~ s/\.md$/.html/;
        spew("$dir/docs/$h", page("$o{title}: $f", '<p><a href="../index.html">&larr; ' . esc($o{title}) . '</a></p><pre>' . esc(slurp("$dir/docs/$f")) . '</pre>'));
        $body .= qq(<li><a href="docs/) . esc($h) . '">' . esc($f) . "</a></li>\n";
    }
    $body .= "</ul>\n";
}

spew("$dir/index.html", page($o{title}, $body));
print "wrote $dir/index.html\n";
