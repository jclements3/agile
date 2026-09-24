#!/usr/bin/perl
# perl t/ledger.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Prelude qw(show fmap sorted nub);
use Ledger;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub dies_like { my ($name, $re, $code) = @_; eval { $code->(); 1 } ? check($name, 'lived', "died matching $re") : check($name, ($@ =~ $re ? 1 : "no match: $@"), 1) }

# ---- amounts
S 'parse plain',   '{"":42.17}',       parse_amount('42.17');
S 'parse neg',     '{"":-42.17}',      parse_amount('-42.17');
S 'parse $',       '{"$":42.17}',      parse_amount('$42.17');
S 'parse $-',      '{"$":-1234.56}',   parse_amount('$-1,234.56');
S 'parse -$',      '{"$":-5}',         parse_amount('-$5');
S 'parse code',    '{"EUR":-12.5}',    parse_amount('-12.5 EUR');
S 'parse qty',     '{"AAPL":10}',      parse_amount('10 AAPL');
S 'parse quoted',  '{"big thing":3}',  parse_amount('3 "big thing"');
S 'parse bad',     'undef',            parse_amount('abc');
S 'parse empty',   'undef',            parse_amount('  ');
S 'fmt $',         '"$-1,234.56"',     format_amount({ '$' => -1234.56 });
S 'fmt code',      '"5.00 USD"',       format_amount({ USD => 5 });
S 'fmt multi',     '"10 AAPL, 5.00 USD"', format_amount({ USD => 5, AAPL => 10 });
S 'fmt zero',      '0',                format_amount({ '' => 0.001 });
S 'fmt big',       '"1,234,567.89"',   format_amount({ '' => 1234567.89 });
S 'amt_add',       '{"$":3,"USD":1}',  amt_add({ '$' => 1 }, { '$' => 2, USD => 1 });
S 'amt_sub',       '{"$":-1}',         amt_sub({ '$' => 1 }, { '$' => 2 });
S 'amt_scale',     '{"":600}',         amt_scale({ '' => 50 }, 12);
S 'amt_zero',      '[1,0]',            [ amt_zero({ '' => 0.0001 }), amt_zero({ '' => 0.01 }) ];

# ---- dates
S 'norm_date',     '"2026-09-03"',     norm_date('2026/9/3');
S 'norm_date bad', 'undef',            norm_date('yesterday');
S 'period year',   '["2026-01-01","2027-01-01"]', [ period_range('2026') ];
S 'period month',  '["2026-12-01","2027-01-01"]', [ period_range('2026-12') ];
S 'period quarter', '["2026-07-01","2026-10-01"]', [ period_range('2026-Q3') ];
S 'months_between', '[6,1,2]', [ months_between('2026-01-01', '2026-07-01'), months_between('2026-09-01', '2026-10-01'), months_between('2026-09-01', '2026-10-15') ];

# ---- journal
my $journal = <<'EOF';
; -*- ledger -*-
account Assets:Checking
    note main account

2026-09-03 * Paycheck
    Assets:Checking            3200.00
    Income:Salary
    (Envelope:Groceries)        600.00

2026/09/05 Kroger   ; weekly shop
    Expenses:Groceries          84.12  ; with coupons
    Liabilities:Visa
    (Envelope:Groceries)       -84.12

2026-09-07 ! Home Depot
    Expenses:House:Repairs      42.17
    Liabilities:Visa

2026-09-10 Brokerage
    Assets:Brokerage        10 AAPL @ 150.00
    Assets:Checking

2026-09-12 Brokerage
    Assets:Brokerage         2 AAPL @@ 310.00
    Assets:Checking

2026-08-20 * Kroger
    Expenses:Groceries          51.00
    Assets:Checking

2026-09-15 Vet
    Expenses:Pets               23.00
    Assets:Checking            -23.00 = 2995.71

comment
    2026-01-01 Not a transaction
        Expenses:Nope   1.00
end comment

= /Groceries/
    (Stats:Food)  1.0

P 2026-09-01 AAPL 155.00

~ Monthly
    Expenses:Groceries         600.00
    Expenses:House             150.00
    Assets:Checking

~ Yearly
    Expenses:Insurance        1200.00
    Assets:Checking
EOF

my $j = parse_journal($journal, 'test.txt');
S 'txn count',      7, scalar @{ $j->{txns} };
S 'periodic count', 2, scalar @{ $j->{periodic} };
S 'prices',         '[{"commodity":"AAPL","date":"2026-09-01","price":{"":155}}]', $j->{prices};
S 'status',         '["*","","!"]', [ fmap(sub { $_[0]{status} }, @{ $j->{txns} }[0 .. 2]) ];
S 'payee comment',  '["Kroger","weekly shop"]', [ @{ $j->{txns}[1] }{qw(payee comment)} ];
S 'posting comment', '"with coupons"', $j->{txns}[1]{postings}[0]{comment};
S 'elided amount',  '{"":-3200}', $j->{txns}[0]{postings}[1]{amount};
S 'virtual flag',   '["unbalanced",0]', [ $j->{txns}[0]{postings}[2]{virtual}, $j->{txns}[0]{postings}[0]{virtual} ];
S 'cost @',         '[{"AAPL":10},{"":1500}]', [ @{ $j->{txns}[3]{postings}[0] }{qw(amount cost)} ];
S 'cost @@ balances', '{"":-310}', $j->{txns}[4]{postings}[1]{amount};
S 'date normalised', '"2026-09-05"', $j->{txns}[1]{date};
S 'assertion ignored', '{"":-23}', $j->{txns}[6]{postings}[1]{amount};
S 'periodic elided', '{"":-750}', $j->{periodic}[0]{postings}[2]{amount};

# ---- errors
dies_like 'unbalanced', qr/bad\.txt:1: transaction does not balance \(off by -1\.00\)/, sub {
    parse_journal("2026-01-01 x\n    A  1.00\n    B  -2.00\n", 'bad.txt') };
dies_like 'two elided', qr/more than one posting without an amount/, sub {
    parse_journal("2026-01-01 x\n    A  1.00\n    B\n    C\n", 'bad.txt') };
dies_like 'bad amount', qr/bad\.txt:2: bad amount 'lots'/, sub {
    parse_journal("2026-01-01 x\n    A  lots\n    B\n", 'bad.txt') };
dies_like 'bad date', qr/bad date/, sub { parse_journal("2026-13-45 x\n    A  1\n    B\n", 'bad.txt') };
dies_like 'garbage line', qr/unrecognised line: hello/, sub { parse_journal("hello\n", 'bad.txt') };
my $len = parse_journal("2026-01-01 x\n    A  1.00\n    B  -2.00\n\n2026-01-02 y\n    A  1\n    B\n", 'bad.txt', lenient => 1);
S 'lenient keeps going', '[1,2]', [ scalar @{ $len->{errors} }, scalar @{ $len->{txns} } ];

# ---- include
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/main.txt" or die $!;
print $fh "include sub/2025.txt\n\n2026-01-01 New\n    Expenses:Misc  5\n    Assets:Cash\n";
close $fh;
mkdir "$dir/sub";
open $fh, '>', "$dir/sub/2025.txt" or die $!;
print $fh "2025-12-31 Old\n    Expenses:Misc  7\n    Assets:Cash\n";
close $fh;
my $inc = read_journal("$dir/main.txt");
S 'include',        '["2025-12-31","2026-01-01"]', [ fmap(sub { $_[0]{date} }, @{ $inc->{txns} }) ];
S 'include file',   1, ($inc->{txns}[0]{file} =~ /2025\.txt$/ ? 1 : 0);
dies_like 'missing include', qr/cannot include/, sub { parse_journal("include nope.txt\n", "$dir/x.txt") };

# ---- postings & filters
S 'postings sorted', '"2026-08-20"', (postings($j))[0]{date};
S 'postings count',  16, scalar postings($j);
S 'period filter',   '["2026-08-20","2026-08-20"]', [ fmap(sub { $_[0]{date} }, postings($j, period => '2026-08')) ];
S 'begin/end',       5, scalar postings($j, begin => '2026-09-05', end => '2026-09-08');
S 'account filter',  '["Expenses:Groceries","Expenses:Groceries"]', [ fmap(sub { $_[0]{account} }, postings($j, account => qr/Groceries/, real => 1)) ];
S 'payee filter',    2, scalar(() = postings($j, payee => qr/kroger/i, account => qr/^Expenses/));
S 'cleared filter',  '["Kroger","Paycheck"]', [ sorted(nub(map { $_->{payee} } postings($j, cleared => 1))) ];
S 'real filter',     14, scalar postings($j, real => 1);

# ---- aggregates
my $own = balances(postings($j, real => 1));
S 'balances own',   '{"":135.12}', $own->{'Expenses:Groceries'};
S 'balances multi', '{"AAPL":12}', $own->{'Assets:Brokerage'};
my $tree = balance_tree($own);
S 'tree rollup',    '{"":200.29}', $tree->{'Expenses'};
S 'tree leaf',      '{"":42.17}',  $tree->{'Expenses:House:Repairs'};
S 'account_total',  '{"":149.29}', account_total($j, 'Expenses', period => '2026-09');
S 'envelope',       '{"":515.88}', account_total($j, 'Envelope:Groceries');
my @reg = register(postings($j, account => qr/^Liabilities/));
S 'register running', '[{"":-84.12},{"":-126.29}]', [ fmap(sub { $_[0]{running} }, @reg) ];

# ---- budget
my $b = budget($j, period => '2026-09');
S 'budget months',  1, $b->{months};
S 'budget rows',    '[["Expenses:Groceries",{"":600},{"":84.12},{"":515.88}],["Expenses:House",{"":150},{"":42.17},{"":107.83}],["Expenses:Insurance",{"":100},{},{"":100}]]',
  [ fmap(sub { [ @{ $_[0] }{qw(account budget actual remaining)} ] }, @{ $b->{rows} }) ];
S 'unbudgeted',     '{"":23}', $b->{unbudgeted};
my $q = budget($j, period => '2026-Q3');
S 'budget quarter', '[3,{"":1800},{"":135.12}]', [ $q->{months}, $q->{rows}[0]{budget}, $q->{rows}[0]{actual} ];
dies_like 'budget needs period', qr/need period/, sub { budget($j) };

# ---- reports
my $bal = report_bal($j, real => 1);
check 'bal text', $bal, <<'EOF';
   1,316.00, 12 AAPL  Assets
             12 AAPL    Brokerage
            1,316.00    Checking
              200.29  Expenses
              135.12    Groceries
               42.17    House:Repairs
               23.00    Pets
           -3,200.00  Income:Salary
             -126.29  Liabilities:Visa
--------------------
  -1,810.00, 12 AAPL
EOF
check 'bal depth', report_bal($j, real => 1, depth => 1, account => qr/^Expenses/), <<'EOF';
              200.29  Expenses
--------------------
              200.29
EOF
check 'bal filtered', report_bal($j, account => qr/Envelope/), <<'EOF';
              515.88  Envelope:Groceries
--------------------
              515.88
EOF
check 'reg text', report_reg($j, account => qr/^Expenses/, period => '2026-09'), <<'EOF';
2026-09-05 Kroger     Expenses:Groceries     84.12  84.12
2026-09-07 Home Depot Expenses:House:Repairs 42.17 126.29
2026-09-15 Vet        Expenses:Pets          23.00 149.29
EOF
check 'budget text', report_budget($j, period => '2026-09'), <<'EOF';
Budget for 2026-09-01 to 2026-10-01 (1 month)
Account             Budget  Actual  Remaining
Expenses:Groceries  600.00   84.12     515.88
Expenses:House      150.00   42.17     107.83
Expenses:Insurance  100.00       0     100.00
Unbudgeted                   23.00           
---------------------------------------------
Total               850.00  149.29     700.71
EOF
check 'csv', to_csv(postings($j, account => qr/Brokerage|Groceries/, real => 1, begin => '2026-09-10')), <<'EOF';
date,status,payee,account,amount,commodity
2026-09-10,,Brokerage,Assets:Brokerage,10,AAPL
2026-09-12,,Brokerage,Assets:Brokerage,2,AAPL
EOF
S 'csv quoting', '"a,\"x\"\"y\",b"', do { my $t = to_csv({ date => 'a', status => '', payee => 'x"y', account => 'b', amount => { '' => 1 } }); ($t =~ /^(a,,"x""y",b)/m)[0] // 'nomatch' } =~ s/,,/,/r;

# ---- CLI
open $fh, '>', "$dir/money.txt" or die $!;
print $fh $journal;
close $fh;
my $bin = "$FindBin::Bin/../bin/ledger.pl";
sub cli { my $out = qx("$^X" "$bin" @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out);
($rc, $out) = cli("-f", "$dir/money.txt", "check");
S 'cli check',     '[0,"ok: 7 transactions, 2 budget entries\n"]', [ $rc, $out ];
($rc, $out) = cli("-f", "$dir/money.txt", "bal", "groceries", "-R");
S 'cli bal regex', 1, ($out =~ /^\s+135\.12  Expenses:Groceries$/m ? 1 : 0);
($rc, $out) = cli("-f", "$dir/money.txt", "budget", "-p", "2026-09");
S 'cli budget',    1, ($out =~ /^Total\s+850\.00\s+149\.29\s+700\.71$/m ? 1 : 0);
($rc, $out) = cli("-f", "$dir/money.txt", "accounts", "^Exp");
S 'cli accounts',  '"Expenses:Groceries\nExpenses:House:Repairs\nExpenses:Pets\n"', $out;
($rc, $out) = cli("-f", "$dir/money.txt", "payees", "--payee", "kro");
S 'cli payees',    '"Kroger\n"', $out;
($rc, $out) = cli("-f", "$dir/money.txt", "reg", "-C", "-b", "2026/09/01", "Assets");
S 'cli reg cleared', '["2026-09-03"]', [ $out =~ /^(\S+)/mg ];
($rc, $out) = cli("-f", "$dir/nope.txt", "bal");
S 'cli missing file', '[1,1]', [ $rc, ($out =~ /cannot open/ ? 1 : 0) ];
($rc, $out) = cli("-f", "$dir/money.txt", "frobnicate");
S 'cli bad command', 2, $rc;
{ local $ENV{LEDGER_FILE} = "$dir/money.txt"; ($rc, $out) = cli("csv", "Pets") }
S 'cli env file',  '"date,status,payee,account,amount,commodity\n2026-09-15,,Vet,Expenses:Pets,23,\n"', $out;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
