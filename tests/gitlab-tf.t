#!/usr/bin/perl
# perl tests/gitlab-tf.t -- lib/GitLabTf.pm and `gitlab.pl terraform` (project.conf -> Terraform/OpenTofu for the
# gitlabhq/gitlab provider), the OpenTofu CI include, and the Kubernetes runner files (tools/gitlab/k8s, the mbse-ci
# Dockerfile). No terraform binary is needed: the HCL is checked as text against every project.conf section it claims;
# when terraform is on the PATH, `terraform fmt` checks it too, and `terraform validate` runs if the provider can be
# downloaded (otherwise it is skipped, and said so).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use GitLab;
use GitLabTf;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++; $got //= '(undef)';
    if ($got eq $want) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like { my ($name, $got, $re) = @_; $n++; $got //= '(undef)';
    if ($got =~ $re) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $re\n" } }
sub unlike_ { my ($name, $got, $re) = @_; $n++; if (($got // '') !~ $re) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n#   matched: $re\n" } }
sub dies { my ($name, $code, $re) = @_; eval { $code->(); 1 } ? like($name, 'lived', $re) : like($name, $@, $re) }
sub slurp { my $p = shift; open my $fh, '<:raw', $p or return ''; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "$p: $!"; print $fh $t; close $fh }
sub which { my $p = shift; for (split /:/, $ENV{PATH} // '') { return "$_/$p" if -x "$_/$p" || -x "$_/$p.exe" } undef }

my $ROOT = "$FindBin::Bin/..";
my $T = tempdir(CLEANUP => 1);
my $conf = "$ROOT/tools/gitlab/templates/project.conf";
my $text = slurp($conf);
my $c = GitLab::parse_project_file($text, $conf);
my $f = GitLabTf::generate($text, file => 'project.conf', url => 'https://gitlab.example.gov/');
my $tf = $f->{'project.tf'};

# ---------------------------------------------------------------- the files
check('terraform: four files', join(' ', sort keys %$f), 'backend.hcl project.tf variables.tf versions.tf');
like('terraform: the provider is pinned', $f->{'versions.tf'}, qr/source  = "gitlabhq\/gitlab"\n\s+version = "~> 19\.4"/);
like('terraform: GitLab-managed state, an empty http backend', $f->{'versions.tf'}, qr/^  backend "http" \{\}$/m);
like('terraform: the state URLs come from the project path', $f->{'backend.hcl'},
     qr{^address        = "https://gitlab\.example\.gov/api/v4/projects/tidewater%2Fmodel/terraform/state/gitlab-project"\nlock_address   = "[^"]+/lock"\nunlock_address = "[^"]+/lock"\nlock_method    = "POST"\nunlock_method  = "DELETE"\n}m);
unlike_('terraform: no password or token in any file', join('', values %$f), qr/glpat-|glrt-|password\s*=|token\s*=\s*"/);
like('terraform: the existing project is adopted by an import block', $tf, qr/^import \{\n  to = gitlab_project\.this\n  id = "tidewater\/model"\n\}$/m);
like('terraform: project settings', $tf, qr/^  merge_method\s+= "merge"$(?s:.*)^  only_allow_merge_if_pipeline_succeeds\s+= true$/m);

# ---------------------------------------------------------------- round trip: every section the generator claims
my %res;
for (@{ GitLabTf::resources($tf) }) { my ($type) = split /\./; $res{$type}++ }
my $count = sub { my $s = shift; scalar @{ $c->{$s} // [] } };
check('round trip: one membership per [members] line', $res{gitlab_project_membership} // 0, $count->('members'));
my ($labels) = $tf =~ /^  labels = \{\n(.*?)^  \}$/ms;
check('round trip: every [labels] line is in the label map', scalar(() = $labels =~ /^    "[^"]+"\s+= \{ color/mg), $count->('labels'));
check('round trip: the label map keeps each colour and description', ($labels =~ /^    "source::windchill"\s+= \{ color = "#3E6E8E", description = "A request submitted in Windchill; the Windchill number starts the title \(gitlab\.pl windchill intake\)" \}$/m) ? 1 : 0, 1);
my ($ms) = $tf =~ /^  milestones = \{\n(.*?)^  \}$/ms;
check('round trip: the sprints line expands to its 39 milestones', scalar(() = $ms =~ /^    "Sprint \d+"/mg), 39);
my %live = map { ($_->{title} => $_) } do { my $g = GitLab->new(local => "$T/gl", now => '2026-10-05T09:00:00Z'); $g->create_group('tidewater'); $g->create_project('tidewater/model'); $g->sprints('tidewater/model', '2026-10-05', 39) };
my %tfm = map { ($1 => "$2 $3") } $ms =~ /^    "(Sprint \d+)"\s+= \{ start = "(\S+)", due = "(\S+)"/mg;
check('round trip: every sprint has the dates gitlab.pl setup gives it', join(' ', grep { $tfm{$_} ne "$live{$_}{start_date} $live{$_}{due_date}" } sort keys %tfm), '');
check('round trip: one branch protection per [branches] line', $res{gitlab_branch_protection} // 0, $count->('branches'));
like('round trip: "push:none" is the provider\'s "no one"', $tf, qr/resource "gitlab_branch_protection" "develop" \{\n(?:.*\n)*?  push_access_level\s+= "no one"\n  merge_access_level\s+= "developer"\n  allow_force_push\s+= false\n  code_owner_approval_required = true\n/);
check('round trip: one tag protection per [tags] line', $res{gitlab_tag_protection} // 0, $count->('tags'));
check('round trip: approval rules, users looked up by name', join(' ', $res{gitlab_project_approval_rule} // 0, $tf =~ /user_ids\s+= \[data\.gitlab_user\.jim\.id, data\.gitlab_user\.bob\.id\]/ ? 'users' : 'no users'), $count->('approvals') . ' users');
check('round trip: one CI/CD variable per [variables] line, its value a Terraform variable', join(' ', $res{gitlab_project_variable} // 0, scalar(() = $f->{'variables.tf'} =~ /^variable "ci_/mg)), $count->('variables') . ' ' . $count->('variables'));
like('round trip: a variable\'s value is never written', $tf, qr/key\s+= "KIT"\n  value\s+= var\.ci_kit\n/);
check('round trip: one schedule per [schedules] line, ref as refs/heads/', join(' ', $res{gitlab_pipeline_schedule} // 0, scalar(() = $tf =~ /ref\s+= "refs\/heads\/develop"/g)), $count->('schedules') . ' ' . $count->('schedules'));
like('round trip: schedule variables', $tf, qr/resource "gitlab_pipeline_schedule_variable" "nightly_full_check_full" \{\n(?:.*\n)*?  pipeline_schedule_id = gitlab_pipeline_schedule\.nightly_full_check\.pipeline_schedule_id\n  key\s+= "FULL"\n  value\s+= "1"\n/);
check('round trip: one board per [boards] line', $res{gitlab_project_issue_board} // 0, $count->('boards'));
like('round trip: board lists by label id, in order; sprint=current is the Started milestone (-3)', $tf,
     qr/resource "gitlab_project_issue_board" "sprint" \{\n  project\s+= local\.project\n  name\s+= "Sprint"\n  milestone_id = -3 [^\n]*\n  lists \{\n    label_id = gitlab_project_label\.this\["workflow::ready"\]\.label_id\n  \}\n  lists \{\n    label_id = gitlab_project_label\.this\["workflow::in-progress"\]/);
like('round trip: what the provider cannot do is said, not dropped', $tf, qr/^# Not managed here:\n#   \[insights\] .*\n#   \[windchill\] /m);

# ---------------------------------------------------------------- other project files
my $small = "[project]\npath = acme/x\n[labels]\na = #111111\n[milestones]\nPDR = 2026-11-02 2026-11-20 | Preliminary design review\n[iterations]\ngroup = acme\nSprints = 2026-10-05 2 4\n[boards]\nB = a | milestone=PDR\n";
my $s = GitLabTf::generate($small, file => 's.conf');
like('terraform: a board scoped to a named milestone refers to it', $s->{'project.tf'}, qr/milestone_id = gitlab_project_milestone\.this\["PDR"\]\.milestone_id/);
like('terraform: a dated milestone keeps its description', $s->{'project.tf'}, qr/"PDR" = \{ start = "2026-11-02", due = "2026-11-20", description = "Preliminary design review" \}/);
like('terraform: the iteration cadence is left to setup, and said', $s->{'project.tf'}, qr/#   \[iterations\] \(the iteration cadence: not in the gitlab provider; gitlab\.pl setup makes it through GraphQL\)/);
like('terraform: no CI/CD variables -> a note, not an empty file', $s->{'variables.tf'}, qr/# no CI\/CD variables in the project file/);
like('terraform: strings are escaped for HCL', GitLabTf::generate("[project]\npath = a/b\n[labels]\nx = #000000 | say \"hi\" \${not} %{this}\n")->{'project.tf'}, qr/description = "say \\"hi\\" \$\$\{not\} %%\{this\}"/);
dies('terraform: a board list needs a defined label', sub { GitLabTf::generate("[project]\npath = a/b\n[boards]\nB = nope\n", file => 'f') }, qr/^f:4: board B lists label 'nope', which \[labels\] does not define/);
dies('terraform: an unknown access level', sub { GitLabTf::generate("[project]\npath = a/b\n[members]\nbob = boss\n", file => 'f') }, qr/^f:4: 'boss' is not an access level Terraform knows/);
dies('terraform: the project path needs a group', sub { GitLabTf::generate("[project]\npath = lonely\n", file => 'f') }, qr/^f: \[project\] path must be GROUP\/NAME, not 'lonely'/);

# ---------------------------------------------------------------- the CLI
my $cli = sub { my $o = qx("$^X" "$ROOT/bin/gitlab.pl" @_ 2>&1); ($o, $? >> 8) };
my ($o, $rc) = $cli->('terraform', qq("$conf"), '--out', qq("$T/tf"), '--url', 'https://gitlab.example.gov');
like('cli: terraform --out writes the files', "$rc $o", qr/^0 backend\.hcl, project\.tf, variables\.tf, versions\.tf -> \S+ \(\d+ resources\)$/);
check('cli: the same files as the library (but for the file name in the header)', slurp("$T/tf/project.tf") =~ s/\A[^\n]*\n//r, $f->{'project.tf'} =~ s/\A[^\n]*\n//r);
($o, $rc) = $cli->('terraform', qq("$conf"));
like('cli: without --out the files go to stdout', "$rc $o", qr/^0 # ==== backend\.hcl\n(?s:.*)# ==== versions\.tf\n/);

# ---------------------------------------------------------------- terraform itself, when present
if (my $tfbin = which('terraform') // which('tofu')) {
    my $out = qx("$tfbin" -chdir="$T/tf" fmt -check -diff 2>&1);
    check("terraform fmt: the generated files are canonical ($tfbin)", $? >> 8, 0) or print "# $out";
    my $init = qx("$tfbin" -chdir="$T/tf" init -backend=false -input=false -no-color 2>&1);
    if ($? >> 8) { print "# skip terraform validate: the provider could not be downloaded here\n" }
    else {
        my $v = qx("$tfbin" -chdir="$T/tf" validate -no-color 2>&1);
        like('terraform validate: the generated configuration is valid for the pinned provider', ($? >> 8) . " $v", qr/^0 Success! The configuration is valid/);
    }
} else { print "# skip terraform fmt and validate: no terraform or tofu on the PATH\n" }

# ---------------------------------------------------------------- the OpenTofu CI include
my $ci = slurp("$ROOT/tools/gitlab/terraform/gitlab-ci.tofu.yml");
like('ci: the OpenTofu component, plan in MRs and apply on the default branch', $ci, qr{^  - component: \$CI_SERVER_FQDN/components/opentofu/validate-plan-apply\@4\.9\.0\n    inputs:\n      version: 4\.9\.0\n      opentofu_version: 1\.12\.6\n      root_dir: gitlab/terraform\n      state_name: gitlab-project\n}m);
like('ci: off by default (included only when GITLAB_TF is true)', $ci, qr/^#     - local: gitlab-ci\.tofu\.yml.*\n#       rules:\n#         - if: \$GITLAB_TF == "true"$/m);
like('ci: Dedicated needs the component mirrored', $ci, qr/GitLab Dedicated and self-managed: components on gitlab\.com are not distributed to your instance/);

# ---------------------------------------------------------------- Kubernetes runner files and the image
my $v = slurp("$ROOT/tools/gitlab/k8s/values.yaml");
like('k8s: the token comes from a Kubernetes secret', $v, qr/^runners:\n  secret: gitlab-runner-mbse/m);
unlike_('k8s: no token in the values file', $v =~ s/^\s*#.*$//mgr, qr/runnerToken|runnerRegistrationToken|glrt-/);
like('k8s: Kubernetes executor in its own namespace with the mbse-ci image', $v, qr/\[runners\.kubernetes\]\n(?:.*\n)*?\s+namespace = "gitlab-runner-jobs"\n\s+image = "[^"]*mbse-ci:1\.0"/);
like('k8s: requests and limits', $v, qr/cpu_request = "500m"\n\s+cpu_limit = "2"\n\s+memory_request = "512Mi"\n\s+memory_limit = "2Gi"/);
like('k8s: Linux nodes only', $v, qr/\[runners\.kubernetes\.node_selector\]\n\s+"kubernetes\.io\/os" = "linux"/);
like('k8s: pods run as the image\'s numeric non-root user', $v, qr/\[runners\.kubernetes\.pod_security_context\]\n\s+run_as_non_root = true\s.*\n\s+run_as_user = 1000\n/);
like('k8s: the CI keys pick the runner by tag and point KIT into the image', slurp("$ROOT/tools/gitlab/k8s/gitlab-ci.k8s.yml"), qr/^default:\n  image: \S+mbse-ci:1\.0.*\n  tags:\n    - k8s-linux.*\n    - mbse\n\nvariables:\n  KIT: \/opt\/agile-kit/m);
like('k8s: the agent config authorizes the model project for sil/* only', slurp("$ROOT/tools/gitlab/k8s/agents/sil-twin/config.yaml"), qr/^ci_access:\n  projects:\n    - id: tidewater\/model\n      environments:\n        - sil\/\*/m);
my $df = slurp("$ROOT/tools/gitlab/docker/Dockerfile");
like('docker: a numeric non-root USER (Kubernetes can verify runAsNonRoot)', $df, qr/^USER 1000:1000$/m);
like('docker: the user is uid and gid 1000', $df, qr/useradd --uid 1000 --gid 1000/);
check('docker: the CI keys and the Helm values name the same uid', ($v =~ /run_as_user = (\d+)/)[0], '1000');

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
