#ifndef FIREBASE_APP_H
#define FIREBASE_APP_H

#include "firebase_client_common.h"

void firebaseAppInit();
void firebaseAppLoop();
bool firebaseReady();
RealtimeDatabase &firebaseDatabase();
AsyncClientClass &firebaseDataClient();
AsyncClientClass &firebaseStreamClient();
void firebaseSubscribeToCommandStream();

#endif
