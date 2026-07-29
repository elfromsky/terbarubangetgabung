#include "wifi_firebase.h"
#include "firebase_app.h"
#include "firebase_command_router.h"
#include "firebase_telemetry.h"
#include "esp_now_protocol.h"
#include "time_config.h"
#include "wifi_config.h"
#include <WiFi.h>
#include <time.h>

namespace
{
bool wifiConnected = false;
bool previousWiFiConnected = false;
bool timeInitialized = false;
unsigned long nextWiFiReconnectMs = 0;
unsigned long wifiReconnectDelayMs = 5000;
unsigned long lastNtpRequestMs = 0;

constexpr unsigned long WIFI_RECONNECT_MAX_MS = 30000;
constexpr unsigned long NTP_RETRY_MS = 60000;

void requestNtpSync()
{
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER, "time.nist.gov");
    lastNtpRequestMs = millis();
}
}

void initWiFi()
{
    Serial.print("Connecting to WiFi");
    WiFi.mode(WIFI_STA);
    WiFi.persistent(false);
    WiFi.setAutoReconnect(true);
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
        previousWiFiConnected = true;
        Serial.println();
        Serial.print("Connected! IP: ");
        Serial.println(WiFi.localIP());
        initNTP();
    }
    else
    {
        wifiConnected = false;
        previousWiFiConnected = false;
        nextWiFiReconnectMs = millis() + wifiReconnectDelayMs;
        Serial.println();
        Serial.println("WiFi connection failed!");
    }
}

void initNTP()
{
    Serial.print("Syncing time with NTP");
    requestNtpSync();

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

void maintainConnections()
{
    unsigned long nowMs = millis();
    bool connected = WiFi.status() == WL_CONNECTED;
    wifiConnected = connected;

    if (!connected)
    {
        if (previousWiFiConnected)
        {
            Serial.println("WiFi disconnected; reconnect scheduled");
            previousWiFiConnected = false;
            wifiReconnectDelayMs = 5000;
            nextWiFiReconnectMs = nowMs;
        }

        if (static_cast<long>(nowMs - nextWiFiReconnectMs) >= 0)
        {
            Serial.println("Attempting WiFi reconnect");
            if (!WiFi.reconnect())
            {
                WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
            }
            nextWiFiReconnectMs = nowMs + wifiReconnectDelayMs;
            wifiReconnectDelayMs *= 2;
            if (wifiReconnectDelayMs > WIFI_RECONNECT_MAX_MS)
            {
                wifiReconnectDelayMs = WIFI_RECONNECT_MAX_MS;
            }
        }
        return;
    }

    if (!previousWiFiConnected)
    {
        previousWiFiConnected = true;
        wifiReconnectDelayMs = 5000;
        Serial.print("WiFi reconnected. IP: ");
        Serial.println(WiFi.localIP());

        if (!timeInitialized)
        {
            requestNtpSync();
        }
        if (initESPNow())
        {
            registerSlavePeer();
            registerBroadcastPeer();
            sendDiscoveryBeacon();
        }
        firebaseSubscribeToCommandStream();
    }

    if (!timeInitialized)
    {
        time_t now = time(nullptr);
        if (now > 1000000000)
        {
            timeInitialized = true;
            Serial.print("Time synchronized: ");
            Serial.println(getTimestamp());
        }
        else if (nowMs - lastNtpRequestMs >= NTP_RETRY_MS)
        {
            requestNtpSync();
        }
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
    return WiFi.status() == WL_CONNECTED;
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
