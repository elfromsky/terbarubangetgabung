#include "firebase_telemetry.h"
#include "firebase_app.h"
#include "wifi_firebase.h"
#include <WiFi.h>
#include <cmath>
#include <time.h>

bool sendSensorData(float temperature, float humidity, PzemData pzemData)
{
    if (!firebaseReady())
    {
        Serial.println("Firebase not ready");
        return false;
    }

    bool environmentConnected = temperature != -1 && humidity != -1;
    float reportedTemperature = environmentConnected ? temperature : 0;
    float reportedHumidity = environmentConnected ? humidity : 0;
    String envJson = String("{\"temperature\":") + String(round(reportedTemperature * 10) / 10.0, 1) +
                     ",\"humidity\":" + String(round(reportedHumidity * 10) / 10.0, 1) +
                     ",\"connected\":" + (environmentConnected ? "true" : "false") + "}";

    if (!firebaseDatabase().set<object_t>(firebaseDataClient(), "/device/sensorData/environment", object_t(envJson.c_str())))
    {
        Serial.print("Env upload error: ");
        Serial.println(firebaseDataClient().lastError().message());
        return false;
    }

    String powerJson = String("{\"voltage\":") + String(round(pzemData.voltage * 10) / 10.0, 1) +
                       ",\"current\":" + String(round(pzemData.current * 100) / 100.0, 2) +
                       ",\"power\":" + String(round(pzemData.power * 10) / 10.0, 1) +
                       ",\"energy\":" + String(round(pzemData.energy * 1000) / 1000.0, 3) +
                       ",\"frequency\":" + String(round(pzemData.frequency * 10) / 10.0, 1) +
                       ",\"pf\":" + String(round(pzemData.pf * 100) / 100.0, 2) +
                       ",\"connected\":" + (pzemData.connected ? "true" : "false") + "}";

    if (!firebaseDatabase().set<object_t>(firebaseDataClient(), "/device/sensorData/power", object_t(powerJson.c_str())))
    {
        Serial.print("Power upload error: ");
        Serial.println(firebaseDataClient().lastError().message());
        return false;
    }

    String timestamp = getTimestamp();
    if (!firebaseDatabase().set<String>(firebaseDataClient(), "/device/sensorData/timestamp", timestamp))
    {
        Serial.print("Timestamp upload error: ");
        Serial.println(firebaseDataClient().lastError().message());
        return false;
    }

    unsigned long now = time(nullptr);
    if (now > 1000000000)
    {
        if (!firebaseDatabase().set<int>(firebaseDataClient(), "/device/sensorData/unix_time", (int)now))
        {
            Serial.print("Unix time upload error: ");
            Serial.println(firebaseDataClient().lastError().message());
            return false;
        }
    }

    String ip = WiFi.localIP().toString();
    String systemJson = String("{\"wifi_connected\":") + (isWiFiConnected() ? "true" : "false") +
                        ",\"free_heap\":" + String(ESP.getFreeHeap()) +
                        ",\"rssi\":" + String(WiFi.RSSI()) +
                        ",\"ip\":\"" + ip + "\"}";

    if (!firebaseDatabase().set<object_t>(firebaseDataClient(), "/device/sensorData/system", object_t(systemJson.c_str())))
    {
        Serial.print("System upload error: ");
        Serial.println(firebaseDataClient().lastError().message());
        return false;
    }

    return true;
}
