# The GitLab project as Terraform/OpenTofu -- an alternative to `gitlab.pl setup`

`gitlab.pl setup .gitlab/project.conf` applies the project file through the REST API. Some platform teams run every
GitLab project as code instead, with Terraform or OpenTofu and the `gitlabhq/gitlab` provider. For them the kit
generates the same settings as `.tf` files from the same project file, so there is still one source of truth:

```sh
perl $KIT/bin/gitlab.pl terraform .gitlab/project.conf --out gitlab/terraform --url https://gitlab.example.gov
```

| File | What it holds |
|---|---|
| `versions.tf` | the provider, pinned (`~> 19.4`), and an empty `backend "http" {}` for GitLab-managed state |
| `project.tf` | the project (adopted with an `import` block), members, labels, milestones (the sprints), protected branches and tags, approval rules, CI/CD variables, pipeline schedules and their variables, issue boards |
| `variables.tf` | one Terraform variable per CI/CD variable: values come from `TF_VAR_...` or a `.tfvars` file kept out of git |
| `backend.hcl` | the state URLs, for `tofu init -backend-config=backend.hcl` on a workstation |

Not in the provider, so left to `gitlab.pl setup`: the iteration cadence (`[iterations]`; GitLab changes it only
through GraphQL) and `.gitlab/insights.yml` (`[insights]`; a repository file goes through a merge request).
`[windchill]` is not a GitLab setting.

## Plan and apply

On a workstation, with a token (scope `api`, Maintainer on the project):

```sh
cd gitlab/terraform
export GITLAB_TOKEN=...  GITLAB_BASE_URL=https://gitlab.example.gov/api/v4/  TF_HTTP_PASSWORD=$GITLAB_TOKEN
tofu init -backend-config=backend.hcl       # terraform works the same
tofu plan                                    # the first plan imports the existing project; nothing else should change
```

In the pipeline: `gitlab-ci.tofu.yml` (the OpenTofu CI/CD component; plan in the merge request, manual apply on
the default branch), off until the CI/CD variable `GITLAB_TF` is `true`. Read its header for GitLab Dedicated, where
the component must be mirrored to your instance first.

## Choose one

Do not run `gitlab.pl setup` and an apply against the same project: they would undo each other's changes. Keep
`setup --diff` as the read-only drift check either way. The kit's tests check the generated files with
`terraform fmt` and `terraform validate` when a terraform binary is on the PATH (validate needs the provider
download); they never need one.
