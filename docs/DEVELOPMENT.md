# Development model

## Repository

Canonical repository: <https://github.com/elfromsky/esh-smart-home> (renamed
from the working name `terbarubangetgabung`, Issue #21).

## Canonical branch

`main` is the canonical coordinated monorepo branch and the repository default.
It is the source of truth. One commit on `main` represents one
coordinated system source revision (Flutter + Master + Slave + Firebase +
contracts + tests together).

## Branch discipline

- Feature/fix branches branch from `main`:
  - `feat/...` for features
  - `fix/...` for fixes
  - `repo/...` for structural/repository changes
- Pull requests target `main`.
- New development always originates from `main`, never from a legacy branch.
- Directories define components. Branches **no longer** define components.

## Legacy branches (historical, read-only)

The following branches are historical component histories that predate the
monorepo. They are preserved for archaeology/reference/recovery but must not
receive new work:

| Branch | Was | New canonical location |
|--------|-----|------------------------|
| `main` (before migration) | Master firmware | `firmware/master/` |
| `slave` | Slave firmware | `firmware/slave/` |
| `clean` | revised Flutter + Firebase | `apps/flutter/`, `firebase/`, `rules-tests/` |
| `flutter` | original Flutter lineage | `apps/flutter/` |

Rules for `clean`, `slave`, and `flutter`:

- Preserve them; do not delete them.
- Do not use them for new development.
- Do not merge new feature work into them.
- Do not force-push them.
- Use them only for archaeology, reference, or recovery.

Do not delete them. Their tips are tagged `legacy/master-final`,
`legacy/slave-final`, `legacy/flutter-final`.

## Making a coordinated change

A cross-component change should be a single pull request that touches, as
needed:

```text
apps/flutter/...        producer or consumer
firmware/master/...     producer or consumer
firmware/slave/...      producer or consumer
firebase/...            rules
contracts/...           contract documentation
rules-tests/...         rules tests
tools/...               deterministic contract tests
```

## Validation before merge

CI runs Flutter, Master, Slave, Firebase rules, and deterministic contract
tests. Locally you can run each of these (see `README.md`).

## Contracts first

When a change alters an interface, update the matching document in
`contracts/` in the same pull request. The contract documents describe real
behavior; do not let them drift from the code.
