#!/usr/bin/perl
# IDEF0 model -> product backlog, as a planning stand-up file the kit compiles.
#
#   model  (tA Name)          -> tome  "A Name"          and one team per model
#   level-1 activity (A1)     -> epic  "A1 Name"
#   leaf activity (A111 ...)  -> task  A-111  in the model's team backlog
#   cross-model link (A1.o1 > B2.c1 Flow)
#                             -> interface task IF-n in the DESTINATION team's backlog, under the
#                                SOURCE epic -- so the epic spans two teams and the planning tree
#                                flags it as an integration point. Interfaces are the architect's job.
#
# Reads the output of tools/idef0/idef0.pl dump and links (so this never parses IDEF0 itself).
#
#   perl sim/idef0-backlog.pl MODEL.md [--date YYYY-MM-DD] [--sprint N] > standups/DATE.txt
#   perl sim/idef0-backlog.pl MODEL.md --roster           # the generated team rosters (who owns what)
#
# Standalone tool -- not part of the tested kit. Pure core Perl.
use strict;
use warnings;
use FindBin;
use Getopt::Long;

my %o = (date => '2026-09-23', sprint => 1, people => 6);
GetOptions(\%o, 'date=s', 'sprint=i', 'people=i', 'roster', 'cap=i', 'commit') or exit 2;   # --commit: also commit each team's top tasks up to --cap (sprint planning)
my $model = shift @ARGV or die "usage: idef0-backlog.pl MODEL.md [--date D] [--sprint N] [--roster]\n";
my $tool = "$FindBin::Bin/../tools/idef0/idef0.pl";

# ---- team name per model: one word, safe in "== Team" sections and Backlog:<Team> accounts -- the model
# name's first word unless the alias table knows a better one (filled in once the models are parsed)
my %TEAM;
my %ALIAS = ('Customer Support & Feedback' => 'Support', 'Human Resources' => 'HR', 'Research & Development' => 'Research',
             'Executive & Strategy' => 'Executive'

);
my @FIRST = qw(Ann Bob Cy Dee Eve Fay Gus Hal Ida Jon Kim Lou Max Nia Ola Pat Quinn Ray Sam Tia Uma Val Wes Xia Yul Zed);

# ---- parse the dump: models, activities (id, name, depth), children
my (%model_name, %act, @order);
open my $d, '-|', 'perl', $tool, 'dump', $model or die "cannot run $tool: $!\n";
while (<$d>) {
    chomp;
    if (/^([A-Z])\s{2,}(.+?)\s{2,}\[/)            { $model_name{$1} = $2; next }
    if (/^(\s*)([A-Z]\d+)\s{2,}(\S.*)$/) {          # activity line: id then name
        my ($indent, $id, $name) = (length $1, $2, $3);
        $act{$id} = { id => $id, name => $name, model => substr($id, 0, 1), depth => length($id) - 1, kids => 0 };
        push @order, $id;
        my $parent = substr($id, 0, -1);
        $act{$parent}{kids}++ if length($parent) > 1 && $act{$parent};
    }
}
close $d;
die "no activities found in $model (is tools/idef0/idef0.pl runnable?)\n" unless @order;
for my $m (keys %model_name) { my $n = $model_name{$m}; $TEAM{$m} = $ALIAS{$n} // (($n =~ /([A-Za-z0-9]+)/)[0] // $m) }

# ---- links from the INTERFACES table: SOURCE DEST FLOW
my @links;
open my $l, '-|', 'perl', $tool, 'links', $model or die $!;
while (<$l>) { chomp; next if /^SOURCE/ || !/\S/; my ($src, $dst, $flow) = split /\s{2,}/, $_, 3; push @links, [ $src, $dst, $flow ] if $src && $dst }
close $l;

# ---- rosters: N people per team, deterministic
my %roster; my $pi = 0;
for my $m (sort keys %model_name) { $roster{$m} = [ map { $FIRST[ ($pi++) % @FIRST ] . " $TEAM{$m}" } 1 .. $o{people} ] }
if ($o{roster}) { print "$TEAM{$_} ($_ $model_name{$_}): @{ [ join ', ', @{ $roster{$_} } ] }\n" for sort keys %model_name; exit 0 }

# ---- emit the planning stand-up file
sub q_ { my $s = shift; $s =~ s/,/;/g; $s =~ s/"/'/g; qq("$s") }
sub epic_of { my $id = shift; my $e = substr($id, 0, 2); $act{$e} ? "$e $act{$e}{name}" : "$id $act{$id}{name}" }
sub tome_of { my $m = shift; "$m $model_name{$m}" }
my %n; my %pick;
sub owner { my $m = shift; my $r = $roster{$m}; $r->[ $pick{$m}++ % @$r ] }
print "$o{date}\nsprint $o{sprint}\n";
for my $m (sort keys %model_name) {
    my $team = $TEAM{$m} // $m;
    print "\n== $team\n";
    print "cap $o{cap}\n" if $o{cap};
    for my $id (grep { $act{$_}{model} eq $m && $act{$_}{kids} == 0 } @order) {
        my $a = $act{$id};
        my $pts = $a->{depth} == 1 ? 8 : $a->{depth} == 2 ? 5 : 3;      # an undecomposed level-1 activity is big; deep leaves are small
        my $prio = $a->{depth} <= 2 ? 1 : $a->{depth} == 3 ? 2 : 3;
        (my $tid = $id) =~ s/^([A-Z])/$1-/;
        printf "new %s %d %s p:%d e:%s t:%s o:%s\n", $tid, $pts, $a->{name} =~ s/,/;/gr, $prio, q_(epic_of($id)), q_(tome_of($m)), q_(owner($m));
    }
}
my $i = 0;
my (%by_team, %tasks);                        # tasks: team letter -> [ {id, pts, prio} ] for --commit
for my $id (@order) { my $a = $act{$id}; next if $a->{kids}; (my $tid = $id) =~ s/^([A-Z])/$1-/;
    push @{ $tasks{ $a->{model} } }, { id => $tid, pts => $a->{depth} == 1 ? 8 : $a->{depth} == 2 ? 5 : 3, prio => $a->{depth} <= 2 ? 1 : $a->{depth} == 3 ? 2 : 3 } }
for my $lk (@links) {
    my ($src, $dst, $flow) = @$lk;
    my ($sa) = $src =~ /^([A-Z]\d+)/; my ($da) = $dst =~ /^([A-Z]\d+)/;
    next unless $sa && $da && $act{$sa} && $act{$da};
    my $dm = substr($da, 0, 1); my $sm = substr($sa, 0, 1);
    push @{ $by_team{$dm} }, sprintf("new IF-%d 5 Interface: %s from %s to %s p:1 e:%s t:%s o:%s", ++$i, ($flow =~ s/,/;/gr), $TEAM{$sm}, $TEAM{$dm},
        q_(epic_of($sa)), q_(tome_of($sm)), q_(owner($dm)));
    push @{ $tasks{$dm} }, { id => "IF-$i", pts => 5, prio => 1 };
}
for my $m (sort keys %by_team) { print "\n== $TEAM{$m}\n", map { "$_\n" } @{ $by_team{$m} } }
if ($o{commit} && $o{cap}) {                  # planning: commit by priority (interfaces first among equals) until the next task would bust the cap
    for my $m (sort keys %tasks) {
        my $sum = 0; my @c;
        for my $t (sort { $a->{prio} <=> $b->{prio} || ($b->{id} =~ /^IF/) <=> ($a->{id} =~ /^IF/) || $a->{id} cmp $b->{id} } @{ $tasks{$m} }) {
            next if $sum + $t->{pts} > $o{cap};
            push @c, $t->{id}; $sum += $t->{pts};
        }
        print "\n== $TEAM{$m}\n", map { "commit $_\n" } @c if @c;
    }
}
