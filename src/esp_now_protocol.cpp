#include "esp_now_protocol.h"
#include "esp_now_keys.h"
#include <esp_now.h>
#include <WiFi.h>

const uint8_t SLAVE_MAC_ADDRESS[6] = {0x68, 0xB6, 0xB3, 0x2E, 0x42, 0x4C};
static const uint8_t ESPNOW_BROADCAST_MAC[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

portMUX_TYPE espNowMux = portMUX_INITIALIZER_UNLOCKED;

volatile bool sendCallbackReceived = false;
volatile bool lastSendSuccess = false;

static const uint8_t RECEIVE_QUEUE_SIZE = 16;
static DeviceStatePayload receiveQueue[RECEIVE_QUEUE_SIZE];
static unsigned long receiveQueueTimestamps[RECEIVE_QUEUE_SIZE];
static volatile uint8_t receiveQueueHead = 0;
static volatile uint8_t receiveQueueTail = 0;
static volatile uint8_t receiveQueueCount = 0;

static bool espNowInitialized = false;
static bool peerRegistered = false;
static bool broadcastPeerRegistered = false;
static uint8_t peerChannel = 0;
static uint8_t broadcastPeerChannel = 0;

static bool recoverESPNowInit()
{
    espNowInitialized = false;
    peerRegistered = false;
    broadcastPeerRegistered = false;
    peerChannel = 0;
    broadcastPeerChannel = 0;
    return initESPNow();
}

void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status)
{
    if (mac_addr == nullptr || memcmp(mac_addr, SLAVE_MAC_ADDRESS, 6) != 0)
    {
        return;
    }

    portENTER_CRITICAL(&espNowMux);
    lastSendSuccess = (status == ESP_NOW_SEND_SUCCESS);
    sendCallbackReceived = true;
    portEXIT_CRITICAL(&espNowMux);
}

void onDataRecv(const uint8_t *mac_addr, const uint8_t *data, int data_len)
{
    if (mac_addr == nullptr || data == nullptr ||
        memcmp(mac_addr, SLAVE_MAC_ADDRESS, 6) != 0 ||
        data_len != sizeof(DeviceStatePayload))
    {
        return;
    }

    portENTER_CRITICAL(&espNowMux);
    if (receiveQueueCount < RECEIVE_QUEUE_SIZE)
    {
        memcpy(&receiveQueue[receiveQueueTail], data, sizeof(DeviceStatePayload));
        receiveQueueTimestamps[receiveQueueTail] = millis();
        receiveQueueTail = (receiveQueueTail + 1) % RECEIVE_QUEUE_SIZE;
        receiveQueueCount++;
    }
    portEXIT_CRITICAL(&espNowMux);
}

bool popReceivedStatePacket(DeviceStatePayload &packet, unsigned long &receivedMs)
{
    bool available = false;
    portENTER_CRITICAL(&espNowMux);
    if (receiveQueueCount > 0)
    {
        packet = receiveQueue[receiveQueueHead];
        receivedMs = receiveQueueTimestamps[receiveQueueHead];
        receiveQueueHead = (receiveQueueHead + 1) % RECEIVE_QUEUE_SIZE;
        receiveQueueCount--;
        available = true;
    }
    portEXIT_CRITICAL(&espNowMux);

    return available;
}

uint8_t computeXorCRC(const uint8_t *data, size_t len)
{
    uint8_t crc = 0;
    for (size_t i = 0; i < len; i++)
    {
        crc ^= data[i];
    }
    return crc;
}

DeviceOwner getDeviceOwner(const String &roomKey, const String &deviceKey)
{
    if (roomKey == "teras")
    {
        return DeviceOwner::Master;
    }
    if (roomKey == "kamar_1" || roomKey == "kamar_2" || roomKey == "dapur" || roomKey == "lorong")
    {
        return DeviceOwner::Slave;
    }
    return DeviceOwner::Unknown;
}

bool isSlaveOwned(const String &roomKey, const String &deviceKey)
{
    return getDeviceOwner(roomKey, deviceKey) == DeviceOwner::Slave;
}

String generateRequestId()
{
    static uint16_t counter = 0;
    counter++;
    return String(millis(), HEX) + "_" + String(counter);
}

bool initESPNow()
{
    if (espNowInitialized)
    {
        return true;
    }

    if (WiFi.status() != WL_CONNECTED || getCurrentEspNowChannel() == 0)
    {
        Serial.println("ESP-NOW init skipped: WiFi router not connected");
        return false;
    }

    if (esp_now_init() != ESP_OK)
    {
        Serial.println("ESP-NOW init failed");
        return false;
    }
    if (esp_now_set_pmk(ESPNOW_PMK) != ESP_OK)
    {
        Serial.println("ESP-NOW PMK setup failed");
        esp_now_deinit();
        return false;
    }
    esp_now_register_send_cb(onDataSent);
    esp_now_register_recv_cb(onDataRecv);
    espNowInitialized = true;
    Serial.print("ESP-NOW initialized on router channel: ");
    Serial.println(getCurrentEspNowChannel());
    return true;
}

uint8_t getCurrentEspNowChannel()
{
    return WiFi.channel();
}

bool registerSlavePeer()
{
    if (!espNowInitialized)
    {
        return false;
    }

    const uint8_t channel = getCurrentEspNowChannel();
    if (channel == 0)
    {
        return false;
    }

    if (peerRegistered && peerChannel == channel && esp_now_is_peer_exist(SLAVE_MAC_ADDRESS))
    {
        return true;
    }

    peerRegistered = false;
    peerChannel = 0;
    if (esp_now_is_peer_exist(SLAVE_MAC_ADDRESS))
    {
        esp_now_del_peer(SLAVE_MAC_ADDRESS);
    }

    esp_now_peer_info_t peerInfo = {};
    memcpy(peerInfo.peer_addr, SLAVE_MAC_ADDRESS, 6);
    memcpy(peerInfo.lmk, ESPNOW_LMK, ESP_NOW_KEY_LEN);
    peerInfo.channel = channel;
    peerInfo.ifidx = WIFI_IF_STA;
    peerInfo.encrypt = true;
    esp_err_t result = esp_now_add_peer(&peerInfo);
    if (result == ESP_ERR_ESPNOW_NOT_INIT && recoverESPNowInit())
    {
        result = esp_now_add_peer(&peerInfo);
    }
    if (result != ESP_OK)
    {
        Serial.println("ESP-NOW add peer failed");
        return false;
    }
    peerRegistered = true;
    peerChannel = channel;
    Serial.println("ESP-NOW slave peer registered");
    return true;
}

bool registerBroadcastPeer()
{
    if (!espNowInitialized)
    {
        return false;
    }

    const uint8_t channel = getCurrentEspNowChannel();
    if (channel == 0)
    {
        return false;
    }

    if (broadcastPeerRegistered && broadcastPeerChannel == channel && esp_now_is_peer_exist(ESPNOW_BROADCAST_MAC))
    {
        return true;
    }

    broadcastPeerRegistered = false;
    broadcastPeerChannel = 0;
    if (esp_now_is_peer_exist(ESPNOW_BROADCAST_MAC))
    {
        esp_now_del_peer(ESPNOW_BROADCAST_MAC);
    }

    esp_now_peer_info_t peerInfo = {};
    memcpy(peerInfo.peer_addr, ESPNOW_BROADCAST_MAC, 6);
    peerInfo.channel = channel;
    peerInfo.ifidx = WIFI_IF_STA;
    peerInfo.encrypt = false;
    esp_err_t result = esp_now_add_peer(&peerInfo);
    if (result == ESP_ERR_ESPNOW_NOT_INIT && recoverESPNowInit())
    {
        result = esp_now_add_peer(&peerInfo);
    }
    if (result != ESP_OK)
    {
        Serial.println("ESP-NOW broadcast peer add failed");
        return false;
    }

    broadcastPeerRegistered = true;
    broadcastPeerChannel = channel;
    Serial.println("ESP-NOW broadcast peer registered");
    return true;
}

bool sendDiscoveryBeacon()
{
    if ((!espNowInitialized && !initESPNow()) || !registerBroadcastPeer())
    {
        return false;
    }

    DiscoveryBeaconPayload beacon = {};
    beacon.type = ESPNOW_MSG_DISCOVERY_BEACON;
    beacon.channel = getCurrentEspNowChannel();
    beacon.magic = ESPNOW_DISCOVERY_MAGIC;
    beacon.crc = computeXorCRC(reinterpret_cast<const uint8_t *>(&beacon), sizeof(beacon) - 1);

    bool broadcastSent = esp_now_send(ESPNOW_BROADCAST_MAC,
                                      reinterpret_cast<const uint8_t *>(&beacon),
                                      sizeof(beacon)) == ESP_OK;

    if (registerSlavePeer())
    {
        beacon.type = ESPNOW_MSG_AUTHENTICATED_BEACON;
        beacon.crc = computeXorCRC(reinterpret_cast<const uint8_t *>(&beacon),
                                   sizeof(beacon) - 1);
        esp_now_send(SLAVE_MAC_ADDRESS,
                     reinterpret_cast<const uint8_t *>(&beacon),
                     sizeof(beacon));
    }
    return broadcastSent;
}

bool sendCommandToSlave(const DeviceCommandPayload &cmd)
{
    if ((!espNowInitialized && !initESPNow()) || !registerSlavePeer())
    {
        Serial.println("Failed send command Slave. ESP-NOW not initialized or peer not registered");
        return false;
    }

    portENTER_CRITICAL(&espNowMux);
    sendCallbackReceived = false;
    lastSendSuccess = false;
    portEXIT_CRITICAL(&espNowMux);
    esp_err_t result = esp_now_send(SLAVE_MAC_ADDRESS, (uint8_t *)&cmd, sizeof(DeviceCommandPayload));
    if (result != ESP_OK)
    {
        Serial.print("ESP-NOW send error: ");
        Serial.println(result);
        return false;
    }
    return true;
}
