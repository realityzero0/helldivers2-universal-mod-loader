# Helldivers 2 Universal Mod Loader (v1.0.1)

[![Nexus Mods](https://img.shields.io/badge/Nexus_Mods-Mod_18527-orange?logo=nexusmods)](https://www.nexusmods.com/helldivers2/mods/18527)
[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Steam%20Build%2026251122%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)
[![Pure Lua 5.1](https://img.shields.io/badge/Engine-Pure%20Lua%205.1-yellow.svg)](https://www.lua.org/)
[![Anti-Cheat Safe](https://img.shields.io/badge/EAC-100%25%20Safe%20(Zero%20FFI)-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is the definitive, all-in-one engine boot loader for *Helldivers 2*. It seamlessly executes mods built for **any** mod loader standard without requiring users to track down, install, or juggle multiple conflicting loaders.

* **Nexus Mods:** [https://www.nexusmods.com/helldivers2/mods/18527](https://www.nexusmods.com/helldivers2/mods/18527)
* **GitHub Repository:** [https://github.com/realityzero0/helldivers2-universal-mod-loader](https://github.com/realityzero0/helldivers2-universal-mod-loader)

---

## What Does Universal Mod Loader Do?

Traditionally in *Helldivers 2*, different mod creators designed mods for different loader frameworks:
- Some mods require **CowboyBingus Mod Loader** (API 1, `BingusRuntime`, `open_log`, `on_update`, `on_shutdown`, `after_startup`).
- Some mods require **Chef Shared Loader** (API Levels 1, 2, and 3 with `chef` parameter injection).
- Some mods require **Boot Mod Loader** (`BootModLoader.hook`, VeganSquid standard).
- Some mods require **HD2 Lua Runtime** (`hd2rt` / `hd2runtime` 0.1.0).
- Many mods depend on **Mod Options Menu (MOM)** or **Mod Bindings Menu (MBM)** to register user settings and hotkeys.

If a player installed mods from different authors, they previously experienced silent load failures, missing dependencies, or crash-to-desktop errors.

**Universal Mod Loader completely replaces all of them with a single, unified, crash-proof loader.** You only install Universal Mod Loader, and every mod loads automatically.

---

## Key Features & Compatibility

### 1. Full Multi-Standard Runtime Compatibility
* **CowboyBingus Mod Loader**: Full API 1 implementation, `BingusRuntime` v1 with canonical `guard()` lifecycle error isolation, `open_log()`, `on_update()`, `on_shutdown()`, and `after_startup()` queues.
* **Chef Shared Loader**: Complete API Levels 1, 2, and 3 emulation with event dispatching, shared state, and cooperative handoff.
* **Boot Mod Loader**: Full VeganSquid API 1 support (`BootModLoader.hook()` and `hooks` registry).
* **HD2 Lua Runtime**: Complete `hd2rt` and `hd2runtime` 0.1.0 event dispatcher (`on`, `emit`, `register_mod`).

### 2. Built-in Mod Options & Bindings Polymorphic Stubs
* **ModOptionsMenu**: Full registration, retrieval (`get`/`set`), and `on_change` callback notification. Dependent mods can safely register settings and default values without failing.
* **ModBindingsMenu & Live Stingray Key Polling**: Full hotkey registration and active Stingray `Keyboard.button` / `Keyboard.pressed` / `Keyboard.released` input polling. Hotkeys registered by mods (such as HUD toggles) work directly through the engine!

### 3. Circuit-Breaker Fault Isolation
* Individual mod scripts are wrapped inside protected call (`pcall`) boundaries.
* If a mod contains a syntax typo or runtime error, Universal Mod Loader logs the failure and safely isolates it, preventing the mod from crashing the game to desktop or breaking other active mods.
* If a mod's update hook encounters 10 consecutive frame errors, the circuit breaker safely unregisters that hook while keeping Helldivers 2 and all other mods running smoothly.

### 4. 100% Pure Lua 5.1 & Anti-Cheat Safe
* Strict PUC-Rio Lua 5.1 compliance.
* Zero native Windows FFI memory tampering, zero `GetModuleHandle` probing, zero `os.execute` child process spawning, and zero native DLL injection.
* Complies fully with game update anti-cheat environments (Easy Anti-Cheat / EAC EOS).

### 5. Multi-Path Scanning (Up to 256 Patches) & Loose Mod Loading
* Automatically discovers and loads mods across `data/` and `../data/` up to `patch_256`.
* Permits loading loose scripts directly from `<GameDir>/mods/` or `%LOCALAPPDATA%/UniversalModLoader/mods/`.

### 6. Standard Bitwise & UTF-8 Polyfills
* Embedded 32-bit signed bitwise LUT engine (`bit` and `bit32` libraries: `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`, `arshift`, `rol`, `ror`).
* Embedded pure-Lua `utf8` standard library (`len`, `char`, `codepoint`).

---

## Installation

### Method A: Arsenal Mod Manager (Recommended)
1. Drag and drop `Helldivers2-Universal-Mod-Loader-v1.0.1.zip` into **Arsenal Mod Manager**.
2. Ensure Universal Mod Loader is placed at the top of your loadout (Position 1 / lowest patch number, e.g., `patch_0`).
3. Deploy your mods and launch Helldivers 2.

### Method B: Manual Installation
1. Navigate to your Helldivers 2 data directory:
   `<SteamLibrary>\steamapps\common\Helldivers 2\data\`
2. Copy the following files into the `data/` folder:
   - `9ba626afa44a3aa3.patch_0`
   - `9ba626afa44a3aa3.patch_0.stream`
   - `9ba626afa44a3aa3.patch_0.gpu_resources`
3. Launch Helldivers 2.

---

## Uninstallation
Disable in your mod manager, or delete `9ba626afa44a3aa3.patch_0*` from `<SteamLibrary>\steamapps\common\Helldivers 2\data\`.

---

## Diagnostics & Logging
Execution status and mod loading diagnostics are logged directly to:
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log`

---

## License
Zero-Clause BSD (0BSD) — Completely free and open source.
