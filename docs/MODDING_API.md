# Universal Mod Loader (UML) v2.0.4 — Modding API Reference

Universal Mod Loader v2.0.4 provides a unified, crash-resilient Lua modding framework for Helldivers 2 mod developers. UML is built on **7 Foundational Domain APIs** (`UML.config`, `UML.input`, `UML.ui`, `UML.hooks`, `UML.locales` / `UML.i18n`, `UML.audio`, and `UML.engine`), all accessible either directly as domain namespaces or through the scoped `mod = UML.register(...)` handle:

1. **`UML.config`** — Options, Action Buttons (`type = "button"`), and Structured JSON Persistence (`get`/`set`/`on_change`/`trigger`/`save_data`/`load_data`)
2. **`UML.input`** — Keybindings, Menu-Allowed Hotkeys (`allow_in_menu = true`), Rising-Edge Polling (`is_down`/`is_pressed`/`consume_press`), and Chat/Focus/Menu Guards
3. **`UML.ui`** (alias `UML.menu`, `UML.hud`) — F9 Full Menu, Single-Mod Compact Menus, Menu State Listeners, Toast Notifications, and 2D Screen HUD Drawing (`screen_size`/`scale`/`color`/`rect`/`text`)
4. **`UML.hooks`** — Lifecycle (`on_init`/`on_update`/`on_shutdown`), Throttled Updates & Timers (`after`/`every`/`cancel_timer`), Managed Function Detours (`hook`/`unhook`), and Inter-Mod Event Bus (`on`/`emit`)
5. **`UML.locales`** (alias `UML.i18n`) — 14-Locale Auto-Detection, Translation Packs, and UTF-8 / Cyrillic / CJK Sanitization
6. **`UML.audio`** — Crash-Guarded Wwise Audio Playback (`play`/`stop`/`is_playing`/`set_parameter`)
7. **`UML.engine`** — Safe Stingray 3D World, Unit Queries (`unit_alive`/`unit_position`), 3D-to-2D `world_to_screen`, Physics `raycast`, and Frame-Safe `vec3`/`box_vec3`

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
  * **Button / Action (One-Shot Menu Trigger):**
    ```lua
    mod:option("reset_presets", {
        label = "Reset Presets to Default",
        type = "button",
        button_text = "EXECUTE",
        description = "Press Enter, Space, or Right Arrow in F9/Compact menu to run.",
        on_click = function()
            mod:set("saved_presets", {})
            mod:notify("PRESETS RESET", 2.0)
        end
    })
    ```

#### `mod:get(option_or_data_id, default_value)` (alias: `mod:load_data`)
Retrieves the current persisted value of an option or structured data key, returning `default_value` if unset.

#### `mod:set(option_or_data_id, new_value)` (alias: `mod:save_data`)
Updates an option or persists structured Lua tables (arrays and nested dictionaries) directly to `uml_mod_settings.json`. Keys set without `mod:option` (or registered with `hidden = true` / `type = "data"`) are persisted on disk without cluttering the F9 menu.
```lua
-- Persist arbitrary nested tables (loadouts, presets, arrays) with the same get/set API:
mod:set("armor_presets", {
    slot_1 = { helmet = "B-01", cape = "Foesmasher", tags = { "heavy", "gold" } }
})
local presets = mod:get("armor_presets", {})
```

#### `mod:on_change(option_id, callback)`
Subscribes to live value changes for an option (can also be passed inline as `on_change = fn` inside `mod:option`).
```lua
mod:on_change("hud_alpha", function(new_val)
    apply_alpha(new_val)
end)
```

#### `mod:trigger(option_id, ...)`
Programmatically triggers a `type = "button"` option's `on_click` and `on_change` callbacks.

---

### Keybindings, Menu-Allowed Hotkeys & Input Polling

#### `mod:bind_key(action_id, default_key, callback, opts)` (or `mod:bind_key(default_key, callback, mode, opts)`)
Registers a rebindable hotkey in the F9 menu.
* **Automatic Multiplayer Chat Guard:** UML automatically disables hotkeys while the in-game text chat box is open (`Enter`), preventing accidental triggers while typing.
* **Window Focus Guard:** Hotkeys will not fire if the player is Alt-Tabbed out of Helldivers 2.
* **Menu-Allowed Hotkeys (`allow_in_menu = true`):** Pass `{ allow_in_menu = true }` when a hotkey should remain active while the F9 or compact menu is open (still blocked during active key-capture or chat).
```lua
mod:bind_key("radar_pulse", "h", function()
    perform_radar_sweep()
end, { allow_in_menu = false, description = "Trigger tactical radar sweep." })
```

#### `mod:is_key_down(action_id_or_key, allow_in_menu)` & `mod:consume_key_press(action_id_or_key, allow_in_menu)`
Edge-safe polling helpers for custom update loops. `consume_key_press` consumes the rising edge for the current frame so multiple handlers do not double-trigger.

---

### Unified UI, Compact Menus & HUD Drawing (`UML.ui` / `mod.ui`)

`UML.ui` (also aliased as `UML.menu`, `UML.hud`, and `mod.ui`) unifies menu state inspection, compact overlay menus, and crash-guarded 2D Stingray HUD drawing:

```lua
-- 1. Register a single-mod Compact Menu shortcut (layouts: 1=Right, 2=Left, 3=Center, 4=Full)
mod:register_compact_menu({
    key = "f10",
    layout = 1,
    layout_option_id = "TacticalScanner.menu_layout"
})

-- 2. Inspect or control menu state
local state = mod.ui.get_state() -- { open, fullscreen, compact, layout, mod_name, option_id, capture, chat_open, ... }
mod.ui.on_change(function(st)
    -- React to menu open/close, compact toggle, or selection changes
end)

-- 3. Draw resolution-scaled HUD rectangles & sanitized text across active Stingray worlds
local w, h = mod.ui.screen_size()
local px = mod.ui.scale()
mod.ui.rect(40, h - 120, 260, 44, mod.ui.color(220, 16, 22, 32), 900)
mod.ui.text("SCANNER ACTIVE", 54, h - 106, px, mod.ui.color(255, 255, 215, 55), 910)
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

### Lifecycle Hooks, Timers, Function Detours & Circuit Breaker

#### `mod:on_init(callback)`
Fires once after all mods and game engine subsystems have initialized.

#### `mod:on_update(callback, interval_seconds)`
Fires every engine frame with delta time `dt`—or, when `interval_seconds` is provided (e.g. `mod:on_update(fn, 0.25)`), throttles execution to run every `interval_seconds`.
* **Automated Circuit Breaker:** If your update code encounters 10 consecutive runtime errors, UML isolates and pauses your hook while logging diagnostics to `UniversalModLoader.log`, preventing the game process from crashing.

#### `mod:after(delay_seconds, callback)` & `mod:every(interval_seconds, callback)`
Schedules a one-shot delayed callback or repeating timer inside UML's update loop (returns `timer_id`, cancellable via `mod:cancel_timer(timer_id)`). Timers are automatically cleaned up on `Ctrl+F5` hot-reload.

#### `mod:hook(target_table, method_name, wrapper_fn)` & `mod:unhook(target_table, method_name, wrapper_fn)`
Safely detours `target_table[method_name]` in a managed multi-mod hook chain without clobbering other mods. `wrapper_fn(orig_fn, ...)` receives the next/original function as its first argument. If a hook errors, UML logs the error and automatically falls back to calling `orig_fn(...)`. All hooks owned by a mod are automatically restored on `Ctrl+F5` hot-reload.
```lua
mod:hook(TargetSystem, "apply_damage", function(orig, self, amount, ...)
    return orig(self, amount * 1.25, ...)
end)
```

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
