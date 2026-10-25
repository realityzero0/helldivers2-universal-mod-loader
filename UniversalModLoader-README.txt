Supports Steam builds 25988413 (EXE 1.8.46539.0) & 26088801+ (EXE 1.8.46659.0).

Helldivers 2 Universal Mod Loader - v22.0.0 (Unified Pure-Lua 5.1 Infrastructure)

Unifies all four Helldivers 2 modding standards into a single engine boot loader:
  1. CowboyBingus Mod Loader (API 1, Version 17, BingusRuntime v1, on_update, on_shutdown, after_startup)
  2. Chef Shared Loader (API Levels 1, 2, 3, HD2-Addon, HD2-Boot, HD2-Options, cooperative handoff)
  3. Boot Mod Loader (VeganSquid API 1)
  4. HD2 Lua Runtime (hd2rt / 0.1.0)
  5. Built-in Mod Options Menu (MOM v2)
  6. Built-in Mod Bindings Menu (MBM v4) with pure Stingray Keyboard/Mouse input polling

Features in v22.0.0:
- Built-in Mod Bindings Menu (MBM): Erases the need for the broken third-party mod_bindings_menu mod.
  Provides native key state tracking (down, pressed, released, poll) using pure Stingray engine calls.
- Persistent Settings & Bindings: Automatically saves mod options and keybinds to
  %LOCALAPPDATA%/UniversalModLoader/settings.json, persisting player settings across sessions.
- Interactive Multi-Tab In-Game Overlay (F2 / F9):
  - Tab 1: Mod Options (adjust booleans, numbers, choices with Up/Down/Left/Right/Enter/Space).
  - Tab 2: Key Bindings (view all registered mod hotkeys and rebind them live in-game).
- Patch Deduplication: Emulates Stingray priority rules across patch_0..255. When multiple archives
  contain the same mod identifier, the highest-numbered patch cleanly executes.
- UTF-8 BOM Stripping: Automatically removes \xEF\xBB\xBF byte order marks from Windows text editors.
- Circuit-Breaker Fault Isolation: Protects against game crashes by catching broken third-party syntax
  or runtime errors in safe sandboxes.
- EAC Safe & Pure Lua 5.1: Zero native DLL injection, zero executable memory patching, zero FFI crashes.

Installation:
- Mod Manager: Import archive into HD2 Mod Manager or HDArsenal, set to patch_0, and deploy.
- Manual: Extract data/9ba626afa44a3aa3.patch_0 (and .stream, .gpu_resources) into Helldivers 2/data/.

Logs: %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log
Settings: %LOCALAPPDATA%/UniversalModLoader/settings.json
License: Zero-Clause BSD (0BSD) - 100% Free & Open Source
