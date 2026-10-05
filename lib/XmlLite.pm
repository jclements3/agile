package XmlLite;
# A small XML reader in core Perl (no XML::Parser, which is not core): a streaming tokenizer with SAX-style
# callbacks, and a tree builder on top of it. Written for the model-port tools (Xmi.pm, Reqif.pm), which read
# Cameo/MagicDraw XMI and DOORS ReqIF exports -- files that can run to hundreds of megabytes.
#
#   my $root = XmlLite::parse_file($path);            # tree: { n => 'uml:Model', l => 'Model', p => 'uml', u => URI,
#                                                      #         a => { attr => value }, k => [ child node | text ], line => N }
#   my $root = XmlLite::parse_string($xml);
#   XmlLite::stream($fh, start => sub { my ($name, $attrs, $line) = @_ }, end => sub { my ($name) = @_ },
#                         text => sub { my ($text) = @_ });
#
# What it handles: the XML declaration (UTF-8, or a single-byte encoding such as ISO-8859-1/windows-1252 which is
# recoded to UTF-8), a UTF-8 BOM (stripped) or a UTF-16 BOM (the file is recoded first), CRLF and lone CR (folded to
# LF as XML requires), comments, processing instructions, CDATA sections, a DOCTYPE with an internal subset (its
# <!ENTITY name "value"> declarations are honoured; external DTDs are not fetched), the five predefined entities and
# numeric character references, attribute-value normalisation (literal newlines/tabs become spaces, &#10; stays a
# newline), and namespaces (each element carries its resolved URI in u; undeclared prefixes, as in hand-written
# XMI, are kept as they are). Input is read in 1 MB chunks, so a large file is never held twice.
#
# Strings stay as UTF-8 bytes throughout (character references are encoded to UTF-8), so the tools write what they
# read without a decode/encode round trip, on any Perl.
#
# Text: whitespace-only text between elements is dropped (XMI and ReqIF are element-only) unless keep_ws => sub
# { $node } says the element holds mixed content (ReqIF's XHTML). Non-blank text is always kept, as plain strings in
# the k list, in document order with the child elements.
use strict;
use warnings;

our $CHUNK = 1 << 20;
my %PREDEF = (lt => '<', gt => '>', amp => '&', quot => '"', apos => "'");

sub _utf8 {                                   # code point -> UTF-8 bytes (no Encode needed)
    my $c = shift;
    return chr($c) if $c < 0x80;
    return pack('C*', 0xC0 | ($c >> 6), 0x80 | ($c & 0x3F)) if $c < 0x800;
    return pack('C*', 0xE0 | ($c >> 12), 0x80 | (($c >> 6) & 0x3F), 0x80 | ($c & 0x3F)) if $c < 0x10000;
    return pack('C*', 0xF0 | ($c >> 18), 0x80 | (($c >> 12) & 0x3F), 0x80 | (($c >> 6) & 0x3F), 0x80 | ($c & 0x3F));
}

sub decode_entities {                         # decode_entities($s, \%internal) -> $s with references replaced; unknown ones kept
    my ($s, $ent) = @_;
    return $s unless defined $s && index($s, '&') >= 0;
    $s =~ s{&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z_][\w.\-]*);}{
        my $r = $1;
        $r =~ /^#[xX](.+)/ ? _utf8(hex $1)
      : $r =~ /^#(\d+)/    ? _utf8($1)
      : exists $PREDEF{$r} ? $PREDEF{$r}
      : ($ent && exists $ent->{$r}) ? $ent->{$r}
      : "&$r;"
    }ge;
    return $s;
}

sub _recode {                                 # bytes in $enc -> UTF-8 bytes
    my ($bytes, $enc) = @_;
    require Encode;
    return Encode::encode('UTF-8', Encode::decode($enc, $bytes));
}

# stream($fh_or_path, start => cb, end => cb, text => cb) -- the tokenizer. Dies with "file:line: message" on
# malformed markup (an unterminated tag, a mismatched end tag, a missing end tag at EOF).
sub stream {
    my ($in, %cb) = @_;
    my ($fh, $label);
    if (ref $in) { ($fh, $label) = ($in, 'input') }
    else { open $fh, '<', $in or die "$in: $!\n"; $label = $in }
    binmode $fh;
    my ($buf, $pos, $eof, $line) = ('', 0, 0, 1);
    my ($enc, %ent, @open);
    my $fill = sub {
        return 0 if $eof;
        my $chunk;
        my $n = read($fh, $chunk, $CHUNK);
        if (!$n) { $eof = 1; return 0 }
        $chunk = _recode($chunk, $enc) if $enc;
        $buf .= $chunk;
        return $n;
    };
    $fill->();
    # BOMs: UTF-8 stripped; UTF-16 means the whole file is recoded up front (rare in these exports)
    if ($buf =~ /^\xEF\xBB\xBF/) { $pos = 3 }
    elsif ($buf =~ /^(\xFF\xFE|\xFE\xFF)/) {
        my $le = $1 eq "\xFF\xFE";
        1 while $fill->();
        $buf = _recode(substr($buf, 2), $le ? 'UTF-16LE' : 'UTF-16BE');
        $pos = 0;
    }
    my $nl = sub { $_[0] =~ s/\r\n?/\n/g; $_[0] };
    my $err = sub { die "$label:$line: $_[0]\n" };
    my $text = '';
    my $flush = sub {
        return if $text eq '';
        my $t = $nl->($text); $text = '';
        $cb{text}->(decode_entities($t, \%ent)) if $cb{text};
    };
    my $need = sub {                          # need($terminator) -> index of it at/after $pos, filling as needed
        my ($term, $from) = @_;
        while (1) {
            my $i = index($buf, $term, $from);
            return $i if $i >= 0;
            $from = length($buf) - length($term) + 1; $from = $pos if $from < $pos;
            return -1 unless $fill->();
        }
    };
    my $consume = sub {                       # consume($to): advance past $to, counting lines
        my $to = shift;
        $line += (substr($buf, $pos, $to - $pos) =~ tr/\n//);
        $pos = $to;
    };
    while (1) {
        if ($pos > $CHUNK) { substr($buf, 0, $pos, ''); $pos = 0 }   # drop what is consumed (only here: no index is live)
        my $lt = index($buf, '<', $pos);
        if ($lt < 0) {
            $text .= substr($buf, $pos); $consume->(length $buf);
            next if $fill->();
            last;
        }
        if ($lt > $pos) { $text .= substr($buf, $pos, $lt - $pos); $consume->($lt) }
        # make sure enough is buffered to tell the construct apart
        $fill->() while length($buf) - $pos < 10 && !$eof;
        if (substr($buf, $pos, 4) eq '<!--') {
            my $e = $need->('-->', $pos + 4); $err->('unterminated comment') if $e < 0;
            $consume->($e + 3); next;
        }
        if (substr($buf, $pos, 9) eq '<![CDATA[') {
            my $e = $need->(']]>', $pos + 9); $err->('unterminated CDATA section') if $e < 0;
            my $c = substr($buf, $pos + 9, $e - $pos - 9);
            $consume->($e + 3);
            $flush->();                       # entities in the text before it are decoded; CDATA is literal
            $cb{text}->($nl->($c)) if $cb{text} && $c ne '';
            next;
        }
        if (substr($buf, $pos, 2) eq '<?') {
            my $e = $need->('?>', $pos + 2); $err->('unterminated processing instruction') if $e < 0;
            my $pi = substr($buf, $pos, $e + 2 - $pos);
            $consume->($e + 2);
            if ($pi =~ /^<\?xml\s.*?encoding\s*=\s*["']([^"']+)["']/s) {
                my $e2 = lc $1;
                if ($e2 !~ /^utf-?8$/ && $e2 !~ /^utf-?16/) {   # single-byte: recode the rest of the buffer and every later chunk
                    $enc = $e2;
                    my $rest = substr($buf, $pos); substr($buf, $pos) = _recode($rest, $enc);
                }
            }
            next;
        }
        if (substr($buf, $pos, 9) =~ /^<!DOCTYPE/i) {
            # an internal subset [...] may contain '>' inside declarations; find the matching ']' then '>'
            my $lb = $need->('[', $pos); my $gt = $need->('>', $pos);
            my $end;
            if ($lb >= 0 && $lb < $gt) {
                my $rb = $need->(']', $lb); $err->('unterminated DOCTYPE') if $rb < 0;
                $end = $need->('>', $rb);
                my $subset = substr($buf, $lb + 1, $rb - $lb - 1);
                while ($subset =~ /<!ENTITY\s+([A-Za-z_][\w.\-]*)\s+(?:"([^"]*)"|'([^']*)')\s*>/g) {
                    $ent{$1} = decode_entities(defined $2 ? $2 : $3);
                }
            } else { $end = $gt }
            $err->('unterminated DOCTYPE') if $end < 0;
            $consume->($end + 1); next;
        }
        if (substr($buf, $pos, 2) eq '</') {
            my $e = $need->('>', $pos); $err->('unterminated end tag') if $e < 0;
            my $name = substr($buf, $pos + 2, $e - $pos - 2); $name =~ s/\s+$//;
            $flush->();
            my $top = pop @open;
            $err->(defined $top ? "end tag </$name> does not match <$top>" : "end tag </$name> with nothing open") if !defined $top || $top ne $name;
            $consume->($e + 1);
            $cb{end}->($name) if $cb{end};
            next;
        }
        # a start tag: the first '>' that is not inside a quoted attribute value
        my $end;
        my $from = $pos + 1;
        while (1) {
            my $e = $need->('>', $from);
            last if $e < 0;
            my $tag = substr($buf, $pos + 1, $e - $pos - 1);
            last if index($tag, '<') >= 0 && $tag !~ /^(?>(?:[^"'<]+|"[^"]*"|'[^']*')*)\z/;   # a '<' outside quotes: malformed
            if ($tag !~ /["']/ || $tag =~ /^(?>(?:[^"']+|"[^"]*"|'[^']*')*)\z/) { $end = $e; last }
            $from = $e + 1;                   # that '>' sat inside a quoted value
        }
        $err->('unterminated start tag') unless defined $end;
        my $tag = substr($buf, $pos + 1, $end - $pos - 1);
        my $startline = $line;
        $consume->($end + 1);
        my $empty = $tag =~ s{/\s*$}{};
        $tag =~ /^([^\s]+)\s*(.*)$/s or $err->('empty tag');
        my ($name, $rest) = ($1, $2);
        my %a; my @order;
        while ($rest =~ /\G\s*([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/gc) {
            my ($an, $v) = ($1, defined $2 ? $2 : $3);
            $v =~ s/\r\n?/\n/g; $v =~ s/[\n\t]/ /g;             # attribute-value normalisation; &#10; survives as a newline below
            $a{$an} = decode_entities($v, \%ent);
            push @order, $an;
        }
        $rest =~ /\G\s*$/gc or $err->("malformed attributes in <$name>");
        $flush->();
        $cb{start}->($name, \%a, $startline, \@order) if $cb{start};
        if ($empty) { $cb{end}->($name) if $cb{end} } else { push @open, $name }
    }
    $flush->();
    $err->('missing end tag for <' . $open[-1] . '>') if @open;
    close $fh unless ref $in;
    return 1;
}

# parse_file($path, keep_ws => sub { $node }) -> the root element as a tree (see the header). Namespace prefixes
# are resolved per element: u is the URI bound to the element's prefix (or the default namespace), '' if none.
sub parse_file { my ($in, %o) = @_; return _tree($in, %o) }

sub parse_string {
    my ($s, %o) = @_;
    open my $fh, '<', \$s or die "parse_string: $!\n";
    return _tree($fh, %o);
}

sub _tree {
    my ($in, %o) = @_;
    my ($root, @stack, @ns);
    my $keep = $o{keep_ws};
    stream($in,
        start => sub {
            my ($name, $a, $line) = @_;
            my %scope = @ns ? %{ $ns[-1] } : ();
            for my $k (keys %$a) {
                if ($k eq 'xmlns') { $scope{''} = $a->{$k} } elsif ($k =~ /^xmlns:(.+)/) { $scope{$1} = $a->{$k} }
            }
            push @ns, \%scope;
            my ($p, $l) = $name =~ /^([^:]+):(.+)$/ ? ($1, $2) : ('', $name);
            my $node = { n => $name, l => $l, p => $p, u => (defined $scope{$p} ? $scope{$p} : ''), a => $a, k => [], line => $line };
            $node->{mixed} = 1 if (@stack && $stack[-1]{mixed}) || ($keep && $keep->($node));
            if (@stack) { push @{ $stack[-1]{k} }, $node } else { $root = $node }
            push @stack, $node;
        },
        end => sub { pop @stack; pop @ns },
        text => sub {
            my ($t) = @_;
            return unless @stack;
            return if $t !~ /\S/ && !$stack[-1]{mixed};
            my $k = $stack[-1]{k};
            if (@$k && !ref $k->[-1]) { $k->[-1] .= $t } else { push @$k, $t }
        },
    );
    die "no root element\n" unless $root;
    return $root;
}

# helpers over the tree
sub kids  { my ($n, $local) = @_; return grep { ref $_ && (!defined $local || $_->{l} eq $local) } @{ $n->{k} } }
sub kid   { my ($n, $local) = @_; for (@{ $n->{k} }) { return $_ if ref $_ && $_->{l} eq $local } return undef }
sub text  {                                  # all text under a node, in order (elements' text included)
    my ($n) = @_;
    return join '', map { ref $_ ? text($_) : $_ } @{ $n->{k} };
}
sub attr  {                                  # attr($node, 'id') -> value of 'id' or of any prefixed 'x:id'
    my ($n, $name) = @_;
    return $n->{a}{$name} if exists $n->{a}{$name};
    for my $k (keys %{ $n->{a} }) { return $n->{a}{$k} if $k =~ /:\Q$name\E$/ }
    return undef;
}

1;
