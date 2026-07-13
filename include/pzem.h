#ifndef PZEM_H
#define PZEM_H

// Define PZEM pins here
// Note: PZEM TX → ESP32 RX, PZEM RX ← ESP32 TX (crossover)
// PZEM is 5V TTL, use level shifter or voltage divider for RX!
const int PZEM_RX_PIN = 15;  // ESP32 RX (receives from PZEM TX)
const int PZEM_TX_PIN = 16;  // ESP32 TX (sends to PZEM RX)

struct PzemData {
  float voltage;
  float current;
  float power;
  float energy;
  float frequency;
  float pf;
  bool connected;
};

void initializePZEM();
PzemData readPZEM();

#endif
