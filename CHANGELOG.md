# Changelog - Helldivers 2 Universal Mod Loader

All notable changes to the **Helldivers 2 Universal Mod Loader** project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [22.0.0] - 2026-10-30

### Initial Unified Release
- **Unified 4-Way Standard Emulation**:
  - Full compatibility layer for CowboyBingus Mod Loader (`api=1`, `version=17`, `revision="loader-v22.0.0"`, `after_startup` returning `true`, `.modules`, `.register_module`, `.register_addon`, `.health`, `.build`, `.jit`, and full `BingusRuntime` v1 with dual-mode `guard` and callable `shared`).
  - Full compatibility layer for Chef Shared Loader (`api_level=3`, `HD2-Addon`, `HD2-Boot`, `HD2-Options`).
  - Full compatibility layer for Boot Mod Loader (`_G.BootModLoader` API 1).
  - Full compatibility layer for HD2 Lua Runtime (`_G.hd2rt` 0.1.0).
- **Built-in Mod Options Menu (`MOM v3`) & Legacy Settings Migration**:
  - Upgraded to `version=3`, `max_mods=112`, `max_options=256`, with multi-listener `on_change(id, fn)` callback lists.
  - Automatically imports and syncs legacy `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ModOptionsMenu.values` alongside `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
  - Full contract compliance with 1-based choice integer indexing (`1 .. #spec.choices`), human-readable UI label rendering, callable localization resolution, and slider step snapping (`min`, `max`, `step`).
- **Built-in Mod Bindings Menu (`MBM v4`) & Authentic Stingray Input Compatibility**:
  - Native pure-Lua implementation of `ModBindingsMenu` (`version=4`, `.extended` metadata, `is_down`/`down`, `is_pressed`/`was_pressed`/`pressed`, `is_released`/`was_released`/`released`, `poll`, `binding`/`get_binding`, `set_binding`, `reset_binding`).
  - Automatic Stingray `Keyboard`/`Mouse`/`Pad1..4` `button_id` <-> `button_index` bidirectional polyfill and boolean (`true`) + numeric (`> 0`) return-value handling.
  - Pre-frame `_G.update` master wrapper ensuring single-frame edge-triggered key states are updated before both `_G.update` wrapper mods and `on_update` hook mods.
- **Universal Discovery, Sub-Module Ordering, & Lua 5.1/5.2 Compatibility**:
  - Multi-path `data` directory resolution (`data`, `../data`, `../../data`, and `package.path` roots).
  - 64-bit MurmurHash64A resource-ID lookup (`KNOWN_HASH_TO_NAME`), on-demand `package.preload` + `stingray.Application.can_get("lua", ...)` integration, preset resource handling (`mods/reticle_ammo/preset_*`), and automatic parent/sub-module load ordering (`<parent>_*` before `<parent>`).
  - Automatic single-line Lua 5.2 `if <cond> then goto <label> end ... ::<label>::` transpiler for Helldivers 2's PUC-Rio Lua 5.1.4 VM.
  - 64-bit safe mock pointer arithmetic (preserving addresses `>= 2^32` such as `0x180000000` and `0x140000000`) and synthetic x64 PE32+ headers (`TimeDateStamp`, `SizeOfImage`, `CheckSum`) for `game.dll` and `helldivers2.exe`.
- **Retained Stingray Screen-GUI & 3-Tab In-Game Mod UI (`F2` / `F9`)**:
  - Built on real Stingray retained Screen-GUI APIs (`World.create_screen_gui(ui_world, "scale", 1, 1)`, `core/performance_hud/debug`, bottom-up `Vector3`/`Vector2`/`Color`, `Gui.destroy_rect`, `Gui.destroy_text`, `World.destroy_gui`) with dirty-signature caching and 1080p resolution scaling.
  - `Tab 1: Mod Options`: Per-mod category filtering (`Q`/`E` or `PgUp`/`PgDn`), interactive toggle/slider/choice controls (`Left`/`Right`/`Enter`), reset-to-default (`Backspace`), and a word-wrapped **Option Details & Description Panel**.
  - `Tab 2: Key Bindings`: Interactive key rebinding (`Enter`/`Space`), clear (`Delete`), cancel (`Escape`), reset-to-default (`Backspace`), and live key press state badge.
  - `Tab 3: Loaded Mods & Diagnostics`: Scrollable inspector for all active, built-in superseded, and errored mods with archive source (`patch_N`) and detailed status diagnostics.
- **Persistent Settings & Keybindings Storage**:
  - Pure-Lua JSON codec saving options and keybinds to `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
- **Patch Deduplication**:
  - Automatically deduplicates entries across `data/9ba626afa44a3aa3.patch_0..255`.
  - When the same mod exists in multiple archives, the highest-numbered patch cleanly executes.
- **UTF-8 BOM Stripping & Fault-Isolated Execution**:
  - Automatically strips Windows UTF-8 Byte Order Marks (`\xEF\xBB\xBF`).
  - Individual mod errors are caught and logged without crashing the engine; circuit-breaker disables runaway update hooks after 20 errors.
- **Hardened Lua 5.1 & Mock FFI Primitives**:
  - Preserves native `ffi` and `bit` if provided by the host VM while falling back to a 4-bit LUT bitwise library and enhanced mock FFI layer (`ffi.cast` function preservation, `ffi.sizeof` struct/buffer sizing, `GetProcAddress`, `GetModuleFileNameW`, `QueryPerformanceCounter`/`Frequency`, and metatable-aware `_G.tonumber`).
