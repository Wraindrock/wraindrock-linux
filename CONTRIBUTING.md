# Contributing

## Ground rules

1. **A fix comes with a test that would have failed before it.** "It builds" is
   not evidence. For image changes, that means a new assertion in
   `tests/parity.sh`, `tests/smoke.sh` or `tests/lint.sh` that is red on `main`
   and green with your change.
2. **Do not weaken the parity test to make a build pass.** The image may differ
   from its base only in ways listed in `/usr/share/wraindrock/delta.json`. A new
   customization means extending the manifest *and* the test's expected sets in
   the same PR, with the reason in the commit message — never deleting an
   assertion or widening the diff to "anything goes".
3. **Never overwrite a published immutable tag.** The workflow enforces this;
   do not add an override.
4. **No secrets in the repository.** No tokens, keys, PATs, authfiles. CI uses
   the ephemeral `GITHUB_TOKEN` only.
5. **No runtime edits of upstream files.** Patch at build time or not at all.

## Workflow

```bash
git clone https://github.com/Wraindrock/wraindrock-linux.git
cd wraindrock-linux

bash tests/lint.sh          # always
just build && just parity && just smoke   # on a real Silverblue/Bluefin host
```

Building requires rootless podman with a working cgroup v2 delegation; a nested
container without capabilities cannot build images (you will see
`cannot write setgroups file` or lock-file errors — that is the environment, not
the repository).

## Local VM test

`tests/vm-test.sh` boots a disk image under QEMU and captures screenshots until
it sees a non-trivial frame:

```bash
tests/vm-test.sh qcow2 artifacts/wraindrock-*-qcow2/disk.qcow2 --timeout 300
tests/vm-test.sh iso   artifacts/wraindrock-*-iso/disk.iso   --timeout 1800
```

It uses KVM when `/dev/kvm` is readable *and* writable, otherwise it falls back
to TCG (slow but usable). The script does not attach a network device: the
qcow2 does not need one and the ISO carries its kickstart on the media.
Screenshots are written next to the serial log. qcow2 mode waits for
`gdm.service` and a `<hostname> login:` prompt on the serial console and checks
that the hostname is `wraindrock`. ISO mode boots the installer once, then the
installed disk, and accepts the GNOME welcome screen (compared with
`tests/fixtures/gnome-initial-setup.png`) or the Wraindrock GDM wallpaper — it
does not trust serial output, because Anaconda may install a kernel that keeps
`console=tty0`. The same test runs in CI as the `disk` workflow's `vm_test`
input; a human should still glance at the uploaded frames.

Open a pull request against `main`. PRs run lint, build, parity and smoke tests
and never publish. A maintainer merges only after those are green.

## Commit style

Short imperative subject, blank line, then *why*. The diff shows the what.

```
Add RPM-set hash to build-info.json

A date and a git SHA identify a build, but not its contents: Fedora
point releases can change packages without changing either. The hash
lets the nightly job prove "same inputs" instead of assuming it.
```

## Patches to upstream

Prefer not to patch. When a build-time patch is unavoidable:

- keep it in `patches/` as a `.patch` with a header comment explaining why and
  the upstream issue link;
- assert the patch applies to **exactly one** match (`patch --dry-run` plus a
  count check); upstream drift must fail the build, not silently apply twice;
- record it in `PATCHES.md`: what changed, why, how to rebase, when to drop it;
- delete the patch as soon as upstream carries the fix.

## Documentation rules

- Troubleshooting entries: symptom → exact error string → cause → workaround →
  escape hatch → upstream issue link.
- Design docs list deliberate non-goals and non-recoverable failure modes, not
  just the happy path.
- Every command in the docs must be copy-pasteable and tested at least once.

## Scratch space

`/tmp` inside the development container is tmpfs, so large downloads, image
layers and extracted ISOs written there consume RAM and can push the host into
swap. Run big temporary work through `tools/scratch.sh`, which creates a
directory under `./.scratch` (disk-backed, gitignored), exports it as `TMPDIR`, and removes it
when the command exits:

```bash
tools/scratch.sh bash -c 'oras pull ... -o "$TMPDIR/disk" && inspect "$TMPDIR/disk"'
```

## Review checklist

- [ ] `bash tests/lint.sh` passes
- [ ] parity/smoke pass for image changes
- [ ] new behaviour has an assertion that fails without the change
- [ ] any new deviation from the base is in `delta.json` and the parity test's
      expected sets (no silent widening of the diff)
- [ ] branding assets are SVG outlines, not `<text>` (no font dependency)
- [ ] docs updated (install, rollback, architecture or roadmap as relevant)
- [ ] no new secrets, no new long-lived credentials
- [ ] immutable-tag and signing logic untouched unless the PR is specifically
      about it
