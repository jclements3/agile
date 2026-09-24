#!/usr/bin/perl
# agile.pl -- the app entry point, beside dashboard.html.
#
#   perl agile.pl [PROJECT]            rebuild PROJECT's reports (daily.pl report), write ./dashboard.html --
#                                      the cockpit -- and open it. PROJECT defaults to data/demo.
#   perl agile.pl serve [PROJECT]      the same page served live on http://127.0.0.1:8090/ : rebuilt from the
#                                      journal on every load, and a "Rebuild reports" button that runs
#                                      daily.pl report. Localhost only, core Perl only. Ctrl-C stops it.
#   perl agile.pl --no-open [PROJECT]  just write the file
#
# The default is the static page: nothing listens, nothing runs in the background, and the page is a
# plain file you can put on a share. Serve mode is a convenience for a second screen.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long;
use Cwd qw(abs_path);
use Scrum;
use Standup qw(read_conf);
use Cockpit;
use Roster ();

my %o = (port => 8090);
GetOptions(\%o, 'no-open', 'port=i', 'today=s') or exit 2;   # --today YYYY-MM-DD: the cockpit's "today" (replays, simulations); default: the real date
my $mode = @ARGV && $ARGV[0] eq 'serve' ? shift @ARGV : 'build';
my $ROOT = abs_path($FindBin::Bin);
my $proj = abs_path(shift @ARGV // "$ROOT/data/demo") // die "no such project directory\n";
-f "$proj/scrum.conf" or die "$proj has no scrum.conf (run daily.pl init there first)\n";
(my $rel = $proj) =~ s{^\Q$ROOT\E/?}{};        # project path relative to the repo root, for links from ./dashboard.html
my $conf = read_conf("$proj/scrum.conf");

sub rebuild_reports { system($^X, "$ROOT/bin/daily.pl", '--conf', "$proj/scrum.conf", ($o{today} ? "--today=$o{today}" : ()), 'report') == 0 or warn "daily.pl report failed\n" }   # same interpreter as this one
sub page {                                     # the cockpit, fresh from the journal, with links that work from where the page lives
    my $base = shift // '';                    # '' for ./dashboard.html (links relative to the repo root), '/' when served
    my $s = load("$proj/$conf->{journal}", today => _today());
    $s->{unit} = $conf->{unit};
    my $plates = -f "$proj/$conf->{reports}/plates.html" ? "$base$rel/$conf->{reports}/plates.html" : undef;
    my %doc = map { $_ => (-f "$ROOT/docs/$_.html" ? "${base}docs/$_.html" : undef) } qw(TUTORIAL TRAINING);
    cockpit_html($s, marking => $conf, days => days_from_standups($s, "$proj/$conf->{standups}", $conf->{history_days}), plates => $plates, plates_file => "$proj/$conf->{reports}/plates.html",
                 tutorial => $doc{TUTORIAL}, training => $doc{TRAINING}, roster => Roster::read_roster("$proj/roster.txt"), readback_clean_days => $conf->{readback_clean_days} // 5);
}
sub _today { $o{today} // do { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] } }
sub open_browser {
    my $target = shift;
    if    ($^O =~ /^(MSWin32|cygwin|msys)$/) { system('powershell.exe', '-NoProfile', '-Command', 'Start-Process', '-FilePath', $target) }
    elsif ($^O eq 'darwin')                  { system('open', $target) }
    else                                      { system('xdg-open', $target) }
}

if ($mode eq 'build') {
    rebuild_reports();
    my $out = "$ROOT/dashboard.html";
    open my $fh, '>:encoding(UTF-8)', $out or die "cannot write $out: $!\n";
    print $fh page('');
    close $fh;
    print "wrote $out (cockpit for $rel)\n";
    open_browser($out) unless $o{'no-open'};
    exit 0;
}

# ---------------------------------------------------------------- serve: a minimal localhost HTTP server, core Perl only
require IO::Socket::INET;
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $o{port}, Proto => 'tcp', Listen => 5, ReuseAddr => 1)
    or die "cannot listen on 127.0.0.1:$o{port}: $@\n";
my $url = "http://127.0.0.1:$o{port}/";
print "serving $rel at $url  (Ctrl-C to stop)\n";
open_browser($url) unless $o{'no-open'};
my %TYPE = (html => 'text/html; charset=utf-8', svg => 'image/svg+xml', css => 'text/css', js => 'text/javascript', json => 'application/json', txt => 'text/plain; charset=utf-8', png => 'image/png', csv => 'text/csv');
while (my $c = $srv->accept) {
    my $req = <$c> // '';
    while (defined(my $l = <$c>)) { last if $l =~ /^\r?\n$/ }     # headers, ignored
    my ($path) = $req =~ m{^GET\s+(\S+)} or do { print $c "HTTP/1.0 400 Bad Request\r\n\r\n"; close $c; next };
    $path =~ s/[?#].*//; $path =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
    my ($status, $type, $body);
    if ($path eq '/' || $path eq '/dashboard.html') { ($status, $type, $body) = ('200 OK', $TYPE{html}, page('/')) }
    elsif ($path eq '/rebuild') { rebuild_reports(); print $c "HTTP/1.0 302 Found\r\nLocation: /\r\nContent-Length: 0\r\n\r\n"; close $c; next }
    elsif ($path !~ m{\.\.} && $path =~ m{^/([\w./-]+)$} && -f "$ROOT/$1" && $1 =~ /\.(\w+)$/ && $TYPE{ lc $1 =~ s/.*\.//r }) {
        my $f = "$ROOT/$1"; my ($ext) = $f =~ /\.(\w+)$/;
        open my $fh, '<:raw', $f or next; local $/; $body = <$fh>; close $fh;
        ($status, $type) = ('200 OK', $TYPE{ lc $ext });
    }
    else { ($status, $type, $body) = ('404 Not Found', 'text/plain', "not found: $path\n") }
    my $bytes = $type =~ /charset/ ? do { utf8::encode(my $b = $body); $b } : $body;
    print $c "HTTP/1.0 $status\r\nContent-Type: $type\r\nContent-Length: " . length($bytes) . "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n$bytes";
    close $c;
}
