-- tests/test_live_gui_simulation.lua
-- Comprehensive simulation of in-engine Stingray Gui, F9 2-Pane Per-Mod Submenu UI,
-- Native UML v2.0.0 Developer API, Chat/Window Focus Guard, and Toast Notifications.

local function run_test()
    print("====================================================")
    print("Testing In-Engine Multi-World GUI & v2.0.0 Subsystems")
    print("====================================================")

    local rects_drawn = 0
    local green_value_rects = 0
    local red_value_rects = 0
    local mock_gui_main = { id = "gui_main" }
    local mock_gui_top = { id = "gui_top" }
    local mock_world_main = { id = "world_main" }
    local mock_world_top = { id = "world_top" }

    local active_keys = {}
    local window_focused = true
    local stingray = {
        Application = {
            main_world = function() return mock_world_main end,
            worlds = function() return { mock_world_main, mock_world_top } end
        },
        Window = {
            has_focus = function() return window_focused end
        },
        World = {
            create_screen_gui = function(w, mode, ...)
                if w == mock_world_main then return mock_gui_main end
                if w == mock_world_top then return mock_gui_top end
                return { id = "gui_other" }
            end
        },
        Gui = {
            resolution = function() return 1920, 1080 end,
            rect = function(g, pos, sz, col)
                rects_drawn = rects_drawn + 1
                assert(type(pos.x) == "number", "pos.x must be number")
                assert(type(pos.y) == "number", "pos.y must be number")
                assert(type(sz.x) == "number", "sz.x must be number")
                assert(type(sz.y) == "number", "sz.y must be number")
                if col then
                    if col.r == 90 and col.g == 235 and col.b == 130 then
                        green_value_rects = green_value_rects + 1
                    elseif col.r == 230 and col.g == 95 and col.b == 95 then
                        red_value_rects = red_value_rects + 1
                    end
                end
            end
        },
        Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        Vector2 = function(x, y) return { x = x, y = y } end,
        Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
        Keyboard = {
            button_id = function(k)
                local kl = tostring(k):lower()
                if kl == "f9" then return 119 end
                if kl == "f1" then return 112 end
                if kl == "escape" or kl == "esc" then return 27 end
                if kl == "enter" or kl == "return" then return 13 end
                if kl == "up" or kl == "up_arrow" then return 38 end
                if kl == "down" or kl == "down_arrow" then return 40 end
                if kl == "left" or kl == "left_arrow" then return 37 end
                if kl == "right" or kl == "right_arrow" then return 39 end
                if kl == "delete" or kl == "del" then return 46 end
                if kl == "backspace" then return 8 end
                if kl == "tab" then return 9 end
                if kl == "space" then return 32 end
                if kl == "1" then return 49 end
                if kl == "2" then return 50 end
                if kl == "3" then return 51 end
                if kl == "4" then return 52 end
                if kl == "[" then return 219 end
                if kl == "]" then return 221 end
                return nil
            end,
            button = function(id) return active_keys[id] == true end,
            pressed = function(id) return active_keys[id] == true end
        }
    }
    _G.stingray = stingray

    -- Back up real user settings & log files if present on host
    local settings_path = (os.getenv("APPDATA") or "") .. "/Arrowhead/Helldivers2/uml_mod_settings.json"
    local settings_path2 = (os.getenv("LOCALAPPDATA") or "") .. "/UniversalModLoader/uml_mod_settings.json"
    local settings_path3 = (os.getenv("LOCALAPPDATA") or "") .. "/UniversalModLoader/mod_settings.json"
    local settings_path4 = "uml_mod_settings.json"
    local log_path = (os.getenv("APPDATA") or "") .. "/Arrowhead/Helldivers2/UniversalModLoader.log"
    local orig_settings_content = nil
    local orig_settings_content2 = nil
    local orig_settings_content3 = nil
    local orig_settings_content4 = nil
    local orig_log_content = nil
    do
        local sf = io.open(settings_path, "rb")
        if sf then
            orig_settings_content = sf:read("*a")
            sf:close()
            os.remove(settings_path)
        end
        local sf2 = io.open(settings_path2, "rb")
        if sf2 then
            orig_settings_content2 = sf2:read("*a")
            sf2:close()
            os.remove(settings_path2)
        end
        local sf3 = io.open(settings_path3, "rb")
        if sf3 then
            orig_settings_content3 = sf3:read("*a")
            sf3:close()
            os.remove(settings_path3)
        end
        local sf4 = io.open(settings_path4, "rb")
        if sf4 then
            orig_settings_content4 = sf4:read("*a")
            sf4:close()
            os.remove(settings_path4)
        end
        local lf = io.open(log_path, "rb")
        if lf then
            orig_log_content = lf:read("*a")
            lf:close()
        end
    end

    -- Load boot_loader chunk
    local f = io.open("G:/antigravity/UniversalModLoader-v1.0.0/src/boot_loader.lua", "r")
    assert(f, "Failed to open boot_loader.lua")
    local code = f:read("*a")
    f:close()

    local chunk, err = loadstring(code, "boot_loader.lua")
    assert(chunk, "Failed to compile boot_loader.lua: " .. tostring(err))

    -- Execute bootloader
    chunk()

    -- Verify ModOptionsMenu & ModBindingsMenu ABI
    local mom = _G.ModOptionsMenu
    local mbm = _G.ModBindingsMenu
    local uml = _G.UML
    assert(mom, "ModOptionsMenu must exist")
    assert(mom.api == 1 and mom.version >= 3, "ModOptionsMenu must expose api=1, version>=3")
    assert(mbm, "ModBindingsMenu must exist")
    assert(mbm.api == 1 and mbm.version >= 4, "ModBindingsMenu must expose api=1, version>=4")
    assert(uml and (uml.version == "2.0.1" or uml.version == "2.0.0"), "UML v2.0.1 global must exist")
    assert(#mom.order >= 6, "Must have at least 6 registered default options, got " .. tostring(#mom.order))
    print(string.format("  [PASS] ModOptionsMenu (v%d), ModBindingsMenu (v%d), & UML (%s) ABI verified", mom.version, mbm.version, uml.version))

    -- Verify Topological Dependency Sorter (Subsystem 14)
    local sorted_mods = uml.sort_dependencies({ "Mod_Dependent", "Mod_Core", "Mod_Middle" }, {
        Mod_Dependent = { "Mod_Middle" },
        Mod_Middle = { "Mod_Core" },
        Mod_Core = {}
    })
    assert(sorted_mods[1] == "Mod_Core" and sorted_mods[2] == "Mod_Middle" and sorted_mods[3] == "Mod_Dependent", "DAG topological sort failed")
    print("  [PASS] Topological Dependency Sorter (DAG) verified: Mod_Core -> Mod_Middle -> Mod_Dependent")

    -- Register third-party choice, slider, and binding options (matching EagleHudProbe, VehicleSeatSwitch, HelmetHeadlamp)
    assert(mom.register_option("eagle_radius_mode", {
        type = "choice",
        title = function() return "Eagle HUD" end,
        label = function() return "Danger Zone / 危险区" end,
        choices = { "Off / 关闭", "Full Damage / 满伤内半径", "Outer / 外圈" },
        default = 2
    }) == true, "register_option must return true")

    assert(mom.register_option("sentry_alpha", {
        type = "slider",
        title = "Sentry HUD",
        label = "HUD Opacity",
        min = 10,
        max = 100,
        step = 15,
        default = 55
    }) == true, "register_option for slider must return true")

    assert(mbm.register_binding("vehicle_seat_1", function() return "Switch to Driver Seat" end, function() return "Vehicle Seat Switch" end, {
        default = "f1"
    }) == true, "register_binding must return true")

    -- Ensure first option (uml_auto_reload, default = true) starts as true
    local opt1_id = mom.order[1]
    mom.set(opt1_id, true)
    assert(mom.get(opt1_id) == true, "Option 1 must start as true")

    -- Simulate frame 1: Idle
    update(0.016)
    render()
    assert(rects_drawn == 0, "No rects drawn when menu is closed")

    -- Simulate frame 2: Press F9 to open menu
    active_keys[119] = true
    update(0.016)
    active_keys[119] = false
    render()

    local frame2_rects = rects_drawn
    assert(frame2_rects > 1000, "Frame 2 must draw full menu across both worlds, got " .. tostring(frame2_rects))
    print(string.format("  [PASS] Frame 2 (F9 Pressed): Menu opened and drew %d rects across 2 worlds", frame2_rects))

    -- Simulate frame 3: Menu STAYS OPEN and REDRAWS EVERY FRAME
    rects_drawn = 0
    update(0.016)
    render()
    local frame3_rects = rects_drawn
    assert(frame3_rects == frame2_rects, "Frame 3 must redraw identically to Frame 2, got " .. tostring(frame3_rects))
    print(string.format("  [PASS] Frame 3 (Hold Open): Redrew %d rects once per frame", frame3_rects))

    -- Simulate frame 4: Press RIGHT arrow in "mods" pane to enter Mod #1 ("UML CORE") submenu ("options" pane)
    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    render()

    -- Record baseline green/red pixels inside UML CORE submenu before toggling
    rects_drawn = 0
    green_value_rects = 0
    red_value_rects = 0
    update(0.016)
    render()
    local green_when_all_true = green_value_rects
    local red_when_all_true = red_value_rects

    -- Simulate frame 5: Press RIGHT arrow inside "options" pane to toggle Option 1 (default = true) -> false
    rects_drawn = 0
    green_value_rects = 0
    red_value_rects = 0
    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    render()
    assert(mom.get(opt1_id) == false, "Right arrow in submenu must toggle boolean option from true to false")
    assert(red_value_rects > red_when_all_true, "Rendered GUI must draw more red pixels when default=true option is toggled to false!")
    assert(green_value_rects < green_when_all_true, "Rendered GUI must draw fewer green pixels when default=true option is toggled to false!")
    print(string.format("  [PASS] Submenu Toggle (Right Arrow): '%s' toggled true -> false and GUI rendered < OFF > in red!", opt1_id))

    -- Simulate frame 6: Press LEFT arrow to toggle Option 1 back false -> true
    active_keys[37] = true
    update(0.016)
    active_keys[37] = false
    render()
    assert(mom.get(opt1_id) == true, "Left arrow must toggle boolean option from false to true")
    print(string.format("  [PASS] Submenu Toggle (Left Arrow): '%s' toggled false -> true", opt1_id))

    -- Press BACKSPACE to return to Mod List sidebar, then DOWN arrow to Mod #2 (EAGLE HUD), then RIGHT arrow to enter its submenu
    active_keys[8] = true
    update(0.016)
    active_keys[8] = false
    update(0.016)

    active_keys[40] = true
    update(0.016)
    active_keys[40] = false
    update(0.016)

    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    update(0.016)

    assert(mom.get("eagle_radius_mode") == 2, "Choice option starts at default index 2")
    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    update(0.016)
    assert(mom.get("eagle_radius_mode") == 3, "Right arrow advances choice index 2 -> 3")
    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    update(0.016)
    assert(mom.get("eagle_radius_mode") == 1, "Right arrow wraps choice index 3 -> 1")
    print("  [PASS] Mod #2 Submenu ('EAGLE HUD' -> 'eagle_radius_mode'): Cycled 2 -> 3 -> 1 via Right Arrow")

    -- Test Direct Quick-Jump Key '3' to jump straight into Mod #3 ('SENTRY HUD') submenu!
    active_keys[51] = true
    update(0.016)
    active_keys[51] = false
    update(0.016)

    assert(mom.get("sentry_alpha") == 55, "Slider starts at 55")
    active_keys[39] = true
    update(0.016)
    active_keys[39] = false
    update(0.016)
    assert(mom.get("sentry_alpha") == 70, "Right arrow steps slider 55 -> 70")
    active_keys[46] = true
    update(0.016)
    active_keys[46] = false
    update(0.016)
    assert(mom.get("sentry_alpha") == 55, "Delete resets slider 70 -> 55 (default)")
    print("  [PASS] Quick-Jump Key [3] -> Mod #3 Submenu ('SENTRY HUD' -> 'sentry_alpha'): Stepped 55 -> 70 and reset to 55 via Delete")

    -- Simulate frame: Press ESCAPE to close menu
    active_keys[27] = true
    update(0.016)
    active_keys[27] = false
    rects_drawn = 0
    render()
    assert(rects_drawn == 0, "Menu closed cleanly, no rects drawn")
    print("  [PASS] Menu closed cleanly via ESC")

    -- Test Native UML v2.0.0 Developer API (`UML.register`, `:option`, `:bind_key`, `:on_update`, `:notify`)
    -- and Subsystem 11 (Chat Box & Window Focus Guard)
    local radar_mod = uml.register("TacticalRadar", { version = "1.0.0" })
    assert(type(radar_mod) == "table", "UML.register must return mod handle")
    radar_mod:option("radar_enabled", { type = "bool", label = "Enable Radar", default = true })
    assert(radar_mod:get("radar_enabled") == true, "radar_mod:get must return true")

    local f1_triggers = 0
    radar_mod:bind_key("f1", function()
        f1_triggers = f1_triggers + 1
    end, "pressed")

    -- 1. With menu closed, chat closed, and window focused: pressing F1 triggers both ModBindingsMenu and radar_mod:bind_key
    active_keys[112] = true
    update(0.016)
    assert(mbm.is_down("vehicle_seat_1") == true, "F1 binding should be down during normal gameplay")
    assert(f1_triggers == 1, "radar_mod:bind_key('f1') should fire once during normal gameplay")
    active_keys[112] = false
    update(0.016)

    -- 2. Press ENTER to open multiplayer chat box -> F1 must be blocked!
    active_keys[13] = true
    update(0.016)
    active_keys[13] = false
    update(0.016)
    assert(uml.is_chat_open() == true, "Pressing Enter during gameplay must mark chat open")

    active_keys[112] = true
    update(0.016)
    assert(mbm.is_down("vehicle_seat_1") == false, "Chat Box Guard must block ModBindingsMenu.is_down while chat is open!")
    assert(f1_triggers == 1, "Chat Box Guard must block mod:bind_key while chat is open!")
    active_keys[112] = false
    update(0.016)

    -- 3. Press ENTER again to submit/close chat -> F1 works again!
    active_keys[13] = true
    update(0.016)
    active_keys[13] = false
    update(0.016)
    assert(uml.is_chat_open() == false, "Pressing Enter again must mark chat closed")

    -- 4. Unfocus game window -> F1 must be blocked!
    window_focused = false
    active_keys[112] = true
    update(0.016)
    assert(mbm.is_down("vehicle_seat_1") == false, "Window Focus Guard must block ModBindingsMenu when unfocused!")
    assert(f1_triggers == 1, "Window Focus Guard must block mod:bind_key when unfocused!")
    active_keys[112] = false
    window_focused = true
    update(0.016)
    print("  [PASS] Native UML.register API + Chat Box & Window Focus Guard verified!")

    -- Test In-Game Toast Notification Banner (`radar_mod:notify`)
    rects_drawn = 0
    radar_mod:notify("RADAR ONLINE", 1.5)
    update(0.016)
    render()
    assert(rects_drawn > 50, "Toast notification banner must draw pixel-font rects when active")
    print(string.format("  [PASS] In-Game Toast Notification Banner rendered (%d rects across 2 worlds)", rects_drawn))

    -- Test Synthetic PE Header in kernel32 / ffi stub (used by Smarter Guard Dogs & Sentries and Sentry HUD)
    local ffi_lib = require("ffi")
    local k32 = ffi_lib.load("kernel32")
    local g_base = tonumber(ffi_lib.cast("uintptr_t", k32.GetModuleHandleA("game.dll")))
    local e_base = tonumber(ffi_lib.cast("uintptr_t", k32.GetModuleHandleA(nil)))
    assert(g_base ~= e_base, "game.dll and exe mock base addresses must be distinct")
    local buf = ffi_lib.new("uint8_t[1024]")
    local done = ffi_lib.new("size_t[1]")
    local rpm_ok = k32.ReadProcessMemory(k32.GetCurrentProcess(), ffi_lib.cast("const void *", g_base), buf, 1024, done)
    assert(rpm_ok == 1 and tonumber(done[0]) == 1024, "ReadProcessMemory must return 1024 bytes for game.dll PE header")
    local pe_str = ffi_lib.string(buf, 1024)
    assert(pe_str:sub(1, 2) == "MZ" and pe_str:sub(129, 132) == "PE\0\0", "Synthetic PE header must contain valid MZ and PE signatures")
    print("  [PASS] Synthetic PE Header for Smarter Guard Dogs & Sentries and Sentry HUD verified!")

    -- Test Official 14-Locale Helldivers 2 Support, UTF-8 Transliteration, and BingusTranslations Protocol
    assert(type(uml.locales) == "table" and #uml.locales == 14, "Must support all 14 official Helldivers 2 locales")
    assert(_G.BingusTranslations and _G.BingusTranslations.version == 1, "BingusTranslations protocol table must exist")
    assert(uml.transliterate("Améliorée / Größe / Configuración / Przełącznik"):upper() == "AMELIOREE / GROSSE / CONFIGURACION / PRZELACZNIK", "European diacritics must transliterate cleanly to ASCII")
    assert(uml.transliterate("Настройки"):upper() == "NASTROYKI", "Russian Cyrillic must transliterate cleanly to ASCII")
    local t_fn = uml.register_translations("test_pack", {
        en = { seat = "Driver Seat" },
        fr = { seat = "Siège Conducteur" },
        ru = { seat = "Место водителя" },
        ["zh-Hans"] = { seat = "驾驶座" },
    })
    local seat_label = function() return t_fn("seat") end
    uml.set_language("fr")
    assert(_G.BingusTranslations.game_language == "fr" and _G.BingusTranslations.game_code == "fr", "Setting fr must update BingusTranslations")
    assert(uml.transliterate(seat_label):upper() == "SIEGE CONDUCTEUR", "French pack string must transliterate with zero dropped letters")
    uml.set_language("ru")
    assert(_G.BingusTranslations.game_language == "ru" and _G.BingusTranslations.game_code == "ru", "Setting ru must update BingusTranslations")
    assert(uml.transliterate(seat_label):upper() == "MESTO VODITELYA", "Russian pack string must transliterate to Latin")
    uml.set_language("zh-Hans")
    assert(_G.BingusTranslations.game_language == "zh-Hans" and _G.BingusTranslations.game_code == "cn", "Setting zh-Hans must update BingusTranslations")
    assert(uml.transliterate(seat_label):upper() == "DRIVER SEAT", "Pure-CJK closure must automatically fall back to English pack entry so it never renders '?'")
    -- Test 4-tier Auto-Detect cascade (e.g. via stingray.Steam.language())
    _G.stingray.Steam = { language = function() return "german" end }
    local auto_tag, auto_code = uml.set_language("auto")
    assert(auto_tag == "de" and auto_code == "de", "Auto-detect must pick up stingray.Steam.language() -> de")
    assert(mom.get("uml_language") == 1, "Setting 'auto' must set uml_language choice index to 1 (Auto-Detect)")
    _G.stingray.Steam = nil
    uml.set_language("auto")
    print("  [PASS] All 14 Official Helldivers 2 Locales + 4-Tier Auto-Detection + UTF-8 Transliteration verified!")

    -- Restore clean settings & log files after simulation
    if orig_settings_content then
        local sf = io.open(settings_path, "wb")
        if sf then
            sf:write(orig_settings_content)
            sf:close()
        end
    end
    if orig_settings_content2 then
        local sf2 = io.open(settings_path2, "wb")
        if sf2 then
            sf2:write(orig_settings_content2)
            sf2:close()
        end
    end
    if orig_settings_content3 then
        local sf3 = io.open(settings_path3, "wb")
        if sf3 then
            sf3:write(orig_settings_content3)
            sf3:close()
        end
    end
    if orig_settings_content4 then
        local sf4 = io.open(settings_path4, "wb")
        if sf4 then
            sf4:write(orig_settings_content4)
            sf4:close()
        end
    end
    if orig_log_content then
        local lf = io.open(log_path, "wb")
        if lf then
            lf:write(orig_log_content)
            lf:close()
        end
    end

    print("====================================================")
    print("STATUS: ALL IN-ENGINE SIMULATION TESTS PASSED 100%!")
    print("====================================================")
end

run_test()
