#ifndef WIFI_FIREBASE_H
#define WIFI_FIREBASE_H

#include <Arduino.h>
#include "pzem.h"

void initWiFi();
void initNTP();
void maintainConnections();
String getTimestamp();
bool isWiFiConnected();

void FirebaseInit();
void FirebaseLoop();
bool FirebaseReady();
void checkFirebaseCommands();

bool sendSensorData(float temperature, float humidity, PzemData pzemData);
void processSlaveCommunication();

#endif
