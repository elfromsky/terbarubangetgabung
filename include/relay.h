#ifndef RELAY_H
#define RELAY_H

#include <Arduino.h>

#define RELAY_LAMPU_PIN 21
#define RELAY_SANYO_PIN 5

void initRelays();
void controlLampu(bool on);
void controlSanyo(bool on);
void allRelaysOff();
bool isMasterRelayDevice(const String &roomKey, const String &deviceKey);
bool setMasterRelayState(const String &roomKey, const String &deviceKey, bool on);
bool getMasterRelayState(const String &roomKey, const String &deviceKey);

#endif
