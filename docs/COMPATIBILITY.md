# Helldivers 2 Community Mod Compatibility Registry

This registry tracks verified compatibility between third-party *Helldivers 2* mods and **Universal Mod Loader v2.0.0+**.

* **Submit a Compatibility Report:** [Mod Compatibility Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=compatibility_report.yml)
* **Submit a Monthly Check-In or Mark Static:** [Mod Stewardship Form](https://github.com/realityzero0/helldivers2-universal-mod-loader/issues/new?template=mod_stewardship.yml)

---

## 📊 Lifecycle Status Legend (Automated via `.github/workflows/mod-lifecycle-tracker.yml`)

| Badge | Status | Label | Definition |
| :---: | :--- | :---: | :--- |
| 🟢 | **Verified Working** | `verified-working` | 100% functional, loads cleanly, and verified in-game on the current build. |
| 🔵 | **Static / Complete** | `static-complete` | Mature, feature-complete mod requiring no updates. **Permanently exempt from 90-day abandonment timers.** |
| 🟡 | **Needs Check-In** | `needs-check-in` | Automated ping after **60 days** of no activity; awaiting a monthly community check-in on the latest patch. |
| 🔴 | **Abandoned Upstream** | `abandoned-upstream` | Inactive for **90+ days (3 months)** without verification or with unresolved game-update breakage; open for community adoption. |

---

## 🗂️ Live Verified Compatibility Matrix

| Mod Name | Original Standard | Status | Verified Build | F9 Submenu / Controls | Technical Notes |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Reticle Ammo HUD** (`mods/reticle_ammo/hud`) | CowboyBingus / ModOptionsMenu | 🟢 Verified Working | Steam Build 26251122+ | `RETICLE AMMO HUD` (25 options) | All 25 toggles, choices, and sliders register in its dedicated F9 submenu and persist across restarts. |
| **Eagle HUD Probe** (`mods/engle/eagle_hud_probe`) | CowboyBingus / ModOptionsMenu | 🟢 Verified Working | Steam Build 26251122+ | `EAGLE HUD` (10 options) | Dynamic bilingual function labels sanitized cleanly; all 10 options configurable in F9 submenu. |
| **Helmet Headlamp** (`mods/patpatpatrick/helmet_headlamp`) | CowboyBingus / ModBindingsMenu | 🟢 Verified Working | Steam Build 26251122+ | `HELMET HEADLAMP` (2 keybindings) | Live in-game hotkey rebinding (`[PRESS KEY]`) verified and persisted in `uml_mod_settings.json`. |
| **Vehicle Specified Seat Switch** (`mods/vehicle_seat_tools/vehicle_seat_switch`) | CowboyBingus / ModOptions + Bindings | 🟢 Verified Working | Steam Build 26251122+ | `VEHICLE SEAT SWITCH` (8 items) | Options and 5 seat switch keybindings unified into a single F9 submenu. |
| **Warbond Desk** (`mods/warbond_desk/main`) | CowboyBingus (`v17`) | 🟢 Verified Working | Steam Build 26251122+ | In-Game Warbond UI (`R` / `F8`) | Hooks `update` and `shutdown` cleanly; keyboard and controller input verified. |
| **Mech Part HUD** (`mods/arena_local/mech_part_hud`) | CowboyBingus (`v17`) | 🟢 Verified Working | Steam Build 26251122+ | Automatic HUD Overlay | Loads and runs cleanly at 0 errors. |
| **Driver HUD** (`mods/driverhud/driver_hud`) | CowboyBingus (`v17`) | 🟢 Verified Working | Steam Build 26251122+ | Automatic Vehicle HUD | Loads and runs cleanly at 0 errors. |
| **Smarter Guard Dogs & Sentries (5.2.0)** (`mods/chef/smarter_guard_dogs_and_sentries*`) | Chef Shared Loader (CSL) | 🟢 Verified Working | Steam Build 26251122+ | `SMARTER GUARD DOGS` (16 modules) | All 18 sub-modules load with 0 errors via `chunk(chef_api, mod_name)` vararg injection. |
| **Mortar HUD (4.4.0)** (`mods/mortar/mortar_hud`) | CowboyBingus (`v17`) | 🟢 Verified Working | Steam Build 26251122+ | `MORTAR HUD` (8 options) | Loads cleanly via `BingusRuntime` and `ModOptionsMenu` v3 bridge. |
| **Sentry HUD** (`mods/retrox/sentry_hud`) | CowboyBingus (`v17`) | 🟢 Verified Working | Steam Build 26251122+ | `SENTRY HUD` (17 options) | Bilingual localized options supported via `ModOptionsMenu` v3. |
| **SEAF Artillery Loadout (2.0.0)** (`mods/chef/seaf_artillery_loadout`) | Custom Boot / CSL | 🟢 Verified Working | Steam Build 26251122+ | `SEAF ARTILLERY` (2 options) | Rogue Guest Boot Shield (`0xF476DF93691895FA`) prevents entrypoint hijack while keeping addon active. |
| **Armor Transmog (1.1.2)** | Rat's Shared Loader | 🟢 Verified Working | Steam Build 26251122+ | In-Game Armory UI | Native `_G.RatsSharedLoader` 1.1.2 ABI emulation; Rat's loader not required separately. |
| **CowboyBingus Vanilla+ Suite** (`better_stratagem_bounce`, `hellpod_steering_unlocked`, `consistent_vaulting`, etc.) | CowboyBingus (`BingusRuntime v1`) | 🔵 Static / Complete | Steam Build 26251122+ | Automatic Gameplay | Full `BingusRuntime.guard()` and `murmur64_key` hash support. |
| **Overdive** | Binary C++ Injector | 🔴 Needs Author Update | N/A | External Binary | External C++ DLL injector blocked by Easy Anti-Cheat (EAC); requires upstream author update. |

---

## 🔄 Monthly Stewardship Pings & Static Mod Protection
Our automated workflow (`.github/workflows/mod-lifecycle-tracker.yml`) runs on the 1st of every month:
1. **60 Days Inactive:** Automatically tags the mod issue with `needs-check-in` (🟡) so players can confirm whether it still works on the current Arrowhead patch.
2. **90 Days Inactive:** Automatically marks unverified mods as `abandoned-upstream` (🔴) so players and modders know which mods are unmaintained and open for community adoption.
3. **Static Mod Exemption:** Any mod confirmed as finished/complete (`static-complete` / 🔵) is permanently immune to the 60-day and 90-day timers.
