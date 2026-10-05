package SysML::Lexer;
# KerML / SysML v2 lexical structure (KerML specification clause 8.2.2), as a pure
# function from text to tokens:
#
#   tokenize(Text, Grammar) -> Either Error [Token]
#   Token = [kind, text, offset]    kind: name kw sym int exp string comment
#
# White space, single-line notes (// ...) and multi-line notes (//* ... */) are
# dropped; regular comments (/* ... */) are tokens, because the grammar uses them
# (Comment, Documentation). Keywords and symbols come from the grammar's
# RESERVED_KEYWORD and RESERVED_SYMBOL rules, so a new release needs no code change.
use strict;
use warnings;
use Prelude qw(unfoldr NOTHING Ok Err fromList);

sub scanner {                          # Grammar -> (Text -> Either Error [Token])
    my $g = shift;
    my $kw = fromList(map { [ $_, 1 ] } @{ $g->{keywords} });
    my $sym = join '|', map { quotemeta } @{ $g->{symbols} };    # longest first
    my $token = qr{
        \G (?: (?<ws>      [ \t\f\r\n]+ )
             | (?<note>    //\*.*?\*/ | //[^\r\n]* )
             | (?<comment> /\*.*?\*/ )
             | (?<string>  "(?:[^"\\]|\\.)*" )
             | (?<qname>   '(?:[^'\\]|\\.)*' )
             | (?<exp>     \d+[eE][-+]?\d+ )
             | (?<int>     \d+ )
             | (?<name>    [A-Za-z_][A-Za-z0-9_]* )
             | (?<sym>     $sym ) )
    }xs;
    sub {
        my $text = shift;
        my $err;
        my $step = sub {               # offset -> NOTHING | [token-or-undef, offset']
            my $at = shift;
            return NOTHING if $at >= length $text;
            pos($text) = $at;
            if ($text !~ /$token/g) { $err = $at; return NOTHING }
            my ($kind) = grep { defined $+{$_} } qw(ws note comment string qname exp int name sym);
            my $s = $+{$kind};
            my $tok = $kind eq 'ws' || $kind eq 'note' ? undef
                    : $kind eq 'qname' ? [ 'name', $s, $at ]
                    : $kind eq 'name' && $kw->{$s} ? [ 'kw', $s, $at ]
                    : [ $kind, $s, $at ];
            [ $tok, pos($text) ];
        };
        my @tokens = grep { defined } unfoldr($step, 0);
        defined $err ? Err([ $err, 'unexpected character ' . substr($text, $err, 1) ]) : Ok(\@tokens);
    };
}

sub line_col {                         # Text, offset -> (line, column), 1-based
    my ($text, $at) = @_;
    my $before = substr($text, 0, $at);
    my $line = 1 + ($before =~ tr/\n//);
    ($line, $at - rindex($before, "\n"));
}

1;
