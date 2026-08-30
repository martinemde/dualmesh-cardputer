# DualMesh — Meshtastic / MeshCore boot picker for the M5Stack Cardputer ADV

Lets one Cardputer ADV + Cap LoRa-1262 run either Meshtastic or MeshCore, each at full power
and full protocol fidelity, chosen from an on-device menu. It is **not** the two networks live
at the same instant on the same radio — see "Why not truly concurrent?" below for why that
option was ruled out, and what was built instead.

## How it works

The ESP32-S3's flash is split into three app slots by `partitions_dualmesh.csv`: `factory`
(this project's own tiny **launcher**), `ota_0` (a stock **Meshtastic** build), and `ota_1` (a
**MeshCore** build in Companion Radio mode). The launcher is what boots by default. It shows a
two-item menu, and when you pick one it calls `esp_ota_set_boot_partition()` and reboots
straight into that slot — from then on the device boots directly into your choice, at full
LoRa TX power, with none of the other slot's code even loaded into flash cache. Holding the
BOOT button (GPIO0) for 3 seconds from inside either guest firmware jumps back to the launcher's
menu.

```
common/                     Shared pin map + the OTA-slot-switching helper both other pieces use
launcher/                   Standalone PlatformIO project — the boot-menu app (factory slot)
meshtastic-overlay/         A few files to drop into your own meshtastic/firmware checkout
meshcore-cardputer/         A new board variant to drop into your own MeshCore checkout
partitions_dualmesh.csv     The shared partition table (all three builds must use this exact file)
flash_all.sh                Builds all three and writes them to the device in one pass
```

## Why not truly concurrent?

I looked into running both networks live at once and it isn't a good fit for this hardware —
worth explaining so this doesn't read as a downgrade from what was asked for:

- The Cardputer ADV's only LoRa radio is the single SX1262 on the Cap LoRa-1262 module, on a
  fixed SPI bus. The board's one other expansion port exposes just two spare GPIOs — not enough
  to wire a second radio's SPI+IRQ+reset+busy lines.
- Meshtastic's `RadioLibInterface` and MeshCore's SX1262 wrapper are both built to exclusively
  own that SPI bus and IRQ line (confirmed directly in MeshCore's own driver code).
- Meshtastic and MeshCore use different default frequencies, spreading factors, and sync words —
  a single radio can't be tuned to receive both at the same instant regardless of firmware.

The realistic paths were: (a) two physical radios on two devices, bridged in software — the
approach real prior art (e.g. the community Akita Meshtastic↔MeshCore bridge) already takes,
full power on both, but it's two gadgets, not one; (b) one radio, duty-cycled between both
protocols' channel parameters — genuinely one device, but each network only hears it part of the
time, denting range/reliability on both; (c) this project's approach — full power, full
reliability, one device, but one protocol live at a time. Given the choice, full power on
whichever network you're actually using beat a compromise that would have made both weaker to
get simultaneity that the radio can't really deliver anyway. If you'd rather have true
simultaneity, option (a) is a straightforward variation on this same firmware — MeshCore's
Companion Radio build here already runs standalone on any SX1262 ESP32-S3 board (Heltec V3,
Xiao ESP32-S3, ...); you'd skip the launcher/partition-table complexity entirely and just run it
on a second board next to the Cardputer.

## RF power & regulatory compliance

The SX1262's hardware ceiling is +22 dBm, and both firmwares are configured here to use it — but
the legal maximum depends on your regulatory region (US915, EU868, etc. all differ in max power
*and* duty cycle rules). Neither build here hardcodes a bypass of that: Meshtastic still exposes
its normal region selector (set yours before transmitting — un-set/`Unset` region does not
transmit), and MeshCore's power/frequency are still whatever you configure through its app. Pick
the correct region for where you actually are; "as powerful as possible" here means "the
hardware's ceiling, inside whatever your region actually allows," not "ignore the rules."

## What you get in each slot

**Meshtastic** (`ota_0`) is an unmodified build of the upstream, actively-maintained
`m5stack-cardputer-adv` target — full on-device keyboard chat UI, GPS, the works. Nothing about
Meshtastic itself was changed; the overlay only points its build at the shared partition table
and adds the one-line return-to-launcher hook.

**MeshCore** (`ota_1`) is built in **Companion Radio** mode (BLE by default, USB-serial as an
alternate env), not on-device chat. This wasn't a shortcut: MeshCore's own closest hardware
match to the Cardputer — the LilyGO T-Deck, the only other keyboard+color-screen+SX1262 board it
supports — *also* only ships Companion Radio, repeater, and modem builds, not on-device chat,
even though it has a keyboard. There's no documented on-device chat UI contract in MeshCore to
build against safely for either board. Companion Radio is also MeshCore's most complete, most
capable mode — full protocol feature set, official iOS/Android/web app pairing over BLE or USB —
so it's the right call on its own merits, not just the safe one. The Cardputer's screen shows
MeshCore's status UI (battery, radio state, contacts) via its existing ST7789 driver; you compose
messages in the paired app, same as any other MeshCore companion node.

## Building — the easy way (recommended): GitHub Actions

`.github/workflows/build.yml` does the entire build for you, for free, on GitHub's own servers —
no local PlatformIO install, and (unlike the sandbox this project was developed in) full,
unrestricted network access to platformio.org's package registry and Espressif's component
registry, which is what real ESP-IDF/Arduino builds need. This is the same approach Meshtastic
and MeshCore themselves use to build their own official releases.

1. Create a new **public** GitHub repo (private repos need a paid plan for Actions minutes on
   some account tiers, but the free tier includes minutes for public repos) and push everything
   in this folder to it — either via GitHub's "upload files" web UI, or:
   ```
   cd dualmesh && git init && git add -A && git commit -m "DualMesh"
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
2. On GitHub, open the repo's **Actions** tab. The push above triggers the workflow
   automatically (or click **Run workflow** to trigger it by hand). It takes roughly 15-25
   minutes — it's compiling three full ESP32 firmware images from source.
3. When the run finishes (green check), open it and download the **dualmesh-cardputer-adv-bin**
   artifact (bottom of the run page, under "Artifacts"). Unzip it.
4. In **M5Burner**, use its custom/local firmware upload option, point it at
   **`dualmesh-cardputer-adv-full.bin`** from that zip, and burn it to your Cardputer ADV at
   flash offset **0x0**. That one file is bootloader + partition table + all three app slots
   merged into a single flat image — it's the only file you need for M5Burner.
   The zip also contains the five images unmerged (`bootloader.bin`, `partitions.bin`,
   `launcher-firmware.bin`, `meshtastic-firmware.bin`, `meshcore-firmware.bin`) for anyone who'd
   rather flash slots individually with `esptool` — see `flash_all.sh`, which does exactly that.

The workflow file is thoroughly commented if you want to see exactly what it's doing at each
step; it's just automating the same manual sequence in "Building — manually" below.

## Building — manually

If you'd rather build locally (or want to modify something first), you need your own local
checkouts of both upstream projects (not included here — this repo only ever ships the *delta*
on top of them, so you can `git pull` upstream normally):

```
git clone https://github.com/meshtastic/firmware.git
git clone https://github.com/ripplebiz/MeshCore.git
pip install platformio
```

**1. Launcher** — fully self-contained, nothing to merge:
```
cd launcher && pio run -e cardputer_adv_launcher
```

**2. Meshtastic overlay:**
```
MT=/path/to/your/meshtastic/firmware
mkdir -p "$MT/variants/esp32s3/m5stack_cardputer_adv_dualmesh"
cp "$MT/variants/esp32s3/m5stack_cardputer_adv/"{pins_arduino.h,variant.h} \
   "$MT/variants/esp32s3/m5stack_cardputer_adv_dualmesh/"
cp common/dualmesh_ota.h common/board_pins_cardputer_adv.h partitions_dualmesh.csv \
   "$MT/variants/esp32s3/m5stack_cardputer_adv_dualmesh/"
cp meshtastic-overlay/platformio_dualmesh_env.ini \
   "$MT/variants/esp32s3/m5stack_cardputer_adv_dualmesh/platformio.ini"
cd "$MT" && git apply /path/to/dualmesh/meshtastic-overlay/0001-add-return-to-launcher-hook.patch
pio run -e m5stack-cardputer-adv-dualmesh
```

**3. MeshCore overlay:**
```
MC=/path/to/your/MeshCore
mkdir -p "$MC/variants/cardputer_adv"
cp meshcore-cardputer/variants/cardputer_adv/*.{h,cpp} "$MC/variants/cardputer_adv/"
cp meshcore-cardputer/platformio.ini "$MC/variants/cardputer_adv/platformio.ini"
cp common/dualmesh_ota.h common/board_pins_cardputer_adv.h partitions_dualmesh.csv \
   "$MC/variants/cardputer_adv/"
cd "$MC"
git apply /path/to/dualmesh/meshcore-cardputer/0001-add-return-to-launcher-hook.patch
git apply /path/to/dualmesh/meshcore-cardputer/0002-st7789lcddisplay-cardputer-adv-panel.patch
git apply /path/to/dualmesh/meshcore-cardputer/0003-spiffs-mc-data-partition-label.patch
pio run -e cardputer_adv_companion_radio_ble
```

**4. Flash everything at once:**
```
./flash_all.sh "$MT" "$MC" /dev/ttyACM0   # port is optional, esptool will try to auto-detect
```

## ⚠️ Not yet verified on real hardware

Every pin number and board macro above was pulled from actual upstream source (not guessed), the
partition table's arithmetic was checked programmatically, and — as of 2026-08-30 — **all four
patch files were re-verified by applying them with `git apply` against fresh, live clones of the
real `meshtastic/firmware` and `ripplebiz/MeshCore` `main` branches; all four applied cleanly with
no fuzz or offset warnings.**

**All three environments have since been fully compiled successfully via the GitHub Actions
workflow above, on a real, unrestricted-network runner:** launcher, Meshtastic
(`m5stack-cardputer-adv-dualmesh`), and MeshCore (`cardputer_adv_companion_radio_ble`) all reach a
clean link with real memory-usage tables. Along the way two real bugs were found and fixed by
that first full run: MeshCore needed `Preferences` added to `lib_deps` explicitly (its
`examples/companion_radio/main.cpp` sits outside `src_dir`, so PlatformIO's Library Dependency
Finder doesn't auto-detect that framework header the way it does for Meshtastic's `src/main.cpp`),
and this workflow's own Verify/Merge steps were hardcoded to a plain `firmware.bin` path for
Meshtastic that doesn't actually exist — Meshtastic's own `platformio-custom.py` build script
renames its output to `firmware-<env>-<version>.<git-hash>.bin`, a name that changes on every
meshtastic/firmware commit. Both are now fixed (see the workflow file and `flash_all.sh`, which
both now locate that file dynamically instead of assuming a fixed name). What has **not** been
done from this side: nothing has touched real hardware yet.

Watch the Actions log for any compiler errors (upstream drift is the most likely remaining
failure mode — a patch hunk that no longer applies cleanly fails the workflow with a clear error
naming which file and patch; the fix is usually just re-locating the one or two lines each patch
adds, using the "if this hunk fails" notes inside each patch file), and test the launcher's
boot-menu and the return-to-launcher hold-to-exit gesture on real hardware before relying on it
day to day.

## Using it

- Power on: the launcher shows **Meshtastic** / **MeshCore**. Tap BOOT to cycle, hold ~1.2s to
  boot the highlighted one. No input for 5s auto-boots your last choice (defaults to Meshtastic
  the very first time).
- From inside either firmware: hold BOOT for 3s to jump back to this menu.
- Do not use Meshtastic's or MeshCore's own "check for firmware update" features on this build —
  each project's self-OTA mechanism assumes it owns both halves of a two-slot A/B layout, and
  would write into the *other* project's slot here, corrupting this partition layout. Reflash
  with `flash_all.sh` instead when you want to update either side.

## Extending this

The most valuable next step, if you want it, is a real on-device MeshCore chat UI (instead of
Companion Radio) — genuinely new work, not something to shortcut, since it means implementing
against MeshCore's `UIScreen`/on-device-UI pattern from scratch with no existing keyboard-driven
reference to build from. Happy to take a run at that as a follow-up if you want the Cardputer's
own keyboard driving MeshCore chat directly instead of pairing with a phone.
