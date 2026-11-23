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
| **Helmet Headlamp (1.6.0)** (`mods/patpatpatrick/helmet_headlamp`) | Pure Lua 5.1 / ModOptions + Bindings | 🟢 Verified Working | Steam Build 26568081+ | `HELMET HEADLAMP` (`L` Toggle / `N` Mode) | Confirmed working in-game. Live hotkey rebinding (`[PRESS KEY]`) with pure-Lua wrist animation chat guard. |
| **Uniformity** (`mods/uniformity`) | Chef / Libra / UML `v2.0.4+` | 🟢 Verified Working | Steam Build 26568081+ | `UNIFORMITY` (`RShift` / Compact Menu) | Validated in-game by mod author Libra. External menu toggle (`allow_in_menu`), `connect_native()` detection, and F9/Compact interop verified. |
| **Reticle Ammo HUD (2.1.6)** (`mods/reticle_ammo/hud`) | Chef Shared Loader (API 3) | 🟢 Verified Working | Steam Build 26568081+ | `RETICLE AMMO HUD` (46 options) | Full Chef Shared Loader API 3 host (`call_kind`, returned `M.update`, immediate UI world GUI, options & keybinds). |
| **HUDdle (0.8.4)** (`mods/rosensterner/minimal_hud`) | Chef Shared Loader (API 3) | 🟢 Verified Working | Steam Build 26568081+ | `HUDDLE` (428 options / 17 sections) | Confirmed working in-game on `v2.0.5` (no-helper edition): atlas icons, 3D trajectory lines, ground decals, camera basis/FOV, Alt-Tab `ScreenGui` recovery, and `minimal_hud.log` routing. |
| **Driver HUD (1.6.5)** (`mods/driverhud/driver_hud`) | Pure Lua 5.1 / CowboyBingus | 🟢 Verified Working | Steam Build 26568081+ | `DRIVER HUD` (11 options) | Pure-Lua vehicle HUD with live F9 config sync to `driver_hud_settings.txt`. |
| **Vehicle Specified Seat Switch (0.4.5)** (`mods/vehicle_seat_tools/vehicle_seat_switch`) | CowboyBingus / ModOptions + Bindings | 🟡 Pending Review | Awaiting Community Test | `VEHICLE SEAT SWITCH` (10 items) | Submenu and keybindings unified; awaiting in-game playtest check-in. |
| **Mech Part HUD (1.11.1)** (`mods/arena_local/mech_part_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | Automatic HUD Overlay | Module discovery mapped; awaiting in-game playtest check-in. |
| **Mortar HUD (4.4.0)** (`mods/mortar/mortar_hud`) | CowboyBingus (`v17`) | 🟡 Pending Review | Awaiting Community Test | `MORTAR HUD` (8 options) | Bridged via `BingusRuntime` and `ModOptionsMenu` v3; awaiting in-game playtest check-in. |
| **Armor Transmog (1.1.2)** | Rat's Shared Loader | 🟡 Pending Review | Awaiting Community Test | In-Game Armory UI | Native `_G.RatsSharedLoader` 1.1.2 ABI emulation implemented; awaiting in-game playtest check-in. |
| **SEAF Artillery Loadout (2.0.0)** (`mods/chef/seaf_artillery_loadout`) | Pre-EAC Native Memory (`ffi`) | 🔴 Blocked by EAC (7.2.0+) | N/A | `SEAF ARTILLERY` (2 options) | Loads & registers F9 options cleanly, but requires `ffi` / `ReadProcessMemory` blocked by Patch 7.2.0 EAC; needs author update. |
| **Smarter Guard Dogs & Sentries (5.2.0)** (`mods/chef/smarter_guard_dogs_and_sentries*`) | Pre-EAC Native Memory (`ffi`) | 🔴 Blocked by EAC (7.2.0+) | N/A | `SMARTER GUARD DOGS` (15 options) | Loads & registers F9 options cleanly, but requires `ffi` / `ReadProcessMemory` blocked by Patch 7.2.0 EAC; needs author update. |
| **Sentry HUD (2.2)** (`mods/retrox/sentry_hud`) | Pre-EAC Native Memory (`ffi`) | 🔴 Blocked by EAC (7.2.0+) | N/A | `SENTRY HUD` (17 options) | Loads & registers F9 options cleanly, but requires `ffi` / `ReadProcessMemory` blocked by Patch 7.2.0 EAC; needs author update. |
| **Warbond Desk (0.9.21)** (`mods/warbond_desk/main`) | Pre-EAC Native Memory (`ffi`) | 🔴 Blocked by EAC (7.2.0+) | N/A | In-Game Warbond UI (`R` / `F8`) | Loads cleanly, but requires native memory bridge blocked by Patch 7.2.0 EAC; needs author update. |
| **Overdive** | Binary C++ Injector | 🔴 Blocked by EAC (7.2.0+) | N/A | External Binary | External C++ DLL injector blocked by Easy Anti-Cheat (EAC); requires upstream author update. |

---

## 🔄 Monthly Stewardship Pings & Static Mod Protection
Our automated workflow (`.github/workflows/mod-lifecycle-tracker.yml`) runs on the 1st of every month:
1. **60 Days Inactive:** Automatically tags the mod issue with `needs-check-in` (🟡) so players can confirm whether it still works on the current Arrowhead patch.
2. **90 Days Inactive:** Automatically marks unverified mods as `abandoned-upstream` (🔴) so players and modders know which mods are unmaintained and open for community adoption.
3. **Static Mod Exemption:** Any mod confirmed as finished/complete (`static-complete` / 🔵) is permanently immune to the 60-day and 90-day timers.
