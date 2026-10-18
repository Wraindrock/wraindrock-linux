# Roadmap

Each milestone is a reviewable change set with a test that fails before it and
passes after it. Nothing is "done" because the image builds.

## v0.1 — parity bootstrap (done)

**Goal:** prove the whole pipeline on an image that is *exactly* Fedora
Silverblue 44.

- [x] `FROM quay.io/fedora/fedora-silverblue:44`, digest-pinned at build time
- [x] Provenance in `/usr/share/wraindrock/` (build info + pristine base os-release)
- [x] `bootc container lint` in the image build
- [x] Parity test: RPM set and `/usr/lib/os-release` diff-clean against the base
- [x] Smoke test: boots under systemd
- [x] Publish immutable + channel tags; refuse to overwrite immutable tags
- [x] Keyless cosign signing and verification in CI
- [x] Install, rollback and security documentation

**Invariant:** the image differs from its base only in `/usr/share/wraindrock/`.

**Non-goals:** branding, package changes, installer ISO, automatic updates.

## v0.2 — branded identity (done)

**Goal:** make Wraindrock *Wraindrock*, without touching the OS machinery.

- [x] `os-release` identity: `NAME="Wraindrock Linux"`, `PRETTY_NAME` derived from
      the base version, `ID=wraindrock`, `ID_LIKE="fedora"`, `LOGO`,
      `DEFAULT_HOSTNAME="wraindrock"`, project URLs, `CPE_NAME`
- [x] `VERSION`, `VERSION_ID`, `OSTREE_VERSION` and `SUPPORT_END` stay Fedora's:
      the update cadence and support window are not ours to rewrite yet
- [x] Placeholder logo: black `Wraindrock` wordmark (long) and `W` mark (short)
      with a thin blue outline, shipped as SVG **outlines** so rendering never
      depends on a font being installed
- [x] GDM login logo through `zz-wraindrock.gschema.override`; Fedora's own
      override is left untouched
- [x] `delta.json` manifest; the parity test relaxes to "base **plus exactly**
      the recorded delta", and cross-checks every declared value
- [x] No package changes: the RPM set is still identical, and a lint rule fails
      the build if `build.sh` grows a package install
- [x] `bootc container lint` and the smoke test stay green on the branded image

**Test that must fail first:** `tests/parity.sh` asserts `NAME="Wraindrock Linux"`
in `/usr/lib/os-release`; that assertion fails on v0.1 and passes on v0.2.

**Known limit:** the black wordmark has low contrast on the dark wallpaper used
by the login screen. A light login-screen variant is a follow-up.

**Non-goals:** package changes, wallpapers, Plymouth, GRUB theme, installer ISO,
automatic updates. The identity delta is deliberately the only delta.

## v0.3 — visual identity and installable ISO (current)

**Goal:** Wraindrock looks like Wraindrock from firmware hand-off to login, and a
fresh machine can be installed without an existing Fedora system. Each step
below ships as its own immutable release; no step relaxes the delta invariant.

- [x] Step 1 — default wallpaper (desktop + GDM): 3840x2160 PNG, set for both
      `picture-uri` and `picture-uri-dark` through
      `zz-wraindrock.gschema.override`, recorded in `delta.json`, and asserted by
      parity via the compiled schema cache and `gsettings get`
- [x] Step 2 — Plymouth splash (boot logo): a `two-step` theme using the base's
      shipped plugin (no package change), 1920x1080 gradient background, 30
      animation frames (outlined `W` + rotating blue arc), and
      `/etc/plymouth/plymouthd.conf` selecting `wraindrock`; parity asserts the
      theme file, the daemon config, frame count/format/dimensions and
      `plymouth-set-default-theme -l`
- [x] Step 3 — GRUB menu theme, delivered as an opt-in helper:
      `/usr/bin/wraindrock-grub-theme` copies the assets to
      `/boot/grub2/themes/wraindrock/` and writes a marked `custom.cfg` that
      bootupd's static config sources. It refuses foreign `custom.cfg` files and
      systemd-boot hosts. The image cannot rewrite an installed GRUB config, so
      automatic application is delegated to the installer (step 4); parity
      exercises enable, idempotency, both refusals and disable against throwaway
      boot trees
- [x] Step 4 — `bootc-image-builder` produces an Anaconda ISO and a qcow2 in CI
      (`.github/workflows/disk.yml`, gated by structural checks and SHA256SUMS);
      the ISO is unattended by construction (BIB baked kickstart: autopart,
      btrfs, reboot). The workflow also boots the ISO under KVM, installs it
      once, and requires the installed system to reach the GNOME welcome/login
      screen (`vm_test`, default on). Verified artifact sets are published as
      immutable OCI artifacts on GHCR
      (`ghcr.io/wraindrock/wraindrock-linux-disk:<version>`, three blobs plus
      `SHA256SUMS`); GitHub Release assets are not used because they cap at
      2 GiB. `bootc switch` remains the upgrade path for existing systems.

**Test that must fail first (step 1):** `tests/parity.sh` runs `gsettings get
org.gnome.desktop.background picture-uri`; it returns Fedora's f44 JXL on the
v0.2 image and the Wraindrock PNG on v0.3.

**Test that must fail first (step 2):** `tests/parity.sh` asserts the
`wraindrock` theme file and `Theme=wraindrock` in `/etc/plymouth/plymouthd.conf`;
both fail on the step-1 image and pass once the splash is installed.

**Test that must fail first (step 3):** `tests/parity.sh` runs
`wraindrock-grub-theme` against fixture boot trees; on the step-2 image the
helper does not exist and every helper assertion fails.

**Non-goals:** custom partitioning UX, encryption UI, dual-boot UX.

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

**Non-goal:** distro-wide package version pinning. Wraindrock follows Fedora
except for documented, tested holds.

## v0.5 — developer edition (optional)

An opt-in variant with toolchains preinstalled (`wraindrock-devel` tag derived
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
- Wraindrock releases are the moving channel tags; there is no separate
  "Wraindrock 1.2.3". The git tag `v0.x.y` on the repository marks source
  milestones, not image versions.
- Immutable image tags are never reused; if a build is wrong, ship a new timestamp.
