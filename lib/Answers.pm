package Answers;
# The three questions, answered in the Teams meeting chat:
#     Y: finished AUTH-103, reviewed RPT-202      (yesterday)
#     T: start AUTH-104                           (today)
#     B: waiting on cert for RPT-202              (blockers; "none" / "-" / "no" if none)
# parse_answers() turns the pasted chat into one record per person; flags() applies the
# deterministic checks (silent people, blockers, blockers that persist, plans that repeat,
# unknown or uncommitted task ids, "done" claims); suggest_lines() writes stand-up verbs
# for Standup.pm; the day's answers are kept in standups/<date>-answers.txt for history.
use strict;
use warnings;
use Prelude qw(sorted nub sum fmap classify sortOn);
use Chat    qw(parse_chat);
use Scrum   qw(items);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Answers: unknown function '$n'\n" unless defined &{"Answers::$n"};
        *{"${caller}::$n"} = \&{"Answers::$n"};
    }
}

my $ID    = qr/\b([A-Z][A-Z0-9_]{0,9}-\d{1,6})\b/;   # B-11 (one-letter prefix, as the IDEF0-derived backlogs use) through AUTH-103
my $LABEL = qr/^\s*(?:(y|yesterday|yday|1|did|done)|(t|today|2|plan|planned|doing|will)|(b|blockers?|blocked|3|impediments?|issues?))\s*[:\-–—.)]\s*(.*)$/i;
my $NONE  = qr/^\s*(?:none|no|nope|nothing|n\/?a|nil|-|--|clear|no blockers?|all good|✅|👍)?\s*[.!]?\s*$/i;
my $LIFTED = qr/\b(?:unblocked|resolved|cleared|fixed|no longer|not any ?more|lifted|sorted)\b/i;
sub _blocked { my $b = shift; (defined $b && $b !~ $NONE && $b !~ $LIFTED) ? 1 : 0 }

# ---------------------------------------------------------------- parsing
# answer = { who, time, y, t, b, raw, ids => { y => [...], t => [...], b => [...] }, complete => 0|1 }
# ---------------------------------------------------------------- one message -> Y/T/B fields, with the reasons when it fails
# Three accepted shapes: labelled lines ("Y: ...\nT: ...\nB: ..."), the same on one line, and bare delimiters with no
# punctuation: "Sam Archer Y finished B-11 T start B-1221 B none". Bare delimiters are standalone Y/T/B words in
# that order. Uppercase ones win when there is exactly one of each; otherwise lowercase is accepted only when it is
# unambiguous (exactly one y, one t, one b as words) -- "will b in the lab" makes a second b and is refused with a
# message naming it, rather than silently mis-split. Anything before the Y (a typed name) is ignored.
sub _fields {                                 # ($message_text) -> (\%got, \@errors)   %got has y/t/b when the shape parsed
    my $text = shift;
    my @lines = map { my $l = $_; (() = $l =~ /\b(?:[ytb]|yesterday|today|blockers?)\s*:/gi) >= 2 ? split(/\s+(?=\b(?:[ytb]|yesterday|today|blockers?)\s*:)/i, $l) : $l } split /\n/, $text;   # "Y: a T: b B: c" on one line
    return ({}, []) if @lines && $lines[0] =~ /^\s*#\s*(?:est|estimate|vote|poll)\b/i;      # Chat.pm rounds, not answers
    my (%got, @err, $cur);
    for my $l (@lines) {
        if ($l =~ $LABEL) { $cur = $1 ? 'y' : $2 ? 't' : 'b'; $got{$cur} = $4 }
        elsif (defined $cur && $l =~ /\S/) { $got{$cur} .= " $l" }
    }
    if (!%got && $lines[0] && $lines[0] =~ /\b(?:y|yesterday)\s*:.*\b(?:t|today)\s*:/i) {   # one line with colons
        my $s = join ' ', @lines;
        $got{y} = $1 if $s =~ /\b(?:y|yesterday)\s*:\s*(.*?)\s*(?=\b(?:t|today)\s*:)/i;
        $got{t} = $1 if $s =~ /\b(?:t|today)\s*:\s*(.*?)\s*(?=\b(?:b|blockers?)\s*:|$)/i;
        $got{b} = $1 if $s =~ /\b(?:b|blockers?)\s*:\s*(.*)$/i;
    }
    if (!%got) {                              # bare delimiters
        (my $s = join ' ', @lines) =~ s/\s+/ /g;
        my @tok; while ($s =~ /(?<!\S)([YyTtBb])(?!\S)/g) { my ($c, $at) = ($1, $-[1]); push @tok, { k => uc $c, up => ($c =~ /[YTB]/ ? 1 : 0), at => $at } }   # read $-[1] before any other match clobbers it
        my %up; push @{ $up{ $_->{k} } }, $_ for grep { $_->{up} } @tok;
        my %all; push @{ $all{ $_->{k} } }, $_ for @tok;
        my %pick;
        if (3 == grep { $up{$_} && @{ $up{$_} } == 1 } qw(Y T B)) { %pick = map { $_ => $up{$_}[0] } qw(Y T B) }
        elsif (@tok) {
            for my $k (qw(Y T B)) { my $n = @{ $all{$k} // [] };
                push @err, $n == 0 ? "no $k found" : "'$k' appears $n times: capitalize the one that is the delimiter" if $n != 1 }
            %pick = map { $_ => $all{$_}[0] } qw(Y T B) unless @err;
        }
        else { push @err, 'no Y/T/B found' }
        if (%pick) {
            if ($pick{Y}{at} < $pick{T}{at} && $pick{T}{at} < $pick{B}{at}) {
                $got{y} = substr $s, $pick{Y}{at} + 1, $pick{T}{at} - $pick{Y}{at} - 1;
                $got{t} = substr $s, $pick{T}{at} + 1, $pick{B}{at} - $pick{T}{at} - 1;
                $got{b} = substr $s, $pick{B}{at} + 1;
            }
            else { push @err, 'out of order: expected Y ... T ... B ...' }
        }
    }
    s/^\s+|\s+$//g for grep { defined } values %got;
    (\%got, \@err);
}
my $ACK = qr/^\s*(?:\+1|y|yes|yep|ok|okay|same|ditto|confirmed?|\x{1F44D}|\x{2705})\s*[.!]?\s*$/i;   # two keystrokes: accept today's proposed status
sub is_ack { my $t = shift // ''; $t =~ $ACK ? 1 : 0 }
sub read_proposals {                          # standups/<date>-proposals.txt (written by daily.pl propose) -> { who => { y, t, b } }
    my $file = shift; my %p;
    open my $fh, '<:encoding(UTF-8)', $file or return {};
    while (<$fh>) { chomp; next if /^\s*(#|$)/; my ($who, $y, $t, $b) = split /\t/, $_, 4; $p{$who} = { y => $y, t => $t, b => $b } if $who }
    close $fh; \%p;
}
sub parse_answers {                           # parse_answers($chat_text, guess => 0|1, proposals => { who => {y,t,b} })
    my ($text, %o) = @_;
    my (%a, @order);
    for my $m (parse_chat($text)) {
        my ($g, $err) = _fields($m->{text});
        my %got = %$g;
        if (!%got && $o{proposals} && $o{proposals}{ $m->{who} } && is_ack($m->{text})) { %got = %{ $o{proposals}{ $m->{who} } }; $got{accepted} = 1 }   # "+1" to the proposal: the proposal is the status
        if (!%got && $o{guess}) { my $gg = _guess($m->{text}); %got = %$gg if $gg }   # guess => 1: the person thumbed-up the lint's reading
        next unless %got;
        my $r = $a{ $m->{who} } //= do { push @order, $m->{who}; { who => $m->{who}, time => $m->{time}, y => undef, t => undef, b => undef, raw => '' } };
        $r->{time} = $m->{time} // $r->{time};
        $r->{raw} .= ($r->{raw} ? "\n" : '') . $m->{text};
        for my $k (keys %got) { (my $v = $got{$k}) =~ s/^\s+|\s+$//g; $r->{$k} = $v }   # later message overrides
    }
    for my $r (values %a) {
        $r->{ids} = { map { my $k = $_; ($k => [ nub(($r->{$k} // '') =~ /$ID/g) ]) } qw(y t b) };
        $r->{blocked}  = _blocked($r->{b});
        $r->{complete} = (defined $r->{y} && defined $r->{t} && defined $r->{b}) ? 1 : 0;
    }
    map { $a{$_} } @order;
}

# ---------------------------------------------------------------- lint: real-time checking during the meeting
# lint_chat($pasted_chat, known => { id => 1, ... }) -> ( { who, line, time, ok, errors => [..], warnings => [..], reply, y, t, b }, ... )
# One record per person (last message wins, like parse_answers). errors = the answer cannot be used; warnings = it parses
# but tells the kit little (no task id, unknown id). reply is the one line to paste back into the chat for that person.
my $NOTHING = qr/^\s*(?:none|nothing|no|n\/a|na|-|nil|clear|same|ditto|no blockers?)\s*[.!]?\s*$/i;
sub _guess {                                  # best reading of an ambiguous bare line: first Y, first T after it, LAST B after that (blockers come last)
    my $text = shift;
    (my $s = $text) =~ s/\s+/ /g;
    my @tok; while ($s =~ /(?<!\S)([YyTtBb])(?!\S)/g) { my ($c, $at) = ($1, $-[1]); push @tok, { k => uc $c, at => $at } }
    my ($y) = grep { $_->{k} eq 'Y' } @tok;                              return undef unless $y;
    my ($t) = grep { $_->{k} eq 'T' && $_->{at} > $y->{at} } @tok;       return undef unless $t;
    my ($b) = reverse grep { $_->{k} eq 'B' && $_->{at} > $t->{at} } @tok; return undef unless $b;
    my %g = (y => substr($s, $y->{at} + 1, $t->{at} - $y->{at} - 1), t => substr($s, $t->{at} + 1, $b->{at} - $t->{at} - 1), b => substr($s, $b->{at} + 1));
    s/^\s+|\s+$//g for values %g;
    (grep { !length } values %g) ? undef : \%g;
}
sub lint_message {                            # ($text, known => \%ids) -> { ok, errors, warnings, guess, y, t, b }
    my ($text, %o) = @_;
    my ($g, $err) = _fields($text);
    my (@e, @w) = (@$err);
    if (!@e && !%$g) { @e = ('no Y/T/B found') }
    my $guess = @e ? _guess($text) : undef;                              # only offered when the strict read failed
    if (!@e) {
        for my $k (qw(y t b)) { push @e, uc($k) . ' is empty' . ($k eq 'b' ? " (write 'none')" : '') unless defined $g->{$k} && $g->{$k} =~ /\S/ }
    }
    if (!@e) {
        for my $k (qw(y t)) { push @w, 'no task id in ' . uc($k) . ' (e.g. ' . ($o{example} // 'B-11') . ')' if $g->{$k} !~ $ID && $g->{$k} !~ $NOTHING }
        if ($o{known}) { for my $id (nub(map { $_ =~ /$ID/g } grep { defined } @$g{qw(y t b)})) { push @w, "$id is not in the journal" unless $o{known}{$id} } }
    }
    { ok => (@e ? 0 : 1), errors => \@e, warnings => \@w, guess => $guess, y => $g->{y}, t => $g->{t}, b => $g->{b} };
}
sub lint_chat {                               # the same reading parse_answers makes -- fields merge across a person's messages ("B: cert arrived" later
    my ($text, %o) = @_;                      # is an update) -- plus a verdict: ERROR when the person's latest attempt failed outright (ambiguous, out of
    my (%by, @order);                         # order, nothing recognisable) or the merged record is still missing a field; chatter after a good status is ignored
    for my $m (parse_chat($text)) {
        next if $m->{text} =~ /^\s*#\s*(?:est|estimate|vote|poll)\b/i;
        my ($g, $err) = _fields($m->{text});
        if (!%$g && $o{proposals} && $o{proposals}{ $m->{who} } && is_ack($m->{text})) { $g = { %{ $o{proposals}{ $m->{who} } } }; $err = [] }   # an ack accepts the proposal
        push @order, $m->{who} unless $by{ $m->{who} };
        my $p = $by{ $m->{who} } //= { who => $m->{who}, line => $m->{line}, time => $m->{time}, fields => {}, last_err => undef, last_text => $m->{text} };
        if (%$g) { $p->{fields}{$_} = $g->{$_} for keys %$g; $p->{last_err} = undef; $p->{line} = $m->{line}; $p->{time} = $m->{time} // $p->{time}; $p->{last_text} = $m->{text} }
        elsif (@$err && !(@$err == 1 && $err->[0] eq 'no Y/T/B found')) { $p->{last_err} = $err; $p->{line} = $m->{line}; $p->{last_text} = $m->{text} }   # tried and failed: this is what the reply addresses; plain chatter is not an attempt
        elsif (!%{ $p->{fields} } && !$p->{last_err}) { $p->{line} = $m->{line}; $p->{last_text} = $m->{text} }                                             # nothing yet: remember the latest chatter for the "no Y/T/B found" verdict
    }
    for my $p (values %by) {
        my $merged = join "\n", map { uc($_) . ": $p->{fields}{$_}" } grep { defined $p->{fields}{$_} } qw(y t b);
        my $r = $p->{last_err} ? lint_message($p->{last_text}, %o)                                   # the failed attempt: its errors and its guess
              : %{ $p->{fields} } ? lint_message($merged, %o)                                        # the merged record: field checks and warnings
              : lint_message($p->{last_text}, %o);                                                   # nothing ever parsed: "no Y/T/B found"
        %$p = (who => $p->{who}, line => $p->{line}, time => $p->{time}, %$r);
    }
    # the reply is written to be pasted into the chat as-is: a question the person can answer with a thumbs-up
    my $fmt = 'Y did ' . ($o{example} // 'B-11') . ' T doing ' . ($o{example2} // 'B-12') . ' B none';
    for my $r (values %by) {
        my ($first) = $r->{who} =~ /^(\S+)/;
        my $hey = "Hey $first! ";
        $r->{confirm} = $r->{ok} ? $hey . "I read your status as: Y $r->{y} / T $r->{t} / B $r->{b}  \x{1F44D} if right, or repost." : '';   # the table entry, for a thumbs-up (lint --reply --confirm)
        $r->{reply} = !$r->{ok} && $r->{guess} ? $hey . "Did you mean: Y $r->{guess}{y} / T $r->{guess}{t} / B $r->{guess}{b} ?  \x{1F44D} if yes, or repost as: $fmt"
                    : !$r->{ok}               ? $hey . "I couldn't read your status (" . join('; ', @{ $r->{errors} }) . "). Repost as: $fmt"
                    : @{ $r->{warnings} }     ? $hey . "Got it. " . join(' ', nub(map { /^no task id/ ? "Add the task id next time so it counts (e.g. $fmt)." : /^(\S+) is not in the journal/ ? "$1 isn't in the backlog -- typo?" : "$_." } @{ $r->{warnings} }))
                    : '';
    }
    map { $by{$_} } @order;
}
sub lint_text {                               # the report: one line per person, FILE:LINE: prefix so editors can jump (quickfix)
    my ($file, @r) = @_;
    my $out = '';
    for my $r (@r) {
        my $st = !$r->{ok} ? 'ERROR' : @{ $r->{warnings} } ? 'warn ' : 'ok   ';
        my $msg = !$r->{ok} ? join('; ', @{ $r->{errors} }) : @{ $r->{warnings} } ? join('; ', @{ $r->{warnings} }) : "Y/T/B parsed";
        $out .= sprintf "%s:%d: %s %s: %s\n", $file, $r->{line} // 0, $st, $r->{who}, $msg;
    }
    my $bad = grep { !$_->{ok} } @r; my $warn = grep { $_->{ok} && @{ $_->{warnings} } } @r;
    $out .= sprintf "# %d answered, %d error%s, %d warning%s\n", scalar @r, $bad, $bad == 1 ? '' : 's', $warn, $warn == 1 ? '' : 's';
    $out;
}

# ---------------------------------------------------------------- answers file (history)
# ---------------------------------------------------------------- proposals: yesterday's status drafts today's
# propose($s, $team, $hist, roster => [..]) -> ( { who, y, t, b, line, basis }, ... )  one per roster member
# Yesterday's T becomes today's Y ("done?"); today's T is the person's next committed task not already in Y (by
# priority, from the journal); B carries yesterday's blocker if it was one. The line is what you post before or
# during the meeting; the person answers with a thumbs-up or a corrected status. Nothing here moves points: a
# proposal that is confirmed is an ordinary answer; one that is not becomes an ASSUMED record (see --assume).
sub propose {
    my ($s, $team, $hist, %o) = @_;
    my $prev = $hist && @$hist ? $hist->[0] : undef;
    my %prev = $prev ? map { $_->{who} => $_ } @{ $prev->{answers} } : ();
    my $n = $s->{current};
    my @out;
    for my $who (@{ $o{roster} // [] }) {
        my $p = $prev{$who};
        my @wip = sortOn(sub { [ $_[0]{meta}{prio} // 9, $_[0]{id} ] }, grep { ($_->{owner} // '') eq $who } (defined $n ? items($s, state => 'committed', sprint => $n, ($team ? (team => $team) : ())) : ()));
        my ($y, $t, $b, $basis);
        if ($p && defined $p->{t} && $p->{t} =~ /\S/) { $y = $p->{t}; $basis = "yesterday's T" } 
        elsif (@wip) { $y = "$wip[0]{id} in progress"; $basis = 'first committed task' }
        else { $y = 'nothing recorded'; $basis = 'no history, no committed tasks' }
        my %in_y = map { $_ => 1 } $y =~ /$ID/g;
        my ($next) = grep { !$in_y{ $_->{id} } } @wip;
        $t = $next ? "$next->{id} $next->{title}" : @wip ? "continue $wip[0]{id}" : 'no committed task';
        $b = ($p && $p->{blocked}) ? $p->{b} : 'none';
        my $done = ($y =~ /$ID/) ? ' done?' : '';
        push @out, { who => $who, y => $y, t => $t, b => $b, basis => $basis, assumed_days => _assumed_days($who, $hist),
                     line => "$who: Y $y$done T $t B $b  -- \x{1F44D} if right, or repost your own Y/T/B" };
    }
    @out;
}
sub _assumed_days { my ($who, $hist) = @_; my $d = 0; for my $h (@{ $hist // [] }) { my ($p) = grep { $_->{who} eq $who } @{ $h->{answers} }; last unless $p && $p->{assumed}; $d++ } $d }
sub assumed_record {                          # a proposal recorded for someone who did not answer: visible, unconfirmed, never moves points
    my $p = shift;
    { who => $p->{who}, time => undef, y => $p->{y}, t => $p->{t}, b => $p->{b}, raw => '', assumed => 1,
      ids => { map { my $k = $_; ($k => [ nub(($p->{$k} // '') =~ /$ID/g) ]) } qw(y t b) }, blocked => _blocked($p->{b}), complete => 1 };
}
sub answers_text {                            # serialise for standups/<date>-answers.txt (also readable by humans)
    my ($date, $team, @ans) = @_;
    my $out = "$date" . ($team ? " $team" : '') . "\n";
    for my $r (@ans) {
        $out .= "$r->{who}" . ($r->{time} ? " ($r->{time})" : '') . ($r->{assumed} ? ' (assumed)' : '') . "\n";
        $out .= "  Y: " . ($r->{y} // '') . "\n  T: " . ($r->{t} // '') . "\n  B: " . ($r->{b} // '') . "\n";
    }
    $out;
}
sub read_answers {                            # -> { date, team, answers => [ ... ] }  (same record shape as parse_answers)
    my $file = shift;
    open my $fh, '<', $file or die "cannot open $file: $!\n";
    my @l = <$fh>;
    close $fh;
    chomp @l;
    my ($date, $team) = (shift(@l) // '') =~ /^(\d{4}-\d{2}-\d{2})\s*(\S*)/;
    my (@ans, $r);
    for my $l (@l) {
        if ($l =~ /^(\S.*?)(?:\s+\((\d{2}:\d{2})\))?(\s+\(assumed\))?$/ && $l !~ /^\s/) { push @ans, $r = { who => $1, time => $2, assumed => ($3 ? 1 : 0), y => undef, t => undef, b => undef, raw => '' } }
        elsif ($r && $l =~ /^\s+([YTB]):\s?(.*)$/) { $r->{ lc $1 } = $2 }
    }
    for my $r (@ans) {
        $r->{ids} = { map { my $k = $_; ($k => [ nub(($r->{$k} // '') =~ /$ID/g) ]) } qw(y t b) };
        $r->{blocked}  = _blocked($r->{b});
        $r->{complete} = (defined $r->{y} && defined $r->{t} && defined $r->{b}) ? 1 : 0;
    }
    { date => $date, team => $team || undef, answers => \@ans };
}
sub history {                                 # history($dir, $team, $before_date, $days) -> newest-first list of read_answers() results
    my ($dir, $team, $before, $days) = @_;
    $days //= 5;
    return () unless -d $dir;
    opendir my $dh, $dir or die "cannot read $dir: $!\n";
    my @f = sort { $b cmp $a } grep { /^(\d{4}-\d{2}-\d{2})(?:-(.+?))?-answers\.txt$/ && $1 lt $before && (!$team || !defined $2 || $2 eq $team) } readdir $dh;
    closedir $dh;
    my @h;
    for my $f (@f) { my $r = read_answers("$dir/$f"); next if $team && $r->{team} && $r->{team} ne $team; push @h, $r; last if @h >= $days }
    @h;
}
sub answers_path { my ($dir, $date, $team) = @_; "$dir/$date" . ($team ? "-$team" : '') . "-answers.txt" }

# ---------------------------------------------------------------- deterministic flags
# flags($s, $team, \@answers, \@history, roster => [names]) -> list of { level => 'red'|'amber'|'info', who, text, id }
sub flags {
    my ($s, $team, $ans, $hist, %o) = @_;
    my @f;
    my %seen = map { $_->{who} => $_ } @$ans;
    my $n = $s->{current};
    my %committed = map { $_->{id} => $_ } ($team && defined $n) ? items($s, state => 'committed', sprint => $n, team => $team) : ();
    my $prev = $hist && @$hist ? $hist->[0] : undef;
    my %prev = $prev ? map { $_->{who} => $_ } @{ $prev->{answers} } : ();
    my $norm = sub { my $t = lc($_[0] // ''); $t =~ s/[^a-z0-9 ]//g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t };

    for my $who (@{ $o{roster} // [] }) { push @f, { level => 'amber', who => $who, text => 'no answers in chat' } unless $seen{$who} }
    for my $r (grep { $_->{assumed} } @$ans) {   # silent, status carried forward from yesterday's proposal: escalates by the day, never counts as done
        my $days = 1 + _assumed_days($r->{who}, $hist);
        push @f, { level => $days >= 2 ? 'red' : 'amber', who => $r->{who}, text => "no answer; status ASSUMED from yesterday" . ($days > 1 ? " ($days days running)" : '') . ": Y $r->{y} / T $r->{t} / B $r->{b} -- unconfirmed" };
    }
    for my $r (grep { !$_->{assumed} } @$ans) {
        push @f, { level => 'info', who => $r->{who}, text => 'incomplete answers (missing ' . join('/', grep { !defined $r->{$_} } qw(y t b)) . ')' } unless $r->{complete};
        if ($r->{blocked}) {
            my $days = 1;
            for my $h (@$hist) { my $p = (grep { $_->{who} eq $r->{who} } @{ $h->{answers} })[0]; last unless $p && $p->{blocked}; $days++ }
            push @f, { level => $days >= 3 ? 'red' : 'amber', who => $r->{who}, text => "blocked" . ($days > 1 ? " for $days days" : '') . ": $r->{b}", id => $r->{ids}{b}[0] };
        }
        if ($prev && $prev{ $r->{who} } && defined $r->{t} && $norm->($r->{t}) ne '' && $norm->($r->{t}) eq $norm->($prev{ $r->{who} }{t})) {
            my $days = 2;
            for my $h (@$hist[ 1 .. $#$hist ]) { my $p = (grep { $_->{who} eq $r->{who} } @{ $h->{answers} })[0]; last unless $p && $norm->($p->{t}) eq $norm->($r->{t}); $days++ }
            # a plan that repeats is normal for as many days as the task is big: amber from day 3, red once it has outlived its points (at least 3)
            my ($big) = sort { $b <=> $a } map { $s->{items}{$_} ? ($s->{items}{$_}{points} // 0) : 0 } @{ $r->{ids}{t} };
            my $limit = ($big // 0) > 3 ? $big : 3;
            push @f, { level => $days >= $limit ? 'red' : $days >= 3 ? 'amber' : 'info', who => $r->{who}, text => "same plan $days days running: $r->{t}" };   # 2 days: routine (info); 3: amber; red once past the task's size
        }
        if (!@{ $r->{ids}{y} } && !@{ $r->{ids}{t} } && $r->{complete}) { push @f, { level => 'info', who => $r->{who}, text => 'no task ids in yesterday/today (untracked work?)' } }
        for my $id (nub(@{ $r->{ids}{y} }, @{ $r->{ids}{t} }, @{ $r->{ids}{b} })) {
            if (!$s->{items}{$id}) { push @f, { level => 'amber', who => $r->{who}, text => "mentions $id which is not in the journal", id => $id }; next }
            my $it = $s->{items}{$id};
            if ($team && !$committed{$id} && $it->{state} ne 'done' && ($it->{owner} // '') ne $r->{who}) {   # their own queued task is what is next, not a flag
                push @f, { level => 'info', who => $r->{who}, text => "mentions $id which is $it->{state}" . ($it->{team} ? " ($it->{team})" : '') . ", not in $team\'s sprint", id => $id };
            }
            if ($it->{owner} && $it->{owner} ne $r->{who} && (grep { $_ eq $id } @{ $r->{ids}{t} })) {
                push @f, { level => 'info', who => $r->{who}, text => "working $id which is owned by $it->{owner}", id => $id };
            }
        }
        for my $id (@{ $r->{ids}{y} }) {
            next unless $s->{items}{$id};
            if ($r->{y} =~ /\b(?:done|finished|complete[d]?|closed|merged|shipped|delivered)\b/i && $r->{y} !~ /\b(?:nearly|almost|not|isn'?t|half|mostly|partly|still)\s+(?:\w+\s+)?(?:done|finished|complete[d]?|closed|merged|shipped|delivered)\b/i && $s->{items}{$id}{state} eq 'committed') {
                push @f, { level => 'info', who => $r->{who}, text => "says $id is done; confirm and mark", id => $id, done => 1 };
            }
        }
    }
    sortOn(sub { [ { red => 0, amber => 1, info => 2 }->{ $_[0]{level} }, $_[0]{who} ] }, @f);
}

# ---------------------------------------------------------------- folding: the architect reads counts of the routine, every line of the serious
sub fold_flags {                              # fold_flags(@flags) -> lines: red/amber one per flag; info grouped by kind with the names
    my @f = @_;
    my (@out, %info, @kinds);
    for my $x (@f) {
        if ($x->{level} ne 'info') { push @out, sprintf "%-5s %-14s %s", uc $x->{level}, $x->{who}, $x->{text}; next }
        (my $kind = $x->{text}) =~ s/\b[A-Z][A-Z0-9_]{0,9}-\d{1,6}\b/ID/g; $kind =~ s/\([^)]*\)//g; $kind =~ s/owned by .*/owned by someone else/; $kind =~ s/in \S+'s sprint/in the team's sprint/; $kind =~ s/\s+/ /g; $kind =~ s/^\s|\s$//g;
        push @kinds, $kind unless $info{$kind};
        push @{ $info{$kind} }, $x->{who} . ($x->{id} ? " ($x->{id})" : '');
    }
    for my $k (@kinds) { my @w = @{ $info{$k} }; push @out, sprintf "%-5s %dx %s: %s", 'INFO', scalar @w, $k, join(', ', @w[0 .. ($#w < 7 ? $#w : 7)]) . (@w > 8 ? ', ...' : '') }
    @out;
}

# ---------------------------------------------------------------- suggested stand-up lines
sub suggest_lines {                           # from answers + flags: done (commented, confirm), block/unblock, note
    my ($s, $team, $ans, $flags) = @_;
    my $out = '';
    my %done_flag = map { $_->{id} => 1 } grep { $_->{done} } @$flags;
    my %said;
    for my $r (@$ans) { push @{ $said{$_} }, $r->{who} for grep { $done_flag{$_} } @{ $r->{ids}{y} } }
    $out .= "; done $_   ; " . join(', ', @{ $said{$_} }) . " say done\n" for sorted(keys %said);
    for my $r (@$ans) {
        if ($r->{blocked}) {
            my ($id) = @{ $r->{ids}{b} };
            (my $why = $r->{b}) =~ s/,/;/g;
            $out .= $id && $s->{items}{$id} ? "block $id $why\n" : "risk $r->{who}: $why\n";
        }
        else {
            for my $id (nub(grep { $s->{items}{$_} && $s->{items}{$_}{blocked} } @{ $r->{ids}{t} }, @{ $r->{ids}{y} }, @{ $r->{ids}{b} })) { $out .= "; unblock $id   ; $r->{who} no longer reports a blocker\n" }
            $out .= "; note $r->{who}: $r->{b}\n" if defined $r->{b} && $r->{b} =~ $LIFTED;
        }
    }
    # the four-letter words, said in a status: "punting A-3, too hard as written", "A-4 on hold", "redo A-1", "pass A-5 to Bravo",
    # "sync A-2 with B-3" -> the matching verb, commented for the architect to confirm (they move points or change teams)
    my %teams = map { lc $_ => $_ } @{ $s->{teams} // [] };
    for my $r (@$ans) {
        for my $text (grep { defined && /\S/ } $r->{t}, $r->{b}) {
            my @ids = nub(grep { $s->{items}{$_} } $text =~ /$ID/g);
            next unless @ids;
            (my $why = $text) =~ s/,/;/g;
            if ($text =~ /\b(?:punt|punting|punted|too (?:hard|big)|can'?t (?:do|finish))\b/i) { $out .= "; punt $ids[0] $why   ; $r->{who}: too hard as written -- back to TODO (confirm)\n" }
            elsif ($text =~ /\b(?:on hold|hold(?:ing)?|parked|paused|pulled (?:on|off)to)\b/i) { $out .= "; hold $ids[0] $why   ; $r->{who}: interrupted (confirm)\n" }
            elsif ($text =~ /\b(?:redo|rework|reopen(?:ed)?|demo found)\b/i) { $out .= "; redo $ids[0] $why   ; $r->{who}: found wrong after the demo (confirm)\n" }
            elsif ($text =~ /\b(?:pass(?:ing)?|hand(?:ing)?[ -]?off|hand(?:ing)? (?:over|to))\b/i) {
                my ($to) = map { $teams{ lc $_ } } grep { $teams{ lc $_ } } $text =~ /\b([A-Za-z][\w&-]*)\b/g;
                $out .= $to ? "; pass $ids[0] $to   ; $r->{who}: another team should do it (confirm)\n" : "; note $r->{who}: $why   ; pass to which team?\n";
            }
            elsif ($text =~ /\b(?:sync|coordinat\w+|together with|jointly)\b/i && @ids >= 2) { $out .= "; sync " . join(' ', @ids[0, 1]) . "   ; $r->{who}: coordinated across teams, shared DONE (confirm)\n" }
        }
    }
    my @silent = map { $_->{who} } grep { $_->{text} eq 'no answers in chat' } @$flags;
    $out .= "; absent " . join(' ', @silent) . "   ; no answers in chat (confirm)\n" if @silent;
    $out;
}

# ---------------------------------------------------------------- text
sub answers_report {
    my ($team, $ans, $flags) = @_;
    my $out = ($team ? "$team " : '') . "stand-up answers: " . scalar(@$ans) . " people, " . scalar(grep { $_->{blocked} } @$ans) . " blocked\n";
    for my $r (@$ans) {
        $out .= sprintf "  %-14s Y: %s\n  %-14s T: %s\n  %-14s B: %s\n", $r->{who}, $r->{y} // '-', '', $r->{t} // '-', '', $r->{b} // '-';
    }
    if (@$flags) {
        $out .= "flags:\n";
        $out .= "  $_\n" for fold_flags(@$flags);   # red/amber one per line; info grouped by kind
    }
    $out;
}

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Answers::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Answers::$_"} == \&{"Prelude::$_"})
          && !(defined &{"Chat::$_"}    && \&{"Answers::$_"} == \&{"Chat::$_"})
          && !(defined &{"Scrum::$_"}   && \&{"Answers::$_"} == \&{"Scrum::$_"})
    } keys %Answers::;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Answers - the three stand-up questions answered in Teams chat, parsed, checked, and recorded

=head1 THE CHAT CONVENTION

Each participant posts one message (or several; later ones override):

    Y: finished AUTH-103, reviewed Bob's PR on RPT-202
    T: start AUTH-104
    B: none

Labels accepted: C<Y/T/B>, C<yesterday/today/blockers>, C<1/2/3>, C<did/plan/issues>,
case-insensitive, followed by C<:> or C<->. A one-line C<Y: … T: … B: …> works too.
Task ids anywhere in the text (C<AUTH-104>) are picked up. C<B: none>, C<->, C<no>,
C<clear>, C<n/a> all mean not blocked.

=head1 WHAT IS DERIVED (no AI needed)

C<flags()> runs deterministic checks and returns red/amber/info items:

    no answers in chat (roster member silent)        amber
    blocked                                          amber; red when the same person reports a blocker 3+ days running
    same plan N days running                         amber at 2, red at 3
    mentions an id not in the journal                amber
    mentions an id not in this team's current sprint info
    working an id owned by someone else              info
    says an id is done (words done/finished/merged…) info + suggested "done" line
    no task ids at all                              info
    incomplete answers                               info

C<suggest_lines()> writes stand-up verbs: C<block ID reason> (live), C<risk who: reason>
when no id, C<; done ID> and C<; absent …> commented for you to confirm, C<; unblock ID>
when a previously blocked task is mentioned without a blocker.

=head1 FILES

    standups/<date>-<Team>-chat.txt     pasted chat (input; one per team meeting)
    standups/<date>-<Team>-answers.txt  parsed answers (kept; the history the checks use)

=head1 FUNCTIONS

    @ans   = parse_answers($chat_text)
    $text  = answers_text($date, $team, @ans);   $rec = read_answers($file);   @hist = history($dir, $team, $before_date, $days)
    @flags = flags($s, $team, \@ans, \@hist, roster => [names])
    $lines = suggest_lines($s, $team, \@ans, \@flags)
    $text  = answers_report($team, \@ans, \@flags)

=head1 SEE ALSO

L<Chat>, L<Standup>, L<Ai>, C<bin/daily.pl answers>.

=cut
