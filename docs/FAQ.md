# Universal Mod Loader v22.0.0 — Frequently Asked Questions

### Do I need to install Bingus Shared Loader AND Universal Mod Loader?
No. Universal Mod Loader is a complete drop-in replacement that fully supersedes Bingus Shared Loader. Do not install both in the same slot.

### Do I need to install Mod Options Menu or Mod Bindings Menu?
No! Both `ModOptionsMenu` (F2 menu) and `ModBindingsMenu` are built directly into Universal Mod Loader. You do not need `mod_options_menu` or `mod_bindings_menu` installed. In fact, removing older versions of those mods is recommended.

### How do I open the menu and rebind keys?
- Press **F2** or **F9** to toggle the in-game overlay.
- Press **Tab** to switch between **Mod Options** and **Key Bindings**.
- In the Key Bindings tab, highlight an action with **Up/Down** and press **Enter**. Then press whatever key you want to bind to that action. Press **Escape** to cancel or **Delete** to unbind.

### Where are my settings saved?
Settings are saved to `%LOCALAPPDATA%/UniversalModLoader/settings.json`.

### Can I get banned by Easy Anti-Cheat?
No. Universal Mod Loader uses pure Lua running within the engine's standard patch archive system. No DLL injection, executable patching, or memory hooking is performed.

### What happens if a mod contains a syntax error?
Universal Mod Loader isolates compilation of each mod. If a mod contains broken code (like an outdated keyword), Universal Mod Loader logs the failure and skips the mod safely, allowing the game and all other mods to continue running normally.
