#include "esp_now_config.h"
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Arduino.h>
#include <cstring>

// Master MAC Address
const uint8_t MASTER_MAC[6] = {0x10, 0xb4, 0x1d, 0xc9, 0x10, 0xb0};

// Received command buffer
static DeviceCommandPayload receivedCommand;
static bool commandPending = false;
static portMUX_TYPE commandMux = portMUX_INITIALIZER_UNLOCKED;
static portMUX_TYPE radioMux = portMUX_INITIALIZER_UNLOCKED;
static bool espNowInitialized = false;
static bool masterPeerRegistered = false;
static bool channelLocked = false;
static bool pendingPeerRegistration = false;
static uint8_t lockedChannel = 0;
static volatile uint8_t pendingBeaconChannel = 0;
static uint8_t scanChannel = ESPNOW_SCAN_MIN_CHANNEL;
static uint32_t lastScanStepMs = 0;
static volatile uint32_t lastValidMasterPacketMs = 0;

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

void handleDiscoveryBeacon(const uint8_t *incomingData, int len) {
  if (len != (int)sizeof(DiscoveryBeaconPayload)) return;

  DiscoveryBeaconPayload beacon;
  memcpy(&beacon, incomingData, sizeof(beacon));

  if (beacon.magic != ESPNOW_DISCOVERY_MAGIC) return;
  if (beacon.channel < ESPNOW_SCAN_MIN_CHANNEL ||
      beacon.channel > ESPNOW_SCAN_MAX_CHANNEL) return;

  uint8_t calculatedCRC = computeCRC(
    reinterpret_cast<const uint8_t *>(&beacon),
    sizeof(DiscoveryBeaconPayload) - 1);
  if (beacon.crc != calculatedCRC) return;

  portENTER_CRITICAL(&radioMux);
  lastValidMasterPacketMs = millis();
  pendingBeaconChannel = beacon.channel;
  portEXIT_CRITICAL(&radioMux);
}

// ESP-NOW receive callback (older API signature)
void onReceiveData(const uint8_t *mac_addr, const uint8_t *incomingData, int len) {
  if (mac_addr == NULL || incomingData == NULL || len <= 0) return;

  // Discovery and commands are accepted only from the configured master.
  if (memcmp(mac_addr, MASTER_MAC, 6) != 0) return;

  if (incomingData[0] == ESPNOW_MSG_DISCOVERY_BEACON) {
    handleDiscoveryBeacon(incomingData, len);
    return;
  }

  if (incomingData[0] != ESPNOW_MSG_DEVICE_COMMAND) return;
  bool ready;
  portENTER_CRITICAL(&radioMux);
  ready = channelLocked && masterPeerRegistered;
  portEXIT_CRITICAL(&radioMux);
  if (!ready) return;
  if (len != (int)sizeof(DeviceCommandPayload)) return;

  DeviceCommandPayload command;
  memcpy(&command, incomingData, sizeof(command));

  if (!validateCommandCRC(command)) {
    Serial.println("ESP-NOW: Invalid CRC");
    return;
  }

  // Force null termination on string fields
  command.roomKey[sizeof(command.roomKey) - 1] = '\0';
  command.deviceKey[sizeof(command.deviceKey) - 1] = '\0';
  command.requestId[sizeof(command.requestId) - 1] = '\0';

  portENTER_CRITICAL(&commandMux);
  if (!commandPending) {
    memcpy(&receivedCommand, &command, sizeof(receivedCommand));
    commandPending = true;
  }
  portEXIT_CRITICAL(&commandMux);

  portENTER_CRITICAL(&radioMux);
  lastValidMasterPacketMs = millis();
  portEXIT_CRITICAL(&radioMux);
}

// Optional send callback (not required for basic operation)
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  // Can be used for send confirmation if needed
}

void initEspNow() {
  // Set WiFi mode to STA
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();

  if (esp_wifi_set_channel(scanChannel, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
    Serial.println("ESP-NOW initial channel set failed");
    return;
  }

  // Initialize ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW initialization failed");
    return;
  }

  // Register receive callback
  esp_now_register_recv_cb(onReceiveData);
  espNowInitialized = true;
  lastScanStepMs = millis();

  Serial.println("ESP-NOW initialized - scanning master channel");
  Serial.print("Scanning ESP-NOW channel: ");
  Serial.println(scanChannel);
}

bool registerMasterPeerOnLockedChannel() {
  if (!espNowInitialized || !channelLocked || lockedChannel == 0) return false;

  if (esp_wifi_set_channel(lockedChannel, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
    Serial.println("ESP-NOW locked channel set failed");
    return false;
  }
  scanChannel = lockedChannel;

  if (esp_now_is_peer_exist(MASTER_MAC)) {
    esp_now_del_peer(MASTER_MAC);
  }

  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, MASTER_MAC, 6);
  peerInfo.channel = lockedChannel;
  peerInfo.encrypt = false;
  peerInfo.ifidx = WIFI_IF_STA;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("ESP-NOW master peer add failed");
    return false;
  }

  portENTER_CRITICAL(&radioMux);
  masterPeerRegistered = true;
  portEXIT_CRITICAL(&radioMux);
  Serial.print("ESP-NOW locked master channel: ");
  Serial.println(lockedChannel);
  return true;
}

bool isEspNowReady() {
  bool ready;
  portENTER_CRITICAL(&radioMux);
  ready = espNowInitialized && channelLocked && masterPeerRegistered;
  portEXIT_CRITICAL(&radioMux);
  return ready;
}

void scanEspNowChannel() {
  if (!espNowInitialized) return;

  uint8_t beaconChannel;
  portENTER_CRITICAL(&radioMux);
  beaconChannel = pendingBeaconChannel;
  pendingBeaconChannel = 0;
  portEXIT_CRITICAL(&radioMux);

  if (beaconChannel > 0 &&
      (!channelLocked || lockedChannel != beaconChannel)) {
    portENTER_CRITICAL(&radioMux);
    lockedChannel = beaconChannel;
    channelLocked = true;
    masterPeerRegistered = false;
    pendingPeerRegistration = true;
    portEXIT_CRITICAL(&radioMux);
  }

  if (pendingPeerRegistration) {
    pendingPeerRegistration = false;
    if (!registerMasterPeerOnLockedChannel()) {
      channelLocked = false;
      lockedChannel = 0;
    }
    return;
  }

  if (channelLocked) return;

  uint32_t now = millis();
  if (now - lastScanStepMs < ESPNOW_SCAN_DWELL_MS) return;

  uint8_t nextChannel = scanChannel + 1;
  if (nextChannel > ESPNOW_SCAN_MAX_CHANNEL) {
    nextChannel = ESPNOW_SCAN_MIN_CHANNEL;
  }

  if (esp_wifi_set_channel(nextChannel, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
    Serial.print("ESP-NOW channel set failed: ");
    Serial.println(nextChannel);
  } else {
    scanChannel = nextChannel;
    Serial.print("Scanning ESP-NOW channel: ");
    Serial.println(scanChannel);
  }
  lastScanStepMs = now;
}

void checkEspNowLinkTimeout() {
  if (!isEspNowReady()) return;

  uint32_t now = millis();
  uint32_t lastPacketMs;
  portENTER_CRITICAL(&radioMux);
  lastPacketMs = lastValidMasterPacketMs;
  portEXIT_CRITICAL(&radioMux);
  if (now - lastPacketMs < ESPNOW_LINK_TIMEOUT_MS) return;

  Serial.println("ESP-NOW link timeout, rescanning channel");
  if (esp_now_is_peer_exist(MASTER_MAC)) {
    esp_now_del_peer(MASTER_MAC);
  }

  portENTER_CRITICAL(&radioMux);
  masterPeerRegistered = false;
  channelLocked = false;
  pendingPeerRegistration = false;
  lockedChannel = 0;
  portEXIT_CRITICAL(&radioMux);
  scanChannel = ESPNOW_SCAN_MIN_CHANNEL;
  esp_wifi_set_channel(scanChannel, WIFI_SECOND_CHAN_NONE);
  lastScanStepMs = now;
}

void sendStateToMaster(const DeviceStatePayload &state) {
  if (!isEspNowReady()) return;

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

bool popReceivedCommand(DeviceCommandPayload &command) {
  bool available;

  portENTER_CRITICAL(&commandMux);
  available = commandPending;
  if (available) {
    memcpy(&command, &receivedCommand, sizeof(command));
    commandPending = false;
  }
  portEXIT_CRITICAL(&commandMux);

  return available;
}
