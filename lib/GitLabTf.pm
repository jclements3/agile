package GitLabTf;
# project.conf -> Terraform/OpenTofu for the GitLab project: the same settings `gitlab.pl setup` applies, as code a
# platform team can plan in a merge request and apply from its pipeline. Core Perl; no terraform binary needed.
#
#   my $files = GitLabTf::generate($conf_text, file => 'project.conf', url => 'https://gitlab.example.gov');
#   # -> { 'versions.tf' => ..., 'project.tf' => ..., 'variables.tf' => ..., 'backend.hcl' => ..., 'README.md' => ... }
#
# Written against the gitlabhq/gitlab provider 19.4 (registry, 2026-10-03) and Terraform 1.5+ / OpenTofu 1.6+ (the
# import block). Resources: gitlab_project (adopted with an import block: setup or the UI made it), gitlab_project_membership
# (users looked up with data gitlab_user), gitlab_project_label, gitlab_project_milestone, gitlab_branch_protection,
# gitlab_tag_protection, gitlab_project_approval_rule, gitlab_project_variable (values are Terraform variables, never in
# the files), gitlab_pipeline_schedule + gitlab_pipeline_schedule_variable (ref as refs/heads/NAME, as the provider
# requires), gitlab_project_issue_board (lists by label_id; position follows the order of the lists, as the provider
# computes it). Not in the provider, so left to `gitlab.pl setup`: the iteration cadence ([iterations]; GitLab changes
# it only through GraphQL), the generated .gitlab/insights.yml ([insights]; a repository file goes through a merge
# request, not an apply) and [windchill] (not a GitLab setting).
#
# State: GitLab-managed Terraform state over the http backend. versions.tf has an empty `backend "http" {}`: in CI
# the OpenTofu component fills it in; on a workstation `tofu init -backend-config=backend.hcl` with TF_HTTP_PASSWORD
# set to a token (scope api). The state address uses the URL-encoded project path; the numeric project id works too.
use strict;
use warnings;
use GitLab ();

my %LEVEL = (none => 'no one', 'no one' => 'no one', noone => 'no one', guest => 'guest', reporter => 'reporter', developer => 'developer',
             maintainer => 'maintainer', owner => 'owner', admin => 'admin');
my %BOARD_MS = (none => 0, any => -1, upcoming => -2, started => -3);

sub _q { my $s = shift // ''; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\$\{/\$\${/g; $s =~ s/%\{/%%{/g; $s =~ s/\n/\\n/g; qq("$s") }
sub _id { my $s = lc shift; $s =~ s/[^a-z0-9_]+/_/g; $s =~ s/^_+|_+$//g; $s = "_$s" if $s =~ /^\d/; length $s ? $s : 'x' }
sub _bool { my $v = shift // ''; $v =~ /^(1|true|yes|on)$/i ? 'true' : 'false' }
sub _level { my ($v, $where) = @_; $LEVEL{ lc $v } // die "$where: '$v' is not an access level Terraform knows (none, developer, maintainer, admin)\n" }
sub _enc { GitLab::_enc(shift) }

sub generate {                                # generate(TEXT, file => F, url => URL, state => NAME) -> { filename => text }
    my ($text, %o) = @_;
    my $file = $o{file} // 'project.conf';
    my $c = GitLab::parse_project_file($text, $file);
    my %pr = map { ($_->[0] => $_->[1]) } @{ $c->{project} // [] };
    my $p = $pr{path} // die "$file: [project] needs path = group/name\n";
    my ($ns, $name) = $p =~ m{^(.+)/([^/]+)$} or die "$file: [project] path must be GROUP/NAME, not '$p'\n";
    my $url = ($o{url} // 'https://gitlab.example.com') =~ s{/+$}{}r;
    my $state = $o{state} // 'gitlab-project';
    my (@tf, %users, @vars, @skipped);
    my $user = sub { my $u = shift; $users{$u} = 1; "data.gitlab_user." . _id($u) . ".id" };

    # the project and its settings
    my %set = map { ($_ => $pr{$_}) } grep { !/^(path|visibility)$/ } keys %pr;
    my @bool = qw(only_allow_merge_if_pipeline_succeeds only_allow_merge_if_all_discussions_are_resolved remove_source_branch_after_merge);
    push @tf, "# The project. It already exists (gitlab.pl setup or the UI made it): the import block adopts it on the first apply.\n"
            . "import {\n  to = gitlab_project.this\n  id = " . _q($p) . "\n}\n\n"
            . "data \"gitlab_group\" \"ns\" {\n  full_path = " . _q($ns) . "\n}\n\n"
            . "resource \"gitlab_project\" \"this\" {\n  name         = " . _q($name) . "\n  path         = " . _q($name) . "\n  namespace_id = data.gitlab_group.ns.group_id\n"
            . ($pr{visibility} ? "  visibility_level = " . _q($pr{visibility}) . "\n" : '')
            . join('', map { my $k = $_; my $v = $set{$k}; "  $k = " . ((grep { $_ eq $k } @bool) || $v =~ /^(true|false)$/i ? _bool($v) : _q($v)) . "\n" } sort keys %set)
            . "}\n\nlocals {\n  project = gitlab_project.this.id\n}\n";

    for (@{ $c->{members} // [] }) {
        push @tf, "resource \"gitlab_project_membership\" \"" . _id($_->[0]) . "\" {\n  project      = local.project\n  user_id      = " . $user->($_->[0])
                . "\n  access_level = " . _q(_level($_->[1], "$file:$_->[2]")) . "\n}\n";
    }
    if (@{ $c->{labels} // [] }) {             # one map, one resource with for_each: the labels stay readable as a table
        my @l;
        for (@{ $c->{labels} }) {
            my ($color, $desc) = $_->[1] =~ /^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$/ or die "$file:$_->[2]: label value is '#RRGGBB | description'\n";
            push @l, "    " . _q($_->[0]) . " = { color = " . _q($color) . ", description = " . _q($desc // '') . " }\n";
        }
        push @tf, "locals {\n  labels = {\n" . join('', @l) . "  }\n}\n\nresource \"gitlab_project_label\" \"this\" {\n  for_each    = local.labels\n  project     = local.project\n"
                . "  name        = each.key\n  color       = each.value.color\n  description = each.value.description\n}\n";
    }
    my @ms;
    for (@{ $c->{milestones} // [] }) {
        if ($_->[0] eq 'sprints') {
            my ($start, $count, $weeks, $prefix) = split ' ', $_->[1], 4;
            $weeks //= 2; $prefix //= 'Sprint ';
            my $t0 = GitLab::_epoch($start);
            for my $k (1 .. $count) {
                my $s = $t0 + ($k - 1) * $weeks * 7 * 86400; my $d = $s + ($weeks * 7 - 3) * 86400;
                push @ms, [ "$prefix$k", GitLab::_date($s), GitLab::_date($d), "Two-week sprint $k: planning on " . GitLab::_date($s) . ', review and retrospective on ' . GitLab::_date($d) . '.' ];
            }
        } else {
            my ($dates, $desc) = split /\s*\|\s*/, $_->[1], 2;
            my ($s, $d) = split ' ', $dates // '';
            push @ms, [ $_->[0], $s, $d, $desc // '' ];
        }
    }
    if (@ms) {
        push @tf, "locals {\n  milestones = {\n" . join('', map { "    " . _q($_->[0]) . " = { start = " . _q($_->[1] // '') . ", due = " . _q($_->[2] // '') . ", description = " . _q($_->[3]) . " }\n" } @ms)
                . "  }\n}\n\nresource \"gitlab_project_milestone\" \"this\" {\n  for_each    = local.milestones\n  project     = local.project\n  title       = each.key\n"
                . "  start_date  = each.value.start != \"\" ? each.value.start : null\n  due_date    = each.value.due != \"\" ? each.value.due : null\n  description = each.value.description\n}\n";
    }
    for (@{ $c->{branches} // [] }) {
        my %a = map { /^(\w+):(\S+)$/ ? (lc $1 => lc $2) : die "$file:$_->[2]: branch rule words are push:LEVEL merge:LEVEL force:yes|no codeowners:yes|no\n" } split ' ', $_->[1];
        push @tf, "resource \"gitlab_branch_protection\" \"" . _id($_->[0]) . "\" {\n  project                      = local.project\n  branch                       = " . _q($_->[0])
                . "\n  push_access_level            = " . _q(_level($a{push} // 'maintainer', "$file:$_->[2]")) . "\n  merge_access_level           = " . _q(_level($a{merge} // 'maintainer', "$file:$_->[2]"))
                . "\n  allow_force_push             = " . _bool(($a{force} // 'no') eq 'yes') . "\n  code_owner_approval_required = " . _bool(($a{codeowners} // 'no') eq 'yes') . "\n}\n";
    }
    for (@{ $c->{tags} // [] }) {
        my ($lvl) = $_->[1] =~ /^create:(\S+)$/ or die "$file:$_->[2]: tag rule is create:LEVEL\n";
        push @tf, "resource \"gitlab_tag_protection\" \"" . _id($_->[0]) . "\" {\n  project             = local.project\n  tag                 = " . _q($_->[0])
                . "\n  create_access_level = " . _q(_level($lvl, "$file:$_->[2]")) . "\n}\n";
    }
    for (@{ $c->{approvals} // [] }) {
        my ($n, @u) = split ' ', $_->[1];
        $n =~ /^\d+$/ or die "$file:$_->[2]: approval rule is N user user ...\n";
        push @tf, "resource \"gitlab_project_approval_rule\" \"" . _id($_->[0]) . "\" {\n  project            = local.project\n  name               = " . _q($_->[0])
                . "\n  approvals_required = $n\n  user_ids           = [" . join(', ', map { $user->($_) } @u) . "]\n}\n";
    }
    for (@{ $c->{variables} // [] }) {
        my ($v, @fl) = split /\s+\|\s+/, $_->[1];
        my %f = map { (lc $_ => 1) } @fl;
        my $tv = 'ci_' . _id($_->[0]);
        push @vars, [ $tv, $_->[0], $f{masked} ];
        push @tf, "resource \"gitlab_project_variable\" \"" . _id($_->[0]) . "\" {\n  project   = local.project\n  key       = " . _q($_->[0])
                . "\n  value     = var.$tv\n  protected = " . _bool($f{protected}) . "\n  masked    = " . _bool($f{masked}) . "\n}\n";
    }
    for (@{ $c->{schedules} // [] }) {
        my ($cron, $ref, $tz, $vars) = map { s/^\s+|\s+$//gr } split /\|/, $_->[1], 4;
        defined $ref && length $ref && defined $cron && length $cron or die "$file:$_->[2]: a schedule is CRON | REF [| TZ [| K=V ...]]\n";
        my $id = _id($_->[0]);
        push @tf, "resource \"gitlab_pipeline_schedule\" \"$id\" {\n  project       = local.project\n  description   = " . _q($_->[0]) . "\n  ref           = " . _q($ref =~ m{^refs/} ? $ref : "refs/heads/$ref")
                . "\n  cron          = " . _q($cron) . "\n  cron_timezone = " . _q(defined $tz && length $tz ? $tz : 'UTC') . "\n  active        = true\n}\n";
        for my $kv (split ' ', $vars // '') {
            my ($k, $v) = $kv =~ /^([A-Za-z_]\w*)=(.*)$/ or die "$file:$_->[2]: schedule variables are KEY=VALUE, not '$kv'\n";
            push @tf, "resource \"gitlab_pipeline_schedule_variable\" \"${id}_" . _id($k) . "\" {\n  project              = local.project\n  pipeline_schedule_id = gitlab_pipeline_schedule.$id.pipeline_schedule_id"
                    . "\n  key                  = " . _q($k) . "\n  value                = " . _q($v) . "\n}\n";
        }
    }
    my $it = GitLab::parse_iterations($c->{iterations}, $file, $p);
    for (@{ $c->{boards} // [] }) {
        my $w = GitLab::parse_board_line($_->[1], "$file:$_->[2]", $it->{use});
        my %known = map { ($_->[0] => 1) } @{ $c->{labels} // [] };
        for my $l (@{ $w->{labels} }) { $known{$l} or die "$file:$_->[2]: board $_->[0] lists label '$l', which [labels] does not define\n" }
        my $ms = $w->{milestone};
        my $mline = exists $BOARD_MS{$ms} ? ($ms eq 'any' ? '' : "  milestone_id = $BOARD_MS{$ms} # GitLab's predefined timebox id for \"$ms\" (Premium/Ultimate)\n")
                  : "  milestone_id = gitlab_project_milestone.this[" . _q($ms) . "].milestone_id\n";
        push @tf, "resource \"gitlab_project_issue_board\" \"" . _id($_->[0]) . "\" {\n  project = local.project\n  name    = " . _q($_->[0]) . "\n" . $mline
                . ($w->{iteration} ne 'any' ? "  # iteration=$w->{iteration}: the provider sets a board's iteration scope only per list; gitlab.pl setup sets it (GraphQL)\n" : '')
                . join('', map { "  lists {\n    label_id = gitlab_project_label.this[" . _q($_) . "].label_id\n  }\n" } @{ $w->{labels} }) . "}\n";
    }
    push @skipped, '[iterations] (the iteration cadence: not in the gitlab provider; gitlab.pl setup makes it through GraphQL)' if @{ $it->{cadences} };
    push @skipped, '[insights] (.gitlab/insights.yml is a repository file: commit it through a merge request; gitlab.pl insights prints it)' if $c->{insights};
    push @skipped, '[windchill] (the Windchill intake mapping is not a GitLab setting)' if $c->{windchill};

    my $users = join '', map { "data \"gitlab_user\" \"" . _id($_) . "\" {\n  username = " . _q($_) . "\n}\n\n" } sort keys %users;
    my $head = "# Generated by gitlab.pl terraform from $file -- edit the project file and regenerate, not these files.\n";
    my %out;
    $out{'versions.tf'} = $head . <<"EOF";
terraform {
  required_version = ">= 1.5" # Terraform 1.5+ or OpenTofu 1.6+ (import blocks)
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 19.4" # written against 19.4.1 (2026-10-03); the major version follows GitLab's
    }
  }
  # GitLab-managed state. In CI the OpenTofu component configures it; on a workstation:
  #   tofu init -backend-config=backend.hcl     (TF_HTTP_PASSWORD = a token with scope api)
  backend "http" {}
}

provider "gitlab" {
  # token from GITLAB_TOKEN; the server from GITLAB_BASE_URL (for example $url/api/v4/)
}
EOF
    $out{'project.tf'} = $head . "# Project " . $p . ".\n\n" . $users . join("\n", @tf)
        . (@skipped ? "\n# Not managed here:\n" . join('', map { "#   $_\n" } @skipped) : '');
    $out{'variables.tf'} = $head . (@vars ? join("\n", map { "variable \"$_->[0]\" {\n  description = " . _q("CI/CD variable $_->[1]: set TF_VAR_$_->[0] or a .tfvars file kept out of git") . "\n  type        = string\n"
        . ($_->[2] ? "  sensitive   = true\n" : '') . "}\n" } @vars) : "# no CI/CD variables in the project file\n");
    my $addr = "$url/api/v4/projects/" . _enc($p) . "/terraform/state/$state";
    $out{'backend.hcl'} = "# tofu init -backend-config=backend.hcl   (state \"$state\" of $p; the numeric project id works in place of the path)\n"
        . "address        = " . _q($addr) . "\nlock_address   = " . _q("$addr/lock") . "\nunlock_address = " . _q("$addr/lock") . "\n"
        . "lock_method    = \"POST\"\nunlock_method  = \"DELETE\"\nretry_wait_min = 5\n# username = your GitLab user; the password comes from TF_HTTP_PASSWORD (never in this file)\n";
    $out{$_} = _align($out{$_}) for grep { /\.(tf|hcl)$/ } keys %out;
    \%out;
}
sub _align {                                  # what `terraform fmt` does to our output: align the = of consecutive attributes at one indent
    my $t = shift;
    my @l = split /\n/, $t, -1;
    my $i = 0;
    while ($i < @l) {
        my ($ind) = $l[$i] =~ /^(\s*)(?:"[^"]*"|[\w.-]+)\s*= /;
        if (!defined $ind) { $i++; next }
        my $j = $i;
        my @g;
        while ($j < @l && $l[$j] =~ /^(\s*)("[^"]*"|[\w.-]+)\s*= (.*)$/ && $1 eq $ind) { push @g, [ $2, $3 ]; $j++; last if $3 =~ /[{\[]\s*$/ }
        my $w = 0; for (@g) { $w = length $_->[0] if length $_->[0] > $w }
        $l[ $i + $_ ] = $ind . $g[$_][0] . (' ' x ($w - length $g[$_][0])) . ' = ' . $g[$_][1] for 0 .. $#g;
        $i = $j > $i ? $j : $i + 1;
    }
    join "\n", @l;
}
sub resources {                               # HCL text -> [ "TYPE.NAME" ] of resource blocks (the round-trip check)
    my $t = shift;
    my @r;
    push @r, "$1.$2" while $t =~ /^resource "(\w+)" "(\w+)" \{/mg;
    \@r;
}

1;
