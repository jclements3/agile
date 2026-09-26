#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
binmode $_, ':encoding(UTF-8)' for \*STDOUT, \*STDERR;
use Ledger ();
exit Ledger::run(@ARGV);
