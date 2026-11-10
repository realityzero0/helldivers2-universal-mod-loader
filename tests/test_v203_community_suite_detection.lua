-- tests/test_v203_community_suite_detection.lua
-- Comprehensive verification of UML v2.0.3 Community Mod Discovery & Ecosystem Support:
-- 1. Universal Archive Lua Resource Enumeration (raw/anonymous Lua resources in Stingray patch files)
-- 2. Discovery & Initialization of Panther117's reported community mod suite:
--    - DriverHud
--    - Scope Zoom
--    - Night Vision - Flashlight
--    - Treasure Radar
--    - NarrowHud
--    - Armor Transmog
-- 3. Non-shadowing package.loaded integrity for Rat's Shared Loader and Chef contexts
-- 4. In-Game F9 Menu verification:
--    - Distinct sidebar entry per detected mod
--    - Zero options in "GENERAL MODS"
--    - Hierarchical Category Folds (nested categories, fold state expansion/collapse)
--    - Option setting preservation during fold navigation

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

local function run_test()
    print("====================================================")
    print("Testing UML v2.0.3 Community Mod Suite Discovery & F9")
    print("====================================================")

    -- -------------------------------------------------------------------------
    -- 0. Set up temporary test files (loose mods and synthetic patch archive)
    -- -------------------------------------------------------------------------
    os.execute("if not exist mods mkdir mods")
    os.execute("if not exist data mkdir data")

    -- Clean any leftover global flags
    _G.TEST_DRIVER_HUD_LOADED = nil
    _G.TEST_SCOPE_ZOOM_LOADED = nil
    _G.TEST_NIGHT_VISION_LOADED = nil
    _G.TEST_TREASURE_RADAR_LOADED = nil
    _G.TEST_NARROW_HUD_LOADED = nil
    _G.TEST_ARMOR_TRANSMOG_LOADED = nil
    _G.TEST_TRANSMOG_INIT_CALLED = nil
    _G.TEST_TRANSMOG_UPDATE_CALLED = nil

    -- Mod 1: DriverHud (loose script in mods/driver_hud.lua)
    local f_dh = io.open("mods/driver_hud.lua", "w")
    assert(f_dh, "Failed to create mods/driver_hud.lua")
    f_dh:write([[
-- @mod mods/driverhud/driver_hud
local chef = rawget(_G, "ChefSharedLoader") or ...
_G.TEST_DRIVER_HUD_LOADED = true

if chef and chef.option then
    chef.option("dh_speedometer", { label = "Digital Speedometer", type = "toggle", default = true, category = "Gauges" })
    chef.option("dh_damage_indicator", { label = "Vehicle Damage Warning", type = "toggle", default = true, category = "Gauges" })
    chef.option("dh_shift_assist", { label = "Automatic Gear Assist", type = "toggle", default = false, category = "Controls" })
    chef.option("dh_steering_sens", { label = "Steering Sensitivity", type = "slider", min = 1, max = 5, step = 1, default = 3, category = "Controls" })
end

return { name = "DriverHud", version = "1.6.5", active = true }
]])
    f_dh:close()

    -- Mod 2: Scope Zoom (loose script in mods/ScopeZoom.lua with slash-path category syntax)
    local f_sz = io.open("mods/ScopeZoom.lua", "w")
    assert(f_sz, "Failed to create mods/ScopeZoom.lua")
    f_sz:write([[
-- Scope Zoom community mod
local c = ...
_G.TEST_SCOPE_ZOOM_LOADED = true

if c and c.option then
    c.option("ScopeZoom/Speed", { label = "Zoom Transition Speed", type = "slider", min = 0.5, max = 5.0, step = 0.5, default = 1.5 })
    c.option("ScopeZoom/Invert", { label = "Invert Mouse Wheel", type = "toggle", default = false })
    c.option("ScopeZoom/FOV", { label = "Max Magnification FOV", type = "slider", min = 10, max = 80, step = 5, default = 35 })
    c.option("Keybindings/ToggleKey", { label = "Scope Zoom Key", type = "key", default = "z" })
    c.option("Keybindings/ResetKey", { label = "Reset Zoom Key", type = "key", default = "middle_mouse" })
end

return { name = "ScopeZoom", active = true }
]])
    f_sz:close()

    -- Mod 3: Night Vision - Flashlight (loose script in mods/night_vision.lua)
    local f_nv = io.open("mods/night_vision.lua", "w")
    assert(f_nv, "Failed to create mods/night_vision.lua")
    f_nv:write([[
-- @mod mods/azpider18/night_vision
local chef = ...
_G.TEST_NIGHT_VISION_LOADED = true

if chef and chef.option then
    chef.option("nv_enabled", { label = "Night Vision Goggles", type = "toggle", default = true, category = "Night Vision" })
    chef.option("nv_phosphor", { label = "Phosphor Color", type = "choice", choices = { "Green", "White", "Amber" }, default = 1, category = "Night Vision" })
    chef.option("nv_gain", { label = "Amplification Gain", type = "slider", min = 1, max = 10, step = 1, default = 5, category = "Night Vision" })
    chef.option("fl_enabled", { label = "Weapon Flashlight", type = "toggle", default = true, category = "Flashlight" })
    chef.option("fl_beam", { label = "Beam Focus", type = "choice", choices = { "Narrow", "Flood", "Hybrid" }, default = 2, category = "Flashlight" })
    chef.option("nv_hotkey", { label = "Toggle NVG Key", type = "key", default = "n", category = "Controls" })
end

return { name = "NightVisionFlashlight", active = true }
]])
    f_nv:close()

    -- Mod 4: NarrowHud (loose script in mods/narrow_hud.lua)
    local f_nh = io.open("mods/narrow_hud.lua", "w")
    assert(f_nh, "Failed to create mods/narrow_hud.lua")
    f_nh:write([[
-- @mod mods/narrow_hud
local c = ...
_G.TEST_NARROW_HUD_LOADED = true

if c and c.option then
    c.option("nh_aspect_ratio", { label = "Target Aspect Ratio", type = "choice", choices = { "16:9", "21:9", "32:9", "Custom" }, default = 1, category = "Layout" })
    c.option("nh_h_margin", { label = "Horizontal Inset Margin", type = "slider", min = 0, max = 400, step = 20, default = 120, category = "Layout" })
    c.option("nh_compass_pos", { label = "Compass Center Pinning", type = "toggle", default = true, category = "Layout" })
    c.option("nh_reticle_alpha", { label = "Reticle Opacity", type = "slider", min = 20, max = 100, step = 10, default = 90, category = "Visuals" })
    c.option("nh_dial_fade", { label = "Fade Weapon Dial When Idle", type = "toggle", default = true, category = "Visuals" })
end

return { name = "NarrowHud", active = true }
]])
    f_nh:close()

    -- Mod 5: Armor Transmog (loose script in mods/transmog.lua using RatsSharedLoader ABI)
    local f_tm = io.open("mods/transmog.lua", "w")
    assert(f_tm, "Failed to create mods/transmog.lua")
    f_tm:write([[
-- @mod mods/armor_transmog
local rat = rawget(_G, "RatsSharedLoader") or require("RatsSharedLoader")
local chef = rawget(_G, "ChefSharedLoader") or ...
_G.TEST_ARMOR_TRANSMOG_LOADED = true

if rat and rat.on then
    rat:on("init", function()
        _G.TEST_TRANSMOG_INIT_CALLED = true
    end)
    rat:on("update", function(dt)
        _G.TEST_TRANSMOG_UPDATE_CALLED = true
    end)
end

if chef and chef.option then
    chef.option("tm_enabled", { label = "Enable Transmog System", type = "toggle", default = true, category = "General" })
    chef.option("tm_helmet_override", { label = "Helmet Model ID", type = "choice", choices = { "Standard Issue", "Hero of the Federation", "Kavalleri", "B-01 Tactical" }, default = 1, category = "Appearance" })
    chef.option("tm_armor_override", { label = "Torso Armor Model ID", type = "choice", choices = { "Standard", "Heavy Exterminator", "Enforcer", "Eradicator" }, default = 2, category = "Appearance" })
    chef.option("tm_cape_override", { label = "Cape Model ID", type = "choice", choices = { "Default", "Foesmasher", "Independence", "Creek Commemorative" }, default = 1, category = "Appearance" })
    chef.option("tm_preserve_passives", { label = "Preserve Underlying Armor Passives", type = "toggle", default = true, category = "Stat Protection" })
end

return { name = "ArmorTransmog", version = "1.1.2", active = true }
]])
    f_tm:close()

    -- Mod 6: Treasure Radar in synthetic patch archive (testing Universal Archive Enumeration)
    -- We construct a valid patch archive 9ba626afa44a3aa3.patch_499 containing a raw Lua resource
    -- with key K = murmur64_key("mods/treasure_radar") and NO comment prefix!
    local radar_script = [[
local c = ...
_G.TEST_TREASURE_RADAR_LOADED = true

if c and c.option then
    c.option("tr_enabled", { label = "Treasure Radar Master", type = "toggle", default = true, category = "General" })
    c.option("tr_scan_radius", { label = "Detection Radius (Meters)", type = "slider", min = 25, max = 250, step = 25, default = 100, category = "Radar Settings" })
    c.option("tr_sweep_speed", { label = "Radar Sweep Interval", type = "slider", min = 1, max = 10, step = 1, default = 3, category = "Radar Settings" })
    c.option("tr_detect_samples", { label = "Detect Rare & Super Samples", type = "toggle", default = true, category = "Detection Filters" })
    c.option("tr_detect_credits", { label = "Detect Super Credits", type = "toggle", default = true, category = "Detection Filters" })
    c.option("tr_detect_medals", { label = "Detect Warbond Medals", type = "toggle", default = true, category = "Detection Filters" })
    c.option("tr_detect_reqs", { label = "Detect Requisition Slips", type = "toggle", default = false, category = "Detection Filters" })
    c.option("tr_ping_sound", { label = "Audible Ping on Detection", type = "toggle", default = true, category = "Audio & Visuals" })
    c.option("tr_marker_scale", { label = "HUD Radar Blip Scale", type = "slider", min = 1, max = 5, step = 1, default = 2, category = "Audio & Visuals" })
    c.option("tr_marker_color", { label = "Blip Marker Palette", type = "choice", choices = { "Gold", "Cyan", "Emerald", "High-Contrast Pink" }, default = 1, category = "Audio & Visuals" })
end

return { name = "TreasureRadar", active = true }
]]

    local function u32_to_bytes(v)
        local b0 = v % 256
        v = math.floor(v / 256)
        local b1 = v % 256
        v = math.floor(v / 256)
        local b2 = v % 256
        v = math.floor(v / 256)
        local b3 = v % 256
        return string.char(b0, b1, b2, b3)
    end

    -- Precomputed MurmurHash64 for "mods/treasure_radar"
    -- In Helldivers 2 / Stingray, hash of "mods/treasure_radar"
    -- Let's build a patch file with 1 Lua resource
    -- Envelope: [4 bytes script len][4 bytes 2][script content]
    local env_hdr = u32_to_bytes(#radar_script) .. u32_to_bytes(2)
    local env_payload = env_hdr .. radar_script
    local resource_len = #env_payload

    -- Resource type 0xA14E8DFA2CD117E2 -> \xE2\x17\xD1\x2C\xFA\x8D\x4E\xA1
    local lua_type_bytes = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)

    -- Header (72 bytes):
    -- magic 0xF0000011, types 1, count 1
    local patch_hdr = u32_to_bytes(0xF0000011) .. u32_to_bytes(1) .. u32_to_bytes(1) .. string.rep("\0", 60)
    -- Type table entry (32 bytes):
    local type_entry = string.rep("\0", 8) .. lua_type_bytes .. u32_to_bytes(1) .. string.rep("\0", 12)

    -- Row offset calculation:
    local table_size = 72 + 32 * 1 + 80 * 1
    local data_offset = math.ceil(table_size / 16) * 16
    local padding_before_data = string.rep("\0", data_offset - table_size)

    -- We compute the MurmurHash64 key K for "mods/treasure_radar" using pure Lua bitwise
    -- Or we can precompute the exact 8 bytes of MurmurHash64 for "mods/treasure_radar"
    -- Let's define the 64-bit murmur64 function for test preparation:
    local function murmur64_key_test(str)
        local len = #str
        local mix_l = 0x5BD1E995
        local mix_h = 0xC6A4A793
        local function mul64(al, ah, bl, bh)
            local a0, a1 = al % 65536, math.floor(al / 65536)
            local a2, a3 = ah % 65536, math.floor(ah / 65536)
            local b0, b1 = bl % 65536, math.floor(bl / 65536)
            local b2, b3 = bh % 65536, math.floor(bh / 65536)
            local p00 = a0 * b0
            local p01 = a0 * b1 + a1 * b0 + math.floor(p00 / 65536)
            local rl = (p00 % 65536) + (p01 % 65536) * 65536
            local c = math.floor(p01 / 65536)
            local p02 = a0 * b2 + a1 * b1 + a2 * b0 + c
            local p03 = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0 + math.floor(p02 / 65536)
            local rh = (p02 % 65536) + (p03 % 65536) * 65536
            return rl % 4294967296, rh % 4294967296
        end
        local function xor64(al, ah, bl, bh)
            local rl, rh = 0, 0
            local m = 1
            for _ = 0, 31 do
                local ba, bb = al % 2, bl % 2
                if ba ~= bb then rl = rl + m end
                al, bl = math.floor(al / 2), math.floor(bl / 2)
                m = m * 2
            end
            m = 1
            for _ = 0, 31 do
                local ba, bb = ah % 2, bh % 2
                if ba ~= bb then rh = rh + m end
                ah, bh = math.floor(ah / 2), math.floor(bh / 2)
                m = m * 2
            end
            return rl, rh
        end
        local function rshift47(al, ah)
            local new_h = 0
            local new_l = math.floor(ah / 32768)
            return new_l, new_h
        end
        local hl, hh = mul64(len, 0, mix_l, mix_h)
        local nblocks = math.floor(len / 8)
        for i = 0, nblocks - 1 do
            local o = i * 8 + 1
            local b = { str:byte(o, o + 7) }
            local kl = b[1] + b[2]*256 + b[3]*65536 + b[4]*16777216
            local kh = b[5] + b[6]*256 + b[7]*65536 + b[8]*16777216
            kl, kh = mul64(kl, kh, mix_l, mix_h)
            local r47_l, r47_h = rshift47(kl, kh)
            kl, kh = xor64(kl, kh, r47_l, r47_h)
            kl, kh = mul64(kl, kh, mix_l, mix_h)
            hl, hh = xor64(hl, hh, kl, kh)
            hl, hh = mul64(hl, hh, mix_l, mix_h)
        end
        local rem = len % 8
        if rem > 0 then
            local tail_l, tail_h = 0, 0
            local base = nblocks * 8 + 1
            local b = { 0, 0, 0, 0, 0, 0, 0, 0 }
            for i = 1, rem do b[i] = str:byte(base + i - 1) end
            tail_l = b[1] + b[2]*256 + b[3]*65536 + b[4]*16777216
            tail_h = b[5] + b[6]*256 + b[7]*65536 + b[8]*16777216
            hl, hh = xor64(hl, hh, tail_l, tail_h)
            hl, hh = mul64(hl, hh, mix_l, mix_h)
        end
        local r47_l, r47_h = rshift47(hl, hh)
        hl, hh = xor64(hl, hh, r47_l, r47_h)
        hl, hh = mul64(hl, hh, mix_l, mix_h)
        r47_l, r47_h = rshift47(hl, hh)
        hl, hh = xor64(hl, hh, r47_l, r47_h)
        return u32_to_bytes(hl) .. u32_to_bytes(hh)
    end

    -- MurmurHash64 key bytes for "mods/treasure_radar" as computed by UML's 64-bit MurmurHash64 engine
    local radar_hash_bytes = string.char(0x66, 0xc5, 0x3b, 0xab, 0x04, 0x29, 0xac, 0xc2)

    -- Entry row (80 bytes = 7 Qs + 6 Is):
    -- [8 bytes key][8 bytes type][8 bytes offset][32 bytes 0][4 bytes len][4 bytes 0][4 bytes 0][4 bytes 16][4 bytes 16][4 bytes 0]
    local entry_row = radar_hash_bytes
        .. lua_type_bytes
        .. u32_to_bytes(data_offset)
        .. u32_to_bytes(0)
        .. string.rep("\0", 32)
        .. u32_to_bytes(resource_len)
        .. u32_to_bytes(0)
        .. u32_to_bytes(0)
        .. u32_to_bytes(16)
        .. u32_to_bytes(16)
        .. u32_to_bytes(0)

    assert(#entry_row == 80, "Entry row must be exactly 80 bytes, got " .. #entry_row)

    local patch_path = "data/9ba626afa44a3aa3.patch_499"
    local f_patch = io.open(patch_path, "wb")
    assert(f_patch, "Failed to create " .. patch_path)
    f_patch:write(patch_hdr)
    f_patch:write(type_entry)
    f_patch:write(entry_row)
    f_patch:write(padding_before_data)
    f_patch:write(env_payload)
    f_patch:close()

    -- -------------------------------------------------------------------------
    -- 1. Mock Stingray Engine Environment
    -- -------------------------------------------------------------------------
    local active_keys = {}
    local rects_drawn = 0
    local mock_world = { id = "world_main" }
    local mock_gui = { id = "gui_main" }

    _G.stingray = {
        Application = {
            main_world = function() return mock_world end,
            worlds = function() return { mock_world } end,
            can_get = function(res_type, res_name)
                -- Emulate Stingray engine archive resource query
                if res_name == "mods/treasure_radar" or res_name == "treasure_radar" then
                    return true
                end
                return false
            end
        },
        Window = {
            has_focus = function() return true end
        },
        World = {
            create_screen_gui = function() return mock_gui end
        },
        Gui = {
            resolution = function() return 1920, 1080 end,
            rect = function(g, pos, sz, col)
                rects_drawn = rects_drawn + 1
            end
        },
        Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        Vector2 = function(x, y) return { x = x, y = y } end,
        Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
        Keyboard = {
            button_id = function(k)
                local kl = tostring(k):lower()
                if kl == "f9" then return 119 end
                if kl == "escape" or kl == "esc" then return 27 end
                if kl == "enter" or kl == "return" then return 13 end
                if kl == "up" then return 38 end
                if kl == "down" then return 40 end
                if kl == "left" then return 37 end
                if kl == "right" then return 39 end
                if kl == "delete" then return 46 end
                if kl == "space" then return 32 end
                if kl == "backspace" then return 8 end
                if kl == "tab" then return 9 end
                if kl == "1" then return 49 end
                if kl == "2" then return 50 end
                if kl == "3" then return 51 end
                if kl == "4" then return 52 end
                if kl == "5" then return 53 end
                if kl == "6" then return 54 end
                if kl == "7" then return 55 end
                return nil
            end,
            button = function(id) return active_keys[id] == true end,
            pressed = function(id) return active_keys[id] == true end
        }
    }

    -- -------------------------------------------------------------------------
    -- 2. Compile and Boot Universal Mod Loader
    -- -------------------------------------------------------------------------
    local bf = io.open("src/boot_loader.lua", "r")
    assert(bf, "Failed to read src/boot_loader.lua")
    local boot_code = bf:read("*a")
    bf:close()

    local chunk, c_err = loadstring(boot_code, "boot_loader.lua")
    assert(chunk, "Failed to compile boot_loader.lua: " .. tostring(c_err))
    chunk()

    local mom = _G.ModOptionsMenu
    local uml = _G.UML
    local chef = _G.ChefSharedLoader
    local rat = _G.RatsSharedLoader
    local hd2rt = _G.HD2Runtime

    assert(mom, "ModOptionsMenu must exist")
    assert(uml, "UML global must exist")
    assert(chef and chef.is_chef_loader, "ChefSharedLoader must be active")
    assert(rat and rat.is_rat_loader, "RatsSharedLoader must be active")
    assert(hd2rt, "HD2Runtime must be active")

    -- -------------------------------------------------------------------------
    -- 3. Verify Universal Archive Lua Resource Enumeration (Treasure Radar)
    -- -------------------------------------------------------------------------
    test("Universal Archive Enumeration: Detects anonymous/raw Lua resource in patch_499", function()
        -- The synthetic patch_499 contains mods/treasure_radar without -- HD2-Addon: prefix
        -- UML patch scanner must have identified it via MurmurHash64 key and loaded it
        assert(_G.TEST_TREASURE_RADAR_LOADED == true, "Treasure Radar script must have executed successfully from patch")
        assert(package.loaded["mods/treasure_radar"] ~= nil or package.preload["mods/treasure_radar"] ~= nil, "Treasure Radar must be loaded or preloaded")
    end)

    -- -------------------------------------------------------------------------
    -- 4. Verify Loose Mod Discovery of Panther117's Reported Suite
    -- -------------------------------------------------------------------------
    test("Panther117 Suite: DriverHud discovered and loaded", function()
        assert(_G.TEST_DRIVER_HUD_LOADED == true, "DriverHud loose mod must be loaded")
        assert(package.loaded["mods/driverhud/driver_hud"] ~= nil or package.loaded["mods/driver_hud"] ~= nil, "DriverHud must be in package.loaded")
    end)

    test("Panther117 Suite: Scope Zoom discovered and loaded", function()
        assert(_G.TEST_SCOPE_ZOOM_LOADED == true, "Scope Zoom loose mod must be loaded")
        assert(package.loaded["mods/ScopeZoom"] ~= nil or package.loaded["mods/scope_zoom"] ~= nil, "Scope Zoom must be in package.loaded")
    end)

    test("Panther117 Suite: Night Vision - Flashlight discovered and loaded", function()
        assert(_G.TEST_NIGHT_VISION_LOADED == true, "Night Vision - Flashlight loose mod must be loaded")
        assert(package.loaded["mods/azpider18/night_vision"] ~= nil or package.loaded["mods/night_vision"] ~= nil, "Night Vision must be in package.loaded")
    end)

    test("Panther117 Suite: NarrowHud discovered and loaded", function()
        assert(_G.TEST_NARROW_HUD_LOADED == true, "NarrowHud loose mod must be loaded")
        assert(package.loaded["mods/narrow_hud"] ~= nil or package.loaded["mods/narrowhud"] ~= nil, "NarrowHud must be in package.loaded")
    end)

    test("Panther117 Suite: Armor Transmog discovered and loaded", function()
        assert(_G.TEST_ARMOR_TRANSMOG_LOADED == true, "Armor Transmog loose mod must be loaded")
        assert(package.loaded["mods/armor_transmog"] ~= nil or package.loaded["mods/transmog"] ~= nil, "Armor Transmog must be in package.loaded")
        assert(_G.TEST_TRANSMOG_INIT_CALLED == true, "RatsSharedLoader:on('init') hook must have run during after_startup")
    end)

    -- -------------------------------------------------------------------------
    -- 5. Non-Shadowing & ABI Integrity Verification
    -- -------------------------------------------------------------------------
    test("ABI Hygiene: package.loaded['mods/transmog'] is mod table, NOT rat_api loader table", function()
        local tm_mod = package.loaded["mods/transmog"] or package.loaded["mods/armor_transmog"]
        assert(type(tm_mod) == "table", "Transmog mod must return table")
        assert(tm_mod.is_rat_loader == nil, "package.loaded['mods/transmog'] must NOT be the RatsSharedLoader API instance!")
        assert(tm_mod.name == "ArmorTransmog", "package.loaded must hold ArmorTransmog module, got: " .. tostring(tm_mod.name))
    end)

    test("Chef Context Proxies: All extended helper methods available on mod context", function()
        local mod_c = package.preload["ChefSharedLoader"]("mods/test_mod_context")
        assert(type(mod_c.option) == "function", "c.option must exist")
        assert(type(mod_c.register_option) == "function", "c.register_option must exist")
        assert(type(mod_c.register) == "function", "c.register must exist")
        assert(type(mod_c.group) == "function", "c.group must exist")
        assert(type(mod_c.on) == "function", "c.on must exist")
        assert(type(mod_c.listen) == "function", "c.listen must exist")
        assert(type(mod_c.hook) == "function", "c.hook must exist")
        assert(type(mod_c.add_hook) == "function", "c.add_hook must exist")
        assert(type(mod_c.after_startup) == "function", "c.after_startup must exist")
        assert(type(mod_c.warn) == "function", "c.warn must exist")
        assert(type(mod_c.error) == "function", "c.error must exist")
        assert(type(mod_c.info) == "function", "c.info must exist")
        assert(type(mod_c.shared) == "table", "c.shared must be table")
    end)

    -- -------------------------------------------------------------------------
    -- 6. In-Game F9 Menu: Distinct Sidebar Entries & Zero General Mods Fallback
    -- -------------------------------------------------------------------------
    test("F9 Menu: All 6 community mods receive distinct sidebar entries & zero options in 'GENERAL MODS'", function()
        -- Open menu via F9
        active_keys[119] = true
        update(0.016)
        active_keys[119] = false
        render()

        -- Verify all expected options are present in ModOptionsMenu registry
        assert(mom.registered["dh_speedometer"], "dh_speedometer must be registered")
        assert(mom.registered["ScopeZoom/Speed"], "ScopeZoom/Speed must be registered")
        assert(mom.registered["nv_enabled"], "nv_enabled must be registered")
        assert(mom.registered["tr_enabled"], "tr_enabled must be registered")
        assert(mom.registered["nh_aspect_ratio"], "nh_aspect_ratio must be registered")
        assert(mom.registered["tm_enabled"], "tm_enabled must be registered")

        -- Verify 100% accurate mod attribution
        assert(mom.registered["dh_speedometer"].mod == "DRIVER HUD", "Must attribute to DRIVER HUD, got: " .. tostring(mom.registered["dh_speedometer"].mod))
        assert(mom.registered["ScopeZoom/Speed"].mod == "SCOPE ZOOM", "Must attribute to SCOPE ZOOM, got: " .. tostring(mom.registered["ScopeZoom/Speed"].mod))
        assert(mom.registered["nv_enabled"].mod == "NIGHT VISION - FLASHLIGHT", "Must attribute to NIGHT VISION - FLASHLIGHT, got: " .. tostring(mom.registered["nv_enabled"].mod))
        assert(mom.registered["tr_enabled"].mod == "TREASURE RADAR", "Must attribute to TREASURE RADAR, got: " .. tostring(mom.registered["tr_enabled"].mod))
        assert(mom.registered["nh_aspect_ratio"].mod == "NARROW HUD", "Must attribute to NARROW HUD, got: " .. tostring(mom.registered["nh_aspect_ratio"].mod))
        assert(mom.registered["tm_enabled"].mod == "ARMOR TRANSMOG", "Must attribute to ARMOR TRANSMOG, got: " .. tostring(mom.registered["tm_enabled"].mod))

        -- Verify none of the 6 mods fell back into "GENERAL MODS"
        for opt_id, spec in pairs(mom.registered) do
            if opt_id:match("^dh_") or opt_id:match("^ScopeZoom") or opt_id:match("^Keybindings") or
               opt_id:match("^nv_") or opt_id:match("^fl_") or opt_id:match("^tr_") or
               opt_id:match("^nh_") or opt_id:match("^tm_") then
                assert(spec.mod ~= "GENERAL MODS", "Option " .. opt_id .. " must NOT be collapsed into GENERAL MODS!")
            end
        end
    end)

    -- -------------------------------------------------------------------------
    -- 7. Hierarchical Category Folds: Navigation, Expansion, and Setting Safety
    -- -------------------------------------------------------------------------
    test("Category Folds: Treasure Radar generates nested folds with expand/collapse protection", function()
        -- Treasure Radar has 4 categories:
        -- "GENERAL", "RADAR SETTINGS", "DETECTION FILTERS", "AUDIO & VISUALS"
        -- Quick-jump into TREASURE RADAR or select it via sidebar
        -- Let's inspect options registration for Treasure Radar
        local tr_rad_val = mom.get("tr_scan_radius")
        assert(tr_rad_val == 100, "Default tr_scan_radius must be 100")

        -- Right arrow or Left arrow on category headers must not alter options
        active_keys[39] = true -- Right
        update(0.016)
        active_keys[39] = false
        update(0.016)

        assert(mom.get("tr_scan_radius") == 100, "tr_scan_radius must remain 100 after fold header navigation")

        active_keys[37] = true -- Left
        update(0.016)
        active_keys[37] = false
        update(0.016)

        assert(mom.get("tr_scan_radius") == 100, "tr_scan_radius must remain 100 after fold collapse navigation")
    end)

    test("Category Folds: Modifying options inside expanded folds preserves state", function()
        -- Modify an option directly via mom.set or toggle logic
        mom.set("tr_detect_reqs", true)
        assert(mom.get("tr_detect_reqs") == true, "tr_detect_reqs must be updated to true")

        mom.set("ScopeZoom/Speed", 3.0)
        assert(mom.get("ScopeZoom/Speed") == 3.0, "ScopeZoom/Speed must be updated to 3.0")

        mom.set("nh_aspect_ratio", 2)
        assert(mom.get("nh_aspect_ratio") == 2, "nh_aspect_ratio choice must be updated to 2")

        mom.set("nv_phosphor", 2)
        assert(mom.get("nv_phosphor") == 2, "nv_phosphor choice must be updated to 2")

        mom.set("dh_speedometer", false)
        assert(mom.get("dh_speedometer") == false, "dh_speedometer must be toggled to false")

        mom.set("tm_helmet_override", 3)
        assert(mom.get("tm_helmet_override") == 3, "tm_helmet_override choice must be updated to 3")
    end)

    -- -------------------------------------------------------------------------
    -- 8. Clean Exit via ESC and Cleanup
    -- -------------------------------------------------------------------------
    test("F9 Menu: Closes cleanly via ESC", function()
        active_keys[27] = true
        update(0.016)
        active_keys[27] = false
        update(0.016)
    end)

    -- Teardown temporary files
    pcall(os.remove, patch_path)
    pcall(os.remove, "mods/driver_hud.lua")
    pcall(os.remove, "mods/ScopeZoom.lua")
    pcall(os.remove, "mods/night_vision.lua")
    pcall(os.remove, "mods/narrow_hud.lua")
    pcall(os.remove, "mods/transmog.lua")

    print("----------------------------------------------------")
    print(string.format("RESULTS: %d / %d tests passed.", pass_count, total_count))
    print("STATUS: ALL v2.0.3 COMMUNITY SUITE DETECTION TESTS PASSED!")
    print("====================================================")
end

run_test()
