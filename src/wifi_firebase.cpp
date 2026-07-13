#include "wifi_firebase.h"
#include "firebase_app.h"
#include "firebase_command_router.h"
#include "firebase_telemetry.h"
#include "time_config.h"
#include "wifi_config.h"
#include <WiFi.h>
#include <time.h>

namespace
{
bool wifiConnected = false;
bool timeInitialized = false;
}

void initWiFi()
{
    Serial.print("Connecting to WiFi");
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30)
    {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED)
    {
        wifiConnected = true;
        Serial.println();
        Serial.print("Connected! IP: ");
        Serial.println(WiFi.localIP());
        initNTP();
    }
    else
    {
        wifiConnected = false;
        Serial.println();
        Serial.println("WiFi connection failed!");
    }
}

void initNTP()
{
    Serial.print("Syncing time with NTP");
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER, "time.nist.gov");

    time_t now;
    int attempts = 0;
    while ((now = time(nullptr)) < 1000000000 && attempts < 30)
    {
        Serial.print(".");
        delay(500);
        attempts++;
    }

    timeInitialized = (now > 1000000000);

    if (timeInitialized)
    {
        Serial.println();
        Serial.print("Time synchronized: ");
        Serial.println(getTimestamp());
    }
    else
    {
        Serial.println();
        Serial.println("NTP sync failed!");
    }
}

String getTimestamp()
{
    if (!timeInitialized)
    {
        return "1970-01-01 00:00:00";
    }

    time_t now = time(nullptr);
    struct tm *timeinfo = localtime(&now);
    char buffer[25];
    strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
    return String(buffer);
}

bool isWiFiConnected()
{
    wifiConnected = (WiFi.status() == WL_CONNECTED);
    return wifiConnected;
}

void FirebaseInit()
{
    firebaseAppInit();
}

void FirebaseLoop()
{
    firebaseAppLoop();
}

bool FirebaseReady()
{
    return firebaseReady();
}

void checkFirebaseCommands()
{
    FirebaseLoop();
    processSlaveCommunication();
}
