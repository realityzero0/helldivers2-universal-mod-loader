# Changelog - Helldivers 2 Universal Mod Loader

All notable changes to the **Helldivers 2 Universal Mod Loader** project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [22.0.0] - 2026-10-31

### Unified Mod Loader Release
- **Unified 4-Way Standard Emulation**:
  - Full compatibility layer for CowboyBingus Mod Loader (`api=1`, `version=17`, `revision="loader-v22.0.0"`, `after_startup` returning `true`, `.modules`, `.register_module`, `.register_addon`, `.health`, `.build`, `.jit`, and full `BingusRuntime` v1 with dual-mode `guard` and callable `shared`).
  - Full compatibility layer for Chef Shared Loader (`api_level=3`, `HD2-Addon`, `HD2-Boot`, `HD2-Options`).
  - Full compatibility layer for Boot Mod Loader (`_G.BootModLoader` API 1).
  - Full compatibility layer for HD2 Lua Runtime (`_G.hd2rt` 0.1.0).
- **Escape Menu `MODS` Tab & 3-Column Settings UI with Mouse Support**:
  - Native top-bar `MODS [F2]` tab integrated into the in-game Pause/Escape menu, positioned cleanly alongside native Display, Graphics, and Audio tabs.
  - Authentic 3-column Helldivers 2 Settings layout: Left column (Categories), Center column (Interactive Options / Controls), Right column (Detailed Description & Metadata Card).
  - Full mouse navigation: Click any tab, category, toggle, slider, or choice button directly with the mouse pointer, complete with hover highlights and interactive sound triggers.
  - Keyboard & Gamepad fallback: Retains intuitive `F2`/`F9` hotkeys, arrow navigation, and tab switching.
- **Lua 5.2 & Lua 5.3 Standard Library Polyfills**:
  - Built-in `bit32` library providing full standard Lua 5.2 bitwise operations (`arshift`, `band`, `bnot`, `bor`, `btest`, `bxor`, `extract`, `replace`, `lrotate`, `lshift`, `rrotate`, `rshift`).
  - Built-in `utf8` library providing full standard Lua 5.3 Unicode operations (`utf8.char`, `utf8.codepoint`, `utf8.codes`, `utf8.len`, `utf8.offset`, and `utf8.charpattern`).
  - Extended standard table and math polyfills: `table.pack`, `table.unpack`, `math.type`, `math.tointeger`, `math.ult`, and `math.maxinteger`/`mininteger`.
  - Automatic transpiler for Lua 5.2 `goto` and `::<label>::` label syntax for PUC-Rio Lua 5.1.4 VM compatibility.
- **Built-in Mod Options Menu (`MOM v3`) & Legacy Settings Migration**:
  - Upgraded to `version=3`, `max_mods=112`, `max_options=256`, with multi-listener `on_change(id, fn)` callback lists.
  - Automatically imports and syncs legacy `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ModOptionsMenu.values` alongside `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
  - Full contract compliance with 1-based choice integer indexing (`1 .. #spec.choices`), human-readable UI label rendering, callable localization resolution, and slider step snapping (`min`, `max`, `step`).
- **Built-in Mod Bindings Menu (`MBM v4`) & Authentic Stingray Input Compatibility**:
  - Native pure-Lua implementation of `ModBindingsMenu` (`version=4`, `.extended` metadata, `is_down`/`down`, `is_pressed`/`was_pressed`/`pressed`, `is_released`/`was_released`/`released`, `poll`, `binding`/`get_binding`, `set_binding`, `reset_binding`).
  - Automatic Stingray `Keyboard`/`Mouse`/`Pad1..4` `button_id` <-> `button_index` bidirectional polyfill and boolean (`true`) + numeric (`> 0`) return-value handling.
  - Pre-frame `_G.update` master wrapper ensuring single-frame edge-triggered key states are updated before both `_G.update` wrapper mods and `on_update` hook mods.
- **Steam Build 26251122+ (Easy Anti-Cheat EOS) Migration & Launch Fixes**:
  - Compatibility verified with Helldivers 2 Steam Build `26251122` (October 29, 2026 EAC EOS update).
  - Resolved `0xc0000142` startup crash by identifying and quarantining obsolete nProtect GameGuard leftover binaries.
  - Repaired missing archive stream sidecars (`patch_72.stream` and `patch_72.gpu_resources`), ensuring 100% clean Stingray asset mounting across all 115 patches.
  - Zero executable memory patching, zero FFI crashes, and zero DLL injection.
- **Universal Discovery & Patch Deduplication**:
  - Multi-path `data` directory resolution (`data`, `../data`, `../../data`, and `package.path` roots).
  - 64-bit MurmurHash64A resource-ID lookup (`KNOWN_HASH_TO_NAME`), on-demand `package.preload` + `stingray.Application.can_get("lua", ...)` integration, preset resource handling (`mods/reticle_ammo/preset_*`), and automatic parent/sub-module load ordering (`<parent>_*` before `<parent>`).
  - Automatically deduplicates entries across `data/9ba626afa44a3aa3.patch_0..255`: the highest-numbered patch cleanly executes without duplicate loading.
- **UTF-8 BOM Stripping & Fault-Isolated Execution**:
  - Automatically strips Windows UTF-8 Byte Order Marks (`\xEF\xBB\xBF`).
  - Individual mod errors are caught and logged without crashing the engine; circuit-breaker disables runaway update hooks after 20 errors.
- **Hardened Lua 5.1 & Mock FFI Primitives**:
  - Preserves native `ffi` and `bit` if provided by the host VM while falling back to a 4-bit LUT bitwise library and enhanced mock FFI layer (`ffi.cast` function preservation, `ffi.sizeof` struct/buffer sizing, `GetProcAddress`, `GetModuleFileNameW`, `QueryPerformanceCounter`/`Frequency`, and metatable-aware `_G.tonumber`).
