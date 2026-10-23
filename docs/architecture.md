# Architecture

Wraindrock is a **bootc system image**: an OCI container whose root
filesystem is the operating system. This document covers how the image is
produced, what is invariant about it, how releases are identified and signed,
and what the project deliberately does not do.

## Feeding from uBlue Silverblue

The base feedstock is Universal Blue's Silverblue image:

```
ghcr.io/ublue-os/silverblue-main:44
```

uBlue Silverblue is itself a bootc image: a GNOME desktop on Fedora Silverblue,
with uBlue's update and application plumbing. We consume it as an OCI base
layer, pin the resolved digest at build time, and record it in the image. The
identity contract the build requires is `ID=fedora` with `VARIANT_ID=silverblue`.

The base is deliberately lean, so this image reapplies the Bluefin DX layer:
the nine Bluefin GNOME extensions and their dconf presets, the seven Bluefin
application folders, the Flathub remote and Bazaar preset, and the NVIDIA +
developer-tool stack. The NVIDIA userland and kernel module are staged from
`ghcr.io/ublue-os/akmods-nvidia-open:main-44-<kernel>`; the kernel must match
the base exactly, and the build fails if it does not. Docker, Incus, libvirt,
QEMU, virt-manager and Distrobox are installed from Fedora and Docker
repositories at build time. Parity asserts the extension set, the enabled list,
the NVIDIA stack and the virtualisation stack, so a base refresh cannot
silently drop them.

Wraindrock still does not own the desktop, kernel, firmware or driver sources:
those belong to Fedora and Universal Blue. What this repository owns is the
declared, tested layer that turns the lean base into the Bluefin DX experience
with personal defaults.

### Why bootc and not `rpm-ostree compose`

Upstream already made this choice: uBlue Silverblue is a bootc image, and Fedora is
moving Atomic Desktops to container-native builds (the "Build Atomic Desktops
with Konflux" change targets Fedora 46). Building with bootc today:

- consumes exactly the artifact upstream publishes and tests;
- makes local reproduction a `podman build` rather than a Koji compose;
- gives OCI-native distribution, signing and mirroring for free;
- keeps `rpm-ostree` out of the *build* path (it remains the update backend on
  the installed system, which is fine).

## Build pipeline

Every push runs lint. A push is only built and published when at least one
changed file can affect the image (`image.env`, `Containerfile`,
`build_files/**`, or anything outside the known documentation/tool/test set);
unknown paths always build. Documentation, `tools/` and `tests/` are not
COPYed into the image — the Containerfile bind-mounts `build_files/` at build
time — so a docs-only rebuild would only change `build-info.json` and force
every client to download the full build layer again. Nightly and manual runs
always build. As a consequence, `:44` can lag `main` by documentation commits;
the image's `build-info.json` (`git_sha`) is the honest record of what it was
built from.

```
image.env ──► workflow (lint) ──► pull base, resolve digest
                                        │
                                        ▼
                              Containerfile (FROM digest-pinned base)
                                        │
                              build_files/build.sh
                              (assert base identity, brand, write delta)
                                        │
                              bootc container lint
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
             parity test           smoke test           (PRs stop here)
                    │                   │
                    └─────────┬─────────┘
                              ▼
                 push immutable tag ──► cosign sign ──► push channel tags
```

Everything is driven by `image.env`, so "which uBlue stream is this?" is a
one-line, reviewable change.

### The delta invariant (v0.2+)

v0.1–v0.3 enforced "identical to Fedora Silverblue". v0.4 moves the baseline to
uBlue Silverblue and keeps the falsifiable part machine-checkable:

> The image's RPM set is the base's plus exactly the packages declared in
> `/usr/share/wraindrock/delta.json`; no base package is removed or upgraded.
> `/usr/lib/os-release` differs only in the listed identity keys, and every
> added file is declared there.

The parity test diffs `rpm -qa` with `comm` and requires the actual additions to
equal `rpm.added`, the removals to be empty, and the additions to be the four
known packages. For os-release it parses both files and allows only the changed
keys `NAME`, `PRETTY_NAME`, `DEFAULT_HOSTNAME` and the four URLs. A removed, added or changed key outside that set fails the build;
each declared value is then cross-checked against the actual file, so the
manifest cannot drift into a polite fiction. The test also proves the app folders
override is compiled into `gschemas.compiled` and that `rpm -V --nomtime` on the
package owning `/usr/lib/os-release` (looked up dynamically — the base owns it,
not a Fedora identity package) reports exactly the two documented identity
files, `/usr/lib/os-release` and `/etc/system-release`. (`--nomtime` is required: image layers store mtime 0 for
ostree hardlinks while rpm headers record build time, so the timestamp check
would flag every file and hide the real diff.)

Adding a customization therefore means adding it to the manifest **and**
teaching the test about it — never relaxing the diff.

The manifest also covers the files the build itself adds: the identity,
hostname-seeding, application-folder and software files sit next to the
`/usr/share/wraindrock/` provenance files in `files.added`, and parity requires
that set to match exactly. Because four RPMs are baked, the image's RPM
database *is* written by design; the build asserts the sqlite WAL is
checkpointed (0 bytes) after the last `rpm` call and keeps the sidecars the base
ships, since `rpm` on a read-only `/usr` relies on the pre-created `-shm`/`-wal`.
`rpmdb.sqlite` is listed under `files.modified`. The build passes
`--no-hostname` to `podman build`, so the image ships no `/etc/hostname` at all
(buildah's empty placeholder would otherwise count as a configured, empty
hostname).

`DEFAULT_HOSTNAME` alone is not enough on an installed system:
`bootc-image-builder`'s install path inherits the base deployment's `/etc`, so a
fresh install came up as `fedora` in the v0.3 VM test. The image therefore ships
`wraindrock-hostname-seed.service` (wired into `sysinit.target.wants`), which runs
once before login. It reads `DEFAULT_HOSTNAME` from `/usr/lib/os-release` and
replaces only an unconfigured value — empty, or the base default `fedora` (or
`fedora`) — then writes `/var/lib/wraindrock/hostname-seeded`. A hostname chosen by the user or
installer is never overwritten, and the marker makes later boots no-ops. The
unit is exercised in parity against a fixture with a temporary root.

### Branding

Visual personalisation was deliberately removed: the logo, GDM artwork,
Plymouth splash and boot-menu theme are better left upstream, and the wallpaper
is stock Silverblue too. The delta is identity (display name and UEFI entry),
application grouping, and the curated defaults below:

| Change | Mechanism |
| --- | --- |
| display name, pretty name, default hostname | `sed` on `/usr/lib/os-release` |
| `LOGO`, `ID`, `ID_LIKE`, `CPE_NAME`, version fields | left at upstream values — the icon stays Fedora's, uBlue tooling keys off `ID=fedora`, and the CPE keeps naming Fedora |
| UEFI boot entry name | `/etc/system-release` rewritten to `Wraindrock release <ver> (Silverblue)`; bootupd derives the firmware label from it (`get_product_name`), falling back to os-release `NAME` |
| default dock | `[org.gnome.shell] favorite-apps` in `zzzz-wraindrock.gschema.override`: Helium, Rnote, Files, Bazaar, Mission Center, Terminal; a user's own value wins |
| application folders | `/etc/dconf/db/distro.d/10-wraindrock-folders` extends `folder-children` with Virtualization, Proxies, Social (社交), Wraindrock and uBlue, lists their apps explicitly, and excludes re-homed apps from Bluefin's folders; one home per app; `dconf update` compiles the distro database |
| default hostname | `DEFAULT_HOSTNAME` (no `/etc/hostname` is shipped; an installer or user file still wins) |
| input method | IBus is inherited from GNOME (no Fcitx in the image). Keyboard layouts and input methods are distinct entries in the source list; the English (US) layout stays and the only addition is the `libpinyin` input method in `[org.gnome.desktop.input-sources]` (`zzzz-wraindrock.gschema.override`). A user's own value wins |

The dconf override sorts after Fedora's `10_*`
`zz0-`/`zz1-` overrides (ours is `zzzz-`), and replaces `picture-uri` and
`picture-uri-dark`. GDM's greeter reads the same
`org.gnome.desktop.background` defaults, so the login background follows without
a separate mechanism.

The UEFI label matters because bootupd's `update_firmware()` takes the label
from `/etc/system-release` and strips everything from the word `release`; with
Fedora's symlink it would name the firmware entry "Fedora". The file is replaced
with a real file owned by no package path, so it is declared under
`files.modified` and parity expects it alongside `os-release`.

Application folders are declarative dconf, so a user can still move launchers.
Bluefin's seven folders (Games, GamingUtilities, Utilities, Development,
Containers, Wine, Productivity) keep their upstream apps and categories; the
drop-in adds one folder per purpose and excludes the re-homed apps from every
upstream folder. GNOME matches `(apps ∪ categories) − excluded-apps` per folder,
so listing an app in two places shows it twice; `tests/folders.py` merges the
upstream definition with ours and fails if any app would land in more than one
folder. Channel folders (`Flatpak`, `AppImage`) were removed for this reason.
A separate Social (社交) folder groups WeChat, QQ and DingTalk with their own
`.directory` file. A separate Accessories folder (附件) lists every GNOME desktop application (RPM
desktop files from the base rpmdb plus Flathub launchable ids); its name comes
from `wraindrock-accessories.directory` (`Name=Accessories`, `Name[zh_CN]=附件`).
Bluefin's Utilities folder (工具) keeps only its own tools, and the GNOME apps
are excluded from it, so Accessories and Tools never overlap. The ids are kept
in `tests/fixtures/gnome-desktop-apps.txt`, and lint/parity fail if any of them
is no longer filed under Accessories.

`glib-compile-schemas` *is* run, because GSettings only reads compiled schemas;
that rewrites `/usr/share/glib-2.0/schemas/gschemas.compiled`, which the delta
lists under `files.modified`. `dconf update` does the same for the distro
database. `gtk-update-icon-cache` is not run.

### Software

Two delivery mechanisms keep the out-of-box set small and updatable:

- **Flatpaks install on first boot.** `/usr/share/flatpak/preinstall.d/wraindrock.preinstall`
  declares 43 apps and the retry wrapper runs
  `flatpak preinstall -y` once the network is up. That service gives up after
  three attempts, which a fresh install usually exhausts before Wi-Fi is
  configured, so `wraindrock-flatpak-preinstall.timer` retries our wrapper
  every ten minutes until the preinstall file's hash is recorded in
  `/var/lib/wraindrock/flatpak-preinstall.sha256`. Helium is the default
  handler in `/etc/xdg/mimeapps.list`; Firefox stays installed and selectable.
  The other Bluefin apps remain a one-liner (`ujust install-system-flatpaks`)
  because Bluefin itself does not bake them.
- **The four app RPMs are baked** (Helium from the official `imput/helium` COPR,
  Clash Verge Rev, Rayburst, sing-box/SFL) because they have no Flatpak.
  HPLIP's core is inherited from Fedora Silverblue: the build asserts the CUPS/SANE
  backends and `hp-setup` are present, and deliberately does not install the
  optional Qt GUI. Every baked RPM is downloaded at build time from a pinned
  upstream URL, checked against a pinned sha256 and expected version, and
  installed with `rpm -i`; nothing is resolved from a repository, and a removal
  of any base package fails the build. Their `%post`
  scriptlets run as root inside the build container. They update with the image;
  `rpm-ostree override replace`
  gives a per-package escape hatch between image releases. SFL installs only
  under `/opt`; because the base's `/opt` is a symlink into `/var` and a bootc
  deployment does not carry `/var`, the build replaces it with a real directory
  so the payload is part of the image (and therefore read-only at runtime).

Backend caveats are deliberate and documented rather than patched: Clash Verge
and SFL both want TUN/network control and should not run at the same time;
WeChat runs through XWayland/portals; Gear Lever needs FUSE for AppImages;
the first-boot preinstall needs working networking.

### Provenance

`build_files/build.sh` writes three files:

- `/usr/share/wraindrock/build-info.json` — schema, image/version, build
  number, git SHA, build date, base image + digest, Bluefin version, identity
  marker, RPM count, RPM-set SHA-256.
- `/usr/share/wraindrock/delta.json` — every intended difference from the base:
  changed/added os-release keys with their actual values, modified files and
  added files. This is the manifest the parity test enforces.
- `/usr/share/wraindrock/base-os-release` — pristine copy of the base's
  `/usr/lib/os-release`, so "what was this built from?" survives even though
  the live file is now branded.

The build fails if the base is not `ID=bluefin`, `VERSION_ID=44`,
`VARIANT_ID=bluefin-dx*`, or if `/usr/bin/bootc` / `/usr/lib/bootc` are missing.
That is a single-match assertion on the base, not a comment.

## Tags and release identity

| Tag | Example | Mutability | Purpose |
| --- | --- | --- | --- |
| immutable | `44.20261017T061500Z.42` | never overwritten | artifact of record |
| channel | `44` | moves per build | what users follow |
| alias | `latest` | moves per build | newest channel |
| rollback aid | `previous` | moves per build | outgoing channel image |

Rules, enforced in CI:

1. Every build first computes the immutable tag from the Bluefin stream
   (`44`), the UTC build timestamp and the workflow run number.
2. Before pushing, CI checks the registry for that tag and **fails if it already
   exists**. Published artifacts are never replaced.
3. Only `main` publishes. Pull requests build and test but cannot touch the
   registry, so a PR cannot become someone's next `bootc update`.
4. Before moving `44`, CI tags the current `44` digest as `previous` and pushes
   it. This gives a second, registry-side rollback target in addition to the
   local `bootc rollback` deployment.
5. Channel tags are pushed only after the immutable artifact exists, so a
   broken channel push can be retried without reusing an artifact tag.

Nightly rebuilds keep the channel current with upstream security updates even when
Wraindrock's own source doesn't change. A rebuild of the same base digest and
same commit yields the same RPM set; the `build-info.json` RPM hash is the cheap
way to spot drift.

## Update lifecycle on an installed system

```
bootc update        fetch :44, pull new image, stage deployment
systemctl reboot    boot into the new deployment
bootc rollback      select the previous deployment
systemctl reboot    boot into it
```

`bootc` stages a new deployment; the old one stays on disk. Rollback is a local,
offline operation — it does not depend on the network or on the registry, which
is why it works when a release is bad or the network is down.

Automatic updates are intentionally **not** enabled by this image. A
distribution that updates its own kernel and desktop without an operator in the
loop is a support problem; the default is manual `bootc update`, with an opt-in
timer documented in [docs/install.md](install.md).

## Trust and supply chain

- **Base:** Universal Blue's Bluefin DX image (`ghcr.io/ublue-os/bluefin-dx`),
  pulled by digest at build time and recorded in `build-info.json`. uBlue's own
  build and signing chain is trusted transitively.
- **Build:** public GitHub Actions workflow; no self-hosted runner, no long-lived
  registry credential. The only secrets are the ephemeral `GITHUB_TOKEN` and the
  OIDC token used by cosign.
- **Publish:** `ghcr.io`, immutable tags, keyless Sigstore signature whose
  certificate identity is bound to this repository's workflow.
- **Verify:** `cosign verify` with
  `--certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/'`
  and issuer `https://token.actions.githubusercontent.com`.

What this does **not** protect against: a compromised Bluefin DX or Fedora base
image, a compromised GitHub Actions runner, a compromised cosign/Sigstore
dependency, or a malicious commit that a maintainer merges. See [SECURITY.md](../SECURITY.md)
for the boundary and the reporting process.

## Deliberate non-goals

These are design decisions, not backlog items:

1. **A custom installer UX before v0.3.** `bootc switch` on an existing Fedora
   Atomic system remains the upgrade path. v0.3 adds bootc-image-builder's stock
   Anaconda ISO with a two-entry boot menu: interactive (default) or unattended
   (erase first disk). The interactive entry uses a partial kickstart that only
   names the bootc payload; the installed system's own Anaconda UI does the
   partitioning and asks for users. A custom installer UX and encryption flow
   stay out of scope.
2. **A package manager that mutates the live root.** `rpm-ostree install` layers
   are a user escape hatch on the installed system, not a Wraindrock feature. The
   image is the unit of change.
3. **Forking Fedora/Bluefin packages or the kernel through v0.7.** There is
   nothing Wraindrock can meaningfully test about a forked glibc or kernel yet.
   Build-time patches, when they arrive, must assert a single match and be
   recorded in `PATCHES.md`.
4. **KDE/XFCE/other spins.** One variant until one variant is reliable.
5. **TLS / disk encryption / installer UX.** Handled by Fedora/Anaconda/bootc;
   reimplementing it is how distributions die.
6. **Automatic updates by default.** See above.
7. **Rootless container security as a tenant boundary.** bootc images run
   system-level services; rootless podman is a convenience, not a security
   boundary. Documented in SECURITY.md rather than pretended otherwise.
8. **Rebranding upstream identity.** `ID`, `IMAGE_ID`, `VARIANT_ID` and
   `CPE_NAME` stay upstream's. uBlue tooling, `ujust`, update services and
   support tooling match on them; we change what a user sees, not what the
   system claims to be.
9. **A physical A/B partition layout.** ostree deployments *are* the A/B slots.
   The C/D partitions are data for development and testing, not second operating
   systems.

## Failure modes that are not automatically recoverable

- **Registry outage during `bootc update`:** the running system is unaffected;
  retry later. Rollback remains available offline.
- **Disk full during staging:** `bootc` fails the update and leaves the current
  deployment; free space and retry. There is no auto-cleanup that deletes
  deployments behind the user's back.
- **Corrupted base image or interrupted push:** an interrupted push can leave a
  partially uploaded tag in some registries. The immutable tag is only trusted
  after `cosign verify` succeeds; if verification fails, do not boot it.
- **Bad kernel/firmware in the Bluefin/Fedora base:** `bootc rollback` to `previous` or to
  the prior deployment. If the system cannot boot at all, use the Fedora
  Atomic rollback entry in the bootloader.
