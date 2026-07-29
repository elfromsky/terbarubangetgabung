#include "firebase_app.h"
#include "firebase_command_router.h"
#include "firebase_config.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>

using AsyncClient = AsyncClientClass;

namespace
{
WiFiClientSecure authSslClient;
WiFiClientSecure commandStreamSslClient;
AsyncClient firebaseClient(authSslClient);
AsyncClient streamClient(commandStreamSslClient);
UserAuth userAuth(FIREBASE_API_KEY, FIREBASE_USER_EMAIL, FIREBASE_USER_PASSWORD, 3000);
FirebaseApp app;
RealtimeDatabase database;
bool firebaseInitialized = false;
bool commandStreamActive = false;
bool commandStreamSubscriptionPending = false;
bool commandStreamRequested = true;
bool commandStreamResetPending = false;
bool commandStreamHadWiFi = false;
unsigned long commandStreamSubscribeMs = 0;
unsigned long nextCommandStreamSubscribeMs = 0;
uint16_t commandStreamGeneration = 0;
String commandStreamUid;

constexpr unsigned long COMMAND_STREAM_SUBSCRIBE_TIMEOUT_MS = 15000;
constexpr unsigned long COMMAND_STREAM_RETRY_MS = 5000;

void configureSslClient(WiFiClientSecure &client)
{
    client.setInsecure();
    client.setHandshakeTimeout(5);
}
}

void firebaseAppInit()
{
    configureSslClient(authSslClient);
    configureSslClient(commandStreamSslClient);

    Serial.printf("Firebase Client v%s\n", FIREBASE_CLIENT_VERSION);
    Serial.println("Initializing Firebase app...");

    initializeApp(firebaseClient, app, getAuth(userAuth), handleFirebaseResult, "authTask");
    app.getApp<RealtimeDatabase>(database);
    database.url(FIREBASE_DATABASE_URL);
    firebaseInitialized = true;
    commandStreamRequested = true;
}

void firebaseAppLoop()
{
    firebaseMaintainCommandStream();
    app.loop();
}

bool firebaseReady()
{
    return WiFi.status() == WL_CONNECTED && app.ready();
}

RealtimeDatabase &firebaseDatabase()
{
    return database;
}

AsyncClientClass &firebaseDataClient()
{
    return firebaseClient;
}

AsyncClientClass &firebaseStreamClient()
{
    return streamClient;
}

void firebaseSubscribeToCommandStream()
{
    if (commandStreamActive || commandStreamSubscriptionPending)
    {
        commandStreamResetPending = true;
    }
    commandStreamActive = false;
    commandStreamSubscriptionPending = false;
    commandStreamRequested = true;
    nextCommandStreamSubscribeMs = 0;
}

void firebaseMaintainCommandStream()
{
    if (!firebaseInitialized)
    {
        return;
    }

    bool wifiAvailable = WiFi.status() == WL_CONNECTED;
    if (!wifiAvailable)
    {
        if (commandStreamHadWiFi || commandStreamActive || commandStreamSubscriptionPending)
        {
            commandStreamResetPending = true;
            commandStreamActive = false;
            commandStreamSubscriptionPending = false;
            commandStreamRequested = true;
            nextCommandStreamSubscribeMs = millis() + COMMAND_STREAM_RETRY_MS;
        }
        commandStreamHadWiFi = false;
        return;
    }

    if (!commandStreamHadWiFi)
    {
        commandStreamHadWiFi = true;
        commandStreamRequested = true;
        nextCommandStreamSubscribeMs = millis();
    }

    if (commandStreamResetPending)
    {
        if (commandStreamUid.length() > 0)
        {
            streamClient.stopAsync(commandStreamUid);
            commandStreamUid = "";
        }
        commandStreamActive = false;
        commandStreamSubscriptionPending = false;
        commandStreamRequested = true;
        commandStreamResetPending = false;
        return;
    }

    if (!app.ready() || commandStreamActive)
    {
        return;
    }

    unsigned long now = millis();
    if (commandStreamSubscriptionPending)
    {
        if (now - commandStreamSubscribeMs < COMMAND_STREAM_SUBSCRIBE_TIMEOUT_MS)
        {
            return;
        }

        if (commandStreamUid.length() > 0)
        {
            streamClient.stopAsync(commandStreamUid);
            commandStreamUid = "";
        }
        commandStreamSubscriptionPending = false;
        commandStreamRequested = true;
        nextCommandStreamSubscribeMs = now + COMMAND_STREAM_RETRY_MS;
        Serial.println("Firebase command stream subscribe timeout");
        return;
    }

    if (!commandStreamRequested || static_cast<long>(now - nextCommandStreamSubscribeMs) < 0)
    {
        return;
    }

    streamClient.setSSEFilters("get,put,patch,keep-alive,cancel,auth_revoked");
    commandStreamGeneration++;
    commandStreamUid = String("commandStream_") + commandStreamGeneration;
    database.get(streamClient, "/commands", handleFirebaseResult, true, commandStreamUid);
    commandStreamSubscriptionPending = true;
    commandStreamRequested = false;
    commandStreamSubscribeMs = now;
}

void firebaseMarkCommandStreamActive()
{
    commandStreamActive = true;
    commandStreamSubscriptionPending = false;
    commandStreamRequested = false;
}

void firebaseMarkCommandStreamInactive()
{
    commandStreamActive = false;
    commandStreamSubscriptionPending = false;
    commandStreamRequested = true;
    commandStreamResetPending = true;
    nextCommandStreamSubscribeMs = millis() + COMMAND_STREAM_RETRY_MS;
}

bool firebaseIsCurrentCommandStreamUid(const String &uid)
{
    return commandStreamUid.length() > 0 && uid == commandStreamUid;
}
