# Helldivers 2 Universal Mod Loader (v22.0.0)

[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Build%2026251122%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is a unified, pure-Lua 5.1 engine boot loader for *Helldivers 2*. It combines all major modding ecosystems into a single, cohesive runtime:

1. **CowboyBingus Mod Loader** (API 1, Version 17, `BingusRuntime` v1, `on_update`, `on_shutdown`, `after_startup`)
2. **Chef Shared Loader** (API Levels 1, 2, 3, `HD2-Addon`, `HD2-Boot`, `HD2-Options`)
3. **Boot Mod Loader** (VeganSquid API 1)
4. **HD2 Lua Runtime** (`hd2rt` 0.1.0)
5. **Built-in Mod Options Menu** (MOM v3) with 1-based choice indexing, slider step-snapping, and description metadata
6. **Built-in Mod Bindings Menu** (MBM v4) with pure Stingray keyboard and mouse input tracking
7. **Native Escape Menu `MODS` Tab** with 3-column Settings layout and full mouse clicking
8. **Lua 5.2 / Lua 5.3 Polyfill Suite** (`bit32`, `utf8`, `table.pack`, `table.unpack`, `math.type`, `math.tointeger`, `math.ult`, and `goto` transpiler)

---

## Why Universal Mod Loader?

Following Arrowhead's October 2026 engine overhaul (Steam Builds 25988413, 26088801, and 26251122+), LuaJIT (`lua51.dll`), FFI, and audio flow hooks were deleted, and anti-cheat was migrated to Easy Anti-Cheat (EAC EOS).

This caused severe ecosystem fragmentation:
- Old CowboyBingus mods crashed due to compiled LuaJIT bytecode.
- CowboyBingus's `mod_options_menu` and `mod_bindings_menu` failed because they relied on hardcoded `game.dll` memory RVAs and native C++ injection.
- Chef Shared Loader mods failed under Bingus loaders because of incompatible parameter conventions (`local chef = ...`).
- Modern mods written with Lua 5.2 `goto` or Lua 5.3 `utf8`/`bit32` failed on the game's PUC-Rio Lua 5.1 VM.
- Multiple mods deployed across different `.patch_N` slots caused duplication or load-order conflicts.

**Universal Mod Loader solves all of this in one installation.**

---

## Key Features

### 1. Native Escape Menu `MODS` Tab & In-Game Overlay
* **Escape Menu Integration**: Press **Escape** to pause the game, then click the **`MODS [F2]`** tab directly in the top navigation bar alongside native Display, Graphics, and Audio tabs!
* **Authentic 3-Column Settings Layout**:
  - **Left Column**: Categorized mod list (navigate with mouse or `Q`/`E`).
  - **Center Column**: Interactive option controls with toggle switches, value steppers, and choice selectors.
  - **Right Column**: Comprehensive option description and metadata card.
* **Full Mouse Navigation**: Click tabs, categories, toggles, and sliders directly with your mouse pointer with hover highlights and sound feedback.
* **Hotkeys**: Press **`F2`** or **`F9`** anytime during gameplay to toggle the menu overlay directly.

### 2. Multi-Tab Configuration Overlay
* **Tab 1: Mod Options**: Adjust mod settings live in-game. Changes are applied instantly.
* **Tab 2: Key Bindings**: View registered mod hotkeys and rebind them live (`Enter` -> Press any key).
* **Tab 3: Loaded Mods & Diagnostics**: Inspect all active, built-in superseded, and errored mods, their source `patch_N` archives, and diagnostic logs.

### 3. Built-in Mod Bindings Menu (MBM v4) & Input Polyfill
* **No Broken Third-Party Dependency**: Replaces legacy `mod_bindings_menu` natively with zero C++ DLL hooks.
* **Pure Engine Polling**: Uses `stingray.Keyboard` and `stingray.Mouse` to track `is_down`, `is_pressed`, and `poll`.
* **Zero FFI Crashes**: 100% safe from Easy Anti-Cheat and engine updates.

### 4. Lua 5.2 & Lua 5.3 Standard Library Polyfills
* **`bit32` Library**: Complete Lua 5.2 bitwise manipulation library (`arshift`, `band`, `bnot`, `bor`, `btest`, `bxor`, `extract`, `replace`, `lrotate`, `lshift`, `rrotate`, `rshift`).
* **`utf8` Library**: Complete Lua 5.3 Unicode library (`utf8.char`, `utf8.codepoint`, `utf8.codes`, `utf8.len`, `utf8.offset`, and `utf8.charpattern`).
* **Standard Polyfills**: `table.pack`, `table.unpack`, `math.type`, `math.tointeger`, `math.ult`.
* **Lua 5.2 `goto` Transpiler**: Automatically transpiles `goto <label>` and `::<label>::` syntax so modern scripts run cleanly on Lua 5.1.

### 5. Persistent Settings & Keybindings Storage
* Automatically saves options and custom keybindings to `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
* Bi-directionally syncs with legacy `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ModOptionsMenu.values` for total backwards compatibility.

### 6. Patch Deduplication (Highest .patch_N Wins)
* Scans `data/9ba626afa44a3aa3.patch_0..255`.
* If a mod exists in multiple patch files, the highest-numbered patch cleanly overrides older copies without duplicate loading.

### 7. UTF-8 BOM Sanitization & Circuit-Breaker Isolation
* Automatically strips UTF-8 Byte Order Marks (`\xEF\xBB\xBF`) commonly introduced by Windows text editors.
* Circuit-breaker fault isolation catches broken third-party scripts without crashing the engine to desktop.

---

## Installation

### Method A: Mod Manager (Recommended)
1. Download `Helldivers2-Universal-Mod-Loader-v22.0.0.zip`.
2. Import the archive into **HD2 Mod Manager** or your preferred mod manager.
3. Deploy your mods.

### Method B: Manual Install
1. Extract `data/9ba626afa44a3aa3.patch_0` (along with `.stream` and `.gpu_resources`) from the ZIP.
2. If another mod uses `patch_0`, rename it to any free slot (e.g. `patch_47`).
3. Place all 3 files in:
   `<SteamLibrary>\steamapps\common\Helldivers 2\data\`

---

## Diagnostic Logs & Settings Locations
* **Settings**: `%LOCALAPPDATA%\UniversalModLoader\settings.json`
* **Logs**: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log`

---

## License
Zero-Clause BSD (0BSD) - 100% Free & Open Source.
