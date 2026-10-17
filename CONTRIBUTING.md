# Contributing

## Ground rules

1. **A fix comes with a test that would have failed before it.** "It builds" is
   not evidence. For image changes, that means a new assertion in
   `tests/parity.sh`, `tests/smoke.sh` or `tests/lint.sh` that is red on `main`
   and green with your change.
2. **Do not weaken the parity test to make a build pass.** If customization
   intentionally changes the RPM set, update the delta manifest and the test
   together, in the same PR, with the reason in the commit message.
3. **Never overwrite a published immutable tag.** The workflow enforces this;
   do not add an override.
4. **No secrets in the repository.** No tokens, keys, PATs, authfiles. CI uses
   the ephemeral `GITHUB_TOKEN` only.
5. **No runtime edits of upstream files.** Patch at build time or not at all.

## Workflow

```bash
git clone https://github.com/Wraindrock/wrainrock-linux.git
cd wrainrock-linux

bash tests/lint.sh          # always
just build && just parity && just smoke   # on a real Silverblue/Bluefin host
```

Building requires rootless podman with a working cgroup v2 delegation; a nested
container without capabilities cannot build images (you will see
`cannot write setgroups file` or lock-file errors — that is the environment, not
the repository).

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

## Review checklist

- [ ] `bash tests/lint.sh` passes
- [ ] parity/smoke pass for image changes
- [ ] new behaviour has an assertion that fails without the change
- [ ] docs updated (install, rollback, architecture or roadmap as relevant)
- [ ] no new secrets, no new long-lived credentials
- [ ] immutable-tag and signing logic untouched unless the PR is specifically
      about it
