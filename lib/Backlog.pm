package Backlog;
# A backlog spreadsheet <-> GitLab: the planning workbook (or CSV) a team keeps, loaded into GitLab as epics, issues
# and tasks, and read back out of GitLab into the same columns -- so a group can be torn down and rebuilt, or moved to
# another instance, from one file. The Perl port of tools/gitlab/se-backlog/gitlab_agile_setup.py's --backlog and
# --export, on the kit's GitLab.pm (REST + GraphQL, or the offline emulator). Core Perl only: an .xlsx is a zip of XML
# (IO::Uncompress::Unzip / IO::Compress::Zip are core).
#
# The sheet (named Backlog, else the first; or a CSV) has one row per item, parents before children:
#   ID | Level | Parent | Title | Team | <Epic> | Sprint | Days | Done when | Model link | Status | Marks |
#   Iteration | Assignee | Spent (d) | GitLab
# Level is one of four names, top down (default Tome, Epic, Story, Task; "Epoch" is taken for Epic and the reverse):
#   tome  -> an epic on the group               epic -> a child epic under its tome
#   story -> an issue (weight = Days, due = the end of its planned sprint, milestone "Sprint N", label team::Team,
#            the Marks as labels), put under its epic
#   task  -> a task under its story (time estimate = Days, 8-hour days)
# The <Epic> column (headed with the second level's name) names a story's epic when Parent does not. Status is one of
# the team's states (TODO OPEN WAIT HOLD PUNT DONE DROP): set as the work-item status ([statuses] in the project
# file), as a state:: label (mode = labels), or, with no [statuses], only DONE and DROP close the item.
# Every item is titled "ID Title"; a re-import finds items by that ID and skips them (it creates, it never edits).
# The [backlog] section of the project file: levels, group, sprint = project|epic, sprints-per-epic, team-label.
use strict;
use warnings;
use Encode ();
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use IO::Compress::Zip qw($ZipError);
use Windchill;

our @COLS = ('ID', 'Level', 'Parent', 'Title', 'Team', 'EPIC', 'Sprint', 'Days', 'Done when', 'Model link', 'Status', 'Marks',
             'Iteration', 'Assignee', 'Spent (d)', 'GitLab');
our @LEVELS = ('Tome', 'Epic', 'Story', 'Task');
our @KINDS = qw(tome epic story task);
our %STATE_COLOR = (TODO => '808082', OPEN => '27235D', WAIT => 'D6292E', HOLD => 'C98500', PUNT => 'D6292E', DONE => '0CA30C', DROP => '555555');
our @MARKS = qw(REDO PASS SYNC);
my $MARK_COLOR = '6B7436';

sub columns { my $lv = shift // \@LEVELS; map { $_ eq 'EPIC' ? $lv->[1] : $_ } @COLS }
sub kind_of {                                 # kind_of(LEVEL NAME, [levels]) -> tome|epic|story|task, or undef
    my ($l, $lv) = @_;
    $lv //= \@LEVELS;
    $l = lc($l // ''); $l =~ s/^\s+|\s+$//g;
    for my $k (0 .. 3) {
        my $n = lc $lv->[$k];
        return $KINDS[$k] if $l eq $n || ($k == 1 && ($l eq 'epic' || $l eq 'epoch') && ($n eq 'epic' || $n eq 'epoch'));
    }
    undef;
}

# ---------------------------------------------------------------- configuration ([backlog] in the project file)
sub config {                                  # config(parsed project file, %overrides) -> { levels, group, numbering, per_epic, team, start, weeks, prefix, statuses }
    my ($c, %o) = @_;
    my %b = map { (lc $_->[0] => $_->[1]) } @{ $c->{backlog} // [] };
    my %pr = map { ($_->[0] => $_->[1]) } @{ $c->{project} // [] };
    my $levels = $o{levels} // $b{levels};
    my @lv = defined $levels ? (grep { length } map { s/^\s+|\s+$//gr } split /,/, $levels) : @LEVELS;
    @lv == 4 or die "Backlog: levels are four names, top down (Tome, Epic, Story, Task), not '" . ($levels // '') . "'\n";
    my $num = $b{sprint} // 'project';
    $num =~ /^(project|epic)$/ or die "Backlog: [backlog] sprint is project or epic, not '$num'\n";
    my ($sp) = grep { $_->[0] eq 'sprints' } @{ $c->{milestones} // [] };
    my ($start, undef, $weeks, $prefix) = $sp ? split(' ', $sp->[1], 4) : ();
    my $p = $o{project} // $pr{path};
    my $st = $c->{statuses} ? GitLab::parse_statuses($c->{statuses}, 'project file', $p) : undef;
    +{ levels => \@lv, group => $o{group} // $b{group} // (defined $p ? ($p =~ m{^(.*)/})[0] : undef), numbering => $num,
       per_epic => 0 + ($b{'sprints-per-epic'} // 13), team => $b{'team-label'} // 'team::', start => $o{start} // $b{start} // $start,
       weeks => 0 + ($weeks // 2), prefix => $prefix // 'Sprint ', status_mode => !$st || !@{ $st->{statuses} } ? 'none' : $st->{mode},
       status_names => [ map { $_->{name} } @{ $st ? $st->{statuses} : [] } ] };
}

# ---------------------------------------------------------------- reading: .xlsx or .csv -> { header => [..], rows => [ { column => value } ], sheet }
sub _xml_unescape { my $s = shift // ''; $s =~ s/&#x([0-9A-Fa-f]+);/chr hex $1/ge; $s =~ s/&#(\d+);/chr $1/ge; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g; $s =~ s/&apos;/'/g; $s =~ s/&amp;/&/g; $s }
sub _member {
    my ($file, $name) = @_;
    my $out;
    unzip($file => \$out, Name => $name) or return undef;
    Encode::decode('UTF-8', $out);
}
sub _col_index { my $c = uc shift; my $n = 0; $n = $n * 26 + (ord($_) - 64) for split //, $c; $n - 1 }
sub read_xlsx {
    my ($file, %o) = @_;
    my $wb = _member($file, 'xl/workbook.xml') // die "Backlog: $file is not an .xlsx workbook (no xl/workbook.xml)\n";
    my @sheets = map { my %a = /(\w+(?::\w+)?)="([^"]*)"/g; +{ name => _xml_unescape($a{name}), rid => $a{'r:id'} } } $wb =~ /<sheet\b([^>]*)\/?>/g;
    @sheets or die "Backlog: $file has no sheets\n";
    my $want = $o{sheet} // 'Backlog';
    my ($sh) = (grep({ lc $_->{name} eq lc $want } @sheets), $sheets[0]);
    my $rels = _member($file, 'xl/_rels/workbook.xml.rels') // '';
    my %tgt = map { my %a = /(\w+)="([^"]*)"/g; ($a{Id} => $a{Target}) } $rels =~ /<Relationship\b([^>]*)\/?>/g;
    my $t = $tgt{ $sh->{rid} // '' } // 'worksheets/sheet1.xml';
    $t = $t =~ s{^/}{}r; $t = "xl/$t" unless $t =~ m{^xl/};
    my $xml = _member($file, $t) // die "Backlog: $file: no $t for sheet '$sh->{name}'\n";
    my @ss;
    if (defined(my $sst = _member($file, 'xl/sharedStrings.xml'))) {
        for my $si ($sst =~ /<si>(.*?)<\/si>/gs) { (my $x = $si) =~ s{<rPh\b.*?</rPh>}{}gs; push @ss, join '', map { _xml_unescape($_) } $x =~ /<t(?:\s[^>]*)?>(.*?)<\/t>/gs }
    }
    my @grid;
    while ($xml =~ /<row\b[^>]*?(?:\/>|>(.*?)<\/row>)/gs) {
        my $body = $1 // '';
        my @r;
        while ($body =~ /<c\b([^>]*?)(?:\/>|>(.*?)<\/c>)/gs) {
            my ($attr, $in) = ($1, $2 // '');
            my ($ref) = $attr =~ /\br="([A-Z]+)\d+"/;
            my ($ty) = $attr =~ /\bt="(\w+)"/;
            my $v;
            if (($ty // '') eq 'inlineStr') { $v = join '', map { _xml_unescape($_) } $in =~ /<t(?:\s[^>]*)?>(.*?)<\/t>/gs }
            elsif ($in =~ /<v>(.*?)<\/v>/s) { $v = _xml_unescape($1); $v = $ss[$v] // '' if ($ty // '') eq 's'; $v = $v ? 'TRUE' : 'FALSE' if ($ty // '') eq 'b' }
            $v = 0 + $v if defined $v && !defined $ty && $v =~ /^-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?$/ && $v =~ /[.eE]/;   # 2.5000000000000001 -> 2.5
            my $i = defined $ref ? _col_index($ref) : scalar @r;
            $r[$i] = $v;
        }
        push @grid, \@r;
    }
    { sheet => $sh->{name}, grid => \@grid };
}
sub read_file {                               # read_file(FILE) -> { header, rows, sheet, file }
    my ($file, %o) = @_;
    -f $file or die "Backlog: cannot read $file: no such file\n";
    my $g;
    if ($file =~ /\.xlsx$/i) { $g = read_xlsx($file, %o) }
    elsif ($file =~ /\.(csv|txt)$/i) {
        open my $fh, '<:raw', $file or die "Backlog: cannot read $file: $!\n";
        my $raw = do { local $/; <$fh> }; close $fh;
        $g = { sheet => undef, grid => Windchill::parse_csv(Windchill::decode_bytes($raw)) };
    }
    else { die "Backlog: $file: give an .xlsx or a .csv file\n" }
    my @grid = @{ $g->{grid} };
    shift @grid while @grid && !grep { defined && /\S/ } @{ $grid[0] };
    my @head = map { my $h = $_ // ''; $h =~ s/^\s+|\s+$//g; $h } @{ shift(@grid) // [] };
    grep({ $_ eq 'ID' } @head) && grep({ $_ eq 'Level' } @head) && grep({ $_ eq 'Title' } @head)
        or die "Backlog: $file" . (defined $g->{sheet} ? " (sheet $g->{sheet})" : '') . ": the header needs ID, Level and Title columns (found: @head)\n";
    my @rows;
    for my $r (@grid) {
        my %h; @h{@head} = map { my $v = $_; defined $v ? ($v =~ s/^\s+|\s+$//gr) : '' } @$r[0 .. $#head];
        next unless length($h{ID} // '') || length($h{Title} // '');
        push @rows, \%h;
    }
    { header => \@head, rows => \@rows, sheet => $g->{sheet}, file => $file };
}

# ---------------------------------------------------------------- writing: rows -> .xlsx (Backlog sheet, colored states) or .csv
sub _xml { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g; $s }
sub _col_name { my $i = shift; my $s = ''; $i++; while ($i > 0) { my $m = ($i - 1) % 26; $s = chr(65 + $m) . $s; $i = int(($i - 1) / 26) } $s }
sub write_xlsx {
    my ($file, $head, $rows) = @_;
    my @st = sort keys %STATE_COLOR;
    my %fill = map { ($st[$_] => $_ + 2) } 0 .. $#st;                 # fills 0 and 1 are reserved by the format
    my $styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
        . '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        . '<fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
        . '<font><b/><sz val="11"/><color rgb="FF' . $MARK_COLOR . '"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        . '<fills count="' . (2 + @st + 1) . '"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        . join('', map { '<fill><patternFill patternType="solid"><fgColor rgb="FF' . $STATE_COLOR{$_} . '"/><bgColor indexed="64"/></patternFill></fill>' } @st)
        . '<fill><patternFill patternType="solid"><fgColor rgb="FF1F3A5F"/><bgColor indexed="64"/></patternFill></fill></fills>'
        . '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        . '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        . '<cellXfs count="' . (3 + @st + 1) . '"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        . '<xf numFmtId="0" fontId="1" fillId="' . (2 + @st) . '" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'       # 1: the header
        . '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                                       # 2: marks
        . join('', map { '<xf numFmtId="0" fontId="1" fillId="' . $fill{$_} . '" borderId="0" xfId="0" applyFont="1" applyFill="1"/>' } @st)   # 3..: states
        . '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                                       # last: bold (tome/epic rows)
        . '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
    my %sx = map { ($st[$_] => 3 + $_) } 0 .. $#st;
    my $bold = 3 + @st;
    my %width = (ID => 18, Level => 8, Parent => 18, Title => 48, Team => 12, Sprint => 7, Days => 6, 'Done when' => 40, 'Model link' => 28,
                 Status => 8, Marks => 10, Iteration => 11, Assignee => 11, 'Spent (d)' => 9, GitLab => 40);
    my $sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
        . '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        . '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        . '<cols>' . join('', map { my $w = $width{ $head->[$_] } // 14; '<col min="' . ($_ + 1) . '" max="' . ($_ + 1) . qq(" width="$w" customWidth="1"/>) } 0 .. $#$head) . '</cols><sheetData>';
    my $n = 0;
    for my $r ([ map { +{ v => $_, s => 1 } } @$head ], map { my $row = $_; my $k = lc($row->{Level} // '');
                   [ map { my $h = $_; my $v = $row->{$h};
                           +{ v => $v, s => $h eq 'Status' && $sx{ uc($v // '') } ? $sx{ uc $v } : $h eq 'Marks' && length($v // '') ? 2
                                         : ($h eq 'Title' || $h eq 'ID') && $k =~ /^(tome|epic|epoch)$/ ? $bold : 0 } } @$head ] } @$rows) {
        $n++;
        $sheet .= qq(<row r="$n">);
        for my $i (0 .. $#$r) {
            my ($v, $s) = ($r->[$i]{v}, $r->[$i]{s});
            next unless defined $v && length $v;
            my $ref = _col_name($i) . $n;
            my $sa = $s ? qq( s="$s") : '';
            if ($n > 1 && $v =~ /^-?\d+(?:\.\d+)?$/ && $head->[$i] =~ /^(Sprint|Days|Spent \(d\))$/) { $sheet .= qq(<c r="$ref"$sa><v>$v</v></c>) }
            else { $sheet .= qq(<c r="$ref"$sa t="inlineStr"><is><t xml:space="preserve">) . _xml($v) . '</t></is></c>' }
        }
        $sheet .= '</row>';
    }
    $sheet .= '</sheetData><autoFilter ref="A1:' . _col_name($#$head) . $n . '"/></worksheet>';
    my %f = (
        '[Content_Types].xml' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
            . '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            . '<Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            . '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            . '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
        '_rels/.rels' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
            . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'xl/workbook.xml' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
            . '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            . '<sheets><sheet name="Backlog" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Backlog!$A$1:$'
            . _col_name($#$head) . '$' . $n . '</definedName></definedNames></workbook>',
        'xl/_rels/workbook.xml.rels' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n"
            . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            . '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
        'xl/styles.xml' => $styles,
        'xl/worksheets/sheet1.xml' => $sheet,
    );
    my @order = ('[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/worksheets/sheet1.xml');
    my $z;
    for my $name (@order) {                   # a fixed time and no extra fields: the same rows give the same bytes
        my %zo = (Name => $name, Time => 315532800, Minimal => 1, ExtAttr => 0);
        if (!$z) { $z = IO::Compress::Zip->new($file, %zo) or die "Backlog: cannot write $file: $ZipError\n" }
        else { $z->newStream(%zo) }
        $z->print(Encode::encode('UTF-8', $f{$name}));
    }
    $z->close;
}
sub _csvq { my $v = shift // ''; $v =~ /[",\r\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v }
sub write_file {                              # write_file(FILE, [rows], levels => [..]): .xlsx or .csv (UTF-8 with a BOM, CRLF: Excel opens it)
    my ($file, $rows, %o) = @_;
    my @head = columns($o{levels});
    my $epic = $head[5];
    my @out = map { my $r = $_; +{ map { ($_ => $_ eq $epic ? $r->{$epic} // $r->{Epic} // $r->{Epoch} : $r->{$_}) } @head } } @$rows;
    if ($file =~ /\.xlsx$/i) { write_xlsx($file, \@head, \@out); return }
    $file =~ /\.csv$/i or die "Backlog: $file: write an .xlsx or a .csv file\n";
    open my $fh, '>:raw', $file or die "Backlog: cannot write $file: $!\n";
    print $fh "\xEF\xBB\xBF", Encode::encode('UTF-8', join("\r\n", map { my $r = $_; join ',', map { _csvq($r->{$_}) } @head } { map { ($_ => $_) } @head }, @out) . "\r\n");
    close $fh or die "Backlog: cannot write $file: $!\n";
}

# ---------------------------------------------------------------- the sprint a story is planned for -> its milestone and due date
sub _ymd_epoch { my ($y, $m, $d) = shift =~ /^(\d{4})-(\d\d)-(\d\d)/ or return undef; require Time::Local; Time::Local::timegm(0, 0, 12, $d, $m - 1, $y) }
sub _ymd { my @t = gmtime shift; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub sprint_of {                               # sprint_of(cfg, SPRINT CELL, EPIC INDEX) -> (project sprint number, its due date YYYY-MM-DD or undef)
    my ($cfg, $cell, $k) = @_;
    return () unless defined $cell && $cell =~ /^\s*(\d+)/;
    my $n = $1 + ($cfg->{numbering} eq 'epic' ? ($k // 0) * $cfg->{per_epic} : 0);
    my $t0 = _ymd_epoch($cfg->{start} // '') // return ($n, undef);
    ($n, _ymd($t0 + (($n - 1) * $cfg->{weeks} * 7 + $cfg->{weeks} * 7 - 3) * 86400));   # the Friday of its last week, as gitlab.pl sprints makes them
}
sub split_title {                             # "E7 Requirements and trace" -> (E7, Requirements and trace); a title without an ID -> (undef, title)
    my $t = shift // '';
    return ($1, $2) if $t =~ /^(\S*[\d.\-_]\S*)\s+(.*)$/s && $1 !~ /[:;,]$/;
    (undef, $t);
}
sub _grab { my ($d, $k) = @_; for (split /\n/, $d // '') { return $1 =~ s/^\s+|\s+$//gr if /^\*\*\Q$k\E:\*\*\s*(.*)$/ } '' }
sub _days { my $v = shift; return '' unless defined $v && length $v; my $d = $v / 28800; $d == int $d ? int $d : sprintf('%.2f', $d) + 0 }

# ---------------------------------------------------------------- import: rows -> GitLab
sub import_rows {                             # import_rows(GitLab, PROJECT, [rows], cfg) -> { log => [..], made => {epic, issue, task}, skipped, warnings => [..] }
    my ($gl, $p, $rows, $cfg) = @_;
    my $g = $cfg->{group} // die "Backlog: no group for the epics: [backlog] group = PATH (or [project] path = group/name)\n";
    my (@log, @warn, %made, $skipped);
    %made = (epic => 0, issue => 0, task => 0); $skipped = 0;
    my $dry = $gl->{dry_run};
    my %by_id;                                 # existing items by ID (the title's first word)
    my $ge = eval { $gl->work_items($g, kind => 'group', types => ['Epic']) } // [];
    for my $e (@$ge) { my ($id) = split_title($e->{title}); $by_id{"e:$id"} = $e if defined $id }
    for my $i (@{ $gl->work_items($p, kind => 'project', types => [ 'Issue', 'Task' ]) }) { my ($id) = split_title($i->{title}); $by_id{ ($i->{type} eq 'Task' ? 't:' : 'i:') . $id } = $i if defined $id }
    my %ms = map { ($_->{title} => $_) } @{ $dry && !$gl->is_local ? [] : $gl->milestones($p) };
    my %lab = map { ($_->{name} => 1) } @{ $dry && !$gl->is_local ? [] : $gl->labels($p) };
    my %status_ok = map { (uc $_ => $_) } @{ $cfg->{status_names} };
    my (%ref, %epic_index, %odd);
    my $ei = 0;
    my $epic_col = $cfg->{levels}[1];
    for my $r (@$rows) {
        my $kind = kind_of($r->{Level}, $cfg->{levels});
        my $id = $r->{ID} // '';
        if (!$kind) { push @warn, "row $id: level '" . ($r->{Level} // '') . "' is not one of " . join(', ', @{ $cfg->{levels} }) . ': skipped'; next }
        length $id or do { push @warn, "a $kind row without an ID ('" . ($r->{Title} // '') . "'): skipped"; next };
        my $title = "$id " . ($r->{Title} // '');
        my $state = uc($r->{Status} // '') || 'TODO';
        if (!$STATE_COLOR{$state} && !$status_ok{$state}) { $odd{ $r->{Status} }++; $state = 'TODO' }   # not a state ("Not started"): TODO, as the Python script
        my @marks = grep { my $m = $_; grep { $_ eq $m } @MARKS } map { uc } split /[\s,;]+/, $r->{Marks} // '';
        my $desc = join "\n\n", grep { length } ((length($r->{'Done when'} // '') ? "**Done when:** $r->{'Done when'}" : ()),
                                                  (length($r->{'Model link'} // '') ? "**Model link:** $r->{'Model link'}" : ()));
        my $setstate = sub {                   # (kind, item) -> the row's state on the item
            my ($what, $it) = @_;
            return if $state eq 'TODO' && $cfg->{status_mode} eq 'none';
            if ($what eq 'epic') { $gl->set_epic_status($g, $it->{id}, $state, mode => 'close') if $state =~ /^(DONE|DROP)$/; return }   # epics: closed, not given a status
            if ($cfg->{status_mode} eq 'none') {
                $gl->update_issue($p, $it->{iid}, state_event => 'close') if $state =~ /^(DONE|DROP)$/;
                return;
            }
            return if $state eq 'TODO';
            my $name = $status_ok{$state} // do { push @warn, "row $id: state '$state' is not in [statuses]: left as is"; return };
            my $ok = eval { $gl->set_item_status($p, $it->{iid}, $name, mode => $cfg->{status_mode}, gid => $it->{id}); 1 };
            push @warn, "row $id: status $name not set (" . ($@ =~ s/^GitLab: //r =~ s/\n$//r) . ')' unless $ok;
        };
        if ($kind eq 'tome' || $kind eq 'epic') {
            $epic_index{$id} = $ei++ if $kind eq 'epic';
            if (my $e = $by_id{"e:$id"}) { $ref{$id} = $e; $skipped++; push @log, "= epic $title"; next }
            my $parent = $kind eq 'epic' && length($r->{Parent} // '') ? $ref{ $r->{Parent} } : undef;
            push @warn, "row $id: parent $r->{Parent} not found above it: made without a parent" if $kind eq 'epic' && length($r->{Parent} // '') && !$parent;
            my $ed = join "\n\n", grep { length } $desc, ($state ne 'TODO' ? "**State:** $state" : ());   # epics carry the state in words (no status widget on them)
            my $e = $gl->create_work_item($g, kind => 'group', type => 'Epic', title => $title, (length $ed ? (description => $ed) : ()), ($parent ? (parent => $parent->{id}) : ()));
            $ref{$id} = $e; $made{epic}++;
            push @log, "+ epic $title" . ($parent ? " (under " . ($r->{Parent}) . ')' : '');
            $setstate->('epic', $e);
        } elsif ($kind eq 'story') {
            if (my $i = $by_id{"i:$id"}) { $ref{$id} = $i; $skipped++; push @log, "= issue $title"; next }
            my $ek = $r->{$epic_col} // $r->{Epic} // $r->{Epoch} // '';
            my $epic = $ref{ length($r->{Parent} // '') ? $r->{Parent} : $ek } // (length $ek ? $ref{$ek} : undef);
            my ($n, $due) = sprint_of($cfg, $r->{Sprint}, $epic_index{$ek} // $epic_index{ $r->{Parent} // '' });
            my $mt = defined $n ? "$cfg->{prefix}$n" : undef;
            my @labels;
            if (length($r->{Team} // '') && length $cfg->{team}) {
                my $tl = "$cfg->{team}$r->{Team}";
                if (!$lab{$tl}) { $gl->create_label($p, $tl, '#2f5d8a', "Team $r->{Team}"); $lab{$tl} = 1; push @log, "+ label $tl" }
                push @labels, $tl;
            }
            for my $m (@marks) { if (!$lab{$m}) { $gl->create_label($p, $m, '#6b7436', "Mark: $m"); $lab{$m} = 1; push @log, "+ label $m" } push @labels, $m }
            my $days = $r->{Days};
            my $i = $gl->create_issue($p, title => $title, description => $desc, (@labels ? (labels => join(',', @labels)) : ()),
                                      (defined $days && $days =~ /^\d+(\.\d+)?$/ ? (weight => int($days + 0.5)) : ()), ($due ? (due_date => $due) : ()),
                                      (defined $mt && $ms{$mt} ? (milestone => $mt) : ()));
            $i = { %$i, id => GitLab::_wi_gid($i->{id} // 0) };
            $ref{$id} = $i; $made{issue}++;
            push @log, "+ issue $title" . (defined $n ? " (sprint $n" . ($ms{$mt // ''} ? '' : ', no milestone') . (defined $days && length $days ? ", $days d" : '') . ')' : '');
            $gl->set_work_item_parent($p, $i->{id}, $epic->{id}) if $epic;
            push @warn, "row $id: epic '" . ($ek || $r->{Parent} // '') . "' not found above it: the issue has no epic" if !$epic && length($ek || $r->{Parent} // '');
            $setstate->('issue', $i);
        } else {
            if (my $t = $by_id{"t:$id"}) { $skipped++; push @log, "= task $title"; next }
            my $parent = $ref{ $r->{Parent} // '' };
            if (!$parent) { push @warn, "row $id: task without its story (Parent '" . ($r->{Parent} // '') . "' not above it): skipped"; next }
            my $days = $r->{Days};
            my $t = $gl->create_work_item($p, kind => 'project', type => 'Task', title => $title, (length $desc ? (description => $desc) : ()), parent => $parent->{id},
                                          (defined $days && $days =~ /^\d+(\.\d+)?$/ ? (estimate => int($days * 28800 + 0.5)) : ()));
            $made{task}++;
            push @log, "+ task $title" . (defined $days && length $days ? " ($days d)" : '');
            $setstate->('task', $t);
        }
    }
    push @warn, join(', ', map { "'$_' ($odd{$_})" } sort keys %odd) . ': not one of the states (' . join(' ', sort keys %STATE_COLOR) . '): taken as TODO' if %odd;
    { log => \@log, made => \%made, skipped => $skipped, warnings => \@warn };
}

# ---------------------------------------------------------------- export: GitLab -> rows
sub export_rows {                             # export_rows(GitLab, PROJECT, cfg) -> [ rows ] in tree order: tome, its epics, their stories, their tasks
    my ($gl, $p, $cfg) = @_;
    my $g = $cfg->{group};
    my ($tome_l, $epic_l, $story_l, $task_l) = @{ $cfg->{levels} };
    my $epics = defined $g ? (eval { $gl->work_items($g, kind => 'group', types => ['Epic']) } // []) : [];
    my $items = $gl->work_items($p, kind => 'project', types => [ 'Issue', 'Task' ]);
    my %ix = map { ($_->{id} => $_) } @$epics, @$items;
    my $rid = sub { my $x = shift; my ($id) = split_title($x->{title}); $id // ($x->{type} eq 'Epic' ? '&' : '#') . $x->{iid} };
    my $rtitle = sub { my $x = shift; my ($id, $t) = split_title($x->{title}); $t };
    my $state = sub {
        my $x = shift;
        my $s = $x->{status};
        $s //= (map { substr($_, 7) } grep { /^state::/ } @{ $x->{labels} // [] })[0];
        $s = _grab($x->{description}, 'State') || undef if !defined $s && $x->{type} eq 'Epic';
        return uc $s if defined $s && $STATE_COLOR{ uc $s };
        return $s if defined $s && length $s;
        $x->{state} eq 'closed' ? 'DONE' : 'TODO';
    };
    my $marks = sub { join ' ', grep { my $m = $_; grep { $_ eq $m } @{ $_[0]{labels} // [] } } @MARKS };
    my $sprint = sub { my $m = shift // ''; my $pre = quotemeta $cfg->{prefix}; $m =~ /^$pre(\d+)$/ ? $1 : '' };
    my $team = sub { my $pre = quotemeta($cfg->{team} // 'team::'); my ($t) = grep { length $pre && /^$pre/ } @{ $_[0]{labels} // [] }; defined $t ? $t =~ s/^$pre//r : '' };
    my (%kids, @rows);
    push @{ $kids{ $_->{parent} // '' } }, $_ for sort { ($a->{iid} // 0) <=> ($b->{iid} // 0) } @$epics, @$items;
    my $base = sub { my ($x, $level, $parent) = @_;
        +{ ID => $rid->($x), Level => $level, Parent => $parent ? $rid->($parent) : '', Title => $rtitle->($x), 'Done when' => _grab($x->{description}, 'Done when'),
           'Model link' => _grab($x->{description}, 'Model link'), Status => $state->($x), Marks => $marks->($x), GitLab => $x->{web_url} // '' } };
    my $story = sub { my ($s, $epic) = @_;
        push @rows, { %{ $base->($s, $story_l, $epic) }, Team => $team->($s), $epic_l => $epic ? $rid->($epic) : '', Sprint => $sprint->($s->{milestone}),
                      Days => $s->{weight} // '', Iteration => $s->{iteration} // '', Assignee => join(' ', @{ $s->{assignees} // [] }), 'Spent (d)' => _days($s->{spent}) };
        for my $t (grep { $_->{type} eq 'Task' } @{ $kids{ $s->{id} } // [] }) {
            push @rows, { %{ $base->($t, $task_l, $s) }, Team => $team->($s), $epic_l => $epic ? $rid->($epic) : '', Days => _days($t->{estimate}),
                          Assignee => join(' ', @{ $t->{assignees} // [] }), 'Spent (d)' => _days($t->{spent}), Sprint => '' };
        }
    };
    my $epic_rows; $epic_rows = sub { my ($e, $parent, $depth) = @_;
        push @rows, { %{ $base->($e, $depth ? $epic_l : $tome_l, $parent) } };
        for my $k (@{ $kids{ $e->{id} } // [] }) {
            if ($k->{type} eq 'Epic') { $epic_rows->($k, $e, 1) }
            elsif ($k->{type} eq 'Issue') { $story->($k, $e) }
        }
    };
    $epic_rows->($_, undef, 0) for grep { !defined $_->{parent} || !$ix{ $_->{parent} } } @$epics;
    my @loose = grep { $_->{type} eq 'Issue' && (!defined $_->{parent} || !$ix{ $_->{parent} }) } @$items;
    if (@loose) {
        push @rows, { ID => 'UNPLANNED', Level => $epic_l, Parent => '', Title => 'Issues with no epic', Status => 'OPEN' };
        my $from = @rows;
        $story->($_, undef) for @loose;
        for (@rows[ $from .. $#rows ]) { next unless $_->{Level} eq $story_l; $_->{Parent} = 'UNPLANNED'; $_->{$epic_l} = 'UNPLANNED' }
    }
    \@rows;
}

1;
