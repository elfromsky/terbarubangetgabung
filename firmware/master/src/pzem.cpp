#include "pzem.h"
#include <PZEM004Tv30.h>
#include <HardwareSerial.h>
#include <cmath>
#include <limits>

HardwareSerial pzemSerial(1); // Use UART 1

PZEM004Tv30 pzem(pzemSerial, PZEM_RX_PIN, PZEM_TX_PIN);

namespace
{
constexpr float PZEM_MAX_VOLTAGE = 260.0f;
constexpr float PZEM_MAX_CURRENT = 100.0f;
constexpr float PZEM_MAX_POWER = 23000.0f;
// Energy is kWh: PZEM004Tv30::energy() divides the raw 1-Wh register by 1000.
// The device energy counter maxes out around 9999.99 kWh.
constexpr float PZEM_MAX_ENERGY = 9999.99f;
constexpr float PZEM_MAX_FREQUENCY = 65.0f;
constexpr float PZEM_MAX_POWER_FACTOR = 1.0f;

float validatedReading(float value, float minimum, float maximum)
{
    return std::isfinite(value) && value >= minimum && value <= maximum
               ? value
               : std::numeric_limits<float>::quiet_NaN();
}
} // namespace

void initializePZEM() {
    // The library constructor now handles calling begin() for ESP32
}

PzemData readPZEM() {
    const float unavailable = std::numeric_limits<float>::quiet_NaN();
    PzemData data = {unavailable, unavailable, unavailable, unavailable,
                     unavailable, unavailable, false};

    float voltage = pzem.voltage();
    if (!std::isfinite(voltage)) {
        return data;
    }

    data.voltage = validatedReading(voltage, 80.0f, PZEM_MAX_VOLTAGE);
    data.current = validatedReading(pzem.current(), 0.0f, PZEM_MAX_CURRENT);
    data.power = validatedReading(pzem.power(), 0.0f, PZEM_MAX_POWER);
    data.energy = validatedReading(pzem.energy(), 0.0f, PZEM_MAX_ENERGY);  // kWh, published unchanged
    data.frequency = validatedReading(pzem.frequency(), 45.0f, PZEM_MAX_FREQUENCY);
    data.pf = validatedReading(pzem.pf(), 0.0f, PZEM_MAX_POWER_FACTOR);
    data.connected = std::isfinite(data.voltage) &&
                     std::isfinite(data.current) &&
                     std::isfinite(data.power) &&
                     std::isfinite(data.energy);

    return data;
}
