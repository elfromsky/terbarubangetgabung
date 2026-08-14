#ifndef FIREBASE_TELEMETRY_H
#define FIREBASE_TELEMETRY_H

#include "pzem.h"
#include <cstdint>

bool sendHeartbeat();
bool sendSensorData(float temperature, float humidity,
                    int64_t environmentSampledAtEpochSeconds,
                    PzemData pzemData,
                    int64_t powerSampledAtEpochSeconds);

#endif
