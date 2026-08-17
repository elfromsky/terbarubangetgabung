# Releases

This document is the authoritative release process for the ESH (e-smart-home)
coordinated monorepo. It defines the version convention, the compatibility
policy, the release procedure, artifact naming, and rollback references.

> **Convention migration note.** The earlier monorepo-migration scaffold
> suggested a date-based tag `v<yyyy>.<release-sequence>` (e.g. `v2026.1`).
> That convention is superseded by the coordinated SemVer convention below
> (`esh-vX.Y.Z`, Issue #25). Historical legacy tags
> (`legacy/master-final`, `legacy/slave-final`, `legacy/flutter-final`) remain
> historical and are not renamed.

## Release model

One commit on `main` is one coordinated system revision (Flutter + Master +
Slave + Firebase + contracts + tests together). A release is an annotated Git
tag that pins exactly that one commit:

```text
Git commit on main
        |
        v
Coordinated ESH version  (root VERSION)
        |
        v
esh-vX.Y.Z
        |
        +--> Flutter revision      (build-name = coordinated version)
        +--> Master firmware       (compiled with ESH_VERSION)
        +--> Slave firmware        (compiled with ESH_VERSION)
        +--> Firebase rules/config (revision = commit + rules hash)
        +--> Contracts + tests     (same commit)
        |
        v
Versioned release artifacts + manifest
```

Because the tag points to one commit, one tag pins every component to the same
source revision. This is the primary compatibility boundary of the monorepo.

## Version sources (single source of truth)

The root `VERSION` file is the single source of truth for the coordinated
version. It holds a plain SemVer string:

```text
1.0.0
```

| Component | Version source | Mechanism |
|-----------|----------------|-----------|
| System    | `VERSION` (root) | authoritative coordinated version |
| Flutter   | `apps/flutter/pubspec.yaml` `version:` | build-name must equal `VERSION`; build-number is the Android build number |
| Master    | `VERSION` (root) | injected at build time as `-D ESH_VERSION="X.Y.Z"` via `scripts/release/platformio_version.py` |
| Slave     | `VERSION` (root) | same injection as Master |
| Firebase  | no runtime version | revision = release commit SHA + deterministic rules hash in the manifest |

There is no independent, manually-maintained version number for any component.
Drift is rejected by the validator (see below).

## SemVer policy

The coordinated version is `MAJOR.MINOR.PATCH`.

- **MAJOR** — incompatible coordinated system change: breaking command
  contract, incompatible RTDB schema, incompatible ESP-NOW protocol/ABI,
  incompatible provisioning behavior.
- **MINOR** — backward-compatible capability: new Flutter feature, additional
  telemetry, new supported-device behavior, coordinated compatible feature.
- **PATCH** — backward-compatible fix: bug fix, reliability fix,
  test/infrastructure correction, release correction that does not change a
  compatibility contract.

No prerelease (`-rc.1`) or build metadata is used in the coordinated version;
a simple stable SemVer is sufficient for a skripsi-oriented project.

## Tag convention

```text
esh-vMAJOR.MINOR.PATCH
```

Examples: `esh-v1.0.0`, `esh-v1.1.0`, `esh-v1.1.1`.

Valid tag pattern:

```regex
^esh-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$
```

Tags are normally annotated:

```bash
git tag -a esh-v1.0.0 -m "ESH v1.0.0"
```

## Compatibility policy

One `esh-vX.Y.Z` tag = one compatibility set. Flutter, Master, Slave, Firebase,
contracts, and tests from the same commit have passed the release gates together
and are the supported tested combination.

- Components from the same coordinated release tag are supported together.
- Mixing component revisions from different release tags is **unsupported**
  unless explicitly documented and tested.

Do not claim arbitrary cross-version compatibility (e.g. "Flutter 1.2 works
with Master 1.1") without evidence.

## Release procedure

1. Make the coordinated change on a feature branch and open a PR.
2. Bump the coordinated version and synchronize components:

   ```bash
   echo "1.2.0" > VERSION
   # apps/flutter/pubspec.yaml:  version: 1.2.0+<build>   (build-name must match)
   ```

3. Validate locally:

   ```bash
   python scripts/release/release.py validate
   python scripts/release/test_release.py
   ```

4. Pass normal CI (Flutter, Master, Slave, Firebase rules, contract tests,
   integration) and merge the PR to `main`.
5. On `main`, create and push the release tag (a deliberate maintainer action):

   ```bash
   git checkout main
   git pull --ff-only
   git tag -a esh-v1.2.0 -m "ESH v1.2.0"
   git push origin esh-v1.2.0
   ```

6. The release workflow builds versioned artifacts and uploads them.

Tagging is **not** automated during this process; production tagging is always
a deliberate maintainer action.

## Release gates (fail closed)

Release packaging must not proceed when any gate fails:

- root `VERSION` is valid SemVer,
- Flutter build-name matches the coordinated version,
- the tag (if present) has valid `esh-vX.Y.Z` format and matches `VERSION`,
- Flutter analyze/test/build pass,
- Master firmware compiles,
- Slave firmware compiles,
- Firebase rules emulator tests pass,
- deterministic contract tests pass.

## Artifact naming

Versioned artifacts use the coordinated version and never a bare `latest`:

```text
esh-flutter-X.Y.Z-debug.apk
esh-master-X.Y.Z-ci.zip
esh-slave-X.Y.Z-ci.zip
esh-firebase-X.Y.Z.zip
esh-release-manifest-X.Y.Z.json
```

`ci` marks firmware artifacts as CI/reproducibility builds (synthetic
provisioning), not production-provisioned firmware.

## Release manifest

Each release emits a machine-readable manifest with full traceability:

```json
{
  "schema_version": 1,
  "release": "1.2.0",
  "tag": "esh-v1.2.0",
  "commit": "<full git sha>",
  "components": {
    "flutter": {"version": "1.2.0+7"},
    "master": {"version": "1.2.0"},
    "slave": {"version": "1.2.0"},
    "firebase": {"version": "1.2.0", "revision": "<sha>", "rules_sha256": "..."}
  }
}
```

Generate it with:

```bash
python scripts/release/release.py manifest --output dist/release-manifest.json
```

`dist/` is git-ignored; generated manifests are artifacts, not tracked source.

## Release notes structure

Use this template when publishing release notes:

```markdown
## Summary
## Component changes
### Flutter
### Master
### Slave
### Firebase
## Contract/schema changes
## Validation
## Known limitations
## Upgrade notes
## Rollback reference
```

## Rollback policy

Rollback references an exact known-good tag, never an ambiguous phrase like
"the old firmware".

```bash
git checkout esh-v1.1.3   # source/debug reproduction
```

Component-specific rollback:

- **Flutter** — install the APK associated with the previous tag.
- **Master** — flash the artifact/source from the previous tag with correct
  (local) provisioning.
- **Slave** — flash the artifact/source from the previous tag.
- **Firebase** — restore/deploy the rules/config revision from the previous tag
  (a deliberate manual action; never automated).

## Security / provisioning limitations

- Real credentials and keys are never committed (see `docs/PROVISIONING.md`).
- Firmware CI artifacts use synthetic provisioning and are build/reproducibility
  artifacts, not production-provisioned images.
- Flutter CI artifacts are debug builds; no production signing key is used.
- No production Firebase deployment is performed as part of release packaging.

The first production release tag remains a deliberate, future maintainer action;
this process defines the mechanism, not an automatic production release.
