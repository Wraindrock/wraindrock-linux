# syntax=docker/dockerfile:1
#
# Wrainrock Linux - a Fedora Silverblue based atomic desktop.
#
# v0.1 is a *parity build*: it must reproduce the official Fedora Silverblue 44
# root filesystem exactly - same RPM set, same /usr/lib/os-release, same bootc
# labels - and add only Wrainrock build provenance. Any difference between this
# image and its base is therefore a pipeline bug, not a customization bug.
# docs/roadmap.md turns on customization one reviewed step at a time.
#
# Build contract: image.env -> build args -> build_files/build.sh -> bootc lint.
# The build inputs are bind-mounted, never COPYed, so the image does not ship
# its own build scripts.

ARG BASE_REF=quay.io/fedora/fedora-silverblue:44

FROM ${BASE_REF}

ARG BASE_REF
ARG BASE_IMAGE=quay.io/fedora/fedora-silverblue:44
ARG BASE_DIGEST=unknown
ARG IMAGE_NAME=wrainrock-linux
ARG IMAGE_REGISTRY=ghcr.io/wraindrock
ARG IMAGE_VERSION=dev
ARG FEDORA_VERSION=44
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
ARG BUILD_NUMBER=local

ENV WR_LINUX=1 \
    WR_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAME}" \
    WR_VERSION="${IMAGE_VERSION}" \
    WR_BASE_IMAGE="${BASE_IMAGE}" \
    WR_FEDORA_VERSION="${FEDORA_VERSION}"

LABEL org.opencontainers.image.title="Wrainrock Linux" \
      org.opencontainers.image.description="Wrainrock Linux - a Fedora Silverblue based atomic desktop" \
      org.opencontainers.image.vendor="Wraindrock" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/Wraindrock/wrainrock-linux" \
      org.opencontainers.image.url="https://github.com/Wraindrock/wrainrock-linux" \
      org.opencontainers.image.documentation="https://github.com/Wraindrock/wrainrock-linux/blob/main/README.md" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.wrainrock.base.image="${BASE_IMAGE}" \
      org.wrainrock.base.digest="${BASE_DIGEST}" \
      org.wrainrock.fedora.version="${FEDORA_VERSION}" \
      org.wrainrock.parity="fedora-silverblue-${FEDORA_VERSION}"

# Record provenance and refuse to build on a base that is not the bootc image
# this project claims to derive from. See build_files/build.sh.
RUN --mount=type=bind,source=build_files,target=/tmp/wrainrock-build \
    /tmp/wrainrock-build/build.sh

# bootc's own contract: fails if this is not a valid bootc image.
RUN bootc container lint

# systemd is PID 1 on a bootc system. The official atomic images default to
# /usr/bin/bash, which exits immediately when someone runs the image as a
# container; setting this makes `podman run` behave like the deployed system.
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
