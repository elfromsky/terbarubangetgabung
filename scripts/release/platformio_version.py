#!/usr/bin/env python3
"""PlatformIO pre-build hook: inject ESH_VERSION from the root VERSION file.

Wired into both Master and Slave ``platformio.ini`` via ``extra_scripts`` so the
coordinated version has a single source of truth (root ``VERSION``) and is never
copy-pasted into firmware build flags. The hook fails the build if the version
is missing or malformed (fail closed).

PlatformIO executes ``extra_scripts`` through ``exec(...)`` with the build
environment exported as ``env``; the script's own ``__file__`` is not available,
so the repo root is located from ``$PROJECT_DIR`` instead.
"""

from pathlib import Path
import re

Import("env")  # noqa: F821 -- provided by PlatformIO SCons build environment

SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

# $PROJECT_DIR is the PlatformIO project dir (firmware/master or firmware/slave);
# the repository root is two levels up.
project_dir = Path(env.subst("$PROJECT_DIR")).resolve()
VERSION_PATH = project_dir.parent.parent / "VERSION"

if not VERSION_PATH.exists():
    raise RuntimeError("missing root VERSION file: %s" % VERSION_PATH)

version = VERSION_PATH.read_text(encoding="utf-8").strip()
if not SEMVER_RE.match(version):
    raise RuntimeError("invalid ESH version in %s: %r" % (VERSION_PATH, version))

# Inject -D ESH_VERSION="X.Y.Z" so firmware can identify the coordinated release.
env.Append(CPPDEFINES=[("ESH_VERSION", '"%s"' % version)])