#!/usr/bin/env perl
# sysml.pl -- SysML v2 / KerML syntax checker generated from the official grammar.
# Core Perl 5 only (Git for Windows), functional style on lib/Prelude.pm.
#
#   perl tools/sysml/sysml.pl check FILE...       syntax-check files; GNU diagnostics; exit 1 on errors
#   perl tools/sysml/sysml.pl corpus [DIR...]     check every .sysml/.kerml file under DIRs (default:
#                                             the vendored standard library and examples)
#   perl tools/sysml/sysml.pl tokens FILE         show the token stream (debugging)
#   perl tools/sysml/sysml.pl grammar             grammar summary: rules, keywords, symbols
#   perl tools/sysml/sysml.pl crosscheck [N] [SEED]
#                                           differential test against the Pilot implementation
#                                           (needs Java): N mutants of the example models, each
#                                           judged by both; every disagreement is listed
#
# The grammar is read at start-up from vendor/sysml-v2-release/bnf/*.kebnf next to this script (the
# KerML and SysML v2 textual-notation grammars published by the Systems-Modeling project), so a new
# release is picked up by replacing those two files. Runs from any directory; Prelude.pm is the kit's lib/.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../../lib";    # SysML::*, then the kit's Prelude.pm
use File::Find ();
use File::Spec;
use Time::HiRes qw(time);
use Prelude qw(fmap filter partition foldl isOk isErr unwrap either Ok Err sortOn take);
use SysML::Grammar;
use SysML::Lexer;
use SysML::Parser;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $ROOT = File::Spec->rel2abs($FindBin::Bin);   # tools/sysml: the grammar and the vendored release live here
my $BNF  = File::Spec->catdir($ROOT, 'vendor', 'sysml-v2-release', 'bnf');

# ---------------------------------------------------------------- pure pipeline
sub language { $_[0] =~ /\.kerml\z/i ? 'kerml' : 'sysml' }

my %CHECKER;                            # language -> (Text -> Either Diagnostic Ok), built once
sub checker {
    my $lang = shift;
    $CHECKER{$lang} //= do {
        my $g = unwrap(SysML::Grammar::load($lang, $BNF));
        my ($scan, $recognize) = (SysML::Lexer::scanner($g), SysML::Parser::recognizer($g));
        sub {
            my $text = shift;
            my $toks = $scan->($text);
            return Err({ offset => $toks->[1][0], message => $toks->[1][1] }) if isErr($toks);
            my $tokens = unwrap($toks);
            my $r = $recognize->($tokens);
            isOk($r) ? Ok(scalar @$tokens) : Err(failure_message($r->[1], $tokens, length $text));
        };
    };
}

sub failure_message {                   # Failure -> {offset, message}
    my ($f, $tokens, $len) = @_;
    my $t = $f->{found};
    my @exp = @{ $f->{expected} };
    my $exp = @exp > 8 ? join(', ', take(8, @exp)) . ', ...' : join(', ', @exp);
    +{ offset  => $t ? $t->[2] : $len,
       message => ($t ? "unexpected '$t->[1]'" : 'unexpected end of file') . (@exp ? "; expected $exp" : '') };
}

sub slurp {
    my $f = shift;
    open my $fh, '<:encoding(UTF-8)', $f or return Err("cannot read $f: $!");
    my $t = do { local $/; <$fh> };
    close $fh;
    $t =~ s/\r\n?/\n/g;
    Ok($t);
}

sub check_file {                        # Path -> {file, ok, tokens | diagnostic, seconds}
    my $f = shift;
    my $t0 = time;
    my $text = slurp($f);
    return { file => $f, ok => 0, diag => "$f: error: $text->[1]", seconds => 0 } if isErr($text);
    my $src = unwrap($text);
    my $r = checker(language($f))->($src);
    my $secs = time - $t0;
    either(
        sub { my $e = shift; my ($l, $c) = SysML::Lexer::line_col($src, $e->{offset});
              +{ file => $f, ok => 0, diag => "$f:$l:$c: error: $e->{message}", seconds => $secs } },
        sub { +{ file => $f, ok => 1, tokens => $_[0], seconds => $secs } },
        $r);
}

sub files_under {
    my @out;
    File::Find::find({ no_chdir => 1, wanted => sub { push @out, $_ if /\.(?:sysml|kerml)\z/ && -f $_ } }, @_);
    sort @out;
}

sub rel {                               # relative to the current directory, unless that means climbing out of it
    my $a = File::Spec->rel2abs($_[0]);
    my $p = File::Spec->abs2rel($a);
    $p = $a if $p =~ m{^\.\.(?:[/\\]|\z)};
    $p =~ s{\\}{/}g;
    $p;
}

# ---------------------------------------------------------------- commands
sub cmd_check {
    my @results = fmap(\&check_file, @_);
    my ($ok, $bad) = partition(sub { $_[0]{ok} }, @results);
    print "$_->{diag}\n" for @$bad;
    printf "sysml: %d file(s), %d error(s)\n", scalar @results, scalar @$bad;
    @$bad ? 1 : 0;
}

sub cmd_corpus {
    my @dirs = @_ ? @_ : (File::Spec->catdir($ROOT, 'vendor', 'sysml-v2-release'));
    my @files = files_under(@dirs);
    my $t0 = time;
    my @results = fmap(sub { my $r = check_file($_[0]); $r->{file} = rel($r->{file}); $r->{diag} =~ s/^\Q$_[0]\E/$r->{file}/ if $r->{diag}; $r }, @files);
    my ($ok, $bad) = partition(sub { $_[0]{ok} }, @results);
    print "$_->{diag}\n" for @$bad;
    my $tokens = foldl(sub { $_[0] + ($_[1]{tokens} // 0) }, 0, @$ok);
    my @slow = take(3, sortOn(sub { -$_[0]{seconds} }, @results));
    printf "corpus: %d file(s): %d parsed, %d failed; %d tokens in %.1f s\n",
        scalar @results, scalar @$ok, scalar @$bad, $tokens, time - $t0;
    printf "  slowest: %s (%.2f s)\n", $_->{file}, $_->{seconds} for @slow;
    @$bad ? 1 : 0;
}

sub cmd_tokens {
    my $f = shift or return usage();
    my $g = unwrap(SysML::Grammar::load(language($f), $BNF));
    my $toks = SysML::Lexer::scanner($g)->(unwrap(slurp($f)));
    return either(sub { print "lexical error at offset $_[0][0]: $_[0][1]\n"; 1 },
                  sub { printf "%-8s %s\n", $_->[0], $_->[1] for @{ $_[0] }; 0 }, $toks);
}

sub cmd_grammar {
    for my $lang (qw(kerml sysml)) {
        my $g = unwrap(SysML::Grammar::load($lang, $BNF));
        my @undef = SysML::Grammar::undefined_refs($g);
        printf "%-6s %3d rules, %3d keywords, %2d symbols, start %s%s\n", $lang, scalar(keys %{ $g->{rules} }),
            scalar @{ $g->{keywords} }, scalar @{ $g->{symbols} }, $g->{start}, (@undef ? "; undefined: @undef" : '');
    }
    0;
}

# ---------------------------------------------------------------- crosscheck against the Pilot
sub pilot {                             # () -> Maybe [java, jar, library]
    my $java = $ENV{JAVA_HOME} ? File::Spec->catfile($ENV{JAVA_HOME}, 'bin', 'java') : undef;
    ($java) = grep { -x } map { File::Spec->catfile($_, 'java'), File::Spec->catfile($_, 'java.exe') } File::Spec->path
        unless $java && -x $java;
    my ($jar) = $ENV{SYSML_JAR} // (map { glob(File::Spec->catfile($_, '*sysml*all.jar')) }
        grep { defined && -d } ($ENV{SYSML_HOME}, $ROOT,
                                File::Spec->catdir($ENV{HOME} // '', qw(miniconda3 share jupyter kernels sysml))));
    my $lib = $ENV{SYSML_LIBRARY} // ($jar ? File::Spec->catdir((File::Spec->splitpath($jar))[1], 'sysml.library') : undef);
    $lib = File::Spec->catdir($ROOT, 'vendor', 'sysml-v2-release', 'sysml.library') if $jar && !($lib && -d $lib);
    $java && $jar && $lib && -d $lib ? [ $java, $jar, $lib ] : undef;
}

sub mutate {                            # (Text, [Token], seed) -> (Text, description) -- pure
    my ($text, $toks, $seed) = @_;
    my $rand = do { my $x = $seed; sub { $x = ($x * 1103515245 + 12345) % 2147483648; $x % $_[0] } };
    my @kinds = ('delete', 'insert', 'swap', 'delete-name');
    my $kind = $kinds[ $rand->(scalar @kinds) ];
    my @pick = $kind eq 'delete'      ? grep { $toks->[$_][1] =~ /^[;{}()\]\[,]$/ } 0 .. $#$toks
             : $kind eq 'delete-name' ? grep { $toks->[$_][0] eq 'name' } 0 .. $#$toks
             : (0 .. $#$toks - 1);
    return ($text, 'none') unless @pick;
    my $i = $pick[ $rand->(scalar @pick) ];
    my ($k, $s, $at) = @{ $toks->[$i] };
    if ($kind eq 'delete' || $kind eq 'delete-name') { return (substr($text, 0, $at) . substr($text, $at + length $s), "$kind '$s'") }
    if ($kind eq 'insert') {
        my $w = (qw(part def ; } { in end then : = ref))[ $rand->(11) ];
        return (substr($text, 0, $at) . "$w " . substr($text, $at), "insert '$w' before '$s'");
    }
    my $n = $toks->[ $i + 1 ];
    (substr($text, 0, $at) . $n->[1] . substr($text, $at + length($s), $n->[2] - $at - length $s) . $s
        . substr($text, $n->[2] + length $n->[1]), "swap '$s' '$n->[1]'");
}

sub one_line {                          # text -> single line for the Pilot REPL (drops // notes)
    my $t = shift;
    $t =~ s{("[^"\n]*")|('(?:[^'\\\n]|\\.)*')|//\*.*?\*/|(/\*.*?\*/)|//[^\n]*}{ $1 // $2 // $3 // '' }gse;   # //* */ notes too
    $t =~ s/\s*\n\s*/ /g;
    $t;
}

sub cmd_crosscheck {
    my ($n, $seed) = (shift // 100, shift // 1);
    my $p = pilot() or do { print "crosscheck: needs Java and the Pilot jar (SYSML_JAR / SYSML_LIBRARY)\n"; return 3 };
    require IPC::Open3;
    my @files = grep { !/\.kerml\z/ } files_under(File::Spec->catdir($ROOT, 'vendor', 'sysml-v2-release', 'examples'));
    my $g = unwrap(SysML::Grammar::load('sysml', $BNF));
    my $scan = SysML::Lexer::scanner($g);
    my @cases = fmap(sub {
        my $k = shift;
        my $f = $files[ ($k * 7919 + $seed) % @files ];
        my $text = unwrap(slurp($f));
        my ($m, $what) = mutate($text, unwrap($scan->($text)), $seed * 100003 + $k);
        +{ file => rel($f), what => $what, text => $m, perl => isOk(checker('sysml')->($m)) ? 'ok' : 'syntax' };
    }, 1 .. $n);
    print "crosscheck: $n mutants; asking the Pilot ...\n";
    my $pid = IPC::Open3::open3(my $in, my $out, undef, $p->[0], '-cp', $p->[1], 'org.omg.sysml.interactive.SysMLInteractive', $p->[2]);
    binmode $in, ':encoding(UTF-8)';
    print {$in} one_line($_->{text}), "\n" for @cases;
    close $in;
    my $buf = '';
    my $last = $n + 1;
    eval {                              # the Pilot can stall on a pathological mutant: stop after a while
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm(60 + 5 * $n);
        while (sysread($out, my $chunk, 65536)) { $buf .= $chunk; last if $buf =~ /(?:^|\n)\s*$last>/ }
        alarm 0;
    };
    print "crosscheck: the Pilot stopped answering; comparing the answers received\n" if $@;
    kill 'KILL', $pid;
    waitpid $pid, 0;
    $buf =~ s/\r//g;
    my %said = $buf =~ /(?:^|\n)\s*(\d+)>(.*?)(?=\n\s*\d+>|\z)/gs;
    my $syntax = qr/mismatched input|no viable alternative|extraneous input|missing \S+ at|token recognition error|required \(\.\.\.\)/;
    my (@diff, @crash);
    my $answered = grep { exists $said{$_ + 1} } 1 .. $n;   # an input is complete once the next prompt appears
    for my $i (1 .. $answered) {
        my $c = $cases[ $i - 1 ];
        my $said = $said{$i} // '';
        $c->{pilot} = $said =~ $syntax ? 'syntax' : $said =~ /Exception/ ? 'crash' : 'ok';
        push @diff, $c if $c->{pilot} ne $c->{perl} && $c->{pilot} ne 'crash';
        push @crash, $c if $c->{pilot} eq 'crash';
    }
    printf "  %-8s %-8s %s\n", 'perl', 'pilot', 'mutant' if @diff;
    printf "  %-8s %-8s %s: %s\n", $_->{perl}, $_->{pilot}, $_->{file}, $_->{what} for @diff;
    my $agree = $answered - @diff;
    my $bad = grep { $_->{perl} eq 'syntax' } @cases[ 0 .. $answered - 1 ];
    printf "  pilot crashed (perl: %s): %s: %s\n", $_->{perl}, $_->{file}, $_->{what} for @crash;
    $agree -= @crash;
    printf "crosscheck: %d/%d agree (%d mutants are syntax errors per Perl)%s%s\n", $agree, $answered - @crash, $bad,
        (@crash ? sprintf('; the Pilot crashed on %d', scalar @crash) : ''),
        ($answered < $n ? sprintf('; the Pilot answered %d of %d', $answered, $n) : '');
    @diff ? 1 : 0;
}

sub usage { print STDERR "usage: perl tools/sysml/sysml.pl check FILE... | corpus [DIR...] | tokens FILE | grammar | crosscheck [N] [SEED]\n"; 2 }

my %CMD = (check => \&cmd_check, corpus => \&cmd_corpus, tokens => \&cmd_tokens, grammar => \&cmd_grammar,
           crosscheck => \&cmd_crosscheck);
my $cmd = shift @ARGV // '';
exit($CMD{$cmd} ? $CMD{$cmd}->(@ARGV) : usage());
