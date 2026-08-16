#ifndef DIMMER_H
#define DIMMER_H

// Initialize both dimmer channels
void initializeDimmers();

// Set the brightness for a specific channel
// channel: 1 or 2
// brightness: 0-100
void setDimmerBrightness(int channel, int brightness);


#endif
