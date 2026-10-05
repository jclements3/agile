#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
binmode $_, ':encoding(UTF-8)' for \*STDOUT, \*STDERR;
@ARGV = map { Ledger::decode_text($_) } @ARGV;                  # arguments are UTF-8 bytes from the shell: roster add "Zo\x{eb} \x{c5}ngstr\x{f6}m" ...
if (@ARGV && $ARGV[0] =~ /^(?:help|--help|-h)$/) { require Help; exit Help::tool_cli('ledger', @ARGV) }   # the help section from vim/doc/agile.txt
use Ledger ();
exit Ledger::run(@ARGV);
