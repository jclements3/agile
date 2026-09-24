package Chat;
# Pasted Teams meeting chat -> rounds of estimates / votes -> tallies and stand-up lines.
# Meeting chat has no simple API path from a plain workstation; select-all + copy in the Teams
# chat pane, paste into standups/<date>-chat.txt, run `daily.pl chat`.  The parser accepts the
# copy formats Teams has used and a plain "Name: message" fallback.
use strict;
use warnings;
use Prelude qw(sorted nub sum fmap classify sortOn maximum minimum);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Chat: unknown function '$n'\n" unless defined &{"Chat::$n"};
        *{"${caller}::$n"} = \&{"Chat::$n"};
    }
}

# ---------------------------------------------------------------- parsing
# message = { who, time => 'HH:MM' | undef, text }
my $TIME = qr/(?:\d{1,2}\/\d{1,2}(?:\/\d{2,4})?,?\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?/;
my $NAME = qr/[^\[\]\t:#]{1,60}?/;
my $PLAIN = qr/[A-Za-z][A-Za-z.'-]*(?:\s[A-Za-z][A-Za-z.'-]*){0,2}/;      # "Ann: 5" fallback: 1-3 words, letters only

sub parse_chat {
    my $text = shift;
    my @msgs;
    my $cur;
    my $flush = sub { push @msgs, $cur if $cur && $cur->{text} =~ /\S/; $cur = undef };
    my $ln = 0;
    for my $raw (split /\r?\n/, $text) {
        $ln++;
        (my $line = $raw) =~ s/\s+$//;
        next if $line =~ /^\s*$/ && !$cur;
        my $hdr;
        if    ($line =~ /^\s*\[$TIME\]\s*($NAME)\s*$/)                       { $hdr = [ $4, _hm($1, $2, $3) ] }   # [9:05 AM] Ann Smith
        elsif ($line =~ /^\s*($NAME)(?:\s{2,}|\t|\s+)$TIME\s*$/)               { $hdr = [ $1, _hm($2, $3, $4) ] }   # Ann Smith 9:05 AM
        elsif ($line =~ /^\s*$TIME\s+($NAME)\s*$/)                              { $hdr = [ $4, _hm($1, $2, $3) ] }   # 9:05 AM Ann Smith
        elsif ($line =~ /^\s*($PLAIN):\s+(.*)$/ && $1 !~ /^(?:https?|note|risk|vote|est|re|fyi|y|t|b|yesterday|yday|today|blockers?|blocked|did|done|plan|planned|doing|will|issues?|impediments?)$/i) { $flush->(); $cur = { who => _clean($1), time => undef, text => $2, line => $ln }; next }   # Ann: 5
        if ($hdr) { $flush->(); $cur = { who => _clean($hdr->[0]), time => $hdr->[1], text => '', line => $ln + 1 }; next }   # line: where the message body starts (for editors)
        next if $line =~ /^\s*(?:Meeting (?:started|ended)|.* (?:joined|left) the meeting\.?|Recording (?:has )?started.*|Transcription (?:has )?started.*)\s*$/i;
        next if $line =~ /^\s*(?:[^\w\s]+\s+\d+\s*)+$/;                                       # reaction tallies "👍 2"
        if ($cur) { $cur->{text} .= ($cur->{text} eq '' ? '' : "\n") . $line }
    }
    $flush->();
    @msgs;
}
sub _hm { my ($h, $m, $ap) = @_; $h += 12 if $ap && $ap =~ /^p/i && $h < 12; $h = 0 if $ap && $ap =~ /^a/i && $h == 12; sprintf '%02d:%02d', $h, $m }
sub _clean { my $s = shift; $s =~ s/^\s+|\s+$//g; $s =~ s/\s*\((?:Guest|External|Unverified)\)$//i; $s }

# ---------------------------------------------------------------- rounds
# A round opens with a marker message:  #est AUTH-104   |  #vote Ship Friday? y/n  |  #vote Pick a name: A B C
# Replies from other people (last reply per person wins) belong to the round until the next marker.
# Facilitator's own reply counts only if it is not itself a marker.
# round = { kind => 'est'|'vote', subject, options => [..], by => $who, time, answers => { who => raw }, msgs => [..] }
sub rounds {
    my (@msgs) = @_;
    my (@rounds, $r);
    for my $m (@msgs) {
        my @lines = split /\n/, $m->{text};
        my ($first) = @lines;
        $first //= '';
        my ($marker) = grep { /^\s*#\s*(?:est(?:imate)?|vote|poll)\b/i } @lines;     # a marker anywhere in the message opens a round
        if ($marker && $marker =~ /^\s*#\s*(est(?:imate)?|vote|poll)\b\s*(.*?)\s*$/i) {
            my ($k, $subject) = ($1, $2);
            my $kind = lc($k) =~ /^est/ ? 'est' : 'vote';
            my @opts;
            if ($kind eq 'vote' && $subject =~ /^(.*[?:])\s*(\S.*)$/) {      # "Ship Friday? y/n"   "Name: A B C"
                my ($stem, $tail) = ($1, $2);
                my @o = map { lc } grep { length } split /\s*\/\s*|\s+/, $tail;
                if (@o >= 2 && @o <= 8 && !grep { length > 12 } @o) { @opts = @o; ($subject = $stem) =~ s/:$// }
            }
            push @rounds, $r = { kind => $kind, subject => $subject, options => \@opts, by => $m->{who}, time => $m->{time}, answers => {}, msgs => [] };
            next;
        }
        next unless $r;
        push @{ $r->{msgs} }, $m;
        $r->{answers}{ $m->{who} } = $first;
    }
    @rounds;
}

# ---------------------------------------------------------------- normalising answers
my %YES = map { $_ => 1 } qw(y yes +1 aye ok go ship 👍 ✅ ✔ yep yup agree approve);
my %NO  = map { $_ => 1 } qw(n no -1 nay 👎 ❌ ✖ nope disagree reject hold);
sub norm_vote {
    my ($raw, $opts) = @_;
    (my $t = lc $raw) =~ s/^\s+|\s+$//g;
    $t =~ s/[.!]+$//;
    return $t if $opts && @$opts && grep { $_ eq $t } @$opts;
    my ($y) = grep { $_ eq 'yes' || $_ eq 'y' } @{ $opts // [] };
    my ($n) = grep { $_ eq 'no'  || $_ eq 'n' } @{ $opts // [] };
    (my $word = $t) =~ s/^(\S+?)[,.!:;]*(?:\s.*)?$/$1/;                  # "no, cert isn't done" -> "no"
    return $y // 'yes' if $YES{$t} || $YES{$word};
    return $n // 'no'  if $NO{$t}  || $NO{$word};
    if ($opts && @$opts) {
        my @hit = grep { $_ eq $word } @$opts;                          # first word is an option: "kestrel!"
        @hit = grep { length($_) >= 3 && index($t, $_) >= 0 } @$opts unless @hit;   # substring, but never for single-letter options
        return $hit[0] if @hit == 1;
    }
    return 'abstain' if $t =~ /^(?:abstain|pass|skip|-)$/;
    undef;
}
sub norm_est {                                # -> number | '?' | undef
    my $raw = shift;
    (my $t = lc $raw) =~ s/^\s+|\s+$//g;
    return '?' if $t =~ /^(?:\?|idk|unknown|☕|coffee|pass)$/;
    return $1 + 0 if $t =~ /^(\d+(?:\.\d+)?)\s*(?:sp|pts?|points?|story\s*points?|h|hrs?|hours?|d|days?)?\.?$/;
    return $1 + 0 if $t =~ /^(?:[^\d]*?)(?<![\w-])(\d+(?:\.\d+)?)(?![\w-])(?:[^\d]*)$/;   # exactly one free-standing number: "actually 8", not "RPT-9"
    undef;
}

# ---------------------------------------------------------------- tallies
# tally(round) -> { kind, subject, n, counts => {opt => n}, voters => {opt => [names]}, result, ... }
sub tally {
    my $r = shift;
    my %by;
    my (@unparsed);
    for my $who (sorted(keys %{ $r->{answers} })) {
        my $v = $r->{kind} eq 'est' ? norm_est($r->{answers}{$who}) : norm_vote($r->{answers}{$who}, $r->{options});
        if (defined $v) { $by{$who} = $v } else { push @unparsed, [ $who, $r->{answers}{$who} ] }
    }
    my $t = { kind => $r->{kind}, subject => $r->{subject}, by => $r->{by}, time => $r->{time}, n => scalar keys %by, answers => \%by, unparsed => \@unparsed };
    if ($r->{kind} eq 'est') {
        my @nums = sorted(grep { $_ ne '?' } values %by);
        $t->{unknown} = [ sorted(grep { $by{$_} eq '?' } keys %by) ];
        if (@nums) {
            $t->{min} = $nums[0]; $t->{max} = $nums[-1];
            $t->{median} = @nums % 2 ? $nums[ $#nums / 2 ] : ($nums[ @nums / 2 - 1 ] + $nums[ @nums / 2 ]) / 2;
            my $c = classify(sub { $_[0] }, @nums);
            my @modes = sortOn(sub { [ -scalar @{ $c->{ $_[0] } }, $_[0] ] }, keys %$c);
            $t->{mode} = $modes[0] + 0;
            $t->{consensus} = @nums >= 2 && $nums[0] == $nums[-1] ? 1 : 0;
            $t->{spread} = $nums[-1] - $nums[0];
            $t->{result} = $t->{consensus} ? $nums[0] : $t->{median};
            $t->{outliers} = [ sorted(grep { $by{$_} ne '?' && abs($by{$_} - $t->{median}) > ($t->{median} || 1) } keys %by) ];
        }
    }
    else {
        my $c = classify(sub { $by{ $_[0] } }, keys %by);
        $t->{voters} = { map { $_ => [ sorted(@{ $c->{$_} }) ] } keys %$c };
        $t->{counts} = { map { $_ => scalar @{ $c->{$_} } } keys %$c };
        my @order = sortOn(sub { [ -$t->{counts}{ $_[0] }, $_[0] ] }, keys %{ $t->{counts} });
        my $cast = sum(map { $t->{counts}{$_} } grep { $_ ne 'abstain' } @order) || 0;
        $t->{result} = @order ? $order[0] : undef;
        $t->{tie}    = (@order >= 2 && $t->{counts}{ $order[0] } == $t->{counts}{ $order[1] }) ? 1 : 0;
        $t->{majority} = ($t->{result} && $cast && $t->{counts}{ $t->{result} } * 2 > $cast) ? 1 : 0;
        $t->{unanimous} = ($t->{result} && $cast && $t->{counts}{ $t->{result} } == $cast) ? 1 : 0;
    }
    $t;
}

# ---------------------------------------------------------------- output
sub tally_text {
    my $t = shift;
    my $out = '';
    if ($t->{kind} eq 'est') {
        $out .= sprintf "ESTIMATE %s  (%d answers%s)\n", $t->{subject}, $t->{n}, $t->{time} ? " at $t->{time}" : '';
        $out .= sprintf "  %-14s %s\n", $_, $t->{answers}{$_} for sorted(keys %{ $t->{answers} });
        if (defined $t->{median}) {
            $out .= $t->{consensus} ? "  consensus: $t->{result}\n"
                  : sprintf("  no consensus: median %s, mode %s, range %s-%s%s\n", $t->{median}, $t->{mode}, $t->{min}, $t->{max}, @{ $t->{outliers} } ? ' — re-discuss with ' . join(', ', @{ $t->{outliers} }) : '');
        }
        $out .= "  unknown: " . join(', ', @{ $t->{unknown} }) . "\n" if $t->{unknown} && @{ $t->{unknown} };
    }
    else {
        $out .= sprintf "VOTE %s  (%d votes%s)\n", $t->{subject}, $t->{n}, $t->{time} ? " at $t->{time}" : '';
        for my $opt (sortOn(sub { [ -$t->{counts}{ $_[0] }, $_[0] ] }, keys %{ $t->{counts} })) {
            $out .= sprintf "  %-10s %2d  %s\n", $opt, $t->{counts}{$opt}, join(', ', @{ $t->{voters}{$opt} });
        }
        $out .= $t->{n} == 0 ? "  no votes\n" : $t->{tie} ? "  TIE\n" : sprintf("  result: %s%s\n", $t->{result}, $t->{unanimous} ? ' (unanimous)' : $t->{majority} ? ' (majority)' : ' (plurality)');
    }
    $out .= "  could not read: " . join('; ', map { "$_->[0] '$_->[1]'" } @{ $t->{unparsed} }) . "\n" if @{ $t->{unparsed} };
    $out;
}
sub standup_lines {                           # for the stand-up file: est lines ready to uncomment, votes as notes
    my @tallies = @_;
    my $out = '';
    for my $t (@tallies) {
        if ($t->{kind} eq 'est') {
            my ($id) = $t->{subject} =~ /([A-Za-z][A-Za-z0-9_]*-\d+)/;
            my $votes = join(', ', map { "$_ $t->{answers}{$_}" } sorted(keys %{ $t->{answers} }));
            if (defined $t->{result} && $id) { $out .= sprintf "%sest %s %s   ; %s: %s\n", $t->{consensus} ? '' : '; ', $id, $t->{result}, $t->{consensus} ? 'consensus' : "median, no consensus", $votes }
            else { $out .= "; est $t->{subject}: " . ($votes || 'no answers') . "\n" }
        }
        else {
            $out .= sprintf "note vote %s -> %s (%s)\n", $t->{subject}, $t->{n} ? ($t->{tie} ? 'tie' : $t->{result}) : 'no votes',
                            join(', ', map { "$_ $t->{counts}{$_}" } sortOn(sub { [ -$t->{counts}{ $_[0] }, $_[0] ] }, keys %{ $t->{counts} })) || '-';
        }
    }
    $out;
}
sub report { my @t = map { tally($_) } rounds(parse_chat($_[0])); (join("\n", map { tally_text($_) } @t), standup_lines(@t), scalar @t) }

# quick tallies without markers:  everything numeric after a time, or every yes/no
sub quick_est  { my ($msgs, $since) = @_; my %a; for (grep { !$since || !$_->{time} || $_->{time} ge $since } @$msgs) { my $v = norm_est((split /\n/, $_->{text})[0] // ''); $a{ $_->{who} } = $v if defined $v } tally({ kind => 'est', subject => $_[2] // '', answers => { map { $_ => $a{$_} } keys %a }, options => [] }) }
sub quick_vote { my ($msgs, $since, $opts) = @_; my %a; for (grep { !$since || !$_->{time} || $_->{time} ge $since } @$msgs) { my $v = norm_vote((split /\n/, $_->{text})[0] // '', $opts); $a{ $_->{who} } = $v if defined $v } tally({ kind => 'vote', subject => $_[3] // '', answers => \%a, options => $opts // [] }) }

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Chat::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Chat::$_"} == \&{"Prelude::$_"})
    } keys %Chat::;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Chat - tally votes and estimates from a pasted Teams meeting chat

=head1 SYNOPSIS

    # in the meeting, as facilitator, type in the chat:
    #est AUTH-104                 then everyone types a number (5, 8, ?, "8 pts" all work)
    #vote Ship Friday? y/n        then y / n / +1 / 👍 ...
    #vote Sprint name: Falcon Hawk Kestrel

    # after: select all in the chat pane, copy, paste into  standups/2026-09-23-chat.txt
    perl bin/daily.pl chat        # tallies, and appends est/vote lines to today's stand-up file
    perl bin/chat.pl standups/2026-09-23-chat.txt
    perl bin/chat.pl --est AUTH-104 --since 09:07 pasted.txt      # no markers: numbers after 09:07

=head1 WHY THIS WAY

Teams meeting chat is reachable only through Graph API permissions an
individual usually cannot get on a managed tenant, so the chat is captured by copy
and paste, which every client permits. Teams Polls (Forms) are the other
option; their results export to Excel from Forms, which Excel then reads.

Copy formats change between Teams versions. The parser accepts C<[9:05 AM]
Name>, C<Name 9:05 AM>, C<9:05 AM Name> headers (with an optional date,
12- or 24-hour), each followed by the message lines, and a one-line C<Name:
message> fallback you can type by hand. Join/leave/recording lines and
reaction tallies are dropped. If a new Teams format breaks it, C<parse_chat>
is the only function to touch; keep a sample in C<examples/>.

=head1 RULES

A round starts at a marker message (C<#est> / C<#estimate> / C<#vote> /
C<#poll>) and runs until the next marker. Only the first line of each
message counts. One answer per person, the latest wins, so people can change
their mind. Estimates: numbers with or without a unit, C<?> for unknown;
consensus when everyone agrees, otherwise the median with the range and the
people more than a median away flagged for re-discussion. Votes: C<y/n>
synonyms map to yes/no; option lists on the marker (C<A B C> or C<y/n>) are
matched by name or substring; plurality, majority and unanimity are reported;
ties are called out.

=head1 FUNCTIONS

    @msgs = parse_chat($text)             # { who, time, text }
    @r    = rounds(@msgs)                 # marker-delimited rounds
    $t    = tally($round)                 # est: answers, median, mode, consensus, outliers ; vote: counts, voters, result, tie, majority
    tally_text($t)  standup_lines(@t)     # text report ; lines for Standup.pm (est ID N ready when consensus, commented otherwise)
    ($text, $lines, $n) = report($chat)   # all of the above
    quick_est(\@msgs, $since, $subject)   quick_vote(\@msgs, $since, \@options, $subject)
    norm_est($raw)  norm_vote($raw, \@options)

=head1 SEE ALSO

L<Standup>, C<bin/chat.pl>, C<bin/daily.pl chat>.

=cut
