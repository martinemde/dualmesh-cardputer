#!/usr/bin/env bash
# flash_all.sh — build all three DualMesh app slots and write them to a Cardputer ADV in one pass.
#
# Usage:
#   ./flash_all.sh <path-to-your-meshtastic-checkout> <path-to-your-meshcore-checkout> [serial-port]
#
# Prerequisites (see README.md "Building" for the full walkthrough):
#   - PlatformIO CLI installed (`pip install platformio`)
#   - esptool.py installed (ships with PlatformIO's espressif32 platform; this script calls the
#     one PlatformIO already installed via `python3 -m esptool`)
#   - Your meshtastic checkout already has meshtastic-overlay/ installed into it (env
#     m5stack-cardputer-adv-dualmesh exists) and the return-to-launcher patch applied.
#   - Your meshcore checkout already has meshcore-cardputer/ installed into it as
#     variants/cardputer_adv/ (envs cardputer_adv_companion_radio_ble / _usb exist) and all
#     three patches applied.
#
# This script does NOT rely on `pio run -t upload` for the app slots (PlatformIO's automatic
# upload-offset detection isn't reliable when a partition table defines three app partitions —
# see the comment in meshcore-cardputer/platformio.ini). Instead it builds each project with
# `pio run` only, then writes bootloader + partition table + all three app images to their exact
# offsets from partitions_dualmesh.csv with esptool.py directly, and leaves otadata untouched
# (erased), which is what makes the ROM bootloader fall back to the "factory" slot (the
# launcher) on first boot.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESHTASTIC_DIR="${1:?usage: $0 <meshtastic-checkout> <meshcore-checkout> [serial-port]}"
MESHCORE_DIR="${2:?usage: $0 <meshtastic-checkout> <meshcore-checkout> [serial-port]}"
SERIAL_PORT="${3:-}"

MESHTASTIC_ENV="m5stack-cardputer-adv-dualmesh"
MESHCORE_ENV="cardputer_adv_companion_radio_ble"   # switch to cardputer_adv_companion_radio_usb if preferred

# ---- partition offsets, must match partitions_dualmesh.csv exactly ----
OFF_BOOTLOADER=0x0
OFF_PARTTABLE=0x8000
OFF_FACTORY=0x10000
SIZE_FACTORY=$((0x100000))
OFF_OTA0=0x110000
SIZE_OTA0=$((0x3A0000))
OFF_OTA1=0x5B0000
SIZE_OTA1=$((0x200000))

log() { echo "[flash_all] $*"; }

check_size() {
  local file="$1" max="$2" label="$3"
  local sz
  sz=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
  if [ "$sz" -gt "$max" ]; then
    echo "ERROR: $label firmware.bin is $sz bytes, which does not fit its $max-byte partition." >&2
    echo "       Grow that slot in partitions_dualmesh.csv (and every project's build_flags" >&2
    echo "       that reference it) and re-flash — do NOT flash an oversized image, it will" >&2
    echo "       overwrite the next partition and corrupt this whole layout." >&2
    exit 1
  fi
  log "$label firmware.bin: $sz / $max bytes OK"
}

log "Building launcher (env cardputer_adv_launcher)..."
( cd "$HERE/launcher" && python3 -m platformio run -e cardputer_adv_launcher )
LAUNCHER_BUILD="$HERE/launcher/.pio/build/cardputer_adv_launcher"

log "Building Meshtastic (env $MESHTASTIC_ENV)..."
( cd "$MESHTASTIC_DIR" && python3 -m platformio run -e "$MESHTASTIC_ENV" )
MESHTASTIC_BUILD="$MESHTASTIC_DIR/.pio/build/$MESHTASTIC_ENV"

# Meshtastic's own platformio-custom.py renames its output away from the generic
# firmware.bin PlatformIO would normally produce -- PROGNAME embeds the app version plus a
# git short-hash (e.g. firmware-m5stack-cardputer-adv-dualmesh-2.8.0.7239fe8.bin), and that
# suffix changes on every meshtastic/firmware commit, so it can't be hardcoded. Exclude the
# *.factory.bin also produced there (Meshtastic's own self-merged image at ITS standalone-
# board offsets, wrong for this project's shared partition table) -- we want the plain,
# unmerged app image only.
MESHTASTIC_BIN=""
for f in "$MESHTASTIC_BUILD"/firmware-*.bin; do
  case "$f" in
    *.factory.bin) continue ;;
  esac
  MESHTASTIC_BIN="$f"
done
if [ -z "$MESHTASTIC_BIN" ] || [ ! -f "$MESHTASTIC_BIN" ]; then
  echo "ERROR: could not find Meshtastic's output binary under $MESHTASTIC_BUILD" >&2
  echo "       (looked for firmware-*.bin, excluding *.factory.bin). Contents:" >&2
  ls -la "$MESHTASTIC_BUILD" >&2 || true
  exit 1
fi
log "Found Meshtastic app image: $MESHTASTIC_BIN"

log "Building MeshCore (env $MESHCORE_ENV)..."
( cd "$MESHCORE_DIR" && python3 -m platformio run -e "$MESHCORE_ENV" )
MESHCORE_BUILD="$MESHCORE_DIR/.pio/build/$MESHCORE_ENV"

check_size "$LAUNCHER_BUILD/firmware.bin" "$SIZE_FACTORY" "launcher"
check_size "$MESHTASTIC_BIN"              "$SIZE_OTA0"    "meshtastic"
check_size "$MESHCORE_BUILD/firmware.bin" "$SIZE_OTA1"    "meshcore"

PORT_ARGS=()
if [ -n "$SERIAL_PORT" ]; then
  PORT_ARGS=(--port "$SERIAL_PORT")
else
  log "No serial port given — letting esptool auto-detect. Pass one explicitly if that fails."
fi

OFF_OTADATA=0xE000
SIZE_OTADATA=$((0x2000))

log "Erasing otadata (0xE000, 8KB) so the device falls back to the launcher on next boot,"
log "regardless of whatever slot it last booted into..."
python3 -m esptool --chip esp32s3 "${PORT_ARGS[@]}" -b 921600 \
  erase_region "$OFF_OTADATA" "$SIZE_OTADATA"

log "Flashing bootloader + partition table + all three app slots..."
python3 -m esptool --chip esp32s3 "${PORT_ARGS[@]}" -b 921600 \
  --before default_reset --after hard_reset write_flash -z \
  --flash_mode qio --flash_freq 80m --flash_size 8MB \
  "$OFF_BOOTLOADER"    "$LAUNCHER_BUILD/bootloader.bin" \
  "$OFF_PARTTABLE"     "$LAUNCHER_BUILD/partitions.bin" \
  "$OFF_FACTORY"       "$LAUNCHER_BUILD/firmware.bin" \
  "$OFF_OTA0"          "$MESHTASTIC_BIN" \
  "$OFF_OTA1"          "$MESHCORE_BUILD/firmware.bin"

log "Done. otadata was erased, so the device boots to the launcher first no matter what it"
log "booted into before. Pick Meshtastic or MeshCore there; it'll remember your choice after that."
