# mbse-ci: the model pipeline's toolchain as a container image -- for Docker runners and Kubernetes runners (tools/gitlab/k8s).
# The Tidewater team does not need it: their runner is a Windows shell executor with Git for Windows' Perl.
#
# Contents: Debian slim + Perl 5.40 (all core modules) + git + curl, and the agile kit's pipeline tools at /opt/agile-kit
# (bin/, lib/, tools/) -- so the image is the kit at one version: tag the image with the kit's tag and every pipeline that
# uses that tag runs exactly the same checks (a baseline of the toolchain, not only of the model).
#
# Build from a committed kit tree (see README.md):
#   git archive --format=tar HEAD bin lib tools | docker build -t mbse-ci:dev -f tools/gitlab/docker/Dockerfile -
# The pipeline then uses it with `image:` and KIT=/opt/agile-kit (gitlab-ci.docker.yml).
#
# Pin the base by digest in production (docker pull perl:5.40-slim-bookworm; docker inspect --format '{{index .RepoDigests 0}}').
FROM perl:5.40-slim-bookworm

# git: checkout, diff, merge-base, ls-tree in the jobs; curl: package registry uploads; ca-certificates: HTTPS to GitLab
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG KIT_VERSION=dev
LABEL org.opencontainers.image.title="mbse-ci" \
      org.opencontainers.image.description="SysML v2 text model pipeline: the agile kit's sysml.pl, model.pl, xmi2sysml, reqif2sysml, gitlab.pl, ci-reports" \
      org.opencontainers.image.version="${KIT_VERSION}"

COPY bin  /opt/agile-kit/bin
COPY lib  /opt/agile-kit/lib
COPY tools /opt/agile-kit/tools
ENV KIT=/opt/agile-kit \
    LANG=C.UTF-8

# GitLab checks the repository out as another user than the image's; let git work in it
RUN git config --system --add safe.directory '*' \
 && groupadd --gid 1000 ci \
 && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash ci \
 && perl -I"$KIT/lib" -c "$KIT/tools/sysml/model.pl" \
 && perl "$KIT/tools/sysml/sysml.pl" grammar > /dev/null

# A numeric user: Kubernetes can only verify runAsNonRoot for a numeric USER (tools/gitlab/k8s/values.yaml runs the
# job pods as 1000:1000). The image needs no network at job time: the kit, Perl and git are all here, and only the
# runner's helper container talks to GitLab.
ENV HOME=/home/ci
USER 1000:1000
WORKDIR /home/ci
