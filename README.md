# Helldivers 2 Universal Mod Loader (v1.0.0)

[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Build%2026251122%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is a unified, pure-Lua 5.1 engine boot loader for *Helldivers 2*. It combines all major modding standards and loaders into a single, cohesive runtime:

1. **CowboyBingus Mod Loader** (API 1, Version 17, `BingusRuntime` v1, `on_update`, `on_shutdown`, `after_startup`)
2. **Chef Shared Loader** (API Levels 1, 2, 3, `HD2-Addon`, `HD2-Boot`, `HD2-Options`, cooperative handoff)
3. **Boot Mod Loader** (VeganSquid API 1)
4. **HD2 Lua Runtime** (`hd2rt` 0.1.0)
5. **Built-in Mod Options Menu** (MOM v3) with 1-based choice indexing, slider step-snapping, and description metadata
6. **Built-in Mod Bindings Menu** (MBM v4) with pure Stingray keyboard and mouse input tracking
7. **Native Escape Menu `MODS` Tab** with authentic 3-column Settings layout and full mouse navigation
8. **Dynamic Live Mod Loading & In-Game Hot-Reload** (run loose `.lua` scripts and reload mods live without restarting)
9. **Live Mod Enable / Disable Toggles** (turn mods on or off on the fly from the ESC menu with Space / Enter)
10. **Real-Time Frame Profiler & Memory Monitor** (track execution cost per frame in milliseconds per mod)
11. **Lua 5.2 / Lua 5.3 Polyfill Suite** (`bit32`, `utf8`, `table.pack`, `table.unpack`, `math.type`, `math.tointeger`, `math.ult`, and `goto` transpiler)

---

## Why Universal Mod Loader?

Following Arrowhead's engine overhaul (Steam Builds 25988413, 26088801, and 26251122+), LuaJIT (`lua51.dll`), FFI, and native memory hooks were deprecated, and anti-cheat was migrated to Easy Anti-Cheat (EAC EOS).

This caused severe ecosystem fragmentation:
- Old CowboyBingus mods crashed due to compiled LuaJIT bytecode.
- CowboyBingus's `mod_options_menu` and `mod_bindings_menu` failed because they relied on hardcoded `game.dll` memory RVAs and native C++ injection.
- Chef Shared Loader mods failed under Bingus loaders because of incompatible parameter conventions (`local chef = ...`).
- Modern mods written with Lua 5.2 `goto` or Lua 5.3 `utf8`/`bit32` failed on the game's PUC-Rio Lua 5.1 VM.
- Modding traditionally required repacking `.patch` files and restarting the entire game on every change.

**Universal Mod Loader v1.0.0 unifies all standards and brings dynamic live loading into a single EAC-safe engine.**

---

## Key Features

### 1. Dynamic Live Mod Loading & In-Game Hot Reload
* **Loose Scripts Directory**: Run mods directly from `<GameDir>/mods/` or `%LOCALAPPDATA%/UniversalModLoader/mods/` as plain `.lua` files without needing to pack them into `.patch` archives!
* **In-Game Hot-Reload ([R] Button / Key)**: Click **`[R] RELOAD ALL`** in the ESC menu or press **`R`** to reload all mods live on the fly. Re-scans disk, re-compiles scripts, and updates options/bindings without quitting your match or returning to desktop!
* **Live Arsenal Mod Manager Integration**: If you deploy or update mods via Arsenal Mod Manager while in your ship, pressing Hot-Reload picks up newly deployed patch archives immediately.

### 2. Live Mod Enable / Disable Toggles
* **On-the-Fly Start/Stop**: In **Tab 3 (Loaded Mods)**, click any mod's badge or press **`Space`** / **`Enter`** to instantly toggle it between `[ ACTIVE ]` and `[ DISABLED ]`.
* **Zero Frame Impact**: Disabled mods are immediately muted—their update loops, render hooks, and keybindings are bypassed, freeing up CPU frame budget.
* **Persistent State**: Disabled preferences are automatically saved in `%LOCALAPPDATA%/UniversalModLoader/settings.json` across game launches.

### 3. Real-Time Frame Profiler & Memory Monitor
* **Execution Time Profiling**: Measures actual CPU time spent executing each mod's `update` hook in milliseconds (`0.04 ms`).
* **Frame Budget Tracking**: Displays total mod CPU execution time and peak spikes so you can spot laggy scripts immediately.
* **Lua Heap Monitor**: Shows live Lua garbage collector memory footprint in kilobytes (`HEAP: 19,420 KB`).

### 4. Native Escape Menu `MODS` Tab & In-Game Overlay
* **Escape Menu Integration**: Press **Escape** to pause the game, then click the **`MODS [F2]`** tab directly in the top navigation bar alongside native Display, Graphics, and Audio tabs!
* **Authentic 3-Column Settings Layout**:
  - **Left Column**: Categorized mod list (navigate with mouse or `Q`/`E`).
  - **Center Column**: Interactive controls with toggle switches, value steppers, and choice selectors.
  - **Right Column**: Comprehensive option description and metadata card.
* **Full Mouse Navigation**: Click tabs, categories, toggles, and sliders directly with your mouse pointer.
* **Hotkeys**: Press **`F2`** or **`F9`** anytime during gameplay to toggle the menu overlay directly.

### 5. Multi-Tab Configuration Overlay
* **Tab 1: Mod Options**: Adjust mod settings live in-game. Changes are applied instantly.
* **Tab 2: Key Bindings**: View registered mod hotkeys and rebind them live (`Enter` -> Press any key).
* **Tab 3: Loaded Mods & Diagnostics**: Inspect all active, loose, superseded, and errored mods, their source (`patch_N` or `[LOOSE]`), CPU frame cost, and toggle states.

### 6. Standard Compatibility & Polyfill Engine
* **Pure Lua 5.1 Compliance**: Zero FFI, zero native C injection, zero EAC flags.
* **Lua 5.2/5.3 Standard Polyfills**: `bit32` and `utf8` standard libraries built-in.
* **Automatic `goto` Transpilation**: Converts Lua 5.2 `goto` continue statements into safe Lua 5.1 equivalents with 100% line number preservation.
* **Patch Deduplication**: Emulates Stingray priority rules across `patch_0..255`.

---

## Installation

### Method A: Arsenal Mod Manager (Recommended)
1. Drag and drop `Helldivers2-Universal-Mod-Loader-v1.0.0.zip` into **Arsenal Mod Manager**.
2. Enable Universal Mod Loader in Arsenal's list and click **Deploy**.
3. Launch Helldivers 2.

### Method B: Manual Installation
1. Extract `data/9ba626afa44a3aa3.patch_0`, `.stream`, and `.gpu_resources` into `Helldivers 2/data/`.
2. Launch the game.

---

## File Locations
* **Settings & Preferences**: `%LOCALAPPDATA%/UniversalModLoader/settings.json`
* **Log File**: `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log`
* **Live Loose Mods Folder**: `<GameDir>/mods/` or `%LOCALAPPDATA%/UniversalModLoader/mods/`

## License
Zero-Clause BSD (0BSD) - 100% Free & Open Source.
