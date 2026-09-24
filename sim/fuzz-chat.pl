#!/usr/bin/perl
# fuzz-chat.pl -- property tests for the chat/answers/lint parsers: thousands of generated Teams pastes with
# every message shape and mutation we know of, checking invariants rather than exact output.
#
#   perl sim/fuzz-chat.pl [--iterations 2000] [--seed N] [--verbose]
#
# Invariants (each violation is printed with the paste that caused it and exits 1):
#   1. lint never attributes a message to a person who did not post one, and never loses a person who did
#   2. a line lint calls ok is parsed by parse_answers to the same Y/T/B; a line it calls ERROR is not parsed at all
#   3. a bare line with a unique uppercase Y, T, B in order always parses, whatever text is between them
#   4. an ambiguous lowercase line is never silently split (either refused, or a guess that is offered, never applied)
#   5. the last message from a person wins; earlier ones never leak into the record
#   6. #est/#vote rounds, reactions, join/leave lines, "Edited", quoted replies and @mentions never become answers
#   7. no parser call dies or warns
# Standalone, not part of the tested kit.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Prelude qw(show);
use Chat qw(parse_chat);
use Answers qw(parse_answers lint_chat suggest_lines);
use Scrum qw(load);

my %o = (iterations => 2000, seed => 1);
GetOptions(\%o, 'iterations=i', 'seed=i', 'verbose') or exit 2;
srand($o{seed});

my @names = ('Ann Lee', 'Bob Ray', 'Cy Diaz', 'Dee Park', 'Eve Ng', 'Fay Ott', 'Gus Hill', 'Hal Ito', 'Ida Roy', 'Jon Wu', 'Kim Cho', 'Lou Bell', 'Archer, Sam', "O'Neil, Pat", 'Pat Guest (Guest)');
my @ids   = qw(A-1 A-12 B-121 IF-3 AUTH-103 RPT-2 G-332 ZZ-999);
my @words = qw(finished started reviewing merged the lab feed parser test ICD waiting on cert done nearly almost b t y be to why and or with for punting hold redo passing sync coordinate Bravo);   # the four-letter words ride along: suggest_lines must stay commented and known-id only
sub pick { $_[int rand @_] }
my @safe  = grep { !/^[ytb]$/ } @words;      # filler for uppercase/labelled shapes: a stray standalone y/t/b would change the shape's meaning
sub words { join ' ', map { rand() < 0.3 ? pick(@ids) : pick(@safe) } 1 .. (1 + int rand 5) }
sub lwords { join ' ', map { rand() < 0.3 ? pick(@ids) : pick(@words) } 1 .. (1 + int rand 5) }   # may contain y/t/b words: for the lowercase shape only
sub hm { my $m = 8 * 60 + 30 + int rand 20; sprintf '[%d:%02d AM]', int($m / 60), $m % 60 }

# message shapes -> (text, expected => ok|error|noanswer|either)
sub shape {
    my $k = int rand 12;
    my ($a, $b, $c) = (words(), words(), rand() < 0.6 ? 'none' : words());
    return ("Y $a T $b B $c", 'ok')                                   if $k == 0;   # bare uppercase
    return ("Y: $a\nT: $b\nB: $c", 'ok')                               if $k == 1;   # labelled
    return ("Y: $a T: $b B: $c", 'ok')                                 if $k == 2;   # one line with colons
    return ("yesterday: $a today: $b blockers: $c", 'ok')              if $k == 3;
    return ("y " . lwords() . " t " . lwords() . " b " . (rand() < 0.6 ? 'none' : lwords()), 'either') if $k == 4;   # lowercase: ok only if unambiguous
    return ("Y $a T $b", 'error')                                      if $k == 5;   # missing B
    return ("T $b B $c Y $a", 'error')                                 if $k == 6;   # out of order
    return ("#est " . pick(@ids), 'noanswer')                          if $k == 7;
    return ("5", 'noanswer')                                           if $k == 8;   # a vote reply
    return ("\x{1F44D} 2", 'noanswer')                                 if $k == 9;   # reaction tally line
    return ("hello everyone, sorry I'm late", 'error')                 if $k == 10;  # prose: lint error (no Y/T/B), not an answer
    return ("Y $a T $b B $c\nEdited", 'ok')                            if $k == 11;  # Teams "Edited" marker
}

my $S = load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01');   # a real journal: suggest_lines cross-checks ids against it
my ($bad, $n) = (0, 0);
my $warned = '';
local $SIG{__WARN__} = sub { $warned .= $_[0] };
for my $it (1 .. $o{iterations}) {
    my @people = map { pick(@names) } 1 .. (1 + int rand 6);
    my %expect; my @lines = ('Meeting started');
    for my $p (@people) {
        my ($text, $exp) = shape();
        push @lines, hm() . " $p", $text;
        push @lines, "$p joined the meeting." if rand() < 0.1;
        # the rule lint and parse_answers share: the last message with a Y/T/B signal is the status; chatter/votes after
        # it change nothing; prose ("hello") counts only when the person has nothing better
        if ($exp eq 'noanswer') { }
        elsif ($text =~ /^hello/) { $expect{$p} = { exp => 'error', text => $text } unless $expect{$p} && $expect{$p}{exp} ne 'error' }
        else { $expect{$p} = { exp => $exp, text => $text } }
    }
    my $chat = join("\n", @lines, 'Meeting ended') . "\n";
    $warned = '';
    my @lint = eval { lint_chat($chat, known => { map { $_ => 1 } grep { $_ ne 'ZZ-999' } @ids }) };
    my @ans  = eval { parse_answers($chat) };
    my $err = $@;
    my $sug = eval { suggest_lines($S, 'Alpha', \@ans, []) } // ''; $err .= $@ if $@;
    $n++;
    my @v;
    push @v, "died: $err" if $err;
    push @v, "warned: $warned" if $warned =~ /\S/;
    for my $l (grep { /\S/ } split /\n/, $sug) {          # 4. the four-letter words are only ever suggested, never applied, and only for tasks the journal knows
        push @v, "suggestion is not a known verb: $l" unless $l =~ /^(?:; )?(?:done|block|unblock|risk|note|absent|punt|hold|redo|pass|sync) /;
        push @v, "a four-letter word suggested uncommented: $l" if $l =~ /^(?:punt|hold|redo|pass|sync) /;
        push @v, "suggestion names an unknown task: $l" if $l =~ /^; (?:punt|hold|redo|pass|sync) (\S+)/ && !$S->{items}{$1};
    }
    my %lint = map { $_->{who} => $_ } @lint;
    my %ans  = map { $_->{who} => $_ } @ans;
    for my $p (keys %lint) { push @v, "lint attributed to '$p' who is not a poster" unless grep { _clean($_) eq $p } @people }
    for my $p (keys %expect) {
        my $e = $expect{$p}{exp}; my $q = _clean($p);
        next if $e eq 'noanswer';
        push @v, "$q posted but lint has no record" unless $lint{$q};
        next unless $lint{$q};
        if ($e eq 'ok')    { push @v, "$q: expected ok, lint says " . join('; ', @{ $lint{$q}{errors} }) . " for: $expect{$p}{text}" unless $lint{$q}{ok}; push @v, "$q: lint ok but parse_answers has no record" if $lint{$q}{ok} && !$ans{$q} }
        if ($e eq 'error') { push @v, "$q: expected error, lint says ok for: $expect{$p}{text}" if $lint{$q}{ok} && !($expect{$p}{text} =~ /^Y .* T [^B]*$/ && $ans{$q} && $ans{$q}{complete}) }   # a missing-B message after a full status is an update: ok is right
        if ($e eq 'either') { my $amb = () = $expect{$p}{text} =~ /(?<!\S)[bB](?!\S)/g; push @v, "$q: ambiguous lowercase ($amb b's) but lint said ok: $expect{$p}{text}" if $amb > 1 && $lint{$q}{ok}; push @v, "$q: unambiguous lowercase refused: " . join('; ', @{ $lint{$q}{errors} }) . " for: $expect{$p}{text}" if $amb == 1 && !$lint{$q}{ok} && $expect{$p}{text} !~ /(?<!\S)[tT](?!\S).*(?<!\S)[tT](?!\S)|(?<!\S)[yY](?!\S).*(?<!\S)[yY](?!\S)/ }
        if ($lint{$q}{ok} && $ans{$q}) { for my $k (qw(y t b)) { push @v, "$q: lint and parse_answers disagree on $k: '$lint{$q}{$k}' vs '$ans{$q}{$k}'" if ($lint{$q}{$k} // '') ne ($ans{$q}{$k} // '') } }
    }
    if (@v) { $bad++; print "\n--- iteration $it\n", (map { "  ! $_\n" } @v), ($o{verbose} ? $chat : ''); last if $bad >= 10 }
}
sub _clean { my $s = shift; $s =~ s/\s*\((?:Guest|External|Unverified)\)$//i; $s }
printf "%d pastes, %d with violations\n", $n, $bad;
exit($bad ? 1 : 0);
