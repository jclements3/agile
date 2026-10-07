# mbse-ci -- an optional Docker image for the model pipeline

**You probably do not need this.** The Tidewater team's runner is a Windows shell executor that runs the kit with
Git for Windows' Perl; the pipeline has no `image:`. Use this image if your GitLab offers Docker or Kubernetes runners
(`tools/gitlab/k8s` has the AKS runner setup), or if you want GitLab's managed scanners (they need a container runner).

| File | What it is |
|---|---|
| `Dockerfile` | Debian slim + Perl 5.40 + git + curl, with the kit's `bin/`, `lib/`, `tools/` at `/opt/agile-kit` (`KIT`) |
| `gitlab-ci.docker.yml` | the three keys to add to the model project's `.gitlab-ci.yml`: `image:`, runner `tags:`, `KIT`, `DOCKER_RUNNER` |
| `build-image.gitlab-ci.yml` | optional job that builds and pushes the image from the kit's own GitLab project on each kit tag |

## Build and test it on a workstation

From the kit's root, on a committed tree (the image is the kit at that commit):

```sh
git archive --format=tar HEAD bin lib tools \
  | docker build --build-arg KIT_VERSION=$(git describe --tags --always) -t mbse-ci:dev -f tools/gitlab/docker/Dockerfile -
docker run --rm mbse-ci:dev perl /opt/agile-kit/tools/sysml/sysml.pl grammar | tail -1
```

Run the model pipeline inside it, from a clone of the model project:

```sh
docker run --rm -v "$PWD":/builds/model -w /builds/model mbse-ci:dev \
  perl /opt/agile-kit/bin/gitlab.pl ci --event push --branch develop
```

About 23 s to build and 277 MB.

## Put it where the runners can pull it

```sh
docker login registry.example.gov                     # your GitLab's Container Registry, with a token (scope write_registry)
docker tag mbse-ci:dev registry.example.gov/tidewater/model/mbse-ci:1.0
docker push registry.example.gov/tidewater/model/mbse-ci:1.0
```

Then add `gitlab-ci.docker.yml`'s keys to `.gitlab-ci.yml` and set `DOCKER_RUNNER` to `true` in the project's CI/CD variables.

## Keep it healthy

- Pin the base image by digest. Rebuild monthly, or when Debian publishes a security update, and give each rebuild a new tag. Never use `:latest` in a pipeline.
- Tag the image with the kit's tag. A pipeline that names `mbse-ci:1.0` always runs the same checks, so the toolchain is baselined along with the model.
- The image runs as the unprivileged user `ci`, uid and gid 1000 (numeric, so a Kubernetes `runAsNonRoot` pod can verify it). It contains no credentials, so pass tokens as masked CI/CD variables.
- If your security office scans images, run that scan in the kit project's pipeline before you push.
