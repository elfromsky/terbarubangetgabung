#!/usr/bin/env bash
#
# Generates synthetic (non-operational) local provisioning headers so that the
# Master and Slave firmware components can be COMPILE-VALIDATED in CI without
# real credentials, real Wi-Fi, or real ESP-NOW keys.
#
# Every value here is a deliberate, obvious placeholder. Values are valid at
# compile time (correct types and lengths) but MUST NEVER be used to talk to
# production Firebase or physical devices.
#
# Usage: prepare-synthetic-provisioning.sh <master|slave> <target-root>
set -euo pipefail

COMPONENT="${1:-}"
TARGET="${2:-}"

if [[ -z "${COMPONENT}" || -z "${TARGET}" ]]; then
  echo "usage: $0 <master|slave> <target-root>" >&2
  exit 2
fi

mkdir -p "${TARGET}"

# Synthetic ESP-NOW keys (16 bytes each, matching the static_assert contract).
ESPNOW_PMK_BYTES='{ 0xC1, 0xE0, 0x5A, 0x11, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17 }'
ESPNOW_LMK_BYTES='{ 0xD2, 0xE1, 0x6B, 0x22, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28 }'

write_keys_header() {
  local file="$1"
  local guard="$2"
  cat > "${file}" <<EOF
#ifndef ${guard}
#define ${guard}

// SYNTHETIC CI-ONLY ESP-NOW keys. Not for production use.
#define ESPNOW_PMK_BYTES \\
    ${ESPNOW_PMK_BYTES}

#define ESPNOW_LMK_BYTES \\
    ${ESPNOW_LMK_BYTES}

#endif
EOF
}

case "${COMPONENT}" in
  master)
    mkdir -p "${TARGET}/include"
    write_keys_header "${TARGET}/include/esp_now_keys.local.h" "ESP_NOW_KEYS_LOCAL_H"
    cat > "${TARGET}/include/wifi_config.local.h" <<'EOF'
#ifndef WIFI_CONFIG_LOCAL_H
#define WIFI_CONFIG_LOCAL_H

// SYNTHETIC CI-ONLY Wi-Fi credentials. Not for production use.
#define WIFI_SSID "TEST_WIFI"
#define WIFI_PASSWORD "synthetic-test-password"

#endif
EOF
    cat > "${TARGET}/include/firebase_config.local.h" <<'EOF'
#ifndef FIREBASE_CONFIG_LOCAL_H
#define FIREBASE_CONFIG_LOCAL_H

// SYNTHETIC CI-ONLY Firebase configuration. Not for production use.
#define FIREBASE_DATABASE_URL "synthetic-ci-test-default-rtdb.firebaseio.com"
#define FIREBASE_API_KEY "SYNTHETIC_API_KEY_CI_ONLY"
#define FIREBASE_USER_EMAIL "ci-test@example.invalid"
#define FIREBASE_USER_PASSWORD "synthetic-test-password"

#endif
EOF
    ;;
  slave)
    mkdir -p "${TARGET}/src"
    write_keys_header "${TARGET}/src/esp_now_keys.local.h" "ESP_NOW_KEYS_LOCAL_H"
    ;;
  *)
    echo "unknown component: ${COMPONENT} (expected master|slave)" >&2
    exit 2
    ;;
esac

echo "generated synthetic provisioning for: ${COMPONENT} -> ${TARGET}"
