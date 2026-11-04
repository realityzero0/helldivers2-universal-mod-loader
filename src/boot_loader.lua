-- Universal Mod Loader v1.0.0 for Helldivers 2 (Steam Builds 25988413 / 26088801 / 26251122+ / Lua 5.1)
-- Replaces engine boot resource 0xF476DF93691895FA in bundle 9ba626afa44a3aa3
-- Unifies All Helldivers 2 Modding Standards:
--   1. Bingus Shared Loader (CowboyBingus / v17 / v20 / v21 / API 1 + BingusRuntime v1)
--   2. Chef Shared Loader (Th3chef / API Levels 1, 2, 3)
--   3. Boot Mod Loader (VeganSquid / API 1)
--   4. HD2 Lua Runtime (hd2rt / 0.1.0)
-- Pure Lua 5.1 compliant (Zero native FFI crashes, EAC-safe, Circuit-Breaker protected).
-- License: Zero-Clause BSD (0BSD)

-- 0. Cooperative handoff to Chef Shared Loader if installed with higher patch priority
local A = rawget(_G, 'stingray') and stingray.Application
if A and type(A.can_get) == 'function' and A.can_get('lua', 'mods/chef_shared_loader/core_1')
    and rawget(_G, 'ChefSharedLoader') == nil then
  rawset(_G, 'ChefSharedLoaderHandoff', { from = 'Universal Mod Loader v1.0.0' })
  local ok, err = pcall(require, 'mods/chef_shared_loader/core_1')
  if ok then return end
end

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

init = function(...)
    return prev_init(...)
end

render = function(...)
    return prev_render(...)
end

update = function(dt, ...)
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
                if cnt >= 10 then
                    update_hooks[id] = nil
                    pcall(print, "[UniversalLoader] [CIRCUIT BREAKER] update hook " .. tostring(id) .. " disabled after 10 errors.")
                end
            end
        end
    end
    return prev_update(dt, ...)
end

shutdown = function(...)
    for i = 1, #shutdown_order do
        local id = shutdown_order[i]
        local fn = shutdown_hooks[id]
        if fn then
            pcall(fn, ...)
        end
    end
    return prev_shutdown(...)
end

-- Engine environment check
if stingray and stingray.Application and type(stingray.Application.build) == "function" and stingray.Application.build() ~= "release" then
    pcall(require, "debug")
end
local jit_lib = rawget(_G, "jit")
if type(jit_lib) == "table" and type(jit_lib.off) == "function" then
    pcall(jit_lib.off)
end

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
    local sign = u >= BIT_MOD_HALF
    local res = floor(u / (2 ^ n))
    if sign then
        res = res + (BIT_MOD - 2 ^ (32 - n))
    end
    return tobit(res)
end

function bit.rol(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    return tobit(((u * (2 ^ n)) + floor(u / (2 ^ (32 - n)))) % BIT_MOD)
end

function bit.ror(x, n)
    n = n % 32
    if n == 0 then return tobit(x) end
    local u = to_u32(x)
    return tobit((floor(u / (2 ^ n)) + (u * (2 ^ (32 - n)))) % BIT_MOD)
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
package.loaded["bit"] = bit

-- 64-bit MurmurHash64A in pure Lua 5.1
local function mul64(al, ah, bl, bh)
    local a0, a1, a2, a3 = al % 65536, floor(al / 65536), ah % 65536, floor(ah / 65536)
    local b0, b1, b2, b3 = bl % 65536, floor(bl / 65536), bh % 65536, floor(bh / 65536)
    local p00 = a0 * b0
    local p01 = a0 * b1 + a1 * b0
    local p02 = a0 * b2 + a1 * b1 + a2 * b0
    local p03 = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
    local mid0 = p00 % 65536
    local c0 = floor(p00 / 65536)
    local mid1 = (p01 + c0) % 65536
    local c1 = floor((p01 + c0) / 65536)
    local mid2 = (p02 + c1) % 65536
    local c2 = floor((p02 + c1) / 65536)
    local mid3 = (p03 + c2) % 65536
    return mid0 + mid1 * 65536, mid2 + mid3 * 65536
end

local function xor64(al, ah, bl, bh)
    return bit_op_2(XOR_LUT, al, bl), bit_op_2(XOR_LUT, ah, bh)
end

local function rshift64(al, ah, shift)
    if shift == 0 then return al, ah end
    if shift < 32 then
        local p = 2 ^ shift
        return floor(al / p) + (ah % p) * (2 ^ (32 - shift)), floor(ah / p)
    elseif shift == 32 then
        return ah, 0
    else
        return floor(ah / (2 ^ (shift - 32))), 0
    end
end

local function murmur64_pair(str)
    local len = #str
    local m_l, m_h = 0x5BD1E995, 0xC6A4A793
    local r = 47
    local h_low, h_high = mul64(len, 0, m_l, m_h)
    local pos = 1
    local rem = len
    while rem >= 8 do
        local k_l = byte(str, pos) + byte(str, pos + 1) * 256 + byte(str, pos + 2) * 65536 + byte(str, pos + 3) * 16777216
        local k_h = byte(str, pos + 4) + byte(str, pos + 5) * 256 + byte(str, pos + 6) * 65536 + byte(str, pos + 7) * 16777216
        k_l, k_h = mul64(k_l, k_h, m_l, m_h)
        local s_l, s_h = rshift64(k_l, k_h, r)
        k_l, k_h = xor64(k_l, k_h, s_l, s_h)
        k_l, k_h = mul64(k_l, k_h, m_l, m_h)
        h_low, h_high = xor64(h_low, h_high, k_l, k_h)
        h_low, h_high = mul64(h_low, h_high, m_l, m_h)
        pos = pos + 8
        rem = rem - 8
    end
    if rem > 0 then
        local t_l, t_h = 0, 0
        if rem >= 7 then t_h = t_h + byte(str, pos + 6) * 65536 end
        if rem >= 6 then t_h = t_h + byte(str, pos + 5) * 256 end
        if rem >= 5 then t_h = t_h + byte(str, pos + 4) end
        if rem >= 4 then t_l = t_l + byte(str, pos + 3) * 16777216 end
        if rem >= 3 then t_l = t_l + byte(str, pos + 2) * 65536 end
        if rem >= 2 then t_l = t_l + byte(str, pos + 1) * 256 end
        if rem >= 1 then t_l = t_l + byte(str, pos) end
        t_l, t_h = mul64(t_l, t_h, m_l, m_h)
        local s_l, s_h = rshift64(t_l, t_h, r)
        t_l, t_h = xor64(t_l, t_h, s_l, s_h)
        t_l, t_h = mul64(t_l, t_h, m_l, m_h)
        h_low, h_high = xor64(h_low, h_high, t_l, t_h)
    end
    local s_l, s_h = rshift64(h_low, h_high, r)
    h_low, h_high = xor64(h_low, h_high, s_l, s_h)
    h_low, h_high = mul64(h_low, h_high, m_l, m_h)
    s_l, s_h = rshift64(h_low, h_high, r)
    h_low, h_high = xor64(h_low, h_high, s_l, s_h)
    return h_low, h_high
end

local function murmur64_key(str)
    local l, h = murmur64_pair(str)
    local b0 = l % 256
    local b1 = floor(l / 256) % 256
    local b2 = floor(l / 65536) % 256
    local b3 = floor(l / 16777216) % 256
    local b4 = h % 256
    local b5 = floor(h / 256) % 256
    local b6 = floor(h / 65536) % 256
    local b7 = floor(h / 16777216) % 256
    return char(b0, b1, b2, b3, b4, b5, b6, b7)
end

-- ==============================================================================
-- 3. PURE LUA 5.2/5.3 POLYFILLS (bit32 & utf8)
-- ==============================================================================
local bit32 = {
    band = bit.band,
    bnot = bit.bnot,
    bor = bit.bor,
    bxor = bit.bxor,
    lshift = bit.lshift,
    rshift = bit.rshift,
    arshift = bit.arshift,
    lrotate = bit.rol,
    rrotate = bit.ror,
    btest = function(a, b) return bit.band(a, b) ~= 0 end,
    extract = function(n, field, width)
        width = width or 1
        return bit.band(bit.rshift(n, field), (2 ^ width) - 1)
    end,
    replace = function(n, v, field, width)
        width = width or 1
        local mask = bit.lshift((2 ^ width) - 1, field)
        return bit.bor(bit.band(n, bit.bnot(mask)), bit.lshift(bit.band(v, (2 ^ width) - 1), field))
    end
}
_G.bit32 = bit32
package.preload["bit32"] = function() return bit32 end
package.loaded["bit32"] = bit32

local utf8_lib = {
    charpattern = "[%z\001-\127\194-\253][\128-\191]*",
    char = function(...)
        local t = {}
        for i = 1, select('#', ...) do
            local cp = select(i, ...)
            if cp < 0x80 then
                t[#t + 1] = char(cp)
            elseif cp < 0x800 then
                t[#t + 1] = char(0xC0 + floor(cp / 64), 0x80 + (cp % 64))
            elseif cp < 0x10000 then
                t[#t + 1] = char(0xE0 + floor(cp / 4096), 0x80 + (floor(cp / 64) % 64), 0x80 + (cp % 64))
            elseif cp < 0x110000 then
                t[#t + 1] = char(0xF0 + floor(cp / 262144), 0x80 + (floor(cp / 4096) % 64), 0x80 + (floor(cp / 64) % 64), 0x80 + (cp % 64))
            end
        end
        return concat(t)
    end,
    len = function(s, i, j)
        s = s:sub(i or 1, j or -1)
        local _, count = s:gsub("[%z\001-\127\194-\253][\128-\191]*", "")
        return count
    end,
    codepoint = function(s, i, j)
        i = i or 1
        j = j or i
        local res = {}
        local pos = 1
        for m in s:gmatch("[%z\001-\127\194-\253][\128-\191]*") do
            if pos >= i and pos <= j then
                local b1 = byte(m, 1)
                if b1 < 0x80 then
                    res[#res + 1] = b1
                elseif b1 < 0xE0 then
                    res[#res + 1] = (b1 - 0xC0) * 64 + (byte(m, 2) - 0x80)
                elseif b1 < 0xF0 then
                    res[#res + 1] = (b1 - 0xE0) * 4096 + (byte(m, 2) - 0x80) * 64 + (byte(m, 3) - 0x80)
                else
                    res[#res + 1] = (b1 - 0xF0) * 262144 + (byte(m, 2) - 0x80) * 4096 + (byte(m, 3) - 0x80) * 64 + (byte(m, 4) - 0x80)
                end
            end
            pos = pos + 1
        end
        return unpack(res)
    end
}
_G.utf8 = utf8_lib
package.preload["utf8"] = function() return utf8_lib end
package.loaded["utf8"] = utf8_lib

-- ==============================================================================
-- 4. NON-CRASHING FFI / WIN32 COMPATIBILITY STUBS & MOCK POINTERS
-- ==============================================================================
local orig_tonumber = _G.tonumber
function _G.tonumber(val, base)
    if type(val) == "table" and getmetatable(val) and getmetatable(val).__tonumber then
        return getmetatable(val).__tonumber(val)
    end
    if base ~= nil then
        return orig_tonumber(val, base)
    end
    return orig_tonumber(val)
end

local mock_ptr_mt
mock_ptr_mt = {
    __index = function(tbl, key)
        if type(key) == "number" then
            local base = rawget(tbl, "__base") or tbl
            local off = rawget(tbl, "__offset") or 0
            return rawget(base, key + off) or 0
        end
        return rawget(tbl, key) or 0
    end,
    __newindex = function(tbl, key, val)
        if type(key) == "number" then
            local base = rawget(tbl, "__base") or tbl
            local off = rawget(tbl, "__offset") or 0
            rawset(base, key + off, val)
            return
        end
        rawset(tbl, key, val)
    end,
    __add = function(self, n)
        local base = rawget(self, "__base") or self
        local off = (rawget(self, "__offset") or 0) + (tonumber(n) or 0)
        return setmetatable({ __base = base, __offset = off, __addr = rawget(self, "__addr") }, mock_ptr_mt)
    end,
    __sub = function(self, n)
        if type(n) == "table" then
            return (tonumber(self) or 0) - (tonumber(n) or 0)
        end
        local base = rawget(self, "__base") or self
        local off = (rawget(self, "__offset") or 0) - (tonumber(n) or 0)
        return setmetatable({ __base = base, __offset = off, __addr = rawget(self, "__addr") }, mock_ptr_mt)
    end,
    __eq = function(a, b)
        return (tonumber(a) or 0) == (tonumber(b) or 0)
    end,
    __lt = function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end,
    __le = function(a, b)
        return (tonumber(a) or 0) <= (tonumber(b) or 0)
    end,
    __tonumber = function(self)
        local base_addr = rawget(self, "__addr") or 65536
        local off = rawget(self, "__offset") or 0
        return base_addr + off
    end,
    __tostring = function(self)
        return tostring(tonumber(self))
    end,
    __call = function(self, ...)
        return setmetatable({ __base = nil, __offset = 0, __addr = 0 }, mock_ptr_mt)
    end
}

local function make_mock_pointer(addr)
    local t = { __base = nil, __offset = 0, __addr = addr or 65536 }
    for i = 0, 64 do t[i] = 0 end
    return setmetatable(t, mock_ptr_mt)
end

local kernel32_stub = {}
kernel32_stub.QueryPerformanceFrequency = function(ptr)
    if type(ptr) == "table" then ptr[0] = 10000000; ptr[1] = 0 end
    return 1
end
kernel32_stub.QueryPerformanceCounter = function(ptr)
    if type(ptr) == "table" then
        local count = floor((os.clock() or 0) * 10000000)
        ptr[0] = count % BIT_MOD
        ptr[1] = floor(count / BIT_MOD)
    end
    return 1
end
kernel32_stub.GetTickCount64 = function()
    return floor((os.clock() or 0) * 1000)
end
kernel32_stub.CreateDirectoryA = function() return 1 end
kernel32_stub.GetLastError = function() return 0 end
kernel32_stub.GetModuleFileNameA = function() return 0 end
kernel32_stub.GetModuleFileNameW = function() return 0 end
kernel32_stub.GetModuleHandleA = function() return make_mock_pointer(4194304) end
kernel32_stub.GetProcAddress = function(handle, name)
    local clean = tostring(name):gsub("^[^_]*_", "")
    return kernel32_stub[clean] or kernel32_stub[name] or function() return 0 end
end
kernel32_stub.FindFirstFileA = function() return make_mock_pointer(0) end
kernel32_stub.FindNextFileA = function() return 0 end
kernel32_stub.FindClose = function() return 1 end
kernel32_stub.CreateFileW = function() return 1 end
kernel32_stub.CloseHandle = function() return 1 end
kernel32_stub.ReadFile = function() return 1 end
kernel32_stub.VirtualQuery = function() return 0 end
kernel32_stub.ReadProcessMemory = function() return 0 end
kernel32_stub.GetCurrentProcess = function() return make_mock_pointer(1) end
kernel32_stub.GetFileSizeEx = function() return 0 end

local ffi_stub = {
    cdef = function() end,
    load = function(lib)
        return setmetatable({}, {
            __index = function(_, key)
                local name = tostring(key):gsub("^[^_]*_", "")
                return kernel32_stub[name] or kernel32_stub[key] or function() return 1 end
            end
        })
    end,
    typeof = function() return function() return make_mock_pointer(65536) end end,
    new = function(tp, ...) return make_mock_pointer(65536) end,
    cast = function(tp, val)
        if type(val) == "function" then return val end
        if type(val) == "table" then return val end
        local num = tonumber(val) or 65536
        return make_mock_pointer(num)
    end,
    metatype = function() end,
    gc = function(o) return o end,
    sizeof = function() return 16 end,
    alignof = function() return 1 end,
    offsetof = function() return 0 end,
    istype = function() return false end,
    string = function(ptr, len) return "" end,
    copy = function() end,
    fill = function() end,
    abi = function(arg) return true end,
    arch = "x64",
    os = "Windows",
    C = setmetatable({}, {
        __index = function(_, name)
            local clean = tostring(name):gsub("^[^_]*_", "")
            return kernel32_stub[clean] or kernel32_stub[name] or function() return 0 end
        end
    })
}
_G.ffi = ffi_stub
package.preload["ffi"] = function() return ffi_stub end
package.loaded["ffi"] = ffi_stub

local jit_stub = {
    on = function() end,
    off = function() end,
    flush = function() end,
    status = function() return false, "PUC-Rio Lua 5.1" end,
    version = "Lua 5.1",
    os = "Windows",
    arch = "x64"
}
_G.jit = jit_stub

-- ==============================================================================
-- 5. BINGUS SHARED RUNTIME v1 (100% pure Lua with Canonical Guard & Statuses)
-- ==============================================================================
local bingus_runtime = (function()
    local M = { VERSION = 1, version = 1 }
    local RT_KEY = "BingusRuntime"
    local SUBTABLES = { "hashes", "statuses", "versions" }

    function M.hash(content)
        return murmur64_key(content)
    end

    function M.status(name)
        local rt = rawget(_G, RT_KEY)
        if rt and rt.statuses then
            return rt.statuses[name] or rt.statuses
        end
        return {}
    end

    function M.shared(env)
        env = env or _G
        local rt = rawget(env, RT_KEY)
        if type(rt) ~= "table" then
            rt = {}
            rawset(env, RT_KEY, rt)
        end
        for _, k in ipairs(SUBTABLES) do
            if type(rawget(rt, k)) ~= "table" then
                rawset(rt, k, {})
            end
        end
        if type(rawget(rt, "hash_reads")) ~= "number" then
            rawset(rt, "hash_reads", 0)
        end
        rawset(rawget(rt, "versions"), M.VERSION, true)
        if type(rawget(rt, "shared")) ~= "function" then
            rawset(rt, "shared", M.shared)
        end
        if type(rawget(rt, "guard")) ~= "function" then
            rawset(rt, "guard", M.guard)
        end
        if type(rawget(rt, "hash")) ~= "function" then
            rawset(rt, "hash", M.hash)
        end
        if type(rawget(rt, "status")) ~= "function" then
            rawset(rt, "status", M.status)
        end
        rt.version = 1
        rt.api = 1
        return rt
    end

    function M.guard(spec)
        local name = type(spec) == "table" and spec.name
        if type(name) ~= "string" or name == "" then
            error("guard name required", 0)
        end
        local rt = M.shared(spec.env)
        if rt.statuses[name] and rt.statuses[name].installed then
            error("guard " .. name .. " already installed", 0)
        end
        local status = {
            errors = 0,
            installed = false,
            lower_errors = 0,
            pauses = 0,
            state = "new",
            name = name,
            version = M.VERSION
        }
        rt.statuses[name] = status

        local step_fn = spec.step
        local after_fn = spec.after
        local stop_fn = spec.stop
        local pause_fn = spec.pause
        local log_fn = spec.log
        local max_errors = spec.errors or 8
        local resume_frames = spec.resume or 60
        local clean_frames = spec.clean or 3600

        local chain_update, chain_shutdown
        local in_flight, stopped, paused, had_error = false, false, false, false
        local clean_count, lower_clean_count = 0, 0

        local function log_msg(msg)
            if log_fn then pcall(log_fn, msg) end
        end

        local function do_stop(reason)
            if stopped then return end
            stopped, paused = true, false
            status.first_failure = status.first_failure or reason
            status.state = "stopped: " .. reason
            log_msg(name .. " stopped: " .. reason)
            if stop_fn then
                local ok, err = pcall(stop_fn, reason)
                if not ok then status.stop_error = tostring(err) end
            end
        end

        local function on_error(err)
            had_error, clean_count = true, 0
            status.errors = status.errors + 1
            local msg = tostring(err)
            status.first_error = status.first_error or msg
            if status.errors == 1 then
                status.burst_error = msg
                log_msg(name .. " error: " .. msg)
            end
            if status.errors >= max_errors then
                do_stop("stopped after " .. max_errors .. " errors: " .. status.burst_error)
            end
        end

        local function on_lower_error()
            lower_clean_count = 0
            status.lower_errors = status.lower_errors + 1
            if not pause_fn then return do_stop("the previous update failed") end
            if status.lower_errors >= max_errors then
                return do_stop("stopped after " .. max_errors .. " failed updates below this mod")
            end
            if paused then return end
            paused = true
            status.pauses = status.pauses + 1
            status.state = "paused: the previous update failed"
            log_msg(name .. " paused: the previous update failed")
            local ok, err = pcall(pause_fn, "the previous update failed")
            if not ok then do_stop("pause failed: " .. tostring(err)) end
        end

        local function check_resume()
            if paused and lower_clean_count >= resume_frames then
                paused = false
                status.state = "running"
                log_msg(name .. " resumed after " .. resume_frames .. " clean frames")
            end
        end

        local function count_clean()
            if had_error then return end
            clean_count = clean_count + 1
            if clean_count == clean_frames then status.errors = 0 end
        end

        local function finish_step(...)
            in_flight = false
            lower_clean_count = lower_clean_count + 1
            if lower_clean_count == clean_frames then status.lower_errors = 0 end
            if not stopped and not paused then
                if after_fn then
                    local ok, err = pcall(after_fn)
                    if not ok then on_error(err) end
                end
                count_clean()
            end
            return ...
        end

        local function guarded_update(...)
            had_error = false
            if in_flight then
                in_flight = false
                if not stopped then on_lower_error() end
            end
            check_resume()
            if step_fn and not stopped and not paused then
                local ok, err = pcall(step_fn, ...)
                if not ok then on_error(err) end
            end
            in_flight = true
            return finish_step(chain_update(...))
        end

        local function guarded_shutdown(...)
            if in_flight then
                in_flight = false
                status.first_failure = status.first_failure or "the previous update failed"
            end
            local fail = status.first_failure
            if not stopped then
                stopped = true
                if stop_fn then
                    local ok, err = pcall(stop_fn, "shutdown")
                    if not ok then status.stop_error = tostring(err) end
                end
            end
            status.state = fail and ("stopped after: " .. fail) or "stopped"
            if chain_shutdown then return chain_shutdown(...) end
        end

        local handle = { status = status }

        function handle.install()
            local env = spec.env or _G
            if status.installed then
                error("guard " .. name .. " already installed", 0)
            end
            chain_update = rawget(env, "update")
            if type(chain_update) ~= "function" then
                error("game update unavailable", 0)
            end
            chain_shutdown = rawget(env, "shutdown")
            rawset(env, "update", guarded_update)
            rawset(env, "shutdown", guarded_shutdown)
            status.installed, status.state = true, "running"
            return handle
        end

        function handle.stop(reason)
            do_stop(tostring(reason))
        end

        function handle.running()
            return status.installed and not stopped
        end

        return handle
    end

    return M
end)()

_G.BingusRuntime = bingus_runtime.shared(_G)
package.preload["BingusRuntime"] = function() return _G.BingusRuntime end
package.loaded["BingusRuntime"] = _G.BingusRuntime

-- ==============================================================================
-- 6. MULTI-STANDARD MOD LOADER GLOBALS & APIS
-- ==============================================================================
local after_startup_queue = {}
local loaded_modules = {}

-- 1. CowboyBingusModLoader & HD2ModLoader
local loader_state = {
    api = 1,
    api_version = 1,
    version = 17,
    revision = "loader-v1.0.0-universal",
    modules = loaded_modules,
    capabilities = {
        api = 1,
        api_version = 1,
        logs = true,
        discovery = true,
        after_startup = true,
        on_update = true,
        on_shutdown = true,
        dynamic_hot_reload = true,
        circuit_breaker = true
    },
    open_log = function(filename)
        local appdata = os.getenv and os.getenv("LOCALAPPDATA")
        if appdata and filename then
            local dir = appdata .. "/CowboyBingus/Helldivers2/Logs"
            pcall(function() os.execute('mkdir "' .. dir:gsub('/', '\\') .. '" 2>nul') end)
            local f = io.open(dir .. "/" .. filename, "a")
            if f then return f end
        end
        return {
            write = function() end,
            flush = function() end,
            close = function() end
        }
    end,
    after_startup = function(fn)
        if type(fn) == "function" then
            table.insert(after_startup_queue, fn)
            return true
        end
        return false
    end,
    on_update = function(id, fn)
        if type(id) == "function" and fn == nil then
            fn = id
            id = "anonymous_" .. tostring(fn)
        end
        if type(id) ~= "string" or id == "" then return false end
        if update_hooks[id] == nil and fn ~= nil then
            update_order[#update_order + 1] = id
        end
        update_hooks[id] = fn
        return true
    end,
    on_shutdown = function(id, fn)
        if type(id) == "function" and fn == nil then
            fn = id
            id = "anonymous_" .. tostring(fn)
        end
        if type(id) ~= "string" or id == "" then return false end
        if shutdown_hooks[id] == nil and fn ~= nil then
            shutdown_order[#shutdown_order + 1] = id
        end
        shutdown_hooks[id] = fn
        return true
    end
}
rawset(_G, "CowboyBingusModLoader", loader_state)
rawset(_G, "HD2ModLoader", loader_state)

-- 2. Boot Mod Loader (VeganSquid)
local BootModLoader
BootModLoader = {
    api = 1,
    api_version = 1,
    version = 1,
    hooks = setmetatable({}, {
        __index = function(t, k)
            local list = {}
            rawset(t, k, list)
            return list
        end
    }),
    hook = function(target, fn)
        if type(target) == "string" and type(fn) == "function" then
            table.insert(BootModLoader.hooks, { target = target, fn = fn })
            table.insert(BootModLoader.hooks[target], fn)
            return true
        end
        return false
    end
}
_G.BootModLoader = BootModLoader
package.preload["BootModLoader"] = function() return BootModLoader end
package.loaded["BootModLoader"] = BootModLoader

-- 3. HD2 Lua Runtime (hd2rt)
local hd2rt_listeners = {}
local hd2rt = {
    _VERSION = "0.1.0",
    version = "0.1.0",
    on = function(evt, cb)
        if type(evt) == "string" and type(cb) == "function" then
            hd2rt_listeners[evt] = hd2rt_listeners[evt] or {}
            table.insert(hd2rt_listeners[evt], cb)
        end
    end,
    emit = function(evt, ...)
        local list = hd2rt_listeners[evt]
        if list then
            for _, fn in ipairs(list) do
                pcall(fn, ...)
            end
        end
    end,
    register_mod = function(info)
        local id = (type(info) == "table" and info.id) or "anonymous_hd2rt"
        loaded_modules[id] = "loaded"
    end
}
_G.hd2rt = hd2rt
_G.hd2runtime = hd2rt
package.preload["hd2rt"] = function() return hd2rt end
package.preload["hd2runtime"] = function() return hd2rt end
package.loaded["hd2rt"] = hd2rt
package.loaded["hd2runtime"] = hd2rt

-- 4. Chef Shared Loader Emulation (API Levels 1, 2, 3)
local chef_shared_state = {}
local chef_api = {
    api_level = 3,
    loader_name = "UniversalModLoader",
    loader_version = "1.0.0",
    is_chef_loader = true,
    is_universal_loader = true,
    on = function(event_name, callback)
        if event_name == "update" and type(callback) == "function" then
            local id = "chef_update_" .. tostring(#update_order + 1)
            update_order[#update_order + 1] = id
            update_hooks[id] = callback
        elseif event_name == "shutdown" and type(callback) == "function" then
            local id = "chef_shut_" .. tostring(#shutdown_order + 1)
            shutdown_order[#shutdown_order + 1] = id
            shutdown_hooks[id] = callback
        else
            hd2rt.on(event_name, callback)
        end
    end,
    state = {
        get = function(key) return chef_shared_state[key] end,
        set = function(key, val) chef_shared_state[key] = val end
    },
    options = {
        register = function(spec)
            if type(spec) == "table" and spec.id then
                local mom = rawget(_G, "ModOptionsMenu")
                if mom and type(mom.register_option) == "function" then
                    pcall(mom.register_option, spec.id, spec)
                end
            end
        end,
        get = function(id)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.get) == "function" then return mom.get(id) end
            return nil
        end,
        set = function(id, val)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.set) == "function" then return mom.set(id, val) end
        end
    },
    bindings = {
        register = function(id, label, default_key)
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.register_binding) == "function" then
                pcall(mbm.register_binding, id, label, nil, { default = default_key })
            end
        end,
        is_down = function(id)
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.is_down) == "function" then return mbm.is_down(id) end
            return false
        end,
        is_pressed = function(id)
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.is_pressed) == "function" then return mbm.is_pressed(id) end
            return false
        end,
        get = function(id)
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.binding) == "function" then return mbm.binding(id) end
            return nil
        end
    },
    log = function(fmt, ...)
        pcall(print, "[ChefMod] " .. string.format(fmt, ...))
    end
}
_G.ChefSharedLoader = chef_api
package.preload["ChefSharedLoader"] = function() return chef_api end
package.loaded["ChefSharedLoader"] = chef_api

-- Fallback stubs for ModOptionsMenu and ModBindingsMenu so dependent mods don't crash
-- if they register settings before mods/cowboybingus/mod_options_menu loads.
if rawget(_G, "ModOptionsMenu") == nil then
    local registered_opts = {}
    local fallback_opts = {}
    local order_opts = {}
    local callbacks_opts = {}
    local mom_stub
    mom_stub = {
        revision = 1,
        values = fallback_opts,
        registered = registered_opts,
        order = order_opts,
        change_callbacks = callbacks_opts,
        register_option = function(id, spec)
            if type(id) ~= "string" or id == "" then return end
            if not registered_opts[id] then
                order_opts[#order_opts + 1] = id
            end
            registered_opts[id] = spec or {}
            if fallback_opts[id] == nil and type(spec) == "table" then
                fallback_opts[id] = spec.default
            end
        end,
        get = function(id)
            if fallback_opts[id] ~= nil then return fallback_opts[id] end
            local s = registered_opts[id]
            return s and s.default
        end,
        set = function(id, v)
            local old = fallback_opts[id]
            fallback_opts[id] = v
            mom_stub.revision = mom_stub.revision + 1
            local cbs = callbacks_opts[id]
            if cbs then
                for i = 1, #cbs do
                    pcall(cbs[i], v, old)
                end
            end
        end,
        on_change = function(id, cb)
            if type(id) == "string" and type(cb) == "function" then
                callbacks_opts[id] = callbacks_opts[id] or {}
                table.insert(callbacks_opts[id], cb)
            end
        end,
        reset_option = function(id)
            local s = registered_opts[id]
            if s and s.default ~= nil then
                mom_stub.set(id, s.default)
            end
        end,
        reset = function()
            for id, s in pairs(registered_opts) do
                if s and s.default ~= nil then
                    fallback_opts[id] = s.default
                end
            end
            mom_stub.revision = mom_stub.revision + 1
        end,
        log = function(...) end
    }
    _G.ModOptionsMenu = mom_stub
    package.preload["ModOptionsMenu"] = function() return _G.ModOptionsMenu end
    package.loaded["ModOptionsMenu"] = _G.ModOptionsMenu
end

if rawget(_G, "ModBindingsMenu") == nil then
    local bound_keys = {}
    local registry_binds = {}
    local order_binds = {}
    local sr_keyboard = nil
    local function get_kb()
        if sr_keyboard ~= nil then return sr_keyboard end
        local sr = rawget(_G, "stingray")
        if sr and sr.Keyboard then sr_keyboard = sr.Keyboard end
        return sr_keyboard
    end

    local mbm_stub
    mbm_stub = {
        revision = 1,
        assignments = bound_keys,
        bindings = registry_binds,
        registry = registry_binds,
        order = order_binds,
        register_binding = function(id, label, default_key, extra)
            if type(id) ~= "string" or id == "" then return end
            if not registry_binds[id] then
                order_binds[#order_binds + 1] = id
            end
            local def_k = default_key or (type(extra) == "table" and extra.default) or nil
            registry_binds[id] = {
                id = id,
                label = label or id,
                default = def_k,
                extra = extra
            }
            if bound_keys[id] == nil and def_k ~= nil then
                bound_keys[id] = def_k
            end
        end,
        binding = function(id)
            return bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
        end,
        get_binding = function(id)
            return bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
        end,
        set_binding = function(id, key)
            bound_keys[id] = key
            mbm_stub.revision = mbm_stub.revision + 1
        end,
        reset_binding = function(id)
            local rec = registry_binds[id]
            if rec and rec.default then
                bound_keys[id] = rec.default
                mbm_stub.revision = mbm_stub.revision + 1
            end
        end,
        is_down = function(id)
            local k = bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if not k then return false end
            local kb = get_kb()
            if kb and type(kb.button) == "function" and type(kb.button_id) == "function" then
                local bid = kb.button_id(tostring(k):lower())
                if bid then
                    local ok, down = pcall(kb.button, bid)
                    return ok and (down == true or (type(down) == "number" and down > 0.5))
                end
            end
            return false
        end,
        is_pressed = function(id)
            local k = bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if not k then return false end
            local kb = get_kb()
            if kb and type(kb.pressed) == "function" and type(kb.button_id) == "function" then
                local bid = kb.button_id(tostring(k):lower())
                if bid then
                    local ok, pressed = pcall(kb.pressed, bid)
                    return ok and pressed == true
                end
            end
            return false
        end,
        is_released = function(id)
            local k = bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if not k then return false end
            local kb = get_kb()
            if kb and type(kb.released) == "function" and type(kb.button_id) == "function" then
                local bid = kb.button_id(tostring(k):lower())
                if bid then
                    local ok, rel = pcall(kb.released, bid)
                    return ok and rel == true
                end
            end
            return false
        end,
        was_pressed = function(id) return mbm_stub.is_pressed(id) end,
        was_released = function(id) return mbm_stub.is_released(id) end,
        log = function(...) end
    }
    _G.ModBindingsMenu = mbm_stub
    package.preload["ModBindingsMenu"] = function() return _G.ModBindingsMenu end
    package.loaded["ModBindingsMenu"] = _G.ModBindingsMenu
end

-- ==============================================================================
-- 7. LOGGING SUBSYSTEM
-- ==============================================================================
local log_lines = {}
local function log_write(msg)
    local line = string.format("[%s] %s", os.date("%Y-%m-%d %H:%M:%S"), tostring(msg))
    table.insert(log_lines, line)
    pcall(print, "[UniversalLoader] " .. line)
    local appdata = os.getenv and os.getenv("LOCALAPPDATA")
    if appdata then
        local p = appdata .. "/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log"
        local f = io.open(p, "a")
        if f then
            f:write(line .. "\n")
            f:close()
        end
    end
end

log_write("Universal Mod Loader v1.0.0 initializing on " .. _VERSION)
log_write("Standards Active: Bingus (API 1 / Runtime v1) | Chef (API 3) | BootModLoader (API 1) | HD2Runtime (0.1.0)")

-- ==============================================================================
-- 8. COMPREHENSIVE ADDON DISCOVERY & SAFE EXECUTION GATEWAY
-- ==============================================================================
pcall(function()
    package.path = package.path .. ";mods/?.lua;mods/?/init.lua;../mods/?.lua;../mods/?/init.lua"
end)

local candidate_modules = {
    -- Core UI Addon Mod (renders the native [MODS 4] 3-column menu)
    "mods/cowboybingus/mod_options_menu",
    "mods/cowboybingus/mod_bindings_menu",

    -- Chef Mods
    "mods/chef/seaf_artillery_loadout",
    "mods/chef/smarter_guard_dogs_and_sentries",
    "mods/chef/smarter_guard_dogs_and_sentries_dogs",
    "mods/chef/smarter_guard_dogs_and_sentries_sentries",
    "mods/chef/smarter_guard_dogs_and_sentries_tesla",
    "mods/chef/smarter_guard_dogs_and_sentries_armor",
    "mods/chef/smarter_guard_dogs_and_sentries_priority",
    "mods/chef/smarter_guard_dogs_and_sentries_ping",
    "mods/chef/smarter_guard_dogs_and_sentries_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_teammates",
    "mods/chef/smarter_guard_dogs_and_sentries_sentry_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_seaf_safety",
    "mods/chef/smarter_guard_dogs_and_sentries_laser",
    "mods/chef/smarter_guard_dogs_and_sentries_glow",
    "mods/chef/smarter_guard_dogs_and_sentries_laser_invert",
    "mods/chef/smarter_guard_dogs_and_sentries_brightness",
    "mods/chef/smarter_guard_dogs_and_sentries_marker",
    "mods/chef/smarter_guard_dogs_and_sentries_marker_opacity",
    "mods/chef/smarter_guard_dogs_and_sentries_marker_size",

    -- CowboyBingus Mods
    "mods/cowboybingus/vanilla_plus_megapack",
    "mods/cowboybingus/better_stratagem_bounce",
    "mods/cowboybingus/hellpod_steering_unlocked",
    "mods/cowboybingus/wide_angle_stratagems",
    "mods/cowboybingus/reinforcement_beacon_fix_data",
    "mods/cowboybingus/consistent_vaulting",
    "mods/cowboybingus/shallow_water_dive",
    "mods/cowboybingus/sentry_aim_retention",
    "mods/cowboybingus/corpse_collision_repair",
    "mods/cowboybingus/vehicle_stability",
    "mods/cowboybingus/hover_pack_cancel",
    "mods/cowboybingus/enemy_intelligence",
    "mods/cowboybingus/armory_preview_cache",

    -- Community HUDs and Addons
    "mods/mortar/mortar_hud",
    "mods/vehicle_seat_tools/vehicle_seat_switch",
    "mods/engle/eagle_hud_probe",
    "mods/retrox/sentry_hud",
    "mods/warbond_desk/main",
    "mods/arena_local/mech_part_hud",
    "mods/reticle_ammo/hud",
    "mods/patpatpatrick/helmet_headlamp",
    "mods/driverhud/driver_hud",
    "mods/codex/gun_calibration"
}

-- Also scan patch files if available to discover any declared addons not in candidate_modules
pcall(function()
    local family = "9ba626afa44a3aa3"
    local lua_type = char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
    local open = io.open

    local function u32(bytes, offset)
        local a, b, c, d = bytes:byte(offset + 1, offset + 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end

    local existing = {}
    for _, name in ipairs(candidate_modules) do existing[name] = true end

    -- Check patches from patch_1 to patch_256 (patch_0 is our loader)
    for p_num = 1, 256 do
        local p_path = "data/" .. family .. ".patch_" .. p_num
        local f = open(p_path, "rb")
        if not f then
            f = open("../data/" .. family .. ".patch_" .. p_num, "rb")
        end
        if f then
            local header = f:read(72)
            if header and #header >= 72 and u32(header, 0) == 0xf0000011 then
                local types, count = u32(header, 4), u32(header, 8)
                local table_start = 72 + 32 * types
                for index = 0, count - 1 do
                    f:seek("set", table_start + index * 80)
                    local row = f:read(80)
                    if row and #row == 80 and row:sub(9, 16) == lua_type then
                        local off = u32(row, 16)
                        local len = u32(row, 56)
                        if off > 0 and len >= 8 then
                            f:seek("set", off)
                            local env = f:read(8)
                            if env and #env == 8 and u32(env, 4) == 2 then
                                local body_len = math.min(u32(env, 0), 256)
                                local prefix = f:read(body_len)
                                if prefix then
                                    local d_name = prefix:match("^%-%- HD2%-Addon:%s*([^\r\n]+)")
                                        or prefix:match("^%-%- @mod%s+([^\r\n]+)")
                                    if d_name then
                                        d_name = d_name:gsub("^%s+", ""):gsub("%s+$", "")
                                        if not existing[d_name] and not d_name:find("boot", 1, true) then
                                            candidate_modules[#candidate_modules + 1] = d_name
                                            existing[d_name] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            f:close()
        end
    end
end)

-- Safe Execution Loop
local app = stingray and stingray.Application
local loaded_count = 0
local failed_count = 0
local not_installed_count = 0

for _, mod_name in ipairs(candidate_modules) do
    local is_installed = false
    if app and type(app.can_get) == "function" then
        local ok, can = pcall(app.can_get, "lua", mod_name)
        if ok and can then
            is_installed = true
        end
    else
        -- Outside game engine (mock/test environment): test via package lookup
        is_installed = true
    end

    if is_installed then
        loaded_modules[mod_name] = "loading"
        local ok, res = pcall(require, mod_name)
        if ok then
            loaded_modules[mod_name] = "loaded"
            loaded_count = loaded_count + 1
            log_write("Loaded mod: " .. mod_name)
        else
            -- ISOLATE ERROR: Mark failed, do not crash!
            local err_msg = tostring(res):gsub("[\r\n]+", " ")
            loaded_modules[mod_name] = "failed: " .. err_msg
            failed_count = failed_count + 1
            log_write("Failed loading " .. mod_name .. ": " .. err_msg)
        end
    else
        loaded_modules[mod_name] = "not installed"
        not_installed_count = not_installed_count + 1
    end
end

log_write(string.format("Startup finished: %d loaded, %d failed, %d not installed", loaded_count, failed_count, not_installed_count))

-- Run after_startup callbacks
local ran_cb, failed_cb = 0, 0
for _, cb in ipairs(after_startup_queue) do
    local ok, err = pcall(cb)
    if ok then
        ran_cb = ran_cb + 1
    else
        failed_cb = failed_cb + 1
        log_write("After startup callback failed: " .. tostring(err))
    end
end
log_write(string.format("After startup: %d callbacks run, %d failed", ran_cb, failed_cb))
