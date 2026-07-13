#ifndef RELAY_H
#define RELAY_H

#include <Arduino.h>
#include "esp_now_config.h"

// Pin assignments (8 relay)
#define RELAY_1_PIN  38  // Lorong Stop Kontak
#define RELAY_2_PIN  39  // Lorong Blower
#define RELAY_3_PIN  40  // Kamar 1 Stop Kontak
#define RELAY_4_PIN  41  // Kamar 1 Lampu
#define RELAY_5_PIN  16  // Kamar 2 Stop Kontak
#define RELAY_6_PIN  8   // Kamar 2 Lampu
#define RELAY_7_PIN  9   // Dapur Lampu
#define RELAY_8_PIN  11  // Dapur Blower

// Named relay IDs for routing
#define RELAY_LORONG_STOP_KONTAK    1
#define RELAY_LORONG_BLOWER         2
#define RELAY_KAMAR1_STOP_KONTAK    3
#define RELAY_KAMAR1_LAMPU          4
#define RELAY_KAMAR2_STOP_KONTAK    5
#define RELAY_KAMAR2_LAMPU          6
#define RELAY_DAPUR_LAMPU           7
#define RELAY_DAPUR_BLOWER          8

// Lamp relays controlled by dimmer
#define DIMMER_CH1_LAMP_RELAYS {4, 6}
#define DIMMER_CH2_LAMP_RELAYS {7}

// Max relay ID
#define RELAY_COUNT 8

// Initialize all relay pins, set all LOW
void initRelays();

// Set single relay state (0=OFF, 1=ON)
void setRelayState(uint8_t relayId, bool state);

// Get single relay state
bool getRelayState(uint8_t relayId);

#endif
