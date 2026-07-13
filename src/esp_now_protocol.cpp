#include "esp_now_protocol.h"
#include <esp_now.h>
#include <WiFi.h>

const uint8_t SLAVE_MAC_ADDRESS[6] = {0x68, 0xB6, 0xB3, 0x2E, 0x42, 0x4C};

portMUX_TYPE espNowMux = portMUX_INITIALIZER_UNLOCKED;

volatile bool sendCallbackReceived = false;
volatile bool lastSendSuccess = false;

static const uint8_t RECEIVE_QUEUE_SIZE = 16;
static DeviceStatePayload receiveQueue[RECEIVE_QUEUE_SIZE];
static volatile uint8_t receiveQueueHead = 0;
static volatile uint8_t receiveQueueTail = 0;
static volatile uint8_t receiveQueueCount = 0;

static bool espNowInitialized = false;
static bool peerRegistered = false;

void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status)
{
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
        receiveQueueTail = (receiveQueueTail + 1) % RECEIVE_QUEUE_SIZE;
        receiveQueueCount++;
    }
    portEXIT_CRITICAL(&espNowMux);
}

bool popReceivedStatePacket(DeviceStatePayload &packet)
{
    bool available = false;
    portENTER_CRITICAL(&espNowMux);
    if (receiveQueueCount > 0)
    {
        packet = receiveQueue[receiveQueueHead];
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
    if (esp_now_init() != ESP_OK)
    {
        Serial.println("ESP-NOW init failed");
        return false;
    }
    esp_now_register_send_cb(onDataSent);
    esp_now_register_recv_cb(onDataRecv);
    espNowInitialized = true;
    Serial.println("ESP-NOW initialized");
    return true;
}

bool registerSlavePeer()
{
    if (!espNowInitialized)
    {
        return false;
    }
    esp_now_peer_info_t peerInfo = {};
    memcpy(peerInfo.peer_addr, SLAVE_MAC_ADDRESS, 6);
    peerInfo.channel = 0;
    peerInfo.ifidx = WIFI_IF_STA;
    peerInfo.encrypt = false;
    if (esp_now_add_peer(&peerInfo) != ESP_OK)
    {
        Serial.println("ESP-NOW add peer failed");
        return false;
    }
    peerRegistered = true;
    Serial.println("ESP-NOW slave peer registered");
    return true;
}

bool sendCommandToSlave(const DeviceCommandPayload &cmd)
{
    if (!espNowInitialized || !peerRegistered)
    {
        Serial.println("Failed send command Slave. ESP-NOW not initialized or peer not registered");
        return false;
    }

    sendCallbackReceived = false;
    lastSendSuccess = false;
    esp_err_t result = esp_now_send(SLAVE_MAC_ADDRESS, (uint8_t *)&cmd, sizeof(DeviceCommandPayload));
    if (result != ESP_OK)
    {
        Serial.print("ESP-NOW send error: ");
        Serial.println(result);
        return false;
    }
    return true;
}
