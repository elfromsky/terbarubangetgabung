#include "room_device_routing.h"
#include "relay.h"
#include "dimmer.h"
#include <cstring>

// ──────────────────────────────────────────────
// Duplicate command cache
// ──────────────────────────────────────────────

// The cache key is the full transmitted command identity:
// requestId + roomKey + deviceKey + commandState + commandBrightness.
// This deduplicates only exact transport-level replays of the same logical
// command (Issue #7): a retry reuses an identical payload, so it still hits;
// a reused requestId carrying a different state or brightness is a new
// command and must not be suppressed. state/brightness hold the values as
// transmitted in DeviceCommandPayload, not the normalized result values.
struct DuplicateCacheEntry {
  bool used;
  char requestId[32];
  char roomKey[24];
  char deviceKey[32];
  uint8_t commandState;
  uint8_t commandBrightness;
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
                                          const char* deviceKey,
                                          uint8_t state,
                                          uint8_t brightness) {
  for (uint8_t i = 0; i < DUPLICATE_CACHE_SIZE; i++) {
    if (duplicateCache[i].used &&
        strcmp(duplicateCache[i].requestId, requestId) == 0 &&
        strcmp(duplicateCache[i].roomKey, roomKey) == 0 &&
        strcmp(duplicateCache[i].deviceKey, deviceKey) == 0 &&
        duplicateCache[i].commandState == state &&
        duplicateCache[i].commandBrightness == brightness) {
      return &duplicateCache[i];
    }
  }
  return nullptr;
}

static void duplicateStore(const char* requestId,
                           const char* roomKey,
                           const char* deviceKey,
                           uint8_t commandState,
                           uint8_t commandBrightness,
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
  entry.commandState = commandState;
  entry.commandBrightness = commandBrightness;
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
  // Bedroom relays are independent; both retain one authoritative CH1 brightness.
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
  DuplicateCacheEntry* dup = duplicateFind(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                                           cmd.state, cmd.brightness);
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
                   cmd.state, cmd.brightness,
                   outState.state, outState.brightness,
                   outState.success, outState.errorCode);
    return false;
  }

  // ── Validate and normalize state ──
  uint8_t finalState;
  uint8_t finalBrightness;

  if (cmd.brightness > 100) {
    outState.success = ESPNOW_RESULT_ERROR;
    outState.errorCode = ESPNOW_ERR_INVALID_BRIGHTNESS;
    outState.timestamp = millis();
    duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                   cmd.state, cmd.brightness,
                   outState.state, outState.brightness,
                   outState.success, outState.errorCode);
    return false;
  }

  if (cmd.state == ESPNOW_STATE_OFF) {
    finalState = ESPNOW_STATE_OFF;
    if (entry->isDimmable) {
      // Dedicated channel: OFF always reports brightness 0. Shared channel
      // must retain the active channel brightness so the remaining ON lamp
      // keeps illuminating at the same level.
      finalBrightness = hasOtherActiveRelayOnDimmer(entry)
          ? getDimmerBrightness(entry->dimmerChannel)
          : cmd.brightness;
    } else {
      finalBrightness = 0;
    }
  } else if (cmd.state == ESPNOW_STATE_ON) {
    finalState = ESPNOW_STATE_ON;
    finalBrightness = cmd.brightness;

    if (entry->isDimmable) {
      if (finalBrightness == 0) {
        finalBrightness = 1;
      }
    } else {
      finalBrightness = 100;
    }
  } else {
    outState.success = ESPNOW_RESULT_ERROR;
    outState.errorCode = ESPNOW_ERR_INVALID_STATE;
    outState.timestamp = millis();
    duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                   cmd.state, cmd.brightness,
                   outState.state, outState.brightness,
                   outState.success, outState.errorCode);
    return false;
  }

  // ── Apply hardware ──
  setRelayState(entry->relayId, (finalState == ESPNOW_STATE_ON));

  if (entry->dimmerChannel > 0) {
    bool channelNeeded = finalState == ESPNOW_STATE_ON ||
                          hasOtherActiveRelayOnDimmer(entry);
    // Dedicated channel OFF => brightness 0. Shared channel OFF with sibling
    // ON retains the active brightness. A channel that is still needed must
    // never be set to zero; bump to the minimum non-zero level.
    if (!channelNeeded) {
      finalBrightness = 0;
    } else if (finalBrightness == 0) {
      finalBrightness = getDimmerBrightness(entry->dimmerChannel);
    }
    if (channelNeeded && finalBrightness == 0) {
      finalBrightness = 1;
    }
    if (!channelNeeded) {
      setDimmerOutputEnabled(entry->dimmerChannel, false);
    }
    setDimmerBrightness(entry->dimmerChannel, finalBrightness);
    if (channelNeeded) {
      setDimmerOutputEnabled(entry->dimmerChannel, true);
    }
    finalBrightness = getDimmerBrightness(entry->dimmerChannel);
  }

  // ── Fill ACK ──
  outState.state = finalState;
  outState.brightness = finalBrightness;
  outState.success = ESPNOW_RESULT_OK;
  outState.errorCode = 0;
  outState.timestamp = millis();

  duplicateStore(cmd.requestId, cmd.roomKey, cmd.deviceKey,
                 cmd.state, cmd.brightness,
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
    // Dedicated channel OFF reports brightness 0. Shared channels report the
    // retained channel brightness while any sibling relay is still ON.
    bool channelActive = relayOn || hasOtherActiveRelayOnDimmer(&entry);
    outState.brightness = channelActive
        ? getDimmerBrightness(entry.dimmerChannel)
        : 0;
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
