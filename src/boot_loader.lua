-- Universal Mod Loader v22.0.0 for Helldivers 2 (Steam Builds 25988413 / 26088801+ / Lua 5.1)
-- Replaces engine boot resource 0xF476DF93691895FA in bundle 9ba626afa44a3aa3
-- Unifies 4 Major Modding Standards + Built-in Mod Options & Mod Bindings Menus:
--   1. Bingus Shared Loader (CowboyBingus / v17 / v20 / v21 / API 1)
--   2. Chef Shared Loader (Th3chef / API Levels 1, 2, 3)
--   3. Boot Mod Loader (VeganSquid / API 1)
--   4. HD2 Lua Runtime (hd2rt / 0.1.0)
--   5. Built-in Mod Options Menu (MOM v2)
--   6. Built-in Mod Bindings Menu (MBM v4) with pure Stingray Keyboard/Mouse polling
-- Pure Lua 5.1 compliant (Zero native FFI crashes, EAC-safe, Circuit-Breaker protected).
-- License: Zero-Clause BSD (0BSD)

-- 0. Cooperative handoff to Chef Shared Loader if installed with higher patch priority
local A = rawget(_G, 'stingray') and stingray.Application
if A and type(A.can_get) == 'function' and A.can_get('lua', 'mods/chef_shared_loader/core_1')
    and rawget(_G, 'ChefSharedLoader') == nil then
  rawset(_G, 'ChefSharedLoaderHandoff', { from = 'Universal Mod Loader v22.0.0' })
  local ok, err = pcall(require, 'mods/chef_shared_loader/core_1')
  if ok then return end
end

-- Forward declaration of persistent settings saver
local save_persistent_settings

-- ==============================================================================
-- 1. ENGINE ENTRYPOINT ASSIGNMENT & SAFE CHAINING
-- ==============================================================================
local function noop() end
local prev_init = type(rawget(_G, "init")) == "function" and rawget(_G, "init") or noop
local prev_shutdown = type(rawget(_G, "shutdown")) == "function" and rawget(_G, "shutdown") or noop
local prev_update = type(rawget(_G, "update")) == "function" and rawget(_G, "update") or noop
local prev_render = type(rawget(_G, "render")) == "function" and rawget(_G, "render") or noop

local update_hooks = {}
local update_order = {}
local update_hook_errors = {}
local shutdown_hooks = {}
local shutdown_order = {}

-- Forward declaration of UniversalLoader lifecycle callbacks
local UniversalLoader_update
local UniversalLoader_render
local UniversalLoader_shutdown

local function handle_init(...)
    return prev_init(...)
end
_G.init = handle_init
init = handle_init

local function handle_update(dt, ...)
    if UniversalLoader_update then
        pcall(UniversalLoader_update, dt)
    end
    for i = 1, #update_order do
        local id = update_order[i]
        local fn = update_hooks[id]
        if fn then
            local ok, err = pcall(fn, dt, ...)
            if not ok then
                local cnt = (update_hook_errors[id] or 0) + 1
                update_hook_errors[id] = cnt
                if cnt <= 3 then
                    pcall(print, "[UniversalLoader] update hook " .. tostring(id) .. " error: " .. tostring(err))
                end
                if cnt >= 20 then
                    update_hooks[id] = nil
                    pcall(print, "[UniversalLoader] [CIRCUIT BREAKER] update hook " .. tostring(id) .. " disabled after 20 errors.")
                end
            end
        end
    end
    return prev_update(dt, ...)
end
_G.update = handle_update
update = handle_update

local function handle_render(...)
    if UniversalLoader_render then
        pcall(UniversalLoader_render, ...)
    end
    return prev_render(...)
end
_G.render = handle_render
render = handle_render

local function handle_shutdown(...)
    if UniversalLoader_shutdown then
        pcall(UniversalLoader_shutdown)
    end
    for i = 1, #shutdown_order do
        local id = shutdown_order[i]
        local fn = shutdown_hooks[id]
        if fn then
            pcall(fn)
        end
    end
    return prev_shutdown(...)
end
_G.shutdown = handle_shutdown
shutdown = handle_shutdown

-- ==============================================================================
-- 2. PURE LUA 5.1 BITWISE LIBRARY & 64-BIT MURMURHASH64A
-- ==============================================================================
local bit = {}
local BIT_MOD = 4294967296
local BIT_MOD_HALF = 2147483648
local floor, char, concat, format, sort, min = math.floor, string.char, table.concat, string.format, table.sort, math.min
local byte, sub = string.byte, string.sub

local function to_u32(x)
    x = tonumber(x) or 0
    if x ~= x or x == math.huge or x == -math.huge then return 0 end
    if x >= 0 then
        return floor(x) % BIT_MOD
    else
        return math.ceil(x) % BIT_MOD
    end
end

local function tobit(x)
    local u = to_u32(x)
    if u >= BIT_MOD_HALF then return u - BIT_MOD end
    return u
end
bit.tobit = tobit

function bit.tohex(x, n)
    n = n or 8
    if n == 0 then return "" end
    local u = to_u32(x)
    local abs_n = math.abs(n)
    if n > 0 then
        return format("%0" .. abs_n .. "x", u):sub(-abs_n)
    else
        return format("%0" .. abs_n .. "X", u):sub(-abs_n)
    end
end

function bit.bnot(x)
    return tobit(BIT_MOD - 1 - to_u32(x))
end

-- 4-bit LUT tables for bitwise band, bor, bxor
local AND_LUT, OR_LUT, XOR_LUT = {}, {}, {}
for a = 0, 15 do
    for b = 0, 15 do
        local ra, ro, rx, p, x, y = 0, 0, 0, 1, a, b
        for _ = 1, 4 do
            local xb, yb = x % 2, y % 2
            if xb == 1 and yb == 1 then ra = ra + p end
            if xb == 1 or yb == 1 then ro = ro + p end
            if xb ~= yb then rx = rx + p end
            x, y, p = floor(x / 2), floor(y / 2), p * 2
        end
        local k = a * 16 + b
        AND_LUT[k], OR_LUT[k], XOR_LUT[k] = ra, ro, rx
    end
end

local function bit_op_2(lut, x, y)
    local u1, u2 = to_u32(x), to_u32(y)
    local r, p = 0, 1
    for _ = 1, 8 do
        local n1, n2 = u1 % 16, u2 % 16
        r = r + lut[n1 * 16 + n2] * p
        u1, u2, p = floor(u1 / 16), floor(u2 / 16), p * 16
    end
    return r
end

function bit.band(x, y, ...)
    local r = bit_op_2(AND_LUT, x, y)
    for i = 1, select('#', ...) do
        r = bit_op_2(AND_LUT, r, select(i, ...))
    end
    return tobit(r)
end

function bit.bor(x, y, ...)
    local r = bit_op_2(OR_LUT, x, y)
    for i = 1, select('#', ...) do
        r = bit_op_2(OR_LUT, r, select(i, ...))
    end
    return tobit(r)
end

function bit.bxor(x, y, ...)
    local r = bit_op_2(XOR_LUT, x, y)
    for i = 1, select('#', ...) do
        r = bit_op_2(XOR_LUT, r, select(i, ...))
    end
    return tobit(r)
end

function bit.lshift(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    return tobit((u * (2 ^ n)) % BIT_MOD)
end

function bit.rshift(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    return tobit(floor(u / (2 ^ n)))
end

function bit.arshift(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    if u >= BIT_MOD_HALF then
        local shifted = floor(u / (2 ^ n))
        local pad = BIT_MOD - (2 ^ (32 - n))
        return tobit(shifted + pad)
    else
        return tobit(floor(u / (2 ^ n)))
    end
end

function bit.rol(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    local high = (u * (2 ^ n)) % BIT_MOD
    local low = floor(u / (2 ^ (32 - n)))
    return tobit(high + low)
end

function bit.ror(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    return bit.rol(x, 32 - n)
end

function bit.bswap(x)
    local u = to_u32(x)
    local b0 = u % 256
    local b1 = floor(u / 256) % 256
    local b2 = floor(u / 65536) % 256
    local b3 = floor(u / 16777216) % 256
    return tobit(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3)
end

_G.bit = bit
package.preload["bit"] = function() return bit end

-- Pure Lua 64-bit MurmurHash64A Implementation
local function murmurhash64a(str, seed)
    seed = seed or 0
    local m = { 0x5bd1e995, 0xc6a4a793 }
    local r = 47
    local len = #str
    local h_low = bit.bxor(seed % BIT_MOD, to_u32(len * m[2]))
    local h_high = bit.bxor(floor(seed / BIT_MOD), to_u32(len * m[1]))

    local function mul64(a_low, a_high, b_low, b_high)
        local a0, a1 = a_low % 65536, floor(a_low / 65536)
        local a2, a3 = a_high % 65536, floor(a_high / 65536)
        local b0, b1 = b_low % 65536, floor(b_low / 65536)
        local b2, b3 = b_high % 65536, floor(b_high / 65536)
        local l0 = a0 * b0
        local l1 = a1 * b0 + a0 * b1 + floor(l0 / 65536)
        local l2 = a2 * b0 + a1 * b1 + a0 * b2 + floor(l1 / 65536)
        local l3 = a3 * b0 + a2 * b1 + a1 * b2 + a0 * b3 + floor(l2 / 65536)
        local low = (l0 % 65536) + (l1 % 65536) * 65536
        local high = (l2 % 65536) + (l3 % 65536) * 65536
        return to_u32(low), to_u32(high)
    end

    local function xor64(a_l, a_h, b_l, b_h)
        return bit_op_2(XOR_LUT, a_l, b_l), bit_op_2(XOR_LUT, a_h, b_h)
    end

    local function rshift64(a_l, a_h, s)
        if s == 0 then return a_l, a_h end
        if s < 32 then
            local nl = floor(a_l / (2 ^ s)) + (a_h % (2 ^ s)) * (2 ^ (32 - s))
            local nh = floor(a_h / (2 ^ s))
            return to_u32(nl), to_u32(nh)
        else
            return to_u32(floor(a_h / (2 ^ (s - 32)))), 0
        end
    end

    local pos = 1
    while pos + 7 <= len do
        local b1, b2, b3, b4 = byte(str, pos, pos + 3)
        local b5, b6, b7, b8 = byte(str, pos + 4, pos + 7)
        local k_l = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        local k_h = b5 + b6 * 256 + b7 * 65536 + b8 * 16777216

        k_l, k_h = mul64(k_l, k_h, m[2], m[1])
        local s_l, s_h = rshift64(k_l, k_h, r)
        k_l, k_h = xor64(k_l, k_h, s_l, s_h)
        k_l, k_h = mul64(k_l, k_h, m[2], m[1])

        local h_l, h_h = xor64(h_low, h_high, k_l, k_h)
        h_low, h_high = mul64(h_l, h_h, m[2], m[1])
        pos = pos + 8
    end

    local rem = len - pos + 1
    if rem > 0 then
        local t_l, t_h = 0, 0
        if rem >= 7 then t_h = t_h + byte(str, pos + 6) * 65536 end
        if rem >= 6 then t_h = t_h + byte(str, pos + 5) * 256 end
        if rem >= 5 then t_h = t_h + byte(str, pos + 4) end
        if rem >= 4 then t_l = t_l + byte(str, pos + 3) * 16777216 end
        if rem >= 3 then t_l = t_l + byte(str, pos + 2) * 65536 end
        if rem >= 2 then t_l = t_l + byte(str, pos + 1) * 256 end
        if rem >= 1 then t_l = t_l + byte(str, pos) end

        t_l, t_h = mul64(t_l, t_h, m[2], m[1])
        local s_l, s_h = rshift64(t_l, t_h, r)
        t_l, t_h = xor64(t_l, t_h, s_l, s_h)
        t_l, t_h = mul64(t_l, t_h, m[2], m[1])
        h_low, h_high = xor64(h_low, h_high, t_l, t_h)
    end

    local s_l, s_h = rshift64(h_low, h_high, r)
    h_low, h_high = xor64(h_low, h_high, s_l, s_h)
    h_low, h_high = mul64(h_low, h_high, m[2], m[1])
    s_l, s_h = rshift64(h_low, h_high, r)
    h_low, h_high = xor64(h_low, h_high, s_l, s_h)

    return h_low, h_high
end

-- ==============================================================================
-- 3. NON-CRASHING FFI / WIN32 COMPATIBILITY STUBS & MOCK POINTERS
-- ==============================================================================
local ffi = {
    os = "Windows",
    arch = "x64"
}
local ptr_mt
ptr_mt = {
    __index = function(t, k)
        if type(k) == "number" then return rawget(t, k) or 0 end
        return rawget(t, k)
    end,
    __newindex = function(t, k, v)
        rawset(t, k, v)
    end,
    __tostring = function(t)
        return format("cdata<uint64_t>: 0x%016x", rawget(t, "_addr") or 0)
    end,
    __tonumber = function(t)
        return rawget(t, "_addr") or 0
    end,
    __add = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        local res = setmetatable({ _addr = (addr_a + addr_b) % BIT_MOD }, ptr_mt)
        return res
    end,
    __sub = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        local diff = addr_a - addr_b
        if type(a) == "table" and type(b) == "table" then return diff end
        return setmetatable({ _addr = (diff + BIT_MOD) % BIT_MOD }, ptr_mt)
    end,
    __eq = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        return addr_a == addr_b
    end,
    __lt = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        return addr_a < addr_b
    end,
    __le = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        return addr_a <= addr_b
    end
}

local function make_mock_pointer(addr)
    return setmetatable({ _addr = tonumber(addr) or 0 }, ptr_mt)
end

function ffi.abi(param)
    return true
end
function ffi.cdef(def) end
function ffi.new(ct, init)
    local p = make_mock_pointer(type(init) == "number" and init or 0)
    if type(init) == "table" then
        for k, v in pairs(init) do p[k] = v end
    end
    return p
end
function ffi.cast(ct, val)
    return make_mock_pointer(type(val) == "table" and rawget(val, "_addr") or tonumber(val) or 0)
end
function ffi.typeof(ct) return ct end
function ffi.sizeof(ct) return 8 end
function ffi.alignof(ct) return 8 end
function ffi.offsetof(ct, field) return 0 end
function ffi.istype(ct, obj) return true end
function ffi.string(ptr, len)
    if type(len) == "number" and len > 0 then
        return string.rep("\0", len)
    end
    return ""
end
function ffi.copy(dst, src, len) end
function ffi.fill(dst, len, val) end

-- Win32 / Kernel32 Emulation
local function win32_fallback(t, k)
    local k_str = tostring(k)
    local k_clean = k_str:lower()

    if k_clean:find("getcurrentprocess") and not k_clean:find("id") then
        local fn = function() return make_mock_pointer(0xFFFFFFFF) end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getcurrentprocessid") then
        local fn = function() return 1000 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getcurrentthreadid") then
        local fn = function() return 1001 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getmodulehandle") then
        local fn = function(name) return make_mock_pointer(0x140000000) end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getmodulefilename") then
        local fn = function(mod, buf, cap) return 0 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("queryperformancefrequency") then
        local fn = function(lpFreq) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("queryperformancecounter") then
        local fn = function(lpCount) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("gettickcount") then
        local fn = function() return floor(os.clock() * 1000) end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("createfile") then
        local fn = function(...) return make_mock_pointer(0x10) end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("closehandle") then
        local fn = function(h) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("readfile") then
        local fn = function(...) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("writefile") then
        local fn = function(...) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("setfilepointer") then
        local fn = function(...) return 0 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("setendoffile") then
        local fn = function(...) return 1 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("virtualquery") then
        local fn = function(...) return 0 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("readprocessmemory") then
        local fn = function(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead)
            if type(lpNumberOfBytesRead) == "table" then
                pcall(function() lpNumberOfBytesRead[0] = nSize end)
            end
            return 1
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("writeprocessmemory") then
        local fn = function(...) return 0 end
        rawset(t, k, fn)
        return fn
    end

    local fallback = function(...) return 0 end
    rawset(t, k, fallback)
    return fallback
end

local win32_lib_mt = {
    __index = win32_fallback
}

local kernel32 = setmetatable({
    GetTickCount64 = function() return floor(os.clock() * 1000) end,
    GetTickCount = function() return floor(os.clock() * 1000) % BIT_MOD end,
    QueryPerformanceCounter = function(lpPerformanceCount) return 1 end,
    QueryPerformanceFrequency = function(lpFrequency) return 1 end,
    GetCurrentProcess = function() return make_mock_pointer(0xFFFFFFFF) end,
    GetCurrentProcessId = function() return 1000 end,
    GetCurrentThreadId = function() return 1001 end,
    VirtualQuery = function() return 0 end,
    ReadProcessMemory = function(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead)
        if type(lpNumberOfBytesRead) == "table" then
            pcall(function() lpNumberOfBytesRead[0] = nSize end)
        end
        return 1
    end,
    MBM_ReadProcessMemory = function() return 0 end,
    MBM_VirtualQuery = function() return 0 end,
    MBM_read_at = function() return 0 end
}, win32_lib_mt)

ffi.C = setmetatable({}, win32_lib_mt)

local loaded_libs = {
    kernel32 = kernel32
}

function ffi.load(name)
    local n = tostring(name):lower():match("([%w_-]+)%.?d?l?l?$") or tostring(name):lower()
    if not loaded_libs[n] then
        loaded_libs[n] = setmetatable({}, win32_lib_mt)
    end
    return loaded_libs[n]
end

_G.ffi = ffi
package.preload["ffi"] = function() return ffi end

-- Safeguard global string metatable while supporting legacy callable log_directory()
local string_mt = debug.getmetatable("") or {}
string_mt.__index = string
string_mt.__call = function(s) return s end
debug.setmetatable("", string_mt)

-- Defensive Application resolver
local function get_app()
    local sr = rawget(_G, "stingray")
    return sr and rawget(sr, "Application")
end

-- ==============================================================================
-- 4. PURE-LUA JSON SERIALIZER & DESERIALIZER (SETTINGS PERSISTENCE)
-- ==============================================================================
local function json_serialize(val)
    local t = type(val)
    if t == "nil" then return "null"
    elseif t == "boolean" then return val and "true" or "false"
    elseif t == "number" then
        if val ~= val or val == math.huge or val == -math.huge then return "0" end
        return tostring(val)
    elseif t == "string" then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        local is_array, max_idx, count = true, 0, 0
        for k in pairs(val) do
            count = count + 1
            if type(k) == "number" and k > 0 and floor(k) == k then
                if k > max_idx then max_idx = k end
            else
                is_array = false
            end
        end
        if is_array and max_idx == count then
            local parts = {}
            for i = 1, max_idx do parts[#parts + 1] = json_serialize(val[i]) end
            return "[" .. concat(parts, ",") .. "]"
        else
            local parts, keys = {}, {}
            for k in pairs(val) do keys[#keys + 1] = tostring(k) end
            sort(keys)
            for _, k in ipairs(keys) do
                local k_esc = tostring(k):gsub('\\', '\\\\'):gsub('"', '\\"')
                parts[#parts + 1] = '"' .. k_esc .. '":' .. json_serialize(val[k])
            end
            return "{" .. concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function json_deserialize(str)
    if type(str) ~= "string" or str == "" then return nil end
    local pos, len = 1, #str
    local function skip_ws()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\r' or c == '\n' then pos = pos + 1 else break end
        end
    end
    local parse_val
    local function parse_str()
        pos = pos + 1
        local res = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1; return concat(res)
            elseif c == '\\' then
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == '"' then res[#res + 1] = '"'
                elseif esc == '\\' then res[#res + 1] = '\\'
                elseif esc == 'n' then res[#res + 1] = '\n'
                elseif esc == 'r' then res[#res + 1] = '\r'
                elseif esc == 't' then res[#res + 1] = '\t'
                else res[#res + 1] = esc end
                pos = pos + 1
            else res[#res + 1] = c; pos = pos + 1 end
        end
        return concat(res)
    end
    local function parse_num()
        local s = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= len do
            local c = str:sub(pos, pos)
            if (c >= '0' and c <= '9') or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-' then
                pos = pos + 1
            else break end
        end
        return tonumber(str:sub(s, pos - 1)) or 0
    end
    local function parse_arr()
        pos = pos + 1; local arr = {}; skip_ws()
        if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
        while pos <= len do
            arr[#arr + 1] = parse_val(); skip_ws()
            local c = str:sub(pos, pos)
            if c == ',' then pos = pos + 1; skip_ws()
            elseif c == ']' then pos = pos + 1; return arr
            else break end
        end
        return arr
    end
    local function parse_obj()
        pos = pos + 1; local obj = {}; skip_ws()
        if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
        while pos <= len do
            skip_ws()
            if str:sub(pos, pos) ~= '"' then break end
            local key = parse_str(); skip_ws()
            if str:sub(pos, pos) ~= ':' then break end
            pos = pos + 1
            obj[key] = parse_val(); skip_ws()
            local c = str:sub(pos, pos)
            if c == ',' then pos = pos + 1; skip_ws()
            elseif c == '}' then pos = pos + 1; return obj
            else break end
        end
        return obj
    end
    parse_val = function()
        skip_ws()
        if pos > len then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then return parse_str()
        elseif c == '{' then return parse_obj()
        elseif c == '[' then return parse_arr()
        elseif c == 't' and str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif c == 'f' and str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif c == 'n' and str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        elseif (c >= '0' and c <= '9') or c == '-' then return parse_num()
        else pos = pos + 1; return nil end
    end
    local ok, res = pcall(parse_val)
    if ok then return res else return nil end
end

-- ==============================================================================
-- 5. UNIVERSAL STATE & LOGGING INFRASTRUCTURE
-- ==============================================================================
local UniversalState = {
    version = "22.0.0",
    revision = "loader-v22.0.0",
    api_levels = { bingus = 1, chef = 3, bml = 1, hd2rt = "0.1.0" },
    active_mods = {},
    addons = {},
    options = {},
    after_startup_cbs = {},
    shared_values = {},
    event_listeners = {},
    start_time = os.clock(),
    log_file = nil,
    log_dir = nil,
    settings_dir = nil,
    declared_codes = {},
    menu_visible = false,
    menu_tab = 1,         -- 1 = Options, 2 = Keybindings
    menu_selected = 1,
    menu_rebind_id = nil   -- binding ID being rebound
}

local function get_log_dir()
    if not UniversalState.log_dir then
        local local_app = os.getenv and os.getenv("LOCALAPPDATA")
        if local_app and local_app ~= "" then
            UniversalState.log_dir = local_app .. [[\CowboyBingus\Helldivers2\Logs]]
        else
            UniversalState.log_dir = "."
        end
    end
    return UniversalState.log_dir
end

local function get_settings_dir()
    if not UniversalState.settings_dir then
        local local_app = os.getenv and os.getenv("LOCALAPPDATA")
        if local_app and local_app ~= "" then
            UniversalState.settings_dir = local_app .. [[\UniversalModLoader]]
        else
            UniversalState.settings_dir = "."
        end
    end
    return UniversalState.settings_dir
end

local function log_message(prefix, fmt_str, ...)
    local msg = select('#', ...) > 0 and format(fmt_str, ...) or tostring(fmt_str)
    local line = format("[%s] %s", prefix, msg)
    pcall(print, line)
    if not UniversalState.log_file then
        local dir = get_log_dir()
        local f = io.open(dir .. [[\BingusSharedLoader.log]], "a")
        if not f then f = io.open("BingusSharedLoader.log", "a") end
        if f then UniversalState.log_file = f end
    end
    if UniversalState.log_file then
        pcall(UniversalState.log_file.write, UniversalState.log_file, line .. "\n")
        pcall(UniversalState.log_file.flush, UniversalState.log_file)
    end
end

_G.UniversalState = UniversalState
_G.UniversalModLoader = {
    version = UniversalState.version,
    revision = UniversalState.revision,
    api_levels = UniversalState.api_levels,
    state = UniversalState,
    active_mods = UniversalState.active_mods,
    log = function(...) log_message("UniversalLoader", ...) end
}
package.preload["UniversalModLoader"] = function() return _G.UniversalModLoader end

-- ==============================================================================
-- 6. BINGUS SHARED LOADER API & BINGUS RUNTIME V1
-- ==============================================================================
local CowboyBingusModLoader
local capabilities_data = {
    api = 1,
    build_gate = false,
    addon_discovery = 1,
    shared_loader_api = 1,
    logs = true,
    discovery = true,
    after_startup = true,
    jit_budget = false,
    health = true,
    on_update = true,
    universal_compat = 1
}
local capabilities_locked = setmetatable({}, {
    __index = capabilities_data,
    __newindex = function() error("capabilities table is read-only", 2) end,
    __metatable = false
})

CowboyBingusModLoader = {
    api = 1,
    version = 17,
    revision = "loader-v22.0.0",
    capabilities = capabilities_locked,
    log_directory = get_log_dir(),
    after_startup = function(fn)
        if type(fn) == "function" then
            table.insert(UniversalState.after_startup_cbs, fn)
        end
    end,
    on_update = function(id, fn)
        if type(id) == "string" and id ~= "" then
            if fn == nil then
                update_hooks[id] = nil
            elseif type(fn) == "function" then
                if update_hooks[id] == nil then
                    update_order[#update_order + 1] = id
                end
                update_hooks[id] = fn
            end
        end
    end,
    on_shutdown = function(id, fn)
        if type(id) == "string" and id ~= "" then
            if fn == nil then
                shutdown_hooks[id] = nil
            elseif type(fn) == "function" then
                if shutdown_hooks[id] == nil then
                    shutdown_order[#shutdown_order + 1] = id
                end
                shutdown_hooks[id] = fn
            end
        end
    end,
    open_log = function(name)
        if type(name) ~= "string" or not name:match("^[%w_%-]+%.log$") then return nil end
        local dir = get_log_dir()
        local f = io.open(dir .. "/" .. name, "a")
        if not f then f = io.open(name, "a") end
        return f or {
            write = function(self, ...)
                local args = {...}
                local s = concat(args, "")
                log_message("ModLog:" .. name, "%s", tostring(s))
            end,
            flush = function() end,
            close = function() end
        }
    end
}
_G.CowboyBingusModLoader = CowboyBingusModLoader
_G.HD2ModLoader = CowboyBingusModLoader
package.preload["CowboyBingusModLoader"] = function() return CowboyBingusModLoader end

local BingusRuntime
BingusRuntime = {
    shared = {
        version = 1,
        statuses = {},
        on = function(event, fn)
            if event == "update" and type(fn) == "function" then
                local id = "bingus_rt_" .. tostring(#update_order + 1)
                update_order[#update_order + 1] = id
                update_hooks[id] = fn
            elseif event == "shutdown" and type(fn) == "function" then
                local id = "bingus_rt_shut_" .. tostring(#shutdown_order + 1)
                shutdown_order[#shutdown_order + 1] = id
                shutdown_hooks[id] = fn
            end
        end
    },
    guard = function(name, fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                log_message("BingusGuard", "Error in %s: %s", tostring(name), tostring(err))
            end
        end
    end
}
_G.BingusRuntime = BingusRuntime
package.preload["BingusRuntime"] = function() return BingusRuntime end

-- ==============================================================================
-- 7. BUILT-IN MOD OPTIONS MENU (MOM v2)
-- ==============================================================================
local ModOptionsMenu
ModOptionsMenu = {
    api = 1,
    version = 2,
    registered = {},
    values = {},
    change_callbacks = {},
    register_option = function(id, spec)
        if type(id) ~= "string" or type(spec) ~= "table" then return false end
        ModOptionsMenu.registered[id] = spec
        if ModOptionsMenu.values[id] == nil and spec.default ~= nil then
            ModOptionsMenu.values[id] = spec.default
        end
        return true
    end,
    get = function(id)
        if ModOptionsMenu.values[id] ~= nil then
            return ModOptionsMenu.values[id]
        end
        local spec = ModOptionsMenu.registered[id]
        if spec and spec.default ~= nil then
            return spec.default
        end
        return nil
    end,
    set = function(id, val)
        ModOptionsMenu.values[id] = val
        local cb = ModOptionsMenu.change_callbacks[id]
        if type(cb) == "function" then
            pcall(cb, val, id)
        end
        if save_persistent_settings then
            save_persistent_settings()
        end
        return true
    end,
    on_change = function(id, fn)
        if type(id) == "string" and type(fn) == "function" then
            ModOptionsMenu.change_callbacks[id] = fn
            return true
        end
        return false
    end,
    ready = function() return true end
}
_G.ModOptionsMenu = ModOptionsMenu
package.preload["ModOptionsMenu"] = function() return ModOptionsMenu end

-- ==============================================================================
-- 8. BUILT-IN MOD BINDINGS MENU (MBM v4) & KEY STATE TRACKING
-- ==============================================================================
local ModBindingsMenu
ModBindingsMenu = {
    api = 1,
    version = 4,
    revision = 1,
    capacity = 256,
    registry = {},
    order = {},
    bindings = {},
    states = {},
    ready = function() return true end
}

local KEY_ALIASES = {
    ["esc"] = "escape", ["del"] = "delete", ["return"] = "enter",
    ["lshift"] = "left shift", ["rshift"] = "right shift",
    ["lctrl"] = "left ctrl", ["rctrl"] = "right ctrl",
    ["lalt"] = "left alt", ["ralt"] = "right alt",
    ["spacebar"] = "space"
}

local function normalize_key_name(k)
    if type(k) ~= "string" then return nil end
    local lower = k:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return KEY_ALIASES[lower] or lower
end

function ModBindingsMenu.register_binding(id, label, slot, options)
    if type(id) ~= "string" or id == "" then return false, "invalid id" end
    local existing = ModBindingsMenu.registry[id]
    if existing then return true end

    local text = type(label) == "string" and label or (type(label) == "function" and label() or id)
    local category = options and options.category or "General"
    local default_key = "NONE"

    if options and options.default then
        if type(options.default) == "string" then
            default_key = normalize_key_name(options.default)
        elseif type(options.default) == "table" and options.default.key then
            default_key = normalize_key_name(tostring(options.default.key))
        end
    end

    local current_key = ModBindingsMenu.bindings[id] or default_key

    local record = {
        id = id,
        label = text,
        category = category,
        slot = slot,
        default = default_key,
        current = current_key
    }

    ModBindingsMenu.registry[id] = record
    table.insert(ModBindingsMenu.order, record)
    if not ModBindingsMenu.bindings[id] then
        ModBindingsMenu.bindings[id] = current_key
    end
    ModBindingsMenu.states[id] = { down = false, pressed = false, released = false }
    ModBindingsMenu.revision = ModBindingsMenu.revision + 1
    return true
end

function ModBindingsMenu.is_down(id)
    local st = ModBindingsMenu.states[id]
    return st and st.down or false
end

function ModBindingsMenu.is_pressed(id)
    local st = ModBindingsMenu.states[id]
    return st and st.pressed or false
end

function ModBindingsMenu.binding(id)
    return ModBindingsMenu.bindings[id] or "NONE"
end

function ModBindingsMenu.set_binding(id, spec)
    local key_name
    if type(spec) == "string" then
        key_name = normalize_key_name(spec)
    elseif type(spec) == "table" and spec.key then
        key_name = normalize_key_name(tostring(spec.key))
    elseif spec == nil or spec == false then
        key_name = "NONE"
    end
    if not key_name then return false end
    ModBindingsMenu.bindings[id] = key_name
    if ModBindingsMenu.registry[id] then
        ModBindingsMenu.registry[id].current = key_name
    end
    ModBindingsMenu.revision = ModBindingsMenu.revision + 1
    if save_persistent_settings then
        save_persistent_settings()
    end
    return true
end

function ModBindingsMenu.binding_info(id)
    return ModBindingsMenu.registry[id]
end

function ModBindingsMenu.poll(ids, out)
    out = out or { down = {}, pressed = {}, released = {} }
    out.down = out.down or {}
    out.pressed = out.pressed or {}
    out.released = out.released or {}
    for _, id in ipairs(ids) do
        local st = ModBindingsMenu.states[id]
        if st then
            out.down[id] = st.down
            out.pressed[id] = st.pressed
            out.released[id] = st.released
        else
            out.down[id] = false
            out.pressed[id] = false
            out.released[id] = false
        end
    end
    return true
end

_G.ModBindingsMenu = ModBindingsMenu
_G.CowboyBingusModBindings = ModBindingsMenu
package.preload["ModBindingsMenu"] = function() return ModBindingsMenu end
package.preload["CowboyBingusModBindings"] = function() return ModBindingsMenu end

-- Key Polling with Compound Modifier Support (e.g. "ctrl+h", "shift+f")
local function check_button_state(kb, mouse, name, check_type)
    if not name or name == "NONE" then return false end
    local has_ctrl = name:find("ctrl%+")
    local has_shift = name:find("shift%+")
    local has_alt = name:find("alt%+")
    local main_key = name:gsub("ctrl%+", ""):gsub("shift%+", ""):gsub("alt%+", ""):gsub("^%s+", ""):gsub("%s+$", "")

    if has_ctrl and kb and kb.button_index then
        local lctrl = kb.button_index("left ctrl")
        local rctrl = kb.button_index("right ctrl")
        local ctrl_down = (lctrl and kb.button and kb.button(lctrl) == 1) or (rctrl and kb.button and kb.button(rctrl) == 1)
        if not ctrl_down then return false end
    end
    if has_shift and kb and kb.button_index then
        local lshift = kb.button_index("left shift")
        local rshift = kb.button_index("right shift")
        local shift_down = (lshift and kb.button and kb.button(lshift) == 1) or (rshift and kb.button and kb.button(rshift) == 1)
        if not shift_down then return false end
    end
    if has_alt and kb and kb.button_index then
        local lalt = kb.button_index("left alt")
        local ralt = kb.button_index("right alt")
        local alt_down = (lalt and kb.button and kb.button(lalt) == 1) or (ralt and kb.button and kb.button(ralt) == 1)
        if not alt_down then return false end
    end

    local idx = kb and kb.button_index and kb.button_index(main_key)
    if idx then
        if check_type == "down" then return kb.button and kb.button(idx) == 1 end
        if check_type == "pressed" then return kb.pressed and kb.pressed(idx) == 1 end
        if check_type == "released" then return kb.released and kb.released(idx) == 1 end
    elseif mouse and mouse.button_index then
        local midx = mouse.button_index(main_key)
        if midx then
            if check_type == "down" then return mouse.button and mouse.button(midx) == 1 end
            if check_type == "pressed" then return mouse.pressed and mouse.pressed(midx) == 1 end
            if check_type == "released" then return mouse.released and mouse.released(midx) == 1 end
        end
    end
    return false
end

local function update_bindings_state()
    local sr = rawget(_G, "stingray")
    if not sr then return end
    local kb = sr.Keyboard
    local mouse = sr.Mouse

    for id, record in pairs(ModBindingsMenu.registry) do
        local key = ModBindingsMenu.bindings[id]
        local is_down = check_button_state(kb, mouse, key, "down")
        local is_pressed = check_button_state(kb, mouse, key, "pressed")
        local is_released = check_button_state(kb, mouse, key, "released")

        local st = ModBindingsMenu.states[id]
        if not st then
            st = {}
            ModBindingsMenu.states[id] = st
        end
        st.down = is_down
        st.pressed = is_pressed
        st.released = is_released
    end
end

-- ==============================================================================
-- 9. PERSISTENT SETTINGS STORAGE (SAVE / LOAD)
-- ==============================================================================
local function load_persistent_settings()
    local sdir = get_settings_dir()
    local path = sdir .. [[\settings.json]]
    local f = io.open(path, "r")
    if not f then
        local ldir = get_log_dir():gsub("[Ll]ogs[/\\]?$", "Settings")
        f = io.open(ldir .. [[\universal_settings.json]], "r")
    end
    if not f then return end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return end
    local data = json_deserialize(content)
    if not data or type(data) ~= "table" then return end

    if data.options and type(data.options) == "table" then
        for k, v in pairs(data.options) do
            ModOptionsMenu.values[k] = v
        end
    end
    if data.bindings and type(data.bindings) == "table" then
        for k, v in pairs(data.bindings) do
            ModBindingsMenu.bindings[k] = tostring(v)
            if ModBindingsMenu.registry[k] then
                ModBindingsMenu.registry[k].current = tostring(v)
            end
        end
    end
    log_message("Settings", "Loaded persistent mod options and keybindings from disk.")
end

save_persistent_settings = function()
    local sdir = get_settings_dir()
    local path = sdir .. [[\settings.json]]
    local payload = {
        options = ModOptionsMenu.values,
        bindings = ModBindingsMenu.bindings
    }
    local str = json_serialize(payload)
    local f = io.open(path, "w")
    if not f then
        pcall(os.execute, 'mkdir "' .. sdir .. '" 2>nul')
        f = io.open(path, "w")
    end
    if f then
        f:write(str)
        f:close()
    else
        local ldir = get_log_dir():gsub("[Ll]ogs[/\\]?$", "Settings")
        pcall(os.execute, 'mkdir "' .. ldir .. '" 2>nul')
        local f_alt = io.open(ldir .. [[\universal_settings.json]], "w")
        if f_alt then
            f_alt:write(str)
            f_alt:close()
        end
    end
end

-- ==============================================================================
-- 10. BOOT MOD LOADER API (VeganSquid) & HD2 RUNTIME (hd2rt)
-- ==============================================================================
local BootModLoader
BootModLoader = {
    api = 1,
    version = 1,
    hooks = {},
    hook = function(target, fn)
        if type(target) == "string" and type(fn) == "function" then
            table.insert(BootModLoader.hooks, { target = target, fn = fn })
            return true
        end
        return false
    end
}
_G.BootModLoader = BootModLoader
package.preload["BootModLoader"] = function() return BootModLoader end

local hd2rt = {
    _VERSION = "0.1.0",
    events = {},
    on = function(evt, cb)
        if type(evt) == "string" and type(cb) == "function" then
            UniversalState.event_listeners[evt] = UniversalState.event_listeners[evt] or {}
            table.insert(UniversalState.event_listeners[evt], cb)
        end
    end,
    emit = function(evt, ...)
        local list = UniversalState.event_listeners[evt]
        if list then
            for _, fn in ipairs(list) do
                pcall(fn, ...)
            end
        end
    end,
    register_mod = function(info)
        local id = (type(info) == "table" and info.id) or "anonymous_hd2rt"
        UniversalState.active_mods[id] = info or true
        log_message("HD2Runtime", "Mod registered: %s", tostring(id))
    end
}
_G.hd2rt = hd2rt
package.preload["hd2rt"] = function() return hd2rt end
package.preload["hd2runtime"] = function() return hd2rt end

-- ==============================================================================
-- 11. CHEF SHARED LOADER API EMULATION (API Levels 1, 2, 3)
-- ==============================================================================
local function create_chef_api_table(mod_id)
    local chef = {
        api_level = 3,
        loader_name = "UniversalModLoader",
        loader_version = UniversalState.version,
        mod_id = mod_id
    }

    chef.on = function(event_name, callback)
        if event_name == "update" and type(callback) == "function" then
            local id = "chef_" .. tostring(mod_id) .. "_" .. tostring(#update_order + 1)
            update_order[#update_order + 1] = id
            update_hooks[id] = callback
        elseif event_name == "shutdown" and type(callback) == "function" then
            local id = "chef_shut_" .. tostring(mod_id) .. "_" .. tostring(#shutdown_order + 1)
            shutdown_order[#shutdown_order + 1] = id
            shutdown_hooks[id] = callback
        else
            hd2rt.on(event_name, callback)
        end
    end

    chef.state = {
        get = function(key) return UniversalState.shared_values[key] end,
        set = function(key, val) UniversalState.shared_values[key] = val end
    }

    chef.options = {
        register = function(spec)
            if type(spec) == "table" and spec.id then
                ModOptionsMenu.register_option(spec.id, spec)
            end
        end,
        get = function(id) return ModOptionsMenu.get(id) end,
        set = function(id, val) return ModOptionsMenu.set(id, val) end
    }

    chef.bindings = {
        register = function(id, label, default_key)
            ModBindingsMenu.register_binding(id, label, nil, { default = default_key })
        end,
        is_down = function(id) return ModBindingsMenu.is_down(id) end,
        is_pressed = function(id) return ModBindingsMenu.is_pressed(id) end,
        get = function(id) return ModBindingsMenu.binding(id) end
    }

    chef.log = function(fmt, ...)
        log_message(mod_id, fmt, ...)
    end

    return chef
end
_G.ChefSharedLoader = create_chef_api_table("ChefSharedLoader")
package.preload["ChefSharedLoader"] = function() return _G.ChefSharedLoader end

-- ==============================================================================
-- 12. UNIVERSAL ADDON DISCOVERY & EXECUTION GATEWAY
-- ==============================================================================
local function strip_bom(str)
    if type(str) == "string" and str:sub(1, 3) == "\239\187\191" then
        return str:sub(4)
    end
    return str
end

local function execute_mod_script(mod_name, source_code, archive_name)
    if mod_name:find("cowboybingus/mod_options_menu") or mod_name:find("cowboybingus/mod_bindings_menu") then
        log_message("UniversalLoader", "Superseding legacy standalone %s (unified built-in engine active)", mod_name)
        UniversalState.active_mods[mod_name] = {
            name = mod_name,
            archive = archive_name,
            status = "superseded_by_builtin"
        }
        return true
    end

    local clean_source = strip_bom(source_code)
    local fn, err = loadstring(clean_source, mod_name)
    if not fn then
        log_message("UniversalLoader", "Failed to compile %s: %s", mod_name, tostring(err))
        return false, err
    end

    local mod_chef_api = create_chef_api_table(mod_name)
    local mod_env = setmetatable({
        chef = mod_chef_api,
        ChefSharedLoader = mod_chef_api,
        HD2ModLoader = CowboyBingusModLoader,
        CowboyBingusModLoader = CowboyBingusModLoader,
        ModOptionsMenu = ModOptionsMenu,
        ModBindingsMenu = ModBindingsMenu,
        BootModLoader = BootModLoader,
        hd2rt = hd2rt,
        bit = bit,
        ffi = ffi
    }, {
        __index = _G,
        __newindex = _G
    })

    setfenv(fn, mod_env)

    _G.chef = mod_chef_api
    _G.ChefSharedLoader = mod_chef_api

    local ok, res = pcall(fn, mod_chef_api)
    if not ok then
        log_message("UniversalLoader", "Error starting %s: %s", mod_name, tostring(res))
        return false, res
    end

    package.loaded[mod_name] = res or true
    capabilities_data.addon_discovery = 1
    UniversalState.active_mods[mod_name] = {
        name = mod_name,
        archive = archive_name,
        status = "loaded"
    }

    log_message("UniversalLoader", "Successfully loaded %s from %s", mod_name, archive_name or "patch")
    return true
end

-- ==============================================================================
-- 13. DYNAMIC ARCHIVE DISCOVERY & DEDUPLICATION (PATCH_0..255)
-- ==============================================================================
local LUA_RESOURCE_TYPE = "\226\23\209\44\250\141\78\161"
local ARCHIVE_MAGIC = 0xF0000011

local function read_u32(str, off)
    local b0, b1, b2, b3 = str:byte(off + 1, off + 4)
    if not b3 then return 0 end
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function discover_installed_mods()
    local data_dir = "data"
    local candidates = {}
    local candidate_order = {}

    for patch_num = 0, 255 do
        local patch_filename = format("%s/9ba626afa44a3aa3.patch_%d", data_dir, patch_num)
        local f = io.open(patch_filename, "rb")
        if f then
            local hdr = f:read(72)
            if hdr and #hdr == 72 and read_u32(hdr, 0) == ARCHIVE_MAGIC then
                -- Stingray binary patch bundle! Parse entry table
                local ntypes = read_u32(hdr, 4)
                local nentries = read_u32(hdr, 8)
                local entry_base = 72 + 32 * ntypes
                for i = 0, nentries - 1 do
                    f:seek("set", entry_base + i * 80)
                    local ent = f:read(80)
                    if ent and #ent == 80 and ent:sub(9, 16) == LUA_RESOURCE_TYPE then
                        local off = read_u32(ent, 16)
                        local sz = read_u32(ent, 56)
                        if off > 0 and sz >= 8 then
                            f:seek("set", off + 8)
                            local code = f:read(sz - 8)
                            if code and #code > 0 then
                                local target_name = code:match("%-%-%s*HD2%-Addon:%s*([^\r\n]+)")
                                    or code:match("%-%-%s*HD2%-Boot:%s*([^\r\n]+)")
                                    or code:match("%-%-%s*HD2%-Options:%s*([^\r\n]+)")

                                if target_name then
                                    target_name = target_name:gsub("^%s+", ""):gsub("%s+$", "")
                                    if candidates[target_name] then
                                        log_message("UniversalLoader", "Overriding %s (patch_%d replaced by higher patch_%d)",
                                            target_name, candidates[target_name].patch_num, patch_num)
                                        candidates[target_name] = {
                                            name = target_name,
                                            content = code,
                                            patch_num = patch_num,
                                            archive = format("9ba626afa44a3aa3.patch_%d", patch_num)
                                        }
                                    else
                                        candidates[target_name] = {
                                            name = target_name,
                                            content = code,
                                            patch_num = patch_num,
                                            archive = format("9ba626afa44a3aa3.patch_%d", patch_num)
                                        }
                                        candidate_order[#candidate_order + 1] = target_name
                                    end
                                end
                            end
                        end
                    end
                end
            else
                -- Raw plain-text Lua patch file (Chef-style raw patch)
                f:seek("set", 0)
                local code = f:read("*a")
                if code and #code > 0 then
                    local target_name = code:match("%-%-%s*HD2%-Addon:%s*([^\r\n]+)")
                        or code:match("%-%-%s*HD2%-Boot:%s*([^\r\n]+)")
                        or code:match("%-%-%s*HD2%-Options:%s*([^\r\n]+)")
                    if target_name then
                        target_name = target_name:gsub("^%s+", ""):gsub("%s+$", "")
                        if candidates[target_name] then
                            log_message("UniversalLoader", "Overriding %s (patch_%d replaced by higher patch_%d)",
                                target_name, candidates[target_name].patch_num, patch_num)
                            candidates[target_name] = {
                                name = target_name,
                                content = code,
                                patch_num = patch_num,
                                archive = format("9ba626afa44a3aa3.patch_%d", patch_num)
                            }
                        else
                            candidates[target_name] = {
                                name = target_name,
                                content = code,
                                patch_num = patch_num,
                                archive = format("9ba626afa44a3aa3.patch_%d", patch_num)
                            }
                            candidate_order[#candidate_order + 1] = target_name
                        end
                    end
                end
            end
            f:close()
        end
    end

    for _, target_name in ipairs(candidate_order) do
        local item = candidates[target_name]
        if item then
            execute_mod_script(item.name, item.content, item.archive)
        end
    end

    local mod_count = 0
    for _ in pairs(UniversalState.active_mods) do mod_count = mod_count + 1 end
    log_message("UniversalLoader", "Discovered & Registered %d unique mods from game archives.", mod_count)
end

-- ==============================================================================
-- 14. INTERACTIVE IN-GAME OVERLAY (F2 / F9 / MULTI-TAB)
-- ==============================================================================
local COMMON_SCAN_KEYS = {
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "space", "left shift", "right shift", "left ctrl", "right ctrl", "left alt", "right alt",
    "up", "down", "left", "right", "insert", "home", "end", "page up", "page down",
    "mouse_middle", "mouse_extra_1", "mouse_extra_2"
}

local function handle_menu_input()
    local sr = rawget(_G, "stingray")
    if not sr then return end

    local function key_pressed(name)
        local idx = sr.Keyboard and sr.Keyboard.button_index and sr.Keyboard.button_index(name)
        if idx and sr.Keyboard.pressed and sr.Keyboard.pressed(idx) == 1 then return true end
        local midx = sr.Mouse and sr.Mouse.button_index and sr.Mouse.button_index(name)
        if midx and sr.Mouse.pressed and sr.Mouse.pressed(midx) == 1 then return true end
        return false
    end

    if key_pressed("f2") or key_pressed("f9") then
        UniversalState.menu_visible = not UniversalState.menu_visible
        UniversalState.menu_rebind_id = nil
        return
    end

    if not UniversalState.menu_visible then return end

    -- Tab switching (1: Options, 2: Keybindings)
    if key_pressed("tab") and not UniversalState.menu_rebind_id then
        UniversalState.menu_tab = (UniversalState.menu_tab == 1) and 2 or 1
        UniversalState.menu_selected = 1
        return
    end

    -- Rebind Mode Active in Tab 2
    if UniversalState.menu_rebind_id then
        if key_pressed("escape") then
            UniversalState.menu_rebind_id = nil
            return
        elseif key_pressed("delete") or key_pressed("backspace") then
            ModBindingsMenu.set_binding(UniversalState.menu_rebind_id, "NONE")
            UniversalState.menu_rebind_id = nil
            return
        end

        for _, k in ipairs(COMMON_SCAN_KEYS) do
            if key_pressed(k) then
                ModBindingsMenu.set_binding(UniversalState.menu_rebind_id, k)
                UniversalState.menu_rebind_id = nil
                return
            end
        end
        return
    end

    -- TAB 1: MOD OPTIONS
    if UniversalState.menu_tab == 1 then
        local opt_keys = {}
        for id in pairs(ModOptionsMenu.registered) do opt_keys[#opt_keys + 1] = id end
        table.sort(opt_keys)
        if #opt_keys == 0 then return end

        if key_pressed("up") then
            UniversalState.menu_selected = math.max(1, (UniversalState.menu_selected or 1) - 1)
        elseif key_pressed("down") then
            UniversalState.menu_selected = math.min(#opt_keys, (UniversalState.menu_selected or 1) + 1)
        end

        local sel = UniversalState.menu_selected or 1
        if sel > #opt_keys then sel = #opt_keys; UniversalState.menu_selected = sel end
        local cur_id = opt_keys[sel]
        if cur_id then
            local spec = ModOptionsMenu.registered[cur_id]
            local cur_val = ModOptionsMenu.get(cur_id)
            local toggle = key_pressed("enter") or key_pressed("space")
            local step_left = key_pressed("left")
            local step_right = key_pressed("right")

            if spec.type == "boolean" or type(cur_val) == "boolean" then
                if toggle or step_left or step_right then
                    ModOptionsMenu.set(cur_id, not cur_val)
                end
            elseif spec.choices and type(spec.choices) == "table" and #spec.choices > 0 then
                local cur_idx = 1
                for i, choice in ipairs(spec.choices) do
                    if choice == cur_val then cur_idx = i; break end
                end
                if toggle or step_right then
                    cur_idx = (cur_idx % #spec.choices) + 1
                    ModOptionsMenu.set(cur_id, spec.choices[cur_idx])
                elseif step_left then
                    cur_idx = cur_idx - 1
                    if cur_idx < 1 then cur_idx = #spec.choices end
                    ModOptionsMenu.set(cur_id, spec.choices[cur_idx])
                end
            elseif type(cur_val) == "number" or spec.type == "number" then
                local step = spec.step or 1
                local min_val = spec.min or -1e9
                local max_val = spec.max or 1e9
                local num = tonumber(cur_val) or 0
                if step_left then
                    num = math.max(min_val, math.min(max_val, num - step))
                    ModOptionsMenu.set(cur_id, num)
                elseif step_right or toggle then
                    num = math.max(min_val, math.min(max_val, num + step))
                    ModOptionsMenu.set(cur_id, num)
                end
            end
        end

    -- TAB 2: KEY BINDINGS
    elseif UniversalState.menu_tab == 2 then
        local bind_list = ModBindingsMenu.order
        if #bind_list == 0 then return end

        if key_pressed("up") then
            UniversalState.menu_selected = math.max(1, (UniversalState.menu_selected or 1) - 1)
        elseif key_pressed("down") then
            UniversalState.menu_selected = math.min(#bind_list, (UniversalState.menu_selected or 1) + 1)
        end

        local sel = UniversalState.menu_selected or 1
        if sel > #bind_list then sel = #bind_list; UniversalState.menu_selected = sel end
        local record = bind_list[sel]
        if record and (key_pressed("enter") or key_pressed("space")) then
            UniversalState.menu_rebind_id = record.id
        end
    end
end

local function draw_menu_overlay()
    if not UniversalState.menu_visible then return end
    local sr = rawget(_G, "stingray")
    if not sr or not sr.Gui or not sr.Gui.rect then return end

    -- Main Panel
    pcall(sr.Gui.rect, 80, 50, 760, 580, 18, 22, 30, 240)
    pcall(sr.Gui.text, "--- UNIVERSAL MOD LOADER v22 (F2 / F9) ---", 100, 75, 20, 255, 215, 0, 255)

    -- Tab Bar
    local is_tab1 = (UniversalState.menu_tab == 1)
    local is_tab2 = (UniversalState.menu_tab == 2)
    pcall(sr.Gui.rect, 100, 98, 160, 26, is_tab1 and 45 or 25, is_tab1 and 65 or 32, is_tab1 and 95 or 42, 230)
    pcall(sr.Gui.text, "[ 1: Mod Options ]", 115, 115, 14, is_tab1 and 255 or 160, is_tab1 and 255 or 170, is_tab1 and 255 or 180, 255)

    pcall(sr.Gui.rect, 270, 98, 160, 26, is_tab2 and 45 or 25, is_tab2 and 65 or 32, is_tab2 and 95 or 42, 230)
    pcall(sr.Gui.text, "[ 2: Key Bindings ]", 285, 115, 14, is_tab2 and 255 or 160, is_tab2 and 255 or 170, is_tab2 and 255 or 180, 255)

    pcall(sr.Gui.text, "[Tab: Switch Tab | Up/Down: Select | Enter: Edit | F2/F9: Close]", 450, 115, 12, 170, 180, 190, 255)

    local y = 150
    local page_size = 14

    -- TAB 1 DRAWING
    if is_tab1 then
        local opt_keys = {}
        for id in pairs(ModOptionsMenu.registered) do opt_keys[#opt_keys + 1] = id end
        table.sort(opt_keys)
        local total = #opt_keys
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        local page = math.floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = math.min(total, start_idx + page_size - 1)

        for i = start_idx, end_idx do
            local id = opt_keys[i]
            local spec = ModOptionsMenu.registered[id]
            local val = ModOptionsMenu.get(id)
            local is_sel = (i == sel)
            if is_sel then
                pcall(sr.Gui.rect, 95, y - 4, 730, 24, 35, 60, 90, 220)
                pcall(sr.Gui.text, format("> [%s] %s: %s <", spec.mod or "MOD", spec.label or id, tostring(val)), 100, y, 15, 255, 255, 255, 255)
            else
                pcall(sr.Gui.text, format("  [%s] %s: %s", spec.mod or "MOD", spec.label or id, tostring(val)), 100, y, 15, 190, 200, 210, 255)
            end
            y = y + 25
        end

        if total == 0 then
            pcall(sr.Gui.text, "No configurable mod options registered.", 100, y, 15, 160, 160, 160, 255)
        elseif total > page_size then
            pcall(sr.Gui.text, format("Page %d of %d (%d options total)", page + 1, math.ceil(total / page_size), total), 100, 595, 12, 150, 160, 170, 255)
        end

    -- TAB 2 DRAWING
    elseif is_tab2 then
        local bind_list = ModBindingsMenu.order
        local total = #bind_list
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        local page = math.floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = math.min(total, start_idx + page_size - 1)

        for i = start_idx, end_idx do
            local record = bind_list[i]
            local current_key = ModBindingsMenu.binding(record.id)
            local is_sel = (i == sel)
            local is_rebinding = (UniversalState.menu_rebind_id == record.id)

            if is_rebinding then
                pcall(sr.Gui.rect, 95, y - 4, 730, 24, 180, 100, 20, 230)
                pcall(sr.Gui.text, format(">> [%s] %s: PRESS ANY KEY... [Esc: Cancel, Del: Clear] <<", record.category, record.label), 100, y, 15, 255, 255, 200, 255)
            elseif is_sel then
                pcall(sr.Gui.rect, 95, y - 4, 730, 24, 35, 60, 90, 220)
                pcall(sr.Gui.text, format("> [%s] %s = [%s] <", record.category, record.label, current_key:upper()), 100, y, 15, 255, 255, 255, 255)
            else
                pcall(sr.Gui.text, format("  [%s] %s = [%s]", record.category, record.label, current_key:upper()), 100, y, 15, 190, 200, 210, 255)
            end
            y = y + 25
        end

        if total == 0 then
            pcall(sr.Gui.text, "No configurable keybindings registered.", 100, y, 15, 160, 160, 160, 255)
        elseif total > page_size then
            pcall(sr.Gui.text, format("Page %d of %d (%d bindings total)", page + 1, math.ceil(total / page_size), total), 100, 595, 12, 150, 160, 170, 255)
        end
    end
end

-- ==============================================================================
-- 15. ENGINE LIFECYCLE HOOKS (INIT, UPDATE, RENDER, SHUTDOWN)
-- ==============================================================================
UniversalLoader_update = function(dt)
    update_bindings_state()
    handle_menu_input()
end

UniversalLoader_render = function(...)
    draw_menu_overlay()
end

UniversalLoader_shutdown = function()
    if save_persistent_settings then
        save_persistent_settings()
    end
    log_message("UniversalLoader", "Shutting down active mods...")
    UniversalState.active_mods = {}
    if UniversalState.log_file then
        UniversalState.log_file:close()
        UniversalState.log_file = nil
    end
end

-- ==============================================================================
-- 16. STARTUP INITIALIZATION
-- ==============================================================================
log_message("UniversalLoader", "Starting Universal Mod Loader (%s)", UniversalState.revision)
log_message("UniversalLoader", "Standards Active: Bingus (API 1) | Chef (API 3) | BootModLoader (API 1) | HD2Runtime (0.1.0)")

load_persistent_settings()
discover_installed_mods()

for _, cb in ipairs(UniversalState.after_startup_cbs) do
    pcall(cb)
end
