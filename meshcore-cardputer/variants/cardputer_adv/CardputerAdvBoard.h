#pragma once

#include <Wire.h>
#include <Arduino.h>
#include "helpers/ESP32Board.h"
#include "board_pins_cardputer_adv.h" // shared with ../../../launcher and ../../../meshtastic-overlay

// Modeled directly on variants/lilygo_tdeck/TDeckBoard.h — the closest existing MeshCore
// board (keyboard + color ST7789 TFT + SX1262), adapted to Cardputer ADV's real wiring
// (see ../../../common/board_pins_cardputer_adv.h, sourced from M5Stack's Cap LoRa-1262
// docs and cross-checked against Meshtastic's upstream m5stack-cardputer-adv variant).

#define PIN_VBAT_READ   DM_BATTERY_PIN
#define BATTERY_SAMPLES 8
// Cardputer ADV uses a 100k+100k divider (2x) with a ~2% fudge factor, matching Meshtastic's
// upstream variant.h for this exact board (`ADC_MULTIPLIER 2 * 1.02`), expressed here as a
// millivolt-scale constant for a 12-bit ADC read: (ADC_MULTIPLIER_MV * raw) / 4096.
#define ADC_MULTIPLIER_MV (2.0f * 1.02f * 3.3f * 1000.0f)

class CardputerAdvBoard : public ESP32Board {
public:
  void begin();

  uint16_t getBattMilliVolts() {
    analogReadResolution(12);
    uint32_t raw = 0;
    for (int i = 0; i < BATTERY_SAMPLES; i++) {
      raw += analogRead(PIN_VBAT_READ);
    }
    raw = raw / BATTERY_SAMPLES;
    return (uint16_t)((ADC_MULTIPLIER_MV * raw) / 4096.0f);
  }

  const char* getManufacturerName() const {
    return "M5Stack Cardputer ADV";
  }
};
