#!/usr/bin/perl
# Stand-in for curl, for tests/gitlab.t (like tests/fake-ps.pl for powershell.exe): records each request as one JSON
# line in $FAKE_CURL_LOG ({method, url, headers, body, upload, output}) and answers from $FAKE_CURL_RESPONSES, a file of
# blocks separated by "----" lines:
#     METHOD URL-REGEX
#     STATUS
#     Header: value          (any number, then a blank line)
#     BODY
# The first block whose method and regex match the request answers it (blocks are reused). No match: 200 and {}.
# -D - prints the status line and headers before the body, -o FILE writes the body there, -f exits 22 on 4xx/5xx.
use strict;
use warnings;
use JSON::PP;
my (%o, @h);
my ($method, $url) = ('GET');
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '-X') { $method = shift @ARGV }
    elsif ($a eq '-H') { push @h, shift @ARGV }
    elsif ($a eq '-D') { $o{dump} = shift @ARGV }
    elsif ($a eq '-o') { $o{out} = shift @ARGV }
    elsif ($a eq '--data-binary') { my $f = shift @ARGV; $f =~ s/^@//; open my $fh, '<:raw', $f or die "fake-curl: $f: $!\n"; local $/; $o{body} = <$fh>; $method = 'POST' if $method eq 'GET' }
    elsif ($a eq '--upload-file' || $a eq '-T') { $o{upload} = shift @ARGV; $method = 'PUT' if $method eq 'GET' }
    elsif ($a eq '-f') { $o{fail} = 1 }
    elsif ($a =~ /^-/) { }
    else { $url = $a }
}
if ($ENV{FAKE_CURL_LOG}) {
    open my $l, '>>:raw', $ENV{FAKE_CURL_LOG} or die;
    print $l JSON::PP->new->canonical->encode({ method => $method, url => $url, headers => \@h, body => $o{body}, upload => $o{upload}, output => $o{out} }), "\n";
    close $l;
}
my ($status, $hdr, $body) = (200, '', '{}');
if ($ENV{FAKE_CURL_RESPONSES} && open my $r, '<:raw', $ENV{FAKE_CURL_RESPONSES}) {
    local $/; my $all = <$r>; close $r;
    for my $b (split /^----\s*$/m, $all) {
        $b =~ s/^\s*\n//;
        my ($first, $st, $rest) = $b =~ /^(\S+ \S+)\n(\d+)\n(.*)$/s or next;
        my ($m, $re) = split ' ', $first, 2;
        next unless $m eq $method && $url =~ /$re/;
        my @l = split /\n/, $rest, -1;
        my @hl; push @hl, shift @l while @l && length $l[0];
        shift @l;
        ($status, $hdr, $body) = ($st, join("\n", @hl), join("\n", @l));
        $body =~ s/\n+$//;
        last;
    }
}
if (defined $o{dump} && $o{dump} eq '-') { print "HTTP/1.1 $status X\r\n", (map { "$_\r\n" } grep { length } split /\n/, $hdr), "\r\n" }
if ($o{out}) { open my $f, '>:raw', $o{out} or die; print $f $body; close $f } else { print $body }
exit($o{fail} && $status >= 400 ? 22 : 0);
