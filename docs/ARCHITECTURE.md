# Universal Mod Loader — Technical Architecture Specification

## 1. Overview
Universal Mod Loader is designed to harmonize multiple competing modding architectures in Helldivers 2 under a single, unified execution environment.

```
                              +-------------------------------------------+
                              |         Stingray Boot Entrypoint          |
                              |   (0xF476DF93691895FA in patch_0)         |
                              +---------------------+---------------------+
                                                    |
                                                    v
                              +-------------------------------------------+
                              |      Universal Mod Loader v22.0.0         |
                              +---------------------+---------------------+
                                                    |
                        +---------------------------+---------------------------+
                        |                           |                           |
                        v                           v                           v
             +--------------------+      +--------------------+      +--------------------+
             | Patch Scanner      |      | Built-in Services  |      | Execution Gateway  |
             | - patch_0..255     |      | - ModOptionsMenu   |      | - Sandboxed Env    |
             | - UTF-8 BOM strip  |      | - ModBindingsMenu  |      | - Multi-Standard   |
             | - Deduplication    |      | - Settings I/O     |      |   Shims            |
             +--------------------+      +--------------------+      +--------------------+
```

## 2. Supported Standards Specification

| Standard | Target Global | Supported Methods / Fields |
|---|---|---|
| **CowboyBingus Mod Loader** | `_G.CowboyBingusModLoader`<br>`_G.HD2ModLoader` | `version=17`, `api=1`, `on_update`, `on_shutdown`, `after_startup`, `open_log`, `log_directory` |
| **Bingus Runtime** | `_G.BingusRuntime` | `shared.version=1`, `shared.on('update'/'shutdown')`, `guard(name, fn)` |
| **Chef Shared Loader** | `chef` parameter<br>`_G.ChefSharedLoader` | `api_level=3`, `chef.on('update'/'shutdown')`, `chef.options`, `chef.bindings`, `chef.state`, `chef.log` |
| **Boot Mod Loader** | `_G.BootModLoader` | `api=1`, `hook(target, fn)` |
| **HD2 Lua Runtime** | `_G.hd2rt` | `_VERSION="0.1.0"`, `on(event, cb)`, `emit(event, ...)`, `register_mod(info)` |
| **Mod Options Menu** | `_G.ModOptionsMenu` | `api=1`, `version=2`, `register_option(id, spec)`, `get(id)`, `set(id, val)`, `on_change(id, fn)` |
| **Mod Bindings Menu** | `_G.ModBindingsMenu`<br>`_G.CowboyBingusModBindings` | `api=1`, `version=4`, `register_binding`, `is_down`, `is_pressed`, `poll`, `set_binding`, `binding` |

## 3. Pure Lua 5.1 Compatibility Primitives
- **Bitwise Library**: 4-bit nibble lookup tables for `band`, `bor`, `bxor`. Exact signed 32-bit truncation (`math.floor` for positives, `math.ceil` for negatives).
- **MurmurHash64A**: Pure 64-bit multi-precision integer multiplication and bitwise XOR emulation.
- **FFI Stubs**: Metamethod-aware mock pointers with arithmetic support (`__add`, `__sub`, `__eq`, `__lt`, `__le`).
