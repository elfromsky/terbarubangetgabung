# Provisioning

This document describes how firmware and Firebase credentials are provided
locally without ever committing secrets to the repository.

## Principle

Real credentials and keys are **local-only** and **git-ignored**. Canonical
repository files contain only placeholders or fail-closed guards. CI uses
exclusively synthetic (non-operational) placeholder values.

## Firmware local provisioning

### Master

Create ignored local headers next to their example files:

```text
firmware/master/include/firebase_config.local.h   (from firebase_config.example.h)
firmware/master/include/wifi_config.local.h        (from wifi_config.example.h)
firmware/master/include/esp_now_keys.local.h       (from esp_now_keys.example.h)
```

Contents:

- `firebase_config.local.h`: `FIREBASE_DATABASE_URL`, `FIREBASE_API_KEY`,
  `FIREBASE_USER_EMAIL`, `FIREBASE_USER_PASSWORD`.
- `wifi_config.local.h`: `WIFI_SSID`, `WIFI_PASSWORD`.
- `esp_now_keys.local.h`: `ESPNOW_PMK_BYTES`, `ESPNOW_LMK_BYTES` (16 bytes each).

The canonical wrapper headers (`firebase_config.h`, `wifi_config.h`,
`esp_now_keys.h`) fail closed at compile time if the corresponding `.local.h`
file is missing.

### Slave

Create the ignored local header:

```text
firmware/slave/src/esp_now_keys.local.h          (from esp_now_keys.example.h)
```

Contents: `ESPNOW_PMK_BYTES`, `ESPNOW_LMK_BYTES` (16 bytes each).

## Synthetic CI provisioning

`scripts/ci/prepare-synthetic-provisioning.sh <master|slave> <target-root>`
writes obvious placeholder `.local.h` files so firmware can be compile-validated
in CI with no real credentials. The synthetic values are valid at compile time
but must never be used against production Firebase or real hardware.

## Credential hygiene guard

`scripts/ci/check-credential-hygiene.sh` asserts structural rules (no tracked
`*.local.h`, no literal credential macros in wrapper headers, no tracked
private-key material) without ever printing secret values. It runs in CI.

## Firebase custom claims

Two strict-boolean custom claims are used: `owner` and `controller`. They are
assigned in the Firebase Auth console or via the Admin SDK (out of band), not
committed to the repository. See `contracts/firebase-authorization.md` for the
full authorization contract and `apps/flutter/lib/auth/device_claim.dart` for
the client-side trust evaluation.

## What must never be committed

- `*.local.h` provisioning headers with real values.
- Firebase service-account private keys (`service-account*.json`, `*.pem`).
- Real Wi-Fi credentials.
- Real ESP-NOW PMK/LMK key bytes.
- Firebase user passwords or API keys beyond the public client config already
  in `apps/flutter/` (and only where that config is intentionally public).

> Deployment of rules or rotation of credentials is a separate operation and is
> not performed by the monorepo migration.
