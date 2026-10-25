# Helldivers 2 Universal Mod Loader (v22.0.0)

[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Build%2025988413%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is a unified, pure-Lua 5.1 engine boot loader for *Helldivers 2*. It combines all major modding ecosystems into a single, cohesive runtime:

1. **CowboyBingus Mod Loader** (API 1, Version 17, `BingusRuntime` v1, `on_update`, `on_shutdown`, `after_startup`)
2. **Chef Shared Loader** (API Levels 1, 2, 3, `HD2-Addon`, `HD2-Boot`, `HD2-Options`)
3. **Boot Mod Loader** (VeganSquid API 1)
4. **HD2 Lua Runtime** (`hd2rt` 0.1.0)
5. **Built-in Mod Options Menu** (MOM v2)
6. **Built-in Mod Bindings Menu** (MBM v4) with pure Stingray keyboard and mouse input tracking

---

## Why Universal Mod Loader?

Following Arrowhead's October 2026 engine overhaul (Steam Builds 25988413 & 26088801+), LuaJIT (`lua51.dll`), FFI, and audio flow hooks were deleted from the game. 

This caused catastrophic ecosystem fragmentation:
- Old CowboyBingus mods crashed due to compiled LuaJIT bytecode.
- CowboyBingus's `mod_options_menu` and `mod_bindings_menu` failed because they relied on hardcoded `game.dll` memory RVAs and native C++ injection.
- Chef Shared Loader mods failed under Bingus loaders because of incompatible parameter conventions (`local chef = ...`).
- Multiple mods deployed in different `.patch_N` slots had no deduplication.

**Universal Mod Loader solves all of this in one installation.**

---

## Key Features

### 1. Built-in Mod Bindings Menu (MBM v4)
* **No Broken Third-Party Dependency**: CowboyBingus's original `mod_bindings_menu` is obsolete. Universal Mod Loader provides `_G.ModBindingsMenu` natively.
* **Pure Engine Polling**: Uses `stingray.Keyboard` and `stingray.Mouse` to track `is_down(id)`, `is_pressed(id)`, and `poll(ids, out)`.
* **Zero FFI Crashes**: Completely safe from anti-cheat and engine updates.

### 2. Multi-Tab In-Game Overlay (`F2` / `F9`)
* Press **`F2`** or **`F9`** anytime in-game to open the configuration overlay:
  * **Tab 1: Mod Options**: Toggle booleans, adjust sliders/numbers, and cycle option choices with `Up`/`Down`/`Enter`/`Left`/`Right`.
  * **Tab 2: Key Bindings**: View all registered mod hotkeys and rebind them live in-game (`Enter` -> Press any key).
* Press **`Tab`** to switch between tabs.

### 3. Persistent Settings & Keybindings Storage
* Automatically saves options and custom keybindings to `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
* Settings are preserved across game updates and restarts.

### 4. Patch Deduplication (Highest .patch_N Wins)
* Scans `data/9ba626afa44a3aa3.patch_0..255`.
* If a mod exists in multiple patch files, the highest-numbered patch cleanly overrides older copies without duplicate loading.

### 5. UTF-8 BOM Sanitization
* Automatically strips UTF-8 Byte Order Marks (`\xEF\xBB\xBF`) commonly introduced by Windows text editors, preventing Lua 5.1 syntax errors.

### 6. Cooperative Chef Handoff
* If Chef Shared Loader is installed in a higher patch slot, Universal Mod Loader yields boot execution gracefully to `mods/chef_shared_loader/core_1`, eliminating load-order conflicts.

---

## Installation

### Via Mod Manager (Recommended)
1. Download `Helldivers2-Universal-Mod-Loader-v22.0.0.zip`.
2. Import the archive into **HD2 Mod Manager** or **HDArsenal**.
3. Set the load priority to the default base slot (`patch_0`).
4. Click **Deploy / Apply Mods**.

### Manual Installation
Extract the contents of `data/` directly into your Helldivers 2 installation directory:
```text
<SteamLibrary>/steamapps/common/Helldivers 2/data/
  ├── 9ba626afa44a3aa3.patch_0
  ├── 9ba626afa44a3aa3.patch_0.stream
  └── 9ba626afa44a3aa3.patch_0.gpu_resources
```

---

## License & Credits
* Released under the **Zero-Clause BSD License (0BSD)** — free to use, modify, and redistribute without conditions.
* Builds upon the foundations of [CowboyBingus](https://github.com/CowboyBingus/BingusSharedLoader), [Th3chef](https://github.com/Th3chef/Chef-Shared-Loader), and the Helldivers 2 modding community.
