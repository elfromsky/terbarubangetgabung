#ifndef FIREBASE_CONFIG_H
#define FIREBASE_CONFIG_H

#if __has_include("firebase_config.local.h")
#include "firebase_config.local.h"
#else
#error "Missing include/firebase_config.local.h; copy firebase_config.example.h and set local credentials"
#endif

#if !defined(FIREBASE_DATABASE_URL) || !defined(FIREBASE_API_KEY) || \
    !defined(FIREBASE_USER_EMAIL) || !defined(FIREBASE_USER_PASSWORD)
#error "firebase_config.local.h must define all Firebase configuration macros"
#endif

#endif
