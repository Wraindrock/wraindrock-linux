# Changelog

All notable changes to the Wrainrock Linux repository are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
image versions are the Fedora channel plus an immutable build tag, see
[docs/architecture.md](docs/architecture.md).

## [0.2.0] - 2026-10-17

### Added

- Branded identity: `NAME="Wrainrock Linux"`, `PRETTY_NAME` derived from the base
  version, `ID=wrainrock` with `ID_LIKE="fedora"`, `LOGO=wrainrock-logo-icon`,
  `DEFAULT_HOSTNAME="wrainrock"`, project URLs, and
  `CPE_NAME="cpe:/o:wraindrock:wrainrock_linux:44"`.
- Placeholder logo assets shipped as SVG **outlines** (no font dependency):
  `wrainrock-logo-icon.svg` (Settings → About) and
  `wrainrock-gdm-logo.{svg,png}` (GDM login screen).
- `zz-wrainrock.gschema.override` so the GDM login screen shows the Wrainrock
  wordmark; Fedora's own override is left untouched.
- `/usr/share/wrainrock/delta.json`: the manifest of every intended difference
  from the base — changed/added os-release keys with their actual values,
  modified files and added files.
- CI anonymous-pull check: the published digest must be pullable without
  credentials, because a freshly installed bootc host has none.

### Changed

- `tests/parity.sh` enforces "base plus exactly the recorded delta" instead of
  byte-identical os-release: the RPM set must stay identical, os-release may
  differ only in the manifest's keys (with the recorded values), and
  `rpm -V --nomtime fedora-release-identity-silverblue` must report exactly one
  modified file (the mtime check is skipped because ostree hardlinks carry mtime
  0, not the rpm header's build time).
- `tests/lint.sh` fails if `build.sh` starts changing the RPM set, and requires
  the branding assets to be font-independent outlines.
- The workflow no longer tries to flip GHCR package visibility with
  `GITHUB_TOKEN` (it lacks `packages` scope); it asserts anonymous
  pullability instead and fails with the package-settings link if the package is
  private.
- `build-info.json` gains `"identity": "wrainrock"`.
- Build provenance is now part of the declared delta: the three
  `/usr/share/wrainrock/` files are listed under `files.added`, RPM queries run
  against a throwaway copy of the database, and parity compares the rpmdb's
  sqlite sidecars (`-wal`/`-shm`/`.rpm.lock`) against the base, so the build
  cannot modify them. The builder's empty `/etc/hostname` placeholder is
  documented as inert (systemd reads it as unset).

### Notes

- `VERSION`, `VERSION_ID`, `OSTREE_VERSION` and `SUPPORT_END` stay Fedora's: the
  update cadence and support window are not rewritten yet.
- No package changes: the RPM set is identical to Fedora Silverblue 44.
- GDM background, wallpapers, Plymouth and GRUB theming move to v0.3.
- Known limit: the black wordmark has low contrast on a dark GDM background.

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
