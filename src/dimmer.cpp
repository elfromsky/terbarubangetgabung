#include <Arduino.h>
#include "dimmer.h"

// --- HARDWARE TIMER HANDLES ---
hw_timer_t *timer1 = NULL;
hw_timer_t *timer2 = NULL;

// --- STATE VARIABLES ---
volatile int delayTime1 = 0;
volatile int delayTime2 = 0;
volatile bool ch1_active = false;
volatile bool ch2_active = false;

// Current brightness values (0-100) in RAM
static uint8_t currentBrightness1 = 0;
static uint8_t currentBrightness2 = 0;

// Noise Filter variable
volatile unsigned long lastZCTime = 0;

// Pulse width for the TRIAC trigger (10 microseconds)
const int TRIAC_PULSE_MICROS = 10;

// --- INTERRUPT SERVICE ROUTINES (ISRs) ---

// Timer 1 ISR: Turn on Channel 1
void IRAM_ATTR onTimer1() {
  if (ch1_active) {
    digitalWrite(DIMMER_1_PIN, HIGH);
    delayMicroseconds(TRIAC_PULSE_MICROS);
    digitalWrite(DIMMER_1_PIN, LOW);
  }
}

// Timer 2 ISR: Turn on Channel 2
void IRAM_ATTR onTimer2() {
  if (ch2_active) {
    digitalWrite(DIMMER_2_PIN, HIGH);
    delayMicroseconds(TRIAC_PULSE_MICROS);
    digitalWrite(DIMMER_2_PIN, LOW);
  }
}

// Zero-Cross ISR
void IRAM_ATTR onZeroCross() {
  unsigned long now = micros();

  // Noise Filter: Ignore noise faster than 8.5ms (8500us)
  if (now - lastZCTime > 8500) {
    lastZCTime = now;

    if (ch1_active && timer1 != NULL) {
      timerWrite(timer1, 0);
      timerAlarmWrite(timer1, delayTime1, false);
      timerAlarmEnable(timer1);
    }

    if (ch2_active && timer2 != NULL) {
      timerWrite(timer2, 0);
      timerAlarmWrite(timer2, delayTime2, false);
      timerAlarmEnable(timer2);
    }
  }
}

// --- PUBLIC FUNCTIONS ---

void initializeDimmers() {
  // 1. Setup Pins
  pinMode(DIMMER_1_PIN, OUTPUT);
  pinMode(DIMMER_2_PIN, OUTPUT);
  pinMode(ZERO_CROSS_PIN, INPUT_PULLUP);

  digitalWrite(DIMMER_1_PIN, LOW);
  digitalWrite(DIMMER_2_PIN, LOW);

  // 2. Setup Hardware Timers
  // Divider 80 → 1 MHz from 80 MHz APB → 1 tick per microsecond
  timer1 = timerBegin(0, 80, true);
  timerAttachInterrupt(timer1, &onTimer1, true);

  timer2 = timerBegin(1, 80, true);
  timerAttachInterrupt(timer2, &onTimer2, true);

  // 3. Setup Zero Cross Interrupt
  attachInterrupt(digitalPinToInterrupt(ZERO_CROSS_PIN), onZeroCross, RISING);

  Serial.println("Dimmer Module Initialized (2 Channels).");
}

void setDimmerBrightness(uint8_t channel, uint8_t brightness) {
  // Clamp brightness
  if (brightness > 100) brightness = 100;

  int delay = 0;
  bool active = (brightness > 0);

  if (active) {
    // Map: High brightness = Short delay. Low brightness = Long delay.
    delay = map(brightness, 1, 100, 8600, 500);
  }

  if (channel == 1) {
    if (!active) ch1_active = false;
    delayTime1 = delay;
    currentBrightness1 = brightness;

    if (!active) {
      digitalWrite(DIMMER_1_PIN, LOW);
    }

  } else if (channel == 2) {
    if (!active) ch2_active = false;
    delayTime2 = delay;
    currentBrightness2 = brightness;

    if (!active) {
      digitalWrite(DIMMER_2_PIN, LOW);
    }
  }
}

void setDimmerOutputEnabled(uint8_t channel, bool enabled) {
  if (channel == 1) {
    ch1_active = enabled && currentBrightness1 > 0;
    if (!ch1_active) {
      digitalWrite(DIMMER_1_PIN, LOW);
    }
  } else if (channel == 2) {
    ch2_active = enabled && currentBrightness2 > 0;
    if (!ch2_active) {
      digitalWrite(DIMMER_2_PIN, LOW);
    }
  }
}

uint8_t getDimmerBrightness(uint8_t channel) {
  if (channel == 1) return currentBrightness1;
  if (channel == 2) return currentBrightness2;
  return 0;
}
