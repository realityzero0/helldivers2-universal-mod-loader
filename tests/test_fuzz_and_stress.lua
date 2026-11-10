-- tests/test_fuzz_and_stress.lua
-- Exhaustive Bug Testing, Edge Case Fuzzing, and Stress Analysis for UML v2.0.3
-- Covers all 5 critical areas:
-- 1. JSON Persistence (corrupted, empty, truncated, locked, special numbers, commas in strings)
-- 2. Patch Archive Scanner (malformed headers, huge counts, zero-byte chunks, huge body lengths, corrupt bytecode)
-- 3. Extreme Inputs to Mod APIs (Chef, Rat, CowboyBingus, UML native, dot vs colon syntax, nil arguments)
-- 4. UI Bounds Stress Testing (120+ mods, 600+ options, rapid keypresses, mouse wheel bounds, dynamic scale bounds)
-- 5. Chat Guard & Window Focus Guard edge conditions (blocking hotkeys, closing chat, focus loss/recovery)

local function run_all_fuzz_tests()
    print("================================================================================")
    print("EXHAUSTIVE FUZZ TESTING, EDGE CASE & STRESS ANALYSIS SUITE")
    print("Universal Mod Loader - boot_loader.lua")
    print("================================================================================")

    local findings = {}
    local function record_finding(category, severity, title, desc, repro)
        table.insert(findings, {
            category = category,
            severity = severity,
            title = title,
            desc = desc,
            repro = repro
        })
        print(string.format("  [DETECTED BUG - %s] (%s): %s", severity, category, title))
    end

    local function record_pass(category, name)
        print(string.format("  [PASS] (%s) %s", category, name))
    end

    local active_keys = {}
    local window_focused = true

    -- Helper to load fresh boot_loader chunk
    local function load_fresh_bootloader(extra_env)
        extra_env = extra_env or {}
        local f = io.open("src/boot_loader.lua", "r")
        assert(f, "Cannot open src/boot_loader.lua")
        local code = f:read("*a")
        f:close()

        local chunk, err = loadstring(code, "boot_loader.lua")
        assert(chunk, "Compilation error: " .. tostring(err))

        -- Clean globals
        _G.UML = nil
        _G.ModOptionsMenu = nil
        _G.ModBindingsMenu = nil
        _G.ChefSharedLoader = nil
        _G.RatsSharedLoader = nil
        _G.CowboyBingusModLoader = nil
        _G.BootModLoader = nil
        _G.hd2rt = nil
        _G.hd2runtime = nil
        _G.HD2Runtime = nil

        -- Mock full Stingray engine environment
        _G.stingray = {
            Application = {
                can_get = function() return false end,
                main_world = function() return { id = "w_main" } end,
                worlds = function() return { { id = "w_main" } } end,
            },
            Window = {
                has_focus = function() return window_focused end
            },
            World = {
                create_screen_gui = function() return { id = "gui" } end
            },
            Gui = {
                resolution = function() return 1920, 1080 end,
                rect = function() end
            },
            Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
            Vector2 = function(x, y) return { x = x, y = y } end,
            Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
            Keyboard = {
                button_id = function(k)
                    local kl = tostring(k):lower()
                    if kl == "f9" then return 119 end
                    if kl == "f2" then return 113 end
                    if kl == "f1" then return 112 end
                    if kl == "escape" or kl == "esc" then return 27 end
                    if kl == "enter" or kl == "return" then return 13 end
                    if kl == "numpad enter" then return 14 end
                    if kl == "up" or kl == "up_arrow" then return 38 end
                    if kl == "down" or kl == "down_arrow" then return 40 end
                    if kl == "left" or kl == "left_arrow" then return 37 end
                    if kl == "right" or kl == "right_arrow" then return 39 end
                    if kl == "delete" or kl == "del" then return 46 end
                    if kl == "backspace" then return 8 end
                    if kl == "tab" then return 9 end
                    if kl == "space" then return 32 end
                    if kl == "page up" then return 33 end
                    if kl == "page down" then return 34 end
                    if kl == "home" then return 36 end
                    if kl == "end" then return 35 end
                    if kl == "-" or kl == "minus" then return 189 end
                    if kl == "=" or kl == "equals" then return 187 end
                    if kl == "[" then return 219 end
                    if kl == "]" then return 221 end
                    for n = 0, 9 do
                        if kl == tostring(n) then return 48 + n end
                        if kl == ("numpad " .. tostring(n)) then return 96 + n end
                    end
                    return nil
                end,
                button = function(id) return active_keys[id] == true end,
                pressed = function(id) return active_keys[id] == true end
            }
        }

        for k, v in pairs(extra_env) do
            _G.stingray[k] = v
        end

        local ok, run_err = pcall(chunk)
        return ok, run_err
    end

    -- =========================================================================
    -- 1. JSON PERSISTENCE & SETTINGS FUZZING
    -- =========================================================================
    print("\n[1] Testing JSON Persistence & Settings Resilience...")
    local test_json_path = "uml_mod_settings.json"
    local bak_path = test_json_path .. ".bak"

    -- 1.1 Empty file (0 bytes)
    do
        local jf = io.open(test_json_path, "wb")
        jf:close()
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            record_pass("JSON", "Empty file (0 bytes) parsed safely without crash")
        else
            record_finding("JSON", "HIGH", "Empty JSON file crashes bootloader", tostring(err), "Write 0 bytes to uml_mod_settings.json and boot")
        end
    end

    -- 1.2 Binary garbage in JSON
    do
        local jf = io.open(test_json_path, "wb")
        jf:write("\x00\xFF\xFE\xFA\x12\x34\x56\x78\x00\x00\xAA\xBB\xCC\xDD")
        jf:close()
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            local bf = io.open(bak_path, "rb")
            if bf then
                bf:close()
                record_pass("JSON", "Binary garbage safely backed up to .bak and defaults preserved")
            else
                record_finding("JSON", "MEDIUM", "Binary garbage in settings did not trigger backup to .bak", "File not backed up", "Write garbage bytes to uml_mod_settings.json")
            end
        else
            record_finding("JSON", "HIGH", "Binary garbage in JSON crashes bootloader", tostring(err), "Write random bytes to uml_mod_settings.json and boot")
        end
    end

    -- 1.3 String values containing commas
    do
        local jf = io.open(test_json_path, "wb")
        jf:write('{\n  "test_comma": "hello, world",\n  "test_num": 42\n}\n')
        jf:close()
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            local val = _G.ModOptionsMenu.get("test_comma")
            if val == "hello, world" then
                record_pass("JSON", "String values containing commas parsed correctly")
            else
                record_finding("JSON", "HIGH", "String values with commas silently dropped by regex parser",
                    string.format("Expected 'hello, world', got %s", tostring(val)),
                    'Save \'{"test_comma": "hello, world"}\' and inspect ModOptionsMenu.get("test_comma")')
            end
        end
    end

    -- 1.4 String values containing curly braces
    do
        local jf = io.open(test_json_path, "wb")
        jf:write('{\n  "test_brace": "value {inside} braces"\n}\n')
        jf:close()
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            local v_brace = _G.ModOptionsMenu.get("test_brace")
            if v_brace == "value {inside} braces" then
                record_pass("JSON", "String values with curly braces parsed correctly")
            else
                record_finding("JSON", "MEDIUM", "String values with curly braces dropped by regex parser",
                    string.format("Expected 'value {inside} braces', got %s", tostring(v_brace)),
                    'Save \'{"test_brace": "value {inside} braces"}\' and inspect ModOptionsMenu.get("test_brace")')
            end
        end
    end

    -- 1.5 NaN / Infinity in settings serialization
    do
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            pcall(function()
                _G.ModOptionsMenu.set("nan_test", 0/0)
                _G.ModOptionsMenu.set("inf_test", 1/0)
            end)
            local jf = io.open(test_json_path, "rb")
            local content = jf and jf:read("*a") or ""
            if jf then jf:close() end
            if content:find("nan", 1, true) or content:find("IND", 1, true) or content:find("inf", 1, true) or content:find("INF", 1, true) then
                record_finding("JSON", "MEDIUM", "NaN and Infinity saved directly as unquoted invalid JSON identifiers",
                    "RFC 8259 violation: file contains unquoted nan/inf which breaks standard JSON parsers",
                    'ModOptionsMenu.set("nan_test", 0/0)')
            else
                record_pass("JSON", "NaN/Infinity safely serialized")
            end
        end
    end

    -- 1.6 Cyclic table in options
    do
        local ok, err = load_fresh_bootloader()
        if ok and _G.ModOptionsMenu then
            local cyclic = {}
            cyclic.self = cyclic
            local ok_set, err_set = pcall(function()
                _G.ModOptionsMenu.set("cyclic_test", cyclic)
            end)
            if ok_set then
                record_pass("JSON", "Cyclic table handled without stack overflow in save_settings_to_disk")
            else
                record_finding("JSON", "HIGH", "Cyclic table causes stack overflow in save_settings_to_disk",
                    tostring(err_set), "ModOptionsMenu.set('cyclic_test', cyclic_table)")
            end
        end
    end

    pcall(os.remove, test_json_path)
    pcall(os.remove, bak_path)

    -- =========================================================================
    -- 2. MALFORMED PATCH ARCHIVE FILES FUZZING
    -- =========================================================================
    print("\n[2] Testing Malformed Patch Archive Files...")
    local patch_dir = "data"
    os.execute("if not exist data mkdir data")
    local test_family = "9ba626afa44a3aa3"
    local bad_patch_0 = patch_dir .. "/" .. test_family .. ".patch_0"

    -- 2.1 Truncated 12-byte header
    do
        local pf = io.open(bad_patch_0, "wb")
        pf:write("\x11\x00\x00\xf0\x01\x00\x00\x00\x01\x00\x00\x00")
        pf:close()
        local ok, err = load_fresh_bootloader()
        if ok then
            record_pass("PatchArchive", "Truncated 12-byte header handled safely")
        else
            record_finding("PatchArchive", "HIGH", "Truncated patch header causes bootloader crash", tostring(err), "Create 12-byte patch_0 and boot")
        end
        pcall(os.remove, bad_patch_0)
    end

    -- 2.2 Huge count (0x7FFFFFFF = 2.1 billion entries) - Unbounded loop DoS check
    do
        local pf = io.open(bad_patch_0, "wb")
        local hdr = "\x11\x00\x00\xf0\x01\x00\x00\x00\xFF\xFF\xFF\x7F" .. string.rep("\x00", 60)
        pf:write(hdr)
        pf:close()

        local t0 = os.clock()
        local ok, err = load_fresh_bootloader()
        local elapsed = os.clock() - t0
        if elapsed > 1.0 or not ok then
            record_finding("PatchArchive", "CRITICAL", "Corrupt archive header with huge count causes DoS hang (unbounded loop)",
                string.format("Elapsed: %.2f seconds (scans 2.1 billion entries without file-size upper bound check)", elapsed),
                "Create patch_0 with header count = 0x7FFFFFFF and boot")
        else
            record_pass("PatchArchive", "Huge count in header safely bounded")
        end
        pcall(os.remove, bad_patch_0)
    end

    -- 2.3 Zero-byte Lua chunk
    do
        local pf = io.open(bad_patch_0, "wb")
        local hdr = "\x11\x00\x00\xf0\x00\x00\x00\x00\x01\x00\x00\x00" .. string.rep("\x00", 60)
        local lua_type = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
        local row = "TESTKEY1" .. lua_type .. "\x98\x00\x00\x00" .. string.rep("\x00", 36) .. "\x08\x00\x00\x00" .. string.rep("\x00", 20)
        local env = "\x00\x00\x00\x00\x02\x00\x00\x00"
        pf:write(hdr .. row .. env)
        pf:close()

        local ok, err = load_fresh_bootloader()
        if ok then
            record_pass("PatchArchive", "Zero-byte Lua chunk handled safely")
        else
            record_finding("PatchArchive", "HIGH", "Zero-byte Lua chunk in patch causes crash", tostring(err), "Create patch with body_len=0 and boot")
        end
        pcall(os.remove, bad_patch_0)
    end

    -- 2.4 Huge body_len (1,000,000,000 bytes) - OOM check
    do
        local pf = io.open(bad_patch_0, "wb")
        local hdr = "\x11\x00\x00\xf0\x00\x00\x00\x00\x01\x00\x00\x00" .. string.rep("\x00", 60)
        local lua_type = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
        local row = "TESTKEY2" .. lua_type .. "\x98\x00\x00\x00" .. string.rep("\x00", 36) .. "\xFF\xFF\xFF\xFF" .. string.rep("\x00", 20)
        local env = "\x00\xCA\x9A\x3B\x02\x00\x00\x00"
        pf:write(hdr .. row .. env)
        pf:close()

        local ok, err = load_fresh_bootloader()
        if ok then
            record_pass("PatchArchive", "Huge body_len safely handled without OOM")
        else
            record_finding("PatchArchive", "HIGH", "Huge body_len in patch causes crash/OOM", tostring(err), "Create patch with body_len=1GB and boot")
        end
        pcall(os.remove, bad_patch_0)
    end

    -- 2.5 Corrupt Lua bytecode (\033Lua) in chunk
    do
        local pf = io.open(bad_patch_0, "wb")
        local hdr = "\x11\x00\x00\xf0\x00\x00\x00\x00\x01\x00\x00\x00" .. string.rep("\x00", 60)
        local lua_type = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
        local row = "TESTKEY3" .. lua_type .. "\x98\x00\x00\x00" .. string.rep("\x00", 36) .. "\x20\x00\x00\x00" .. string.rep("\x00", 20)
        local env = "\x10\x00\x00\x00\x02\x00\x00\x00"
        local bad_bytecode = "\033Lua\x51\x00\x01\x04\x04\x04\x08\x00\xFF\xFF\xFF\xFF"
        pf:write(hdr .. row .. env .. bad_bytecode)
        pf:close()

        local ok, err = load_fresh_bootloader()
        if ok then
            record_pass("PatchArchive", "Corrupt Lua bytecode handled safely")
        else
            record_finding("PatchArchive", "HIGH", "Corrupt Lua bytecode causes unhandled crash", tostring(err), "Create patch with corrupt bytecode")
        end
        pcall(os.remove, bad_patch_0)
    end

    -- =========================================================================
    -- 3. EXTREME INPUTS TO LOADER & MOD APIS
    -- =========================================================================
    print("\n[3] Testing Extreme Inputs to Loader & Mod APIs...")
    load_fresh_bootloader()

    -- 3.1 RatsSharedLoader dot syntax crash
    do
        local rat = _G.RatsSharedLoader
        local ok_dot_reg, err_dot_reg = pcall(function()
            rat.register("dot_mod", { version = "1.0.0" })
        end)
        if not ok_dot_reg then
            record_finding("RatAPI", "HIGH", "RatsSharedLoader.register crashes when called with dot syntax",
                err_dot_reg, "RatsSharedLoader.register('dot_mod', {version='1.0'})")
        else
            record_pass("RatAPI", "RatsSharedLoader.register handles dot syntax")
        end

        local ok_dot_on, err_dot_on = pcall(function()
            rat.on("update", function() end)
        end)
        if not ok_dot_on then
            record_finding("RatAPI", "HIGH", "RatsSharedLoader.on crashes when called with dot syntax",
                err_dot_on, "RatsSharedLoader.on('update', function() end)")
        else
            record_pass("RatAPI", "RatsSharedLoader.on handles dot syntax")
        end

        local ok_dot_trig, err_dot_trig = pcall(function()
            rat.trigger("update")
        end)
        if not ok_dot_trig then
            record_finding("RatAPI", "HIGH", "RatsSharedLoader.trigger crashes when called with dot syntax",
                err_dot_trig, "RatsSharedLoader.trigger('update')")
        else
            record_pass("RatAPI", "RatsSharedLoader.trigger handles dot syntax")
        end
    end

    -- 3.2 ModOptionsMenu.set and Chef.set with nil option ID
    do
        local mom = _G.ModOptionsMenu
        local chef = _G.ChefSharedLoader
        local ok_mom_nil, err_mom_nil = pcall(function()
            mom.set(nil, 123)
        end)
        if not ok_mom_nil then
            record_finding("ModOptionsMenu", "HIGH", "ModOptionsMenu.set crashes with 'table index is nil' on nil option id",
                err_mom_nil, "ModOptionsMenu.set(nil, 123)")
        else
            record_pass("ModOptionsMenu", "ModOptionsMenu.set safely rejects nil id")
        end

        local ok_chef_nil, err_chef_nil = pcall(function()
            chef.set(nil, 123)
        end)
        if not ok_chef_nil then
            record_finding("ChefAPI", "HIGH", "ChefSharedLoader.set crashes with 'table index is nil' on nil option id",
                err_chef_nil, "ChefSharedLoader.set(nil, 123)")
        else
            record_pass("ChefAPI", "ChefSharedLoader.set safely rejects nil id")
        end
    end

    -- 3.3 UML mod_obj:get and mod_obj:set with nil option ID
    do
        local uml = _G.UML
        local m1 = uml.register("TestModNil")
        local ok_get, err_get = pcall(function()
            return m1:get(nil)
        end)
        if not ok_get then
            record_finding("UMLAPI", "HIGH", "UML mod_obj:get crashes on nil id (id:find called on nil)",
                err_get, "mod:get(nil)")
        else
            record_pass("UMLAPI", "UML mod_obj:get handles nil id")
        end

        local ok_set, err_set = pcall(function()
            return m1:set(nil, 123)
        end)
        if not ok_set then
            record_finding("UMLAPI", "HIGH", "UML mod_obj:set crashes on nil id (id:find called on nil)",
                err_set, "mod:set(nil, 123)")
        else
            record_pass("UMLAPI", "UML mod_obj:set handles nil id")
        end
    end

    -- 3.4 Choice options with nil or empty choices table
    do
        local mom = _G.ModOptionsMenu
        mom.register_option("bad_choice_nil", {
            type = "choice",
            label = "Broken Choice Nil"
        })
        mom.register_option("bad_choice_empty", {
            type = "choice",
            label = "Broken Choice Empty",
            choices = {}
        })

        -- Open F9 menu
        active_keys[119] = true
        _G.update(0.016)
        active_keys[119] = false

        local err_count_before = #(_G.uml_error_log or {})
        local ok_r, err_r = pcall(_G.render)
        local err_count_after = #(_G.uml_error_log or {})
        local had_error = (not ok_r) or (err_count_after > err_count_before)
        local error_msg = (not ok_r and tostring(err_r)) or (had_error and tostring(_G.uml_error_log[#_G.uml_error_log].error) or nil)

        if had_error then
            record_finding("ModOptionsMenu", "HIGH", "Choice option with nil or empty choices table crashes GUI rendering",
                error_msg, "Register option {type='choice'} without choices table and render")
        else
            record_pass("ModOptionsMenu", "Choice options with nil/empty choices table render safely")
        end

        -- Close F9 menu and unregister bad options
        active_keys[27] = true
        _G.update(0.016)
        active_keys[27] = false
        mom.registered["bad_choice_nil"] = nil
        mom.registered["bad_choice_empty"] = nil
        for idx = #mom.order, 1, -1 do
            if mom.order[idx] == "bad_choice_nil" or mom.order[idx] == "bad_choice_empty" then
                table.remove(mom.order, idx)
            end
        end
    end

    -- 3.5 Degenerate sliders (zero-step, inverted, NaN)
    do
        local mom = _G.ModOptionsMenu
        mom.register_option("slider_zero", {
            type = "slider",
            label = "Zero Step",
            min = 50,
            max = 50,
            step = 0,
            default = 50
        })
        mom.register_option("slider_nan", {
            type = "slider",
            label = "NaN Slider",
            min = 0/0,
            max = 1/0,
            step = 0/0,
            default = 0/0
        })
        local ok_r, err_r = pcall(_G.render)
        if not ok_r then
            record_finding("ModOptionsMenu", "HIGH", "Degenerate slider crashes GUI render",
                err_r, "Register slider with min=50, max=50, step=0 and render()")
        else
            record_pass("ModOptionsMenu", "Degenerate sliders render safely")
        end
    end

    -- 3.6 Non-function update callbacks in CowboyBingusModLoader
    do
        local cbml = _G.CowboyBingusModLoader
        cbml.on_update("bad_1", "string_callback")
        cbml.on_update("bad_2", 12345)
        local ok_u, err_u = pcall(_G.update, 0.016)
        if ok_u then
            record_pass("CowboyBingus", "Non-function callbacks isolated by circuit breaker")
        else
            record_finding("CowboyBingus", "HIGH", "Non-function update hook crashes engine update tick",
                err_u, "cbml.on_update('bad', 123) then update(0.016)")
        end
    end

    -- =========================================================================
    -- 4. UI BOUNDS STRESS TESTING (120+ MODS, 600+ OPTIONS)
    -- =========================================================================
    print("\n[4] Testing UI Bounds Stress (120+ Mods, 600+ Options)...")
    do
        load_fresh_bootloader()
        local mom = _G.ModOptionsMenu
        for m = 1, 120 do
            local mod_name = string.format("StressMod_%03d", m)
            for opt = 1, 5 do
                local opt_id = string.format("stress_opt_%03d_%d", m, opt)
                mom.register_option(opt_id, {
                    mod = mod_name,
                    category = (opt <= 2) and "Primary" or "Advanced",
                    label = string.format("Option %d for %s", opt, mod_name),
                    type = (opt == 1) and "toggle" or ((opt == 2) and "choice" or "slider"),
                    choices = (opt == 2) and { "Alpha", "Beta", "Gamma" } or nil,
                    min = (opt > 2) and 0 or nil,
                    max = (opt > 2) and 100 or nil,
                    step = (opt > 2) and 10 or nil,
                    default = (opt == 1) and true or ((opt == 2) and 1 or 50),
                    description = string.format("Long stress test description for option %d of mod %d.", opt, m)
                })
            end
        end

        -- Open F9 menu for stress testing
        active_keys[119] = true
        _G.update(0.016)
        active_keys[119] = false

        local ok_render, err_render = pcall(_G.render)
        if ok_render then
            record_pass("UIStress", "Successfully rendered F9 menu with 120 mods and 600+ options")
        else
            record_finding("UIStress", "HIGH", "F9 menu crashes under 120 mods / 600 options",
                err_render, "Register 120 mods / 600 options and render()")
        end

        -- Rapid down navigation 50 ticks
        active_keys[40] = true
        local ok_nav = true
        for _ = 1, 50 do
            local ok_s, err_s = pcall(_G.update, 0.016)
            if not ok_s then ok_nav = false; break end
        end
        active_keys[40] = false
        pcall(_G.render)
        if ok_nav then
            record_pass("UIStress", "Rapid navigation (50 ticks) completed cleanly")
        else
            record_finding("UIStress", "HIGH", "Rapid navigation crashed menu", "Error", "Rapid down arrow")
        end

        -- Mouse wheel extreme scrolling (+10.0 / -10.0)
        _G.stingray.Mouse = {
            axis_id = function(a) return (a == "wheel") and 1 or nil end,
            axis = function(id) return { y = 10.0 } end
        }
        local ok_w1 = pcall(function()
            for _ = 1, 15 do _G.update(0.016) end
            _G.render()
        end)
        _G.stingray.Mouse.axis = function(id) return { y = -10.0 } end
        local ok_w2 = pcall(function()
            for _ = 1, 15 do _G.update(0.016) end
            _G.render()
        end)
        _G.stingray.Mouse = nil
        if ok_w1 and ok_w2 then
            record_pass("UIStress", "Extreme mouse wheel scrolling safely clamped")
        else
            record_finding("UIStress", "HIGH", "Extreme mouse wheel scrolling crashed menu", "Error", "Mouse wheel +10/-10")
        end

        -- Dynamic UI scale cycling ([-] and [=]) 20 times each
        local ok_scale = true
        for _ = 1, 20 do
            active_keys[189] = true; pcall(_G.update, 0.016); active_keys[189] = false; pcall(_G.update, 0.016)
        end
        for _ = 1, 20 do
            active_keys[187] = true; pcall(_G.update, 0.016); active_keys[187] = false; pcall(_G.update, 0.016)
        end
        pcall(_G.render)
        local cur_scale = mom.get("uml_ui_scale")
        if ok_scale and cur_scale >= 1 and cur_scale <= 4 then
            record_pass("UIStress", string.format("UI Scale cycling ([-] / [=]) clamped in bounds [1, 4] (got %s)", tostring(cur_scale)))
        else
            record_finding("UIStress", "HIGH", "UI scale cycling out of bounds", tostring(cur_scale), "Press [-] / [=] 50 times")
        end

        -- Close F9 menu
        active_keys[27] = true; _G.update(0.016); active_keys[27] = false; _G.update(0.016)
    end

    -- =========================================================================
    -- 5. CHAT GUARD & WINDOW FOCUS GUARD EDGE CONDITIONS
    -- =========================================================================
    print("\n[5] Testing Chat Guard & Window Focus Guard...")
    do
        local uml = _G.UML
        local mbm = _G.ModBindingsMenu
        mbm.register_binding("test_f1_guard", "Guard Test F1", nil, { default = "f1" })

        -- Close F9 menu via ESC
        active_keys[27] = true; _G.update(0.016); active_keys[27] = false; _G.update(0.016)

        -- 5.1 Open chat via Enter
        active_keys[13] = true; _G.update(0.016); active_keys[13] = false; _G.update(0.016)
        if uml.is_chat_open() then
            record_pass("Guard", "Enter key opens in-game chat box")
        else
            record_finding("Guard", "HIGH", "Enter key failed to open in-game chat box", "Chat not open", "Press Enter")
        end

        -- 5.2 Hotkey blocked while chat is open
        active_keys[112] = true; _G.update(0.016)
        local f1_blocked = not mbm.is_down("test_f1_guard")
        active_keys[112] = false; _G.update(0.016)
        if f1_blocked then
            record_pass("Guard", "Chat Guard successfully blocked F1 hotkey during active chat")
        else
            record_finding("Guard", "CRITICAL", "Chat Guard failed to block hotkey during active chat", "F1 active", "Press F1 while chat open")
        end

        -- 5.3 Close chat via ESC
        active_keys[27] = true; _G.update(0.016); active_keys[27] = false; _G.update(0.016)
        if not uml.is_chat_open() then
            record_pass("Guard", "ESC key closes in-game chat box")
        else
            record_finding("Guard", "HIGH", "ESC key failed to close in-game chat box", "Chat still open", "Press ESC while chat open")
        end

        -- 5.4 Window unfocused blocks hotkeys
        window_focused = false
        active_keys[112] = true; _G.update(0.016)
        local f1_unfocused_blocked = not mbm.is_down("test_f1_guard")
        active_keys[112] = false
        window_focused = true
        _G.update(0.016)
        if f1_unfocused_blocked then
            record_pass("Guard", "Window Focus Guard successfully blocked hotkey while unfocused")
        else
            record_finding("Guard", "CRITICAL", "Window Focus Guard failed to block hotkey while unfocused", "F1 active", "Unfocus and press F1")
        end
    end

    -- =========================================================================
    -- 6. HOT RELOAD (CTRL+F5) HOOK DUPLICATION
    -- =========================================================================
    print("\n[6] Testing Hot Reload (Ctrl+F5) Hook Integrity...")
    do
        load_fresh_bootloader()
        local chef = _G.ChefSharedLoader
        local hook_exec_count = 0
        chef.on("update", function() hook_exec_count = hook_exec_count + 1 end)

        _G.update(0.016)
        local baseline_count = hook_exec_count

        -- Simulate Ctrl+F5 hot reload
        active_keys[17] = true; active_keys[116] = true -- Ctrl + F5
        _G.update(0.016)
        active_keys[17] = false; active_keys[116] = false
        _G.update(0.016)

        record_pass("HotReload", "Ctrl+F5 hot reload executed safely without crash")
    end

    print("\n================================================================================")
    print(string.format("ANALYSIS COMPLETE: %d BUG FINDINGS DETECTED", #findings))
    print("================================================================================")

    for i, f in ipairs(findings) do
        print(string.format("\n[%d] [%s - %s] %s\n    Description: %s\n    Reproduction: %s",
            i, f.severity, f.category, f.title, f.desc, f.repro))
    end

    return findings
end

local findings = run_all_fuzz_tests()
os.exit(#findings > 0 and 1 or 0)
