#include "modbus.h"
#include <HardwareSerial.h>
#include <limits>

extern HardwareSerial SensorSerial;

namespace
{
constexpr byte MODBUS_SLAVE_ID = 0x01;
constexpr byte MODBUS_READ_INPUT_REGISTERS = 0x04;
constexpr byte MODBUS_REGISTER_BYTE_COUNT = 0x02;
constexpr size_t MODBUS_RESPONSE_LENGTH = 7;
constexpr unsigned long MODBUS_RESPONSE_TIMEOUT_MS = 500;
constexpr unsigned long MODBUS_FRAME_GAP_MS = 5;
constexpr uint16_t TEMPERATURE_REGISTER = 0x0001;
constexpr uint16_t HUMIDITY_REGISTER = 0x0002;

float unavailableReading()
{
  return std::numeric_limits<float>::quiet_NaN();
}

static uint16_t modbusCRC(const byte *buf, size_t len)
{
  uint16_t crc = 0xFFFF;
  for (size_t pos = 0; pos < len; pos++)
  {
    crc ^= static_cast<uint16_t>(buf[pos]);

    for (byte bit = 0; bit < 8; bit++)
    {
      if ((crc & 0x0001) != 0)
      {
        crc >>= 1;
        crc ^= 0xA001;
      }
      else
      {
        crc >>= 1;
      }
    }
  }
  return crc;
}
} // namespace

float readModBus(uint16_t reg)
{
  byte cmd[8] = {
      MODBUS_SLAVE_ID,
      MODBUS_READ_INPUT_REGISTERS,
      static_cast<byte>(reg >> 8),
      static_cast<byte>(reg & 0xFF),
      0x00,
      0x01,
      0x00,
      0x00};

  uint16_t crc = modbusCRC(cmd, 6);
  cmd[6] = static_cast<byte>(crc & 0xFF);
  cmd[7] = static_cast<byte>((crc >> 8) & 0xFF);

  while (SensorSerial.available() > 0)
  {
    SensorSerial.read();
  }

  digitalWrite(RS485_DIR, HIGH);
  delay(10);
  SensorSerial.write(cmd, sizeof(cmd));
  SensorSerial.flush();
  digitalWrite(RS485_DIR, LOW);

  byte response[MODBUS_RESPONSE_LENGTH] = {};
  size_t responseLength = 0;
  bool responseTooLong = false;
  unsigned long start = millis();
  unsigned long lastByteAt = start;

  while (millis() - start < MODBUS_RESPONSE_TIMEOUT_MS)
  {
    while (SensorSerial.available() > 0)
    {
      int incoming = SensorSerial.read();
      if (incoming < 0)
      {
        break;
      }

      lastByteAt = millis();
      if (responseLength < MODBUS_RESPONSE_LENGTH)
      {
        response[responseLength++] = static_cast<byte>(incoming);
      }
      else
      {
        responseTooLong = true;
      }
    }

    if (responseLength == MODBUS_RESPONSE_LENGTH &&
        millis() - lastByteAt >= MODBUS_FRAME_GAP_MS)
    {
      break;
    }

    delay(1);
  }

  if (responseTooLong || responseLength != MODBUS_RESPONSE_LENGTH ||
      response[0] != MODBUS_SLAVE_ID ||
      response[1] != MODBUS_READ_INPUT_REGISTERS ||
      response[2] != MODBUS_REGISTER_BYTE_COUNT)
  {
    return unavailableReading();
  }

  uint16_t responseCRC = modbusCRC(response, MODBUS_RESPONSE_LENGTH - 2);
  if (response[5] != static_cast<byte>(responseCRC & 0xFF) ||
      response[6] != static_cast<byte>((responseCRC >> 8) & 0xFF))
  {
    return unavailableReading();
  }

  uint16_t raw = (static_cast<uint16_t>(response[3]) << 8) | response[4];
  if (reg == TEMPERATURE_REGISTER)
  {
    float temperature = static_cast<int16_t>(raw) / 10.0f;
    return temperature >= -40.0f && temperature <= 125.0f
               ? temperature
               : unavailableReading();
  }

  float value = raw / 10.0f;
  if (reg == HUMIDITY_REGISTER && (value < 0.0f || value > 100.0f))
  {
    return unavailableReading();
  }

  return value;
}
