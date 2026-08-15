#!/usr/bin/env bash
#
# Lightweight, dependency-free credential-hygiene check.
#
# This is a current-tree focused guard. It NEVER reads or prints credential
# values. It only asserts structural rules that prevent real credentials from
# being reintroduced into tracked source, without requiring any secret-manager
# or secret scanner dependency.
#
# On failure it reports only:
#   path, symbol, policy violation
# It never prints the line contents or any credential value.
#
# Usage: bash scripts/ci/check-credential-hygiene.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

fail=0

echo "credential-hygiene: checking tracked local headers"

# 1. No local credential headers may be tracked.
if git ls-files 'include/*.local.h' | grep -q .; then
  echo "POLICY: include/*.local.h must not be tracked"
  git ls-files 'include/*.local.h'
  fail=1
fi

# 2. Canonical config wrappers must not define credential macros with literals.
#    (These wrappers include the ignored *.local.h and only perform the
#    fail-closed guard; they must never carry a real value themselves.)
check_no_literal() {
  local file="$1"
  shift
  local sym
  for sym in "$@"; do
    if git grep -qE "^[[:space:]]*#define[[:space:]]+${sym}[[:space:]]+" -- "${file}"; then
      echo "POLICY: ${file} must not define ${sym} directly (use the ignored *.local.h)"
      fail=1
    fi
  done
}

check_no_literal include/firebase_config.h \
  FIREBASE_API_KEY FIREBASE_USER_EMAIL FIREBASE_USER_PASSWORD
check_no_literal include/wifi_config.h \
  WIFI_SSID WIFI_PASSWORD

# 3. Required placeholder example files must exist.
for ex in \
  include/firebase_config.example.h \
  include/wifi_config.example.h \
  include/esp_now_keys.example.h; do
  if [ ! -f "${ex}" ]; then
    echo "POLICY: required example file missing: ${ex}"
    fail=1
  fi
done

# 4. include/*.local.h must remain ignored.
probe="include/issue6-probe-$$.local.h"
touch "${probe}"
if git check-ignore -q "${probe}"; then
  :
else
  echo "POLICY: include/*.local.h is not ignored"
  fail=1
fi
rm -f "${probe}"

if [ "${fail}" -ne 0 ]; then
  echo "credential-hygiene: FAILED"
  exit 1
fi

echo "credential-hygiene: OK"
