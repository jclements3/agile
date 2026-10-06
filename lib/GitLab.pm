package GitLab;
# A small GitLab client with two backends behind one interface:
#
#   my $gl = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GITLAB_TOKEN');   # REST API v4 through curl
#   my $gl = GitLab->new(local => $dir);       # an offline emulator: state in $dir/gitlab.json, bare repos in $dir/repos/
#
# The emulator stands in for a GitLab instance when there is none (training, the Tidewater simulation, tests): it keeps
# projects, members, labels, milestones, protected branches and tags, approval rules, issues with quick actions, merge
# requests, pipelines (run for real by lib/GitLabCI.pm on the merged result), tags, releases and wiki pages, and its bare
# repositories carry a pre-receive hook that enforces branch and tag protection the way GitLab does. Merges are real
# `git merge --no-ff` commits with GitLab's message. Time is a settable clock ($gl->clock(ISO)), so a simulation can
# replay months of work. The REST backend sends the same calls to a real GitLab (PRIVATE-TOKEN from token_env; dry_run
# prints each request instead). Both return GitLab-shaped hashes (iid, title, labels, milestone {title}, author
# {username}, created_at ...), so export() and the callers do not care which backend they talk to.
#
# Methods take the project path ('tidewater/model') first. See the Tidewater design notes in docs/GITLAB.html.
use strict;
use warnings;
use JSON::PP ();
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempfile tempdir);
use Cwd qw(abs_path);
use POSIX ();
use Time::Local qw(timegm);
use Digest::MD5 qw(md5_hex);
use File::Glob ();

my $JSON = JSON::PP->new->canonical(1)->utf8(1);
my %LEVEL = (none => 0, 'no one' => 0, noone => 0, guest => 10, reporter => 20, developer => 30, maintainer => 40, owner => 50, admin => 60);
my $ZERO = '0' x 40;

# ---------------------------------------------------------------- construction, identity, time
sub new {
    my ($class, %o) = @_;
    my $self = bless { as => $o{user} // 'root', cache_on => $o{cache} // 1, base => $o{url_base} // 'https://gitlab.local',
                       dry_run => $o{dry_run} ? 1 : 0, sudo => $o{sudo} ? 1 : 0, out => $o{out} // \*STDOUT,
                       freeze => $o{freeze} ? 1 : 0, job_seconds => $o{job_seconds}, runner_shell => $o{runner_shell} // 'sh', parallel => $o{parallel} // $ENV{GITLAB_CI_PARALLEL} // 1 }, $class;   # freeze: the clock moves only by clock()/tick() (replays)
    if (defined $o{local}) {
        make_path($o{local});
        -d $o{local} or die "GitLab: cannot create $o{local}\n";
        $self->{local} = abs_path($o{local});
        my $f = "$self->{local}/gitlab.json";
        if (-f $f) { open my $fh, '<:raw', $f or die "GitLab: cannot read $f: $!\n"; local $/; $self->{st} = $JSON->decode(<$fh>); close $fh }
        else { $self->{st} = { next_id => 0, users => {}, groups => {}, projects => {}, ci_cache => {} } }
        $self->{st}{users}{root} //= { id => 1, username => 'root', name => 'Administrator', email => 'admin@example.invalid', admin => 1 };
        $self->clock($o{now}) if defined $o{now};
        $self->{t} //= defined $self->{st}{clock} ? _epoch($self->{st}{clock}) : time;
        $self->{wall0} = time;
    } else {
        defined $o{url} or die "GitLab: give url => URL (a GitLab server) or local => DIR (the emulator)\n";
        ($self->{url} = $o{url}) =~ s{/+$}{};
        $self->{token_env} = $o{token_env} // 'GITLAB_TOKEN';
        $self->{curl} = ref $o{curl} ? $o{curl} : [ $o{curl} // 'curl' ];
        $self->{t} = time;
        $self->clock($o{now}) if defined $o{now};
    }
    $self;
}
sub is_local { $_[0]{local} ? 1 : 0 }
sub as { my ($self, $u) = @_; if (defined $u) { $self->{as} = $u; $self->_user($u) if $self->{local}; return $self } $self->{as} }
sub clock {                                   # clock(ISO or epoch): set the emulator's time; returns $self
    my ($self, $t) = @_;
    $self->{t} = $t =~ /^\d+$/ ? $t : _epoch($t);
    $self->{wall0} = time;
    $self->{st}{clock} = _iso($self->{t}) if $self->{local};
    $self;
}
sub now { _iso($_[0]->epoch) }                # the time, ISO 8601 UTC
sub epoch { my $self = shift; $self->{freeze} ? $self->{t} : $self->{t} + (time - ($self->{wall0} // time)) }
sub tick { my ($self, $s) = @_; $self->{t} += $s; $self }    # advance the clock by $s seconds
sub save {
    my $self = shift;
    return unless $self->{local} && !$self->{dry_run};   # a dry run changes nothing, the clock included
    $self->{st}{clock} = $self->now;
    my $f = "$self->{local}/gitlab.json";
    open my $fh, '>:raw', "$f.tmp" or die "GitLab: cannot write $f: $!\n";
    print $fh JSON::PP->new->canonical(1)->utf8(1)->pretty->encode($self->{st});
    close $fh or die "GitLab: cannot write $f: $!\n";
    rename "$f.tmp", $f or die "GitLab: cannot write $f: $!\n";
}

sub _epoch {
    my $s = shift;
    my ($y, $mo, $d, $h, $mi, $se) = $s =~ /^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?/ or die "GitLab: bad time '$s' (want YYYY-MM-DD[THH:MM[:SS]])\n";
    timegm($se // 0, $mi // 0, $h // 0, $d, $mo - 1, $y);
}
sub _iso { POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(int $_[0])) }
sub _date { substr(_iso($_[0]), 0, 10) }
sub _slug { my $s = lc shift; $s =~ s/[^a-z0-9]+/-/g; $s =~ s/^-+|-+$//g; substr($s, 0, 63) }
sub _arr { my $v = shift; return [] unless defined $v; ref $v eq 'ARRAY' ? $v : [ grep { length } map { s/^\s+|\s+$//gr } split /,/, $v ] }
sub level_of { my $n = lc(shift // ''); return $n if $n =~ /^\d+$/; exists $LEVEL{$n} ? $LEVEL{$n} : die "GitLab: unknown access level '$n' (none, developer, maintainer, owner)\n" }

# ---------------------------------------------------------------- process helper: (output with stderr, exit code)
sub _run {
    my ($cwd, $env, @cmd) = @_;
    local @ENV{ keys %$env } = values %$env;
    my $pid = open(my $fh, '-|') // die "GitLab: fork: $!\n";
    if (!$pid) {
        if (defined $cwd && !chdir $cwd) { print "chdir $cwd: $!\n"; POSIX::_exit(127) }
        open STDERR, '>&', \*STDOUT;
        exec { $cmd[0] } @cmd or do { print "exec $cmd[0]: $!\n"; POSIX::_exit(127) };
    }
    binmode $fh;
    local $/;
    my $out = <$fh> // '';
    close $fh;
    return ($out, $? >> 8);
}
sub _git_env {
    my ($self, $user) = @_;
    my $u = $self->{local} ? $self->_user($user // $self->{as}) : { name => $user, email => "$user\@example.invalid" };
    my $d = $self->now;
    return (GIT_AUTHOR_NAME => $u->{name}, GIT_AUTHOR_EMAIL => $u->{email}, GIT_COMMITTER_NAME => $u->{name}, GIT_COMMITTER_EMAIL => $u->{email},
            GIT_AUTHOR_DATE => $d, GIT_COMMITTER_DATE => $d, GIT_TERMINAL_PROMPT => 0);
}
sub _git {                                    # _git($dir, \%env, @args) -> output; dies on failure
    my ($self, $dir, $env, @args) = @_;
    my ($out, $rc) = _run($dir, { %{ $env // {} } }, 'git', '-c', 'core.autocrlf=false', '-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false',
                          '-c', 'init.defaultBranch=main', @args);
    die "GitLab: git @args: $out" if $rc;
    $out;
}
sub _git_rc { my ($self, $dir, $env, @args) = @_; _run($dir, { %{ $env // {} } }, 'git', '-c', 'core.autocrlf=false', '-c', 'commit.gpgsign=false', @args) }

# ================================================================ REST backend
sub _enc { my $s = shift; $s =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord $1)/ge; $s }
sub _q { my %q = @_; my @k = sort grep { defined $q{$_} } keys %q; @k ? '?' . join('&', map { _enc($_) . '=' . _enc($q{$_}) } @k) : '' }
sub _api {                                    # _api(METHOD, PATH, BODY|undef, query => {}, all => 1) -> decoded JSON
    my ($self, $method, $path, $body, %o) = @_;
    my %q = %{ $o{query} // {} };
    if ($o{all}) {
        my (@all, $page);
        $q{per_page} //= 100;
        $page = 1;
        while (defined $page && length $page) {
            my ($data, $hdr) = $self->_api1($method, $path, undef, { %q, page => $page });
            push @all, @{ ref $data eq 'ARRAY' ? $data : [] };
            $page = $hdr->{'x-next-page'};
        }
        return \@all;
    }
    return ($self->_api1($method, $path, $body, \%q))[0];
}
sub _api1 {
    my ($self, $method, $path, $body, $q) = @_;
    my $rel = "/api/v4$path" . _q(%$q);
    if ($self->{dry_run}) {
        my $fh = $self->{out};
        print $fh "$method $rel" . (defined $body ? ' ' . $JSON->encode($body) : '') . "\n";
        return ($method eq 'GET' ? ($q->{page} ? [] : {}) : { %{ $body // {} }, id => 0, iid => 0 }, {});
    }
    my $tok = $ENV{ $self->{token_env} };
    defined $tok && length $tok or die "GitLab: set $self->{token_env} to a personal or project access token (scope api)\n";
    my @cmd = (@{ $self->{curl} }, '-sS', '-D', '-', '-X', $method, '-H', "PRIVATE-TOKEN: $tok", '-H', 'Accept: application/json');
    push @cmd, '-H', "Sudo: $self->{as}" if $self->{sudo} && $self->{as} && $self->{as} ne 'root';
    my $tmp;
    if (defined $body) {
        my $fh;
        ($fh, $tmp) = tempfile('gitlab-XXXXXX', TMPDIR => 1, UNLINK => 1);
        binmode $fh; print $fh $JSON->encode($body); close $fh;
        push @cmd, '-H', 'Content-Type: application/json', '--data-binary', "\@$tmp";
    }
    push @cmd, "$self->{url}$rel";
    my ($out, $rc) = _run(undef, {}, @cmd);
    unlink $tmp if $tmp;
    die "GitLab: curl exit $rc: $out\n" if $rc;
    my ($status, %hdr);
    while ($out =~ s/\AHTTP\/[\d.]+\s+(\d{3})[^\n]*\n((?:[^\r\n]+\r?\n)*)\r?\n//) {
        ($status, my $h) = ($1, $2);
        %hdr = map { /^([^:]+):\s*(.*?)\r?$/ ? (lc $1, $2) : () } split /\n/, $h;
        last unless $status == 100;
    }
    defined $status or die "GitLab: $method $rel: no HTTP status in curl's output\n";
    my $data = length($out) && $out =~ /^\s*[\[{]/ ? eval { $JSON->decode($out) } : $out;
    if ($status >= 400) {
        my $msg = ref $data eq 'HASH' ? ($data->{message} // $data->{error} // '') : $out;
        $msg = $JSON->encode($msg) if ref $msg;
        die "GitLab: $method $path: $status $msg\n";
    }
    return ($data, \%hdr);
}
sub _pid { _enc($_[1]) }                      # project path -> the :id part of the URL
sub _uid {                                    # username -> user id (REST), cached
    my ($self, $u) = @_;
    return "{id of $u}" if $self->{dry_run};
    return $self->{uids}{$u} //= do { my $r = $self->_api('GET', '/users', undef, query => { username => $u }); ref $r eq 'ARRAY' && @$r ? $r->[0]{id} : die "GitLab: no user '$u'\n" };
}
sub _mid {                                    # milestone title -> id (REST)
    my ($self, $p, $title) = @_;
    return "{id of milestone $title}" if $self->{dry_run};
    my $r = $self->_api('GET', '/projects/' . $self->_pid($p) . '/milestones', undef, query => { title => $title });
    ref $r eq 'ARRAY' && @$r ? $r->[0]{id} : die "GitLab: no milestone '$title' in $p\n";
}

# ================================================================ public API (dispatch per backend)
sub create_user {
    my ($self, $u, %o) = @_;
    return $self->_user($u, %o) if $self->{local};
    $self->_api('POST', '/users', { username => $u, name => $o{name} // $u, email => $o{email} // "$u\@example.invalid",
                                    ($o{password} ? (password => $o{password}) : (reset_password => JSON::PP::true)), skip_confirmation => JSON::PP::true });
}
sub create_group {
    my ($self, $path, %o) = @_;
    if ($self->{local}) {
        return $self->{st}{groups}{$path} //= { id => $self->_id, full_path => $path, name => $o{name} // $path, members => {}, created_at => $self->now };
    }
    my ($parent, $name) = $path =~ m{^(?:(.*)/)?([^/]+)$};
    $self->_api('POST', '/groups', { name => $o{name} // $name, path => $name, ($parent ? (parent_id => $self->_api('GET', '/groups/' . _enc($parent))->{id}) : ()),
                                     visibility => $o{visibility} // 'private' });
}
sub project {
    my ($self, $p) = @_;
    return $self->_summary($self->_p($p)) if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p));
}
sub create_project {
    my ($self, $path, %o) = @_;
    return $self->_create_project($path, %o) if $self->{local};
    my ($ns, $name) = $path =~ m{^(.*)/([^/]+)$} or die "GitLab: project path '$path' needs a group: group/name\n";
    my $nsid = $self->{dry_run} ? "{id of $ns}" : $self->_api('GET', '/namespaces/' . _enc($ns))->{id};
    $self->_api('POST', '/projects', { name => $o{name} // $name, path => $name, namespace_id => $nsid, visibility => $o{visibility} // 'private',
                                       initialize_with_readme => JSON::PP::false, (map { ($_ => $o{$_}) } grep { $_ ne 'name' && $_ ne 'visibility' } keys %o) });
}
sub update_project {
    my ($self, $p, %s) = @_;
    return $self->_update_project($p, %s) if $self->{local};
    $self->_api('PUT', '/projects/' . $self->_pid($p), { map { ($_ => _jbool($s{$_})) } keys %s });
}
sub _jbool { my $v = shift; return $v unless defined $v && !ref $v; $v =~ /^(true|yes|on)$/i ? JSON::PP::true : $v =~ /^(false|no|off)$/i ? JSON::PP::false : $v }
sub add_member {
    my ($self, $p, $u, $lvl, %o) = @_;
    my $l = level_of($lvl);
    if ($self->{local}) {
        $self->_user($u);
        my $g = $self->{st}{groups}{$p};
        my $h = $g ? $g->{members} : $self->_p($p)->{members};
        $h->{$u} = $l;
        $self->_write_protect($_) for $g ? grep { $_->{namespace} eq $p } values %{ $self->{st}{projects} } : ($self->_p($p));
        return { username => $u, access_level => $l };
    }
    my $kind = $o{group} ? 'groups' : 'projects';
    $self->_api('POST', "/$kind/" . $self->_pid($p) . '/members', { user_id => $self->_uid($u), access_level => $l });
}
sub set_variable {
    my ($self, $p, $k, $v, %o) = @_;
    if ($self->{local}) { my $P = $self->_p($p); $P->{variables}{$k} = { key => $k, value => $v, protected => $o{protected} ? 1 : 0, masked => $o{masked} ? 1 : 0 }; return $P->{variables}{$k} }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/variables', { key => $k, value => $v, protected => _jbool($o{protected} ? 'true' : 'false'), masked => _jbool($o{masked} ? 'true' : 'false') });
}
sub create_label {
    my ($self, $p, $name, $color, $desc) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($l) = grep { $_->{name} eq $name } @{ $P->{labels} };
        if ($l) { $l->{color} = $color // $l->{color}; $l->{description} = $desc // $l->{description}; return $l }
        push @{ $P->{labels} }, $l = { id => $self->_id, name => $name, color => $color // '#6699cc', description => $desc // '' };
        return $l;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/labels', { name => $name, color => $color // '#6699cc', description => $desc // '' });
}
sub labels { my ($self, $p) = @_; $self->{local} ? [ @{ $self->_p($p)->{labels} } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/labels', undef, all => 1) }
sub create_milestone {
    my ($self, $p, $title, %o) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($m) = grep { $_->{title} eq $title } @{ $P->{milestones} };
        die "GitLab: milestone '$title' already exists in $p\n" if $m;
        push @{ $P->{milestones} }, $m = { id => $self->_id, iid => ++$P->{iids}{milestone}, title => $title, description => $o{description} // '',
                                           start_date => $o{start_date}, due_date => $o{due_date}, state => 'active', created_at => $self->now };
        return $m;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/milestones', { title => $title, map { defined $o{$_} ? ($_ => $o{$_}) : () } qw(description start_date due_date) });
}
sub milestones { my ($self, $p) = @_; $self->{local} ? [ @{ $self->_p($p)->{milestones} } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/milestones', undef, all => 1) }
sub update_milestone {
    my ($self, $p, $title, %o) = @_;
    if ($self->{local}) {
        my ($m) = grep { $_->{title} eq $title } @{ $self->_p($p)->{milestones} } or die "GitLab: no milestone '$title' in $p\n";
        if (my $e = delete $o{state_event}) { $m->{state} = $e eq 'close' ? 'closed' : 'active' }
        $m->{$_} = $o{$_} for keys %o;
        return $m;
    }
    $self->_api('PUT', '/projects/' . $self->_pid($p) . '/milestones/' . $self->_mid($p, $title), \%o);
}
sub protect_branch {
    my ($self, $p, $name, %o) = @_;
    my %r = (name => $name, push_access_level => level_of($o{push_access_level} // 'maintainer'), merge_access_level => level_of($o{merge_access_level} // 'maintainer'),
             allow_force_push => $o{allow_force_push} ? 1 : 0, code_owner_approval_required => $o{code_owner_approval_required} ? 1 : 0);
    if ($self->{local}) {
        my $P = $self->_p($p);
        @{ $P->{protected_branches} } = ((grep { $_->{name} ne $name } @{ $P->{protected_branches} }), \%r);
        $self->_write_protect($P);
        return \%r;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/protected_branches', { %r, allow_force_push => _jbool($r{allow_force_push} ? 'true' : 'false'),
        code_owner_approval_required => _jbool($r{code_owner_approval_required} ? 'true' : 'false') });
}
sub protect_tag {
    my ($self, $p, $name, %o) = @_;
    my %r = (name => $name, create_access_level => level_of($o{create_access_level} // 'maintainer'));
    if ($self->{local}) {
        my $P = $self->_p($p);
        @{ $P->{protected_tags} } = ((grep { $_->{name} ne $name } @{ $P->{protected_tags} }), \%r);
        $self->_write_protect($P);
        return \%r;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/protected_tags', \%r);
}
sub create_approval_rule {
    my ($self, $p, $name, $n, %o) = @_;
    my $users = _arr($o{users});
    if ($self->{local}) {
        my $P = $self->_p($p);
        @{ $P->{approval_rules} } = ((grep { $_->{name} ne $name } @{ $P->{approval_rules} }), my $r = { name => $name, approvals_required => 0 + $n, users => $users });
        return $r;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/approval_rules', { name => $name, approvals_required => 0 + $n, user_ids => [ map { $self->_uid($_) } @$users ] });
}

# ---------------------------------------------------------------- issues
sub create_issue {
    my ($self, $p, %o) = @_;
    defined $o{title} && length $o{title} or die "GitLab: an issue needs a title\n";
    return $self->_create_issue($p, %o) if $self->{local};
    my %b = (title => $o{title});
    $b{description} = $o{description} if defined $o{description};
    $b{labels} = join(',', @{ _arr($o{labels}) }) if $o{labels};
    $b{milestone_id} = $self->_mid($p, $o{milestone}) if $o{milestone};
    $b{assignee_ids} = [ map { $self->_uid($_) } @{ _arr($o{assignees}) } ] if $o{assignees};
    $b{$_} = $o{$_} for grep { defined $o{$_} } qw(issue_type weight due_date confidential);
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/issues', \%b);
}
sub update_issue {
    my ($self, $p, $iid, %o) = @_;
    return $self->_update_issue($p, $iid, %o) if $self->{local};
    my %b;
    $b{$_} = $o{$_} for grep { defined $o{$_} } qw(state_event description title weight due_date);
    $b{$_} = join(',', @{ _arr($o{$_}) }) for grep { defined $o{$_} } qw(add_labels remove_labels labels);
    $b{milestone_id} = $o{milestone} eq '' ? 0 : $self->_mid($p, $o{milestone}) if defined $o{milestone};
    $b{assignee_ids} = [ map { $self->_uid($_) } @{ _arr($o{assignees}) } ] if $o{assignees};
    $self->_api('PUT', '/projects/' . $self->_pid($p) . "/issues/$iid", \%b);
}
sub issue { my ($self, $p, $iid) = @_; $self->{local} ? $self->_issue($self->_p($p), $iid) : $self->_api('GET', '/projects/' . $self->_pid($p) . "/issues/$iid") }
sub issues {
    my ($self, $p, %f) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my $st = $f{state} // 'all';
        my $labels = _arr($f{labels});
        return [ grep {
            ($st eq 'all' || $_->{state} eq $st)
            && (!@$labels || _has_all($_->{labels}, $labels))
            && (!defined $f{milestone} || ($_->{milestone} && $_->{milestone}{title} eq $f{milestone}))
            && (!defined $f{issue_type} || $_->{issue_type} eq $f{issue_type})
            && (!defined $f{assignee_username} || grep({ $_->{username} eq $f{assignee_username} } @{ $_->{assignees} }))
            && (!defined $f{search} || index(lc $_->{title}, lc $f{search}) >= 0)
        } @{ $P->{issues} } ];
    }
    my %q = (state => $f{state} // 'all');
    $q{labels} = join(',', @{ _arr($f{labels}) }) if $f{labels};
    $q{$_} = $f{$_} for grep { defined $f{$_} } qw(milestone issue_type assignee_username search);
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/issues', undef, query => \%q, all => 1);
}
sub add_note {
    my ($self, $p, $kind, $iid, $body, %o) = @_;
    $kind =~ /^(issue|mr)$/ or die "GitLab: add_note kind is issue or mr, not '$kind'\n";
    return $self->_add_note($p, $kind, $iid, $body, %o) if $self->{local};
    my $what = $kind eq 'mr' ? 'merge_requests' : 'issues';
    my $path = '/projects/' . $self->_pid($p) . "/$what/$iid/" . ($o{resolvable} ? 'discussions' : 'notes');
    $self->_api('POST', $path, { body => $body });
}
sub resolve_discussions {
    my ($self, $p, $iid) = @_;
    if ($self->{local}) { my $m = $self->_mr($self->_p($p), $iid); $_->{resolved} = 1 for grep { $_->{resolvable} } @{ $m->{notes} }; return $m }
    my $base = '/projects/' . $self->_pid($p) . "/merge_requests/$iid/discussions";
    my $ds = $self->_api('GET', $base, undef, all => 1);
    for my $d (@$ds) {
        next unless grep { $_->{resolvable} && !$_->{resolved} } @{ $d->{notes} // [] };
        $self->_api('PUT', "$base/$d->{id}", undef, query => { resolved => 'true' });
    }
    return $ds;
}
sub link_issues {
    my ($self, $p, $iid, $target, $type) = @_;
    $type //= 'relates_to';
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($a, $b) = ($self->_issue($P, $iid), $self->_issue($P, $target));
        my %inv = (relates_to => 'relates_to', blocks => 'is_blocked_by', is_blocked_by => 'blocks');
        $inv{$type} or die "GitLab: link type is relates_to, blocks or is_blocked_by, not '$type'\n";
        push @{ $a->{links} }, { iid => 0 + $target, link_type => $type } unless grep { $_->{iid} == $target } @{ $a->{links} };
        push @{ $b->{links} }, { iid => 0 + $iid, link_type => $inv{$type} } unless grep { $_->{iid} == $iid } @{ $b->{links} };
        return { source_issue => { iid => $iid }, target_issue => { iid => $target }, link_type => $type };
    }
    my $proj = $self->{dry_run} ? "{id of $p}" : $self->_api('GET', '/projects/' . $self->_pid($p))->{id};
    $self->_api('POST', '/projects/' . $self->_pid($p) . "/issues/$iid/links", { target_project_id => $proj, target_issue_iid => $target, link_type => $type });
}

# ---------------------------------------------------------------- merge requests
sub create_mr {
    my ($self, $p, %o) = @_;
    defined $o{$_} or die "GitLab: a merge request needs $_\n" for qw(source_branch target_branch title);
    return $self->_create_mr($p, %o) if $self->{local};
    my %b = map { defined $o{$_} ? ($_ => $o{$_}) : () } qw(source_branch target_branch title description squash);
    $b{remove_source_branch} = _jbool($o{remove_source_branch} ? 'true' : 'false') if defined $o{remove_source_branch};
    $b{labels} = join(',', @{ _arr($o{labels}) }) if $o{labels};
    $b{milestone_id} = $self->_mid($p, $o{milestone}) if $o{milestone};
    $b{assignee_id} = $self->_uid($o{assignee}) if $o{assignee};
    $b{reviewer_ids} = [ map { $self->_uid($_) } @{ _arr($o{reviewers}) } ] if $o{reviewers};
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/merge_requests', \%b);
}
sub mr { my ($self, $p, $iid) = @_; $self->{local} ? $self->_mr($self->_p($p), $iid) : $self->_api('GET', '/projects/' . $self->_pid($p) . "/merge_requests/$iid") }
sub mrs {
    my ($self, $p, %f) = @_;
    if ($self->{local}) {
        my $st = $f{state} // 'all';
        my $labels = _arr($f{labels});
        return [ grep { ($st eq 'all' || $_->{state} eq $st) && (!defined $f{source_branch} || $_->{source_branch} eq $f{source_branch})
                        && (!defined $f{target_branch} || $_->{target_branch} eq $f{target_branch}) && (!@$labels || _has_all($_->{labels}, $labels)) }
                 @{ $self->_p($p)->{mrs} } ];
    }
    my %q = (state => $f{state} // 'all');
    $q{$_} = $f{$_} for grep { defined $f{$_} } qw(source_branch target_branch);
    $q{labels} = join(',', @{ _arr($f{labels}) }) if $f{labels};
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/merge_requests', undef, query => \%q, all => 1);
}
sub approve_mr {
    my ($self, $p, $iid) = @_;
    return $self->_approve($p, $iid) if $self->{local};
    $self->_api('POST', '/projects/' . $self->_pid($p) . "/merge_requests/$iid/approve", {});
}
sub merge_mr {
    my ($self, $p, $iid, %o) = @_;
    return $self->_merge($p, $iid, %o) if $self->{local};
    my %b;
    $b{merge_when_pipeline_succeeds} = _jbool($o{merge_when_pipeline_succeeds} ? 'true' : 'false') if defined $o{merge_when_pipeline_succeeds};
    $b{should_remove_source_branch} = _jbool($o{remove_source_branch} ? 'true' : 'false') if defined $o{remove_source_branch};
    $b{squash} = _jbool($o{squash} ? 'true' : 'false') if defined $o{squash};
    $b{merge_commit_message} = $o{merge_commit_message} if defined $o{merge_commit_message};
    $self->_api('PUT', '/projects/' . $self->_pid($p) . "/merge_requests/$iid/merge", \%b);
}

# ---------------------------------------------------------------- pipelines, tags, releases, wiki
sub pushed { my ($self, $p, $ref) = @_; return [] unless $self->{local}; $self->_pushed($p, $ref) }
sub run_pipeline {
    my ($self, $p, $ref, %o) = @_;
    return $self->_run_pipeline($p, $ref, %o) if $self->{local};
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/pipeline', { ref => $ref, ($o{variables} ? (variables => [ map { { key => $_, value => $o{variables}{$_} } } sort keys %{ $o{variables} } ]) : ()) });
}
sub pipelines {
    my ($self, $p, %f) = @_;
    if ($self->{local}) {
        return [ grep { (!defined $f{ref} || $_->{ref} eq $f{ref}) && (!defined $f{status} || $_->{status} eq $f{status})
                        && (!defined $f{source} || $_->{source} eq $f{source}) && (!defined $f{mr_iid} || ($_->{mr_iid} // 0) == $f{mr_iid}) }
                 @{ $self->_p($p)->{pipelines} } ];
    }
    my %q = map { defined $f{$_} ? ($_ => $f{$_}) : () } qw(ref status source updated_after updated_before);
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/pipelines', undef, query => \%q, all => 1);
}
sub pipeline {
    my ($self, $p, $id) = @_;
    if ($self->{local}) { my ($pl) = grep { $_->{id} == $id } @{ $self->_p($p)->{pipelines} }; return $pl // die "GitLab: no pipeline $id in $p\n" }
    $self->_api('GET', '/projects/' . $self->_pid($p) . "/pipelines/$id");
}
sub jobs {
    my ($self, $p, $id) = @_;
    return [ @{ $self->pipeline($p, $id)->{jobs} } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . "/pipelines/$id/jobs", undef, query => { include_retried => 'false' }, all => 1);
}
sub create_branch {                           # create_branch(p, NAME, REF): how protected branches such as develop are made
    my ($self, $p, $name, $ref) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        die "GitLab: branch '$name' already exists in $p (400 Branch already exists)\n" if $self->_sha($P, "refs/heads/$name");
        my $sha = $self->_sha($P, "refs/heads/$ref") // $self->_sha($P, $ref) // die "GitLab: no branch or commit '$ref' in $p (400 Invalid reference name)\n";
        my $r = $self->_protected_branch($P, $name);
        my $lvl = $self->_level($P, $self->{as});
        die "GitLab: you are not allowed to create branch '$name' (403 Forbidden)\n" if $lvl < 30 || ($r && $lvl < ($r->{merge_access_level} || 99) && $lvl < ($r->{push_access_level} || 99));
        $self->_git($self->_bare($P), {}, 'update-ref', "refs/heads/$name", $sha);
        $self->_pushed($p, "refs/heads/$name");
        return { name => $name, commit => { id => $sha }, protected => $r ? 1 : 0 };
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/repository/branches', undef, query => { branch => $name, ref => $ref });
}
sub create_tag {
    my ($self, $p, $name, $ref, $msg) = @_;
    return $self->_create_tag($p, $name, $ref, $msg) if $self->{local};
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/repository/tags', { tag_name => $name, ref => $ref, (defined $msg ? (message => $msg) : ()) });
}
sub create_release {
    my ($self, $p, %o) = @_;
    defined $o{tag_name} or die "GitLab: a release needs tag_name\n";
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($sha, $rc) = $self->_git_rc($self->_bare($P), {}, 'rev-parse', '--verify', '-q', "refs/tags/$o{tag_name}^{commit}");
        die "GitLab: tag '$o{tag_name}' does not exist in $p\n" if $rc;
        chomp $sha;
        die "GitLab: release '$o{tag_name}' already exists in $p\n" if grep { $_->{tag_name} eq $o{tag_name} } @{ $P->{releases} };
        my $ms = _arr($o{milestones});
        $self->_milestone($P, $_) for @$ms;   # a release can only name milestones that exist
        my $links = [ map { +{ id => $self->_id, name => $_->{name}, url => $_->{url}, link_type => $_->{link_type} // 'other' } } @{ $o{assets}{links} // [] } ];
        push @{ $P->{releases} }, my $r = { tag_name => $o{tag_name}, name => $o{name} // $o{tag_name}, description => $o{description} // '',
            milestones => $ms, created_at => $self->now, released_at => $o{released_at} // $self->now,
            author => { username => $self->{as} }, commit => { id => $sha }, assets => { links => $links },
            _links => { self => "$self->{base}/$p/-/releases/$o{tag_name}" } };
        # release evidence, as GitLab collects it when a release is created: the milestones and their issues, and the
        # test report of the tag's pipeline, frozen as a JSON snapshot
        my $pl = $o{evidence_pipeline};
        $r->{evidences} = [ { collected_at => $self->now, sha => substr(md5_hex($o{tag_name} . $self->now), 0, 16), json => {
            release => { tag_name => $r->{tag_name}, name => $r->{name}, released_at => $r->{released_at}, commit => $sha },
            milestones => [ map { my $t = $_; my $m = $self->_milestone($P, $t);
                                  +{ title => $t, state => $m->{state}, due_date => $m->{due_date},
                                     issues => [ map { +{ iid => $_->{iid}, title => $_->{title}, state => $_->{state}, labels => [ @{ $_->{labels} } ] } }
                                                 grep { $_->{milestone} && $_->{milestone}{title} eq $t } @{ $P->{issues} } ] } } @$ms ],
            ($pl ? (report => { pipeline => $pl->{id}, status => $pl->{status}, tests => ($pl->{reports} // {})->{junit} }) : ()) } } ];
        return $r;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/releases', { tag_name => $o{tag_name}, name => $o{name} // $o{tag_name}, description => $o{description} // '',
                                                                       ($o{milestones} ? (milestones => _arr($o{milestones})) : ()) });
}
sub releases { my ($self, $p) = @_; $self->{local} ? [ reverse @{ $self->_p($p)->{releases} } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/releases', undef, all => 1) }
sub wiki_put {
    my ($self, $p, $title, $content) = @_;
    (my $slug = $title) =~ s/\s+/-/g;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($w) = grep { $_->{slug} eq $slug } @{ $P->{wiki} };
        if ($w) { @$w{qw(content updated_at)} = ($content, $self->now); return $w }
        push @{ $P->{wiki} }, $w = { slug => $slug, title => $title, format => 'markdown', content => $content, created_at => $self->now, updated_at => $self->now };
        return $w;
    }
    my $base = '/projects/' . $self->_pid($p) . '/wikis';
    my $have = $self->{dry_run} ? [] : $self->_api('GET', $base, undef, all => 1);
    return grep({ $_->{slug} eq $slug } @$have)
        ? $self->_api('PUT', "$base/" . _enc($slug), { title => $title, content => $content, format => 'markdown' })
        : $self->_api('POST', $base, { title => $title, content => $content, format => 'markdown' });
}
sub wiki { my ($self, $p) = @_; $self->{local} ? [ @{ $self->_p($p)->{wiki} } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/wikis', undef, query => { with_content => 1 }, all => 1) }

sub environments { my ($self, $p) = @_; $self->{local} ? [ @{ $self->_p($p)->{environments} // [] } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/environments', undef, all => 1) }
sub deployments {
    my ($self, $p, %f) = @_;
    if ($self->{local}) { return [ grep { !defined $f{environment} || $_->{environment}{name} eq $f{environment} } @{ $self->_p($p)->{deployments} // [] } ] }
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/deployments', undef, query => { (defined $f{environment} ? (environment => $f{environment}) : ()), order_by => 'id' }, all => 1);
}
sub pages {                                   # where the project's Pages site is (emulator: also the local folder)
    my ($self, $p) = @_;
    return $self->_p($p)->{pages} if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/pages');
}

# ---------------------------------------------------------------- Generic Package Registry
sub _pkgcheck { my ($n, $v, $f) = @_;
    $n =~ /^[\w.-]+$/ or die "GitLab: a package name is letters, digits and . _ - ('$n')\n";
    $v =~ /^[\w.+-]+$/ or die "GitLab: a package version is letters, digits and . _ + - ('$v')\n";
    !defined $f || $f =~ /^[\w.+-]+$/ or die "GitLab: a package file name is letters, digits and . _ + - ('$f')\n" }
sub package_put {                             # package_put(p, NAME, VERSION, FILE, deploy_token => T) -> { name, version, file_name, size, file_sha256 }
    my ($self, $p, $name, $ver, $file, %o) = @_;
    -f $file or die "GitLab: no file $file to upload\n";
    (my $base = $file) =~ s{.*[/\\]}{};
    _pkgcheck($name, $ver, $base);
    require Digest::SHA;
    my $sha = Digest::SHA->new(256)->addfile($file, 'b')->hexdigest;
    my $size = -s $file;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my $dt = $o{deploy_token} ? $self->_deploy_token_ok($P, $o{deploy_token}, 'write_package_registry') : undef;
        die "GitLab: the deploy token cannot publish packages to $p (403 Forbidden)\n" if $o{deploy_token} && !$dt;
        die "GitLab: $self->{as} cannot publish packages to $p (403 Forbidden)\n" if !$dt && $self->_level($P, $self->{as}) < 30;
        my $dir = "$self->{local}/packages/$P->{path_with_namespace}/$name/$ver";
        make_path($dir);
        require File::Copy;
        File::Copy::copy($file, "$dir/$base") or die "GitLab: cannot store $file: $!\n";
        my ($pk) = grep { $_->{name} eq $name && $_->{version} eq $ver } @{ $P->{packages} //= [] };
        push @{ $P->{packages} }, $pk = { id => $self->_id, name => $name, version => $ver, package_type => 'generic', created_at => $self->now, files => [] } unless $pk;
        @{ $pk->{files} } = ((grep { $_->{file_name} ne $base } @{ $pk->{files} }), my $f = { file_name => $base, size => $size, file_sha256 => $sha, created_at => $self->now, uploaded_by => $dt ? $dt->{username} : $self->{as} });
        return { name => $name, version => $ver, %$f };
    }
    my $path = '/projects/' . $self->_pid($p) . "/packages/generic/$name/$ver/$base";
    if ($self->{dry_run}) { my $fh = $self->{out}; print $fh "PUT /api/v4$path <$file ($size bytes, sha256 $sha)>\n"; return { name => $name, version => $ver, file_name => $base, size => $size, file_sha256 => $sha } }
    my $tok = $o{deploy_token} ? '' : $ENV{ $self->{token_env} } // die "GitLab: set $self->{token_env} to a personal or project access token (scope api)\n";
    my $hdr = $o{deploy_token} ? "Deploy-Token: $o{deploy_token}" : "PRIVATE-TOKEN: $tok";
    my ($out, $rc) = _run(undef, {}, @{ $self->{curl} }, '-sS', '-f', '-H', $hdr, '--upload-file', $file, "$self->{url}/api/v4$path");
    die "GitLab: package upload failed: $out\n" if $rc;
    return { name => $name, version => $ver, file_name => $base, size => $size, file_sha256 => $sha };
}
sub package_get {                             # package_get(p, NAME, VERSION, FILE, DEST) -> DEST path
    my ($self, $p, $name, $ver, $fname, $dest) = @_;
    _pkgcheck($name, $ver, $fname);
    $dest //= $fname;
    $dest = "$dest/$fname" if -d $dest;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($pk) = grep { $_->{name} eq $name && $_->{version} eq $ver } @{ $P->{packages} // [] };
        my ($f) = $pk ? grep { $_->{file_name} eq $fname } @{ $pk->{files} } : ();
        $f or die "GitLab: no package file $name/$ver/$fname in $p (404 Not found)\n";
        my $src = "$self->{local}/packages/$P->{path_with_namespace}/$name/$ver/$fname";
        require File::Copy; require Digest::SHA;
        File::Copy::copy($src, $dest) or die "GitLab: cannot write $dest: $!\n";
        Digest::SHA->new(256)->addfile($dest, 'b')->hexdigest eq $f->{file_sha256} or die "GitLab: $dest does not match the registry's sha256\n";
        return $dest;
    }
    my $path = '/projects/' . $self->_pid($p) . "/packages/generic/$name/$ver/$fname";
    if ($self->{dry_run}) { my $fh = $self->{out}; print $fh "GET /api/v4$path > $dest\n"; return $dest }
    my $tok = $ENV{ $self->{token_env} } // die "GitLab: set $self->{token_env} to a personal or project access token (scope api)\n";
    my ($out, $rc) = _run(undef, {}, @{ $self->{curl} }, '-sS', '-f', '-H', "PRIVATE-TOKEN: $tok", '-o', $dest, "$self->{url}/api/v4$path");
    die "GitLab: package download failed: $out\n" if $rc;
    $dest;
}
sub packages {
    my ($self, $p) = @_;
    return [ @{ $self->_p($p)->{packages} // [] } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/packages', undef, query => { package_type => 'generic' }, all => 1);
}

# ---------------------------------------------------------------- pipeline trigger tokens and deploy tokens (deliveries from outside)
sub create_trigger {                          # create_trigger(p, DESCRIPTION) -> { id, token, description, owner }
    my ($self, $p, $desc) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        die "GitLab: $self->{as} cannot create trigger tokens in $p (403 Forbidden)\n" if $self->_level($P, $self->{as}) < 40;
        my $id = $self->_id;
        push @{ $P->{triggers} }, my $tr = { id => $id, description => $desc // '', token => 'glptt-' . substr(md5_hex("trigger $p $id $desc"), 0, 20),
                                             owner => { username => $self->{as} }, created_at => $self->now };
        return { %$tr };
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/triggers', { description => $desc // '' });
}
sub triggers { my ($self, $p) = @_; $self->{local} ? [ map { +{ %$_ } } @{ $self->_p($p)->{triggers} // [] } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/triggers', undef, all => 1) }
sub trigger_pipeline {                        # trigger_pipeline(p, TOKEN, REF, variables => {K => V}) -> pipeline (source "trigger")
    my ($self, $p, $token, $ref, %o) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my ($tr) = grep { $_->{token} eq ($token // '') } @{ $P->{triggers} // [] };
        die "GitLab: invalid trigger token for $p (404 Not Found)\n" unless $tr;
        my $sha = $self->_sha($P, "refs/heads/$ref") // die "GitLab: no branch or tag '$ref' in $p (400 Reference not found)\n";
        local $self->{as} = $tr->{owner}{username};          # a triggered pipeline runs as the token's owner
        my ($pl) = $self->_pipeline($P, sha => $sha, source => 'trigger', ref => $ref, protected => ($self->_protected_branch($P, $ref) ? 1 : 0),
                                    vars => { CI_COMMIT_BRANCH => $ref, %{ $o{variables} // {} } });
        return $pl;
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/trigger/pipeline', { token => $token, ref => $ref, ($o{variables} ? (variables => $o{variables}) : ()) });
}
sub create_deploy_token {                     # create_deploy_token(p, NAME, [scopes], expires_at => DATE) -> { id, username, token, scopes }
    my ($self, $p, $name, $scopes, %o) = @_;
    my @s = @{ _arr($scopes) };
    my %ok = map { $_ => 1 } qw(read_repository read_registry write_registry read_package_registry write_package_registry);
    $ok{$_} or die "GitLab: deploy token scope is read_repository, read_registry, write_registry, read_package_registry or write_package_registry, not '$_'\n" for @s;
    if ($self->{local}) {
        my $P = $self->_p($p);
        die "GitLab: $self->{as} cannot create deploy tokens in $p (403 Forbidden)\n" if $self->_level($P, $self->{as}) < 40;
        my $id = $self->_id;
        push @{ $P->{deploy_tokens} }, my $dt = { id => $id, name => $name, username => "gitlab+deploy-token-$id", scopes => \@s, expires_at => $o{expires_at},
                                                  token => 'gldt-' . substr(md5_hex("deploy $p $id $name"), 0, 20), created_at => $self->now, revoked => 0 };
        return { %$dt };
    }
    $self->_api('POST', '/projects/' . $self->_pid($p) . '/deploy_tokens', { name => $name, scopes => \@s, ($o{expires_at} ? (expires_at => $o{expires_at}) : ()) });
}
sub deploy_tokens { my ($self, $p) = @_; $self->{local} ? [ map { +{ %$_, token => undef } } @{ $self->_p($p)->{deploy_tokens} // [] } ] : $self->_api('GET', '/projects/' . $self->_pid($p) . '/deploy_tokens', undef, all => 1) }
sub _deploy_token_ok {                        # a deploy token with this scope, not expired or revoked (local)
    my ($self, $P, $token, $scope) = @_;
    my ($dt) = grep { $_->{token} eq ($token // '') } @{ $P->{deploy_tokens} // [] } or return 0;
    return 0 if $dt->{revoked} || ($dt->{expires_at} && substr($self->now, 0, 10) gt $dt->{expires_at});
    (grep { $_ eq $scope } @{ $dt->{scopes} }) ? $dt : 0;
}

# ---------------------------------------------------------------- job artifacts and issue notes
sub job_artifact {                            # job_artifact(p, ref => R, job => NAME, path => FILE) -> the file's bytes, from the latest successful job
    my ($self, $p, %o) = @_;
    defined $o{$_} && length $o{$_} or die "GitLab: job_artifact needs $_\n" for qw(ref job path);
    (my $path = $o{path}) =~ s{^/+}{};
    !grep { $_ eq '..' } split m{/}, $path or die "GitLab: an artifact path may not contain '..' ('$o{path}')\n";
    if ($self->{local}) {
        my $P = $self->_p($p);
        for my $pl (reverse @{ $P->{pipelines} }) {
            next unless $pl->{ref} eq $o{ref} || ($pl->{ref} =~ m{^refs/merge-requests/} ? 0 : "refs/heads/$pl->{ref}" eq $o{ref});
            my ($j) = grep { $_->{name} eq $o{job} && $_->{status} eq 'success' } @{ $pl->{jobs} } or next;
            my $f = File::Spec->catfile($pl->{log_dir}, 'artifacts', GitLabCI::_safe($o{job}), split m{/}, $path);
            open my $fh, '<:raw', $f or die "GitLab: no artifact $path in job $o{job} of pipeline #$pl->{id} on $o{ref} (404 Not found)\n";
            local $/; my $t = <$fh>; close $fh;
            return $t;
        }
        die "GitLab: no successful job $o{job} on $o{ref} in $p (404 Not found)\n";
    }
    my $rel = '/projects/' . $self->_pid($p) . '/jobs/artifacts/' . _enc($o{ref}) . '/raw/' . join('/', map { _enc($_) } split m{/}, $path) . '?job=' . _enc($o{job});
    if ($self->{dry_run}) { my $fh = $self->{out}; print $fh "GET /api/v4$rel\n"; return '' }
    my $tok = $ENV{ $self->{token_env} } // die "GitLab: set $self->{token_env} to a personal or project access token (scope api)\n";
    my ($out, $rc) = _run(undef, {}, @{ $self->{curl} }, '-sS', '-f', '-L', '-H', "PRIVATE-TOKEN: $tok", "$self->{url}/api/v4$rel");
    die "GitLab: no artifact $path from job $o{job} on $o{ref} in $p (curl exit $rc: $out)\n" if $rc;
    $out;
}
sub issue_notes {                             # issue_notes(p, iid) -> [ { body, author {username}, created_at, system } ], oldest first
    my ($self, $p, $iid) = @_;
    return [ @{ $self->_issue($self->_p($p), $iid)->{notes} // [] } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . "/issues/$iid/notes", undef, query => { sort => 'asc', order_by => 'created_at' }, all => 1);
}

# ---------------------------------------------------------------- analytics: value stream, DORA, CI/CD, MRs, issues
# Computed only from what every tier's REST API returns (merge requests with their commits and notes, pipelines and
# jobs, issues and labels, deployments, releases, milestones), so the same report comes from gitlab.com Free, a
# self-managed server or the emulator. Times are hours unless named otherwise; p85 is the nearest-rank 85th percentile.
sub _t {                                      # ISO 8601 with optional fraction and offset -> epoch
    my $s = shift // return undef;
    my ($y, $mo, $d, $h, $mi, $se, $tz) = $s =~ /^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:\.\d+)?)?)?\s*(Z|[+-]\d\d:?\d\d)?/ or return undef;
    my $t = timegm($se // 0, $mi // 0, $h // 0, $d, $mo - 1, $y);
    if ($tz && $tz ne 'Z') { my ($sg, $hh, $mm) = $tz =~ /([+-])(\d\d):?(\d\d)/; $t -= ($sg eq '-' ? -1 : 1) * ($hh * 3600 + $mm * 60) }
    $t;
}
sub _median { my @v = sort { $a <=> $b } grep { defined } @_; return undef unless @v; @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2 }
sub _pct { my ($p, @v) = @_; @v = sort { $a <=> $b } grep { defined } @v; return undef unless @v; my $k = int($p * @v + 0.999999) - 1; $v[$k < 0 ? 0 : $k] }
sub _r1 { my $v = shift; defined $v ? 0 + sprintf('%.1f', $v) : undef }
sub mr_commits {                              # mr_commits(p, iid) -> [ { id, title, authored_date, created_at } ], newest first (as GitLab)
    my ($self, $p, $iid) = @_;
    return $self->_api('GET', '/projects/' . $self->_pid($p) . "/merge_requests/$iid/commits", undef, all => 1) unless $self->{local};
    my $P = $self->_p($p);
    my $m = $self->_mr($P, $iid);
    my $range = $m->{merge_commit_sha} ? "$m->{merge_commit_sha}^1..$m->{merge_commit_sha}^2"
              : ($self->_sha($P, "refs/heads/$m->{source_branch}") && $self->_sha($P, "refs/heads/$m->{target_branch}")) ? "refs/heads/$m->{target_branch}..refs/heads/$m->{source_branch}" : return [];
    my ($out, $rc) = $self->_git_rc($self->_bare($P), {}, 'log', '--first-parent', '--format=%H%x09%aI%x09%cI%x09%s', $range);
    return [] if $rc;
    [ map { my ($h, $a, $c, $s) = split /\t/, $_, 4; +{ id => $h, authored_date => $a, created_at => $c, title => $s } } grep { length } split /\n/, $out ];
}
sub mr_notes {
    my ($self, $p, $iid) = @_;
    return [ @{ $self->_mr($self->_p($p), $iid)->{notes} // [] } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . "/merge_requests/$iid/notes", undef, query => { sort => 'asc', order_by => 'created_at' }, all => 1);
}
sub _period {                                 # epoch -> period label for by => sprint|week|month
    my ($t, $by, $sprints) = @_;
    if ($by eq 'month') { return POSIX::strftime('%Y-%m', gmtime $t) }
    if ($by eq 'week') { my $wd = ((gmtime $t)[6] + 6) % 7; return 'week of ' . _date($t - $wd * 86400 - $t % 86400) }
    for my $s (@$sprints) { return $s->[0] if $t >= $s->[1] && $t < $s->[2] }
    return 'no sprint';
}
sub analytics {                               # analytics(p, since => D, until => D, by => sprint|week|month) -> report hash
    my ($self, $p, %o) = @_;
    my $by = $o{by} // 'sprint';
    $by =~ /^(sprint|week|month)$/ or die "GitLab: analytics --by is sprint, week or month, not '$by'\n";
    my $since = defined $o{since} ? _t($o{since}) // die("GitLab: bad date '$o{since}'\n") : 0;
    my $until = defined $o{until} ? (_t($o{until}) // die("GitLab: bad date '$o{until}'\n")) + ($o{until} =~ /T/ ? 0 : 86399) : $self->epoch;
    my $in = sub { my $t = shift; defined $t && $t >= $since && $t <= $until };
    my $proj = $self->project($p);
    my $dev = $proj->{default_branch} // 'main';
    my @sprints = sort { $a->[1] <=> $b->[1] } map { [ $_->{title}, _t($_->{start_date}), _t($_->{due_date}) + 3 * 86400 ] }
                  grep { ($_->{title} // '') =~ /sprint/i && $_->{start_date} && $_->{due_date} } @{ $self->milestones($p) };
    my $per = sub { _period(shift, $by, \@sprints) };
    my %periods;
    my %R = (project => $p, by => $by, since => $since ? _iso($since) : undef, until => _iso($until), default_branch => $dev);

    # merge requests, with their first commit and first review
    my $mrs = $self->mrs($p, state => 'all');
    my %issue = map { ($_->{iid} => $_) } @{ $self->issues($p, state => 'all') };
    my (@mr, %author);
    for my $m (sort { $a->{iid} <=> $b->{iid} } @$mrs) {
        my $open = _t($m->{created_at});
        my $merged = _t($m->{merged_at});
        next unless $in->($open) || $in->($merged);
        my $commits = $self->mr_commits($p, $m->{iid});
        my ($first) = sort { $a <=> $b } map { _t($_->{authored_date} // $_->{created_at}) } @$commits;
        my $au = ($m->{author} // {})->{username} // '';
        my ($review) = sort { $a <=> $b } map { _t($_->{created_at}) }
            grep { (($_->{author} // {})->{username} // '') ne $au && (!$_->{system} || ($_->{body} // '') =~ /^approved this merge request/) } @{ $self->mr_notes($p, $m->{iid}) };
        my @closes = map { /#(\d+)/g } (($m->{description} // '') =~ /\b(?:[Cc]los(?:e|es|ed|ing)|[Ff]ix(?:|es|ed|ing)|[Rr]esolv(?:e|es|ed|ing)|[Ii]mplement(?:s|ed|ing)?)\s*:?\s+((?:#\d+(?:\s*,\s*|\s+and\s+|\s+)?)+)/g);
        my $fix = (grep { $_ eq 'fix-forward' } @{ $m->{labels} // [] }) || ($m->{title} // '') =~ /^Revert\b/ ? 1 : 0;
        push @mr, my $r = { iid => $m->{iid}, title => $m->{title}, author => $au, source => $m->{source_branch}, target => $m->{target_branch}, state => $m->{state},
                            opened => $open, merged => $merged, first_commit => $first, first_review => $review, closes => \@closes, fix => $fix };
        $author{$au}{opened}++ if $in->($open);
        $author{$au}{merged}++ if $in->($merged);
    }

    # (1) value stream: per issue closed by an MR
    my @vs;
    for my $r (grep { $_->{merged} && @{ $_->{closes} } } @mr) {
        for my $n (@{ $r->{closes} }) {
            my $i = $issue{$n} or next;
            my ($c, $x) = (_t($i->{created_at}), _t($i->{closed_at}));
            my $h = sub { my ($a, $b) = @_; defined $a && defined $b ? ($b - $a) / 3600 : undef };
            push @vs, { issue => $n, mr => $r->{iid}, created => $c, closed => $x,
                        plan => $h->($c, $r->{first_commit}), code => $h->($r->{first_commit}, $r->{opened}), review => $h->($r->{opened}, $r->{first_review}),
                        approve => $h->($r->{first_review}, $r->{merged}), close => $h->($r->{merged}, $x), total => $h->($c, $x) };
        }
    }
    my @stages = ([ plan => 'issue created -> first commit' ], [ code => 'first commit -> MR opened' ], [ review => 'MR opened -> first review' ],
                  [ approve => 'first review -> merged' ], [ close => 'merged -> issue closed' ], [ total => 'issue created -> issue closed' ]);
    $R{value_stream} = { items => \@vs, stages => [ map { my $k = $_->[0]; my @v = map { $_->{$k} } @vs;
        +{ stage => $k, label => $_->[1], n => scalar(grep { defined } @v), median => _r1(_median(@v)), p85 => _r1(_pct(0.85, @v)) } } @stages ] };

    # pipelines and jobs
    my @pl;
    for my $pl (sort { $a->{id} <=> $b->{id} } @{ $self->pipelines($p) }) {
        my $t = _t($pl->{created_at});
        next unless $in->($t);
        my $jobs = $self->{local} ? $pl->{jobs} : $self->jobs($p, $pl->{id});
        my @st = grep { defined } map { _t($_->{started_at}) } @$jobs;
        my @fi = grep { defined } map { _t($_->{finished_at}) } @$jobs;
        my $dur = defined $pl->{duration} ? $pl->{duration} : @st && @fi ? (sort { $b <=> $a } @fi)[0] - (sort { $a <=> $b } @st)[0] : undef;
        push @pl, { id => $pl->{id}, ref => $pl->{ref}, source => $pl->{source}, status => $pl->{status}, t => $t, end => $t + ($dur // 0), minutes => defined $dur ? $dur / 60 : undef,
                    failed_jobs => [ map { $_->{name} } grep { $_->{status} eq 'failed' && !$_->{allow_failure} } @$jobs ], jobs => [ map { [ $_->{name}, $_->{status}, $_->{allow_failure} ? 1 : 0 ] } @$jobs ] };
    }
    # (2) DORA for a model repository
    my @dep = grep { $in->($_->{t}) } map { +{ t => _t($_->{created_at}), what => "pages deployment" } }
              grep { (($_->{environment} // {})->{name} // '') eq 'pages' && ($_->{status} // 'success') eq 'success' } @{ $self->deployments($p) };
    push @dep, grep { $in->($_->{t}) } map { +{ t => _t($_->{released_at} // $_->{created_at}), what => "release $_->{tag_name}" } } @{ $self->releases($p) };
    my @dmr = grep { $_->{target} eq $dev && $in->($_->{merged}) } @mr;
    my @lead = map { ($_->{merged} - $_->{first_commit}) / 3600 } grep { defined $_->{first_commit} } @dmr;
    my $fails = grep { $_->{fix} } @dmr;
    my $base = grep { !$_->{fix} } @dmr;
    my (@restore, $red);
    for my $x (grep { $_->{ref} eq $dev && $_->{source} ne 'merge_request_event' && $_->{status} =~ /^(success|failed)$/ } @pl) {
        if ($x->{status} eq 'failed') { $red //= $x->{t} }
        elsif (defined $red) { push @restore, ($x->{end} - $red) / 3600; undef $red }
    }
    my $weeks = ($until - ($since || (sort { $a <=> $b } map { $_->{opened} } @mr)[0] // $until)) / (7 * 86400);
    $R{dora} = { deployments => scalar @dep, per_week => $weeks > 0 ? 0 + sprintf('%.2f', @dep / $weeks) : undef, deploy_list => [ sort { $a->{t} <=> $b->{t} } @dep ],
                 lead_median => _r1(_median(@lead)), lead_p85 => _r1(_pct(0.85, @lead)), merges => $base, failures => $fails,
                 change_failure_rate => $base ? 0 + sprintf('%.1f', 100 * $fails / $base) : undef,
                 restore_median => _r1(_median(@restore)), restore_p85 => _r1(_pct(0.85, @restore)), restores => scalar @restore, still_red => defined $red ? 1 : 0 };
    # (3) CI/CD
    my %jf; my %jr;
    for my $x (@pl) { for my $j (@{ $x->{jobs} }) { next unless $j->[1] =~ /^(success|failed)$/; $jr{ $j->[0] }++; $jf{ $j->[0] }++ if $j->[1] eq 'failed' && !$j->[2] } }
    my $ok = grep { $_->{status} eq 'success' } @pl;
    my $bad = grep { $_->{status} eq 'failed' } @pl;
    my %cip;
    for my $x (@pl) { my $k = $per->($x->{t}); $periods{$k} //= $x->{t}; push @{ $cip{$k} }, $x }
    $R{ci} = { pipelines => scalar @pl, success => $ok, failed => $bad, success_rate => $ok + $bad ? 0 + sprintf('%.1f', 100 * $ok / ($ok + $bad)) : undef,
               median_minutes => _r1(_median(map { $_->{minutes} } @pl)), p85_minutes => _r1(_pct(0.85, map { $_->{minutes} } @pl)),
               jobs => [ map { +{ job => $_, runs => $jr{$_}, failed => $jf{$_} // 0 } } sort { ($jf{$b} // 0) <=> ($jf{$a} // 0) || $a cmp $b } keys %jr ],
               trend => [ map { my $k = $_; my @x = @{ $cip{$k} }; my $s = grep { $_->{status} eq 'success' } @x; my $f = grep { $_->{status} eq 'failed' } @x;
                   +{ period => $k, pipelines => scalar @x, success => $s, failed => $f, rate => $s + $f ? 0 + sprintf('%.1f', 100 * $s / ($s + $f)) : undef,
                      median_minutes => _r1(_median(map { $_->{minutes} } @x)) } } keys %cip ] };
    # (4) merge requests
    my %mp;
    for my $r (grep { $in->($_->{merged}) } @mr) { my $k = $per->($r->{merged}); $periods{$k} //= $r->{merged}; push @{ $mp{$k} }, $r }
    my @ttm = map { ($_->{merged} - $_->{opened}) / 3600 } grep { $in->($_->{merged}) } @mr;
    my @rev = map { ($_->{first_review} - $_->{opened}) / 3600 } grep { defined $_->{first_review} && $in->($_->{opened}) } @mr;
    $R{mrs} = { opened => scalar(grep { $in->($_->{opened}) } @mr), merged => scalar @ttm, ttm_median => _r1(_median(@ttm)), ttm_p85 => _r1(_pct(0.85, @ttm)),
                review_median => _r1(_median(@rev)), review_p85 => _r1(_pct(0.85, @rev)),
                authors => [ map { +{ author => $_, opened => $author{$_}{opened} // 0, merged => $author{$_}{merged} // 0 } } sort keys %author ],
                throughput => [ map { my @x = @{ $mp{$_} }; +{ period => $_, merged => scalar @x, ttm_median => _r1(_median(map { ($_->{merged} - $_->{opened}) / 3600 } @x)),
                                    review_median => _r1(_median(map { defined $_->{first_review} ? ($_->{first_review} - $_->{opened}) / 3600 : undef } @x)) } } keys %mp ],
                list => \@mr };
    # (5) issues
    my (%flow, @age);
    for my $i (values %issue) {
        my ($type) = map { /^type::(.+)/ ? $1 : () } @{ $i->{labels} // [] };
        $type //= $i->{issue_type} // 'issue';
        my ($c, $x) = (_t($i->{created_at}), _t($i->{closed_at}));
        if ($in->($c)) { my $k = $per->($c); $periods{$k} //= $c; $flow{$k}{$type}{opened}++ }
        if ($in->($x)) { my $k = $per->($x); $periods{$k} //= $x; $flow{$k}{$type}{closed}++ }
        push @age, { iid => $i->{iid}, type => $type, title => $i->{title}, days => ($until - $c) / 86400 } if $c <= $until && (!defined $x || $x > $until);
    }
    $R{issues} = { flow => [ map { my $k = $_; map { +{ period => $k, type => $_, opened => $flow{$k}{$_}{opened} // 0, closed => $flow{$k}{$_}{closed} // 0 } } sort keys %{ $flow{$k} } } keys %flow ],
                   open => scalar @age, age_median_days => _r1(_median(map { $_->{days} } @age)), age_p85_days => _r1(_pct(0.85, map { $_->{days} } @age)),
                   open_list => [ map { +{ %$_, days => _r1($_->{days}) } } sort { $b->{days} <=> $a->{days} || $a->{iid} <=> $b->{iid} } @age ] };
    $R{issues}{oldest} = [ @{ $R{issues}{open_list} }[0 .. ($#age < 9 ? $#age : 9)] ];
    # periods in time order
    my %ord = %periods;
    for my $k (qw(ci mrs)) { my $key = $k eq 'ci' ? 'trend' : 'throughput'; @{ $R{$k}{$key} } = sort { $ord{ $a->{period} } <=> $ord{ $b->{period} } } @{ $R{$k}{$key} } }
    @{ $R{issues}{flow} } = sort { $ord{ $a->{period} } <=> $ord{ $b->{period} } || $a->{type} cmp $b->{type} } @{ $R{issues}{flow} };
    \%R;
}
sub analytics_text {                          # the report as text tables
    my ($A) = @_;
    my $f = sub { defined $_[0] ? $_[0] : '-' };
    my $o = "GitLab analytics: $A->{project}, " . ($A->{since} // 'start') . " .. $A->{until}, by $A->{by}\n";
    $o .= "\n1. Value stream (hours; " . scalar(@{ $A->{value_stream}{items} }) . " issues closed by merge requests)\n";
    $o .= sprintf "   %-34s %5s %8s %8s\n", 'stage', 'n', 'median', 'p85';
    $o .= sprintf "   %-34s %5d %8s %8s\n", $_->{label}, $_->{n}, $f->($_->{median}), $f->($_->{p85}) for @{ $A->{value_stream}{stages} };
    my $d = $A->{dora};
    $o .= "\n2. DORA, for a model repository\n";
    $o .= sprintf "   %-34s %s (%s a week)\n", 'deployment frequency', $d->{deployments}, $f->($d->{per_week});
    $o .= sprintf "   %-34s median %s h, p85 %s h\n", "lead time (first commit -> merged on $A->{default_branch})", $f->($d->{lead_median}), $f->($d->{lead_p85});
    $o .= sprintf "   %-34s %s%% (%d fix-forward or revert MRs / %d merges)\n", 'change failure rate', $f->($d->{change_failure_rate}), $d->{failures}, $d->{merges};
    $o .= sprintf "   %-34s median %s h, p85 %s h (%d restores%s)\n", "time to restore ($A->{default_branch} red -> green)", $f->($d->{restore_median}), $f->($d->{restore_p85}), $d->{restores}, $d->{still_red} ? ', red now' : '';
    my $c = $A->{ci};
    $o .= "\n3. CI/CD: $c->{pipelines} pipelines, success rate " . $f->($c->{success_rate}) . "%, duration median " . $f->($c->{median_minutes}) . " min, p85 " . $f->($c->{p85_minutes}) . " min\n";
    $o .= sprintf "   %-28s %6s %8s %8s %12s\n", 'period', 'runs', 'failed', 'success%', 'median min';
    $o .= sprintf "   %-28s %6d %8d %8s %12s\n", $_->{period}, $_->{pipelines}, $_->{failed}, $f->($_->{rate}), $f->($_->{median_minutes}) for @{ $c->{trend} };
    $o .= "   job failures: " . (join(', ', map { "$_->{job} $_->{failed}/$_->{runs}" } grep { $_->{failed} } @{ $c->{jobs} }) || 'none') . "\n";
    my $m = $A->{mrs};
    $o .= "\n4. Merge requests: $m->{opened} opened, $m->{merged} merged; time to merge median " . $f->($m->{ttm_median}) . " h (p85 " . $f->($m->{ttm_p85})
        . " h); review turnaround median " . $f->($m->{review_median}) . " h (p85 " . $f->($m->{review_p85}) . " h)\n";
    $o .= sprintf "   %-28s %7s %12s %14s\n", 'period', 'merged', 'ttm median h', 'review median h';
    $o .= sprintf "   %-28s %7d %12s %14s\n", $_->{period}, $_->{merged}, $f->($_->{ttm_median}), $f->($_->{review_median}) for @{ $m->{throughput} };
    $o .= "   per author: " . join(', ', map { "$_->{author} $_->{merged}/$_->{opened}" } @{ $m->{authors} }) . " (merged/opened)\n";
    my $i = $A->{issues};
    $o .= "\n5. Issues: $i->{open} open, age median " . $f->($i->{age_median_days}) . " days, p85 " . $f->($i->{age_p85_days}) . " days\n";
    $o .= sprintf "   %-28s %-14s %7s %7s\n", 'period', 'type', 'opened', 'closed';
    $o .= sprintf "   %-28s %-14s %7d %7d\n", @$_{qw(period type opened closed)} for @{ $i->{flow} };
    $o .= "   oldest open: " . join(', ', map { "#$_->{iid} ($_->{type}, $_->{days} d)" } @{ $i->{oldest} }[0 .. ($#{ $i->{oldest} } < 4 ? $#{ $i->{oldest} } : 4)]) . "\n" if @{ $i->{oldest} };
    $o;
}
sub analytics_csv {                           # analytics_csv(report, DIR) -> { file => rows }
    my ($A, $dir) = @_;
    make_path($dir);
    -d $dir or die "GitLab: cannot create $dir\n";
    my %n;
    my $iso = sub { defined $_[0] ? _iso($_[0]) : '' };
    $n{'value_stream.csv'} = _csv("$dir/value_stream.csv", [qw(issue mr issue_created issue_closed plan_h code_h review_h approve_h close_h total_h)],
        map { [ $_->{issue}, $_->{mr}, $iso->($_->{created}), $iso->($_->{closed}), map { _r1($_) // '' } @$_{qw(plan code review approve close total)} ] } @{ $A->{value_stream}{items} });
    my $d = $A->{dora};
    $n{'dora.csv'} = _csv("$dir/dora.csv", [qw(metric value)], [ 'deployments', $d->{deployments} ], [ 'deployments_per_week', $d->{per_week} ], [ 'lead_time_median_h', $d->{lead_median} ],
        [ 'lead_time_p85_h', $d->{lead_p85} ], [ 'merges', $d->{merges} ], [ 'failures', $d->{failures} ], [ 'change_failure_rate_pct', $d->{change_failure_rate} ],
        [ 'time_to_restore_median_h', $d->{restore_median} ], [ 'time_to_restore_p85_h', $d->{restore_p85} ]);
    $n{'deployments.csv'} = _csv("$dir/deployments.csv", [qw(time what)], map { [ _iso($_->{t}), $_->{what} ] } @{ $d->{deploy_list} });
    $n{'pipelines.csv'} = _csv("$dir/pipelines.csv", [qw(period pipelines success failed success_pct median_minutes)], map { [ @$_{qw(period pipelines success failed rate median_minutes)} ] } @{ $A->{ci}{trend} });
    $n{'job_failures.csv'} = _csv("$dir/job_failures.csv", [qw(job runs failed)], map { [ @$_{qw(job runs failed)} ] } @{ $A->{ci}{jobs} });
    $n{'mr_throughput.csv'} = _csv("$dir/mr_throughput.csv", [qw(period merged ttm_median_h review_median_h)], map { [ @$_{qw(period merged ttm_median review_median)} ] } @{ $A->{mrs}{throughput} });
    $n{'mr_authors.csv'} = _csv("$dir/mr_authors.csv", [qw(author opened merged)], map { [ @$_{qw(author opened merged)} ] } @{ $A->{mrs}{authors} });
    $n{'mr_list.csv'} = _csv("$dir/mr_list.csv", [qw(iid title author source target state opened first_commit first_review merged fix)],
        map { [ $_->{iid}, $_->{title}, $_->{author}, $_->{source}, $_->{target}, $_->{state}, map({ $iso->($_) } @$_{qw(opened first_commit first_review merged)}), $_->{fix} ] } @{ $A->{mrs}{list} });
    $n{'issue_flow.csv'} = _csv("$dir/issue_flow.csv", [qw(period type opened closed)], map { [ @$_{qw(period type opened closed)} ] } @{ $A->{issues}{flow} });
    $n{'open_issues.csv'} = _csv("$dir/open_issues.csv", [qw(iid type age_days title)], map { [ @$_{qw(iid type days title)} ] } @{ $A->{issues}{open_list} });
    \%n;
}

# ---------------------------------------------------------------- export: CSVs for status-metrics and the sprint tracker
sub _csv_cell { my $v = shift // ''; $v =~ /[",\r\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v }
sub _csv { my ($path, $head, @rows) = @_; open my $fh, '>:raw', $path or die "GitLab: cannot write $path: $!\n"; print $fh join(',', @$head) . "\n";
           print $fh join(',', map { _csv_cell($_) } @$_) . "\n" for @rows; close $fh; scalar @rows }
sub export {
    my ($self, $p, $dir, %o) = @_;
    make_path("$dir/tracker");
    -d $dir or die "GitLab: cannot create $dir\n";
    my ($since, $until) = ($o{since} // '0000', $o{until} // '9999');
    my $in = sub { my $t = shift // ''; my $d = substr($t, 0, 10); $d ge substr($since, 0, 10) && $d le substr($until, 0, 10) };
    my %n;
    my (@jobs);
    for my $pl (sort { $a->{id} <=> $b->{id} } @{ $self->pipelines($p) }) {
        my $jobs = $self->{local} ? $pl->{jobs} : $self->jobs($p, $pl->{id});
        for my $j (sort { ($a->{started_at} // '') cmp ($b->{started_at} // '') || $a->{id} <=> $b->{id} } @$jobs) {
            next unless $j->{started_at} && $in->($j->{started_at});
            my $r = $j->{status} eq 'success' ? 'pass' : $j->{status} eq 'failed' ? ($j->{allow_failure} ? 'warn' : 'fail') : next;
            push @jobs, [ $j->{started_at}, $j->{name}, $pl->{ref}, $r, sprintf('%.2f', ($j->{duration} // 0) / 60) ];
        }
    }
    $n{ci_jobs} = _csv("$dir/ci_jobs.csv", [qw(ts job branch result minutes)], @jobs);
    my @mr;
    for my $m (sort { $a->{iid} <=> $b->{iid} } @{ $self->mrs($p) }) {
        next unless $in->($m->{created_at});
        my $lead = $m->{merged_at} ? sprintf('%.1f', (_epoch($m->{merged_at}) - _epoch($m->{created_at})) / 3600) : '';
        push @mr, [ $m->{iid}, $m->{title}, $m->{author}{username} // '', $m->{source_branch}, $m->{target_branch}, $m->{created_at}, $m->{merged_at} // '', $lead,
                    join(';', @{ $m->{labels} // [] }), $m->{state} ];
    }
    $n{mrs} = _csv("$dir/mrs.csv", [qw(iid title author source target created_at merged_at lead_hours labels state)], @mr);
    my $issues = $self->issues($p, state => 'all');
    my $type = sub { my $i = shift; my ($t) = map { /^type::(.+)/ ? $1 : () } @{ $i->{labels} }; $t // $i->{issue_type} // 'issue' };
    my $mil = sub { my $i = shift; ref $i->{milestone} ? $i->{milestone}{title} : '' };
    $n{issues} = _csv("$dir/issues.csv", [qw(iid type title labels milestone assignee state created_at closed_at)],
        map { [ $_->{iid}, $type->($_), $_->{title}, join(';', @{ $_->{labels} }), $mil->($_), join(';', map { $_->{username} } @{ $_->{assignees} // [] }),
                $_->{state}, $_->{created_at}, $_->{closed_at} // '' ] } grep { $in->($_->{created_at}) } sort { $a->{iid} <=> $b->{iid} } @$issues);
    my @def;
    for my $i (sort { $a->{iid} <=> $b->{iid} } @$issues) {
        next unless grep { $_ eq 'type::defect' || $_ eq 'type::discrepancy' } @{ $i->{labels} };
        my ($area) = map { /^area::(.+)/ ? $1 : () } @{ $i->{labels} };
        my ($phase) = map { /^phase::(.+)/ ? $1 : () } @{ $i->{labels} };
        push @def, [ "#$i->{iid}", $area // '', $phase // '', substr($i->{created_at}, 0, 10), $i->{closed_at} ? substr($i->{closed_at}, 0, 10) : '' ];
    }
    $n{defects} = _csv("$dir/defects.csv", [qw(id type phase found closed)], @def);
    my %sp;
    for my $i (@$issues) { my $t = $mil->($i); push @{ $sp{$1} }, $i if $t =~ /(\d+)\s*$/ && grep { $_ eq 'type::story' || $_ eq 'type::task' } @{ $i->{labels} } }
    for my $s (sort { $a <=> $b } keys %sp) {
        my @rows = map { my ($days, $why) = $self->_blocked($_); [ "#$_->{iid}", $_->{state} eq 'closed' ? 'done' : 'open', $days, $why ] } sort { $a->{iid} <=> $b->{iid} } @{ $sp{$s} };
        _csv("$dir/tracker/sprint-$s.csv", [qw(id status blocked_days blocker)], @rows);
        $n{tracker}++;
    }
    return \%n;
}
sub _blocked {                                # (working days with ~workflow::blocked, the reason) from the label history
    my ($self, $i) = @_;
    my ($from, $days, $why) = (undef, 0, '');
    for my $n (@{ $i->{notes} // [] }) {
        if ($n->{system} && $n->{body} =~ /added ~"?workflow::blocked/) { $from = _epoch($n->{created_at}) }
        elsif ($n->{system} && $n->{body} =~ /removed ~"?workflow::blocked/ && defined $from) { $days += _wdays($from, _epoch($n->{created_at})); undef $from }
        elsif (!$n->{system} && $n->{body} =~ /^\s*(?:Blocked(?: by)?|Blocker)\s*:\s*(.+)$/mi) { $why = $1 }
    }
    if (defined $from) { $days += _wdays($from, $i->{closed_at} ? _epoch($i->{closed_at}) : $self->epoch) }
    return ($days, $why);
}
sub _wdays { my ($a, $b) = @_; my $n = 0; for (my $t = $a; $t < $b; $t += 86400) { my $w = (gmtime $t)[6]; $n++ if $w > 0 && $w < 6 } $n }
sub _has_all { my ($have, $want) = @_; my %h = map { $_ => 1 } @$have; !grep { !$h{$_} } @$want }

# ---------------------------------------------------------------- project file: setup in one step
sub parse_project_file {                      # text -> { section => [ [key, value, line] ] }
    my ($text, $file) = @_;
    $file //= 'project file';
    my (%c, $sec);
    my $n = 0;
    for my $l (split /\r?\n/, $text) {
        $n++;
        $l =~ s/^\s*[;#].*$//; $l =~ s/\s+;.*$//; $l =~ s/\s+#\s.*$//;
        next unless $l =~ /\S/;
        if ($l =~ /^\s*\[\s*([\w ]+?)\s*\]\s*$/) { $sec = lc $1; next }
        defined $sec or die "$file:$n: a key before any [section]\n";
        my ($k, $v) = $l =~ /^\s*(.+?)\s*=\s*(.*?)\s*$/ or die "$file:$n: expected KEY = VALUE\n";
        push @{ $c{$sec} }, [ $k, $v, $n ];
    }
    \%c;
}
sub apply_project_file {                      # apply_project_file(path) -> [ lines of what was done ]
    my ($self, $path, %o) = @_;
    open my $fh, '<:raw', $path or die "GitLab: cannot read $path: $!\n";
    my $text = do { local $/; <$fh> }; close $fh;
    my $c = parse_project_file($text, $path);
    my @log;
    my %pr = map { ($_->[0] => $_->[1]) } @{ $c->{project} // [] };
    my $p = $o{project} // $pr{path} // die "$path: [project] needs path = group/name\n";
    my $exists = $self->{local} ? $self->{st}{projects}{$p} : eval { $self->_api('GET', '/projects/' . $self->_pid($p)); 1 } && !$self->{dry_run};
    if (!$exists) { my ($ns) = $p =~ m{^(.*)/}; $self->create_group($ns) if $self->{local}; $self->create_project($p, ($pr{visibility} ? (visibility => $pr{visibility}) : ())); push @log, "created project $p" }
    my %set = map { ($_ => $pr{$_}) } grep { $_ ne 'path' && $_ ne 'visibility' } keys %pr;
    if (%set) { $self->update_project($p, %set); push @log, 'settings: ' . join(', ', map { "$_=$set{$_}" } sort keys %set) }
    for (@{ $c->{members} // [] }) { $self->add_member($p, $_->[0], $_->[1]); push @log, "member $_->[0] $_->[1]" }
    for (@{ $c->{variables} // [] }) { my ($v, @fl) = split /\s+\|\s+/, $_->[1]; $self->set_variable($p, $_->[0], $v, map { ($_ => 1) } @fl); push @log, "variable $_->[0]" }
    for (@{ $c->{labels} // [] }) {
        my ($color, $desc) = $_->[1] =~ /^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$/ or die "$path:$_->[2]: label value is '#RRGGBB | description'\n";
        $self->create_label($p, $_->[0], $color, $desc // ''); push @log, "label $_->[0]";
    }
    for (@{ $c->{milestones} // [] }) {
        if ($_->[0] eq 'sprints') {
            my ($start, $count, $weeks, $prefix) = split ' ', $_->[1], 4;
            push @log, map { "milestone $_->{title}" } $self->sprints($p, $start, $count, weeks => $weeks // 2, prefix => $prefix);
        } else {
            my ($dates, $desc) = split /\s*\|\s*/, $_->[1], 2;
            my ($s, $d) = split ' ', $dates // '';
            $self->_upsert_milestone($p, $_->[0], start_date => $s, due_date => $d, description => $desc // ''); push @log, "milestone $_->[0]";
        }
    }
    for (@{ $c->{branches} // [] }) {
        my %a = map { /^(\w+):(\S+)$/ ? (lc $1 => lc $2) : die "$path:$_->[2]: branch rule words are push:LEVEL merge:LEVEL force:yes|no codeowners:yes|no\n" } split ' ', $_->[1];
        $self->protect_branch($p, $_->[0], push_access_level => $a{push} // 'maintainer', merge_access_level => $a{merge} // 'maintainer',
                              allow_force_push => ($a{force} // 'no') eq 'yes', code_owner_approval_required => ($a{codeowners} // 'no') eq 'yes');
        push @log, "protected branch $_->[0] ($_->[1])";
    }
    for (@{ $c->{tags} // [] }) {
        my ($lvl) = $_->[1] =~ /^create:(\S+)$/ or die "$path:$_->[2]: tag rule is create:LEVEL\n";
        $self->protect_tag($p, $_->[0], create_access_level => $lvl); push @log, "protected tag $_->[0]";
    }
    for (@{ $c->{approvals} // [] }) {
        my ($n, @users) = split ' ', $_->[1];
        $n =~ /^\d+$/ or die "$path:$_->[2]: approval rule is N user user ...\n";
        $self->create_approval_rule($p, $_->[0], $n, users => \@users); push @log, "approval rule $_->[0] ($n)";
    }
    for (@{ $c->{schedules} // [] }) {               # Description = CRON | REF | TZ | K=V K=V
        my ($cron, $ref, $tz, $vars) = map { s/^\s+|\s+$//gr } split /\|/, $_->[1], 4;
        defined $ref && length $ref && defined $cron && length $cron or die "$path:$_->[2]: a schedule is CRON | REF [| TZ [| K=V ...]]\n";
        my %v = map { /^([A-Za-z_]\w*)=(.*)$/ ? ($1 => $2) : die "$path:$_->[2]: schedule variables are KEY=VALUE, not '$_'\n" } split ' ', $vars // '';
        my %o = (description => $_->[0], ref => $ref, cron => $cron, cron_timezone => (defined $tz && length $tz ? $tz : 'UTC'), variables => \%v);
        my $name = $_->[0];
        my $old;
        ($old) = grep { $_->{description} eq $name } @{ $self->schedules($p) } unless $self->{dry_run} && !$self->{local};
        if ($old) { my %drop = map { ($_->{key} => undef) } @{ $old->{variables} // [] }; $self->update_schedule($p, $old->{id}, %o, variables => { %drop, %v }) }
        elsif ($self->{local} && !$self->_sha($self->_p($p), "refs/heads/$ref") && !$self->_sha($self->_p($p), "refs/tags/$ref")) {   # a new project: no branches yet
            warn "GitLab: schedule $name skipped: $ref does not exist yet; re-run setup after flow init\n";
            push @log, "schedule $name skipped ($ref does not exist yet)";
            next;
        }
        else { $self->create_schedule($p, %o) }
        push @log, "schedule $name ($cron, $o{cron_timezone}, $ref)";
    }
    return \@log;
}
sub _upsert_milestone {                       # create, or bring an existing milestone of that title up to date (setup re-runs)
    my ($self, $p, $title, %o) = @_;
    my ($m) = $self->{dry_run} ? () : grep { $_->{title} eq $title } @{ $self->milestones($p) };
    return $self->create_milestone($p, $title, %o) unless $m;
    my %ch = map { ($_ => $o{$_}) } grep { defined $o{$_} && ($m->{$_} // '') ne $o{$_} } keys %o;
    return %ch ? $self->update_milestone($p, $title, %ch) : $m;
}
sub sprints {                                 # sprints(p, START, COUNT, weeks => 2, prefix => 'Sprint ') -> milestones
    my ($self, $p, $start, $count, %o) = @_;
    my $w = $o{weeks} // 2;
    my $prefix = $o{prefix} // 'Sprint ';
    my $t0 = _epoch($start);
    my @m;
    for my $k (1 .. $count) {
        my $s = $t0 + ($k - 1) * $w * 7 * 86400;
        push @m, $self->_upsert_milestone($p, "$prefix$k", start_date => _date($s), due_date => _date($s + ($w * 7 - 3) * 86400),
                                         description => "Two-week sprint $k: planning on " . _date($s) . ', review and retrospective on ' . _date($s + ($w * 7 - 3) * 86400) . '.');
    }
    @m;
}

# ---------------------------------------------------------------- pipeline schedules: cron in a time zone
# Five fields, as GitLab (and cron) read them: minute hour day-of-month month day-of-week. Each field is *, a number,
# a list (1,15), a range (1-5), a step (*/15, 8-18/2) or a name (jan..dec, sun..sat; 0 and 7 are Sunday). When both
# day fields are restricted, either may match (cron's rule). @hourly @daily @midnight @weekly @monthly @yearly
# @annually are accepted. Time zones: UTC, fixed offsets (+05:30, -0400, UTC-5), and the US zones with US daylight
# saving (second Sunday of March 02:00 to first Sunday of November 02:00, local): America/New_York, America/Chicago,
# America/Denver, America/Phoenix (no DST), America/Los_Angeles, America/Anchorage, Pacific/Honolulu (no DST).
# A local time skipped by the spring change runs an hour later (02:30 -> 03:30 EDT); one repeated by the autumn
# change runs once, at its first occurrence.
my %MONTHS = (jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6, jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12);
my %DAYS = (sun => 0, mon => 1, tue => 2, wed => 3, thu => 4, fri => 5, sat => 6);
my %MACRO = ('@yearly' => '0 0 1 1 *', '@annually' => '0 0 1 1 *', '@monthly' => '0 0 1 * *', '@weekly' => '0 0 * * 0',
             '@daily' => '0 0 * * *', '@midnight' => '0 0 * * *', '@hourly' => '0 * * * *');
my %US_TZ = ('America/New_York' => [ -5, 1 ], 'US/Eastern' => [ -5, 1 ], 'America/Chicago' => [ -6, 1 ], 'US/Central' => [ -6, 1 ],
             'America/Denver' => [ -7, 1 ], 'US/Mountain' => [ -7, 1 ], 'America/Phoenix' => [ -7, 0 ], 'America/Los_Angeles' => [ -8, 1 ],
             'US/Pacific' => [ -8, 1 ], 'America/Anchorage' => [ -9, 1 ], 'Pacific/Honolulu' => [ -10, 0 ]);
sub parse_cron {                              # parse_cron('0 2 * * 1-5') -> { min, hour, dom, mon, dow => {n => 1}, dom_any, dow_any }
    my ($expr) = @_;
    my $e = lc($expr // '');
    $e =~ s/^\s+|\s+$//g;
    $e = $MACRO{$e} if $MACRO{$e};
    my @f = split ' ', $e;
    @f == 5 or die "GitLab: bad cron '" . ($expr // '') . "': want 5 fields (minute hour day-of-month month day-of-week)\n";
    my @spec = ([ 'minute', 0, 59 ], [ 'hour', 0, 23 ], [ 'day-of-month', 1, 31 ], [ 'month', 1, 12, \%MONTHS ], [ 'day-of-week', 0, 7, \%DAYS ]);
    my %c;
    for my $i (0 .. 4) {
        my ($name, $lo, $hi, $names) = @{ $spec[$i] };
        my %set;
        for my $part (split /,/, $f[$i]) {
            my ($range, $step) = split m{/}, $part, 2;
            !defined $step || $step =~ /^[1-9]\d*$/ or die "GitLab: bad cron '$expr': step '$step' in the $name field\n";
            my $num = sub { my $v = shift; return $names->{$v} if $names && exists $names->{$v}; $v =~ /^\d+$/ && $v >= $lo && $v <= $hi ? $v
                            : die "GitLab: bad cron '$expr': '$v' is not a $name ($lo-$hi" . ($names ? ' or a name' : '') . ")\n" };
            my ($a, $b);
            if ($range eq '*') { ($a, $b) = ($lo, $hi) }
            elsif ($range =~ /^([^-]+)-([^-]+)$/) { ($a, $b) = ($num->($1), $num->($2)); $a <= $b or die "GitLab: bad cron '$expr': range '$range' runs backwards\n" }
            else { $a = $num->($range); $b = defined $step ? $hi : $a }
            for (my $v = $a; $v <= $b; $v += $step // 1) { $set{ $i == 4 && $v == 7 ? 0 : $v } = 1 }
        }
        $c{ (qw(min hour dom mon dow))[$i] } = \%set;
    }
    $c{dom_any} = $f[2] =~ /^\*(\/1)?$/ ? 1 : 0;
    $c{dow_any} = $f[4] =~ /^\*(\/1)?$/ ? 1 : 0;
    \%c;
}
sub _nth_sunday { my ($y, $m, $n) = @_; my $t = timegm(0, 0, 0, 1, $m - 1, $y); my $w = (gmtime $t)[6]; 1 + (7 - $w) % 7 + 7 * ($n - 1) }
sub tz_offset {                               # tz_offset(TZ, utc_epoch) -> seconds east of UTC
    my ($tz, $t) = @_;
    $tz = 'UTC' if !defined $tz || $tz eq '';
    return 0 if $tz =~ /^(UTC|GMT|Z|Etc\/UTC|Etc\/GMT|Universal|Zulu)$/i;
    if ($tz =~ /^(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d\d))?$/i) { my $o = $2 * 3600 + ($3 // 0) * 60; return $1 eq '-' ? -$o : $o }
    my $z = $US_TZ{$tz} or die "GitLab: unknown time zone '$tz' (UTC, +HH:MM, America/New_York, America/Chicago, America/Denver, America/Los_Angeles, ...)\n";
    my $std = $z->[0] * 3600;
    return $std unless $z->[1];
    my $y = (gmtime($t + $std))[5] + 1900;
    my $on = timegm(0, 0, 2, _nth_sunday($y, 3, 2), 2, $y) - $std;             # 02:00 standard -> 03:00 daylight
    my $off = timegm(0, 0, 2, _nth_sunday($y, 11, 1), 10, $y) - ($std + 3600);  # 02:00 daylight -> 01:00 standard
    $t >= $on && $t < $off ? $std + 3600 : $std;
}
sub _local_to_utc {                           # a local wall-clock time (as a naive epoch) -> UTC epoch; gaps run an hour later, overlaps once
    my ($tz, $l) = @_;
    my @c = sort { $a <=> $b } grep { tz_offset($tz, $_) == $l - $_ } map { $l - $_ } do { my %u = map { ($_ => 1) } tz_offset($tz, $l - 86400), tz_offset($tz, $l + 86400); keys %u };
    return $c[0] if @c;
    return $l - tz_offset($tz, $l - 86400);  # in the spring gap: read it with the offset in force before the change
}
sub cron_next {                               # cron_next(CRON, TZ, after_epoch) -> the first run strictly after it (UTC epoch)
    my ($cron, $tz, $after) = @_;
    my $c = ref $cron ? $cron : parse_cron($cron);
    tz_offset($tz, $after);                   # an unknown zone dies here
    my $l = $after + tz_offset($tz, $after);
    $l = $l - $l % 60 + 60;
    for (my $guard = 0; $guard < 2_000_000; $guard++) {
        my ($mi, $h, $d, $mo, $y, $w) = (gmtime $l)[1 .. 6];
        $mo++; $y += 1900;
        if (!$c->{mon}{$mo}) { $l = $mo == 12 ? timegm(0, 0, 0, 1, 0, $y + 1) : timegm(0, 0, 0, 1, $mo, $y); next }
        my $day = $c->{dom_any} && $c->{dow_any} ? 1 : $c->{dom_any} ? $c->{dow}{$w} : $c->{dow_any} ? $c->{dom}{$d} : ($c->{dom}{$d} || $c->{dow}{$w});
        if (!$day) { $l = timegm(0, 0, 0, $d, $mo - 1, $y) + 86400; next }
        if (!$c->{hour}{$h}) { $l = $l - $l % 3600 + 3600; next }
        if (!$c->{min}{$mi}) { $l += 60; next }
        my $u = _local_to_utc($tz, $l);
        return $u if $u > $after;
        $l += 60;
    }
    die "GitLab: cron '$cron' never runs\n";
}
sub cron_runs { my ($cron, $tz, $after, $n) = @_; my @r; my $t = $after; for (1 .. $n) { $t = cron_next($cron, $tz, $t); push @r, $t } @r }

sub create_schedule {                         # create_schedule(p, description, ref, cron, cron_timezone => UTC, active => 1, variables => {K => V})
    my ($self, $p, %o) = @_;
    defined $o{$_} && length $o{$_} or die "GitLab: a pipeline schedule needs $_\n" for qw(description ref cron);
    my $tz = $o{cron_timezone} // 'UTC';
    my $active = defined $o{active} ? ($o{active} =~ /^(0|false|no|off)$/i ? 0 : 1) : 1;
    if ($self->{local}) {
        my $P = $self->_p($p);
        parse_cron($o{cron}); tz_offset($tz, 0);
        (my $ref = $o{ref}) =~ s{^refs/heads/}{};
        $self->_sha($P, "refs/heads/$ref") or $self->_sha($P, "refs/tags/$ref") or die "GitLab: no branch or tag '$ref' in $p (400 Ref is invalid)\n";
        push @{ $P->{schedules} }, my $s = { id => $self->_id, description => $o{description}, ref => $ref, cron => $o{cron}, cron_timezone => $tz, active => $active,
            owner => { username => $self->{as} }, created_at => $self->now, updated_at => $self->now, last_pipeline => undef,
            variables => [ map { +{ key => $_, value => $o{variables}{$_}, variable_type => 'env_var' } } sort keys %{ $o{variables} // {} } ] };
        $s->{next_run_at} = $active ? _iso(cron_next($s->{cron}, $tz, $self->epoch)) : undef;
        return $s;
    }
    my $base = '/projects/' . $self->_pid($p) . '/pipeline_schedules';
    my $s = $self->_api('POST', $base, { description => $o{description}, ref => $o{ref}, cron => $o{cron}, cron_timezone => $tz, active => _jbool($active ? 'true' : 'false') });
    my $sid = $self->{dry_run} ? '{id}' : $s->{id};
    $self->_api('POST', "$base/$sid/variables", { key => $_, value => $o{variables}{$_} }) for sort keys %{ $o{variables} // {} };
    $s;
}
sub schedules {
    my ($self, $p) = @_;
    return [ @{ $self->_p($p)->{schedules} // [] } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/pipeline_schedules', undef, all => 1);
}
sub _schedule { my ($self, $P, $id) = @_; (grep { $_->{id} == $id } @{ $P->{schedules} // [] })[0] // die "GitLab: no pipeline schedule $id in $P->{path_with_namespace} (404 Not found)\n" }
sub update_schedule {                         # update_schedule(p, id, description, ref, cron, cron_timezone, active, variables => {K => V or undef to drop})
    my ($self, $p, $id, %o) = @_;
    if ($self->{local}) {
        my $P = $self->_p($p);
        my $s = $self->_schedule($P, $id);
        parse_cron($o{cron}) if defined $o{cron};
        tz_offset($o{cron_timezone}, 0) if defined $o{cron_timezone};
        $s->{$_} = $o{$_} for grep { defined $o{$_} } qw(description ref cron cron_timezone);
        $s->{active} = $o{active} =~ /^(0|false|no|off)$/i ? 0 : 1 if defined $o{active};
        if (my $v = $o{variables}) {
            my %have = map { ($_->{key} => $_) } @{ $s->{variables} };
            for my $k (keys %$v) { if (defined $v->{$k}) { $have{$k} = { key => $k, value => $v->{$k}, variable_type => 'env_var' } } else { delete $have{$k} } }
            $s->{variables} = [ map { $have{$_} } sort keys %have ];
        }
        $s->{updated_at} = $self->now;
        $s->{next_run_at} = $s->{active} ? _iso(cron_next($s->{cron}, $s->{cron_timezone}, $self->epoch)) : undef;
        return $s;
    }
    my $base = '/projects/' . $self->_pid($p) . "/pipeline_schedules/$id";
    my %b = map { defined $o{$_} ? ($_ => $o{$_}) : () } qw(description ref cron cron_timezone);
    $b{active} = _jbool($o{active} =~ /^(0|false|no|off)$/i ? 'false' : 'true') if defined $o{active};
    my $s = %b ? $self->_api('PUT', $base, \%b) : undef;
    if (my $v = $o{variables}) {
        my %have = $self->{dry_run} ? () : map { ($_->{key} => 1) } @{ ($self->_api('GET', $base) // {})->{variables} // [] };
        for my $k (sort keys %$v) {
            if (!defined $v->{$k}) { $self->_api('DELETE', "$base/variables/" . _enc($k)) if $have{$k} }
            elsif ($have{$k}) { $self->_api('PUT', "$base/variables/" . _enc($k), { value => $v->{$k} }) }
            else { $self->_api('POST', "$base/variables", { key => $k, value => $v->{$k} }) }
        }
    }
    $s // ($self->{dry_run} ? {} : $self->_api('GET', $base));
}
sub delete_schedule {
    my ($self, $p, $id) = @_;
    if ($self->{local}) { my $P = $self->_p($p); $self->_schedule($P, $id); @{ $P->{schedules} } = grep { $_->{id} != $id } @{ $P->{schedules} }; return { id => $id } }
    $self->_api('DELETE', '/projects/' . $self->_pid($p) . "/pipeline_schedules/$id");
}
sub _schedule_pipeline {                      # one scheduled run: the ref's head, the schedule's variables, as its owner
    my ($self, $p, $s) = @_;
    my $as = $self->{as};
    $self->{as} = $s->{owner}{username};
    my $pl = eval { $self->_run_pipeline($p, $s->{ref}, source => 'schedule', variables => { map { ($_->{key} => $_->{value}) } @{ $s->{variables} } }) };
    my $err = $@;
    $self->{as} = $as;
    die $err if $err;
    if ($pl) { $pl->{schedule} = { id => $s->{id}, description => $s->{description} }; $s->{last_pipeline} = { id => $pl->{id}, status => $pl->{status}, ref => $pl->{ref}, created_at => $pl->{created_at} } }
    $pl;
}
sub play_schedule {                           # run a schedule now (its next_run_at does not change)
    my ($self, $p, $id) = @_;
    return $self->_schedule_pipeline($p, $self->_schedule($self->_p($p), $id)) if $self->{local};
    $self->_api('POST', '/projects/' . $self->_pid($p) . "/pipeline_schedules/$id/play", {});
}
sub run_due_schedules {                       # emulator: every due run up to `until`, in time order -> [ pipelines ]
    my ($self, $p, %o) = @_;
    $self->{local} or die "GitLab: run_due_schedules is for the local emulator; a GitLab server runs its schedules itself\n";
    my $P = $self->_p($p);
    my $until = defined $o{until} ? _epoch($o{until}) : $self->epoch;
    my $was = $self->epoch;
    if ($self->{dry_run}) {                   # list what would run, in order; change nothing
        my %next = map { ($_->{id} => _epoch($_->{next_run_at})) } grep { $_->{active} && defined $_->{next_run_at} } @{ $P->{schedules} // [] };
        my %by = map { ($_->{id} => $_) } @{ $P->{schedules} // [] };
        my $fh = $self->{out};
        while (my ($id) = sort { $next{$a} <=> $next{$b} || $a <=> $b } grep { $next{$_} <= $until } keys %next) {
            print $fh "POST /api/v4/projects/" . _enc($p) . "/pipeline_schedules/$id/play {}   # " . _iso($next{$id}) . " $by{$id}{description}\n";
            $next{$id} = cron_next($by{$id}{cron}, $by{$id}{cron_timezone}, $next{$id});
        }
        return [];
    }
    my (@pl, $n);
    while (1) {
        my ($s) = sort { $a->{next_run_at} cmp $b->{next_run_at} || $a->{id} <=> $b->{id} } grep { $_->{active} && defined $_->{next_run_at} && _epoch($_->{next_run_at}) <= $until } @{ $P->{schedules} // [] };
        last unless $s;
        ++$n <= 10_000 or die "GitLab: more than 10000 scheduled runs before $o{until}: check the cron lines\n";
        my $at = _epoch($s->{next_run_at});
        $self->clock($at);
        my $pl = $self->_schedule_pipeline($p, $s);
        push @pl, $pl if $pl;
        $s->{next_run_at} = _iso(cron_next($s->{cron}, $s->{cron_timezone}, $at));
    }
    $self->clock($until > $was ? $until : $was);
    \@pl;
}

# ================================================================ the local emulator
sub _id { ++$_[0]{st}{next_id} }
sub _user {
    my ($self, $u, %o) = @_;
    defined $u && length $u or die "GitLab: no user given\n";
    my $us = $self->{st}{users}{$u} //= { id => $self->_id, username => $u, name => $o{name} // ucfirst($u), email => $o{email} // "$u\@example.invalid", created_at => $self->now };
    $us->{name} = $o{name} if $o{name};
    $us->{email} = $o{email} if $o{email};
    $us;
}
sub _p { my ($self, $p) = @_; $self->{st}{projects}{$p} // die "GitLab: no project '$p' (404 Project Not Found)\n" }
sub _bare { my ($self, $P) = @_; "$self->{local}/repos/$P->{path_with_namespace}.git" }
sub _summary { my ($self, $P) = @_; +{ map { ($_ => $P->{$_}) } qw(id name path path_with_namespace namespace default_branch http_url_to_repo web_url settings created_at) } }
sub _create_project {
    my ($self, $path, %o) = @_;
    my ($ns, $name) = $path =~ m{^(.*)/([^/]+)$} or die "GitLab: project path '$path' needs a group: group/name\n";
    die "GitLab: project '$path' already exists (400 has already been taken)\n" if $self->{st}{projects}{$path};
    $self->create_group($ns);
    my $P = $self->{st}{projects}{$path} = { id => $self->_id, name => $o{name} // $name, path => $name, path_with_namespace => $path, namespace => $ns,
        default_branch => 'main', created_at => $self->now, creator => $self->{as}, web_url => "$self->{base}/$path",
        settings => { merge_method => 'merge', squash_option => 'default_off', only_allow_merge_if_pipeline_succeeds => 0,
                      only_allow_merge_if_all_discussions_are_resolved => 0, remove_source_branch_after_merge => 1, visibility => $o{visibility} // 'private' },
        members => { $self->{as} => 50 }, labels => [], milestones => [], protected_branches => [], protected_tags => [], approval_rules => [], variables => {},
        issues => [], mrs => [], pipelines => [], releases => [], wiki => [], iids => {}, seen => {} };
    my $bare = $self->_bare($P);
    make_path($bare);
    $self->_git($bare, {}, 'init', '-q', '--bare');
    $self->_git($bare, {}, 'symbolic-ref', 'HEAD', 'refs/heads/main');
    $P->{http_url_to_repo} = $bare;
    $self->_install_hook($P);
    $self->_write_protect($P);
    return $self->_summary($P);
}
sub _update_project {
    my ($self, $p, %s) = @_;
    my $P = $self->_p($p);
    for my $k (keys %s) {
        my $v = $s{$k};
        $v = $v =~ /^(true|yes|on|1)$/i ? 1 : $v =~ /^(false|no|off|0)$/i ? 0 : $v if defined $v;
        if ($k eq 'default_branch') { $P->{default_branch} = $v; $self->_git($self->_bare($P), {}, 'symbolic-ref', 'HEAD', "refs/heads/$v") }
        elsif ($k eq 'name') { $P->{name} = $v }
        else { $P->{settings}{$k} = $v }
    }
    $self->_write_protect($P);
    return $self->_summary($P);
}
sub _level {                                  # a user's access level on a project (project member, else group member, admin 60)
    my ($self, $P, $u) = @_;
    return 60 if ($self->{st}{users}{$u} // {})->{admin};
    my $l = $P->{members}{$u} // 0;
    my $ns = $P->{namespace};
    while (defined $ns && length $ns) {
        my $g = $self->{st}{groups}{$ns};
        $l = $g->{members}{$u} if $g && ($g->{members}{$u} // 0) > $l;
        $ns =~ s{/?[^/]*$}{};
    }
    $l;
}
sub _install_hook {
    my ($self, $P) = @_;
    my $hook = $self->_bare($P) . '/hooks/pre-receive';
    open my $fh, '>:raw', $hook or die "GitLab: cannot write $hook: $!\n";
    print $fh <<'HOOK';
#!/usr/bin/env perl
# pre-receive hook written by lib/GitLab.pm (the local GitLab emulator): protected branches and tags, as GitLab
# enforces them. Reads protect.txt beside it (rewritten whenever protection or membership changes). The pusher is
# $GITLAB_USER_LOGIN; the emulator's own merges set GITLAB_EMULATOR_BYPASS=1.
use strict;
use warnings;
exit 0 if $ENV{GITLAB_EMULATOR_BYPASS};
my $dir = $ENV{GIT_DIR} // '.';
my (%member, @branch, @tag);
open my $fh, '<', "$dir/protect.txt" or exit 0;
while (<$fh>) {
    chomp;
    my @f = split /\t/;
    if    ($f[0] eq 'member') { $member{ $f[1] } = $f[2] }
    elsif ($f[0] eq 'branch') { push @branch, { name => $f[1], push => $f[2], force => $f[3] } }
    elsif ($f[0] eq 'tag')    { push @tag, { name => $f[1], create => $f[2] } }
}
close $fh;
sub match { my ($pat, $s) = @_; my $re = join '.*', map { quotemeta } split /\*/, $pat, -1; $s =~ /^$re$/ }
my $user = $ENV{GITLAB_USER_LOGIN} // '';
my $level = $member{$user} // 0;
my $z = '0' x 40;
my $empty = !`git for-each-ref --count=1 refs/heads`;     # "fully protected after initial push": the first push is allowed
my @err;
while (my $l = <STDIN>) {
    my ($old, $new, $ref) = split ' ', $l;
    if ($level < 30) { push @err, "You are not allowed to push code to this project."; next }
    if ($ref =~ m{^refs/heads/(.+)$}) {
        my $b = $1;
        my ($r) = grep { match($_->{name}, $b) } @branch;
        next unless $r;
        next if $empty && $old eq $z;
        if ($new eq $z) { push @err, "You are not allowed to delete protected branches from this project."; next }
        if ($r->{push} == 0 || $level < $r->{push}) { push @err, "You are not allowed to push code to protected branches on this project."; next }
        if ($old ne $z && !$r->{force}) {
            system('git', 'merge-base', '--is-ancestor', $old, $new);
            push @err, "You are not allowed to force push code to a protected branch on this project." if $?;
        }
    } elsif ($ref =~ m{^refs/tags/(.+)$}) {
        my $t = $1;
        my ($r) = grep { match($_->{name}, $t) } @tag;
        next unless $r;
        if ($old ne $z) { push @err, "You are not allowed to change existing tags on this project."; next }
        push @err, "You are not allowed to create this tag as it is protected." if $r->{create} == 0 || $level < $r->{create};
    }
}
if (@err) { print STDERR "GitLab: $_\n" for @err; exit 1 }
exit 0;
HOOK
    close $fh;
    chmod 0755, $hook;
}
sub _write_protect {
    my ($self, $P) = @_;
    my $f = $self->_bare($P) . '/protect.txt';
    my %m = map { ($_ => $self->_level($P, $_)) } keys %{ $self->{st}{users} };
    open my $fh, '>:raw', $f or die "GitLab: cannot write $f: $!\n";
    print $fh "member\t$_\t$m{$_}\n" for sort keys %m;
    print $fh "branch\t$_->{name}\t$_->{push_access_level}\t$_->{allow_force_push}\n" for @{ $P->{protected_branches} };
    print $fh "tag\t$_->{name}\t$_->{create_access_level}\n" for @{ $P->{protected_tags} };
    close $fh;
}
sub _match_glob { my ($pat, $s) = @_; my $re = join '.*', map { quotemeta } split /\*/, $pat, -1; $s =~ /^$re$/ }
sub _protected_branch { my ($self, $P, $b) = @_; (grep { _match_glob($_->{name}, $b) } @{ $P->{protected_branches} })[0] }
sub _work {                                   # the emulator's own clone, fetched before every use
    my ($self, $P) = @_;
    my $w = "$self->{local}/work/" . _slug($P->{path_with_namespace});
    if (!-d "$w/.git") { make_path("$self->{local}/work"); remove_tree($w); $self->_git(undef, {}, 'clone', '-q', $self->_bare($P), $w); delete $self->{fetched}{$w} }
    my $sig = $self->_refsig($P);             # fetch only when the bare repository's refs changed (process starts are slow on Windows)
    if (($self->{fetched}{$w} // '') ne $sig) {
        $self->_git($w, {}, 'fetch', '-q', '--prune', '--force', 'origin', '+refs/heads/*:refs/remotes/origin/*', '+refs/tags/*:refs/tags/*');
        $self->{fetched}{$w} = $sig;
    }
    $w;
}
sub _refsig {                                 # a cheap signature of the bare repository's refs: packed-refs and loose ref files
    my ($self, $P) = @_;
    my $b = $self->_bare($P);
    my @f;
    my $walk; $walk = sub { my $d = shift; opendir my $dh, $d or return; for (sort grep { !/^\.\.?$/ } readdir $dh) { -d "$d/$_" ? $walk->("$d/$_") : push @f, "$d/$_" } closedir $dh };
    $walk->("$b/refs");
    my $one = sub { my $f = shift; my @st = stat $f; my $l = ''; if (open my $fh, '<', $f) { $l = <$fh> // ''; close $fh } "$f:" . ($st[7] // 0) . ':' . ($st[9] // 0) . ":$l" };
    join ';', map { $one->($_) } (-f "$b/packed-refs" ? "$b/packed-refs" : ()), @f;
}
sub _sha {                                    # a ref's sha: plain refs/heads|tags/NAME read from the files (no process), the rest via git
    my ($self, $P, $ref) = @_;
    if ($ref =~ m{^refs/(?:heads|tags)/[^\^~:\s]+$}) {
        my $b = $self->_bare($P);
        if (open my $fh, '<', "$b/$ref") { my $l = <$fh> // ''; close $fh; return $1 if $l =~ /^([0-9a-f]{40})/ }
        if (open my $fh, '<', "$b/packed-refs") { while (my $l = <$fh>) { if ($l =~ /^([0-9a-f]{40}) (\S+)$/ && $2 eq $ref) { close $fh; return $1 } } close $fh }
        return undef if -d "$b/refs";
    }
    my ($o, $rc) = $self->_git_rc($self->_bare($P), {}, 'rev-parse', '--verify', '-q', $ref);
    $rc ? undef : ($o =~ /([0-9a-f]{40})/)[0];
}
sub _commit_msg { my ($self, $P, $sha) = @_; $self->_git($self->_bare($P), {}, 'log', '-1', '--format=%B', $sha) }

# ---------------------------------------------------------------- local: issues and quick actions
sub _issue { my ($self, $P, $iid) = @_; (grep { $_->{iid} == $iid } @{ $P->{issues} })[0] // die "GitLab: no issue #$iid in $P->{path_with_namespace} (404 Not found)\n" }
sub _mr { my ($self, $P, $iid) = @_; (grep { $_->{iid} == $iid } @{ $P->{mrs} })[0] // die "GitLab: no merge request !$iid in $P->{path_with_namespace} (404 Not found)\n" }
sub _milestone { my ($self, $P, $t) = @_; my ($m) = grep { $_->{title} eq $t } @{ $P->{milestones} }; $m // die "GitLab: no milestone '$t' in $P->{path_with_namespace}\n" }
sub _sysnote { my ($self, $obj, $body) = @_; push @{ $obj->{notes} }, { id => $self->_id, body => $body, author => { username => $self->{as} }, created_at => $self->now, system => 1 } }
sub _labels_add {
    my ($self, $P, $obj, @l) = @_;
    for my $l (@l) {
        next if grep { $_ eq $l } @{ $obj->{labels} };
        $self->create_label($P->{path_with_namespace}, $l) unless grep { $_->{name} eq $l } @{ $P->{labels} };
        if ($l =~ /^(.+)::[^:]+$/) {                      # scoped labels are exclusive within their scope
            my $scope = $1;
            my @old = grep { /^\Q$scope\E::[^:]+$/ } @{ $obj->{labels} };
            if (@old) { @{ $obj->{labels} } = grep { !/^\Q$scope\E::[^:]+$/ } @{ $obj->{labels} }; $self->_sysnote($obj, 'removed ' . join(' ', map { qq(~"$_") } @old) . ' label' . (@old > 1 ? 's' : '')) }
        }
        push @{ $obj->{labels} }, $l;
        $self->_sysnote($obj, qq(added ~"$l" label));
    }
}
sub _labels_remove {
    my ($self, $obj, @l) = @_;
    my %r = map { $_ => 1 } @l;
    my @gone = grep { $r{$_} } @{ $obj->{labels} };
    @{ $obj->{labels} } = grep { !$r{$_} } @{ $obj->{labels} };
    $self->_sysnote($obj, 'removed ' . join(' ', map { qq(~"$_") } @gone) . ' label' . (@gone > 1 ? 's' : '')) if @gone;
}
sub _duration {                               # GitLab time notation (1w 2d 3h 30m) -> seconds; 1w = 5d, 1d = 8h, 1mo = 4w
    my $s = shift;
    my %u = (mo => 4 * 5 * 8 * 3600, w => 5 * 8 * 3600, d => 8 * 3600, h => 3600, m => 60);
    my $t = 0;
    my $neg = $s =~ s/^\s*-//;
    while ($s =~ /(\d+(?:\.\d+)?)\s*(mo|w|d|h|m)\b/g) { $t += $1 * $u{$2} }
    $neg ? -$t : $t;
}
sub _quick {                                  # run the quick actions in $body on $obj; returns the body without them
    my ($self, $P, $kind, $obj, $body) = @_;
    my @keep;
    my $tokens = sub { my $s = shift; my @t; while ($s =~ /([~%@#!])(?:"([^"]+)"|(\S+))/g) { push @t, [ $1, $2 // $3 ] } @t };
    for my $line (split /\n/, $body // '', -1) {
        my ($cmd, $arg) = $line =~ m{^/([a-z_]+)\b\s*(.*?)\s*$};
        if (!defined $cmd) { push @keep, $line; next }
        my @t = $tokens->($arg);
        if ($cmd eq 'milestone' && !grep { my $x = $_; $x->[0] eq '%' && grep { $_->{title} eq $x->[1] } @{ $P->{milestones} } } @t) { next }   # GitLab ignores a
        if ($cmd =~ /^(assign|label|relabel|relate|blocks|blocked_by)$/ && !@t) { next }                            # quick action whose
        if ($cmd =~ /^(assign)$/ && !grep { $_->[0] eq '@' && length $_->[1] } @t) { next }                        # argument is missing
        if ($cmd =~ /^(estimate|spend)$/ && $arg !~ /\d/) { next }                                                 # or invalid (the
        if ($cmd eq 'weight' && $arg !~ /^\d+$/) { next }                                                          # template's blanks)
        if ($cmd =~ /^(due|title)$/ && $arg !~ /\S/) { next }
        if    ($cmd eq 'label')   { $self->_labels_add($P, $obj, map { $_->[1] } grep { $_->[0] eq '~' } @t) }
        elsif ($cmd eq 'unlabel') { $self->_labels_remove($obj, @t ? (map { $_->[1] } grep { $_->[0] eq '~' } @t) : @{ $obj->{labels} }) }
        elsif ($cmd eq 'relabel') { $self->_labels_remove($obj, @{ $obj->{labels} }); $self->_labels_add($P, $obj, map { $_->[1] } grep { $_->[0] eq '~' } @t) }
        elsif ($cmd eq 'milestone') { my ($m) = map { $_->[1] } grep { $_->[0] eq '%' } @t; my $ms = $self->_milestone($P, $m);
                                      $obj->{milestone} = { id => $ms->{id}, iid => $ms->{iid}, title => $ms->{title} }; $self->_sysnote($obj, qq(changed milestone to %"$m")) }
        elsif ($cmd eq 'remove_milestone') { $obj->{milestone} = undef; $self->_sysnote($obj, 'removed milestone') }
        elsif ($cmd eq 'assign')  { for my $u (map { $_->[1] eq 'me' ? $self->{as} : $_->[1] } grep { $_->[0] eq '@' } @t) { $self->_user($u);
                                      push @{ $obj->{assignees} }, { username => $u, name => $self->{st}{users}{$u}{name} } unless grep { $_->{username} eq $u } @{ $obj->{assignees} };
                                      $self->_sysnote($obj, "assigned to \@$u") } }
        elsif ($cmd eq 'unassign') { $obj->{assignees} = []; $self->_sysnote($obj, 'unassigned') }
        elsif ($cmd eq 'close')   { $self->_close($obj) }
        elsif ($cmd eq 'reopen')  { if ($obj->{state} eq 'closed') { $obj->{state} = 'opened'; $obj->{closed_at} = undef; $self->_sysnote($obj, 'reopened') } }
        elsif ($cmd eq 'estimate') { $obj->{time_stats}{time_estimate} = _duration($arg); $self->_sysnote($obj, "changed time estimate to $arg") }
        elsif ($cmd eq 'spend')   { my ($d) = split ' ', $arg; $obj->{time_stats}{total_time_spent} += _duration($d); $self->_sysnote($obj, "added $d of time spent") }
        elsif ($cmd eq 'relate')  { $self->link_issues($P->{path_with_namespace}, $obj->{iid}, $_->[1], 'relates_to') for grep { $_->[0] eq '#' } @t; $self->_sysnote($obj, "marked this issue as related to $arg") }
        elsif ($cmd eq 'blocks')  { $self->link_issues($P->{path_with_namespace}, $obj->{iid}, $_->[1], 'blocks') for grep { $_->[0] eq '#' } @t }
        elsif ($cmd eq 'blocked_by') { $self->link_issues($P->{path_with_namespace}, $obj->{iid}, $_->[1], 'is_blocked_by') for grep { $_->[0] eq '#' } @t }
        elsif ($cmd eq 'title')   { $obj->{title} = $arg; $self->_sysnote($obj, "changed title to **$arg**") }
        elsif ($cmd eq 'due')     { $obj->{due_date} = $arg; $self->_sysnote($obj, "changed due date to $arg") }
        elsif ($cmd eq 'weight')  { $obj->{weight} = 0 + $arg; $self->_sysnote($obj, "set weight to $arg") }
        elsif ($cmd eq 'approve' && $kind eq 'mr') { $self->_approve($P->{path_with_namespace}, $obj->{iid}) }
        elsif ($cmd eq 'draft' && $kind eq 'mr') { $obj->{draft} = 1; $obj->{title} = "Draft: $obj->{title}" unless $obj->{title} =~ /^Draft:/; $self->_sysnote($obj, 'marked this merge request as **draft**') }
        elsif ($cmd eq 'ready' && $kind eq 'mr') { $obj->{draft} = 0; $obj->{title} =~ s/^Draft:\s*//; $self->_sysnote($obj, 'marked this merge request as **ready**') }
        elsif ($cmd eq 'done' || $cmd eq 'todo') { }
        else { push @keep, $line }
    }
    my $t = join "\n", @keep;
    $t =~ s/^\s*\n+//; $t =~ s/\s+$//;
    $t;
}
sub _close { my ($self, $obj, $note) = @_; return if $obj->{state} ne 'opened'; $obj->{state} = 'closed'; $obj->{closed_at} = $self->now; $obj->{closed_by} = { username => $self->{as} }; $self->_sysnote($obj, $note // 'closed') }
sub _create_issue {
    my ($self, $p, %o) = @_;
    my $P = $self->_p($p);
    my $iid = ++$P->{iids}{issue};
    my $type = $o{issue_type} // 'issue';
    $type =~ /^(issue|task|incident)$/ or die "GitLab: issue_type is issue, task or incident, not '$type'\n";
    my $i = { id => $self->_id, iid => $iid, project_id => $P->{id}, title => $o{title}, description => '', state => 'opened', labels => [], milestone => undef,
              assignees => [], author => { username => $self->{as} }, issue_type => $type, type => uc $type, weight => $o{weight}, due_date => $o{due_date},
              created_at => $self->now, updated_at => $self->now, closed_at => undef, web_url => "$self->{base}/$p/-/" . ($type eq 'task' ? 'work_items' : 'issues') . "/$iid",
              references => { short => "#$iid", full => "$p#$iid" }, time_stats => { time_estimate => 0, total_time_spent => 0 }, links => [], notes => [] };
    push @{ $P->{issues} }, $i;
    $self->_labels_add($P, $i, @{ _arr($o{labels}) }) if $o{labels};
    if ($o{milestone}) { my $m = $self->_milestone($P, $o{milestone}); $i->{milestone} = { id => $m->{id}, iid => $m->{iid}, title => $m->{title} } }
    for my $u (@{ _arr($o{assignees}) }) { $self->_user($u); push @{ $i->{assignees} }, { username => $u, name => $self->{st}{users}{$u}{name} } }
    $i->{description} = $self->_quick($P, 'issue', $i, $o{description} // '');
    @{ $i->{notes} } = ();                    # creation-time changes are not history notes
    $i;
}
sub _update_issue {
    my ($self, $p, $iid, %o) = @_;
    my $P = $self->_p($p);
    my $i = $self->_issue($P, $iid);
    $self->_labels_add($P, $i, @{ _arr($o{add_labels}) }) if $o{add_labels};
    $self->_labels_remove($i, @{ _arr($o{remove_labels}) }) if $o{remove_labels};
    if (defined $o{labels}) { $self->_labels_remove($i, @{ $i->{labels} }); $self->_labels_add($P, $i, @{ _arr($o{labels}) }) }
    if (defined $o{milestone}) { if ($o{milestone} eq '') { $i->{milestone} = undef } else { my $m = $self->_milestone($P, $o{milestone}); $i->{milestone} = { id => $m->{id}, iid => $m->{iid}, title => $m->{title} } } }
    if ($o{assignees}) { $i->{assignees} = [ map { $self->_user($_); { username => $_, name => $self->{st}{users}{$_}{name} } } @{ _arr($o{assignees}) } ] }
    $i->{$_} = $o{$_} for grep { defined $o{$_} } qw(title description weight due_date);
    if (my $e = $o{state_event}) {
        if ($e eq 'close') { $self->_close($i) }
        elsif ($e eq 'reopen') { if ($i->{state} eq 'closed') { $i->{state} = 'opened'; $i->{closed_at} = undef; $self->_sysnote($i, 'reopened') } }
        else { die "GitLab: state_event is close or reopen, not '$e'\n" }
    }
    $i->{updated_at} = $self->now;
    $i;
}
sub _add_note {
    my ($self, $p, $kind, $iid, $body, %o) = @_;
    my $P = $self->_p($p);
    my $obj = $kind eq 'mr' ? $self->_mr($P, $iid) : $self->_issue($P, $iid);
    my $text = $self->_quick($P, $kind, $obj, $body);
    $obj->{updated_at} = $self->now;
    return { commands_only => 1 } unless length $text;
    push @{ $obj->{notes} }, my $n = { id => $self->_id, body => $text, author => { username => $self->{as} }, created_at => $self->now, system => 0,
                                      resolvable => $o{resolvable} ? 1 : 0, resolved => 0 };
    $n;
}

# ---------------------------------------------------------------- local: merge requests, approvals, merging
sub _create_mr {
    my ($self, $p, %o) = @_;
    my $P = $self->_p($p);
    my ($s, $t) = @o{qw(source_branch target_branch)};
    $self->_sha($P, "refs/heads/$s") or die "GitLab: source branch '$s' does not exist in $p\n";
    $self->_sha($P, "refs/heads/$t") or die "GitLab: target branch '$t' does not exist in $p\n";
    die "GitLab: another open merge request already exists for this source branch: !" . join(', !', map { $_->{iid} } grep { $_->{state} eq 'opened' && $_->{source_branch} eq $s && $_->{target_branch} eq $t } @{ $P->{mrs} }) . "\n"
        if grep { $_->{state} eq 'opened' && $_->{source_branch} eq $s && $_->{target_branch} eq $t } @{ $P->{mrs} };
    my $iid = ++$P->{iids}{mr};
    my $m = { id => $self->_id, iid => $iid, project_id => $P->{id}, title => $o{title}, description => '', state => 'opened', source_branch => $s, target_branch => $t,
              labels => [], milestone => undef, author => { username => $self->{as} }, assignees => [], reviewers => [], created_at => $self->now, updated_at => $self->now,
              merged_at => undef, merged_by => undef, merge_commit_sha => undef, sha => $self->_sha($P, "refs/heads/$s"), draft => ($o{title} =~ /^(Draft|WIP):/i ? 1 : 0),
              remove_source_branch => (defined $o{remove_source_branch} ? ($o{remove_source_branch} ? 1 : 0) : $P->{settings}{remove_source_branch_after_merge} ? 1 : 0),
              web_url => "$self->{base}/$p/-/merge_requests/$iid", references => { short => "!$iid", full => "$p!$iid" }, approved_by => [], notes => [],
              pipelines => [], head_pipeline => undef, has_conflicts => 0 };
    push @{ $P->{mrs} }, $m;
    $self->_labels_add($P, $m, @{ _arr($o{labels}) }) if $o{labels};
    if ($o{milestone}) { my $ms = $self->_milestone($P, $o{milestone}); $m->{milestone} = { id => $ms->{id}, iid => $ms->{iid}, title => $ms->{title} } }
    $m->{assignees} = [ map { $self->_user($_); { username => $_ } } @{ _arr($o{assignee}) } ] if $o{assignee};
    $m->{reviewers} = [ map { $self->_user($_); { username => $_ } } @{ _arr($o{reviewers}) } ] if $o{reviewers};
    $m->{description} = $self->_quick($P, 'mr', $m, $o{description} // '');
    @{ $m->{notes} } = ();
    $self->_mr_pipeline($P, $m) unless $o{no_pipeline};
    $m;
}
sub _approve {
    my ($self, $p, $iid) = @_;
    my $P = $self->_p($p);
    my $m = $self->_mr($P, $iid);
    my $u = $self->{as};
    die "GitLab: merge request !$iid is not open\n" if $m->{state} ne 'opened';
    die "GitLab: $u wrote merge request !$iid and cannot approve it (401 Unauthorized)\n" if $m->{author}{username} eq $u;
    die "GitLab: $u has no access to approve in $p (401 Unauthorized)\n" if $self->_level($P, $u) < 20;
    die "GitLab: $u already approved merge request !$iid (401 Unauthorized)\n" if grep { $_->{user}{username} eq $u } @{ $m->{approved_by} };
    push @{ $m->{approved_by} }, { user => { username => $u }, approved_at => $self->now };
    $self->_sysnote($m, 'approved this merge request');
    $m;
}
sub _codeowners {                             # (CODEOWNERS text) -> [ { section, pattern, owners => [..] } ] from the target branch
    my ($self, $P, $ref) = @_;
    for my $f ('CODEOWNERS', 'docs/CODEOWNERS', '.gitlab/CODEOWNERS') {
        my ($t, $rc) = $self->_git_rc($self->_bare($P), {}, 'show', "$ref:$f");
        next if $rc;
        my ($sec, $opt, $count, $def, @r) = ('', 0, 1, []);
        for my $l (split /\r?\n/, $t) {
            $l =~ s/(^|\s)#.*$//;
            next unless $l =~ /\S/;
            if ($l =~ /^\s*(\^?)\[([^\]]+)\](?:\[(\d+)\])?\s*(.*)$/) {   # [Section][N] @default @owners; ^[Section] is optional
                ($opt, $sec, $count, $def) = ($1 ? 1 : 0, $2, $3 // 1, [ split ' ', $4 ]); next }
            my ($pat, @own) = split ' ', $l;
            push @r, { section => $sec, pattern => $pat, owners => (@own ? \@own : $def), optional => $opt, count => $count };   # no owners: the section's
        }
        return \@r;
    }
    return [];
}
sub _owner_re {                               # CODEOWNERS pattern -> regex over repo-relative paths (gitignore-like)
    my $p = shift;
    my $anch = $p =~ s{^/}{};
    my $dir = $p =~ s{/$}{};
    my $re = '';
    while (length $p) {
        if ($p =~ s/^\*\*\/?//) { $re .= '(?:.*/)?' }
        elsif ($p =~ s/^\*//) { $re .= '[^/]*' }
        elsif ($p =~ s/^\?//) { $re .= '[^/]' }
        else { $p =~ s/^([^*?]+)//; $re .= quotemeta $1 }
    }
    $re = ($anch || $re =~ m{/} ? '^' : '(?:^|/)') . $re . ($dir ? '/' : '(?:/|$)');
    qr/$re/;
}
sub _owners_count {                           # how many distinct approvers are among @owners (users, group members, e-mails)
    my ($self, $owners, $appr) = @_;
    my %who;
    for my $o (@$owners) {
        if ($o =~ /^@(.+)$/) {
            my $n = $1;
            $who{$n} = 1 if $appr->{$n};
            my $g = $self->{st}{groups}{$n};
            $who{$_} = 1 for $g ? grep { $appr->{$_} } keys %{ $g->{members} } : ();
        } elsif ($o =~ /@/) { $who{$_} = 1 for grep { ($self->{st}{users}{$_}{email} // '') eq $o } keys %$appr }
    }
    scalar keys %who;
}
sub _owners_ok {                              # is some owner in @owners among the approvers?
    my ($self, $owners, $appr) = @_;
    for my $o (@$owners) {
        if ($o =~ /^@(.+)$/) {
            my $n = $1;
            return 1 if $appr->{$n};
            my $g = $self->{st}{groups}{$n};
            return 1 if $g && grep { $appr->{$_} } keys %{ $g->{members} };
        } elsif ($o =~ /@/) { return 1 if grep { ($self->{st}{users}{$_}{email} // '') eq $o } keys %$appr }
    }
    0;
}
sub _changed { my ($self, $P, $from, $to) = @_; [ grep { length } split /\n/, $self->_git($self->_bare($P), {}, 'diff', '--name-only', "$from...$to") ] }
sub _merge {
    my ($self, $p, $iid, %o) = @_;
    my $P = $self->_p($p);
    my $m = $self->_mr($P, $iid);
    my $u = $self->{as};
    die "GitLab: MR is not open (!$iid is $m->{state}) (405 Method Not Allowed)\n" if $m->{state} ne 'opened';
    die "GitLab: MR !$iid is a draft; mark it ready first (405 Method Not Allowed)\n" if $m->{draft};
    die "GitLab: squash is not supported by the local emulator (the project merges with merge commits)\n" if $o{squash};
    my ($s, $t) = @$m{qw(source_branch target_branch)};
    my $ssha = $self->_sha($P, "refs/heads/$s") or die "GitLab: source branch '$s' no longer exists\n";
    my $rule = $self->_protected_branch($P, $t);
    my $lvl = $self->_level($P, $u);
    die "GitLab: $u is not allowed to merge into '$t' (405 Method Not Allowed)\n" if $lvl < ($rule ? ($rule->{merge_access_level} || 99) : 30);
    if ($m->{sha} ne $ssha || !$m->{head_pipeline}) { $m->{sha} = $ssha; $self->_mr_pipeline($P, $m) }
    if ($P->{settings}{only_allow_merge_if_pipeline_succeeds}) {
        my $hp = $m->{head_pipeline};
        die "GitLab: pipeline must succeed (!$iid has no pipeline) (405 Method Not Allowed)\n" unless $hp;
        die "GitLab: pipeline must succeed (pipeline #$hp->{id} $hp->{status}) (405 Method Not Allowed)\n" unless $hp->{status} eq 'success';
    }
    if ($P->{settings}{only_allow_merge_if_all_discussions_are_resolved}) {
        my $open = grep { $_->{resolvable} && !$_->{resolved} } @{ $m->{notes} };
        die "GitLab: discussions not resolved ($open open) (405 Method Not Allowed)\n" if $open;
    }
    my %appr = map { ($_->{user}{username} => 1) } @{ $m->{approved_by} };
    for my $r (@{ $P->{approval_rules} }) {
        my %elig = map { $_ => 1 } @{ $r->{users} };
        my $have = grep { !%elig || $elig{$_} } keys %appr;
        die "GitLab: approvals required: $r->{name} needs $r->{approvals_required}, has $have (405 Method Not Allowed)\n" if $have < $r->{approvals_required};
    }
    if ($rule && $rule->{code_owner_approval_required}) {
        my $own = $self->_codeowners($P, "refs/heads/$t");
        my %bysec;
        for my $f (@{ $self->_changed($P, "refs/heads/$t", "refs/heads/$s") }) {
            my %last;
            for my $e (@$own) { $last{ $e->{section} } = $e if $f =~ _owner_re($e->{pattern}) }
            for my $sec (sort keys %last) {
                my $e = $last{$sec};
                next if !@{ $e->{owners} } || $e->{optional};
                my $have = $self->_owners_count($e->{owners}, \%appr);
                next if $have >= ($e->{count} // 1);
                die "GitLab: code owner approval required for $f (" . join(' ', @{ $e->{owners} }) . (($e->{count} // 1) > 1 ? ", $e->{count} approvals, has $have" : '') . ") (405 Method Not Allowed)\n";
            }
        }
    }
    # the merge itself, in the emulator's clone
    my $w = $self->_work($P);
    $self->_git($w, {}, 'checkout', '-q', '--detach', "origin/$t");
    my @refs = ($m->{description} // '') =~ /\b(?:[Cc]los(?:e|es|ed|ing)|[Ff]ix(?:|es|ed|ing)|[Rr]esolv(?:e|es|ed|ing)|[Ii]mplement(?:s|ed|ing)?)\s*:?\s+((?:#\d+(?:\s*,\s*|\s+and\s+|\s+)?)+)/g;
    my @close = map { /#(\d+)/g } @refs;
    my $msg = "Merge branch '$s' into '$t'\n\n$m->{title}\n\n" . (@close ? join("\n", map { "Closes #$_" } @close) . "\n\n" : '') . "See merge request $p!$iid";
    my ($out, $rc) = $self->_git_rc($w, { $self->_git_env($u) }, 'merge', '--no-ff', '-q', '-m', $msg, "origin/$s");
    if ($rc) {
        $self->_git_rc($w, {}, 'merge', '--abort');
        $m->{has_conflicts} = 1;
        die "GitLab: merge conflict: !$iid cannot be merged into '$t'; merge '$t' into '$s' and resolve (406 Branch cannot be merged)\n";
    }
    my $before = $self->_sha($P, "refs/heads/$t");
    $self->_git($w, { GITLAB_EMULATOR_BYPASS => 1 }, 'push', '-q', 'origin', "HEAD:refs/heads/$t");
    my $msha = $self->_sha($P, "refs/heads/$t");
    @$m{qw(state merged_at merge_commit_sha has_conflicts)} = ('merged', $self->now, $msha, 0);
    $m->{merged_by} = { username => $u };
    $self->_sysnote($m, 'merged');
    if ($t eq $P->{default_branch}) {
        for my $n (@close) {
            my ($i) = grep { $_->{iid} == $n } @{ $P->{issues} } or next;
            $self->_close($i, "closed via merge request !$iid");
        }
    }
    if ($m->{remove_source_branch} || $o{remove_source_branch}) {
        $self->_git($self->_bare($P), {}, 'update-ref', '-d', "refs/heads/$s");
        delete $P->{seen}{"refs/heads/$s"};
    }
    $P->{seen}{"refs/heads/$t"} = $msha;
    $self->_push_pipeline($P, $t, $before, $msha);
    $m;
}

# ---------------------------------------------------------------- local: pipelines
sub _vars {
    my ($self, $P, %v) = @_;
    my $path = $P->{path_with_namespace};
    my $prot = $v{_protected}; delete $v{_protected};
    my %proj = map { ($_->{key} => $_->{value}) } grep { !$_->{protected} || $prot } values %{ $P->{variables} };
    my ($host) = $self->{base} =~ m{^\w+://([^/]+)};
    return (%proj, CI_DEFAULT_BRANCH => $P->{default_branch}, CI_PROJECT_PATH => $path, CI_PROJECT_NAME => $P->{path}, CI_PROJECT_NAMESPACE => $P->{namespace},
            CI_PROJECT_URL => "$self->{base}/$path", CI_SERVER_URL => $self->{base}, CI_SERVER_HOST => $host, GITLAB_USER_LOGIN => $self->{as}, %v);
}
sub _pipeline {                               # run .gitlab-ci.yml at $sha (or a merged result) -> pipeline record, or undef when no job runs
    my ($self, $P, %o) = @_;
    my $w = $self->_work($P);
    make_path("$self->{local}/tmp");
    my $wt = tempdir('pl-XXXXXX', DIR => "$self->{local}/tmp");
    rmdir $wt;
    $self->_git($w, {}, 'worktree', 'add', '-q', '--detach', $wt, $o{sha});
    my $cleanup = sub { $self->_git_rc($w, {}, 'worktree', 'remove', '--force', $wt); remove_tree($wt) if -d $wt };
    my $sha = $o{sha};
    if ($o{merge_from}) {                    # a merged-results pipeline: merge the source into the target, do not push
        my ($out, $rc) = $self->_git_rc($wt, { $self->_git_env($self->{as}) }, 'merge', '--no-ff', '-q', '-m', "Merge branch '$o{source}' into '$o{target}'", $o{merge_from});
        if ($rc) { $self->_git_rc($wt, {}, 'merge', '--abort'); $self->_git($wt, {}, 'checkout', '-q', '--detach', $o{merge_from}); $o{conflict} = 1; $sha = $o{merge_from} }
        else { ($sha) = $self->_git($wt, {}, 'rev-parse', 'HEAD') =~ /([0-9a-f]{40})/ }
    }
    if (!-f "$wt/.gitlab-ci.yml") { $cleanup->(); return (undef, $o{conflict}) }
    require GitLabCI;
    my $id = ++$self->{st}{next_pipeline_id};
    my $piid = ++$P->{iids}{pipeline};
    my ($tree, $msg) = $self->_git($wt, {}, 'log', '-1', '--format=%T%n%B', $sha) =~ /^([0-9a-f]{40})\n(.*)$/s;
    my ($title) = split /\n/, $msg;
    (my $ref_slug = lc $o{ref}) =~ s/[^a-z0-9]+/-/g;
    my %vars = $self->_vars($P, %{ $o{vars} // {} }, CI_PIPELINE_SOURCE => $o{source}, CI_PIPELINE_ID => $id, CI_PIPELINE_IID => $piid, CI_COMMIT_SHA => $sha,
        CI_COMMIT_SHORT_SHA => substr($sha, 0, 8), CI_COMMIT_REF_NAME => $o{ref}, CI_COMMIT_REF_SLUG => substr($ref_slug, 0, 63), CI_COMMIT_TITLE => $title // '',
        CI_COMMIT_MESSAGE => $msg, CI_COMMIT_REF_PROTECTED => ($o{protected} ? 'true' : 'false'), _protected => $o{protected});
    $vars{GITLAB_LOCAL_REGISTRY} //= "$self->{local}/packages/$P->{path_with_namespace}";   # the emulator's package registry, as files (no HTTP here)
    $vars{CI_PROJECT_ID} //= $P->{id};
    my %uv = map { ($_ => $vars{$_}) } grep { !/^(?:CI_|GITLAB_USER_LOGIN$|_)/ } keys %vars;   # trigger, schedule, run and project variables
    my $cache_tree = %uv ? "$tree\0" . md5_hex(join "\0", map { "$_=$uv{$_}" } sort keys %uv) : $tree;   # a job result is reused only with the same variables
    my $log = "$self->{local}/pipelines/" . _slug($P->{path_with_namespace}) . "/$id";
    make_path($log);
    my $t0 = $self->epoch;
    my $wall = time;
    my $res = eval { GitLabCI::run(GitLabCI::load("$wt/.gitlab-ci.yml", file => '.gitlab-ci.yml'), dir => $wt, vars => \%vars, changed => $o{changed} // [],
                                   log_dir => $log, cache => ($self->{cache_on} ? ($self->{st}{ci_cache} //= {}) : undef), tree => $cache_tree, shell => $self->{runner_shell},
                                   clock => ($self->{freeze} ? sub { $t0 } : sub { $t0 + (time - $wall) }), manual => 0, parallel => $self->{parallel} // 1) };
    my $err = $@;
    $self->_model_times($res, $t0, $tree) if $res && $self->{job_seconds};
    my $ci = $err ? undef : eval { GitLabCI::load("$wt/.gitlab-ci.yml", file => '.gitlab-ci.yml') };
    my %post = $ci ? $self->_post_jobs($P, $ci, $res, $wt, $tree, $log, \%vars) : ();
    $cleanup->();
    if ($err) { $err =~ s/\s+$//; $res = { status => 'failed', jobs => [], yaml_errors => $err } }
    if (!$err && !grep { $_->{status} ne 'skipped' } @{ $res->{jobs} }) { $self->{st}{next_pipeline_id}--; $P->{iids}{pipeline}--; remove_tree($log); return (undef, $o{conflict}) }
    my $jid = 0;
    my $at = $t0;
    my @jobs;
    for my $j (@{ $res->{jobs} }) {
        next if $j->{status} eq 'skipped' && !defined $j->{started};
        my $st = $j->{status} eq 'allowed_failure' ? 'failed' : $j->{status};
        my $start = defined $j->{started} ? $j->{started} : $at;
        my $dur = $j->{duration} // 0;
        push @jobs, { id => ++$self->{st}{next_job_id}, name => $j->{name}, stage => $j->{stage}, status => $st, allow_failure => ($j->{status} eq 'allowed_failure' ? 1 : 0),
                      ref => $o{ref}, started_at => ($st eq 'skipped' || $st eq 'manual' ? undef : _iso($start)), finished_at => ($st eq 'skipped' || $st eq 'manual' ? undef : _iso($start + $dur)),
                      duration => ($st eq 'skipped' || $st eq 'manual' ? undef : 0 + sprintf('%.2f', $dur)), log => $j->{log}, exit => $j->{exit}, cached => $j->{cached} ? 1 : 0,
                      pipeline => { id => $id } };
        $at = $start + $dur if $start + $dur > $at;
    }
    my $status = $err ? 'failed' : $res->{status} eq 'failed' ? 'failed' : 'success';
    my $pl = { id => $id, iid => $piid, project_id => $P->{id}, sha => $sha, before_sha => $o{before} // $ZERO, ref => $o{ref}, tag => $o{tag} ? 1 : 0, source => $o{source},
               status => $status, created_at => _iso($t0), updated_at => _iso($at), started_at => _iso($t0), finished_at => _iso($at), duration => 0 + sprintf('%.2f', $at - $t0),
               user => { username => $self->{as} }, web_url => "$self->{base}/$P->{path_with_namespace}/-/pipelines/$id", jobs => \@jobs,
               ($o{mr_iid} ? (mr_iid => $o{mr_iid}) : ()), ($o{conflict} ? (detached => 1) : ()), ($err ? (yaml_errors => $err) : ()), log_dir => $log,
               (%{ $post{reports} // {} } ? (reports => $post{reports}) : ()) };
    push @{ $P->{pipelines} }, $pl;
    if (!$o{mr_iid} && !$o{tag}) {
        for my $d (@{ $post{deploy} // [] }) { $self->_deploy($P, $pl, %$d) }
        $self->_pages($P, $pl, $post{pages}) if $post{pages} && $o{ref} eq $P->{default_branch};
    }
    for my $r (@{ $post{release} // [] }) {   # created by the pipeline, as release-cli does after the job
        next if grep { $_->{tag_name} eq $r->{tag_name} } @{ $P->{releases} };
        eval { $self->create_release($P->{path_with_namespace}, %$r, released_at => $pl->{finished_at}, evidence_pipeline => $pl); 1 } or warn $@;
    }
    return ($pl, $o{conflict});
}
sub _model_times {                            # job_seconds => sub { (job, tree) -> seconds }: durations from a model, not the wall clock
    my ($self, $res, $t0, $tree) = @_;        # (replays and simulations need the same times on every run); a stage starts when the last ends
    my ($at, $stage, $end) = ($t0 + 15, undef, $t0 + 15);   # 15 s for a runner to pick the pipeline up
    for my $j (@{ $res->{jobs} }) {
        next if $j->{status} eq 'skipped' || $j->{status} eq 'manual';
        if (!defined $stage || $j->{stage} ne $stage) { $at = $end + (defined $stage ? 5 : 0); $stage = $j->{stage} }
        my $d = 0 + sprintf('%.1f', $self->{job_seconds}->($j->{name}, $tree, $j) // 0);
        @$j{qw(started duration)} = ($at, $d);
        $end = $at + $d if $at + $d > $end;
    }
}
# ---------------------------------------------------------------- local: report widgets, Pages, environments
sub _jobdef {                                 # the job's YAML (extends merged) from the loaded pipeline
    my ($ci, $name) = @_;
    my $j = eval { GitLabCI::_extends($ci, $name, {}, 0) };
    ref $j eq 'HASH' ? $j : ref $ci->{data}{$name} eq 'HASH' ? $ci->{data}{$name} : {};
}
sub _glob_files { my ($dir, $pat) = @_; return () unless defined $pat; map { substr($_, length($dir) + 1) } grep { -f } File::Glob::bsd_glob("$dir/$pat") }
sub parse_junit {                             # JUnit XML text -> { total, failed, skipped, failures => [ "suite: name" ] }
    my $t = shift // '';
    my %r = (total => 0, failed => 0, skipped => 0, failures => []);
    while ($t =~ m{<testcase\b([^>]*?)(/>|>(.*?)</testcase>)}gs) {
        my ($a, $body) = ($1, $3 // '');
        $r{total}++;
        my ($n) = $a =~ /\bname="([^"]*)"/;
        my ($c) = $a =~ /\bclassname="([^"]*)"/;
        if ($body =~ /<(failure|error)\b/) { $r{failed}++; push @{ $r{failures} }, join(': ', grep { defined && length } $c, $n) }
        elsif ($body =~ /<skipped\b/) { $r{skipped}++ }
    }
    \%r;
}
sub parse_codequality {                       # Code Climate JSON -> [ { fingerprint, severity, description, path, line } ]
    my $t = shift // '';
    my $d = eval { $JSON->decode($t) };
    return [] unless ref $d eq 'ARRAY';
    [ map { +{ fingerprint => $_->{fingerprint} // md5_hex(($_->{description} // '') . ($_->{location}{path} // '')), severity => $_->{severity} // 'info',
              description => $_->{description} // '', path => $_->{location}{path} // '', line => ($_->{location}{lines} // {})->{begin} // ($_->{location}{positions} // {})->{begin}{line} // 0 } }
      grep { ref $_ eq 'HASH' } @$d ];
}
sub parse_metrics {                           # OpenMetrics text -> { name => value }
    my %m;
    for (split /\n/, shift // '') { next if /^\s*(#|$)/; my ($k, $v) = /^\s*(\S+)\s+(\S+)/ or next; $m{$k} = $v }
    \%m;
}
sub _post_jobs {                              # after the jobs ran in $wt: report files, the pages job, deployments
    my ($self, $P, $ci, $res, $wt, $tree, $log, $vars) = @_;
    my (%rep, @deploy, $pages, @release);
    my $rc = $self->{st}{report_cache} //= {};
    my %dot;                                  # artifacts:reports:dotenv: KEY=VALUE files a job leaves for the jobs after it
    for my $j (grep { $_->{status} eq 'success' } @{ $res->{jobs} }) {
        my $def = _jobdef($ci, $j->{name});
        my $de = ref $def->{artifacts} eq 'HASH' && ref $def->{artifacts}{reports} eq 'HASH' ? $def->{artifacts}{reports}{dotenv} : undef;
        for my $f (map { _glob_files($wt, $_) } GitLabCI::_list_of($de)) {
            open my $fh, '<:raw', "$wt/$f" or next;
            while (<$fh>) { $dot{$1} = $2 if /^\s*([A-Za-z_]\w*)=(.*?)\s*$/ }
            close $fh;
        }
    }
    my %rv = (%{ $vars // {} }, CI_API_V4_URL => "$self->{base}/api/v4", CI_PROJECT_ID => $P->{id}, %dot);   # what release: expands
    for my $j (@{ $res->{jobs} }) {
        next unless $j->{status} =~ /^(success|failed|allowed_failure)$/;
        my $def = _jobdef($ci, $j->{name});
        my $reports = ref $def->{artifacts} eq 'HASH' && ref $def->{artifacts}{reports} eq 'HASH' ? $def->{artifacts}{reports} : {};
        my $key = "$j->{name}\0$tree";
        if (%$reports) {
            my $r = $j->{cached} && $rc->{$key} ? $rc->{$key} : do {
                my %one;
                for my $kind (qw(junit codequality metrics)) {
                    my @files = map { _glob_files($wt, $_) } GitLabCI::_list_of($reports->{$kind});
                    next unless @files;
                    my $text = join "\n", map { open my $fh, '<:raw', "$wt/$_" or (); local $/; <$fh> // '' } @files;
                    $one{$kind} = $kind eq 'junit' ? parse_junit($text) : $kind eq 'codequality' ? parse_codequality($text) : parse_metrics($text);
                }
                $rc->{$key} = \%one;
            };
            for my $kind (keys %$r) {
                if ($kind eq 'junit') { my $a = $rep{junit} //= { total => 0, failed => 0, skipped => 0, failures => [] }; $a->{$_} += $r->{junit}{$_} for qw(total failed skipped); push @{ $a->{failures} }, @{ $r->{junit}{failures} } }
                elsif ($kind eq 'codequality') { push @{ $rep{codequality} }, @{ $r->{codequality} } }
                else { $rep{metrics}{$_} = $r->{metrics}{$_} for keys %{ $r->{metrics} } }
            }
        }
        next unless $j->{status} eq 'success';
        if (my $env = $def->{environment}) {
            my %e = ref $env eq 'HASH' ? %$env : (name => $env);
            push @deploy, { environment => $e{name}, url => $e{url}, action => $e{action} // 'start', job => $j->{name} } if defined $e{name} && ($e{action} // 'start') ne 'prepare';
        }
        if (ref $def->{release} eq 'HASH') {   # the release: keyword (release-cli on GitLab): tag_name, name, description (text or a
            my $x = sub { my $s = shift // ''; $s =~ s/\$\{?(\w+)\}?/$rv{$1} \/\/ ''/ge; $s };   # file), milestones, assets: links
            my $rel = $def->{release};
            my %r = map { ($_ => $x->($rel->{$_})) } grep { !ref $rel->{$_} } keys %$rel;
            if (defined $r{description} && $r{description} !~ /\n/ && -f "$wt/$r{description}") { open my $fh, '<:raw', "$wt/$r{description}"; local $/; $r{description} = <$fh>; close $fh }
            $r{milestones} = [ grep { length } map { $x->($_) } GitLabCI::_list_of($rel->{milestones}) ] if $rel->{milestones};
            if (ref $rel->{assets} eq 'HASH' && ref $rel->{assets}{links} eq 'ARRAY') {
                $r{assets} = { links => [ map { my $l = $_; +{ map { ($_ => $x->($l->{$_})) } grep { !ref $l->{$_} } keys %$l } } grep { ref $_ eq 'HASH' } @{ $rel->{assets}{links} } ] };
            }
            push @release, \%r if length($r{tag_name} // '');
        }
        my $up = File::Spec->catdir($log, 'artifacts', GitLabCI::_safe($j->{name}), 'package-upload');
        if (-d $up) {                          # package-upload/NAME/VERSION/FILE: what ci/job.pl uploads with CI_JOB_TOKEN on GitLab
            for my $name (sort grep { !/^\./ } do { opendir(my $d1, $up); my @x = readdir $d1; closedir $d1; @x }) {
                for my $ver (sort grep { !/^\./ } do { opendir(my $d2, "$up/$name"); my @x = readdir $d2; closedir $d2; @x }) {
                    for my $f (sort grep { !/^\./ && -f "$up/$name/$ver/$_" } do { opendir(my $d3, "$up/$name/$ver"); my @x = readdir $d3; closedir $d3; @x }) {
                        eval { $self->package_put($P->{path_with_namespace}, $name, $ver, "$up/$name/$ver/$f"); 1 } or warn $@;
                    }
                }
            }
        }
        if ($j->{name} eq 'pages') {
            my $a = File::Spec->catdir($log, 'artifacts', GitLabCI::_safe($j->{name}), 'public');
            $pages = $a if -d $a;
        }
    }
    return (reports => \%rep, deploy => \@deploy, pages => $pages, release => \@release);
}
sub _target_reports {                         # the reports of the target branch's latest pipeline
    my ($self, $P, $t) = @_;
    my ($pl) = grep { $_->{ref} eq $t && $_->{reports} } reverse @{ $P->{pipelines} };
    $pl ? $pl->{reports} : {};
}
sub _mr_reports {                             # the MR widgets: test summary, code quality new/resolved vs target, metrics changes
    my ($self, $P, $m, $pl) = @_;
    my $r = $pl->{reports} or do { delete $m->{reports}; return };
    my $base = $self->_target_reports($P, $m->{target_branch});
    my %w;
    $w{junit} = $r->{junit} if $r->{junit};
    if ($r->{codequality}) {
        my %b = map { ($_->{fingerprint} => 1) } @{ $base->{codequality} // [] };
        my %h = map { ($_->{fingerprint} => 1) } @{ $r->{codequality} };
        $w{codequality} = { total => scalar @{ $r->{codequality} }, new => [ grep { !$b{ $_->{fingerprint} } } @{ $r->{codequality} } ],
                            resolved => [ grep { !$h{ $_->{fingerprint} } } @{ $base->{codequality} // [] } ] };
    }
    if ($r->{metrics}) {
        my $bm = $base->{metrics} // {};
        $w{metrics} = [ map { +{ name => $_, value => $r->{metrics}{$_}, previous => $bm->{$_} } } sort keys %{ $r->{metrics} } ];
    }
    $m->{reports} = \%w;
}
sub _deploy {
    my ($self, $P, $pl, %d) = @_;
    my $envs = $P->{environments} //= [];
    my ($e) = grep { $_->{name} eq $d{environment} } @$envs;
    push @$envs, $e = { id => $self->_id, name => $d{environment}, state => 'available', external_url => $d{url}, created_at => $self->now } unless $e;
    $e->{external_url} = $d{url} if $d{url};
    if ($d{action} eq 'stop') { $e->{state} = 'stopped'; return }
    $e->{state} = 'available';
    push @{ $P->{deployments} }, my $dep = { id => $self->_id, iid => ++$P->{iids}{deployment}, environment => { name => $e->{name} }, ref => $pl->{ref}, sha => $pl->{sha},
        status => 'success', created_at => $pl->{finished_at}, deployable => { name => $d{job}, pipeline => { id => $pl->{id} } }, user => { username => $self->{as} } };
    $e->{last_deployment} = { id => $dep->{id}, iid => $dep->{iid}, sha => $pl->{sha}, ref => $pl->{ref}, created_at => $dep->{created_at} };
    $dep;
}
sub _pages {
    my ($self, $P, $pl, $from) = @_;
    my $to = "$self->{local}/pages/$P->{path_with_namespace}";
    remove_tree($to);
    GitFlow::_copy_tree($from, $to) if eval { require GitFlow; 1 };
    my ($host) = $self->{base} =~ m{^\w+://([^/]+)};
    my ($top) = split m{/}, $P->{namespace};
    $P->{pages} = { url => "https://$top.pages." . ($host // 'gitlab.local') . "/$P->{path}/", path => $to, sha => $pl->{sha}, pipeline => $pl->{id}, updated_at => $pl->{finished_at} };
    $self->_deploy($P, $pl, environment => 'pages', url => $P->{pages}{url}, action => 'start', job => 'pages');
}

sub _mr_pipeline {
    my ($self, $P, $m) = @_;
    my ($s, $t) = @$m{qw(source_branch target_branch)};
    my $ssha = $self->_sha($P, "refs/heads/$s") // return;
    my $tsha = $self->_sha($P, "refs/heads/$t") // return;
    $m->{sha} = $ssha;
    my $prot = $self->_protected_branch($P, $s) ? 1 : 0;
    my ($pl, $conflict) = $self->_pipeline($P, sha => $tsha, merge_from => $ssha, source => 'merge_request_event', ref => "refs/merge-requests/$m->{iid}/merge",
        source_branch => $s, target => $t, mr_iid => $m->{iid}, protected => $prot, changed => $self->_changed($P, $tsha, $ssha),
        vars => { CI_MERGE_REQUEST_IID => $m->{iid}, CI_MERGE_REQUEST_ID => $m->{id}, CI_MERGE_REQUEST_TITLE => $m->{title}, CI_MERGE_REQUEST_SOURCE_BRANCH_NAME => $s,
                  CI_MERGE_REQUEST_TARGET_BRANCH_NAME => $t, CI_MERGE_REQUEST_SOURCE_BRANCH_SHA => $ssha, CI_MERGE_REQUEST_TARGET_BRANCH_SHA => $tsha,
                  CI_MERGE_REQUEST_DIFF_BASE_SHA => ($self->_git($self->_bare($P), {}, 'merge-base', $tsha, $ssha) =~ /([0-9a-f]{40})/)[0],
                  CI_MERGE_REQUEST_LABELS => join(',', @{ $m->{labels} }), CI_MERGE_REQUEST_EVENT_TYPE => 'merged_result',
                  CI_MERGE_REQUEST_PROJECT_PATH => $P->{path_with_namespace}, CI_MERGE_REQUEST_APPROVED => (@{ $m->{approved_by} } ? 'true' : 'false') });
    $m->{has_conflicts} = $conflict ? 1 : 0;
    if ($pl) { $pl->{source_sha} = $ssha; push @{ $m->{pipelines} }, $pl->{id} }
    else {                                    # no MR pipeline (jobs without rules join none): GitLab shows the branch pipeline
        ($pl) = grep { $_->{ref} eq $s && $_->{sha} eq $ssha && $_->{source} ne 'merge_request_event' } reverse @{ $P->{pipelines} };
        $pl //= $self->_push_pipeline($P, $s, undef, $ssha);
    }
    if ($pl) {
        $m->{head_pipeline} = { id => $pl->{id}, status => $pl->{status}, sha => $ssha, web_url => $pl->{web_url} };
        $m->{pipeline} = $m->{head_pipeline};
        $self->_mr_reports($P, $m, $pl);
    }
    $pl;
}
sub _open_mrs_for { my ($self, $P, $b) = @_; grep { $_->{state} eq 'opened' && $_->{source_branch} eq $b } @{ $P->{mrs} } }
sub _push_pipeline {
    my ($self, $P, $b, $before, $after) = @_;
    my @open = $self->_open_mrs_for($P, $b);
    my $changed = $before && $before ne $ZERO ? [ grep { length } split /\n/, $self->_git($self->_bare($P), {}, 'diff', '--name-only', $before, $after) ] : [];
    my ($pl) = $self->_pipeline($P, sha => $after, source => 'push', ref => $b, before => $before, changed => $changed, protected => ($self->_protected_branch($P, $b) ? 1 : 0),
        vars => { CI_COMMIT_BRANCH => $b, CI_COMMIT_BEFORE_SHA => $before // $ZERO, (@open ? (CI_OPEN_MERGE_REQUESTS => join(',', map { "$P->{path_with_namespace}!$_->{iid}" } @open)) : ()) });
    $pl;
}
sub _tag_pipeline {
    my ($self, $P, $tag) = @_;
    my $sha = $self->_sha($P, "refs/tags/$tag^{commit}") // return;
    my $prot = grep { _match_glob($_->{name}, $tag) } @{ $P->{protected_tags} };
    my ($msg) = $self->_git($self->_bare($P), {}, 'for-each-ref', '--format=%(contents)', "refs/tags/$tag");
    my ($pl) = $self->_pipeline($P, sha => $sha, source => 'push', ref => $tag, tag => 1, protected => $prot ? 1 : 0,
                                vars => { CI_COMMIT_TAG => $tag, CI_COMMIT_TAG_MESSAGE => $msg // '' });
    $pl;
}
sub _pushed {                                 # a push happened (the emulator has no daemon): run the pipelines GitLab would
    my ($self, $p, $ref) = @_;
    my $P = $self->_p($p);
    my @refs = defined $ref ? ($ref =~ m{^refs/} ? $ref : $self->_sha($P, "refs/heads/$ref") ? "refs/heads/$ref" : "refs/tags/$ref")
                            : (map { (split ' ', $_)[1] } grep { length } split /\n/, $self->_git($self->_bare($P), {}, 'for-each-ref', '--format=%(objectname) %(refname)'));
    my @pl;
    for my $r (@refs) {
        my $sha = $self->_sha($P, $r);
        my $old = $P->{seen}{$r};
        next if !$sha || (defined $old && $old eq $sha);
        $P->{seen}{$r} = $sha;
        if ($r =~ m{^refs/tags/(.+)$}) { push @pl, $self->_tag_pipeline($P, $1) // (); next }
        my ($b) = $r =~ m{^refs/heads/(.+)$} or next;
        push @pl, $self->_push_pipeline($P, $b, $old // $ZERO, $sha) // ();
        for my $m ($self->_open_mrs_for($P, $b)) { push @pl, $self->_mr_pipeline($P, $m) // () }
    }
    \@pl;
}
sub _run_pipeline {
    my ($self, $p, $ref, %o) = @_;
    my $P = $self->_p($p);
    my $src = $o{source} // 'web';
    if ($src eq 'merge_request_event' || $o{mr_iid}) { my $m = $self->_mr($P, $o{mr_iid} // die "GitLab: a merge request pipeline needs mr_iid\n"); return $self->_mr_pipeline($P, $m) }
    my $isb = $self->_sha($P, "refs/heads/$ref");
    my $ist = !$isb && $self->_sha($P, "refs/tags/$ref^{commit}");
    $isb || $ist or die "GitLab: no branch or tag '$ref' in $p (400 Reference not found)\n";
    if ($ist) {
        my ($pl) = $self->_pipeline($P, sha => $ist, source => $src, ref => $ref, tag => 1, vars => { CI_COMMIT_TAG => $ref, %{ $o{variables} // {} } }, protected => 1);
        return $pl;
    }
    my ($pl) = $self->_pipeline($P, sha => $isb, source => $src, ref => $ref, protected => ($self->_protected_branch($P, $ref) ? 1 : 0),
                                vars => { CI_COMMIT_BRANCH => $ref, %{ $o{variables} // {} } });
    $pl;
}
sub _create_tag {
    my ($self, $p, $name, $ref, $msg) = @_;
    my $P = $self->_p($p);
    die "GitLab: tag '$name' already exists in $p (400 Tag $name already exists)\n" if $self->_sha($P, "refs/tags/$name");
    my ($r) = grep { _match_glob($_->{name}, $name) } @{ $P->{protected_tags} };
    my $lvl = $self->_level($P, $self->{as});
    die "GitLab: you are not allowed to create this tag as it is protected (403 Forbidden)\n" if $r && ($r->{create_access_level} == 0 || $lvl < $r->{create_access_level});
    die "GitLab: you are not allowed to push code to this project (403 Forbidden)\n" if $lvl < 30;
    my $sha = $self->_sha($P, $ref) // $self->_sha($P, "refs/heads/$ref") // die "GitLab: no branch or commit '$ref' in $p (400 Target $ref is invalid)\n";
    $self->_git($self->_bare($P), { $self->_git_env($self->{as}) }, 'tag', (defined $msg && length $msg ? ('-a', '-m', $msg) : ()), $name, $sha);
    $P->{seen}{"refs/tags/$name"} = $sha;
    my $pl = $self->_tag_pipeline($P, $name);
    return { name => $name, target => $sha, message => $msg // '', commit => { id => $sha }, protected => $r ? 1 : 0, ($pl ? (pipeline => { id => $pl->{id}, status => $pl->{status} }) : ()) };
}

# ---------------------------------------------------------------- dry runs on the emulator: print the request, change nothing
# Every method that changes something is wrapped: with local => DIR and dry_run => 1 it takes the REST path, which
# prints `METHOD /api/v4/... {json}` and sends nothing; reads still answer from the emulator's state.
for my $m (qw(create_user create_group create_project update_project add_member set_variable create_label create_milestone update_milestone
              protect_branch protect_tag create_approval_rule create_issue update_issue add_note resolve_discussions link_issues create_mr approve_mr
              merge_mr run_pipeline create_tag create_branch create_release wiki_put package_put create_schedule update_schedule delete_schedule
              play_schedule pushed)) {
    no strict 'refs';
    no warnings 'redefine';
    my $orig = defined &{"GitLab::$m"} ? \&{"GitLab::$m"} : next;
    *{"GitLab::$m"} = sub {
        my $self = $_[0];
        return $orig->(@_) unless ref $self && $self->{local} && $self->{dry_run};
        local $self->{local};
        local $self->{url} = $self->{base};
        $orig->(@_);
    };
}

# ---------------------------------------------------------------- the live settings, and the drift against a project file
sub protected_branches {                      # -> [ { name, push_access_level, merge_access_level, allow_force_push, code_owner_approval_required } ]
    my ($self, $p) = @_;
    return [ map { +{ %$_ } } @{ $self->_p($p)->{protected_branches} } ] if $self->{local};
    my $lv = sub { my $l = shift // []; my ($x) = sort { $a <=> $b } map { $_->{access_level} // 0 } @$l; $x // 0 };
    [ map { +{ name => $_->{name}, push_access_level => $lv->($_->{push_access_levels}), merge_access_level => $lv->($_->{merge_access_levels}),
               allow_force_push => $_->{allow_force_push} ? 1 : 0, code_owner_approval_required => $_->{code_owner_approval_required} ? 1 : 0 } }
      @{ $self->_api('GET', '/projects/' . $self->_pid($p) . '/protected_branches', undef, all => 1) } ];
}
sub protected_tags {
    my ($self, $p) = @_;
    return [ map { +{ %$_ } } @{ $self->_p($p)->{protected_tags} } ] if $self->{local};
    [ map { my ($x) = sort { $a <=> $b } map { $_->{access_level} // 0 } @{ $_->{create_access_levels} // [] }; +{ name => $_->{name}, create_access_level => $x // 0 } }
      @{ $self->_api('GET', '/projects/' . $self->_pid($p) . '/protected_tags', undef, all => 1) } ];
}
sub approval_rules {                          # -> [ { name, approvals_required, users => [usernames] } ]
    my ($self, $p) = @_;
    return [ map { +{ %$_, users => [ @{ $_->{users} } ] } } @{ $self->_p($p)->{approval_rules} } ] if $self->{local};
    [ map { +{ name => $_->{name}, approvals_required => $_->{approvals_required}, users => [ map { $_->{username} } @{ $_->{users} // [] } ] } }
      @{ $self->_api('GET', '/projects/' . $self->_pid($p) . '/approval_rules', undef, all => 1) } ];
}
sub variables {                               # -> [ { key, value, protected, masked } ]
    my ($self, $p) = @_;
    return [ map { +{ %$_ } } sort { $a->{key} cmp $b->{key} } values %{ $self->_p($p)->{variables} } ] if $self->{local};
    $self->_api('GET', '/projects/' . $self->_pid($p) . '/variables', undef, all => 1);
}
sub members {                                 # -> { username => access level }, direct and inherited
    my ($self, $p) = @_;
    if ($self->{local}) { my $P = $self->_p($p); my %u = %{ $P->{members} }; my $ns = $P->{namespace};
        while (defined $ns && length $ns) { my $g = $self->{st}{groups}{$ns}; $u{$_} = $g->{members}{$_} for grep { ($g->{members}{$_} // 0) > ($u{$_} // 0) } keys %{ $g ? $g->{members} : {} }; $ns =~ s{/?[^/]*$}{} }
        return \%u }
    +{ map { ($_->{username} => $_->{access_level}) } @{ $self->_api('GET', '/projects/' . $self->_pid($p) . '/members/all', undef, all => 1) } };
}
sub diff_project_file {                       # diff_project_file(path) -> [ "[section] what: file X, live Y" ]; reads only
    my ($self, $path, %o) = @_;
    open my $fh, '<:raw', $path or die "GitLab: cannot read $path: $!\n";
    my $c = parse_project_file(do { local $/; <$fh> }, $path); close $fh;
    my %pr = map { ($_->[0] => $_->[1]) } @{ $c->{project} // [] };
    my $p = $o{project} // $pr{path} // die "$path: [project] needs path = group/name\n";
    my $proj = eval { $self->project($p) } or return [ "[project] $p: missing (setup creates it)" ];
    my @d;
    my %name = reverse %LEVEL; $name{0} = 'none'; $name{60} = 'admin';
    my $ln = sub { my $l = shift // 0; $name{$l} // $l };
    my $bool = sub { my $v = shift; ref $v ? ($v ? 1 : 0) : defined $v && $v =~ /^(1|true|yes|on)$/i ? 1 : 0 };
    my $live = $self->{local} ? { %{ $proj->{settings} // {} }, default_branch => $proj->{default_branch} } : $proj;
    for my $k (sort grep { $_ ne 'path' } keys %pr) {
        my ($f, $l) = ($pr{$k}, $live->{$k});
        my $same = $f =~ /^(true|false|yes|no|on|off)$/i || ref $l || (defined $l && $l =~ /^[01]$/) ? $bool->($f) == $bool->($l) : ($l // '') eq $f;
        push @d, "[project] $k: file $f, live " . (ref $l ? ($l ? 'true' : 'false') : $l // '(unset)') unless $same;
    }
    my $mem = $self->members($p);
    my %fm;
    for (@{ $c->{members} // [] }) { my $want = level_of($_->[1]); $fm{ $_->[0] } = 1;
        my $have = $mem->{ $_->[0] };
        push @d, !defined $have ? "[members] $_->[0]: missing (file $_->[1])" : $have != $want ? "[members] $_->[0]: file $_->[1], live " . $ln->($have) : () }
    push @d, map { "[members] $_: live only (" . $ln->($mem->{$_}) . ')' } grep { !$fm{$_} && $_ ne 'root' } sort keys %$mem if $c->{members};
    my %ll = map { ($_->{name} => $_) } @{ $self->labels($p) };
    for (@{ $c->{labels} // [] }) {
        my ($color, $desc) = $_->[1] =~ /^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$/ or die "$path:$_->[2]: label value is '#RRGGBB | description'\n";
        my $l = delete $ll{ $_->[0] };
        if (!$l) { push @d, "[labels] $_->[0]: missing"; next }
        push @d, "[labels] $_->[0]: color file $color, live $l->{color}" if lc $color ne lc($l->{color} // '');
        push @d, "[labels] $_->[0]: description differs" if ($desc // '') ne ($l->{description} // '');
    }
    push @d, map { "[labels] $_: live only" } sort keys %ll if $c->{labels};
    my %lm = map { ($_->{title} => $_) } @{ $self->milestones($p) };
    for (@{ $c->{milestones} // [] }) {
        my @want;
        if ($_->[0] eq 'sprints') {
            my ($start, $count, $weeks, $prefix) = split ' ', $_->[1], 4;
            my $t0 = _epoch($start); $weeks //= 2; $prefix //= 'Sprint ';
            @want = map { my $s0 = $t0 + ($_ - 1) * $weeks * 7 * 86400; [ "$prefix$_", _date($s0), _date($s0 + ($weeks * 7 - 3) * 86400) ] } 1 .. $count;
        } else { my ($dates) = split /\s*\|\s*/, $_->[1], 2; my ($s0, $d0) = split ' ', $dates // ''; @want = ([ $_->[0], $s0, $d0 ]) }
        for my $w (@want) {
            my $m = $lm{ $w->[0] };
            if (!$m) { push @d, "[milestones] $w->[0]: missing"; next }
            push @d, "[milestones] $w->[0]: dates file " . ($w->[1] // '') . '..' . ($w->[2] // '') . ", live " . ($m->{start_date} // '') . '..' . ($m->{due_date} // '')
                if ($w->[1] // '') ne ($m->{start_date} // '') || ($w->[2] // '') ne ($m->{due_date} // '');
        }
    }
    my %pb = map { ($_->{name} => $_) } @{ $self->protected_branches($p) };
    for (@{ $c->{branches} // [] }) {
        my %a = map { /^(\w+):(\S+)$/ ? (lc $1 => lc $2) : () } split ' ', $_->[1];
        my $b = delete $pb{ $_->[0] };
        if (!$b) { push @d, "[branches] $_->[0]: not protected"; next }
        for (['push', 'push_access_level'], ['merge', 'merge_access_level']) {
            my $want = level_of($a{ $_->[0] } // 'maintainer');
            push @d, "[branches] $b->{name}: $_->[0] file " . $ln->($want) . ", live " . $ln->($b->{ $_->[1] }) if $want != ($b->{ $_->[1] } // 0);
        }
        push @d, "[branches] $b->{name}: force file " . ($a{force} // 'no') . ', live ' . ($b->{allow_force_push} ? 'yes' : 'no') if (($a{force} // 'no') eq 'yes' ? 1 : 0) != ($b->{allow_force_push} ? 1 : 0);
        push @d, "[branches] $b->{name}: codeowners file " . ($a{codeowners} // 'no') . ', live ' . ($b->{code_owner_approval_required} ? 'yes' : 'no')
            if (($a{codeowners} // 'no') eq 'yes' ? 1 : 0) != ($b->{code_owner_approval_required} ? 1 : 0);
    }
    push @d, map { "[branches] $_: protected live only" } sort keys %pb if $c->{branches};
    my %pt = map { ($_->{name} => $_) } @{ $self->protected_tags($p) };
    for (@{ $c->{tags} // [] }) {
        my ($lvl) = $_->[1] =~ /^create:(\S+)$/;
        my $t = delete $pt{ $_->[0] };
        if (!$t) { push @d, "[tags] $_->[0]: not protected"; next }
        push @d, "[tags] $_->[0]: create file $lvl, live " . $ln->($t->{create_access_level}) if level_of($lvl // 'maintainer') != ($t->{create_access_level} // 0);
    }
    push @d, map { "[tags] $_: protected live only" } sort keys %pt if $c->{tags};
    my %ar = map { ($_->{name} => $_) } @{ $self->approval_rules($p) };
    for (@{ $c->{approvals} // [] }) {
        my ($n, @users) = split ' ', $_->[1];
        my $r = delete $ar{ $_->[0] };
        if (!$r) { push @d, "[approvals] $_->[0]: missing"; next }
        push @d, "[approvals] $_->[0]: file $n required, live $r->{approvals_required}" if $n != $r->{approvals_required};
        push @d, "[approvals] $_->[0]: users file @{[ sort @users ]}, live @{[ sort @{ $r->{users} } ]}" if join(' ', sort @users) ne join(' ', sort @{ $r->{users} });
    }
    push @d, map { "[approvals] $_: live only" } sort keys %ar if $c->{approvals};
    my %vr = map { ($_->{key} => $_) } @{ $self->variables($p) };
    for (@{ $c->{variables} // [] }) {
        my ($v) = split /\s+\|\s+/, $_->[1];
        my $x = delete $vr{ $_->[0] };
        push @d, !$x ? "[variables] $_->[0]: missing" : ($x->{value} // '') ne $v ? "[variables] $_->[0]: value differs" : ();
    }
    push @d, map { "[variables] $_: live only" } sort keys %vr if $c->{variables};
    my %sc = map { ($_->{description} => $_) } @{ $self->schedules($p) };
    for (@{ $c->{schedules} // [] }) {
        my ($cron, $ref, $tz, $vars) = map { s/^\s+|\s+$//gr } split /\|/, $_->[1], 4;
        $tz = 'UTC' unless defined $tz && length $tz;
        my $s = delete $sc{ $_->[0] };
        if (!$s) { push @d, "[schedules] $_->[0]: missing"; next }
        $s = $self->_api('GET', '/projects/' . $self->_pid($p) . "/pipeline_schedules/$s->{id}") if !$self->{local} && !$self->{dry_run};
        push @d, "[schedules] $_->[0]: cron file $cron, live $s->{cron}" if $cron ne $s->{cron};
        push @d, "[schedules] $_->[0]: ref file $ref, live $s->{ref}" if $ref ne ($s->{ref} =~ s{^refs/heads/}{}r);
        push @d, "[schedules] $_->[0]: time zone file $tz, live $s->{cron_timezone}" if $tz ne $s->{cron_timezone};
        my $fv = join ' ', sort split ' ', $vars // '';
        my $lv = join ' ', sort map { "$_->{key}=$_->{value}" } @{ $s->{variables} // [] };
        push @d, "[schedules] $_->[0]: variables file '$fv', live '$lv'" if $fv ne $lv;
    }
    push @d, map { "[schedules] $_: live only" } sort keys %sc if $c->{schedules};
    \@d;
}

1;
