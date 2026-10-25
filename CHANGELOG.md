# Changelog - Helldivers 2 Universal Mod Loader

All notable changes to the **Helldivers 2 Universal Mod Loader** project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [22.0.0] - 2026-10-25

### Initial Unified Release
- **Unified 4-Way Standard Emulation**:
  - Full compatibility layer for CowboyBingus Mod Loader (`api=1`, `version=17`, `revision="loader-v22.0.0"`).
  - Full compatibility layer for Chef Shared Loader (`api_level=3`, `HD2-Addon`, `HD2-Boot`, `HD2-Options`).
  - Full compatibility layer for Boot Mod Loader (`_G.BootModLoader` API 1).
  - Full compatibility layer for HD2 Lua Runtime (`_G.hd2rt` 0.1.0).
- **Built-in Mod Bindings Menu (MBM v4)**:
  - Native pure-Lua implementation of `ModBindingsMenu` using `stingray.Keyboard` and `stingray.Mouse`.
  - Deprecates and replaces CowboyBingus's broken C++ memory injection mod.
  - Per-frame input state tracking (`is_down`, `is_pressed`, `poll`).
- **Built-in Mod Options Menu (MOM v2)**:
  - Drop-in in-engine configuration system for all registered mod options.
- **Persistent Settings & Keybindings Storage**:
  - Pure-Lua JSON codec saving options and keybinds to `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
- **Interactive Multi-Tab In-Game Overlay (`F2` / `F9`)**:
  - `Tab 1: Mod Options`: Configure booleans, numbers, and choices live in-game.
  - `Tab 2: Key Bindings`: Live key remapping interface with key capture and clear.
  - `Tab` switches between tabs; `Up`/`Down`/`Enter`/`Left`/`Right` navigate and adjust values.
- **Patch Deduplication**:
  - Automatically deduplicates entries across `data/9ba626afa44a3aa3.patch_0..255`.
  - When the same mod exists in multiple archives, the highest-numbered patch cleanly executes.
- **UTF-8 BOM Stripping**:
  - Automatically strips Windows UTF-8 Byte Order Marks (`\xEF\xBB\xBF`) preventing Lua 5.1 syntax errors.
- **Fault-Isolated Execution**:
  - Individual mod errors are caught and logged without crashing the engine.
  - Circuit-breaker disables runaway update hooks after 20 errors.
- **Hardened Lua 5.1 Primitives**:
  - High-performance 4-bit LUT bitwise library with exact C-style signed 32-bit truncation.
  - Mock pointer arithmetic metamethods (`__add`, `__sub`, `__eq`, `__lt`, `__le`).
  - Safeguarded global string metatable preserving all standard Lua 5.1 string library methods.
  - Defensive `get_app()` resolver.
