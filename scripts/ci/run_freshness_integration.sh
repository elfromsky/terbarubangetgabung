#!/usr/bin/env bash
#
# Issue #24 — Firebase emulator-backed Flutter integration suite.
#
# Runs on the Android emulator (hosted by reactivecircus/android-emulator-runner).
# The Firebase Auth + Realtime Database emulators are started on the HOST; the
# Flutter test process runs on the Android emulator and reaches them through the
# host-loopback alias 10.0.2.2.
#
# Auth emulator port (9099) and database emulator port (9000) match
# firebase/firebase.json. The synthetic project id esh-integration-test is used
# so the suite can never touch a production project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FIREBASE_BIN="integration-tests/node_modules/.bin/firebase"

# The Auth + RTDB emulators are Node processes (no Java required). They bind to
# localhost; the Android emulator reaches host loopback via 10.0.2.2.
"$FIREBASE_BIN" emulators:exec \
  --config firebase/firebase.json \
  --only auth,database \
  --project esh-integration-test \
  "node integration-tests/provision_owner.js && cd apps/flutter && flutter test integration_test --dart-define=ESH_INTEGRATION=true --dart-define=ESH_EMULATOR_HOST=10.0.2.2"
