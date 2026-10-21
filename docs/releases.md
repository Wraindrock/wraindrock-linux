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

Current channel: `44` → `44.20261020T045729Z.69`
(`sha256:f517b873143538fa7e7c51512280d5e727d57db59535c6abe077594490777902`).
`.57`–`.59` were documentation rebuilds of `.55`; `.69` is the release that
removed the appearance overrides, branded `/etc/system-release` and added the
application folders. Documentation and tool commits are linted but do not rebuild the image, so the
channel can lag `main`; it advances on image-affecting pushes and on the nightly
build. The immutable tag and `delta.json` are the honest reference.

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
```

Tags up to `.50` predate the rename and contain `install.iso`; `.55` and later
contain `Wraindrock-Live.iso`. They stay public for reproducibility, but use the
newest.

```bash
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:44.20261020T045729Z.69 -o disk
cd disk && sha256sum -c SHA256SUMS
```

The pre-rename `wrainrock-*` packages were deleted on 2026-10-20; only the two
`wraindrock-*` packages remain public.

## GitHub Releases

| Release | ISO | Assets |
| --- | --- | --- |
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

```bash
sha256sum -c SHA256SUMS                     # parts or artifacts
sha256sum Wraindrock-Live.iso               # must match the release notes
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```
