#include <Arduino.h>
#include "CardputerAdvBoard.h"

// Modeled on variants/lilygo_tdeck/TDeckBoard.cpp.
void CardputerAdvBoard::begin() {
  ESP32Board::begin();

  // Configure user/BOOT button (also used by dualmesh::ReturnHook — see
  // ../../0001-add-return-to-launcher-hook.patch — both just digitalRead() it,
  // no exclusive ownership, so this is safe to share).
  pinMode(PIN_USER_BTN, INPUT);

  // Configure LoRa pins
  pinMode(P_LORA_MISO, INPUT_PULLUP);

  esp_reset_reason_t reason = esp_reset_reason();
  if (reason == ESP_RST_DEEPSLEEP) {
    long wakeup_source = esp_sleep_get_ext1_wakeup_status();
    if (wakeup_source & (1 << P_LORA_DIO_1)) {
      startup_reason = BD_STARTUP_RX_PACKET; // received a LoRa packet while asleep
    }
    rtc_gpio_hold_dis((gpio_num_t)P_LORA_NSS);
    rtc_gpio_deinit((gpio_num_t)P_LORA_DIO_1);
  }
}
