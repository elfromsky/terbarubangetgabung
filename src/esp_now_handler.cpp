#include "esp_now_config.h"
#include <WiFi.h>
#include <esp_now.h>
#include <Arduino.h>
#include <cstring>

// Master MAC Address
const uint8_t MASTER_MAC[6] = {0x10, 0xb4, 0x1d, 0xc9, 0x10, 0xb0};

// Received command buffer
static DeviceCommandPayload receivedCommand;
static bool commandPending = false;
static uint32_t lastCommandTime = 0;

// CRC calculation over arbitrary byte buffer
uint8_t computeCRC(const uint8_t *data, uint16_t len) {
  uint8_t crc = 0;
  for (uint16_t i = 0; i < len; i++) {
    crc ^= data[i];
  }
  return crc;
}

bool validateCommandCRC(const DeviceCommandPayload &cmd) {
  const uint8_t* data = (const uint8_t*)&cmd;
  uint8_t calcCRC = computeCRC(data, sizeof(DeviceCommandPayload) - 1);
  return cmd.crc == calcCRC;
}

bool validateStateCRC(const DeviceStatePayload &state) {
  const uint8_t* data = (const uint8_t*)&state;
  uint8_t calcCRC = computeCRC(data, sizeof(DeviceStatePayload) - 1);
  return state.crc == calcCRC;
}

// ESP-NOW receive callback (older API signature)
void onReceiveData(const uint8_t *mac_addr, const uint8_t *incomingData, int len) {
  if (mac_addr == NULL || incomingData == NULL) return;

  // Ignore if not from master
  if (memcmp(mac_addr, MASTER_MAC, 6) != 0) return;

  // Must be exactly a command payload
  if (len != (int)sizeof(DeviceCommandPayload)) return;

  // Check message type field
  if (incomingData[0] != ESPNOW_MSG_DEVICE_COMMAND) return;

  memcpy(&receivedCommand, incomingData, sizeof(DeviceCommandPayload));

  // Force null termination on string fields
  receivedCommand.roomKey[sizeof(receivedCommand.roomKey) - 1] = '\0';
  receivedCommand.deviceKey[sizeof(receivedCommand.deviceKey) - 1] = '\0';
  receivedCommand.requestId[sizeof(receivedCommand.requestId) - 1] = '\0';

  if (!validateCommandCRC(receivedCommand)) {
    Serial.println("ESP-NOW: Invalid CRC");
    return;
  }

  commandPending = true;
  lastCommandTime = millis();
}

// Optional send callback (not required for basic operation)
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  // Can be used for send confirmation if needed
}

void initEspNow() {
  // Set WiFi mode to STA
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();

  // Initialize ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW initialization failed");
    return;
  }

  // Register peer (master)
  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, MASTER_MAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  peerInfo.ifidx = WIFI_IF_STA;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("ESP-NOW peer add failed");
    return;
  }

  // Register receive callback
  esp_now_register_recv_cb(onReceiveData);

  Serial.println("ESP-NOW initialized - waiting for master commands");
}

void sendStateToMaster(const DeviceStatePayload &state) {
  // Compute CRC before sending
  DeviceStatePayload sendBuf = state;
  uint8_t* data = (uint8_t*)&sendBuf;
  sendBuf.crc = computeCRC(data, sizeof(DeviceStatePayload) - 1);

  esp_err_t result = esp_now_send(MASTER_MAC, (uint8_t*)&sendBuf, sizeof(DeviceStatePayload));

  if (result != ESP_OK) {
    Serial.print("ESP-NOW send failed: ");
    Serial.println(result);
  }
}

void setCommandPending(bool pending) {
  commandPending = pending;
}

DeviceCommandPayload* getReceivedCommand() {
  if (commandPending) {
    return &receivedCommand;
  }
  return nullptr;
}

uint32_t getLastCommandTime() {
  return lastCommandTime;
}
