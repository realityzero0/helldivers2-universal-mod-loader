# Changelog — Helldivers 2 Universal Mod Loader

## [2.0.0] - Generational Update: The Indestructible Universal Runtime
### Community Feedback & Direct Issue Resolutions

Universal Mod Loader v2.0.0 addresses every community question, inquiry, and defect report directly. Below are the actual quotes from community members on Nexus Mods, along with the technical root cause analysis and the permanent fixes implemented in this release:

#### 1. Chef Shared Loader Hooking & Deactivation Defect
> **Quote from @Vindsv3ll3:**  
> *"You're not alone; I've been unable to make this function anywhere in my load order, and with or without Chefs Shared Loader. With it, CSL simply deactivates Universal Mod Loader; without CSL, none of the mods are hooked, and the CSL F9 menu is absent."*
>
> **Quote from @XCABAL:**  
> *"So I'm not sure what I did wrong. I load into the game fine, but nothing seems to be working. All of my CSL mods don't turn on except maybe one or two. Just to be clear. Where do I place it in a bottom priority load order? Cause I tried switching it around and nothing seems to work."*
>
> * **Why it didn't work in v1.0.1:**  
>   1. **Cooperative Handoff Surrender:** In v1.0.1, line 15 checked `Application.can_get('lua', 'mods/chef_shared_loader/core_1')` and deliberately exited via `return` if Chef Shared Loader was installed in any patch layer. This surrendered control completely to CSL, deactivating Universal Mod Loader by design.  
>   2. **Vararg Calling Parameter Mismatch:** In Lua 5.1, standard `require("mod_name")` passes the *name of the module* as `...`. All CSL mods start with `local chef = ...` expecting the `chef_api` table. Under v1.0.1, `chef` was assigned the string name of the mod instead of the table, causing `chef.on(...)` to fail with `attempt to index local 'chef' (a string value)`. Although our circuit breaker caught the error to prevent the game from crashing, the mod could not hook.
> * **What was done to fix it in v2.0.0:**  
>   1. **Permanent Deactivation Removal:** Removed the CSL cooperative handoff surrender entirely. Universal Mod Loader is now the sole engine authority and never deactivates itself.  
>   2. **True Vararg Chunk Injection:** Implemented direct bytecode chunk loading via `chunk(chef_api, mod_name)`. Now when any CSL mod runs `local chef = ...`, it receives the fully functional, live `chef_api` table. All CSL mods now hook seamlessly and execute without needing Chef Shared Loader installed at all!

---

#### 2. Settings Menu & In-Game Options (F9 Key)
> **Quote from @homehome:**  
> *"How do I change mod's settings ? F9 not working anymore."*
>
> **Quote from @Katzenwerfer99:**  
> *"Does this include a settings menu like Chef's?"*
>
> * **Why it didn't work in v1.0.1:**  
>   v1.0.1 was released headless to guarantee total crash immunity under Easy Anti-Cheat. In legacy loaders, F9 overlays frequently caused hard C++ desktop crashes during drop pod sequences or loading screens due to unmanaged font memory references.
> * **What was done to fix it in v2.0.0:**  
>   Introduced a native, **100% crash-proof 2-Pane Per-Mod Submenu Settings UI** accessed via **F9** (or **F2**).  
>   - **Left Sidebar (`MODS`) & Right Submenu (`MOD OPTIONS`):** Automatically groups every mod's options and keybindings into its own dedicated submenu so options are never jumbled together.  
>   - **Multi-Modal Navigation:** Use `Up`/`Down` or **Mouse Wheel** to browse, `Right Arrow`/`Space`/`Tab` to enter a mod's submenu, `Left`/`Right` to toggle/adjust values or rebind keys, `Backspace`/`Tab` to return to the mod list, `1`–`9` to quick-jump directly to a mod submenu, `[`/`]` to cycle mods, and `Delete` to reset an option to default.  
>   - **Engine-Independent 5x7 Pixel Font Renderer:** Drawn entirely via pure `Gui.rect` primitives inside a `pcall` shield—immune to missing C++ font resource or Unicode glyph crashes.  
>   - **Persistent Settings:** Automatically imports existing `ModOptionsMenu.values` profiles and saves all changes to `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/uml_mod_settings.json`.

---

#### 3. Rat's Shared Loader & Armor Transmog 1.1.2 Compatibility
> **Quote from @Pyrodyne:**  
> *"How does this play with Rat's Shared Loader for the Transmog mod?"*
>
> **Quote from @TeXchNo:**  
> *"It works with version 1.1.2 of the Armor Transmog mod; I mean, if I install this, do I no longer need to install Rat's Shared Loader?"*
>
> * **Why it didn't work in v1.0.1:**  
>   v1.0.1 unified CowboyBingus, Chef Shared Loader, Boot Mod Loader, and hd2rt, but had not yet emulated the proprietary `_G.RatsSharedLoader` table and manifest spec structure used by Armor Transmog 1.1.2.
> * **What was done to fix it in v2.0.0:**  
>   Integrated native support for **Rat's Shared Loader 1.1.2 ABI**. Universal Mod Loader now natively exposes `_G.RatsSharedLoader`, registers Transmog specs, and provides all necessary inventory and loadout sync hooks. Players no longer need Rat's Shared Loader installed separately.

---

#### 4. Hellforge Version of Bingus
> **Quote from @TerribleVennyBun:**  
> *"Does this provide support for hellforge version of bingus? (I believe it's an updated version.)"*
>
> * **Technical Clarification & Compatibility:**  
>   Hellforge was an external memory-injection tool built before Arrowhead enforced Easy Anti-Cheat (EAC). Under EAC, all external memory injectors and DLL loaders are actively terminated by the anti-cheat driver.  
>   However, Universal Mod Loader is a **100% pure-Lua archive patch (`patch_0`)** that runs entirely within the game's official Stingray engine sandbox without any external binaries or DLLs. Any Lua script mods created for Bingus or Hellforge will load and run natively inside Universal Mod Loader!

---

#### 5. Overdive Mod Compatibility
> **Quote from @MihaGun123:**  
> *"Maybe it is stupid question but is Overdive working correctly with this?"*
>
> * **Technical Clarification:**  
>   Overdive is an external C++ binary injector that hooked into the game executable before EAC was enabled. Because Easy Anti-Cheat terminates third-party native code injection, pure-Lua mod loaders cannot bypass EAC to run Overdive. Only the original author of Overdive can update their injector for compatibility with EAC. All pure-Lua mods, however, run flawlessly in Universal Mod Loader.

---

#### 6. MDL3 (Mod Dynamic Loader 3) Inquiries & Architectural Boundaries
> **Community Inquiry:**  
> *"Can Universal Mod Loader replace or bundle MDL3 (Mod Dynamic Loader 3)?"*
>
> * **Technical Clarification & Architectural Boundary:**  
>   Universal Mod Loader is deliberately built as an **EAC-safe, 100% pure Lua 5.1 Stingray archive patch (`patch_0`)**. It executes entirely within the game engine's sanctioned Lua VM and performs zero external process creation, zero Windows DLL hijacking (`version.dll`), and zero memory byte-patching.  
>   MDL3, conversely, is a native C++ proxy DLL that hooks into Windows process memory directly to enable low-level FFI memory scraping. Because UML adheres strictly to a pure-Lua design, it will never inject external DLLs into your game.  
>   However, **UML v2.0.0 is engineered to cleanly coexist alongside MDL3**: because UML operates at the Stingray patch level (`data/`) and provides non-crashing FFI mock interfaces and synthetic PE headers, players can run both frameworks concurrently without collisions!

---

### New Architecture & Engine Subsystems in v2.0.0
- **Clean-Install Directory Fallback & Settings Persistence:** Implements a 4-tier candidate path cascade across `open_log()`, `save_settings_to_disk()`, and crash sentinels targeting `%APPDATA%/Arrowhead/Helldivers2/` and `%LOCALAPPDATA%/`. Guarantees 100% reliable logging and persistent settings even on clean PCs where CowboyBingus was never installed.
- **2-Pane Per-Mod Submenu Settings Overlay (`F9`):** Groups mod options and keybindings by mod with `1`–`9` quick-jump shortcuts, `[`/`]` mod cycling, Mouse Wheel scrolling, and live keybinding capture.
- **Dynamic UI Scaling & Word-Wrapped Description Panel:** Dynamic scaling modes (`Auto`, `Compact`, `Medium`, `Large`) with live `[-]`/`[=]` hotkeys, fitting up to 28 options per page, plus a 3-line word-wrapped description box.
- **Automatic 14-Locale Language Detection & i18n Engine:** 4-tier auto-detection cascade (Game configs, live Steamworks API, appmanifest, Windows OS) supporting all 14 official Helldivers 2 locales (`en`, `en-GB`, `fr`, `de`, `it`, `es`, `es-419`, `pt-BR`, `pl`, `ru`, `ja`, `ko`, `zh-Hans`, `zh-Hant`) with zero-letter-loss UTF-8 diacritic and Cyrillic transliteration.
- **Native `UML` v2.0.0 Developer API:** Complete 60-second modder framework (`UML.register`, `:on_init`, `:on_update`, `:on_shutdown`, `:bind_key`, `:option`, `:notify`, `:translate`, `:log`, `:error`, `UML.on`, `UML.emit`, `UML.register_translations`).
- **Pure-Lua Fake DLL Bridge & Native FFI Preservation:** Preserves native engine `ffi` / `bit` / `package.loadlib` when present while falling back to EAC-safe mock interfaces when absent.
- **Topological Dependency Sorter (DAG):** Resolves `-- HD2-Requires:` / `needs` prerequisites before dependents, eliminating load order race conditions.
- **Infinite Loop & Hang Watchdog:** Uses `debug.sethook` with a 3.0s threshold to detect and terminate runaway `while` loops, preventing game thread freezes.
- **Chat & Window Focus Guard:** Gated input polling that checks `Window.has_focus()` and `Enter` chat box state, preventing accidental hotkey activations while typing in multiplayer chat or alt-tabbed.
- **Crash Sentinel & Auto-Quarantine:** Writes an active sentinel file during mod initialization. If an unmanaged C++ crash occurs, the faulted mod is auto-quarantined on the next launch so the game boots cleanly.
- **Rogue Guest Boot Shield:** Intercepts secondary `boot` resources (`0xf476df93691895fa`) shipped accidentally in third-party mod archives (e.g. SEAF Artillery 2.0.0) without overwriting the engine entrypoint.
- **Live Script Hot-Reloading (`Ctrl+F5` Dev Mode):** Re-executes loose scripts from `<GameDir>/mods/` on demand without restarting the game.
- **Font Glyph Sanitizer:** Automatically sanitizes and transliterates non-ASCII Unicode characters before rendering, preventing engine assertion failures.
- **Automatic Log Rotation:** Automatically rotates `BingusSharedLoader.log` to `.log.old` when exceeding 5 MB to prevent unbounded disk usage.

---

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
