# Changelog — Helldivers 2 Universal Mod Loader

## [1.0.1] - Hotfix Release
### Fixed
- **Launch Freeze / Black Screen on Startup**: Eliminated `os.execute` child process spawning in `open_log()` which caused Easy Anti-Cheat (EAC EOS) to suspend the engine thread and hang indefinitely on startup when dependent mods requested log handles.
- **Mod Lifecycle Safety**: Streamlined `BingusRuntime.guard()` to prevent `_G.update` execution locks during early boot.
- **Filesystem Path Overhead**: Cleaned package search paths to eliminate unnecessary directory probing under anti-cheat.

## [1.0.0] - Initial Release
### Added
- **Multi-Standard Engine Bootloader**: Unified runtime providing native support for CowboyBingus (API 1, BingusRuntime v1), Chef Shared Loader (API Levels 1, 2, 3), Boot Mod Loader (VeganSquid API 1), and HD2 Lua Runtime (hd2rt 0.1.0).
- **Circuit-Breaker Fault Isolation**: Protected `pcall` execution sandbox for all mod loads and frame updates. Upstream syntax bugs or runtime typos in third-party mods are logged and isolated without crashing the game to desktop.
- **Native Stingray Hotkey Polling**: Direct engine `Keyboard.button` and `Keyboard.pressed` input polling so registered mod keybindings (such as radar/HUD toggles) function reliably in-game.
- **100% Pure Lua 5.1 & Anti-Cheat Compliance**: Completely eliminated native Win32 FFI memory writes and GetModuleHandle probing for 100% crash-free launches under Easy Anti-Cheat (EAC EOS).
- **Extended Archive & Loose Mod Discovery**: Scans archives up to `patch_256` across `data/` and `../data/`, and enables loose script loading from `<GameDir>/mods/`.
- **Standard Polyfills**: Embedded 32-bit signed bitwise engine (`bit` and `bit32`) and standard `utf8` library for full backward and forward mod compatibility.
