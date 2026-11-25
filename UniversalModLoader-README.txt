Supports Steam builds 25988413, 26088801, 26251122, and 26568081+ (EAC EOS Overhaul).

Helldivers 2 Universal Mod Loader - v2.0.6 (The Indestructible Universal Runtime)

Unifies all Helldivers 2 modding standards into a single engine boot loader:
  1. CowboyBingus Mod Loader (API 1, Version 19, BingusRuntime v1, on_update, on_shutdown, after_startup)
  2. Chef Shared Loader (API Levels 1, 2, 3 / v1.5.3, HD2-Addon, HD2-Boot, HD2-Options) with native vararg injection
  3. Boot Mod Loader (VeganSquid API 1)
  4. HD2 Lua Runtime (hd2rt / 0.1.0)
  5. Rat's Shared Loader (Armor Transmog 1.1.2 ABI & hooks)
  6. Native UML v2.0.6 Developer API — 7 Foundational Domains (config, input, ui, hooks, locales/i18n, audio, engine) + legacy mod:* helpers
  7. Crash-Proof 2-Pane Per-Mod Submenu UI & Single-Mod Compact Overlay (F9 to open, 1-9 quick-jump, [/] mod cycle, Mouse Wheel, action buttons, rebindable keys, auto-saved to uml_mod_settings.json)
  8. Dynamic UI Scaling ([-] / [=] live hotkeys, Auto/Compact/Medium/Large density) & 3-line word-wrapped description panel
  9. Automatic 14-Locale Language Detection (Helldivers 2 settings, live Steam API, appmanifest, Windows OS) with UTF-8 diacritic & Cyrillic transliteration
 10. Pure-Lua Fake DLL Bridge (interception of package.loadlib, zero native Win32 LoadLibrary calls)
 11. Infinite Loop & Hang Watchdog (debug.sethook 3.0s abort threshold, zero game freezes)
 12. Crash Sentinel & Auto-Safe Mode (detects and isolates broken mods across launches)
 13. Topological Dependency Sorter (DAG prerequisite ordering via -- HD2-Requires / needs)
 14. Chat & Window Focus Guard (no accidental keypresses while typing in multiplayer chat or alt-tabbed)
 15. Rogue Guest Boot Shield (sandboxes secondary 0xF476DF93691895FA resources without overwriting entrypoint)
 16. Automatic Log Rotation (> 5MB rotates to .log.old)
 17. Live Hot-Reloading (Ctrl+F5 Dev Mode for loose mods)
 18. Safe pcall sandbox mod execution with quarantine logging so broken mods cannot crash the game

INSTALLATION (HD2 Arsenal Mod Manager):
1. Drag and drop 'Helldivers2-Universal-Mod-Loader-v2.0.6.zip' into Arsenal Mod Manager.
2. Disable other boot loaders (such as Chef Shared Loader, Boot Mod Loader, or CowboyBingus Mod Loader) — UML replaces them directly; stacking two boot loaders causes the higher patch to overwrite the other.
3. Place Universal Mod Loader at the bottom of your load order (highest patch priority) so bundled starter/boot shims in other mods cannot overwrite UML.
4. Deploy and launch the game.

MANUAL INSTALLATION:
1. Copy the files inside the 'data/' folder into your game's data directory:
   Steam\steamapps\common\Helldivers 2\data\
2. Ensure '9ba626afa44a3aa3.patch_0' is present.
3. Launch Helldivers 2 via Steam. Press F9 in-game to access per-mod submenus and settings!
