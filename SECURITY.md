# Security policy

## Reporting a vulnerability

Open a **private** GitHub security advisory:
<https://github.com/Wraindrock/wraindrock-linux/security/advisories/new>

Do not file a public issue for a vulnerability. Include the image tag (or
`build-info.json`), a reproduction, and the impact you believe it has. We aim to
acknowledge within 72 hours and to publish a fixed build before disclosing.

## Supported versions

Only the current upstream channel (`44` at the time of writing) and the
`previous` tag receive security rebuilds. Older immutable tags are kept for
audit and reproducibility but are **not** patched. The nightly workflow rebuilds
the channel against the freshest Bluefin DX base, so upstream fixes reach
Wraindrock without a Wraindrock commit.

## Trust model

```
uBlue / Fedora (Bluefin DX base)        ── trusted upstream
        │
GitHub Actions (public workflow)        ── trusted build environment
        │
Sigstore keyless signature              ── binds artifact to workflow identity
        │
ghcr.io (registry)                      ── distribution
        │
your machine (bootc)                    ── verifies only if you ask it to
```

- The base image is Universal Blue's Bluefin DX, pulled **by digest** at build
  time; the digest is recorded in `/usr/share/wraindrock/build-info.json`. uBlue's
  own build and signing chain is trusted transitively.
- The only deviation from that base is the recorded identity and presentation
  delta, listed in `/usr/share/wraindrock/delta.json`. `rpm -V --nomtime` on the
  package that owns `/usr/lib/os-release` (looked up dynamically) reporting that
  one file as modified is expected, not tampering; a deviation not listed in the
  manifest is a bug worth reporting.
- The workflow runs on GitHub-hosted runners only. There are no self-hosted
  runners and no long-lived registry credentials.
- The only credentials in the pipeline are the ephemeral `GITHUB_TOKEN` and the
  OIDC token cosign exchanges for a short-lived signing certificate.
- Image signatures are **keyless**: the certificate identity is
  `https://github.com/Wraindrock/wraindrock-linux/.github/workflows/build.yml@refs/heads/main`
  and the issuer is `https://token.actions.githubusercontent.com`. `cosign
  verify` is documented in [docs/install.md](docs/install.md).
- `bootc` verifies the image is a bootc image and imports it atomically; it does
  **not** verify the Sigstore signature for you. Run `cosign verify` yourself if
  provenance matters. The immutable tag plus the recorded digest is the
  reproducibility story.

## What this project does not protect against

State it plainly rather than implying a guarantee:

1. **A compromised Bluefin DX or Fedora base image.** Every package in
   Wraindrock comes from Universal Blue and Fedora. If either upstream's build or
   distribution infrastructure is compromised, so is Wraindrock.
2. **A compromised GitHub Actions runner.** The build executes on GitHub's
   infrastructure; a runner compromise can produce a signed malicious image.
   This is the same trust assumption every GitHub-built container makes.
3. **A malicious commit merged to `main`.** Signing proves *who built it*, not
   that the change is benign. Review and branch protection are the control here.
4. **Compromise of Sigstore/Fulcio/Rekor or cosign themselves.** We use the
   standard keyless flow; its failure modes are inherited.
5. **Kernel-level attacks from the container model.** A bootc image *is* the
   host; its system services run as root. Rootless podman is a convenience for
   users and is **not** a tenant boundary against untrusted users on the same
   kernel.
6. **Physical access, firmware implants, disk theft without encryption.**
   Wraindrock ships upstream's defaults and adds no hardening of its own. The
   stock unattended ISO does not offer full-disk encryption; installing with
   encryption is not implemented yet (see the roadmap).

## Credentials and build hygiene

- No secrets are baked into the image. Build arguments are public by design
  (`BASE_DIGEST`, `GIT_SHA`, versions) and appear in image history; never pass a
  token as a build argument.
- Local registry credentials live in `$XDG_RUNTIME_DIR/containers/auth.json`
  (0600) or a podman `--authfile`. Do not copy them into the repository; the
  lint check rejects credential-shaped strings.
- If you fork this repository: the cosign identity regexp, the image name and
  the GHCR package must all change together. A fork that keeps the original
  identity can produce images that *look* signed by the upstream workflow — change
  `IMAGE_REGISTRY`/`IMAGE_NAME` and the verification examples in the same PR.
- Rotating the `GITHUB_TOKEN` is automatic (per workflow run). There is no
  project-wide secret to rotate; if that ever changes, this file must document
  the source and rotation procedure for each name.

## Hardening principles for future changes

When Wraindrock starts shipping its own services (v0.6+):

- run as non-root with an explicit `User=`;
- `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=read-only`,
  `PrivateTmp=yes`, and a narrowed `CapabilityBoundingSet=`;
- listen on `127.0.0.1` unless a host reverse proxy terminates TLS;
- any privilege escalation (docker socket, `--privileged`, host networking) is
  a named, documented, disable-able flag — never a default;
- credentials only via 0600 files or runtime environment, never in the image,
  logs, `/proc` visible command lines, or shell history.
