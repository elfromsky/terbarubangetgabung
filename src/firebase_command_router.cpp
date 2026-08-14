#include "firebase_command_router.h"
#include "firebase_app.h"
#include "esp_now_protocol.h"
#include "relay.h"
#include "wifi_firebase.h"
#include <ArduinoJson.h>
#include <cstring>
#include <sys/time.h>

namespace
{
struct ParsedCommand
{
    bool valid;
    bool state;
    uint8_t brightness;
    char requestId[32];
    int64_t issuedAtMs;
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
    char desiredRequestId[32];
    int64_t desiredIssuedAtMs;
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
constexpr unsigned long SLAVE_ONLINE_WINDOW_MS = 15000;
constexpr unsigned long SLAVE_STATUS_PUBLISH_INTERVAL_MS = 5000;
constexpr unsigned long SLAVE_STATUS_RETRY_MS = 1000;
constexpr unsigned long SLAVE_STATUS_PUBLISH_TIMEOUT_MS = 5000;
constexpr int64_t COMMAND_FUTURE_TOLERANCE_MS = 5000;
constexpr int64_t COMMAND_MAX_AGE_MS = 15000;

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
uint8_t sharedBedroomDesiredBrightness = 0;
int64_t sharedBedroomIssuedAtMs = 0;
char sharedBedroomRequestId[32] = {};
int sharedBedroomOwnerRoute = -1;
bool slavePacketSeen = false;
unsigned long lastSlavePacketMs = 0;
bool slaveLastSeenEpochKnown = false;
int64_t lastSlaveSeenEpochSeconds = 0;
bool slaveOnline = false;
bool slaveStatusPublishPending = false;
bool slaveStatusPublishUrgent = true;
bool slaveStatusPublished = false;
bool publishedSlaveOnline = false;
unsigned long slaveStatusPublishStartedMs = 0;
unsigned long nextSlaveStatusPublishMs = 0;
uint32_t slaveStatusPublishGeneration = 0;
String slaveStatusPublishUid;

bool deadlineReached(unsigned long now, unsigned long deadline)
{
    return static_cast<long>(now - deadline) >= 0;
}

void handleSlaveStatusPublishResult(AsyncResult &result)
{
    if (!result.isResult() || !slaveStatusPublishPending ||
        result.uid() != slaveStatusPublishUid)
    {
        return;
    }

    if (result.isError())
    {
        slaveStatusPublishPending = false;
        slaveStatusPublishUrgent = true;
        nextSlaveStatusPublishMs = millis() + SLAVE_STATUS_RETRY_MS;
        Serial.print("Slave status publish failed: ");
        Serial.println(result.error().message());
        return;
    }

    if (!result.available())
    {
        return;
    }

    slaveStatusPublishPending = false;
    slaveStatusPublished = true;
    if (slaveOnline != publishedSlaveOnline)
    {
        slaveStatusPublishUrgent = true;
        nextSlaveStatusPublishMs = millis();
    }
    else
    {
        nextSlaveStatusPublishMs = slaveStatusPublishStartedMs +
                                   SLAVE_STATUS_PUBLISH_INTERVAL_MS;
    }
}

void noteValidSlavePacket(unsigned long receivedMs)
{
    unsigned long nowMs = millis();
    lastSlavePacketMs = receivedMs;
    slavePacketSeen = true;

    int64_t epochSeconds;
    if (getValidEpochSeconds(epochSeconds))
    {
        slaveLastSeenEpochKnown = true;
        lastSlaveSeenEpochSeconds = epochSeconds - (nowMs - receivedMs) / 1000;
    }
}

void refreshSlaveAvailability(unsigned long now)
{
    bool nextOnline = slavePacketSeen &&
                      now - lastSlavePacketMs < SLAVE_ONLINE_WINDOW_MS;
    if (nextOnline == slaveOnline)
    {
        return;
    }

    if (slaveStatusPublishPending)
    {
        firebaseSlaveStatusClient().stopAsync(slaveStatusPublishUid);
        slaveStatusPublishPending = false;
    }
    slaveOnline = nextOnline;
    slaveStatusPublishUrgent = true;
    nextSlaveStatusPublishMs = now;
}

void publishSlaveAvailability(unsigned long now)
{
    refreshSlaveAvailability(now);

    if (slaveStatusPublishPending)
    {
        if (now - slaveStatusPublishStartedMs < SLAVE_STATUS_PUBLISH_TIMEOUT_MS)
        {
            return;
        }

        firebaseSlaveStatusClient().stopAsync(slaveStatusPublishUid);
        slaveStatusPublishPending = false;
        slaveStatusPublishUrgent = true;
        nextSlaveStatusPublishMs = now + SLAVE_STATUS_RETRY_MS;
        Serial.println("Slave status publish timeout");
        return;
    }

    if (!firebaseReady() || !deadlineReached(now, nextSlaveStatusPublishMs) ||
        (!slaveStatusPublishUrgent && slaveStatusPublished &&
         now - slaveStatusPublishStartedMs < SLAVE_STATUS_PUBLISH_INTERVAL_MS))
    {
        return;
    }

    JsonDocument document;
    document["online"] = slaveOnline;
    if (slaveLastSeenEpochKnown)
    {
        document["last_seen"] = lastSlaveSeenEpochSeconds;
    }
    else
    {
        document["last_seen"] = nullptr;
    }

    String payload;
    serializeJson(document, payload);
    slaveStatusPublishStartedMs = now;
    publishedSlaveOnline = slaveOnline;
    slaveStatusPublishPending = true;
    slaveStatusPublishUrgent = false;
    slaveStatusPublishGeneration++;
    slaveStatusPublishUid = String("slaveStatus_") + slaveStatusPublishGeneration;
    firebaseDatabase().set<object_t>(
        firebaseSlaveStatusClient(), "/gateway/status/slave",
        object_t(payload.c_str()), handleSlaveStatusPublishResult,
        slaveStatusPublishUid);
}

bool usesSharedBedroomDimmer(const DeviceRoute &route)
{
    return route.owner == DeviceOwner::Slave && route.dimmable &&
           strcmp(route.deviceKey, "lampu") == 0 &&
           (strcmp(route.roomKey, "kamar_1") == 0 || strcmp(route.roomKey, "kamar_2") == 0);
}

bool commandVersionIsNewer(int64_t issuedAtMs, const char *requestId,
                           const DeviceRoute &route)
{
    return !route.desiredKnown || issuedAtMs > route.desiredIssuedAtMs ||
           (issuedAtMs == route.desiredIssuedAtMs &&
            strcmp(requestId, route.desiredRequestId) > 0);
}

bool sharedBedroomVersionIsNewer(int64_t issuedAtMs, const char *requestId)
{
    return sharedBedroomOwnerRoute < 0 ||
           issuedAtMs > sharedBedroomIssuedAtMs ||
           (issuedAtMs == sharedBedroomIssuedAtMs &&
            strcmp(requestId, sharedBedroomRequestId) > 0);
}

uint8_t desiredBrightnessForRoute(size_t routeIndex)
{
    const DeviceRoute &route = routes[routeIndex];
    if (!usesSharedBedroomDimmer(route))
    {
        return route.desiredBrightness;
    }
    if (sharedBedroomOwnerRoute >= 0)
    {
        return sharedBedroomDesiredBrightness;
    }
    return route.actualKnown ? route.actualBrightness : route.desiredBrightness;
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

bool getCurrentEpochMilliseconds(int64_t &epochMs)
{
    int64_t epochSeconds;
    struct timeval nowValue;
    if (!getValidEpochSeconds(epochSeconds) || gettimeofday(&nowValue, nullptr) != 0)
    {
        return false;
    }

    epochMs = static_cast<int64_t>(nowValue.tv_sec) * 1000 + nowValue.tv_usec / 1000;
    return true;
}

void disableDesiredCommand(DeviceRoute &route, const char *reason)
{
    size_t routeIndex = static_cast<size_t>(&route - routes);
    if (sharedBedroomOwnerRoute == static_cast<int>(routeIndex))
    {
        sharedBedroomOwnerRoute = -1;
        sharedBedroomDesiredBrightness = route.actualKnown ? route.actualBrightness : 0;
        sharedBedroomIssuedAtMs = 0;
        sharedBedroomRequestId[0] = '\0';
    }
    route.desiredKnown = false;
    route.desiredState = false;
    route.desiredBrightness = 0;
    route.dirty = false;
    route.desiredRequestId[0] = '\0';
    route.desiredIssuedAtMs = 0;

    Serial.print("Desired command disabled for ");
    Serial.print(route.roomKey);
    Serial.print("/");
    Serial.print(route.deviceKey);
    Serial.print(": ");
    Serial.println(reason);
}

bool ensureDesiredCommandFresh(DeviceRoute &route)
{
    if (!route.desiredKnown)
    {
        route.dirty = false;
        return false;
    }

    int64_t nowMs;
    if (!getCurrentEpochMilliseconds(nowMs))
    {
        disableDesiredCommand(route, "NTP time unavailable");
        return false;
    }
    if (route.desiredIssuedAtMs <= nowMs - COMMAND_MAX_AGE_MS)
    {
        disableDesiredCommand(route, "command expired");
        return false;
    }
    return true;
}

void expireDesiredCommands()
{
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        if (routes[i].desiredKnown)
        {
            ensureDesiredCommandFresh(routes[i]);
        }
    }
}

bool actualMatchesDesired(const DeviceRoute &route)
{
    if (!route.desiredKnown || !route.actualKnown || route.desiredState != route.actualState)
    {
        return false;
    }
    if (!route.dimmable)
    {
        return true;
    }
    if (usesSharedBedroomDimmer(route))
    {
        size_t routeIndex = static_cast<size_t>(&route - routes);
        return sharedBedroomOwnerRoute != static_cast<int>(routeIndex) ||
               sharedBedroomDesiredBrightness == route.actualBrightness;
    }
    return (!route.desiredState && route.desiredBrightness == 0) ||
           route.desiredBrightness == route.actualBrightness;
}

void refreshDirty(DeviceRoute &route)
{
    route.dirty = ensureDesiredCommandFresh(route) && !actualMatchesDesired(route);
}

bool commandIsFresh(int64_t issuedAtMs)
{
    int64_t nowMs;
    if (!getCurrentEpochMilliseconds(nowMs))
    {
        Serial.println("Invalid command: NTP time unavailable");
        return false;
    }

    if (issuedAtMs > nowMs + COMMAND_FUTURE_TOLERANCE_MS)
    {
        Serial.println("Invalid command: issued_at is too far in the future");
        return false;
    }
    if (issuedAtMs <= nowMs - COMMAND_MAX_AGE_MS)
    {
        Serial.println("Invalid command: command is stale");
        return false;
    }
    return true;
}

ParsedCommand parseCommand(const DeviceRoute &route, JsonVariantConst value)
{
    ParsedCommand command = {};
    if (!value.is<JsonObjectConst>())
    {
        Serial.println("Invalid command: expected object payload");
        return command;
    }

    JsonObjectConst object = value.as<JsonObjectConst>();
    size_t expectedFieldCount = route.dimmable ? 4 : 3;
    if (object.size() != expectedFieldCount)
    {
        Serial.println(route.dimmable
                           ? "Invalid dimmer command: expected state, brightness, request_id, issued_at"
                           : "Invalid relay command: expected state, request_id, issued_at");
        return command;
    }

    JsonVariantConst state = object["state"];
    if (!state.is<bool>())
    {
        Serial.println("Invalid command: state must be bool");
        return command;
    }

    JsonVariantConst requestId = object["request_id"];
    const char *requestIdValue = requestId.is<const char *>() ? requestId.as<const char *>() : nullptr;
    size_t requestIdLength = requestIdValue == nullptr ? 0 : strlen(requestIdValue);
    if (requestIdLength == 0 || requestIdLength >= sizeof(command.requestId))
    {
        Serial.println("Invalid command: request_id must contain 1..31 characters");
        return command;
    }

    JsonVariantConst issuedAt = object["issued_at"];
    if (!issuedAt.is<int64_t>())
    {
        Serial.println("Invalid command: issued_at must be an epoch millisecond integer");
        return command;
    }
    int64_t issuedAtMs = issuedAt.as<int64_t>();
    if (!commandIsFresh(issuedAtMs))
    {
        return command;
    }
    command.issuedAtMs = issuedAtMs;

    command.state = state.as<bool>();
    strncpy(command.requestId, requestIdValue, sizeof(command.requestId) - 1);

    if (!route.dimmable)
    {
        command.valid = true;
        return command;
    }

    JsonVariantConst brightness = object["brightness"];
    if (!brightness.is<int>())
    {
        Serial.println("Invalid dimmer command: brightness must be integer");
        return command;
    }

    int brightnessValue = brightness.as<int>();
    if (brightnessValue < 0 || brightnessValue > 100)
    {
        Serial.println("Invalid dimmer command: brightness must be 0..100");
        return command;
    }

    command.valid = true;
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

    if (!commandVersionIsNewer(command.issuedAtMs, command.requestId, route))
    {
        Serial.println("Command ignored: older or duplicate version");
        return;
    }

    route.desiredKnown = true;
    route.desiredState = command.state;
    route.desiredBrightness = command.brightness;
    strncpy(route.desiredRequestId, command.requestId, sizeof(route.desiredRequestId) - 1);
    route.desiredRequestId[sizeof(route.desiredRequestId) - 1] = '\0';
    route.desiredIssuedAtMs = command.issuedAtMs;

    // Relay state remains per route. Only the newest command version owns CH1 brightness.
    bool sharedBrightnessChanged = usesSharedBedroomDimmer(route) &&
                                   command.brightness > 0 &&
                                   sharedBedroomVersionIsNewer(command.issuedAtMs,
                                                               command.requestId);
    if (sharedBrightnessChanged)
    {
        sharedBedroomDesiredBrightness = command.brightness;
        sharedBedroomIssuedAtMs = command.issuedAtMs;
        strncpy(sharedBedroomRequestId, command.requestId,
                sizeof(sharedBedroomRequestId) - 1);
        sharedBedroomRequestId[sizeof(sharedBedroomRequestId) - 1] = '\0';
        sharedBedroomOwnerRoute = static_cast<int>(routeIndex);
    }
    refreshDirty(route);
    route.nextRetryMs = millis();

    if (pendingCmd.active &&
        (pendingCmd.routeIndex == routeIndex ||
         (sharedBrightnessChanged &&
          usesSharedBedroomDimmer(routes[pendingCmd.routeIndex]))))
    {
        DeviceRoute &pendingRoute = routes[pendingCmd.routeIndex];
        bool payloadIsCurrent = pendingCmd.payload.state == (pendingRoute.desiredState ? 1 : 0) &&
                                  pendingCmd.payload.brightness ==
                                      (pendingRoute.dimmable
                                           ? desiredBrightnessForRoute(pendingCmd.routeIndex)
                                           :
                                                               (pendingRoute.desiredState ? 100 : 0)) &&
                                  strcmp(pendingCmd.payload.requestId, pendingRoute.desiredRequestId) == 0;
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
        Serial.print(desiredBrightnessForRoute(routeIndex));
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
        if (route.owner != DeviceOwner::Master ||
            !ensureDesiredCommandFresh(route) || !route.dirty)
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

    if (!usesSharedBedroomDimmer(route))
    {
        return;
    }

    // Every CH1 report updates shared brightness; semantic relay states stay independent.
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        if (i == routeIndex || !usesSharedBedroomDimmer(routes[i]))
        {
            continue;
        }

        DeviceRoute &candidate = routes[i];
        bool brightnessChanged = candidate.actualBrightness != normalizedBrightness;
        candidate.actualBrightness = normalizedBrightness;
        if (!candidate.actualKnown)
        {
            continue;
        }
        candidate.publishPending = candidate.publishPending || brightnessChanged;
        if (brightnessChanged)
        {
            candidate.nextPublishMs = millis();
        }
        refreshDirty(candidate);
        if (candidate.dirty)
        {
            candidate.nextRetryMs = millis();
        }
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
    if (!ensureDesiredCommandFresh(route))
    {
        pendingCmd.active = false;
        return;
    }
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
    pendingCmd.payload.brightness = route.dimmable
                                        ? desiredBrightnessForRoute(routeIndex)
                                        : (route.desiredState ? 100 : 0);
    strncpy(pendingCmd.payload.requestId, route.desiredRequestId, sizeof(pendingCmd.payload.requestId) - 1);
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
        if (route.owner != DeviceOwner::Slave || !ensureDesiredCommandFresh(route))
        {
            continue;
        }
        if (route.dirty && deadlineReached(now, route.nextRetryMs))
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
        if (!pendingCmd.waitingForAck && !ensureDesiredCommandFresh(route))
        {
            pendingCmd.active = false;
            return;
        }
        bool payloadIsCurrent = pendingCmd.payload.state == (route.desiredState ? 1 : 0) &&
                                  pendingCmd.payload.brightness ==
                                      (route.dimmable
                                           ? desiredBrightnessForRoute(pendingCmd.routeIndex)
                                           : (route.desiredState ? 100 : 0)) &&
                                 strcmp(pendingCmd.payload.requestId, route.desiredRequestId) == 0;
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
    unsigned long receivedMs;
    while (popReceivedStatePacket(packet, receivedMs))
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

        noteValidSlavePacket(receivedMs);

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
                if (ensureDesiredCommandFresh(route))
                {
                    route.dirty = true;
                    route.nextRetryMs = millis() + CYCLE_BACKOFF_MS;
                }
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

void initializeMasterRouteStates()
{
    for (size_t i = 0; i < ROUTE_COUNT; i++)
    {
        DeviceRoute &route = routes[i];
        if (route.owner != DeviceOwner::Master)
        {
            continue;
        }
        route.actualKnown = true;
        route.actualState = getMasterRelayState(route.roomKey, route.deviceKey);
        route.actualBrightness = 0;
        route.publishPending = true;
        route.nextPublishMs = millis();
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
    expireDesiredCommands();
    processStatePackets();
    processSendResult();
    reconcileMasterRoutes();
    startNextSlaveCycle();
    attemptPendingSend();
    flushPendingRoomStates();
    publishSlaveAvailability(millis());
}
