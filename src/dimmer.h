#ifndef DIMMER_H
#define DIMMER_H

#include <Arduino.h>
#include "esp_now_config.h"

// Pin definitions
#define ZERO_CROSS_PIN  14
#define DIMMER_1_PIN    13  // Kamar 1 & 2
#define DIMMER_2_PIN    12  // Dapur

// Max dimmer channel
#define DIMMER_COUNT 2

// Initialize both dimmer channels + zero-cross
void initializeDimmers();

// Set brightness for a specific channel (0-100)
void setDimmerBrightness(uint8_t channel, uint8_t brightness);

// Get brightness for a specific channel (0-100)
uint8_t getDimmerBrightness(uint8_t channel);

#endif
