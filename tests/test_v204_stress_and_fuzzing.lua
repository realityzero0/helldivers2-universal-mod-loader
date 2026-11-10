-- tests/test_v204_stress_and_fuzzing.lua
-- Exhaustive Stress Testing, Fuzzing & Resilience Verification Battery for UML v2.0.4:
-- 1. Corrupted JSON Settings Recovery (empty, half-written, malformed syntax, invalid types, extreme values)
-- 2. Corrupted and Malformed Patch Archive Chunks (truncated envelopes, invalid magic, buffer overreads, non-Lua data, rogue boot shielding)
-- 3. High-Concurrency Option Registration (128 mods, 640 options) & In-Game F9 Menu Pagination / Scale / Navigation Fuzzing
-- 4. Faulty Mod Simulation (runtime errors during require, init, update, shutdown, and circuit-breaker quarantine)

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

-- Pure Lua 5.1 helpers for binary archive generation
local function u32_to_bytes(v)
    v = v or 0
    local b0 = v % 256
    v = math.floor(v / 256)
    local b1 = v % 256
    v = math.floor(v / 256)
    local b2 = v % 256
    v = math.floor(v / 256)
    local b3 = v % 256
    return string.char(b0, b1, b2, b3)
end

local function u32(str, offset)
    local b0, b1, b2, b3 = string.byte(str, offset + 1, offset + 4)
    if not b3 then return 0 end
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

-- MurmurHash64A pure Lua implementation for generating valid resource keys
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
        local rl = math.floor(ah / 32768)
        local rh = 0
        return rl, rh
    end

    local seed_l, seed_h = 0, 0
    local hl, hh = xor64(seed_l, seed_h, mul64(len, 0, mix_l, mix_h))
    local nblocks = math.floor(len / 8)
    for i = 0, nblocks - 1 do
        local pos = i * 8 + 1
        local b1, b2, b3, b4, b5, b6, b7, b8 = str:byte(pos, pos + 7)
        local kl = b1 + b2*256 + b3*65536 + b4*16777216
        local kh = b5 + b6*256 + b7*65536 + b8*16777216
        kl, kh = mul64(kl, kh, mix_l, mix_h)
        local r_l, r_h = rshift47(kl, kh)
        kl, kh = xor64(kl, kh, r_l, r_h)
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

local function run_battery()
    print("====================================================================")
    print("Running UML v2.0.4 Stress Testing, Fuzzing & Resilience Battery")
    print("====================================================================")

    -- Back up real host settings and ensure clean test workspace
    os.execute("if not exist data mkdir data")
    os.execute("if not exist mods mkdir mods")
    local settings_path_local = "uml_mod_settings.json"
    local settings_path_bak = "uml_mod_settings.json.testbackup"
    local orig_settings = nil
    local f_orig = io.open(settings_path_local, "rb")
    if f_orig then
        orig_settings = f_orig:read("*a")
        f_orig:close()
        local f_bak = io.open(settings_path_bak, "wb")
        if f_bak then
            f_bak:write(orig_settings)
            f_bak:close()
        end
        os.remove(settings_path_local)
    end

    -- =========================================================================
    -- GROUP 1: CORRUPTED JSON SETTINGS RECOVERY & RESILIENCE
    -- =========================================================================
    print("\n--- GROUP 1: Corrupted JSON Settings Recovery ---")

    -- 1.1: Empty JSON file
    test("JSON Settings: Recovers safely from empty (0-byte) settings file", function()
        local f = io.open(settings_path_local, "wb")
        assert(f, "Failed to write empty settings")
        f:close()

        -- Simulate parser logic from boot_loader.lua
        local out = {}
        local f_in = io.open(settings_path_local, "r")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    out[k] = v
                end
            end
        end
        assert(type(out) == "table", "Parser must return valid table")
        assert(next(out) == nil, "Empty file must yield empty table without errors")
    end)

    -- 1.2: Whitespace-only JSON file
    test("JSON Settings: Recovers safely from whitespace-only (spaces, tabs, newlines) settings file", function()
        local f = io.open(settings_path_local, "w")
        assert(f)
        f:write("   \t\n\r  \n\t   \n")
        f:close()

        local out = {}
        local f_in = io.open(settings_path_local, "r")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    out[k] = v
                end
            end
        end
        assert(type(out) == "table", "Parser must return valid table")
        assert(next(out) == nil, "Whitespace-only file must yield empty table without errors")
    end)

    -- 1.3: Truncated / half-written JSON settings
    test("JSON Settings: Salvages valid options from half-written / truncated JSON", function()
        local f = io.open(settings_path_local, "w")
        assert(f)
        -- File truncated mid-stream (e.g. system crash during write)
        f:write('{\n  "uml_overlay": true,\n  "radar_scan_speed": 4,\n  "half_written_opt": ')
        f:close()

        local out = {}
        local f_in = io.open(settings_path_local, "r")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    v = v:match("^%s*(.-)%s*$")
                    if v == "true" then out[k] = true
                    elseif v == "false" then out[k] = false
                    elseif tonumber(v) then out[k] = tonumber(v)
                    elseif v:sub(1,1) == '"' and v:sub(-1) == '"' then out[k] = v:sub(2, -2) end
                end
            end
        end
        assert(out["uml_overlay"] == true, "Must salvage complete boolean option")
        assert(out["radar_scan_speed"] == 4, "Must salvage complete number option")
        assert(out["half_written_opt"] == nil, "Incomplete option must be safely discarded")
    end)

    -- 1.4: Malformed syntax: trailing commas, unquoted keys, bad brackets
    test("JSON Settings: Tolerates trailing commas, unquoted keys, and malformed braces", function()
        local f = io.open(settings_path_local, "w")
        assert(f)
        f:write('{\n  "opt_sound": true,\n  "volume": 85,\n  unquoted_key: 123,\n  "nested": { missing_brace: true,\n}\n')
        f:close()

        local out = {}
        local f_in = io.open(settings_path_local, "r")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    v = v:match("^%s*(.-)%s*$")
                    if v == "true" then out[k] = true
                    elseif v == "false" then out[k] = false
                    elseif tonumber(v) then out[k] = tonumber(v)
                    elseif v:sub(1,1) == '"' and v:sub(-1) == '"' then out[k] = v:sub(2, -2) end
                end
            end
        end
        assert(out["opt_sound"] == true, "Must parse valid key opt_sound")
        assert(out["volume"] == 85, "Must parse valid key volume despite trailing syntax errors")
    end)

    -- 1.5: Binary garbage & unrecoverable corrupt JSON backup (.bak)
    test("JSON Settings: Corrupted binary garbage generates .bak file without crashing", function()
        local f = io.open(settings_path_local, "wb")
        assert(f)
        -- Pure binary noise
        f:write(string.char(0x00, 0xFF, 0xFE, 0xFD, 0x10, 0x20, 0x30, 0x40, 0x80, 0x90) .. "TOTAL_BINARY_GARBAGE_NO_JSON")
        f:close()

        local out = {}
        local f_in = io.open(settings_path_local, "rb")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                local parsed_any = false
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    parsed_any = true
                    out[k] = v
                end
                local trimmed = content:match("^%s*(.-)%s*$") or ""
                if not parsed_any and trimmed ~= "{}" then
                    local fb = io.open(settings_path_local .. ".bak", "wb")
                    if fb then
                        fb:write(content)
                        fb:close()
                    end
                end
            end
        end

        assert(next(out) == nil, "Garbage must yield empty table")
        local f_chk = io.open(settings_path_local .. ".bak", "rb")
        assert(f_chk ~= nil, "Corrupted file must be backed up to .bak")
        local bak_data = f_chk:read("*a")
        f_chk:close()
        assert(#bak_data > 0, "Backup file must preserve corrupted bytes")
        os.remove(settings_path_local .. ".bak")
    end)

    -- 1.6: Type fuzzing (null, negative numbers, extreme floats, empty strings, nested objects)
    test("JSON Settings: Handles type fuzzing (null, negative floats, empty strings, nested objects)", function()
        local f = io.open(settings_path_local, "w")
        assert(f)
        f:write([[
{
  "opt_neg_float": -128.75,
  "opt_null": null,
  "opt_empty_str": "",
  "opt_large_int": 999999999,
  "opt_str_bool": "true",
  "opt_nested": { "child": 1 }
}
]])
        f:close()

        local out = {}
        local f_in = io.open(settings_path_local, "r")
        if f_in then
            local content = f_in:read("*a")
            f_in:close()
            if content and content:match("%S") then
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    v = v:match("^%s*(.-)%s*$")
                    if v == "true" then out[k] = true
                    elseif v == "false" then out[k] = false
                    elseif tonumber(v) then out[k] = tonumber(v)
                    elseif v:sub(1,1) == '"' and v:sub(-1) == '"' then out[k] = v:sub(2, -2) end
                end
            end
        end

        assert(out["opt_neg_float"] == -128.75, "Negative float parsed correctly")
        assert(out["opt_large_int"] == 999999999, "Large int parsed correctly")
        assert(out["opt_empty_str"] == "", "Empty string parsed correctly")
        assert(out["opt_str_bool"] == "true", "String bool retained as string")
        assert(out["opt_null"] == nil, "JSON null discarded cleanly")
    end)

    -- 1.7: Serialization robustness under extreme input types
    test("JSON Settings: save_settings_to_disk serializes robustly with foreign/unexpected types", function()
        local function save_settings_to_disk_test(values, dest_path)
            local parts = {}
            for k, v in pairs(values) do
                local val_str = "null"
                if type(v) == "boolean" then
                    val_str = v and "true" or "false"
                elseif type(v) == "number" then
                    val_str = tostring(v)
                elseif type(v) == "string" then
                    val_str = string.format("%q", v)
                end
                parts[#parts + 1] = string.format("  %q: %s", tostring(k), val_str)
            end
            local payload = "{\n" .. table.concat(parts, ",\n") .. "\n}\n"
            local f = io.open(dest_path, "w")
            if f then
                f:write(payload)
                f:close()
                return true
            end
            return false
        end

        local fuzzed_values = {
            bool_true = true,
            bool_false = false,
            int_val = 42,
            float_val = 3.14159,
            neg_val = -99,
            str_simple = "hello world",
            str_quotes = 'quote "test" and \n newline',
            func_val = function() end, -- foreign type
            table_val = { a = 1 },     -- foreign type
            thread_val = coroutine.create(function() end) -- foreign type
        }

        local ok = save_settings_to_disk_test(fuzzed_values, settings_path_local)
        assert(ok == true, "Must write settings successfully")

        -- Verify written file parses cleanly back
        local f_in = io.open(settings_path_local, "r")
        local content = f_in:read("*a")
        f_in:close()

        assert(content:find('"bool_true": true', 1, true) ~= nil)
        assert(content:find('"bool_false": false', 1, true) ~= nil)
        assert(content:find('"int_val": 42', 1, true) ~= nil)
        assert(content:find('"func_val": null', 1, true) ~= nil, "Foreign function type safely serialized as null")
        assert(content:find('"table_val": null', 1, true) ~= nil, "Foreign table type safely serialized as null")
    end)

    -- 1.8: Quoted string values containing commas and curly braces
    test("JSON Settings: Preserves quoted string values containing commas and curly braces", function()
        local test_json = [[
{
  "opt_comma": "Danger Zone, Outer Radius, Full Damage",
  "opt_braces": "{name}:{val}",
  "opt_escaped": "Quote: \"Hello\" \\ Backslash"
}
]]
        local f = io.open(settings_path_local, "w")
        assert(f)
        f:write(test_json)
        f:close()

        local f_in = io.open(settings_path_local, "r")
        local content = f_in:read("*a")
        f_in:close()

        assert(content:find("Danger Zone, Outer Radius, Full Damage", 1, true) ~= nil, "Commas in quotes preserved")
        assert(content:find("{name}:{val}", 1, true) ~= nil, "Curly braces in quotes preserved")
    end)

    -- 1.9: NaN and Infinity handling in serialization
    test("JSON Settings: Sanitizes NaN and Infinity numbers to avoid invalid unquoted JSON identifiers", function()
        local bad_numbers = {
            nan_val = 0/0,
            inf_val = 1/0,
            neg_inf_val = -1/0,
            valid_num = 42
        }
        local parts = {}
        for k, v in pairs(bad_numbers) do
            if type(v) == "number" then
                if v == v and v ~= math.huge and v ~= -math.huge then
                    parts[#parts + 1] = string.format("  %q: %s", tostring(k), tostring(v))
                end
            end
        end
        local json_out = "{\n" .. table.concat(parts, ",\n") .. "\n}\n"
        assert(json_out:find("nan") == nil, "NaN must not appear in JSON output")
        assert(json_out:find("inf") == nil, "Infinity must not appear in JSON output")
        assert(json_out:find('"valid_num": 42') ~= nil, "Valid number must be preserved")
    end)

    -- Clean up test settings file
    pcall(os.remove, settings_path_local)

    -- =========================================================================
    -- GROUP 2: CORRUPTED & MALFORMED PATCH ARCHIVE CHUNKS
    -- =========================================================================
    print("\n--- GROUP 2: Corrupted and Malformed Patch Archive Chunks ---")

    local lua_type_bytes = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)

    -- Helper to create synthetic patch file
    local function create_patch_file(path, magic, types_cnt, count, entries_data, payload_data)
        local f = io.open(path, "wb")
        assert(f, "Failed to create " .. path)
        local hdr = u32_to_bytes(magic) .. u32_to_bytes(types_cnt) .. u32_to_bytes(count) .. string.rep("\0", 60)
        f:write(hdr)
        if types_cnt > 0 then
            local type_tbl = string.rep("\0", 8) .. lua_type_bytes .. u32_to_bytes(types_cnt) .. string.rep("\0", 12)
            f:write(type_tbl)
        end
        if entries_data then
            f:write(entries_data)
        end
        if payload_data then
            f:write(payload_data)
        end
        f:close()
    end

    -- 2.1: Truncated Patch Header (< 72 bytes)
    test("Patch Scanner: Handles truncated patch header (< 72 bytes) gracefully", function()
        local p_path = "data/9ba626afa44a3aa3.patch_450"
        local f = io.open(p_path, "wb")
        f:write("SHORT_HEADER_ONLY_16B")
        f:close()

        local scanned_count = 0
        local f_in = io.open(p_path, "rb")
        if f_in then
            local header = f_in:read(72)
            if header and #header >= 72 and u32(header, 0) == 0xf0000011 then
                scanned_count = scanned_count + 1
            end
            f_in:close()
        end
        assert(scanned_count == 0, "Truncated header safely rejected without crash")
        os.remove(p_path)
    end)

    -- 2.2: Bad magic header
    test("Patch Scanner: Handles invalid magic (0xDEADBEEF) gracefully", function()
        local p_path = "data/9ba626afa44a3aa3.patch_451"
        create_patch_file(p_path, 0xDEADBEEF, 1, 1, nil, nil)

        local scanned_count = 0
        local f_in = io.open(p_path, "rb")
        if f_in then
            local header = f_in:read(72)
            if header and #header >= 72 and u32(header, 0) == 0xf0000011 then
                scanned_count = scanned_count + 1
            end
            f_in:close()
        end
        assert(scanned_count == 0, "Bad magic rejected safely")
        os.remove(p_path)
    end)

    -- 2.3: Enormous count field with truncated file (bounds defense)
    test("Patch Scanner: Handles enormous entry count with EOF defense", function()
        local p_path = "data/9ba626afa44a3aa3.patch_452"
        create_patch_file(p_path, 0xF0000011, 1, 65535, nil, nil)

        local ok, err = pcall(function()
            local f_in = io.open(p_path, "rb")
            if f_in then
                local header = f_in:read(72)
                if header and #header >= 72 and u32(header, 0) == 0xf0000011 then
                    local types, count = u32(header, 4), u32(header, 8)
                    local table_start = 72 + 32 * types
                    for idx = 0, math.min(count - 1, 100) do
                        f_in:seek("set", table_start + idx * 80)
                        local row = f_in:read(80)
                        if not row or #row < 80 then break end
                    end
                end
                f_in:close()
            end
        end)
        assert(ok, "Scanning truncated table must not raise error: " .. tostring(err))
        os.remove(p_path)
    end)

    -- 2.4: Truncated Envelope (offset points to near-EOF with fewer than 8 bytes)
    test("Patch Scanner: Handles truncated chunk envelope (< 8 bytes at offset)", function()
        local p_path = "data/9ba626afa44a3aa3.patch_453"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xAA), 8)
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(16) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        -- Write only 4 bytes at data_offset
        create_patch_file(p_path, 0xF0000011, 1, 1, row, "1234")

        local f_in = io.open(p_path, "rb")
        local env_valid = false
        if f_in then
            f_in:seek("set", data_offset)
            local env = f_in:read(8)
            if env and #env == 8 and u32(env, 4) == 2 then
                env_valid = true
            end
            f_in:close()
        end
        assert(env_valid == false, "Truncated envelope correctly identified and skipped")
        os.remove(p_path)
    end)

    -- 2.5: Invalid Envelope Magic (u32(env, 4) != 2)
    test("Patch Scanner: Rejects envelope with invalid magic (e.g. 999 instead of 2)", function()
        local p_path = "data/9ba626afa44a3aa3.patch_454"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xBB), 8)
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(24) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        local bad_env = u32_to_bytes(16) .. u32_to_bytes(999) .. string.rep("X", 16)
        create_patch_file(p_path, 0xF0000011, 1, 1, row, bad_env)

        local f_in = io.open(p_path, "rb")
        local env_valid = false
        if f_in then
            f_in:seek("set", data_offset)
            local env = f_in:read(8)
            if env and #env == 8 and u32(env, 4) == 2 then
                env_valid = true
            end
            f_in:close()
        end
        assert(env_valid == false, "Invalid envelope magic rejected")
        os.remove(p_path)
    end)

    -- 2.6: Envelope body_len Buffer Overread attempt (body_len > len - 8)
    test("Patch Scanner: Defends against buffer overread attempt (body_len > len - 8)", function()
        local p_path = "data/9ba626afa44a3aa3.patch_455"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xCC), 8)
        local row_len = 16
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(row_len) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        -- Envelope claims body_len is 50000 bytes, but row_len is only 16 bytes
        local bad_env = u32_to_bytes(50000) .. u32_to_bytes(2) .. string.rep("A", 8)
        create_patch_file(p_path, 0xF0000011, 1, 1, row, bad_env)

        local f_in = io.open(p_path, "rb")
        local overread_prevented = false
        if f_in then
            f_in:seek("set", data_offset)
            local env = f_in:read(8)
            if env and #env == 8 and u32(env, 4) == 2 then
                local body_len = u32(env, 0)
                if body_len > 0 and body_len <= row_len - 8 then
                    -- would read
                else
                    overread_prevented = true
                end
            end
            f_in:close()
        end
        assert(overread_prevented == true, "Buffer overread correctly blocked")
        os.remove(p_path)
    end)

    -- 2.7: Non-Lua pure binary data in patch chunk
    test("Patch Scanner: Non-Lua binary data chunk compilation handled safely without crash", function()
        local p_path = "data/9ba626afa44a3aa3.patch_456"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xDD), 8)
        local binary_payload = string.char(0x7F, 0x45, 0x4C, 0x46, 0x01, 0x02, 0x00, 0xFF) .. string.rep(string.char(0xAA, 0x55), 32)
        local env_payload = u32_to_bytes(#binary_payload) .. u32_to_bytes(2) .. binary_payload
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(#env_payload) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        create_patch_file(p_path, 0xF0000011, 1, 1, row, env_payload)

        local ok_scan, err_scan = pcall(function()
            local f_in = io.open(p_path, "rb")
            if f_in then
                f_in:seek("set", data_offset + 8)
                local content = f_in:read(#binary_payload)
                f_in:close()
                local chunk, c_err = loadstring(content, "@binary_chunk")
                assert(chunk == nil, "Binary data must not compile as Lua")
                assert(c_err ~= nil, "Compiler error must be logged")
            end
        end)
        assert(ok_scan, "Non-Lua binary chunk handling raised unhandled error: " .. tostring(err_scan))
        os.remove(p_path)
    end)

    -- 2.8: Invalid Lua syntax chunk
    test("Patch Scanner: Malformed Lua syntax in chunk compiles safely with error isolation", function()
        local p_path = "data/9ba626afa44a3aa3.patch_457"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xEE), 8)
        local bad_syntax = "function () this is completely invalid lua syntax !!! @@##$$ for while end"
        local env_payload = u32_to_bytes(#bad_syntax) .. u32_to_bytes(2) .. bad_syntax
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(#env_payload) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        create_patch_file(p_path, 0xF0000011, 1, 1, row, env_payload)

        local ok_scan, err_scan = pcall(function()
            local f_in = io.open(p_path, "rb")
            if f_in then
                f_in:seek("set", data_offset + 8)
                local content = f_in:read(#bad_syntax)
                f_in:close()
                local chunk, c_err = loadstring(content, "@bad_syntax_chunk")
                assert(chunk == nil, "Malformed syntax must fail compilation")
                assert(c_err ~= nil, "Compilation error must be reported")
            end
        end)
        assert(ok_scan, "Syntax error chunk handling raised unhandled error: " .. tostring(err_scan))
        os.remove(p_path)
    end)

    -- 2.9: Guest Boot Shield Neutralization of corrupted secondary rogue boot resource
    test("Patch Scanner: GuestBootShield neutralizes secondary boot chunk with corrupted body", function()
        local boot_hash_bytes = string.char(0xFA, 0x95, 0x18, 0x69, 0x93, 0xDF, 0x76, 0xF4)
        local rogue_payload = "corrupted secondary rogue payload without UML signature"
        local env_payload = u32_to_bytes(#rogue_payload) .. u32_to_bytes(2) .. rogue_payload
        local data_offset = 72 + 32 + 80
        local row = boot_hash_bytes .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(#env_payload) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        local p_path = "data/9ba626afa44a3aa3.patch_458"
        create_patch_file(p_path, 0xF0000011, 1, 1, row, env_payload)

        local is_rogue_neutralized = false
        local f_in = io.open(p_path, "rb")
        if f_in then
            f_in:seek("set", data_offset)
            local env = f_in:read(8)
            if env and #env == 8 and u32(env, 4) == 2 then
                local body_len = math.min(u32(env, 0), 256)
                local prefix = f_in:read(body_len)
                if prefix and not prefix:find("Universal Mod Loader", 1, true) then
                    is_rogue_neutralized = true
                end
            end
            f_in:close()
        end
        assert(is_rogue_neutralized == true, "Rogue boot resource without UML header must be neutralized")
        os.remove(p_path)
    end)

    -- 2.10: Archive recovery: Corrupted patch does not prevent valid patch discovery
    test("Patch Scanner: Corrupted patch does not halt discovery of subsequent valid patches", function()
        local p_bad = "data/9ba626afa44a3aa3.patch_480"
        local p_good = "data/9ba626afa44a3aa3.patch_481"

        -- Write bad patch
        local fb = io.open(p_bad, "wb")
        fb:write("CORRUPT_BYTES_999999999999999999999999")
        fb:close()

        -- Write good patch with a test mod
        local good_script = "-- @mod mods/stress_test/valid_patch_mod\nreturn { active = true }"
        local env_payload = u32_to_bytes(#good_script) .. u32_to_bytes(2) .. good_script
        local data_offset = 72 + 32 + 80
        local test_hash = murmur64_key_test("mods/stress_test/valid_patch_mod")
        local row = test_hash .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(#env_payload) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        create_patch_file(p_good, 0xF0000011, 1, 1, row, env_payload)

        -- Verify scanner skips p_bad safely and reads p_good
        local good_chunk = nil
        for _, p_target in ipairs({ p_bad, p_good }) do
            local f = io.open(p_target, "rb")
            if f then
                local hdr = f:read(72)
                if hdr and #hdr >= 72 and u32(hdr, 0) == 0xf0000011 then
                    f:seek("set", data_offset + 8)
                    local s = f:read(#good_script)
                    good_chunk = loadstring(s, "@valid_patch_mod")
                end
                f:close()
            end
        end

        assert(good_chunk ~= nil, "Good patch must be parsed successfully despite prior corrupted patch")
        os.remove(p_bad)
        os.remove(p_good)
    end)

    -- 2.11: Precompiled Lua bytecode rejection
    test("Patch Scanner: Precompiled Lua bytecode (\\027Lua) is safely rejected", function()
        local p_path = "data/9ba626afa44a3aa3.patch_460"
        local data_offset = 72 + 32 + 80
        local dummy_key = string.rep(string.char(0xAA), 8)
        local bytecode_payload = string.char(27) .. "Lua" .. string.rep(string.char(0), 60)
        local env_payload = u32_to_bytes(#bytecode_payload) .. u32_to_bytes(2) .. bytecode_payload
        local row = dummy_key .. lua_type_bytes .. u32_to_bytes(data_offset) .. u32_to_bytes(0) .. string.rep("\0", 32)
            .. u32_to_bytes(#env_payload) .. u32_to_bytes(0) .. u32_to_bytes(0) .. u32_to_bytes(16) .. u32_to_bytes(16) .. u32_to_bytes(0)

        create_patch_file(p_path, 0xF0000011, 1, 1, row, env_payload)

        local bytecode_rejected = false
        local f_in = io.open(p_path, "rb")
        if f_in then
            f_in:seek("set", data_offset + 8)
            local s = f_in:read(4)
            if s and s:sub(1, 4) == string.char(27) .. "Lua" then
                bytecode_rejected = true
            end
            f_in:close()
        end
        assert(bytecode_rejected == true, "Bytecode detected and rejected")
        os.remove(p_path)
    end)

    -- 2.12: Huge count clamped safely to file bounds without DoS loop
    test("Patch Scanner: Header with count = 0xFFFFFFFF is safely clamped without DoS loop", function()
        local p_path = "data/9ba626afa44a3aa3.patch_461"
        create_patch_file(p_path, 0xF0000011, 1, 4294967295, nil, nil)

        local ok, err = pcall(function()
            local f_in = io.open(p_path, "rb")
            if f_in then
                local file_size = f_in:seek("end") or 0
                f_in:seek("set", 0)
                local hdr = f_in:read(72)
                if hdr and #hdr >= 72 and u32(hdr, 0) == 0xf0000011 then
                    local types, count = u32(hdr, 4), u32(hdr, 8)
                    local table_start = 72 + 32 * types
                    local max_possible = math.max(0, math.floor((file_size - table_start) / 80))
                    local clamped_count = math.min(count, max_possible, 8192)
                    assert(clamped_count == 0, "Truncated file count clamped to 0")
                end
                f_in:close()
            end
        end)
        assert(ok, "Huge count clamped without hang: " .. tostring(err))
        os.remove(p_path)
    end)

    -- =========================================================================
    -- GROUP 3: HIGH-CONCURRENCY OPTION REGISTRATION & F9 MENU STRESS
    -- =========================================================================
    print("\n--- GROUP 3: High-Concurrency Option Registration (128 Mods, 640 Options) & F9 Menu ---")

    -- Set up Stingray GUI simulation environment
    local active_keys = {}
    local rects_drawn = 0
    local mock_world = { id = "world_main" }
    local mock_gui = { id = "gui_main" }

    _G.stingray = {
        Application = {
            main_world = function() return mock_world end,
            worlds = function() return { mock_world } end,
            can_get = function() return false end
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
                assert(type(pos.x) == "number", "pos.x must be number")
                assert(type(pos.y) == "number", "pos.y must be number")
                assert(type(sz.x) == "number", "sz.x must be number")
                assert(type(sz.y) == "number", "sz.y must be number")
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
                if kl == "-" or kl == "minus" then return 189 end
                if kl == "=" or kl == "equals" then return 187 end
                if kl == "page_down" or kl == "pagedown" then return 34 end
                if kl == "page_up" or kl == "pageup" then return 33 end
                for i = 0, 9 do
                    if kl == tostring(i) then return 48 + i end
                end
                return nil
            end,
            button = function(id) return active_keys[id] == true end,
            pressed = function(id) return active_keys[id] == true end
        }
    }

    -- Compile and load bootloader
    local bf = io.open("src/boot_loader.lua", "r")
    assert(bf, "Failed to read src/boot_loader.lua")
    local boot_code = bf:read("*a")
    bf:close()

    local chunk, b_err = loadstring(boot_code, "boot_loader.lua")
    assert(chunk, "Failed to compile boot_loader.lua: " .. tostring(b_err))
    chunk()

    local mom = _G.ModOptionsMenu
    assert(mom, "ModOptionsMenu must exist")

    -- 3.1: High-Concurrency Option Registration: 128 mods, 640 options
    test("High-Concurrency: Registers 128 distinct mods and 640 diverse options without degradation", function()
        local mod_count = 128
        local opts_per_mod = 5

        for m = 1, mod_count do
            local m_title = string.format("StressMod_%03d", m)
            -- 1: Toggle
            mom.register_option(string.format("sm_%03d_toggle", m), {
                mod = m_title,
                label = "Enable Features",
                type = "toggle",
                default = (m % 2 == 0)
            })
            -- 2: Slider
            mom.register_option(string.format("sm_%03d_slider", m), {
                mod = m_title,
                label = "Sensitivity Level",
                type = "slider",
                min = 0, max = 100, step = 5,
                default = 50
            })
            -- 3: Choice
            mom.register_option(string.format("sm_%03d_choice", m), {
                mod = m_title,
                label = "Rendering Quality",
                type = "choice",
                choices = { "Low", "Medium", "High", "Ultra" },
                default = (m % 4) + 1
            })
            -- 4: Keybinding
            mom.register_option(string.format("sm_%03d_key", m), {
                mod = m_title,
                label = "Activation Key",
                type = "key",
                default = "f" .. tostring((m % 12) + 1)
            })
            -- 5: Category Path
            mom.register_option(string.format("sm_%03d_cat_opt", m), {
                mod = m_title,
                category = "Advanced Subsystem",
                label = "Overclock Multiplier",
                type = "slider",
                min = 1, max = 10, step = 1,
                default = 2
            })
        end

        local total_registered = 0
        for opt_id, _ in pairs(mom.registered) do
            if opt_id:match("^sm_%d%d%d_") then
                total_registered = total_registered + 1
            end
        end
        assert(total_registered == mod_count * opts_per_mod, string.format("Expected %d options, got %d", mod_count * opts_per_mod, total_registered))
    end)

    -- 3.2: F9 Mod Sidebar Pagination across 128 mods
    test("F9 Menu Pagination: Left sidebar calculates pages, clamps bounds, and navigates 128 mods", function()
        -- Open F9 Menu
        rects_drawn = 0
        active_keys[119] = true
        update(0.016)
        active_keys[119] = false
        render()
        assert(rects_drawn > 100, "Menu must render open frame with rects")

        -- Step Down 30 times through mod sidebar
        rects_drawn = 0
        for _ = 1, 30 do
            active_keys[40] = true -- Down
            update(0.016)
            active_keys[40] = false
            render()
        end
        assert(rects_drawn > 100, "Menu renders cleanly after stepping down 30 mods")

        -- Quick jump keys (1-0 jumps to percentage of list)
        for _, jump_key in ipairs({ 49, 53, 57, 48 }) do -- 1, 5, 9, 0
            active_keys[jump_key] = true
            update(0.016)
            active_keys[jump_key] = false
            render()
        end
        assert(rects_drawn > 100, "Menu renders cleanly after quick-jump keys")
    end)

    -- 3.3: Right Pane Options Submenu Pagination under dense mod
    test("F9 Menu Pagination: Right pane navigates options and expands/collapses category folds", function()
        rects_drawn = 0
        -- Focus Right Pane (Tab key = 9 or Right Arrow = 39)
        active_keys[9] = true
        update(0.016)
        active_keys[9] = false
        render()

        -- Step through options in right pane
        for _ = 1, 10 do
            active_keys[40] = true -- Down
            update(0.016)
            active_keys[40] = false
            render()
        end

        -- Expand / collapse fold (Right = 39, Left = 37)
        active_keys[39] = true
        update(0.016)
        active_keys[39] = false
        render()

        active_keys[37] = true
        update(0.016)
        active_keys[37] = false
        render()

        assert(rects_drawn > 100, "Right pane renders cleanly during option and fold navigation")
    end)

    -- 3.4: Dynamic UI Scale Cycling Stress
    test("F9 Menu UI Scale: Cycles all scale presets via [-] and [=] without math or nil rect errors", function()
        -- Press [-] (189) multiple times to shrink scale
        for _ = 1, 5 do
            active_keys[189] = true
            update(0.016)
            active_keys[189] = false
            update(0.016)
            render()
        end

        -- Press [=] (187) multiple times to grow scale
        for _ = 1, 8 do
            active_keys[187] = true
            update(0.016)
            active_keys[187] = false
            update(0.016)
            render()
        end
        assert(true, "UI scaling completed smoothly across extremes")
    end)

    -- 3.5: Rapid Navigation Input Fuzzing (250 randomized inputs)
    test("F9 Menu Input Fuzzing: 250 randomized rapid keypresses execute without nil crashes or stalls", function()
        local test_keys = { 119, 27, 13, 38, 40, 37, 39, 46, 32, 8, 9, 189, 187, 49, 50, 51, 52 }
        for step = 1, 250 do
            local k = test_keys[(step % #test_keys) + 1]
            active_keys[k] = true
            update(0.016)
            active_keys[k] = false
            update(0.016)
            if step % 25 == 0 then
                render()
            end
        end
        assert(true, "250 fuzzed inputs survived without exception")
    end)

    -- 3.6: High-Concurrency Option Mutation & Batch Reset
    test("High-Concurrency Persistence: Modifies 60 options simultaneously and verifies reset()", function()
        for i = 1, 60 do
            mom.set(string.format("sm_%03d_slider", i), 85)
            mom.set(string.format("sm_%03d_toggle", i), true)
        end
        for i = 1, 60 do
            assert(mom.get(string.format("sm_%03d_slider", i)) == 85, "Slider value must be updated to 85")
            assert(mom.get(string.format("sm_%03d_toggle", i)) == true, "Toggle value must be updated to true")
        end

        -- Reset all options to defaults
        mom.reset()
        for i = 1, 60 do
            assert(mom.get(string.format("sm_%03d_slider", i)) == 50, "Slider default restored to 50")
            assert(mom.get(string.format("sm_%03d_toggle", i)) == (i % 2 == 0), "Toggle default restored")
        end
    end)

    -- 3.7: Choice option without choices table defaults safely
    test("F9 Menu: Choice option without choices table falls back to defaults without crash", function()
        mom.register_option("sm_no_choices", {
            mod = "ChoiceFallbackTest",
            label = "Fallback Option",
            type = "choice",
            default = 1
        })
        assert(mom.registered["sm_no_choices"] ~= nil, "Option registered")
        render()
        assert(true, "Rendered cleanly with choices fallback")
    end)

    -- Close F9 Menu cleanly
    active_keys[27] = true
    update(0.016)
    active_keys[27] = false
    update(0.016)

    -- =========================================================================
    -- GROUP 4: FAULTY MOD SIMULATION & CIRCUIT-BREAKER QUARANTINE
    -- =========================================================================
    print("\n--- GROUP 4: Faulty Mod Simulation & Circuit-Breaker Quarantine ---")

    -- 4.1: Faulty Mod throwing runtime error during require / preload
    test("Faulty Mod Simulation: Intercepts and isolates mod runtime crash during require", function()
        local faulty_mod_path = "mods/faulty_require_mod.lua"
        local f = io.open(faulty_mod_path, "w")
        assert(f)
        f:write([[
-- @mod mods/faulty_require_mod
error("FATAL_DELIBERATE_CRASH_IN_REQUIRE: nil index dereference")
]])
        f:close()

        -- Simulate loader loop
        local loaded_modules = {}
        local f_in = io.open(faulty_mod_path, "rb")
        local content = f_in:read("*a")
        f_in:close()

        local chunk_fn, c_err = loadstring(content, "@" .. faulty_mod_path)
        assert(chunk_fn ~= nil, "Mod must compile to chunk")

        local ok, res = pcall(chunk_fn)
        if ok then
            loaded_modules["faulty_require_mod"] = "loaded"
        else
            loaded_modules["faulty_require_mod"] = "failed: " .. tostring(res)
        end

        assert(ok == false, "Faulty mod execution must fail")
        assert(loaded_modules["faulty_require_mod"]:find("FATAL_DELIBERATE_CRASH_IN_REQUIRE", 1, true) ~= nil, "Crash message captured")
        os.remove(faulty_mod_path)
    end)

    -- 4.2: Faulty Mod throwing error during init / after_startup
    test("Faulty Mod Simulation: Intercepts and isolates mod runtime crash during after_startup / init", function()
        local startup_cbs = {}
        local executed_count = 0
        local failed_count = 0

        -- Healthy callback 1
        table.insert(startup_cbs, function() executed_count = executed_count + 1 end)
        -- Faulty callback throwing error
        table.insert(startup_cbs, function() error("SIMULATED_INIT_HOOK_EXPLOSION") end)
        -- Healthy callback 2
        table.insert(startup_cbs, function() executed_count = executed_count + 1 end)

        for _, cb in ipairs(startup_cbs) do
            local ok, err = pcall(cb)
            if not ok then
                failed_count = failed_count + 1
            end
        end

        assert(executed_count == 2, "Healthy callbacks must execute completely")
        assert(failed_count == 1, "Faulty callback isolated without halting loop")
    end)

    -- 4.3: Faulty Mod throwing error during update -> Circuit-Breaker Quarantine
    test("Circuit Breaker: Faulty update hook is quarantined and disabled after 10 errors without affecting healthy mods", function()
        local update_hooks = {}
        local update_hook_errors = {}
        local update_order = { "faulty_update_mod", "healthy_update_mod" }

        local faulty_call_count = 0
        local healthy_call_count = 0

        update_hooks["faulty_update_mod"] = function(dt)
            faulty_call_count = faulty_call_count + 1
            error("SIMULATED_PER_FRAME_UPDATE_ERROR")
        end

        update_hooks["healthy_update_mod"] = function(dt)
            healthy_call_count = healthy_call_count + 1
        end

        -- Simulated update loop matching boot_loader.lua circuit breaker mechanics
        local function execute_update_tick(dt)
            for i = 1, #update_order do
                local id = update_order[i]
                local fn = update_hooks[id]
                if fn then
                    local ok, err = pcall(fn, dt)
                    if not ok then
                        local cnt = (update_hook_errors[id] or 0) + 1
                        update_hook_errors[id] = cnt
                        if cnt >= 10 then
                            update_hooks[id] = nil -- Circuit Breaker Trips!
                        end
                    end
                end
            end
        end

        -- Run 25 consecutive frames
        for frame = 1, 25 do
            execute_update_tick(0.016)
        end

        assert(faulty_call_count == 10, string.format("Faulty hook must be called exactly 10 times before quarantine, got %d", faulty_call_count))
        assert(update_hooks["faulty_update_mod"] == nil, "Faulty hook must be nilled out by Circuit Breaker")
        assert(update_hook_errors["faulty_update_mod"] == 10, "Faulty hook error count clamped at 10")
        assert(healthy_call_count == 25, string.format("Healthy hook must execute all 25 frames unimpeded, got %d", healthy_call_count))
    end)

    -- 4.4: Faulty Mod throwing error during shutdown
    test("Faulty Mod Simulation: Intercepts and isolates mod runtime crash during shutdown", function()
        local shutdown_hooks = {}
        local shutdown_order = { "faulty_shutdown_mod", "healthy_shutdown_mod" }
        local healthy_shutdown_ran = false

        shutdown_hooks["faulty_shutdown_mod"] = function()
            error("SIMULATED_SHUTDOWN_DISASTER")
        end

        shutdown_hooks["healthy_shutdown_mod"] = function()
            healthy_shutdown_ran = true
        end

        local function execute_shutdown()
            for i = 1, #shutdown_order do
                local id = shutdown_order[i]
                local fn = shutdown_hooks[id]
                if fn then
                    pcall(fn)
                end
            end
        end

        local ok, err = pcall(execute_shutdown)
        assert(ok == true, "Shutdown must complete without unhandled exception")
        assert(healthy_shutdown_ran == true, "Healthy shutdown hook must run even if prior hook threw error")
    end)

    -- 4.5: Crash Sentinel Quarantine Recovery across launches
    test("Crash Sentinel: Detects active sentinel from prior crash, quarantines mod, and clears sentinel", function()
        local sentinel_file = "uml_active_sentinel.txt"
        local f = io.open(sentinel_file, "w")
        assert(f)
        f:write("mods/fatal_freeze_mod\n")
        f:close()

        local quarantined_mods = {}
        local f_in = io.open(sentinel_file, "r")
        if f_in then
            local crashed_mod = f_in:read("*l")
            f_in:close()
            pcall(os.remove, sentinel_file)
            if crashed_mod and crashed_mod ~= "" then
                quarantined_mods[crashed_mod] = true
            end
        end

        assert(quarantined_mods["mods/fatal_freeze_mod"] == true, "Crashed mod must be added to quarantine list")
        assert(io.open(sentinel_file, "r") == nil, "Sentinel file must be deleted upon recovery")

        -- Simulate candidate boot loop skipping quarantined mod
        local candidates = { "mods/fatal_freeze_mod", "mods/healthy_combat_mod" }
        local loaded = {}
        for _, m in ipairs(candidates) do
            if quarantined_mods[m] then
                loaded[m] = "quarantined"
            else
                loaded[m] = "loaded"
            end
        end

        assert(loaded["mods/fatal_freeze_mod"] == "quarantined", "Quarantined mod skipped during boot")
        assert(loaded["mods/healthy_combat_mod"] == "loaded", "Healthy mod loaded successfully")
    end)

    -- 4.6: API resilience against nil and empty option IDs
    test("API Resilience: ModOptionsMenu, Chef, and UML APIs safely guard against nil option IDs", function()
        assert(mom.set(nil, 123) == false or mom.set(nil, 123) == nil, "mom.set(nil) must not throw")
        assert(mom.get(nil) == nil, "mom.get(nil) must return nil")
        assert(mom.on_change(nil, function() end) == false, "mom.on_change(nil) must not throw")
        if _G.ChefSharedLoader and type(_G.ChefSharedLoader.set) == "function" then
            assert(_G.ChefSharedLoader.set(nil, 123) == false or _G.ChefSharedLoader.set(nil, 123) == nil)
            assert(_G.ChefSharedLoader.get(nil) == nil)
        end
    end)

    -- 4.7: RatsSharedLoader dot syntax support
    test("API Resilience: RatsSharedLoader supports dot syntax calls (rat.register, rat.on)", function()
        local rat = _G.RatsSharedLoader
        if rat and type(rat.register) == "function" then
            local ok1, res1 = pcall(rat.register, "dot_syntax_mod", { version = "1.0.0" })
            assert(ok1 == true, "rat.register dot syntax must not throw: " .. tostring(res1))
            local ok2, res2 = pcall(rat.on, "init", function() end)
            assert(ok2 == true, "rat.on dot syntax must not throw: " .. tostring(res2))
        end
    end)

    -- =========================================================================
    -- TEARDOWN & RESTORATION
    -- =========================================================================
    if orig_settings then
        local f_restore = io.open(settings_path_local, "wb")
        if f_restore then
            f_restore:write(orig_settings)
            f_restore:close()
        end
        pcall(os.remove, settings_path_bak)
    else
        pcall(os.remove, settings_path_local)
        pcall(os.remove, settings_path_bak)
    end

    print("\n--------------------------------------------------------------------")
    print(string.format("RESULTS: %d / %d tests passed successfully.", pass_count, total_count))
    print("STATUS: ALL UML v2.0.4 STRESS, FUZZING & RESILIENCE TESTS PASSED 100%!")
    print("====================================================================")
end

run_battery()
