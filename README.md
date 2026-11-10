# Helldivers 2 Universal Mod Loader (v2.0.0)

[![Nexus Mods](https://img.shields.io/badge/Nexus_Mods-Mod_18527-orange?logo=nexusmods)](https://www.nexusmods.com/helldivers2/mods/18527)
[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Steam%20Build%2026251122%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)
[![Pure Lua 5.1](https://img.shields.io/badge/Engine-Pure%20Lua%205.1-yellow.svg)](https://www.lua.org/)
[![Anti-Cheat Safe](https://img.shields.io/badge/EAC-100%25%20Safe%20(Zero%20FFI)-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is the definitive, indestructible engine runtime for *Helldivers 2*. It seamlessly executes mods built for **any** post-EAC mod loader standard without requiring users to track down, install, or juggle multiple conflicting loaders.

* **Nexus Mods:** [https://www.nexusmods.com/helldivers2/mods/18527](https://www.nexusmods.com/helldivers2/mods/18527)
* **GitHub Repository:** [https://github.com/realityzero0/helldivers2-universal-mod-loader](https://github.com/realityzero0/helldivers2-universal-mod-loader)
* **License:** Zero-Clause BSD (0BSD) — 100% Free, Public Domain Equivalent, and Open Source forever.

---

## 🌟 Key Features in v2.0.0

* **True Multi-Standard Unification:**
  * **CowboyBingus Mod Loader** (API 1, Version 17, BingusRuntime v1, `on_update`, `on_shutdown`, `after_startup`)
  * **Chef Shared Loader** (API Levels 1, 2, 3, `HD2-Addon`, `HD2-Boot`, `HD2-Options`) with native vararg injection
  * **Boot Mod Loader** (VeganSquid API 1)
  * **HD2 Lua Runtime** (`hd2rt` / 0.1.0)
  * **Rat's Shared Loader** (Armor Transmog 1.1.2 ABI & hooks)
  * **Native `UML` v2.0.0 Developer API** (`UML.register`, `:option`, `:bind_key`, `:on_update`, `:notify`, Event Bus)
* **Crash-Proof 2-Pane Per-Mod Submenu Settings UI (`F9`):**
  * **Left Mod Sidebar + Right Options Submenu:** Organizes options cleanly per mod (`1`–`9` direct mod quick-jump, `[`/`]` mod cycling, `Right`/`Backspace`/`Tab` pane focus, Mouse Wheel scrolling).
  * **Dynamic Viewport Scaling & Description Panel:** Dynamically scales font size, row heights, and items per page (`Auto`, `Compact`, `Medium`, `Large`) with live `[-]` and `[=]` hotkeys, plus a 3-line word-wrapped option description panel.
  * **Automatic 14-Locale Language Detection:** Automatically detects game language via in-game configs, live Steamworks API (`stingray.Steam.language()`), Steam appmanifest, or Windows OS locale, with UTF-8 diacritic & Cyrillic transliteration.
  * **100% Crash-Proof 5x7 Pixel Bitmap Font Renderer:** Renders crisp vector-free text using pure `Gui.rect` calls across all active Stingray worlds with zero dependency on unloaded font assets.
  * **Persistent JSON Storage:** Automatically saves user options to `%APPDATA%/Arrowhead/Helldivers2/uml_mod_settings.json` (or `%LOCALAPPDATA%/UniversalModLoader/uml_mod_settings.json`) while bi-directionally syncing with `ModOptionsMenu.values`.
* **Zero PC Freezes (Hang Watchdog):**
  * Real-time `debug.sethook` 3.0s watchdog that intercepts runaway loops and aborts them cleanly without freezing the game window.
* **Pure-Lua Fake DLL Bridge & FFI ABI Emulator:**
  * Intercepts legacy `package.loadlib` calls and `ffi.sizeof` / `BCrypt` struct queries, returning safe mock interfaces that prevent native Win32 crashes or anti-cheat triggers.
* **Crash Sentinel & Auto-Safe Mode:**
  * Detects unmanaged C++ engine crashes on previous launches and auto-quarantines the faulty mod to guarantee the game always boots.
* **Chat & Window Focus Guard:**
  * Verifies window focus (`Window.has_focus()`) and multiplayer chat prompt states (`Enter`/`Esc`) before polling mod hotkeys, preventing accidental key activations while typing.
* **Topological Dependency Sorter (DAG) & Rogue Guest Boot Shield:**
  * Resolves `-- HD2-Requires:` / `needs` prerequisites before dependents and neutralizes conflicting secondary `0xF476DF93691895FA` boot resources.
* **Automatic Log Rotation & Live Hot-Reloading (`Ctrl+F5`):**
  * Automatically rotates `UniversalModLoader.log` to `.log.old` when exceeding 5 MB and reloads loose scripts from `<GameDir>/mods/` instantly.

---

## 🚀 Installation

### Using Arsenal Mod Manager / HD2MM (Recommended)
1. Download `Helldivers2-Universal-Mod-Loader-v2.0.0.zip`.
2. Drag and drop the archive directly into your mod manager.
3. Place **Universal Mod Loader in Position 1** (`patch_0`).
4. Deploy and launch Helldivers 2. Press **F9** in-game to access settings!

### Manual Installation
1. Extract `data/9ba626afa44a3aa3.patch_0` (along with `.stream` and `.gpu_resources`) from the zip.
2. Copy them into your Helldivers 2 data directory:
   ```text
   Steam\steamapps\common\Helldivers 2\data\
   ```
3. Launch the game via Steam.

---

## 🔍 How to Find Your Logs (For Bug Reporting)
If a mod breaks, fails to load, or you encounter unexpected behavior, grab your log file before submitting a ticket. Universal Mod Loader writes all diagnostics and mod errors to:

* **Primary Path:**
  ```text
  %APPDATA%\Arrowhead\Helldivers2\UniversalModLoader.log
  ```
* **Local AppData Fallback:**
  ```text
  %LOCALAPPDATA%\UniversalModLoader\UniversalModLoader.log
  ```
*(Press `Win + R`, paste either path above into the box, and press `Enter` to view your log).*

---

## 📚 Documentation & Developer Guides
* [Modding API Developer Reference](docs/MODDING_API.md) — Create custom Helldivers 2 mods with F9 options, hotkeys, and event hooks in 60 seconds.
* [Frequently Asked Questions (FAQ)](docs/FAQ.md) — Compatibility, Easy Anti-Cheat safety, MDL3, and troubleshooting.
* [Community Compatibility Registry](docs/COMPATIBILITY.md) — Live catalog of verified mods (open for community reports).
* [Bug & Troubleshooting Guide](docs/REPORTING_GUIDE.md) — How to submit logs and report broken mods.
* [Detailed Changelog](CHANGELOG.md) — Complete release history and technical analyses.
