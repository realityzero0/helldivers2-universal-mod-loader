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
local orig_settings_content = nil
local orig_settings_content2 = nil
local orig_settings_content3 = nil
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
assert(UML and (UML.version == "2.0.3" or UML.version == "2.0.2" or UML.version == "2.0.1" or UML.version == "2.0.0"), "UML API global must be initialized")

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
