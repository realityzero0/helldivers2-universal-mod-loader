# Helldivers 2 Community Mod Compatibility Registry

This registry tracks verified compatibility between third-party *Helldivers 2* mods and **Universal Mod Loader v2.0.0+**.

* **Submit a Compatibility Report:** [Mod Compatibility Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=compatibility_report.yml)
* **Submit a Monthly Check-In or Mark Static:** [Mod Stewardship Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=mod_stewardship.yml)

---

## 📊 Lifecycle Status Legend (Automated via `.github/workflows/mod-lifecycle-tracker.yml`)

| Badge | Status | Label | Definition |
| :---: | :--- | :---: | :--- |
| 🟢 | **Verified Working** | `verified-working` | 100% functional, loads cleanly, and verified in-game on the current build by maintainer. |
| 🟡 | **Pending Review** | `pending-review` | Initial support & hooks implemented; awaiting community playtest confirmation on current build. |
| 🔵 | **Static / Complete** | `static-complete` | Mature, feature-complete mod requiring no updates. **Permanently exempt from 90-day abandonment timers.** |
| 🔴 | **Abandoned Upstream** | `abandoned-upstream` | Inactive for **90+ days (3 months)** without verification or broken by game patches; open for community adoption. |

---

## 🗂️ Live Verified Compatibility Matrix (Open for Community Reports)

> **Note:** With the release of v2.0.0, the matrix is actively open for community confirmation. Only mods physically verified in-game on the live build are marked green. Please test your installed mods and submit a quick report to verify them!

| Mod Name | Original Standard | Status | Verified Build | F9 Submenu / Controls | Technical Notes |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Helmet Headlamp (Flashlight)** (`mods/patpatpatrick/helmet_headlamp`) | CowboyBingus / ModBindingsMenu | 🟢 Verified Working | Steam Build 26251122+ | `HELMET HEADLAMP` (Rebindable) | Confirmed working in-game. Live hotkey rebinding (`[PRESS KEY]`) with chat guard protection. |
| **Reticle Ammo HUD** (`mods/reticle_ammo/hud`) | CowboyBingus / ModOptionsMenu | 🟡 Pending Review | Awaiting Community Test | `RETICLE AMMO HUD` (25 options) | Synthetic PE headers & option registration implemented; awaiting in-game playtest check-in. |
| **Eagle HUD Probe** (`mods/engle/eagle_hud_probe`) | CowboyBingus / ModOptionsMenu | 🟡 Pending Review | Awaiting Community Test | `EAGLE HUD` (10 options) | Dynamic bilingual labels sanitized cleanly; awaiting in-game playtest check-in. |
| **Vehicle Specified Seat Switch** (`mods/vehicle_seat_tools/vehicle_seat_switch`) | CowboyBingus / ModOptions + Bindings | 🟡 Pending Review | Awaiting Community Test | `VEHICLE SEAT SWITCH` (8 items) | Submenu and keybindings unified; awaiting in-game playtest check-in. |
| **Warbond Desk** (`mods/warbond_desk/main`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | In-Game Warbond UI (`R` / `F8`) | `update` and `shutdown` hooks bound; awaiting in-game playtest check-in. |
| **Mech Part HUD** (`mods/arena_local/mech_part_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | Automatic HUD Overlay | Module discovery mapped; awaiting in-game playtest check-in. |
| **Driver HUD** (`mods/driverhud/driver_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | Automatic Vehicle HUD | Live config sync to `driver_hud_settings.txt` implemented; awaiting in-game playtest check-in. |
| **Smarter Guard Dogs & Sentries (5.2.0)** (`mods/chef/smarter_guard_dogs_and_sentries*`) | Chef Shared Loader (CSL) | 🟡 Pending Review | Awaiting Community Test | `SMARTER GUARD DOGS` (16 modules) | True CSL vararg chunk injection enabled; awaiting in-game playtest check-in. |
| **Mortar HUD (4.4.0)** (`mods/mortar/mortar_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | `MORTAR HUD` (8 options) | Bridged via `BingusRuntime` and `ModOptionsMenu` v3; awaiting in-game playtest check-in. |
| **Sentry HUD** (`mods/retrox/sentry_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | `SENTRY HUD` (17 options) | Bilingual options mapped; awaiting in-game playtest check-in. |
| **SEAF Artillery Loadout (2.0.0)** (`mods/chef/seaf_artillery_loadout`) | Custom Boot / CSL | 🟡 Pending Review | Awaiting Community Test | `SEAF ARTILLERY` (2 options) | Rogue Guest Boot Shield (`0xF476DF93691895FA`) sandboxed; awaiting in-game playtest check-in. |
| **Armor Transmog (1.1.2)** | Rat's Shared Loader | 🟡 Pending Review | Awaiting Community Test | In-Game Armory UI | Native `_G.RatsSharedLoader` 1.1.2 ABI emulation implemented; awaiting in-game playtest check-in. |
| **CowboyBingus Vanilla+ Suite** (`better_stratagem_bounce`, `hellpod_steering_unlocked`, etc.) | CowboyBingus (`BingusRuntime v1`) | 🟡 Pending Review | Awaiting Community Test | Automatic Gameplay | `BingusRuntime.guard()` active; awaiting community confirmation. |
| **Overdive** | Binary C++ Injector | 🔴 Needs Author Update | N/A | External Binary | External C++ DLL injector blocked by Easy Anti-Cheat (EAC); requires upstream author update. |

---

## 🔄 Monthly Stewardship Pings & Static Mod Protection
Our automated workflow (`.github/workflows/mod-lifecycle-tracker.yml`) runs on the 1st of every month:
1. **60 Days Inactive:** Automatically tags the mod issue with `needs-check-in` (🟡) so players can confirm whether it still works on the current Arrowhead patch.
2. **90 Days Inactive:** Automatically marks unverified mods as `abandoned-upstream` (🔴) so players and modders know which mods are unmaintained and open for community adoption.
3. **Static Mod Exemption:** Any mod confirmed as finished/complete (`static-complete` / 🔵) is permanently immune to the 60-day and 90-day timers.
