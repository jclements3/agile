#!/usr/bin/perl
# sysml-threats.pl : threat-model checks on a SysML v2 model (SecMeta), with a threat table.
# Core Perl 5 only.
#
#   perl sysml-threats.pl [--today YYYY-MM-DD] DIR|FILE...
#
# Checks (the binder's threat-model rules):
#   error    SEC-2 threat completeness: every @Threat has a STRIDE category (one of the six) and
#            a CAPEC id (CAPEC-n)
#   error    SEC-3 mitigation closure: every threat is named by a @Mitigates on a requirement
#            that is satisfied and verified (itself or a requirement group above it)
#   warning  ... unless a current @RiskAcceptance { threat; approver; expires; } on the threat
#            downgrades it; an expired or unsigned acceptance is an error
#   error    @Mitigates naming a threat that does not exist
#   warning  a threat's mitigation = "req" attribute (the status-metrics line form) that no
#            @Mitigates on that requirement backs, or a @Mitigates the attribute does not name
# A threat is an element carrying @Threat { stride; capec; }, or a named metadata usage of Threat,
# one line per threat: metadata t1 : Threat { asset = "..."; mitigation = "req"; stride = "..."; capec = "..."; }
# Prints the threat table, then the diagnostics (GNU format), then a summary line.
# Exit status: 0 no errors, 1 errors, 2 usage error.
use strict; use warnings;
use File::Find; use Getopt::Long;
binmode STDOUT, ':encoding(UTF-8)';

my %O;
GetOptions(\%O, 'today=s') && @ARGV
    or do { print STDERR "usage: perl sysml-threats.pl [--today YYYY-MM-DD] DIR|FILE...\n"; exit 2 };
my $TODAY = $O{today} // do { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] };
if ($TODAY !~ /^\d{4}-\d\d-\d\d$/) { print STDERR "sysml-threats: --today must be YYYY-MM-DD\n"; exit 2 }
my @files;
for my $a (@ARGV) {
    if (-d $a) { find(sub { push @files, $File::Find::name if /\.sysml$/ }, $a) }
    elsif (-f $a) { push @files, $a }
    else { print STDERR "sysml-threats: $a: no such file or directory\n"; exit 2 }
}
@files = sort @files;

my $NAME = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF  = qr/$NAME(?:\s*(?:::|\.)\s*$NAME)*/;
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }
sub sval { my $v = shift; return $1 =~ s/\\(.)/$1/gr if $v =~ /^"((?:[^"\\]|\\.)*)"$/; $v }

# ------------------------------------------------------------------------------------------
# Parse: elements with bodies, metadata usages with their attribute values, satisfy, verify
# ------------------------------------------------------------------------------------------
my (@nodes, @sat, @ver);
for my $f (@files) {
    open my $h, '<:encoding(UTF-8)', $f or die "$f: $!";
    local $/; my $t = <$h>;
    my @stack = ({ kind => 'file', pkg => [] });
    my ($head, $hline, $line) = ('', 1, 1);
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G\n/gc) { $line++; $head .= ' ' }
        elsif ($t =~ m{\G//[^\n]*}gc) { }
        elsif ($t =~ m{\G/\*}gc) {
            my $from = pos($t); my $end = index($t, '*/', $from); $end = length $t if $end < 0;
            my $body = substr($t, $from, $end - $from); pos($t) = $end + 2;
            $line += ($body =~ tr/\n//);
            if ($head =~ /^\s*doc\b/) { $body =~ s/^\s*\*\s?//mg; $body =~ s/\s+/ /g; $body =~ s/^ | $//g;
                my $n = (grep { $_->{node} } reverse @stack)[0]; $n->{node}{doc} //= $body if $n; $head = '' }
            elsif ($head =~ /^\s*comment\b/) { $head = '' }
        }
        elsif ($t =~ /\G("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gc) { my $q = $1; $hline = $line if $head !~ /\S/; $head .= $q; $line += ($q =~ tr/\n//) }
        elsif ($t =~ /\G([{};])/gc) {
            my $c = $1;
            if ($c eq '}') { if (@stack > 1) { my $s = pop @stack; finish($s) } $head = ''; next }
            my $st = statement($head, $f, $hline, \@stack, $c);
            $head = '';
            if ($c eq '{') { push @stack, $st // { kind => 'other', pkg => $stack[-1]{pkg} } }
            elsif ($st && $st->{kind} eq 'meta') { finish($st) }
        }
        elsif ($t =~ m{\G([^{};"'/\n]+|/)}gc) { my $x = $1; $hline = $line if $head !~ /\S/ && $x =~ /\S/; $head .= $x }
    }
}

sub finish {            # a metadata usage is complete: attach it to its element
    my $s = shift;
    return unless $s->{kind} eq 'meta' && $s->{target};
    push @{$s->{target}{meta}{$s->{name}}}, { %{$s->{attrs}}, file => $s->{file}, line => $s->{line} };
}
sub statement {
    my ($s, $f, $line, $stack, $c) = @_;
    my $top = $stack->[-1];
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    return undef if $s eq '';
    my $pkg = $top->{pkg};
    my ($owner) = map { $_->{node} } grep { $_->{node} } reverse @$stack;
    if ($top->{kind} eq 'meta') {                                   # attribute = value inside @Meta { }
        $top->{attrs}{$1} = sval($2) if $s =~ /^(?::>>\s*)?(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\S+)/;
        return undef;
    }
    if ($s =~ /^metadata\s+($NAME)\s*(?::|\bdefined\s+by\b)\s*(?:\w+::)*Threat$/) {    # a named threat usage: the threat itself
        my $n = unq($1);
        my $node = { kind => 'metadata', name => $n, id => '', isreq => 0, pkg => $pkg, path => [$n], file => $f, line => $line, meta => {} };
        push @nodes, $node;
        return { kind => 'meta', name => 'Threat', target => $node, attrs => {}, pkg => $pkg, file => $f, line => $line };
    }
    if ($s =~ /^@\s*(?:\w+::)*(\w+)\s*$/ || $s =~ /^metadata\s+(?:\w+::)*(\w+)\s*$/) {
        return { kind => 'meta', name => $1, target => $owner, attrs => {}, pkg => $pkg, file => $f, line => $line };
    }
    my @hash;
    $s =~ s/^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*//;
    push @hash, $1 while $s =~ s/^#\s*(?:\w+::)*(\w+)\s*//;
    if ($s =~ /^(?:standard\s+)?(?:library\s+)?package\s+($NAME)/) { return { kind => 'package', pkg => [@$pkg, unq($1)] } }
    if ($s =~ /^satisfy\s+(?:requirement\s+)?($REF)\s+by\s+($REF)/) { push @sat, { ref => [segs($1)], file => $f, line => $line }; return undef }
    if ($s =~ /^verify\s+(?:requirement\s+)?($REF)/) { push @ver, { ref => [segs($1)], file => $f, line => $line }; return undef }
    if ($s =~ /^(\w+(?:\s+def)?)\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAME)/ && $1 !~ /^(?:import|alias|dependency|doc|comment|subject|objective|return|in|out|inout)$/) {
        my ($kw, $id, $n) = ($1, $2 // '', unq($3));
        my $isreq = $kw eq 'requirement';
        my @path = ((map { $_->{node}{name} } grep { $_->{node} && $_->{node}{isreq} } @$stack), $n);
        my $node = { kind => $kw, name => $n, id => $id, isreq => $isreq, pkg => $pkg, path => $isreq ? \@path : [$n],
                     up => ($owner && $owner->{isreq} && $isreq ? $owner : undef), file => $f, line => $line, meta => {} };
        push @{$node->{meta}{$_}}, { file => $f, line => $line } for @hash;
        push @nodes, $node;
        return $c eq '{' ? { kind => 'node', node => $node, pkg => $pkg } : undef;
    }
    return undef;
}

# ------------------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------------------
my ($NERR, $NWARN, @DIAG) = (0, 0);
sub diag { my ($f, $l, $sev, $m) = @_; push @DIAG, [$f, $l, scalar @DIAG, "$f:$l: $sev: $m"]; $sev eq 'error' ? $NERR++ : $NWARN++ }
my %STRIDE = map { lc($_) => $_ } ('Spoofing', 'Tampering', 'Repudiation', 'Information disclosure', 'Denial of service', 'Elevation of privilege');

my @reqs = grep { $_->{isreq} && $_->{kind} eq 'requirement' } @nodes;
sub hit { my ($r, $sg) = @_; my @full = (@{$r->{pkg}}, @{$r->{path}}); @full >= @$sg && join("\0", @full[$#full - $#$sg .. $#full]) eq join("\0", @$sg) }
for my $s (@sat) { $_->{sat_direct} = 1 for grep { hit($_, $s->{ref}) } @reqs }
for my $v (@ver) { $_->{ver_direct} = 1 for grep { hit($_, $v->{ref}) } @reqs }
for my $r (@reqs) { for (my $o = $r; $o; $o = $o->{up}) { $r->{sat} ||= $o->{sat_direct}; $r->{ver} ||= $o->{ver_direct} } }

my @threats = grep { $_->{meta}{Threat} } @nodes;
my %tbyname; push @{$tbyname{$_->{name}}}, $_ for @threats;
my %mit;                # threat -> [requirements]
my $nmit = 0;
for my $r (@reqs) {
    for my $m (@{$r->{meta}{Mitigates} // []}) {
        $nmit++;
        my $tn = $m->{threat};
        if (!defined $tn || $tn eq '') { diag($m->{file}, $m->{line}, 'error', "\@Mitigates on requirement '" . ($r->{id} || $r->{name}) . "' names no threat"); next }
        my @t = @{$tbyname{(split /::|\./, $tn)[-1]} // []};
        if (!@t) { diag($m->{file}, $m->{line}, 'error', "\@Mitigates on requirement '" . ($r->{id} || $r->{name}) . "' names unknown threat '$tn'"); next }
        push @{$mit{$_}}, $r for @t;
    }
}
my (@rows, $nacc);
$nacc = 0;
for my $t (@threats) {
    my $m = $t->{meta}{Threat}[0];
    my ($stride, $capec) = ($m->{stride} // '', $m->{capec} // '');
    my @bad;
    if ($stride eq '') { push @bad, 'no STRIDE category' }
    elsif (!$STRIDE{lc $stride}) { push @bad, "STRIDE category '$stride' is not one of the six" }
    if ($capec eq '') { push @bad, 'no CAPEC id' }
    elsif ($capec !~ /^CAPEC-\d+$/) { push @bad, "CAPEC id '$capec' is not CAPEC-n" }
    diag($m->{file}, $m->{line}, 'error', "threat '$t->{name}': $_") for @bad;
    my @rq = @{$mit{$t} // []};
    my @good = grep { $_->{sat} && $_->{ver} } @rq;
    my $status;
    if (@good) { $status = 'mitigated' }
    else {
        my $why = !@rq ? 'is not mitigated by any requirement'
                : 'is mitigated only by requirements that are not ' . join(' and ', (grep { !$_->{sat} } @rq) ? 'satisfied' : (), (grep { !$_->{ver} } @rq) ? 'verified' : ())
                  . ' (' . join(', ', map { ($_->{id} || $_->{name}) . ':' . ($_->{sat} ? '' : ' not satisfied') . ($_->{ver} ? '' : ' not verified') } @rq) . ')';
        my @acc = @{$t->{meta}{RiskAcceptance} // []};
        my ($cur) = grep { ($_->{approver} // '') ne '' && ($_->{expires} // '') =~ /^\d{4}-\d\d-\d\d$/ && $_->{expires} ge $TODAY } @acc;
        if ($cur) {
            $nacc++;
            $status = "accepted until $cur->{expires} ($cur->{approver})";
            diag($t->{file}, $t->{line}, 'warning', "threat '$t->{name}' $why; accepted by risk acceptance (approver: $cur->{approver}, expires $cur->{expires})");
        } else {
            $status = !@rq ? 'UNMITIGATED' : 'NOT CLOSED';
            for my $a (@acc) {
                my $p = ($a->{approver} // '') eq '' ? 'has no approver' : ($a->{expires} // '') !~ /^\d{4}-\d\d-\d\d$/ ? "has no expiry date (YYYY-MM-DD)" : "expired on $a->{expires}";
                diag($a->{file}, $a->{line}, 'error', "risk acceptance on threat '$t->{name}' $p");
            }
            diag($t->{file}, $t->{line}, 'error', "threat '$t->{name}' $why");
        }
    }
    if (defined $m->{mitigation}) {     # the status-metrics attribute and the @Mitigates links must agree
        my $attr = $m->{mitigation};
        my %by = map { ($_->{name} => 1, ($_->{id} ne '' ? ($_->{id} => 1) : ())) } @rq;
        diag($m->{file}, $m->{line}, 'warning', "threat '$t->{name}': mitigation = \"$attr\" but no \@Mitigates on '$attr' names it")
            if $attr ne '' && !$by{(split /::|\./, $attr)[-1]};
        diag($m->{file}, $m->{line}, 'warning', "threat '$t->{name}': \@Mitigates on " . join(', ', map { $_->{id} || $_->{name} } @rq) . " but mitigation = \"\"")
            if $attr eq '' && @rq;
    }
    $status = "INCOMPLETE; $status" if @bad;
    push @rows, [$t->{name}, $STRIDE{lc $stride} // ($stride eq '' ? '-' : "?$stride"), $capec eq '' ? '-' : $capec,
                 @rq ? join(', ', map { ($_->{id} || $_->{name}) . ' (' . ($_->{sat} ? 'S' : '-') . ($_->{ver} ? 'V' : '-') . ')' } @rq) : '-', $status];
}

# ------------------------------------------------------------------------------------------
# Report
# ------------------------------------------------------------------------------------------
my @hdr = ('threat', 'STRIDE', 'CAPEC', 'mitigated by (S satisfied, V verified)', 'status');
my @w = map { length $hdr[$_] } 0 .. $#hdr;
for my $r (@rows) { for my $i (0 .. $#$r - 1) { $w[$i] = length $r->[$i] if length $r->[$i] > $w[$i] } }
my $fmt = join('  ', map { "%-${_}s" } @w[0 .. $#w - 1]) . "  %s\n";
if (@rows) {
    printf $fmt, @hdr;
    printf $fmt, map { '-' x $_ } @w[0 .. $#w - 1], length $hdr[-1];
    printf $fmt, @$_ for @rows;
    print "\n";
}
print map { "$_->[3]\n" } sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @DIAG;
printf "%d file(s): %d error(s), %d warning(s), %d threat(s), %d mitigation(s), %d risk acceptance(s) in force\n",
    scalar @files, $NERR, $NWARN, scalar @threats, $nmit, $nacc;
exit($NERR ? 1 : 0);
