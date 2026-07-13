#ifndef MODBUS_H
#define MODBUS_H

#include <Arduino.h>

const int RS485_DIR = 4;

float readModBus(uint16_t reg);

#endif