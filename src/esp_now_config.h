#ifndef ESP_NOW_CONFIG_H
#define ESP_NOW_CONFIG_H

#include <Arduino.h>
#include <esp_now.h>

// Master MAC Address
extern const uint8_t MASTER_MAC[6];

// ESP-NOW message types
#define ESPNOW_MSG_DEVICE_COMMAND 1
#define ESPNOW_MSG_DEVICE_STATE 2

// Device state values
#define ESPNOW_STATE_OFF 0
#define ESPNOW_STATE_ON 1

// ACK result values
#define ESPNOW_RESULT_OK 1
#define ESPNOW_RESULT_ERROR 0

// Error codes
#define ESPNOW_ERR_UNKNOWN_DEVICE 1
#define ESPNOW_ERR_INVALID_STATE 2
#define ESPNOW_ERR_INVALID_BRIGHTNESS 3
#define ESPNOW_ERR_CRC 4
#define ESPNOW_ERR_HARDWARE 5

// Command payload (Master -> Slave)
struct DeviceCommandPayload {
  uint8_t type;                    // ESPNOW_MSG_DEVICE_COMMAND
  char roomKey[24];                // null-terminated
  char deviceKey[32];              // null-terminated
  uint8_t state;                   // ESPNOW_STATE_OFF or ESPNOW_STATE_ON
  uint8_t brightness;              // 0..100
  char requestId[32];              // opaque identifier echoed in ACK
  uint8_t crc;                     // XOR CRC over all preceding bytes
} __attribute__((packed));

// Compile-time struct size verification
static_assert(sizeof(DeviceCommandPayload) == 92,
  "DeviceCommandPayload size mismatch — master and slave must agree");

// Status / ACK payload (Slave -> Master)
struct DeviceStatePayload {
  uint8_t type;                    // ESPNOW_MSG_DEVICE_STATE
  char roomKey[24];                // null-terminated
  char deviceKey[32];              // null-terminated
  uint8_t state;                   // final state
  uint8_t brightness;              // final brightness
  char requestId[32];              // echoed from command; empty for periodic
  uint8_t success;                 // ESPNOW_RESULT_OK or ESPNOW_RESULT_ERROR
  uint8_t errorCode;               // 0 = OK, nonzero = failure reason
  uint32_t timestamp;              // millis()
  uint8_t crc;                     // XOR CRC over all preceding bytes
} __attribute__((packed));

static_assert(sizeof(DeviceStatePayload) == 98,
  "DeviceStatePayload size mismatch — master and slave must agree");

// Function declarations
void initEspNow();
void sendStateToMaster(const DeviceStatePayload &state);
bool validateCommandCRC(const DeviceCommandPayload &cmd);
bool validateStateCRC(const DeviceStatePayload &state);
uint8_t computeCRC(const uint8_t *data, uint16_t len);
DeviceCommandPayload* getReceivedCommand();
void setCommandPending(bool pending);

#endif
