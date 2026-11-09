# Universal Mod Loader (UML) v2.0.0 — Modding API Reference

Universal Mod Loader v2.0.0 introduces a modern, native Lua modding framework designed specifically for Helldivers 2 mod developers. It provides crash-resilient hooks, an automatic F9 settings menu integration, rebindable hotkeys with chat guard protection, in-game toast notifications, 14-locale localization, and an inter-mod event bus.

---

## 1. Quick Start: 60-Second Mod Example

Place your script inside `Helldivers 2/data/mods/my_awesome_mod.lua`:

```lua
-- mods/my_awesome_mod.lua
local UML = _G.UniversalModLoader

-- 1. Register your mod with UML
local mod = UML.register("TacticalScanner", {
    version = "1.0.0",
    author = "SuperEarthEngineer",
    description = "Displays tactical perimeter radar and target range indicators."
})

-- 2. Register options (automatically placed in your mod's F9 submenu)
mod:option("scanner_enabled", {
    label = "Enable Tactical Scanner",
    type = "toggle",
    default = true,
    description = "Toggle the scanner overlay on your HUD."
})

mod:option("scan_range", {
    label = "Scanner Detection Radius",
    type = "slider",
    default = 75,
    min = 25,
    max = 200,
    step = 5,
    description = "Maximum detection distance in meters."
})

mod:option("hud_theme", {
    label = "HUD Color Profile",
    type = "choice",
    default = 1,
    choices = { "Cyan Tactical", "Super Earth Gold", "Crimson Warning" },
    description = "Color scheme used for radar indicators."
})

-- 3. Register a rebindable hotkey (features automatic multiplayer Chat Guard)
mod:bind_key("toggle_hotkey", "k", function()
    local is_enabled = mod:get("scanner_enabled")
    mod:set("scanner_enabled", not is_enabled)
    mod:notify(is_enabled and "SCANNER OFFLINE" or "SCANNER ONLINE", 2.0)
end)

-- 4. Main engine update loop (protected by circuit breaker)
mod:on_update(function(dt)
    if not mod:get("scanner_enabled") then return end
    local range = mod:get("scan_range")
    -- Mod rendering and tactical logic here
end)

-- 5. Shutdown cleanup
mod:on_shutdown(function()
    mod:log("Tactical Scanner cleanly shut down.")
end)
```

---

## 2. API Specification

### `UniversalModLoader.register(mod_name, metadata)`
Registers a managed mod instance.
* **Arguments:**
  * `mod_name` *(string)*: Unique identifier for your mod (e.g. `"MortarHUD"`).
  * `metadata` *(table)*:
    * `version` *(string)*: Version string (e.g. `"1.0.0"`).
    * `author` *(string)*: Mod author name.
    * `description` *(string)*: Brief description shown in the F9 menu.
* **Returns:** `mod` *(table)*: Managed mod context object.

---

### Options & Settings

#### `mod:option(option_id, spec)`
Registers a configurable setting into the F9 Mod Settings Menu and saves it to `%LOCALAPPDATA%/.../uml_mod_settings.json`.
* **Option Types:**
  * **Toggle (Boolean):**
    ```lua
    mod:option("laser_pointer", {
        label = "Weapon Laser Sight",
        type = "toggle",
        default = true,
        description = "Enable visual laser guide."
    })
    ```
  * **Slider (Numeric Range):**
    ```lua
    mod:option("hud_alpha", {
        label = "HUD Opacity",
        type = "slider",
        default = 0.80,
        min = 0.10,
        max = 1.00,
        step = 0.05,
        description = "Adjust transparency of HUD elements."
    })
    ```
  * **Choice (Enumeration):**
    ```lua
    mod:option("reticle_style", {
        label = "Reticle Design",
        type = "choice",
        default = 1,
        choices = { "Dot", "Crosshair", "Circle" },
        description = "Select your preferred aiming reticle."
    })
    ```

#### `mod:get(option_id)`
Retrieves the current persisted value of an option.

#### `mod:set(option_id, new_value)`
Updates an option programmatically and immediately saves changes to disk.

#### `mod:on_change(option_id, callback)`
Subscribes to live value changes for an option.
```lua
mod:on_change("hud_alpha", function(new_val)
    apply_alpha(new_val)
end)
```

---

### Keybindings & Input Polling

#### `mod:bind_key(action_id, default_key, callback)`
Registers a rebindable hotkey in the F9 menu.
* **Automatic Multiplayer Chat Guard:** UML automatically disables hotkeys while the in-game text chat box is open (`Enter`), preventing accidental triggers while typing.
* **Window Focus Guard:** Hotkeys will not fire if the player is Alt-Tabbed out of Helldivers 2.
```lua
mod:bind_key("radar_pulse", "h", function()
    perform_radar_sweep()
end)
```

---

### In-Engine Visual Notifications

#### `mod:notify(message, duration)`
Renders an in-game HUD toast notification banner.
* `message` *(string)*: Text to display.
* `duration` *(number, optional)*: Seconds to keep banner on screen (default: `2.5`).
```lua
mod:notify("SENTRY OVERCLOCK ACTIVATED", 3.0)
```
* **Multi-World Viewport Support:** UML draws notification banners across both `main_world` and HUD overlay viewports, ensuring visibility during dropship cinematic sequences and stratagem aiming.

---

### Lifecycle Hooks & Circuit Breaker

#### `mod:on_init(callback)`
Fires once after all mods and game engine subsystems have initialized.

#### `mod:on_update(callback)`
Fires every engine frame with delta time `dt`.
* **Automated Circuit Breaker:** If your update code encounters 10 consecutive syntax or runtime errors, UML isolates and pauses your hook while logging diagnostics to `BingusSharedLoader.log`, preventing the entire game process from crashing.

#### `mod:on_shutdown(callback)`
Fires during engine shutdown or live reload cleanup.

---

### Official 14-Locale Localization

#### `UML.register_translations(pack)`
Registers a localization pack for your mod.
```lua
UML.register_translations({
    id = "MyMod",
    strings = {
        en = { greeting = "WELCOME HELLDIVER" },
        fr = { greeting = "BIENVENUE HELLDIVER" },
        de = { greeting = "WILLKOMMEN HELLDIVER" },
        es = { greeting = "BIENVENIDO HELLDIVER" },
        ru = { greeting = "DOBRO POZHALOVAT" },
    }
})
```

#### `mod:translate(key, ...)`
Retrieves the translated string for the player's active locale. Automatically falls back to English if the translation is missing, and transliterates CJK ideographs for bitmap font display.

---

### Inter-Mod Event Bus

Communicate between different mods without tight coupling:
```lua
-- In Mod A (Emitter)
UML.emit("StratagemCalled", { id = "orbital_strike", time = 4.5 })

-- In Mod B (Receiver)
UML.on("StratagemCalled", function(data)
    mod:log("Detected stratagem: " .. data.id)
end)
```

---

### Dependency Declaration (Topological Sorting)

Declare dependencies in your file header to guarantee correct execution order:
```lua
-- HD2-Requires: mods/author/core_framework
-- HD2-After: mods/chef/smarter_guard_dogs_and_sentries_dogs
```
UML uses Directed Acyclic Graph (DAG) topological sorting to ensure prerequisite mods boot before dependent scripts.
