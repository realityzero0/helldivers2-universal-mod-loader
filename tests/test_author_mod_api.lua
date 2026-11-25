-- tests/test_author_mod_api.lua
-- End-to-end verification of the Native UML v2.0.0 Developer API for Mod Authors

local pass_count = 0
local total_count = 0

local function test(desc, fn)
    total_count = total_count + 1
    local ok, err = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        print(string.format("  [PASS] %s", desc))
    else
        print(string.format("  [FAIL] %s: %s", desc, tostring(err)))
        error(err)
    end
end

print("====================================================")
print("Testing Native UML v2.0.0 Developer API for Modders")
print("====================================================")

local appdata = os.getenv("APPDATA") or os.getenv("LOCALAPPDATA") or "."
local settings_path = (os.getenv("APPDATA") or ".") .. "/Arrowhead/Helldivers2/uml_mod_settings.json"
local settings_path2 = (os.getenv("LOCALAPPDATA") or ".") .. "/UniversalModLoader/uml_mod_settings.json"
local settings_path3 = (os.getenv("LOCALAPPDATA") or ".") .. "/UniversalModLoader/mod_settings.json"
local settings_path4 = "uml_mod_settings.json"
local orig_settings_content = nil
local orig_settings_content2 = nil
local orig_settings_content3 = nil
local orig_settings_content4 = nil
local sf_chk = io.open(settings_path, "rb")
if sf_chk then
    orig_settings_content = sf_chk:read("*a")
    sf_chk:close()
    os.remove(settings_path)
end
local sf_chk2 = io.open(settings_path2, "rb")
if sf_chk2 then
    orig_settings_content2 = sf_chk2:read("*a")
    sf_chk2:close()
    os.remove(settings_path2)
end
local sf_chk3 = io.open(settings_path3, "rb")
if sf_chk3 then
    orig_settings_content3 = sf_chk3:read("*a")
    sf_chk3:close()
    os.remove(settings_path3)
end
local sf_chk4 = io.open(settings_path4, "rb")
if sf_chk4 then
    orig_settings_content4 = sf_chk4:read("*a")
    sf_chk4:close()
    os.remove(settings_path4)
end

-- Load bootloader into clean mock environment
local function boot_clean_environment()
    -- Create Stingray mock globals
    local mock_worlds = { { id = "main_world" }, { id = "hud_world" } }
    local rects = {}
    local kb_down = {}

    local mock_sr = {
        Application = {
            main_world = function() return mock_worlds[1] end,
            worlds = function() return mock_worlds end,
            user_setting = function(k)
                if k == "language" then return "us" end
                return nil
            end
        },
        World = {
            create_screen_gui = function(w)
                return { world = w, id = "gui_" .. tostring(w.id) }
            end
        },
        Gui = {
            rect = function(g, pos, size, col)
                rects[#rects + 1] = { g = g, pos = pos, size = size, col = col }
            end,
            resolution = function() return 1920, 1080 end
        },
        Keyboard = {
            button_id = function(name)
                local map = { f9 = 119, h = 72, f1 = 112, enter = 13, esc = 27 }
                return map[name:lower()]
            end,
            button = function(idx) return kb_down[idx] == true end,
            pressed = function(idx) return kb_down[idx] == true end
        },
        Window = {
            has_focus = function() return true end
        },
        Vector2 = function(x, y) return { x = x, y = y } end,
        Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end
    }

    _G.stingray = mock_sr
    _G.Keyboard = mock_sr.Keyboard
    _G.Window = mock_sr.Window

    local boot_path = "src/boot_loader.lua"
    local f_chk = io.open(boot_path, "r")
    if f_chk then
        f_chk:close()
    else
        boot_path = "UniversalModLoader-v1.0.0/src/boot_loader.lua"
        local f_chk2 = io.open(boot_path, "r")
        if f_chk2 then
            f_chk2:close()
        else
            boot_path = "G:/antigravity/UniversalModLoader-v1.0.0/src/boot_loader.lua"
        end
    end
    local chunk, err = loadfile(boot_path)
    assert(chunk, "Failed to load boot_loader.lua: " .. tostring(err))
    chunk()

    return mock_sr, kb_down, rects
end

local sr, kb, rects = boot_clean_environment()
local UML = _G.UML
assert(UML and (UML.version == "2.0.6" or UML.version == "2.0.5" or UML.version == "2.0.4" or UML.version == "2.0.3" or UML.version == "2.0.2" or UML.version == "2.0.1" or UML.version == "2.0.0"), "UML API global must be initialized")

-- Test 1: Mod Registration & Metadata
test("UML.register creates managed mod object with metadata", function()
    local my_mod = UML.register("TacticalSentryPlus", {
        version = "2.1.0",
        author = "SampleAuthor",
        description = "Upgrades sentry targeting AI and displays tactical ranges.",
        needs = { "BaseFramework" }
    })
    assert(type(my_mod) == "table", "my_mod must be a table")
    assert(my_mod.name == "TacticalSentryPlus")
    assert(my_mod.version == "2.1.0")
    assert(my_mod.author == "SampleAuthor")
    assert(type(my_mod.option) == "function", "my_mod:option must be a function")
    assert(type(my_mod.bind_key) == "function", "my_mod:bind_key must be a function")
    assert(type(my_mod.notify) == "function", "my_mod:notify must be a function")
    assert(type(my_mod.translate) == "function", "my_mod:translate must be a function")
end)

-- Test 2: In-Game F9 Submenu Option Registration
test("mod:option registers toggle, slider, and choices into ModOptionsMenu", function()
    local my_mod = UML.mods["TacticalSentryPlus"]
    assert(my_mod, "Registered mod must be cached in UML.mods")

    -- Register a toggle
    local ok1 = my_mod:option("laser_sight", {
        label = "Enable Sentry Laser",
        type = "toggle",
        default = true,
        description = "Shows real-time targeting beam."
    })
    assert(ok1 == true, "Toggle option registration must return true")

    -- Register a slider
    local ok2 = my_mod:option("scan_radius", {
        label = "Scan Radius (Meters)",
        type = "slider",
        min = 25, max = 150, step = 25,
        default = 75,
        description = "Maximum distance for sentry target acquisition."
    })
    assert(ok2 == true, "Slider option registration must return true")

    -- Register a multi-choice
    local ok3 = my_mod:option("targeting_mode", {
        label = "Target Priority",
        type = "choice",
        choices = { "Closest", "Heaviest Threat", "Fastest", "Patrols Only" },
        default = 2,
        description = "Specifies target selection algorithm."
    })
    assert(ok3 == true, "Choice option registration must return true")

    -- Verify getters and setters
    assert(my_mod:get("laser_sight") == true, "laser_sight must start at default true")
    assert(my_mod:get("scan_radius") == 75, "scan_radius must start at default 75")
    assert(my_mod:get("targeting_mode") == 2, "targeting_mode must start at choice 2")

    my_mod:set("laser_sight", false)
    assert(my_mod:get("laser_sight") == false, "laser_sight must update to false")
    my_mod:set("scan_radius", 125)
    assert(my_mod:get("scan_radius") == 125, "scan_radius must update to 125")
end)

-- Test 3: Keybinding with Chat Guard & Trigger Modes
test("mod:bind_key creates rebindable hotkey with multiplayer chat guard", function()
    local my_mod = UML.mods["TacticalSentryPlus"]
    local key_triggers = 0

    local ok = my_mod:bind_key("h", function(self)
        key_triggers = key_triggers + 1
        local laser = self:get("laser_sight")
        self:set("laser_sight", not laser)
        self:notify("LASER " .. (not laser and "ON" or "OFF"), 2.0)
    end, "press")
    assert(ok == true, "bind_key must return true")

    -- Verify binding appears in ModBindingsMenu
    local mbm = _G.ModBindingsMenu
    assert(mbm, "ModBindingsMenu must exist")
    assert(mbm.get_binding("TacticalSentryPlus.key_h") == "h", "Binding ID must match mod name prefix")

    -- Simulate pressing key 'h' while in-game (not chatting)
    kb[72] = true -- key 'h' down
    _G.update(0.016)
    kb[72] = false
    _G.update(0.016)
    assert(key_triggers == 1, "Hot key 'h' must trigger callback once, got: " .. tostring(key_triggers))

    -- Simulate opening in-game chat (Enter key)
    kb[13] = true -- press Enter
    _G.update(0.016)
    kb[13] = false
    _G.update(0.016)
    assert(UML.is_chat_open() == true, "Chat must be marked open")

    -- Now press 'h' while chat is open -> Hotkey MUST be blocked!
    kb[72] = true
    _G.update(0.016)
    kb[72] = false
    _G.update(0.016)
    assert(key_triggers == 1, "Hotkey 'h' MUST NOT trigger while typing in multiplayer chat!")

    -- Close chat with Enter
    kb[13] = true
    _G.update(0.016)
    kb[13] = false
    _G.update(0.016)
    assert(UML.is_chat_open() == false, "Chat must be marked closed")

    -- Press 'h' again -> Hotkey works again!
    kb[72] = true
    _G.update(0.016)
    kb[72] = false
    _G.update(0.016)
    assert(key_triggers == 2, "Hotkey must work again once chat is closed")
end)

-- Test 4: Toast Notifications
test("mod:notify pushes in-game HUD banner rendered across viewports", function()
    local my_mod = UML.mods["TacticalSentryPlus"]
    local initial_rects = #rects
    my_mod:notify("SENTRY OVERCLOCK ACTIVE", 3.0)

    _G.update(0.016)
    _G.render()

    local new_rects = #rects
    assert(new_rects > initial_rects, "Toast notification must draw pixel rectangles on screen")
end)

-- Test 5: Mod Translations & 14-Locale i18n
test("UML.register_translations and mod:translate return localized strings", function()
    local my_mod = UML.mods["TacticalSentryPlus"]

    UML.register_translations("TacticalSentryPlus", {
        en = { status_ready = "System Ready" },
        fr = { status_ready = "Système Prêt" },
        de = { status_ready = "System Bereit" },
        ru = { status_ready = "Система Готова" },
        ["zh-Hans"] = { status_ready = "系统就绪" }
    })

    UML.set_language("fr")
    assert(my_mod:translate("status_ready", "System Ready"):upper() == "SYSTEME PRET", "French translation must normalize cleanly")

    UML.set_language("de")
    assert(my_mod:translate("status_ready", "System Ready"):upper() == "SYSTEM BEREIT", "German translation must match")

    UML.set_language("ru")
    assert(my_mod:translate("status_ready", "System Ready"):upper() == "SISTEMA GOTOVA", "Russian translation must transliterate to Latin")

    UML.set_language("zh-Hans")
    -- Pure-CJK fallback returns English clean entry for 5x7 bitmap renderer
    assert(my_mod:translate("status_ready", "System Ready"):upper() == "SYSTEM READY", "CJK entry falls back cleanly")

    UML.set_language("en")
end)

-- Test 6: Mod Lifecycle & Circuit Breaker Fault Isolation
test("mod:on_update circuit breaker isolates faulty hook without crashing game", function()
    local broken_mod = UML.register("FaultyModTest", { version = "1.0.0" })
    local crash_count = 0

    broken_mod:on_update(function(dt)
        crash_count = crash_count + 1
        error("Simulated syntax/nil error in mod update code!")
    end)

    -- Trigger 12 frames of updates
    for frame = 1, 12 do
        local ok, err = pcall(_G.update, 0.016)
        assert(ok == true, "Engine update must never crash even if mod throws errors!")
    end

    -- Circuit breaker trips at 10 errors and quarantines the hook
    assert(crash_count == 10, "Circuit breaker must stop calling hook after 10 consecutive failures, got: " .. tostring(crash_count))
end)

-- Test 7: Topological Dependency Sorter
test("UML.sort_dependencies resolves mod dependencies into correct boot order", function()
    local list = { "Mod_C", "Mod_A", "Mod_B" }
    local deps = {
        Mod_C = { "Mod_B" },
        Mod_B = { "Mod_A" },
        Mod_A = {}
    }
    local sorted = UML.sort_dependencies(list, deps)
    assert(sorted[1] == "Mod_A" and sorted[2] == "Mod_B" and sorted[3] == "Mod_C", "DAG sorting failed")
end)

-- Test 8: 3-arg bind_key(action_id, key, cb), mod:on_change, and table register_translations
test("3-arg mod:bind_key, mod:on_change, and table UML.register_translations work seamlessly", function()
    local m = UML.register("UnifiedPillarMod", { version = "2.0.4", author = "Tester" })

    local changed_val = nil
    m:option("alpha", { label = "Alpha", type = "slider", default = 0.5, min = 0.1, max = 1.0, step = 0.1 })
    local ok_chg = m:on_change("alpha", function(v)
        changed_val = v
    end)
    assert(ok_chg == true, "mod:on_change must return true")
    m:set("alpha", 0.8)
    assert(math.abs((changed_val or 0) - 0.8) < 0.001, "mod:on_change callback must fire on mod:set")

    local hk_hits = 0
    local ok_bk, bind_id = m:bind_key("pulse_action", "f1", function()
        hk_hits = hk_hits + 1
    end)
    assert(ok_bk == true and bind_id == "UnifiedPillarMod.pulse_action", "3-arg bind_key must register explicit action id")
    kb[112] = true
    _G.update(0.016)
    kb[112] = false
    _G.update(0.016)
    assert(hk_hits == 1, "3-arg bind_key callback must fire on rising edge")

    local tr_fn = UML.register_translations({
        id = "UnifiedPillarMod",
        strings = {
            en = { title = "UNIFIED TITLE" },
            fr = { title = "TITRE UNIFIE" }
        }
    })
    assert(type(tr_fn) == "function", "Table-form UML.register_translations must return translator function")
    UML.set_language("fr")
    assert(m:translate("title") == "TITRE UNIFIE", "Table-form translation pack must resolve French string")
    UML.set_language("en")
end)

-- Test 9: Button / Action Option Type & mod:trigger
test("type = 'button' option triggers on_click and on_change via mod:trigger", function()
    local m = UML.mods["UnifiedPillarMod"]
    local clicks = 0
    local change_fired = false
    m:option("reset_action", {
        label = "Reset Action",
        type = "button",
        button_text = "RESET NOW",
        on_click = function(id)
            clicks = clicks + 1
        end,
        on_change = function()
            change_fired = true
        end
    })
    assert(m:trigger("reset_action") == true, "mod:trigger must return true for registered button")
    assert(clicks == 1 and change_fired == true, "Button option must invoke both on_click and on_change")
end)

-- Test 10: Structured Table Persistence via mod:set / mod:get (save_data / load_data)
test("mod:set and mod:get persist nested tables to disk without cluttering F9 menu", function()
    local m = UML.mods["UnifiedPillarMod"]
    local payload = {
        active_slot = 2,
        slots = {
            { name = "Helldiver Gold", armor = "B-01", cape = "Foesmasher" },
            { name = "Stealth Scout", armor = "SC-30", cape = "Trailblazer" }
        }
    }
    assert(m:save_data("loadout_presets", payload) == true, "mod:save_data must succeed")
    local loaded = m:load_data("loadout_presets")
    assert(type(loaded) == "table" and loaded.active_slot == 2 and #loaded.slots == 2, "In-memory table retrieval must match")
    assert(m:get("nonexistent_key", "fallback_val") == "fallback_val", "mod:get must return default_val when unset")

    -- Verify disk JSON round-trip contains serialized nested object/array
    local f = io.open(settings_path, "rb")
    assert(f ~= nil, "Settings file must exist on disk")
    local raw_json = f:read("*a")
    f:close()
    assert(raw_json:find('"UnifiedPillarMod.loadout_presets"', 1, true) ~= nil, "Nested table key must be serialized to JSON")
    assert(raw_json:find('"Helldiver Gold"', 1, true) ~= nil, "Nested array/object contents must be serialized to JSON")
end)

-- Test 11: Throttled on_update, Timers (after/every/cancel), and Managed Function Detours (hook/unhook)
test("Timers and managed function detours chain and isolate errors cleanly", function()
    local m = UML.mods["UnifiedPillarMod"]

    local throttle_Count = 0
    m:on_update(function(elapsed)
        throttle_Count = throttle_Count + 1
    end, 0.05)

    local after_fired = 0
    m:after(0.03, function()
        after_fired = after_fired + 1
    end)

    local every_fired = 0
    local tid = m:every(0.02, function()
        every_fired = every_fired + 1
    end)

    for _ = 1, 4 do _G.update(0.016) end -- total 0.064s
    assert(throttle_Count == 1, "Throttled on_update(fn, 0.05) must fire once in 0.064s, got " .. tostring(throttle_Count))
    assert(after_fired == 1, "mod:after(0.03) must fire exactly once, got " .. tostring(after_fired))
    assert(every_fired == 3, "mod:every(0.02) must fire 3 times in 0.064s, got " .. tostring(every_fired))

    assert(m:cancel_timer(tid) == true, "mod:cancel_timer must cancel active repeating timer")
    _G.update(0.05)
    assert(every_fired == 3, "Cancelled timer must not fire again")

    -- Function Detour Chaining & Error Fallback
    local target = {
        compute = function(x) return x * 2 end
    }
    m:hook(target, "compute", function(orig, x)
        return orig(x + 1)
    end)
    m:hook(target, "compute", function(orig, x)
        return orig(x) + 10
    end)
    assert(target.compute(5) == 22, "Chained hooks must compute ((5 + 1) * 2) + 10 = 22, got " .. tostring(target.compute(5)))

    -- Faulty hook fallback: if a hook throws, original chain still executes without crashing
    local bad_fn = function(orig, x)
        error("Simulated hook failure")
    end
    m:hook(target, "compute", bad_fn)
    assert(target.compute(5) == 22, "Faulty hook must fall back to remaining chain cleanly")

    m:unhook(target, "compute")
    assert(target.compute(5) == 10, "mod:unhook must restore original function (5 * 2 = 10)")
end)

-- Test 12: Unified UI & HUD Drawing API (UML.ui / mod.ui)
test("mod.ui screen_size, scale, color, rect, and text render safely", function()
    local m = UML.mods["UnifiedPillarMod"]
    local w, h = m.ui.screen_size()
    local px = m.ui.scale()
    assert(w == 1920 and h == 1080 and px == 2, "mod.ui.screen_size and scale must match 1080p mock")
    local before_rects = #rects
    local col = m.ui.color(255, 255, 215, 55)
    assert(m.ui.rect(20, 20, 120, 30, col, 900) == true, "mod.ui.rect must draw on active world GUI")
    assert(m.ui.text("HUD TEST", 26, 26, px, col, 910) == true, "mod.ui.text must draw pixel text on active world GUI")
    assert(#rects > before_rects + 5, "mod.ui.rect and mod.ui.text must emit GUI rectangles")
end)

-- Test 13: Foundational Audio API (UML.audio / mod:play_sound)
test("UML.audio and mod:play_sound safely wrap Stingray WwiseWorld", function()
    local m = UML.mods["UnifiedPillarMod"]
    local active_sounds = {}
    local rtpc_params = {}
    local mock_ww = { id = "wwise_main" }
    _G.stingray.Wwise = {
        wwise_world = function(w) return mock_ww end
    }
    _G.stingray.WwiseWorld = {
        trigger_event = function(ww, evt, unit)
            local pid = 500 + #active_sounds + 1
            active_sounds[pid] = { evt = evt, unit = unit, playing = true }
            return pid, 1
        end,
        stop_event = function(ww, pid)
            if active_sounds[pid] then active_sounds[pid].playing = false end
        end,
        is_playing = function(ww, pid)
            return active_sounds[pid] and active_sounds[pid].playing == true or false
        end,
        set_global_parameter = function(ww, name, val)
            rtpc_params[name] = val
        end
    }

    local pid = m:play_sound("play_ui_button_click")
    assert(pid == 501, "mod:play_sound must trigger Wwise event and return playing_id")
    assert(UML.audio.is_playing(pid) == true, "UML.audio.is_playing must return true while active")
    assert(UML.audio.set_parameter("menu_volume", 0.85) == true, "UML.audio.set_parameter must set Wwise RTPC")
    assert(rtpc_params["menu_volume"] == 0.85, "RTPC parameter value must match")
    assert(m:stop_sound(pid) == true, "mod:stop_sound must stop active Wwise event")
    assert(UML.audio.is_playing(pid) == false, "UML.audio.is_playing must return false after stop")
end)

-- Test 14: Foundational Engine API (UML.engine) & 7-Domain Architecture Verification
test("UML.engine and all 7 foundational domain APIs (config, input, ui, hooks, locales, audio, engine) work cohesively", function()
    local m = UML.mods["UnifiedPillarMod"]
    assert(type(UML.config) == "table" and type(m.config) == "table" and m.config ~= UML.config, "UML.config and scoped m.config must exist")
    assert(type(UML.input) == "table" and type(m.input) == "table" and m.input ~= UML.input, "UML.input and scoped m.input must exist")
    assert(type(UML.ui) == "table" and type(m.ui) == "table" and m.ui ~= UML.ui, "UML.ui and scoped m.ui must exist")
    assert(type(UML.hooks) == "table" and type(m.hooks) == "table" and m.hooks ~= UML.hooks, "UML.hooks and scoped m.hooks must exist")
    assert(type(UML.locales) == "table" and #UML.locales == 14 and UML.i18n == UML.locales, "UML.locales/i18n domain must preserve 14-locale array and methods")
    assert(type(m.locales) == "table" and #m.locales == 14 and m.i18n == m.locales and m.locales ~= UML.locales, "m.locales/i18n scoped domain must preserve 14-locale array")
    assert(type(UML.audio) == "table" and m.audio == UML.audio, "UML.audio domain must exist")
    assert(type(UML.engine) == "table" and m.engine == UML.engine, "UML.engine domain must exist")

    -- Test UML.locales domain methods directly
    local lang_tag = UML.locales.get()
    assert(lang_tag == "en", "UML.locales.get() must return active language tag")
    assert(UML.locales.sanitize("CAFÉ") == "CAFE", "UML.locales.sanitize must transliterate diacritics")

    -- Mock Stingray Unit, Camera, and PhysicsWorld for UML.engine
    local mock_unit = { alive = true, pos = { x = 10, y = 20, z = 30 } }
    _G.stingray.Unit = {
        alive = function(u) return type(u) == "table" and u.alive == true end,
        world_position = function(u, node) return u.pos end
    }
    _G.stingray.Camera = {
        world_to_screen = function(cam, wpos) return { x = 960, y = 540, z = 15 } end
    }
    _G.stingray.World.physics_world = function(w) return { id = "phys_main" } end
    _G.stingray.PhysicsWorld = {
        raycast = function(pw, from_pos, dir, dist, mode, k, filter)
            return true, { x = 10, y = 25, z = 30 }, 5.0, { x = 0, y = -1, z = 0 }, "hit_actor"
        end
    }

    assert(UML.engine.main_world() ~= nil, "UML.engine.main_world() must return active world")
    assert(UML.engine.unit_alive(mock_unit) == true, "UML.engine.unit_alive must detect live unit")
    local upos = UML.engine.unit_position(mock_unit)
    assert(upos and upos.y == 20, "UML.engine.unit_position must return world position")
    local sx, sy, sz = UML.engine.world_to_screen("cam", upos)
    assert(sx == 960 and sy == 540 and sz == 15, "UML.engine.world_to_screen must unpack 2D screen coordinates")
    local hit, hit_pos, hit_dist = UML.engine.raycast({ x = 10, y = 20, z = 30 }, { x = 0, y = 1, z = 0 }, 50)
    assert(hit == true and hit_dist == 5.0 and hit_pos.y == 25, "UML.engine.raycast must return hit result")

    -- Frame-safe Vector3Box
    local boxed = UML.engine.box_vec3(1.5, 2.5, 3.5)
    local unboxed = boxed:unbox()
    assert(unboxed.x == 1.5 and unboxed.y == 2.5 and unboxed.z == 3.5, "UML.engine.box_vec3 must safely persist and unbox Vector3")
end)

-- Test 15: Per-mod Scoped Domain Isolation & Zero Key Collisions
test("Scoped mod domains prevent cross-mod collisions and support dot + colon syntax", function()
    local m1 = UML.register("ScopedAlpha", { version = "1.0.0" })
    local m2 = UML.register("ScopedBeta", { version = "1.0.0" })

    assert(m1.config.register("enabled", { type = "boolean", default = true, label = "Alpha Enabled" }), "Alpha register")
    assert(m2.config.register("enabled", { type = "boolean", default = false, label = "Beta Enabled" }), "Beta register")
    assert(m1.config.get("enabled") == true and m2.config.get("enabled") == false, "Separate namespaces for 'enabled'")

    m1.config:set("enabled", false)
    assert(m1:get("enabled") == false and m1.config:get("enabled") == false, "m1 config:set syncs with m1:get")
    assert(m2.config:get("enabled") == false, "m2 unaffected by m1")

    -- Scoped config.reset() must only reset its own mod's options
    m2.config:set("enabled", true)
    m1.config:reset()
    assert(m1.config:get("enabled") == true, "m1.config:reset() restores m1 default")
    assert(m2.config:get("enabled") == true, "m1.config:reset() must NOT clobber m2 config")

    -- Scoped input bind & consume_press short ID resolution
    local fired_alpha = 0
    local fired_beta = 0
    assert(m1.input.bind("action", "h", function() fired_alpha = fired_alpha + 1 end), "Alpha bind")
    assert(m2.input:bind("action", "f1", function() fired_beta = fired_beta + 1 end), "Beta bind colon")

    kb[72] = true -- h
    _G.update(0.02)
    assert(fired_alpha == 1 and fired_beta == 0, "Scoped bind_id resolves independently")
    kb[72] = nil
    _G.update(0.02)

    -- Scoped locales pack & colon syntax
    assert(m1.locales.register({ en = { title = "Alpha Pack" } }), "m1.locales.register")
    assert(m2.locales:register({ en = { title = "Beta Pack" } }), "m2.locales:register colon")
    assert(m1.locales.translate("title") == "Alpha Pack", "m1.locales.translate isolated")
    assert(m2.locales:translate("title") == "Beta Pack", "m2.locales:translate isolated")

    -- Scoped ui.open focuses owning mod tab and supports colon syntax
    m1.ui:open()
    local st = m1.ui:get_state()
    assert(st.open == true and (st.mod_name == "SCOPED ALPHA" or st.mod_name == "SCOPEDALPHA" or st.mod_name == "ScopedAlpha"), "m1.ui:open focuses ScopedAlpha, got: " .. tostring(st.mod_name))
    m1.ui:close()
end)

-- Test 16: Global 7-Domain Colon-Syntax Parity
test("Global UML domains support both dot and colon invocation cleanly", function()
    local v1 = UML.engine.vec3(1, 2, 3)
    local v2 = UML.engine:vec3(4, 5, 6)
    assert(v1.x == 1 and v1.z == 3 and v2.x == 4 and v2.z == 6, "UML.engine:vec3 colon parity")
    assert(UML.locales:get() == UML.locales.get(), "UML.locales:get() colon parity")
    assert(UML.locales:sanitize("CAFÉ") == "CAFE", "UML.locales:sanitize() colon parity")
    local st = UML.ui:get_state()
    assert(type(st) == "table" and st.open == false, "UML.ui:get_state() colon parity")
    UML.config.register("GlobalColon.val", { type = "number", default = 7, min = 0, max = 10 })
    assert(UML.config:get("GlobalColon.val") == 7, "UML.config:get() colon parity")
    assert(UML.config:set("GlobalColon.val", 9) == true and UML.config:get("GlobalColon.val") == 9, "UML.config:set() colon parity")
end)

-- Test 17: Unbounded Hook Return Values (>4 returns) & Nil Holes
test("mod.hooks.hook preserves 5+ return values and nil holes", function()
    local m = UML.register("HookReturnsMod", { version = "1.0.0" })
    local target = {
        multi = function(self, a)
            return a, nil, "three", false, 5, 6
        end
    }
    m.hooks:hook(target, "multi", function(orig, self, a)
        return orig(self, a * 2)
    end)
    local r1, r2, r3, r4, r5, r6 = target:multi(10)
    assert(r1 == 20 and r2 == nil and r3 == "three" and r4 == false and r5 == 5 and r6 == 6,
        "Hook chain must preserve >4 return values and nil holes")
end)

-- Test 18: Dead :timer_ Pruning & VK_MAP Letter/Modifier Fallback
test("Completed/cancelled timers are pruned from update_order and VK_MAP handles letters + shift", function()
    local m = UML.register("TimerAndVKMod", { version = "1.0.0" })
    local fired = false
    local cancelled_fired = false
    m:after(0.01, function() fired = true end)
    local tid2 = m:after(0.01, function() cancelled_fired = true end)
    assert(m:cancel_timer(tid2) == true, "cancel_timer must return true")

    _G.update(0.05)
    assert(fired == true and cancelled_fired == false, "Timer execution check")

    local found_dead_timer = false
    local order = uml_internal and uml_internal.update_order
    if type(order) == "table" then
        for i = 1, #order do
            if type(order[i]) == "string" and order[i]:find(":timer_", 1, true) then
                found_dead_timer = true
            end
        end
    end
    assert(not found_dead_timer, "Dead :timer_ entries must be pruned from update_order")

    -- Fallback VK_MAP when Keyboard.button_id returns nil for letter/modifier
    local orig_btn_id = _G.stingray.Keyboard.button_id
    _G.stingray.Keyboard.button_id = function(name)
        return orig_btn_id(name) -- returns nil for 'k' and 'shift'
    end
    local k_hits = 0
    local shift_hits = 0
    assert(m:bind_key("k", function() k_hits = k_hits + 1 end), "Fallback VK_MAP must support letter keys")
    assert(m:bind_key("shift", function() shift_hits = shift_hits + 1 end), "Fallback VK_MAP must support shift")
    kb[75] = true  -- VK_K = 75
    kb[16] = true  -- VK_SHIFT = 16
    _G.update(0.02)
    assert(k_hits == 1 and shift_hits == 1, "Fallback VK_MAP keys must trigger callbacks")
    kb[75] = nil
    kb[16] = nil
    _G.update(0.02)
    _G.stingray.Keyboard.button_id = orig_btn_id
end)

-- Test 19: Engine immediate_raycast & Vector3Box.unbox Support
test("UML.engine.raycast supports Stingray immediate_raycast (pos-first return) and unbox_vec3", function()
    _G.stingray.PhysicsWorld = {
        immediate_raycast = function(pw, from_pos, dir, dist, mode, k, filter)
            if dir.y > 0 then
                return { x = 1, y = 2, z = 3 }, 4.5, { x = 0, y = -1, z = 0 }, "wall_actor"
            end
            return nil
        end
    }
    local hit, pos, dist, normal, actor = UML.engine.raycast({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, 20)
    assert(hit == true and pos.y == 2 and dist == 4.5 and normal.y == -1 and actor == "wall_actor",
        "immediate_raycast pos-first hit must map to (true, pos, dist, normal, actor)")
    local miss = UML.engine.raycast({ x = 0, y = 0, z = 0 }, { x = 0, y = -1, z = 0 }, 20)
    assert(miss == false, "immediate_raycast nil must map to false")

    _G.stingray.Vector3Box = {
        unbox = function(b) return UML.engine.vec3(b._x, b._y, b._z) end
    }
    local fake_box = { _x = 7, _y = 8, _z = 9 }
    local uv = UML.engine.unbox_vec3(fake_box)
    assert(uv.x == 7 and uv.y == 8 and uv.z == 9, "unbox_vec3 must invoke Vector3Box.unbox")
end)

print("----------------------------------------------------")
print(string.format("RESULTS: %d / %d author API tests passed.", pass_count, total_count))
print("STATUS: MODDING API FULLY VERIFIED AND FUNCTIONAL!")
print("====================================================")

if orig_settings_content then
    local f_res = io.open(settings_path, "wb")
    if f_res then
        f_res:write(orig_settings_content)
        f_res:close()
    end
end
if orig_settings_content2 then
    local f_res2 = io.open(settings_path2, "wb")
    if f_res2 then
        f_res2:write(orig_settings_content2)
        f_res2:close()
    end
end
if orig_settings_content3 then
    local f_res3 = io.open(settings_path3, "wb")
    if f_res3 then
        f_res3:write(orig_settings_content3)
        f_res3:close()
    end
end
if orig_settings_content4 then
    local f_res4 = io.open(settings_path4, "wb")
    if f_res4 then
        f_res4:write(orig_settings_content4)
        f_res4:close()
    end
else
    os.remove(settings_path4)
end
