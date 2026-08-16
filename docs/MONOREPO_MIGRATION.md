# Monorepo migration (Issue #8)

This document records the migration of this repository from a
branch-as-component model into a coordinated monorepo, and the preservation of
the legacy histories.

- Issue: <https://github.com/elfromsky/terbarubangetgabung/issues/8>
- Strategy: normal feature branch from `main`, snapshot import, squash merge.
- Intentional runtime behavior changes: **zero**.

## Legacy revision baseline

| Component | Legacy branch | Legacy SHA | Legacy tag |
|-----------|---------------|------------|------------|
| Master | `main` | `9246844aeffe8f61dfbc00841f5d44c4518204a5` | `legacy/master-final` |
| Slave | `slave` | `7cd09508599db4dcfd72c9c3d3c78a9476a92e38` | `legacy/slave-final` |
| Flutter (revised) | `clean` | `8b9346e6c6729dcf923e8a24cef0d0cafd7e3fcd` | `legacy/flutter-final` |
| Flutter (original) | `flutter` | `6cb3438d409bb0759738224a0c89e3050348c0a4` | *(not migrated)* |

- `origin/flutter` is the older Flutter lineage; `origin/clean` is the final
  revised Flutter lineage used for migration.
- `origin/main`, `origin/slave`, and `origin/clean` are unrelated histories
  (no shared merge base). Only `flutter -> clean` shares ancestry
  (merge base `6cb3438`).

## Migration strategy

We created a normal feature branch (`repo/issue-8-monorepo`) from the legacy
Master tip (`main`), relocated the Master source, and imported immutable
snapshots of the revised Flutter (`clean`) and Slave (`slave`) trees into
directories. The branch was then squash-merged into `main`.

Why not merge unrelated histories: `git merge --allow-unrelated-histories` was
explicitly avoided. It would have produced confusing ancestry, hard-to-read
blame, and large rename/copy noise, with little benefit, and it is explicitly
prohibited by the issue.

Why not an orphan default-branch replacement: an ordinary `main`-based pull
request keeps normal review flow, preserves the current `main` ancestry, and
avoids force-pushing or replacing the default branch.

## Source -> target mapping

| Legacy path/category | Source | New monorepo path | Method |
|----------------------|--------|-------------------|--------|
| Flutter app (lib, test, android, ios, linux, macos, web, windows, images, pubspec) | `clean` | `apps/flutter/` | snapshot import |
| Flutter docs + diagrams | `clean` | `apps/flutter/docs/` | snapshot import |
| Master source (include, lib, src, test, platformio.ini) | `main` | `firmware/master/` | `git mv` |
| Master diagrams | `main` | `firmware/master/docs/` | `git mv` |
| Master `.vscode` | `main` | `firmware/master/.vscode/` | `git mv` |
| Slave source (src) | `slave` | `firmware/slave/` | snapshot import |
| Slave docs + diagrams + notes | `slave` | `firmware/slave/docs/` | snapshot import |
| Slave `.serena` | `slave` | `firmware/slave/.serena/` | snapshot import |
| Firebase config/rules (firebase.json, database.rules.json, firestore.rules, firestore.indexes.json, .firebaserc) | `clean` | `firebase/` | snapshot import |
| Rules tests | `clean` | `rules-tests/` | snapshot import (paths adjusted) |
| Diagnostics/tests (evidence_gaps_tests.py, diagnose-broken-revision.py, duplicate_cache_tests.py, reports) | `clean` + `slave` | `tools/` | snapshot import (one path adjusted) |
| CI helper scripts | `main` | `scripts/ci/` | kept (hygiene script adapted) |
| CI workflows | `main`, `clean` | `.github/workflows/` | superseded by coordinated workflows |
| Root `.gitignore`, `README.md` | n/a | repo root | consolidated anew |

## Inventory reconciliation

Tracked files at each legacy tip:

| Component | Tracked files | Outcome |
|-----------|---------------|---------|
| Master (`9246844`) | 39 | all mapped into `firmware/master/`, `scripts/ci/`, or superseded by root consolidation |
| Slave (`7cd0950`) | 27 | all mapped into `firmware/slave/` or `tools/` |
| Flutter (`8b9346e`) | 245 | all mapped into `apps/flutter/`, `firebase/`, `rules-tests/`, or `tools/` |

No runtime source, PlatformIO config, Android config, Firebase rule, or
deterministic test file was intentionally omitted. Generated/CI-workaround
artifacts (the detached-slave worktree step in the old firmware CI) were
superseded, not lost.

## Intentional path/content changes

Only two files required content changes, both path-only for monorepo
operation (classification: PATH/CI MIGRATION ONLY):

- `rules-tests/rules.test.js`: rule paths `../firestore.rules` and
  `../database.rules.json` -> `../firebase/firestore.rules` and
  `../firebase/database.rules.json`.
- `tools/duplicate_cache_tests.py`: source path `src/room_device_routing.cpp`
  -> `firmware/slave/src/room_device_routing.cpp`.
- `rules-tests/package.json`: `test:emulator` gains `--config
  firebase/firebase.json`.
- `scripts/ci/check-credential-hygiene.sh`: extended to cover both
  `firmware/master/include/` and `firmware/slave/src/`.

All other runtime source was moved/copied byte-identically (see validation
below).

## Validation summary

- Flutter: `pub get`, `analyze` (no issues), `test` (all green) pass locally;
  CI also runs `build apk --debug`.
- Master & Slave: compile via PlatformIO CI with synthetic provisioning
  (environment `esp32-s3-devkitc-1`).
- Firebase rules: emulator tests pass (`rules-tests`), preserving sensorLogs
  authorization and `issued_at` freshness suites.
- Deterministic tests: `tools/evidence_gaps_tests.py` and
  `tools/duplicate_cache_tests.py` remain green.

## Rollback / archaeology

- Legacy sources remain available at their original SHAs and branches
  (`slave`, `clean`, `flutter`) and annotated tags (`legacy/*`).
- To inspect a legacy component exactly as it was, check out its tag:

  ```bash
  git fetch --all --prune
  git checkout legacy/master-final -- <path>
  ```

- The migration is a single squash-merged commit; reverting it is a normal
  `git revert` on `main`.
