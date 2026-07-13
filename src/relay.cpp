#include "relay.h"
#include <Arduino.h>

// Relay states in RAM
static bool relayStates[RELAY_COUNT] = {false};

// Pin array for easy access
static const int relayPins[RELAY_COUNT] = {
  RELAY_1_PIN,  // Relay 1  -> Lorong stop kontak
  RELAY_2_PIN,  // Relay 2  -> Lorong blower
  RELAY_3_PIN,  // Relay 3  -> Kamar 1 stop kontak
  RELAY_4_PIN,  // Relay 4  -> Kamar 1 lampu
  RELAY_5_PIN,  // Relay 5  -> Kamar 2 stop kontak
  RELAY_6_PIN,  // Relay 6  -> Kamar 2 lampu
  RELAY_7_PIN,  // Relay 7  -> Dapur lampu
  RELAY_8_PIN   // Relay 8  -> Dapur blower
};

void initRelays() {
  for (int i = 0; i < RELAY_COUNT; i++) {
    pinMode(relayPins[i], OUTPUT);

    // Relay diset LOW trigger:
    // LOW  = ON
    // HIGH = OFF
    digitalWrite(relayPins[i], HIGH);

    relayStates[i] = false;
  }

  Serial.println("Relay Module Initialized (Active-LOW Mode).");
}

void setRelayState(uint8_t relayId, bool state) {
  if (relayId < 1 || relayId > RELAY_COUNT) {
    Serial.printf("Relay ID tidak valid: %d\n", relayId);
    return;
  }

  int idx = relayId - 1;
  // Relay LOW trigger:
  // state true  -> LOW  -> ON
  // state false -> HIGH -> OFF
  digitalWrite(relayPins[idx], state ? LOW : HIGH);

  relayStates[idx] = state;

  Serial.printf(
    "Relay %d pin %d dieksekusi: %s\n",
    relayId,
    relayPins[idx],
    state ? "ON" : "OFF"
  );
}

bool getRelayState(uint8_t relayId) {
  if (relayId < 1 || relayId > RELAY_COUNT) {
    return false;
  }

  return relayStates[relayId - 1];
}
