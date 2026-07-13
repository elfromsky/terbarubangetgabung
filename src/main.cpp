#include "relay.h"
#include "dimmer.h"
#include "esp_now_config.h"
#include "room_device_routing.h"

// External functions from esp_now_handler.cpp
extern void setCommandPending(bool pending);
extern DeviceCommandPayload *getReceivedCommand();
extern uint32_t getLastCommandTime();

// Status reporting interval
const unsigned long STATUS_INTERVAL = 5000;
unsigned long lastStatusReport = 0;

void setup()
{
    Serial.begin(115200);
    delay(1500);
    Serial.println("BOOT OK");

    // Initialize relay pins (ALL OFF by default)
    Serial.println("Initializing relays...");
    initRelays();

    // Initialize dimmer (ALL OFF by default)
    Serial.println("Initializing dimmer...");
    initializeDimmers();

    // Initialize ESP-NOW
    Serial.println("Initializing ESP-NOW...");
    initEspNow();

    // Send immediate full-state snapshot so master can resync before first periodic report
    Serial.println("Sending boot state snapshot...");
    {
        DeviceStatePayload statePayload;
        uint8_t count = getDeviceCount();
        for (uint8_t i = 0; i < count; i++)
        {
            buildPeriodicStateForDevice(i, statePayload);
            sendStateToMaster(statePayload);
            delay(20);
        }
    }

    Serial.println("System Ready - Waiting for commands from master");
}

void loop()
{
    unsigned long currentMillis = millis();

    // Check for received ESP-NOW command
    DeviceCommandPayload *cmd = getReceivedCommand();
    if (cmd != nullptr)
    {
        setCommandPending(false);

        Serial.printf("Command: room=%s, device=%s, state=%d, brightness=%d, reqId=%s\n",
                      cmd->roomKey, cmd->deviceKey, cmd->state, cmd->brightness, cmd->requestId);

        // Apply command via semantic routing layer
        DeviceStatePayload statePayload;
        applyDeviceCommand(*cmd, statePayload);

        // Always send ACK back (even on failure)
        sendStateToMaster(statePayload);
    }

    // Send periodic full status every 5 seconds
    if (currentMillis - lastStatusReport >= STATUS_INTERVAL)
    {
        lastStatusReport = currentMillis;

        Serial.println("--- STATUS REPORT ---");

        DeviceStatePayload statePayload;
        uint8_t count = getDeviceCount();
        for (uint8_t i = 0; i < count; i++)
        {
            buildPeriodicStateForDevice(i, statePayload);
            sendStateToMaster(statePayload);
            delay(20);
        }

        Serial.println("--- END STATUS ---");
    }

    delay(50);
}
