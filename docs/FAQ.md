# Universal Mod Loader v2.0.0 — Frequently Asked Questions (FAQ)

### 1. Do I need to install Bingus Shared Loader, Chef Shared Loader, or Rat's Shared Loader?
**No.** Universal Mod Loader v2.0.0 is an all-in-one universal drop-in replacement that supersedes all previous shared loaders. It natively provides:
- CowboyBingus API 1 & BingusRuntime v1
- Chef Shared Loader API Levels 1, 2, and 3 (with true vararg chunk injection)
- Rat's Shared Loader (Armor Transmog 1.1.2 ABI)
- Boot Mod Loader & hd2rt
Do not install secondary loader patch files. UML handles all of them natively.

### 2. How do I change mod settings in-game?
- Press **F9** (or **F2**) anytime in-game or aboard the Super Destroyer to toggle the 2-pane Mod Settings Menu.
- Use **Up / Down** arrow keys or **Mouse Wheel** to scroll.
- Press **Right Arrow**, **Space**, or **Tab** to enter a mod's dedicated options submenu.
- Press **Left / Right** arrow keys to cycle toggles, sliders, or choices.
- Press **[-]** or **[=]** anytime to dynamically scale the UI font size and row density live.
- Press **1** through **9** to quick-jump directly to a specific mod submenu.
- Press **Delete** or **Backspace** to reset an option to the mod's default value.
- Press **ESC** to close the menu.

### 3. Where are my settings saved?
Settings are persisted in JSON format across a resilient path cascade:
1. `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/uml_mod_settings.json`
2. `%APPDATA%/Arrowhead/Helldivers2/uml_mod_settings.json`
3. `%LOCALAPPDATA%/UniversalModLoader/mod_settings.json`

Existing settings from older `ModOptionsMenu.values` files are automatically imported on boot. If a settings file ever suffers corruption from an improper system shutdown, UML automatically creates a `.bak` backup and restores default values safely.

### 4. Can I get banned by Easy Anti-Cheat (EAC)?
**No.** Universal Mod Loader is strictly written in 100% pure Lua 5.1 and runs entirely within the game's sanctioned Stingray engine virtual machine. It performs:
- **Zero** external process creation (`os.execute` is never used)
- **Zero** Win32 DLL injection (`version.dll` hijacking is avoided)
- **Zero** binary memory byte-patching

It is completely undetectable and safe.

### 5. Will Universal Mod Loader support or replace MDL3 (Mod Dynamic Loader 3)?
**No.** Universal Mod Loader is intentionally built as a pure Lua 5.1 patch archive (100% EAC-safe, zero DLL injection, zero binary hooking). MDL3 is a native C++ proxy DLL that hooks into Windows process memory directly to enable low-level FFI memory scraping. UML will never inject external DLLs into your game. However, UML v2.0.0 can cleanly coexist alongside MDL3 if you run both, because UML operates at the Stingray patch level (`data/`), not the binary DLL level.

### 6. Can I use this with Arsenal Mod Manager or HD2MM?
**Yes.** Universal Mod Loader comes packaged with complete manifests (`manifest.json` and `UniversalModLoader-manifest.json`) formatted specifically for Arsenal Mod Manager and HD2MM. Simply drag and drop the release `.zip` into your manager and place UML at **Position 1 (`patch_0`)**.

### 7. What if another mod requires `patch_0`?
You can rename UML's `9ba626afa44a3aa3.patch_0` (and its companion `.stream` / `.gpu_resources` files) to any higher patch index (e.g. `patch_111`, `patch_200`). As long as UML's patch index is higher than or equal to other game patches, it will boot seamlessly and override default engine scripts.

### 8. Does UML support my language?
**Yes!** UML v2.0.0 features automatic language detection across all **14 official Helldivers 2 locales**:
- English (US / UK)
- French (`fr`)
- German (`de`)
- Italian (`it`)
- Spanish (Spain `es` / Latin America `es-419`)
- Portuguese (Brazil `pt-BR`)
- Polish (`pl`)
- Russian (`ru`)
- Japanese (`ja`)
- Korean (`ko`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

It automatically queries your active game settings, Steam language, or Windows OS locale, with real-time UTF-8 diacritic and Cyrillic transliteration.

### 9. What happens if a mod crashes or has an infinite loop?
UML includes an automated **Crash Sentinel** and **3.0-second Hang Watchdog**:
- If a mod enters an infinite `while` loop, the watchdog aborts execution before the game freezes.
- If a mod triggers an engine crash during startup, UML records the active sentinel and automatically quarantines the offending mod on your next launch so Helldivers 2 boots cleanly.
- If a mod's update hook encounters 10 consecutive runtime errors, our **Circuit Breaker** disables that specific hook without affecting the rest of your game.

### 10. How do mod authors create mods for UML?
Modders can use the native `UniversalModLoader.register("ModName")` API to register options, hotkeys, in-game notifications, and event hooks in under 60 seconds. See `docs/MODDING_API.md` for full documentation and code examples.
