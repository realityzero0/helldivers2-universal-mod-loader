# Changelog - Helldivers 2 Universal Mod Loader

## [1.0.0] - 2026-10-31 (Inaugural Unified Release)
### Added
- **Clean Semantic Versioning**: Adopted clean semantic versioning starting at `v1.0.0` for the standalone unified mod loader project.
- **Dynamic Live Mod Loading**:
  - Run loose `.lua` scripts directly from `<GameDir>/mods/` or `%LOCALAPPDATA%/UniversalModLoader/mods/` without repacking into archives.
  - In-game hot-reload button `[R] RELOAD ALL` in the ESC menu (and `R` hotkey) to re-scan disk and re-execute scripts on the fly.
  - Live pickup of newly deployed patch archives from Arsenal Mod Manager without game restarts.
- **Live Mod Enable / Disable Management**:
  - Toggle any mod active or inactive directly from Tab 3 (Loaded Mods) with `Space` / `Enter` or mouse click.
  - Instant hook muting: disabled mods stop executing update callbacks, keybindings, and render loops, freeing frame budget.
  - Persistent disabled state saved across launches in `%LOCALAPPDATA%/UniversalModLoader/settings.json`.
- **Real-Time Frame Profiler**:
  - Per-mod CPU frame execution cost tracking in milliseconds (`0.04 ms`) using rolling exponential moving averages.
  - Peak spike detection and total mod frame budget tracking.
  - Live Lua heap memory monitor in kilobytes (`HEAP: 19,528 KB`).
- **Interactive In-Game Overlay Upgrades**:
  - Enhanced Tab 3 layout showing mod sources (`ARCHIVE` vs `[LOOSE]`), real-time CPU cost, and live status badges (`[ ACTIVE ]`, `[ DISABLED ]`, `[ BUILT-IN ]`, `[ ERROR ]`).
  - Action buttons in Details Pane: `[ SPACE / ENTER ] TOGGLE ACTIVE` and `[ R ] RELOAD ALL MODS`.
  - Floating tactical notification toast banner for live reload confirmations.
- **Unified Mod Ecosystem Parity**:
  - CowboyBingus Mod Loader (API 1 / v17 / v20 / v21 / BingusRuntime v1).
  - Chef Shared Loader (API Levels 1, 2, 3 / cooperative handoff).
  - Boot Mod Loader (VeganSquid API 1).
  - HD2 Lua Runtime (`hd2rt` 0.1.0).
  - Built-in Mod Options Menu (MOM v3).
  - Built-in Mod Bindings Menu (MBM v4).
- **Pure Lua 5.1 Polyfill Suite**:
  - Complete pure-Lua `bit32` library.
  - Pure-Lua `utf8` module.
  - Lua 5.3 `math.type`, `math.tointeger`, `math.ult`.
  - Transparent Lua 5.2 forward-`goto` transpiler.
  - Stingray `button_id`/`button_index` polyfill.
  - Automatic UTF-8 BOM stripping.
  - Circuit-breaker fault isolation protecting against broken third-party mod syntax.
