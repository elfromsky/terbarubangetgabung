#ifndef ESP_NOW_KEYS_H
#define ESP_NOW_KEYS_H

#include <cstdint>
#include <esp_now.h>

#if __has_include("esp_now_keys.local.h")
#include "esp_now_keys.local.h"
#else
#error "Missing src/esp_now_keys.local.h; copy esp_now_keys.example.h and set local keys"
#endif

#if !defined(ESPNOW_PMK_BYTES) || !defined(ESPNOW_LMK_BYTES)
#error "esp_now_keys.local.h must define ESPNOW_PMK_BYTES and ESPNOW_LMK_BYTES"
#endif

static constexpr uint8_t ESPNOW_PMK[] = ESPNOW_PMK_BYTES;
static constexpr uint8_t ESPNOW_LMK[] = ESPNOW_LMK_BYTES;

static_assert(ESP_NOW_KEY_LEN == 16, "ESP-NOW encryption keys must be 16 bytes");
static_assert(sizeof(ESPNOW_PMK) == ESP_NOW_KEY_LEN, "ESPNOW_PMK must contain exactly 16 bytes");
static_assert(sizeof(ESPNOW_LMK) == ESP_NOW_KEY_LEN, "ESPNOW_LMK must contain exactly 16 bytes");

#endif
