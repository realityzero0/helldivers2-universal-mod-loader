Supports Steam builds 25988413, 26088801, and 26251122+ (EAC EOS Overhaul).

Helldivers 2 Universal Mod Loader - v1.0.1 (Strict Pure-Lua 5.1 Infrastructure)

Unifies all Helldivers 2 modding standards into a single engine boot loader:
  1. CowboyBingus Mod Loader (API 1, Version 17, BingusRuntime v1, on_update, on_shutdown, after_startup)
  2. Chef Shared Loader (API Levels 1, 2, 3, HD2-Addon, HD2-Boot, HD2-Options, cooperative handoff)
  3. Boot Mod Loader (VeganSquid API 1)
  4. HD2 Lua Runtime (hd2rt / 0.1.0)
  5. Fallback stubs for Mod Options Menu & Mod Bindings Menu so early mod settings registrations succeed safely
  6. Signed 32-bit bitwise emulation LUT engine (bit.tobit, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift)
  7. Strict PUC-Rio Lua 5.1 environment compliance (zero 5.2 syntax breaks, zero FFI crashes, zero native DLL hooks)
  8. Safe pcall sandbox mod execution with quarantine logging so broken mods cannot crash the game

Features in v1.0.1:
- Strict Lua 5.1 PUC-Rio Core: Tailored specifically to Helldivers 2's native Lua 5.1 engine.
- High-Performance 4-bit LUT 'bit' Library: Full 32-bit signed bitwise operations (tobit, tohex, bnot, band, bor, bxor, lshift, rshift, arshift, rol, ror, bswap).
- Mock FFI Primitives: Non-crashing pure-Lua FFI layer allowing legacy mods to fail closed safely without crash-to-desktop.
- Circuit-Breaker Fault Isolation: Protects against game crashes by catching individual mod errors and continuing cleanly.
- EAC Safe & Pure Lua 5.1: Zero native DLL injection, zero executable memory patching, zero FFI crashes.

Installation:
- Mod Manager (Arsenal Mod Manager / HD2MM): Drag and drop Helldivers2-Universal-Mod-Loader-v1.0.1.zip into your mod manager and deploy.
- Manual: Extract data/9ba626afa44a3aa3.patch_0 (and .stream, .gpu_resources) into Helldivers 2/data/.

Logs: %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log
Settings: %LOCALAPPDATA%/UniversalModLoader/settings.json
Loose Mods: <GameDir>/mods/ or %LOCALAPPDATA%/UniversalModLoader/mods/
License: Zero-Clause BSD (0BSD) - 100% Free & Open Source
