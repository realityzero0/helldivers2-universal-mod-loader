# Helldivers 2 Universal Mod Loader (v2.0.0)

[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](../LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Build%2026251122%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

**Universal Mod Loader** is a unified, pure-Lua 5.1 engine boot loader for *Helldivers 2*. It combines all major modding ecosystems into a single, cohesive runtime:

1. **CowboyBingus Mod Loader** (API 1, Version 17, `BingusRuntime` v1, `on_update`, `on_shutdown`, `after_startup`)
2. **Chef Shared Loader** (API Levels 1, 2, 3, `HD2-Addon`, `HD2-Boot`, `HD2-Options`)
3. **Boot Mod Loader** (VeganSquid API 1)
4. **HD2 Lua Runtime** (`hd2rt` 0.1.0)
5. **Rat's Shared Loader** (Armor Transmog 1.1.2 ABI & hooks)
6. **Built-in Mod Options Menu** (MOM v3) with 1-based choice indexing, slider step-snapping, and description metadata
7. **Built-in Mod Bindings Menu** (MBM v4) with pure Stingray keyboard and mouse input tracking
8. **2-Pane Per-Mod Submenu In-Game UI (`F9`)** rendered via a 100% crash-proof 5x7 pixel bitmap font (`Gui.rect`)
9. **Lua 5.2 / Lua 5.3 Polyfill Suite** (`bit32`, `utf8`, `table.pack`, `table.unpack`, `math.type`, `math.tointeger`, `math.ult`, and `goto` transpiler)

---

## Documentation Index

* **[Compatibility Matrix & Verified Mods (`COMPATIBILITY.md`)](COMPATIBILITY.md)** — Live compatibility table of verified mods, automated 60/90-day lifecycle tracking rules, and the Native `UML` v2.0.0 Developer API quickstart.
* **[Mod Issue & Stewardship Reporting Guide (`REPORTING_GUIDE.md`)](REPORTING_GUIDE.md)** — How to report broken mods, request community patches, and use diagnostic logs.

---

## Diagnostic Logs & Settings Locations
* **Persistent JSON Settings**: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\uml_mod_settings.json`
* **Legacy Settings Sync**: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ModOptionsMenu.values`
* **Diagnostic Logs**: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log`
