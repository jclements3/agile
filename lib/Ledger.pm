package Ledger;
# Plain-text double-entry accounting on the ledger-cli file format.
# Core Perl only; uses Prelude.pm for the list plumbing.
use strict;
use warnings;
use Prelude qw(sorted nub sum classify fromListWith fmap filter maximum);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Ledger: unknown function '$n'\n" unless defined &{"Ledger::$n"};
        *{"${caller}::$n"} = \&{"Ledger::$n"};
    }
}

# ---------------------------------------------------------------- amounts  {commodity => number}
my %PREC;                                     # commodity => decimals seen
my $EPS = 1e-9;

sub parse_amount {                            # "$-1,234.56"  "-12.5 USD"  '10 "big thing"'  -> hashref or undef
    my $s = shift;
    return undef unless defined $s && $s =~ /\S/;
    $s =~ s/^\s+|\s+$//g;
    return undef
      unless $s =~ /^(-)?\s*([^\s\d\-+.,"]+)?\s*(-)?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*([A-Za-z]\w*|"[^"]*")?$/;
    my ($neg, $sym, $neg2, $num, $code) = ($1, $2, $3, $4, $5);
    my $c = defined $sym ? $sym : defined $code ? $code : '';
    $c =~ s/^"|"$//g;
    (my $n = $num) =~ s/,//g;
    my $dec = $n =~ /\.(\d+)/ ? length $1 : 0;
    $PREC{$c} = $dec if !defined $PREC{$c} || $dec > $PREC{$c};
    $n += 0;
    $n = -$n if $neg || $neg2;
    return { $c => $n };
}
sub amt_add   { my ($x, $y) = @_; my %r = %$x; $r{$_} += $y->{$_} for keys %$y; \%r }
sub amt_neg   { my $x = shift; +{ map { ($_ => -$x->{$_}) } keys %$x } }
sub amt_sub   { amt_add($_[0], amt_neg($_[1])) }
sub amt_scale { my ($x, $k) = @_; +{ map { ($_ => $x->{$_} * $k) } keys %$x } }
sub amt_zero  { my $x = shift; for (values %$x) { return 0 if abs($_) > _tol() } 1 }
sub _tol      { my $p = 2; for (values %PREC) { $p = $_ if $_ > $p } 0.5 * 10**-$p }
sub _commas   { my $s = shift; 1 while $s =~ s/^(-?\d+)(\d{3})/$1,$2/; $s }

sub format_amount {                           # {'$'=>-42.17} -> "$-42.17"; {USD=>5}->"5.00 USD"; {}->"0"
    my $a = shift;
    my @parts;
    for my $c (sorted(keys %$a)) {
        my $v = $a->{$c};
        next if abs($v) < _tol();
        my $p = $PREC{$c} // 2;
        my $n = _commas(sprintf("%.${p}f", $v));
        push @parts, $c eq '' ? $n : $c =~ /^[A-Za-z]/ ? "$n $c" : ($c =~ /\s/ ? "$n \"$c\"" : "$c$n");
    }
    @parts ? join(', ', @parts) : '0';
}

# ---------------------------------------------------------------- dates
sub norm_date {                               # 2026/9/3 -> 2026-09-03 ; undef if not a date
    my $d = shift;
    return undef unless defined $d && $d =~ m{^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$};
    return undef if $2 < 1 || $2 > 12 || $3 < 1 || $3 > 31;
    sprintf '%04d-%02d-%02d', $1, $2, $3;
}
sub _add_months { my ($y, $m, $k) = @_; $m += $k - 1; ($y + int($m / 12), $m % 12 + 1) }
sub period_range {                            # '2026' | '2026-09' | '2026-Q3' -> (begin, end)  end exclusive
    my $p = shift;
    if ($p =~ /^(\d{4})$/)                { return ("$1-01-01", sprintf('%04d-01-01', $1 + 1)) }
    if ($p =~ /^(\d{4})[-\/]?(\d{1,2})$/) {
        my ($y, $m) = ($1, $2);
        my ($y2, $m2) = _add_months($y, $m, 1);
        return (sprintf('%04d-%02d-01', $y, $m), sprintf('%04d-%02d-01', $y2, $m2));
    }
    if ($p =~ /^(\d{4})[-\/]?[Qq]([1-4])$/) {
        my ($y, $q) = ($1, $2);
        my $m = ($q - 1) * 3 + 1;
        my ($y2, $m2) = _add_months($y, $m, 3);
        return (sprintf('%04d-%02d-01', $y, $m), sprintf('%04d-%02d-01', $y2, $m2));
    }
    die "bad period '$p' (want YYYY, YYYY-MM or YYYY-Qn)\n";
}
sub months_between {                          # whole months from begin to end (exclusive), min 1
    my ($b, $e) = @_;
    my ($y1, $m1, $d1) = split /-/, $b;
    my ($y2, $m2, $d2) = split /-/, $e;
    my $n = ($y2 * 12 + $m2) - ($y1 * 12 + $m1);
    $n++ if $d2 > $d1;
    $n < 1 ? 1 : $n;
}
sub this_month { my @t = localtime; sprintf '%04d-%02d', $t[5] + 1900, $t[4] + 1 }
sub today      { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub next_month { my ($y, $m) = $_[0] =~ /^(\d{4})-(\d{2})/; sprintf '%04d-%02d-01', _add_months($y, $m, 1) }
sub month_starts {                            # ('2026-10-05', '2027-01-01') -> ('2026-10-01', '2026-11-01', '2026-12-01')
    my ($b, $e) = @_;
    my @out;
    for (my $s = substr($b, 0, 8) . '01'; $s lt $e; $s = next_month($s)) { push @out, $s }
    @out;
}
sub day_number { my ($y, $m, $d) = split /-/, shift; require Time::Local; int(Time::Local::timegm(0, 0, 12, $d, $m - 1, $y) / 86400) }
sub add_days { my ($d, $n) = @_; my @t = gmtime((day_number($d) + $n) * 86400 + 43200); sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub month_fraction {                          # the share of the month starting $ms that lies inside [b, e): 0..1
    my ($ms, $b, $e) = @_;
    my $me = next_month($ms);
    my $lo = defined $b && $b gt $ms ? $b : $ms;
    my $hi = defined $e && $e lt $me ? $e : $me;
    return 0 if $lo ge $hi;
    (day_number($hi) - day_number($lo)) / (day_number($me) - day_number($ms));
}
sub periodic_window {                         # 'Monthly from 2026-10-01 to 2027-01-01' -> (kind, from, to); from/to undef when absent
    my $p = shift;
    my ($kind) = $p =~ /^(\w+)/;
    my ($from) = $p =~ /\bfrom\s+(\d[\d\/.-]*)/i;
    my ($to)   = $p =~ /\b(?:to|until)\s+(\d[\d\/.-]*)/i;
    (lc($kind // ''), norm_date($from), norm_date($to));
}
sub plan_months {                             # months of a ~ entry that fall in [beg, end): whole months as before when the
    my ($period, $beg, $end, $whole) = @_;    # entry has no from/to; prorated by day inside its window when it does
    my (undef, $from, $to) = periodic_window($period);
    return $whole // months_between($beg, $end) unless $from || $to;
    my $lo = !$from || $beg gt $from ? $beg : $from;
    my $hi = !$to   || $end lt $to   ? $end : $to;
    return 0 if $lo ge $hi;
    sum(0, map { month_fraction($_, $lo, $hi) } month_starts($lo, $hi));
}

# ---------------------------------------------------------------- parsing
# journal = { txns => [...], periodic => [...], prices => [...], errors => [...] }
# txn     = { date, status, payee, comment, line, file, postings => [ posting ] }
# posting = { account, amount => {c=>n} | undef, cost => {c=>n} | undef, virtual => 0|'balanced'|'unbalanced', comment, line }

sub decode_text {                             # bytes -> characters: a UTF-8 BOM dropped; UTF-8, or Windows-1252 when the bytes are not valid UTF-8 (Notepad, Excel)
    my $b = shift // '';
    return $b if utf8::is_utf8($b);
    $b =~ s/^\xEF\xBB\xBF//;
    require Encode;
    my $copy = $b;
    my $t = eval { Encode::decode('UTF-8', $copy, Encode::FB_CROAK()) };
    defined $t ? $t : Encode::decode('cp1252', $b);
}
sub read_text {                               # read_text($file) -> the file as characters (decode_text), or undef if it cannot be opened
    my $file = shift;
    open my $fh, '<:raw', $file or return undef;
    local $/;
    my $b = <$fh>;
    close $fh;
    decode_text($b // '');
}
sub read_journal {
    my ($file, %opt) = @_;
    my $text = read_text($file);
    die "cannot open $file: $!\n" unless defined $text;
    parse_journal($text, $file, %opt);
}

sub parse_journal {
    my ($text, $file, %opt) = @_;
    $file //= '(string)';
    my $j = { txns => [], periodic => [], prices => [], errors => [] };
    _parse_into($j, $text, $file);
    _balance_all($j);
    die join('', map { "$_\n" } @{ $j->{errors} }) if @{ $j->{errors} } && !$opt{lenient};
    $j;
}

sub _parse_into {
    my ($j, $text, $file) = @_;
    my @lines = split /\r?\n/, $text;
    my $i = 0;
    my $err = sub { push @{ $j->{errors} }, "$file:$_[0]: $_[1]" };
    while ($i < @lines) {
        my $ln   = $i + 1;
        my $line = $lines[ $i++ ];
        next if $line =~ /^\s*$/ || $line =~ /^[;#%|*]/;
        if ($line =~ /^\s/) { $err->($ln, "unexpected indented line"); next }

        # gather the indented block that follows
        my @block;
        while ($i < @lines && $lines[$i] =~ /^\s+\S/) { push @block, [ $i + 1, $lines[$i] ]; $i++ }

        if ($line =~ /^(\d[\d\/.-]*)(?:=(\d[\d\/.-]*))?\s+(?:([*!])\s+)?(.*?)\s*(?:;(.*))?$/) {
            my ($d, $status, $payee, $cmt) = ($1, $3, $4, $5);
            my $date = norm_date($d);
            if (!$date) { $err->($ln, "bad date '$d'"); next }
            my $t = { date => $date, status => $status // '', payee => $payee, comment => _trim($cmt), line => $ln, file => $file, postings => [] };
            _parse_postings($t, \@block, $err);
            push @{ $j->{txns} }, $t;
        }
        elsif ($line =~ /^~\s*(.*?)\s*$/) {
            my $t = { period => $1, line => $ln, file => $file, postings => [] };
            _parse_postings($t, \@block, $err);
            push @{ $j->{periodic} }, $t;
        }
        elsif ($line =~ /^P\s+(\S+)\s+(?:\d\d:\d\d(?::\d\d)?\s+)?(\S+)\s+(.*)$/) {
            my $amt = parse_amount($3);
            push @{ $j->{prices} }, { date => norm_date($1) // $1, commodity => $2, price => $amt } if $amt;
        }
        elsif ($line =~ /^!?include\s+(.+?)\s*$/) {
            my $inc = $1;
            (my $dir = $file) =~ s{[^/\\]*$}{};
            $inc = "$dir$inc" if $dir ne '' && $inc !~ m{^(/|[A-Za-z]:)};
            if (defined(my $t = read_text($inc))) { _parse_into($j, $t, $inc) }
            else { $err->($ln, "cannot include '$inc': $!") }
        }
        elsif ($line =~ /^comment\b/) {
            $i++ while $i < @lines && $lines[$i] !~ /^end comment\b/;
            $i++;
        }
        elsif ($line =~ /^=/ || $line =~ /^(?:account|commodity|payee|tag|year|Y|apply|end|bucket|A|N|D|C|alias|define|assert|check)\b/) {
            next;                             # recognised, ignored (block already consumed)
        }
        else { $err->($ln, "unrecognised line: $line") }
    }
}
sub _trim { my $s = shift; return '' unless defined $s; $s =~ s/^\s+|\s+$//g; $s }

sub _parse_postings {
    my ($t, $block, $err) = @_;
    for my $b (@$block) {
        my ($ln, $raw) = @$b;
        (my $body = $raw) =~ s/^\s+//;
        my $cmt = '';
        if ($body =~ s/\s*;(.*)$//) { $cmt = _trim($1) }
        next if $body eq '';                  # comment-only line inside a transaction
        my ($acct, $rest) = split /(?:\s{2,}|\t)\s*/, $body, 2;
        my $virtual = 0;
        if    ($acct =~ /^\((.*)\)$/) { $acct = $1; $virtual = 'unbalanced' }
        elsif ($acct =~ /^\[(.*)\]$/) { $acct = $1; $virtual = 'balanced' }
        $acct = _trim($acct);
        my ($amount, $cost);
        if (defined $rest && $rest =~ /\S/) {
            $rest =~ s/\s*=.*$//;             # balance assertion: ignored
            my ($amt_s, $at, $price_s) = $rest =~ /^(.*?)\s*(?:(@@?)\s*(.*))?$/;
            $amount = parse_amount($amt_s);
            if (!$amount) { $err->($ln, "bad amount '$amt_s'"); next }
            if ($at) {
                my $p = parse_amount($price_s);
                if (!$p) { $err->($ln, "bad price '$price_s'"); next }
                my ($qc) = keys %$amount;
                my ($pc) = keys %$p;
                $cost = { $pc => $at eq '@' ? $amount->{$qc} * $p->{$pc} : ($amount->{$qc} < 0 ? -1 : 1) * $p->{$pc} };
            }
        }
        push @{ $t->{postings} }, { account => $acct, amount => $amount, cost => $cost, virtual => $virtual, comment => $cmt, line => $ln };
    }
}

sub _balance_all {
    my $j = shift;
    for my $t (@{ $j->{txns} }, @{ $j->{periodic} }) {
        my $sum = {};
        my @elided;
        for my $p (@{ $t->{postings} }) {
            next if $p->{virtual} eq 'unbalanced';
            if ($p->{amount}) { $sum = amt_add($sum, $p->{cost} // $p->{amount}) }
            else              { push @elided, $p }
        }
        my $where = "$t->{file}:$t->{line}";
        if (@elided > 1) { push @{ $j->{errors} }, "$where: more than one posting without an amount"; next }
        if (@elided == 1) { $elided[0]{amount} = amt_neg($sum); next }
        next if $t->{period};                 # periodic entries need not balance
        push @{ $j->{errors} }, "$where: transaction does not balance (off by " . format_amount($sum) . ")" unless amt_zero($sum);
    }
}

# ---------------------------------------------------------------- queries
# postings($j, begin=>, end=>, period=>, account=>qr//, payee=>qr//, cleared=>1, real=>1)
sub postings {
    my ($j, %f) = @_;
    my ($beg, $end) = ($f{begin}, $f{end});
    ($beg, $end) = period_range($f{period}) if $f{period};
    my @out;
    for my $t (sort { $a->{date} cmp $b->{date} } @{ $j->{txns} }) {
        next if $beg && $t->{date} lt $beg;
        next if $end && $t->{date} ge $end;
        next if $f{cleared} && $t->{status} ne '*';
        next if $f{payee} && $t->{payee} !~ $f{payee};
        for my $p (@{ $t->{postings} }) {
            next if $f{real} && $p->{virtual};
            next if $f{account} && $p->{account} !~ $f{account};
            push @out, { date => $t->{date}, payee => $t->{payee}, status => $t->{status},
                         account => $p->{account}, amount => $p->{amount}, virtual => $p->{virtual},
                         comment => $p->{comment}, txn => $t };
        }
    }
    @out;
}

sub balances {                                # account => {c=>n}, own postings only
    my %b;
    $b{ $_->{account} } = amt_add($b{ $_->{account} } // {}, $_->{amount}) for @_;
    \%b;
}
sub balance_tree {                            # every account and every ancestor, totals rolled up
    my $own = shift;
    my %t;
    for my $a (keys %$own) {
        my @parts = split /:/, $a;
        for my $i (0 .. $#parts) {
            my $node = join ':', @parts[ 0 .. $i ];
            $t{$node} = amt_add($t{$node} // {}, $own->{$a});
        }
    }
    \%t;
}
sub account_total { my ($j, $acct, %f) = @_; balance_tree(balances(postings($j, %f)))->{$acct} // {} }

sub register {                                # rows with running balance
    my $run = {};
    map { $run = amt_add($run, $_->{amount}); +{ %$_, running => $run } } @_;
}

# budget($j, period => '2026-09')  or  (begin=>, end=>)
# returns { rows => [ {account, budget, actual, remaining} ], unbudgeted => {c=>n}, months => n, begin, end }
sub budget {
    my ($j, %f) = @_;
    my ($beg, $end) = $f{period} ? period_range($f{period}) : ($f{begin}, $f{end});
    die "budget: need period or begin+end\n" unless $beg && $end;
    my $months = months_between($beg, $end);
    my %planned;                              # account => budget over [beg, end)
    for my $t (@{ $j->{periodic} }) {
        my $k = $t->{period} =~ /^month/i ? 1 : $t->{period} =~ /^year/i ? 1 / 12 : $t->{period} =~ /^week/i ? 52 / 12 : undef;
        next unless defined $k;
        my $span = plan_months($t->{period}, $beg, $end, $months);
        for my $p (@{ $t->{postings} }) {
            next unless $p->{amount};
            my $a = $p->{amount};
            next if $a->{ (keys %$a)[0] } < 0 && $p->{account} =~ /^(Assets|Liabilities|Equity|Income)\b/i;
            $planned{ $p->{account} } = amt_add($planned{ $p->{account} } // {}, amt_scale($a, $k * $span));
        }
    }
    my @accts = sorted(keys %planned);
    my @ps    = postings($j, begin => $beg, end => $end, real => 1);
    my (%actual, $unb);
    $unb = {};
    my %roots = map { (split /:/)[0] => 1 } @accts;
  POST: for my $p (@ps) {
        for my $a (@accts) {
            if ($p->{account} eq $a || index($p->{account}, "$a:") == 0) {
                $actual{$a} = amt_add($actual{$a} // {}, $p->{amount});
                next POST;
            }
        }
        my $root = (split /:/, $p->{account})[0];
        $unb = amt_add($unb, $p->{amount}) if $roots{$root};
    }
    my @rows = map {
        my $bud = $planned{$_};
        my $act = $actual{$_} // {};
        +{ account => $_, budget => $bud, actual => $act, remaining => amt_sub($bud, $act) }
    } @accts;
    { rows => \@rows, unbudgeted => $unb, months => $months, begin => $beg, end => $end };
}

# ---------------------------------------------------------------- reports (return text)
sub report_bal {
    my ($j, %f) = @_;
    my $depth = delete $f{depth};
    my $tree  = balance_tree(balances(postings($j, %f)));
    my $own   = balances(postings($j, %f));
    my %kids;
    push @{ $kids{ $_ =~ /^(.*):[^:]+$/ ? $1 : '' } }, $_ for keys %$tree;
    my @lines;
    my $walk;
    $walk = sub {
        my ($node, $level, $shown) = @_;
        my $label = $shown;
        while (@{ $kids{$node} // [] } == 1 && amt_zero($own->{$node} // {})) {    # collapse A:B chains
            my $only = $kids{$node}[0];
            $label .= ':' . ($only =~ /([^:]+)$/)[0];
            $node = $only;
        }
        return if defined $depth && $level >= $depth;
        return if amt_zero($tree->{$node}) && !$f{empty};
        push @lines, [ format_amount($tree->{$node}), ('  ' x $level) . $label ];
        $walk->($_, $level + 1, ($_ =~ /([^:]+)$/)[0]) for sorted(@{ $kids{$node} // [] });
    };
    my $total = {};
    for my $root (sorted(@{ $kids{''} // [] })) { $walk->($root, 0, $root); $total = amt_add($total, $tree->{$root}) }
    my $w = maximum(20, map { length $_->[0] } @lines);
    join('', map { sprintf("%*s  %s\n", $w, @$_) } @lines) . ('-' x $w) . "\n" . sprintf("%*s\n", $w, format_amount($total));
}

sub report_reg {
    my ($j, %f) = @_;
    my @rows = register(postings($j, %f));
    return "" unless @rows;
    my $wp = maximum(map { length $_->{payee} } @rows);   $wp = 30 if $wp > 30;
    my $wa = maximum(map { length $_->{account} } @rows);
    my @out = map { [ $_->{date}, substr($_->{payee}, 0, 30), $_->{account}, format_amount($_->{amount}), format_amount($_->{running}) ] } @rows;
    my $w1 = maximum(map { length $_->[3] } @out);
    my $w2 = maximum(map { length $_->[4] } @out);
    join '', map { sprintf("%s %-*s %-*s %*s %*s\n", $_->[0], $wp, $_->[1], $wa, $_->[2], $w1, $_->[3], $w2, $_->[4]) } @out;
}

sub report_budget {
    my ($j, %f) = @_;
    my $r = budget($j, %f);
    my @rows = map { [ $_->{account}, format_amount($_->{budget}), format_amount($_->{actual}), format_amount($_->{remaining}) ] } @{ $r->{rows} };
    my ($tb, $ta) = ({}, {});
    for (@{ $r->{rows} }) { $tb = amt_add($tb, $_->{budget}); $ta = amt_add($ta, $_->{actual}) }
    push @rows, [ 'Unbudgeted', '', format_amount($r->{unbudgeted}), '' ] unless amt_zero($r->{unbudgeted});
    $ta = amt_add($ta, $r->{unbudgeted});
    my @tot = [ 'Total', format_amount($tb), format_amount($ta), format_amount(amt_sub($tb, $ta)) ];
    my @all = (@rows, @tot);
    my @w = map { my $i = $_; maximum(map { length $_->[$i] } [ 'Account', 'Budget', 'Actual', 'Remaining' ], @all) } 0 .. 3;
    my $fmt = "%-*s  %*s  %*s  %*s\n";
    my $line = sub { sprintf $fmt, map { ($w[$_], $_[0][$_]) } 0 .. 3 };
    my $hdr  = sprintf("Budget for %s to %s (%d month%s)\n", $r->{begin}, $r->{end}, $r->{months}, $r->{months} == 1 ? '' : 's');
    $hdr . $line->([ 'Account', 'Budget', 'Actual', 'Remaining' ]) . join('', map { $line->($_) } @rows)
      . ('-' x (sum(@w) + 6)) . "\n" . $line->($tot[0]);
}

sub to_csv {                                  # date,status,payee,account,amount,commodity
    my @out = ("date,status,payee,account,amount,commodity\n");
    for my $p (@_) {
        for my $c (sorted(keys %{ $p->{amount} })) {
            push @out, join(',', $p->{date}, $p->{status}, _csvq($p->{payee}), _csvq($p->{account}), $p->{amount}{$c}, _csvq($c)) . "\n";
        }
    }
    join '', @out;
}
sub _csvq { my $s = shift; $s =~ /[",\n]/ ? '"' . ($s =~ s/"/""/gr) . '"' : $s }

# ---------------------------------------------------------------- per month (-M)
sub _range {                                  # the report window: --period, --begin/--end, else first posting .. day after the last
    my ($j, %f) = @_;
    return period_range($f{period}) if $f{period};
    my @d = sort map { $_->{date} } @{ $j->{txns} };
    return () unless @d;
    ($f{begin} // $d[0], $f{end} // add_days($d[-1], 1));
}
sub _at_depth { my ($a, $d) = @_; defined $d ? join(':', grep { defined } (split /:/, $a)[ 0 .. $d - 1 ]) : $a }
sub _table {                                  # rows of cells -> text; first column left, the rest right-aligned
    my @rows = @_;
    my @w;
    for my $r (@rows) { for my $i (0 .. $#$r) { my $l = length $r->[$i]; $w[$i] = $l if !defined $w[$i] || $l > $w[$i] } }
    join '', map { my $r = $_; join('  ', map { $_ == 0 ? sprintf('%-*s', $w[0], $r->[0]) : sprintf('%*s', $w[$_], $r->[$_] // '') } 0 .. $#$r) =~ s/\s+$//r . "\n" } @rows;
}
sub report_bal_monthly {                      # net change per account per month, one column per month, and the total
    my ($j, %f) = @_;
    my ($beg, $end) = _range($j, %f) or return '';
    my @ms = month_starts($beg, $end);
    my (%cell, %tot);
    for my $p (postings($j, %f, begin => $beg, end => $end, period => undef)) {
        my $a = _at_depth($p->{account}, $f{depth});
        my $m = substr($p->{date}, 0, 7);
        $cell{$a}{$m} = amt_add($cell{$a}{$m} // {}, $p->{amount});
        $tot{$a} = amt_add($tot{$a} // {}, $p->{amount});
    }
    my @rows = ([ 'Account', (map { substr($_, 0, 7) } @ms), 'Total' ]);
    for my $a (sorted(keys %cell)) {
        next if amt_zero($tot{$a}) && !$f{empty} && !grep { !amt_zero($_) } values %{ $cell{$a} };
        push @rows, [ $a, (map { my $c = $cell{$a}{ substr($_, 0, 7) }; $c && !amt_zero($c) ? format_amount($c) : '' } @ms), format_amount($tot{$a}) ];
    }
    _table(@rows);
}
sub report_reg_monthly {                      # one line per account per month: that month's net change and the running total
    my ($j, %f) = @_;
    my ($beg, $end) = _range($j, %f) or return '';
    my (%m, $run);
    $run = {};
    for my $p (postings($j, %f, begin => $beg, end => $end, period => undef)) {
        my $a = _at_depth($p->{account}, $f{depth});
        my $k = substr($p->{date}, 0, 7);
        $m{$k}{$a} = amt_add($m{$k}{$a} // {}, $p->{amount});
    }
    my @rows = ([ 'Month', 'Account', 'Amount', 'Running' ]);
    for my $k (sorted(keys %m)) {
        for my $a (sorted(keys %{ $m{$k} })) {
            $run = amt_add($run, $m{$k}{$a});
            push @rows, [ $k, $a, format_amount($m{$k}{$a}), format_amount($run) ];
        }
    }
    my @w = map { my $i = $_; maximum(map { length $_->[$i] } @rows) } 0 .. 3;
    join '', map { sprintf("%-*s  %-*s  %*s  %*s\n", $w[0], $_->[0], $w[1], $_->[1], $w[2], $_->[2], $w[3], $_->[3]) =~ s/\s+\n$/\n/r } @rows;
}
sub report_budget_monthly {                   # budget, actual and remaining per budgeted account, month by month
    my ($j, %f) = @_;
    my ($beg, $end) = _range($j, %f) or return '';
    my @rows = ([ 'Month', 'Account', 'Budget', 'Actual', 'Remaining' ]);
    for my $ms (month_starts($beg, $end)) {
        my $r = budget($j, begin => $ms, end => next_month($ms));
        for my $row (@{ $r->{rows} }) {
            next if $f{account} && $row->{account} !~ $f{account};
            next if amt_zero($row->{budget}) && amt_zero($row->{actual});
            push @rows, [ substr($ms, 0, 7), $row->{account}, format_amount($row->{budget}), format_amount($row->{actual}), format_amount($row->{remaining}) ];
        }
    }
    my @w = map { my $i = $_; maximum(map { length $_->[$i] } @rows) } 0 .. 4;
    join '', map { sprintf("%-*s  %-*s  %*s  %*s  %*s\n", $w[0], $_->[0], $w[1], $_->[1], $w[2], $_->[2], $w[3], $_->[3], $w[4], $_->[4]) } @rows;
}

# ---------------------------------------------------------------- earned value and funding run-out
# Percent complete: --complete ACCOUNT=PCT (repeatable) or --complete-file FILE (lines "account,pct", # comments).
# PCT is 0-100, or 0-1 when written with a decimal point and <= 1. An account's percent applies to it and its sub-accounts.
sub read_complete {
    my ($pairs, $file) = @_;
    my %c;
    my $put = sub {
        my ($a, $v, $where) = @_;
        $a = _trim($a); $v = _trim($v);
        $v =~ s/%$//;
        die "$where: percent complete for '$a' is not a number: '$v'\n" unless $v =~ /^\d+(?:\.\d+)?$/;
        $v = $v <= 1 && $v =~ /\./ ? $v * 100 : $v;
        die "$where: percent complete for '$a' is over 100: $v\n" if $v > 100;
        $c{$a} = $v / 100;
    };
    for (@{ $pairs // [] }) { my ($a, $v) = /^(.+)=(.*)$/ or die "--complete wants ACCOUNT=PCT, got '$_'\n"; $put->($a, $v, '--complete') }
    if (defined $file) {
        my $t = read_text($file) // die "cannot read $file: $!\n";
        my $ln = 0;
        for (split /\r?\n/, $t) {
            $ln++;
            next if /^\s*(#|;|$)/ || ($ln == 1 && /^\s*account\s*,/i);
            my ($a, $v) = /^(.*),\s*([^,]*)$/ or die "$file:$ln: want 'account,pct'\n";
            $put->($a, $v, "$file:$ln");
        }
    }
    \%c;
}
sub _pct_for { my ($c, $a) = @_; my @k = sort { length $b <=> length $a } grep { $a eq $_ || index($a, "$_:") == 0 } keys %$c; @k ? $c->{ $k[0] } : undef }
sub _num { my $x = shift; my ($c) = sorted(keys %$x); defined $c ? ($x->{$c}, $c) : (0, undef) }

# evm($j, status => 'YYYY-MM-DD' (exclusive; default today), complete => {acct => 0..1})
# Planned value (BCWS) comes from the dated ~ budgets up to the status date, budget at completion (BAC) from their whole
# window, actual cost (ACWP) from the journal, earned value (BCWP) = BAC x percent complete.
sub evm {
    my ($j, %f) = @_;
    my $status = $f{status} // today();
    my (%bac, %pv, %plan_begin);
    for my $t (@{ $j->{periodic} }) {
        my ($kind, $from, $to) = periodic_window($t->{period});
        my $k = $kind =~ /^month/ ? 1 : $kind =~ /^year/ ? 1 / 12 : $kind =~ /^week/ ? 52 / 12 : undef;
        next unless defined $k;
        die "evm: budget '~ $t->{period}' ($t->{file}:$t->{line}) needs 'from DATE to DATE' to give a budget at completion\n" unless $from && $to;
        my $all = plan_months($t->{period}, $from, $to);
        my $now = $status le $from ? 0 : plan_months($t->{period}, $from, $status lt $to ? $status : $to);
        for my $p (@{ $t->{postings} }) {
            next unless $p->{amount};
            my ($n) = _num($p->{amount});
            next if $n < 0;                   # the funding side of the budget entry
            next if $f{account} && $p->{account} !~ $f{account};
            my $a = $p->{account};
            $bac{$a} = amt_add($bac{$a} // {}, amt_scale($p->{amount}, $k * $all));
            $pv{$a}  = amt_add($pv{$a}  // {}, amt_scale($p->{amount}, $k * $now));
            $plan_begin{$a} = $from if !$plan_begin{$a} || $from lt $plan_begin{$a};
        }
    }
    my @accts = sorted(keys %bac);
    my %ac;
  POST: for my $p (postings($j, end => $status, real => 1)) {
        for my $a (@accts) { if ($p->{account} eq $a || index($p->{account}, "$a:") == 0) { $ac{$a} = amt_add($ac{$a} // {}, $p->{amount}); next POST } }
    }
    my @rows;
    for my $a (@accts) {
        my ($bac, $c) = _num($bac{$a});
        my ($bcws) = _num($pv{$a});
        my ($acwp) = _num($ac{$a} // {});
        my $pct = _pct_for($f{complete} // {}, $a);
        my $bcwp = defined $pct ? $bac * $pct : undef;
        push @rows, _evm_row($a, $c, $bac, $bcws, $bcwp, $acwp, $pct);
    }
    my $c = @rows ? $rows[0]{commodity} : '$';
    my %t = (bac => 0, bcws => 0, bcwp => 0, acwp => 0);
    my $all_known = 1;
    for my $r (@rows) { $t{$_} += $r->{$_} // 0 for qw(bac bcws acwp); if (defined $r->{bcwp}) { $t{bcwp} += $r->{bcwp} } else { $all_known = 0 } }
    my $total = @rows ? _evm_row('Total', $c, $t{bac}, $t{bcws}, $all_known ? $t{bcwp} : undef, $t{acwp}, $all_known && $t{bac} ? $t{bcwp} / $t{bac} : undef) : undef;
    { status => $status, rows => \@rows, total => $total };
}
sub _evm_row {
    my ($a, $c, $bac, $bcws, $bcwp, $acwp, $pct) = @_;
    my %r = (account => $a, commodity => $c, bac => $bac, bcws => $bcws, bcwp => $bcwp, acwp => $acwp, pct => $pct);
    if (defined $bcwp) {
        $r{cv}  = $bcwp - $acwp;
        $r{sv}  = $bcwp - $bcws;
        $r{cpi} = $acwp ? $bcwp / $acwp : undef;
        $r{spi} = $bcws ? $bcwp / $bcws : undef;
        $r{eac} = $r{cpi} ? $bac / $r{cpi} : undef;
        $r{etc} = defined $r{eac} ? $r{eac} - $acwp : undef;
        $r{vac} = defined $r{eac} ? $bac - $r{eac} : undef;
    }
    \%r;
}
sub report_evm {
    my ($j, %f) = @_;
    my $e = evm($j, %f);
    return "no dated budgets (~ Monthly from DATE to DATE) to measure against\n" unless @{ $e->{rows} };
    my $m = sub { my ($v, $c) = @_; defined $v ? format_amount({ $c // '$' => $v }) : '-' };
    my $x = sub { defined $_[0] ? sprintf('%.2f', $_[0]) : '-' };
    my @rows = ([ 'Account', '%done', 'BAC', 'BCWS', 'BCWP', 'ACWP', 'CV', 'SV', 'CPI', 'SPI', 'EAC', 'VAC' ]);
    for my $r (@{ $e->{rows} }, $e->{total}) {
        my $c = $r->{commodity};
        push @rows, [ $r->{account}, defined $r->{pct} ? sprintf('%.0f%%', 100 * $r->{pct}) : '-',
                      map({ $m->($r->{$_}, $c) } qw(bac bcws bcwp acwp cv sv)), $x->($r->{cpi}), $x->($r->{spi}), $m->($r->{eac}, $c), $m->($r->{vac}, $c) ];
    }
    my $missing = grep { !defined $_->{pct} } @{ $e->{rows} };
    "Earned value as of $e->{status}\n" . _table(@rows)
      . ($missing ? "($missing account" . ($missing == 1 ? '' : 's') . " without a percent complete: give --complete ACCOUNT=PCT or --complete-file)\n" : '');
}

# forecast($j, status => date, months => N): for each account, the balance at the status date, the average monthly burn
# (net decrease) over the N whole months before it (fewer if the account is younger), and when it reaches zero at that rate.
sub forecast {
    my ($j, %f) = @_;
    my $status = $f{status} // today();
    my $n = $f{months} // 3;
    my $win_end = substr($status, 0, 8) . '01';
    my ($y, $m) = $win_end =~ /^(\d{4})-(\d{2})/;
    my $win_beg = sprintf '%04d-%02d-01', _add_months($y, $m, -$n);
    my (%bal, %burn);
    for my $p (postings($j, end => $status, real => 1)) {
        next if $f{account} && $p->{account} !~ $f{account};
        my $a = _at_depth($p->{account}, $f{depth});
        $bal{$a} = amt_add($bal{$a} // {}, $p->{amount});
        $burn{$a} = amt_add($burn{$a} // {}, $p->{amount}) if $p->{date} ge $win_beg && $p->{date} lt $win_end && (_num($p->{amount}))[0] < 0;
    }
    my (@rows, %first);
    for my $p (postings($j, end => $status, real => 1)) { my $a = _at_depth($p->{account}, $f{depth}); $first{$a} //= substr($p->{date}, 0, 8) . '01' }
    for my $a (sorted(keys %bal)) {
        my ($b, $c) = _num($bal{$a});
        my ($u) = _num($burn{$a} // {});
        my $k = grep { $_ ge $first{$a} } month_starts($win_beg, $win_end);   # only months since the account's first posting
        my $rate = $k ? -$u / $k : 0;
        my %r = (account => $a, commodity => $c, balance => $b, burn => $rate);
        if ($rate > 0 && $b > 0) { $r{months} = $b / $rate; $r{runout} = add_days($status, int($r{months} * 30.4375 + 0.5)) }
        push @rows, \%r;
    }
    { status => $status, months => $n, window => [ $win_beg, $win_end ], rows => \@rows };
}
sub report_forecast {
    my ($j, %f) = @_;
    my $r = forecast($j, %f);
    my @rows = ([ 'Account', 'Balance', 'Burn/month', 'Months left', 'Runs out' ]);
    for my $x (@{ $r->{rows} }) {
        push @rows, [ $x->{account}, format_amount({ $x->{commodity} // '' => $x->{balance} }), $x->{burn} > 0 ? format_amount({ $x->{commodity} // '' => $x->{burn} }) : 'not burning',
                      defined $x->{months} ? sprintf('%.1f', $x->{months}) : '-', $x->{runout} // '-' ];
    }
    "Funding run-out as of $r->{status} (burn = average monthly spend, $r->{window}[0] to $r->{window}[1])\n" . _table(@rows);
}

# ---------------------------------------------------------------- command-line driver
sub run {                                     # run(@ARGV) -> exit status; used by bin/ledger.pl
    my @argv = @_;
    require Getopt::Long;
    Getopt::Long::Configure('no_ignore_case');   # -e end vs -E empty, -C/-R as in ledger-cli; Git for Windows' Perl 5.42 otherwise rejects the spec as duplicate
    my %o = (file => $ENV{LEDGER_FILE} // 'ledger.txt');
    Getopt::Long::GetOptionsFromArray(\@argv,
        'f|file=s' => \$o{file}, 'b|begin=s' => \$o{begin}, 'e|end=s' => \$o{end}, 'p|period=s' => \$o{period},
        'depth=i' => \$o{depth}, 'C|cleared' => \$o{cleared}, 'R|real' => \$o{real}, 'E|empty' => \$o{empty},
        'payee=s' => \$o{payee}, 'M|monthly' => \$o{monthly}, 'now=s' => \$o{now}, 'months=i' => \$o{months},
        'complete=s@' => \$o{complete}, 'complete-file=s' => \$o{complete_file}) or return 2;
    my $cmd = shift @argv // 'bal';
    my %f;
    $f{$_} = $o{$_} for grep { defined $o{$_} } qw(begin end period depth cleared real empty);
    $f{begin} = norm_date($f{begin}) // die "bad --begin\n" if $f{begin};
    $f{end}   = norm_date($f{end})   // die "bad --end\n"   if $f{end};
    $f{payee}   = qr/$o{payee}/i if defined $o{payee};
    $f{account} = do { my $re = join '|', @argv; qr/$re/i } if @argv;
    my $j = eval { read_journal($o{file}) };
    if (!$j) { print STDERR $@; return 1 }
    my $now = defined $o{now} ? (norm_date($o{now}) // die "bad --now (want YYYY-MM-DD)\n") : undef;
    my $status = defined $now ? add_days($now, 1) : add_days(today(), 1);   # through the end of that day
    if ($o{monthly} && $cmd =~ /^(bal|balance)$/)      { print report_bal_monthly($j, %f) }
    elsif ($o{monthly} && $cmd =~ /^(reg|register)$/)  { print report_reg_monthly($j, %f) }
    elsif ($o{monthly} && $cmd eq 'budget')            { print report_budget_monthly($j, %f) }
    elsif ($cmd eq 'bal' || $cmd eq 'balance')  { print report_bal($j, %f) }
    elsif ($cmd eq 'reg' || $cmd eq 'register') { print report_reg($j, %f) }
    elsif ($cmd eq 'budget') { $f{period} = this_month() unless $f{period} || ($f{begin} && $f{end}); print report_budget($j, %f) }
    elsif ($cmd eq 'evm') {
        my $c = read_complete($o{complete}, $o{complete_file});
        print report_evm($j, %f, status => $status, complete => $c) =~ s/as of \S+/'as of ' . add_days($status, -1)/er;
    }
    elsif ($cmd eq 'forecast') { print report_forecast($j, %f, status => $status, months => $o{months}) =~ s/run-out as of \S+/'run-out as of ' . add_days($status, -1)/er }
    elsif ($cmd eq 'csv')    { print to_csv(postings($j, %f)) }
    elsif ($cmd eq 'check')  { printf "ok: %d transactions, %d budget entries\n", scalar @{ $j->{txns} }, scalar @{ $j->{periodic} } }
    elsif ($cmd eq 'accounts') { print "$_\n" for sorted(nub(map { $_->{account} } postings($j, %f))) }
    elsif ($cmd eq 'payees')   { print "$_\n" for sorted(nub(map { $_->{payee} } postings($j, %f))) }
    else { print STDERR "unknown command '$cmd' (bal reg budget evm forecast csv check accounts payees)\n"; return 2 }
    0;
}

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Ledger::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Ledger::$_"} == \&{"Prelude::$_"})    # don't re-export Prelude
    } keys %Ledger::;
}

1;

__END__

=head1 NAME

Ledger - plain-text double-entry accounting in core Perl (ledger-cli file format)

=head1 SYNOPSIS

    # command line (bin/ledger.pl is a two-line wrapper around Ledger::run)
    perl bin/ledger.pl -f money.txt bal
    perl bin/ledger.pl -f money.txt bal Expenses --depth 2
    perl bin/ledger.pl -f money.txt reg Groceries --period 2026-09
    perl bin/ledger.pl -f money.txt budget --period 2026-09
    perl bin/ledger.pl -f money.txt csv > postings.csv        # for Excel pivots
    perl bin/ledger.pl -f money.txt check

    # as a library
    use Ledger;
    my $j = read_journal('money.txt');
    print report_bal($j, period => '2026-09', depth => 2);
    my $food = account_total($j, 'Expenses:Groceries', period => '2026-Q3');
    print format_amount($food), "\n";

Set C<LEDGER_FILE> to skip C<-f>.

=head1 FILE FORMAT

A subset of ledger-cli's journal syntax. Edit it in Vim, keep it in Git.

    ; comment lines start with ; # % | or *

    2026-09-03 * Paycheck
        Assets:Checking            3200.00
        Income:Salary

    2026-09-05 Kroger                     ; payee text, optional * (cleared) or ! (pending)
        Expenses:Groceries           84.12  ; posting comment
        Liabilities:Visa                    ; amount omitted: balances the transaction

    2026-09-10 Brokerage
        Assets:Brokerage        10 AAPL @ 150.00      ; cost is used for balancing
        Assets:Checking

    ~ Monthly                              ; budget: periodic transaction
        Expenses:Groceries          600.00
        Expenses:House:Repairs      150.00
        Assets:Checking

    ~ Yearly                               ; spread over 12 months in budget reports
        Expenses:Insurance         1200.00
        Assets:Checking

    include 2025.txt                       ; relative to the including file

Rules and details:

=over 4

=item * Account and amount are separated by two or more spaces or a tab.

=item * Amounts: C<42.17>, C<-42.17>, C<$42.17>, C<$-42.17>, C<1,234.56>,
C<42.17 USD>, C<10 AAPL>. A symbol before the number or a code after it is the
commodity; balances are kept per commodity. Display precision is the largest
number of decimals seen for that commodity.

=item * Dates: C<YYYY-MM-DD> or C<YYYY/MM/DD>. An effective date C<=YYYY-MM-DD>
is accepted and ignored.

=item * Exactly one posting per transaction may omit its amount. A transaction
whose postings don't sum to zero is an error (C<check> lists them all).

=item * Virtual postings: C<(Account)> is unbalanced virtual and skipped by
balancing; C<[Account]> is balanced virtual. C<--real> excludes both.

=item * C<@ price> and C<@@ total cost> are honoured for balancing; C<= assertion>
after an amount is ignored. C<P> price lines are parsed and stored but not
used in reports. Directives C<account>, C<commodity>, C<payee>, C<tag>,
C<year>, C<apply>, and automated C<=> transactions are skipped.

=back

=head1 COMMANDS (Ledger::run)

    bal [ACCOUNT-REGEX...]   balance tree; single-child chains collapse (Assets:Checking)
    reg [ACCOUNT-REGEX...]   one line per posting with running balance
    budget                   periodic ~ entries vs actual for --period (default: this month)
    csv                      postings as CSV: date,status,payee,account,amount,commodity
    check                    parse and verify every transaction balances
    accounts | payees        distinct names seen

    -f FILE      journal (or $LEDGER_FILE, default ledger.txt)
    -p PERIOD    2026 | 2026-09 | 2026-Q3
    -b DATE      begin (inclusive)      -e DATE  end (exclusive)
    --depth N    limit bal to N levels
    -C           cleared (*) transactions only
    -R           real postings only (no virtual)
    -E           show zero balances in bal
    --payee RE   filter by payee (case-insensitive)

Positional arguments after the command are account regexes, ORed together,
case-insensitive: C<bal groceries repairs>.

=head1 FUNCTIONS

=head2 Reading

    my $j = read_journal($path);            # dies listing every error
    my $j = read_journal($path, lenient => 1);   # keep going; see $j->{errors}
    my $j = parse_journal($text, $name);    # same, from a string

C<$j-E<gt>{txns}> is a list of transactions in file order; each has C<date>,
C<status> (C<*>, C<!> or empty), C<payee>, C<comment>, C<line>, C<file> and
C<postings>. Each posting has C<account>, C<amount> (a hash ref of
commodity => number), C<cost>, C<virtual> and C<comment>.
C<$j-E<gt>{periodic}> holds the C<~> entries.

=head2 Selecting postings

    my @ps = postings($j, period => '2026-09');
    my @ps = postings($j, begin => '2026-01-01', end => '2026-07-01');
    my @ps = postings($j, account => qr/^Expenses/, payee => qr/kroger/i, cleared => 1, real => 1);

Postings come back sorted by date, each flattened to C<date>, C<payee>,
C<status>, C<account>, C<amount>, C<virtual>, C<comment>, plus C<txn> for the
parent. This is the hook for anything the reports don't cover:

    use Prelude;
    my $by_month = classify(sub { substr($_[0]{date}, 0, 7) }, postings($j, account => qr/^Expenses/));
    printf "%s %s\n", $_, format_amount(foldl(\&amt_add, {}, fmap(sub { $_[0]{amount} }, @{ $by_month->{$_} })))
        for sorted(keys %$by_month);

=head2 Aggregating

    my $own  = balances(@ps);              # { 'Expenses:Groceries' => {'' => 84.12}, ... }
    my $tree = balance_tree($own);         # adds 'Expenses' => rolled-up total, etc.
    my $amt  = account_total($j, 'Expenses', period => '2026');
    my @rows = register(@ps);              # each posting plus running => running balance
    my $b    = budget($j, period => '2026-09');
    # $b->{rows}[0] = { account, budget, actual, remaining }, $b->{unbudgeted}, $b->{months}

C<budget> matches actual postings by account prefix, so a C<~ Monthly> line for
C<Expenses:House> also collects C<Expenses:House:Repairs>. Postings under a
budgeted top-level account (usually C<Expenses>) that match no budget line are
summed as C<unbudgeted>. Multi-month periods multiply the monthly budget.

=head2 Amounts

Amounts are hash refs C<{ commodity =E<gt> number }> so one posting can hold
several commodities.

    parse_amount('$-1,234.56')          # { '$' => -1234.56 }
    format_amount({ '$' => -1234.56 })  # '$-1,234.56'
    format_amount({ USD => 5, AAPL => 10 })   # '10 AAPL, 5.00 USD'
    amt_add($a, $b)  amt_sub($a, $b)  amt_neg($a)  amt_scale($a, 12)  amt_zero($a)

=head2 Reports

    print report_bal($j, %filters, depth => 2, empty => 1);
    print report_reg($j, %filters);
    print report_budget($j, period => '2026-09');
    print to_csv(postings($j, %filters));

Sample C<bal>:

              $3,115.88  Assets:Checking
                $-84.12  Liabilities:Visa
                 $84.12  Expenses:Groceries
             $-3,200.00  Income:Salary
    --------------------
                      0

Sample C<budget --period 2026-09>:

    Budget for 2026-09-01 to 2026-10-01 (1 month)
    Account                 Budget   Actual  Remaining
    Expenses:Groceries      600.00   512.30      87.70
    Expenses:House:Repairs  150.00   342.17    -192.17
    Unbudgeted                        23.00
    ---------------------------------------------------
    Total                   750.00   877.47    -127.47

=head2 Dates and periods

    norm_date('2026/9/3')          # '2026-09-03'
    period_range('2026-Q3')        # ('2026-07-01', '2026-10-01')
    months_between('2026-01-01', '2026-07-01')   # 6
    this_month()                   # '2026-09'

=head1 WORKFLOW

Journal in Vim, C<git commit> after each session, C<check> in a pre-commit hook
if you like. C<budget> on the first of the month, C<csv> into Excel when you
want a pivot table or chart. Envelope budgeting works with virtual postings:

    2026-09-03 * Paycheck
        Assets:Checking          3200.00
        Income:Salary
        (Envelope:Groceries)      600.00
        (Envelope:Fun)            200.00

    2026-09-05 Kroger
        Expenses:Groceries         84.12
        Assets:Checking
        (Envelope:Groceries)      -84.12

    perl bin/ledger.pl bal Envelope        # what is left in each envelope

=head1 SEE ALSO

L<Prelude>, and ledger-cli's manual for the full format this implements a
subset of: https://ledger-cli.org/doc/ledger3.html

=cut
