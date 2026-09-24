#!/usr/bin/perl
# Calendar CLI.  --mock FILE runs against a captured fixture instead of Outlook.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();
use Calendar;

my %o = (minutes => 15);
GetOptionsFromArray(\@ARGV, 'mock=s' => \$o{mock}, 'date=s' => \$o{date}, 'from=s' => \$o{from}, 'to=s' => \$o{to}, 'match=s' => \$o{match},
    'file=s' => \$o{file}, 'text=s' => \$o{text}, 'send' => \$o{send}, 'replace' => \$o{replace}, 'csv=s' => \$o{csv}, 'team=s' => \$o{team},
    'subject=s' => \$o{subject}, 'start=s' => \$o{start}, 'minutes=i' => \$o{minutes}, 'attendee=s@' => \$o{attendees}, 'location=s' => \$o{location}, 'weekdays' => \$o{weekdays}, 'no-display' => \$o{nodisplay}) or exit 2;
my $cmd = shift @ARGV // 'list';
my $cal = $o{mock} ? Calendar->new(backend => 'mock', fixture => $o{mock}) : Calendar->new;
my %f;
$f{from} = $o{from} // $o{date} if $o{from} || $o{date};
$f{to}   = $o{to}   // $o{date} if $o{to}   || $o{date};
$f{match} = qr/$o{match}/i if defined $o{match};

if ($cmd eq 'list') {
    for my $e ($cal->events(%f)) {
        printf "%s %s-%s  %-40s %s%s  [%d attendees]\n", substr($e->{start}, 0, 10), substr($e->{start}, 11, 5), substr($e->{end}, 11, 5), $e->{subject},
            $e->{teams} ? 'Teams' : '', $e->{recurring} ? ' recurring' : '', scalar @{ $e->{attendees} };
    }
}
elsif ($cmd eq 'dump')   { print JSON::PP->new->pretty->canonical->encode([ $cal->events(%f) ]) }
elsif ($cmd eq 'attend') {
    my @ev = $cal->events(%f, ($ARGV[0] ? (match => qr/$ARGV[0]/i) : ()));
    print "no matching events\n" unless @ev;
    for my $e (@ev) {
        print $cal->attendance_text($e);
        printf "  logged %d rows to %s\n", $cal->log_attendance($o{csv}, $o{date} // substr($e->{start}, 0, 10), $o{team} // ($cal->team_for($e) // '?'), $e), $o{csv} if $o{csv};
    }
}
elsif ($cmd eq 'lines')  { print $cal->standup_lines($_) for $cal->events(%f, ($ARGV[0] ? (match => qr/$ARGV[0]/i) : ())) }
elsif ($cmd eq 'post') {
    my $key = shift @ARGV or die "post needs an event id or subject pattern\n";
    my $text = defined $o{text} ? $o{text} : do { my $f = $o{file} // '-'; open my $fh, '<', $f or die "cannot open $f: $!\n"; local $/; <$fh> };
    my $ev = $cal->find($key, %f) or die "no event matching '$key'\n";
    $cal->post_text($ev, $text, send => $o{send}, replace => $o{replace});
    printf "posted %d chars to '%s' at %s%s\n", length $text, $ev->{subject}, $ev->{start}, $o{send} ? ' (update sent)' : ' (saved)';
}
elsif ($cmd eq 'create') {
    my $id = $cal->create(subject => $o{subject}, start => $o{start}, minutes => $o{minutes}, attendees => $o{attendees}, location => $o{location}, weekdays => $o{weekdays},
                          display => !$o{nodisplay}, body => defined $o{text} ? $o{text} : '');
    print "created $id\n";
}
elsif ($cmd eq 'ps') { print $ARGV[0] && $ARGV[0] eq 'post' ? Calendar::ps_post_text('ID', '2026-01-01T09:00', 'TEXT') : Calendar::ps_list_events($f{from} // '2026-01-01', $f{to} // '2026-01-01') }
else { print STDERR "commands: list dump attend [match] lines [match] post <id|match> [--file f|--text t] [--send] create --subject --start [--attendee a]... [--weekdays] ps\n"; exit 2 }
if ($o{mock} && $cal->actions) { print "mock actions:\n"; printf "  %s %s\n", $_->{action}, $_->{id} // $_->{subject} for $cal->actions }
