package Calendar;
# Outlook / Teams calendar from Git Bash Perl: list stand-up meetings, read attendee responses,
# post metrics into a meeting body, create meetings.  Real work goes through PowerShell +
# Outlook COM (Teams calendar == the Exchange calendar Outlook shows).  A mock backend runs the
# same code paths against fixture data so everything above the COM layer is testable offline.
use strict;
use warnings;
use JSON::PP ();
use MIME::Base64 qw(encode_base64);
use Encode qw(encode);
use Prelude qw(sorted classify fmap);
our $VERSION = '0.90';

my %RESPONSE = (0 => 'none', 1 => 'organizer', 2 => 'tentative', 3 => 'accepted', 4 => 'declined', 5 => 'no response');

# ---------------------------------------------------------------- construction
# Calendar->new(backend => 'outlook')                      real Outlook via powershell.exe
# Calendar->new(backend => 'mock', events => [...])        fixture events (same shape as the JSON below)
# Calendar->new(backend => 'mock', fixture => 'cal.json')  fixture from a file (e.g. one captured with `cal.pl dump`)
sub new {
    my ($class, %o) = @_;
    my $self = bless { backend => $o{backend} // 'outlook', log => [], ps_cmd => $o{ps_cmd} // [ 'powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand' ] }, $class;
    if ($self->{backend} eq 'mock') {
        my $ev = $o{events};
        if ($o{fixture}) { open my $fh, '<:encoding(UTF-8)', $o{fixture} or die "cannot open $o{fixture}: $!\n"; local $/; $ev = JSON::PP->new->decode(<$fh>); close $fh }
        $self->{events} = [ map { _norm_event($_) } @{ $ev // [] } ];
    }
    $self;
}
sub backend { $_[0]{backend} }
sub actions { @{ $_[0]{log} } }             # mock: what would have been done (post/create/send)

# ---------------------------------------------------------------- events
# event = { id, subject, start => 'YYYY-MM-DDTHH:MM:SS', end, location, organizer, teams => 0|1, recurring => 0|1,
#           body, attendees => [ { name, email, type => 'required'|'optional'|'resource', response => 'accepted'|... } ] }
sub events {                                 # events(from => 'YYYY-MM-DD', to => 'YYYY-MM-DD', match => qr//)
    my ($self, %f) = @_;
    my $from = $f{from} // _today();
    my $to   = $f{to}   // $from;
    my @ev = $self->{backend} eq 'mock'
      ? @{ $self->{events} }
      : map { _norm_event($_) } @{ $self->_run_json(ps_list_events($from, $to)) };
    @ev = grep { substr($_->{start}, 0, 10) ge $from && substr($_->{start}, 0, 10) le $to } @ev;
    @ev = grep { $_->{subject} =~ $f{match} } @ev if $f{match};
    sort { $a->{start} cmp $b->{start} } @ev;
}
sub today   { my ($self, %f) = @_; $self->events(%f, from => $f{date} // _today(), to => $f{date} // _today()) }
sub find    { my ($self, $key, %f) = @_;    # by id, or first subject match (regex, case-insensitive)
    my @ev = $self->events(%f);
    my ($byid) = grep { $_->{id} eq $key } @ev;
    return $byid if $byid;
    (grep { $_->{subject} =~ /$key/i } @ev)[0];
}

# ---------------------------------------------------------------- attendance
sub attendance {                             # -> { accepted => [names], tentative, declined, 'no response', organizer, none, all => n }
    my ($self, $ev) = @_;
    my $by = classify(sub { $_[0]{response} }, grep { ($_->{type} // '') ne 'resource' } @{ $ev->{attendees} });
    my %a = map { $_ => [ sorted(fmap(sub { $_[0]{name} }, @{ $by->{$_} // [] })) ] } values %RESPONSE;
    $a{all} = scalar grep { ($_->{type} // '') ne 'resource' } @{ $ev->{attendees} };
    \%a;
}
sub attendance_text {                        # one line per status, for the stand-up file or a report
    my ($self, $ev) = @_;
    my $a = $self->attendance($ev);
    my $out = sprintf "%s  %s  (%d invited)\n", substr($ev->{start}, 11, 5), $ev->{subject}, $a->{all};
    for my $k ('accepted', 'tentative', 'declined', 'no response') { $out .= sprintf("  %-12s %s\n", "$k:", join(', ', @{ $a->{$k} })) if @{ $a->{$k} } }
    $out;
}
sub standup_lines {                          # comment block + suggested 'absent' lines for Standup.pm (uncomment to confirm)
    my ($self, $ev) = @_;
    my $a = $self->attendance($ev);
    my $t = join '', map { "; $_" } split /^/m, $self->attendance_text($ev);
    $t . join('', map { "; absent $_   ; declined in calendar\n" } @{ $a->{declined} });
}
sub log_attendance {                         # append to CSV: date,team,name,status ; idempotent per date+team+name ; returns rows written
    my ($self, $path, $date, $team, $ev) = @_;
    my $a = $self->attendance($ev);
    log_rows($path, $date, $team, map { my $k = $_; map { [ $_, $k ] } @{ $a->{$k} } } 'accepted', 'tentative', 'declined', 'no response', 'none');
}
sub log_rows {                                # log_rows($csv, $date, $team, [name, status], ...) ; same idempotence
    my ($path, $date, $team, @rows) = @_;
    my %have;
    if (open my $r, '<', $path) { while (<$r>) { chomp; my @c = split /,/; $have{"$c[0],$c[1],$c[2]"}++ } close $r }
    my $new = !-e $path;
    open my $fh, '>>', $path or die "cannot append $path: $!\n";
    print $fh "date,team,name,status\n" if $new;
    my $n = 0;
    for my $row (@rows) {
        my ($name, $k) = @$row;
        next if $have{ join ',', $date, $team, _csv($name) }++;
        print $fh join(',', $date, $team, _csv($name), $k), "\n"; $n++;
    }
    close $fh;
    $n;
}
sub team_for {                               # team name from the subject: conf team_from_subject regex (capture 1) or a known team name
    my ($self, $ev, $conf, $teams) = @_;
    if ($conf && $conf->{team_from_subject}) { return $1 if $ev->{subject} =~ /$conf->{team_from_subject}/i }
    for my $t (@{ $teams // [] }) { return $t if $ev->{subject} =~ /\b\Q$t\E\b/i }
    undef;
}

# ---------------------------------------------------------------- writing
sub post_text {                              # append text to the meeting body (this occurrence); send => 1 sends the update to attendees
    my ($self, $ev, $text, %o) = @_;
    my $rec = { action => 'post', id => $ev->{id}, start => $ev->{start}, text => $text, send => $o{send} ? 1 : 0, replace => $o{replace} ? 1 : 0 };
    push @{ $self->{log} }, $rec;
    if ($self->{backend} eq 'mock') { $ev->{body} = ($o{replace} ? '' : ($ev->{body} // '') . "\n") . $text; return 1 }
    $self->_run_json(ps_post_text($ev->{id}, $ev->{start}, $text, %o))->{ok};
}
sub create {                                 # create(subject =>, start => 'YYYY-MM-DDTHH:MM', minutes => 15, attendees => [emails], body =>, location =>, weekdays => 1, display => 1)
    my ($self, %o) = @_;
    die "create: need subject and start\n" unless $o{subject} && $o{start};
    push @{ $self->{log} }, { action => 'create', %o };
    if ($self->{backend} eq 'mock') {
        my $ev = _norm_event({ id => 'mock-' . scalar(@{ $self->{events} }), subject => $o{subject}, start => "$o{start}:00", body => $o{body} // '',
                               location => $o{location} // '',
                               attendees => [ map { { name => $_, email => $_, type => 'required', response => 5 } } @{ $o{attendees} // [] } ], recurring => $o{weekdays} ? 1 : 0 });
        push @{ $self->{events} }, $ev;
        return $ev->{id};
    }
    $self->_run_json(ps_create($self, %o))->{id};
}

# ---------------------------------------------------------------- PowerShell builders (pure functions; inspect in tests)
my $PS_HEAD = <<'PS';
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$ol = New-Object -ComObject Outlook.Application
$ns = $ol.GetNamespace('MAPI')
$cal = $ns.GetDefaultFolder(9)
PS
sub _fill { my ($tpl, %v) = @_; $tpl =~ s/__(\w+)__/$v{$1} \/\/ ''/ge; $PS_HEAD . $tpl }
sub ps_list_events {
    my ($from, $to) = @_;
    _fill(<<'PS', FROM => _psdate($from, '00:00'), TO => _psdate($to, '23:59'));
$items = $cal.Items
$items.IncludeRecurrences = $true
$items.Sort('[Start]')
$r = $items.Restrict("[Start] >= '__FROM__' AND [Start] <= '__TO__'")
$out = @()
foreach ($a in $r) {
  $att = @()
  foreach ($rc in $a.Recipients) { $att += @{ name = $rc.Name; email = $rc.Address; type = $rc.Type; response = $rc.MeetingResponseStatus } }
  $out += @{ id = $a.EntryID; subject = $a.Subject; start = $a.Start.ToString('s'); end = $a.End.ToString('s'); location = $a.Location;
             organizer = $a.Organizer; recurring = $a.IsRecurring; teams = [bool]($a.Body -match 'teams\.microsoft\.com'); body = $a.Body; attendees = $att }
}
ConvertTo-Json -InputObject @($out) -Depth 5 -Compress
PS
}
sub ps_post_text {
    my ($id, $start, $text, %o) = @_;
    my $q = _psq($text);
    _fill(<<'PS', ID => _psq($id), START => $start, MODE => ($o{replace} ? "\$a.Body = $q" : "\$a.Body = \$a.Body + \"`r`n\" + $q"), FINISH => ($o{send} ? '$a.Send()' : '$a.Save()'));
$a = $ns.GetItemFromID(__ID__)
if ($a.IsRecurring) { $a = $a.GetRecurrencePattern().GetOccurrence([datetime]'__START__') }
__MODE__
__FINISH__
ConvertTo-Json -InputObject @{ ok = $true; id = $a.EntryID } -Compress
PS
}
sub ps_create {
    my ($self, %o) = @_;
    my $rec   = join "\n", map { "\$a.Recipients.Add(" . _psq($_) . ") | Out-Null" } @{ $o{attendees} // [] };
    my $recur = $o{weekdays} ? "\$p = \$a.GetRecurrencePattern(); \$p.RecurrenceType = 1; \$p.DayOfWeekMask = 62; \$p.PatternStartDate = [datetime]'$o{start}'" : '';
    _fill(<<'PS', SUBJECT => _psq($o{subject}), START => $o{start}, MINUTES => $o{minutes} // 15, BODY => _psq($o{body} // ''), LOCATION => _psq($o{location} // ''), REC => $rec, RECUR => $recur, SHOW => (($o{display} // 1) ? '$a.Display()' : '$a.Save()'));
$a = $ol.CreateItem(1)
$a.Subject = __SUBJECT__
$a.Start = [datetime]'__START__'
$a.Duration = __MINUTES__
$a.MeetingStatus = 1
$a.Body = __BODY__
$a.Location = __LOCATION__
__REC__
__RECUR__
__SHOW__
ConvertTo-Json -InputObject @{ ok = $true; id = $a.EntryID } -Compress
PS
}
sub ps_encode { encode_base64(encode('UTF-16LE', $_[0]), '') }   # what -EncodedCommand wants

# ---------------------------------------------------------------- runner
sub _run_json {
    my ($self, $script) = @_;
    my @cmd = (@{ $self->{ps_cmd} }, ps_encode($script));
    open my $ph, '-|', @cmd or die "cannot run $cmd[0]: $!\n";
    my $out = do { local $/; <$ph> };
    close $ph;
    my $rc = $? >> 8;
    die "powershell failed (rc=$rc): " . substr($out // '', 0, 500) . "\n" if $rc;
    $out =~ s/^\x{FEFF}//; $out =~ s/^[^\[{]*//s;     # strip BOM / chatter before the JSON
    my $data = eval { JSON::PP->new->utf8->decode($out) };
    die "bad JSON from PowerShell: $@" . substr($out, 0, 300) . "\n" unless defined $data;
    $data;
}

# ---------------------------------------------------------------- helpers
sub _norm_event {
    my $e = shift;
    my %n = %$e;
    $n{start}    = _isodt($n{start} // '');
    $n{end}      = _isodt($n{end} // '');
    $n{teams}    = ($n{teams} || ($n{body} // '') =~ /teams\.microsoft\.com/ || ($n{location} // '') =~ /teams/i) ? 1 : 0;
    $n{recurring} = $n{recurring} ? 1 : 0;
    $n{body}   //= '';
    $n{attendees} = [ map {
        my %a = %$_;
        my $r = $a{response}; $r = 'none' unless defined $r; $r = $RESPONSE{$r} // $r if $r =~ /^\d$/;
        my $t = $a{type};     $t = 'required' unless defined $t; $t = { 1 => 'required', 2 => 'optional', 3 => 'resource' }->{$t} // $t if $t =~ /^\d$/;
        @a{qw(response type)} = ($r, $t);
        \%a;
    } @{ $n{attendees} // [] } ];
    \%n;
}
sub _isodt  { my $d = shift; $d =~ s{^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(?::(\d{2}))?.*$}{ "$1T$2:" . ($3 // '00') }e; $d }
sub _psdate { my ($ymd, $hm) = @_; my ($y, $m, $d) = split /-/, $ymd; sprintf '%02d/%02d/%04d %s', $m, $d, $y, $hm }   # en-US Restrict format
sub _psq    { my $s = shift // ''; $s =~ s/'/''/g; "'$s'" }
sub _csv    { my $s = shift; $s =~ /[",\n]/ ? '"' . ($s =~ s/"/""/gr) . '"' : $s }
sub _today  { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }

1;

__END__

=head1 NAME

Calendar - Outlook/Teams calendar for the stand-up battle rhythm (PowerShell COM, mockable)

=head1 STATUS

Interface and offline behaviour are tested; the Outlook COM layer is not yet
verified on a real machine. First thing to run on the laptop:

    perl bin/cal.pl list                     # today's events as JSON-ish text; proves COM + JSON round trip
    perl bin/cal.pl dump > cal-fixture.json  # capture real events for offline tests
    perl bin/cal.pl attend "stand"           # attendee responses for today's stand-ups

Things most likely to need adjusting after that test, all in one place at the
bottom of this file: C<_psdate> (Outlook's C<Restrict> wants dates in the
machine's locale format; en-US is assumed), and the C<teams> detection (the
body of a Teams meeting contains a teams.microsoft.com link; new-style joins
may differ).

=head1 SYNOPSIS

    use Calendar;
    my $cal = Calendar->new;                              # real Outlook
    my $cal = Calendar->new(backend => 'mock', fixture => 'cal-fixture.json');   # offline

    my @ev = $cal->today(match => qr/stand-?up/i);
    for my $ev (@ev) {
        print $cal->attendance_text($ev);                 # accepted/tentative/declined/no response by name
        $cal->log_attendance('attendance.csv', '2026-09-23', 'Alpha', $ev);
        $cal->post_text($ev, $metrics_text);              # appended to the meeting body, saved (send => 1 to update attendees)
    }
    $cal->create(subject => 'Alpha Stand-up', start => '2026-10-01T09:00', minutes => 15,
                 attendees => ['ann@x.example', 'bob@x.example'], weekdays => 1, body => 'Daily.');

C<bin/daily.pl attend> pulls today's stand-up meetings, appends attendance
comments and suggested C<absent> lines to today's stand-up file, and logs to
C<attendance.csv>. C<bin/daily.pl post> puts today's metrics text into each
stand-up meeting's body.

=head1 HOW IT REACHES OUTLOOK

C<powershell.exe -EncodedCommand> with a generated script (base64 UTF-16LE, so
no quoting problems and no script-file execution policy involved). The script
uses C<Outlook.Application> COM: default calendar folder, C<Items.Restrict> on
the date range with C<IncludeRecurrences>, C<Recipients.MeetingResponseStatus>
for attendance, C<GetItemFromID> + C<GetOccurrence> to write into one
occurrence of a recurring meeting, C<ConvertTo-Json> back to Perl. Outlook must
be installed and configured; the Teams calendar is the same Exchange calendar.

Limits of COM: creating a meeting cannot attach a Teams link by itself. C<create>
opens the invite (C<display => 1>) so you press the Teams Meeting button and
Send; with Outlook's "add online meeting to all meetings" setting on, it is
automatic. Appointment bodies are plain text through COM (no HTML), so metrics
are posted as the text report.

=head1 EVENT SHAPE

    { id, subject, start => '2026-09-23T09:00:00', end, location, organizer, teams => 0|1, recurring => 0|1, body,
      attendees => [ { name, email, type => required|optional|resource, response => accepted|tentative|declined|'no response'|organizer|none } ] }

The mock backend accepts the same shape with Outlook's numeric codes too (type
1/2/3, response 0-5), which is what C<dump> captures.

=head1 METHODS

    new(backend => 'outlook'|'mock', events => [...], fixture => $file)
    events(from =>, to =>, match => qr//)   today(date =>, match =>)   find($id_or_subject_regex, %f)
    attendance($ev)   attendance_text($ev)   standup_lines($ev)   log_attendance($csv, $date, $team, $ev)
    team_for($ev, $conf, \@teams)          # conf key team_from_subject = ^(\w+) stand
    post_text($ev, $text, send => 0|1, replace => 0|1)   create(%spec)
    ps_list_events($from, $to)  ps_post_text($id, $start, $text, %o)  ps_create($self, %spec)  ps_encode($script)
    actions()                               # mock: recorded post/create calls

=head1 SEE ALSO

L<Standup>, L<Scrum>, C<bin/cal.pl>, C<bin/daily.pl>.

=cut
