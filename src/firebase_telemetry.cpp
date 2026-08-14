#include "firebase_telemetry.h"
#include "firebase_app.h"
#include "wifi_firebase.h"
#include <ArduinoJson.h>
#include <WiFi.h>
#include <cmath>

namespace
{
void setRoundedOrNull(JsonDocument &document, const char *key, float value,
                      bool available, uint8_t decimals)
{
    if (!available || !std::isfinite(value))
    {
        document[key] = nullptr;
        return;
    }

    float multiplier = powf(10.0f, decimals);
    document[key] = roundf(value * multiplier) / multiplier;
}

bool uploadObject(const char *path, const char *label, JsonDocument &document)
{
    String payload;
    serializeJson(document, payload);
    if (firebaseDatabase().set<object_t>(firebaseDataClient(), path, object_t(payload.c_str())))
    {
        return true;
    }

    Serial.print(label);
    Serial.print(" upload error: ");
    Serial.println(firebaseDataClient().lastError().message());
    return false;
}
}

bool sendHeartbeat()
{
    if (!firebaseReady())
    {
        return false;
    }

    int64_t epochSeconds;
    if (!getValidEpochSeconds(epochSeconds))
    {
        Serial.println("Heartbeat skipped: time not synchronized");
        return false;
    }

    if (firebaseDatabase().set<int64_t>(firebaseDataClient(), "/device/sensorData/unix_time", epochSeconds))
    {
        return true;
    }

    Serial.print("Heartbeat upload error: ");
    Serial.println(firebaseDataClient().lastError().message());
    return false;
}

bool sendSensorData(float temperature, float humidity,
                    int64_t environmentSampledAtEpochSeconds,
                    PzemData pzemData,
                    int64_t powerSampledAtEpochSeconds)
{
    if (!firebaseReady())
    {
        Serial.println("Firebase not ready");
        return false;
    }

    bool uploadSucceeded = true;
    bool temperatureAvailable = std::isfinite(temperature);
    bool humidityAvailable = std::isfinite(humidity);
    bool environmentConnected = temperatureAvailable && humidityAvailable &&
                                environmentSampledAtEpochSeconds > 0;
    JsonDocument environment;
    setRoundedOrNull(environment, "temperature", temperature, temperatureAvailable, 1);
    setRoundedOrNull(environment, "humidity", humidity, humidityAvailable, 1);
    environment["connected"] = environmentConnected;
    if (environmentConnected)
    {
        environment["sampled_at"] = environmentSampledAtEpochSeconds;
    }
    else
    {
        environment["sampled_at"] = nullptr;
    }
    uploadSucceeded = uploadObject("/device/sensorData/environment", "Environment", environment) && uploadSucceeded;

    bool voltageAvailable = std::isfinite(pzemData.voltage);
    bool currentAvailable = std::isfinite(pzemData.current);
    bool powerAvailable = std::isfinite(pzemData.power);
    bool energyAvailable = std::isfinite(pzemData.energy);
    bool frequencyAvailable = std::isfinite(pzemData.frequency);
    bool pfAvailable = std::isfinite(pzemData.pf);
    bool powerConnected = pzemData.connected && powerSampledAtEpochSeconds > 0;
    JsonDocument power;
    setRoundedOrNull(power, "voltage", pzemData.voltage, voltageAvailable, 1);
    setRoundedOrNull(power, "current", pzemData.current, currentAvailable, 2);
    setRoundedOrNull(power, "power", pzemData.power, powerAvailable, 1);
    setRoundedOrNull(power, "energy", pzemData.energy, energyAvailable, 3);
    setRoundedOrNull(power, "frequency", pzemData.frequency, frequencyAvailable, 1);
    setRoundedOrNull(power, "pf", pzemData.pf, pfAvailable, 2);
    power["connected"] = powerConnected;
    if (powerConnected)
    {
        power["sampled_at"] = powerSampledAtEpochSeconds;
    }
    else
    {
        power["sampled_at"] = nullptr;
    }
    uploadSucceeded = uploadObject("/device/sensorData/power", "Power", power) && uploadSucceeded;

    int64_t currentEpochSeconds;
    if (getValidEpochSeconds(currentEpochSeconds))
    {
        String timestamp = getTimestamp();
        if (timestamp.length() > 0 &&
            !firebaseDatabase().set<String>(firebaseDataClient(), "/device/sensorData/timestamp", timestamp))
        {
            Serial.print("Timestamp upload error: ");
            Serial.println(firebaseDataClient().lastError().message());
            uploadSucceeded = false;
        }
    }

    String ip = WiFi.localIP().toString();
    JsonDocument system;
    system["wifi_connected"] = isWiFiConnected();
    system["free_heap"] = ESP.getFreeHeap();
    system["rssi"] = WiFi.RSSI();
    system["ip"] = ip;
    uploadSucceeded = uploadObject("/device/sensorData/system", "System", system) && uploadSucceeded;

    return uploadSucceeded;
}
