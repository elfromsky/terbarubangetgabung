#ifndef WIFI_FIREBASE_H
#define WIFI_FIREBASE_H

#include <Arduino.h>
#include <cstdint>
#include "pzem.h"

void initWiFi();
void initNTP();
void maintainConnections();
String getTimestamp();
bool getValidEpochSeconds(int64_t &epochSeconds);
bool isWiFiConnected();

void FirebaseInit();
void FirebaseLoop();
bool FirebaseReady();
void checkFirebaseCommands();

bool sendHeartbeat();
bool sendSensorData(float temperature, float humidity,
                    int64_t environmentSampledAtEpochSeconds,
                    PzemData pzemData,
                    int64_t powerSampledAtEpochSeconds);
void processSlaveCommunication();

#endif
