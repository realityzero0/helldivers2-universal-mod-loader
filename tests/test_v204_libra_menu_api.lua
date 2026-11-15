-- tests/test_v204_libra_menu_api.lua
-- Regression & API tests for Libra / Uniformity collaboration features:
--   1. Public Menu State & Control API (UML.menu / UML.ui / ModOptionsMenu.menu / mod_obj)
--   2. Built-in Compact Menu Mode (Right / Left / Center layouts + F9 <-> Compact seamless transitions)
--   3. Menu-Allowed Keybindings (allow_in_menu = true) + Edge-Latched Polling (consume_press)
--      across menu, chat, key-capture, and window-unfocus blocked states (zero delayed edges)
--   4. External Menu Registration (set_external_open) without Window spoofing
--   5. Per-Mod Compact Shortcut (mod:register_compact_menu) & spec.compact_menu
--   6. Backward Compatibility with Uniformity 2.64's connect_native() closure-upvalue bridge

local function run_test()
    print("====================================================")
    print("Testing Public Menu State, Compact Menu & Allow-In-Menu Key API")
    print("====================================================")

    -- Back up real user settings & log files if present on host
    local settings_paths = {
        (os.getenv("APPDATA") or "") .. "/Arrowhead/Helldivers2/uml_mod_settings.json",
        (os.getenv("LOCALAPPDATA") or "") .. "/UniversalModLoader/uml_mod_settings.json",
        (os.getenv("LOCALAPPDATA") or "") .. "/UniversalModLoader/mod_settings.json",
        "uml_mod_settings.json"
    }
    local log_path = (os.getenv("APPDATA") or "") .. "/Arrowhead/Helldivers2/UniversalModLoader.log"
    local backups = {}
    for _, sp in ipairs(settings_paths) do
        local f = io.open(sp, "rb")
        if f then
            backups[sp] = f:read("*a")
            f:close()
            os.remove(sp)
        end
    end
    local lf = io.open(log_path, "rb")
    if lf then
        backups[log_path] = lf:read("*a")
        lf:close()
    end

    local function restore_files()
        for _, sp in ipairs(settings_paths) do
            os.remove(sp)
            if backups[sp] then
                local wf = io.open(sp, "wb")
                if wf then wf:write(backups[sp]); wf:close() end
            end
        end
        if backups[log_path] then
            local wf = io.open(log_path, "wb")
            if wf then wf:write(backups[log_path]); wf:close() end
        end
    end

    local ok_all, err_all = pcall(function()
        local rects = {}
        local mock_gui_main = { id = "gui_main" }
        local mock_world_main = { id = "world_main" }
        local active_keys = {}
        local window_focused = true
        local mock_res_w, mock_res_h = 1920, 1080

        local key_map = {
            f2 = 113, f5 = 116, f7 = 118, f8 = 119, f9 = 120, f10 = 121,
            ["j"] = 74, ["k"] = 75, ["l"] = 76, ["m"] = 77, ["n"] = 78, ["p"] = 80, ["q"] = 81,
            escape = 27, esc = 27, enter = 13, ["numpad enter"] = 13, ["return"] = 13,
            up = 38, down = 40, left = 37, right = 39,
            space = 32, tab = 9, backspace = 8, delete = 46, del = 46,
            ["left ctrl"] = 17, ["right ctrl"] = 17, ctrl = 17,
            ["["] = 219, ["left bracket"] = 219, ["]"] = 221, ["right bracket"] = 221,
            ["-"] = 189, minus = 189, ["="] = 187, equals = 187, equal = 187,
            ["1"] = 49, ["2"] = 50
        }

        _G.stingray = {
            Application = {
                main_world = function() return mock_world_main end,
                worlds = function() return { mock_world_main } end
            },
            Window = {
                has_focus = function() return window_focused end
            },
            World = {
                create_screen_gui = function() return mock_gui_main end
            },
            Gui = {
                resolution = function() return mock_res_w, mock_res_h end,
                rect = function(g, pos, sz, col)
                    rects[#rects + 1] = { x = pos.x, y = pos.y, z = pos.z, w = sz.x, h = sz.y, col = col }
                end
            },
            Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
            Vector2 = function(x, y) return { x = x, y = y } end,
            Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
            Keyboard = {
                button_id = function(k) return key_map[tostring(k):lower()] end,
                button = function(id) return active_keys[id] == true end,
                pressed = function(id) return active_keys[id] == true end
            }
        }

        -- Clean globals so boot_loader initializes fresh
        local clear_keys = {
            "ModOptionsMenu", "ModBindingsMenu", "CowboyBingusModLoader",
            "BingusRuntime", "HD2Runtime", "ChefSharedLoader",
            "RatsSharedLoader", "UML", "UniversalModLoader",
            "__uml_master_update", "__uml_master_render",
            "update", "render"
        }
        for _, k in ipairs(clear_keys) do _G[k] = nil end
        package.loaded["UML"] = nil
        package.loaded["ModOptionsMenu"] = nil
        package.loaded["ModBindingsMenu"] = nil

        assert(loadfile("src/boot_loader.lua"))()

        assert(type(_G.UML) == "table", "UML global must exist")
        assert(type(UML.menu) == "table", "UML.menu table must exist")
        assert(UML.menu == UML.ui, "UML.ui must alias UML.menu")
        assert(ModOptionsMenu.menu == UML.menu, "ModOptionsMenu.menu must alias UML.menu")

        local visual_lock_hits = 0
        local gameplay_hits = 0

        local mod = UML.register("Uniformity", {
            version = "2.64",
            author = "Libralion"
        })
        mod:option("enable_mod", {
            label = "Enable Uniformity",
            type = "toggle",
            default = true,
            description = "Master toggle"
        })
        mod:option("menu_layout", {
            label = "Menu Layout",
            type = "choice",
            default = 1,
            choices = { "Right", "Left", "Center", "Full Screen" }
        })
        mod:bind_key("f7", function()
            visual_lock_hits = visual_lock_hits + 1
        end, "press", {
            id = "visual_lock",
            label = "Toggle Visual Lock",
            allow_in_menu = true
        })
        mod:bind_key("k", function()
            gameplay_hits = gameplay_hits + 1
        end, "press", {
            id = "gameplay_action",
            label = "Gameplay Only Key"
        })
        mod:register_compact_menu({
            key = "f10",
            id = "uniformity.compact_menu_key",
            label = "Compact Menu Key",
            layout = 1,
            layout_option_id = "Uniformity.menu_layout"
        })

        -- Track state listener notifications
        local listener_states = {}
        UML.menu.on_change(function(st)
            listener_states[#listener_states + 1] = st
        end)

        -- 1. Test initial closed state
        local st0 = UML.get_menu_state()
        assert(st0.ready == true, "menu state must be ready")
        assert(st0.open == false and UML.is_menu_open() == false, "menu starts closed")
        assert(st0.compact == false and UML.is_compact_menu_open() == false, "compact starts closed")
        assert(st0.fullscreen == false and UML.is_fullscreen_menu_open() == false, "fullscreen starts closed")
        assert(st0.capture == false and UML.is_capturing_key() == false, "capture starts false")
        assert(st0.chat_open == false and UML.is_chat_active() == false, "chat starts closed")
        assert(st0.window_focused == true and UML.is_window_focused() == true, "window starts focused")
        assert(st0.gameplay_input_allowed == true, "gameplay input allowed initially")
        print("  [PASS] Initial public menu state & listeners")

        -- 2. Test opening compact menu targeted to Uniformity in Right / Left / Center layouts + rendering
        assert(UML.open_menu("Uniformity", { compact = true, layout = 1 }) == true)
        local st_r = UML.get_menu_state()
        assert(st_r.open == true and st_r.compact == true and st_r.fullscreen == false, "must open compact")
        assert(st_r.layout == 1, "layout must be 1 (Right)")
        assert(st_r.mod_name == "UNIFORMITY", "must target Uniformity mod group, got " .. tostring(st_r.mod_name))
        assert(st_r.focus == "options", "compact mode targeting a mod must focus options")
        assert(#listener_states >= 1 and listener_states[#listener_states].compact == true, "listener notified")

        rects = {}
        _G.update(0.016)
        assert(#rects > 0, "compact menu Right must render gui rects")
        local panel_right = rects[2] -- rect[1] is gold border, rect[2] is main slate panel
        assert(panel_right.w == math.max(420, math.floor(1920 * 0.35)), "compact width must be 35% of W")
        assert(panel_right.h == math.max(380, math.floor(1080 * 0.58)), "compact height must be 58% of H")
        assert(panel_right.x > 1100, "Right layout panel x must be near right edge, got " .. tostring(panel_right.x))

        -- Layout 2 = Left
        UML.open_menu("Uniformity", { compact = true, layout = "left" })
        assert(UML.get_menu_state().layout == 2)
        rects = {}
        _G.update(0.016)
        local panel_left = rects[2]
        assert(panel_left.x < 100, "Left layout panel x must be near left edge, got " .. tostring(panel_left.x))

        -- Layout 3 = Center
        UML.open_menu("Uniformity", { compact = true, layout = 3 })
        assert(UML.get_menu_state().layout == 3)
        rects = {}
        _G.update(0.016)
        local panel_center = rects[2]
        assert(panel_center.x > panel_left.x and panel_center.x < panel_right.x, "Center layout must sit between Left and Right")
        print("  [PASS] Compact Menu targeting + Right/Left/Center geometry & rendering")

        -- 3. Test seamless transition F9 (Compact -> Fullscreen -> Closed) and F10 shortcut
        active_keys[key_map.f9] = true
        _G.update(0.016)
        active_keys[key_map.f9] = false
        _G.update(0.016)
        assert(UML.is_fullscreen_menu_open() == true and UML.is_compact_menu_open() == false, "F9 in compact must expand seamlessly to fullscreen")

        -- Now press F10 while fullscreen is open -> switches directly to Uniformity compact Right!
        active_keys[key_map.f10] = true
        _G.update(0.016)
        active_keys[key_map.f10] = false
        _G.update(0.016)
        assert(UML.is_compact_menu_open() == true and UML.get_menu_state().mod_name == "UNIFORMITY", "F10 from fullscreen must switch to Uniformity compact")

        -- Press F10 again -> closes compact menu!
        active_keys[key_map.f10] = true
        _G.update(0.016)
        active_keys[key_map.f10] = false
        _G.update(0.016)
        assert(UML.is_menu_open() == false, "F10 again must close compact menu")
        print("  [PASS] F9 <-> Compact seamless toggle & F10 compact shortcut")

        -- 4. Test allow_in_menu = true keybinding vs regular gameplay keybinding inside open menu
        UML.open_menu("Uniformity", { compact = true, layout = 1 })
        assert(UML.is_menu_open() == true)
        assert(UML.is_input_blocked(false) == true, "gameplay input must be blocked inside menu")
        assert(UML.is_input_blocked(true) == false, "allow_in_menu input must be allowed inside menu")

        -- Press F7 (allow_in_menu = true) AND K (gameplay only) while menu is open
        active_keys[key_map.f7] = true
        active_keys[key_map["k"]] = true
        _G.update(0.016)
        assert(visual_lock_hits == 1, "F7 allow_in_menu binding MUST fire inside open menu (hits=" .. tostring(visual_lock_hits) .. ")")
        assert(gameplay_hits == 0, "Regular gameplay binding K must NOT fire inside open menu")

        -- Repeat while F7 still held -> must NOT re-trigger press
        _G.update(0.016)
        assert(visual_lock_hits == 1, "Holding F7 must not repeat press edge")

        active_keys[key_map.f7] = false
        active_keys[key_map["k"]] = false
        _G.update(0.016)
        print("  [PASS] allow_in_menu = true keybinding works inside menu while gameplay binds stay gated")

        -- 5. Test ModBindingsMenu.consume_press + Blocked-State Edge Latch across Chat, Key Capture & Unfocus
        mod:bind_key("l", function() end, "press", {
            id = "poll_test",
            label = "Poll Edge Test",
            allow_in_menu = true
        })

        -- 5a. Hold L while UN-FOCUSED, then re-focus while STILL holding L -> ZERO delayed edge!
        window_focused = false
        active_keys[key_map["l"]] = true
        _G.update(0.016)
        assert(mod:consume_key_press("poll_test", true) == false, "L pressed while unfocused must return false")
        window_focused = true
        _G.update(0.016)
        assert(mod:consume_key_press("poll_test", true) == false, "Re-focusing while L still held must NOT fire delayed edge!")
        active_keys[key_map["l"]] = false
        _G.update(0.016)
        assert(mod:consume_key_press("poll_test", true) == false, "Release after latch returns false")
        -- Now fresh press -> MUST fire!
        active_keys[key_map["l"]] = true
        _G.update(0.016)
        assert(ModBindingsMenu.is_pressed("Uniformity.poll_test", true) == true, "is_pressed true on fresh press")
        assert(mod:consume_key_press("poll_test", true) == true, "consume_key_press returns true once")
        assert(mod:consume_key_press("poll_test", true) == false, "second consume_key_press in same frame returns false")
        active_keys[key_map["l"]] = false
        _G.update(0.016)

        -- 5b. Hold F7 while CHAT is open, close chat while F7 still held -> ZERO delayed edge!
        UML.close_menu()
        -- Open chat via Enter key
        key_map["enter"] = 13
        active_keys[13] = true
        _G.update(0.016)
        active_keys[13] = false
        _G.update(0.016)
        assert(UML.is_chat_active() == true, "Enter must activate chat guard")

        local before_chat_hits = visual_lock_hits
        active_keys[key_map.f7] = true
        _G.update(0.016)
        assert(visual_lock_hits == before_chat_hits, "F7 must NOT fire while chat is open")

        -- Close chat via Esc while F7 is STILL held!
        active_keys[key_map.escape] = true
        _G.update(0.016)
        active_keys[key_map.escape] = false
        _G.update(0.016)
        assert(UML.is_chat_active() == false, "Esc must close chat")
        assert(visual_lock_hits == before_chat_hits, "Closing chat while F7 STILL held must NOT fire delayed edge!")

        -- Release F7 then press F7 cleanly -> fires!
        active_keys[key_map.f7] = false
        _G.update(0.016)
        active_keys[key_map.f7] = true
        _G.update(0.016)
        assert(visual_lock_hits == before_chat_hits + 1, "Fresh F7 press after release must fire normally")
        active_keys[key_map.f7] = false
        _G.update(0.016)
        print("  [PASS] Blocked-state edge latch across Window Unfocus & Chat (zero delayed triggers)")

        -- 6. Test External Menu Registration (replaces stingray.Window spoofing)
        UML.menu.set_external_open("uniformity_custom_panel", true)
        local st_ext = UML.get_menu_state()
        assert(st_ext.open == true and st_ext.external_open == true and st_ext.gameplay_input_allowed == false, "external menu blocks gameplay input cleanly")
        active_keys[key_map["k"]] = true
        _G.update(0.016)
        assert(gameplay_hits == 0, "Gameplay key K suppressed during external menu without Window spoofing")
        active_keys[key_map["k"]] = false
        _G.update(0.016)
        UML.menu.set_external_open("uniformity_custom_panel", false)
        assert(UML.get_menu_state().gameplay_input_allowed == true, "Clearing external menu restores gameplay input")
        active_keys[key_map["k"]] = true
        _G.update(0.016)
        assert(gameplay_hits == 1, "Gameplay key K works normally once external menu closed")
        active_keys[key_map["k"]] = false
        _G.update(0.016)
        print("  [PASS] External menu registration gates gameplay input cleanly")

        -- 7. Test Uniformity 2.64's exact connect_native() closure-upvalue bridge backward compatibility
        local function find_upvalue(fn, name)
            local i = 1
            while true do
                local n, v = debug.getupvalue(fn, i)
                if not n then return nil end
                if n == name then return i, v end
                i = i + 1
            end
        end
        local master_fn = rawget(_G, "__uml_master_update")
        assert(type(master_fn) == "function", "__uml_master_update must exist")
        local _, handle_input_fn = find_upvalue(master_fn, "handle_uml_menu_input")
        assert(type(handle_input_fn) == "function", "handle_uml_menu_input upvalue must exist on __uml_master_update")
        local idx_open, val_open = find_upvalue(handle_input_fn, "uml_ui_open")
        local idx_cap = find_upvalue(handle_input_fn, "uml_key_capture_id")
        local idx_chat = find_upvalue(handle_input_fn, "uml_chat_open")
        local idx_logged = find_upvalue(handle_input_fn, "uml_menu_open_logged")
        assert(idx_open and idx_cap and idx_chat and idx_logged, "All 4 Uniformity 2.64 bridge upvalues must exist on handle_uml_menu_input")
        assert(type(val_open) == "boolean", "uml_ui_open upvalue must be boolean")

        -- Verify setting key capture via bridge blocks allow_in_menu hotkeys and exposes is_capturing_key() == true
        debug.setupvalue(handle_input_fn, idx_cap, "uniformity.key_bind_test")
        assert(UML.is_capturing_key() == true and UML.menu.get_capture_id() == "uniformity.key_bind_test")
        local pre_cap_hits = visual_lock_hits
        active_keys[key_map.f7] = true
        _G.update(0.016)
        assert(visual_lock_hits == pre_cap_hits, "F7 must not fire while key capture is active")
        debug.setupvalue(handle_input_fn, idx_cap, nil)
        -- Still holding F7 after capture ends -> must NOT delayed-fire!
        _G.update(0.016)
        assert(visual_lock_hits == pre_cap_hits, "Ending key capture while F7 held must NOT delayed-fire")
        active_keys[key_map.f7] = false
        _G.update(0.016)
        print("  [PASS] Uniformity 2.64 / 3.0 connect_native() closure-bridge 100% preserved & capture latch verified")

        -- 8. Test Uniformity 3.0 (_G.UniformityMenu) automatic bridge awareness in UML menu state API
        local mock_u3_state = {
            compact = true,
            fullscreen = false,
            focus = "options",
            capture = "uniformity.lock_visual_key",
            group_index = 2,
            ready = true
        }
        _G.UniformityMenu = {
            version = "3.0",
            state = function() return mock_u3_state end
        }
        assert(UML.is_menu_open() == true, "UML.is_menu_open must see Uniformity 3.0 compact menu")
        assert(UML.is_compact_menu_open() == true, "UML.is_compact_menu_open must see Uniformity 3.0 compact menu")
        assert(UML.is_capturing_key() == true, "UML.is_capturing_key must see Uniformity 3.0 capture")
        assert(UML.get_capture_id() == "uniformity.lock_visual_key", "UML.get_capture_id must return Uniformity 3.0 capture id")
        local st_u3 = UML.get_menu_state()
        assert(st_u3.open == true and st_u3.compact == true and st_u3.external_open == true and st_u3.capture == true and st_u3.gameplay_input_allowed == false)
        mock_u3_state.compact = false
        mock_u3_state.capture = nil
        assert(UML.is_menu_open() == false and UML.is_compact_menu_open() == false and UML.is_capturing_key() == false)
        _G.UniformityMenu = nil
        print("  [PASS] Uniformity 3.0 (_G.UniformityMenu) live state automatically reflected in UML API")

        -- Enable full Keyboard enumeration for hardware key-capture regression suites (Sections 9-14)
        local primary_key_names = {
            [8] = "backspace", [9] = "tab", [13] = "enter", [17] = "left ctrl", [27] = "escape",
            [32] = "space", [37] = "left", [38] = "up", [39] = "right", [40] = "down", [46] = "delete",
            [49] = "1", [50] = "2", [74] = "j", [75] = "k", [76] = "l", [77] = "m", [78] = "n", [80] = "p", [81] = "q",
            [113] = "f2", [116] = "f5", [118] = "f7", [119] = "f8", [120] = "f9", [121] = "f10",
            [187] = "equal", [189] = "minus", [219] = "left bracket", [221] = "right bracket"
        }
        _G.stingray.Keyboard.num_buttons = function() return 256 end
        _G.stingray.Keyboard.button_name = function(idx) return primary_key_names[idx] end

        -- 9. Rebinding/reset stale latches, "off" cleanup, MOM/MBM sync, dispatch release misfire, poll(..., allow_in_menu=false)
        UML.close_menu()
        _G.update(0.016)
        local rebind_mod = UML.register("RebindSuite", { version = "1.0" })
        local rebind_change_count = 0
        ModBindingsMenu.register_binding("rebind_held", "Rebind Held", "k", { category = "RebindSuite", allow_in_menu = false })
        ModOptionsMenu.on_change("rebind_held", function() rebind_change_count = rebind_change_count + 1 end)

        -- Rebinding to "j" while "j" is ALREADY physically down must latch (zero misfire until release+repress)
        active_keys[key_map.j] = true
        ModBindingsMenu.set_binding("rebind_held", "j")
        assert(ModBindingsMenu.is_pressed("rebind_held") == false, "Rebind to currently held key must not trigger is_pressed")
        assert(ModBindingsMenu.consume_press("rebind_held") == false, "Rebind to currently held key must not trigger consume_press")
        assert(ModBindingsMenu.is_down("rebind_held") == false, "Rebind to currently held key must stay latched down until release")
        _G.update(0.016)
        assert(ModBindingsMenu.is_pressed("rebind_held") == false, "Holding rebind key across next frame must still be latched")
        active_keys[key_map.j] = false
        _G.update(0.016)
        active_keys[key_map.j] = true
        _G.update(0.016)
        assert(ModBindingsMenu.consume_press("rebind_held") == true, "Fresh press after releasing rebind key must succeed")

        -- Unbinding ("off") while held must clean poll_edge_state immediately
        assert(ModBindingsMenu.set_binding("rebind_held", nil) == true)
        assert(ModBindingsMenu.get_binding("rebind_held") == "off")
        assert(ModBindingsMenu.is_down("rebind_held") == false)
        assert(ModBindingsMenu.is_pressed("rebind_held") == false)
        assert(ModBindingsMenu.consume_press("rebind_held") == false)
        active_keys[key_map.j] = false
        _G.update(0.016)

        -- Release-mode callback must NOT misfire when rebound from held "j" to unheld "m"
        local release_hits = 0
        rebind_mod:bind_key("j", function() release_hits = release_hits + 1 end, "release", { id = "rel_guard", label = "Release Guard" })
        active_keys[key_map.j] = true
        _G.update(0.016)
        assert(release_hits == 0)
        ModBindingsMenu.set_binding("RebindSuite.rel_guard", "m")
        active_keys[key_map.j] = false
        _G.update(0.016)
        assert(release_hits == 0, "Rebinding held key to up key must not misfire release callback")

        -- Direct ModOptionsMenu.set & Del-key reset_option syncs MBM + latches held target key
        active_keys[key_map.m] = true
        ModOptionsMenu.set("rebind_held", "m")
        assert(ModBindingsMenu.get_binding("rebind_held") == "m" and ModBindingsMenu.assignments["rebind_held"] == "m", "MOM.set must sync MBM")
        assert(ModBindingsMenu.is_pressed("rebind_held") == false and ModBindingsMenu.is_down("rebind_held") == false, "MOM.set to held key must latch")
        active_keys[key_map.m] = false
        _G.update(0.016)

        -- Test explicit allow_in_menu = false override on poll/is_down/is_pressed/consume_press when rec.allow_in_menu == true
        UML.open_menu("Uniformity", { compact = false })
        active_keys[key_map.f7] = true
        local poll_out = {}
        ModBindingsMenu.poll({ "Uniformity.visual_lock" }, poll_out, false)
        assert(poll_out.down[1] == false, "MBM.poll(ids, out, false) must override rec.allow_in_menu=true while menu open")
        assert(ModBindingsMenu.is_down("Uniformity.visual_lock", false) == false, "MBM.is_down(id, false) must override rec.allow_in_menu=true")
        assert(ModBindingsMenu.is_pressed("Uniformity.visual_lock", false) == false, "MBM.is_pressed(id, false) must override rec.allow_in_menu=true")
        assert(ModBindingsMenu.consume_press("Uniformity.visual_lock", false) == false, "MBM.consume_press(id, false) must override rec.allow_in_menu=true")
        active_keys[key_map.f7] = false
        _G.update(0.016)
        active_keys[key_map.f7] = true
        poll_out = {}
        ModBindingsMenu.poll({ "Uniformity.visual_lock" }, poll_out, true)
        assert(poll_out.down[1] == true, "MBM.poll(ids, out, true) must allow key in menu")
        active_keys[key_map.f7] = false
        _G.update(0.016)
        active_keys[key_map.k] = true
        poll_out = {}
        ModBindingsMenu.poll({ "Uniformity.gameplay_action" }, poll_out, true)
        assert(poll_out.down[1] == true, "MBM.poll(ids, out, true) must allow gameplay binding in menu")
        active_keys[key_map.k] = false
        _G.update(0.016)

        -- Del key reset in F9 menu on rebind_held resets to default ("k") and syncs MBM + latches if held
        UML.select_mod("RebindSuite", true)
        active_keys[key_map.k] = true
        active_keys[key_map.del] = true
        _G.update(0.016)
        active_keys[key_map.del] = false
        assert(ModBindingsMenu.get_binding("rebind_held") == "k", "Del reset_option must sync MBM back to default 'k'")
        UML.close_menu()
        assert(ModBindingsMenu.is_pressed("rebind_held") == false and ModBindingsMenu.is_down("rebind_held") == false, "Del reset while default key held must latch")
        active_keys[key_map.k] = false
        _G.update(0.016)
        print("  [PASS] Rebind/reset latches, 'off' edge cleanup, MOM<->MBM sync, and poll allow_in_menu=false override verified")

        -- 10. Key capture wait_release, edge-leak suppression (tab / f10), and single write (no duplicate on_change)
        local cap_mod = UML.register("CaptureSuite", { version = "1.0" })
        cap_mod:option("cap_edge_opt", { label = "Capture Edge Key", type = "key", default = "k" })
        cap_mod:option("cap_toggle", { label = "Next Toggle", type = "toggle", default = false })
        local cap_changes = 0
        ModOptionsMenu.on_change("CaptureSuite.cap_edge_opt", function() cap_changes = cap_changes + 1 end)

        UML.open_menu("CaptureSuite", { compact = false, focus = "options" })
        assert(UML.get_menu_state().option_id == "CaptureSuite.cap_edge_opt")
        local c0 = cap_changes

        -- Enter capture with Space held across next frame -> wait_release must prevent capturing Space itself
        active_keys[key_map.space] = true
        _G.update(0.016)
        assert(UML.is_capturing_key() == true and UML.get_capture_id() == "CaptureSuite.cap_edge_opt")
        _G.update(0.016)
        assert(UML.is_capturing_key() == true, "Holding activation key into capture must NOT capture itself")
        active_keys[key_map.space] = false
        _G.update(0.016)

        -- Press Tab during capture -> binds once, exits capture, and keeping Tab held does NOT switch focus!
        active_keys[key_map.tab] = true
        _G.update(0.016)
        assert(UML.is_capturing_key() == false, "Tab must finish key capture")
        assert(ModOptionsMenu.get("CaptureSuite.cap_edge_opt") == "tab")
        assert(cap_changes == c0 + 1, "Binding key must fire MOM on_change exactly ONCE (got " .. tostring(cap_changes - c0) .. ")")
        assert(UML.get_menu_state().focus == "options", "Holding bound Tab on capture exit must not immediately leak Tab focus toggle")
        _G.update(0.016)
        assert(UML.get_menu_state().focus == "options", "Continued hold of bound Tab on next frame must not leak Tab focus toggle")
        active_keys[key_map.tab] = false
        _G.update(0.016)

        -- Bind F10 (same key as Uniformity's compact shortcut) during capture -> must NOT trigger compact shortcut toggle!
        active_keys[key_map.enter] = true
        _G.update(0.016)
        active_keys[key_map.enter] = false
        _G.update(0.016)
        assert(UML.is_capturing_key() == true)
        active_keys[key_map.f10] = true
        _G.update(0.016)
        assert(UML.is_capturing_key() == false and ModOptionsMenu.get("CaptureSuite.cap_edge_opt") == "f10")
        assert(cap_changes == c0 + 2, "Binding f10 must fire MOM on_change exactly ONCE")
        assert(UML.is_fullscreen_menu_open() == true, "Binding f10 must not leak into poll_compact_shortcuts")
        _G.update(0.016)
        assert(UML.is_fullscreen_menu_open() == true, "Continued hold of f10 after capture must not trigger compact shortcut")
        active_keys[key_map.f10] = false
        _G.update(0.016)

        -- Clear via Del during capture -> binds "off" and fires on_change once
        active_keys[key_map.right] = true
        _G.update(0.016)
        active_keys[key_map.right] = false
        _G.update(0.016)
        active_keys[key_map.del] = true
        _G.update(0.016)
        active_keys[key_map.del] = false
        _G.update(0.016)
        assert(UML.is_capturing_key() == false and ModOptionsMenu.get("CaptureSuite.cap_edge_opt") == "off")
        assert(cap_changes == c0 + 3, "Clearing key in capture must fire MOM on_change exactly ONCE")
        UML.close_menu()
        _G.update(0.016)
        print("  [PASS] Key capture wait_release, edge-leak isolation, and single-write MOM/MBM update verified")

        -- 11. Enter navigation, key aliases ("equal", "left bracket", "right bracket"), and Chat Guard on close / external menu
        local nav_mod = UML.register("NavSuite", { version = "1.0" })
        nav_mod:option("cat_toggle", { label = "Cat Toggle", category = "NavCat", type = "toggle", default = false })
        nav_mod:option("cat2_toggle", { label = "Cat2 Toggle", category = "NavCat2", type = "toggle", default = false })
        UML.open_menu("NavSuite", { compact = false, focus = "mods" })
        assert(UML.get_menu_state().focus == "mods")
        active_keys[key_map.enter] = true
        _G.update(0.016)
        assert(UML.get_menu_state().focus == "options", "Enter in mods pane must enter options submenu")
        active_keys[key_map.enter] = false
        _G.update(0.016)

        -- Items[1] is NavCat category header row; collapse with Left, expand with Enter, Down to cat_toggle, toggle with Enter
        assert(UML.get_menu_state().option_id == nil, "Should start on first category header row")
        active_keys[key_map.left] = true
        _G.update(0.016)
        active_keys[key_map.left] = false
        _G.update(0.016)
        active_keys[key_map.enter] = true
        _G.update(0.016)
        active_keys[key_map.enter] = false
        _G.update(0.016)
        active_keys[key_map.down] = true
        _G.update(0.016)
        active_keys[key_map.down] = false
        _G.update(0.016)
        assert(UML.get_menu_state().option_id == "NavSuite.cat_toggle")
        active_keys[key_map.enter] = true
        _G.update(0.016)
        assert(ModOptionsMenu.get("NavSuite.cat_toggle") == true, "Enter on toggle row must flip value")
        active_keys[key_map.enter] = false
        _G.update(0.016)

        -- Scale alias "equal" and mod cycling aliases "left bracket"/"right bracket"
        local scale_before = UML.get_menu_state().scale
        active_keys[key_map.equal] = true
        _G.update(0.016)
        active_keys[key_map.equal] = false
        _G.update(0.016)
        assert(UML.get_menu_state().scale ~= scale_before, "Stingray 'equal' key must adjust UI scale")
        local mod_before = UML.get_menu_state().mod_index
        active_keys[key_map["left bracket"]] = true
        _G.update(0.016)
        active_keys[key_map["left bracket"]] = false
        _G.update(0.016)
        assert(UML.get_menu_state().mod_index ~= mod_before, "Stingray 'left bracket' key must cycle mod")
        active_keys[key_map["right bracket"]] = true
        _G.update(0.016)
        active_keys[key_map["right bracket"]] = false
        _G.update(0.016)
        assert(UML.get_menu_state().mod_index == mod_before, "Stingray 'right bracket' key must cycle mod back")

        -- Holding Enter while closing via ESC must NOT open uml_chat_open on subsequent frames!
        active_keys[key_map.enter] = true
        _G.update(0.016)
        active_keys[key_map.escape] = true
        _G.update(0.016)
        active_keys[key_map.escape] = false
        assert(UML.is_menu_open() == false)
        _G.update(0.016)
        assert(UML.is_chat_active() == false, "Holding Enter while menu closed must NOT trigger chat_open")
        active_keys[key_map.enter] = false
        _G.update(0.016)

        -- Pressing Enter while external menu is open (with Window.has_focus=true) must NOT trigger chat_open!
        UML.set_external_open("no_spoof_ext", true)
        active_keys[key_map.enter] = true
        _G.update(0.016)
        assert(UML.is_chat_active() == false, "Enter inside external menu must NOT open uml_chat_open")
        -- Closing external menu while Enter is still held must stay latched
        UML.set_external_open("no_spoof_ext", false)
        _G.update(0.016)
        assert(UML.is_chat_active() == false, "Closing external menu while Enter held must NOT trigger chat_open")
        active_keys[key_map.enter] = false
        _G.update(0.016)
        print("  [PASS] Enter nav, Stingray 'equal'/'left bracket'/'right bracket' aliases, and Chat Guard verified")

        -- 12. Uniformity 3.0 bridge overlap refusal, group-scoped option_id, select_mod delegation, toggle_menu(missing_mod)
        local ok_cap, cap_idx, cap_name = UML.select_mod("CaptureSuite", true)
        assert(ok_cap and cap_idx and cap_name ~= nil)
        UML.select_mod("Uniformity", true)
        local u3_st = { compact = true, fullscreen = false, focus = "options", group_index = cap_idx, ready = true }
        local u3_close_called = 0
        local u3_select_called = nil
        _G.UniformityMenu = { state = function() return u3_st end }
        local st_bridge = UML.get_menu_state()
        assert(st_bridge.mod_index == cap_idx and st_bridge.mod_name == cap_name and st_bridge.option_id == "CaptureSuite.cap_edge_opt",
            "get_menu_state under Uniformity3 bridge must derive mod_name & option_id from bridge group_index")
        assert(UML.open_menu("Uniformity", { compact = false }) == false and st_bridge.fullscreen == false, "open_menu must refuse to overlap Uniformity3 bridge without close()")
        assert(UML.toggle_menu("Uniformity", { compact = true }) == false and UML.get_menu_state().fullscreen == false, "toggle_menu must refuse to overlap Uniformity3 bridge without close()")
        assert(UML.select_mod("Uniformity") == false, "select_mod must refuse when Uniformity3 bridge owns screen without select_mod()")

        _G.UniformityMenu = {
            state = function() return u3_st end,
            close = function() u3_close_called = u3_close_called + 1; u3_st.compact = false end,
            select_mod = function(t) u3_select_called = t; return true, 2, "NavSuite" end
        }
        assert(UML.select_mod("NavSuite") == true and u3_select_called == "NavSuite", "select_mod must delegate to bridge.select_mod when available")
        assert(UML.open_menu("Uniformity", { compact = false }) == true and u3_close_called == 1 and UML.is_fullscreen_menu_open() == true, "open_menu must close bridge when bridge.close() exists")
        _G.UniformityMenu = nil

        -- toggle_menu("MissingMod") when open must NOT close current menu
        assert(UML.is_menu_open() == true)
        assert(UML.toggle_menu("NonExistentModXYZ") == true)
        assert(UML.is_menu_open() == true, "toggle_menu on unknown mod must not close open menu")
        UML.close_menu()
        _G.update(0.016)
        print("  [PASS] Uniformity 3.0 bridge isolation, per-group option_id, delegation, and toggle_menu(missing_mod) verified")

        -- 13. UML.menu.off_change, unsubscribe fn, self-unsubscribing safe iteration, & interactive notify_menu_listeners
        local seq_hits = {}
        local unsub_a, unsub_b, unsub_c
        local function cb_a(st) seq_hits[#seq_hits + 1] = "A" end
        local function cb_b(st) seq_hits[#seq_hits + 1] = "B"; unsub_b() end
        local function cb_c(st) seq_hits[#seq_hits + 1] = "C" end
        unsub_a = UML.menu.on_change(cb_a)
        unsub_b = UML.menu.on_change(cb_b)
        unsub_c = UML.menu.on_change(cb_c)
        assert(type(unsub_b) == "function", "on_change must return unsubscribe closure")
        UML.open_menu("Uniformity", { compact = false, focus = "mods" })
        assert(#seq_hits == 3 and seq_hits[1] == "A" and seq_hits[2] == "B" and seq_hits[3] == "C", "Self-unsubscribing cb_b must NOT skip cb_c during dispatch")
        seq_hits = {}
        assert(UML.menu.off_change(cb_a) == true and UML.menu.off_change(cb_a) == false)

        -- Interactive handle_uml_menu_input transitions must notify remaining listener C
        active_keys[key_map.tab] = true
        _G.update(0.016)
        active_keys[key_map.tab] = false
        _G.update(0.016)
        assert(#seq_hits == 1 and seq_hits[1] == "C", "Tab focus switch must notify menu listeners")

        seq_hits = {}
        active_keys[key_map.down] = true
        _G.update(0.016)
        active_keys[key_map.down] = false
        _G.update(0.016)
        assert(#seq_hits == 1, "Down option navigation must notify menu listeners")

        seq_hits = {}
        active_keys[key_map.backspace] = true
        _G.update(0.016)
        active_keys[key_map.backspace] = false
        _G.update(0.016)
        assert(#seq_hits == 1, "Backspace pane switch must notify menu listeners")

        seq_hits = {}
        active_keys[key_map["]"]] = true
        _G.update(0.016)
        active_keys[key_map["]"]] = false
        _G.update(0.016)
        assert(#seq_hits == 1, "] mod cycling must notify menu listeners")

        seq_hits = {}
        active_keys[key_map["1"]] = true
        _G.update(0.016)
        active_keys[key_map["1"]] = false
        _G.update(0.016)
        assert(#seq_hits == 1, "Number quick-jump must notify menu listeners")
        unsub_c()
        UML.close_menu()
        _G.update(0.016)
        print("  [PASS] off_change, safe snapshot dispatch, and interactive menu listener notifications verified")

        -- 14. Compact category header & narrow option label truncation (zero overlap with count/value column)
        local wide_mod = UML.register("CompactTruncMod", { version = "1.0" })
        wide_mod:option("long_opt", {
            label = "EXTREMELY LONG OPTION LABEL OVERFLOWING COMPACT PANEL",
            category = "VERY LONG CATEGORY HEADER NAME IN COMPACT VIEW",
            type = "choice",
            default = 1,
            choices = { "SUPER LONG CHOICE STRING ALPHA", "BETA" }
        })
        wide_mod:option("short_opt2", {
            label = "Second Category Long Option Label Check",
            category = "SECOND LONG CATEGORY HEADER IN COMPACT VIEW",
            type = "choice",
            default = 1,
            choices = { "ALPHA", "BETA" }
        })
        local prev_scale = ModOptionsMenu.get("uml_ui_scale")
        ModOptionsMenu.set("uml_ui_scale", 1)
        UML.open_menu("CompactTruncMod", { compact = true, layout = 1 })
        mock_res_w, mock_res_h = 800, 600
        rects = {}
        _G.update(0.016)
        local compact_panel_rect = rects[2]
        assert(compact_panel_rect ~= nil, "Compact panel must render at 800x600")
        for _, r in ipairs(rects) do
            if r.z == 970 and r.y >= (compact_panel_rect.y + 115) and r.y <= (compact_panel_rect.y + compact_panel_rect.h - 60) then
                assert(r.x >= compact_panel_rect.x and (r.x + r.w) <= (compact_panel_rect.x + compact_panel_rect.w),
                    "Narrow compact list row glyph must not overflow panel edge")
            end
        end
        local white_max_by_y, gray_min_by_y, cyan_by_y = {}, {}, {}
        for _, r in ipairs(rects) do
            if r.z == 970 and r.y >= (compact_panel_rect.y + 115) and r.y <= (compact_panel_rect.y + compact_panel_rect.h - 60) and type(r.col) == "table" then
                if r.col.r == 220 and r.col.g == 225 and r.col.b == 235 then
                    white_max_by_y[r.y] = math.max(white_max_by_y[r.y] or -1, r.x + r.w)
                elseif r.col.r == 155 and r.col.g == 165 and r.col.b == 180 then
                    gray_min_by_y[r.y] = math.min(gray_min_by_y[r.y] or 99999, r.x)
                elseif r.col.r == 110 and r.col.g == 210 and r.col.b == 250 then
                    local cb = cyan_by_y[r.y] or { min = 99999, max = -1 }
                    if r.x < cb.min then cb.min = r.x end
                    if (r.x + r.w) > cb.max then cb.max = r.x + r.w end
                    cyan_by_y[r.y] = cb
                end
            end
        end
        local checked_opt_rows, checked_cat_rows = 0, 0
        for y, wmax in pairs(white_max_by_y) do
            local cb = cyan_by_y[y]
            assert(cb ~= nil and wmax < cb.min, "Truncated option label must stay strictly left of choice value")
            checked_opt_rows = checked_opt_rows + 1
        end
        for y, gmin in pairs(gray_min_by_y) do
            local cb = cyan_by_y[y]
            assert(cb ~= nil and cb.max < gmin, "Truncated category header must stay strictly left of count message")
            checked_cat_rows = checked_cat_rows + 1
        end
        assert(checked_opt_rows >= 2 and checked_cat_rows >= 1, "Must check both truncated option rows and category header row")
        mock_res_w, mock_res_h = 1920, 1080
        ModOptionsMenu.set("uml_ui_scale", prev_scale or 1)
        UML.close_menu()
        _G.update(0.016)
        print("  [PASS] Narrow compact category & option label truncation verified with zero overflow")
    end)

    restore_files()
    if not ok_all then
        error(err_all)
    end

    -- 15. Fresh sandbox check: frame_counter == 0 poll_edge_key & empty uml_mod_groups focus reset
    local ok_fresh, err_fresh = pcall(function()
        local active_keys = {}
        local key_map = { j = 74 }
        _G.stingray = {
            Application = { main_world = function() return nil end, worlds = function() return {} end },
            Window = { has_focus = function() return true end },
            Keyboard = {
                button_id = function(k) return key_map[tostring(k):lower()] end,
                button = function(id) return active_keys[id] == true end,
                pressed = function(id) return active_keys[id] == true end
            }
        }
        for _, k in ipairs({ "ModOptionsMenu", "ModBindingsMenu", "CowboyBingusModLoader", "BingusRuntime", "HD2Runtime", "ChefSharedLoader", "RatsSharedLoader", "UML", "UniversalModLoader", "__uml_master_update", "__uml_master_render", "update", "render" }) do
            _G[k] = nil
        end
        package.loaded["UML"] = nil; package.loaded["ModOptionsMenu"] = nil; package.loaded["ModBindingsMenu"] = nil
        assert(loadfile("src/boot_loader.lua"))()

        ModBindingsMenu.register_binding("frame0_bind", "Frame 0 Bind", "j")
        active_keys[74] = true
        assert(ModBindingsMenu.is_pressed("frame0_bind") == true, "is_pressed at frame_counter==0 must detect press")
        assert(ModBindingsMenu.consume_press("frame0_bind") == true, "consume_press right after is_pressed at frame_counter==0 must NOT wipe pending_edge")
        assert(ModBindingsMenu.consume_press("frame0_bind") == false, "Second consume_press at frame_counter==0 must return false")

        -- Empty groups focus reset check
        ModOptionsMenu.order = {}
        ModOptionsMenu.registered = {}
        UML.open_menu(nil, { focus = "options" })
        UML.close_menu()
        assert(UML.open_menu(nil, {}) == true)
        assert(UML.get_menu_state().focus == "mods" and UML.get_menu_state().group_count == 0, "Empty groups open_menu must reset stale 'options' focus to 'mods'")
        UML.close_menu()
        assert(UML.open_menu("nonexistent_mod", {}) == true)
        assert(UML.get_menu_state().focus == "mods", "Empty groups open_menu(missing_mod) must reset stale 'options' focus to 'mods'")
        print("  [PASS] frame_counter==0 pending_edge preservation & empty uml_mod_groups focus reset verified")
    end)
    restore_files()
    if not ok_fresh then
        error(err_fresh)
    end

    -- 16. Real Hot-Reload cleanup of compact_shortcuts, menu_listeners, external_menus, key_blocked_latch, poll_edge_state & raw poll isolation
    local mods_dir_existed = (os.rename("mods", "mods") == true)
    local prev_mods_txt = nil
    local f_prev = io.open("mods/mods.txt", "rb")
    if f_prev then prev_mods_txt = f_prev:read("*a"); f_prev:close() end
    os.execute('if not exist "mods" mkdir "mods"')

    local ok_hr, err_hr = pcall(function()
        local active_keys = {}
        local key_map = { f5 = 116, f8 = 119, f9 = 120, n = 78, p = 80, ["left ctrl"] = 17, ctrl = 17 }
        local kb_names = { [17] = "left ctrl", [78] = "n", [80] = "p", [116] = "f5", [119] = "f8", [120] = "f9" }
        _G.stingray = {
            Application = { main_world = function() return nil end, worlds = function() return {} end },
            Window = { has_focus = function() return true end },
            Keyboard = {
                button_id = function(k) return key_map[tostring(k):lower()] end,
                button = function(id) return active_keys[id] == true end,
                pressed = function(id) return active_keys[id] == true end,
                num_buttons = function() return 256 end,
                button_name = function(idx) return kb_names[idx] end
            }
        }
        _G.__LIBRA_HR = { a_v1_list = 0, a_v1_p = 0, b_p = 0, persist_events = 0 }

        local fa = assert(io.open("mods/libra_hr_a.lua", "wb"))
        fa:write([[
            local modA = UML.register("LibraHrA", { version = "1.0" })
            modA:register_compact_menu({ id = "libra_a_sc", key = "f8", label = "Libra A Compact" })
            UML.menu.on_change(function()
                _G.__LIBRA_HR.a_v1_list = _G.__LIBRA_HR.a_v1_list + 1
            end)
            ModBindingsMenu.register_binding("hr_a_latch_bind", "HR A Latch", "n")
            local opened_ext = false
            modA:on_update(function()
                if not opened_ext then
                    opened_ext = true
                    UML.set_external_open("libra_a_ext_panel", true)
                end
                ModBindingsMenu.is_down("hr_a_latch_bind")
                if modA:consume_key_press("p", true) then
                    _G.__LIBRA_HR.a_v1_p = _G.__LIBRA_HR.a_v1_p + 1
                end
            end)
        ]])
        fa:close()

        local fb = assert(io.open("mods/libra_hr_b.lua", "wb"))
        fb:write([[
            local modB = UML.register("LibraHrB", { version = "1.0" })
            modB:on_update(function()
                if modB:consume_key_press("p", true) then
                    _G.__LIBRA_HR.b_p = _G.__LIBRA_HR.b_p + 1
                end
            end)
        ]])
        fb:close()

        local fm = assert(io.open("mods/mods.txt", "wb"))
        fm:write("mods/libra_hr_a\nmods/libra_hr_b\n")
        fm:close()

        for _, k in ipairs({ "ModOptionsMenu", "ModBindingsMenu", "CowboyBingusModLoader", "BingusRuntime", "HD2Runtime", "ChefSharedLoader", "RatsSharedLoader", "UML", "UniversalModLoader", "__uml_master_update", "__uml_master_render", "update", "render" }) do
            _G[k] = nil
        end
        package.loaded["UML"] = nil; package.loaded["ModOptionsMenu"] = nil; package.loaded["ModBindingsMenu"] = nil
        assert(loadfile("src/boot_loader.lua"))()

        -- Hold "n" (blocked by external menu) and press "p" once -> BOTH Mod A and Mod B must see "p" without colliding
        active_keys[78] = true
        active_keys[80] = true
        _G.update(0.016)
        assert(_G.__LIBRA_HR.a_v1_p == 1 and _G.__LIBRA_HR.b_p == 1, "Two mods polling same raw key 'p' must NOT collide or steal edges")
        assert(UML.is_menu_open() == true and UML.is_input_blocked(false) == true, "Mod A external panel must be active")
        active_keys[80] = false
        _G.update(0.016)

        local persist_unsub = UML.menu.on_change(function() _G.__LIBRA_HR.persist_events = _G.__LIBRA_HR.persist_events + 1 end)

        -- Rewrite Mod A without shortcut, listener, external panel, or update hook, then Ctrl+F5 reload
        local fa2 = assert(io.open("mods/libra_hr_a.lua", "wb"))
        fa2:write([[ local modA2 = UML.register("LibraHrA", { version = "2.0" }) ]])
        fa2:close()

        active_keys[17] = true
        active_keys[116] = true
        _G.update(0.016)
        active_keys[17] = false
        active_keys[116] = false

        assert(UML.is_menu_open() == false and UML.is_input_blocked(false) == false, "Hot-reload must close Mod A's orphaned external menu")
        assert(_G.__LIBRA_HR.persist_events >= 1, "Clearing open external menu on hot-reload must notify surviving listeners")

        local list_snap = _G.__LIBRA_HR.a_v1_list
        UML.open_menu("LibraHrA")
        UML.close_menu()
        assert(_G.__LIBRA_HR.a_v1_list == list_snap, "Hot-reload must prune Mod A's UML.menu.on_change listener")

        -- Pressing Mod A v1 compact shortcut key f8 must do nothing
        active_keys[119] = true
        _G.update(0.016)
        active_keys[119] = false
        _G.update(0.016)
        assert(UML.is_menu_open() == false, "Hot-reload must prune Mod A's compact_shortcuts")

        -- Release "n" while re-registering "hr_a_latch_bind": stale latch must be gone and fresh press must work
        active_keys[78] = false
        _G.update(0.016)
        ModBindingsMenu.register_binding("hr_a_latch_bind", "HR A Latch", "n")
        active_keys[78] = true
        _G.update(0.016)
        assert(ModBindingsMenu.consume_press("hr_a_latch_bind") == true, "Cleared latch on reload must allow clean press")

        -- Verify Mod B raw "p" still works cleanly across reload
        local b_before = _G.__LIBRA_HR.b_p
        active_keys[80] = true
        _G.update(0.016)
        assert(_G.__LIBRA_HR.b_p == b_before + 1, "Reloaded Mod B raw key 'p' polling must still function cleanly")
        persist_unsub()
        print("  [PASS] Hot-reload cleanup of compact shortcuts, menu listeners, external menus, blocked latches, & raw poll isolation verified")
    end)

    os.remove("mods/libra_hr_a.lua")
    os.remove("mods/libra_hr_b.lua")
    if prev_mods_txt ~= nil then
        local fw = io.open("mods/mods.txt", "wb")
        if fw then fw:write(prev_mods_txt); fw:close() end
    else
        os.remove("mods/mods.txt")
    end
    if not mods_dir_existed then
        os.execute('rmdir "mods" 2>nul')
    end
    restore_files()
    if not ok_hr then
        error(err_hr)
    end

    print("====================================================")
    print("ALL LIBRA MENU API TESTS PASSED!")
    print("====================================================")
end

run_test()
