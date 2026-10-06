#!/usr/bin/perl
# sim/tidewater-v1.pl [OUTDIR] -- a notional SysML v1 project, written the way the legacy tools export it, for testing
# the v1 -> v2 port pipeline (bin/xmi2sysml.pl, bin/reqif2sysml.pl) on something bigger than the Courier fixtures.
#
# Tidewater is a fictional coastal weather-observation network: moored buoys and shore stations observe, a data
# center ingests, checks, archives and publishes a marine bulletin, and a field crew services the stations.
# Structure only; every value is notional. Writes (default OUTDIR = examples/tidewater-v1):
#
#   tidewater.xmi   Cameo/MagicDraw 2022x-style XMI: blocks on six levels, ports and interface blocks, IBD connectors,
#                   activities with object flows and a fork, a state machine, a sequence interaction, use cases with
#                   actors and an include, a constraint block bound in a parametric, requirements of several Cameo
#                   kinds, satisfy / verify / deriveReqt / refine / trace / allocate, test cases, value types with
#                   units, a project profile (level stereotypes and a Procurement stereotype), diagrams in xmi:Extension
#   tidewater.reqif DOORS 9.7-style ReqIF 1.2: three formal modules with headings, XHTML text, a verification-method
#                   enumeration, owner, and "derived from" links
#   tidewater.csv   the same three modules as a DOORS CSV export
#
# The model is the spider web a document port leaves behind: about 45 diagrams, stale ones included; a "Legacy Import"
# package of duplicated, unused and placeholder blocks; Trace and Dependency lines that make package cycles
# (Stations <-> DataCenter, Network <-> Operations) and pile 11 traces on ObservingStation; prose pasted from the SRS
# into comments. The run prints those measures for the drop. The prime removes the clutter in later drops (drop 3
# deletes "Copy of SensorSuite", drop 6 the whole "Legacy Import" package) after the government's Discrepancy Reports.
#
# Planted, so the port has something to find (see README.md next to the output):
#   TW-SYS-012 has no satisfy; TW-SYS-011, TW-SEG-002 and TW-SEG-009 have no verify;
#   TW-SYS-016 is in DOORS only, TW-SEG-009 is in the model only; TW-SYS-006's text differs between the two.
#
# Prime drops (--drop N, default 1): the prime contractor keeps maintaining this v1 model and delivers it again under
# the CDRL. Each drop is cumulative; ids are stable (an element keeps its xmi:id from drop to drop, as Cameo's do), so
# drops can be compared element by element (bin/xmi2sysml.pl --delta) and their conversions merged as a vendor branch.
#   perl sim/tidewater-v1.pl                      drop 1 into examples/tidewater-v1
#   perl sim/tidewater-v1.pl --drop 3 OUTDIR      drop 3 (v1.2) into OUTDIR, with MANIFEST.txt
use strict;
use warnings;
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);
use Digest::SHA qw(sha256_hex);
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Xmi ();

my $DROP = 1;
GetOptions('drop=i' => \$DROP) or die "usage: tidewater-v1.pl [--drop N] [OUTDIR]\n";
# drop, version, delivery date (a Friday), change summary
my @DROPS = (
    [1, 'v1.0', '2026-10-02', 'Initial delivery: the model at contract start.'],
    [2, 'v1.1', '2027-01-08', 'Hygrometer added to the sensor suite; TW-SYS-017 humidity; TW-SYS-006 model text aligned with DOORS.'],
    [3, 'v1.2', '2027-04-02', 'Storm mode in BuoyModes; Fuse added to the power system; TW-SEG-009 deleted; TW-SEG-010 added; TW-SYS-012 satisfied by ServiceVessel; Copy of SensorSuite deleted.'],
    [4, 'v1.3', '2027-07-02', 'Salinity in ObservationRecord; DriftingBuoy added; TW-SYS-016 added to the model; TW-SYS-002 text revised.'],
    [5, 'v1.4', '2027-10-01', 'EnergyBalance expression revised (reserve term); activity PublishBulletin renamed IssueBulletin.'],
    [6, 'v1.5', '2028-01-07', 'TW-SYS-019 partner sharing; DailyUpload gains requestResend; Legacy Import package deleted.'],
    [7, 'v1.6', '2028-03-03', 'Verification added for TW-SYS-011 (AnalyzeEnergyBalance) and TW-SEG-002; documentation edits.'],
);
die "--drop must be 1 to " . scalar(@DROPS) . "\n" if $DROP < 1 || $DROP > @DROPS;
my (undef, $VERSION, $DELIVERED, $SUMMARY) = @{ $DROPS[ $DROP - 1 ] };
sub at { $DROP >= $_[0] }                                  # this drop includes the change made in drop N
my $OUT = shift // ($DROP == 1 ? 'examples/tidewater-v1' : die "--drop $DROP needs an OUTDIR\n");
make_path($OUT);
my $STAMP = "${DELIVERED}T09:00:00Z";

# ---------------------------------------------------------------- ids and escaping
my (%ID, %DEF, @APPS);
sub id  { my ($k) = @_; $ID{$k} //= '_22_1_7f3a0c1_' . substr(md5_hex($k), 0, 12) }    # stable: the same key gets the same id in every drop
sub def { my ($k) = @_; die "$k defined twice\n" if $DEF{$k}++; id($k) }
sub esc { my ($s) = @_; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s =~ s/\n/&#10;/g; $s }
sub app { my ($stereo, $base, $key, %tags) = @_;                            # a stereotype application
    my $t = join '', map { qq( $_="@{[ esc($tags{$_}) ]}") } sort keys %tags;
    push @APPS, qq(  <$stereo xmi:id="@{[ id("app:$stereo:$key") ]}" $base="@{[ id($key) ]}"$t/>\n) }
my $PRIM = 'http://www.omg.org/spec/UML/20131001/PrimitiveTypes.xmi';

# ---------------------------------------------------------------- the requirements, shared by the model and DOORS
# id, module/section, title, Cameo kind, verification method, derived from, where (both|model|doors), owner, text
my @REQ = (
 ['TW-STK-001','Stakeholder Needs','Coastal coverage','Requirement','',[],'both','Network Office',
  'The network shall provide marine weather observations for the coastal region it covers.'],
 ['TW-STK-002','Stakeholder Needs','Timely observations','Requirement','',[],'both','Network Office',
  'Forecasters shall receive observations in time to use them in the next bulletin.'],
 ['TW-STK-003','Stakeholder Needs','Public access','Requirement','',[],'both','Network Office',
  'Mariners shall be able to read the latest bulletin and observations from a public service.'],
 ['TW-STK-004','Stakeholder Needs','Serviceable in the field','Requirement','',[],'both','Network Office',
  'Field crews shall be able to service any station from a single service vessel.'],
 ['TW-STK-005','Stakeholder Needs','Observation history','Requirement','',[],'both','Network Office',
  'Past observations shall be kept so earlier conditions can be reviewed.'],
 ['TW-STK-006','Stakeholder Needs','Off-grid operation','Requirement','',[],'both','Network Office',
  'Offshore stations shall keep observing without shore power.'],

 ['TW-SYS-001','System Requirements/Functions','Measure conditions','functionalRequirement','Test',['TW-STK-001'],'both','Station Engineering',
  'Each station shall measure wind, air pressure and air temperature, and each buoy shall also measure waves.'],
 ['TW-SYS-002','System Requirements/Functions','Scheduled transmission','functionalRequirement','Test',['TW-STK-002'],'both','Station Engineering',
  'Each station shall transmit its observations to the data center on a fixed schedule.'],
 ['TW-SYS-003','System Requirements/Functions','Ingest','functionalRequirement','Test',['TW-STK-002'],'both','Data Services',
  'The data center shall ingest every observation it receives.'],
 ['TW-SYS-004','System Requirements/Functions','Quality control','functionalRequirement','Test',['TW-STK-002'],'both','Data Services',
  'The data center shall flag observations that fail a quality check.'],
 ['TW-SYS-005','System Requirements/Functions','Archive','functionalRequirement','Demonstration',['TW-STK-005'],'both','Data Services',
  'The data center shall archive every observation together with its quality flag.'],
 ['TW-SYS-006','System Requirements/Functions','Bulletin','functionalRequirement','Demonstration',['TW-STK-003'],'both','Data Services',
  'The data center shall publish a marine bulletin on a fixed schedule.'],
 ['TW-SYS-007','System Requirements/Functions','Latest observations','functionalRequirement','Demonstration',['TW-STK-003'],'both','Data Services',
  'The public service shall show the latest observation from every station.'],
 ['TW-SYS-008','System Requirements/Interfaces','Observation interface','interfaceRequirement','Test',['TW-STK-002'],'both','Station Engineering',
  'Stations shall send observations to the data center over the observation interface.'],
 ['TW-SYS-009','System Requirements/Interfaces','Health reporting','interfaceRequirement','Test',['TW-STK-004'],'both','Station Engineering',
  'Stations shall report their health to the data center over the health interface.'],
 ['TW-SYS-010','System Requirements/Interfaces','Public interface','interfaceRequirement','Inspection',['TW-STK-003'],'both','Data Services',
  'The data center shall offer observations through a documented public interface.'],
 ['TW-SYS-011','System Requirements/Operations','Own power','performanceRequirement','Analysis',['TW-STK-006'],'both','Station Engineering',
  'Each buoy shall run from its own solar panel and battery.'],
 ['TW-SYS-012','System Requirements/Operations','Vessel access','designConstraint','Inspection',['TW-STK-004'],'both','Field Operations',
  'Every station shall be serviceable from the service vessel.'],
 ['TW-SYS-013','System Requirements/Operations','Store and forward','functionalRequirement','Test',['TW-STK-002'],'both','Station Engineering',
  'Each station shall keep observations it could not send and send them once the link returns.'],
 ['TW-SYS-014','System Requirements/Operations','Operating mode','functionalRequirement','Test',['TW-STK-004'],'both','Station Engineering',
  'Each station shall report its operating mode.'],
 ['TW-SYS-015','System Requirements/Operations','Bulletin log','functionalRequirement','Inspection',['TW-STK-005'],'both','Data Services',
  'The data center shall keep a log of every bulletin it published.'],
 ['TW-SYS-016','System Requirements/Operations','Common time','interfaceRequirement','Test',['TW-STK-002'],'doors','Station Engineering',
  'All stations and the data center shall use a common time reference.'],

 ['TW-SEG-001','Segment Requirements/Stations','Sensor height','physicalRequirement','Inspection',['TW-SYS-001'],'both','Station Engineering',
  'The buoy hull shall carry the sensor suite above the waterline.'],
 ['TW-SEG-002','Segment Requirements/Stations','Watch circle','performanceRequirement','Analysis',['TW-SYS-001'],'both','Station Engineering',
  'The mooring shall keep the buoy within its assigned watch circle.'],
 ['TW-SEG-003','Segment Requirements/Stations','State of charge','functionalRequirement','Test',['TW-SYS-011'],'both','Station Engineering',
  'The power system shall report the battery state of charge.'],
 ['TW-SEG-004','Segment Requirements/Stations','Retry','functionalRequirement','Test',['TW-SYS-013'],'both','Station Engineering',
  'The telemetry unit shall retry a failed transmission.'],
 ['TW-SEG-005','Segment Requirements/Data Center','Duplicates','functionalRequirement','Test',['TW-SYS-003'],'both','Data Services',
  'The ingest service shall discard duplicate observations.'],
 ['TW-SEG-006','Segment Requirements/Data Center','Flag reason','functionalRequirement','Test',['TW-SYS-004'],'both','Data Services',
  'The quality control service shall record why an observation was flagged.'],
 ['TW-SEG-007','Segment Requirements/Data Center','Retrieval','functionalRequirement','Demonstration',['TW-SYS-005'],'both','Data Services',
  'The archive shall return any observation by station and time.'],
 ['TW-SEG-008','Segment Requirements/Data Center','Issue time','functionalRequirement','Inspection',['TW-SYS-006'],'both','Data Services',
  'The publisher shall stamp each bulletin with its issue time.'],
 ['TW-SEG-009','Segment Requirements/Stations','Lowerable mast','designConstraint','Inspection',['TW-SYS-012'],'model','Field Operations',
  'The shore station mast shall be lowerable for maintenance.'],
);
my %DOORS_TEXT = ('TW-SYS-006' => 'The data center shall publish a marine bulletin <b>twice a day</b>, on a fixed schedule.');   # planted drift (drop 1)
my %R = map { $_->[0] => $_ } @REQ;
# the drops' requirement changes (cumulative)
if (at(2)) {
    $R{'TW-SYS-006'}[8] = 'The data center shall publish a marine bulletin twice a day, on a fixed schedule.';    # aligned with DOORS
    push @REQ, ['TW-SYS-017','System Requirements/Functions','Humidity','functionalRequirement','Test',['TW-STK-001'],'both','Station Engineering',
        'Each station shall measure relative humidity.'];
}
if (at(3)) {
    @REQ = grep { $_->[0] ne 'TW-SEG-009' } @REQ;
    push @REQ, ['TW-SEG-010','Segment Requirements/Stations','Fuse','functionalRequirement','Test',['TW-SYS-011'],'both','Station Engineering',
        'The fuse shall isolate a shorted load.'];
}
if (at(4)) {
    $R{'TW-SYS-016'}[6] = 'both';
    $R{'TW-SYS-002'}[8] = 'Each station shall transmit its observations to the data center on a fixed schedule, at least every hour.';
}
if (at(6)) {
    push @REQ, ['TW-SYS-019','System Requirements/Interfaces','Partner sharing','interfaceRequirement','Demonstration',['TW-STK-003'],'both','Data Services',
        'The data center shall share observations with partner agencies.'];
}
%R = map { $_->[0] => $_ } @REQ;
my %NAME = at(5) ? (PublishBulletin => 'IssueBulletin') : ();     # renamed in drop 5: same element, same xmi:id

# ---------------------------------------------------------------- model building blocks
sub comment { my ($key, $body, $ind) = @_;
    return qq($ind<ownedComment xmi:type="uml:Comment" xmi:id="@{[ id("c:$key") ]}" body="@{[ esc($body) ]}">\n)
         . qq($ind  <annotatedElement xmi:idref="@{[ id($key) ]}"/>\n$ind</ownedComment>\n) }
sub mult { my ($k, $lo, $hi, $ind) = @_; return '' unless defined $lo;
    return qq($ind<lowerValue xmi:type="uml:LiteralInteger" xmi:id="@{[ id("$k:lo") ]}" value="$lo"/>\n)
         . qq($ind<upperValue xmi:type="uml:LiteralUnlimitedNatural" xmi:id="@{[ id("$k:hi") ]}" value="$hi"/>\n) }
sub prim { my ($t) = @_; qq(<type href="$PRIM#$t"/>) }

# block(NAME, level => 'L3System', doc => ..., gen => PARENT, abstract => 1, parts => [[name, Type, lo, hi]...],
#       refs => [[name, Type]], values => [[name, ValueType|prim:Real, default]], ports => [[name, Type, proxy|full|flow, conj, dir]],
#       connectors => [[name, [partA, portA], [partB, portB]]], extra => sub { xml }, procured => [supplier, partNo])
sub block {
    my ($name, %a) = @_;
    my $k = $name; my $i = '      ';
    my $x = qq(    <packagedElement xmi:type="uml:Class" xmi:id="@{[ def($k) ]}" name="$name") . ($a{abstract} ? ' isAbstract="true"' : '') . ">\n";
    $x .= comment($k, $a{doc}, $i) if $a{doc};
    my $nn = 0;
    for my $note (@{ $a{notes} || [] }) {                 # prose pasted from a document, as a second comment
        my $ck = "note" . ++$nn . ":$k";
        $x .= qq($i<ownedComment xmi:type="uml:Comment" xmi:id="@{[ id($ck) ]}" body="@{[ esc($note) ]}">\n$i  <annotatedElement xmi:idref="@{[ id($k) ]}"/>\n$i</ownedComment>\n);
    }
    $x .= qq($i<generalization xmi:type="uml:Generalization" xmi:id="@{[ id("gen:$k") ]}" general="@{[ id($a{gen}) ]}"/>\n) if $a{gen};
    for my $p (@{ $a{parts} // [] }) {
        my ($pn, $t, $lo, $hi) = @$p; my $pk = "$k.$pn";
        $x .= qq($i<ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def($pk) ]}" name="$pn" type="@{[ id($t) ]}" aggregation="composite");
        $x .= defined $lo ? ">\n" . mult($pk, $lo, $hi, "$i  ") . "$i</ownedAttribute>\n" : "/>\n";
    }
    for my $p (@{ $a{refs} // [] }) {
        my ($pn, $t) = @$p;
        $x .= qq($i<ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def("$k.$pn") ]}" name="$pn" type="@{[ id($t) ]}"/>\n);
    }
    for my $p (@{ $a{values} // [] }) {
        my ($pn, $t, $dv) = @$p; my $pk = "$k.$pn";
        my $type = $t =~ /^prim:(.*)/ ? prim($1) : undef;
        $x .= qq($i<ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def($pk) ]}" name="$pn") . ($type ? '' : qq( type="@{[ id($t) ]}")) . ">\n";
        $x .= "$i  $type\n" if $type;
        $x .= qq($i  <defaultValue xmi:type="uml:LiteralReal" xmi:id="@{[ id("$pk:dv") ]}" value="$dv"/>\n) if defined $dv;
        $x .= "$i</ownedAttribute>\n";
    }
    for my $p (@{ $a{ports} // [] }) {
        my ($pn, $t, $kind, $conj, $dir) = @$p; my $pk = "$k.$pn";
        my $type = $t =~ /^prim:(.*)/ ? prim($1) : undef;
        $x .= qq($i<ownedAttribute xmi:type="uml:Port" xmi:id="@{[ def($pk) ]}" name="$pn" aggregation="composite") . ($conj ? ' isConjugated="true"' : '')
            . ($type ? ">\n$i  $type\n$i</ownedAttribute>\n" : qq( type="@{[ id($t) ]}"/>\n));
        if    ($kind eq 'proxy') { app('sysml:ProxyPort', 'base_Port', $pk) }
        elsif ($kind eq 'full')  { app('sysml:FullPort', 'base_Port', $pk) }
        elsif ($kind eq 'flow')  { app('sysml:FlowPort', 'base_Port', $pk, direction => $dir // 'inout') }
    }
    for my $c (@{ $a{connectors} // [] }) {
        my ($cn, $e1, $e2) = @$c; my $ck = "$k:cn:" . ($cn // 'c' . ++$a{_cc});
        $x .= qq($i<ownedConnector xmi:type="uml:Connector" xmi:id="@{[ id($ck) ]}") . ($cn ? qq( name="$cn") : '') . ">\n";
        my $n = 0;
        for my $e ($e1, $e2) {
            my ($part, $port) = @$e; $n++;
            my $pt = ref $port ? $port->[0] : $port;             # [Type.port] when the port is on the part's type
            $x .= qq($i  <end xmi:type="uml:ConnectorEnd" xmi:id="@{[ id("$ck:e$n") ]}" role="@{[ id($pt) ]}") . ($part ? qq( partWithPort="@{[ id("$k.$part") ]}") : '') . "/>\n";
        }
        $x .= "$i</ownedConnector>\n";
    }
    $x .= $a{extra}->($k, $i) if $a{extra};
    $x .= "    </packagedElement>\n";
    app('sysml:Block', 'base_Class', $k);
    app("Tidewater_Profile:$a{level}", 'base_Class', $k) if $a{level};
    app('Tidewater_Profile:Procured', 'base_Class', $k, supplier => $a{procured}[0], partNumber => $a{procured}[1]) if $a{procured};
    return $x;
}
sub leaf { my ($name, $level, $doc, %a) = @_; block($name, level => $level, doc => $doc, %a) }
sub dep { my ($kind, $client, $supplier) = @_;          # a Trace (stereotyped Abstraction) or a plain Dependency drawn on a diagram
    my $k = "dep:$kind:$client:$supplier";
    app('sysml:Trace', 'base_Abstraction', $k) if $kind eq 'Trace';
    my $t = $kind eq 'Trace' ? 'Abstraction' : 'Dependency';
    return qq(    <packagedElement xmi:type="uml:$t" xmi:id="@{[ def($k) ]}" client="@{[ id($client) ]}" supplier="@{[ id($supplier) ]}"/>\n) }
sub package_ { my ($name, $doc, @body) = @_;
    my $k = "pkg:$name";
    return qq(  <packagedElement xmi:type="uml:Package" xmi:id="@{[ def($k) ]}" name="$name">\n)
         . ($doc ? comment($k, $doc, '    ') : '') . join('', @body) . "  </packagedElement>\n" }

# ---------------------------------------------------------------- packages
my @PKG;

# the project profile: Cameo exports the profile with the model; its stereotypes are unknown to the converter (TODOs)
push @PKG, qq(  <packagedElement xmi:type="uml:Profile" xmi:id="@{[ def('profile') ]}" name="Tidewater Profile">\n)
    . join('', map { qq(    <packagedElement xmi:type="uml:Stereotype" xmi:id="@{[ def("st:$_") ]}" name="$_"/>\n) }
                   qw(L1Network L2Segment L3Station L4Subsystem L5Assembly L6Component Procured))
    . "  </packagedElement>\n";

push @PKG, package_('Types', 'Value types and units used across the network.',
    (map { my ($vt, $unit) = @$_;
           app('sysml:ValueType', 'base_DataType', $vt, unit => '');
           $APPS[-1] =~ s/ unit=""/ unit="@{[ id("unit:$unit") ]}"/;
           qq(    <packagedElement xmi:type="uml:DataType" xmi:id="@{[ def($vt) ]}" name="$vt">\n)
         . qq(      <generalization xmi:type="uml:Generalization" xmi:id="@{[ id("gen:$vt") ]}"><general href="$PRIM#Real"/></generalization>\n)
         . "    </packagedElement>\n" } ['Power', 'watt'], ['Energy', 'watt hour'], ['Percentage', 'percent']),
    (map { app('sysml:Unit', 'base_InstanceSpecification', "unit:$_");
           qq(    <packagedElement xmi:type="uml:InstanceSpecification" xmi:id="@{[ def("unit:$_") ]}" name="$_"/>\n) } 'watt', 'watt hour', 'percent'),
    qq(    <packagedElement xmi:type="uml:Enumeration" xmi:id="@{[ def('StationMode') ]}" name="StationMode">\n)
    . join('', map { qq(      <ownedLiteral xmi:type="uml:EnumerationLiteral" xmi:id="@{[ def("lit:$_") ]}" name="$_"/>\n) } qw(observing degraded maintenance recovered))
    . "    </packagedElement>\n");

my $sig = sub { my ($name, $doc, @attrs) = @_;
    qq(    <packagedElement xmi:type="uml:Signal" xmi:id="@{[ def($name) ]}" name="$name">\n) . comment($name, $doc, '      ')
    . join('', map { my ($an, $t) = @$_; qq(      <ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def("$name.$an") ]}" name="$an">) . prim($t) . "</ownedAttribute>\n" } @attrs)
    . "    </packagedElement>\n" };
my $ifb = sub { my ($name, $doc, @fp) = @_;
    app('sysml:InterfaceBlock', 'base_Class', $name);
    qq(    <packagedElement xmi:type="uml:Class" xmi:id="@{[ def($name) ]}" name="$name">\n) . comment($name, $doc, '      ')
    . join('', map { my ($fn, $t, $dir) = @$_; app('sysml:FlowProperty', 'base_Property', "$name.$fn", direction => $dir);
                     qq(      <ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def("$name.$fn") ]}" name="$fn" type="@{[ id($t) ]}"/>\n) } @fp)
    . "    </packagedElement>\n" };
push @PKG, package_('Interfaces', 'What crosses each segment boundary: interface blocks with flow properties, and the signals they carry.',
    $sig->('ObservationRecord', 'One timed set of measurements from one station.', ['stationId', 'String'], ['observedAt', 'String'], ['qualityFlag', 'Integer'],
        (at(4) ? (['salinity', 'Real']) : ())),
    $sig->('HealthReport', 'Battery, mode and fault state of one station.', ['stationId', 'String'], ['stateOfCharge', 'Real']),
    $sig->('Bulletin', 'The published marine bulletin.', ['issuedAt', 'String']),
    $ifb->('ObservationIF', 'Observations from a station to the data center.', ['observation', 'ObservationRecord', 'out']),
    $ifb->('HealthIF', 'Health reports from a station to the data center.', ['health', 'HealthReport', 'out']),
    $ifb->('PublicIF', 'Bulletins and latest observations to the public.', ['bulletin', 'Bulletin', 'out'], ['latest', 'ObservationRecord', 'out']),
    $ifb->('PowerIF', 'DC power between the power system and its loads.', ['supply', 'Power', 'out']));

# Network: the top of the tree, the context, the actors, the use cases and the daily upload interaction
my $usecases = sub { my ($k, $i) = @_; '' };
push @PKG, package_('Network', 'The observation network as a whole, its users and what they do with it.',
    block('ObservationNetwork', level => 'L1Network', doc => 'Every station, the data center and the field crew that keeps them running.',
        parts => [['stations', 'StationSegment'], ['dataCenter', 'DataSegment'], ['operations', 'OperationsSegment']],
        connectors => [['observationLink', ['stations', ['StationSegment.obsOut']], ['dataCenter', ['DataSegment.obsIn']]],
                       ['healthLink', ['stations', ['StationSegment.healthOut']], ['dataCenter', ['DataSegment.healthIn']]]]),
    block('NetworkContext', doc => 'The network among the people who use and service it.',
        parts => [['network', 'ObservationNetwork']], refs => [['forecaster', 'Forecaster'], ['mariner', 'Mariner'], ['technician', 'Technician']],
        extra => sub { my ($k, $i) = @_;
            my ($l1, $l2, $l3) = map { id("ll:$_") } qw(buoy ingest forecaster);
            qq($i<ownedBehavior xmi:type="uml:Interaction" xmi:id="@{[ def('DailyUpload') ]}" name="DailyUpload">\n)
          . qq($i  <lifeline xmi:type="uml:Lifeline" xmi:id="$l1" name="buoy" represents="@{[ id('StationSegment.buoys') ]}"/>\n)
          . qq($i  <lifeline xmi:type="uml:Lifeline" xmi:id="$l2" name="ingest" represents="@{[ id('DataSegment.ingest') ]}"/>\n)
          . qq($i  <lifeline xmi:type="uml:Lifeline" xmi:id="$l3" name="forecaster" represents="@{[ id('NetworkContext.forecaster') ]}"/>\n)
          . join('', map { my ($m, $s, $r) = @$_;
                qq($i  <message xmi:type="uml:Message" xmi:id="@{[ id("msg:$m") ]}" name="$m" messageSort="asynchSignal" sendEvent="@{[ id("mos:$m") ]}" receiveEvent="@{[ id("mor:$m") ]}"/>\n)
              . qq($i  <fragment xmi:type="uml:MessageOccurrenceSpecification" xmi:id="@{[ id("mos:$m") ]}" covered="$s" message="@{[ id("msg:$m") ]}"/>\n)
              . qq($i  <fragment xmi:type="uml:MessageOccurrenceSpecification" xmi:id="@{[ id("mor:$m") ]}" covered="$r" message="@{[ id("msg:$m") ]}"/>\n) }
                ['sendObservations', $l1, $l2], ['acknowledge', $l2, $l1], (at(6) ? (['requestResend', $l2, $l1]) : ()), ['notifyNewData', $l2, $l3])
          . "$i</ownedBehavior>\n" }),
    (map { my ($n, $d) = @$_; qq(    <packagedElement xmi:type="uml:Actor" xmi:id="@{[ def($n) ]}" name="$n">\n) . comment($n, $d, '      ') . "    </packagedElement>\n" }
        ['Forecaster', 'Writes forecasts from the observations.'], ['Mariner', 'Reads the bulletin before going out.'], ['Technician', 'Services stations from the vessel.']),
    (map { my ($n, $d, $inc) = @$_;
        qq(    <packagedElement xmi:type="uml:UseCase" xmi:id="@{[ def($n) ]}" name="$n" subject="@{[ id('ObservationNetwork') ]}">\n) . comment($n, $d, '      ')
        . join('', map { qq(      <include xmi:type="uml:Include" xmi:id="@{[ id("inc:$n:$_") ]}" addition="@{[ id($_) ]}"/>\n) } @{ $inc // [] })
        . "    </packagedElement>\n" }
        ['ReadBulletin', 'A mariner reads the latest bulletin.'],
        ['ReviewObservations', 'A forecaster reviews recent and past observations.', ['QueryArchive']],
        ['QueryArchive', 'Look up observations by station and time.'],
        ['ServiceStation', 'A technician visits, inspects and repairs a station.']),
    (map { my ($a, $u) = @$_; my $k = "assoc:$a:$u";
        qq(    <packagedElement xmi:type="uml:Association" xmi:id="@{[ def($k) ]}" memberEnd="@{[ id("$k:a") ]} @{[ id("$k:u") ]}">\n)
      . qq(      <ownedEnd xmi:type="uml:Property" xmi:id="@{[ id("$k:a") ]}" type="@{[ id($a) ]}" association="@{[ id($k) ]}"/>\n)
      . qq(      <ownedEnd xmi:type="uml:Property" xmi:id="@{[ id("$k:u") ]}" type="@{[ id($u) ]}" association="@{[ id($k) ]}"/>\n)
      . "    </packagedElement>\n" } ['Mariner', 'ReadBulletin'], ['Forecaster', 'ReviewObservations'], ['Technician', 'ServiceStation']),
    dep('Dependency', 'ObservationNetwork', 'MaintenanceDepot'));       # spaghetti: Network -> Operations

# Stations: buoys and shore stations down to components; the buoy's modes as a state machine; the power parametric
my $modes = sub { my ($k, $i) = @_;
    my @st = (qw(Observing Degraded Maintenance Recovered), at(3) ? ('Storm') : ());
    my $x = qq($i<ownedBehavior xmi:type="uml:StateMachine" xmi:id="@{[ def('BuoyModes') ]}" name="BuoyModes">\n$i  <region xmi:type="uml:Region" xmi:id="@{[ id('BuoyModes:r') ]}">\n);
    $x .= qq($i    <subvertex xmi:type="uml:Pseudostate" xmi:id="@{[ id('state:init') ]}" kind="initial"/>\n);
    $x .= qq($i    <subvertex xmi:type="uml:State" xmi:id="@{[ id("state:$_") ]}" name="$_"/>\n) for @st;
    for my $t (['init', 'Observing', ''], ['Observing', 'Degraded', 'lowBattery'], ['Degraded', 'Observing', 'charged'],
               ['Observing', 'Maintenance', 'crewOnSite'], ['Degraded', 'Maintenance', 'crewOnSite'], ['Maintenance', 'Observing', 'crewDeparts'],
               ['Maintenance', 'Recovered', 'liftedAboard'],
               (at(3) ? (['Observing', 'Storm', 'stormWarning'], ['Storm', 'Observing', 'calm']) : ())) {
        my ($s, $d, $ev) = @$t; my $tk = "tr:$s:$d";
        $x .= qq($i    <transition xmi:type="uml:Transition" xmi:id="@{[ id($tk) ]}" source="@{[ id("state:$s") ]}" target="@{[ id("state:$d") ]}");
        $x .= $ev ? qq(>\n$i      <trigger xmi:type="uml:Trigger" xmi:id="@{[ id("$tk:t") ]}" name="$ev"/>\n$i    </transition>\n) : "/>\n";
    }
    return $x . "$i  </region>\n$i</ownedBehavior>\n" };
my $power_par = sub { my ($k, $i) = @_;
    app('sysml:ConstraintProperty', 'base_Property', 'PowerSystem.balance');
    my $x = qq($i<ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def('PowerSystem.balance') ]}" name="balance" type="@{[ id('EnergyBalance') ]}" aggregation="composite"/>\n);
    for my $b (['generation', 'solar', 'SolarPanel.ratedPower'], ['storage', 'battery', 'Battery.capacity'], ['load', undef, 'PowerSystem.averageLoad']) {
        my ($param, $part, $prop) = @$b; my $ck = "bind:$param";
        app('sysml:BindingConnector', 'base_Connector', $ck);
        $x .= qq($i<ownedConnector xmi:type="uml:Connector" xmi:id="@{[ id($ck) ]}">\n)
            . qq($i  <end xmi:type="uml:ConnectorEnd" xmi:id="@{[ id("$ck:e1") ]}" role="@{[ id("EnergyBalance.$param") ]}" partWithPort="@{[ id('PowerSystem.balance') ]}"/>\n)
            . qq($i  <end xmi:type="uml:ConnectorEnd" xmi:id="@{[ id("$ck:e2") ]}" role="@{[ id($prop) ]}") . ($part ? qq( partWithPort="@{[ id("PowerSystem.$part") ]}") : '') . "/>\n"
            . "$i</ownedConnector>\n";
    }
    return $x };
push @PKG, package_('Stations', 'Everything that goes out to a site: moored buoys and shore stations.',
    block('StationSegment', level => 'L2Segment', doc => 'All the observing stations of the network.',
        parts => [['buoys', 'MooredBuoy', 1, '*'], ['shoreStations', 'ShoreStation', 1, '*'], (at(4) ? (['drifters', 'DriftingBuoy', 0, '*']) : ())],
        ports => [['obsOut', 'ObservationIF', 'proxy'], ['healthOut', 'HealthIF', 'proxy']],
        connectors => [[undef, [undef, 'StationSegment.obsOut'], ['buoys', ['ObservingStation.obsOut']]],
                       [undef, [undef, 'StationSegment.obsOut'], ['shoreStations', ['ObservingStation.obsOut']]]]),
    block('ObservingStation', abstract => 1, level => 'L3Station', doc => 'What every station has: sensors, a logger, telemetry and the two outgoing ports.',
        parts => [['sensors', 'SensorSuite'], ['logger', 'DataLogger'], ['telemetry', 'TelemetryUnit']],
        values => [['stationId', 'prim:String']],
        ports => [['obsOut', 'ObservationIF', 'proxy'], ['healthOut', 'HealthIF', 'proxy'], ['mode', 'StationMode', 'flow', 0, 'out']],
        connectors => [['toLogger', ['sensors', ['SensorSuite.dataOut']], ['logger', ['DataLogger.dataIn']]],
                       ['toTelemetry', ['logger', ['DataLogger.uplink']], ['telemetry', ['TelemetryUnit.dataIn']]],
                       [undef, ['telemetry', ['TelemetryUnit.obsOut']], [undef, 'ObservingStation.obsOut']]]),
    block('MooredBuoy', gen => 'ObservingStation', level => 'L3Station', doc => 'An offshore station on a mooring, powered by its own solar panel.',
        parts => [['hull', 'Hull'], ['mooring', 'Mooring'], ['power', 'PowerSystem'], ['waveSensor', 'WaveSensor']],
        extra => $modes),
    block('ShoreStation', gen => 'ObservingStation', level => 'L3Station', doc => 'A station on a mast at the shore, on mains power.',
        parts => [['mast', 'Mast']]),
    (at(4) ? block('DriftingBuoy', gen => 'ObservingStation', level => 'L3Station', doc => 'A free-drifting station, tracked by its own position reports.',
        parts => [['hull', 'Hull'], ['power', 'PowerSystem']]) : ()),
    block('PowerSystem', level => 'L4Subsystem', doc => 'Solar generation, storage and regulation for a buoy.',
        notes => ['Per SSDD section 4.3 the power budget is TBD pending the 2024 trade study. Do not change without CCB approval.'],
        parts => [['solar', 'SolarPanel'], ['battery', 'Battery'], ['regulator', 'ChargeRegulator'], (at(3) ? (['fuse', 'Fuse']) : ())],
        values => [['averageLoad', 'Power']],
        ports => [['supplyOut', 'PowerIF', 'proxy']],
        connectors => [['charge', ['solar', ['SolarPanel.out']], ['regulator', ['ChargeRegulator.in']]],
                       ['store', ['regulator', ['ChargeRegulator.toBattery']], ['battery', ['Battery.terminal']]]],
        extra => $power_par),
    block('SensorSuite', level => 'L4Subsystem', doc => 'The meteorological sensors common to every station.',
        parts => [['anemometer', 'Anemometer'], ['barometer', 'Barometer'], ['thermometer', 'Thermometer'], (at(2) ? (['hygrometer', 'Hygrometer']) : ())],
        ports => [['dataOut', 'prim:String', 'flow', 0, 'out']]),
    block('DataLogger', level => 'L4Subsystem', doc => (at(7) ? 'Timestamps observations and stores them until they are sent.' : 'Timestamps and stores observations until they are sent.'),
        notes => ['Per SRS rev C para 3.2.1 the logger shall buffer observations while the link is down (see ICD-004 Table 7, TBR). Copied from the SRS 2023-11 baseline.'],
        values => [['bufferedRecords', 'prim:Integer']],
        ports => [['dataIn', 'prim:String', 'flow', 0, 'in'], ['uplink', 'ObservationIF', 'proxy']], procured => ['Notional Logger Co.', 'LG-100']),
    block('TelemetryUnit', level => 'L4Subsystem', doc => 'Sends observations and health over the cellular or satellite link.',
        parts => [['modem', 'Modem'], ['antenna', 'Antenna']],
        ports => [['dataIn', 'ObservationIF', 'proxy', 1], ['obsOut', 'ObservationIF', 'proxy']]),
    leaf('Hull', 'L4Subsystem', 'The floating body that carries everything else.', parts => [['mastFrame', 'SensorMast'], ['ballast', 'Ballast']]),
    leaf('Mooring', 'L4Subsystem', 'Holds the buoy on station.', parts => [['chain', 'MooringChain'], ['anchor', 'Anchor']]),
    leaf('Mast', 'L4Subsystem', 'Holds the shore sensors at height.'),
    leaf('SolarPanel', 'L5Assembly', 'Generates power.', values => [['ratedPower', 'Power', '40']], ports => [['out', 'PowerIF', 'proxy']], procured => ['Notional Solar Ltd.', 'SP-40']),
    leaf('Battery', 'L5Assembly', 'Stores power for night and cloud.', values => [['capacity', 'Energy', '400'], ['stateOfCharge', 'Percentage']],
        ports => [['terminal', 'PowerIF', 'proxy', 1]], parts => [['cells', 'Cell', 4, 4]]),
    leaf('ChargeRegulator', 'L5Assembly', 'Keeps the battery within its charge limits.', ports => [['in', 'PowerIF', 'proxy', 1], ['toBattery', 'PowerIF', 'proxy']]),
    leaf('Anemometer', 'L5Assembly', 'Wind speed and direction.'),
    leaf('Barometer', 'L5Assembly', 'Air pressure.'),
    leaf('Thermometer', 'L5Assembly', 'Air temperature.'),
    (at(2) ? leaf('Hygrometer', 'L5Assembly', 'Relative humidity.') : ()),
    (at(3) ? leaf('Fuse', 'L5Assembly', 'Isolates a shorted load from the battery.') : ()),
    leaf('WaveSensor', 'L5Assembly', 'Wave height and period, from motion.'),
    leaf('Modem', 'L5Assembly', 'The radio link.', procured => ['Notional Radio Inc.', 'MD-2']),
    leaf('Antenna', 'L5Assembly', 'The radio antenna.'),
    leaf('SensorMast', 'L5Assembly', 'The frame on the hull that carries the sensors.'),
    leaf('Ballast', 'L5Assembly', 'Keeps the hull upright.'),
    leaf('MooringChain', 'L5Assembly', 'Chain between hull and anchor.'),
    leaf('Anchor', 'L5Assembly', at(7) ? 'Holds the mooring to the seabed; sized for each site.' : 'Holds the mooring to the seabed.'),
    leaf('Cell', 'L6Component', 'One battery cell.'),
    # spaghetti: ObservingStation traced to every requirement anyone pointed at on a slide, on top of its satisfies,
    # and a trace into the data center (Stations -> DataCenter, which depends back on Stations: a package cycle)
    (map { dep('Trace', 'ObservingStation', sprintf 'req:TW-SYS-%03d', $_) } 1 .. 11),
    dep('Trace', 'DataLogger', 'IngestService'));

# the constraint block, in its own package as Cameo teams usually keep them
app('sysml:ConstraintBlock', 'base_Class', 'EnergyBalance');
push @PKG, package_('Analysis', 'Constraint blocks used in parametric diagrams.',
    qq(    <packagedElement xmi:type="uml:Class" xmi:id="@{[ def('EnergyBalance') ]}" name="EnergyBalance">\n)
  . comment('EnergyBalance', 'Daily energy in must cover daily energy out, with the battery as the buffer.', '      ')
  . join('', map { qq(      <ownedAttribute xmi:type="uml:Property" xmi:id="@{[ def("EnergyBalance.$_->[0]") ]}" name="$_->[0]" type="@{[ id($_->[1]) ]}"/>\n) }
                 ['generation', 'Power'], ['storage', 'Energy'], ['load', 'Power'])
  . qq(      <ownedRule xmi:type="uml:Constraint" xmi:id="@{[ id('EnergyBalance:rule') ]}" name="balance">\n)
  . qq(        <specification xmi:type="uml:OpaqueExpression" xmi:id="@{[ id('EnergyBalance:spec') ]}"><body>@{[ at(5) ? 'generation * sunHours &gt;= load * 24 + reserve' : 'generation * sunHours &gt;= load * 24' ]}</body><language>English</language></specification>\n)
  . "      </ownedRule>\n    </packagedElement>\n");

push @PKG, package_('DataCenter', 'The services that turn observations into an archive and a bulletin.',
    block('DataSegment', level => 'L2Segment', doc => 'Ingest, quality control, archive and publication.',
        parts => [['ingest', 'IngestService'], ['qc', 'QualityControl'], ['archive', 'Archive'], ['publisher', 'BulletinPublisher']],
        ports => [['obsIn', 'ObservationIF', 'proxy', 1], ['healthIn', 'HealthIF', 'proxy', 1], ['publicOut', 'PublicIF', 'full']],
        connectors => [[undef, [undef, 'DataSegment.obsIn'], ['ingest', ['IngestService.obsIn']]],
                       ['toQc', ['ingest', ['IngestService.out']], ['qc', ['QualityControl.in']]],
                       ['toArchive', ['qc', ['QualityControl.out']], ['archive', ['Archive.in']]],
                       ['toPublisher', ['archive', ['Archive.query']], ['publisher', ['BulletinPublisher.source']]],
                       [undef, ['publisher', ['BulletinPublisher.publicOut']], [undef, 'DataSegment.publicOut']]]),
    leaf('IngestService', 'L3Station', 'Receives and de-duplicates observations.', ports => [['obsIn', 'ObservationIF', 'proxy', 1], ['out', 'ObservationIF', 'proxy']]),
    leaf('QualityControl', 'L3Station', 'Checks each observation and sets its flag.', ports => [['in', 'ObservationIF', 'proxy', 1], ['out', 'ObservationIF', 'proxy']],
        notes => ['From the Ops Concept briefing, slide 22: QC flags are reviewed by the duty forecaster each morning. Para 4.1.2 of the CONOPS applies.']),
    dep('Dependency', 'QualityControl', 'SensorSuite'),               # spaghetti: DataCenter -> Stations
    leaf('Archive', 'L3Station', 'Keeps every observation with its flag.', ports => [['in', 'ObservationIF', 'proxy', 1], ['query', 'ObservationIF', 'proxy']]),
    leaf('BulletinPublisher', 'L3Station', 'Writes and publishes the marine bulletin.', ports => [['source', 'ObservationIF', 'proxy', 1], ['publicOut', 'PublicIF', 'proxy']]));

push @PKG, package_('Operations', 'The field crew and what it needs to keep the stations running.',
    block('OperationsSegment', level => 'L2Segment', doc => 'The depot, the vessel and the spares.',
        parts => [['depot', 'MaintenanceDepot'], ['vessel', 'ServiceVessel'], ['spares', 'SparesPool']]),
    leaf('MaintenanceDepot', 'L3Station', 'Where stations are refurbished.'),
    leaf('ServiceVessel', 'L3Station', 'Carries the crew and a spare buoy.', parts => [['crane', 'DeckCrane']]),
    leaf('DeckCrane', 'L4Subsystem', 'Lifts a buoy aboard.'),
    leaf('SparesPool', 'L3Station', 'Spare sensors, batteries and one spare buoy.'),
    dep('Dependency', 'ServiceVessel', 'Technician'));                 # spaghetti: Operations -> Network

# Legacy Import: what the point-and-click port of the documents left behind (removed by the prime in drop 6;
# 'Copy of SensorSuite' already in drop 3, after the government's Discrepancy Reports)
push @PKG, package_('Legacy Import', 'Imported from the SRS and SSDD in 2023. Clean up later.',
    block('Battery_old', doc => 'Copy of Battery from the 2023 SRS import. Use Battery.',
        values => [['capacity', 'Energy', '400'], ['stateOfCharge', 'Percentage']], ports => [['terminal', 'PowerIF', 'proxy', 1]], parts => [['cells', 'Cell', 4, 4]]),
    (at(3) ? () : block('Copy of SensorSuite', doc => 'The meteorological sensors common to every station.',
        parts => [['anemometer', 'Anemometer'], ['barometer', 'Barometer'], ['thermometer', 'Thermometer']], ports => [['dataOut', 'prim:String', 'flow', 0, 'out']])),
    block('TBD Component', doc => 'Placeholder from the document import. TBD.'),
    qq(    <packagedElement xmi:type="uml:Class" xmi:id="@{[ def('Requirement from slide 14') ]}" name="Requirement from slide 14">\n)
      . comment('Requirement from slide 14', 'The system shall be available 99.5% of the time (2024-03 program review, slide 14).', '      ')
      . "    </packagedElement>\n") unless at(6);

# Behavior: the observation cycle as activities (call actions, control and object flows, a fork, pins)
my $activity = sub {
    my ($name, $doc, $params, $calls, $extra) = @_;
    my $k = $name; my $i = '      ';
    my $x = qq(    <packagedElement xmi:type="uml:Activity" xmi:id="@{[ def($k) ]}" name="@{[ $NAME{$name} // $name ]}">\n) . comment($k, $doc, $i);
    for my $p (@{ $params // [] }) { my ($pn, $t, $dir) = @$p;
        $x .= qq($i<ownedParameter xmi:type="uml:Parameter" xmi:id="@{[ def("$k.$pn") ]}" name="$pn" direction="$dir" type="@{[ id($t) ]}"/>\n) }
    return $x . "    </packagedElement>\n" unless $calls;
    $x .= qq($i<node xmi:type="uml:InitialNode" xmi:id="@{[ id("$k:init") ]}"/>\n);
    $x .= qq($i<node xmi:type="uml:CallBehaviorAction" xmi:id="@{[ id("$k:$_->[0]") ]}" name="$_->[0]" behavior="@{[ id($_->[1]) ]}"/>\n) for @$calls;
    $x .= qq($i<node xmi:type="uml:ActivityFinalNode" xmi:id="@{[ id("$k:final") ]}"/>\n);
    my @seq = ('init', map { $_->[0] } @$calls); push @seq, 'final';
    for my $j (0 .. $#seq - 1) { $x .= qq($i<edge xmi:type="uml:ControlFlow" xmi:id="@{[ id("$k:cf$j") ]}" source="@{[ id("$k:$seq[$j]") ]}" target="@{[ id("$k:$seq[$j+1]") ]}"/>\n) }
    $x .= $extra->($k, $i) if $extra;
    return $x . "    </packagedElement>\n" };
push @PKG, package_('Behavior', 'The observation cycle, from sampling to the published bulletin.',
    $activity->('ObserveCoast', 'One cycle of the network: sample, send, ingest, check, archive, publish.', [['bulletin', 'Bulletin', 'out']],
        [['sample', 'SampleSensors'], ['send', 'TransmitObservations'], ['ingest', 'IngestObservations'], ['check', 'CheckQuality'],
         ['store', 'ArchiveObservations'], ['publish', 'PublishBulletin']],
        sub { my ($k, $i) = @_;
            # what the converter is expected to leave as TODOs: a fork, pins and an object flow
            qq($i<node xmi:type="uml:ForkNode" xmi:id="@{[ id("$k:fork") ]}" name="after check"/>\n)
          . qq($i<node xmi:type="uml:OpaqueAction" xmi:id="@{[ id("$k:log") ]}" name="log health">\n)
          . qq($i  <inputValue xmi:type="uml:InputPin" xmi:id="@{[ id("$k:log:in") ]}" name="report" type="@{[ id('HealthReport') ]}"/>\n$i</node>\n)
          . qq($i<node xmi:type="uml:ActivityParameterNode" xmi:id="@{[ id("$k:bulletinNode") ]}" name="bulletin" parameter="@{[ id("$k.bulletin") ]}"/>\n)
          . qq($i<edge xmi:type="uml:ObjectFlow" xmi:id="@{[ id("$k:of1") ]}" source="@{[ id("$k:publish") ]}" target="@{[ id("$k:bulletinNode") ]}"/>\n)
          . qq($i<edge xmi:type="uml:ControlFlow" xmi:id="@{[ id("$k:cfork") ]}" source="@{[ id("$k:fork") ]}" target="@{[ id("$k:log") ]}"/>\n) }),
    $activity->('SampleSensors', 'Read every sensor and timestamp the readings.', [['record', 'ObservationRecord', 'out']]),
    $activity->('TransmitObservations', 'Send the buffered records; keep them if the link is down.', [['record', 'ObservationRecord', 'in']]),
    $activity->('IngestObservations', 'Receive records and discard duplicates.', [['record', 'ObservationRecord', 'inout']]),
    $activity->('CheckQuality', 'Range, step and consistency checks; set the flag and the reason.', [['record', 'ObservationRecord', 'inout']]),
    $activity->('ArchiveObservations', 'Store each record with its flag.', [['record', 'ObservationRecord', 'in']]),
    $activity->('PublishBulletin', 'Write the bulletin from the latest good observations and publish it.', [['bulletin', 'Bulletin', 'out']]),
    $activity->('ReportHealth', 'Send battery state, mode and faults.', [['report', 'HealthReport', 'out']]));

# Requirements: nested packages by module and section, the Cameo kinds as stereotypes
my $MDR = 'MD_Customization_for_Requirements__additional_stereotypes';
my %sections; my @sec_order;
for my $r (grep { $_->[6] ne 'doors' } @REQ) { push @sec_order, $r->[1] unless $sections{ $r->[1] }; push @{ $sections{ $r->[1] } }, $r }
my %tree;
for my $s (@sec_order) { my ($top, $sub) = split m{/}, $s; push @{ $tree{$top}{order} }, $sub // '' unless grep { $_ eq ($sub // '') } @{ $tree{$top}{order} // [] }; $tree{$top}{seen} //= scalar keys %tree }
my $req_xml = sub { my ($r, $ind) = @_;
    my ($id, undef, $title, $kind, $vm) = @$r;
    if ($kind eq 'Requirement') { app('sysml:Requirement', 'base_Class', "req:$id", Id => $id, Text => $r->[8]) }
    else { app("$MDR:$kind", 'base_Class', "req:$id", Id => $id, Text => $r->[8], ($vm ? (verifyMethod => $vm) : ()), risk => 'Low') }
    qq($ind<packagedElement xmi:type="uml:Class" xmi:id="@{[ def("req:$id") ]}" name="@{[ esc($title) ]}"/>\n) };
my @reqpk;
for my $top (sort { $tree{$a}{seen} <=> $tree{$b}{seen} } keys %tree) {
    my $body = '';
    for my $sub (@{ $tree{$top}{order} }) {
        my $sec = $sub eq '' ? $top : "$top/$sub";
        my $rs = join '', map { $req_xml->($_, $sub eq '' ? '      ' : '        ') } @{ $sections{$sec} };
        $body .= $sub eq '' ? $rs : qq(      <packagedElement xmi:type="uml:Package" xmi:id="@{[ def("pkg:$sec") ]}" name="$sub">\n$rs      </packagedElement>\n);
    }
    push @reqpk, qq(    <packagedElement xmi:type="uml:Package" xmi:id="@{[ def("pkg:$top") ]}" name="$top">\n$body    </packagedElement>\n);
}
my $rel = sub { my ($stereo, $client, $supplier) = @_; my $k = "rel:$stereo:$client:$supplier";
    app("sysml:$stereo", 'base_Abstraction', $k);
    qq(    <packagedElement xmi:type="uml:Abstraction" xmi:id="@{[ def($k) ]}" client="@{[ id($client) ]}" supplier="@{[ id($supplier) ]}"/>\n) };
my @SAT = (['ObservingStation', 'TW-SYS-001'], ['ObservingStation', 'TW-SYS-002'], ['IngestService', 'TW-SYS-003'], ['QualityControl', 'TW-SYS-004'],
           ['Archive', 'TW-SYS-005'], ['BulletinPublisher', 'TW-SYS-006'], ['BulletinPublisher', 'TW-SYS-007'], ['ObservingStation.obsOut', 'TW-SYS-008'],
           ['ObservingStation.healthOut', 'TW-SYS-009'], ['DataSegment.publicOut', 'TW-SYS-010'], ['PowerSystem', 'TW-SYS-011'], ['DataLogger', 'TW-SYS-013'],
           ['ObservingStation.mode', 'TW-SYS-014'], ['BulletinPublisher', 'TW-SYS-015'],
           ['Hull', 'TW-SEG-001'], ['Mooring', 'TW-SEG-002'], ['Battery.stateOfCharge', 'TW-SEG-003'], ['TelemetryUnit', 'TW-SEG-004'], ['IngestService', 'TW-SEG-005'],
           ['QualityControl', 'TW-SEG-006'], ['Archive', 'TW-SEG-007'], ['BulletinPublisher', 'TW-SEG-008'], (at(3) ? () : (['Mast', 'TW-SEG-009'])),
           (at(2) ? (['ObservingStation', 'TW-SYS-017']) : ()), (at(3) ? (['ServiceVessel', 'TW-SYS-012'], ['Fuse', 'TW-SEG-010']) : ()),
           (at(4) ? (['DataLogger', 'TW-SYS-016']) : ()), (at(6) ? (['DataSegment', 'TW-SYS-019']) : ()));
@SAT = (@SAT, map { ['ObservationNetwork', "TW-STK-00$_"] } 1 .. 6);
my @TC = (['TestStationObservations', 'Sensors and transmission on a buoy and a shore station.', qw(TW-SYS-001 TW-SYS-002 TW-SYS-008 TW-SEG-001), (at(2) ? ('TW-SYS-017') : ()), (at(7) ? ('TW-SEG-002') : ())],
          ['TestDataFlow', 'Ingest, quality control and archive with seeded bad records.', qw(TW-SYS-003 TW-SYS-004 TW-SYS-005 TW-SEG-005 TW-SEG-006 TW-SEG-007)],
          ['DemonstratePublication', 'A full bulletin cycle on the public service.', qw(TW-SYS-006 TW-SYS-007 TW-SYS-010 TW-SYS-015 TW-SEG-008)],
          ['InspectVesselAccess', 'Crew inspection of each station type from the vessel.', qw(TW-SYS-012)],
          ['TestHealthReporting', 'Health reports and mode changes, with a drained battery.', qw(TW-SYS-009 TW-SYS-014 TW-SEG-003)],
          ['TestStoreAndForward', 'Link outage and recovery.', qw(TW-SYS-013 TW-SEG-004)],
          (at(7) ? (['AnalyzeEnergyBalance', 'Energy balance analysis over a winter month at the darkest site.', qw(TW-SYS-011)]) : ()));
push @PKG, package_('Requirements', 'The requirements as they stood when DOORS was last synchronized, and their trace.',
    @reqpk,
    (map { $rel->('Satisfy', $_->[0], "req:$_->[1]") } @SAT),
    (map { my $r = $_; map { $rel->('DeriveReqt', "req:$r->[0]", "req:$_") } @{ $r->[5] } } grep { $_->[6] ne 'doors' } @REQ),
    $rel->('Refine', 'ReadBulletin', 'req:TW-STK-003'), $rel->('Refine', 'ServiceStation', 'req:TW-STK-004'),
    $rel->('Trace', 'Mast', 'req:TW-SYS-012'));   # traced, never satisfied: the planted gap
push @PKG, package_('Verification', 'Test cases and what they verify.',
    (map { my ($n, $d) = @$_; app('sysml:TestCase', 'base_Behavior', $n); $activity->($n, $d) } @TC),
    (map { my $tc = $_; map { $rel->('Verify', $tc->[0], "req:$_") } @{ $tc }[2 .. $#$tc] } @TC));
push @PKG, package_('Allocations', 'Which part performs which step of the observation cycle.',
    (map { $rel->('Allocate', $_->[0], $_->[1]) } ['SampleSensors', 'SensorSuite'], ['TransmitObservations', 'TelemetryUnit'], ['IngestObservations', 'IngestService'],
        ['CheckQuality', 'QualityControl'], ['ArchiveObservations', 'Archive'], ['PublishBulletin', 'BulletinPublisher'], ['ReportHealth', 'ObservingStation']));

# ---------------------------------------------------------------- the XMI file
my @diagrams = ('bdd Network', 'bdd Stations', 'bdd Stations OLD', 'bdd Stations (Jim edits)', 'bdd DataCenter', 'bdd Operations',
                'bdd Types and Units', 'bdd Interfaces', 'bdd Everything', 'ibd ObservationNetwork', 'ibd ObservationNetwork v2',
                'ibd ObservingStation', 'ibd MooredBuoy', 'ibd ShoreStation', 'ibd PowerSystem', 'ibd PowerSystem (copy)',
                'ibd SensorSuite', 'ibd TelemetryUnit', 'ibd DataSegment', 'par PowerSystem', 'par PowerSystem draft',
                'act ObserveCoast', 'act ObserveCoast - swimlanes', 'act SampleSensors', 'act TransmitObservations',
                'act CheckQuality', 'act ' . ($NAME{PublishBulletin} // 'PublishBulletin'), 'stm BuoyModes', 'stm BuoyModes OLD',
                'sd DailyUpload', 'sd DailyUpload (as briefed)', 'uc Network', 'uc Operators', 'req Stakeholder Needs',
                'req System Requirements', 'req System Requirements - by owner', 'req Segment Requirements', 'Satisfy matrix',
                'Verify matrix', 'Allocation matrix', 'Trace matrix (all)', 'Package overview', 'Briefing chart 2024-03 - do not edit',
                'PDR backup slide 12', 'Content diagram',
                (at(6) ? () : ('bdd Legacy Import', at(3) ? () : 'ibd Copy of SensorSuite')));
my $model = join '', @PKG;
my $xmi = qq(<?xml version="1.0" encoding="UTF-8"?>
<!-- Tidewater prime drop $VERSION ($DELIVERED) -->
<!-- Tidewater: a notional coastal weather-observation network, written by sim/tidewater-v1.pl in the shape of a
     Cameo Systems Modeler 2022x export (Eclipse UML2 5.x XMI). Fictional; every value is notional. -->
<xmi:XMI xmlns:xmi="http://www.omg.org/spec/XMI/20131001" xmlns:uml="http://www.omg.org/spec/UML/20131001"
         xmlns:sysml="http://www.omg.org/spec/SysML/20181001/SysML"
         xmlns:$MDR="http://www.magicdraw.com/spec/Customization/190/Requirements"
         xmlns:Tidewater_Profile="http://example.com/profiles/Tidewater">
  <xmi:Documentation><xmi:exporter>MagicDraw UML</xmi:exporter><xmi:exporterVersion>2022x</xmi:exporterVersion></xmi:Documentation>
  <uml:Model xmi:type="uml:Model" xmi:id="@{[ def('model') ]}" name="Tidewater">
    <packageImport xmi:type="uml:PackageImport" xmi:id="@{[ id('model:pi') ]}"><importedPackage href="http://www.omg.org/spec/UML/20131001/PrimitiveTypes.xmi#_0"/></packageImport>
    <profileApplication xmi:type="uml:ProfileApplication" xmi:id="@{[ id('model:pa') ]}"><appliedProfile xmi:idref="@{[ id('profile') ]}"/></profileApplication>
) . join('', map { s/^/  /mgr } $model) . qq(  </uml:Model>
) . join('', @APPS) . qq(  <xmi:Extension extender="MagicDraw UML 2022x">
) . join('', map { qq(    <diagram name="$_"/>\n) } @diagrams) . qq(  </xmi:Extension>
</xmi:XMI>
);
my @undef = grep { !$DEF{$_} } sort keys %ID;
my @dangling = grep { !/[:.]/ || /^(req|pkg|st|unit|lit):/ } @undef;     # named elements referenced but never written
die "referenced but not defined: @dangling\n" if @dangling;

# ---------------------------------------------------------------- the DOORS side: ReqIF and CSV
my @MOD = ('Stakeholder Needs', 'System Requirements', 'Segment Requirements');
my %in_mod; for my $r (grep { $_->[6] ne 'model' } @REQ) { my ($m, $s) = split m{/}, $r->[1]; push @{ $in_mod{$m}{order} }, $s // '' unless grep { $_ eq ($s // '') } @{ $in_mod{$m}{order} // [] }; push @{ $in_mod{$m}{$s // ''} }, $r }
my $abs = 0; my (%oid, @objs, @rows, %spec);
my $val_s = sub { my ($ad, $v) = @_; qq(            <ATTRIBUTE-VALUE-STRING THE-VALUE="@{[ esc($v) ]}"><DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>$ad</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION></ATTRIBUTE-VALUE-STRING>\n) };
my $val_x = sub { my ($ad, $v) = @_; (my $h = $v) =~ s{<(/?)(\w+)>}{<$1xhtml:$2>}g;
    qq(            <ATTRIBUTE-VALUE-XHTML><DEFINITION><ATTRIBUTE-DEFINITION-XHTML-REF>$ad</ATTRIBUTE-DEFINITION-XHTML-REF></DEFINITION>\n              <THE-VALUE><xhtml:div>$h</xhtml:div></THE-VALUE></ATTRIBUTE-VALUE-XHTML>\n) };
my $obj = sub { my ($o, $vals) = @_; push @objs, qq(        <SPEC-OBJECT IDENTIFIER="$o" LAST-CHANGE="$STAMP">\n          <TYPE><SPEC-OBJECT-TYPE-REF>sot-obj</SPEC-OBJECT-TYPE-REF></TYPE>\n          <VALUES>\n$vals          </VALUES>\n        </SPEC-OBJECT>\n) };
my $csvq = sub { my ($v) = @_; $v //= ''; $v =~ s/"/""/g; qq("$v") };
for my $m (@MOD) {
    my @kids; my $hn = 0;
    for my $s (@{ $in_mod{$m}{order} }) {
        my @reqs;
        for my $r (@{ $in_mod{$m}{$s} }) {
            my ($id, undef, $title, undef, $vm, undef, undef, $owner, $text) = @$r;
            my $o = 'o-' . lc $id; $oid{$id} = $o; $abs++;
            my $t = $DOORS_TEXT{$id} // $text; (my $plain = $t) =~ s/<[^>]+>//g;
            $obj->($o, $val_s->('ad-oid', $id) . $val_s->('ad-abs', $abs) . $val_s->('ad-name', $title) . $val_x->('ad-text', $t =~ s/\bshall\b/<b>shall<\/b>/r)
                     . ($vm ? qq(            <ATTRIBUTE-VALUE-ENUMERATION><DEFINITION><ATTRIBUTE-DEFINITION-ENUMERATION-REF>ad-vm</ATTRIBUTE-DEFINITION-ENUMERATION-REF></DEFINITION>\n              <VALUES><ENUM-VALUE-REF>ev-@{[ lc $vm ]}</ENUM-VALUE-REF></VALUES></ATTRIBUTE-VALUE-ENUMERATION>\n) : '')
                     . $val_s->('ad-owner', $owner));
            push @reqs, $o;
            push @rows, [$id, $abs, ($s eq '' ? 2 : 3), '', $plain, $vm, $owner, $title];
        }
        if ($s eq '') { push @kids, map { [$_, []] } @reqs; next }
        my $h = 'o-h-' . lc($m =~ s/\W+//gr) . '-' . ++$hn; $abs++;
        $obj->($h, $val_s->('ad-oid', '') . $val_s->('ad-abs', $abs) . $val_x->('ad-head', $s));
        splice @rows, -scalar(@reqs), 0, ['', $abs, 2, $s, '', '', '', ''];
        push @kids, [$h, [map { [$_, []] } @reqs]];
    }
    $spec{$m} = \@kids;
}
my @rels;
for my $r (grep { $_->[6] ne 'model' } @REQ) { for my $p (@{ $r->[5] }) { next unless $oid{$p};
    push @rels, qq(        <SPEC-RELATION IDENTIFIER="rel-@{[ lc $r->[0] ]}-@{[ lc $p ]}" LAST-CHANGE="$STAMP">\n          <TYPE><SPEC-RELATION-TYPE-REF>srt-derive</SPEC-RELATION-TYPE-REF></TYPE>\n          <SOURCE><SPEC-OBJECT-REF>$oid{$r->[0]}</SPEC-OBJECT-REF></SOURCE>\n          <TARGET><SPEC-OBJECT-REF>$oid{$p}</SPEC-OBJECT-REF></TARGET>\n        </SPEC-RELATION>\n) } }
my $hier; my $hn = 0;
$hier = sub { my ($nodes, $ind) = @_; join '', map { my ($o, $k) = @$_; $hn++;
    qq($ind<SPEC-HIERARCHY IDENTIFIER="sh-$hn"><OBJECT><SPEC-OBJECT-REF>$o</SPEC-OBJECT-REF></OBJECT>) . (@$k ? "\n$ind  <CHILDREN>\n" . $hier->($k, "$ind    ") . "$ind  </CHILDREN>\n$ind</SPEC-HIERARCHY>\n" : "</SPEC-HIERARCHY>\n") } @$nodes };
my $specs = join '', map { my $m = $_; (my $sid = lc $m) =~ s/\W+/-/g;
    qq(        <SPECIFICATION IDENTIFIER="spec-$sid" LONG-NAME="$m" LAST-CHANGE="$STAMP">\n          <TYPE><SPECIFICATION-TYPE-REF>st-mod</SPECIFICATION-TYPE-REF></TYPE>\n          <CHILDREN>\n)
  . $hier->($spec{$m}, '            ') . "          </CHILDREN>\n        </SPECIFICATION>\n" } @MOD;
my $ad = sub { my ($kind, $id, $name, $dt) = @_;
    qq(            <ATTRIBUTE-DEFINITION-$kind IDENTIFIER="$id" LONG-NAME="$name" LAST-CHANGE="$STAMP"><TYPE><DATATYPE-DEFINITION-$kind-REF>$dt</DATATYPE-DEFINITION-$kind-REF></TYPE></ATTRIBUTE-DEFINITION-$kind>\n) };
my $reqif = qq(<?xml version="1.0" encoding="UTF-8"?>
<!-- Tidewater prime drop $VERSION ($DELIVERED) -->
<!-- Tidewater requirements, written by sim/tidewater-v1.pl in the shape of a DOORS 9.7 ReqIF 1.2 export. Fictional. -->
<REQ-IF xmlns="http://www.omg.org/spec/ReqIF/20110401/reqif.xsd" xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <THE-HEADER>
    <REQ-IF-HEADER IDENTIFIER="hdr-tidewater">
      <CREATION-TIME>$STAMP</CREATION-TIME>
      <REQ-IF-TOOL-ID>IBM Rational DOORS</REQ-IF-TOOL-ID>
      <REQ-IF-VERSION>1.0</REQ-IF-VERSION>
      <SOURCE-TOOL-ID>DOORS 9.7</SOURCE-TOOL-ID>
      <TITLE>Tidewater requirements</TITLE>
    </REQ-IF-HEADER>
  </THE-HEADER>
  <CORE-CONTENT>
    <REQ-IF-CONTENT>
      <DATATYPES>
        <DATATYPE-DEFINITION-STRING IDENTIFIER="dt-str" LONG-NAME="String" MAX-LENGTH="2000" LAST-CHANGE="$STAMP"/>
        <DATATYPE-DEFINITION-XHTML IDENTIFIER="dt-xhtml" LONG-NAME="XHTML" LAST-CHANGE="$STAMP"/>
        <DATATYPE-DEFINITION-ENUMERATION IDENTIFIER="dt-vm" LONG-NAME="Verification Method" LAST-CHANGE="$STAMP">
          <SPECIFIED-VALUES>
) . join('', map { my $k = $_ - 1; my $n = (qw(Test Analysis Inspection Demonstration))[$k];
    qq(            <ENUM-VALUE IDENTIFIER="ev-@{[ lc $n ]}" LONG-NAME="$n" LAST-CHANGE="$STAMP"><PROPERTIES><EMBEDDED-VALUE KEY="$k" OTHER-CONTENT=""/></PROPERTIES></ENUM-VALUE>\n) } 1 .. 4)
. qq(          </SPECIFIED-VALUES>
        </DATATYPE-DEFINITION-ENUMERATION>
      </DATATYPES>
      <SPEC-TYPES>
        <SPEC-OBJECT-TYPE IDENTIFIER="sot-obj" LONG-NAME="DOORS object" LAST-CHANGE="$STAMP">
          <SPEC-ATTRIBUTES>
) . $ad->('STRING', 'ad-oid', 'Object Identifier', 'dt-str') . $ad->('STRING', 'ad-abs', 'ReqIF.ForeignID', 'dt-str')
  . $ad->('XHTML', 'ad-head', 'ReqIF.ChapterName', 'dt-xhtml') . $ad->('XHTML', 'ad-text', 'ReqIF.Text', 'dt-xhtml')
  . $ad->('STRING', 'ad-name', 'ReqIF.Name', 'dt-str') . $ad->('ENUMERATION', 'ad-vm', 'Verification Method', 'dt-vm')
  . $ad->('STRING', 'ad-owner', 'Owner', 'dt-str') . qq(          </SPEC-ATTRIBUTES>
        </SPEC-OBJECT-TYPE>
        <SPEC-RELATION-TYPE IDENTIFIER="srt-derive" LONG-NAME="derived from" LAST-CHANGE="$STAMP"/>
        <SPECIFICATION-TYPE IDENTIFIER="st-mod" LONG-NAME="Formal module" LAST-CHANGE="$STAMP"/>
      </SPEC-TYPES>
      <SPEC-OBJECTS>
) . join('', @objs) . qq(      </SPEC-OBJECTS>
      <SPEC-RELATIONS>
) . join('', @rels) . qq(      </SPEC-RELATIONS>
      <SPECIFICATIONS>
$specs      </SPECIFICATIONS>
    </REQ-IF-CONTENT>
  </CORE-CONTENT>
</REQ-IF>
);
my $csv = join('', map { join(',', map { $csvq->($_) } @$_) . "\r\n" }
    ['Object Identifier', 'Absolute Number', 'Object Level', 'Object Heading', 'Object Text', 'Verification Method', 'Owner', 'Name'], @rows);

# the prime's test report, from drop 4 on: one row per (requirement, case) in the government's results schema
my $results;
if (at(4)) {
    my %verdict = (TestStoreAndForward => ($DROP == 4 ? 'not-run' : $DROP == 5 ? 'failed' : 'passed'), InspectVesselAccess => (at(5) ? 'passed' : 'not-run'));
    my %env = (InspectVesselAccess => 'NWM dockside inspection', AnalyzeEnergyBalance => 'NWM analysis', DemonstratePublication => 'NWM integration lab');
    my %sign = (InspectVesselAccess => 'NWM V&V lead', AnalyzeEnergyBalance => 'NWM V&V lead');
    require Time::Local;
    my ($y, $m, $d) = split /-/, $DELIVERED;
    my @g = gmtime(Time::Local::timegm(0, 0, 14, $d, $m - 1, $y) - 3 * 86400);   # tested the Tuesday before delivery
    my $ts = sprintf '%04d-%02d-%02dT14:00:00Z', $g[5] + 1900, $g[4] + 1, $g[3];
    $results = "requirement,case,verdict,commit,environment,timestamp,signed_by\r\n";
    for my $tc (@TC) {
        my ($case, undef, @reqs) = @$tc;
        for my $r (@reqs) {
            my $v = $verdict{$case} // 'passed';
            $v = 'passed' if $case eq 'TestStoreAndForward' && $r eq 'TW-SEG-004' && $v eq 'failed';   # only the store-and-forward requirement failed
            $results .= join(',', $r, $case, $v, sprintf('nwm-cameo-r%d', 100 * $DROP), $env{$case} // 'NWM test lab', $ts, $sign{$case} // '') . "\r\n";
        }
    }
}
my $junit;                                                    # the same results as the prime's Jenkins JUnit plugin archives them
if ($results) {
    my @r = map { [ split /,/, $_, -1 ] } grep { /\S/ } split /\r\n/, $results; shift @r;
    my $fail = grep { $_->[2] eq 'failed' } @r; my $skip = grep { $_->[2] eq 'not-run' } @r;
    $junit = qq(<?xml version="1.0" encoding="UTF-8"?>\r\n<testsuite name="nwm.tidewater.verification" tests=") . scalar(@r) . qq(" failures="$fail" skipped="$skip">\r\n)
           . join('', map { qq(  <testcase classname="$_->[1]" name="$_->[0]") . ($_->[2] eq 'failed' ? qq(>\r\n    <failure message="$_->[1] failed on $_->[0]"/>\r\n  </testcase>\r\n)
                                                                              : $_->[2] eq 'not-run' ? qq(>\r\n    <skipped/>\r\n  </testcase>\r\n) : qq(/>\r\n)) } @r)
           . "</testsuite>\r\n";
}
# ---------------------------------------------------------------- the prime's change control: the CRs in this drop
# cr_id, kind, title, rationale, element keys (their xmi:ids; an element's children belong to the same CR), requirements.
# The rename in drop 5 deliberately comes with no rationale: the government asks for one.
my @CR = (
    [1, 'NWM-CR-0001', 'add', 'Baseline delivery at contract start', 'The model as it stood when the contract was awarded.', [], []],
    [2, 'NWM-CR-0012', 'add', 'Add hygrometer to the sensor suite', 'Humidity is needed to forecast fog at the shore stations.',
        ['SensorSuite', 'SensorSuite.hygrometer', 'Hygrometer'], ['TW-SYS-017']],
    [2, 'NWM-CR-0013', 'add', 'Add humidity requirement TW-SYS-017 and its trace', 'Derived from TW-STK-001 for the hygrometer.',
        ['req:TW-SYS-017', 'rel:Satisfy:ObservingStation:req:TW-SYS-017', 'rel:DeriveReqt:req:TW-SYS-017:req:TW-STK-001',
         'rel:Verify:TestStationObservations:req:TW-SYS-017'], ['TW-SYS-017']],
    [2, 'NWM-CR-0014', 'fix', 'Align TW-SYS-006 text with DOORS', 'Answers government DR-1: the model text lagged DOORS after the SRS rev C update.', ['req:TW-SYS-006'], ['TW-SYS-006']],
    [3, 'NWM-CR-0015', 'add', 'Add storm mode to BuoyModes', 'Buoys must stop wave sampling above the sea-state limit and resume when it is calm.',
        ['state:Storm', 'tr:Observing:Storm', 'tr:Storm:Observing'], ['TW-SYS-014']],
    [3, 'NWM-CR-0016', 'add', 'Add a fuse to the power system', 'A shorted sensor drained two buoys in the 2026 winter season.',
        ['PowerSystem', 'PowerSystem.fuse', 'Fuse', 'req:TW-SEG-010', 'rel:Satisfy:Fuse:req:TW-SEG-010', 'rel:DeriveReqt:req:TW-SEG-010:req:TW-SYS-011'], ['TW-SEG-010', 'TW-SYS-011']],
    [3, 'NWM-CR-0017', 'delete', 'Delete the lowerable-mast requirement TW-SEG-009', 'Shore masts are now fixed; crews use a lift for maintenance.',
        ['req:TW-SEG-009', 'rel:Satisfy:Mast:req:TW-SEG-009', 'rel:DeriveReqt:req:TW-SEG-009:req:TW-SYS-012'], ['TW-SEG-009']],
    [3, 'NWM-CR-0018', 'add', 'Satisfy TW-SYS-012 by the service vessel', 'Answers government DR-2: TW-SYS-012 had nothing satisfying it.',
        ['rel:Satisfy:ServiceVessel:req:TW-SYS-012'], ['TW-SYS-012']],
    [3, 'NWM-CR-0019', 'delete', 'Delete Copy of SensorSuite', 'Answers government DR-5: a duplicate block left by the 2023 document import.',
        ['Copy of SensorSuite'], []],
    [4, 'NWM-CR-0020', 'add', 'Add salinity to the observation record', 'Partner agencies asked for surface salinity with each observation.',
        ['ObservationRecord', 'ObservationRecord.salinity'], []],
    [4, 'NWM-CR-0021', 'add', 'Add drifting buoys', 'Drifting buoys fill the gap between moorings during the storm season.',
        ['StationSegment', 'StationSegment.drifters', 'DriftingBuoy'], []],
    [4, 'NWM-CR-0022', 'add', 'Bring TW-SYS-016 into the model', 'Answers government DR-3: TW-SYS-016 was in DOORS but not in the model.',
        ['req:TW-SYS-016', 'rel:Satisfy:DataLogger:req:TW-SYS-016', 'rel:DeriveReqt:req:TW-SYS-016:req:TW-STK-002'], ['TW-SYS-016']],
    [4, 'NWM-CR-0023', 'change', 'Revise the TW-SYS-002 transmission interval', 'Forecasters need hourly data for the coastal model runs.',
        ['req:TW-SYS-002'], ['TW-SYS-002']],
    [5, 'NWM-CR-0024', 'change', 'Add a reserve term to EnergyBalance', 'Battery reserve was left out of the energy balance.',
        ['EnergyBalance:spec'], ['TW-SYS-011']],
    [5, 'NWM-CR-0025', 'rename', 'Rename PublishBulletin to IssueBulletin', '', ['PublishBulletin'], []],
    [6, 'NWM-CR-0026', 'add', 'Add partner sharing TW-SYS-019', 'Data-sharing agreement with partner agencies.',
        ['req:TW-SYS-019', 'rel:Satisfy:DataSegment:req:TW-SYS-019', 'rel:DeriveReqt:req:TW-SYS-019:req:TW-STK-003'], ['TW-SYS-019']],
    [6, 'NWM-CR-0027', 'add', 'Add requestResend to DailyUpload', 'The data center asks a station to resend a gap.',
        ['msg:requestResend', 'mos:requestResend', 'mor:requestResend'], ['TW-SYS-013']],
    [6, 'NWM-CR-0028', 'delete', 'Delete the Legacy Import package', 'Answers government DR-5: duplicated and placeholder elements from the document import.',
        ['pkg:Legacy Import'], []],
    [7, 'NWM-CR-0029', 'add', 'Add the energy balance analysis for TW-SYS-011', 'Answers government DR-4: TW-SYS-011 had no verification.',
        ['AnalyzeEnergyBalance', 'rel:Verify:AnalyzeEnergyBalance:req:TW-SYS-011'], ['TW-SYS-011']],
    [7, 'NWM-CR-0030', 'add', 'Verify TW-SEG-002 in the station tests', 'TW-SEG-002 had no verification.',
        ['rel:Verify:TestStationObservations:req:TW-SEG-002'], ['TW-SEG-002']],
    [7, 'NWM-CR-0031', 'change', 'Documentation edits', 'Clearer descriptions for the logger and the anchor.', ['c:DataLogger', 'c:Anchor'], []],
);
my @MYCR = grep { $_->[0] == $DROP } @CR;
for my $cr (@MYCR) {                           # a CR names only elements this drop has (or, for a delete, no longer has)
    for my $k (@{ $cr->[5] }) {
        my $in = $xmi =~ /xmi:id="\Q@{[ id($k) ]}\E"/ ? 1 : 0;
        die "$cr->[1]: $k is " . ($in ? 'still in' : 'not in') . " drop $DROP\n" if $in == ($cr->[2] eq 'delete' ? 1 : 0);
    }
}
my $crq = sub { my $v = shift // ''; $v =~ /[",\r\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v };
my $changes = "cr_id,title,rationale,kind,xmi_ids,requirements\r\n"
    . join('', map { join(',', map { $crq->($_) } $_->[1], $_->[3], $_->[4], $_->[2], join(' ', map { id($_) } @{ $_->[5] }), join(' ', @{ $_->[6] })) . "\r\n" } @MYCR);
my @FILES = (['tidewater.xmi', $xmi], ['tidewater.reqif', $reqif], ['tidewater.csv', $csv], ['CHANGES.csv', $changes], ($results ? (['results.csv', $results], ['results.xml', $junit]) : ()));
# Jenkins provenance: the prime builds every drop in its Jenkins job (fictional host); the MANIFEST says which build made it
my %CAMEO = (1 => '2022x Refresh2', 2 => '2022x Refresh2', 3 => '2024x', 4 => '2024x', 5 => '2024x Refresh1', 6 => '2024x Refresh1', 7 => '2024x Refresh1');
my $build = 100 + 37 * $DROP + ($DROP > 3 ? 11 : 0);
my $prov = "Built by: Jenkins https://jenkins.nwm.example.invalid/job/tidewater-model-delivery/$build/ (build $build)\r\n"
         . sprintf("Prime repository commit: %s\r\n", substr(sha256_hex("nwm-tidewater-$DROP"), 0, 40))
         . "Tools: Cameo Systems Modeler $CAMEO{$DROP}; DOORS 9.7 ReqIF export; Teamwork Cloud 2024x" . ($DROP >= 4 ? "; NWM verification harness 3.2 (JUnit)" : '') . "\r\n"
         . "Delivery: " . ($DROP >= 4 ? "uploaded by Jenkins to the government Generic Package Registry (prime-drop/$VERSION) and pipeline trigger" : 'CDRL file transfer to government approved storage') . "\r\n";
my $manifest = "Tidewater system model -- prime drop $VERSION (drop $DROP)\r\nCDRL: A003 System Model\r\nContractor: Northwind Marine Systems (fictional)\r\nDelivered: $DELIVERED\r\n" . $prov
    . "Changes: $SUMMARY\r\nChange requests:\r\n"
    . join('', map { sprintf "  %s  %-6s  %s -- %s\r\n", $_->[1], $_->[2], $_->[3], $_->[4] ne '' ? $_->[4] : '(no rationale given)' } @MYCR)
    . "Files (sha256):\r\n" . join('', map { sprintf "  %s  %s\r\n", sha256_hex($_->[1]), $_->[0] } @FILES);
$manifest =~ s{\r\n}{\n}g;                              # the MANIFEST in LF line endings, so `sha256sum -c` reads it as delivered
for (@FILES, ['MANIFEST.txt', $manifest]) {
    my ($f, $t) = @$_;
    open my $fh, '>:raw', "$OUT/$f" or die "$OUT/$f: $!\n"; print $fh $t; close $fh;
    printf "%-16s %6d lines\n", $f, scalar(() = $t =~ /\n/g);
}
print "drop $DROP ($VERSION, $DELIVERED): $SUMMARY\n";
printf "requirements: %d in the model, %d in DOORS\n", scalar(grep { $_->[6] ne 'doors' } @REQ), scalar(grep { $_->[6] ne 'model' } @REQ);

# ---------------------------------------------------------------- the spider web, measured from the export itself
sub spider_web {
    my ($path, $ndiag) = @_;
    my $m = Xmi::load($path);
    my ($el, $st) = ($m->{el}, $m->{st});
    my $top = sub { my $x = shift; $x = $m->{parent}{$x} while defined $m->{parent}{$x} && defined $m->{parent}{ $m->{parent}{$x} }; $x };
    my $name = sub { $el->{ $_[0] } && defined $el->{ $_[0] }{a}{name} ? $el->{ $_[0] }{a}{name} : $_[0] };
    my @rels = grep { $el->{$_}{t} =~ /^(Abstraction|Dependency|Usage|Realization)$/ } @{ $m->{order} };
    my @blocks = grep { $st->{$_} && $st->{$_}{block} } @{ $m->{order} };
    my (%deg, %pk, %used);
    for my $r (@rels) {
        my @c = Xmi::_idrefs($el->{$r}, 'client'); my @s = Xmi::_idrefs($el->{$r}, 'supplier');
        $deg{$_}++, $used{$_}++ for @c, @s;
        for my $c (@c) { for my $s (@s) { my ($a, $b) = ($top->($c), $top->($s)); $pk{$a}{$b} = 1 if $a ne $b } }
    }
    for my $id (@{ $m->{order} }) {
        my $n = $el->{$id};
        $used{$_}++ for Xmi::_idrefs($n, 'type'), Xmi::_idrefs($n, 'general'), Xmi::_idrefs($n, 'represents');
    }
    my ($max) = sort { ($deg{$b} // 0) <=> ($deg{$a} // 0) || $name->($a) cmp $name->($b) } @blocks;
    my $sum = 0; $sum += $deg{$_} // 0 for @blocks;
    # package dependency cycles: strongly connected sets of top-level packages (Tarjan)
    my ($i, %ix, %low, %on, @stack, @scc) = (0);
    my $visit; $visit = sub {
        my $v = shift; $ix{$v} = $low{$v} = $i++; push @stack, $v; $on{$v} = 1;
        for my $w (sort keys %{ $pk{$v} || {} }) {
            if (!defined $ix{$w}) { $visit->($w); $low{$v} = $low{$w} if $low{$w} < $low{$v} }
            elsif ($on{$w}) { $low{$v} = $ix{$w} if $ix{$w} < $low{$v} }
        }
        if ($low{$v} == $ix{$v}) { my @c; while (1) { my $w = pop @stack; $on{$w} = 0; push @c, $w; last if $w eq $v } push @scc, [ sort map { $name->($_) } @c ] if @c > 1 }
    };
    $visit->($_) for grep { !defined $ix{$_} } sort keys %pk;
    # unused: a class nothing types, generalizes, relates to or owns a behavior through (requirements and test cases aside)
    my @unused = grep { my $id = $_; my $s = $st->{$id} || {};
        $el->{$id}{t} eq 'Class' && !$used{$id} && !grep({ /requirement|testcase|interfaceblock|constraintblock/i } keys %$s)
            && !XmlLite::kids($el->{$id}, 'ownedBehavior') } @{ $m->{order} };
    # duplicates: blocks with the same owned features (name and type) as another block
    my %sig;
    for my $b (@blocks) {
        my @f = sort map { ($_->{a}{name} // '') . ':' . $name->((Xmi::_idrefs($_, 'type'))[0] // '') } grep { ($_->{a}{'xmi:type'} // '') =~ /uml:(Property|Port)$/ } XmlLite::kids($el->{$b}, 'ownedAttribute');
        push @{ $sig{ join ',', @f } }, $b if @f;
    }
    my @dups = map { [ map { $name->($_) } @$_ ] } grep { @$_ > 1 } values %sig;
    my %bn = map { $name->($_) => 1 } @blocks;                    # stale copies no longer match: pair them by name
    my %have = map { join("\0", sort @$_) => 1 } @dups;
    for my $b (sort keys %bn) {
        my ($orig) = $b =~ /^Copy of (.+)$/ ? ($1) : $b =~ /^(.+)_old$/ ? ($1) : ();
        next unless defined $orig && $bn{$orig};
        my $k = join "\0", sort $b, $orig;
        push @dups, [ $orig, $b ] unless $have{$k}++;
    }
    return { elements => scalar @{ $m->{order} }, diagrams => $ndiag, relationships => scalar @rels, blocks => scalar @blocks,
             max => $deg{$max} // 0, max_block => $name->($max), mean => @blocks ? $sum / @blocks : 0,
             cycles => [ sort { "@$a" cmp "@$b" } @scc ], unused => [ map { $name->($_) } @unused ],
             duplicates => [ sort { "@$a" cmp "@$b" } map { [ sort @$_ ] } @dups ] };
}
my $w = spider_web("$OUT/tidewater.xmi", scalar @diagrams);
printf "spider web: %d elements, %d diagrams, %d relationships over %d blocks (max %d on %s, mean %.1f)\n",
    @$w{qw(elements diagrams relationships blocks max max_block mean)};
printf "  package dependency cycles: %d%s\n", scalar @{ $w->{cycles} }, join('', map { '  [' . join(' <-> ', @$_) . ']' } @{ $w->{cycles} });
printf "  unused: %d%s\n", scalar @{ $w->{unused} }, @{ $w->{unused} } ? ' (' . join(', ', @{ $w->{unused} }) . ')' : '';
printf "  duplicates: %d%s\n", scalar(map { @$_ - 1 } @{ $w->{duplicates} }), join('', map { '  [' . join(' = ', @$_) . ']' } @{ $w->{duplicates} });
