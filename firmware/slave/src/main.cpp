#include "relay.h"
#include "dimmer.h"
#include "esp_now_config.h"
#include "room_device_routing.h"

// Status reporting interval
const unsigned long STATUS_INTERVAL = 5000;
unsigned long lastStatusReport = 0;
bool bootSnapshotSent = false;

void sendFullStateSnapshot(const char *startMessage, const char *endMessage)
{
    Serial.println(startMessage);

    DeviceStatePayload statePayload;
    uint8_t count = getDeviceCount();
    for (uint8_t i = 0; i < count; i++)
    {
        buildPeriodicStateForDevice(i, statePayload);
        sendStateToMaster(statePayload);
        delay(20);
    }

    if (endMessage != nullptr)
    {
        Serial.println(endMessage);
    }
}

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

    Serial.println("System Ready - Scanning for master");
}

void loop()
{
    unsigned long currentMillis = millis();

    scanEspNowChannel();
    checkEspNowLinkTimeout();

    if (!isEspNowReady())
    {
        delay(50);
        return;
    }

    if (!bootSnapshotSent)
    {
        bootSnapshotSent = true;
        sendFullStateSnapshot("Sending boot state snapshot...", nullptr);
        lastStatusReport = currentMillis;
    }

    // Check for received ESP-NOW command
    DeviceCommandPayload cmd;
    if (popReceivedCommand(cmd))
    {
        Serial.printf("Command: room=%s, device=%s, state=%d, brightness=%d, reqId=%s\n",
                      cmd.roomKey, cmd.deviceKey, cmd.state, cmd.brightness, cmd.requestId);

        // Apply command via semantic routing layer
        DeviceStatePayload statePayload;
        applyDeviceCommand(cmd, statePayload);

        // Always send ACK back (even on failure)
        sendStateToMaster(statePayload);
        delay(20);

        // Shared dimmer state must reach every semantic device immediately.
        if (isDimmableDevice(cmd.roomKey, cmd.deviceKey))
        {
            sendFullStateSnapshot("Sending dimmer state snapshot...", nullptr);
            lastStatusReport = millis();
            currentMillis = lastStatusReport;
        }
    }

    // Send periodic full status every 5 seconds
    if (currentMillis - lastStatusReport >= STATUS_INTERVAL)
    {
        lastStatusReport = currentMillis;

        sendFullStateSnapshot("--- STATUS REPORT ---", "--- END STATUS ---");
    }

    delay(50);
}
