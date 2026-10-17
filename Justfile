set dotenv-filename := "image.env"
set dotenv-load
set export

image_name := env_var("IMAGE_NAME")
repo_organization := env_var("REPO_ORGANIZATION")
image_desc := env_var("IMAGE_DESC")
image_keywords := env_var("IMAGE_KEYWORDS")
image_logo_url := env_var("IMAGE_LOGO_URL")
image_license := env_var("IMAGE_LICENSE")
default_tag := env_var("DEFAULT_TAG")
base_image := env_var("BASE_IMAGE")
fedora_version := env_var("FEDORA_VERSION")

# List recipes
default:
    @just --list

# ---------------------------------------------------------------------------
# Static checks. No podman required.
# ---------------------------------------------------------------------------
[group('Lint')]
check:
    bash tests/lint.sh

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
[group('Build')]
build tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    git_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    registry="$(printf '%s' "${repo_organization}" | tr '[:upper:]' '[:lower:]')"

    # Pin FROM to the digest of the tag we just pulled: a tag that moves
    # mid-build would make build-info.json lie about its feedstock.
    podman pull --quiet "${base_image}"
    base_ref="$(
      podman image inspect "${base_image}" --format '{{index .RepoDigests 0}}' \
        2>/dev/null || true
    )"
    [[ -n ${base_ref} ]] || base_ref="${base_image}"

    podman build \
      --build-arg "BASE_REF=${base_ref}" \
      --build-arg "BASE_IMAGE=${base_image}" \
      --build-arg "IMAGE_NAME=${image_name}" \
      --build-arg "IMAGE_REGISTRY=ghcr.io/${registry}" \
      --build-arg "IMAGE_VERSION=${tag}" \
      --build-arg "FEDORA_VERSION=${fedora_version}" \
      --build-arg "GIT_SHA=${git_sha}" \
      --build-arg "BUILD_DATE=${build_date}" \
      --build-arg "BUILD_NUMBER=local" \
      --label "org.opencontainers.image.created=${build_date}" \
      --label "org.opencontainers.image.version=${tag}" \
      --label "org.opencontainers.image.revision=${git_sha}" \
      --tag "localhost/${image_name}:${tag}" \
      --file Containerfile \
      .
    podman images --filter "reference=localhost/${image_name}"

# ---------------------------------------------------------------------------
# Behavioural tests (need podman and a pulled base image)
# ---------------------------------------------------------------------------
[group('Test')]
parity image='localhost/' + image_name + ':' + default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    # Compare with the digest-pinned feedstock when the base is present locally;
    # fall back to the tag so the test still gives a useful error when it is not.
    base_ref="$(
      podman image inspect "{{base_image}}" --format '{{index .RepoDigests 0}}' \
        2>/dev/null || true
    )"
    bash tests/parity.sh "${base_ref:-{{base_image}}}" "{{image}}"

[group('Test')]
smoke image='localhost/' + image_name + ':' + default_tag:
    bash tests/smoke.sh "{{image}}"

# Everything that does not need a build
[group('Test')]
all: check
    @echo "static checks passed (build + parity + smoke need podman)"
