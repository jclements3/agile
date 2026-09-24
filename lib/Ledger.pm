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

# ---------------------------------------------------------------- parsing
# journal = { txns => [...], periodic => [...], prices => [...], errors => [...] }
# txn     = { date, status, payee, comment, line, file, postings => [ posting ] }
# posting = { account, amount => {c=>n} | undef, cost => {c=>n} | undef, virtual => 0|'balanced'|'unbalanced', comment, line }

sub read_journal {
    my ($file, %opt) = @_;
    open my $fh, '<', $file or die "cannot open $file: $!\n";
    local $/;
    my $text = <$fh>;
    close $fh;
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
            if (open my $fh, '<', $inc) { local $/; my $t = <$fh>; close $fh; _parse_into($j, $t, $inc) }
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
    my %per_month;
    for my $t (@{ $j->{periodic} }) {
        my $k = $t->{period} =~ /^month/i ? 1 : $t->{period} =~ /^year/i ? 1 / 12 : $t->{period} =~ /^week/i ? 52 / 12 : undef;
        next unless defined $k;
        for my $p (@{ $t->{postings} }) {
            next unless $p->{amount};
            my $a = $p->{amount};
            next if $a->{ (keys %$a)[0] } < 0 && $p->{account} =~ /^(Assets|Liabilities|Equity|Income)\b/i;
            $per_month{ $p->{account} } = amt_add($per_month{ $p->{account} } // {}, amt_scale($a, $k));
        }
    }
    my @accts = sorted(keys %per_month);
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
        my $bud = amt_scale($per_month{$_}, $months);
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

# ---------------------------------------------------------------- command-line driver
sub run {                                     # run(@ARGV) -> exit status; used by bin/ledger.pl
    my @argv = @_;
    require Getopt::Long;
    Getopt::Long::Configure('no_ignore_case');   # -e end vs -E empty, -C/-R as in ledger-cli; Git for Windows' Perl 5.42 otherwise rejects the spec as duplicate
    my %o = (file => $ENV{LEDGER_FILE} // 'ledger.txt');
    Getopt::Long::GetOptionsFromArray(\@argv,
        'f|file=s' => \$o{file}, 'b|begin=s' => \$o{begin}, 'e|end=s' => \$o{end}, 'p|period=s' => \$o{period},
        'depth=i' => \$o{depth}, 'C|cleared' => \$o{cleared}, 'R|real' => \$o{real}, 'E|empty' => \$o{empty},
        'payee=s' => \$o{payee}) or return 2;
    my $cmd = shift @argv // 'bal';
    my %f;
    $f{$_} = $o{$_} for grep { defined $o{$_} } qw(begin end period depth cleared real empty);
    $f{begin} = norm_date($f{begin}) // die "bad --begin\n" if $f{begin};
    $f{end}   = norm_date($f{end})   // die "bad --end\n"   if $f{end};
    $f{payee}   = qr/$o{payee}/i if defined $o{payee};
    $f{account} = do { my $re = join '|', @argv; qr/$re/i } if @argv;
    my $j = eval { read_journal($o{file}) };
    if (!$j) { print STDERR $@; return 1 }
    if    ($cmd eq 'bal' || $cmd eq 'balance')  { print report_bal($j, %f) }
    elsif ($cmd eq 'reg' || $cmd eq 'register') { print report_reg($j, %f) }
    elsif ($cmd eq 'budget') { $f{period} = this_month() unless $f{period} || ($f{begin} && $f{end}); print report_budget($j, %f) }
    elsif ($cmd eq 'csv')    { print to_csv(postings($j, %f)) }
    elsif ($cmd eq 'check')  { printf "ok: %d transactions, %d budget entries\n", scalar @{ $j->{txns} }, scalar @{ $j->{periodic} } }
    elsif ($cmd eq 'accounts') { print "$_\n" for sorted(nub(map { $_->{account} } postings($j, %f))) }
    elsif ($cmd eq 'payees')   { print "$_\n" for sorted(nub(map { $_->{payee} } postings($j, %f))) }
    else { print STDERR "unknown command '$cmd' (bal reg budget csv check accounts payees)\n"; return 2 }
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
