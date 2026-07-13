#include "room_device_routing.h"
#include "relay.h"
#include "dimmer.h"
#include <cstring>

// ──────────────────────────────────────────────
// Duplicate command cache
// ──────────────────────────────────────────────

struct DuplicateCacheEntry {
  bool used;
  char requestId[32];
  char roomKey[24];
  char deviceKey[32];
  uint8_t resultState;
  uint8_t resultBrightness;
  uint8_t resultSuccess;
  uint8_t resultErrorCode;
};

static const uint8_t DUPLICATE_CACHE_SIZE = 8;
static DuplicateCacheEntry duplicateCache[DUPLICATE_CACHE_SIZE];
static uint8_t duplicateCacheIndex = 0;

static DuplicateCacheEntry* duplicateFind(const char* requestId,
                                          const char* roomKey,
                                          const char* deviceKey) {
  for (uint8_t i = 0; i < DUPLICATE_CACHE_SIZE; i++) {
    if (duplicateCache[i].used &&
        strcmp(duplicateCache[i].requestId, requestId) == 0 &&
        strcmp(duplicateCache[i].roomKey, roomKey) == 0 &&
        strcmp(duplicateCache[i].deviceKey, deviceKey) == 0) {
      return &duplicateCache[i];
    }
  }
  return nullptr;
}

static void duplicateStore(const char* requestId,
                           const char* roomKey,
                           const char* deviceKey,
                           uint8_t state,
                           uint8_t brightness,
                           uint8_t success,
                           uint8_t errorCode) {
  DuplicateCacheEntry& entry = duplicateCache[duplicateCacheIndex];
  entry.used = true;
  strncpy(entry.requestId, requestId, sizeof(entry.requestId) - 1);
  entry.requestId[sizeof(entry.requestId) - 1] = '\0';
  strncpy(entry.roomKey, roomKey, sizeof(entry.roomKey) - 1);
  entry.roomKey[sizeof(entry.roomKey) - 1] = '\0';
  strncpy(entry.deviceKey, deviceKey, sizeof(entry.deviceKey) - 1);
  entry.deviceKey[sizeof(entry.deviceKey) - 1] = '\0';
  entry.resultState = state;
  entry.resultBrightness = brightness;
  entry.resultSuccess = success;
  entry.resultErrorCode = errorCode;
  duplicateCacheIndex = (duplicateCacheIndex + 1) % DUPLICATE_CACHE_SIZE;
}

// ──────────────────────────────────────────────
// Route table — maps contract keys to hardware
// ──────────────────────────────────────────────

struct DeviceRouteEntry {
  const char* roomKey;
  const char* deviceKey;
  uint8_t relayId;
  uint8_t dimmerChannel;
  bool isDimmable;
};

static const DeviceRouteEntry ROUTE_TABLE[] = {
  // Dimmable lamps
  {"kamar_1",  "lampu",       RELAY_KAMAR1_LAMPU,  1, true},
  {"kamar_2",  "lampu",       RELAY_KAMAR2_LAMPU,  1, true},
  {"dapur",    "lampu",       RELAY_DAPUR_LAMPU,   2, true},
  // State-only devices
  {"lorong",   "stop_kontak", RELAY_LORONG_STOP_KONTAK, 0, false},
  {"lorong",   "blower",      RELAY_LORONG_BLOWER, 0, false},
  {"kamar_1",  "stop_kontak", RELAY_KAMAR1_STOP_KONTAK, 0, false},
  {"kamar_2",  "stop_kontak", RELAY_KAMAR2_STOP_KONTAK, 0, false},
  {"dapur",    "blower",      RELAY_DAPUR_BLOWER, 0, false},
};

static const uint8_t DEVICE_COUNT = sizeof(ROUTE_TABLE) / sizeof(ROUTE_TABLE[0]);

static const DeviceRouteEntry* findEntry(const char* roomKey, const char* deviceKey) {
  for (uint8_t i = 0; i < DEVICE_COUNT; i++) {
    if (strcmp(roomKey, ROUTE_TABLE[i].roomKey) == 0 &&
        strcmp(deviceKey, ROUTE_TABLE[i].deviceKey) == 0) {
      return &ROUTE_TABLE[i];
    }
  }
  return nullptr;
}

static void copyStr(char* dst, const char* src, uint8_t maxLen) {
  strncpy(dst, src, maxLen - 1);
  dst[maxLen - 1] = '\0';
}

static bool hasOtherActiveRelayOnDimmer(const DeviceRouteEntry* currentEntry) {
  for (uint8_t i = 0; i < DEVICE_COUNT; i++) {
    const DeviceRouteEntry& candidate = ROUTE_TABLE[i];
    if (&candidate != currentEntry &&
        candidate.dimmerChannel == currentEntry->dimmerChannel &&
        getRelayState(candidate.relayId)) {
      return true;
    }
  }
  return false;
}

// ──────────────────────────────────────────────
// Public API
// ──────────────────────────────────────────────

bool isDimmableDevice(const char* roomKey, const char* deviceKey) {
  const DeviceRouteEntry* entry = findEntry(roomKey, deviceKey);
  return entry != nullptr && entry->isDimmable;
}

bool applyDeviceCommand(const DeviceCommandPayload &cmd, DeviceStatePayload &outState) {
  memset(&outState, 0, sizeof(outState));
  outState.type = ESPNOW_MSG_DEVICE_STATE;

  copyStr(outState.roomKey, cmd.roomKey, sizeof(outState.roomKey));
  copyStr(outState.deviceKey, cmd.deviceKey, sizeof(outState.deviceKey));
  copyStr(outState.requestId, cmd.requestId, sizeof(outState.requestId));

  // ── Duplicate check: skip hardware if already executed ──
  DuplicateCacheEntry* dup = duplicateFind(cmd.requestId, cmd.roomKey, cmd.deviceKey);
  if (dup != nullptr) {
    outState.state = dup->resultState;
    outState.brightness = dup->resultBrightness;
    outState.success = dup->resultSuccess;
    outState.errorCode = dup->resultErrorCode;
    outState.timestamp = millis();
    return dup->resultSuccess == ESPNOW_RESULT_OK;
  }

  const DeviceRouteEntry* entry = findEntry(cmd.roomKey, cmd.deviceKey);
  if (entry == nullptr) {
    outState.success = ESPNOW_RESULT_ERROR;
    outState.errorCode = ESPNOW_ERR_UNKNOWN_DEVICE;
    outState.timestamp = millis();
    duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                   outState.state, outState.brightness,
                   outState.success, outState.errorCode);
    return false;
  }

  // ── Validate and normalize state ──
  uint8_t finalState;
  uint8_t finalBrightness;

  if (cmd.state == ESPNOW_STATE_OFF) {
    finalState = ESPNOW_STATE_OFF;
    finalBrightness = 0;
  } else if (cmd.state == ESPNOW_STATE_ON) {
    finalState = ESPNOW_STATE_ON;
    finalBrightness = cmd.brightness;

    if (finalBrightness > 100) {
      outState.success = ESPNOW_RESULT_ERROR;
      outState.errorCode = ESPNOW_ERR_INVALID_BRIGHTNESS;
      outState.timestamp = millis();
      duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                     outState.state, outState.brightness,
                     outState.success, outState.errorCode);
      return false;
    }

    if (entry->isDimmable) {
      if (finalBrightness == 0) {
        finalState = ESPNOW_STATE_OFF;
        finalBrightness = 0;
      }
    } else {
      finalBrightness = 100;
    }
  } else {
    outState.success = ESPNOW_RESULT_ERROR;
    outState.errorCode = ESPNOW_ERR_INVALID_STATE;
    outState.timestamp = millis();
    duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                   outState.state, outState.brightness,
                   outState.success, outState.errorCode);
    return false;
  }

  // ── Apply hardware ──
  setRelayState(entry->relayId, (finalState == ESPNOW_STATE_ON));

  if (entry->dimmerChannel > 0) {
    if (finalState == ESPNOW_STATE_ON) {
      setDimmerBrightness(entry->dimmerChannel, finalBrightness);
    } else if (!hasOtherActiveRelayOnDimmer(entry)) {
      setDimmerBrightness(entry->dimmerChannel, 0);
    }
  }

  // ── Fill ACK ──
  outState.state = finalState;
  outState.brightness = finalBrightness;
  outState.success = ESPNOW_RESULT_OK;
  outState.errorCode = 0;
  outState.timestamp = millis();

  duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                 finalState, finalBrightness,
                 ESPNOW_RESULT_OK, 0);

  return true;
}

void buildPeriodicStateForDevice(uint8_t index, DeviceStatePayload &outState) {
  memset(&outState, 0, sizeof(outState));
  outState.type = ESPNOW_MSG_DEVICE_STATE;

  if (index >= DEVICE_COUNT) {
    outState.success = ESPNOW_RESULT_ERROR;
    outState.errorCode = ESPNOW_ERR_UNKNOWN_DEVICE;
    outState.timestamp = millis();
    return;
  }

  const DeviceRouteEntry &entry = ROUTE_TABLE[index];

  copyStr(outState.roomKey, entry.roomKey, sizeof(outState.roomKey));
  copyStr(outState.deviceKey, entry.deviceKey, sizeof(outState.deviceKey));

  bool relayOn = getRelayState(entry.relayId);
  outState.state = relayOn ? ESPNOW_STATE_ON : ESPNOW_STATE_OFF;

  if (entry.isDimmable) {
    outState.brightness = relayOn ? getDimmerBrightness(entry.dimmerChannel) : 0;
  } else {
    outState.brightness = relayOn ? 100 : 0;
  }

  outState.requestId[0] = '\0';
  outState.success = ESPNOW_RESULT_OK;
  outState.errorCode = 0;
  outState.timestamp = millis();
}

uint8_t getDeviceCount() {
  return DEVICE_COUNT;
}
