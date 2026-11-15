-- tests/test_v204_swarm_audit.lua
-- Comprehensive regression tests for v2.0.4 swarm audit bug fixes and edge cases.
-- Exercises the REAL src/boot_loader.lua with full host-file backup/restore.

print("====================================================")
print("Testing UML v2.0.4 Swarm Audit Fixes & Edge Cases")
print("====================================================")

local passed = 0
local total = 0

local function check(cond, name)
    total = total + 1
    if not cond then
        error("ASSERTION FAILED [" .. tostring(name) .. "]", 2)
    end
    passed = passed + 1
    print("  [PASS] " .. tostring(name))
end

local function make_u32_le(n)
    local b0 = n % 256
    local b1 = math.floor(n / 256) % 256
    local b2 = math.floor(n / 65536) % 256
    local b3 = math.floor(n / 16777216) % 256
    return string.char(b0, b1, b2, b3)
end

local function make_murmur64_bytes(str)
    -- Pure Lua 5.1 MurmurHash64A matching src/boot_loader.lua
    local function bxor32(a, b)
        local r, p = 0, 1
        for _ = 1, 32 do
            local aa = a % 2
            local bb = b % 2
            if aa ~= bb then r = r + p end
            a = (a - aa) / 2
            b = (b - bb) / 2
            p = p * 2
        end
        return r
    end
    local function mul64(al, ah, bl, bh)
        local a0, a1 = al % 65536, math.floor(al / 65536)
        local a2, a3 = ah % 65536, math.floor(ah / 65536)
        local b0, b1 = bl % 65536, math.floor(bl / 65536)
        local b2, b3 = bh % 65536, math.floor(bh / 65536)
        local c0 = a0 * b0
        local c1 = a0 * b1 + a1 * b0 + math.floor(c0 / 65536); c0 = c0 % 65536
        local c2 = a0 * b2 + a1 * b1 + a2 * b0 + math.floor(c1 / 65536); c1 = c1 % 65536
        local c3 = (a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0 + math.floor(c2 / 65536)) % 65536
        c2 = c2 % 65536
        return c0 + c1 * 65536, c2 + c3 * 65536
    end
    local function rshift64(l, h, sh)
        if sh >= 32 then
            return math.floor(h / (2 ^ (sh - 32))), 0
        end
        local div = 2 ^ sh
        local nl = math.floor(l / div) + (h % div) * (2 ^ (32 - sh))
        local nh = math.floor(h / div)
        return nl, nh
    end
    local ml, mh = 0x5bd1e995, 0xc6a4a793
    local seed_l, seed_h = 0, 0
    local len = #str
    local lm, hm = mul64(len, 0, ml, mh)
    local hl, hh = bxor32(seed_l, lm), bxor32(seed_h, hm)
    local nblocks = math.floor(len / 8)
    for i = 0, nblocks - 1 do
        local off = i * 8 + 1
        local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(str, off, off + 7)
        local kl = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        local kh = b5 + b6 * 256 + b7 * 65536 + b8 * 16777216
        kl, kh = mul64(kl, kh, ml, mh)
        local r1, r2 = rshift64(kl, kh, 47)
        kl, kh = bxor32(kl, r1), bxor32(kh, r2)
        kl, kh = mul64(kl, kh, ml, mh)
        hl, hh = bxor32(hl, kl), bxor32(hh, kh)
        hl, hh = mul64(hl, hh, ml, mh)
    end
    local rem = len % 8
    local tail = nblocks * 8 + 1
    if rem > 0 then
        local tl, th = 0, 0
        for j = rem, 1, -1 do
            local bv = string.byte(str, tail + j - 1)
            if j > 4 then
                th = th * 256 + bv
            else
                tl = tl * 256 + bv
            end
        end
        hl, hh = bxor32(hl, tl), bxor32(hh, th)
        hl, hh = mul64(hl, hh, ml, mh)
    end
    local f1, f2 = rshift64(hl, hh, 47)
    hl, hh = bxor32(hl, f1), bxor32(hh, f2)
    hl, hh = mul64(hl, hh, ml, mh)
    local g1, g2 = rshift64(hl, hh, 47)
    hl, hh = bxor32(hl, g1), bxor32(hh, g2)
    return make_u32_le(hl) .. make_u32_le(hh)
end

local function build_stingray_patch(path, entries)
    -- entries = { { key_bytes = 8-byte str, script_text = "..." }, ... }
    local type_lua = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
    local type_count = 1
    local count = #entries
    local header = make_u32_le(0xf0000011) .. make_u32_le(type_count) .. make_u32_le(count) .. string.rep("\0", 60)
    local type_table = type_lua .. make_u32_le(count) .. make_u32_le(0) .. string.rep("\0", 16)
    local table_start = 72 + 32
    local body_offset = table_start + 80 * count
    local rows = {}
    local bodies = {}
    local cur_off = body_offset
    for i = 1, count do
        local e = entries[i]
        local src = e.script_text
        local payload = make_u32_le(#src) .. make_u32_le(2) .. src
        local row = e.key_bytes
            .. type_lua
            .. make_u32_le(cur_off % 4294967296)
            .. make_u32_le(math.floor(cur_off / 4294967296))
            .. string.rep("\0", 32)
            .. make_u32_le(#payload)
            .. string.rep("\0", 20)
        rows[i] = row
        bodies[i] = payload
        cur_off = cur_off + #payload
    end
    local f = assert(io.open(path, "wb"))
    f:write(header)
    f:write(type_table)
    f:write(table.concat(rows))
    f:write(table.concat(bodies))
    f:close()
end

-- Backup host files that boot_loader.lua reads/writes
local localapp = os.getenv("LOCALAPPDATA") or "."
local roam = os.getenv("APPDATA") or "."
local host_paths = {
    roam .. "/Arrowhead/Helldivers2/uml_mod_settings.json",
    localapp .. "/UniversalModLoader/uml_mod_settings.json",
    localapp .. "/UniversalModLoader/mod_settings.json",
    "uml_mod_settings.json",
    roam .. "/Arrowhead/Helldivers2/UniversalModLoader.log",
    localapp .. "/UniversalModLoader/Logs/UniversalModLoader.log",
    localapp .. "/UniversalModLoader/UniversalModLoader.log",
    localapp .. "/UniversalModLoader.log",
    "UniversalModLoader.log",
    roam .. "/Arrowhead/Helldivers2/uml_active_sentinel.txt",
    localapp .. "/UniversalModLoader/uml_active_sentinel.txt",
    "uml_active_sentinel.txt",
    "mods/mods.txt",
}

local backups = {}
for _, p in ipairs(host_paths) do
    local f = io.open(p, "rb")
    if f then
        backups[p] = f:read("*a")
        f:close()
    else
        backups[p] = false
    end
end

local created_files = {}
local created_mods_dir = false
local function track_temp_file(p)
    created_files[#created_files + 1] = p
end

local function ensure_mods_dir()
    local probe = io.open("mods/.probe_tmp", "wb")
    if not probe then
        os.execute('mkdir mods 2>nul')
        created_mods_dir = true
    else
        probe:close()
        os.remove("mods/.probe_tmp")
    end
end

local orig_print = _G.print
local function restore_all()
    _G.print = orig_print
    pcall(function() debug.sethook() end)
    for i = #created_files, 1, -1 do
        pcall(os.remove, created_files[i])
    end
    for p, content in pairs(backups) do
        if content == false then
            pcall(os.remove, p)
            pcall(os.remove, p .. ".bak")
        else
            local f = io.open(p, "wb")
            if f then
                f:write(content)
                f:close()
            end
        end
    end
    if created_mods_dir then
        pcall(os.execute, 'rmdir mods 2>nul')
    end
end

local function clear_loader_globals()
    local clear_names = {
        "ModOptionsMenu", "ModBindingsMenu", "UML", "HD2Runtime",
        "BootModLoader", "RatsSharedLoader", "ChefSharedLoader",
        "CowboyBingusModLoader", "HD2ModLoader", "BingusTranslations",
        "__uml_original_init", "__uml_inner_init",
        "__uml_original_render", "__uml_inner_render",
        "__uml_original_update", "__uml_inner_update",
        "__uml_original_shutdown", "__uml_inner_shutdown",
        "init", "render", "update", "shutdown",
        "stingray", "Keyboard", "Mouse", "Window", "active_keys",
    }
    for _, k in ipairs(clear_names) do
        rawset(_G, k, nil)
    end
    local loaded_clear = {
        "ModOptionsMenu", "ModBindingsMenu", "UML", "HD2Runtime",
        "BootModLoader", "RatsSharedLoader", "ChefSharedLoader",
        "chef_shared_loader", "mods/chef_shared_loader/core_1",
        "mods/chef_shared_loader/core", "mods/chef_shared_loader",
        "mods/chef/chef_shared_loader", "mods/chef/core_1",
        "mods/chef/core", "mods/chef/shared_loader", "mods/chef/main",
        "mods/chef/init", "mods/chef/api", "mods/chef/chef",
        "mods/chef", "chef",
        "mods/cowboybingus/mod_options_menu",
        "mods/cowboybingus/mod_bindings_menu",
        "rats_shared_loader", "rat_shared_loader",
        "mods/rat/shared_loader", "mods/rat/rats_shared_loader",
        "mods/rat/core", "mods/rat/main", "mods/rat", "rat",
        "uml", "mods/uml",
        "boot_mod_loader", "mods/boot_mod_loader",
        "hd2_runtime", "mods/hd2_runtime",
        "mods/audit_mod_a", "mods/audit_mod_b",
        "mods/audit_hotreload_v1", "mods/audit_patch_inner",
    }
    for _, k in ipairs(loaded_clear) do
        package.loaded[k] = nil
        package.preload[k] = nil
    end
end

local function build_mock_stingray(opts)
    opts = opts or {}
    local active = {}
    _G.active_keys = active
    local draw_records = {}
    local wheel_y = opts.wheel_y or 0
    local wheel_table = { x = 0, y = wheel_y, z = 0 }
    local res_w = opts.width or 1920
    local res_h = opts.height or 1080
    local has_focus = (opts.focused ~= false)

    local kb_map = {
        f1 = 112, f2 = 113, f3 = 114, f4 = 115, f5 = 116, f6 = 117,
        f7 = 118, f8 = 119, f9 = 120, f10 = 121, f11 = 122, f12 = 123,
        enter = 13, ["return"] = 13, ["numpad enter"] = 13,
        escape = 27, esc = 27, space = 32, tab = 9, backspace = 8,
        delete = 46, del = 46,
        up = 38, down = 40, left = 37, right = 39,
        ["left ctrl"] = 17, ["right ctrl"] = 17, ctrl = 17,
        k = 75, j = 74, a = 65, b = 66,
    }
    local kb_reverse = {}
    for kname, kid in pairs(kb_map) do
        if not kb_reverse[kid] or #kname > #kb_reverse[kid] then
            kb_reverse[kid] = kname
        end
    end
    kb_reverse[27] = "escape"
    kb_reverse[46] = "delete"
    local kb_obj = {
        button = function(id) return active[id] and 1.0 or 0.0 end,
        pressed = function(id) return active[id] == true end,
        num_buttons = function() return 256 end,
        button_name = function(id) return kb_reverse[id] end,
        _resolve_fn = function(name) return kb_map[tostring(name):lower()] end,
    }
    if not opts.omit_button_id then
        kb_obj.button_id = kb_obj._resolve_fn
    end
    local ms_obj = {
        axis_id = function(name) return (name == "wheel") and 1 or nil end,
        axis = function(id) return (id == 1) and wheel_table or { x = 0, y = 0, z = 0 } end,
        button_id = function() return nil end,
        button = function() return 0 end,
    }
    local vector3_val
    if opts.vector3_as_fn then
        vector3_val = function(x, y, z) return { x = x, y = y, z = z } end
    else
        vector3_val = setmetatable({
            y = function(v) return v.y end,
        }, {
            __call = function(_, x, y, z) return { x = x, y = y, z = z } end
        })
    end

    local world_obj = {}
    local gui_obj = {}
    _G.stingray = {
        Keyboard = kb_obj,
        Mouse = ms_obj,
        Window = { has_focus = function() return has_focus end },
        Application = {
            build = function() return "dev" end,
            main_world = function() return world_obj end,
            worlds = function() return { world_obj } end,
            user_setting = function(k)
                if k == "language" then return "en" end
                return nil
            end,
        },
        World = {
            create_screen_gui = function() return gui_obj end,
        },
        Gui = {
            resolution = function() return res_w, res_h end,
            rect = function(g, pos, size, col)
                draw_records[#draw_records + 1] = {
                    x = pos.x, y = pos.y, z = pos.z,
                    w = size.x, h = size.y, col = col,
                }
            end,
        },
        Vector3 = vector3_val,
        Vector2 = function(x, y) return { x = x, y = y } end,
        Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
    }
    return {
        active = active,
        draw_records = draw_records,
        set_wheel = function(y) wheel_table.y = y end,
        set_resolution = function(w, h) res_w, res_h = w, h end,
    }
end

local function clear_settings_files()
    for i = 1, 4 do
        pcall(os.remove, host_paths[i])
        pcall(os.remove, host_paths[i] .. ".bak")
    end
end

local function boot_real_loader(mock_opts)
    clear_loader_globals()
    local env = build_mock_stingray(mock_opts)
    local base_init_calls, base_update_calls, base_shutdown_calls = 0, 0, 0
    _G.init = function() base_init_calls = base_init_calls + 1 end
    _G.render = function() end
    _G.update = function() base_update_calls = base_update_calls + 1 end
    _G.shutdown = function() base_shutdown_calls = base_shutdown_calls + 1 end
    assert(dofile("src/boot_loader.lua") == nil or true)
    return env, function() return base_init_calls, base_update_calls, base_shutdown_calls end
end

local function run_all_tests()
    ensure_mods_dir()
    clear_settings_files()

    -- =========================================================================
    -- GROUP 1: JSON Serialization & Parsing Edge Cases + Multi-boot Persistence
    -- =========================================================================
    do
        boot_real_loader()
        local mom = _G.ModOptionsMenu
        local complex_str = "line1\nline2\r\ntab\there \"quoted\" \\slash\000end"
        assert(mom.register_option("audit_str", { type = "toggle", title = "Audit", label = "Str", default = "" }))
        assert(mom.set("audit_str", complex_str))
        assert(mom.register_option("audit_num", { type = "slider", title = "Audit", label = "Num", default = 42 }))
        assert(mom.set("audit_num", 77))

        -- Verify written JSON does not contain raw unescaped newline/tab/NUL inside string value
        local jf = assert(io.open("uml_mod_settings.json", "rb"))
        local raw_json = jf:read("*a")
        jf:close()
        check(raw_json:find('\\n', 1, true) ~= nil, "JSON serializer escapes newline as \\n")
        check(raw_json:find('\\r', 1, true) ~= nil, "JSON serializer escapes CR as \\r")
        check(raw_json:find('\\t', 1, true) ~= nil, "JSON serializer escapes tab as \\t")
        check(raw_json:find('\\u0000', 1, true) ~= nil, "JSON serializer escapes NUL as \\u0000")
        check(raw_json:find('\000', 1, true) == nil, "JSON file contains no raw NUL byte")

        -- Reboot loader and verify exact string + number round-trip
        boot_real_loader()
        local mom2 = _G.ModOptionsMenu
        check(mom2.get("audit_str") == complex_str, "JSON round-trip preserves \\n, \\r, \\t, quotes, \\\\, and \\000 identically")
        check(mom2.get("audit_num") == 77, "JSON round-trip preserves number value")

        -- Test nested objects, arrays, \uXXXX escapes, and unterminated string without top-level key leaks
        local tricky_json = '{\n'
            .. '  "meta": { "leaked_inner": 999, "sub": [1, {"deep": "leak"}] },\n'
            .. '  "arr": ["x", {"inner_arr_key": true}],\n'
            .. '  "u_ascii": "\\u0041\\u00e9\\u4e2d",\n'
            .. '  "trueish": 123,\n'
            .. '  "top_ok": true,\n'
            .. '  "dangling": "unterminated_tail\n'
        for i = 1, 4 do
            local wf = io.open(host_paths[i], "wb")
            if wf then wf:write(tricky_json); wf:close() end
        end
        boot_real_loader()
        local mom3 = _G.ModOptionsMenu
        check(mom3.get("leaked_inner") == nil, "Nested object key 'leaked_inner' does NOT leak to top-level settings")
        check(mom3.get("deep") == nil, "Nested array/object key 'deep' does NOT leak to top-level settings")
        check(mom3.get("inner_arr_key") == nil, "Array inner object key does NOT leak to top-level settings")
        check(mom3.get("u_ascii") == "A\195\169\228\184\173", "JSON \\uXXXX escapes decode to proper UTF-8 bytes")
        check(mom3.get("top_ok") == true, "Top-level key after nested containers parses properly")
        check(mom3.get("dangling") == "unterminated_tail\n", "Unterminated trailing JSON string handled cleanly without crash")
    end

    clear_settings_files()

    -- =========================================================================
    -- GROUP 2: Keybinding Trigger Modes, Edge States, VK_MAP, Key Capture & Wheel
    -- =========================================================================
    do
        local env = boot_real_loader({ omit_button_id = true, vector3_as_fn = true, height = 2160, width = 3840 })
        local active = env.active
        local mom = _G.ModOptionsMenu
        local mbm = _G.ModBindingsMenu

        -- Test VK_MAP f9 (120) vs f8 (119) separation when button_id is absent
        active[119] = true -- F8
        _G.update(0.016)
        _G.render()
        active[119] = false
        _G.update(0.016)
        check(#env.draw_records == 0, "VK_MAP: F8 (119) does NOT falsely toggle F9 settings menu")

        active[120] = true -- F9
        _G.update(0.016)
        _G.render()
        local open_rects = #env.draw_records
        active[120] = false
        _G.update(0.016)
        check(open_rects > 0, "VK_MAP: F9 (120) opens settings menu when button_id is absent")

        -- Register a key option, enter key capture, cancel with ESC while held -> menu MUST stay open!
        assert(mom.register_option("audit_bind_key", {
            type = "key",
            title = "UML CORE",
            label = "Audit Test Key",
            default = "k",
        }))
        -- Navigate right to options pane, down to last item ("audit_bind_key"), press right to enter capture
        -- Actually, let's check order index of audit_bind_key in UML CORE group:
        -- UML CORE options are all in first group; move down N times or count UML CORE items before pressing right
        active[39] = true; _G.update(0.016); active[39] = false; _G.update(0.016) -- focus = options
        local uml_core_count = 0
        for _, oid in ipairs(mom.order) do
            local sp = mom.registered[oid]
            if sp and (sp.title == "UML CORE" or oid:sub(1, 4) == "uml_") then
                uml_core_count = uml_core_count + 1
            end
        end
        for _ = 1, uml_core_count - 1 do
            active[40] = true; _G.update(0.016); active[40] = false; _G.update(0.016)
        end
        active[39] = true; _G.update(0.016); active[39] = false; _G.update(0.016) -- enters key capture

        -- Frame 1 with ESC down cancels key capture; Frame 2 with ESC STILL held must NOT close menu!
        local prev_rect = _G.stingray.Gui.rect
        local after_esc_count = 0
        _G.stingray.Gui.rect = function(...) after_esc_count = after_esc_count + 1; return prev_rect(...) end
        active[27] = true
        _G.update(0.016) -- cancels capture cleanly
        after_esc_count = 0
        _G.update(0.016) -- ESC still held: menu must stay OPEN and redraw!
        _G.stingray.Gui.rect = prev_rect
        active[27] = false
        _G.update(0.016)
        check(after_esc_count > 0, "Key capture cancel with held ESC syncs edge state and keeps F9 menu OPEN")

        -- Test mouse wheel scrolling when stingray.Vector3 is a constructor function (no crash!)
        env.set_wheel(1)
        _G.update(0.016)
        env.set_wheel(-1)
        _G.update(0.016)
        env.set_wheel(0)
        _G.update(0.016)
        check(true, "get_mouse_wheel_steps safely handles stingray.Vector3 as function without crash")

        -- Close menu with ESC press, then attach button_id for alphanumeric bind_key tests
        active[27] = true; _G.update(0.016); active[27] = false; _G.update(0.016)
        _G.stingray.Keyboard.button_id = _G.stingray.Keyboard._resolve_fn

        -- Test "hold", "release", and "press" keybinding modes + 4K notification box height
        local mod_obj = _G.UML.register("KeyModeTest", { version = "1.0.0" })
        local press_cnt, hold_cnt, release_cnt = 0, 0, 0
        assert(mod_obj:bind_key("k", function() press_cnt = press_cnt + 1 end, "press"))
        assert(mod_obj:bind_key("j", function() hold_cnt = hold_cnt + 1 end, "hold"))
        assert(mod_obj:bind_key("a", function() release_cnt = release_cnt + 1 end, "release"))

        -- Frame 1: K pressed -> press_cnt=1; Frame 2: K held -> still 1; Frame 3: K released -> still 1
        active[75] = true; _G.update(0.016)
        check(press_cnt == 1, "bind_key 'press' fires on initial press")
        _G.update(0.016)
        check(press_cnt == 1, "bind_key 'press' does not re-fire while held")
        active[75] = false; _G.update(0.016)
        check(press_cnt == 1, "bind_key 'press' does not fire on release")

        -- Hold mode on J (74): 3 frames held -> 3 calls, 1 frame released -> still 3
        active[74] = true
        _G.update(0.016); _G.update(0.016); _G.update(0.016)
        active[74] = false; _G.update(0.016)
        check(hold_cnt == 3, "bind_key 'hold' triggers every frame key is held (got " .. tostring(hold_cnt) .. ")")

        -- Release mode on A (65): press + hold -> 0, release -> 1
        active[65] = true
        _G.update(0.016); _G.update(0.016)
        check(release_cnt == 0, "bind_key 'release' does NOT fire on press or hold")
        active[65] = false
        _G.update(0.016)
        check(release_cnt == 1, "bind_key 'release' fires exactly once on key release")

        -- Test ModBindingsMenu live _G.Keyboard lookup when sr.Keyboard is removed/swapped after load
        local orig_sr_kb = _G.stingray.Keyboard
        _G.stingray.Keyboard = nil
        local swapped_pressed = false
        _G.Keyboard = {
            button_id = function(n) return (n == "b") and 66 or nil end,
            pressed = function(id) return id == 66 and swapped_pressed end,
            button = function() return 0 end,
        }
        assert(mbm.register_binding("audit_live_kb", "Audit Live KB", nil, { default = "b", category = "Audit" }))
        swapped_pressed = true
        check(mbm.is_pressed("audit_live_kb") == true, "ModBindingsMenu uses live _G.Keyboard instead of stale cached reference")
        _G.Keyboard = nil
        _G.stingray.Keyboard = orig_sr_kb

        -- Test 4K (3840x2160) notification box height scaling >= 53px (px = 5, 7*px+18 = 53)
        local max_toast_h = 0
        local orig_rect_fn = _G.stingray.Gui.rect
        _G.stingray.Gui.rect = function(g, pos, size, col)
            if size and size.y and size.y > max_toast_h and size.y < 200 then
                max_toast_h = size.y
            end
            return orig_rect_fn(g, pos, size, col)
        end
        mod_obj:notify("4K TOAST SCALE CHECK", 2.0)
        _G.update(0.016)
        _G.render()
        _G.stingray.Gui.rect = orig_rect_fn
        check(max_toast_h >= 53, "4K notification toast box_h scales cleanly with px (" .. tostring(max_toast_h) .. " >= 53)")

        -- Test ModOptionsMenu.reset() fires on_change callbacks
        local reset_fired_val = nil
        assert(mom.register_option("audit_reset_cb_opt", { type = "slider", title = "Audit", default = 10 }))
        mom.on_change("audit_reset_cb_opt", function(val) reset_fired_val = val end)
        mom.set("audit_reset_cb_opt", 99)
        reset_fired_val = nil
        mom.reset()
        check(reset_fired_val == 10, "ModOptionsMenu.reset() invokes on_change callbacks when restoring defaults")
    end

    clear_settings_files()

    -- =========================================================================
    -- GROUP 3: Chef Bridge Isolation, Safe Formatting, RatsSharedLoader & BML Hooks
    -- =========================================================================
    do
        track_temp_file("mods/audit_mod_a.lua")
        track_temp_file("mods/audit_mod_b.lua")
        local fa = assert(io.open("mods/audit_mod_a.lua", "wb"))
        fa:write([[
local csl = require("ChefSharedLoader")
csl.option("opt_a", { title = nil, label = "Opt A", default = true })
csl.log("100% loaded mod A")
csl:info("colon 50% safe")
csl.warn(nil)
local ctx = ...
ctx:log("ctx percent 25% safe")
_G.__AUDIT_MOD_A_CTX = ctx
return { who = "A" }
]])
        fa:close()

        local fb = assert(io.open("mods/audit_mod_b.lua", "wb"))
        fb:write([[
local csl = require("ChefSharedLoader")
csl.option("opt_b", { label = "Opt B", default = false })
csl.shared.shared_flag = 12345
return { who = "B" }
]])
        fb:close()

        local fm = assert(io.open("mods/mods.txt", "wb"))
        fm:write("mods/audit_mod_a\nmods/audit_mod_b\n")
        fm:close()

        local _, counts = boot_real_loader()
        local mom = _G.ModOptionsMenu
        local mod_a_grp = mom.registered["opt_a"] and (mom.registered["opt_a"].mod or mom.registered["opt_a"].title)
        local mod_b_grp = mom.registered["opt_b"] and (mom.registered["opt_b"].mod or mom.registered["opt_b"].title)
        check(mod_a_grp == "AUDIT MOD A", "require('ChefSharedLoader') uses active mod A title (not 'CHEF SHARED LOADER')")
        check(mod_b_grp == "AUDIT MOD B", "2nd mod require('ChefSharedLoader') is NOT pinned to mod A's name")
        check(_G.ChefSharedLoader.shared and _G.ChefSharedLoader.shared.shared_flag == 12345, "ChefSharedLoader.shared table exists and preserves shared state")

        -- Also direct safety checks on ChefSharedLoader & ctx log/info/warn/error
        local csl = _G.ChefSharedLoader
        local ok_log = pcall(function()
            csl.log("100%% literal %s", "hi")
            csl.log("bare 100% sign")
            csl:info("colon 100%")
            csl.warn(nil)
            csl.error("% invalid %q")
            _G.__AUDIT_MOD_A_CTX:warn("50% ctx warn")
        end)
        check(ok_log, "ChefSharedLoader & ctx log/info/warn/error safely handle bare '%', nil, and colon calls")
        _G.__AUDIT_MOD_A_CTX = nil

        -- RatsSharedLoader dot vs colon syntax + BootModLoader hook dispatch
        local rat = _G.RatsSharedLoader
        local got_args = {}
        rat.register("audit_rat", { ver = 2 })
        check(rat.get_spec("audit_rat", "extra") and rat.get_spec("audit_rat", "extra").ver == 2, "RatsSharedLoader.get_spec works in dot syntax with extra args")
        rat.on("audit_evt", function(a, b, c) got_args = { a = a, b = b, c = c } end)
        rat.trigger("audit_evt", "first", nil, "third")
        check(got_args.a == "first" and got_args.b == nil and got_args.c == "third", "RatsSharedLoader.trigger dot syntax preserves 1st arg and nil holes")
        got_args = {}
        rat:trigger("audit_evt", "c_first", nil, "c_third")
        check(got_args.a == "c_first" and got_args.b == nil and got_args.c == "c_third", "RatsSharedLoader:trigger colon syntax preserves 1st arg and nil holes")

        local bml = _G.BootModLoader
        local bml_upd, bml_shut = 0, 0
        bml.hook("update", function() bml_upd = bml_upd + 1 end)
        bml.hook("shutdown", function() bml_shut = bml_shut + 1 end)
        _G.update(0.016)
        _G.shutdown()
        local init_c, upd_c, shut_c = counts()
        check(bml_upd == 1 and upd_c == 1, "BootModLoader.hook('update') dispatches cleanly alongside chained original update")
        check(bml_shut == 1 and shut_c == 1, "BootModLoader.hook('shutdown') dispatches cleanly alongside chained original shutdown")
    end

    clear_settings_files()

    -- =========================================================================
    -- GROUP 4: Hot-Reload (Ctrl+F5), Full Hook Pruning, Auto-Reload Toggle & Error Logging
    -- =========================================================================
    do
        local script_path = "mods/audit_hotreload_v1.lua"
        track_temp_file(script_path)
        local f1 = assert(io.open(script_path, "wb"))
        f1:write([[
_G.__HR_V1_HITS = { upd = 0, bml = 0, hd2 = 0, rat = 0, key = 0, mom = 0, shut = 0 }
local m = UML.register("AuditHotMod", { version = "1.0" })
m:on_update(function() _G.__HR_V1_HITS.upd = _G.__HR_V1_HITS.upd + 1 end)
m:on_shutdown(function() _G.__HR_V1_HITS.shut = _G.__HR_V1_HITS.shut + 1 end)
m:bind_key("k", function() _G.__HR_V1_HITS.key = _G.__HR_V1_HITS.key + 1 end, "press")
BootModLoader.hook("update", function() _G.__HR_V1_HITS.bml = _G.__HR_V1_HITS.bml + 1 end)
HD2Runtime.on("audit_hr_evt", function() _G.__HR_V1_HITS.hd2 = _G.__HR_V1_HITS.hd2 + 1 end)
RatsSharedLoader.on("audit_hr_rat", function() _G.__HR_V1_HITS.rat = _G.__HR_V1_HITS.rat + 1 end)
ModOptionsMenu.register_option("audit_hr_opt", { type = "toggle", title = "AuditHR", default = false })
ModOptionsMenu.on_change("audit_hr_opt", function() _G.__HR_V1_HITS.mom = _G.__HR_V1_HITS.mom + 1 end)
return true
]])
        f1:close()

        local fm = assert(io.open("mods/mods.txt", "wb"))
        fm:write("mods/audit_hotreload_v1\n")
        fm:close()

        local env = boot_real_loader()
        local active = env.active
        _G.update(0.016)
        check(_G.__HR_V1_HITS.upd == 1 and _G.__HR_V1_HITS.bml == 1, "Pre-reload v1 update and BML hooks active")

        -- Overwrite v1 file on disk with v2
        local f2 = assert(io.open(script_path, "wb"))
        f2:write([[
_G.__HR_V2_HITS = { upd = 0, bml = 0, hd2 = 0, rat = 0, key = 0, mom = 0, shut = 0 }
local m = UML.register("AuditHotMod", { version = "2.0" })
m:on_update(function() _G.__HR_V2_HITS.upd = _G.__HR_V2_HITS.upd + 1 end)
m:on_shutdown(function() _G.__HR_V2_HITS.shut = _G.__HR_V2_HITS.shut + 1 end)
m:bind_key("k", function() _G.__HR_V2_HITS.key = _G.__HR_V2_HITS.key + 1 end, "press")
BootModLoader.hook("update", function() _G.__HR_V2_HITS.bml = _G.__HR_V2_HITS.bml + 1 end)
HD2Runtime.on("audit_hr_evt", function() _G.__HR_V2_HITS.hd2 = _G.__HR_V2_HITS.hd2 + 1 end)
RatsSharedLoader.on("audit_hr_rat", function() _G.__HR_V2_HITS.rat = _G.__HR_V2_HITS.rat + 1 end)
ModOptionsMenu.on_change("audit_hr_opt", function() _G.__HR_V2_HITS.mom = _G.__HR_V2_HITS.mom + 1 end)
return true
]])
        f2:close()

        -- Test uml_auto_reload = false blocks Ctrl+F5
        _G.ModOptionsMenu.set("uml_auto_reload", false)
        active[17] = true; active[116] = true -- Ctrl+F5
        _G.update(0.016)
        active[17] = false; active[116] = false
        _G.update(0.016)
        check(_G.__HR_V2_HITS == nil, "uml_auto_reload = false prevents Ctrl+F5 hot-reload")

        -- Re-enable uml_auto_reload and ALSO open F9 menu to prove Ctrl+F5 works inside F9 menu!
        _G.ModOptionsMenu.set("uml_auto_reload", true)
        active[120] = true; _G.update(0.016); active[120] = false; _G.update(0.016) -- open F9 menu
        active[17] = true; active[116] = true -- Ctrl+F5 while menu is open
        _G.update(0.016)
        active[17] = false; active[116] = false
        active[27] = true; _G.update(0.016); active[27] = false -- close menu

        -- Snapshot v1 and v2 counts right before triggering events + single update/shutdown frame
        local v1_snap = {
            upd = _G.__HR_V1_HITS.upd,
            bml = _G.__HR_V1_HITS.bml,
            hd2 = _G.__HR_V1_HITS.hd2,
            rat = _G.__HR_V1_HITS.rat,
            key = _G.__HR_V1_HITS.key,
            mom = _G.__HR_V1_HITS.mom,
            shut = _G.__HR_V1_HITS.shut,
        }
        local v2_upd_before = _G.__HR_V2_HITS.upd
        local v2_bml_before = _G.__HR_V2_HITS.bml
        _G.HD2Runtime.emit("audit_hr_evt")
        _G.RatsSharedLoader.trigger("audit_hr_rat")
        _G.ModOptionsMenu.set("audit_hr_opt", true)
        active[75] = true -- press K
        _G.update(0.016)
        active[75] = false
        _G.shutdown()

        check(_G.__HR_V2_HITS ~= nil, "Ctrl+F5 hot-reload succeeds even while F9 menu is open")
        check(_G.__HR_V1_HITS.upd == v1_snap.upd and (_G.__HR_V2_HITS.upd - v2_upd_before) == 1, "unregister_mod_hooks pruned v1 on_update")
        check(_G.__HR_V1_HITS.bml == v1_snap.bml and (_G.__HR_V2_HITS.bml - v2_bml_before) == 1, "unregister_mod_hooks pruned v1 BootModLoader.hook('update')")
        check(_G.__HR_V1_HITS.hd2 == v1_snap.hd2 and _G.__HR_V2_HITS.hd2 == 1, "unregister_mod_hooks pruned v1 HD2Runtime.on listener")
        check(_G.__HR_V1_HITS.rat == v1_snap.rat and _G.__HR_V2_HITS.rat == 1, "unregister_mod_hooks pruned v1 RatsSharedLoader.on listener")
        check(_G.__HR_V1_HITS.key == v1_snap.key and _G.__HR_V2_HITS.key == 1, "unregister_mod_hooks pruned v1 mod:bind_key")
        check(_G.__HR_V1_HITS.mom == v1_snap.mom and _G.__HR_V2_HITS.mom == 1, "unregister_mod_hooks pruned v1 ModOptionsMenu.on_change callback")
        check(_G.__HR_V1_HITS.shut == 0 and _G.__HR_V2_HITS.shut == 1, "unregister_mod_hooks pruned v1 on_shutdown")

        -- Broken syntax reload logs into UniversalModLoader.log without crashing
        local fb = assert(io.open(script_path, "wb"))
        fb:write("this is intentionally invalid syntax !!! (")
        fb:close()
        active[17] = true; active[116] = true
        local ok_bad = pcall(_G.update, 0.016)
        active[17] = false; active[116] = false
        check(ok_bad, "Ctrl+F5 hot-reload syntax error does not crash update()")

        local found_err_log = false
        local errs = _G.UML and type(_G.UML.get_error_log) == "function" and _G.UML.get_error_log() or {}
        for _, entry in ipairs(errs) do
            if type(entry) == "table" and tostring(entry.source):find("hot_reload", 1, true) then
                found_err_log = true
                break
            end
        end
        local found_file_log = false
        for idx = 5, 9 do
            local lf = io.open(host_paths[idx], "rb")
            if lf then
                local log_txt = lf:read("*a") or ""
                lf:close()
                if log_txt:find("Syntax error compiling", 1, true) then
                    found_file_log = true
                    break
                end
            end
        end
        check(found_err_log and found_file_log, "Ctrl+F5 syntax error is recorded in UML error log and UniversalModLoader.log")

        _G.__HR_V1_HITS = nil
        _G.__HR_V2_HITS = nil
    end

    clear_settings_files()

    -- =========================================================================
    -- GROUP 5: Duplicate Hook Deduplication & Nested Patch require() Preservation
    -- =========================================================================
    do
        local patch_path = "data/9ba626afa44a3aa3.patch_497"
        track_temp_file(patch_path)
        local inner_name = "mods/audit_patch_inner"
        local inner_code = [[
-- HD2-Mod: mods/audit_patch_inner
local csl = require("ChefSharedLoader")
csl.option("inner_patch_opt", { label = "Inner Opt", default = true })
return { inner = true }
]]
        build_stingray_patch(patch_path, {
            { key_bytes = make_murmur64_bytes(inner_name), script_text = inner_code }
        })

        local outer_path = "mods/audit_outer_host.lua"
        track_temp_file(outer_path)
        local fo = assert(io.open(outer_path, "wb"))
        fo:write([[
local inner_res = require("mods/audit_patch_inner")
_G.__AUDIT_INNER_RES = inner_res
local hook_fn, hook_mask, hook_cnt = debug.gethook()
_G.__AUDIT_OUTER_HOOK_AFTER_REQ = (hook_fn ~= nil)
local csl = require("ChefSharedLoader")
csl.option("outer_post_opt", { label = "Outer Post Opt", default = true })

local m = UML.register("DupHookTest")
_G.__DUP_HOOK_CALLS = 0
m:on_update(function() _G.__DUP_HOOK_CALLS = _G.__DUP_HOOK_CALLS + 1 end)
-- Also verify CowboyBingusModLoader.on_update(id, nil) -> on_update(id, fn2) runs once per frame
CowboyBingusModLoader.on_update("audit_dup_id", function() end)
CowboyBingusModLoader.on_update("audit_dup_id", nil)
CowboyBingusModLoader.on_update("audit_dup_id", function() _G.__CB_DUP_CALLS = (_G.__CB_DUP_CALLS or 0) + 1 end)
return true
]])
        fo:close()

        -- Only list outer mod in mods.txt so inner patch mod is loaded via nested require()
        local fm = assert(io.open("mods/mods.txt", "wb"))
        fm:write("mods/audit_outer_host\n")
        fm:close()

        boot_real_loader()
        local mom = _G.ModOptionsMenu
        check(type(_G.__AUDIT_INNER_RES) == "table" and _G.__AUDIT_INNER_RES.inner == true, "Nested require() of .patch_N mod succeeds")
        check(_G.__AUDIT_OUTER_HOOK_AFTER_REQ == true, "Nested require() of .patch_N mod preserves outer watchdog debug hook")
        local inner_grp = mom.registered["inner_patch_opt"] and (mom.registered["inner_patch_opt"].mod or mom.registered["inner_patch_opt"].title)
        local outer_grp = mom.registered["outer_post_opt"] and (mom.registered["outer_post_opt"].mod or mom.registered["outer_post_opt"].title)
        check(inner_grp == "AUDIT PATCH INNER", "Inner patch mod gets its own option title")
        check(outer_grp == "AUDIT OUTER HOST", "Outer mod retains active_loading_mod_name after nested patch require()")

        _G.__CB_DUP_CALLS = 0
        _G.update(0.016)
        check(_G.__CB_DUP_CALLS == 1, "Re-registering on_update after nil does NOT duplicate execution in update_order")

        _G.__AUDIT_INNER_RES = nil
        _G.__AUDIT_OUTER_HOOK_AFTER_REQ = nil
        _G.__DUP_HOOK_CALLS = nil
        _G.__CB_DUP_CALLS = nil
    end
end

local ok, err = xpcall(run_all_tests, function(e)
    return tostring(e) .. "\n" .. debug.traceback()
end)
restore_all()
clear_loader_globals()

if not ok then
    io.stderr:write("FAILED: " .. tostring(err) .. "\n")
    os.exit(1)
end

print("----------------------------------------------------")
print(string.format("RESULTS: %d / %d swarm audit regression tests passed.", passed, total))
print("STATUS: ALL v2.0.4 SWARM AUDIT FIXES VERIFIED 100%!")
print("====================================================")
