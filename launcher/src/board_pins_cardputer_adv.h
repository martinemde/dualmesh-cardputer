// board_pins_cardputer_adv.h
//
// Shared pin definitions for M5Stack Cardputer ADV + official Cap LoRa-1262 module.
// Sourced from:
//  - M5Stack's published Cap LoRa-1262 pinout (docs.m5stack.com/en/cap/Cap_LoRa-1262)
//  - Meshtastic's upstream, maintained `variants/esp32s3/m5stack_cardputer_adv/variant.h`
//    (meshtastic/firmware, board env `m5stack-cardputer-adv`), which targets the exact same
//    module and is the ground truth this file was cross-checked against.
//
// Used by both launcher/ and meshcore-cardputer/ so the two projects can never disagree about
// wiring. Do NOT edit divergently in each project — edit here and copy/symlink into both.
#pragma once

// ---- LoRa radio: SX1262 on Cap LoRa-1262, dedicated SPI bus ----
#define DM_LORA_SCK     40
#define DM_LORA_MISO    39
#define DM_LORA_MOSI    14
#define DM_LORA_CS      5   // NSS
#define DM_LORA_RESET   3
#define DM_LORA_DIO1    4   // IRQ
#define DM_LORA_BUSY    6
#define DM_LORA_FREQ_MIN_MHZ  868   // Cap LoRa-1262 covers 868-923 MHz; select per regulatory region
#define DM_LORA_FREQ_MAX_MHZ  923
#define DM_LORA_TCXO_VOLTAGE  1.8f
#define DM_LORA_DIO2_AS_RF_SWITCH 1
#define DM_LORA_MAX_POWER_DBM 22   // SX1262 hardware ceiling — actual legal max depends on region,
                                   // see README.md "RF power & regulatory compliance"

// ---- Display: ST7789 240x135, separate SPI bus from the radio ----
#define DM_TFT_SCK      36
#define DM_TFT_MOSI     35
#define DM_TFT_MISO     -1
#define DM_TFT_CS       37
#define DM_TFT_DC       34
#define DM_TFT_RST      33
#define DM_TFT_BACKLIGHT 38
#define DM_TFT_BACKLIGHT_ON HIGH
#define DM_TFT_WIDTH    240
#define DM_TFT_HEIGHT   135

// ---- Keyboard: TCA8418 I2C matrix controller ----
#define DM_I2C_SDA      8
#define DM_I2C_SCL      9
#define DM_KB_INT       11
#define DM_TCA8418_ADDR 0x34

// ---- GPS (ATGM336H on the same Cap, optional use) ----
#define DM_GPS_RX_PIN   15
#define DM_GPS_TX_PIN   13
#define DM_GPS_BAUD     115200

// ---- Misc ----
#define DM_BUTTON_PIN   0     // GPIO0 / BOOT button — same physical button Meshtastic's stock
                               // Cardputer-ADV UI already uses for on-device menu navigation.
#define DM_BATTERY_PIN  10
#define DM_NEOPIXEL_PIN 21
