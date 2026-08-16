#include <HardwareSerial.h>
#include "modbus.h"
#include "pzem.h"
#include "relay.h"
#include "wifi_firebase.h"
#include "esp_now_protocol.h"
#include "firebase_command_router.h"
#include <cmath>
#include <limits>

HardwareSerial SensorSerial(2);

#define RXD2 41
#define TXD2 42

const unsigned long HEARTBEAT_INTERVAL = 5000;
const unsigned long SENSOR_UPLOAD_INTERVAL = 5000;
const unsigned long SENSOR_POLL_INTERVAL = 500;
unsigned long lastHeartbeatUpload = 0;
unsigned long lastSensorUpload = 0;
unsigned long lastSensorPoll = 0;
unsigned long lastDiscoveryBeacon = 0;

float latestTemperature = std::numeric_limits<float>::quiet_NaN();
float latestHumidity = std::numeric_limits<float>::quiet_NaN();
PzemData latestPzemData = {-1, -1, -1, -1, -1, -1, false};
int64_t latestTemperatureSampledAt = 0;
int64_t latestHumiditySampledAt = 0;
int64_t latestPzemSampledAt = 0;

enum class SensorPollStep
{
    Temperature,
    Humidity,
    Pzem
};

SensorPollStep sensorPollStep = SensorPollStep::Temperature;

void pollSensorsNonBlocking()
{
    unsigned long currentMillis = millis();
    if (currentMillis - lastSensorPoll < SENSOR_POLL_INTERVAL)
    {
        return;
    }
    lastSensorPoll = currentMillis;

    switch (sensorPollStep)
    {
    case SensorPollStep::Temperature:
        latestTemperature = readModBus(0x0001);
        if (std::isfinite(latestTemperature))
        {
            getValidEpochSeconds(latestTemperatureSampledAt);
        }
        Serial.print("{\"temperature\":");
        Serial.print(latestTemperature);
        Serial.print(",\"humidity\":");
        Serial.print(latestHumidity);
        Serial.println("}");
        sensorPollStep = SensorPollStep::Humidity;
        break;

    case SensorPollStep::Humidity:
        latestHumidity = readModBus(0x0002);
        if (std::isfinite(latestHumidity))
        {
            getValidEpochSeconds(latestHumiditySampledAt);
        }
        Serial.print("{\"temperature\":");
        Serial.print(latestTemperature);
        Serial.print(",\"humidity\":");
        Serial.print(latestHumidity);
        Serial.println("}");
        sensorPollStep = SensorPollStep::Pzem;
        break;

    case SensorPollStep::Pzem:
        latestPzemData = readPZEM();
        if (latestPzemData.connected)
        {
            getValidEpochSeconds(latestPzemSampledAt);
            Serial.print("{\"voltage\":");
            Serial.print(latestPzemData.voltage);
            Serial.print(",\"current\":");
            Serial.print(latestPzemData.current);
            Serial.print(",\"power\":");
            Serial.print(latestPzemData.power);
            Serial.print(",\"energy\":");
            Serial.print(latestPzemData.energy);
            Serial.print(",\"frequency\":");
            Serial.print(latestPzemData.frequency);
            Serial.print(",\"pf\":");
            Serial.print(latestPzemData.pf);
            Serial.println("}");
        }
        else
        {
            Serial.println("{\"pzem_status\":\"disconnected\"}");
        }
        sensorPollStep = SensorPollStep::Temperature;
        break;
    }
}

void setup()
{
    Serial.begin(115200);
    delay(1500);
    Serial.println("BOOT OK");

    initRelays();
    initializeMasterRouteStates();

    SensorSerial.begin(9600, SERIAL_8N1, RXD2, TXD2);
    pinMode(RS485_DIR, OUTPUT);
    digitalWrite(RS485_DIR, LOW);

    Serial.println("Before WiFi");
    initWiFi();
    Serial.println("After WiFi");

    FirebaseInit();

    if (initESPNow())
    {
        registerSlavePeer();
        registerBroadcastPeer();
    }

    initializePZEM();

    Serial.println("System Ready!");
}

void loop()
{
    unsigned long currentMillis = millis();

    maintainConnections();

    if (currentMillis - lastDiscoveryBeacon >= ESPNOW_DISCOVERY_INTERVAL_MS)
    {
        lastDiscoveryBeacon = currentMillis;
        sendDiscoveryBeacon();
    }

    checkFirebaseCommands();
    pollSensorsNonBlocking();

    if (currentMillis - lastHeartbeatUpload >= HEARTBEAT_INTERVAL)
    {
        lastHeartbeatUpload = currentMillis;

        if (!FirebaseReady())
        {
            Serial.println("{\"firebase_heartbeat\":\"waiting_ready\"}");
        }
        else
        {
            bool heartbeatSent = sendHeartbeat();
            Serial.println(heartbeatSent
                               ? "{\"firebase_heartbeat\":\"upload_success\"}"
                               : "{\"firebase_heartbeat\":\"upload_failed\"}");

        }
    }

    if (currentMillis - lastSensorUpload >= SENSOR_UPLOAD_INTERVAL)
    {
        lastSensorUpload = currentMillis;

        if (!FirebaseReady())
        {
            Serial.println("{\"firebase_telemetry\":\"waiting_ready\"}");
        }
        else
        {
            int64_t environmentSampledAt = 0;
            if (std::isfinite(latestTemperature) && std::isfinite(latestHumidity) &&
                latestTemperatureSampledAt > 0 && latestHumiditySampledAt > 0)
            {
                environmentSampledAt = latestTemperatureSampledAt < latestHumiditySampledAt
                                           ? latestTemperatureSampledAt
                                           : latestHumiditySampledAt;
            }
            bool sensorDataSent = sendSensorData(
                latestTemperature, latestHumidity, environmentSampledAt,
                latestPzemData, latestPzemData.connected ? latestPzemSampledAt : 0);
            Serial.println(sensorDataSent
                               ? "{\"firebase_telemetry\":\"upload_success\"}"
                               : "{\"firebase_telemetry\":\"upload_failed\"}");
        }
    }

    delay(100);
}
