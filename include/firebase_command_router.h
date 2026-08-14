#ifndef FIREBASE_COMMAND_ROUTER_H
#define FIREBASE_COMMAND_ROUTER_H

#include <Arduino.h>
#include "firebase_client_common.h"

void handleFirebaseResult(AsyncResult &aResult);
void handleCommandStream(RealtimeDatabaseResult &stream);
void initializeMasterRouteStates();
void processSlaveCommunication();

#endif
