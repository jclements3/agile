#!/usr/bin/perl
# tools/gitlab/ci-reports.pl -- turns the kit's model checks into the report files GitLab shows on a merge request.
#
#   ci-reports.pl grammar [--junit F] [--codequality F] LOG [FILE...]      LOG = `sysml.pl check` output; FILEs = what was checked
#   ci-reports.pl lint    [--junit F] [--codequality F] [--metrics F] LOG  LOG = `model.pl lint` output
#   ci-reports.pl outline [--junit F] [--codequality F] [--metrics F] LOG  LOG = `model.pl check` output
#   ci-reports.pl todo    [--junit F] [--codequality F] [--metrics F] DIR|LOG   a model directory, or `grep -rn '// TODO'` output
#   ci-reports.pl trace   [--junit F] [--metrics F] LOG                    LOG = `reqif2sysml.pl --report --model` output
#   (LOG may be - for standard input)
#
# The outputs are the three report types a GitLab pipeline job can attach (artifacts:reports):
#   --junit        JUnit XML: the MR's test widget lists each failed check, with its message.
#   --codequality  Code Quality JSON (the Code Climate subset GitLab reads): one finding per error, warning or TODO line,
#                  with path, line, severity and a fingerprint (md5 of path and message, so a finding keeps its identity
#                  when lines move). The MR widget shows which findings the change added or fixed.
#   --metrics      Metrics text, one "name value" per line (Premium shows the change in each value on the MR).
# The job keeps failing or passing on the checker's own exit status; this script only reports, and exits 0 unless its
# input cannot be read.
#
# Core Perl, standalone (no kit libraries), so a runner needs nothing but Perl.
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Getopt::Long qw(GetOptionsFromArray);

$SIG{__DIE__} = sub { print STDERR $_[0]; exit 2 };   # unreadable or unrecognised input: exit 2, like a usage error

sub usage { print STDERR "usage: ci-reports.pl grammar|lint|outline|todo|trace [--junit F] [--codequality F] [--metrics F] LOG|DIR [FILE...]\n"; exit 2 }

my $mode = shift @ARGV // usage();
usage() unless $mode =~ /^(grammar|lint|outline|todo|trace)$/;
my %o;
GetOptionsFromArray(\@ARGV, \%o, 'junit=s', 'codequality=s', 'metrics=s') or usage();
my $in = shift @ARGV // usage();
my @files = @ARGV;

sub slurp { my ($p) = @_; my $fh; if ($p eq '-') { $fh = \*STDIN } else { open $fh, '<', $p or die "ci-reports: cannot read $p: $!\n" }
    local $/; my $t = <$fh>; $t //= ''; $t =~ s/\r\n/\n/g; $t }
sub xml { my ($t) = @_; $t //= ''; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g; $t }
sub js  { my ($t) = @_; $t //= ''; $t =~ s/\\/\\\\/g; $t =~ s/"/\\"/g; $t =~ s/\n/\\n/g; $t =~ s/\t/\\t/g; $t =~ s/([\x00-\x1f])/sprintf('\\u%04x', ord $1)/ge; "\"$t\"" }
sub spew { my ($p, $t) = @_; open my $fh, '>', $p or die "ci-reports: cannot write $p: $!\n"; binmode $fh; print $fh $t; close $fh }

# A report is: cases => [ { suite, name, file, fail => message|undef, detail } ], findings => [ { check, path, line,
# severity, message } ], metrics => [ [name, value] ].
my %r = (cases => [], findings => [], metrics => []);
my $DIAG = qr/^(\S.*?\.sysml):(\d+)(?::\d+)?: (error|warning): (.*)$/;

if ($mode eq 'grammar' || $mode eq 'lint') {
    my $log = slurp($in);
    my (%by, @order);
    for my $l (split /\n/, $log) {
        next unless $l =~ $DIAG;
        my ($f, $line, $sev, $msg) = ($1, $2, $3, $4);
        push @order, $f unless $by{$f};
        push @{ $by{$f} }, [ $line, $sev, $msg ];
        push @{ $r{findings} }, { check => "sysml-$mode", path => $f, line => $line,
            severity => $mode eq 'grammar' ? 'critical' : $sev eq 'error' ? 'major' : 'minor', message => $msg };
    }
    my %seen; my @all = grep { !$seen{$_}++ } (@files, @order);
    for my $f (@all) {
        my @d = @{ $by{$f} // [] };
        my @err = grep { $_->[1] eq 'error' } @d;
        push @{ $r{cases} }, { suite => $mode, name => $f, file => $f,
            fail => @err ? sprintf('%d error(s), first at line %d: %s', scalar @err, $err[0][0], $err[0][2]) : undef,
            detail => join("\n", map { "$f:$_->[0]: $_->[1]: $_->[2]" } @d) };
    }
    if ($mode eq 'lint') {
        my ($el, $e, $w) = $log =~ /^elements=(\d+) errors=(\d+) warnings=(\d+)\s*$/m;
        die "ci-reports: no 'elements=N errors=E warnings=W' line in $in (is it model.pl lint output?)\n" unless defined $el;
        push @{ $r{metrics} }, [ model_elements => $el ], [ lint_errors => $e ], [ lint_warnings => $w ];
        push @{ $r{cases} }, { suite => 'lint', name => 'lint 0/0', file => '', fail => ($e || $w) ? "errors=$e warnings=$w" : undef, detail => '' };
    } else {
        my ($n, $e) = $log =~ /^sysml: (\d+) file\(s\), (\d+) error\(s\)/m;
        push @{ $r{metrics} }, [ grammar_files => $n // scalar @all ], [ grammar_errors => $e // scalar @{ $r{findings} } ];
    }
}
elsif ($mode eq 'outline') {
    my $log = slurp($in);
    my ($mm) = $log =~ /^\@L tag mismatches\s+(\d+)/m;
    my ($viol) = $log =~ /^violations\s+(\d+)/m;
    die "ci-reports: no '\@L tag mismatches' or 'violations' line in $in (is it model.pl check output?)\n" unless defined $mm || defined $viol;
    my (@tags, @outl, $sec);
    for my $l (split /\n/, $log) {
        if ($l =~ /^== Level tags/) { $sec = 'tags'; next }
        if ($l =~ /^== Outline/)    { $sec = 'outline'; next }
        next unless $sec;
        if ($sec eq 'tags' && $l =~ /^  (\S.*): tagged L(\d+), first reached at L(\d+)$/) { push @tags, [ $1, $2, $3 ] }
        if ($sec eq 'outline' && $l =~ /^\s+(\d+)  (.*)  \((.*)\)$/) { push @outl, [ $1, $2, $3 ] }
    }
    for my $t (@tags) {
        push @{ $r{findings} }, { check => 'level-tag', path => 'model', line => 1, severity => 'minor',
            message => "$t->[0]: tagged L$t->[1], first reached at L$t->[2]" };
    }
    for my $v (@outl) {
        (my $path = $v->[2]) =~ s{/$}{};
        push @{ $r{findings} }, { check => 'outline', path => $path, line => 1, severity => 'minor',
            message => "$v->[1]: $v->[0] (outside 2..9)" };
    }
    push @{ $r{cases} }, { suite => 'outline', name => 'level tags', file => '', fail => @tags ? scalar(@tags) . ' mismatch(es)' : undef,
        detail => join("\n", map { "$_->[0]: tagged L$_->[1], first reached at L$_->[2]" } @tags) };
    push @{ $r{cases} }, { suite => 'outline', name => '2..9 children per parent', file => '', fail => @outl ? scalar(@outl) . ' violation(s)' : undef,
        detail => join("\n", map { "$_->[2]: $_->[1] = $_->[0]" } @outl) };
    push @{ $r{metrics} }, [ level_tag_mismatches => $mm // 0 ], [ outline_violations => $viol // 0 ];
}
elsif ($mode eq 'todo') {
    my @hits;                                         # [ path, line, text ]
    if (-d $in) {
        my @stack = ($in);
        my @found;
        while (my $d = shift @stack) {
            opendir my $dh, $d or die "ci-reports: cannot read $d: $!\n";
            for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$d/$e"; if (-d $p) { push @stack, $p } elsif ($e =~ /\.sysml$/) { push @found, $p } }
            closedir $dh;
        }
        for my $f (sort @found) {
            open my $fh, '<', $f or die "ci-reports: cannot read $f: $!\n";
            while (my $l = <$fh>) { push @hits, [ $f, $., $1 ] if $l =~ m{//\s*(TODO\b.*?)\s*$} }
            close $fh;
        }
    } else {
        for my $l (split /\n/, slurp($in)) { push @hits, [ $1, $2, $3 ] if $l =~ m{^(.*?):(\d+):.*?//\s*(TODO\b.*?)\s*$} }
    }
    my %pkg;
    for my $h (@hits) {
        my ($p) = $h->[0] =~ m{(?:^|/)model/([^/]+)/};
        $pkg{ $p // 'other' }++;
        (my $msg = $h->[2]) =~ s/\s*\(xmi:id [^)]*\)//;    # the fingerprint survives a re-numbered element
        push @{ $r{findings} }, { check => 'todo', path => $h->[0], line => $h->[1], severity => 'info', message => $msg };
    }
    push @{ $r{metrics} }, [ todo_lines => scalar @hits ], map { [ "todo_lines_$_" => $pkg{$_} ] } sort keys %pkg;
    push @{ $r{cases} }, { suite => 'todo', name => 'converter TODO lines', file => '', fail => undef,
        detail => scalar(@hits) . " TODO line(s): " . join(', ', map { "$_ $pkg{$_}" } sort keys %pkg) };
}
elsif ($mode eq 'trace') {
    my $log = slurp($in);
    my ($lk, $tot) = $log =~ /^C requirements linked.*?(\d+) of (\d+)/m;
    die "ci-reports: no 'C requirements linked' line in $in (is it reqif2sysml.pl --report --model output?)\n" unless defined $lk;
    my ($orph) = $log =~ /^F orphan requirements.*?(\d+)\s*$/m;
    my ($unv)  = $log =~ /^G unverified requirements.*?(\d+)\s*$/m;
    my ($comp) = $log =~ /^I trace completeness.*?([\d.]+)%/m;
    my ($drift) = $log =~ /^text differs from DOORS\s+(\d+)/m;
    my %list = map { $_ => [] } qw(orphans unverified drift), 'not in the model';
    for my $k (keys %list) { my ($l) = $log =~ /^\Q$k\E: (.*)$/m; $list{$k} = [ split ' ', $l // '' ] }
    push @{ $r{metrics} }, [ trace_linked => $lk ], [ trace_total => $tot ], [ trace_orphans => $orph // scalar @{ $list{orphans} } ],
        [ trace_unverified => $unv // scalar @{ $list{unverified} } ], [ trace_completeness_pct => $comp // 0 ],
        [ trace_drift => $drift // scalar @{ $list{drift} } ], [ trace_not_in_model => scalar @{ $list{'not in the model'} } ];
    my %what = (orphans => 'nothing satisfies it', unverified => 'nothing verifies it', drift => 'the text differs from DOORS',
                'not in the model' => 'in DOORS, not in the model');
    for my $k ('not in the model', 'orphans', 'unverified', 'drift') {
        for my $id (@{ $list{$k} }) { push @{ $r{cases} }, { suite => "trace $k", name => $id, file => '', fail => "$id: $what{$k}", detail => '' } }
    }
    push @{ $r{cases} }, { suite => 'trace', name => 'requirements linked', file => '', fail => $lk < $tot ? "$lk of $tot linked" : undef, detail => '' };
}

# ---------------------------------------------------------------- writers
if ($o{junit}) {
    my %suites; my @sorder;
    for my $c (@{ $r{cases} }) { push @sorder, $c->{suite} unless $suites{ $c->{suite} }; push @{ $suites{ $c->{suite} } }, $c }
    my $total = @{ $r{cases} }; my $fails = grep { defined $_->{fail} } @{ $r{cases} };
    my $x = qq(<?xml version="1.0" encoding="UTF-8"?>\n<testsuites name="sysml-$mode" tests="$total" failures="$fails">\n);
    for my $s (@sorder) {
        my @c = @{ $suites{$s} }; my $f = grep { defined $_->{fail} } @c;
        $x .= sprintf qq(  <testsuite name="%s" tests="%d" failures="%d">\n), xml($s), scalar @c, $f;
        for my $c (@c) {
            $x .= sprintf qq(    <testcase classname="%s" name="%s"%s), xml($s), xml($c->{name}), $c->{file} ? sprintf(' file="%s"', xml($c->{file})) : '';
            if (defined $c->{fail}) { $x .= sprintf qq(>\n      <failure message="%s" type="%s">%s</failure>\n    </testcase>\n), xml($c->{fail}), xml($mode), xml($c->{detail} || $c->{fail}) }
            elsif ($c->{detail}) { $x .= sprintf qq(>\n      <system-out>%s</system-out>\n    </testcase>\n), xml($c->{detail}) }
            else { $x .= "/>\n" }
        }
        $x .= "  </testsuite>\n";
    }
    spew($o{junit}, "$x</testsuites>\n");
}
if ($o{codequality}) {
    my %seen;
    my @j;
    for my $f (@{ $r{findings} }) {
        my $fp = md5_hex("$f->{path}\0$f->{check}\0$f->{message}");
        my $n = $seen{$fp}++; $fp = md5_hex("$fp$n") if $n;            # the same message twice in a file: still two findings
        push @j, sprintf qq(  {"description": %s, "check_name": %s, "fingerprint": "%s", "severity": "%s", "location": {"path": %s, "lines": {"begin": %d}}}),
            js($f->{message}), js($f->{check}), $fp, $f->{severity}, js($f->{path}), $f->{line};
    }
    spew($o{codequality}, @j ? "[\n" . join(",\n", @j) . "\n]\n" : "[]\n");
}
if ($o{metrics}) { spew($o{metrics}, join('', map { "$_->[0] $_->[1]\n" } @{ $r{metrics} })) }

my $nf = grep { defined $_->{fail} } @{ $r{cases} };
printf "ci-reports %s: %d check(s), %d failed, %d finding(s)%s\n", $mode, scalar @{ $r{cases} }, $nf, scalar @{ $r{findings} },
    @{ $r{metrics} } ? '; ' . join(' ', map { "$_->[0]=$_->[1]" } @{ $r{metrics} }) : '';
exit 0;
