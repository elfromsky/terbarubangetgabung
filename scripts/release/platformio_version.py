#!/usr/bin/env python3
"""PlatformIO pre-build hook: inject ESH_VERSION from the root VERSION file.

Wired into both Master and Slave ``platformio.ini`` via ``extra_scripts`` so the
coordinated version has a single source of truth (root ``VERSION``) and is never
copy-pasted into firmware build flags. The hook fails the build if the version
is missing or malformed (fail closed).
"""

from pathlib import Path
import re

Import("env")  # noqa: F821 -- provided by PlatformIO SCons build environment

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
VERSION_PATH = REPO_ROOT / "VERSION"

SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

if not VERSION_PATH.exists():
    raise RuntimeError("missing root VERSION file: %s" % VERSION_PATH)

version = VERSION_PATH.read_text(encoding="utf-8").strip()
if not SEMVER_RE.match(version):
    raise RuntimeError("invalid ESH version in %s: %r" % (VERSION_PATH, version))

# Inject -D ESH_VERSION="X.Y.Z" so firmware can identify the coordinated release.
env.Append(CPPDEFINES=[("ESH_VERSION", '"%s"' % version)])
