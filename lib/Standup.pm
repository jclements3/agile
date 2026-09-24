package Standup;
# Terse daily stand-up notes -> journal transactions + material for the day's report.
use strict;
use warnings;
use Prelude qw(sorted nub sum fmap);
use Scrum   qw(items);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Standup: unknown function '$n'\n" unless defined &{"Standup::$n"};
        *{"${caller}::$n"} = \&{"Standup::$n"};
    }
}

# ---------------------------------------------------------------- config  (scrum.conf: key = value)
my %DEFAULT = (
    journal => 'scrum.txt', standups => 'standups', reports => 'reports', unit => 'SP',
    to => '', cc => '', subject_prefix => '',
    banner => '', marking_owner => '', marking_category => '', marking_handling => '', marking_poc => '',
    standup_match => 'stand-?up', team_from_subject => '', attendance => 'attendance.csv', calendar => 'outlook', calendar_fixture => '',
    ai_backend => 'paste', ai_url => '', ai_model => '', ai_key_env => '', ai_curl_args => '', history_days => 5, default_team => '',
);
sub read_conf {
    my $path = shift;
    my %c = %DEFAULT;
    if (defined $path && open my $fh, '<', $path) {
        while (<$fh>) { next if /^\s*(#|$)/; s/\s+#.*$//; $c{ lc $1 } = $2 if /^\s*([\w.]+)\s*=\s*(.*?)\s*$/ }
        close $fh;
    }
    \%c;
}
sub find_conf {                               # walk up from cwd looking for scrum.conf; undef if none
    my $dir = shift // '.';
    require Cwd;
    $dir = Cwd::abs_path($dir);
    while (1) {
        return "$dir/scrum.conf" if -f "$dir/scrum.conf";
        my $up = $dir =~ s{/[^/]*$}{}r;
        return undef if $up eq $dir || $up eq '';
        $dir = $up;
    }
}

# ---------------------------------------------------------------- stand-up file format
#   2026-09-23                       (optional; else taken from the file name)
#   sprint 42                        (optional; else the journal's current sprint)
#   == Alpha                         team section; lines below belong to it ("==" alone ends it)
#   done AUTH-101 AUTH-102           Committed -> Done
#   carry RPT-201                    Committed -> Carryover
#   drop OPS-301                     Committed -> Removed
#   commit AUTH-104 Bob              backlog (team, master, or last sprint's carryover) -> this sprint, owner optional
#   refine OPS-302                   master backlog (or another team's backlog) -> this team's backlog
#   prune OPS-303 superseded         retire a backlog task: -> this sprint's Removed, reason kept on the posting
#   (a "== Master" section: new lines there go to the master backlog)
#   new AUTH-105 5 Login MFA p:1 e:Auth o:Ann     intake to the team backlog
#   new E-111 3 Scan market e:"E1 Set Direction" t:"E Executive & Strategy"   quote multi-word values
#   new! AUTH-106 3 Hotfix o:Bob     intake straight into this sprint
#   est AUTH-103 8                   re-estimate to 8
#   assign AUTH-103 Ann              change owner
#   block RPT-202 waiting on cert    mark blocked (reason free text)
#   unblock RPT-202
#   hold OPS-301 pulled onto P1 fix   interrupted by higher-priority work (stays committed; shows HOLD on the quad)
#   resume OPS-301
#   cap 12                           team capacity for this sprint
#   note Bob out Friday              free text -> report
#   risk cert renewal slipping       free text -> report
#   absent Dee
#   ; anything after ; or # is a comment
# A "# compiled ..." first line means the file has already been applied.

sub parse_standup {
    my ($text, $file) = @_;
    $file //= '(string)';
    my $su = { file => $file, date => undef, sprint => undef, teams => {}, order => [], notes => [], risks => [], errors => [], compiled => 0 };
    $su->{date} = $1 if $file =~ /(\d{4}-\d{2}-\d{2})/;
    my ($team, $ln) = (undef, 0);
    my $err = sub { push @{ $su->{errors} }, "$file:$ln: $_[0]" };
    my $bucket = sub { $team ? $su->{teams}{$team} : $su };
    for my $raw (split /\r?\n/, $text) {
        $ln++;
        $su->{compiled} = 1, next if $ln == 1 && $raw =~ /^#\s*compiled\b/;
        (my $line = $raw) =~ s/\s*[;#].*$//;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '';
        if ($line =~ /^(\d{4}-\d{2}-\d{2})$/)         { $su->{date} = $1; next }
        if ($line =~ /^sprint\s+(\d+)$/i)             { ($team ? $su->{teams}{$team} : $su)->{sprint} = $1; next }
        if ($line =~ /^==+\s*$/)                       { $team = undef; next }
        if ($line =~ /^==+\s*(\S+)/)                  { $team = $1; push @{ $su->{order} }, $team unless $su->{teams}{$team};
                                                        $su->{teams}{$team} //= { team => $team, done => [], carry => [], drop => [], commit => [], new => [], est => [],
                                                                                  assign => [], block => [], unblock => [], note => [], risk => [], absent => [], cap => undef, sprint => undef,
                                                                                  refine => [], prune => [], hold => [], resume => [] };
                                                        next }
        my ($verb, $rest) = $line =~ /^(\S+)\s*(.*)$/;
        $verb = lc $verb;
        if ($verb eq 'note' || $verb eq 'risk') { push @{ $team ? $su->{teams}{$team}{$verb} : $su->{ $verb . 's' } }, $rest; next }
        if (!$team) { $err->("'$verb' needs a team section (== Team) first"); next }
        my $t = $su->{teams}{$team};
        if    ($verb =~ /^(done|carry|drop|unblock|resume)$/) { push @{ $t->{$verb} }, split ' ', $rest }
        elsif ($verb eq 'hold')    { my ($id, $why) = split ' ', $rest, 2; $id ? push @{ $t->{hold} }, [ $id, $why // '' ] : $err->("hold needs an id") }
        elsif ($verb eq 'commit')  { my ($id, $owner) = split ' ', $rest; $id ? push @{ $t->{commit} }, [ $id, $owner ] : $err->("commit needs an id") }
        elsif ($verb eq 'assign')  { my ($id, $owner) = split ' ', $rest; $id && $owner ? push @{ $t->{assign} }, [ $id, $owner ] : $err->("assign needs id and owner") }
        elsif ($verb eq 'est')     { my ($id, $pts) = split ' ', $rest; $id && defined $pts && $pts =~ /^\d+(\.\d+)?$/ ? push @{ $t->{est} }, [ $id, $pts ] : $err->("est needs id and points") }
        elsif ($verb eq 'block')   { my ($id, $why) = split ' ', $rest, 2; $id ? push @{ $t->{block} }, [ $id, $why // '' ] : $err->("block needs an id") }
        elsif ($verb eq 'refine')  { my ($id) = split ' ', $rest; $id ? push @{ $t->{refine} }, [ $id ] : $err->("refine needs an id") }
        elsif ($verb eq 'prune')   { my ($id, $why) = split ' ', $rest, 2; $id ? push @{ $t->{prune} }, [ $id, $why // '' ] : $err->("prune needs an id") }
        elsif ($verb eq 'cap')     { $rest =~ /^\d+(\.\d+)?$/ ? $t->{cap} = $rest : $err->("cap needs a number") }
        elsif ($verb eq 'absent')  { push @{ $t->{absent} }, split ' ', $rest }
        elsif ($verb eq 'new' || $verb eq 'new!') {
            my (%meta, @title);
            my %K = (p => 'prio', e => 'epic', o => 'owner', t => 'tome');
            while ($rest =~ s/(?:^|\s)([peot]):"([^"]*)"(?=\s|$)/ /) { $meta{ $K{$1} } = $2 }   # quoted values may hold spaces: e:"Set Direction"
            my ($id, $pts, @w) = split ' ', $rest;
            if (!$id || !defined $pts || $pts !~ /^\d+(\.\d+)?$/) { $err->("new needs: id points title [p:N e:Epic t:Tome o:Owner]"); next }
            for (@w) { if (/^([peot]):(.+)$/) { $meta{ $K{$1} } = $2 } else { push @title, $_ } }
            push @{ $t->{new} }, { id => $id, pts => $pts, title => "@title", meta => \%meta, now => $verb eq 'new!' ? 1 : 0 };
        }
        else { $err->("unknown verb '$verb'") }
    }
    push @{ $su->{errors} }, "$file: no date (put YYYY-MM-DD in the file name or on the first line)" unless $su->{date};
    $su;
}
sub read_standup { my $f = shift; open my $fh, '<', $f or die "cannot open $f: $!\n"; local $/; my $t = <$fh>; close $fh; parse_standup($t, $f) }

# ---------------------------------------------------------------- compile to ledger text
sub compile {                                 # compile($scrum_state, $standup) -> ledger text ; dies listing every problem
    my ($s, $su) = @_;
    my @err = @{ $su->{errors} };
    my $unit = $s->{unit} // 'SP';
    my $out  = "\n; ---- standup $su->{date}" . ($su->{file} ne '(string)' ? " ($su->{file})" : '') . "\n";
    my $seen = {};                            # points moved within this compile: id -> {account => delta}
    my $bal  = sub { my ($id, $acct) = @_;                # no autovivification: a read must not create a task
                     ($s->{items}{$id} ? ($s->{items}{$id}{bal}{$acct} // 0) : 0) + ($seen->{$id} ? ($seen->{$id}{$acct} // 0) : 0) };
    my $move = sub { my ($id, $from, $to, $pts) = @_; $seen->{$id}{$from} -= $pts; $seen->{$id}{$to} += $pts;
                     sprintf("    %-32s  %s %s   ; id: %s\n    %-32s  %s %s   ; id: %s\n", $from, -$pts, $unit, $id, $to, $pts, $unit, $id) };
    my $meta = sub { my %m = @_; join '', map { ", $_: $m{$_}" } grep { defined $m{$_} && $m{$_} ne '' } sorted(keys %m) };
    my $known = sub { my $id = shift; return 1 if $s->{items}{$id} || $seen->{$id}; push @err, "$su->{file}: unknown task '$id'"; 0 };

    my %sprint_of;                            # pass 1: capacities and intakes for every section, so a refine/commit in an earlier section can see a new in a later one
    for my $team (@{ $su->{order} }) {
        my $t = $su->{teams}{$team};
        my $n = $sprint_of{$team} = $t->{sprint} // $su->{sprint} // $s->{current} // do { push @err, "$su->{file}: no sprint number (add 'sprint N')"; 0 };
        $out .= "~ Sprint $n\n    $team   $t->{cap} $unit\n\n" if defined $t->{cap};
        for my $it (@{ $t->{new} }) {
            my $acct = $it->{now} ? "Sprint:$n:$team:Committed" : "Backlog:$team";
            push @err, "$su->{file}: task '$it->{id}' already exists" if $s->{items}{ $it->{id} } || $seen->{ $it->{id} };
            $seen->{ $it->{id} }{$acct} += $it->{pts};
            $out .= sprintf("%s Intake %s %s\n    %-32s  %s %s   ; id: %s%s\n    Equity:Intake\n\n", $su->{date}, $it->{id}, $it->{title}, $acct, $it->{pts}, $unit, $it->{id}, $meta->(%{ $it->{meta} }));
        }
    }
    for my $team (@{ $su->{order} }) {        # pass 2: the moves
        my $t = $su->{teams}{$team};
        my $n = $sprint_of{$team};
        my $committed = "Sprint:$n:$team:Committed";
        my @post;
        my $where = sub { my $id = shift; my @l = grep { $bal->($id, $_) > 1e-9 } nub(($s->{items}{$id} ? keys %{ $s->{items}{$id}{bal} } : ()), ($seen->{$id} ? keys %{ $seen->{$id} } : ())); "@l" };
        for my $c (@{ $t->{commit} }) {
            my ($id, $owner) = @$c;
            next unless $known->($id);
            my ($from) = grep { $bal->($id, $_) > 1e-9 } ("Backlog:$team", 'Backlog:Master', map { "Sprint:$_:$team:Carryover" } reverse @{ $s->{sprints} });
            if (!$from) { push @err, "$su->{file}: '$id' is not in a backlog or carryover for $team (at: " . ($where->($id) || 'nowhere') . ")"; next }
            push @post, $move->($id, $from, $committed, $bal->($id, $from));
            $post[-1] =~ s/\n\z/, owner: $owner\n/ if $owner;
        }
        for my $rf (@{ $t->{refine} }) {          # master (or another team's) backlog -> this team's backlog
            my ($id) = @$rf;
            next unless $known->($id);
            my ($from) = grep { $bal->($id, $_) > 1e-9 } ('Backlog:Master', map { "Backlog:$_" } grep { $_ ne $team } @{ $s->{teams} });
            if (!$from) { push @err, "$su->{file}: '$id' is not in the master backlog or another team's backlog (at: " . ($where->($id) || 'nowhere') . ")"; next }
            push @post, $move->($id, $from, "Backlog:$team", $bal->($id, $from));
        }
        for my $pr (@{ $t->{prune} }) {           # retire a backlog task: -> this sprint's Removed; the reason rides on the posting
            my ($id, $why) = @$pr;
            next unless $known->($id);
            my ($from) = grep { $bal->($id, $_) > 1e-9 } ("Backlog:$team", 'Backlog:Master', map { "Backlog:$_" } @{ $s->{teams} });
            if (!$from) { push @err, "$su->{file}: '$id' is not in a backlog (at: " . ($where->($id) || 'nowhere') . "); use drop for committed work"; next }
            push @post, $move->($id, $from, "Sprint:$n:$team:Removed", $bal->($id, $from));
            ($why //= '') =~ s/,/;/g;
            $post[-1] =~ s/\n\z/, pruned: $why\n/ if $why ne '';
        }
        for my $verb (qw(done carry drop)) {
            my $to = "Sprint:$n:$team:" . { done => 'Done', carry => 'Carryover', drop => 'Removed' }->{$verb};
            for my $id (@{ $t->{$verb} }) {
                next unless $known->($id);
                my $pts = $bal->($id, $committed);
                if ($pts <= 1e-9) { push @err, "$su->{file}: '$id' is not committed in sprint $n for $team (at: " . ($where->($id) || 'nowhere') . ")"; next }
                push @post, $move->($id, $committed, $to, $pts);
            }
        }
        for my $e (@{ $t->{est} }) {
            my ($id, $pts) = @$e;
            next unless $known->($id);
            my ($loc) = split ' ', $where->($id);
            if (!$loc) { push @err, "$su->{file}: '$id' has no points to re-estimate"; next }
            my $diff = $pts - $bal->($id, $loc);
            next if abs($diff) < 1e-9;
            $seen->{$id}{$loc} += $diff;
            push @post, sprintf("    %-32s  %s %s   ; id: %s\n    %-32s  %s %s\n", $loc, $diff, $unit, $id, 'Equity:Intake', -$diff, $unit);
        }
        for my $a (@{ $t->{assign} }) { my ($id, $owner) = @$a; next unless $known->($id); push @post, _zero($id, $where->($id) || $committed, $unit, "owner: $owner") }
        for my $b (@{ $t->{block} })  { my ($id, $why) = @$b; next unless $known->($id); ($why //= '') =~ s/,/;/g; push @post, _zero($id, $where->($id) || $committed, $unit, "blocked: " . ($why || 'yes')) }
        for my $id (@{ $t->{unblock} }) { next unless $known->($id); push @post, _zero($id, $where->($id) || $committed, $unit, 'blocked:') }
        for my $b (@{ $t->{hold} })   { my ($id, $why) = @$b; next unless $known->($id); ($why //= '') =~ s/,/;/g; push @post, _zero($id, $where->($id) || $committed, $unit, "hold: " . ($why || 'yes')) }
        for my $id (@{ $t->{resume} }) { next unless $known->($id); push @post, _zero($id, $where->($id) || $committed, $unit, 'hold:') }

        $out .= "$su->{date} Standup $team\n" . join('', @post) . "\n" if @post;
    }
    die join('', map { "$_\n" } @err) if @err;
    $out;
}
sub _zero { my ($id, $acct, $unit, $m) = @_; sprintf("    %-32s  0 %s   ; id: %s, %s\n    %-32s  0 %s\n", (split ' ', $acct)[0], $unit, $id, $m, 'Equity:Intake', $unit) }

sub apply {                                   # compile, append to journal, mark file compiled; returns text appended
    my ($s, $su, $journal) = @_;
    my $text = compile($s, $su);
    open my $fh, '>>', $journal or die "cannot append to $journal: $!\n";
    print $fh $text;
    close $fh;
    mark_compiled($su->{file}) if -f $su->{file};
    $text;
}
sub mark_compiled {
    my $file = shift;
    open my $in, '<', $file or die "cannot read $file: $!\n"; local $/; my $t = <$in>; close $in;
    my @lt = localtime;
    open my $o, '>', $file or die "cannot write $file: $!\n";
    printf $o "# compiled %04d-%02d-%02d %02d:%02d\n%s", $lt[5] + 1900, $lt[4] + 1, $lt[3], $lt[2], $lt[1], $t;
    close $o;
}
sub pending {                                 # stand-up files in $dir not yet compiled, oldest first
    my $dir = shift;
    return () unless -d $dir;
    opendir my $dh, $dir or die "cannot read $dir: $!\n";
    my @f = sorted(grep { /^\d{4}-\d{2}-\d{2}.*\.txt$/ && !/-(?:chat|answers)\.txt$/ } readdir $dh);   # DATE.txt, DATE-x.txt; not chats or answers
    closedir $dh;
    grep { !read_standup($_)->{compiled} } map { "$dir/$_" } @f;
}

# ---------------------------------------------------------------- template for a new day
sub template {                                # template($s, $date, [@teams]) -> text with open items listed as comments
    my ($s, $date, $teams) = @_;
    my $n = $s->{current};
    my $out = "$date\n" . (defined $n ? "sprint $n\n" : "sprint ?\n") . "\n";
    for my $team (@{ $teams // $s->{teams} }) {
        $out .= "== $team\n";
        my @open = defined $n ? items($s, state => 'committed', sprint => $n, team => $team) : ();
        $out .= sprintf("; open: %-10s %3s  %-28s %s%s\n", $_->{id}, $_->{points}, substr($_->{title}, 0, 28), $_->{owner} // '-', $_->{blocked} ? "  BLOCKED: $_->{blocked}" : '') for @open;
        $out .= "; (nothing committed)\n" unless @open;
        $out .= "\n";
    }
    $out;
}

# ---------------------------------------------------------------- day's notes for the report
sub day_notes {                               # day_notes(@standups) -> { date, teams => { T => { done, carry, drop, new, note, risk, absent } }, notes, risks }
    my @sus = @_;
    my %d = (date => $sus[0] ? $sus[0]{date} : undef, teams => {}, notes => [], risks => [], extra => '');
    for my $su (@sus) {
        push @{ $d{notes} }, @{ $su->{notes} };
        push @{ $d{risks} }, @{ $su->{risks} };
        for my $team (@{ $su->{order} }) {
            my $t = $su->{teams}{$team};
            my $r = $d{teams}{$team} //= { done => [], carry => [], drop => [], new => [], note => [], risk => [], absent => [], block => [], refine => [], prune => [] };
            push @{ $r->{$_} }, @{ $t->{$_} } for qw(done carry drop note risk absent);
            push @{ $r->{refine} }, map { $_->[0] } @{ $t->{refine} // [] };
            push @{ $r->{prune} },  map { $_->[1] ? "$_->[0]: $_->[1]" : $_->[0] } @{ $t->{prune} // [] };
            push @{ $r->{new} },   map { "$_->{id} ($_->{pts})" } @{ $t->{new} };
            push @{ $r->{block} }, map { $_->[1] ? "$_->[0]: $_->[1]" : $_->[0] } @{ $t->{block} };
        }
    }
    \%d;
}

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Standup::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Standup::$_"} == \&{"Prelude::$_"})
          && !(defined &{"Scrum::$_"}   && \&{"Standup::$_"} == \&{"Scrum::$_"})
    } keys %Standup::;
}

1;

__END__

=head1 NAME

Standup - terse daily stand-up notes compiled into the scrum journal

=head1 SYNOPSIS

    perl bin/daily.pl new          # standups/2026-09-23.txt with each team's open items listed
    vim standups/2026-09-23.txt    # type a handful of lines per team during the stand-up
    perl bin/daily.pl all          # compile -> journal, reports, Outlook draft, git commit

=head1 THE NOTE FORMAT

One file per day, one section per team. Everything is a verb, an id, and
maybe a word or two. Story points and titles come from the journal, so you
never retype them; names are only typed when ownership changes.

    2026-09-23
    sprint 42

    == Alpha
    ; open: AUTH-103   13  SSO                          Bob
    done AUTH-103
    new AUTH-104 5 MFA enrolment p:1 e:Auth o:Ann
    commit AUTH-104
    cap 12
    note Bob out Friday

    == Bravo
    carry RPT-201
    block RPT-202 waiting on cert from ISSM
    risk cert renewal may slip the sprint
    absent Dee

Verbs: C<done carry drop> (Committed to Done / Carryover / Removed),
C<commit ID [owner]> (from the team backlog, master backlog or last sprint's
carryover into this sprint), C<new ID PTS title [p:N e:Epic o:Owner]> (intake
to the team backlog; C<new!> puts it straight into the sprint), C<est ID PTS>,
C<assign ID owner>, C<block ID reason>, C<unblock ID>, C<hold ID reason>, C<resume ID>, C<cap N>, and the
report-only C<note>, C<risk>, C<absent>. C<;> and C<#> start comments, so the
C<; open:> lines the template writes are ignored.

Compiling checks every line against the journal: unknown ids, C<done> on a
task that isn't committed in this sprint, duplicate C<new> ids, and so on,
and refuses the whole file if anything is wrong, so a typo never lands in the
journal. Once applied, the file gets a C<# compiled> first line and is skipped
thereafter; the file stays in Git as the record of the day.

=head1 FUNCTIONS

    my $conf = read_conf('scrum.conf');   my $path = find_conf();
    my $su   = read_standup('standups/2026-09-23.txt');   # or parse_standup($text, $name)
    my $text = compile($s, $su);          # ledger text, or dies with every error
    apply($s, $su, 'scrum.txt');          # compile + append + mark_compiled
    my @todo = pending('standups');       # uncompiled files, oldest first
    template($s, '2026-09-24');           # new day's file
    day_notes(@sus);                      # notes/risks/absences/done-today for the report

=head1 SEE ALSO

L<Scrum>, L<Ledger>, C<bin/daily.pl>.

=cut
