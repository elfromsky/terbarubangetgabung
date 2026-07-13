#include "pzem.h"
#include <PZEM004Tv30.h>
#include <HardwareSerial.h>

HardwareSerial pzemSerial(1); // Use UART 1

PZEM004Tv30 pzem(pzemSerial, PZEM_RX_PIN, PZEM_TX_PIN);

void initializePZEM() {
    // The library constructor now handles calling begin() for ESP32
}

PzemData readPZEM() {
    PzemData data;
    data.voltage = pzem.voltage();
    if (isnan(data.voltage)) {
        data.connected = false;
        data.voltage = 0;
        data.current = 0;
        data.power = 0;
        data.energy = 0;
        data.frequency = 0;
        data.pf = 0;
    } else {
        data.connected = true;
        data.current = pzem.current();
        data.power = pzem.power();
        data.energy = pzem.energy();
        data.frequency = pzem.frequency();
        data.pf = pzem.pf();
    }
    return data;
}
