#!/usr/bin/perl
# kickoff.pl -- week zero for a model team: check the laptop, make the model repository, and set up the GitLab project,
# the first prime drop, the journal and the first issues -- one command at a time, each printed before it runs.
#
#   perl tools/gitlab/kickoff.pl doctor [--quick] [--fix] [--local DIR | --url URL [--token-env VAR]]
#   perl tools/gitlab/kickoff.pl scaffold DIR [--project GROUP/NAME] [--title T] [--noun-root N] [--verb-root V] [--levels L1A,...] [--layout-map FILE] [--force]
#   perl tools/gitlab/kickoff.pl start [--yes] [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME]
#                                      [--title T] [--conf FILE] [--dir REPO] [--journal DIR] [--team NAME] [--as USER]
#                                      [--drop DROPDIR --version V] [--sprints START COUNT] [--no-wiki] [--no-issues] [--from N]
#   perl tools/gitlab/kickoff.pl help [COMMAND]
#
# doctor   PASS / WARN / FAIL / SKIP, one line per check, with the exact command that fixes each failure. It changes
#          nothing, unless --fix: then it sets the recommended git settings (never your name or e-mail), printing each
#          `git config --global` line before it runs it. Exit 1 when anything FAILs.
# scaffold the model repository from tools/gitlab/templates: .gitlab-ci.yml, ci/job.pl, CODEOWNERS, .gitignore,
#          README.md, CHANGELOG.md, .gitlab/ (issue and MR templates, project.conf), docs/ (index, conventions, onboarding,
#          the model exchange agreement, ADRs 0001-0003, memo templates under docs/memos/templates/), sysml.conf,
#          verification/results.csv, model/library/conventions/Conventions.sysml (the level tags: --levels); `git init -b main` and the first commit.
# start    the whole week-zero sequence. Without --yes it only prints the steps and their commands (a dry run);
#          with --yes it runs them, stopping at the first failure with what to do next.
#
# Everything GitLab is done by bin/gitlab.pl (lib/GitLab.pm, lib/GitFlow.pm), the journal by bin/daily.pl: this
# script only puts their commands in order. Core Perl; runs under Git for Windows' Perl and Linux.
use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Find ();
use File::Temp qw(tempdir);
use Cwd qw(abs_path getcwd);
use Getopt::Long qw(GetOptionsFromArray);

my $KIT = abs_path("$FindBin::Bin/../..");
my $TPL = "$KIT/tools/gitlab/templates";
my $WIN = $^O =~ /^(MSWin32|cygwin|msys)$/ ? 1 : 0;

my %HELP = (
    doctor   => "kickoff.pl doctor [--quick] [--fix] [--local DIR | --url URL [--token-env VAR]]\n"
              . "  Checks Perl and its modules, git and its settings, Vim and the kit's Vim setup, curl, a quick self-test of\n"
              . "  the kit, GitLab reachability and an SSH key. --quick skips the self-test. --fix sets the recommended git\n"
              . "  settings (init.defaultBranch, core.autocrlf, pull.ff, merge.conflictstyle, core.longpaths on Windows),\n"
              . "  printing each command first; it never sets your name or e-mail. Exit 1 if anything FAILs.\n",
    scaffold => "kickoff.pl scaffold DIR [--project GROUP/NAME] [--title T] [--noun-root N] [--verb-root V] [--levels L1A,L2B,...] [--layout-map FILE] [--force]\n"
              . "  Makes the model repository in DIR from tools/gitlab/templates, runs git init -b main and commits it.\n"
              . "  --layout-map FILE: where each prime package lands (.ci/layout.map; flow vendor uses it from the first drop).\n"
              . "  Without it, .ci/layout.map.example explains the format.\n"
              . "  --levels names the part-tree levels, top first (default L1System,L2Segment,L3Subsystem,L4Assembly,L5Component,L6Part).\n"
              . "  DIR must be empty or missing (--force: fill it anyway). Defaults: --project tidewater/model, --title Tidewater.\n",
    start    => "kickoff.pl start [--yes] [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME] [--title T]\n"
              . "                 [--conf FILE] [--dir REPO] [--journal DIR] [--team NAME] [--as USER]\n"
              . "                 [--drop DROPDIR --version V] [--sprints START COUNT] [--no-wiki] [--no-issues] [--from N]\n"
              . "  Week zero, in order: doctor; scaffold; gitlab.pl setup (without schedules: they need develop; on --local\n"
              . "  with KIT = this kit); push main; flow init (develop); setup again (schedules); sprints; flow vendor (the first\n"
              . "  prime drop) and the drop's regenerated docs on its branch; daily.pl init +\n"
              . "  roster; wiki pages; the first issues from the Story template. Without --yes: print the plan only.\n",
);
sub usage { print STDERR "usage: kickoff.pl doctor|scaffold|start|help [COMMAND]  (kickoff.pl help COMMAND)\n"; 2 }

# ---------------------------------------------------------------- small helpers
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($f, $t) = @_; my (undef, $d) = File::Spec->splitpath($f); make_path($d) if length $d && !-d $d;
           open my $fh, '>:raw', $f or die "kickoff: cannot write $f: $!\n"; print $fh $t; close $fh }
sub capture {                                   # capture(cmd...) -> (output, exit code); stdout+stderr via a temp file
    my @cmd = @_;
    my $tmp = File::Temp->new(UNLINK => 1); my $tf = $tmp->filename;
    open my $oldout, '>&', \*STDOUT or die "kickoff: cannot save STDOUT: $!\n";
    open my $olderr, '>&', \*STDERR or die "kickoff: cannot save STDERR: $!\n";
    open STDOUT, '>', $tf or die "kickoff: cannot redirect STDOUT: $!\n";
    open STDERR, '>&', \*STDOUT or die "kickoff: cannot redirect STDERR: $!\n";
    my $rc = system { $cmd[0] } @cmd;
    open STDOUT, '>&', $oldout or die "kickoff: cannot restore STDOUT: $!\n";
    open STDERR, '>&', $olderr or die "kickoff: cannot restore STDERR: $!\n";
    my $out = slurp($tf) // '';
    return ($out, $rc == -1 ? 127 : $rc >> 8);
}
sub have { my $prog = shift; my ($o, $rc) = capture($prog, '--version'); $rc == 127 ? undef : $o }
sub shq { my $a = shift; $a =~ /^[\w.\/:=@%+,-]+$/ ? $a : do { (my $q = $a) =~ s/'/'\\''/g; "'$q'" } }
sub show { join ' ', map { shq($_) } @_ }
sub git_cfg { my ($key) = @_; my ($o, $rc) = capture('git', 'config', '--global', '--get', $key); $rc ? undef : (split /\n/, $o)[0] }

# ---------------------------------------------------------------- doctor
my @CORE_MODULES = qw(JSON::PP Digest::SHA Digest::MD5 MIME::Base64 File::Temp File::Path File::Copy File::Find File::Spec
                      File::Basename Getopt::Long Time::Local POSIX Encode Archive::Tar IO::Uncompress::Unzip List::Util Cwd);
sub doctor {
    my (%o) = @_;
    my @r;                                      # [status, what, fix]
    my $add = sub { push @r, [@_] };
    # perl
    $add->($] >= 5.010 ? 'PASS' : 'FAIL', sprintf('perl %vd (%s)', $^V, $^X), $] >= 5.010 ? undef : 'use the Perl that comes with Git for Windows (Git Bash: which perl)');
    my @miss = grep { my $m = $_; !eval "require $m; 1" } @CORE_MODULES;
    $add->(@miss ? 'FAIL' : 'PASS', @miss ? "perl modules missing: @miss" : 'perl core modules the kit uses (' . scalar(@CORE_MODULES) . ')',
           @miss ? 'this Perl is cut down: run the kit with Git for Windows\' Perl (C:\\Program Files\\Git\\usr\\bin\\perl.exe)' : undef);
    # git
    my $gv = have('git');
    if (!defined $gv) { $add->('FAIL', 'git not found', 'install Git for Windows (it brings git, bash, perl and vim), then open Git Bash') }
    else {
        my ($maj, $min) = $gv =~ /(\d+)\.(\d+)/;
        my $ok = defined $maj && ($maj > 2 || ($maj == 2 && $min >= 28));
        (my $line = (split /\n/, $gv)[0]) =~ s/\s+$//;
        $add->($ok ? 'PASS' : 'FAIL', $line, $ok ? undef : 'git 2.28 or newer is needed (git init -b): update Git for Windows');
        for my $k (['user.name', 'git config --global user.name "Your Name"'], ['user.email', 'git config --global user.email you@agency.gov']) {
            my $v = git_cfg($k->[0]);
            $add->(defined $v ? 'PASS' : 'FAIL', defined $v ? "git $k->[0] = $v" : "git $k->[0] is not set (commits need it)", defined $v ? undef : $k->[1]);
        }
        for my $s (recommended()) {
            my ($key, $want, $why) = @$s;
            my $v = git_cfg($key);
            if (defined $v && $v eq $want) { $add->('PASS', "git $key = $want") }
            elsif ($o{fix}) {
                print "running: git config --global $key $want\n";
                my ($out, $rc) = capture('git', 'config', '--global', $key, $want);
                $add->($rc ? 'FAIL' : 'PASS', $rc ? "git $key could not be set: $out" : "git $key = $want (set by --fix)", $rc ? "git config --global $key $want" : undef);
            }
            else { $add->('WARN', "git $key is " . (defined $v ? "'$v'" : 'not set') . ", recommended $want ($why)", "git config --global $key $want   (or: kickoff.pl doctor --fix)") }
        }
    }
    # vim and the kit's Vim setup
    my $vv = have('vim');
    if (!defined $vv) { $add->('FAIL', 'vim not found', 'Vim comes with Git for Windows: run this from Git Bash') }
    else {
        (my $line = (split /\n/, $vv)[0]) =~ s/\s+$//;
        $add->('PASS', $line);
        my $home = $ENV{HOME} // '';
        my ($rc) = grep { -f } map { "$home/$_" } qw(.vimrc _vimrc .vim/vimrc);
        my $t = defined $rc ? slurp($rc) // '' : '';
        if ($t =~ /scrum\.vim/) { $add->('PASS', "the kit's Vim setup is sourced ($rc)") }
        else { $add->('FAIL', "the kit's Vim setup is not sourced" . (defined $rc ? " in $rc" : ' (no ~/.vimrc)'),
                      "echo 'source $KIT/vim/scrum.vim' >> ~/.vimrc   (and 'syntax on'; :help agile-vimrc)") }
    }
    # curl
    my $cv = have('curl');
    $add->(defined $cv ? 'PASS' : 'FAIL', defined $cv ? join(q( ), (split q( ), (split /\n/, $cv)[0])[0, 1]) : q(curl not found),
           defined $cv ? undef : 'curl comes with Git for Windows: run this from Git Bash');
    # the kit's self-test
    if ($o{quick}) { $add->('SKIP', "the kit's self-test (--quick)") }
    else {
        for my $t (qw(prelude.t ledger.t)) {
            my ($out, $rc) = capture($^X, "$KIT/tests/$t");
            my ($sum) = $out =~ /^(# (?:all \d+ passed|\d+ of \d+ FAILED))/m;
            $add->($rc ? 'FAIL' : 'PASS', "kit self-test tests/$t: " . ($sum // "exit $rc"), $rc ? "perl $KIT/tests/$t   (read the 'not ok' lines; the kit checkout may be incomplete)" : undef);
        }
        my $tmp = tempdir(CLEANUP => 1);
        my ($out, $rc) = capture($^X, "$KIT/bin/xmi2sysml.pl", '--out', "$tmp/v2", '--check', "$KIT/examples/tidewater-v1/tidewater.xmi");
        my ($sum) = $out =~ /^(xmi2sysml: .*)$/m;
        $add->($rc ? 'FAIL' : 'PASS', 'converter and grammar check: ' . ($sum // "exit $rc"), $rc ? "perl $KIT/bin/xmi2sysml.pl --report --check $KIT/examples/tidewater-v1/tidewater.xmi" : undef);
    }
    # GitLab
    if ($o{local}) {
        $add->('PASS', -f "$o{local}/gitlab.json" ? "GitLab: the local emulator in $o{local}" : "GitLab: the local emulator ($o{local} is created on first use)");
    } elsif (my $url = $o{url} // $ENV{GITLAB_URL}) {
        my $var = $o{token_env} // 'GITLAB_TOKEN';
        if (!defined $cv) { $add->('SKIP', "GitLab $url: no curl to ask it") }
        elsif (!length($ENV{$var} // '')) { $add->('FAIL', "GitLab $url: no token in \$$var", "create a personal access token (scope api) under Preferences > Access tokens, then: export $var=glpat-...") }
        else {
            (my $base = $url) =~ s{/+$}{};
            my ($out, $rc) = capture('curl', '-s', '-o', File::Spec->devnull, '-w', '%{http_code}', '--max-time', '15', '-H', "PRIVATE-TOKEN: $ENV{$var}", "$base/api/v4/version");
            my $code = $out =~ /(\d{3})\s*$/ ? $1 : '000';
            $add->($code eq '200' ? 'PASS' : 'FAIL', "GitLab $base: " . ($code eq '200' ? 'reachable, token accepted' : "HTTP $code"),
                   $code eq '200' ? undef : $code eq '401' ? "the token in \$$var is wrong or expired: make a new one (scope api)" : 'check the URL, the VPN and the proxy (curl -v ' . "$base/api/v4/version)");
        }
    } else { $add->('SKIP', 'GitLab: none named', 'export GITLAB_URL=https://gitlab.your.agency  (or --local DIR for the offline emulator)') }
    # SSH key
    my $home = $ENV{HOME} // '';
    my ($key) = grep { -f } map { "$home/.ssh/$_" } qw(id_ed25519.pub id_ecdsa.pub id_rsa.pub);
    $add->($key ? 'PASS' : 'WARN', $key ? "SSH key $key" : 'no SSH key (HTTPS with a token works too)',
           $key ? undef : 'ssh-keygen -t ed25519 -C "you@agency.gov"   then paste ~/.ssh/id_ed25519.pub into GitLab > Preferences > SSH Keys');
    # report
    my %n;
    for my $r (@r) {
        $n{ $r->[0] }++;
        printf "%-5s %s\n", $r->[0], $r->[1];
        print "      fix: $r->[2]\n" if $r->[2] && $r->[0] ne 'PASS';
    }
    printf "doctor: %d pass, %d warn, %d fail, %d skipped\n", map { $n{$_} // 0 } qw(PASS WARN FAIL SKIP);
    return $n{FAIL} ? 1 : 0;
}
sub recommended {
    (['init.defaultBranch', 'main', 'new repositories start on main'],
     ['core.autocrlf', 'false', 'model files keep their line endings; the baselines hash them'],
     ['pull.ff', 'only', 'a pull never makes a surprise merge commit'],
     ['merge.conflictstyle', 'diff3', 'conflicts show the common ancestor too'],
     ($WIN ? (['core.longpaths', 'true', 'deep model folders exceed the old Windows path limit']) : ()));
}

# ---------------------------------------------------------------- scaffold
my %SKIP_TPL = map { $_ => 1 } qw(project.conf release-notes.md CHANGELOG.md);   # project.conf goes to .gitlab/; release notes are written by the pipeline;
                                                                      # CHANGELOG.md is written fresh (the template's is a filled-in example)
sub LAYOUT_EXAMPLE { <<'EOF' }
# .ci/layout.map.example -- an example, not in use. Rename it to .ci/layout.map (by merge request, BEFORE the first
# prime drop) to choose where each top-level package of a drop lands in this repository:
#
#   PACKAGE = folder/                -> model/folder/<Package>.sysml
#   PACKAGE = folder/File.sysml      -> exactly that file
#
# gitlab.pl flow vendor reads .ci/layout.map for every drop (both converters use it), so a package always lands at
# the same path and the next drop merges 3-way on vendor/prime. Without it the converters write one folder per
# package (model/<package>/) and the DOORS modules under model/doors/. A package the prime adds later that the map
# does not list lands in unsorted/, and the converter's report names it.
#
# The folders are the repository's layers, lowest first: library -> requirements -> logical -> physical ->
# analysis -> verification (a package may depend only on its own layer or a lower one). Tidewater's map, for
# example (examples/tidewater-v1/layout.map in the kit):
#
# Types                = library/
# Interfaces           = library/
# Tidewater            = library/
# Stakeholder Needs    = requirements/stakeholder/
# System Requirements  = requirements/system/
# Segment Requirements = requirements/segment/
# Requirements         = requirements/model/
# Behavior             = logical/
# Network              = physical/network/
# Stations             = physical/stations/
# DataCenter           = physical/datacenter/
# Operations           = physical/operations/
# Allocations          = physical/allocation/
# Analysis             = analysis/
# Verification         = verification/
# Legacy Import        = legacy/
EOF
sub scaffold {
    my ($dir, %o) = @_;
    my $project = $o{project} // 'tidewater/model';
    my $title   = $o{title} // 'Tidewater';
    die "kickoff: --project is GROUP/NAME, not '$project'\n" unless $project =~ m{^[\w.-]+(?:/[\w.-]+)+$};
    if (-e $dir) {
        opendir my $dh, $dir or die "kickoff: cannot read $dir: $!\n";
        my @e = grep { !/^\.\.?$/ } readdir $dh; closedir $dh;
        die "kickoff: $dir is not empty (use an empty or new folder, or --force)\n" if @e && !$o{force};
    }
    -d "$TPL" or die "kickoff: no templates in $TPL (is this the agile kit?)\n";
    make_path($dir);
    my @made;
    my $put = sub { my ($rel, $text) = @_; spew("$dir/$rel", $text); push @made, $rel };
    my $subst = sub { my $t = shift; $t =~ s{\btidewater/model\b}{$project}g; $t };
    # the templates: everything that belongs in the repository
    File::Find::find({ no_chdir => 1, wanted => sub {
        return unless -f $_;
        (my $rel = $File::Find::name) =~ s{^\Q$TPL\E/}{};
        return if $rel =~ m{^(wiki|prime)/} || $SKIP_TPL{$rel};
        my $to = $rel eq q(gitlab-ci.yml) ? q(.gitlab-ci.yml)
               : $rel =~ m{^memos/(.+)} ? "docs/memos/templates/$1"       # memo templates: the team copies one per memo into docs/memos/
               : $rel;                                                 # docs/ (README, conventions, onboarding, agreement, ADRs) as is
        $put->($to, $subst->(slurp($File::Find::name)));
    } }, $TPL);
    $put->('.gitlab/project.conf', $subst->(slurp("$TPL/project.conf")));
    if ($title ne 'Tidewater' && -f "$dir/README.md") {
        my $t = slurp("$dir/README.md");
        $t =~ s/^# Tidewater\b/# $title/m;
        spew("$dir/README.md", $t);
    }
    my @levels = @{ $o{levels} // [qw(L1System L2Segment L3Subsystem L4Assembly L5Component L6Part)] };
    my ($noun, $verb) = ($o{noun_root} // q(), $o{verb_root} // q());   # set once the model has them: a root that does not exist fails docs
    $put->('sysml.conf', join '',
        "# sysml.conf -- read by the kit's tools/sysml/model.pl (key = value; # comments). Written by kickoff.pl scaffold.\n",
        "title         = $title\n",
        (length $noun ? "noun_root     = $noun\n" : "# noun_root  = TopPartDef      the part def at the top of the part tree (set it once the model has one)\n"),
        (length $verb ? "verb_root     = $verb\n" : "# verb_root  = TopActionDef    the action def at the top of the function tree; set it once the model has one\n# (until then model.pl docs skips the IDEF0 plates). Tidewater: noun_root = ObservationNetwork, verb_root = ObserveCoast\n"),
        "level_tags    = " . join(q(, ), @levels) . "\n",
        "# The level tags are metadata defs in model/library/conventions/Conventions.sysml: rename them in both places\n",
        "# (or scaffold with --levels L1Network,L2Segment,...).\n",
        "# layers: the dependency order of the root packages, lowest first; `;` between layers, `,` within one. A package may\n",
        "# depend only on its own layer or a lower one (the complexity job). The folders under model/ are the same layers:\n",
        "#   library (types, interfaces, conventions); requirements; logical (behavior); physical (structure, allocation);\n",
        "#   analysis; verification. Add each package here as it arrives, e.g.\n",
        "#   layers = Types, Conventions; Interfaces; System Requirements; Behavior; Network, Stations; Analysis; Verification\n",
        "layers        = Conventions\n",
        "# The other keys (idef0_name, steps, control_types, alloc_prefix, acronyms, need_prefix): :help agile-mbse, or\n",
        "# the header of tools/sysml/model.pl.\n");
    $put->(q(model/library/conventions/Conventions.sysml), join q(),
        "// Government-owned (model/library/conventions): the metadata the team tags the model with, in one place,\n",
        "// reviewed by merge request. The level tags below name the levels of the part tree, top first (sysml.conf\n",
        "// level_tags lists the same names). The port adds here whatever else the v1 profile had.\n",
        "package Conventions {\n",
        "    doc /* Metadata definitions used across the model. */\n",
        (map { "    metadata def $levels[$_] { doc /* Level " . ($_ + 1) . " of the part tree. */ }\n" } 0 .. $#levels),
        "}\n");
    $put->('verification/results.csv', "requirement,case,verdict,commit,environment,timestamp,signed_by\n");
    $put->('CHANGELOG.md', <<"EOF");
# Changelog

All notable changes to the $title model, one section per baseline, newest first. Entries come from the merge
requests' `Changelog:` commit trailers (the wiki page *Definition of Done*). The release job publishes a baseline's
section as its release notes.

<!-- When you cut a baseline, on the release branch: rename `## [Unreleased]` to `## [baseline-N] -- DATE` and
     delete the headings left empty under it; put a fresh `## [Unreleased]` with the four empty headings above it;
     add the link lines at the bottom. The release job publishes exactly the `## [baseline-N]` section (empty
     headings and this comment are never part of it). A baseline entry looks like this (indented here so it is
     not taken for a real section):

    ## [baseline-1] -- 2027-03-19

    ### Added
    - The structure ported from prime drop v1.0: 12 packages, 40 part definitions (!3 to !21).
    - Requirements from DOORS with their doorsId, and the satisfy/verify trace (!22 to !30).

    ### Prime drops merged
    - v1.0, 2026-10-02 (#5)

    [Unreleased]: ../-/compare/baseline-1...develop
    [baseline-1]: ../-/tags/baseline-1
-->

## [Unreleased]

### Added

### Changed

### Fixed

### Prime drops merged

[Unreleased]: ../-/commits/develop
EOF
    $put->('docs/adr/0001-record-decisions.md', <<'EOF');
# 1. Record decisions in the repository

Date: (the day you merge this)

## Status

Accepted

## Context

The team makes structural decisions about the model and the process: branching, merge method, where the prime's drops
land, what counts as progress. Decisions kept in e-mail or slides get lost, and new people repeat old debates.

## Decision

Each decision is a short Markdown file in `docs/adr/`, numbered in order, with Context, Decision and Consequences.
A decision is proposed in a merge request and accepted when the MR merges. A changed decision gets a new file that
supersedes the old one; the old file stays.

## Consequences

The reasons behind the model's structure are reviewed like the model and travel with it. Writing a decision down
takes ten minutes.
EOF
    if ($o{layout_map}) {                     # the project's own layout: flow vendor reads .ci/layout.map from the first drop on
        my $map = slurp($o{layout_map}) // die "kickoff: cannot read $o{layout_map}: $!\n";
        $put->('.ci/layout.map', "# .ci/layout.map -- where each top-level package of a prime drop goes in this repository.\n"
            . "# gitlab.pl flow vendor (and the drop intake) read it for every drop, so a package always lands at the same\n"
            . "# path and the next drop merges 3-way on vendor/prime. Change it only by merge request, and before a drop:\n"
            . "# moving a package later means re-importing on the vendor branch. Copied by kickoff.pl scaffold.\n#\n" . $map);
    } else {
        $put->('.ci/layout.map.example', LAYOUT_EXAMPLE());
    }
    {   # the outline ratchet starts at what the skeleton has (new folders hold one entry each); the port only lowers it
        my ($chk) = capture($^X, "$KIT/tools/sysml/model.pl", '--root', $dir, 'check');
        my ($v) = $chk =~ /^violations\s+(\d+)/m;
        my ($m) = $chk =~ /^\@L tag mismatches\s+(\d+)/m;
        $put->('.ci/outline-max', (($v // 0) + ($m // 0)) . "\n");
        # the generated documents are committed with the model that made them (the docs job checks they are current)
        my ($d, $drc) = capture($^X, "$KIT/tools/sysml/model.pl", '--root', $dir, 'docs');
        die "kickoff: model.pl docs failed on the new repository: $d" if $drc;
        push @made, map { "docs/$_ (generated)" } grep { -f "$dir/docs/$_" } qw(Nouns.md Verbs.md Traceability.md);
    }
    # git: init on main, first commit
    my $cwd = getcwd();
    chdir $dir or die "kickoff: cannot enter $dir: $!\n";
    my @git = ('git', '-c', 'core.autocrlf=false', '-c', 'commit.gpgsign=false');
    my ($out, $rc) = capture(@git, 'init', '-q', '-b', 'main');
    die "kickoff: git init failed: $out" if $rc;
    capture('git', 'config', 'core.autocrlf', 'false');
    ($out, $rc) = capture(@git, 'add', '-A');
    die "kickoff: git add failed: $out" if $rc;
    my @who = (defined git_cfg('user.name') ? () : ('-c', 'user.name=kickoff'), defined git_cfg('user.email') ? () : ('-c', 'user.email=kickoff@example.invalid'));
    ($out, $rc) = capture(@git, @who, 'commit', '-q', '-m', "Scaffold the $title model repository (kickoff.pl)");
    die "kickoff: git commit failed: $out" if $rc;
    chdir $cwd;
    print "made $dir (git, branch main, 1 commit):\n";
    print "  $_\n" for sort @made;
    print "level tags: ", join(q(, ), @levels), " -- to rename them, edit model/library/conventions/Conventions.sysml and\n",
          "  level_tags in sysml.conf together (they must match)\n";
    print "next:\n",
          "  edit .gitlab/project.conf (members, labels, sprints), README.md and sysml.conf for your project\n",
          "  perl $KIT/tools/gitlab/kickoff.pl start --dir $dir ...   (or the steps by hand: kickoff.pl help start)\n";
    return 0;
}

# ---------------------------------------------------------------- start
sub conf_members {                              # [members] user = level, in file order
    my $t = slurp(shift) // return ();
    my ($sec, @m) = ('');
    for my $l (split /\n/, $t) {
        $l =~ s/\s+[;#].*$//; $l =~ s/^\s+|\s+$//g;
        next if $l eq '' || $l =~ /^[;#]/;
        if ($l =~ /^\[(.+)\]$/) { $sec = $1; next }
        push @m, [$1, $2] if $sec eq 'members' && $l =~ /^(\S+)\s*=\s*(\S+)/;
    }
    @m;
}
sub conf_value { my ($f, $sec, $key) = @_; my $t = slurp($f) // return undef; my $in = '';
    for my $l (split /\n/, $t) { $l =~ s/\s+;.*$//; if ($l =~ /^\s*\[(.+)\]\s*$/) { $in = $1; next } return $1 if $in eq $sec && $l =~ /^\s*\Q$key\E\s*=\s*(\S+)/ } undef }
sub without_section {                           # the project file minus one [section] (setup runs before develop exists)
    my ($f, $drop) = @_;
    my ($in, $out) = ('', '');
    for my $l (split /(?<=\n)/, slurp($f) // '') {
        $in = $1 if $l =~ /^\s*\[(.+)\]\s*$/;
        $out .= $l unless $in eq $drop;
    }
    $out;
}
sub run_conf {                                  # the project file as setup should apply it now: minus one section (schedules need develop),
    my ($conf, $drop, $local) = @_;            # and on the local emulator with KIT = this kit (the jobs run here, before the first push)
    my $t = defined $drop ? without_section($conf, $drop) : (slurp($conf) // '');
    if ($local) { my $in = ''; $t = join '', map { $in = $1 if /^\s*\[(.+)\]\s*$/; $in eq 'variables' && /^(\s*KIT\s*=\s*)/ ? "$1$KIT\n" : $_ } split /(?<=\n)/, $t }
    my $tmp = File::Temp->new(SUFFIX => '.conf', UNLINK => 1); print $tmp $t; close $tmp;
    $tmp;
}
sub start {
    my (%o) = @_;
    my $yes = $o{yes};
    my @gl = ($^X, "$KIT/bin/gitlab.pl", ($o{local} ? ('--local', abs_path_new($o{local})) : ()),
              ($o{url} ? ('--url', $o{url}) : ()), ($o{token_env} ? ('--token-env', $o{token_env}) : ()));
    my $repo = $o{dir} // 'model';
    my $conf_src = $o{conf};
    my $project = $o{project};
    my $title = $o{title} // 'Tidewater';
    my $journal = $o{journal} // 'journal';
    my $team = $o{team} // 'Model';
    my @steps;
    my $step = sub { push @steps, { @_ } };
    my $dropdir = $o{drop};
    die "kickoff: --drop needs --version (e.g. v1.0)\n" if $dropdir && !$o{version};
    die "kickoff: no --local DIR or --url URL (or GITLAB_URL): which GitLab?\n" unless $o{local} || $o{url};

    my ($conf, $as);                           # resolved before each step: the scaffold may only now exist
    my $resolve = sub {
        $conf = $conf_src // (-f "$repo/.gitlab/project.conf" ? "$repo/.gitlab/project.conf" : "$TPL/project.conf");
        $project = $o{project} // conf_value($conf, q(project), q(path)) // q(tidewater/model);
        $as = $o{as} // (map { $_->[0] } grep { $_->[1] =~ /^(maintainer|owner)$/ } conf_members($conf))[0] // $ENV{GITLAB_USER} // q(root);
    };
    my $tmpconf;
    my $glp = sub { (@gl, '--project', $project, '--as', $as, @_) };
    $step->(title => 'Check this laptop', why => 'a missing tool or setting is cheaper to fix now than in the middle of a sprint',
            cmd => [$^X, $0, 'doctor', '--quick', ($o{local} ? ('--local', $o{local}) : ()), ($o{url} ? ('--url', $o{url}) : ())], allow_fail => 1);
    $step->(title => 'Make the model repository', why => 'the templates give the pipeline, the review rules and the issue templates from day one',
            skip => -d "$repo/.git" ? "$repo already exists" : undef,
            cmd => [$^X, $0, 'scaffold', $repo, '--project', ($project // 'tidewater/model'), '--title', $title, ($o{layout_map} ? ('--layout-map', $o{layout_map}) : ())]);
    $step->(title => 'Create the GitLab project from the project file (schedules come later: they need develop)',
            why => 'settings, members, labels, sprints and branch protection as a reviewed file, not clicks',
            cmd_dyn => sub { $tmpconf = run_conf($conf, 'schedules', $o{local}); ([$glp->(q(setup), $tmpconf->filename)]) },
            show => sub { show($glp->(q(setup), "$conf")) . ($o{local} ? q(   (a copy: without [schedules], KIT = this kit)) : q(   (a copy without [schedules]))) });
    $step->(title => 'Push the scaffold to main', why => 'the first commit is the project\'s starting point; everything after it arrives by merge request',
            cmd_dyn => sub { my $url = remote_url(\%o, $project);
                             my $has = -d "$repo/.git" && (capture('git', '-C', $repo, 'remote'))[0] =~ /^origin$/m;
                             (($has ? () : ([ 'git', '-C', $repo, 'remote', 'add', 'origin', $url ])), [ 'git', '-C', $repo, 'push', '-q', '-u', 'origin', 'main' ],
                              # a GitLab server starts main's first pipeline on the push; the local emulator is told to
                              ($o{local} ? ([$glp->('pipeline', 'run', 'main', '--source', 'push')]) : ())) },
            env => sub { (GITLAB_USER_LOGIN => $as) });
    $step->(title => 'Start gitflow: develop from main', why => 'develop is where work lands; main only takes baselines',
            dir => $repo, cmd_dyn => sub { ([$glp->('flow', 'init')]) }, env => sub { (GITLAB_USER_LOGIN => $as) });
    $step->(title => 'Apply the whole project file again (now with the schedules)', why => 'setup is safe to re-run: it updates what differs',
            cmd_dyn => sub { $tmpconf = run_conf($conf, undef, $o{local}); ([$glp->(q(setup), $tmpconf->filename)]) },
            show => sub { show($glp->(q(setup), "$conf")) . ($o{local} ? q(   (a copy: KIT = this kit)) : '') });
    $step->(title => 'Sprints as milestones', why => 'each two-week sprint is a GitLab milestone that issues and MRs belong to',
            skip_if => sub { $o{sprints} ? undef : 'the project file\'s [milestones] made them (or pass --sprints START COUNT)' },
            cmd_dyn => sub { ([$glp->('sprints', @{ $o{sprints} })]) });
    $step->(title => 'Import the first prime drop onto vendor/prime', why => 'the prime\'s delivery lands on its own branch, converted but untouched, and is merged by MR',
            skip_if => sub { $dropdir ? undef : 'no --drop given (later: gitlab.pl flow vendor DROPDIR VERSION in the clone)' },
            dir => $repo, cmd_dyn => sub { ([$glp->('flow', 'vendor', abs_path_new($dropdir), $o{version})]) }, env => sub { (GITLAB_USER_LOGIN => $as) });
    $step->(title => 'Regenerate the documents for the drop, on its branch',
            why => 'the drop changes the model, so the generated documents must change in the same merge request (the docs job checks)',
            skip_if => sub { $dropdir ? undef : 'no --drop given' },
            dir => $repo, env => sub { (GITLAB_USER_LOGIN => $as) },
            cmd_dyn => sub { ([$^X, "$KIT/tools/sysml/model.pl", 'docs'], ['git', 'add', '-A', 'docs'],
                              ['git', '-c', 'core.autocrlf=false', 'commit', '-q', '--allow-empty', '-m', "Regenerate docs for prime drop $o{version}"],
                              [$glp->('flow', 'publish')]) });
    $step->(title => 'Make the journal and the roster', why => 'stand-ups, sprints and stories are recorded in the kit\'s journal; tasks stay in GitLab',
            skip_if => sub { -f "$journal/scrum.conf" ? "$journal already holds a journal" : undef },
            cmd_dyn => sub { my @c = ([$^X, "$KIT/bin/daily.pl", 'init', $journal]);
                             for my $m (conf_members($conf)) { my ($u, $lvl) = @$m;
                                 push @c, [$^X, "$KIT/bin/daily.pl", '--conf', "$journal/scrum.conf", 'roster', 'add', ucfirst($u), "$u\@example.invalid", $team, ucfirst($lvl), 'Government'] }
                             @c });
    $step->(title => 'Wiki pages: Home, Definition of Ready and Done, Gitflow, Onboarding, ...', why => 'the working agreements live where everyone looks',
            skip_if => sub { $o{no_wiki} ? '--no-wiki' : undef },
            cmd_dyn => sub { my @c; opendir my $dh, "$TPL/wiki" or return (); for my $f (sort grep { /\.md$/ } readdir $dh) { (my $t = $f) =~ s/\.md$//; push @c, [$glp->('wiki', 'put', $t, "$TPL/wiki/$f")] } closedir $dh; @c });
    $step->(title => 'The first stories, from the Story template', why => 'sprint 1 starts with work already written down, each with its acceptance criteria',
            skip_if => sub { $o{no_issues} ? '--no-issues' : undef },
            dir => $repo,
            cmd_dyn => sub { map { [$glp->('issue', 'new', $_->[0], '--template', 'Story', '--milestone', 'Sprint 1', '--assign', $_->[1])] }
                             (['Create the GitLab project and protect its branches', $as], ['First pipeline gates every merge request', $as],
                              ['Receive the first prime drop and record it', $as], ['Convert the first drop and assess it', $as],
                              ['Working agreements: Definition of Ready and Done', $as]) });
    # run (or print) them
    my $n = 0;
    my $from = $o{from};
    print $yes ? "kickoff: week zero, running each step\n" : "kickoff: week zero, the plan (nothing runs without --yes)\n";
    for my $s (@steps) {
        $n++;
        my @cmds;
        my $skip = $s->{skip} // ($s->{skip_if} ? $s->{skip_if}->() : undef);
        print "\n== step $n: $s->{title}\n   why: $s->{why}\n";
        if ($skip) { print "   skipped: $skip\n"; next }
        if ($from && $n < $from) { print "   skipped: before --from $from\n"; next }
        $resolve->();
        if ($s->{cmd}) { @cmds = ($s->{cmd}) }
        else { @cmds = $s->{cmd_dyn}->() }
        my %env = $s->{env} ? $s->{env}->() : ();
        for my $c (@cmds) {
            my $shown = $s->{show} && $c == $cmds[0] ? $s->{show}->() : show(@$c);
            print '   $ ', (%env ? join(' ', map { "$_=" . shq($env{$_}) } sort keys %env) . ' ' : ''), ($s->{dir} ? "(in $s->{dir}) " : ''), $shown, "\n";
            next unless $yes;
            local @ENV{ keys %env } = values %env;
            my $cwd = getcwd();
            if ($s->{dir}) { chdir $s->{dir} or die "kickoff: cannot enter $s->{dir}: $!\n" }
            my ($out, $rc) = capture(@$c);
            chdir $cwd;
            if (length $out) { $out =~ s/^/   | /mg; $out .= "\n" if $out !~ /\n$/; print $out }
            if ($rc && !$s->{allow_fail}) {
                print "kickoff: step $n failed (exit $rc). Fix what it says, then carry on from this step:\n",
                      "         kickoff.pl start --yes --from $n (the same options as before)\n";
                return 1;
            }
            print "   (doctor found problems: fix them soon; continuing)\n" if $rc && $s->{allow_fail};
        }
    }
    print "\nkickoff: " . ($yes ? 'week zero is set up.' : 'that is the plan; run again with --yes to do it.') . "\n";
    print "next: the sprint 1 kickoff -- perl $KIT/bin/daily.pl --conf $journal/scrum.conf new; the board at the project's Issues > Boards\n" if $yes;
    return 0;
}
sub abs_path_new { my $p = shift; return $p if File::Spec->file_name_is_absolute($p); File::Spec->rel2abs($p) }
sub remote_url {                                # the clone URL: the emulator's bare repo, or the server's https URL
    my ($o, $project) = @_;
    return abs_path_new($o->{local}) . "/repos/$project.git" if $o->{local};
    (my $base = $o->{url}) =~ s{/+$}{};
    "$base/$project.git";
}

# ---------------------------------------------------------------- main
sub main {
    my @a = @_;
    my $cmd = shift @a // '';
    if ($cmd eq 'help' || $cmd eq '--help' || $cmd eq '-h') {
        my $t = shift @a;
        if ($t && $HELP{$t}) { print $HELP{$t}; return 0 }
        print "kickoff.pl -- week zero for a model team (tools/gitlab/kickoff.pl)\n\n", map { $HELP{$_} . "\n" } qw(doctor scaffold start);
        return 0;
    }
    my %o;
    if ($cmd eq 'doctor') {
        GetOptionsFromArray(\@a, \%o, 'quick', 'fix', 'local=s', 'url=s', 'token-env=s') or return usage();
        $o{token_env} = delete $o{'token-env'};
        return doctor(%o);
    }
    if ($cmd eq 'scaffold') {
        GetOptionsFromArray(\@a, \%o, q(project=s), q(title=s), q(noun-root=s), q(verb-root=s), q(levels=s), q(layout-map=s), q(force)) or return usage();
        if (defined $o{'layout-map'} && !-f $o{'layout-map'}) { print STDERR "kickoff: no layout map $o{'layout-map'}\n"; return 2 }
        if (defined $o{levels}) {
            my @l = grep { length } map { s/^\s+|\s+$//gr } split /,/, $o{levels};
            if (!@l || grep { !/^[A-Za-z_]\w*$/ } @l) { print STDERR "kickoff: --levels is a comma list of names, top level first (e.g. L1Network,L2Segment,L3Station)\n"; return 2 }
            $o{levels} = \@l;
        }
        my $dir = shift @a or do { print STDERR "kickoff: scaffold needs a DIR\n"; return 2 };
        return scaffold($dir, %o, noun_root => $o{'noun-root'}, verb_root => $o{'verb-root'}, layout_map => $o{'layout-map'});
    }
    if ($cmd eq 'start') {
        my @sp;
        GetOptionsFromArray(\@a, \%o, 'yes', 'local=s', 'url=s', 'token-env=s', 'project=s', 'title=s', 'conf=s', 'dir=s', 'journal=s',
                            'team=s', 'as=s', 'from=i', 'drop=s', 'version=s', 'sprints=s{2}' => \@sp, 'no-wiki', 'no-issues', 'layout-map=s') or return usage();
        if (defined $o{'layout-map'}) { if (!-f $o{'layout-map'}) { print STDERR "kickoff: no layout map $o{'layout-map'}\n"; return 2 } $o{'layout-map'} = abs_path_new($o{'layout-map'}) }
        $o{sprints} = \@sp if @sp;
        $o{url} //= $ENV{GITLAB_URL} unless $o{local};
        $o{$_ =~ tr/-/_/r} = delete $o{$_} for grep { /-/ } keys %o;
        return start(%o);
    }
    return usage();
}
exit main(@ARGV);
