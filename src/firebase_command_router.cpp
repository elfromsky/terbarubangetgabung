#include "firebase_command_router.h"
#include "firebase_app.h"
#include "esp_now_protocol.h"
#include "relay.h"
#include <ArduinoJson.h>
#include <cstring>

namespace
{
struct ParsedCommand
{
    bool valid;
    bool state;
    uint8_t brightness;
};

struct DeviceRoute
{
    const char *roomKey;
    const char *deviceKey;
    DeviceOwner owner;
    bool dimmable;
    bool desiredKnown;
    bool desiredState;
    uint8_t desiredBrightness;
    bool actualKnown;
    bool actualState;
    uint8_t actualBrightness;
    bool dirty;
    bool publishPending;
    unsigned long nextRetryMs;
    unsigned long nextPublishMs;
};

DeviceRoute routes[] = {
    {"teras", "lampu", DeviceOwner::Master, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"teras", "sanyo", DeviceOwner::Master, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"lorong", "blower", DeviceOwner::Slave, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"lorong", "stop_kontak", DeviceOwner::Slave, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"kamar_1", "stop_kontak", DeviceOwner::Slave, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"kamar_2", "stop_kontak", DeviceOwner::Slave, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"dapur", "blower", DeviceOwner::Slave, false, false, false, 0, false, false, 0, false, false, 0, 0},
    {"kamar_1", "lampu", DeviceOwner::Slave, true, false, false, 0, false, false, 0, false, false, 0, 0},
    {"kamar_2", "lampu", DeviceOwner::Slave, true, false, false, 0, false, false, 0, false, false, 0, 0},
    {"dapur", "lampu", DeviceOwner::Slave, true, false, false, 0, false, false, 0, false, false, 0, 0},
};

constexpr size_t ROUTE_COUNT = sizeof(routes) / sizeof(routes[0]);
static_assert(ROUTE_COUNT == 10, "Device route table must contain 10 routes");
constexpr uint8_t MAX_SEND_ATTEMPTS = 3;
constexpr unsigned long SEND_RETRY_DELAY_MS = 300;
constexpr unsigned long ACK_TIMEOUT_MS = 3000;
constexpr unsigned long CYCLE_BACKOFF_MS = 2000;
constexpr unsigned long PUBLISH_RETRY_MS = 2000;

struct PendingCommand
{
    bool active;
    DeviceCommandPayload payload;
    size_t routeIndex;
    uint8_t attempts;
    unsigned long sentMs;
    unsigned long nextAttemptMs;
    bool waitingForAck;
};

PendingCommand pendingCmd = {};
size_t nextSlaveRoute = 0;
size_t nextPublishRoute = 0;

bool deadlineReached(unsigned long now, unsigned long deadline)
{
    return static_cast<long>(now - deadline) >= 0;
}

int findRoute(const String &roomKey, const String &deviceKey)
{
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        if (roomKey == routes[i].roomKey && deviceKey == routes[i].deviceKey)
        {
            return static_cast<int>(i);
        }
    }
    return -1;
}

int findSlaveRoute(const char *roomKey, const char *deviceKey)
{
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        if (routes[i].owner == DeviceOwner::Slave &&
            strcmp(roomKey, routes[i].roomKey) == 0 &&
            strcmp(deviceKey, routes[i].deviceKey) == 0)
        {
            return static_cast<int>(i);
        }
    }
    return -1;
}

bool actualMatchesDesired(const DeviceRoute &route)
{
    if (!route.desiredKnown || !route.actualKnown || route.desiredState != route.actualState)
    {
        return false;
    }
    return !route.dimmable ||
           (!route.desiredState && route.desiredBrightness == 0) ||
           route.desiredBrightness == route.actualBrightness;
}

void refreshDirty(DeviceRoute &route)
{
    route.dirty = route.desiredKnown && !actualMatchesDesired(route);
}

ParsedCommand parseCommand(const DeviceRoute &route, JsonVariantConst value)
{
    ParsedCommand command = {false, false, 0};
    if (!value.is<JsonObjectConst>())
    {
        Serial.println("Invalid command: expected object payload");
        return command;
    }

    JsonObjectConst object = value.as<JsonObjectConst>();
    JsonVariantConst state = object["state"];
    if (!state.is<bool>())
    {
        Serial.println("Invalid command: state must be bool");
        return command;
    }

    if (!route.dimmable)
    {
        if (object.size() != 1)
        {
            Serial.println("Invalid relay command: expected only state");
            return command;
        }
        command.valid = true;
        command.state = state.as<bool>();
        return command;
    }

    JsonVariantConst brightness = object["brightness"];
    if (object.size() != 2 || !brightness.is<int>())
    {
        Serial.println("Invalid dimmer command: expected state bool and brightness integer");
        return command;
    }

    int brightnessValue = brightness.as<int>();
    if (brightnessValue < 0 || brightnessValue > 100)
    {
        Serial.println("Invalid dimmer command: brightness must be 0..100");
        return command;
    }

    command.valid = true;
    command.state = state.as<bool>();
    command.brightness = static_cast<uint8_t>(command.state && brightnessValue == 0 ? 1 : brightnessValue);
    return command;
}

void acceptDesired(size_t routeIndex, JsonVariantConst value)
{
    if (value.isNull())
    {
        return;
    }

    DeviceRoute &route = routes[routeIndex];
    ParsedCommand command = parseCommand(route, value);
    if (!command.valid)
    {
        Serial.print("Command ignored for ");
        Serial.print(route.roomKey);
        Serial.print("/");
        Serial.println(route.deviceKey);
        return;
    }

    route.desiredKnown = true;
    route.desiredState = command.state;
    route.desiredBrightness = command.brightness;
    refreshDirty(route);
    route.nextRetryMs = millis();

    if (pendingCmd.active && pendingCmd.routeIndex == routeIndex)
    {
        bool payloadIsCurrent = pendingCmd.payload.state == (route.desiredState ? 1 : 0) &&
                                pendingCmd.payload.brightness ==
                                    (route.dimmable ? route.desiredBrightness : (route.desiredState ? 100 : 0));
        if (!payloadIsCurrent && !pendingCmd.waitingForAck)
        {
            pendingCmd.active = false;
        }
    }

    Serial.print("Desired state updated: ");
    Serial.print(route.roomKey);
    Serial.print("/");
    Serial.print(route.deviceKey);
    Serial.print(" state=");
    Serial.print(route.desiredState ? "ON" : "OFF");
    if (route.dimmable)
    {
        Serial.print(" brightness=");
        Serial.print(route.desiredBrightness);
    }
    Serial.println();
}

void processDevicePayload(const String &roomKey, const String &deviceKey, const String &payload)
{
    int routeIndex = findRoute(roomKey, deviceKey);
    if (routeIndex < 0)
    {
        Serial.println("Ignoring unknown room/device command");
        return;
    }

    JsonDocument document;
    DeserializationError error = deserializeJson(document, payload);
    if (error)
    {
        Serial.print("Command JSON parse error: ");
        Serial.println(error.c_str());
        return;
    }
    acceptDesired(static_cast<size_t>(routeIndex), document.as<JsonVariantConst>());
}

void processToolsValue(const String &roomKey, JsonVariantConst tools)
{
    if (tools.isNull())
    {
        return;
    }
    if (!tools.is<JsonObjectConst>())
    {
        Serial.println("Tools snapshot ignored: expected object");
        return;
    }

    for (JsonPairConst pair : tools.as<JsonObjectConst>())
    {
        int routeIndex = findRoute(roomKey, pair.key().c_str());
        if (routeIndex >= 0)
        {
            acceptDesired(static_cast<size_t>(routeIndex), pair.value());
        }
    }
}

void processRoomValue(const String &roomKey, JsonVariantConst room)
{
    if (room.isNull())
    {
        return;
    }
    if (!room.is<JsonObjectConst>())
    {
        Serial.println("Room snapshot ignored: expected object");
        return;
    }

    JsonVariantConst tools = room["tools"];
    if (!tools.isNull())
    {
        processToolsValue(roomKey, tools);
    }
}

void processRoomsValue(JsonVariantConst rooms)
{
    if (rooms.isNull())
    {
        return;
    }
    if (!rooms.is<JsonObjectConst>())
    {
        Serial.println("Rooms snapshot ignored: expected object");
        return;
    }

    for (JsonPairConst pair : rooms.as<JsonObjectConst>())
    {
        processRoomValue(pair.key().c_str(), pair.value());
    }
}

bool parsePayload(const String &payload, JsonDocument &document, const char *label)
{
    DeserializationError error = deserializeJson(document, payload);
    if (error)
    {
        Serial.print(label);
        Serial.print(" parse error: ");
        Serial.println(error.c_str());
        return false;
    }
    return true;
}

void processCommandsSnapshot(const String &payload)
{
    JsonDocument document;
    if (!parsePayload(payload, document, "Commands snapshot"))
    {
        return;
    }

    JsonVariantConst root = document.as<JsonVariantConst>();
    if (!root.is<JsonObjectConst>())
    {
        Serial.println("Commands snapshot ignored: expected object");
        return;
    }
    processRoomsValue(root["rooms"]);
}

void processRoomsPayload(const String &payload)
{
    JsonDocument document;
    if (parsePayload(payload, document, "Rooms payload"))
    {
        processRoomsValue(document.as<JsonVariantConst>());
    }
}

void processRoomPayload(const String &roomKey, const String &payload)
{
    JsonDocument document;
    if (parsePayload(payload, document, "Room payload"))
    {
        processRoomValue(roomKey, document.as<JsonVariantConst>());
    }
}

void processToolsPayload(const String &roomKey, const String &payload)
{
    JsonDocument document;
    if (parsePayload(payload, document, "Tools payload"))
    {
        processToolsValue(roomKey, document.as<JsonVariantConst>());
    }
}

bool processFlattenedPatch(const String &basePath, const String &payload)
{
    JsonDocument document;
    if (!parsePayload(payload, document, "Patch payload") ||
        !document.is<JsonObjectConst>())
    {
        return false;
    }

    bool handled = false;
    for (JsonPairConst pair : document.as<JsonObjectConst>())
    {
        String relativePath = pair.key().c_str();
        if (relativePath.indexOf('/') < 0)
        {
            continue;
        }

        String fullPath;
        if (relativePath.startsWith("/commands"))
        {
            fullPath = relativePath;
        }
        else if (relativePath.startsWith("commands/"))
        {
            fullPath = "/" + relativePath;
        }
        else
        {
            fullPath = basePath;
            if (fullPath.endsWith("/"))
            {
                fullPath.remove(fullPath.length() - 1);
            }
            fullPath += "/" + relativePath;
        }

        const char *prefix = "/commands/rooms/";
        if (!fullPath.startsWith(prefix))
        {
            continue;
        }

        String remainder = fullPath.substring(strlen(prefix));
        int roomSlash = remainder.indexOf('/');
        if (roomSlash <= 0)
        {
            continue;
        }
        String roomKey = remainder.substring(0, roomSlash);
        String devicePath = remainder.substring(roomSlash + 1);
        const char *toolsPrefix = "tools/";
        if (!devicePath.startsWith(toolsPrefix))
        {
            continue;
        }
        String deviceKey = devicePath.substring(strlen(toolsPrefix));
        if (deviceKey.length() == 0 || deviceKey.indexOf('/') >= 0)
        {
            continue;
        }

        int routeIndex = findRoute(roomKey, deviceKey);
        if (routeIndex >= 0)
        {
            acceptDesired(static_cast<size_t>(routeIndex), pair.value());
            handled = true;
        }
    }
    return handled;
}

void reconcileMasterRoutes()
{
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        DeviceRoute &route = routes[i];
        if (route.owner != DeviceOwner::Master || !route.desiredKnown || !route.dirty)
        {
            continue;
        }

        if (!setMasterRelayState(route.roomKey, route.deviceKey, route.desiredState))
        {
            continue;
        }

        route.actualKnown = true;
        route.actualState = getMasterRelayState(route.roomKey, route.deviceKey);
        route.actualBrightness = 0;
        route.publishPending = true;
        route.nextPublishMs = millis();
        refreshDirty(route);
    }
}

void updateActual(size_t routeIndex, bool state, uint8_t brightness)
{
    DeviceRoute &route = routes[routeIndex];
    uint8_t normalizedBrightness = route.dimmable ? brightness : 0;
    bool changed = !route.actualKnown ||
                   route.actualState != state ||
                   route.actualBrightness != normalizedBrightness;
    route.actualKnown = true;
    route.actualState = state;
    route.actualBrightness = normalizedBrightness;
    route.publishPending = route.publishPending || changed;
    if (changed)
    {
        route.nextPublishMs = millis();
    }
    refreshDirty(route);
    if (route.dirty)
    {
        route.nextRetryMs = millis();
    }
}

bool publishActual(DeviceRoute &route)
{
    String path = String("/rooms/") + route.roomKey + "/tools/" + route.deviceKey;
    char payload[96];
    if (route.dimmable)
    {
        snprintf(payload, sizeof(payload), "{\"state\":%s,\"brightness\":%u}",
                 route.actualState ? "true" : "false", static_cast<unsigned>(route.actualBrightness));
    }
    else
    {
        snprintf(payload, sizeof(payload), "{\"state\":%s}", route.actualState ? "true" : "false");
    }

    if (firebaseDatabase().set<object_t>(firebaseDataClient(), path, object_t(payload)))
    {
        Serial.print("Actual state published: ");
        Serial.println(path);
        return true;
    }

    Serial.print("Actual state publish failed: ");
    Serial.print(path);
    Serial.print(" error=");
    Serial.println(firebaseDataClient().lastError().message());
    return false;
}

void flushPendingRoomStates()
{
    if (!firebaseReady())
    {
        return;
    }

    unsigned long now = millis();
    for (size_t offset = 0; offset < ROUTE_COUNT; offset++)
    {
        size_t routeIndex = (nextPublishRoute + offset) % ROUTE_COUNT;
        DeviceRoute &route = routes[routeIndex];
        if (!route.publishPending || !route.actualKnown ||
            !deadlineReached(now, route.nextPublishMs))
        {
            continue;
        }

        nextPublishRoute = (routeIndex + 1) % ROUTE_COUNT;
        if (publishActual(route))
        {
            route.publishPending = false;
        }
        else
        {
            route.nextPublishMs = millis() + PUBLISH_RETRY_MS;
        }
        return;
    }
}

void clearPendingCycle(unsigned long retryDelayMs)
{
    if (!pendingCmd.active)
    {
        return;
    }

    DeviceRoute &route = routes[pendingCmd.routeIndex];
    refreshDirty(route);
    if (route.dirty)
    {
        route.nextRetryMs = millis() + retryDelayMs;
    }
    pendingCmd.active = false;
    pendingCmd.waitingForAck = false;
}

void schedulePendingRetry(const char *reason)
{
    DeviceRoute &route = routes[pendingCmd.routeIndex];
    Serial.print(reason);
    Serial.print(": ");
    Serial.print(route.roomKey);
    Serial.print("/");
    Serial.println(route.deviceKey);

    pendingCmd.waitingForAck = false;
    if (pendingCmd.attempts >= MAX_SEND_ATTEMPTS)
    {
        clearPendingCycle(CYCLE_BACKOFF_MS);
        return;
    }
    pendingCmd.nextAttemptMs = millis() + SEND_RETRY_DELAY_MS;
}

void startPendingCycle(size_t routeIndex)
{
    DeviceRoute &route = routes[routeIndex];
    pendingCmd = {};
    pendingCmd.active = true;
    pendingCmd.routeIndex = routeIndex;
    pendingCmd.nextAttemptMs = millis();
    pendingCmd.payload.type = CMD_TYPE_COMMAND;
    strncpy(pendingCmd.payload.roomKey, route.roomKey, sizeof(pendingCmd.payload.roomKey) - 1);
    strncpy(pendingCmd.payload.deviceKey, route.deviceKey, sizeof(pendingCmd.payload.deviceKey) - 1);
    pendingCmd.payload.state = route.desiredState ? 1 : 0;
    pendingCmd.payload.brightness = route.dimmable ? route.desiredBrightness : (route.desiredState ? 100 : 0);
    String requestId = generateRequestId();
    strncpy(pendingCmd.payload.requestId, requestId.c_str(), sizeof(pendingCmd.payload.requestId) - 1);
    pendingCmd.payload.crc = computeXorCRC(reinterpret_cast<const uint8_t *>(&pendingCmd.payload), sizeof(pendingCmd.payload) - 1);
}

void startNextSlaveCycle()
{
    if (pendingCmd.active)
    {
        return;
    }

    unsigned long now = millis();
    for (size_t offset = 0; offset < ROUTE_COUNT; offset++)
    {
        size_t routeIndex = (nextSlaveRoute + offset) % ROUTE_COUNT;
        DeviceRoute &route = routes[routeIndex];
        if (route.owner == DeviceOwner::Slave && route.desiredKnown && route.dirty &&
            deadlineReached(now, route.nextRetryMs))
        {
            nextSlaveRoute = (routeIndex + 1) % ROUTE_COUNT;
            startPendingCycle(routeIndex);
            return;
        }
    }
}

void attemptPendingSend()
{
    if (pendingCmd.active)
    {
        DeviceRoute &route = routes[pendingCmd.routeIndex];
        bool payloadIsCurrent = pendingCmd.payload.state == (route.desiredState ? 1 : 0) &&
                                pendingCmd.payload.brightness ==
                                    (route.dimmable ? route.desiredBrightness : (route.desiredState ? 100 : 0));
        if (!payloadIsCurrent && !pendingCmd.waitingForAck)
        {
            pendingCmd.active = false;
            return;
        }
    }

    if (!pendingCmd.active || pendingCmd.waitingForAck ||
        !deadlineReached(millis(), pendingCmd.nextAttemptMs))
    {
        return;
    }

    pendingCmd.attempts++;
    if (!sendCommandToSlave(pendingCmd.payload))
    {
        schedulePendingRetry("ESP-NOW command queue failed");
        return;
    }

    pendingCmd.waitingForAck = true;
    pendingCmd.sentMs = millis();
}

void processSendResult()
{
    portENTER_CRITICAL(&espNowMux);
    sendCallbackReceived = false;
    portEXIT_CRITICAL(&espNowMux);

    if (pendingCmd.active && pendingCmd.waitingForAck &&
        millis() - pendingCmd.sentMs >= ACK_TIMEOUT_MS)
    {
        schedulePendingRetry("Slave ACK timeout");
    }
}

void processStatePackets()
{
    DeviceStatePayload packet;
    while (popReceivedStatePacket(packet))
    {
        uint8_t crc = computeXorCRC(reinterpret_cast<const uint8_t *>(&packet), sizeof(packet) - 1);
        if (packet.type != CMD_TYPE_STATE || crc != packet.crc)
        {
            Serial.println("Invalid slave packet ignored");
            continue;
        }

        packet.roomKey[sizeof(packet.roomKey) - 1] = '\0';
        packet.deviceKey[sizeof(packet.deviceKey) - 1] = '\0';
        packet.requestId[sizeof(packet.requestId) - 1] = '\0';
        int routeIndex = findSlaveRoute(packet.roomKey, packet.deviceKey);
        if (routeIndex < 0 || packet.state > 1 || packet.brightness > 100 || packet.success > 1)
        {
            Serial.println("Slave packet route/state invalid, ignored");
            continue;
        }

        bool matchedAck = pendingCmd.active &&
                          static_cast<size_t>(routeIndex) == pendingCmd.routeIndex &&
                          strcmp(packet.requestId, pendingCmd.payload.requestId) == 0;
        if (matchedAck)
        {
            if (packet.success)
            {
                updateActual(static_cast<size_t>(routeIndex), packet.state != 0, packet.brightness);
                Serial.print("Slave ACK OK: ");
            }
            else
            {
                DeviceRoute &route = routes[routeIndex];
                route.dirty = true;
                route.nextRetryMs = millis() + CYCLE_BACKOFF_MS;
                Serial.print("Slave ACK error code=");
                Serial.print(packet.errorCode);
                Serial.print(": ");
            }
            Serial.print(packet.roomKey);
            Serial.print("/");
            Serial.println(packet.deviceKey);
            if (packet.success)
            {
                clearPendingCycle(0);
            }
            else
            {
                pendingCmd.active = false;
                pendingCmd.waitingForAck = false;
            }
            continue;
        }

        if (packet.success && packet.requestId[0] == '\0')
        {
            updateActual(static_cast<size_t>(routeIndex), packet.state != 0, packet.brightness);
            if (pendingCmd.active &&
                static_cast<size_t>(routeIndex) == pendingCmd.routeIndex &&
                !routes[routeIndex].dirty)
            {
                clearPendingCycle(0);
            }
            Serial.print("Slave report: ");
            Serial.print(packet.roomKey);
            Serial.print("/");
            Serial.println(packet.deviceKey);
        }
        else
        {
            Serial.println("Unmatched slave ACK/error ignored");
        }
    }
}
}

void handleFirebaseResult(AsyncResult &aResult)
{
    if (!aResult.isResult())
    {
        return;
    }

    if (aResult.isError())
    {
        Firebase.printf("Error task: %s, msg: %s, code: %d\n", aResult.uid().c_str(), aResult.error().message().c_str(), aResult.error().code());
        if (firebaseIsCurrentCommandStreamUid(aResult.uid()))
        {
            firebaseMarkCommandStreamInactive();
        }
        return;
    }

    if (!aResult.available())
    {
        return;
    }

    RealtimeDatabaseResult &stream = aResult.to<RealtimeDatabaseResult>();
    if (stream.isStream() && firebaseIsCurrentCommandStreamUid(aResult.uid()))
    {
        handleCommandStream(stream);
    }
}

void handleCommandStream(RealtimeDatabaseResult &stream)
{
    String event = stream.event();
    if (event == "cancel" || event == "auth_revoked")
    {
        Serial.print("Firebase command stream stopped: ");
        Serial.println(event);
        firebaseMarkCommandStreamInactive();
        return;
    }

    firebaseMarkCommandStreamActive();
    if (event == "keep-alive")
    {
        return;
    }

    String payload = stream.to<String>();
    if (payload.length() == 0 || payload == "null")
    {
        return;
    }

    String path = stream.dataPath();
    String fullPath = path == "/" ? "/commands" : path;
    if (!fullPath.startsWith("/commands"))
    {
        fullPath = "/commands" + fullPath;
    }

    if (event == "patch" && processFlattenedPatch(fullPath, payload))
    {
        return;
    }

    if (fullPath == "/commands" || fullPath == "/commands/")
    {
        processCommandsSnapshot(payload);
        return;
    }
    if (fullPath == "/commands/rooms" || fullPath == "/commands/rooms/")
    {
        processRoomsPayload(payload);
        return;
    }

    const char *prefix = "/commands/rooms/";
    if (!fullPath.startsWith(prefix))
    {
        Serial.println("Ignoring command outside canonical path");
        return;
    }

    String remainder = fullPath.substring(strlen(prefix));
    int roomSlash = remainder.indexOf('/');
    if (roomSlash < 0)
    {
        processRoomPayload(remainder, payload);
        return;
    }

    String roomKey = remainder.substring(0, roomSlash);
    String devicePath = remainder.substring(roomSlash + 1);
    if (devicePath == "tools")
    {
        processToolsPayload(roomKey, payload);
        return;
    }

    const char *toolsPrefix = "tools/";
    if (!devicePath.startsWith(toolsPrefix))
    {
        Serial.println("Ignoring non-canonical command path");
        return;
    }

    String deviceKey = devicePath.substring(strlen(toolsPrefix));
    if (deviceKey.length() == 0 || deviceKey.indexOf('/') >= 0)
    {
        Serial.println("Ignoring nested command field event");
        return;
    }
    processDevicePayload(roomKey, deviceKey, payload);
}

void processSlaveCommunication()
{
    processStatePackets();
    processSendResult();
    reconcileMasterRoutes();
    startNextSlaveCycle();
    attemptPendingSend();
    flushPendingRoomStates();
}
