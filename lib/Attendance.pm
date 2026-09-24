package Attendance;
# Teams meeting attendance report (Meeting > Attendance > Download, or the Attendance tab in the
# chat after the meeting) -> join time, leave time, duration per person -> attendance.csv rows.
# The download is a tab- or comma-separated text file, sometimes UTF-16; sections are
# "1. Summary", "2. Participants", "3. In-Meeting Activities".  Only "Participants" is used.
use strict;
use warnings;
use Prelude qw(sorted nub sum fmap);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Attendance: unknown function '$n'\n" unless defined &{"Attendance::$n"};
        *{"${caller}::$n"} = \&{"Attendance::$n"};
    }
}

# ---------------------------------------------------------------- reading
sub read_report {                             # -> { title, start, end, participants => [ { name, email, join, leave, minutes, role } ] }
    my $file = shift;
    open my $fh, '<:raw', $file or die "cannot open $file: $!\n";
    my $raw = do { local $/; <$fh> };
    close $fh;
    parse_report(decode_bytes($raw));
}
sub decode_bytes {                            # UTF-16 (with/without BOM) or UTF-8; returns a Perl string
    my $b = shift;
    require Encode;
    return Encode::decode('UTF-16LE', substr($b, 2)) if substr($b, 0, 2) eq "\xFF\xFE";
    return Encode::decode('UTF-16BE', substr($b, 2)) if substr($b, 0, 2) eq "\xFE\xFF";
    return Encode::decode('UTF-16LE', $b) if length($b) > 3 && substr($b, 1, 1) eq "\0" && substr($b, 3, 1) eq "\0";
    (my $u = $b) =~ s/^\xEF\xBB\xBF//;
    Encode::decode('UTF-8', $u);
}
sub parse_report {
    my $text = shift;
    $text =~ s/\r//g;
    my %r = (participants => []);
    my $sep = ($text =~ tr/\t//) > ($text =~ tr/,//) ? "\t" : ',';
    my $section = '';
    my @hdr;
    for my $line (split /\n/, $text) {
        next if $line =~ /^\s*$/;
        if ($line =~ /^\s*\d+\.\s*(Summary|Participants|In-Meeting Activities|Activities)\b/i) { $section = lc $1; @hdr = (); next }
        my @c = map { s/^\s+|\s+$//g; s/^"(.*)"$/$1/; $_ } _split($line, $sep);
        if ($section eq 'summary' || $section eq '') {
            $r{title} = $c[1] if $c[0] =~ /^meeting title$/i;
            $r{start} = $c[1] if $c[0] =~ /^start time$/i;
            $r{end}   = $c[1] if $c[0] =~ /^end time$/i;
            next;
        }
        next unless $section eq 'participants';
        if (!@hdr) { next unless grep { /^name$/i } @c; @hdr = map { lc } @c; next }
        my %row; @row{@hdr} = @c;
        my $name = $row{name} // next;
        next if $name eq '';
        my ($join)  = grep { defined } @row{ grep { /join/ } @hdr };
        my ($leave) = grep { defined } @row{ grep { /leave/ } @hdr };
        my ($dur)   = grep { defined } @row{ grep { /duration/ } @hdr };
        my ($mail)  = grep { defined && /@/ } @row{ grep { /email|upn/ } @hdr };
        push @{ $r{participants} }, { name => $name, email => $mail, join => hm($join), leave => hm($leave), join_raw => $join, leave_raw => $leave,
                                      minutes => minutes($dur), role => $row{role} };
    }
    \%r;
}
sub _split {                                  # split on $sep honouring double quotes
    my ($line, $sep) = @_;
    my @out; my $cur = ''; my $q = 0;
    for my $ch (split //, $line) {
        if ($ch eq '"') { $q = !$q }
        elsif ($ch eq $sep && !$q) { push @out, $cur; $cur = '' }
        else { $cur .= $ch }
    }
    push @out, $cur;
    @out;
}
sub hm {                                      # "9/23/26, 9:00:15 AM" | "2026-09-23T13:05:15" | "09:00" -> "09:00"
    my $t = shift // '';
    return undef unless $t =~ /(?<![\d:])(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*([AaPp])\.?[Mm]\.?)?/;
    my ($h, $m, $ap) = ($1, $2, $3);
    $h += 12 if $ap && lc $ap eq 'p' && $h < 12;
    $h = 0   if $ap && lc $ap eq 'a' && $h == 12;
    sprintf '%02d:%02d', $h, $m;
}
sub minutes {                                 # "1h 2m 3s" | "14m 55s" | "45s" | "0:14:55" -> minutes (float, 1 decimal)
    my $d = shift // '';
    my $s = 0;
    if ($d =~ /^\s*(\d+):(\d+):(\d+)\s*$/) { $s = $1 * 3600 + $2 * 60 + $3 }
    else { $s += $1 * 3600 while $d =~ /(\d+)\s*h/g; $s += $1 * 60 while $d =~ /(\d+)\s*m(?!s)/g; $s += $1 while $d =~ /(\d+)\s*s/g }
    sprintf('%.1f', $s / 60) + 0;
}

# ---------------------------------------------------------------- applying
sub rows {                                    # -> ( [name, status, join, leave, minutes], ... )  status: present | brief (< $min minutes)
    my ($rep, %o) = @_;
    my $min = $o{min_minutes} // 3;
    map { [ $_->{name}, $_->{minutes} >= $min ? 'present' : 'brief', $_->{join}, $_->{leave}, $_->{minutes} ] } @{ $rep->{participants} };
}
sub team_of {                                 # name -> team via journal members; undef if unknown
    my ($s, $name) = @_;
    require Scrum;
    my $m = Scrum::members($s);
    return $m->{$name}{team} if $m->{$name};
    my ($first) = split ' ', $name;
    my @hit = grep { $_ eq $first || index($_, $first) == 0 } keys %$m;     # "Ann Smith" -> "Ann"
    @hit == 1 ? $m->{ $hit[0] }{team} : undef;
}
sub log_report {                              # append to attendance.csv (date,team,name,status[,join,leave,minutes]); idempotent per date+team+name
    my ($path, $date, $rep, %o) = @_;
    my %have;
    if (open my $r, '<', $path) { while (<$r>) { chomp; my @c = split /,/; $have{"$c[0],$c[1],$c[2]"}++ } close $r }
    my $new = !-e $path;
    open my $fh, '>>', $path or die "cannot append $path: $!\n";
    print $fh "date,team,name,status,join,leave,minutes\n" if $new;
    my $n = 0;
    for my $row (rows($rep, %o)) {
        my ($name, $status, $join, $leave, $min) = @$row;
        my $team = $o{team} // ($o{team_of} ? $o{team_of}->($name) : undef) // '?';
        next if $have{ join ',', $date, $team, _csv($name) }++;
        print $fh join(',', $date, $team, _csv($name), $status, $join // '', $leave // '', $min), "\n"; $n++;
    }
    close $fh;
    $n;
}
sub report_text {
    my $rep = shift;
    my $out = ($rep->{title} ? "$rep->{title}  " : '') . ($rep->{start} ? "$rep->{start} - $rep->{end}\n" : "\n");
    $out .= sprintf("  %-22s %5s  %5s  %5s min\n", $_->{name}, $_->{join} // '', $_->{leave} // '', $_->{minutes}) for sort { ($a->{join} // '') cmp ($b->{join} // '') } @{ $rep->{participants} };
    $out;
}
sub _csv { my $s = shift; $s =~ /[",\n]/ ? '"' . ($s =~ s/"/""/gr) . '"' : $s }

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Attendance::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Attendance::$_"} == \&{"Prelude::$_"})
    } keys %Attendance::;
}

1;

__END__

=head1 NAME

Attendance - join/leave/duration from a downloaded Teams attendance report

=head1 SYNOPSIS

    # after the meeting: Teams > the meeting chat > Attendance tab > Download (or Meeting > People > Download attendance list)
    # save as standups/<date>-<Team>-attendance.csv   (one joint meeting for all teams: standups/<date>-attendance.csv)
    daily.pl joined                     # parses every attendance file for today into attendance.csv, prints join/leave
    perl -Ilib -MAttendance -e 'print report_text(read_report(shift))' file.csv

=head1 WHY A DOWNLOAD

Join and leave times are not on the calendar item and not in the chat; they exist only in the
attendance report the organiser can download from the meeting. That download is a manual click
per meeting, then everything is parsed. The file is tab- or comma-separated, often UTF-16; both
are handled. Rows land in attendance.csv as C<date,team,name,status,join,leave,minutes> with
status C<present> (E<gt>= 3 minutes, configurable) or C<brief>. Names are mapped to teams via
the journal's owners; unknown names get team C<?> and are listed for you to fix.

=head1 FUNCTIONS

    $rep = read_report($file)            # { title, start, end, participants => [ { name, email, join, leave, minutes, role } ] }
    $rep = parse_report($text)
    @rows = rows($rep, min_minutes => 3)
    $n = log_report('attendance.csv', $date, $rep, team => 'Alpha')        # or team_of => sub { ... }
    print report_text($rep)
    hm('9/23/26, 1:05:10 PM')  # '13:05'      minutes('1h 2m 3s')  # 62.1

=head1 SEE ALSO

L<Calendar>, L<Answers>, C<bin/daily.pl joined>.

=cut
