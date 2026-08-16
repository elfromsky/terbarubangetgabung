# Releases

## Coordinated releases

A release is a tag on `main`. One release tag identifies the Flutter, Master,
Slave, and Firebase source that belong together, plus the contracts and tests
that describe them.

Suggested tag format:

```text
v<yyyy>.<release-sequence>
```

For example, `v2026.1` identifies the first coordinated release.

## Release contents

A release tag on `main` pins, simultaneously:

- `apps/flutter/` application source,
- `firmware/master/` Master firmware source,
- `firmware/slave/` Slave firmware source,
- `firebase/` rules and configuration,
- `contracts/` the contract documentation at that revision,
- `tools/` and `rules-tests/` the tests that describe that revision.

## Process

1. Complete the coordinated change on a feature branch.
2. Merge to `main` (squash preferred for structural changes).
3. Tag `main` with a release tag.

The monorepo migration itself does not create a production release; the first
release tag is a future, deliberate action.
