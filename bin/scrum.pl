#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
binmode $_, ':encoding(UTF-8)' for \*STDOUT, \*STDERR;
@ARGV = map { Ledger::decode_text($_) } @ARGV;                  # arguments are UTF-8 bytes from the shell: roster add "Zo\x{eb} \x{c5}ngstr\x{f6}m" ...
use Scrum ();
exit Scrum::run(@ARGV);
