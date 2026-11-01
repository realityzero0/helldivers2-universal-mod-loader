Supports Steam builds 25988413, 26088801, and 26251122+ (EAC EOS Overhaul).

Helldivers 2 Universal Mod Loader - v1.0.0 (Unified Pure-Lua 5.1 Infrastructure)

Unifies all Helldivers 2 modding standards into a single engine boot loader:
  1. CowboyBingus Mod Loader (API 1, Version 17, BingusRuntime v1, on_update, on_shutdown, after_startup)
  2. Chef Shared Loader (API Levels 1, 2, 3, HD2-Addon, HD2-Boot, HD2-Options, cooperative handoff)
  3. Boot Mod Loader (VeganSquid API 1)
  4. HD2 Lua Runtime (hd2rt / 0.1.0)
  5. Built-in Mod Options Menu (MOM v3) with 1-based choice indexing, slider snapping, & localization callables
  6. Built-in Mod Bindings Menu (MBM v4) with Stingray button_id/button_index polyfill & boolean/numeric polling
  7. Native Escape-Menu MODS Tab with 3-column Settings layout and full mouse navigation
  8. Dynamic Live Mod Loading & In-Game Hot-Reload (load loose .lua mods from mods/ without restarting)
  9. Live Mod Management: Enable or Disable mods on the fly with Space/Enter directly in the ESC menu
 10. Real-Time Frame Profiler: Live millisecond CPU cost tracking per mod & Lua heap memory monitor
 11. Lua 5.2 & Lua 5.3 Polyfill Suite (bit32, utf8, table.pack/unpack, math.type/tointeger, and goto transpiler)

Features in v1.0.0:
- Versioning Reset to v1.0.0: Clean semantic versioning for the standalone unified mod loader project.
- Dynamic Live Mod Loading:
  - Drop loose .lua scripts into `mods/` or `%LOCALAPPDATA%/UniversalModLoader/mods/` to run without packing into archives!
  - Click [R] RELOAD ALL in the ESC menu (or press 'R') to hot-reload all mods live without restarting Helldivers 2!
  - Picks up newly deployed patch archives from Arsenal Mod Manager live while in your ship or in the pause menu!
- Live Mod Enable / Disable Toggles:
  - Toggle any mod active or inactive on the fly in Tab 3 (Loaded Mods) with Space / Enter or mouse click.
  - Disabled mods immediately stop executing update hooks and keybindings, saving CPU frame time.
  - Disabled state persists across game sessions in %LOCALAPPDATA%/UniversalModLoader/settings.json.
- Real-Time Frame Profiler & Memory Monitor:
  - Tracks execution cost per frame in milliseconds (rolling exponential moving average) for each mod.
  - Displays individual mod CPU time in the mod list and details pane to detect laggy scripts.
  - Monitors total Lua heap allocation (KB) and total mod frame time at a glance.
- Native Escape Menu "MODS" Tab: Click MODS [F2] in the top navigation bar of the pause menu alongside Display/Graphics!
- Authentic 3-Column Settings Layout: Categories (left), Controls (center), and Option Descriptions (right).
- Full Mouse Support: Click tabs, categories, toggles, and sliders directly with mouse pointer and hover feedback.
- Interactive 3-Tab Overlay (F2 / F9):
  - Tab 1: Mod Options (adjust toggles/sliders/choices and read full option descriptions).
  - Tab 2: Key Bindings (rebind any mod hotkey live in-game with key press indicator).
  - Tab 3: Loaded Mods & Diagnostics (inspect all active, loose, superseded, and errored mods).
- Lua 5.2/5.3 Standard Polyfills: bit32 and utf8 standard libraries built-in; runs modern mods cleanly on Lua 5.1.
- Built-in Mod Options (MOM v3) & Mod Bindings (MBM v4): Replaces legacy standalone mods with zero DLL hooks.
- Persistent Settings & Bindings: Automatically saves to %LOCALAPPDATA%/UniversalModLoader/settings.json.
- Patch Deduplication: Emulates Stingray priority rules across patch_0..255 (highest .patch_N cleanly executes).
- UTF-8 BOM Stripping: Automatically removes \xEF\xBB\xBF byte order marks from Windows text editors.
- Circuit-Breaker Fault Isolation: Protects against game crashes by catching broken third-party syntax in safe sandboxes.
- EAC Safe & Pure Lua 5.1: Zero native DLL injection, zero executable memory patching, zero FFI crashes.

Installation:
- Mod Manager (Arsenal Mod Manager / HD2MM): Drag and drop Helldivers2-Universal-Mod-Loader-v1.0.0.zip into your mod manager and deploy.
- Manual: Extract data/9ba626afa44a3aa3.patch_0 (and .stream, .gpu_resources) into Helldivers 2/data/.

Logs: %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log
Settings: %LOCALAPPDATA%/UniversalModLoader/settings.json
Loose Mods: <GameDir>/mods/ or %LOCALAPPDATA%/UniversalModLoader/mods/
License: Zero-Clause BSD (0BSD) - 100% Free & Open Source
