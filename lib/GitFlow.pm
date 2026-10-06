package GitFlow;
# Gitflow for a model repository, with GitLab merge requests at every hand-off:
#
#   main            released baselines only (a merge from release/* or hotfix/*, then tag baseline-N)
#   develop         integration; GitLab's default branch, so "Closes #N" in an MR closes the issue
#   feature/<iid>-<slug>   one task or story, from develop, back to develop by MR
#   release/<name>  stabilise a baseline: from develop, MR to main, tag, then back-merge main -> develop
#   hotfix/<name>   a fix to a released baseline: from main, MR to main, tag, back-merge
#   vendor/prime    the raw converter output of each prime drop (never edited by hand): merging it into a
#                   feature branch is a three-way merge of the prime's change into the government's model
#
#   my $f = GitFlow->new(dir => $clone, gl => $gl, project => 'tidewater/model', user => 'bob', name => 'Bob', email => '...');
#   $f->clone; $f->init; $f->start(feature => '12-close-stations-todos'); ...edit...; $f->commit('Close the Stations TODOs');
#   my $mr = $f->finish(title => '...', description => "Closes #12"); # the MR; then review, approve, $gl->merge_mr
#
# Every git command runs with core.autocrlf=false; commits take their dates from the GitLab clock ($gl->now), so a
# simulation replays real-looking history; pushes carry GITLAB_USER_LOGIN for the emulator's protection hook.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Basename qw(dirname basename);
use Cwd qw(abs_path);
use Digest::SHA ();

my %BR = (main => 'main', develop => 'develop', feature => 'feature/', release => 'release/', hotfix => 'hotfix/', vendor => 'vendor/prime');

sub new {
    my ($class, %o) = @_;
    defined $o{$_} or die "GitFlow: new needs $_\n" for qw(dir project user);
    my $self = bless { %o, branches => { %BR, %{ $o{branches} // {} } }, tag_prefix => $o{tag_prefix} // 'baseline-' }, $class;
    $self->{name} //= ucfirst $o{user};
    $self->{email} //= "$o{user}\@example.invalid";
    $self;
}
sub dir { $_[0]{dir} }
sub _now { my $self = shift; $self->{gl} ? $self->{gl}->now : undef }
sub _env {
    my $self = shift;
    my $d = $self->_now;
    return (GIT_AUTHOR_NAME => $self->{name}, GIT_AUTHOR_EMAIL => $self->{email}, GIT_COMMITTER_NAME => $self->{name}, GIT_COMMITTER_EMAIL => $self->{email},
            GITLAB_USER_LOGIN => $self->{user}, GIT_TERMINAL_PROMPT => 0, ($d ? (GIT_AUTHOR_DATE => $d, GIT_COMMITTER_DATE => $d) : ()));
}
sub git_rc {                                  # git_rc(@args) -> (output, exit code), in the clone
    my ($self, @args) = @_;
    my $cwd = -d $self->{dir} ? $self->{dir} : undef;
    GitLab::_run($cwd, { $self->_env }, 'git', '-c', 'core.autocrlf=false', '-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false', '-c', 'init.defaultBranch=main', @args);
}
sub git {                                     # git(@args) -> output; dies with git's message
    my ($self, @args) = @_;
    my ($out, $rc) = $self->git_rc(@args);
    die "GitFlow: git @args: $out" if $rc;
    $out;
}
sub branch {                                  # the current branch, from .git/HEAD (no process)
    my $self = shift;
    if (open my $fh, '<', "$self->{dir}/.git/HEAD") { my $l = <$fh> // ''; close $fh; return $1 if $l =~ m{^ref: refs/heads/(\S+)} }
    my ($b) = $self->git('rev-parse', '--abbrev-ref', 'HEAD') =~ /(\S+)/; $b;
}
sub _ref {                                    # a ref's sha from the clone's files (loose or packed), else undef
    my ($self, $ref) = @_;
    my $g = "$self->{dir}/.git";
    if (open my $fh, '<', "$g/$ref") { my $l = <$fh> // ''; close $fh; return $1 if $l =~ /^([0-9a-f]{40})/ }
    if (open my $fh, '<', "$g/packed-refs") { while (my $l = <$fh>) { if ($l =~ /^([0-9a-f]{40}) (\S+)$/ && $2 eq $ref) { close $fh; return $1 } } close $fh }
    undef;
}
sub _remote_has { my ($self, $b) = @_; defined $self->_ref("refs/remotes/origin/$b") }
sub _gl { my $self = shift; $self->{gl} // die "GitFlow: this step needs a GitLab connection (gl => GitLab->new(...))\n" }
sub _pushed { my ($self, $ref) = @_; $self->{gl}->pushed($self->{project}, $ref) if $self->{gl} }

sub clone {                                   # clone([url]) -- default: the project's repository URL from GitLab
    my ($self, $url) = @_;
    $url //= $self->_gl->project($self->{project})->{http_url_to_repo};
    die "GitFlow: $self->{dir} already exists\n" if -e $self->{dir};
    make_path(dirname($self->{dir}));
    my ($out, $rc) = GitLab::_run(undef, { $self->_env }, 'git', '-c', 'core.autocrlf=false', 'clone', '-q', $url, $self->{dir});
    die "GitFlow: git clone $url: $out" if $rc;
    $self->git('config', 'user.name', $self->{name});
    $self->git('config', 'user.email', $self->{email});
    $self->git('config', 'core.autocrlf', 'false');
    $self->git('config', 'pull.ff', 'only');
    $self;
}
sub init {                                    # develop from main (an empty repository gets a first commit on main)
    my $self = shift;
    my ($m, $d) = @{ $self->{branches} }{qw(main develop)};
    $self->git('fetch', '-q', 'origin');
    if (!$self->_remote_has($m)) {
        my (undef, $rc) = $self->git_rc('rev-parse', '--verify', '-q', 'HEAD');
        if ($rc) {
            $self->git('checkout', '-q', '-B', $m);
            $self->git('commit', '-q', '--allow-empty', '-m', 'Initial commit');
        }
        $self->git('push', '-q', '-u', 'origin', "HEAD:refs/heads/$m");
        $self->_pushed("refs/heads/$m");
    }
    $self->git('fetch', '-q', 'origin');
    if (!$self->_remote_has($d)) {             # through the API when there is one: develop is usually protected already
        if ($self->{gl}) { $self->{gl}->create_branch($self->{project}, $d, $m); $self->git('fetch', '-q', 'origin') }
        else { $self->git('push', '-q', 'origin', "refs/remotes/origin/$m:refs/heads/$d"); $self->git('fetch', '-q', 'origin') }
    }
    $self->git('checkout', '-q', '-B', $d, "origin/$d");
    $self->git('branch', '-q', '--set-upstream-to', "origin/$d", $d);
    $self;
}
sub start {                                   # start(feature|release|hotfix => NAME) -> branch name
    my ($self, $kind, $name) = @_;
    $kind =~ /^(feature|release|hotfix)$/ or die "GitFlow: start feature, release or hotfix, not '$kind'\n";
    defined $name && $name =~ /^[\w.\/-]+$/ or die "GitFlow: a branch name is letters, digits and . _ - / ('" . ($name // '') . "')\n";
    my $base = $kind eq 'hotfix' ? $self->{branches}{main} : $self->{branches}{develop};
    my $b = $self->{branches}{$kind} . $name;
    $self->git('fetch', '-q', 'origin');
    $self->_remote_has($base) or die "GitFlow: origin has no '$base' branch (run init first)\n";
    die "GitFlow: branch '$b' already exists on origin\n" if $self->_remote_has($b);
    $self->git('checkout', '-q', '-B', $b, "origin/$base");
    $b;
}
sub commit {                                  # commit(MESSAGE[, paths]) -> sha, or undef when there is nothing to commit
    my ($self, $msg, @paths) = @_;
    $self->git('add', '-A', (@paths ? ('--', @paths) : ()));
    my ($st) = $self->git('status', '--porcelain');
    my (undef, $merging) = $self->git_rc('rev-parse', '--verify', '-q', 'MERGE_HEAD');
    return undef unless length($st) || !$merging;
    $self->git('commit', '-q', '-m', $msg);
    my ($sha) = $self->git('rev-parse', 'HEAD') =~ /([0-9a-f]{40})/;
    $sha;
}
sub publish {                                 # push the current branch (and tell GitLab, which runs its pipelines)
    my $self = shift;
    my $b = $self->branch;
    $self->git('push', '-q', '-u', 'origin', "$b:refs/heads/$b");
    $self->_pushed("refs/heads/$b");
    $b;
}
sub kind {                                    # (kind, name) of the current branch
    my ($self, $b) = @_;
    $b //= $self->branch;
    for my $k (qw(feature release hotfix)) { my $p = $self->{branches}{$k}; return ($k, substr($b, length $p)) if index($b, $p) == 0 }
    return ('vendor', $b) if $b eq $self->{branches}{vendor};
    return ('other', $b);
}
sub finish {                                  # push and open the merge request(s) for the current branch
    my ($self, %o) = @_;
    my $b = $self->branch;
    my ($kind, $name) = $self->kind($b);
    $kind =~ /^(feature|release|hotfix)$/ or die "GitFlow: '$b' is not a feature, release or hotfix branch\n";
    $self->publish;
    my $target = $kind eq 'feature' ? $self->{branches}{develop} : $self->{branches}{main};
    my $title = $o{title} // ucfirst($kind) . ": $name";
    my $mr = $self->_gl->create_mr($self->{project}, source_branch => $b, target_branch => $target, title => $title, description => $o{description} // '',
        labels => $o{labels}, milestone => $o{milestone}, reviewers => $o{reviewers}, assignee => $o{assignee} // $self->{user},
        remove_source_branch => ($kind eq 'feature' || $kind eq 'hotfix') ? 1 : 0);
    $mr;
}
sub docs_hash {                               # sha256 over `git ls-tree -r <ref> -- docs`: what the baseline pipeline re-checks
    my ($self, $ref) = @_;
    my $t = $self->git('ls-tree', '-r', $ref, '--', 'docs');
    Digest::SHA::sha256_hex($t);
}
sub after_release {                           # after a release/hotfix MR merged into main: tag, release, back-merge MR
    my ($self, $mr, %o) = @_;
    my $gl = $self->_gl;
    my $m = ref $mr ? $gl->mr($self->{project}, $mr->{iid}) : $gl->mr($self->{project}, $mr);
    $m->{state} eq 'merged' or die "GitFlow: merge request !$m->{iid} is not merged yet\n";
    my ($kind, $name) = $self->kind($m->{source_branch});
    $m->{target_branch} eq $self->{branches}{main} or die "GitFlow: !$m->{iid} did not go into $self->{branches}{main}\n";
    my $tag = $o{tag} // (index($name, $self->{tag_prefix}) == 0 ? $name : $self->{tag_prefix} . $name);
    $self->git('fetch', '-q', 'origin');
    my $sha = $m->{merge_commit_sha};
    my $hash = $self->docs_hash($sha);
    my $msg = "$tag\n\nsha256=$hash (docs/ at " . substr($sha, 0, 8) . ")\n" . ($o{message} // '');
    my $t = $gl->create_tag($self->{project}, $tag, $sha, $msg);
    my ($rel) = grep { $_->{tag_name} eq $tag } @{ $gl->releases($self->{project}) };   # the tag pipeline's release: job may have made it
    $rel //= $gl->create_release($self->{project}, tag_name => $tag, name => $o{name} // $tag, description => $o{notes} // "Baseline $tag.\n", milestones => $o{milestones});
    my $back = $gl->create_mr($self->{project}, source_branch => $self->{branches}{main}, target_branch => $self->{branches}{develop},
        title => $o{back_title} // "Back-merge $tag into $self->{branches}{develop}", description => $o{back_description} // "Brings the $tag release commits back into $self->{branches}{develop}.",
        remove_source_branch => 0, labels => $o{back_labels});
    return { tag => $t, release => $rel, mr => $back, sha256 => $hash };
}
sub sync {                                    # fetch; fast-forward the local main and develop
    my $self = shift;
    $self->git('fetch', '-q', '--prune', 'origin');
    my $cur = $self->branch;
    for my $b (@{ $self->{branches} }{qw(main develop)}) {
        next unless $self->_remote_has($b);
        if ($cur eq $b) { $self->git('merge', '-q', '--ff-only', "origin/$b") }
        else { $self->git('branch', '-q', '-f', $b, "origin/$b") }
    }
    $self;
}
sub checkout { my ($self, $b) = @_; $self->git('fetch', '-q', 'origin'); $self->git('checkout', '-q', '-B', $b, "origin/$b"); $b }

sub _sha256_file { my $f = shift; my $d = Digest::SHA->new(256); $d->addfile($f, 'b'); $d->hexdigest }
sub _copy_tree {
    my ($from, $to) = @_;
    make_path($to);
    opendir my $dh, $from or die "GitFlow: cannot read $from: $!\n";
    for my $e (sort grep { !/^\.\.?$/ } readdir $dh) {
        if (-d "$from/$e") { _copy_tree("$from/$e", "$to/$e") }
        else { copy("$from/$e", "$to/$e") or die "GitFlow: copy $from/$e: $!\n" }
    }
    closedir $dh;
}
sub _slurp_head { my $f = shift; open my $fh, '<:raw', $f or return ''; my $l = <$fh> // ''; close $fh; $l }   # a file's first line
sub vendor_import {                           # a prime drop onto vendor/prime, then merged into a new feature branch
    my ($self, %o) = @_;
    my ($drop, $ver, $convert) = @o{qw(drop version convert)};
    defined $drop && -d $drop or die "GitFlow: vendor import needs drop => DIR (got " . ($drop // 'nothing') . ")\n";
    defined $ver && $ver =~ /^[\w.-]+$/ or die "GitFlow: vendor import needs version => NAME (letters, digits, . _ -)\n";
    ref $convert eq 'CODE' or die "GitFlow: vendor import needs convert => sub { my (\$drop, \$model_dir) = \@_; ... }\n";
    my $v = $self->{branches}{vendor};
    my ($main, $dev) = @{ $self->{branches} }{qw(main develop)};
    $self->git('fetch', '-q', 'origin');
    if ($self->_remote_has($v)) { $self->git('checkout', '-q', '-B', $v, "origin/$v") }
    else {
        my ($root) = $self->git('rev-list', '--max-parents=0', "origin/$main") =~ /([0-9a-f]{40})/ or die "GitFlow: origin/$main has no root commit\n";
        $self->git('checkout', '-q', '-B', $v, $root);
    }
    # the government's own files under model/ (a scaffold's model/library/conventions/, say) are not the prime's: the
    # converter never writes them, so they are kept as they are -- otherwise the first drop would delete them on
    # vendor/prime and the merge would carry the deletion into develop
    my @gov = grep { length && (_slurp_head("$self->{dir}/$_") !~ m{generated by (?:xmi|reqif)2sysml\.pl}) }
              split /\n/, $self->git('ls-files', '--', 'model');
    $self->git('rm', '-r', '-q', '--ignore-unmatch', '--', 'model', "imports/$ver");
    remove_tree("$self->{dir}/model", "$self->{dir}/imports/$ver");
    _copy_tree($drop, "$self->{dir}/imports/$ver");
    make_path("$self->{dir}/model");
    $convert->(abs_path($drop), "$self->{dir}/model");
    $self->git('checkout', 'HEAD', '--', $_) for grep { !-e "$self->{dir}/$_" } @gov;
    my $man = -f "$drop/MANIFEST.txt" ? ' (MANIFEST sha256 ' . substr(_sha256_file("$drop/MANIFEST.txt"), 0, 16) . ')' : '';
    my $sha = $self->commit($o{message} // "Import prime drop $ver$man");
    defined $sha or die "GitFlow: drop $ver changes nothing on $v\n";
    $self->git('push', '-q', '-u', 'origin', "$v:refs/heads/$v");
    $self->_pushed("refs/heads/$v");
    my $b = $self->start(feature => $o{branch} // "drop-$ver");
    my ($out, $rc) = $self->git_rc('merge', '--no-ff', '-m', $o{merge_message} // "Merge prime drop $ver into $dev", $v);
    my @conf = $rc ? grep { length } split /\n/, $self->git('diff', '--name-only', '--diff-filter=U') : ();
    die "GitFlow: merging $v into $b failed: $out" if $rc && !@conf;
    my $allow = @conf ? undef : $self->record_outline_allowance($ver);   # after a conflict: call it once the merge is resolved and committed
    return { branch => $b, conflicts => \@conf, merged => $rc ? 0 : 1, sha => $sha, outline => $allow };
}
sub outline_count {                           # the outline violations plus @L tag mismatches, as tools/sysml/model.pl check counts them
    my ($self) = @_;
    my $kit = $self->{kit} // do { my $me = $INC{'GitFlow.pm'} // 'lib/GitFlow.pm'; abs_path(dirname(abs_path($me)) . '/..') };
    my ($out) = GitLab::_run(undef, {}, $^X, "$kit/tools/sysml/model.pl", '--root', $self->{dir}, 'check');
    my ($v) = $out =~ /^violations\s+(\d+)/m;
    my ($m) = $out =~ /^\@L tag mismatches\s+(\d+)/m;
    defined $v or die "GitFlow: tools/sysml/model.pl check gave no violation count: $out";
    $v + ($m // 0);
}
sub record_outline_allowance {                # raise .ci/outline-max to what a prime drop brings, in its own commit on the drop branch
    my ($self, $ver) = @_;
    my $f = "$self->{dir}/.ci/outline-max";
    return undef unless -f $f;                # a repository without the outline ratchet
    open my $fh, '<', $f or die "GitFlow: cannot read $f: $!\n";
    my ($old) = (<$fh> // '') =~ /(\d+)/; close $fh;
    $old //= 0;
    my $n = $self->outline_count;
    return { old => $old, new => $old, count => $n, raised => 0 } if $n <= $old;   # only raising: lowering is the team's own MR
    open $fh, '>', $f or die "GitFlow: cannot write $f: $!\n"; print $fh "$n\n"; close $fh;
    $self->commit("Record the outline allowance after drop $ver\n\nThe prime's drop $ver brings $n outline violations (2..9 rule and level tags; was $old).\n"
                . "Reviewed with the drop's merge request; Discrepancy Reports ask the prime to fix them.", '.ci/outline-max');
    return { old => $old, new => $n, count => $n, raised => 1 };
}
sub conflict_files { my $self = shift; [ grep { length } split /\n/, $self->git('diff', '--name-only', '--diff-filter=U') ] }
sub take {                                    # take(ours|theirs, paths): resolve conflicted files wholesale
    my ($self, $side, @paths) = @_;
    $side =~ /^(ours|theirs)$/ or die "GitFlow: take ours or theirs, not '$side'\n";
    for my $p (@paths) {
        my (undef, $rc) = $self->git_rc('checkout', "--$side", '--', $p);
        if ($rc) { $self->git('rm', '-q', '--', $p) } else { $self->git('add', '--', $p) }
    }
}

sub default_convert {                         # the kit's converters: XMI -> model/, ReqIF -> model/doors/ (or both by a layout map)
    my ($kit, %o) = @_;
    my @map = defined $o{layout_map} ? ('--layout-map', $o{layout_map}) : ();   # every package at the path the map gives it
    return sub {
        my ($drop, $out) = @_;
        opendir my $dh, $drop or die "GitFlow: cannot read $drop: $!\n";
        my @f = sort readdir $dh; closedir $dh;
        my ($xmi) = grep { /\.xmi$/i } @f;
        my ($req) = grep { /\.reqifz?$/i } @f;
        defined $xmi or die "GitFlow: no .xmi file in $drop\n";
        my ($o1, $rc1) = GitLab::_run(undef, {}, $^X, "$kit/bin/xmi2sysml.pl", @map, '--out', $out, "$drop/$xmi");
        die "GitFlow: xmi2sysml.pl failed on $drop/$xmi: $o1" if $rc1;
        if (defined $req) {
            my ($o2, $rc2) = GitLab::_run(undef, {}, $^X, "$kit/bin/reqif2sysml.pl", @map, '--out', (@map ? $out : "$out/doors"), "$drop/$req");
            die "GitFlow: reqif2sysml.pl failed on $drop/$req: $o2" if $rc2;
        }
    };
}

require GitLab;
1;
