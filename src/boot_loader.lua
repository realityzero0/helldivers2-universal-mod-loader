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
        local u_ok, u_err = pcall(UniversalLoader_update, dt)
        if not u_ok then
            pcall(print, "[UniversalLoader] internal update error: " .. tostring(u_err))
        end
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

local orig_tonumber = tonumber
local function safe_tonumber(v, base)
    if type(v) == "table" then
        local mt = getmetatable(v)
        if mt and type(mt.__tonumber) == "function" then
            return mt.__tonumber(v)
        end
    end
    if base ~= nil then
        return orig_tonumber(v, base)
    end
    return orig_tonumber(v)
end
_G.tonumber = safe_tonumber
tonumber = safe_tonumber

local native_bit = rawget(_G, "bit")
if type(native_bit) ~= "table" and package and package.preload and type(package.preload["bit"]) == "function" then
    local ok, res = pcall(package.preload["bit"])
    if ok and type(res) == "table" then native_bit = res end
end
if type(native_bit) == "table" and type(native_bit.band) == "function" then
    for k, v in pairs(bit) do
        if native_bit[k] == nil then native_bit[k] = v end
    end
    bit = native_bit
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
function ffi.new(ct, init, init2)
    local ct_str = tostring(ct or "")
    local sz = 4096
    if type(init) == "number" and ct_str:find("%[%?%]") then
        sz = init
    elseif ct_str:match("%[(%d+)%]") then
        sz = tonumber(ct_str:match("%[(%d+)%]")) or 4096
    end
    local p = make_mock_pointer(type(init) == "number" and init or 0)
    rawset(p, "_size", sz)
    if type(init) == "table" then
        for k, v in pairs(init) do p[k] = v end
    elseif type(init2) == "table" then
        for k, v in pairs(init2) do p[k] = v end
    end
    return p
end
function ffi.cast(ct, val)
    if type(val) == "function" then return val end
    if type(val) == "table" and type(rawget(val, "_fn")) == "function" then
        return rawget(val, "_fn")
    end
    return make_mock_pointer(type(val) == "table" and rawget(val, "_addr") or tonumber(val) or 0)
end
function ffi.typeof(ct) return ct end
function ffi.sizeof(ct)
    if type(ct) == "table" then
        return rawget(ct, "_size") or 4096
    end
    local s = tostring(ct or ""):lower()
    if s:find("memory") or s:find("region") then
        return 48
    end
    local arr_n = s:match("%[(%d+)%]")
    if arr_n then
        return tonumber(arr_n) or 48
    end
    return 48
end
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
    elseif k_clean:find("getprocaddress") then
        local fn = function(hmod, proc_name)
            return win32_fallback(t, tostring(proc_name or ""))
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getmodulefilename") then
        local fn = function(mod, buf, cap) return 12 end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("queryperformancefrequency") then
        local fn = function(lpFreq)
            if type(lpFreq) == "table" then pcall(function() lpFreq[0] = 10000000 end) end
            return 1
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("queryperformancecounter") then
        local fn = function(lpCount)
            if type(lpCount) == "table" then pcall(function() lpCount[0] = floor(os.clock() * 10000000) end) end
            return 1
        end
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
    elseif k_clean:find("getfilesizeex") then
        local fn = function(hFile, lpFileSize)
            if type(lpFileSize) == "table" then pcall(function() lpFileSize[0] = 4096 end) end
            return 1
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("readfile") then
        local fn = function(hFile, lpBuf, nBytesToRead, lpBytesRead, lpOverlapped)
            if type(lpBytesRead) == "table" then pcall(function() lpBytesRead[0] = 0 end) end
            return 1
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("writefile") then
        local fn = function(hFile, lpBuf, nBytesToWrite, lpBytesWritten, lpOverlapped)
            if type(lpBytesWritten) == "table" then pcall(function() lpBytesWritten[0] = tonumber(nBytesToWrite) or 0 end) end
            return 1
        end
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
    QueryPerformanceCounter = function(lpPerformanceCount)
        if type(lpPerformanceCount) == "table" then
            pcall(function() lpPerformanceCount[0] = floor(os.clock() * 10000000) end)
        end
        return 1
    end,
    QueryPerformanceFrequency = function(lpFrequency)
        if type(lpFrequency) == "table" then
            pcall(function() lpFrequency[0] = 10000000 end)
        end
        return 1
    end,
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

local native_ffi = rawget(_G, "ffi")
if type(native_ffi) ~= "table" and package and package.preload and type(package.preload["ffi"]) == "function" then
    local ok, res = pcall(package.preload["ffi"])
    if ok and type(res) == "table" then native_ffi = res end
end
if type(native_ffi) == "table" and type(native_ffi.cdef) == "function" and type(native_ffi.new) == "function" then
    pcall(native_ffi.cdef, [[
        typedef struct {
            void* BaseAddress;
            void* AllocationBase;
            uint32_t AllocationProtect;
            uint16_t PartitionId;
            size_t RegionSize;
            uint32_t State;
            uint32_t Protect;
            uint32_t Type;
        } MEMORY_BASIC_INFORMATION;
        void* GetCurrentProcess(void);
        uint32_t GetCurrentProcessId(void);
        uint32_t GetCurrentThreadId(void);
        uint64_t GetTickCount64(void);
        uint32_t GetTickCount(void);
        int QueryPerformanceCounter(int64_t* lpPerformanceCount);
        int QueryPerformanceFrequency(int64_t* lpFrequency);
        size_t VirtualQuery(const void* lpAddress, MEMORY_BASIC_INFORMATION* lpBuffer, size_t dwLength);
        int ReadProcessMemory(void* hProcess, const void* lpBaseAddress, void* lpBuffer, size_t nSize, size_t* lpNumberOfBytesRead);
    ]])
    ffi = native_ffi
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
    failed_mods = {},
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
    menu_tab = 1,         -- 1 = Mod Options, 2 = Key Bindings, 3 = Loaded Mods
    menu_selected = 1,
    menu_mod_filter = 1,  -- 1 = All Mods, 2+ = specific mod category
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
                return true
            end,
            flush = function() return true end,
            close = function() return true end
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
local function resolve_text(v, fallback)
    if type(v) == "function" then
        local ok, res = pcall(v)
        if ok and res ~= nil then
            return tostring(res)
        end
        return fallback or ""
    elseif v ~= nil then
        return tostring(v)
    end
    return fallback or ""
end

local function snap_slider_value(spec, val)
    local num = tonumber(val)
    if num == nil then
        num = tonumber(spec and spec.default) or tonumber(spec and spec.min) or 0
    end
    local min_v = tonumber(spec and spec.min)
    local max_v = tonumber(spec and spec.max)
    local step = tonumber(spec and spec.step) or 1
    if step <= 0 then step = 1 end
    if min_v and max_v and min_v > max_v then
        min_v, max_v = max_v, min_v
    end
    if min_v ~= nil then
        num = min_v + floor((num - min_v) / step + 0.5) * step
    else
        num = floor(num / step + 0.5) * step
    end
    if min_v ~= nil and num < min_v then num = min_v end
    if max_v ~= nil and num > max_v then num = max_v end
    num = tonumber(format("%.6f", num)) or num
    return num
end

local function normalize_option_value(spec, val)
    if type(spec) ~= "table" then return val end
    local otype = spec.type
    if otype == "toggle" or otype == "boolean" or (otype == nil and type(spec.default) == "boolean") then
        if val == nil then return spec.default == true end
        return val == true
    elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
        local count = (type(spec.choices) == "table") and #spec.choices or 0
        if count == 0 then return 1 end
        if type(val) == "number" then
            local idx = floor(val)
            if idx >= 1 and idx <= count then return idx end
        elseif type(val) == "string" then
            local as_num = tonumber(val)
            if as_num then
                local idx = floor(as_num)
                if idx >= 1 and idx <= count then return idx end
            end
            for i = 1, count do
                local c = spec.choices[i]
                if c == val or resolve_text(c, "") == val then
                    return i
                end
            end
        end
        local def = tonumber(spec.default)
        if def then
            local idx = floor(def)
            if idx >= 1 and idx <= count then return idx end
        end
        return 1
    elseif otype == "slider" or otype == "number" or type(spec.default) == "number" then
        return snap_slider_value(spec, val)
    end
    if val ~= nil then return val end
    return spec.default
end

local ModOptionsMenu
ModOptionsMenu = {
    api = 1,
    version = 2,
    revision = 1,
    registered = {},
    order = {},
    values = {},
    change_callbacks = {},
    register_option = function(id, spec)
        if type(id) ~= "string" or id == "" or type(spec) ~= "table" then
            return false, "invalid args"
        end
        if ModOptionsMenu.registered[id] == nil then
            ModOptionsMenu.order[#ModOptionsMenu.order + 1] = id
        end
        ModOptionsMenu.registered[id] = spec
        ModOptionsMenu.values[id] = normalize_option_value(spec, ModOptionsMenu.values[id])
        if type(spec.on_change) == "function" and ModOptionsMenu.change_callbacks[id] == nil then
            ModOptionsMenu.change_callbacks[id] = spec.on_change
        end
        ModOptionsMenu.revision = (ModOptionsMenu.revision or 1) + 1
        return true
    end,
    get = function(id)
        local spec = ModOptionsMenu.registered[id]
        local val = ModOptionsMenu.values[id]
        if spec then
            return normalize_option_value(spec, val)
        end
        return val
    end,
    set = function(id, val)
        local spec = ModOptionsMenu.registered[id]
        local norm = spec and normalize_option_value(spec, val) or val
        ModOptionsMenu.values[id] = norm
        ModOptionsMenu.revision = (ModOptionsMenu.revision or 1) + 1
        local cb = ModOptionsMenu.change_callbacks[id]
        if type(cb) == "function" then
            pcall(cb, norm, id)
        end
        if save_persistent_settings then
            save_persistent_settings()
        end
        return true
    end,
    reset_option = function(id)
        local spec = ModOptionsMenu.registered[id]
        if not spec then return false end
        return ModOptionsMenu.set(id, spec.default)
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
    if lower == "" or lower == "none" then return "NONE" end
    return KEY_ALIASES[lower] or lower
end

function ModBindingsMenu.register_binding(id, label, slot, options)
    if type(id) ~= "string" or id == "" then return false, "invalid id" end
    local existing = ModBindingsMenu.registry[id]
    if existing then
        existing.raw_label = label
        existing.label = resolve_text(label, id)
        if options and options.category ~= nil then
            existing.raw_category = options.category
            existing.category = resolve_text(options.category, "General")
        end
        return true
    end

    local raw_cat = options and options.category or "General"
    local text = resolve_text(label, id)
    local category = resolve_text(raw_cat, "General")
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
        raw_label = label,
        label = text,
        raw_category = raw_cat,
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

function ModBindingsMenu.reset_binding(id)
    local rec = ModBindingsMenu.registry[id]
    if not rec then return false end
    return ModBindingsMenu.set_binding(id, rec.default or "NONE")
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
        UniversalState.failed_mods[mod_name] = {
            name = mod_name,
            archive = archive_name,
            status = "compile_error",
            error = tostring(err)
        }
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
        UniversalState.failed_mods[mod_name] = {
            name = mod_name,
            archive = archive_name,
            status = "runtime_error",
            error = tostring(res)
        }
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
-- 14. INTERACTIVE IN-GAME OVERLAY (F2 / F9 / 3-TAB STINGRAY SCREEN-GUI)
-- ==============================================================================
local UI_FONT = "core/performance_hud/debug"
local UI_GFX = {
    gui = nil,
    world = nil,
    rect_ids = {},
    text_ids = {},
    last_sig = nil
}

local COMMON_SCAN_KEYS = {
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "space", "left shift", "right shift", "left ctrl", "right ctrl", "left alt", "right alt",
    "up", "down", "left", "right", "insert", "home", "end", "page up", "page down",
    "mouse_middle", "mouse_extra_1", "mouse_extra_2"
}

local function is_stingray_retained_gui(sr)
    return sr and sr.World and type(sr.World.create_screen_gui) == "function"
        and type(sr.Vector3) == "function" and type(sr.Vector2) == "function" and type(sr.Color) == "function"
end

local function ui_world_alive(sr, w)
    if not w then return false end
    local app = sr and sr.Application
    if not app or type(app.worlds) ~= "function" then return true end
    local ok, worlds = pcall(app.worlds)
    if not ok or type(worlds) ~= "table" then return true end
    for i = 1, #worlds do
        if worlds[i] == w then return true end
    end
    return false
end

local function ui_find_world(sr)
    local app = sr and sr.Application
    if not app then return nil end
    local main_w = (type(app.main_world) == "function") and select(2, pcall(app.main_world)) or nil
    if type(app.worlds) == "function" then
        local ok, worlds = pcall(app.worlds)
        if ok and type(worlds) == "table" then
            for i = #worlds, 1, -1 do
                if worlds[i] ~= main_w then return worlds[i] end
            end
            if worlds[1] then return worlds[1] end
        end
    end
    return main_w
end

local function ui_gfx_clear(sr)
    if not UI_GFX.gui then
        UI_GFX.rect_ids = {}
        UI_GFX.text_ids = {}
        UI_GFX.last_sig = nil
        return
    end
    if not ui_world_alive(sr, UI_GFX.world) then
        UI_GFX.gui = nil
        UI_GFX.world = nil
        UI_GFX.rect_ids = {}
        UI_GFX.text_ids = {}
        UI_GFX.last_sig = nil
        return
    end
    local g = sr and sr.Gui
    if g then
        if type(g.destroy_rect) == "function" then
            for i = #UI_GFX.rect_ids, 1, -1 do
                pcall(g.destroy_rect, UI_GFX.gui, UI_GFX.rect_ids[i])
            end
        end
        if type(g.destroy_text) == "function" then
            for i = #UI_GFX.text_ids, 1, -1 do
                pcall(g.destroy_text, UI_GFX.gui, UI_GFX.text_ids[i])
            end
        end
    end
    UI_GFX.rect_ids = {}
    UI_GFX.text_ids = {}
    UI_GFX.last_sig = nil
end

local function ui_gfx_release(sr)
    ui_gfx_clear(sr)
    if UI_GFX.gui and UI_GFX.world and ui_world_alive(sr, UI_GFX.world) then
        if sr and sr.World and type(sr.World.destroy_gui) == "function" then
            pcall(sr.World.destroy_gui, UI_GFX.world, UI_GFX.gui)
        end
    end
    UI_GFX.gui = nil
    UI_GFX.world = nil
    UI_GFX.last_sig = nil
end

local function ui_gfx_ensure(sr)
    if UI_GFX.gui and ui_world_alive(sr, UI_GFX.world) then
        return true
    end
    UI_GFX.gui = nil
    UI_GFX.world = nil
    UI_GFX.rect_ids = {}
    UI_GFX.text_ids = {}
    UI_GFX.last_sig = nil
    local w = ui_find_world(sr)
    if not w then return false end
    local ok, gui = pcall(sr.World.create_screen_gui, w, "scale", 1, 1)
    if ok and gui then
        UI_GFX.gui = gui
        UI_GFX.world = w
        return true
    end
    return false
end

local function get_mod_option_categories()
    local categories = { "ALL MODS" }
    local mod_names = {}
    local seen_mods = {}
    local by_cat = { ["ALL MODS"] = {} }

    local ordered_ids = {}
    local seen_ids = {}
    for i = 1, #ModOptionsMenu.order do
        local id = ModOptionsMenu.order[i]
        if ModOptionsMenu.registered[id] and not seen_ids[id] then
            ordered_ids[#ordered_ids + 1] = id
            seen_ids[id] = true
        end
    end
    local extra_ids = {}
    for id in pairs(ModOptionsMenu.registered) do
        if not seen_ids[id] then extra_ids[#extra_ids + 1] = id end
    end
    sort(extra_ids)
    for i = 1, #extra_ids do
        ordered_ids[#ordered_ids + 1] = extra_ids[i]
    end

    for i = 1, #ordered_ids do
        local id = ordered_ids[i]
        local spec = ModOptionsMenu.registered[id]
        local mod_name = resolve_text(spec and (spec.mod or spec.category or spec.mod_id), "General")
        if mod_name == "" then mod_name = "General" end
        if not seen_mods[mod_name] then
            seen_mods[mod_name] = true
            mod_names[#mod_names + 1] = mod_name
            by_cat[mod_name] = {}
        end
        by_cat["ALL MODS"][#by_cat["ALL MODS"] + 1] = id
        by_cat[mod_name][#by_cat[mod_name] + 1] = id
    end

    sort(mod_names)
    for i = 1, #mod_names do
        categories[#categories + 1] = mod_names[i]
    end
    return categories, by_cat
end

local function get_loaded_mods_list()
    local list = {}
    for name, info in pairs(UniversalState.active_mods) do
        if type(info) == "table" then
            list[#list + 1] = {
                name = info.name or name,
                archive = info.archive or "patch",
                status = info.status or "loaded",
                error = info.error
            }
        else
            list[#list + 1] = {
                name = tostring(name),
                archive = "runtime",
                status = "loaded"
            }
        end
    end
    for name, info in pairs(UniversalState.failed_mods) do
        if type(info) == "table" then
            list[#list + 1] = {
                name = info.name or name,
                archive = info.archive or "patch",
                status = info.status or "error",
                error = info.error
            }
        end
    end
    sort(list, function(a, b)
        local pa = tonumber(tostring(a.archive):match("patch_(%d+)$")) or 999
        local pb = tonumber(tostring(b.archive):match("patch_(%d+)$")) or 999
        if pa ~= pb then return pa < pb end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

local function format_option_value(spec, val)
    if type(spec) ~= "table" then return tostring(val), 220, 225, 235 end
    local otype = spec.type
    if otype == "toggle" or otype == "boolean" or (otype == nil and type(val) == "boolean") then
        if val == true then
            return "[  ON  ]", 90, 235, 130
        else
            return "[ OFF  ]", 200, 110, 110
        end
    elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
        local count = #spec.choices
        local idx = normalize_option_value(spec, val)
        local choice_lbl = resolve_text(spec.choices[idx], tostring(idx))
        return format("< %s (%d/%d) >", choice_lbl, idx, count), 245, 210, 85
    elseif otype == "slider" or otype == "number" or type(val) == "number" then
        local num = tonumber(val) or 0
        local min_v = tonumber(spec.min)
        local max_v = tonumber(spec.max)
        if min_v and max_v and max_v > min_v then
            local ratio = (num - min_v) / (max_v - min_v)
            if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
            local filled = floor(ratio * 10 + 0.5)
            local bar = string.rep("#", filled) .. string.rep("-", 10 - filled)
            return format("[%s] %s", bar, tostring(num)), 110, 210, 250
        else
            return format("< %s >", tostring(num)), 110, 210, 250
        end
    end
    return tostring(val), 220, 225, 235
end

local function format_default_value(spec)
    if type(spec) ~= "table" or spec.default == nil then return "N/A" end
    local otype = spec.type
    if otype == "toggle" or otype == "boolean" or type(spec.default) == "boolean" then
        return (spec.default == true) and "ON" or "OFF"
    elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
        local idx = normalize_option_value(spec, spec.default)
        return resolve_text(spec.choices[idx], tostring(idx))
    end
    return tostring(spec.default)
end

local function wrap_text_lines(text, max_chars, max_lines)
    local clean = tostring(text or ""):gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return { "No description provided." } end
    local lines = {}
    local pos = 1
    local len = #clean
    while pos <= len and #lines < max_lines do
        if len - pos + 1 <= max_chars then
            lines[#lines + 1] = clean:sub(pos)
            break
        end
        local slice = clean:sub(pos, pos + max_chars)
        local split = slice:match("^.*()%s")
        if not split or split < floor(max_chars * 0.4) then
            split = max_chars
            lines[#lines + 1] = clean:sub(pos, pos + split - 1)
            pos = pos + split
        else
            lines[#lines + 1] = clean:sub(pos, pos + split - 2)
            pos = pos + split
        end
    end
    return lines
end

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
        if not UniversalState.menu_visible then
            ui_gfx_clear(sr)
        end
        return
    end

    if not UniversalState.menu_visible then return end

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

    if key_pressed("escape") then
        UniversalState.menu_visible = false
        ui_gfx_clear(sr)
        return
    end

    -- Tab switching (1: Mod Options, 2: Key Bindings, 3: Loaded Mods)
    if key_pressed("tab") then
        UniversalState.menu_tab = ((UniversalState.menu_tab or 1) % 3) + 1
        UniversalState.menu_selected = 1
        return
    elseif key_pressed("1") then
        UniversalState.menu_tab = 1
        UniversalState.menu_selected = 1
        return
    elseif key_pressed("2") then
        UniversalState.menu_tab = 2
        UniversalState.menu_selected = 1
        return
    elseif key_pressed("3") then
        UniversalState.menu_tab = 3
        UniversalState.menu_selected = 1
        return
    end

    -- TAB 1: MOD OPTIONS
    if UniversalState.menu_tab == 1 then
        local categories, by_cat = get_mod_option_categories()
        local cat_idx = UniversalState.menu_mod_filter or 1
        if cat_idx < 1 or cat_idx > #categories then
            cat_idx = 1
            UniversalState.menu_mod_filter = 1
        end

        if key_pressed("q") or key_pressed("page up") then
            cat_idx = cat_idx - 1
            if cat_idx < 1 then cat_idx = #categories end
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_selected = 1
            return
        elseif key_pressed("e") or key_pressed("page down") then
            cat_idx = (cat_idx % #categories) + 1
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_selected = 1
            return
        end

        local active_cat = categories[cat_idx] or "ALL MODS"
        local opt_keys = by_cat[active_cat] or {}
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
            local reset_def = key_pressed("backspace")

            if reset_def then
                ModOptionsMenu.reset_option(cur_id)
                return
            end

            local otype = spec and spec.type
            if otype == "toggle" or otype == "boolean" or (otype == nil and type(cur_val) == "boolean") then
                if toggle or step_left or step_right then
                    ModOptionsMenu.set(cur_id, not cur_val)
                end
            elseif otype == "choice" or (spec and type(spec.choices) == "table" and #spec.choices > 0) then
                local count = #spec.choices
                local cur_idx = normalize_option_value(spec, cur_val)
                if toggle or step_right then
                    cur_idx = (cur_idx % count) + 1
                    ModOptionsMenu.set(cur_id, cur_idx)
                elseif step_left then
                    cur_idx = cur_idx - 1
                    if cur_idx < 1 then cur_idx = count end
                    ModOptionsMenu.set(cur_id, cur_idx)
                end
            elseif otype == "slider" or otype == "number" or type(cur_val) == "number" then
                local step = tonumber(spec and spec.step) or 1
                local num = tonumber(cur_val) or 0
                if step_left then
                    ModOptionsMenu.set(cur_id, snap_slider_value(spec, num - step))
                elseif step_right or toggle then
                    ModOptionsMenu.set(cur_id, snap_slider_value(spec, num + step))
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
        elseif key_pressed("page up") then
            UniversalState.menu_selected = math.max(1, (UniversalState.menu_selected or 1) - 12)
        elseif key_pressed("page down") then
            UniversalState.menu_selected = math.min(#bind_list, (UniversalState.menu_selected or 1) + 12)
        end

        local sel = UniversalState.menu_selected or 1
        if sel > #bind_list then sel = #bind_list; UniversalState.menu_selected = sel end
        local record = bind_list[sel]
        if record then
            if key_pressed("enter") or key_pressed("space") then
                UniversalState.menu_rebind_id = record.id
            elseif key_pressed("backspace") then
                ModBindingsMenu.reset_binding(record.id)
            end
        end

    -- TAB 3: LOADED MODS & DIAGNOSTICS
    elseif UniversalState.menu_tab == 3 then
        local mods_list = get_loaded_mods_list()
        if #mods_list == 0 then return end

        if key_pressed("up") then
            UniversalState.menu_selected = math.max(1, (UniversalState.menu_selected or 1) - 1)
        elseif key_pressed("down") then
            UniversalState.menu_selected = math.min(#mods_list, (UniversalState.menu_selected or 1) + 1)
        elseif key_pressed("page up") then
            UniversalState.menu_selected = math.max(1, (UniversalState.menu_selected or 1) - 12)
        elseif key_pressed("page down") then
            UniversalState.menu_selected = math.min(#mods_list, (UniversalState.menu_selected or 1) + 12)
        end
    end
end

local function draw_menu_overlay()
    local sr = rawget(_G, "stingray")
    if not UniversalState.menu_visible then
        if UI_GFX.gui or #UI_GFX.rect_ids > 0 or #UI_GFX.text_ids > 0 then
            ui_gfx_clear(sr)
        end
        return
    end
    if not sr or not sr.Gui or not sr.Gui.rect then return end

    local retained_mode = is_stingray_retained_gui(sr)
    local W, H = 1920, 1080
    if type(sr.Gui.resolution) == "function" then
        local ok, rw, rh = pcall(sr.Gui.resolution)
        if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then
            W, H = rw, rh
        end
    end

    local categories, by_cat = get_mod_option_categories()
    local total_opts = #(by_cat["ALL MODS"] or {})
    local total_binds = #ModBindingsMenu.order
    local mods_list = get_loaded_mods_list()
    local total_mods = #mods_list

    if retained_mode then
        if not ui_gfx_ensure(sr) then return end
        local sel_bind_down = false
        if UniversalState.menu_tab == 2 then
            local rec = ModBindingsMenu.order[UniversalState.menu_selected or 1]
            if rec then sel_bind_down = ModBindingsMenu.is_down(rec.id) end
        end
        local sig = format("%d:%d:%d:%d:%d:%s:%d:%d:%d:%s",
            W, H,
            UniversalState.menu_tab or 1,
            UniversalState.menu_selected or 1,
            UniversalState.menu_mod_filter or 1,
            tostring(UniversalState.menu_rebind_id or ""),
            ModOptionsMenu.revision or 1,
            ModBindingsMenu.revision or 1,
            total_mods,
            tostring(sel_bind_down)
        )
        if UI_GFX.last_sig == sig then
            return
        end
        ui_gfx_clear(sr)
        UI_GFX.last_sig = sig
    end

    local scale = H / 1080
    local ox = floor((W - 1920 * scale) * 0.5)

    local function draw_rect(x, y, w, h, r, g, b, a, layer)
        if retained_mode then
            local sx = floor(ox + x * scale)
            local sy_top = floor(y * scale)
            local sw = math.max(1, floor(w * scale))
            local sh = math.max(1, floor(h * scale))
            local pos = sr.Vector3(sx, H - sy_top - sh, layer or 960)
            local sz = sr.Vector2(sw, sh)
            local col = sr.Color(a or 255, r or 255, g or 255, b or 255)
            local ok, id = pcall(sr.Gui.rect, UI_GFX.gui, pos, sz, col)
            if ok and id then UI_GFX.rect_ids[#UI_GFX.rect_ids + 1] = id end
        else
            pcall(sr.Gui.rect, x, y, w, h, r, g, b, a)
        end
    end

    local function draw_text(str, x, y, font_size, r, g, b, a, layer)
        if retained_mode then
            local sx = floor(ox + x * scale)
            local sy = floor(H - y * scale)
            local fsize = math.max(10, floor((font_size or 16) * scale))
            local pos = sr.Vector3(sx, sy, layer or 970)
            local col = sr.Color(a or 255, r or 255, g or 255, b or 255)
            local ok, id = pcall(sr.Gui.text, UI_GFX.gui, tostring(str or ""), UI_FONT, fsize, UI_FONT, pos, col)
            if ok and id then UI_GFX.text_ids[#UI_GFX.text_ids + 1] = id end
        else
            pcall(sr.Gui.text, tostring(str or ""), x, y, font_size, r, g, b, a)
        end
    end

    -- Window Frame (1200x860 centered on 1920x1080 canvas at X=360, Y=110)
    draw_rect(356, 106, 1208, 868, 235, 195, 45, 220, 955) -- Gold outer border
    draw_rect(360, 110, 1200, 860, 14, 18, 25, 242, 956)   -- Main dark background
    draw_rect(360, 110, 1200, 52, 24, 32, 46, 250, 958)    -- Title bar background
    draw_rect(360, 160, 1200, 2, 235, 195, 45, 255, 959)   -- Title accent rule

    draw_text("UNIVERSAL MOD LOADER v22.0.0", 385, 143, 22, 255, 215, 55, 255, 970)
    draw_text("[F2 / F9 / Esc] Close    [Tab / 1-3] Switch Tab", 1130, 142, 15, 185, 198, 215, 255, 970)

    -- 3-Tab Navigation Bar (Y=172..208)
    local tab = UniversalState.menu_tab or 1
    local tab_specs = {
        { idx = 1, x = 385, w = 360, label = format("[1] MOD OPTIONS (%d)", total_opts) },
        { idx = 2, x = 760, w = 360, label = format("[2] KEY BINDINGS (%d)", total_binds) },
        { idx = 3, x = 1135, w = 400, label = format("[3] LOADED MODS (%d)", total_mods) }
    }
    for i = 1, #tab_specs do
        local ts = tab_specs[i]
        local active = (tab == ts.idx)
        draw_rect(ts.x, 172, ts.w, 34, active and 48 or 24, active and 72 or 30, active and 106 or 42, 240, 960)
        if active then
            draw_rect(ts.x, 203, ts.w, 3, 255, 215, 55, 255, 962)
        end
        draw_text(ts.label, ts.x + 18, 195, 16, active and 255 or 165, active and 240 or 175, active and 180 or 190, 255, 970)
    end

    -- ==========================================================================
    -- TAB 1: MOD OPTIONS (WITH MOD CATEGORY FILTER & DESCRIPTION PANEL)
    -- ==========================================================================
    if tab == 1 then
        local cat_idx = UniversalState.menu_mod_filter or 1
        if cat_idx < 1 or cat_idx > #categories then
            cat_idx = 1
            UniversalState.menu_mod_filter = 1
        end
        local active_cat = categories[cat_idx] or "ALL MODS"
        local opt_keys = by_cat[active_cat] or {}
        local total = #opt_keys
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        -- Mod Filter Sub-Header (Y=216..250)
        draw_rect(385, 216, 1150, 34, 22, 28, 38, 240, 960)
        draw_text("MOD FILTER [Q / E or PgUp / PgDn]:", 402, 238, 15, 170, 185, 205, 255, 970)
        draw_text(format("<  %s  (%d / %d Categories | %d Options)  >", active_cat, cat_idx, #categories, total),
            720, 238, 16, 255, 215, 65, 255, 970)

        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)
        local y = 262

        for i = start_idx, end_idx do
            local id = opt_keys[i]
            local spec = ModOptionsMenu.registered[id]
            local val = ModOptionsMenu.get(id)
            local is_sel = (i == sel)

            local mod_prefix = resolve_text(spec and (spec.mod or spec.category or spec.mod_id), "Mod")
            local opt_label = resolve_text(spec and spec.label, id)
            local row_title = (active_cat == "ALL MODS")
                and format("[%s]  %s", mod_prefix, opt_label)
                or opt_label
            if #row_title > 62 then
                row_title = row_title:sub(1, 59) .. "..."
            end

            local val_str, vr, vg, vb = format_option_value(spec, val)

            if is_sel then
                draw_rect(385, y, 1150, 31, 40, 68, 102, 235, 961)
                draw_rect(385, y, 4, 31, 255, 215, 55, 255, 962)
                draw_text("> " .. row_title, 400, y + 21, 16, 255, 255, 255, 255, 970)
            else
                if (i % 2) == 0 then
                    draw_rect(385, y, 1150, 31, 18, 24, 34, 190, 960)
                end
                draw_text("  " .. row_title, 400, y + 21, 16, 195, 205, 218, 255, 970)
            end
            draw_text(val_str, 1180, y + 21, 16, vr, vg, vb, 255, 970)
            y = y + 34
        end

        if total == 0 then
            draw_text("No configurable mod options registered in this category.", 405, 310, 17, 160, 170, 180, 255, 970)
        end

        -- Bottom Description & Metadata Panel (Y=685..915)
        draw_rect(385, 685, 1150, 230, 20, 26, 36, 245, 960)
        draw_rect(385, 685, 1150, 2, 70, 105, 150, 255, 962)

        local sel_id = opt_keys[sel]
        local sel_spec = sel_id and ModOptionsMenu.registered[sel_id]
        if sel_spec then
            local sel_mod = resolve_text(sel_spec.mod or sel_spec.category or sel_spec.mod_id, "General")
            local sel_lbl = resolve_text(sel_spec.label, sel_id)
            local def_str = format_default_value(sel_spec)
            local desc_str = resolve_text(sel_spec.description or sel_spec.tooltip or sel_spec.help, "No description provided for this option.")

            draw_text(format("OPTION DETAILS:  [%s] %s", sel_mod, sel_lbl), 405, 712, 16, 255, 215, 65, 255, 970)
            draw_text(format("ID: %s   |   Default: %s   |   [Backspace] Reset to Default", tostring(sel_id), def_str),
                405, 738, 14, 155, 175, 198, 255, 970)

            local desc_lines = wrap_text_lines(desc_str, 102, 4)
            local dy = 772
            for li = 1, #desc_lines do
                draw_text(desc_lines[li], 405, dy, 15, 220, 228, 238, 255, 970)
                dy = dy + 24
            end
        else
            draw_text("OPTION DETAILS", 405, 712, 16, 255, 215, 65, 255, 970)
            draw_text("Select an option above to inspect its description and default value.", 405, 745, 15, 170, 180, 190, 255, 970)
        end

        local total_pages = math.max(1, math.ceil(total / page_size))
        draw_text(format("Page %d / %d (%d options)   |   Up/Down: Select   |   Left/Right/Enter: Change   |   Q/E: Filter Mod   |   Backspace: Reset",
            page + 1, total_pages, total), 385, 945, 14, 165, 180, 198, 255, 970)

    -- ==========================================================================
    -- TAB 2: KEY BINDINGS (WITH INTERACTIVE REBINDING & LIVE STATUS)
    -- ==========================================================================
    elseif tab == 2 then
        local bind_list = ModBindingsMenu.order
        local total = #bind_list
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        draw_rect(385, 216, 1150, 34, 22, 28, 38, 240, 960)
        draw_text("REGISTERED KEYBINDINGS   --   [Enter / Space] Rebind Key   |   [Backspace] Reset to Default",
            402, 238, 15, 200, 215, 230, 255, 970)

        local page_size = 13
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)
        local y = 262

        for i = start_idx, end_idx do
            local record = bind_list[i]
            local current_key = ModBindingsMenu.binding(record.id)
            local is_sel = (i == sel)
            local is_rebinding = (UniversalState.menu_rebind_id == record.id)
            local cat_str = resolve_text(record.raw_category or record.category, "General")
            local lbl_str = resolve_text(record.raw_label or record.label, record.id)
            local row_title = format("[%s]  %s", cat_str, lbl_str)
            if #row_title > 62 then row_title = row_title:sub(1, 59) .. "..." end

            if is_rebinding then
                draw_rect(385, y, 1150, 32, 175, 95, 20, 240, 961)
                draw_rect(385, y, 4, 32, 255, 230, 120, 255, 962)
                draw_text(">> " .. row_title, 400, y + 22, 16, 255, 250, 210, 255, 970)
                draw_text(">> PRESS ANY KEY (Esc: Cancel, Del: Unbind) <<", 1040, y + 22, 15, 255, 240, 150, 255, 970)
            elseif is_sel then
                draw_rect(385, y, 1150, 32, 40, 68, 102, 235, 961)
                draw_rect(385, y, 4, 32, 255, 215, 55, 255, 962)
                draw_text("> " .. row_title, 400, y + 22, 16, 255, 255, 255, 255, 970)
                draw_text(format("[ %s ]", tostring(current_key):upper()), 1220, y + 22, 16, 255, 215, 65, 255, 970)
            else
                if (i % 2) == 0 then
                    draw_rect(385, y, 1150, 32, 18, 24, 34, 190, 960)
                end
                draw_text("  " .. row_title, 400, y + 22, 16, 195, 205, 218, 255, 970)
                draw_text(format("[ %s ]", tostring(current_key):upper()), 1220, y + 22, 16, 130, 205, 245, 255, 970)
            end
            y = y + 35
        end

        if total == 0 then
            draw_text("No configurable keybindings registered.", 405, 310, 17, 160, 170, 180, 255, 970)
        end

        -- Bottom Binding Details Panel (Y=730..915)
        draw_rect(385, 730, 1150, 185, 20, 26, 36, 245, 960)
        draw_rect(385, 730, 1150, 2, 70, 105, 150, 255, 962)

        local sel_rec = bind_list[sel]
        if sel_rec then
            local cat_str = resolve_text(sel_rec.raw_category or sel_rec.category, "General")
            local lbl_str = resolve_text(sel_rec.raw_label or sel_rec.label, sel_rec.id)
            local cur_k = tostring(ModBindingsMenu.binding(sel_rec.id)):upper()
            local def_k = tostring(sel_rec.default or "NONE"):upper()
            local live_down = ModBindingsMenu.is_down(sel_rec.id) and "PRESSED (DOWN)" or "IDLE (UP)"

            draw_text(format("BINDING DETAILS:  [%s] %s", cat_str, lbl_str), 405, 760, 16, 255, 215, 65, 255, 970)
            draw_text(format("Binding ID: %s   |   Current Key: [%s]   |   Default Key: [%s]   |   Live State: %s",
                tostring(sel_rec.id), cur_k, def_k, live_down), 405, 792, 15, 210, 220, 232, 255, 970)
            draw_text("Press [Enter] or [Space] to assign a new key/mouse button. While rebinding, press [Delete] to unbind or [Escape] to cancel.",
                405, 830, 14, 160, 178, 196, 255, 970)
        end

        local total_pages = math.max(1, math.ceil(total / page_size))
        draw_text(format("Page %d / %d (%d bindings)   |   Up/Down: Select   |   Enter/Space: Rebind   |   Backspace: Reset Default",
            page + 1, total_pages, total), 385, 945, 14, 165, 180, 198, 255, 970)

    -- ==========================================================================
    -- TAB 3: LOADED MODS & DIAGNOSTICS
    -- ==========================================================================
    elseif tab == 3 then
        local total = #mods_list
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        local loaded_cnt, builtin_cnt, err_cnt = 0, 0, 0
        for i = 1, total do
            local st = mods_list[i].status
            if st == "loaded" then loaded_cnt = loaded_cnt + 1
            elseif st == "superseded_by_builtin" then builtin_cnt = builtin_cnt + 1
            else err_cnt = err_cnt + 1 end
        end

        draw_rect(385, 216, 1150, 34, 22, 28, 38, 240, 960)
        draw_text(format("ACTIVE MODS: %d   |   BUILT-IN SUPERSEDED: %d   |   ERRORS: %d   |   UPDATE HOOKS: %d",
            loaded_cnt, builtin_cnt, err_cnt, #update_order), 402, 238, 15, 200, 215, 230, 255, 970)

        local page_size = 13
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)
        local y = 262

        for i = start_idx, end_idx do
            local item = mods_list[i]
            local is_sel = (i == sel)
            local badge, br, bg, bb = "[ ACTIVE ]", 90, 235, 130
            if item.status == "superseded_by_builtin" then
                badge, br, bg, bb = "[ BUILT-IN ]", 110, 210, 250
            elseif item.status ~= "loaded" then
                badge, br, bg, bb = "[ ERROR ]", 240, 95, 95
            end

            if is_sel then
                draw_rect(385, y, 1150, 32, 40, 68, 102, 235, 961)
                draw_rect(385, y, 4, 32, 255, 215, 55, 255, 962)
                draw_text(format("> %s", tostring(item.name)), 400, y + 22, 16, 255, 255, 255, 255, 970)
            else
                if (i % 2) == 0 then
                    draw_rect(385, y, 1150, 32, 18, 24, 34, 190, 960)
                end
                draw_text(format("  %s", tostring(item.name)), 400, y + 22, 16, 195, 205, 218, 255, 970)
            end
            draw_text(tostring(item.archive or "patch"), 980, y + 22, 15, 165, 180, 198, 255, 970)
            draw_text(badge, 1360, y + 22, 15, br, bg, bb, 255, 970)
            y = y + 35
        end

        -- Bottom Mod Diagnostics Panel (Y=730..915)
        draw_rect(385, 730, 1150, 185, 20, 26, 36, 245, 960)
        draw_rect(385, 730, 1150, 2, 70, 105, 150, 255, 962)

        local sel_mod = mods_list[sel]
        if sel_mod then
            draw_text(format("MOD DIAGNOSTICS:  %s", tostring(sel_mod.name)), 405, 760, 16, 255, 215, 65, 255, 970)
            draw_text(format("Source Archive: %s   |   Status: %s", tostring(sel_mod.archive), tostring(sel_mod.status):upper()),
                405, 790, 15, 210, 220, 232, 255, 970)
            if sel_mod.error then
                local err_lines = wrap_text_lines("Error: " .. tostring(sel_mod.error), 102, 2)
                for li = 1, #err_lines do
                    draw_text(err_lines[li], 405, 820 + (li - 1) * 24, 14, 245, 120, 120, 255, 970)
                end
            elseif sel_mod.status == "superseded_by_builtin" then
                draw_text("Standalone menu archive automatically superseded by Universal Mod Loader's built-in MOM v2 / MBM v4 engine.",
                    405, 825, 14, 140, 210, 245, 255, 970)
            else
                draw_text("Mod compiled and initialized cleanly inside isolated multi-standard sandbox (Bingus / Chef / BML / HD2RT).",
                    405, 825, 14, 160, 185, 205, 255, 970)
            end
            draw_text(format("Settings Storage: %s\\settings.json", get_settings_dir()), 405, 880, 13, 135, 150, 168, 255, 970)
        end

        local total_pages = math.max(1, math.ceil(total / page_size))
        draw_text(format("Page %d / %d (%d mods)   |   Up/Down/PgUp/PgDn: Scroll   |   Tab / 1-3: Switch Tab   |   F2/F9: Close",
            page + 1, total_pages, total), 385, 945, 14, 165, 180, 198, 255, 970)
    end
end

-- ==============================================================================
-- 15. ENGINE LIFECYCLE HOOKS (INIT, UPDATE, RENDER, SHUTDOWN)
-- ==============================================================================
UniversalLoader_update = function(dt)
    update_bindings_state()
    handle_menu_input()
    draw_menu_overlay()
end

UniversalLoader_render = function(...)
    local sr = rawget(_G, "stingray")
    if not is_stingray_retained_gui(sr) then
        draw_menu_overlay()
    end
end

UniversalLoader_shutdown = function()
    local sr = rawget(_G, "stingray")
    ui_gfx_release(sr)
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
