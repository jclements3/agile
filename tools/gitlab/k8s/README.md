# Running the model pipeline on Kubernetes (AKS)

Where the program's GitLab runners live in Kubernetes (here: Azure Kubernetes Service), the model pipeline runs the
same way it does on the Tidewater team's Windows shell runner. Every job is `perl ci/job.pl NAME`, the kit is inside
the `mbse-ci` image (`tools/gitlab/docker`), and nothing is installed at job time.

| File | What it is |
|---|---|
| `values.yaml` | Helm values for GitLab Runner with the Kubernetes executor: namespace, the mbse-ci image, CPU and memory, Linux nodes, non-root pods; the token comes from a Kubernetes secret |
| `gitlab-ci.k8s.yml` | the keys that replace the template's `default:` block (image, tags, `KIT`, `DOCKER_RUNNER`) |
| `networkpolicy.yaml` | optional: job pods may reach GitLab and DNS, nothing else |
| `agents/sil-twin/config.yaml` | optional: the GitLab agent for Kubernetes, for a SIL or digital-twin test environment |

## Who owns what

| The platform team owns | The MBSE team needs to know |
|---|---|
| the AKS cluster, node pools, namespaces, quotas | which runner tags to use (`k8s-linux`, `mbse`) |
| installing and upgrading the runner chart (`values.yaml` is a starting point for them) | the image name and version the pipeline uses (`mbse-ci:1.0`) |
| the runner's authentication token and its Kubernetes secret | that a pending job means "no runner with these tags is free", not a broken model |
| network policy, image registry, scanning of images | how to read a job log (the same as on the shell runner) |
| the GitLab agent, if a test environment is wanted | which environments a job may deploy to (`sil/*`), if the agent is used |

The MBSE team does not need `kubectl` to run the pipeline.

## How a job becomes a pod

1. A pipeline starts. GitLab queues each job with its `tags`.
2. The runner manager (one pod in `gitlab-runner`) polls GitLab. It picks up jobs whose tags are all on this runner.
3. For each job it creates a pod in `gitlab-runner-jobs` with three kinds of container:
   - the **build** container, using the job's `image` (default `mbse-ci`), which runs the script;
   - the **helper** container, which clones the repository and moves the cache and artifacts;
   - any **services** the job names.
4. The script runs (`perl ci/job.pl lint`). The log streams back to GitLab, artifacts are uploaded, and the pod is
   deleted.

A job that waits a minute before it starts is usually a node starting up or pulling the image the first time.

## Tags: which runner takes which job

The template's jobs share one `default: tags:` block. On the Tidewater shell runner it is `[windows, mbse]`. For
the AKS runner, replace that block with `gitlab-ci.k8s.yml` (`[k8s-linux, mbse]` plus the image). Keys in
`.gitlab-ci.yml` override an included file's, so edit the block itself rather than including the file.

A job that must stay on Windows keeps `tags: [windows, mbse]` on the job itself. Examples are a PowerShell-only step
or a Windows tool. `hil-test` keeps its own `hil-bench` tag, because only the bench's runner has it.

Tags are set on the runner in GitLab when it is created (Settings > CI/CD > Runners), not in `values.yaml`.

## Windows jobs on Kubernetes

The kit needs nothing from Windows, so the Linux pool is enough. If a job must run Windows containers, AKS needs a
Windows node pool and a second runner with these settings:

```toml
[runners.kubernetes.node_selector]
  "kubernetes.io/os" = "windows"
  "kubernetes.io/arch" = "amd64"
  "node.kubernetes.io/windows-build" = "10.0.20348"     # Windows Server 2022 nodes
```

It also needs a Windows image with Perl and Git (for example Git for Windows in a Server Core image), tagged
`k8s-windows`. That is a platform-team project. Most teams keep their Windows shell runner for the few Windows jobs
instead.

## The image on Kubernetes

`mbse-ci` runs as the numeric user 1000, so `run_as_non_root` can verify it. It is the kit at one version, with no
credentials and no network access needed at job time. Only the helper talks to GitLab. GitLab's scanner images
(Secret Detection) are GitLab's; if your cluster refuses one with "runAsNonRoot", give the scanners a runner without
`run_as_non_root`, or ask the platform team for an exception for those images.

## Optional: a test environment through the GitLab agent

`agents/sil-twin/config.yaml` lets jobs that deploy to `sil/...` environments use `kubectl` against a cluster that
hosts a SIL or digital-twin environment. No cluster credential is stored in GitLab. Use it only when the program has
such an environment; the template's `sil-regression` job (off by default) is where it would be called.
