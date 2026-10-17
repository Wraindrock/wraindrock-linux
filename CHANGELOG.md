# Changelog

All notable changes to the Wrainrock Linux repository are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
image versions are the Fedora channel plus an immutable build tag, see
[docs/architecture.md](docs/architecture.md).

## [0.1.0] - 2026-10-17

### Added

- Bootc image `ghcr.io/wraindrock/wrainrock-linux`, built `FROM
  quay.io/fedora/fedora-silverblue:44` with the base digest resolved and
  recorded at build time.
- Parity invariant: the image's RPM set and `/usr/lib/os-release` are identical
  to the base; only `/usr/share/wrainrock/` is added.
- Build provenance in `/usr/share/wrainrock/build-info.json` (schema, image,
  version, build number, git SHA, build date, base image, base digest, Fedora
  version, parity marker, RPM count, RPM-set SHA-256) and a pristine
  `/usr/share/wrainrock/base-os-release`.
- `bootc container lint` runs inside the image build.
- CI gates: `tests/lint.sh`, `tests/parity.sh` (RPM + os-release diff against the
  base), `tests/smoke.sh` (the image boots under systemd).
- Publishing: immutable tags `<fedora>.<UTC timestamp>.<run>` that are never
  overwritten, moving `44`/`latest` channel tags, and a `previous` rollback tag.
- Keyless Sigstore signing of the published digest with `cosign`, verified in the
  same workflow.
- Nightly rebuild against the freshest Fedora 44 base.
- Documentation: architecture, install with preflight and troubleshooting,
  rollback, roadmap with explicit non-goals, security model, contributing guide.

### Notes

- v0.1 is intentionally unmodified Fedora Silverblue 44. It is a pipeline
  validation release; customization begins in v0.2 (`docs/roadmap.md`).
- Automatic updates are off by default.
- No installer ISO yet; install with `bootc switch` on an existing Fedora Atomic
  Desktop.
