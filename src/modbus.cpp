#include "modbus.h"
#include <HardwareSerial.h>

extern HardwareSerial SensorSerial;

// Making sure the data not changed even one bit during transmission
static uint16_t modbusCRC(byte *buf, int len)
{
  uint16_t crc = 0xFFFF;
  for (int pos = 0; pos < len; pos++)
  {
    // Assign crc with the XOR of the next byte data
    // Cast buf[pos] to uint16_t since XOR need to have the same bit width
    // Adding 8 new bits to the crc since casting 8 bit to 16 bit so the first 8 is 0
    crc ^= (uint16_t)buf[pos];

    // Loop 8 time since we only need to process 8 bits, while the other 8 is padding
    for (int i = 8; i != 0; i--)
    {
      // Checking if the lowest bit is 1
      if ((crc & 0x0001) != 0)
      {
        // Shift right by 1 bit
        // Then assign crc with the XOR of the polynomial
        crc >>= 1;
        crc ^= 0xA001;
      }
      else
      {
        // Just shift right by 1 bit
        crc >>= 1;
      }
    }
  }
  return crc;
}

// Read the Modbus register
// High Byte : the first 8 number from 16 bits
// Low Byte  : the last 8 number from 16 bits
float readModBus(uint16_t reg)
{
  byte cmd[8];
  cmd[0] = 0x01;       // Slave ID ( check ref manual )
  cmd[1] = 0x04;       // Function code ( check ref manual )
  cmd[2] = reg >> 8;   // Hight Byte (0x00)
  cmd[3] = reg & 0xFF; // Low Byte (0x01)
  cmd[4] = 0x00;       // Count High Byte (0x00)
  cmd[5] = 0x01;       // Count Low Byte (0x01, read 1 register)
  // array 0 - 5 is the command data, 6 and 7 is CRC

  uint16_t crc = modbusCRC(cmd, 6);
  cmd[6] = crc & 0xFF;        // CRC Low Byte
  cmd[7] = (crc >> 8) & 0xFF; // CRC High Byte

  digitalWrite(RS485_DIR, HIGH); // Send through RS485
  delay(10);
  SensorSerial.write(cmd, 8);   // Send Data (cmd) with length of (8) bytes
  SensorSerial.flush();         // Making sure all data is sent before switching to receive mode
  digitalWrite(RS485_DIR, LOW); // Switch to receive mode
  delay(200);                   // Wait for response

  // Actual respon only 7 bytes
  // response[0] = 0x01;   ->     Slave ID
  // response[1] = 0x04;    ->    Function code
  // response[2] = 0x02;    ->    Byte count (2 data bytes)
  // response[3] = HIGH;    ->    Data high byte
  // response[4] = LOW;     ->    Data low byte
  // response[5] = CRC_LOW; ->    CRC low byte
  // response[6] = CRC_HIGH;->    CRC high byte

  byte response[8]; // Allocate 8 bytes to avoid buffer overflow
  unsigned int i = 0;
  unsigned long start = millis(); // Start time for response timeout
  while (millis() - start < 500)  // Wait for response
  {
    // Check if data is available
    if (SensorSerial.available())
    {
      // Read the incoming byte by assigning it to the response array
      response[i++] = SensorSerial.read();
      if (i >= sizeof(response))
        break;
    }
  }

  // Check response validity
  if (i >= 5 && response[1] == 0x04)
  {
    // Shifting high byte to the left by 8 bits and ORing with low byte
    int raw = (response[3] << 8) | response[4];
    return raw / 10.0; // Convert to float and divide by 10 for temperature/humidity since it have 0.1f resolution ( check ref manual )
  }

  return -1;
}