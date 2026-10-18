# syntax=docker/dockerfile:1
#
# Wraindrock - a Bluefin DX based atomic desktop, tuned out of the box.
#
# v0.3 is a *branded parity build*: the RPM set is still exactly Fedora
# Bluefin DX 44, plus a presentation delta (os-release display fields, logo
# icon, GDM logo, default wallpaper, Plymouth boot splash, GRUB theme assets
# and an opt-in boot-menu helper) recorded in
# /usr/share/wraindrock/delta.json. Any difference outside that manifest is a
# pipeline bug, not a customization bug. docs/roadmap.md turns on real
# customization one reviewed step at a time.
#
# Build contract: image.env -> build args -> build_files/build.sh -> bootc lint.
# The build inputs are bind-mounted, never COPYed, so the image does not ship
# its own build scripts.

ARG BASE_REF=ghcr.io/ublue-os/bluefin-dx:stable

FROM ${BASE_REF}

ARG BASE_REF
ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin-dx:stable
ARG BASE_DIGEST=unknown
ARG IMAGE_NAME=wraindrock-linux
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

LABEL org.opencontainers.image.title="Wraindrock Linux" \
      org.opencontainers.image.description="Wraindrock - a Bluefin DX based atomic desktop, tuned out of the box" \
      org.opencontainers.image.vendor="Wraindrock" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/Wraindrock/wraindrock-linux" \
      org.opencontainers.image.url="https://github.com/Wraindrock/wraindrock-linux" \
      org.opencontainers.image.documentation="https://github.com/Wraindrock/wraindrock-linux/blob/main/README.md" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.wraindrock.base.image="${BASE_IMAGE}" \
      org.wraindrock.base.digest="${BASE_DIGEST}" \
      org.wraindrock.fedora.version="${FEDORA_VERSION}" \
      org.wraindrock.parity="bluefin-dx-${FEDORA_VERSION}"

# Apply the identity delta and record provenance, refusing to build on a base
# that is not the bootc image this project claims to derive from. See
# build_files/build.sh.
RUN --mount=type=bind,source=build_files,target=/tmp/wraindrock-build \
    /tmp/wraindrock-build/build.sh

# bootc's own contract: fails if this is not a valid bootc image.
RUN bootc container lint

# systemd is PID 1 on a bootc system. The official atomic images default to
# /usr/bin/bash, which exits immediately when someone runs the image as a
# container; setting this makes `podman run` behave like the deployed system.
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
