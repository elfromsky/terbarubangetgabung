#include <HardwareSerial.h>
#include "modbus.h"
#include "pzem.h"
#include "dimmer.h"
#include "relay.h"
#include "wifi_firebase.h"
#include "esp_now_protocol.h"

HardwareSerial SensorSerial(2);

#define RXD2 18
#define TXD2 17

const unsigned long FIREBASE_INTERVAL = 5000;
const unsigned long SENSOR_POLL_INTERVAL = 500;
unsigned long lastFirebaseUpload = 0;
unsigned long lastSensorPoll = 0;

float latestTemperature = -1;
float latestHumidity = -1;
PzemData latestPzemData = {-1, -1, -1, -1, -1, -1, false};

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
        Serial.print("{\"temperature\":");
        Serial.print(latestTemperature);
        Serial.print(",\"humidity\":");
        Serial.print(latestHumidity);
        Serial.println("}");
        sensorPollStep = SensorPollStep::Humidity;
        break;

    case SensorPollStep::Humidity:
        latestHumidity = readModBus(0x0002);
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
    }

    initializePZEM();
    initializeDimmers();

    Serial.println("System Ready!");
}

void loop()
{
    unsigned long currentMillis = millis();

    checkFirebaseCommands();
    pollSensorsNonBlocking();

    if (currentMillis - lastFirebaseUpload >= FIREBASE_INTERVAL)
    {
        lastFirebaseUpload = currentMillis;

        if (!FirebaseReady())
        {
            Serial.println("{\"firebase\":\"waiting_ready\"}");
        }
        else if (sendSensorData(latestTemperature, latestHumidity, latestPzemData))
        {
            Serial.println("{\"firebase\":\"upload_success\"}");
        }
        else
        {
            Serial.println("{\"firebase\":\"upload_failed\"}");
        }
    }

    delay(100);
}
