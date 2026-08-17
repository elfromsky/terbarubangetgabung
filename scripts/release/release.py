#!/usr/bin/env python3
"""ESH coordinated release metadata tool.

Single source of truth for the coordinated ESH system version is the root
``VERSION`` file (plain SemVer ``X.Y.Z``). This tool validates that the release
metadata does not drift across components and can emit a deterministic release
manifest.

Commands:

    python scripts/release/release.py validate [--tag esh-vX.Y.Z]
    python scripts/release/release.py manifest [--tag esh-vX.Y.Z] [--output PATH]

``validate`` exits non-zero on any inconsistency (fail closed). It checks:

1. root ``VERSION`` is valid SemVer ``X.Y.Z`` (no leading zeros, no prerelease),
2. Flutter ``pubspec.yaml`` build-name equals the coordinated version,
3. an optional Git tag has the correct ``esh-vX.Y.Z`` format,
4. the tag version equals the coordinated version.

``manifest`` writes a machine-readable JSON release manifest for traceability.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
VERSION_PATH = REPO_ROOT / "VERSION"
PUBSPEC_PATH = REPO_ROOT / "apps" / "flutter" / "pubspec.yaml"
FIREBASE_DIR = REPO_ROOT / "firebase"

# Valid SemVer: X.Y.Z with no leading zeros and no prerelease/build metadata.
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
# Valid ESH release tag: esh-vX.Y.Z with no leading zeros and no prerelease.
TAG_RE = re.compile(r"^esh-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
# Flutter pubspec version: X.Y.Z+build (build number is a positive integer).
FLUTTER_VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([0-9]+)$"
)


class ReleaseError(Exception):
    """Raised when release metadata is inconsistent or malformed."""


def parse_semver(value: str) -> tuple[int, int, int]:
    """Parse a SemVer ``X.Y.Z`` string into (major, minor, patch)."""
    text = value.strip()
    match = SEMVER_RE.match(text)
    if not match:
        raise ReleaseError(
            "invalid SemVer version %r (expected X.Y.Z, no leading zeros, "
            "no prerelease)" % text
        )
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def parse_tag(tag: str) -> str:
    """Parse an ``esh-vX.Y.Z`` tag and return the ``X.Y.Z`` version string."""
    match = TAG_RE.match(tag)
    if not match:
        raise ReleaseError(
            "invalid release tag %r (expected esh-vX.Y.Z, no leading zeros)" % tag
        )
    return "%s.%s.%s" % (match.group(1), match.group(2), match.group(3))


def parse_flutter_version(value: str) -> tuple[str, int]:
    """Parse a Flutter ``X.Y.Z+build`` version into (build_name, build_number)."""
    match = FLUTTER_VERSION_RE.match(value.strip())
    if not match:
        raise ReleaseError(
            "invalid Flutter version %r (expected X.Y.Z+build)" % value.strip()
        )
    name = "%s.%s.%s" % (match.group(1), match.group(2), match.group(3))
    return name, int(match.group(4))


def check_tag_matches_root(root_version: str, tag_version: str) -> None:
    if root_version != tag_version:
        raise ReleaseError(
            "version/tag mismatch: VERSION=%s but tag version=%s"
            % (root_version, tag_version)
        )


def check_flutter_matches_root(flutter_name: str, root_version: str) -> None:
    if flutter_name != root_version:
        raise ReleaseError(
            "Flutter/coordinated version mismatch: VERSION=%s but "
            "Flutter build-name=%s" % (root_version, flutter_name)
        )


def read_root_version() -> str:
    if not VERSION_PATH.exists():
        raise ReleaseError("missing root VERSION file: %s" % VERSION_PATH)
    text = VERSION_PATH.read_text(encoding="utf-8").strip()
    if not text:
        raise ReleaseError("root VERSION file is empty: %s" % VERSION_PATH)
    parse_semver(text)
    return text


def read_flutter_version() -> tuple[str, int]:
    if not PUBSPEC_PATH.exists():
        raise ReleaseError("missing Flutter pubspec: %s" % PUBSPEC_PATH)
    for line in PUBSPEC_PATH.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("version:"):
            value = stripped[len("version:"):].strip()
            return parse_flutter_version(value)
    raise ReleaseError("no version: line found in %s" % PUBSPEC_PATH)


def git_commit() -> str:
    """Return the full commit SHA of HEAD (or the empty string if unavailable)."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(REPO_ROOT),
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return out.stdout.strip()


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def firebase_rules_sha256() -> str:
    """Deterministic hash of the Firebase rules sources (fixed file order)."""
    rule_files = [
        FIREBASE_DIR / "database.rules.json",
        FIREBASE_DIR / "firestore.rules",
    ]
    digest = hashlib.sha256()
    for path in rule_files:
        if path.exists():
            digest.update(path.read_bytes())
    return digest.hexdigest()


def validate(tag: str | None) -> str:
    """Validate release metadata; return the coordinated version string."""
    version = read_root_version()
    flutter_name, _flutter_build = read_flutter_version()
    check_flutter_matches_root(flutter_name, version)

    tag_version = None
    if tag is not None:
        tag_version = parse_tag(tag)
        check_tag_matches_root(version, tag_version)

    return version


def build_manifest(tag: str | None) -> dict:
    version = validate(tag)
    flutter_name, flutter_build = read_flutter_version()
    commit = git_commit()
    effective_tag = tag if tag is not None else "esh-v%s" % version

    return {
        "schema_version": 1,
        "release": version,
        "tag": effective_tag,
        "commit": commit,
        "components": {
            "flutter": {"version": "%s+%d" % (flutter_name, flutter_build)},
            "master": {"version": version},
            "slave": {"version": version},
            "firebase": {
                "version": version,
                "revision": commit,
                "rules_sha256": firebase_rules_sha256(),
            },
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ESH coordinated release metadata tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate release metadata")
    validate_parser.add_argument("--tag", help="optional release tag to validate")

    manifest_parser = subparsers.add_parser("manifest", help="generate release manifest")
    manifest_parser.add_argument("--tag", help="optional release tag")
    manifest_parser.add_argument("--output", help="output JSON path (default: stdout)")

    args = parser.parse_args(argv)

    try:
        if args.command == "validate":
            version = validate(args.tag)
            print("OK coordinated version=%s" % version)
            if args.tag:
                print("OK tag=%s" % args.tag)
            return 0

        if args.command == "manifest":
            manifest = build_manifest(args.tag)
            payload = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
            if args.output:
                out_path = Path(args.output)
                out_path.parent.mkdir(parents=True, exist_ok=True)
                out_path.write_text(payload, encoding="utf-8")
                print("wrote manifest to %s" % out_path)
            else:
                sys.stdout.write(payload)
            return 0

        parser.error("unknown command")
        return 2
    except ReleaseError as exc:
        print("release validation FAILED: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
