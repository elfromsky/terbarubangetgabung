#ifndef ROOM_DEVICE_ROUTING_H
#define ROOM_DEVICE_ROUTING_H

#include <Arduino.h>
#include "esp_now_config.h"

// Apply a semantic device command to local hardware.
// Fills outState with final status for ACK.
// Returns true on success, false on failure (unknown device, etc.).
bool applyDeviceCommand(const DeviceCommandPayload &cmd, DeviceStatePayload &outState);

// Build a semantic state payload for the i-th device in the route table.
// Used for periodic full-state reporting.
void buildPeriodicStateForDevice(uint8_t index, DeviceStatePayload &outState);

// Number of entries in the route table.
uint8_t getDeviceCount();

// Returns true if roomKey/deviceKey maps to a dimmable device.
bool isDimmableDevice(const char* roomKey, const char* deviceKey);

#endif
