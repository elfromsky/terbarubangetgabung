#include "relay.h"

namespace
{
    bool lampuState = false;
    bool sanyoState = false;

    void setRelayPin(uint8_t pin, bool &state, bool on, const char *label)
    {
        state = on;
        // Active-low relay input with NC-COM load wiring.
        digitalWrite(pin, on ? HIGH : LOW);
        Serial.print(label);
        Serial.print(": ");
        Serial.println(on ? "ON" : "OFF");
    }
}

void initRelays()
{
    pinMode(RELAY_LAMPU_PIN, OUTPUT);
    pinMode(RELAY_SANYO_PIN, OUTPUT);

    digitalWrite(RELAY_LAMPU_PIN, LOW);
    digitalWrite(RELAY_SANYO_PIN, LOW);
    lampuState = false;
    sanyoState = false;

    Serial.println("Relays initialized (active-low input, NC-COM load): OFF=LOW, ON=HIGH; Lampu=13, Sanyo=14");
}

void controlLampu(bool on)
{
    setRelayPin(RELAY_LAMPU_PIN, lampuState, on, "Lampu");
}

void controlSanyo(bool on)
{
    setRelayPin(RELAY_SANYO_PIN, sanyoState, on, "Sanyo");
}

void allRelaysOff()
{
    controlLampu(false);
    controlSanyo(false);
    Serial.println("All relays turned OFF (trip/safety)");
}

bool isMasterRelayDevice(const String &roomKey, const String &deviceKey)
{
    return roomKey == "teras" &&
           (deviceKey == "lampu" || deviceKey == "sanyo");
}

bool setMasterRelayState(const String &roomKey, const String &deviceKey, bool on)
{
    if (!isMasterRelayDevice(roomKey, deviceKey))
    {
        return false;
    }

    if (deviceKey == "lampu")
    {
        controlLampu(on);
        return true;
    }

    controlSanyo(on);
    return true;
}

bool getMasterRelayState(const String &roomKey, const String &deviceKey)
{
    if (roomKey != "teras")
    {
        return false;
    }
    if (deviceKey == "lampu")
    {
        return lampuState;
    }
    if (deviceKey == "sanyo")
    {
        return sanyoState;
    }
    return false;
}
