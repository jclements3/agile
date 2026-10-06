# sim/tidewater-model.pl -- the model side of the Tidewater simulation (required by sim/tidewater-sim.pl).
#
#   tw_convert($kit)->($drop_dir, $model_dir)   the drop intake converter: XMI -> model/<group>/, ReqIF -> model/doors/,
#                                               the prime's test results -> verification/results-prime.csv
#   tw_edit($name, $clone, %o)                  one of the government's hand edits (idempotent): returns the files it changed
#
# The intake converter runs the kit's two converters with examples/tidewater-v1/layout.map: the layered layout
# (library -> requirements -> logical -> physical -> analysis -> verification, one folder per segment under physical/),
# so every drop lands on the same paths -- which is what lets git merge the prime's next drop into the government's
# edited copy. The edits are the work of the port: each replaces converter TODO lines with
# hand-written SysML v2, and each is written to be re-applied after a vendor merge takes the prime's side of a file.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Temp qw(tempdir);


sub _slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub _spew { my ($f, $t) = @_; (my $d = $f) =~ s{/[^/]+$}{}; make_path($d); open my $fh, '>:raw', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
sub _run_q { my @cmd = @_; my $o = ''; if (open my $fh, '-|', @cmd) { local $/; $o = <$fh> // ''; close $fh } ($o, $? >> 8) }

sub tw_convert {                                    # the drop intake converter: both converters with examples/tidewater-v1/layout.map
    my ($kit, %o) = @_;
    my $map = $o{map} // "$kit/examples/tidewater-v1/layout.map";
    return sub {
        my ($drop, $model) = @_;
        opendir my $dh, $drop or die "cannot read $drop: $!\n";
        my @f = sort readdir $dh; closedir $dh;
        my ($xmi) = grep { /\.xmi$/i } @f;
        my ($req) = grep { /\.reqifz?$/i } @f;
        my ($o, $rc) = _run_q($^X, "$kit/bin/xmi2sysml.pl", '--layout-map', $map, '--out', $model, "$drop/$xmi");
        die "xmi2sysml.pl failed on $drop/$xmi: $o" if $rc;
        if (defined $req && !$o{no_doors}) {
            ($o, $rc) = _run_q($^X, "$kit/bin/reqif2sysml.pl", '--layout-map', $map, '--out', $model, "$drop/$req");
            die "reqif2sysml.pl failed on $drop/$req: $o" if $rc;
        }
        if (-f "$drop/results.csv") {                 # the prime's test report rides in the drop (from drop 4)
            (my $root = $model) =~ s{/model/?$}{};
            make_path("$root/verification");
            my $t = _slurp("$drop/results.csv"); $t =~ s/\r\n/\n/g;
            _spew("$root/verification/results-prime.csv", $t);
        }
    };
}

# ---------------------------------------------------------------- the government's edits
my %PROCURED = (DataLogger => ['Notional Logger Co.', 'LG-100'], SolarPanel => ['Notional Solar Ltd.', 'SP-40'], Modem => ['Notional Radio Inc.', 'MD-2']);

sub _import {                                       # add `private import P::*;` after the package line, once
    my ($t, $pkg) = @_;
    return $t if $t =~ /private import \Q$pkg\E::\*;/;
    $t =~ s/^(package \S+ \{\n)/$1    private import $pkg\::*;\n/m;
    $t;
}
sub _edit_file { my ($c, $rel, $f) = @_; my $p = "$c/$rel"; my $t = _slurp($p) // return (); my $n = $f->($t); return () if !defined $n || $n eq $t; _spew($p, $n); ($rel) }

my %EDIT;
$EDIT{conventions} = sub {                          # the government's conventions package: the v1 profile, in SysML v2
    my ($c) = @_;
    my $t = <<'SYSML';
// Government-owned (model/library/conventions): the conventions every Tidewater package uses. They replace the v1 "Tidewater Profile":
// its level stereotypes become level metadata (model.pl checks them against the part tree) and Procured becomes
// metadata with the same two tags. The converter cannot carry a profile, so this file is written by hand, once.
package Conventions {
    doc /* Level tags for the part tree and the Procured marking, replacing the v1 Tidewater Profile. */
    private import ScalarValues::String;
    metadata def L1Network { doc /* The whole observation network. */ }
    metadata def L2Segment { doc /* A segment: stations, data services or field operations. */ }
    metadata def L3Station { doc /* A station, a service or a facility within a segment. */ }
    metadata def L4Subsystem { doc /* A subsystem: a separately specified unit. */ }
    metadata def L5Assembly { doc /* An assembly within a subsystem. */ }
    metadata def L6Component { doc /* A component: the lowest level this model describes. */ }
    metadata def Procured {
        doc /* A part bought, not built: its supplier and part number (the v1 Procured stereotype's tags). */
        attribute supplier : String;
        attribute partNumber : String;
    }
}
SYSML
    my @ch;
    push @ch, 'model/library/conventions/Conventions.sysml' if (_slurp("$c/model/library/conventions/Conventions.sysml") // '') ne $t && do { _spew("$c/model/library/conventions/Conventions.sysml", $t); 1 };
    my $readme = "# model/library/conventions -- government-owned SysML v2\n\nThe prime's drops never write here. The conventions every package uses: the level tags model.pl checks and\n"
               . "the Procured marking, replacing the v1 Tidewater Profile (which the converter cannot carry). Government additions\n"
               . "live in the layer they belong to: these conventions in library/, the hand-written behavior in logical/GovBehavior.sysml.\n";
    push @ch, 'model/library/conventions/README.md' if (_slurp("$c/model/library/conventions/README.md") // '') ne $readme && do { _spew("$c/model/library/conventions/README.md", $readme); 1 };
    @ch;
};
$EDIT{levels} = sub {                               # level stereotype TODOs -> @L<n> metadata, in one file
    my ($c, %o) = @_;
    _edit_file($c, $o{file}, sub {
        my $t = shift;
        my $n = $t =~ s{^(\s*)// TODO stereotype Tidewater_Profile:(L\d\w+) on this element \(xmi:id [^)]*\) not converted\n}{$1\@$2;\n}mg;
        $n ? _import($t, 'Conventions') : $t;
    });
};
$EDIT{procured} = sub {                             # Procured stereotype TODOs -> @Procured { supplier; partNumber; }
    my ($c, %o) = @_;
    _edit_file($c, $o{file}, sub {
        my $t = shift;
        my $out = ''; my $part = '';
        for my $l (split /(?<=\n)/, $t) {
            $part = $1 if $l =~ /^\s*part def (\w+)/;
            if ($l =~ m{^(\s*)// TODO stereotype Tidewater_Profile:Procured on this element}) {
                my ($sup, $pn) = @{ $PROCURED{$part} // [ 'unknown', 'unknown' ] };
                $l = qq($1\@Procured { supplier = "$sup"; partNumber = "$pn"; }\n);
            }
            $out .= $l;
        }
        $out ne $t ? _import($out, 'Conventions') : $t;
    });
};
$EDIT{units} = sub {                                # the v1 units: value types specialize ISQ quantities
    my ($c) = @_;
    _edit_file($c, 'model/library/Types.sysml', sub {
        my $t = shift;
        my %isq = (Power => ['ISQ::PowerValue', 'W'], Energy => ['ISQ::EnergyValue', 'Wh']);
        for my $k (sort keys %isq) {
            $t =~ s/attribute def $k :> ScalarValues::Real \{\n(\s*)\/\/ SysML 1\.x unit: [^\n]*\n/attribute def $k :> $isq{$k}[0] {\n$1\/\/ unit: $isq{$k}[1] (v1 unit carried by the ISQ quantity kind)\n/;
        }
        $t =~ s/(attribute def Percentage :> ScalarValues::Real \{\n\s*)\/\/ SysML 1\.x unit: percent[^\n]*\n/$1\/\/ unit: percent, a dimensionless ratio 0..100\n/;
        $t =~ s{^\s*// TODO uml:InstanceSpecification '(?:watt|watt hour|percent)' [^\n]*\n}{}mg;
        $t;
    });
};
$EDIT{include} = sub {                              # the v1 Include -> an include use case
    my ($c) = @_;
    _edit_file($c, 'model/physical/network/Network.sysml', sub {
        my $t = shift;
        $t =~ s{^(\s*)// TODO uml:Include \(xmi:id [^)]*\): [^\n]*\n}{$1include use case queryArchive : QueryArchive;\n}m;
        $t;
    });
};
$EDIT{profile} = sub {                              # the profile TODO: replaced by model/library/conventions/Conventions.sysml
    my ($c) = @_;
    _edit_file($c, 'model/library/Tidewater.sysml', sub {
        my $t = shift;
        $t =~ s{^(\s*)// TODO uml:Profile 'Tidewater Profile' (\(xmi:id [^)]*\))[^\n]*\n}{$1// v1 Tidewater Profile $2: replaced by model/library/conventions/Conventions.sysml (level tags, Procured)\n}m;
        $t;
    });
};
sub _gov_behavior {                                 # model/logical/GovBehavior.sysml: hand-written behavior the converter cannot carry
    my (%o) = @_;
    my @states = ('observing', 'degraded', 'maintenance', 'recovered', ($o{storm} ? 'storm' : ()));
    my @tr = (['observing', 'degraded', 'LowBattery'], ['degraded', 'observing', 'Charged'], ['observing', 'maintenance', 'CrewOnSite'],
              ['degraded', 'maintenance', 'CrewOnSite'], ['maintenance', 'observing', 'CrewDeparts'], ['maintenance', 'recovered', 'LiftedAboard'],
              ($o{storm} ? (['observing', 'storm', 'StormWarning'], ['storm', 'observing', 'StormPassed']) : ()));
    my %sig; $sig{ $_->[2] } = 1 for @tr;
    my $t = "// Government-owned (model/logical/GovBehavior.sysml): behavior written by hand where the v1 model has a construct the converter leaves\n"
          . "// as a TODO (state machines, interactions). Each replaces a TODO line elsewhere in model/; the delta report of every\n"
          . "// prime drop says when the v1 original changed, and the change is reworked here by hand.\n"
          . "package GovBehavior {\n    doc /* Hand-written SysML v2 for the v1 state machine BuoyModes" . ($o{upload} ? ' and the v1 interaction DailyUpload' : '') . ". */\n";
    $t .= "    item def $_;\n" for sort keys %sig;
    $t .= "    state def BuoyModes {\n        doc /* v1 state machine BuoyModes, on MooredBuoy. */\n        entry; then observing;\n";
    $t .= "        state $_;\n" for @states;
    $t .= "        transition first $_->[0] accept $_->[2] then $_->[1];\n" for @tr;
    $t .= "    }\n";
    if ($o{upload}) {
        my @m = ('sendObservations', 'acknowledge', 'notifyNewData', ($o{resend} ? 'requestResend' : ()));
        $t .= "    action def DailyUpload {\n        doc /* v1 sequence DailyUpload (buoy, ingest, forecaster) as ordered steps. */\n";
        $t .= "        action $_;\n" for @m;
        $t .= "        first $m[$_ - 1] then $m[$_];\n" for 1 .. $#m;
        $t .= "    }\n";
    }
    $t . "}\n";
}
$EDIT{statemachine} = sub {                         # BuoyModes: TODO -> exhibit state, the state def in logical/GovBehavior
    my ($c, %o) = @_;
    my @ch;
    my $cur = _slurp("$c/model/logical/GovBehavior.sysml") // '';
    my $new = _gov_behavior(storm => ($o{storm} || $cur =~ /state storm;/) ? 1 : 0, upload => ($cur =~ /action def DailyUpload/ ? 1 : 0), resend => ($cur =~ /requestResend/ ? 1 : 0));
    if ($new ne $cur) { _spew("$c/model/logical/GovBehavior.sysml", $new); push @ch, 'model/logical/GovBehavior.sysml' }
    push @ch, _edit_file($c, 'model/physical/stations/Stations.sysml', sub {
        my $t = shift;
        my $n = $t =~ s{^(\s*)// TODO uml:StateMachine 'BuoyModes' \(xmi:id [^)]*\)[^\n]*\n}{$1exhibit state modes : BuoyModes;\n}m;
        $n ? _import($t, 'GovBehavior') : $t;
    });
    @ch;
};
$EDIT{interaction} = sub {                          # DailyUpload: TODO -> perform action, the steps in logical/GovBehavior
    my ($c, %o) = @_;
    my @ch;
    my $cur = _slurp("$c/model/logical/GovBehavior.sysml") // '';
    my $new = _gov_behavior(storm => ($cur =~ /state storm;/ ? 1 : 0), upload => 1, resend => ($o{resend} || $cur =~ /requestResend/) ? 1 : 0);
    if ($new ne $cur) { _spew("$c/model/logical/GovBehavior.sysml", $new); push @ch, 'model/logical/GovBehavior.sysml' }
    push @ch, _edit_file($c, 'model/physical/network/Network.sysml', sub {
        my $t = shift;
        my $n = $t =~ s{^(\s*)// TODO uml:Interaction 'DailyUpload' \(xmi:id [^)]*\)[^\n]*\n}{$1perform action dailyUpload : DailyUpload;\n}m;
        $n ? _import($t, 'GovBehavior') : $t;
    });
    @ch;
};
$EDIT{flows} = sub {                                # ObserveCoast: the fork, the pin, the object and control flows
    my ($c) = @_;
    _edit_file($c, 'model/logical/Behavior.sysml', sub {
        my $t = shift;
        $t =~ s{^(\s*)// TODO uml:ForkNode 'after check' \(xmi:id [^)]*\)[^\n]*\n}{$1fork afterCheck;\n}m;
        $t =~ s{^(\s*)action 'log health';\n\s*// TODO uml:InputPin 'report' \(xmi:id [^)]*\)[^\n]*\n}{$1action 'log health' { in report : HealthReport; }\n}m;
        $t =~ s{^(\s*)// TODO uml:ObjectFlow \(xmi:id [^)]*\)[^\n]*\n}{$1flow publish.bulletin to bulletin;\n}m;
        $t =~ s{^(\s*)// TODO uml:ControlFlow \(xmi:id [^)]*\)[^\n]*\n}{$1first afterCheck then 'log health';\n}m;
        $t;
    });
};
$EDIT{constraint} = sub {                           # EnergyBalance: the expression, from the TODO line's own text
    my ($c) = @_;
    _edit_file($c, 'model/analysis/Analysis.sysml', sub {
        my $t = shift;
        $t =~ s{^(\s*)// TODO constraint expression \(parametrics\) not converted\n}{$1attribute sunHours : ScalarValues::Real;\n}m;
        if ($t =~ m{^(\s*)// TODO uml:Constraint 'balance' \(xmi:id [^)]*\): constraint: English: ([^\n]*)\n}m) {
            my ($ind, $expr) = ($1, $2);
            my $extra = $expr =~ /\breserve\b/ && $t !~ /attribute reserve\b/ ? "${ind}attribute reserve : Energy;\n" : '';
            $t =~ s{^\s*// TODO uml:Constraint 'balance' [^\n]*\n}{$extra$ind$expr\n}m;
        }
        $t;
    });
};
$EDIT{legacy} = sub {                               # untangle: the Legacy Import package is clutter from the document port
    my ($c) = @_;
    return () unless -f "$c/model/legacy/Legacy_Import.sysml";
    unlink "$c/model/legacy/Legacy_Import.sysml";
    ('model/legacy/Legacy_Import.sysml');
};
$EDIT{cycles} = sub {                               # break the package cycles: the v1 Dependency lines that close them
    my ($c, %o) = @_;
    my $w = $o{which} // 'both';
    my @ch;
    # the dependency line, and the import the converter added only for it
    push @ch, _edit_file($c, 'model/physical/operations/Operations.sysml', sub { my $t = shift; $t =~ s{^\s*dependency from ServiceVessel to Technician; // dependency\n}{}m and $t =~ s{^\s*private import Network::\*;\n}{}m; $t }) if $w ne 'sd';
    push @ch, _edit_file($c, 'model/physical/datacenter/DataCenter.sysml', sub { my $t = shift; $t =~ s{^\s*dependency from QualityControl to SensorSuite; // dependency\n}{}m and $t =~ s{^\s*private import Stations::\*;\n}{}m; $t }) if $w ne 'no';
    @ch;
};
$EDIT{wavesensor} = sub {                           # the v1 level is wrong: WaveSensor is a direct part of MooredBuoy (L4), tagged L5
    my ($c) = @_;
    _edit_file($c, 'model/physical/stations/Stations.sysml', sub {
        my $t = shift;
        $t =~ s{(part def WaveSensor \{\n\s*)\@L5Assembly;\n}{$1\@L4Subsystem;   // v1 says L5; it is a direct part of MooredBuoy (DR-7)\n};
        $t;
    });
};
$EDIT{ifdocs} = sub {                               # what crosses each interface, said once, in the model
    my ($c) = @_;
    my %doc = (observation => 'One record per observation cycle, on the schedule TW-SYS-002 sets.',
               health => 'Sent with every transmission; the data center flags a station whose report is late.',
               bulletin => 'Issued on the schedule TW-SYS-006 sets; the public service shows the latest.',
               latest => 'The newest good observation from each station, for the public service.');
    _edit_file($c, 'model/library/Interfaces.sysml', sub {
        my $t = shift;
        for my $k (sort keys %doc) { $t =~ s{^(\s*)out item $k : (\w+);\n}{$1out item $k : $2 { doc /* $doc{$k} */ }\n}m }
        $t;
    });
};
$EDIT{spaghetti} = sub {                            # ObservingStation's trace spaghetti: 11 traces that duplicate its satisfies
    my ($c, %o) = @_;
    _edit_file($c, 'model/physical/stations/Stations.sysml', sub {
        my $t = shift;
        $t =~ s{^\s*dependency from ObservingStation to TW_SYS_\d+; // trace\n}{}mg;
        $t;
    }), ($o{lose} ? _edit_file($c, 'model/requirements/model/Requirements.sysml', sub {   # the slip the trace ratchet catches
        my $t = shift; $t =~ s{^\s*satisfy $o{lose} by [^\n]*\n}{}m; $t }) : ());
};

sub tw_edit {
    my ($name, $c, %o) = @_;
    my $e = $EDIT{$name} or die "no edit '$name'\n";
    $e->($c, %o);
}
sub tw_edits { sort keys %EDIT }

1;
