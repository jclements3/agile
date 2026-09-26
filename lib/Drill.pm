package Drill;
# The memory drill: the backlog tree and the people, recalled rather than read, so the meeting can be run from memory.
# Cards are generated from the journal on every run (nothing to maintain), at every level:
#
#     team   Team Alpha: who?                  -> AL BJ          initials, any order
#     who    AL = ?                            -> Ann Lee        the name behind the initials
#     home   AL: team?                         -> Alpha
#     tome   Tome C Contracting: epics?        -> C1 C2          epic codes (the first word when it looks like one)
#     up     C2 Win Contracts: tome?           -> C
#     epic   C2 Win Contracts: open tasks?     -> C-21 C-23      (in-sprint only when the epic has more than 8 open)
#     now    AL: in the sprint?                -> C-23
#     next   AL: next up?                      -> C-11 C-12      the top 5 of their queue
#     task   C-23 Negotiate & Close: who?      -> AL
#     what   C-23: what is it?                 -> negotiate close   a few words, half the title's words is enough
#     blk    C-23: blocked on?                 -> legal review
#
# Answers are terse: ids, codes and initials in any order, case and commas ignored. An id you give that is not in the
# answer counts against you (wrong recall is worse than a gap). On a miss you can write a hook -- your own mnemonic --
# which is shown the next time you miss that card, together with the hooks of the people in the answer.
#
# Progress is the Leitner system in one plain-text file (drill.txt next to scrum.conf):
#     key | box | due | right | wrong | answer | hook
# right moves a card up a box (due again in 1, 1, 3, 7, 14, 30 days), wrong sends it back to box 0 (due tomorrow).
# The answer is kept, so a card whose answer changed in the journal (reassigned, new task in the epic, new blocker)
# comes back first, marked "changed, was: ...". Two front ends share this: an interactive terminal loop, and a sheet
# (reports/<date>-drill.txt) answered in Vim and graded on :w.
use strict;
use warnings;
use Time::Local qw(timegm);
use Prelude qw(sorted nub classify);
use Scrum qw(items members);

our @EXPORT = qw(initials cards grade read_progress write_progress pick record sheet_text grade_sheet drill_loop);
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Drill: unknown function '$n'\n" unless defined &{"Drill::$n"};
        *{"${caller}::$n"} = \&{"Drill::$n"};
    }
}

our @KINDS    = qw(team who home tome up epic now next task what blk);   # presentation order: top of the tree first
our @INTERVAL = (1, 1, 3, 7, 14, 30);                                     # days until due again, by box
our $MAX_EPIC = 8;                                                        # more open tasks than this: ask only the in-sprint ones
our $NEXT     = 5;
my %KIND_RANK = map { $KINDS[$_] => $_ } 0 .. $#KINDS;
my %STOP      = map { $_ => 1 } qw(AND THE OF TO ON IN FOR BY WITH FROM A AN);

# ---------------------------------------------------------------- initials
sub _words { my $n = shift // ''; $n = "$2 $1" if $n =~ /^([^,]+),\s*(.+)$/; grep { length } map { (my $w = $_) =~ s/[^\p{L}\d]//g; $w } split ' ', $n }   # "Archer, Sam" reads as "Sam Archer"
sub initials {                                # initials(@names) -> { name => 'AL' }; collisions extend with letters of the last word: ACh ACo
    my @names = nub(@_);
    my %base = map { my @w = _words($_); $_ => (@w > 1 ? join('', map { uc substr($_, 0, 1) } @w) : ucfirst lc substr($w[0] // '?', 0, 2)) } @names;
    my %out;
    my $groups = classify(sub { uc $base{ $_[0] } }, @names);
    for my $g (values %$groups) {
        if (@$g == 1) { $out{ $g->[0] } = $base{ $g->[0] }; next }
        for my $k (1 .. 12) {
            my %try = map { my @w = _words($_); $_ => $base{$_} . lc substr($w[-1] // '', 1, $k) } @$g;
            my %n; $n{ uc $_ }++ for values %try;
            if ((grep { $_ == 1 } values %n) == @$g || $k == 12) { %out = (%out, %try); last }
        }
        my %seen; for (sorted(@$g)) { $out{$_} .= ++$seen{ uc $out{$_} } if $seen{ uc $out{$_} } }   # identical names: AL, AL2
    }
    \%out;
}

# ---------------------------------------------------------------- cards
sub _code { my $name = shift // ''; my ($w) = $name =~ /^(\S+)\s+\S/; defined $w && $w =~ /^[A-Z0-9][A-Z0-9.\-]{0,5}$/ && $w =~ /[A-Z]/ ? $w : $name }
my %OPEN = map { $_ => 1 } qw(committed carryover backlog master);
sub cards {                                   # cards($s, team => T, roster => [..]) -> [ { key, kind, q, want => [..], mode => set|name|gist, show, names => [..] } ]
    my ($s, %o) = @_;
    my $team = $o{team};
    my @open = grep { $OPEN{ $_->{state} } && (!$team || ($_->{team} // '') eq $team) } items($s);
    my @ros  = grep { !$team || ($_->{team} // '') eq $team } @{ $o{roster} // [] };
    my %home = map { $_->{name} => $_->{team} } grep { $_->{team} } @ros;
    for my $it (@open) { next unless $it->{owner} && $it->{team} && $it->{team} ne 'Master'; $home{ $it->{owner} } //= $it->{team} }
    my @people = sorted(nub((map { $_->{owner} } grep { $_->{owner} } @open), map { $_->{name} } @ros));
    my $ini = initials(@people, map { $_->{name} } @{ $o{roster} // [] });   # the whole roster, so initials don't shift with the team filter
    my $at = $team ? "\@$team" : '';
    my @c;
    my $card = sub { my %c = @_; $c{show} //= join ' ', @{ $c{want} }; $c{names} //= []; push @c, \%c };
    my $who_show = sub { join ' ', map { "$ini->{$_} ($_)" } @_ };

    my $by_team = classify(sub { $home{ $_[0] } // '' }, @people);
    for my $t (sorted(grep { length } keys %$by_team)) {
        my @p = @{ $by_team->{$t} };
        $card->(key => "team:$t", kind => 'team', q => "Team $t: who? (initials)", want => [ map { $ini->{$_} } @p ], mode => 'set', show => $who_show->(@p), names => \@p);
    }
    for my $p (@people) {
        $card->(key => "who:$p", kind => 'who', q => "$ini->{$p} = ?  (full name)", want => [$p], mode => 'name', names => [$p]);
        $card->(key => "home:$p", kind => 'home', q => "$ini->{$p}: team?", want => [ $home{$p} ], mode => 'set', names => [$p]) if $home{$p};
    }
    my $by_epic = classify(sub { $_[0]{meta}{epic} // '' }, @open);
    my %tome_of = map { my $e = $_; $e => ((grep { defined } map { $_->{meta}{tome} } @{ $by_epic->{$e} })[0] // '') } keys %$by_epic;
    my $by_tome = classify(sub { $tome_of{ $_[0] } }, grep { length } keys %$by_epic);
    for my $t (sorted(grep { length } keys %$by_tome)) {
        my @e = sorted(@{ $by_tome->{$t} });
        my $codes = grep { _code($_) ne $_ } @e;
        $card->(key => "tome:$t$at", kind => 'tome', q => "Tome $t: epics?" . ($codes ? ' (codes)' : ''), want => [ map { _code($_) } @e ], mode => 'set', show => join(', ', @e));
    }
    for my $e (sorted(grep { length } keys %$by_epic)) {
        my @it = @{ $by_epic->{$e} };
        $card->(key => "up:$e", kind => 'up', q => "$e: tome?", want => [ _code($tome_of{$e}) ], mode => 'set', show => $tome_of{$e}) if $tome_of{$e};
        my ($q, @ask) = ('open tasks?', @it);
        ($q, @ask) = ('in the sprint?', grep { $_->{state} eq 'committed' || $_->{state} eq 'carryover' } @it) if @it > $MAX_EPIC;
        next unless @ask && @ask <= $MAX_EPIC;
        $card->(key => "epic:$e$at", kind => 'epic', q => "$e: $q (ids)", want => [ map { $_->{id} } @ask ], mode => 'set', show => join(', ', map { "$_->{id} $_->{title}" } @ask));
    }
    my %by_owner = %{ classify(sub { $_[0]{owner} // '' }, @open) };
    for my $p (@people) {
        my @mine = @{ $by_owner{$p} // [] };
        my @now  = grep { $_->{state} eq 'committed' || $_->{state} eq 'carryover' } @mine;
        my @next = grep { $_->{state} eq 'backlog' || $_->{state} eq 'master' } @mine;
        $card->(key => "now:$p", kind => 'now', q => "$ini->{$p}: in the sprint? (ids)", want => [ map { $_->{id} } @now ], mode => 'set', show => join(', ', map { "$_->{id} $_->{title}" } @now), names => [$p]) if @now;
        @next = @next[0 .. $NEXT - 1] if @next > $NEXT;
        $card->(key => "next:$p", kind => 'next', q => "$ini->{$p}: next up? (ids" . (@{ $by_owner{$p} } - @now > $NEXT ? ", top $NEXT" : '') . ')', want => [ map { $_->{id} } @next ], mode => 'set', show => join(', ', map { "$_->{id} $_->{title}" } @next), names => [$p]) if @next;
    }
    for my $it (@open) {
        $card->(key => "task:$it->{id}", kind => 'task', q => "$it->{id} $it->{title}: who?", want => [ $ini->{ $it->{owner} } ], mode => 'set', show => $who_show->($it->{owner}), names => [ $it->{owner} ]) if $it->{owner};
        $card->(key => "what:$it->{id}", kind => 'what', q => "$it->{id}: what is it? (a few words)", want => [ $it->{title} ], mode => 'gist') if length($it->{title} // '');
        $card->(key => "blk:$it->{id}", kind => 'blk', q => "$it->{id} $it->{title}: blocked on?", want => [ $it->{blocked} ], mode => 'gist') if $it->{blocked};
    }
    my %vocab; for my $c (grep { $_->{mode} eq 'set' } @c) { $vocab{$_}++ for map { _norm($_) } @{ $c->{want} } }   # the ids, codes and initials of the whole deck
    $_->{vocab} = \%vocab for @c;
    \@c;
}

# ---------------------------------------------------------------- grading
sub _norm { my $t = uc(shift // ''); $t =~ s/[^\p{L}\d\-]+/ /g; $t =~ s/^\s+|\s+$//g; $t }
sub _sig { grep { length > 2 && !$STOP{$_} } split ' ', _norm(shift) }
sub _like { my ($a, $b) = @_; return 1 if $a eq $b; my ($s, $l) = length $a < length $b ? ($a, $b) : ($b, $a); length $s >= 4 && index($l, $s) == 0 }   # "negot" = NEGOTIATE
sub grade {                                   # grade($card, $answer) -> { ok, missed => [..], extra => [..] }
    my ($c, $ans) = @_;
    my (@missed, @extra);
    if ($c->{mode} eq 'set') {
        my $a = ' ' . _norm($ans) . ' ';
        for my $w (@{ $c->{want} }) { my $n = _norm($w); push @missed, $w unless $a =~ s/ \Q$n\E / /i }
        @extra = grep { $c->{vocab} ? $c->{vocab}{$_} : !$STOP{$_} && (/\d/ || /^\p{Lu}{1,3}$/) } split ' ', $a;   # leftover ids, codes, initials from the deck: wrong recall
    } elsif ($c->{mode} eq 'name') {
        my %got = map { $_ => 1 } split ' ', _norm($ans);
        @missed = grep { !$got{$_} } map { _norm($_) } map { _words($_) } @{ $c->{want} };
    } else {
        my @got = _sig($ans);
        my @want = nub(_sig($c->{want}[0]));
        @missed = grep { my $w = $_; !grep { _like($w, $_) } @got } @want;
        return { ok => (@want && 2 * (@want - @missed) >= @want ? 1 : 0), missed => \@missed, extra => [] };
    }
    { ok => (!@missed && !@extra ? 1 : 0), missed => \@missed, extra => \@extra };
}

# ---------------------------------------------------------------- progress (drill.txt)
sub read_progress {                           # -> { key => { box, due, right, wrong, ans, hook } }
    my $file = shift;
    open my $fh, '<:encoding(UTF-8)', $file or return {};
    my %p;
    while (my $l = <$fh>) {
        chomp $l; $l =~ s/\r$//; $l =~ s/^\x{FEFF}//; next if $l =~ /^\s*(#|$)/;
        my @f = split /\|/, $l, 7; s/^\s+|\s+$//g for @f;
        next unless $f[0];
        $p{ $f[0] } = { box => $f[1] || 0, due => $f[2] // '', right => $f[3] || 0, wrong => $f[4] || 0, ans => $f[5] // '', hook => $f[6] // '' };
    }
    close $fh;
    \%p;
}
sub write_progress {
    my ($file, $p) = @_;
    open my $fh, '>:encoding(UTF-8)', $file or die "cannot write $file: $!\n";
    print $fh "# memory drill progress (daily.pl drill): key | box | due | right | wrong | answer | hook\n";
    for my $k (sorted(keys %$p)) { my $r = $p->{$k}; print $fh join(' | ', $k, $r->{box}, $r->{due}, $r->{right}, $r->{wrong}, map { _flat($_) } $r->{ans}, $r->{hook}), "\n" }
    close $fh;
    scalar keys %$p;
}
sub _add_days { my ($d, $n) = @_; my ($y, $m, $dd) = split /-/, $d; my @t = gmtime(timegm(0, 0, 0, $dd, $m - 1, $y) + $n * 86400); sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub record {                                  # record($prog, $card, $ok, $today): move the card between boxes, remember the answer
    my ($p, $c, $ok, $today) = @_;
    my $r = $p->{ $c->{key} } //= { box => 0, right => 0, wrong => 0, hook => '' };
    $r->{box} = $ok ? ($r->{box} < $#INTERVAL ? $r->{box} + 1 : $#INTERVAL) : 0;
    $r->{ $ok ? 'right' : 'wrong' }++;
    $r->{due} = _add_days($today, $INTERVAL[ $r->{box} ]);
    $r->{ans} = _flat($c->{show});
    $r;
}
sub _flat { (my $t = shift // '') =~ tr/|\n/\/ /; $t }
sub pick {                                    # pick(\@cards, $prog, today => D, n => 12) -> cards due now, each with status changed|due|new (and was)
    my ($cards, $p, %o) = @_;
    my $n = $o{n} // 12;
    my (@changed, @due, %new);
    for my $c (@$cards) {
        my $r = $p->{ $c->{key} };
        if (!$r) { push @{ $new{ $c->{kind} } }, { %$c, status => 'new' }; next }
        if (length $r->{ans} && $r->{ans} ne _flat($c->{show})) { push @changed, { %$c, status => 'changed', was => $r->{ans} } }
        elsif (($r->{due} // '') le $o{today}) { push @due, { %$c, status => 'due', box => $r->{box}, due => $r->{due} } }
    }
    @due = sort { $a->{box} <=> $b->{box} || $a->{due} cmp $b->{due} } @due;
    my @new;                                  # new cards round-robin across kinds, so a big backlog doesn't crowd out the people
    while (grep { @$_ } values %new) { for my $k (@KINDS) { push @new, shift @{ $new{$k} } if @{ $new{$k} // [] } } }
    my @out = (@changed, @due, @new);
    @out = @out[0 .. $n - 1] if @out > $n;
    my $i = 0; my %ord = map { $_->{key} => $i++ } @$cards;
    sort { $KIND_RANK{ $a->{kind} } <=> $KIND_RANK{ $b->{kind} } || $ord{ $a->{key} } <=> $ord{ $b->{key} } } @out;
}

sub _hooks {                                  # the hooks worth showing on a miss: the card's own, then the people in the answer
    my ($c, $p) = @_;
    my @h;
    push @h, "hook: $p->{ $c->{key} }{hook}" if $p->{ $c->{key} } && length $p->{ $c->{key} }{hook};
    for my $who (@{ $c->{names} // [] }) { my $r = $p->{"who:$who"}; push @h, "$who: $r->{hook}" if $r && length $r->{hook} && $c->{key} ne "who:$who" }
    @h;
}
sub _verdict {                                # the result lines under an answer
    my ($c, $g) = @_;
    return ("= ok" . ($c->{mode} eq 'set' && $c->{show} eq join(' ', @{ $c->{want} }) ? '' : "  $c->{show}")) if $g->{ok};
    my @d = (@{ $g->{missed} } && $c->{mode} eq 'set' ? 'missed ' . join(' ', @{ $g->{missed} }) : (), @{ $g->{extra} } ? 'not in it ' . join(' ', @{ $g->{extra} }) : ());
    ("= miss  $c->{show}", @d ? '  ' . join('; ', @d) : ());
}

# ---------------------------------------------------------------- the sheet (answered in Vim, graded on :w)
sub _status { my $c = shift; $c->{status} eq 'changed' ? "  (changed, was: $c->{was})" : $c->{status} eq 'new' ? '  (new)' : '' }
sub sheet_text {                              # sheet_text(\@picked, today => D, team => T, total => N) -> text
    my ($pick, %o) = @_;
    my %n; $n{ $_->{status} }++ for @$pick;
    my $out = "; memory drill $o{today}" . ($o{team} ? " -- $o{team}" : '') . ': ' . scalar(@$pick) . ' cards (' . join(', ', map { "$n{$_} $_" } grep { $n{$_} } qw(changed due new)) . ")\n"
            . "; answer after each '>', then :w to grade. Terse: ids, codes, initials, any order. '?' = don't know.\n"
            . "; after grading, write a mnemonic after 'hook:' and :w again to keep it ('hook: -' forgets it).\n"
            . ($o{team} ? "; team: $o{team}\n" : '') . "; score: -\n";
    my $i = 0;
    $out .= "\n#" . ++$i . " $_->{key}" . _status($_) . "\n$_->{q}\n> \n" for @$pick;
    $out;
}
sub grade_sheet {                             # grade_sheet($text, \%card_by_key, $prog, $today) -> ($new_text, { graded, ok, miss, hooks, done, total })
    my ($text, $by, $p, $today) = @_;
    my @lines = split /\n/, $text, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my (@head, @blocks);
    for (@lines) { if (/^#\d+\s+(.+?)(?:\s{2}\(.*\))?\s*$/) { push @blocks, { key => $1, lines => [$_] } } elsif (@blocks) { push @{ $blocks[-1]{lines} }, $_ } else { push @head, $_ } }
    my %st = (graded => 0, ok => 0, miss => 0, hooks => 0, done => 0, total => scalar @blocks);
    for my $b (@blocks) {
        my $L = $b->{lines};
        my ($ai) = grep { $L->[$_] =~ /^>/ } 0 .. $#$L;
        my $graded = grep { /^= / } @$L;
        my $ans = defined $ai ? substr($L->[$ai], ($L->[$ai] =~ /^>\s?/ ? $+[0] : 0)) : '';
        my $c = $by->{ $b->{key} };
        if (defined $ai && $ans =~ /\S/ && !$graded) {
            my @ins;
            if (!$c) { @ins = ('= gone  (no longer in the journal)') }
            else {
                my $g = $ans =~ /^\s*\?\s*$/ ? { ok => 0, missed => [], extra => [] } : grade($c, $ans);
                @ins = _verdict($c, $g);
                push @ins, map { "  $_" } grep { !/^hook: / } _hooks($c, $p) unless $g->{ok};
                push @ins, 'hook: ' . ($p->{ $b->{key} } ? $p->{ $b->{key} }{hook} : '') unless $g->{ok} || grep { /^hook:/ } @$L;
                record($p, $c, $g->{ok}, $today);
                $st{graded}++;
            }
            splice @$L, $ai + 1, 0, @ins;
        }
        for (@$L) {                           # hooks: kept when written, forgotten with '-'
            next unless /^hook:\s*(.*?)\s*$/ && length $1;
            my $h = $1 eq '-' ? '' : $1;
            my $r = $p->{ $b->{key} } or next;
            next if ($r->{hook} // '') eq _flat($h);
            $r->{hook} = _flat($h); $st{hooks}++;
        }
        $st{ok}++   if grep { /^= ok/ } @$L;
        $st{miss}++ if grep { /^= miss/ } @$L;
        $st{done}++ if grep { /^= / } @$L;
    }
    my $score = "; score: $st{ok}/$st{total} ok, $st{miss} missed" . ($st{done} < $st{total} ? ', ' . ($st{total} - $st{done}) . ' to go' : '');
    s/^; score:.*$/$score/ for @head;
    (join("\n", @head, map { @{ $_->{lines} } } @blocks) . "\n", \%st);
}

# ---------------------------------------------------------------- the terminal loop
sub drill_loop {                              # drill_loop(\@picked, $prog, in => FH, out => FH, today => D, save => sub {}) -> { ok, miss, total }
    my ($pick, $p, %o) = @_;
    my ($in, $out) = ($o{in}, $o{out});
    my %st = (ok => 0, miss => 0, total => scalar @$pick);
    my $i = 0;
    for my $c (@$pick) {
        printf $out "\n[%d/%d] %s%s\n> ", ++$i, scalar @$pick, $c->{q}, _status($c);
        my $ans = <$in>;
        last unless defined $ans;
        chomp $ans; $ans =~ s/\r$//;
        last if $ans =~ /^\s*(q|quit)\s*$/i;
        my $g = $ans =~ /^\s*\??\s*$/ ? { ok => 0, missed => [], extra => [] } : grade($c, $ans);
        print $out map { "$_\n" } _verdict($c, $g);
        if (!$g->{ok}) {
            print $out map { "  $_\n" } _hooks($c, $p);
            record($p, $c, 0, $o{today});
            print $out "hook (enter to keep, - to forget)> ";
            my $h = <$in>;
            if (defined $h) { chomp $h; $h =~ s/\r$//; $h =~ s/^\s+|\s+$//g; $p->{ $c->{key} }{hook} = ($h eq '-' ? '' : _flat($h)) if length $h }
        } else { record($p, $c, 1, $o{today}) }
        $st{ $g->{ok} ? 'ok' : 'miss' }++;
        $o{save}->() if $o{save};
    }
    printf $out "\n%d/%d ok, %d missed\n", $st{ok}, $st{ok} + $st{miss}, $st{miss};
    \%st;
}

1;
