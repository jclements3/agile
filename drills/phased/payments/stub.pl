# phased-payments: your solution, grown phase by phase (perl drills/drill.pl phased test N --scenario payments)
#
# ASSUME: (write your answers to the five questions here, one line each)
#
# A decomposition that survives the changes: write these as separate subs, now.
#   close_enough($order, $payment, %opt)   the same purchase?
#   validate($orders, $payments)           can these inputs be matched at all? (a reason, or nothing)
#   pair($orders, $payments, %opt) -> (\@matches, \@unmatched_orders, \@unmatched_payments)
# Put the things that will move (tolerances) in %opt with defaults.
use strict;
use warnings;

sub solve {
    my ($orders, $payments, %opt) = @_;
    # your code here
    return { pairs => [], unpaired_a => [], unpaired_b => [], ok => 0, reason => 'todo' };
}

1;
