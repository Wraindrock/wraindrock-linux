# Roadmap

Each milestone is a reviewable change set with a test that fails before it and
passes after it. Nothing is "done" because the image builds.

## v0.1 — pipeline bootstrap (done)

**Goal:** prove the whole pipeline on an image that is *exactly* Fedora
Silverblue 44.

- [x] Digest-pinned base, `bootc container lint`, parity test
- [x] Immutable + channel tags, keyless cosign signing
- [x] Smoke test, install/rollback/security docs

## v0.2 — branded identity (done)

**Goal:** make the image *Wraindrock* without touching the OS machinery.

- [x] os-release display fields and hostname
- [x] `delta.json` manifest; parity relaxes to "base plus exactly the delta"
- [x] No package changes

## v0.3 — visual identity and installable media (done)

**Goal:** Wraindrock looks like Wraindrock from firmware hand-off to login, and
a fresh machine can be installed without an existing system.

- [x] Default wallpaper (desktop + GDM)
- [x] Plymouth boot splash (removed again in v0.15: upstream's is better)
- [x] Opt-in GRUB menu theme (removed again in v0.15)
      (bootc cannot rewrite an installed bootloader config)
- [x] qcow2 + Anaconda ISO in CI (interactive default, unattended option);
      KVM install + boot tests
- [x] Verified disk artifacts published as immutable OCI artifacts on GHCR

## v0.4 — rebase onto Bluefin DX (done)

**Goal:** stop maintaining a Fedora derivative and become a Bluefin DX remix.
Upstream already ships the desktop, the uBlue tooling and the kernel modules;
Wraindrock should only own its identity and its preferences.

- [x] `BASE_IMAGE=ghcr.io/ublue-os/bluefin-dx:stable`, digest-pinned per build
- [x] Base assertions now require `ID=bluefin` and `VARIANT_ID=bluefin-dx*`
- [x] `ID`, `ID_LIKE`, `CPE_NAME` and version fields stay upstream's; uBlue
      tooling keys off `ID=bluefin`, so rebranding it would break uBlue
- [x] Identity delta reduced to `NAME`, `PRETTY_NAME`,
      `DEFAULT_HOSTNAME`, project URLs
- [x] Parity baseline is Bluefin DX; RPM set must stay identical
- [x] Hostname seeding accepts `bluefin` as the base default to replace

**Test that must fail first:** `tests/parity.sh` asserts the base is
`ID=bluefin`/`VARIANT_ID=bluefin-dx*` and that the image's `NAME` is
`Wraindrock`; on the Silverblue-based v0.3 image the base assertion fails.

**Delivered:** image `sha256:d9a3209f…` (version `44.20261018T031309Z.29`,
revision `ce6df12`), base digest `sha256:a41cf1eb…`, bluefin-dx RPM set
(2,237 packages), cosign-verified. The container smoke test now gives the
throwaway systemd container the full capability set of its user namespace;
journald and dbus cannot build their mount namespaces without it.

## v0.5 — out-of-the-box preferences

**Goal:** "install it and it is already mine", built only from mechanisms
upstream already provides.

- [x] Flatpak preinstalls through uBlue's supported mechanism
      (`/usr/share/flatpak/preinstall.d/wraindrock.preinstall`, generated from
      `build_files/software/flatpaks.txt`): 43 apps = Bluefin's core and DX set
      (GNOME apps, Thunderbird, Podman Desktop, Builder, DevToolbox, Clapgrep,
      Embellish, Bazaar, Flatseal, DistroShelf, Mission Center, Refine, …) plus
      WeChat, Rnote and Gear Lever. Firefox is skipped by explicit request,
      Tavern is no longer on Flathub and the two adw-gtk3 theme extensions are
      not app refs. Helium (pinned RPM from the official COPR) is the default
      browser via `/etc/xdg/mimeapps.list`.
- [x] Four RPMs baked at pinned versions with sha256 checks: Helium 0.19.4.1
      (official `imput/helium` COPR), Clash Verge Rev 2.5.8, Rayburst 4.0.1,
      sing-box (SFL) 1.14.3; declared in delta.json schema 2 under `rpm.added`.
      The daily `upstream-watch` workflow refreshes `rpms.tsv` and dispatches a
      build per upstream release, so apps track their own cadence
- [ ] Homebrew bundle for CLI tooling: uBlue's Brew is inherited, but no
      formulae are preinstalled yet (deliberately left user-controlled)
- [x] Bluefin's desktop defaults inherited rather than re-implemented: the 13
      GNOME extensions with Bluefin's 8-enabled/5-off split, Extension Manager,
      the Flathub remote and the Bazaar `host-etc` Flatpak preset. Parity
      compares base and image so upstream updates carry through
- [ ] Remaining GNOME preferences of our own (theme, fonts, clock)
- [x] CJK fonts (Noto Sans CJK, already in the base) + **IBus + libpinyin**
      as the declared system default (Fcitx is not installed)
- [x] Every addition lands in `delta.json`; the delta invariant stays enforced

**Non-goals:** a second package manager, a mutable `/usr`, removing upstream
apps "for taste" without a documented reason.

**Delivered:** image `.55` (base `bluefin-dx-nvidia-open`, 2,251 RPMs, 41
Flatpaks declared, IBus/libpinyin default, Helium default browser) and the
`44.20261019T132911Z.55` split ISO release.

## v0.6 — KVM and NVIDIA by reusing uBlue

**Goal:** no custom driver or virtualization work; consume what uBlue already
builds and signs.

- [x] KVM/virt-manager inherited from Bluefin DX (QEMU/KVM, libvirt-daemon-kvm,
      virt-manager, Incus, Docker, Distrobox) and asserted by the build — no
      hand-picked list, nothing rebuilt
- [x] NVIDIA open driver stack inherited from `bluefin-dx-nvidia-open:stable`
      (prebuilt `kmod-nvidia` + `nvidia-driver` + `nvidia-container-toolkit`);
      Secure Boot/MOK is handled exactly as upstream Bluefin does
- [x] Hard limit kept: no self-built kernel modules, no out-of-tree patches

**Delivered:** inherited from the NVIDIA base variant and asserted at build
time; no module we build ourselves.

**Non-goals:** supporting every GPU; NVIDIA is a variant, never the default
image.

## v0.7 — dev/test data partitions (C/D) — deferred

**Status:** deliberately paused. The C/D layout touches partitioning and the
installer, so it is kept out of the stable line for now; v1.0 does not require
it.

**Goal:** the C/D partitions are *data*, not boot slots. Development, container
builds and VM images live there; the OS stays atomic and rollbackable.

- [ ] Install-time layout: one extra partition for `/srv/dev` and `/srv/test`
      (BIB filesystem customization + a reviewed kickstart `part` rule)
- [ ] Docs: what belongs on the data partition vs. what must stay in the image
- [ ] No second OS on the machine; `bootc switch` + `rollback` remains the way
      to test a new system

**A/B is already there:** ostree deployments *are* the A/B slots. Do not add
physical A/B partitions.

**Non-goals:** dual-boot UX, a second package manager on the data partition.

## v1.0 — "would you recommend it to a friend"

1. The same delta survives three consecutive upstream Bluefin releases without
   a rollback-causing regression.
2. ISO install and `bootc switch` both pass automated tests on current and
   previous upstream releases.
3. Documented rollback exercised in CI (install → update → rollback → verify).
4. Every preference is declared, tested and removable; no untracked mutation.
5. No known unfixed regression in the last 90 days.

## Deliberate non-goals (all versions until revisited)

1. Being an independent distribution or forking Fedora/Bluefin packages.
2. A second package manager or a mutable `/usr`.
3. Reimplementing Anaconda, disk encryption or Secure Boot key management.
4. Automatic major-version upgrades without user consent.
5. KDE/XFCE/Sway variants before GNOME is boring.
6. Treating rootless containers as a multi-tenant security boundary.
7. Physical A/B partitions; ostree deployments already provide A/B.

## Versioning

- Channel tags follow the upstream stream: `44`, plus immutable
  `44.<UTC timestamp>.<run>` builds.
- The git tag `v0.x.y` marks source milestones, not image versions.
- Immutable image tags are never reused; if a build is wrong, ship a new
  timestamp.
