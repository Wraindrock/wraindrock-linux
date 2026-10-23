# What Wraindrock changes relative to Bluefin DX

Wraindrock is a **bootc system image derived from
`ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable`**. Bluefin remains the
upstream: the kernel, drivers, desktop, uBlue tooling, update service and
packaging content are inherited. This page is the complete inventory of the
differences the build actually applies, and `tests/parity.sh` fails if the
image differs from the base in any way that is not recorded in
`/usr/share/wraindrock/delta.json`.

The base digest resolved by the current build is
`sha256:f91341a71615b606414dc72c5c76415ccde8bb8928c114d9bbdaac17198e54cd`.

## 1. Identity

`/usr/lib/os-release` is rewritten in place. Only these keys change:

| key | value |
|---|---|
| `NAME` | `Wraindrock` |
| `PRETTY_NAME` | `Wraindrock (Version: 44.20261022.1)` (the base version is preserved) |
| `DEFAULT_HOSTNAME` | `wraindrock` |
| `HOME_URL` | `https://github.com/Wraindrock/wraindrock-linux` |
| `DOCUMENTATION_URL` | `https://github.com/Wraindrock/wraindrock-linux/blob/main/docs/install.md` |
| `SUPPORT_URL` | `https://github.com/Wraindrock/wraindrock-linux/issues` |
| `BUG_REPORT_URL` | `https://github.com/Wraindrock/wraindrock-linux/issues` |

Every other field is inherited on purpose: `ID=bluefin`, `ID_LIKE=fedora`,
`VERSION_ID`, `VERSION_CODENAME`, `VARIANT_ID=bluefin-dx-nvidia-open`,
`OSTREE_VERSION`, `CPE_NAME`, `LOGO`, `IMAGE_ID`/`IMAGE_VERSION` and the update
identity. uBlue tooling keys off `ID`/`IMAGE_ID`, so changing them would break
`ujust`, the update service and support tooling.

`/etc/system-release` is replaced with `Wraindrock release <version> (Bluefin DX)`.
bootupd derives the UEFI firmware entry from this file, so a UEFI install shows
**Wraindrock** in the firmware boot menu instead of `Fedora`/`Bluefin`.

The image also carries its own record of the delta:

- `/usr/share/wraindrock/build-info.json` — image, version, build number, git sha, base digest, RPM counts;
- `/usr/share/wraindrock/delta.json` — the manifest described below;
- `/usr/share/wraindrock/base-os-release` and `/usr/share/wraindrock/base-rpm-set` — pristine copies of the upstream data;
- `/usr/share/wraindrock/rpm-pins` — the pins the build verified.

## 2. Desktop defaults

All defaults are system schema/dconf values; a value the user changes in
Settings always wins.

- **Wallpaper**: `/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png`
  (3840x2160), set for both light and dark mode. This is the only visual
  customisation that is kept.
- **Dock** (`org.gnome.shell favorite-apps`): Helium, Rnote, Files, Bazaar,
  Mission Center, Terminal.
- **Input**: English (US) keyboard layout plus the inherited IBus/libpinyin
  input method, both in `sources`/`mru-sources`, `show-all-sources=true`.
- **Deliberately removed** (previously prototyped, now gone): GDM logo, Plymouth
  boot splash, GRUB theme, custom icon/logo, any dconf theme tweaks. Upstream
  Bluefin's own look (fonts, accent, extensions) is left untouched.

## 3. Application folders

GNOME puts an app in every folder it matches, so each folder below has one home
per app, and the re-homed apps are appended to `excluded-apps` of all seven
Bluefin folders (`Games`, `GamingUtilities`, `Utilities`, `Development`,
`Containers`, `Wine`, `Productivity`). `tests/folders.py` proves the invariant
on the merged definitions.

| folder | contents |
|---|---|
| Accessories / 附件 | 29 GNOME desktop apps |
| Virtualization | virt-manager.desktop, io.podman_desktop.PodmanDesktop.desktop |
| Proxies | Clash Verge.desktop, sing-box.desktop |
| Social / 社交 | com.tencent.WeChat.desktop, com.qq.QQ.desktop, com.dingtalk.DingTalk.desktop |
| Wraindrock | helium.desktop, Rayburst.desktop |
| uBlue | discourse.desktop, documentation.desktop, system-update.desktop |

Bluefin's seven folders keep their upstream apps and categories. The
Accessories and Social names come from our own `.directory` files
(`wraindrock-accessories.directory`: `附件`; `wraindrock-social.directory`:
`社交`), because GNOME's `X-GNOME-Utilities` translation is “工具” (Tools).

Accessories contains:
- `org.gnome.Nautilus.desktop`
- `org.gnome.Ptyxis.desktop`
- `org.gnome.Settings.desktop`
- `org.gnome.DiskUtility.desktop`
- `org.gnome.SystemMonitor.desktop`
- `org.gnome.Tour.desktop`
- `org.gnome.tweaks.desktop`
- `orca.desktop`
- `org.gnome.Calculator.desktop`
- `org.gnome.Calendar.desktop`
- `org.gnome.Characters.desktop`
- `org.gnome.Connections.desktop`
- `org.gnome.Contacts.desktop`
- `org.gnome.DejaDup.desktop`
- `org.gnome.FileRoller.desktop`
- `org.gnome.Firmware.desktop`
- `org.gnome.Logs.desktop`
- `org.gnome.Loupe.desktop`
- `org.gnome.Maps.desktop`
- `org.gnome.Papers.desktop`
- `org.gnome.Showtime.desktop`
- `org.gnome.SimpleScan.desktop`
- `org.gnome.Snapshot.desktop`
- `org.gnome.Decibels.desktop`
- `org.gnome.TextEditor.desktop`
- `org.gnome.Weather.desktop`
- `org.gnome.baobab.desktop`
- `org.gnome.clocks.desktop`
- `org.gnome.font-viewer.desktop`

The channel folders (`Flatpak`, `AppImage`, `Bluefin`) that an earlier iteration
had are gone: grouping by packaging channel duplicated apps across the
functional folders.

## 4. First boot

- **Hostname seeding** — `wraindrock-hostname-seed.service` (oneshot, after
  local-fs) writes `DEFAULT_HOSTNAME` to `/etc/hostname` and applies it, but only
  when the file is empty or still `fedora`/`bluefin`, and only once (marker
  `/var/lib/wraindrock/hostname-seeded`). A user-chosen hostname is never
  touched.
- **Flatpak preinstall** — the image ships
  `/usr/share/flatpak/preinstall.d/wraindrock.preinstall` with 43
  apps. Bluefin's `flatpak-preinstall.service` gives up after three attempts,
  which happens before a fresh laptop has joined Wi-Fi, so our
  `wraindrock-flatpak-preinstall.service` + `.timer` (every 10 minutes) retry
  until the network is up. The wrapper checks the preinstall file hash, waits for
  the base service, runs `flatpak preinstall -y`, then verifies every declared
  app is actually installed; a matching marker alone is not trusted.
- **Dell G15/G16 control center** — `wraindrock-g15-install.service` runs only on
  machines whose DMI matches `*G15*|*G16*`. It installs
  `Wraindrock/Ian-g-control-center` from a pinned commit/archive sha256 into
  `/var/opt/g15-controller`, logs to `/var/log/wraindrock-g15-install.log`, and
  marks completion; other hardware is untouched.

## 5. Software

### Preinstalled Flatpaks (43)

- `be.alexandervanhee.gradia`
- `com.github.PintaProject.Pinta`
- `com.github.tchx84.Flatseal`
- `com.mattjakeman.ExtensionManager`
- `com.ranfdev.DistroShelf`
- `io.github.flattool.Ignition`
- `io.github.kolunmi.Bazaar`
- `io.gitlab.adhami3310.Impression`
- `io.missioncenter.MissionCenter`
- `org.gnome.Calculator`
- `org.gnome.Calendar`
- `org.gnome.Characters`
- `org.gnome.Connections`
- `org.gnome.Contacts`
- `org.gnome.DejaDup`
- `org.gnome.FileRoller`
- `org.gnome.Firmware`
- `org.gnome.Logs`
- `org.gnome.Loupe`
- `org.gnome.Maps`
- `org.gnome.NautilusPreviewer`
- `org.gnome.Papers`
- `org.gnome.Showtime`
- `org.gnome.SimpleScan`
- `org.gnome.Snapshot`
- `org.gnome.Decibels`
- `org.gnome.TextEditor`
- `org.gnome.Weather`
- `org.gnome.baobab`
- `org.gnome.clocks`
- `org.gnome.font-viewer`
- `page.tesk.Refine`
- `de.leopoldluley.Clapgrep`
- `io.github.getnf.embellish`
- `io.podman_desktop.PodmanDesktop`
- `me.iepure.devtoolbox`
- `org.gnome.Builder`
- `com.tencent.WeChat`
- `com.github.flxzt.rnote`
- `it.mijorus.gearlever`
- `com.dingtalk.DingTalk`
- `com.qq.QQ`
- `io.github.yucling.open-orpheus`

This is Bluefin's core and DX list minus `org.mozilla.firefox` (Helium is the
default browser and no Firefox preinstall was wanted), `org.mozilla.thunderbird`,
the two GTK3 theme extensions, and `com.github.tuna_os.Tavern` (no longer on
Flathub), plus WeChat, Rnote, Gear Lever, DingTalk, QQ and Open Orpheus.
Bluefin's remaining core apps stay a documented one-liner
(`ujust install-system-flatpaks`) because Bluefin itself does not bake them.

Helium is the default handler for `http`, `https`, `text/html` and
`application/xhtml+xml` via `/etc/xdg/mimeapps.list`.

### Pinned RPMs

| package | version | source |
|---|---|---|
| `helium-bin` | `0.20.1.1-1.fc44` | download.copr.fedorainfracloud.org |
| `clash-verge` | `2.5.8-1` | github.com |
| `rayburst` | `4.1.0-1` | github.com |
| `sing-box` | `1.14.3-1` | github.com |

All four have no Flatpak. They are downloaded at build time from the pinned URL,
checked against the pinned sha256 and expected version, installed with `rpm -i`,
and recorded in `delta.json`. The closure is already in the base, so no
repository resolution happens and no base package is replaced. `/opt` is turned
into a real directory first because Bluefin's `/opt` symlink into `/var` dangles
inside a bootc deployment. A daily `upstream-watch` workflow bumps a pin and
publishes a new signed image tag when upstream releases.

**Not installed**: the HPLIP Qt GUI (`hplip-gui`). The inherited HPLIP core
(CUPS/SANE backends, `hp-setup`) is asserted to be complete.

## 6. Install media

- `disk.yml` builds a qcow2 and an Anaconda ISO with bootc-image-builder, from
  the same image digest, and names the ISO `Wraindrock-Live.iso`.
- The ISO boot menu is patched to two entries:
  1. `Install Wraindrock (interactive, choose disks)` — a partial kickstart
     (`/interactive.ks`) only supplies the bootc payload location, so Anaconda
     asks for the disk/partitioning and user account; language is chosen at
     GNOME Initial Setup.
  2. `Install Wraindrock - erase first disk (unattended)` — the generated
     kickstart, an explicit opt-in that wipes the first disk.
- Both kickstarts switch the installed system to
  `ghcr.io/wraindrock/wraindrock-linux:44`, with the original digest as a
  fallback, so installed machines track the moving channel instead of freezing
  on one immutable tag.
- CI installs the ISO under KVM, boots the installed disk to the GNOME welcome
  screen, boots the qcow2 and requires `wraindrock login:`, and captures the
  interactive installer screens.
- Verified qcow2/ISO/SHA256SUMS are published as immutable OCI artifacts on
  GHCR, and the ISO is also split into <2 GiB parts with a self-extracting
  script and uploaded to a GitHub Release. `tools/get-live-iso.sh` downloads the
  newest release without authentication and resumes interrupted transfers.

## 7. Files added and modified

Modified:

- `/usr/lib/os-release`
- `/etc/system-release`
- `/usr/share/glib-2.0/schemas/gschemas.compiled`
- `/usr/share/rpm/rpmdb.sqlite`
- `/etc/dconf/db/distro`
- `/opt`

Added:

- `/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override`
- `/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png`
- `/usr/libexec/wraindrock-hostname-seed`
- `/usr/lib/systemd/system/wraindrock-hostname-seed.service`
- `/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service`
- `/usr/share/wraindrock/base-os-release`
- `/usr/share/wraindrock/base-rpm-set`
- `/usr/share/wraindrock/rpm-pins`
- `/usr/share/wraindrock/build-info.json`
- `/usr/share/wraindrock/delta.json`
- `/usr/share/flatpak/preinstall.d/wraindrock.preinstall`
- `/usr/libexec/wraindrock-flatpak-preinstall`
- `/usr/lib/systemd/system/wraindrock-flatpak-preinstall.service`
- `/usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer`
- `/etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer`
- `/usr/libexec/wraindrock-g15-install`
- `/usr/lib/systemd/system/wraindrock-g15-install.service`
- `/etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service`
- `/etc/xdg/mimeapps.list`
- `/etc/dconf/db/distro.d/10-wraindrock-folders`
- `/usr/share/desktop-directories/wraindrock-accessories.directory`
- `/usr/share/desktop-directories/wraindrock-social.directory`

RPM additions:

- `clash-verge-2.5.8-1.x86_64`
- `helium-bin-0.20.1.1-1.fc44.x86_64`
- `rayburst-4.1.0-1.x86_64`
- `sing-box-1.14.3-1.x86_64`

## 8. Build, CI and tooling

- Base image is resolved to a digest and passed as `BASE_REF`, so a moving tag
  cannot change the build between pull and build.
- `build.yml`: lint always, image build only when a changed path can affect the
  image (docs/tools/tests-only pushes skip the build); parity, bootc lint, smoke
  test, keyless cosign sign/verify, immutable tag guard, `:previous`
  preservation, anonymous pull check.
- `disk.yml`, `release-iso.yml`, `upstream-watch.yml` as described above.
- Tests: `tests/lint.sh`, `parity.sh`, `smoke.sh`, `folders.py`, `vm-test.sh`,
  `iso-menu.sh`, `iso-interactive-shots.sh`, `png-stats.py`.
- `tools/get-live-iso.sh`, `release-iso.sh`, `scratch.sh`.

## 9. Not changed, or explicitly out of scope

- No fork of the kernel, systemd, GNOME or any Fedora/uBlue package.
- No mutable `/usr`: software changes arrive as new image tags.
- No physical A/B partitions: ostree deployments provide rollback; the C/D
  dev/test data partitions are deferred.
- No custom installer UI or encryption/partitioning defaults beyond the stock
  unattended kickstart.
- No self-built kernel modules: NVIDIA/KVM support comes from the uBlue base.
- The project is a personal remix, not an independent distribution.
