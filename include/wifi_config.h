#ifndef WIFI_CONFIG_H
#define WIFI_CONFIG_H

#if __has_include("wifi_config.local.h")
#include "wifi_config.local.h"
#else
#error "Missing include/wifi_config.local.h; copy wifi_config.example.h and set local credentials"
#endif

#if !defined(WIFI_SSID) || !defined(WIFI_PASSWORD)
#error "wifi_config.local.h must define WIFI_SSID and WIFI_PASSWORD"
#endif

#endif
