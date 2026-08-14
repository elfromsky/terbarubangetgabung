#ifndef ESP_NOW_PROTOCOL_H
#define ESP_NOW_PROTOCOL_H

#include <Arduino.h>
#include <cstdint>
#include <cstring>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string>

struct DeviceCommandPayload {
  uint8_t type;
  char roomKey[24];
  char deviceKey[32];
  uint8_t state;
  uint8_t brightness;
  char requestId[32];
  uint8_t crc;
} __attribute__((packed));

struct DeviceStatePayload {
  uint8_t type;
  char roomKey[24];
  char deviceKey[32];
  uint8_t state;
  uint8_t brightness;
  char requestId[32];
  uint8_t success;
  uint8_t errorCode;
  uint32_t timestamp;
  uint8_t crc;
} __attribute__((packed));

struct DiscoveryBeaconPayload {
  uint8_t type;
  uint8_t channel;
  uint32_t magic;
  uint8_t crc;
} __attribute__((packed));

static_assert(sizeof(DeviceCommandPayload) == 92, "DeviceCommandPayload must be 92 bytes");
static_assert(sizeof(DeviceStatePayload) == 98, "DeviceStatePayload must be 98 bytes");
static_assert(sizeof(DiscoveryBeaconPayload) == 7, "DiscoveryBeaconPayload must be 7 bytes");

#define CMD_TYPE_COMMAND 1
#define CMD_TYPE_STATE   2
#define ESPNOW_MSG_DISCOVERY_BEACON 3
#define ESPNOW_MSG_AUTHENTICATED_BEACON 4

#define ESPNOW_DISCOVERY_MAGIC 0xA5C35A7EUL
#define ESPNOW_DISCOVERY_INTERVAL_MS 1000UL

#define ERR_OK                0
#define ERR_UNKNOWN_KEY       1
#define ERR_INVALID_STATE     2
#define ERR_INVALID_BRIGHTNESS 3
#define ERR_CRC_INVALID       4
#define ERR_HARDWARE          5

uint8_t computeXorCRC(const uint8_t* data, size_t len);

enum class DeviceOwner { Master, Slave, Unknown };
DeviceOwner getDeviceOwner(const String& roomKey, const String& deviceKey);
bool isSlaveOwned(const String& roomKey, const String& deviceKey);

extern const uint8_t SLAVE_MAC_ADDRESS[6];

bool initESPNow();
bool registerSlavePeer();
bool registerBroadcastPeer();
bool sendDiscoveryBeacon();
uint8_t getCurrentEspNowChannel();
bool sendCommandToSlave(const DeviceCommandPayload& cmd);

extern volatile bool sendCallbackReceived;
extern volatile bool lastSendSuccess;
extern portMUX_TYPE espNowMux;

bool popReceivedStatePacket(DeviceStatePayload& packet, unsigned long& receivedMs);
std::string generateRequestId();

#endif
