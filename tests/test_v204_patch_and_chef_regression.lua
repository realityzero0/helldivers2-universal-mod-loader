-- tests/test_v204_patch_and_chef_regression.lua
-- End-to-end regression tests for:
--   1. Large Stingray patch archives (> 8,192 rows) with Lua mods past row 8,192
--   2. -- HD2-Addon: directives after 384+ byte comment headers
--   3. ChefSharedLoader methods via require("mods/chef_shared_loader/core_1")
--      (register, register_option, add_option, on("init"), infer_caller parent dir on main.lua)
--   4. Single-table ModOptionsMenu.register_option({ id = ..., ... })
--   5. Heavy 2MB+ / 40k-table payload completion under the 5000-instruction watchdog

local function u32_to_bytes(n)
    local b0 = n % 256
    local b1 = math.floor(n / 256) % 256
    local b2 = math.floor(n / 65536) % 256
    local b3 = math.floor(n / 16777216) % 256
    return string.char(b0, b1, b2, b3)
end

local function make_key(b)
    return string.rep(string.char(b), 8)
end

local lua_type_bytes = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
local dummy_type_bytes = string.rep("\0", 8)

local function run_tests()
    print("====================================================")
    print("Testing Large Patch Scan (>8192) & Chef API Edge Cases")
    print("====================================================")

    local pass_count = 0
    local total_count = 0
    local function test(name, fn)
        total_count = total_count + 1
        local ok, err = pcall(fn)
        if ok then
            pass_count = pass_count + 1
            print("  [PASS] " .. name)
        else
            print("  [FAIL] " .. name .. ": " .. tostring(err))
            error(err)
        end
    end

    local temp_dir = "tests/tmp_reg"
    local patch_path = "data/9ba626afa44a3aa3.patch_498"
    local loose_main_path = "mods/chef_require_late/main.lua"
    local loose_txt = "mods/mods.txt"

    -- Clean any leftover state
    pcall(os.remove, patch_path)
    pcall(os.remove, loose_main_path)
    local had_mods_txt = false
    local old_mods_txt = io.open(loose_txt, "rb")
    if old_mods_txt then
        had_mods_txt = old_mods_txt:read("*a")
        old_mods_txt:close()
    end

    os.execute('mkdir "data" 2>nul')
    os.execute('mkdir "mods\\chef_require_late" 2>nul')

    -- Build a 10,000-entry Stingray patch_498 where row 9,500 holds a real Lua mod
    -- with a 500-byte header banner before "-- HD2-Addon: mods/late_row_mod"
    local row_count = 10000
    local target_row = 9500
    local table_start = 72 + 32 -- 1 type (32 bytes)
    local data_offset = table_start + row_count * 80

    local long_banner = "-- " .. string.rep("=", 480) .. "\n"
    local late_script = long_banner .. [[
-- HD2-Addon: mods/test_author/deep_row_addon
local chef = require("mods/chef_shared_loader/core_1")
chef.register("deep_row_enabled", {
    label = "Deep Row Addon Toggle",
    type = "toggle",
    default = true
})
return true
]]
    local payload = u32_to_bytes(#late_script) .. u32_to_bytes(2) .. late_script

    local patch_hdr = u32_to_bytes(0xF0000011) .. u32_to_bytes(1) .. u32_to_bytes(row_count) .. string.rep("\0", 60)
    local type_desc = string.rep("\0", 32)
    local empty_row = string.rep("\0", 80)
    local target_row_bytes = make_key(0xA5)
        .. lua_type_bytes
        .. u32_to_bytes(data_offset) .. u32_to_bytes(0)
        .. string.rep("\0", 32)
        .. u32_to_bytes(#payload) .. u32_to_bytes(0) .. u32_to_bytes(0)
        .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

    local f_patch = assert(io.open(patch_path, "wb"))
    f_patch:write(patch_hdr)
    f_patch:write(type_desc)
    for i = 0, row_count - 1 do
        if i == target_row then
            f_patch:write(target_row_bytes)
        else
            f_patch:write(empty_row)
        end
    end
    f_patch:write(payload)
    f_patch:close()

    -- Build a loose main.lua mod that registers via require("mods/chef_shared_loader/core_1")
    -- both synchronously (register_option / add_option) and asynchronously in after_startup
    local main_lua = [[
local chef = require("mods/chef_shared_loader/core_1")
chef.register_option("req_opt_sync", {
    label = "Sync Register Option",
    type = "toggle",
    default = false
})
chef.add_option("req_opt_add", {
    label = "Add Option Alias",
    type = "slider",
    min = 1,
    max = 10,
    default = 5
})
chef.on("init", function()
    chef.options.register("req_opt_late", {
        label = "Late Init Option",
        type = "toggle",
        default = true
    })
end)
ModOptionsMenu.register_option({
    id = "single_table_mom_opt",
    label = "Single Table MOM",
    mod = "Single Table Test",
    type = "toggle",
    default = true
})
return true
]]
    local f_main = assert(io.open(loose_main_path, "wb"))
    f_main:write(main_lua)
    f_main:close()

    -- Add mods/chef_require_late/main to mods/mods.txt temporarily so boot_loader discovers it
    local f_mtxt = assert(io.open(loose_txt, "wb"))
    if had_mods_txt then f_mtxt:write(had_mods_txt .. "\n") end
    f_mtxt:write("mods/chef_require_late/main\n")
    f_mtxt:close()

    -- Mock clean minimal Stingray environment
    _G.ModOptionsMenu = nil
    _G.ModBindingsMenu = nil
    _G.ChefSharedLoader = nil
    _G.UML = nil
    _G.update = nil
    _G.render = nil
    _G.shutdown = nil
    for k in pairs(package.loaded) do
        if type(k) == "string" and (k:find("chef", 1, true) or k:find("deep_row", 1, true) or k:find("ModOptionsMenu", 1, true)) then
            package.loaded[k] = nil
        end
    end

    _G.stingray = {
        Application = {
            can_get = function() return false end,
            main_world = function() return "w1" end,
            worlds = function() return { "w1" } end,
            user_setting = function() return nil end
        },
        Keyboard = {
            button_index = function() return 1 end,
            pressed = function() return 0 end,
            button = function() return 0 end
        },
        Mouse = {
            button_index = function() return 1 end,
            pressed = function() return 0 end
        },
        Gui = {
            resolution = function() return 1920, 1080 end,
            rect = function() end,
            text = function() end
        },
        World = {
            create_screen_gui = function() return "gui1" end
        },
        Vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        Vector2 = function(x, y) return { x = x, y = y } end,
        Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end
    }

    local chunk = assert(loadfile("src/boot_loader.lua"))
    chunk()
    -- Run 2 frames to trigger after_startup
    _G.update(0.016)
    _G.update(0.016)

    local mom = _G.ModOptionsMenu

    test("Patch scanner scans past row 8,192 and finds row 9,500 after 480-byte banner", function()
        assert(mom and mom.registered["deep_row_enabled"], "deep_row_enabled at row 9,500 was not registered!")
        assert(mom.get("deep_row_enabled") == true, "deep_row_enabled default must be true")
    end)

    test("Chef require() exposes register_option and add_option aliases cleanly", function()
        assert(mom.registered["req_opt_sync"], "chef.register_option failed via require()")
        assert(mom.registered["req_opt_add"], "chef.add_option failed via require()")
        assert(mom.get("req_opt_add") == 5, "req_opt_add default must be 5")
    end)

    test("Chef after_startup late option registration resolves parent folder mod name instead of MAIN", function()
        local spec = mom.registered["req_opt_late"]
        assert(spec, "req_opt_late not registered in after_startup")
        assert(spec.mod ~= "MAIN" and spec.mod ~= "INIT" and spec.mod ~= "GENERAL MODS",
            "Expected parent folder name, got: " .. tostring(spec.mod))
        assert(spec.mod == "CHEF REQUIRE LATE", "Expected CHEF REQUIRE LATE, got: " .. tostring(spec.mod))
    end)

    test("ModOptionsMenu.register_option supports single-table call { id = ..., ... }", function()
        local spec = mom.registered["single_table_mom_opt"]
        assert(spec, "single_table_mom_opt not registered")
        assert(spec.mod == "Single Table Test", "Unexpected mod name: " .. tostring(spec.mod))
        assert(mom.get("single_table_mom_opt") == true, "single_table_mom_opt default must be true")
    end)

    test("Watchdog safely completes 40,455-table initialization well under 8s timeout", function()
        local big_script_parts = { "local t = {}\n" }
        for i = 1, 40500 do
            big_script_parts[#big_script_parts + 1] = "t[" .. i .. "] = { a = " .. i .. ", b = true }\n"
        end
        big_script_parts[#big_script_parts + 1] = "return #t"
        local big_fn = assert(loadstring(table.concat(big_script_parts), "@big_payload"))
        local start_t = os.clock()
        local c = 0
        local function hook()
            c = c + 1
            if c % 25 == 0 and (os.clock() - start_t) > 8.0 then
                debug.sethook()
                error("WATCHDOG_HANG_TIMEOUT")
            end
        end
        debug.sethook(hook, "", 5000)
        local ok, count_res = pcall(big_fn)
        debug.sethook()
        local elapsed = os.clock() - start_t
        assert(ok and count_res == 40500, "Heavy 40.5k-table script failed: " .. tostring(count_res))
        assert(elapsed < 2.0, "Heavy script took too long under 5000-step hook: " .. tostring(elapsed) .. "s")
    end)

    -- Teardown temp files
    pcall(os.remove, patch_path)
    pcall(os.remove, loose_main_path)
    os.execute('rmdir "mods\\chef_require_late" 2>nul')
    if had_mods_txt then
        local rf = assert(io.open(loose_txt, "wb"))
        rf:write(had_mods_txt)
        rf:close()
    else
        pcall(os.remove, loose_txt)
    end

    print("----------------------------------------------------")
    print(string.format("RESULTS: %d / %d regression tests passed.", pass_count, total_count))
    print("STATUS: ALL LARGE PATCH & CHEF REGRESSION TESTS PASSED!")
    print("====================================================")
end

run_tests()
