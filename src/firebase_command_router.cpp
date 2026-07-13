#include "firebase_command_router.h"
#include "firebase_app.h"
#include "esp_now_protocol.h"
#include "relay.h"
#include <ArduinoJson.h>
#include <cstring>

namespace
{
    struct ParsedRoomCommand
    {
        bool valid = false;
        bool isOn = false;
        int brightness = 0;
    };

    struct PendingCommand
    {
        bool active = false;
        char requestId[32];
        char firebasePath[128];
        char roomKey[24];
        char deviceKey[32];
        uint8_t state;
        uint8_t brightness;
        unsigned long sentMs;
    };

    PendingCommand pendingCmd;
    const unsigned long ESP_NOW_TIMEOUT_MS = 3000;

    bool isStateOnlyDevice(const String &roomKey, const String &deviceKey)
    {
        if (roomKey == "teras")
        {
            return deviceKey == "lampu" || deviceKey == "sanyo";
        }
        if (roomKey == "lorong")
        {
            return deviceKey == "blower" || deviceKey == "stop_kontak";
        }
        if (roomKey == "kamar_1" || roomKey == "kamar_2")
        {
            return deviceKey == "stop_kontak";
        }
        if (roomKey == "dapur")
        {
            return deviceKey == "blower";
        }
        return false;
    }

    bool isDimmableDevice(const String &roomKey, const String &deviceKey)
    {
        if (roomKey == "kamar_1" || roomKey == "kamar_2")
        {
            return deviceKey == "lampu";
        }
        if (roomKey == "dapur")
        {
            return deviceKey == "lampu";
        }
        return false;
    }

    bool isKnownDevice(const String &roomKey, const String &deviceKey)
    {
        return isStateOnlyDevice(roomKey, deviceKey) || isDimmableDevice(roomKey, deviceKey);
    }

    bool parseStateText(String stateText, bool &isOn)
    {
        stateText.trim();
        stateText.toUpperCase();
        if (stateText == "ON" || stateText == "TRUE" || stateText == "1")
        {
            isOn = true;
            return true;
        }
        if (stateText == "OFF" || stateText == "FALSE" || stateText == "0")
        {
            isOn = false;
            return true;
        }
        return false;
    }

    bool parseStateValue(JsonVariant value, bool &isOn)
    {
        if (value.is<bool>())
        {
            isOn = value.as<bool>();
            return true;
        }

        if (value.is<int>())
        {
            int stateValue = value.as<int>();
            if (stateValue == 0 || stateValue == 1)
            {
                isOn = stateValue == 1;
                return true;
            }
            return false;
        }

        if (value.is<const char *>())
        {
            return parseStateText(value.as<String>(), isOn);
        }

        return false;
    }

    void removeCommand(const String &path)
    {
        firebaseDatabase().remove(firebaseDataClient(), path);
    }

    void setDeviceRoomState(const String &roomKey, const String &deviceKey, bool isOn, int brightness)
    {
        if (brightness < 0)
        {
            brightness = 0;
        }
        if (brightness > 100)
        {
            brightness = 100;
        }

        String path = "/rooms/" + roomKey + "/" + deviceKey;
        if (isStateOnlyDevice(roomKey, deviceKey))
        {
            firebaseDatabase().set<bool>(firebaseDataClient(), path, isOn);
            return;
        }

        if (isDimmableDevice(roomKey, deviceKey))
        {
            if (!isOn)
            {
                brightness = 0;
            }
            char buf[128];
            snprintf(buf, sizeof(buf), "{\"state\":%s,\"brightness\":%d}", isOn ? "true" : "false", brightness);
            firebaseDatabase().set<object_t>(firebaseDataClient(), path, object_t(buf));
            return;
        }

        Serial.println("Room state write ignored: unknown device");
    }

    void setDeviceRoomState(const String &roomKey, const String &deviceKey, bool isOn)
    {
        setDeviceRoomState(roomKey, deviceKey, isOn, isOn ? 100 : 0);
    }

    ParsedRoomCommand parseRoomCommand(const String &roomKey, const String &deviceKey, const String &payload)
    {
        ParsedRoomCommand command;
        JsonDocument doc;
        DeserializationError error = deserializeJson(doc, payload);
        if (error)
        {
            if (isStateOnlyDevice(roomKey, deviceKey))
            {
                bool isOn = false;
                if (parseStateText(payload, isOn))
                {
                    command.isOn = isOn;
                    command.brightness = command.isOn ? 100 : 0;
                    command.valid = true;
                    return command;
                }
            }
            Serial.print("Command JSON parse error: ");
            Serial.println(error.c_str());
            return command;
        }

        if (isStateOnlyDevice(roomKey, deviceKey))
        {
            JsonVariant stateValue = doc.as<JsonVariant>();
            if (doc.is<JsonObject>())
            {
                stateValue = doc["state"];
            }

            bool isOn = false;
            if (!parseStateValue(stateValue, isOn))
            {
                Serial.println("Invalid state-only command: expected bool, ON/OFF, or object state");
                return command;
            }

            command.isOn = isOn;
            command.brightness = command.isOn ? 100 : 0;
            command.valid = true;
            return command;
        }

        if (isDimmableDevice(roomKey, deviceKey))
        {
            if (!doc.is<JsonObject>())
            {
                Serial.println("Invalid dimmable command: expected object");
                return command;
            }

            JsonVariant state = doc["state"];
            JsonVariant brightness = doc["brightness"];
            bool isOn = false;
            if (!parseStateValue(state, isOn) || !brightness.is<int>())
            {
                Serial.println("Invalid dimmable command fields");
                return command;
            }

            int brightnessValue = brightness.as<int>();
            if (brightnessValue < 0 || brightnessValue > 100)
            {
                Serial.println("Invalid brightness value in command");
                return command;
            }

            command.isOn = isOn;
            command.brightness = command.isOn ? brightnessValue : 0;
            command.valid = true;
        }

        return command;
    }

    void forwardToSlave(const String &roomKey, const String &deviceKey, bool isOn, int brightness, const String &fullPath)
    {
        if (pendingCmd.active)
        {
            Serial.println("Slave command dropped: pending command in flight");
            removeCommand(fullPath);
            return;
        }

        DeviceCommandPayload cmd = {};
        cmd.type = CMD_TYPE_COMMAND;
        strncpy(cmd.roomKey, roomKey.c_str(), sizeof(cmd.roomKey) - 1);
        strncpy(cmd.deviceKey, deviceKey.c_str(), sizeof(cmd.deviceKey) - 1);
        cmd.state = isOn ? 1 : 0;
        cmd.brightness = (uint8_t)brightness;
        String requestId = generateRequestId();
        strncpy(cmd.requestId, requestId.c_str(), sizeof(cmd.requestId) - 1);
        cmd.crc = computeXorCRC((uint8_t *)&cmd, sizeof(cmd) - 1);

        if (!sendCommandToSlave(cmd))
        {
            Serial.println("Failed to queue slave command via ESP-NOW");
            removeCommand(fullPath);
            return;
        }

        pendingCmd.active = true;
        strncpy(pendingCmd.requestId, requestId.c_str(), sizeof(pendingCmd.requestId) - 1);
        pendingCmd.requestId[sizeof(pendingCmd.requestId) - 1] = '\0';
        strncpy(pendingCmd.firebasePath, fullPath.c_str(), sizeof(pendingCmd.firebasePath) - 1);
        pendingCmd.firebasePath[sizeof(pendingCmd.firebasePath) - 1] = '\0';
        strncpy(pendingCmd.roomKey, roomKey.c_str(), sizeof(pendingCmd.roomKey) - 1);
        pendingCmd.roomKey[sizeof(pendingCmd.roomKey) - 1] = '\0';
        strncpy(pendingCmd.deviceKey, deviceKey.c_str(), sizeof(pendingCmd.deviceKey) - 1);
        pendingCmd.deviceKey[sizeof(pendingCmd.deviceKey) - 1] = '\0';
        pendingCmd.state = cmd.state;
        pendingCmd.brightness = cmd.brightness;
        pendingCmd.sentMs = millis();

        Serial.print("Forwarded to slave: ");
        Serial.print(roomKey);
        Serial.print("/");
        Serial.print(deviceKey);
        Serial.print(" state=");
        Serial.print(isOn ? "ON" : "OFF");
        Serial.print(" brightness=");
        Serial.print(brightness);
        Serial.print(" rid=");
        Serial.println(requestId);
    }
}

void handleFirebaseResult(AsyncResult &aResult)
{
    if (!aResult.isResult())
        return;

    if (aResult.isError())
    {
        Firebase.printf("Error task: %s, msg: %s, code: %d\n", aResult.uid().c_str(), aResult.error().message().c_str(), aResult.error().code());
    }

    if (!aResult.available())
        return;

    RealtimeDatabaseResult &stream = aResult.to<RealtimeDatabaseResult>();
    if (stream.isStream())
    {
        handleCommandStream(stream);
    }
}

void handleCommandStream(RealtimeDatabaseResult &stream)
{
    String event = stream.event();
    if (event == "keep-alive")
    {
        return;
    }

    String path = stream.dataPath();
    String payload = stream.to<String>();

    if (payload == "null" || path == "/")
    {
        return;
    }

    String fullPath = path;
    if (!fullPath.startsWith("/commands"))
    {
        fullPath = "/commands" + fullPath;
    }

    if (fullPath.startsWith("/commands/rooms/"))
    {
        String remainder = fullPath.substring(strlen("/commands/rooms/"));
        int slashPos = remainder.indexOf('/');
        if (slashPos < 0)
        {
            return;
        }

        String roomKey = remainder.substring(0, slashPos);
        String devicePath = remainder.substring(slashPos + 1);
        if (devicePath.endsWith("/state"))
        {
            devicePath = devicePath.substring(0, devicePath.length() - strlen("/state"));
        }

        if (devicePath.indexOf('/') >= 0)
        {
            Serial.println("Ignoring command with unsupported nested device path");
            removeCommand(fullPath);
            return;
        }

        String deviceKey = devicePath;

        if (!isKnownDevice(roomKey, deviceKey))
        {
            Serial.println("Ignoring unknown room/device command");
            removeCommand(fullPath);
            return;
        }

        ParsedRoomCommand command = parseRoomCommand(roomKey, deviceKey, payload);
        Serial.printf("Parsed room command: valid=%s, isOn=%s, brightness=%d\n", command.valid ? "true" : "false", command.isOn ? "ON" : "OFF", command.brightness);

        if (!command.valid)
        {
            removeCommand(fullPath);
            return;
        }

        DeviceOwner owner = getDeviceOwner(roomKey, deviceKey);
        switch (owner)
        {
        case DeviceOwner::Master:
            if (setMasterRelayState(roomKey, deviceKey, command.isOn))
            {
                setDeviceRoomState(roomKey, deviceKey, getMasterRelayState(roomKey, deviceKey));
            }
            else
            {
                Serial.println("Master relay command ignored: unknown relay device");
            }
            removeCommand(fullPath);
            break;

        case DeviceOwner::Slave:
            forwardToSlave(roomKey, deviceKey, command.isOn, command.brightness, fullPath);
            break;

        case DeviceOwner::Unknown:
            Serial.println("Ignoring unknown room/device command");
            removeCommand(fullPath);
            break;
        }
        return;
    }

    Serial.println("Ignoring command outside /commands/rooms contract");
}

void processSlaveCommunication()
{
    DeviceStatePayload pkt;
    while (popReceivedStatePacket(pkt))
    {
        uint8_t computedCrc = computeXorCRC((uint8_t *)&pkt, sizeof(pkt) - 1);
        if (computedCrc != pkt.crc)
        {
            Serial.println("Slave packet CRC mismatch, ignored");
            continue;
        }

        if (pkt.type != CMD_TYPE_STATE)
        {
            continue;
        }

        pkt.roomKey[sizeof(pkt.roomKey) - 1] = '\0';
        pkt.deviceKey[sizeof(pkt.deviceKey) - 1] = '\0';
        pkt.requestId[sizeof(pkt.requestId) - 1] = '\0';

        bool matchedAck = pendingCmd.active &&
                          strcmp(pkt.requestId, pendingCmd.requestId) == 0 &&
                          strcmp(pkt.roomKey, pendingCmd.roomKey) == 0 &&
                          strcmp(pkt.deviceKey, pendingCmd.deviceKey) == 0;

        if (matchedAck)
        {
            if (pkt.success)
            {
                setDeviceRoomState(String(pkt.roomKey), String(pkt.deviceKey), pkt.state != 0, pkt.brightness);
                Serial.print("Slave ACK OK: ");
            }
            else
            {
                Serial.print("Slave ACK error code=");
                Serial.print(pkt.errorCode);
                Serial.print(": ");
            }
            Serial.print(pkt.roomKey);
            Serial.print("/");
            Serial.println(pkt.deviceKey);

            removeCommand(String(pendingCmd.firebasePath));
            pendingCmd.active = false;
            continue;
        }

        if (isSlaveOwned(String(pkt.roomKey), String(pkt.deviceKey)))
        {
            setDeviceRoomState(String(pkt.roomKey), String(pkt.deviceKey), pkt.state != 0, pkt.brightness);
            Serial.print("Slave report: ");
            Serial.print(pkt.roomKey);
            Serial.print("/");
            Serial.print(pkt.deviceKey);
            Serial.print(" state=");
            Serial.print(pkt.state);
            Serial.print(" brightness=");
            Serial.println(pkt.brightness);
        }
    }

    bool callbackReceived = false;
    bool sendFailed = false;
    {
        portENTER_CRITICAL(&espNowMux);
        if (pendingCmd.active && sendCallbackReceived)
        {
            sendCallbackReceived = false;
            callbackReceived = true;
            sendFailed = !lastSendSuccess;
        }
        portEXIT_CRITICAL(&espNowMux);
    }

    if (callbackReceived && sendFailed)
    {
        Serial.print("ESP-NOW send failed for: ");
        Serial.print(pendingCmd.roomKey);
        Serial.print("/");
        Serial.println(pendingCmd.deviceKey);
        removeCommand(String(pendingCmd.firebasePath));
        pendingCmd.active = false;
        return;
    }

    if (pendingCmd.active && millis() - pendingCmd.sentMs >= ESP_NOW_TIMEOUT_MS)
    {
        Serial.print("Slave ACK timeout: ");
        Serial.print(pendingCmd.roomKey);
        Serial.print("/");
        Serial.println(pendingCmd.deviceKey);
        removeCommand(String(pendingCmd.firebasePath));
        pendingCmd.active = false;
    }
}
