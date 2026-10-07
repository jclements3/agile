package Windchill;
# Windchill requests -> GitLab issues, and GitLab progress -> a sheet for Windchill. The users of a program submit
# DevSecOps requests in Windchill (PTC); the team plans and works them in GitLab (sprints, boards, merge requests). There
# is no API between them on a managed network, so the bridge is a file each way:
#
#   in:   a Windchill report or search result exported as CSV  -> intake(): one issue per new Windchill number
#   out:  status() -> one row per Windchill-sourced issue (state, board column, sprint, MRs, release) -> CSV to send back
#
# The mapping lives in the [windchill] section of the project file (tools/gitlab/templates/project.conf): which column
# holds the number, title, state, type, requester, priority, need date and description; the link template; the labels
# every issue gets; the states that are imported; and a priority -> priority:: label map.
#
# An issue made by intake is titled "NUMBER: title" and ends with a hidden marker,
#   <!-- windchill number="WC-000123" state="Open" priority="High" title="..." -->
# which records what Windchill said when the issue was made. A later export is compared with the marker (or with the
# marker of the latest "Windchill update" comment), so the team may retitle or relabel the issue freely: only changes
# on the Windchill side are reported as drift. Core Perl only.
use strict;
use warnings;
use Encode ();
use GitLab ();

my %DEFAULT = (number => 'Number', title => 'Name', state => 'State', type => 'Type', requester => 'Created By', priority => 'Priority',
               'need-date' => 'Need Date', description => 'Description', url => '', labels => 'source::windchill, type::story', accept => '*',
               'priority-map' => '');
my @FIELDS = qw(number title state type requester priority need-date description);
my %MON = (jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6, jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12);

sub _list { my $v = shift // ''; [ grep { length } map { s/^\s+|\s+$//gr } split /,/, $v ] }

# ---------------------------------------------------------------- configuration
sub config {                                  # config(parsed project file, FILE) -> { col => {field => header}, url, labels, accept, pmap, source }
    my ($c, $file) = @_;
    my %v = %DEFAULT;
    for (@{ $c->{windchill} // [] }) {
        my $k = lc $_->[0];
        exists $DEFAULT{$k} or die "$file:$_->[2]: unknown [windchill] key '$_->[0]' (" . join(', ', sort keys %DEFAULT) . ")\n";
        $v{$k} = $_->[1];
    }
    my %pmap;
    for (@{ _list($v{'priority-map'}) }) { /^(.+?)\s*=\s*(\S+)$/ or die "$file: [windchill] priority-map entries are WINDCHILL=LABEL, not '$_'\n"; $pmap{ lc $1 } = $2 }
    my $labels = _list($v{labels});
    my ($source) = grep { /^source::/ } @$labels;
    my $acc = _list($v{accept});
    +{ col => { map { ($_ => $v{$_}) } @FIELDS }, url => $v{url}, labels => $labels, pmap => \%pmap, source => $source // 'source::windchill',
       accept => (!@$acc || grep { $_ eq '*' } @$acc) ? undef : { map { (lc $_ => 1) } @$acc } };
}
sub config_file {                             # config_file(PATH) -> (config, project path from [project] or undef)
    my $path = shift;
    open my $fh, '<:raw', $path or die "Windchill: cannot read $path: $!\n";
    my $c = GitLab::parse_project_file(do { local $/; <$fh> }, $path); close $fh;
    my ($p) = map { $_->[1] } grep { $_->[0] eq 'path' } @{ $c->{project} // [] };
    (config($c, $path), $p);
}

# ---------------------------------------------------------------- reading the export
sub decode_bytes {                            # bytes -> text: UTF-16 (BOM or not), UTF-8 (BOM or not), else Windows-1252; LF line ends
    my $raw = shift;
    my $t;
    if    ($raw =~ /^\xFF\xFE/) { $t = Encode::decode('UTF-16LE', substr($raw, 2)) }
    elsif ($raw =~ /^\xFE\xFF/) { $t = Encode::decode('UTF-16BE', substr($raw, 2)) }
    elsif ($raw =~ /^(?:[^\0]\0){4}/) { $t = Encode::decode('UTF-16LE', $raw) }
    elsif ($raw =~ /^(?:\0[^\0]){4}/) { $t = Encode::decode('UTF-16BE', $raw) }
    else { $t = eval { Encode::decode('UTF-8', $raw, Encode::FB_CROAK) } // Encode::decode('cp1252', $raw) }
    $t =~ s/^\x{FEFF}//;
    $t =~ s/\r\n?/\n/g;
    $t;
}
sub parse_csv {                               # text -> [ [cells] ]; the separator (comma, tab or semicolon) is read off the header line
    my $t = shift;
    my ($head) = $t =~ /^([^\n]*)/;
    (my $bare = $head // '') =~ s/"[^"]*"//g;
    my %n = map { ($_ => scalar(() = $bare =~ /\Q$_\E/g)) } (',', "\t", ';');
    my ($sep) = sort { $n{$b} <=> $n{$a} || ($a eq ',' ? -1 : $b eq ',' ? 1 : 0) } keys %n;
    my (@rows, @row, $cell);
    my $i = 0;
    my $len = length $t;
    my $q = quotemeta $sep;
    while ($i <= $len) {
        if ($i < $len && substr($t, $i, 1) eq '"') {          # a quoted cell: "" is a quote, separators and newlines are text
            my $j = $i + 1; $cell = '';
            while (1) {
                my $k = index($t, '"', $j);
                if ($k < 0) { $cell .= substr($t, $j); $i = $len; last }
                $cell .= substr($t, $j, $k - $j);
                if (substr($t, $k + 1, 1) eq '"') { $cell .= '"'; $j = $k + 2; next }
                $i = $k + 1; last;
            }
            $cell .= $1 if substr($t, $i) =~ /^([^\n$q]*)/ and $i += length $1;   # text after the closing quote, kept
        } else {
            substr($t, $i) =~ /^([^\n$q]*)/; $cell = $1; $i += length $1;
        }
        push @row, $cell;
        if ($i >= $len) { push @rows, [@row] if grep { length } @row; last }
        my $ch = substr($t, $i, 1); $i++;
        if ($ch eq "\n") { push @rows, [@row] if grep { length } @row; @row = () }
    }
    \@rows;
}
sub iso_date {                                # 2026-11-02, 11/2/2026, 02-Nov-2026, 2 Nov 2026 (a time after it is ignored) -> YYYY-MM-DD or undef
    my $s = shift // '';
    return sprintf('%04d-%02d-%02d', $1, $2, $3) if $s =~ /^\s*(\d{4})-(\d{1,2})-(\d{1,2})\b/;
    return sprintf('%04d-%02d-%02d', $3, $1, $2) if $s =~ m{^\s*(\d{1,2})/(\d{1,2})/(\d{4})\b};
    return sprintf('%04d-%02d-%02d', $3, $MON{ lc $2 }, $1) if $s =~ /^\s*(\d{1,2})[-\s]([A-Za-z]{3})[A-Za-z]*[-\s,]+(\d{4})\b/ && $MON{ lc $2 };
    undef;
}
sub read_export {                             # read_export(FILE, config) -> { records => [ {field => value, line} ], warnings => [..] }
    my ($file, $cfg) = @_;
    open my $fh, '<:raw', $file or die "Windchill: cannot read $file: $!\n";
    my $raw = do { local $/; <$fh> }; close $fh;
    my $rows = parse_csv(decode_bytes($raw));
    @$rows or die "Windchill: $file is empty (export a Windchill report or search result as CSV)\n";
    my @head = map { s/^\s+|\s+$//gr } @{ shift @$rows };
    my %at;
    for my $k (0 .. $#head) { $at{ lc $head[$k] } //= $k }
    my %col;
    for my $f (@FIELDS) { my $h = $cfg->{col}{$f}; $col{$f} = $at{ lc $h } if defined $h && length $h && defined $at{ lc $h } }
    for my $f (qw(number title)) {
        defined $col{$f} or die "Windchill: $file has no '$cfg->{col}{$f}' column for the $f (its columns: " . join(', ', @head)
            . "); set $f = COLUMN in [windchill]\n";
    }
    my (@rec, @warn, %seen);
    my $line = 1;
    for my $r (@$rows) {
        $line++;
        my %x = (line => $line);
        $x{$_} = defined $col{$_} ? ($r->[ $col{$_} ] // '') =~ s/^\s+|\s+$//gr : '' for @FIELDS;
        if (!length $x{number}) { push @warn, "row $line: no Windchill number; skipped"; next }
        if ($seen{ $x{number} }++) { push @warn, "row $line: $x{number} appears again; the first row is used"; next }
        push @rec, \%x;
    }
    +{ records => \@rec, warnings => \@warn, columns => \@head };
}

# ---------------------------------------------------------------- the issue: body, marker, drift
sub _attr { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/"/&quot;/g; $s =~ s/--/-&#45;/g; $s =~ s/\n/ /g; $s }
sub _unattr { my $s = shift; $s =~ s/&#45;/-/g; $s =~ s/&quot;/"/g; $s =~ s/&amp;/&/g; $s }
sub marker { my $r = shift; '<!-- windchill ' . join(' ', map { $_ . '="' . _attr($r->{$_}) . '"' } qw(number state priority title)) . ' -->' }
sub read_marker {                             # text -> { number, state, priority, title } of the last marker, or undef
    my $t = shift // '';
    my @m = $t =~ /<!-- windchill (.*?) -->/g or return undef;
    my %h; $h{$1} = _unattr($2) while $m[-1] =~ /(\w+)="([^"]*)"/g;
    \%h;
}
sub issue_link { my ($cfg, $num) = @_; my $u = $cfg->{url} // ''; length $u ? $u =~ s/\{number\}/$num/gr : undef }
sub _cell { my $s = shift // ''; $s =~ s/\|/\\|/g; $s =~ s/\n/ /g; length $s ? $s : '-' }
sub body {                                    # the issue description for one request
    my ($r, $cfg) = @_;
    my $u = issue_link($cfg, $r->{number});
    my $num = $u ? "[$r->{number}]($u)" : $r->{number};
    my $d = $r->{description} // '';
    join '', "Windchill request $num, submitted by " . (length $r->{requester} ? $r->{requester} : 'an unnamed requester') . ".\n\n",
        "| Windchill | |\n|---|---|\n", (map { "| $_->[0] | " . _cell($_->[1]) . " |\n" }
            [ 'Number', $num ], [ 'Type', $r->{type} ], [ 'State', $r->{state} ], [ 'Priority', $r->{priority} ],
            [ 'Requested by', $r->{requester} ], [ 'Need date', $r->{'need-date'} ]),
        "\n### The request\n\n", (length $d ? $d : '(no description in the export)'), "\n\n",
        "<!-- Keep the Windchill number at the start of the title: intake and status find the issue by it. -->\n", marker($r), "\n";
}
sub _labels { my ($r, $cfg) = @_; my $pl = $cfg->{pmap}{ lc($r->{priority} // '') }; [ @{ $cfg->{labels} }, ($pl ? $pl : ()) ] }
sub _number_of {                              # an issue -> its Windchill number (marker first, then the title), or undef
    my ($i) = @_;
    my $m = read_marker($i->{description});
    return $m->{number} if $m && length($m->{number} // '');
    $i->{title} =~ /^\s*([^\s:]+)\s*:/ ? $1 : undef;
}

# ---------------------------------------------------------------- intake
sub intake {                                  # intake($gl, PROJECT, FILE, config, note => 1) -> { rows, created, skipped, drift, lines => [..] }
    my ($gl, $p, $file, $cfg, %o) = @_;
    my $x = read_export($file, $cfg);
    my (%by_num, %by_title);
    for my $i (@{ $gl->issues($p, state => 'all') }) {
        my $m = read_marker($i->{description});
        $by_num{ $m->{number} } //= $i if $m && length($m->{number} // '');
        $by_title{$1} //= $i if $i->{title} =~ /^\s*([^\s:]+)\s*:/;
    }
    my %s = (rows => scalar @{ $x->{records} } + scalar @{ $x->{warnings} }, created => 0, skipped => 0, drift => 0, lines => [ map { "warning: $_" } @{ $x->{warnings} } ]);
    $s{skipped} += @{ $x->{warnings} };
    for my $r (@{ $x->{records} }) {
        my $i = $by_num{ $r->{number} } // $by_title{ $r->{number} };
        if ($i) {
            my $was = read_marker($i->{description}) // {};
            if (!$gl->{dry_run} || $gl->is_local) {       # the latest "Windchill update" comment wins over the description
                for my $n (@{ (eval { $gl->issue_notes($p, $i->{iid}) }) // [] }) { my $m = read_marker($n->{body}); $was = $m if $m }
            }
            my @ch = map { my ($f, $old) = ($_, $was->{$_} // ''); $old ne ($r->{$f} // '') ? "$f '" . $old . "' -> '" . ($r->{$f} // '') . "'" : () } qw(title state priority);
            if (@ch && %$was) {
                $s{drift}++;
                push @{ $s{lines} }, "drift   #$i->{iid} $r->{number}: " . join('; ', @ch);
                if ($o{note}) {
                    $gl->add_note($p, 'issue', $i->{iid}, "Windchill update (from " . ($file =~ s{.*[/\\]}{}r) . "): " . join('; ', @ch) . ".\n\n" . marker($r) . "\n");
                    push @{ $s{lines} }, "noted   #$i->{iid} $r->{number}";
                }
            } else { $s{skipped}++; push @{ $s{lines} }, "exists  #$i->{iid} $r->{number}" }
            next;
        }
        if ($cfg->{accept} && !$cfg->{accept}{ lc $r->{state} }) {
            $s{skipped}++; push @{ $s{lines} }, "skipped $r->{number}: state '$r->{state}' is not accepted (accept = " . join(', ', sort keys %{ $cfg->{accept} }) . ')';
            next;
        }
        my $due = iso_date($r->{'need-date'});
        my $title = length $r->{title} ? "$r->{number}: $r->{title}" : "$r->{number}: (no title in Windchill)";
        my $new = $gl->create_issue($p, title => $title, description => body($r, $cfg), labels => _labels($r, $cfg), ($due ? (due_date => $due) : ()));
        $s{created}++;
        push @{ $s{lines} }, "created #" . ($new->{iid} // '?') . " $title";
        $by_num{ $r->{number} } = $new;
    }
    push @{ $s{lines} }, "windchill: $s{rows} rows, $s{created} created, $s{skipped} skipped, $s{drift} drift";
    \%s;
}

# ---------------------------------------------------------------- status: what to send back
my $CLOSES = qr/\b(?:close[sd]?|closing|fix(?:e[sd]|ing)?|resolve[sd]?|resolving|implement(?:s|ed|ing)?|refs?|related\s+to)\b\s*:?\s+((?:#\d+(?:\s*(?:,|and)\s*)?)+)/i;
sub _mr_issues {                              # an MR -> the issue iids it closes or names (description, title, branch feature/12-...)
    my $m = shift;
    my %n;
    for my $t ($m->{description} // '', $m->{title} // '') { while ($t =~ /$CLOSES/g) { my $l = $1; $n{$_} = 1 for $l =~ /#(\d+)/g } }
    $n{$1} = 1 if ($m->{source_branch} // '') =~ m{^(?:[\w.-]+/)?(\d+)-};
    keys %n;
}
sub status {                                  # status($gl, PROJECT, config, since => DATE) -> [ { number, iid, state, workflow, milestone, closed, mrs, release, url } ]
    my ($gl, $p, $cfg, %o) = @_;
    my @iss = grep { my $i = $_; (grep { $_ eq $cfg->{source} } @{ $i->{labels} // [] }) || read_marker($i->{description}) } @{ $gl->issues($p, state => 'all') };
    @iss = grep { substr($_->{updated_at} // $_->{created_at} // '', 0, 10) ge $o{since} } @iss if $o{since};
    my %mrs;
    for my $m (@{ $gl->mrs($p, state => 'all') }) { push @{ $mrs{$_} }, $m for _mr_issues($m) }
    my %rel = map { ($_->{tag_name} => $_) } @{ (eval { $gl->releases($p) }) // [] };
    my %tags;
    my @rows;
    for my $i (sort { $a->{iid} <=> $b->{iid} } @iss) {
        my @m = sort { $a->{iid} <=> $b->{iid} } @{ $mrs{ $i->{iid} } // [] };
        my ($wf) = map { s/^workflow:://r } grep { /^workflow::/ } @{ $i->{labels} // [] };
        my $release = '';
        for my $mr (grep { $_->{state} eq 'merged' } @m) {
            my $sha = $mr->{merge_commit_sha} // $mr->{squash_commit_sha} // $mr->{sha} // next;
            my $t = $tags{$sha} //= (eval { $gl->tags_containing($p, $sha) }) // [];
            my ($r) = sort { ($a->{released_at} // $a->{created_at} // '') cmp ($b->{released_at} // $b->{created_at} // '') || $a->{tag_name} cmp $b->{tag_name} } map { $rel{$_} // () } @$t;
            my $name = $r ? $r->{tag_name} : (sort @$t)[0];
            $release = $name if defined $name && (!length $release || $name lt $release);
        }
        push @rows, { number => _number_of($i) // '', iid => $i->{iid}, state => $i->{state} eq 'opened' ? 'open' : $i->{state}, workflow => $wf // '',
                      milestone => ref $i->{milestone} ? $i->{milestone}{title} // '' : '', closed => substr($i->{closed_at} // '', 0, 10),
                      mrs => join('; ', map { "!$_->{iid} $_->{state}" } @m), release => $release, url => $i->{web_url} // '' };
    }
    \@rows;
}
my @COLS = ([ number => 'windchill' ], [ iid => 'issue' ], [ state => 'state' ], [ workflow => 'workflow' ], [ milestone => 'milestone' ],
            [ closed => 'closed' ], [ mrs => 'merge_requests' ], [ release => 'release' ], [ url => 'url' ]);
sub _csvq { my $v = shift // ''; $v =~ /[",\r\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v }
sub status_csv { my $rows = shift; join '', join(',', map { $_->[1] } @COLS) . "\r\n", map { my $r = $_; join(',', map { _csvq($r->{ $_->[0] }) } @COLS) . "\r\n" } @$rows }
sub status_text {
    my $rows = shift;
    return "no Windchill requests in GitLab yet (gitlab.pl windchill intake EXPORT.csv)\n" unless @$rows;
    my @c = @COLS[0 .. 7];
    my @w = map { my $k = $_->[0]; my $m = length $_->[1]; for (@$rows) { my $l = length($k eq 'iid' ? "#$_->{iid}" : $_->{$k} // ''); $m = $l if $l > $m } $m } @c;
    my $fmt = join('  ', map { "%-${_}s" } @w) . "\n";
    my $out = sprintf $fmt, map { $_->[1] } @c;
    for my $r (@$rows) { $out .= sprintf $fmt, map { my $k = $_->[0]; my $v = $k eq 'iid' ? "#$r->{iid}" : $r->{$k} // ''; length $v ? $v : '-' } @c }
    $out =~ s/ +$//mg;
    $out;
}

1;
