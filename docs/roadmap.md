# Roadmap

Each milestone is a reviewable change set with a test that fails before it and
passes after it. Nothing is "done" because the image builds.

## v0.1 — parity bootstrap (current)

**Goal:** prove the whole pipeline on an image that is *exactly* Fedora
Silverblue 44.

- [x] `FROM quay.io/fedora/fedora-silverblue:44`, digest-pinned at build time
- [x] Provenance in `/usr/share/wrainrock/` (build info + pristine base os-release)
- [x] `bootc container lint` in the image build
- [x] Parity test: RPM set and `/usr/lib/os-release` diff-clean against the base
- [x] Smoke test: boots under systemd
- [x] Publish immutable + channel tags; refuse to overwrite immutable tags
- [x] Keyless cosign signing and verification in CI
- [x] Install, rollback and security documentation

**Invariant:** the image differs from its base only in `/usr/share/wrainrock/`.

**Non-goals:** branding, package changes, installer ISO, automatic updates.

## v0.2 — first real customization

**Goal:** make Wrainrock *Wrainrock*, without touching the OS machinery.

- `os-release` identity (`NAME="Wrainrock Linux"`, `VARIANT="Wrainrock"`,
  `ID=wrainrock`, `ID_LIKE="fedora"`, `VERSION_ID=44`, `HOME_URL`, `BUG_REPORT_URL`)
- Branding package: wallpapers, logo, GDM background
- Default applications decision (start with *no removals*: add nothing, remove
  nothing until the branding pipeline is stable)
- Parity test relaxed to "base **plus** recorded deltas": each change must be
  listed in a manifest that CI diffs against the actual RPM/file delta, so
  unintended drift still fails
- `/usr/share/wrainrock/build-info.json` gains `customizations[]`

**Test that must fail first:** a new test asserts `NAME="Wrainrock Linux"` in
`/usr/lib/os-release`; it fails on v0.1 and passes on v0.2.

## v0.3 — installable ISO

**Goal:** a fresh machine can be installed without an existing Fedora system.

- `bootc-image-builder` produces an Anaconda ISO in CI
- Automated VM install test (qemu + kickstart) boots to GDM
- ISO artifact uploaded to the GitHub release with checksums
- Install docs rewritten around the ISO; `bootc switch` remains the upgrade path

**Non-goal:** custom partitioning UX, encryption UI, dual-boot UX.

## v0.4 — update policy and channels

**Goal:** deliberate upgrade cadence.

- Channels: `44` (stable), `next` (pre-release of the next Fedora), `testing`
- Opt-in automatic updates documented and tested (bootc update timer)
- A `bootc update --check` based "update available" notifier, if the CLI
  supports it on the target version
- Rebase to Fedora 45 when released; one release cycle of overlap where `44`
  still receives security rebuilds
- Package pin/delta policy: document how a specific Fedora package update is
  held back if it breaks the desktop

**Non-goal:** distro-wide package version pinning. Wrainrock follows Fedora
except for documented, tested holds.

## v0.5 — developer edition (optional)

An opt-in variant with toolchains preinstalled (`wrainrock-devel` tag derived
from the same base), or a documented `rpm-ostree install` recipe. Decide based
on real usage; a second image doubles build and test cost and is not free.

## v1.0 — "would you recommend it to a friend"

Release criteria, all measurable:

1. Three consecutive Fedora point releases shipped through the pipeline with no
   rollback-causing regression.
2. ISO install and `bootc switch` both pass automated tests on the current and
   previous Fedora release.
3. Documented rollback exercised in CI (install → update → rollback → verify).
4. At least two maintainers with publishing rights; keyless signing identities
   restricted to the release workflow.
5. No known unfixed regression in the last 90 days.

Not criteria: number of users, GitHub stars, or feature count.

## Deliberate non-goals (all versions until revisited)

1. Forking Fedora packages, the kernel, GNOME or systemd without a tested reason.
2. A second package manager or a mutable `/usr`.
3. Flatpak remotes beyond Fedora's; Flatpak is the app story, not the OS.
4. Reimplementing Anaconda, disk encryption or Secure Boot key management.
5. Automatic major-version upgrades without user consent.
6. KDE/XFCE/Sway variants before GNOME is boring.
7. Treating rootless containers as a multi-tenant security boundary.

## Versioning

- Fedora version is the first tag component: `44`, `44.20261017T061500Z.42`.
- Wrainrock releases are the moving channel tags; there is no separate
  "Wrainrock 1.2.3". The git tag `v0.x.y` on the repository marks source
  milestones, not image versions.
- Immutable image tags are never reused; if a build is wrong, ship a new timestamp.
