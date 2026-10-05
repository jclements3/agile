#!/usr/bin/perl
# status-metrics.pl -- the 26 status metrics (A-Z) of docs/STATUS-METRICS.html: init / collect / report (lib/StatusMetrics.pm)
#
#   perl bin/status-metrics.pl init    --config metrics.json --xmi legacy.xmi --reqif export.reqif   # once
#   perl bin/status-metrics.pl collect --config metrics.json --history history.jsonl                # daily
#   perl bin/status-metrics.pl report  --config metrics.json --history history.jsonl --out report   # any time
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use StatusMetrics ();
exit StatusMetrics::run(@ARGV);
