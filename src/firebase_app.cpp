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

    firebaseSubscribeToCommandStream();
}

void firebaseAppLoop()
{
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
    streamClient.setSSEFilters("get,put,patch,keep-alive,cancel,auth_revoked");
    database.get(streamClient, "/commands", handleFirebaseResult, true, "commandStream");
}
