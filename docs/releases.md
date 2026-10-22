# Published artifacts

Everything below is public on GHCR and GitHub. Tags that carry a version are
never overwritten; always prefer the newest one.

## System image

`ghcr.io/wraindrock/wraindrock-linux`

| Tag | Meaning |
| --- | --- |
| `44` | Bluefin 44 channel — what `bootc switch …:44` follows |
| `latest` | Alias of the newest channel |
| `previous` | Where `44` pointed before the last release |
| `44.<UTC>.<run>` | Immutable build; quote this when reporting a bug |

Current channel: `44` → `44.20261022T145603Z.93`
(`sha256:7897a3fd5878208abd7fb733ae693f0777f674e53ec110cd688b9c9cdce21e09`,
revision `2a2d125`).
`.57`–`.59` were documentation rebuilds of `.55`; `.69` removed the appearance
overrides, branded `/etc/system-release` and added application folders; `.78`
gave every app exactly one folder; `.80` curated the default dock and added the
`uBlue` folder; `.82` files every GNOME desktop application under Utilities;
`.87` added the Flatpak retry timer; `.88` split Accessories from Tools; `.89`
made installs follow the `:44` channel; `.93` fixed the Flatpak retry wrapper and asserted the scanner stack; `.91` replaced Thunderbird with
DingTalk, QQ and Open Orpheus and added the Dell G15/G16 control-center
first-boot installer. Documentation, tool and test commits are
linted but do not rebuild the image, so the channel can lag `main`; it advances
on image-affecting pushes and on the nightly build. The immutable tag and
`delta.json` are the honest reference.

```bash
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
```

## Disk artifacts (qcow2 + live ISO)

`ghcr.io/wraindrock/wraindrock-linux-disk:<image version>`

Each tag is one OCI artifact (`application/vnd.wraindrock.disk.v1+json`) with
three layers: `file:disk.qcow2`, `file:Wraindrock-Live.iso` and
`file:SHA256SUMS`. Published tags:

```
44.20261018T010940Z.22   44.20261018T121004Z.37   44.20261019T052954Z.50
44.20261018T031902Z.30   44.20261018T150250Z.43   44.20261019T132911Z.55
44.20261018T071737Z.32   44.20261018T161148Z.47
44.20261018T100652Z.35   44.20261018T233302Z.48   44.20261020T045729Z.69
44.20261021T045220Z.73   44.20261021T134851Z.78   44.20261022T051527Z.82
44.20261022T145603Z.93   44.20261022T132634Z.91
```

Tags up to `.50` predate the rename and contain `install.iso`; `.55` and later
contain `Wraindrock-Live.iso`. They stay public for reproducibility, but use the
newest.

```bash
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:44.20261022T145603Z.93 -o disk
cd disk && sha256sum -c SHA256SUMS
```

The pre-rename `wrainrock-*` packages were deleted on 2026-10-20; only the two
`wraindrock-*` packages remain public.

## GitHub Releases

| Release | ISO | Assets |
| --- | --- | --- |
| [`44.20261022T145603Z.93`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261022T145603Z.93) | `Wraindrock-Live.iso`, 6,876,561,408 B, `sha256:e740e088412a5fb610c0bb44ffd4be1294210ea2df772714968e75d7c3590d12` | 4 parts (1.94 GB ×3 + 883 MB) + `-extract.sh` + `SHA256SUMS` |
| [`44.20261022T132634Z.91`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261022T132634Z.91) | `Wraindrock-Live.iso`, 6,876,561,408 B, `sha256:20de9df6b9641da2019462985599e67dcaf536990ed5e380829a9204401c4f91` | 4 parts (1.94 GB ×3 + 882 MB) + `-extract.sh` + `SHA256SUMS` |
| [`44.20261022T051527Z.82`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261022T051527Z.82) | `Wraindrock-Live.iso`, 6,875,774,976 B, `sha256:08cb0cbff3c400a9e0808913e07019dca20f7d2876705dd6f636ee2977ae863e` | 4 parts (1.94 GB ×3 + 881 MB) + `-extract.sh` + `SHA256SUMS` |
| [`44.20261021T134851Z.78`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261021T134851Z.78) | `Wraindrock-Live.iso`, 6,867,451,904 B, `sha256:453a664bedfa435f622ef07f12f4b57fd0bd8cfa2455f3f8a3f38391bfd0d291` | 4 parts (1.94 GB ×3 + 915 MB) + `-extract.sh` + `SHA256SUMS` |
| [`44.20261020T045729Z.69`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261020T045729Z.69) | `Wraindrock-Live.iso`, 6,868,303,872 B, `sha256:4578dc91b6bf344ef979bade21f74b1727ccb3ed8b29466c2948f2877862057d` | 4 parts (1.94 GB ×3 + 916 MB) + `-extract.sh` + `SHA256SUMS` |
| [`44.20261019T132911Z.55`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261019T132911Z.55) | `Wraindrock-Live.iso`, 6,869,286,912 B, `sha256:84039f3b01689959490fe68c0d9c2fa5b084d9078ee84e9d9ac928b97c15a3cb` | 4 parts (1.94 GB ×3 + 917 MB) + `-extract.sh` + `SHA256SUMS` |

No earlier releases exist; builds before `.55` were published only as GHCR disk
artifacts. New releases are cut by `.github/workflows/release-iso.yml`, which
fetches the ISO layer from GHCR, builds the deterministic split archive and
publishes it directly (no draft).

Download from the release page in a browser, or let the helper resolve the
newest release and do the work (no GitHub account needed):

```bash
curl -fsSL https://raw.githubusercontent.com/Wraindrock/wraindrock-linux/main/tools/get-live-iso.sh | bash
sha256sum Wraindrock-Live.iso
```

## Verifying

Documentation-only pushes are linted but deliberately not rebuilt (see
`docs/architecture.md`), so a release entry can be newer than the channel tag.

```bash
sha256sum -c SHA256SUMS                     # parts or artifacts
sha256sum Wraindrock-Live.iso               # must match the release notes
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```
