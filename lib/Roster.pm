package Roster;
# The people file: roster.txt in the project directory -- one line per person, pipe-separated:
#
#     # name                 | email                        | team     | role            | org
#     Archer, Sam            | sam.archer@example.com         | Alpha | Solutions Architect | ACME
#     Ann Lee                | ann.lee@example.com          | Alpha    | Lead             | ACME
#
# The name is the display name as Teams shows it in the meeting chat (that is what the parsers see); the team is the
# journal's team; role and org are free text. The old two-field form "Name, email" still reads. Everything that needs
# people reads this file: 1:1 chat links (cards, lint --private, propose --private), the meeting invite (daily.pl
# invite), the roster check (daily.pl roster), and the console's roster pane. Kept next to scrum.conf, in the
# project's git repo, so it is part of the record.
use strict;
use warnings;
use Prelude qw(sorted nub);
use Scrum qw(members);

our @EXPORT;
our @FIELDS = qw(name email team role org);
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Roster: unknown function '$n'\n" unless defined &{"Roster::$n"};
        *{"${caller}::$n"} = \&{"Roster::$n"};
    }
}

sub read_roster {                             # read_roster($file) -> [ { name, email, team, role, org, line } ]  (missing file: empty list)
    my $file = shift;
    open my $fh, '<:encoding(UTF-8)', $file or return [];
    my @r;
    while (my $l = <$fh>) {
        chomp $l; $l =~ s/^\x{FEFF}//; next if $l =~ /^\s*(#|$)/;
        my @f = $l =~ /\|/ ? split(/\s*\|\s*/, $l, 5) : split(/\s*,\s*/, $l, 5);   # "a | b | c" or the old "Name, email"
        s/^\s+|\s+$//g for @f;
        next unless $f[0];
        push @r, { name => $f[0], email => $f[1] // '', team => $f[2] // '', role => $f[3] // '', org => $f[4] // '', line => $. };
    }
    close $fh;
    \@r;
}
sub write_roster {                            # write_roster($file, \@people): aligned columns, one header comment; sorted by team then name
    my ($file, $people) = @_;
    my @p = sort { ($a->{team} // '') cmp ($b->{team} // '') || $a->{name} cmp $b->{name} } @$people;
    my @w = map { my $k = $_; my $m = length $k; for (@p) { $m = length $_->{$k} if length($_->{$k} // '') > $m } $m } @FIELDS;
    open my $fh, '>:encoding(UTF-8)', $file or die "cannot write $file: $!\n";
    print $fh '# ', join(' | ', map { sprintf "%-*s", $w[$_], $FIELDS[$_] } 0 .. $#FIELDS), "\n";
    for my $x (@p) { print $fh '  ', join(' | ', map { sprintf "%-*s", $w[$_], $x->{ $FIELDS[$_] } // '' } 0 .. $#FIELDS), "\n" }
    close $fh;
    scalar @p;
}
sub emails { my $r = shift; +{ map { $_->{name} => $_->{email} } grep { $_->{email} =~ /@/ } @$r } }   # name -> email
sub by_team { my $r = shift; my %t; push @{ $t{ $_->{team} || '?' } }, $_ for @$r; \%t }

sub roster_check {                                   # check($s, \@roster) -> list of { level => warn|info, text }: roster vs journal owners, and the fields a feature needs
    my ($s, $r) = @_;
    my @p;
    my %ros = map { $_->{name} => $_ } @$r;
    my $m = members($s);
    for my $who (sorted(keys %$m)) {
        if (!$ros{$who}) { push @p, { level => 'warn', text => "$who owns tasks in the journal but is not in roster.txt (name must match the Teams display name)" }; next }
        push @p, { level => 'warn', text => "$who: roster team '$ros{$who}{team}' differs from the journal's '$m->{$who}{team}'" } if $ros{$who}{team} && ($m->{$who}{team} // '') && $ros{$who}{team} ne $m->{$who}{team};
    }
    for my $x (@$r) {
        push @p, { level => 'info', text => "$x->{name} is in roster.txt but owns no task in the journal" . ($x->{role} =~ /lead|architect|manager|owner/i ? " (fine for a $x->{role})" : '') } unless $m->{ $x->{name} };
        push @p, { level => 'warn', text => "$x->{name}: no e-mail (1:1 links and the invite will skip them)" } unless $x->{email} =~ /@/;
        push @p, { level => 'info', text => "$x->{name}: no team" } unless $x->{team};
    }
    my %seen; for my $x (@$r) { push @p, { level => 'warn', text => "$x->{name} appears twice (lines $seen{$x->{name}} and $x->{line})" } if $seen{ $x->{name} }; $seen{ $x->{name} } //= $x->{line} }
    @p;
}
sub roster_text {                             # the listing: by team, with role and org
    my $r = shift;
    my $bt = by_team($r);
    my $out = '';
    for my $t (sorted(keys %$bt)) {
        $out .= "== $t (" . scalar(@{ $bt->{$t} }) . ")\n";
        $out .= sprintf("  %-26s %-34s %-22s %s\n", $_->{name}, $_->{email} || '-', $_->{role} || '-', $_->{org} || '-') for sort { $a->{name} cmp $b->{name} } @{ $bt->{$t} };
    }
    $out;
}
@EXPORT = qw(read_roster write_roster emails by_team roster_check roster_text);
1;
