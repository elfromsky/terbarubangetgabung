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

# 1. No local credential headers may be tracked (Master + Slave).
for local_header in \
  'firmware/master/include/*.local.h' \
  'firmware/slave/src/*.local.h'; do
  if git ls-files "${local_header}" | grep -q .; then
    echo "POLICY: ${local_header} must not be tracked"
    git ls-files "${local_header}"
    fail=1
  fi
done

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

check_no_literal firmware/master/include/firebase_config.h \
  FIREBASE_API_KEY FIREBASE_USER_EMAIL FIREBASE_USER_PASSWORD
check_no_literal firmware/master/include/wifi_config.h \
  WIFI_SSID WIFI_PASSWORD

# 3. Required placeholder example files must exist (Master + Slave).
for ex in \
  firmware/master/include/firebase_config.example.h \
  firmware/master/include/wifi_config.example.h \
  firmware/master/include/esp_now_keys.example.h \
  firmware/slave/src/esp_now_keys.example.h; do
  if [ ! -f "${ex}" ]; then
    echo "POLICY: required example file missing: ${ex}"
    fail=1
  fi
done

# 4. Local credential headers must remain ignored.
for spec in \
  'firmware/master/include' \
  'firmware/slave/src'; do
  probe="${spec}/issue6-probe-$$.local.h"
  touch "${probe}"
  if git check-ignore -q "${probe}"; then
    :
  else
    echo "POLICY: ${spec}/*.local.h is not ignored"
    fail=1
  fi
  rm -f "${probe}"
done

# 5. No tracked private-key PEM material anywhere.
if git ls-files | grep -Ei '(service.?account|private.?key|\.pem$|\.p12$)' | grep -q .; then
  echo "POLICY: private key / service-account material must not be tracked"
  git ls-files | grep -Ei '(service.?account|private.?key|\.pem$|\.p12$)'
  fail=1
fi

if [ "${fail}" -ne 0 ]; then
  echo "credential-hygiene: FAILED"
  exit 1
fi

echo "credential-hygiene: OK"
