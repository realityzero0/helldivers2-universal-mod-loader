-- Universal Mod Loader v22.0.0 for Helldivers 2 (Steam Builds 25988413 / 26088801 / 26251122+ / Lua 5.1)
-- Replaces engine boot resource 0xF476DF93691895FA in bundle 9ba626afa44a3aa3
-- Unifies All Helldivers 2 Modding Standards + Built-in Mod Options & Mod Bindings Menus:
--   1. Bingus Shared Loader (CowboyBingus / v17 / v20 / v21 / API 1 + BingusRuntime v1)
--   2. Chef Shared Loader (Th3chef / API Levels 1, 2, 3)
--   3. Boot Mod Loader (VeganSquid / API 1)
--   4. HD2 Lua Runtime (hd2rt / 0.1.0)
--   5. Built-in Mod Options Menu (MOM v2 / v3) with legacy ModOptionsMenu.values migration
--   6. Built-in Mod Bindings Menu (MBM v4) with Stingray button_id / button_index polling
-- Pure Lua 5.1 compliant (Zero native FFI crashes, Lua 5.2 goto transpiler, EAC-safe, Circuit-Breaker protected).
-- License: Zero-Clause BSD (0BSD)

-- 0. Cooperative handoff to Chef Shared Loader if installed with higher patch priority
local A = rawget(_G, 'stingray') and stingray.Application
if A and type(A.can_get) == 'function' and A.can_get('lua', 'mods/chef_shared_loader/core_1')
    and rawget(_G, 'ChefSharedLoader') == nil then
  rawset(_G, 'ChefSharedLoaderHandoff', { from = 'Universal Mod Loader v22.0.0' })
  local ok, err = pcall(require, 'mods/chef_shared_loader/core_1')
  if ok then return end
end

-- Forward declarations
local save_persistent_settings
local update_bindings_state

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
local handle_update_ran = false
local bindings_polled_this_frame = false

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
    handle_update_ran = true
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
    bindings_polled_this_frame = false
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
if type(native_bit) ~= "table" then
    local ok, res = pcall(require, "bit")
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
package.loaded["bit"] = bit

-- Lua 5.2 / 5.3 Standard Library Polyfills (bit32, table.pack/unpack, utf8)
local bit32 = {
    band = function(...)
        local n = select("#", ...)
        if n == 0 then return 0xFFFFFFFF end
        return to_u32(bit.band(...))
    end,
    bor = function(...)
        local n = select("#", ...)
        if n == 0 then return 0 end
        return to_u32(bit.bor(...))
    end,
    bxor = function(...)
        local n = select("#", ...)
        if n == 0 then return 0 end
        return to_u32(bit.bxor(...))
    end,
    bnot = function(x) return to_u32(bit.bnot(x)) end,
    lshift = function(x, disp)
        disp = tonumber(disp) or 0
        if disp < 0 then return to_u32(bit.rshift(x, -disp)) end
        if disp >= 32 then return 0 end
        return to_u32(bit.lshift(x, disp))
    end,
    rshift = function(x, disp)
        disp = tonumber(disp) or 0
        if disp < 0 then return to_u32(bit.lshift(x, -disp)) end
        if disp >= 32 then return 0 end
        return to_u32(bit.rshift(x, disp))
    end,
    arshift = function(x, disp)
        disp = tonumber(disp) or 0
        if disp < 0 then return to_u32(bit.lshift(x, -disp)) end
        return to_u32(bit.arshift(x, disp))
    end,
    btest = function(...)
        local n = select("#", ...)
        if n == 0 then return true end
        return to_u32(bit.band(...)) ~= 0
    end,
    extract = function(n, field, width)
        width = tonumber(width) or 1
        field = tonumber(field) or 0
        local u = to_u32(n)
        return floor(u / (2 ^ field)) % (2 ^ width)
    end,
    replace = function(n, v, field, width)
        width = tonumber(width) or 1
        field = tonumber(field) or 0
        local u = to_u32(n)
        local mask = (2 ^ width - 1) * (2 ^ field)
        local cleared = to_u32(bit.band(u, bit.bnot(mask)))
        local ins = (to_u32(v) % (2 ^ width)) * (2 ^ field)
        return to_u32(bit.bor(cleared, ins))
    end,
    lrotate = function(x, disp) return to_u32(bit.rol(x, disp)) end,
    rrotate = function(x, disp) return to_u32(bit.ror(x, disp)) end
}
_G.bit32 = rawget(_G, "bit32") or bit32
package.preload["bit32"] = function() return _G.bit32 end
package.loaded["bit32"] = _G.bit32

if type(table.unpack) ~= "function" then
    table.unpack = unpack
end
if type(table.pack) ~= "function" then
    table.pack = function(...)
        return { n = select("#", ...), ... }
    end
end

local utf8_lib
utf8_lib = {
    charpattern = "[\0-\127\194-\244][\128-\191]*",
    char = function(...)
        local out = {}
        local n = select("#", ...)
        for i = 1, n do
            local cp = floor(tonumber(select(i, ...)) or 0)
            if cp < 0 or cp > 0x10FFFF then
                out[#out + 1] = "?"
            elseif cp <= 0x7F then
                out[#out + 1] = char(cp)
            elseif cp <= 0x7FF then
                out[#out + 1] = char(0xC0 + floor(cp / 64), 0x80 + (cp % 64))
            elseif cp <= 0xFFFF then
                out[#out + 1] = char(
                    0xE0 + floor(cp / 4096),
                    0x80 + (floor(cp / 64) % 64),
                    0x80 + (cp % 64)
                )
            else
                out[#out + 1] = char(
                    0xF0 + floor(cp / 262144),
                    0x80 + (floor(cp / 4096) % 64),
                    0x80 + (floor(cp / 64) % 64),
                    0x80 + (cp % 64)
                )
            end
        end
        return concat(out)
    end,
    codepoint = function(s, i, j)
        s = tostring(s or "")
        local len = #s
        i = i or 1
        if i < 0 then i = len + 1 + i end
        j = j or i
        if j < 0 then j = len + 1 + j end
        local res = {}
        local pos = i
        while pos <= j and pos <= len do
            local b1 = byte(s, pos)
            if not b1 then break end
            if b1 < 0x80 then
                res[#res + 1] = b1
                pos = pos + 1
            elseif b1 >= 0xC2 and b1 <= 0xDF then
                local b2 = byte(s, pos + 1) or 0x80
                res[#res + 1] = (b1 - 0xC0) * 64 + (b2 - 0x80)
                pos = pos + 2
            elseif b1 >= 0xE0 and b1 <= 0xEF then
                local b2 = byte(s, pos + 1) or 0x80
                local b3 = byte(s, pos + 2) or 0x80
                res[#res + 1] = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
                pos = pos + 3
            elseif b1 >= 0xF0 and b1 <= 0xF4 then
                local b2 = byte(s, pos + 1) or 0x80
                local b3 = byte(s, pos + 2) or 0x80
                local b4 = byte(s, pos + 3) or 0x80
                res[#res + 1] = (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
                pos = pos + 4
            else
                res[#res + 1] = b1
                pos = pos + 1
            end
        end
        return unpack(res)
    end,
    len = function(s, i, j)
        s = tostring(s or "")
        local len = #s
        i = i or 1
        if i < 0 then i = len + 1 + i end
        j = j or len
        if j < 0 then j = len + 1 + j end
        local count = 0
        local pos = i
        while pos <= j and pos <= len do
            local b1 = byte(s, pos)
            if not b1 then break end
            count = count + 1
            if b1 < 0x80 then pos = pos + 1
            elseif b1 >= 0xC2 and b1 <= 0xDF then pos = pos + 2
            elseif b1 >= 0xE0 and b1 <= 0xEF then pos = pos + 3
            elseif b1 >= 0xF0 and b1 <= 0xF4 then pos = pos + 4
            else pos = pos + 1 end
        end
        return count
    end,
    codes = function(s)
        s = tostring(s or "")
        local len = #s
        local pos = 1
        return function()
            if pos > len then return nil end
            local cur = pos
            local b1 = byte(s, pos)
            local cp = b1
            if b1 < 0x80 then
                pos = pos + 1
            elseif b1 >= 0xC2 and b1 <= 0xDF then
                local b2 = byte(s, pos + 1) or 0x80
                cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
                pos = pos + 2
            elseif b1 >= 0xE0 and b1 <= 0xEF then
                local b2 = byte(s, pos + 1) or 0x80
                local b3 = byte(s, pos + 2) or 0x80
                cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
                pos = pos + 3
            elseif b1 >= 0xF0 and b1 <= 0xF4 then
                local b2 = byte(s, pos + 1) or 0x80
                local b3 = byte(s, pos + 2) or 0x80
                local b4 = byte(s, pos + 3) or 0x80
                cp = (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
                pos = pos + 4
            else
                pos = pos + 1
            end
            return cur, cp
        end
    end,
    offset = function(s, n, i)
        s = tostring(s or "")
        local len = #s
        n = tonumber(n) or 1
        i = i or ((n >= 0) and 1 or (len + 1))
        if i < 0 then i = len + 1 + i end
        if n == 0 then
            while i > 1 do
                local b = byte(s, i)
                if not b or b < 0x80 or b >= 0xC0 then break end
                i = i - 1
            end
            return i
        elseif n > 0 then
            local pos = i
            local rem = n - 1
            while rem > 0 and pos <= len do
                local b1 = byte(s, pos)
                if not b1 then return nil end
                if b1 < 0x80 then pos = pos + 1
                elseif b1 >= 0xC2 and b1 <= 0xDF then pos = pos + 2
                elseif b1 >= 0xE0 and b1 <= 0xEF then pos = pos + 3
                elseif b1 >= 0xF0 and b1 <= 0xF4 then pos = pos + 4
                else pos = pos + 1 end
                rem = rem - 1
            end
            return (pos <= len + 1) and pos or nil
        else
            local pos = i
            local rem = -n
            while rem > 0 and pos > 1 do
                repeat
                    pos = pos - 1
                    local b = byte(s, pos)
                until pos <= 1 or not b or b < 0x80 or b >= 0xC0
                rem = rem - 1
            end
            return (rem == 0) and pos or nil
        end
    end
}
_G.utf8 = rawget(_G, "utf8") or utf8_lib
package.preload["utf8"] = function() return _G.utf8 end
package.loaded["utf8"] = _G.utf8

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

local function murmur64_key(str)
    local l, h = murmurhash64a(str, 0)
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
-- 3. NON-CRASHING FFI / WIN32 COMPATIBILITY STUBS & MOCK POINTERS
-- ==============================================================================
local function u32_le(v)
    local u = to_u32(v)
    return char(u % 256, floor(u / 256) % 256, floor(u / 65536) % 256, floor(u / 16777216) % 256)
end

local function make_synthetic_pe_header(timestamp, image_size, checksum)
    -- 1024-byte valid x64 PE32+ header for offline/sandboxed layout & stamp checks
    local dos = "MZ" .. string.rep("\0", 58) .. u32_le(128) .. string.rep("\0", 64)
    -- COFF header at offset 128 (24 bytes): 'PE\0\0', Machine=0x8664, NumberOfSections=1, TimeDateStamp, ..., SizeOfOptionalHeader=240, Characteristics=0x22
    local coff = "PE\0\0\100\134\1\0" .. u32_le(timestamp) .. string.rep("\0", 8) .. "\240\0\34\0"
    -- Optional header at offset 152 (240 bytes): Magic=0x020B (PE32+), SizeOfImage at +56, SizeOfHeaders at +60, CheckSum at +64
    local opt = "\11\2" .. string.rep("\0", 54) .. u32_le(image_size) .. u32_le(1024) .. u32_le(checksum or 0) .. string.rep("\0", 172)
    -- Section header at offset 392 (40 bytes): '.text', VirtualSize=0x1000, VirtualAddress=0x1000, Characteristics=0x60000020
    local sec = ".text\0\0\0" .. u32_le(4096) .. u32_le(4096) .. string.rep("\0", 20) .. u32_le(0x60000020)
    local hdr = dos .. coff .. opt .. sec
    return hdr .. string.rep("\0", 1024 - #hdr)
end

local GAME_PE_HEADER = make_synthetic_pe_header(1790161983, 74727424, 0xECDA6F)
local EXE_PE_HEADER  = make_synthetic_pe_header(1790149348, 60719104, 0xE48B1D)
local MOCK_EXE_PATH  = [[C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2\bin\helldivers2.exe]]

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
    __call = function(t, ...)
        local fn = rawget(t, "_fn")
        if type(fn) == "function" then
            return fn(...)
        end
        return 0
    end,
    __add = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        local res = setmetatable({ _addr = addr_a + addr_b }, ptr_mt)
        return res
    end,
    __sub = function(a, b)
        local addr_a = (type(a) == "table" and rawget(a, "_addr")) or tonumber(a) or 0
        local addr_b = (type(b) == "table" and rawget(b, "_addr")) or tonumber(b) or 0
        local diff = addr_a - addr_b
        if type(a) == "table" and type(b) == "table" then return diff end
        return setmetatable({ _addr = diff }, ptr_mt)
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

local function make_mock_pointer(addr, fn)
    return setmetatable({ _addr = tonumber(addr) or 0, _fn = fn }, ptr_mt)
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
    if type(ptr) == "string" then
        return len and ptr:sub(1, len) or ptr
    end
    if type(ptr) == "table" and type(rawget(ptr, "_str")) == "string" then
        local s = rawget(ptr, "_str")
        if type(len) == "number" and len > 0 then
            if #s >= len then return s:sub(1, len) end
            return s .. string.rep("\0", len - #s)
        end
        return s
    end
    if type(len) == "number" and len > 0 then
        return string.rep("\0", len)
    end
    return ""
end
function ffi.copy(dst, src, len)
    if type(dst) == "table" and type(src) == "string" then
        rawset(dst, "_str", len and src:sub(1, len) or src)
    end
end
function ffi.fill(dst, len, val)
    if type(dst) == "table" then
        rawset(dst, "_str", nil)
    end
end

local function mock_get_module_handle(name)
    local s = name ~= nil and tostring(name):lower() or ""
    if s:find("game") then
        return make_mock_pointer(0x180000000)
    elseif s:find("kernel32") then
        return make_mock_pointer(0x7FF800000000)
    elseif s:find("bcrypt") then
        return make_mock_pointer(0x7FF810000000)
    end
    return make_mock_pointer(0x140000000)
end

local function mock_read_process_memory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead)
    local addr = (type(lpBaseAddress) == "table" and rawget(lpBaseAddress, "_addr")) or tonumber(lpBaseAddress) or 0
    local sz = tonumber(nSize) or 0
    if type(lpBuffer) == "table" then
        if addr >= 0x180000000 and addr < 0x180000400 then
            local off = addr - 0x180000000
            rawset(lpBuffer, "_str", GAME_PE_HEADER:sub(off + 1, off + sz))
        elseif addr >= 0x140000000 and addr < 0x140000400 then
            local off = addr - 0x140000000
            rawset(lpBuffer, "_str", EXE_PE_HEADER:sub(off + 1, off + sz))
        else
            rawset(lpBuffer, "_str", nil)
        end
    end
    if type(lpNumberOfBytesRead) == "table" then
        pcall(function() lpNumberOfBytesRead[0] = sz end)
    end
    return 1
end

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
        rawset(t, k, mock_get_module_handle)
        return mock_get_module_handle
    elseif k_clean:find("getprocaddress") then
        local fn = function(hmod, proc_name)
            return win32_fallback(t, tostring(proc_name or ""))
        end
        rawset(t, k, fn)
        return fn
    elseif k_clean:find("getmodulefilename") then
        local fn = function(mod, buf, cap)
            if type(buf) == "table" then
                rawset(buf, "_str", MOCK_EXE_PATH)
            end
            return #MOCK_EXE_PATH
        end
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
        rawset(t, k, mock_read_process_memory)
        return mock_read_process_memory
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
    GetModuleHandleA = mock_get_module_handle,
    GetModuleHandleW = mock_get_module_handle,
    VirtualQuery = function() return 0 end,
    ReadProcessMemory = mock_read_process_memory,
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

local has_native_ffi = false
local native_ffi = rawget(_G, "ffi")
if type(native_ffi) ~= "table" then
    local ok, res = pcall(require, "ffi")
    if ok and type(res) == "table" then native_ffi = res end
end
if type(native_ffi) == "table" and type(native_ffi.cdef) == "function" and type(native_ffi.new) == "function" then
    ffi = native_ffi
    has_native_ffi = true
end

_G.ffi = ffi
package.preload["ffi"] = function() return ffi end
package.loaded["ffi"] = ffi

-- Lua 5.1 JIT / jit.util compatibility stubs for mods inspecting jit status
if type(rawget(_G, "jit")) ~= "table" then
    local mock_jit = {
        version = "Lua 5.1.4 (UniversalModLoader)",
        version_num = 20100,
        os = "Windows",
        arch = "x64",
        status = function() return false end,
        on = noop,
        off = noop,
        flush = noop,
        opt = { start = noop }
    }
    _G.jit = mock_jit
    package.preload["jit"] = function() return mock_jit end
    package.loaded["jit"] = mock_jit
end
if not package.preload["jit.util"] and not package.loaded["jit.util"] then
    local mock_jit_util = {
        funcinfo = function() return { loc = "lua", ffid = nil, addr = 0 } end,
        ircalladdr = function() return 0 end,
        traceinfo = function() return nil end
    }
    package.preload["jit.util"] = function() return mock_jit_util end
    package.loaded["jit.util"] = mock_jit_util
end

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
-- 6. BINGUS SHARED LOADER API & BINGUS RUNTIME V1 (V17 / V20 / V21 PARITY)
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
    modules = {},
    addons = UniversalState.addons,
    health = {
        header = {},
        changes = {}
    },
    build = {
        supported = true,
        enforce = false,
        status = "universal"
    },
    jit = {
        managed = false,
        status = "lua51"
    },
    register_module = function(name, value)
        if type(name) ~= "string" or name == "" then return false end
        CowboyBingusModLoader.modules[name] = value
        return true
    end,
    register_addon = function(name, info)
        if type(name) ~= "string" or name == "" then return false end
        UniversalState.addons[name] = type(info) == "table" and info or { status = "registered" }
        return true
    end,
    after_startup = function(fn)
        if type(fn) == "function" then
            table.insert(UniversalState.after_startup_cbs, fn)
            return true
        end
        return false
    end,
    on_update = function(id, fn)
        if type(id) == "string" and id ~= "" then
            if fn == nil then
                update_hooks[id] = nil
                return true
            elseif type(fn) == "function" then
                if update_hooks[id] == nil then
                    update_order[#update_order + 1] = id
                end
                update_hooks[id] = fn
                return true
            end
        end
        return false
    end,
    on_shutdown = function(id, fn)
        if type(id) == "string" and id ~= "" then
            if fn == nil then
                shutdown_hooks[id] = nil
                return true
            elseif type(fn) == "function" then
                if shutdown_hooks[id] == nil then
                    shutdown_order[#shutdown_order + 1] = id
                end
                shutdown_hooks[id] = fn
                return true
            end
        end
        return false
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
package.loaded["CowboyBingusModLoader"] = CowboyBingusModLoader

local BingusRuntime
local bingus_statuses = {}
local bingus_shared_table = setmetatable({
    version = 1,
    statuses = bingus_statuses,
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
}, {
    __call = function(self, env)
        return CowboyBingusModLoader
    end
})

BingusRuntime = {
    api = 1,
    version = 1,
    statuses = bingus_statuses,
    hashes = {},
    versions = {},
    hash_reads = {},
    shared = bingus_shared_table,
    guard = function(spec_or_name, fn)
        if type(spec_or_name) == "table" then
            local spec = spec_or_name
            local name = tostring(spec.name or "addon")
            local step = spec.step
            local after = spec.after
            local on_stop = spec.stop
            local stopped = false
            local status = {
                state = "starting",
                calls = 0,
                errors = 0,
                last_error = nil
            }
            bingus_statuses[name] = status
            local function stop_guard(reason)
                if stopped then return end
                stopped = true
                status.state = "stopped"
                status.last_error = reason
                CowboyBingusModLoader.on_update(name, nil)
                if type(on_stop) == "function" then pcall(on_stop, reason) end
            end
            local function run_step(...)
                if stopped then return end
                status.calls = status.calls + 1
                if type(step) == "function" then
                    local ok, err = pcall(step, ...)
                    if not ok then
                        status.errors = status.errors + 1
                        status.last_error = tostring(err)
                        log_message("BingusGuard", "Error in %s: %s", name, tostring(err))
                        if status.errors >= 20 then stop_guard(tostring(err)) end
                        return
                    end
                end
                if type(after) == "function" then
                    pcall(after, ...)
                end
                status.state = "running"
            end
            local function install()
                CowboyBingusModLoader.on_update(name, run_step)
                if type(on_stop) == "function" then
                    CowboyBingusModLoader.on_shutdown(name, function() stop_guard("shutdown") end)
                end
                status.state = "ready"
                return true
            end
            return {
                status = status,
                install = install,
                stop = stop_guard,
                running = function() return not stopped end
            }
        end
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                log_message("BingusGuard", "Error in %s: %s", tostring(spec_or_name), tostring(err))
            end
        end
    end
}
_G.BingusRuntime = BingusRuntime
package.preload["BingusRuntime"] = function() return BingusRuntime end
package.loaded["BingusRuntime"] = BingusRuntime

-- ==============================================================================
-- 7. BUILT-IN MOD OPTIONS MENU (MOM v2 / v3)
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
    version = 3,
    revision = 1,
    max_mods = 112,
    max_options = 256,
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
        if type(spec.on_change) == "function" then
            ModOptionsMenu.on_change(id, spec.on_change)
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
        local cbs = ModOptionsMenu.change_callbacks[id]
        if type(cbs) == "function" then
            pcall(cbs, norm, id)
        elseif type(cbs) == "table" then
            for i = 1, #cbs do
                if type(cbs[i]) == "function" then
                    pcall(cbs[i], norm, id)
                end
            end
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
            local existing = ModOptionsMenu.change_callbacks[id]
            if type(existing) == "function" then
                if existing ~= fn then
                    ModOptionsMenu.change_callbacks[id] = { existing, fn }
                end
            elseif type(existing) == "table" then
                local found = false
                for i = 1, #existing do
                    if existing[i] == fn then found = true; break end
                end
                if not found then existing[#existing + 1] = fn end
            else
                ModOptionsMenu.change_callbacks[id] = { fn }
            end
            return true
        end
        return false
    end,
    ready = function() return true end
}
_G.ModOptionsMenu = ModOptionsMenu
package.preload["ModOptionsMenu"] = function() return ModOptionsMenu end
package.loaded["ModOptionsMenu"] = ModOptionsMenu

-- ==============================================================================
-- 8. BUILT-IN MOD BINDINGS MENU (MBM v4) & KEY STATE TRACKING
-- ==============================================================================
local ModBindingsMenu
ModBindingsMenu = {
    api = 1,
    version = 4,
    revision = 1,
    capacity = 256,
    extended = {
        devices = { "keyboard", "mouse", "controller" },
        triggers = { "press", "release", "hold" },
        count = 0
    },
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
    ModBindingsMenu.extended.count = #ModBindingsMenu.order
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
ModBindingsMenu.down = ModBindingsMenu.is_down

function ModBindingsMenu.is_pressed(id)
    local st = ModBindingsMenu.states[id]
    return st and st.pressed or false
end
ModBindingsMenu.was_pressed = ModBindingsMenu.is_pressed
ModBindingsMenu.pressed = ModBindingsMenu.is_pressed

function ModBindingsMenu.is_released(id)
    local st = ModBindingsMenu.states[id]
    return st and st.released or false
end
ModBindingsMenu.was_released = ModBindingsMenu.is_released
ModBindingsMenu.released = ModBindingsMenu.is_released

function ModBindingsMenu.binding(id)
    return ModBindingsMenu.bindings[id] or "NONE"
end
ModBindingsMenu.get_binding = ModBindingsMenu.binding

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
package.loaded["ModBindingsMenu"] = ModBindingsMenu
package.loaded["CowboyBingusModBindings"] = ModBindingsMenu

-- Stingray Input Compatibility: Helldivers 2 exposes Keyboard.button_id / Mouse.button_id
-- while some mods call button_index, and pressed()/button() may return true OR 1 (> 0).
local function ensure_input_compat(sr)
    if type(sr) ~= "table" then return end
    for _, dev_name in ipairs({ "Keyboard", "Mouse", "Pad1", "Pad2", "Pad3", "Pad4" }) do
        local dev = rawget(sr, dev_name)
        if type(dev) == "table" then
            local bid = rawget(dev, "button_id")
            local bidx = rawget(dev, "button_index")
            if type(bid) == "function" and bidx == nil then
                pcall(rawset, dev, "button_index", bid)
            elseif type(bidx) == "function" and bid == nil then
                pcall(rawset, dev, "button_id", bidx)
            end
        end
    end
end

local function is_input_active(v)
    return v == true or (type(v) == "number" and v > 0)
end

local function resolve_button_id(dev, name)
    if type(dev) ~= "table" or type(name) ~= "string" or name == "" then return nil end
    local fn = rawget(dev, "button_id") or rawget(dev, "button_index")
    if type(fn) ~= "function" then return nil end
    local ok, idx = pcall(fn, name)
    if ok and idx ~= nil then
        return idx
    end
    return nil
end

local function query_device_button(dev, idx, method_name)
    if type(dev) ~= "table" or idx == nil then return false end
    local fn = rawget(dev, method_name)
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, idx)
    return ok and is_input_active(res)
end

-- Key Polling with Compound Modifier Support (e.g. "ctrl+h", "shift+f")
local function check_button_state(kb, mouse, name, check_type)
    if not name or name == "NONE" then return false end
    local has_ctrl = name:find("ctrl%+")
    local has_shift = name:find("shift%+")
    local has_alt = name:find("alt%+")
    local main_key = name:gsub("ctrl%+", ""):gsub("shift%+", ""):gsub("alt%+", ""):gsub("^%s+", ""):gsub("%s+$", "")

    if has_ctrl and kb then
        local lctrl = resolve_button_id(kb, "left ctrl")
        local rctrl = resolve_button_id(kb, "right ctrl")
        local ctrl_down = query_device_button(kb, lctrl, "button") or query_device_button(kb, rctrl, "button")
        if not ctrl_down then return false end
    end
    if has_shift and kb then
        local lshift = resolve_button_id(kb, "left shift")
        local rshift = resolve_button_id(kb, "right shift")
        local shift_down = query_device_button(kb, lshift, "button") or query_device_button(kb, rshift, "button")
        if not shift_down then return false end
    end
    if has_alt and kb then
        local lalt = resolve_button_id(kb, "left alt")
        local ralt = resolve_button_id(kb, "right alt")
        local alt_down = query_device_button(kb, lalt, "button") or query_device_button(kb, ralt, "button")
        if not alt_down then return false end
    end

    local method = (check_type == "down" and "button") or check_type
    local idx = resolve_button_id(kb, main_key)
    if idx ~= nil then
        return query_device_button(kb, idx, method)
    elseif mouse then
        local midx = resolve_button_id(mouse, main_key)
        if midx ~= nil then
            return query_device_button(mouse, midx, method)
        end
    end
    return false
end

update_bindings_state = function()
    if bindings_polled_this_frame then return end
    bindings_polled_this_frame = true
    local sr = rawget(_G, "stingray")
    if not sr then return end
    ensure_input_compat(sr)
    local kb = sr.Keyboard
    local mouse = sr.Mouse

    for id in pairs(ModBindingsMenu.registry) do
        local key = ModBindingsMenu.bindings[id]
        local is_down = check_button_state(kb, mouse, key, "down")
        local is_pressed = check_button_state(kb, mouse, key, "pressed")
        local is_released = check_button_state(kb, mouse, key, "released")

        local st = ModBindingsMenu.states[id]
        if not st then
            st = { down = false, pressed = false, released = false }
            ModBindingsMenu.states[id] = st
        end
        local prev_down = st.down == true
        st.down = is_down
        st.pressed = is_pressed or (is_down and not prev_down)
        st.released = is_released or (not is_down and prev_down)
    end
end

-- ==============================================================================
-- 9. PERSISTENT SETTINGS STORAGE (SAVE / LOAD + LEGACY MOM MIGRATION)
-- ==============================================================================
local function load_legacy_mom_values()
    local ldir = get_log_dir()
    local f = io.open(ldir .. [[\ModOptionsMenu.values]], "r")
    if not f then return 0 end
    local count = 0
    for line in f:lines() do
        local k, v = line:match("^([^\t\r\n]+)\t([^\r\n]*)$")
        if k and v ~= nil then
            if v == "true" then
                ModOptionsMenu.values[k] = true
            elseif v == "false" then
                ModOptionsMenu.values[k] = false
            else
                local num = tonumber(v)
                ModOptionsMenu.values[k] = (num ~= nil) and num or v
            end
            count = count + 1
        end
    end
    f:close()
    return count
end

local function save_legacy_mom_values()
    local ldir = get_log_dir()
    local f = io.open(ldir .. [[\ModOptionsMenu.values]], "w")
    if not f then return end
    local keys = {}
    for k in pairs(ModOptionsMenu.values) do
        keys[#keys + 1] = tostring(k)
    end
    sort(keys)
    for i = 1, #keys do
        local k = keys[i]
        local v = ModOptionsMenu.values[k]
        if type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
            f:write(format("%s\t%s\n", k, tostring(v)))
        end
    end
    f:close()
end

local function load_persistent_settings()
    local legacy_count = load_legacy_mom_values()
    local sdir = get_settings_dir()
    local path = sdir .. [[\settings.json]]
    local f = io.open(path, "r")
    if not f then
        local ldir = get_log_dir():gsub("[Ll]ogs[/\\]?$", "Settings")
        f = io.open(ldir .. [[\universal_settings.json]], "r")
    end
    if not f then
        if legacy_count > 0 then
            log_message("Settings", "Imported %d legacy ModOptionsMenu values from disk.", legacy_count)
        end
        return
    end
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
    pcall(save_legacy_mom_values)
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

-- Automatically transpile simple Lua 5.2+ `if <cond> then goto <label> end ... ::<label>::`
-- forward-continue patterns into Lua 5.1 `if not (<cond>) then ... end` blocks when
-- running under Helldivers 2's PUC-Rio Lua 5.1.4 VM (preserves exact line numbers).
local function transpile_lua52_goto(str)
    if type(str) ~= "string" or not str:find("::", 1, true) then
        return str
    end
    local out = str
    for label in str:gmatch("::([%a_][%w_]*)%s*::") do
        local goto_pat = "(if%s+)([^\r\n]-)(%s+then%s+)goto%s+" .. label .. "%s+end"
        local label_pat = "::" .. label .. "%s*::"
        if out:find(goto_pat) and out:find(label_pat) then
            out = out:gsub(goto_pat, "%1not (%2)%3"):gsub(label_pat, "end")
        end
    end
    return out
end

local function execute_mod_script(mod_name, source_code, archive_name)
    if UniversalState.active_mods[mod_name] and UniversalState.active_mods[mod_name].status == "loaded" then
        return true
    end

    if mod_name:find("cowboybingus/mod_options_menu") or mod_name:find("cowboybingus/mod_bindings_menu") then
        log_message("UniversalLoader", "Superseding legacy standalone %s (unified built-in engine active)", mod_name)
        UniversalState.active_mods[mod_name] = {
            name = mod_name,
            archive = archive_name,
            status = "superseded_by_builtin"
        }
        BingusRuntime.statuses[mod_name] = "superseded_by_builtin"
        package.loaded[mod_name] = mod_name:find("mod_options_menu") and ModOptionsMenu or ModBindingsMenu
        return true
    end

    local clean_source = strip_bom(source_code)
    local fn, err = loadstring(clean_source, "@" .. mod_name)
    if not fn and clean_source:find("::", 1, true) then
        local transpiled = transpile_lua52_goto(clean_source)
        if transpiled ~= clean_source then
            local fn2, err2 = loadstring(transpiled, "@" .. mod_name)
            if fn2 then
                fn, err = fn2, nil
                log_message("UniversalLoader", "Transpiled Lua 5.2 goto/label syntax for %s (Lua 5.1 VM compatibility)", mod_name)
            else
                err = err2
            end
        end
    end
    if not fn then
        log_message("UniversalLoader", "Failed to compile %s: %s", mod_name, tostring(err))
        UniversalState.failed_mods[mod_name] = {
            name = mod_name,
            archive = archive_name,
            status = "compile_error",
            error = tostring(err)
        }
        BingusRuntime.statuses[mod_name] = "compile_error: " .. tostring(err)
        return false, err
    end

    local mod_chef_api = create_chef_api_table(mod_name)
    local mod_env = setmetatable({
        chef = mod_chef_api,
        ChefSharedLoader = mod_chef_api,
        HD2ModLoader = CowboyBingusModLoader,
        CowboyBingusModLoader = CowboyBingusModLoader,
        BingusRuntime = BingusRuntime,
        ModOptionsMenu = ModOptionsMenu,
        ModBindingsMenu = ModBindingsMenu,
        CowboyBingusModBindings = ModBindingsMenu,
        BootModLoader = BootModLoader,
        hd2rt = hd2rt,
        bit = bit,
        bit32 = _G.bit32,
        utf8 = _G.utf8,
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
        BingusRuntime.statuses[mod_name] = "runtime_error: " .. tostring(res)
        return false, res
    end

    package.loaded[mod_name] = res or true
    capabilities_data.addon_discovery = 1
    UniversalState.active_mods[mod_name] = {
        name = mod_name,
        archive = archive_name,
        status = "loaded"
    }
    BingusRuntime.statuses[mod_name] = "ok"
    CowboyBingusModLoader.modules[mod_name] = UniversalState.active_mods[mod_name]

    log_message("UniversalLoader", "Successfully loaded %s from %s", mod_name, archive_name or "patch")
    return true
end

-- ==============================================================================
-- 13. DYNAMIC ARCHIVE DISCOVERY & DEDUPLICATION (PATCH_0..255)
-- ==============================================================================
local LUA_RESOURCE_TYPE = "\226\23\209\44\250\141\78\161"
local BOOT_RESOURCE_KEY = "\250\149\24\105\147\223\118\244" -- 0xF476DF93691895FA
local BOOT_NAME_KEY = murmur64_key("core/app/boot")
local ARCHIVE_MAGIC = 0xF0000011

local KNOWN_MOD_NAMES = {
    "mods/cowboybingus/mod_options_menu",
    "mods/cowboybingus/mod_bindings_menu",
    "mods/cowboybingus/warbond_desk",
    "mods/cowboybingus/warbond_desk_options",
    "mods/warbond_desk/main",
    "mods/cowboybingus/trajectory_hud",
    "mods/cowboybingus/trajectory_hud_options",
    "mods/cowboybingus/minimap_hud",
    "mods/cowboybingus/minimap_hud_options",
    "mods/cowboybingus/resupply_hud",
    "mods/cowboybingus/resupply_hud_options",
    "mods/cowboybingus/eagle_hud",
    "mods/cowboybingus/eagle_hud_options",
    "mods/engle/eagle_hud_probe",
    "mods/cowboybingus/headlamp",
    "mods/cowboybingus/headlamp_options",
    "mods/patpatpatrick/helmet_headlamp",
    "mods/cowboybingus/experimental_minimap",
    "mods/cowboybingus/experimental_minimap_options",
    "mods/chef/seaf_artillery_loadout",
    "mods/chef/seaf_artillery_loadout_options",
    "mods/chef/smarter_guard_dogs_and_sentries",
    "mods/chef/smarter_guard_dogs_and_sentries_options",
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
    "mods/chef/reticle_ammo_hud",
    "mods/chef/reticle_ammo_hud_options",
    "mods/reticle_ammo/hud",
    "mods/reticle_ammo/preset_style",
    "mods/reticle_ammo/preset_hotkey",
    "mods/reticle_ammo/preset_size",
    "mods/reticle_ammo/preset_position",
    "mods/reticle_ammo/preset_visibility",
    "mods/reticle_ammo/preset_numbers",
    "mods/reticle_ammo/preset_ring",
    "mods/reticle_ammo/preset_vehicles",
    "mods/reticle_ammo/preset_ammotype",
    "mods/reticle_ammo/preset_prompts",
    "mods/reticle_ammo/preset_rpm",
    "mods/reticle_ammo/preset_labels",
    "mods/reticle_ammo/preset_items",
    "mods/reticle_ammo/preset_switch",
    "mods/chef/vehicle_seat_switch",
    "mods/chef/vehicle_seat_switch_options",
    "mods/vehicle_seat_tools/vehicle_seat_switch",
    "mods/chef/mortar_hud",
    "mods/chef/mortar_hud_options",
    "mods/mortar/mortar_hud",
    "mods/retrox/sentry_hud",
    "mods/arena_local/mech_part_hud",
    "mods/driverhud/driver_hud",
    "mods/chef/pelican_hud",
    "mods/chef/pelican_hud_options",
    "mods/chef/hellpod_hud",
    "mods/chef/hellpod_hud_options",
    "mods/chef/sentry_hud",
    "mods/chef/sentry_hud_options",
    "mods/chef/shield_hud",
    "mods/chef/shield_hud_options",
    "mods/chef/sample_radar",
    "mods/chef/sample_radar_options",
    "mods/chef/stratagem_hero",
    "mods/chef/stratagem_hero_options"
}

local KNOWN_HASH_TO_NAME = {}
for i = 1, #KNOWN_MOD_NAMES do
    local nm = KNOWN_MOD_NAMES[i]
    KNOWN_HASH_TO_NAME[murmur64_key(nm)] = nm
end

local function read_u32(str, off)
    local b0, b1, b2, b3 = str:byte(off + 1, off + 4)
    if not b3 then return 0 end
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function resolve_data_dir()
    local candidates_dirs = { "data", "../data", "../../data" }
    local pkg_path = package and package.path or ""
    for pattern in pkg_path:gmatch("[^;]+") do
        local root = pattern:match("^(.*)[/\\]data[/\\]") or pattern:match("^(.*)[/\\]bin[/\\]")
        if root and #root > 0 then
            candidates_dirs[#candidates_dirs + 1] = root .. "/data"
        end
    end
    for i = 1, #candidates_dirs do
        local d = candidates_dirs[i]
        for probe_idx = 0, 5 do
            local f = io.open(format("%s/9ba626afa44a3aa3.patch_%d", d, probe_idx), "rb")
            if f then
                f:close()
                return d
            end
        end
    end
    return "data"
end

local function is_boot_loader_script(code, target_name, key8)
    if key8 == BOOT_RESOURCE_KEY or key8 == BOOT_NAME_KEY then
        if type(code) ~= "string" or (not code:find("%-%-%s*HD2%-Addon:") and not code:find("%-%-%s*HD2%-Options:")) then
            return true
        end
    end
    if type(code) ~= "string" then return false end
    if code:find("UniversalModLoader", 1, true) and code:find("discover_installed_mods", 1, true) then
        return true
    end
    if code:find("%-%-%s*HD2%-Boot:") then
        return true
    end
    if target_name and (
        target_name == "core/app/boot"
        or target_name:find("bingus_shared_loader", 1, true)
        or target_name:find("chef_shared_loader", 1, true)
        or target_name:find("boot_mod_loader", 1, true)
    ) then
        return true
    end
    return false
end

local function is_preset_resource(code, target_name)
    if type(target_name) == "string" and target_name:find("/preset_", 1, true) then
        return true
    end
    if type(code) == "string" and code:find("Reticle Ammo HUD preset", 1, true) then
        return true
    end
    return false
end

local function extract_declared_mod_name(code, key8, patch_num, entry_idx)
    if type(code) ~= "string" then return nil end
    local target_name = code:match("%-%-%s*HD2%-Addon:%s*([^\r\n]+)")
        or code:match("%-%-%s*HD2%-Boot:%s*([^\r\n]+)")
        or code:match("%-%-%s*HD2%-Options:%s*([^\r\n]+)")
        or code:match("%-%-%s*@mod%s+([^\r\n]+)")
        or code:match("%-%-%s*Mod:%s*([^\r\n]+)")
        or code:match('BingusRuntime%.guard%(%s*{[^}]*name%s*=%s*["\'](mods/[^"\']+)["\']')
        or code:match('BingusRuntime%.guard%(%s*["\'](mods/[^"\']+)["\']')
        or code:match('MOD_ID%s*=%s*["\'](mods/[^"\']+)["\']')
        or code:match('MOD_NAME%s*=%s*["\'](mods/[^"\']+)["\']')

    if target_name then
        return target_name:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if key8 and KNOWN_HASH_TO_NAME[key8] then
        return KNOWN_HASH_TO_NAME[key8]
    end
    if key8 and key8 ~= BOOT_RESOURCE_KEY and key8 ~= BOOT_NAME_KEY then
        return format("mods/custom/patch_%d_entry_%d", patch_num or 0, entry_idx or 0)
    end
    return nil
end

local function discover_installed_mods()
    local data_dir = resolve_data_dir()
    local candidates = {}
    local candidate_order = {}
    local preset_modules = {}

    local function register_candidate(target_name, code, patch_num, key8)
        if is_boot_loader_script(code, target_name, key8) then
            return
        end
        if not target_name or #target_name == 0 then return end
        if is_preset_resource(code, target_name) then
            preset_modules[target_name] = code
            package.preload[target_name] = function()
                local fn = loadstring(strip_bom(code), "@" .. target_name)
                if fn then
                    local ok, res = pcall(fn)
                    if ok then return res end
                end
                return nil
            end
            return
        end
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
                        local key8 = ent:sub(1, 8)
                        local off = read_u32(ent, 16)
                        local sz = read_u32(ent, 56)
                        if off > 0 and sz >= 8 then
                            f:seek("set", off + 8)
                            local code = f:read(sz - 8)
                            if code and #code > 0 then
                                local target_name = extract_declared_mod_name(code, key8, patch_num, i)
                                register_candidate(target_name, code, patch_num, key8)
                            end
                        end
                    end
                end
            else
                -- Raw plain-text Lua patch file (Chef-style raw patch)
                f:seek("set", 0)
                local code = f:read("*a")
                if code and #code > 0 then
                    local target_name = extract_declared_mod_name(code, nil, patch_num, 0)
                    register_candidate(target_name, code, patch_num, nil)
                end
            end
            f:close()
        end
    end

    -- Register on-demand package.preload loaders and stingray.Application.can_get compatibility
    -- so mods that call require("mods/..._options") during startup resolve immediately without duplicate runs.
    for target_name, item in pairs(candidates) do
        if not package.preload[target_name] then
            local mod_item = item
            package.preload[target_name] = function()
                if not package.loaded[mod_item.name] then
                    execute_mod_script(mod_item.name, mod_item.content, mod_item.archive)
                end
                return package.loaded[mod_item.name]
            end
        end
    end

    local sr = rawget(_G, "stingray")
    if sr and type(sr.Application) == "table" and type(sr.Application.can_get) == "function" and not sr.Application._uml_can_get_wrapped then
        local orig_can_get = sr.Application.can_get
        sr.Application._uml_can_get_wrapped = true
        sr.Application.can_get = function(res_type, res_name, ...)
            if res_type == "lua" and type(res_name) == "string" then
                if candidates[res_name] or preset_modules[res_name] or package.loaded[res_name] or package.preload[res_name] or UniversalState.active_mods[res_name] then
                    return true
                end
            end
            return orig_can_get(res_type, res_name, ...)
        end
    end

    -- Sort execution order so sub-modules (`<parent>_*`, e.g. `warbond_desk_options`) run before `<parent>` (`warbond_desk`)
    local orig_idx = {}
    for idx, nm in ipairs(candidate_order) do
        orig_idx[nm] = idx
    end
    table.sort(candidate_order, function(a, b)
        if a == b then return false end
        if a:sub(1, #b + 1) == (b .. "_") then return true end
        if b:sub(1, #a + 1) == (a .. "_") then return false end
        return (orig_idx[a] or 0) < (orig_idx[b] or 0)
    end)

    for _, target_name in ipairs(candidate_order) do
        local item = candidates[target_name]
        if item then
            execute_mod_script(item.name, item.content, item.archive)
        end
    end

    local mod_count = 0
    for _ in pairs(UniversalState.active_mods) do mod_count = mod_count + 1 end
    log_message("UniversalLoader", "Discovered & Registered %d unique mods from %s.", mod_count, data_dir)
end

-- ==============================================================================
-- 14. INTERACTIVE ESCAPE-MENU "MODS" TAB & 3-COLUMN SETTINGS UI (MOUSE + KEYBOARD)
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

-- Escape-Menu Top-Bar "MODS [F2]" Tab Button Geometry (1920x1080 Canvas)
local ESC_TOP_MODS_BTN = { x = 1150, y = 36, w = 190, h = 44 }

-- Win32 Cursor State (used when native LuaJIT FFI is active in Helldivers 2)
local win32_cursor_state = nil
local function init_win32_cursor()
    if win32_cursor_state ~= nil then return win32_cursor_state end
    if not has_native_ffi then
        win32_cursor_state = false
        return false
    end
    local ok, state = pcall(function()
        for _, decl in ipairs({
            "void *GetForegroundWindow(void);",
            "uint32_t GetWindowThreadProcessId(void *, void *);",
            "uint32_t GetCurrentProcessId(void);",
            "int GetCursorPos(void *);",
            "int ScreenToClient(void *, void *);",
            "int GetClientRect(void *, void *);"
        }) do
            pcall(ffi.cdef, decl)
        end
        local u32 = ffi.load("user32")
        local k32 = ffi.load("kernel32")
        return {
            user32 = u32,
            own_pid = k32.GetCurrentProcessId(),
            pid_buf = ffi.new("uint32_t[1]"),
            pt_buf = ffi.new("int32_t[2]"),
            rc_buf = ffi.new("int32_t[4]")
        }
    end)
    win32_cursor_state = (ok and type(state) == "table") and state or false
    return win32_cursor_state
end

local function get_screen_resolution(sr)
    local W, H = 1920, 1080
    if sr and sr.Gui and type(sr.Gui.resolution) == "function" then
        local ok, rw, rh = pcall(sr.Gui.resolution)
        if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then
            W, H = rw, rh
        end
    end
    return W, H
end

local function is_cursor_shown(sr)
    if not sr or type(sr.Window) ~= "table" then return false end
    if type(sr.Window.show_cursor) == "function" then
        local ok, shown = pcall(sr.Window.show_cursor)
        if ok and shown == true then return true end
    end
    if type(sr.Window.has_cursor) == "function" then
        local ok, shown = pcall(sr.Window.has_cursor)
        if ok and shown == true then return true end
    end
    return false
end

local function get_mouse_canvas_pos(sr)
    local W, H = get_screen_resolution(sr)
    local scale = H / 1080
    local ox = floor((W - 1920 * scale) * 0.5)
    local raw_x, raw_y = nil, nil

    -- 1. Try Win32 ScreenToClient (exact top-down client coordinates in Helldivers 2)
    local w32 = init_win32_cursor()
    if w32 then
        pcall(function()
            local u = w32.user32
            local win = u.GetForegroundWindow()
            if win ~= nil and win ~= ffi.NULL then
                if u.GetWindowThreadProcessId(win, ffi.cast("void *", w32.pid_buf)) ~= 0
                    and tonumber(w32.pid_buf[0]) == tonumber(w32.own_pid)
                then
                    if u.GetCursorPos(ffi.cast("void *", w32.pt_buf)) ~= 0
                        and u.ScreenToClient(win, ffi.cast("void *", w32.pt_buf)) ~= 0
                        and u.GetClientRect(win, ffi.cast("void *", w32.rc_buf)) ~= 0
                    then
                        local cw = tonumber(w32.rc_buf[2] - w32.rc_buf[0]) or 0
                        local ch = tonumber(w32.rc_buf[3] - w32.rc_buf[1]) or 0
                        if cw > 0 and ch > 0 then
                            local px = tonumber(w32.pt_buf[0]) * W / cw
                            local py = tonumber(w32.pt_buf[1]) * H / ch
                            if px >= 0 and py >= 0 and px <= W and py <= H then
                                raw_x, raw_y = px, py
                            end
                        end
                    end
                end
            end
        end)
    end

    -- 2. Fallback to Stingray Mouse.axis("cursor")
    if (raw_x == nil or raw_y == nil) and sr and type(sr.Mouse) == "table" then
        pcall(function()
            local m = sr.Mouse
            if type(m.axis) == "function" then
                local aid = (type(m.axis_id) == "function") and m.axis_id("cursor") or "cursor"
                if aid ~= nil then
                    local v = m.axis(aid)
                    if v ~= nil then
                        local vx, vy
                        if type(sr.Vector3) == "table" and type(sr.Vector3.x) == "function" then
                            vx, vy = sr.Vector3.x(v), sr.Vector3.y(v)
                        elseif type(v) == "table" then
                            vx = v.x or v[1]
                            vy = v.y or v[2]
                        end
                        if type(vx) == "number" and type(vy) == "number" then
                            if vx >= 0 and vx <= 1 and vy >= 0 and vy <= 1 and (vx > 0 or vy > 0) and W > 1 and H > 1 then
                                vx = vx * W
                                vy = vy * H
                            end
                            raw_x, raw_y = vx, vy
                        end
                    end
                end
            end
        end)
    end

    if raw_x == nil or raw_y == nil or scale <= 0 then
        return nil, nil
    end
    local cx = (raw_x - ox) / scale
    local cy = raw_y / scale
    return cx, cy
end

local function get_mouse_wheel_delta(sr)
    if not sr or type(sr.Mouse) ~= "table" then return 0 end
    local m = sr.Mouse
    if type(m.axis) == "function" then
        local ok, wy = pcall(function()
            local aid = (type(m.axis_id) == "function") and m.axis_id("wheel") or "wheel"
            if aid == nil then return 0 end
            local v = m.axis(aid)
            if v == nil then return 0 end
            if type(sr.Vector3) == "table" and type(sr.Vector3.y) == "function" then
                return sr.Vector3.y(v)
            elseif type(v) == "table" then
                return v.y or v[2] or 0
            elseif type(v) == "number" then
                return v
            end
            return 0
        end)
        if ok and type(wy) == "number" and wy ~= 0 and wy == wy and math.abs(wy) < math.huge then
            return wy
        end
    end
    local w_up = resolve_button_id(m, "wheel_up")
    if w_up ~= nil and query_device_button(m, w_up, "pressed") then return 1 end
    local w_dn = resolve_button_id(m, "wheel_down")
    if w_dn ~= nil and query_device_button(m, w_dn, "pressed") then return -1 end
    return 0
end

local function pt_in_rect(cx, cy, x, y, w, h)
    return cx ~= nil and cy ~= nil and cx >= x and cx <= (x + w) and cy >= y and cy <= (y + h)
end

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
            return "ON", 90, 235, 130
        else
            return "OFF", 200, 110, 110
        end
    elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
        local count = #spec.choices
        local idx = normalize_option_value(spec, val)
        local choice_lbl = resolve_text(spec.choices[idx], tostring(idx))
        return format("%s (%d/%d)", choice_lbl, idx, count), 245, 210, 85
    elseif otype == "slider" or otype == "number" or type(val) == "number" then
        local num = tonumber(val) or 0
        return tostring(num), 110, 210, 250
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

local function step_option_value(cur_id, dir)
    local spec = ModOptionsMenu.registered[cur_id]
    if not spec then return end
    local cur_val = ModOptionsMenu.get(cur_id)
    local otype = spec.type
    if otype == "toggle" or otype == "boolean" or (otype == nil and type(cur_val) == "boolean") then
        ModOptionsMenu.set(cur_id, not cur_val)
    elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
        local count = #spec.choices
        local cur_idx = normalize_option_value(spec, cur_val)
        if dir >= 0 then
            cur_idx = (cur_idx % count) + 1
        else
            cur_idx = cur_idx - 1
            if cur_idx < 1 then cur_idx = count end
        end
        ModOptionsMenu.set(cur_id, cur_idx)
    elseif otype == "slider" or otype == "number" or type(cur_val) == "number" then
        local step = tonumber(spec.step) or 1
        local num = tonumber(cur_val) or 0
        ModOptionsMenu.set(cur_id, snap_slider_value(spec, num + (dir >= 0 and step or -step)))
    end
end

local function set_slider_from_ratio(cur_id, ratio)
    local spec = ModOptionsMenu.registered[cur_id]
    if not spec then return end
    local min_v = tonumber(spec.min)
    local max_v = tonumber(spec.max)
    if not min_v or not max_v or max_v <= min_v then return end
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    local raw_val = min_v + ratio * (max_v - min_v)
    ModOptionsMenu.set(cur_id, snap_slider_value(spec, raw_val))
end

local function handle_menu_input()
    local sr = rawget(_G, "stingray")
    if not sr then return end
    ensure_input_compat(sr)

    local function key_pressed(name)
        local idx = resolve_button_id(sr.Keyboard, name)
        if idx ~= nil and query_device_button(sr.Keyboard, idx, "pressed") then return true end
        local midx = resolve_button_id(sr.Mouse, name)
        if midx ~= nil and query_device_button(sr.Mouse, midx, "pressed") then return true end
        if type(sr.Pad1) == "table" then
            local pidx = resolve_button_id(sr.Pad1, name)
            if pidx ~= nil and query_device_button(sr.Pad1, pidx, "pressed") then return true end
        end
        return false
    end

    local function mouse_btn_pressed(btn_name, alt_name)
        local m = sr.Mouse
        if type(m) ~= "table" then return false end
        local idx = resolve_button_id(m, btn_name)
        if idx ~= nil and query_device_button(m, idx, "pressed") then return true end
        if alt_name then
            local aidx = resolve_button_id(m, alt_name)
            if aidx ~= nil and query_device_button(m, aidx, "pressed") then return true end
        end
        return false
    end

    local function mouse_btn_down(btn_name, alt_name)
        local m = sr.Mouse
        if type(m) ~= "table" then return false end
        local idx = resolve_button_id(m, btn_name)
        if idx ~= nil and query_device_button(m, idx, "button") then return true end
        if alt_name then
            local aidx = resolve_button_id(m, alt_name)
            if aidx ~= nil and query_device_button(m, aidx, "button") then return true end
        end
        return false
    end

    local cx, cy = get_mouse_canvas_pos(sr)
    local mouse_moved = false
    if cx ~= nil and cy ~= nil then
        if UniversalState.last_mouse_cx == nil or UniversalState.last_mouse_cy == nil
            or math.abs(cx - UniversalState.last_mouse_cx) >= 1.0
            or math.abs(cy - UniversalState.last_mouse_cy) >= 1.0
        then
            mouse_moved = true
            UniversalState.last_mouse_cx = cx
            UniversalState.last_mouse_cy = cy
        end
    end

    local lclick = mouse_btn_pressed("left", "mouse_left")
    local ldown = mouse_btn_down("left", "mouse_left")
    local rclick = mouse_btn_pressed("right", "mouse_right")
    local wheel = get_mouse_wheel_delta(sr)

    if not ldown then
        UniversalState.dragging_slider_id = nil
    end

    -- Hotkey toggle (F2 / F9) works anywhere
    if key_pressed("f2") or key_pressed("f9") then
        UniversalState.menu_visible = not UniversalState.menu_visible
        UniversalState.menu_rebind_id = nil
        UniversalState.dragging_slider_id = nil
        if not UniversalState.menu_visible then
            ui_gfx_clear(sr)
        end
        return
    end

    -- When MODS screen is closed, check if Escape Menu cursor is active for Top-Bar "MODS [F2]" Tab Button
    if not UniversalState.menu_visible then
        if is_cursor_shown(sr) then
            local hov = pt_in_rect(cx, cy, ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h)
            UniversalState.hover_esc_mods_btn = hov
            if hov and lclick then
                UniversalState.menu_visible = true
                UniversalState.menu_rebind_id = nil
                UniversalState.dragging_slider_id = nil
                return
            end
        else
            UniversalState.hover_esc_mods_btn = false
        end
        return
    end

    -- Rebind Mode Active in Tab 2
    if UniversalState.menu_rebind_id then
        if key_pressed("escape") or rclick then
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
        UniversalState.dragging_slider_id = nil
        ui_gfx_clear(sr)
        return
    end

    -- Continue active slider drag if left mouse button is held down
    if UniversalState.dragging_slider_id and ldown and cx ~= nil then
        local ratio = (cx - 1028) / 190
        set_slider_from_ratio(UniversalState.dragging_slider_id, ratio)
        return
    end

    -- Top Header Bar Mouse Clicks (Y=36..80)
    if lclick and cy ~= nil and cy >= 34 and cy <= 82 then
        -- Native Escape-Menu Tabs: [ GAME ] (105..250), [ SOCIAL ] (260..415), [ OPTIONS ] (425..590)
        if (cx >= 105 and cx <= 590) or (cx >= 1605 and cx <= 1815) then
            UniversalState.menu_visible = false
            UniversalState.dragging_slider_id = nil
            ui_gfx_clear(sr)
            return
        elseif cx >= 810 and cx <= 1070 then
            UniversalState.menu_tab = 1
            UniversalState.menu_selected = 1
            return
        elseif cx >= 1080 and cx <= 1330 then
            UniversalState.menu_tab = 2
            UniversalState.menu_selected = 1
            return
        elseif cx >= 1340 and cx <= 1590 then
            UniversalState.menu_tab = 3
            UniversalState.menu_selected = 1
            return
        end
    end

    -- Keyboard Tab Switching (Tab / 1 / 2 / 3)
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

    local categories, by_cat = get_mod_option_categories()
    local cat_idx = UniversalState.menu_mod_filter or 1
    if cat_idx < 1 or cat_idx > #categories then
        cat_idx = 1
        UniversalState.menu_mod_filter = 1
    end

    -- Left Column (X=105..495): Category Sidebar Clicks & Wheel
    local cat_page_size = 12
    local cat_page = floor((cat_idx - 1) / cat_page_size)
    local cat_start = cat_page * cat_page_size + 1
    local cat_end = min(#categories, cat_start + cat_page_size - 1)

    if cx ~= nil and cx >= 105 and cx <= 495 then
        if wheel > 0 and #categories > 0 then
            cat_idx = cat_idx - 1
            if cat_idx < 1 then cat_idx = #categories end
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_tab = 1
            UniversalState.menu_selected = 1
            return
        elseif wheel < 0 and #categories > 0 then
            cat_idx = (cat_idx % #categories) + 1
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_tab = 1
            UniversalState.menu_selected = 1
            return
        end

        if lclick then
            for ci = cat_start, cat_end do
                local ry = 152 + (ci - cat_start) * 60
                if pt_in_rect(cx, cy, 115, ry, 370, 54) then
                    UniversalState.menu_mod_filter = ci
                    UniversalState.menu_tab = 1
                    UniversalState.menu_selected = 1
                    return
                end
            end
            -- Left column bottom [< PREV (Q)] / [(E) NEXT >] buttons
            if pt_in_rect(cx, cy, 115, 885, 180, 44) and #categories > 0 then
                cat_idx = cat_idx - 1
                if cat_idx < 1 then cat_idx = #categories end
                UniversalState.menu_mod_filter = cat_idx
                UniversalState.menu_tab = 1
                UniversalState.menu_selected = 1
                return
            elseif pt_in_rect(cx, cy, 305, 885, 180, 44) and #categories > 0 then
                cat_idx = (cat_idx % #categories) + 1
                UniversalState.menu_mod_filter = cat_idx
                UniversalState.menu_tab = 1
                UniversalState.menu_selected = 1
                return
            end
        end
    end

    -- ==========================================================================
    -- TAB 1: MOD OPTIONS INPUT
    -- ==========================================================================
    if (UniversalState.menu_tab or 1) == 1 then
        if key_pressed("q") or key_pressed("left_shoulder") then
            cat_idx = cat_idx - 1
            if cat_idx < 1 then cat_idx = #categories end
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_selected = 1
            return
        elseif key_pressed("e") or key_pressed("right_shoulder") then
            cat_idx = (cat_idx % #categories) + 1
            UniversalState.menu_mod_filter = cat_idx
            UniversalState.menu_selected = 1
            return
        end

        local active_cat = categories[cat_idx] or "ALL MODS"
        local opt_keys = by_cat[active_cat] or {}
        local total = #opt_keys
        if total == 0 then return end

        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = total; UniversalState.menu_selected = sel end
        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        -- Mouse Wheel in Center/Right Columns
        if wheel ~= 0 and (cx == nil or cx > 495) then
            if wheel > 0 then
                UniversalState.menu_selected = math.max(1, sel - 1)
            else
                UniversalState.menu_selected = math.min(total, sel + 1)
            end
            return
        end

        -- Center Column Header [< PAGE] / [PAGE >] Clicks
        if lclick and pt_in_rect(cx, cy, 1095, 109, 115, 34) then
            UniversalState.menu_selected = math.max(1, sel - page_size)
            return
        elseif lclick and pt_in_rect(cx, cy, 1220, 109, 115, 34) then
            UniversalState.menu_selected = math.min(total, sel + page_size)
            return
        end

        -- Right Column [RESET TO DEFAULT] Button Click
        if lclick and pt_in_rect(cx, cy, 1395, 880, 400, 48) then
            local cur_id = opt_keys[sel]
            if cur_id then ModOptionsMenu.reset_option(cur_id) end
            return
        end

        -- Center Column Option Rows: Hover, Left-Click, Slider Drag, Right-Click
        if cx ~= nil and cx >= 525 and cx <= 1345 then
            for i = start_idx, end_idx do
                local ry = 152 + (i - start_idx) * 60
                if pt_in_rect(cx, cy, 525, ry, 820, 54) then
                    if mouse_moved or lclick or rclick then
                        UniversalState.menu_selected = i
                        sel = i
                    end
                    local row_id = opt_keys[i]
                    local spec = row_id and ModOptionsMenu.registered[row_id]
                    if rclick and row_id then
                        ModOptionsMenu.reset_option(row_id)
                        return
                    elseif lclick and row_id and spec then
                        local cur_val = ModOptionsMenu.get(row_id)
                        local otype = spec.type
                        if otype == "toggle" or otype == "boolean" or (otype == nil and type(cur_val) == "boolean") then
                            if cx >= 1045 and cx <= 1180 then
                                ModOptionsMenu.set(row_id, false)
                            elseif cx >= 1185 and cx <= 1320 then
                                ModOptionsMenu.set(row_id, true)
                            else
                                ModOptionsMenu.set(row_id, not cur_val)
                            end
                        elseif otype == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
                            if cx >= 985 and cx <= 1030 then
                                step_option_value(row_id, -1)
                            else
                                step_option_value(row_id, 1)
                            end
                        elseif otype == "slider" or otype == "number" or type(cur_val) == "number" then
                            local min_v = tonumber(spec.min)
                            local max_v = tonumber(spec.max)
                            if cx >= 985 and cx <= 1024 then
                                step_option_value(row_id, -1)
                            elseif min_v and max_v and max_v > min_v and cx >= 1028 and cx <= 1218 then
                                UniversalState.dragging_slider_id = row_id
                                set_slider_from_ratio(row_id, (cx - 1028) / 190)
                            elseif cx >= 1222 and cx <= 1265 then
                                step_option_value(row_id, 1)
                            else
                                step_option_value(row_id, 1)
                            end
                        end
                        return
                    end
                    break
                end
            end
        end

        -- Keyboard / Controller Navigation
        if key_pressed("up") or key_pressed("d_up") then
            UniversalState.menu_selected = math.max(1, sel - 1)
        elseif key_pressed("down") or key_pressed("d_down") then
            UniversalState.menu_selected = math.min(total, sel + 1)
        elseif key_pressed("page up") then
            UniversalState.menu_selected = math.max(1, sel - page_size)
        elseif key_pressed("page down") then
            UniversalState.menu_selected = math.min(total, sel + page_size)
        end

        sel = UniversalState.menu_selected or 1
        local cur_id = opt_keys[sel]
        if cur_id then
            if key_pressed("backspace") then
                ModOptionsMenu.reset_option(cur_id)
                return
            elseif key_pressed("left") or key_pressed("d_left") then
                step_option_value(cur_id, -1)
            elseif key_pressed("right") or key_pressed("d_right") or key_pressed("enter") or key_pressed("space") then
                step_option_value(cur_id, 1)
            end
        end

    -- ==========================================================================
    -- TAB 2: KEY BINDINGS INPUT
    -- ==========================================================================
    elseif UniversalState.menu_tab == 2 then
        local bind_list = ModBindingsMenu.order
        local total = #bind_list
        if total == 0 then return end

        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = total; UniversalState.menu_selected = sel end
        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        if wheel ~= 0 and (cx == nil or cx > 495) then
            if wheel > 0 then
                UniversalState.menu_selected = math.max(1, sel - 1)
            else
                UniversalState.menu_selected = math.min(total, sel + 1)
            end
            return
        end

        if lclick and pt_in_rect(cx, cy, 1395, 880, 400, 48) then
            local rec = bind_list[sel]
            if rec then ModBindingsMenu.reset_binding(rec.id) end
            return
        end

        if cx ~= nil and cx >= 525 and cx <= 1345 then
            for i = start_idx, end_idx do
                local ry = 152 + (i - start_idx) * 60
                if pt_in_rect(cx, cy, 525, ry, 820, 54) then
                    if mouse_moved or lclick or rclick then
                        UniversalState.menu_selected = i
                        sel = i
                    end
                    local rec = bind_list[i]
                    if rclick and rec then
                        ModBindingsMenu.reset_binding(rec.id)
                        return
                    elseif lclick and rec then
                        if cx >= 1235 and cx <= 1335 then
                            ModBindingsMenu.reset_binding(rec.id)
                        else
                            UniversalState.menu_rebind_id = rec.id
                        end
                        return
                    end
                    break
                end
            end
        end

        if key_pressed("up") or key_pressed("d_up") then
            UniversalState.menu_selected = math.max(1, sel - 1)
        elseif key_pressed("down") or key_pressed("d_down") then
            UniversalState.menu_selected = math.min(total, sel + 1)
        elseif key_pressed("page up") then
            UniversalState.menu_selected = math.max(1, sel - page_size)
        elseif key_pressed("page down") then
            UniversalState.menu_selected = math.min(total, sel + page_size)
        end

        sel = UniversalState.menu_selected or 1
        local record = bind_list[sel]
        if record then
            if key_pressed("enter") or key_pressed("space") then
                UniversalState.menu_rebind_id = record.id
            elseif key_pressed("backspace") then
                ModBindingsMenu.reset_binding(record.id)
            end
        end

    -- ==========================================================================
    -- TAB 3: LOADED MODS & DIAGNOSTICS INPUT
    -- ==========================================================================
    elseif UniversalState.menu_tab == 3 then
        local mods_list = get_loaded_mods_list()
        local total = #mods_list
        if total == 0 then return end

        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = total; UniversalState.menu_selected = sel end
        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        if wheel ~= 0 and (cx == nil or cx > 495) then
            if wheel > 0 then
                UniversalState.menu_selected = math.max(1, sel - 1)
            else
                UniversalState.menu_selected = math.min(total, sel + 1)
            end
            return
        end

        if lclick and pt_in_rect(cx, cy, 1095, 109, 115, 34) then
            UniversalState.menu_selected = math.max(1, sel - page_size)
            return
        elseif lclick and pt_in_rect(cx, cy, 1220, 109, 115, 34) then
            UniversalState.menu_selected = math.min(total, sel + page_size)
            return
        end

        if cx ~= nil and cx >= 525 and cx <= 1345 then
            for i = start_idx, end_idx do
                local ry = 152 + (i - start_idx) * 60
                if pt_in_rect(cx, cy, 525, ry, 820, 54) then
                    if mouse_moved or lclick then
                        UniversalState.menu_selected = i
                    end
                    break
                end
            end
        end

        if key_pressed("up") or key_pressed("d_up") then
            UniversalState.menu_selected = math.max(1, sel - 1)
        elseif key_pressed("down") or key_pressed("d_down") then
            UniversalState.menu_selected = math.min(total, sel + 1)
        elseif key_pressed("page up") then
            UniversalState.menu_selected = math.max(1, sel - page_size)
        elseif key_pressed("page down") then
            UniversalState.menu_selected = math.min(total, sel + page_size)
        end
    end
end

local function draw_menu_overlay()
    local sr = rawget(_G, "stingray")
    if not sr or not sr.Gui or not sr.Gui.rect then return end

    local cursor_open = is_cursor_shown(sr)
    if not UniversalState.menu_visible and not cursor_open then
        if UI_GFX.gui or #UI_GFX.rect_ids > 0 or #UI_GFX.text_ids > 0 then
            ui_gfx_clear(sr)
        end
        return
    end

    local retained_mode = is_stingray_retained_gui(sr)
    local W, H = get_screen_resolution(sr)
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

    -- ==========================================================================
    -- STATE 1: ESCAPE MENU OPEN (TOP-BAR "MODS [F2]" TAB BUTTON ONLY)
    -- ==========================================================================
    if not UniversalState.menu_visible and cursor_open then
        local hov = UniversalState.hover_esc_mods_btn == true
        if retained_mode then
            if not ui_gfx_ensure(sr) then return end
            local sig = format("ESC_TOPBAR:%d:%d:%s", W, H, tostring(hov))
            if UI_GFX.last_sig == sig then return end
            ui_gfx_clear(sr)
            UI_GFX.last_sig = sig
        end

        local bx, by, bw, bh = ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h
        draw_rect(bx - 2, by - 2, bw + 4, bh + 4, 245, 205, 50, hov and 255 or 195, 955)
        draw_rect(bx, by, bw, bh, hov and 52 or 22, hov and 68 or 28, hov and 92 or 38, 242, 956)
        draw_rect(bx, by + bh - 3, bw, 3, 255, 215, 55, 255, 958)
        draw_text("MODS [F2]", bx + 34, by + 29, 18, 255, hov and 245 or 215, hov and 140 or 65, 255, 970)
        return
    end

    -- ==========================================================================
    -- STATE 2: FULL-SCREEN HELLDIVERS 2 3-COLUMN "MODS" TAB
    -- ==========================================================================
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
        local sig = format("MODS_3COL:%d:%d:%d:%d:%d:%s:%d:%d:%d:%s",
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

    -- Outer Tactical Frame (X=85..1835, Y=24..1012 on 1920x1080 Canvas)
    draw_rect(82, 21, 1756, 994, 235, 195, 45, 225, 954)  -- Gold outer frame
    draw_rect(85, 24, 1750, 988, 12, 16, 22, 246, 955)    -- Deep tactical backdrop
    draw_rect(85, 24, 1750, 66, 20, 27, 38, 252, 956)     -- Top Menu Bar backdrop
    draw_rect(85, 90, 1750, 2, 235, 195, 45, 255, 957)    -- Top Menu gold divider

    -- Top Bar Left: Native Escape-Menu Tab Return Buttons + Active [ MODS ] Tab
    local esc_tabs = {
        { x = 105, w = 145, label = "GAME",    active = false },
        { x = 260, w = 155, label = "SOCIAL",  active = false },
        { x = 425, w = 165, label = "OPTIONS", active = false },
        { x = 600, w = 165, label = "MODS",    active = true  }
    }
    for i = 1, #esc_tabs do
        local et = esc_tabs[i]
        if et.active then
            draw_rect(et.x, 36, et.w, 44, 58, 52, 24, 245, 958)
            draw_rect(et.x, 76, et.w, 4, 255, 215, 55, 255, 960)
            draw_text(et.label, et.x + 44, 65, 19, 255, 220, 65, 255, 970)
        else
            draw_rect(et.x, 36, et.w, 44, 26, 34, 46, 220, 958)
            draw_text(et.label, et.x + 34, 64, 17, 165, 178, 195, 255, 970)
        end
    end

    -- Top Bar Right: 3 Mode Sub-Tabs + [ ESC / F2 ] Close Button
    local tab = UniversalState.menu_tab or 1
    local mode_tabs = {
        { idx = 1, x = 810,  w = 260, label = format("[1] MOD OPTIONS (%d)", total_opts) },
        { idx = 2, x = 1080, w = 250, label = format("[2] KEY BINDINGS (%d)", total_binds) },
        { idx = 3, x = 1340, w = 250, label = format("[3] LOADED MODS (%d)", total_mods) }
    }
    for i = 1, #mode_tabs do
        local mt = mode_tabs[i]
        local active = (tab == mt.idx)
        draw_rect(mt.x, 36, mt.w, 44, active and 42 or 24, active and 66 or 32, active and 98 or 44, 240, 958)
        if active then
            draw_rect(mt.x, 77, mt.w, 3, 255, 215, 55, 255, 960)
        end
        draw_text(mt.label, mt.x + 16, 64, 15, active and 255 or 170, active and 240 or 182, active and 175 or 198, 255, 970)
    end

    -- Close Button (X=1605, W=210, Y=36, H=44)
    draw_rect(1605, 36, 210, 44, 68, 28, 32, 235, 958)
    draw_rect(1605, 77, 210, 3, 235, 95, 95, 255, 960)
    draw_text("[ESC / F2] CLOSE", 1632, 64, 15, 255, 210, 210, 255, 970)

    -- ==========================================================================
    -- COLUMN 1 (LEFT SIDEBAR, X=105..495, Y=105..945): MOD CATEGORIES
    -- ==========================================================================
    draw_rect(105, 105, 390, 840, 16, 22, 30, 240, 956)
    draw_rect(105, 105, 390, 40, 24, 34, 48, 250, 957)
    draw_rect(105, 143, 390, 2, 235, 195, 45, 220, 958)
    draw_text("MOD CATEGORIES  [Q / E]", 122, 131, 16, 255, 215, 65, 255, 970)

    local cat_idx = UniversalState.menu_mod_filter or 1
    if cat_idx < 1 or cat_idx > #categories then
        cat_idx = 1
        UniversalState.menu_mod_filter = 1
    end
    local cat_page_size = 12
    local cat_page = floor((cat_idx - 1) / cat_page_size)
    local cat_start = cat_page * cat_page_size + 1
    local cat_end = min(#categories, cat_start + cat_page_size - 1)

    for ci = cat_start, cat_end do
        local cname = categories[ci]
        local ccount = #(by_cat[cname] or {})
        local ry = 152 + (ci - cat_start) * 60
        local is_active_cat = (tab == 1 and ci == cat_idx)
        local disp_cat = cname:upper()
        if #disp_cat > 24 then disp_cat = disp_cat:sub(1, 21) .. "..." end

        if is_active_cat then
            draw_rect(115, ry, 370, 54, 46, 70, 104, 245, 958)
            draw_rect(115, ry, 5, 54, 255, 215, 55, 255, 960)
            draw_text(disp_cat, 132, ry + 34, 16, 255, 245, 190, 255, 970)
            draw_text(format("(%d)", ccount), 432, ry + 34, 15, 255, 215, 65, 255, 970)
        else
            draw_rect(115, ry, 370, 54, 22, 28, 39, 215, 957)
            draw_text(disp_cat, 130, ry + 34, 15, 188, 198, 214, 255, 970)
            draw_text(format("(%d)", ccount), 432, ry + 34, 14, 140, 158, 178, 255, 970)
        end
    end

    -- Left Column Bottom Category Prev/Next Buttons
    draw_rect(115, 885, 180, 44, 26, 36, 52, 235, 958)
    draw_text("< PREV [Q]", 152, 913, 15, 210, 222, 238, 255, 970)
    draw_rect(305, 885, 180, 44, 26, 36, 52, 235, 958)
    draw_text("[E] NEXT >", 345, 913, 15, 210, 222, 238, 255, 970)

    -- ==========================================================================
    -- COLUMN 2 (CENTER LIST, X=515..1355) & COLUMN 3 (RIGHT DESCRIPTION, X=1375..1815)
    -- ==========================================================================
    draw_rect(515, 105, 840, 840, 16, 22, 30, 240, 956)
    draw_rect(515, 105, 840, 40, 24, 34, 48, 250, 957)
    draw_rect(515, 143, 840, 2, 235, 195, 45, 220, 958)

    draw_rect(1375, 105, 440, 840, 16, 22, 30, 244, 956)
    draw_rect(1375, 105, 440, 40, 24, 34, 48, 250, 957)
    draw_rect(1375, 105, 440, 4, 255, 215, 55, 255, 959)
    draw_rect(1375, 143, 440, 2, 70, 105, 150, 220, 958)
    draw_text("DESCRIPTION & DETAILS", 1395, 131, 16, 255, 215, 65, 255, 970)

    -- ==========================================================================
    -- TAB 1: MOD OPTIONS (3-COLUMN HELDDIVERS 2 SETTINGS VIEW)
    -- ==========================================================================
    if tab == 1 then
        local active_cat = categories[cat_idx] or "ALL MODS"
        local opt_keys = by_cat[active_cat] or {}
        local total = #opt_keys
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local total_pages = math.max(1, math.ceil(total / page_size))
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        draw_text(format("%s  —  %d OPTIONS (PAGE %d / %d)", active_cat:upper(), total, page + 1, total_pages),
            535, 131, 16, 255, 215, 65, 255, 970)
        draw_rect(1095, 109, 115, 32, 32, 46, 66, 235, 958)
        draw_text("< PAGE", 1122, 130, 14, 215, 225, 240, 255, 970)
        draw_rect(1220, 109, 115, 32, 32, 46, 66, 235, 958)
        draw_text("PAGE >", 1248, 130, 14, 215, 225, 240, 255, 970)

        for i = start_idx, end_idx do
            local id = opt_keys[i]
            local spec = ModOptionsMenu.registered[id]
            local val = ModOptionsMenu.get(id)
            local is_sel = (i == sel)
            local ry = 152 + (i - start_idx) * 60

            local mod_prefix = resolve_text(spec and (spec.mod or spec.category or spec.mod_id), "Mod")
            local opt_label = resolve_text(spec and spec.label, id)
            local row_title = (active_cat == "ALL MODS")
                and format("[%s] %s", mod_prefix, opt_label)
                or opt_label
            if #row_title > 54 then
                row_title = row_title:sub(1, 51) .. "..."
            end

            if is_sel then
                draw_rect(525, ry, 820, 54, 38, 62, 94, 240, 958)
                draw_rect(525, ry, 5, 54, 255, 215, 55, 255, 960)
                draw_text(row_title, 544, ry + 34, 16, 255, 255, 255, 255, 970)
            else
                draw_rect(525, ry, 820, 54, (i % 2 == 0) and 20 or 24, (i % 2 == 0) and 27 or 32, (i % 2 == 0) and 38 or 44, 215, 957)
                draw_text(row_title, 544, ry + 34, 15, 198, 208, 222, 255, 970)
            end

            -- Interactive Right-Side Widget per Option Type
            local otype = spec and spec.type
            if otype == "toggle" or otype == "boolean" or (otype == nil and type(val) == "boolean") then
                local is_on = (val == true)
                -- [ OFF ] box (1045..1180) | [ ON ] box (1185..1320)
                draw_rect(1045, ry + 9, 135, 36, not is_on and 135 or 26, not is_on and 42 or 32, not is_on and 42 or 42, 240, 960)
                draw_rect(1185, ry + 9, 135, 36, is_on and 36 or 26, is_on and 125 or 32, is_on and 64 or 42, 240, 960)
                if not is_on then
                    draw_rect(1045, ry + 42, 135, 3, 255, 120, 120, 255, 962)
                else
                    draw_rect(1185, ry + 42, 135, 3, 100, 245, 140, 255, 962)
                end
                draw_text("OFF", 1096, ry + 33, 15, not is_on and 255 or 130, not is_on and 220 or 140, not is_on and 220 or 155, 255, 970)
                draw_text("ON", 1240, ry + 33, 15, is_on and 230 or 130, is_on and 255 or 140, is_on and 235 or 155, 255, 970)

            elseif otype == "choice" or (spec and type(spec.choices) == "table" and #spec.choices > 0) then
                local count = #spec.choices
                local idx = normalize_option_value(spec, val)
                local choice_lbl = resolve_text(spec.choices[idx], tostring(idx))
                if #choice_lbl > 22 then choice_lbl = choice_lbl:sub(1, 19) .. "..." end

                draw_rect(985, ry + 9, 40, 36, 30, 44, 64, 240, 960)
                draw_text("<", 1000, ry + 33, 16, 255, 215, 65, 255, 970)

                draw_rect(1030, ry + 9, 255, 36, 22, 30, 42, 240, 960)
                local seg_w = math.max(8, floor(255 / math.max(1, count)))
                local seg_x = 1030 + floor((idx - 1) * (255 - seg_w) / math.max(1, count - 1))
                draw_rect(seg_x, ry + 42, seg_w, 3, 255, 215, 55, 255, 962)
                draw_text(choice_lbl, 1045, ry + 33, 15, 245, 215, 95, 255, 970)

                draw_rect(1290, ry + 9, 40, 36, 30, 44, 64, 240, 960)
                draw_text(">", 1305, ry + 33, 16, 255, 215, 65, 255, 970)

            elseif otype == "slider" or otype == "number" or type(val) == "number" then
                local num = tonumber(val) or 0
                local min_v = tonumber(spec and spec.min)
                local max_v = tonumber(spec and spec.max)

                draw_rect(985, ry + 9, 36, 36, 30, 44, 64, 240, 960)
                draw_text("-", 999, ry + 33, 17, 255, 215, 65, 255, 970)

                -- Visual Slider Track (X=1028..1218, W=190)
                draw_rect(1028, ry + 14, 190, 26, 16, 22, 32, 245, 960)
                if min_v and max_v and max_v > min_v then
                    local ratio = (num - min_v) / (max_v - min_v)
                    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
                    local fill_w = math.max(4, floor(186 * ratio))
                    draw_rect(1030, ry + 16, fill_w, 22, 55, 155, 215, 245, 961)
                    draw_rect(1028 + fill_w, ry + 12, 4, 30, 255, 215, 55, 255, 962)
                end

                draw_rect(1225, ry + 9, 36, 36, 30, 44, 64, 240, 960)
                draw_text("+", 1237, ry + 33, 16, 255, 215, 65, 255, 970)
                draw_text(tostring(num), 1270, ry + 33, 15, 125, 220, 255, 255, 970)
            else
                local val_str, vr, vg, vb = format_option_value(spec, val)
                draw_text(val_str, 1140, ry + 33, 15, vr, vg, vb, 255, 970)
            end
        end

        if total == 0 then
            draw_text("No configurable mod options registered in this category.", 545, 220, 17, 160, 170, 180, 255, 970)
        end

        -- Right Column: Selected Option Details & Description Box
        local sel_id = opt_keys[sel]
        local sel_spec = sel_id and ModOptionsMenu.registered[sel_id]
        if sel_spec then
            local sel_mod = resolve_text(sel_spec.mod or sel_spec.category or sel_spec.mod_id, "General")
            local sel_lbl = resolve_text(sel_spec.label, sel_id)
            local cur_str, cr, cg, cb = format_option_value(sel_spec, ModOptionsMenu.get(sel_id))
            local def_str = format_default_value(sel_spec)
            local desc_str = resolve_text(sel_spec.description or sel_spec.tooltip or sel_spec.help,
                "No additional description provided by the mod author.")

            local title_lines = wrap_text_lines(sel_lbl:upper(), 34, 2)
            local ty = 180
            for ti = 1, #title_lines do
                draw_text(title_lines[ti], 1395, ty, 19, 255, 220, 65, 255, 970)
                ty = ty + 26
            end

            draw_rect(1395, 232, 400, 96, 22, 30, 42, 235, 958)
            draw_text(format("MOD:  %s", sel_mod), 1410, 258, 15, 200, 215, 235, 255, 970)
            draw_text(format("CURRENT:  %s", cur_str), 1410, 286, 15, cr, cg, cb, 255, 970)
            draw_text(format("DEFAULT:  %s", def_str), 1410, 314, 14, 155, 175, 198, 255, 970)

            local desc_lines = wrap_text_lines(desc_str, 44, 16)
            local dy = 365
            for li = 1, #desc_lines do
                draw_text(desc_lines[li], 1395, dy, 15, 220, 228, 238, 255, 970)
                dy = dy + 26
            end

            draw_text(format("Option ID: %s", tostring(sel_id)), 1395, 855, 13, 125, 142, 162, 255, 970)

            -- Interactive Reset Button
            draw_rect(1395, 880, 400, 48, 52, 34, 36, 240, 958)
            draw_rect(1395, 925, 400, 3, 235, 185, 55, 255, 960)
            draw_text("[ BACKSPACE / R-CLICK ]  RESET TO DEFAULT", 1425, 910, 15, 255, 220, 130, 255, 970)
        else
            draw_text("Hover or select any option row to inspect its description and default value.",
                1395, 200, 15, 170, 180, 195, 255, 970)
        end

    -- ==========================================================================
    -- TAB 2: KEY BINDINGS (3-COLUMN VIEW WITH INTERACTIVE CAPTURE)
    -- ==========================================================================
    elseif tab == 2 then
        local bind_list = ModBindingsMenu.order
        local total = #bind_list
        local sel = UniversalState.menu_selected or 1
        if sel > total then sel = math.max(1, total); UniversalState.menu_selected = sel end

        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local total_pages = math.max(1, math.ceil(total / page_size))
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        draw_text(format("REGISTERED KEYBINDINGS  —  %d BINDINGS (PAGE %d / %d)", total, page + 1, total_pages),
            535, 131, 16, 255, 215, 65, 255, 970)

        for i = start_idx, end_idx do
            local record = bind_list[i]
            local current_key = ModBindingsMenu.binding(record.id)
            local is_sel = (i == sel)
            local is_rebinding = (UniversalState.menu_rebind_id == record.id)
            local ry = 152 + (i - start_idx) * 60

            local cat_str = resolve_text(record.raw_category or record.category, "General")
            local lbl_str = resolve_text(record.raw_label or record.label, record.id)
            local row_title = format("[%s]  %s", cat_str, lbl_str)
            if #row_title > 54 then row_title = row_title:sub(1, 51) .. "..." end

            if is_rebinding then
                draw_rect(525, ry, 820, 54, 165, 90, 20, 245, 958)
                draw_rect(525, ry, 5, 54, 255, 235, 120, 255, 960)
                draw_text(row_title, 544, ry + 34, 16, 255, 250, 210, 255, 970)
                draw_text(">> PRESS KEY (ESC: CANCEL / DEL: UNBIND) <<", 930, ry + 34, 14, 255, 240, 150, 255, 970)
            elseif is_sel then
                draw_rect(525, ry, 820, 54, 38, 62, 94, 240, 958)
                draw_rect(525, ry, 5, 54, 255, 215, 55, 255, 960)
                draw_text(row_title, 544, ry + 34, 16, 255, 255, 255, 255, 970)
                draw_rect(1015, ry + 9, 210, 36, 24, 36, 54, 245, 960)
                draw_text(format("[ %s ]", tostring(current_key):upper()), 1045, ry + 33, 15, 255, 215, 65, 255, 970)
                draw_rect(1235, ry + 9, 95, 36, 52, 34, 36, 240, 960)
                draw_text("RESET", 1258, ry + 33, 14, 245, 195, 195, 255, 970)
            else
                draw_rect(525, ry, 820, 54, (i % 2 == 0) and 20 or 24, (i % 2 == 0) and 27 or 32, (i % 2 == 0) and 38 or 44, 215, 957)
                draw_text(row_title, 544, ry + 34, 15, 198, 208, 222, 255, 970)
                draw_rect(1015, ry + 9, 210, 36, 20, 28, 40, 235, 960)
                draw_text(format("[ %s ]", tostring(current_key):upper()), 1045, ry + 33, 15, 130, 205, 245, 255, 970)
                draw_rect(1235, ry + 9, 95, 36, 32, 28, 32, 215, 960)
                draw_text("RESET", 1258, ry + 33, 14, 175, 160, 165, 255, 970)
            end
        end

        local sel_rec = bind_list[sel]
        if sel_rec then
            local cat_str = resolve_text(sel_rec.raw_category or sel_rec.category, "General")
            local lbl_str = resolve_text(sel_rec.raw_label or sel_rec.label, sel_rec.id)
            local cur_k = tostring(ModBindingsMenu.binding(sel_rec.id)):upper()
            local def_k = tostring(sel_rec.default or "NONE"):upper()
            local live_down = ModBindingsMenu.is_down(sel_rec.id) and "PRESSED (DOWN)" or "IDLE (UP)"

            draw_text(lbl_str:upper(), 1395, 185, 19, 255, 220, 65, 255, 970)
            draw_rect(1395, 210, 400, 125, 22, 30, 42, 235, 958)
            draw_text(format("MOD:  %s", cat_str), 1410, 238, 15, 200, 215, 235, 255, 970)
            draw_text(format("BOUND KEY:  [%s]", cur_k), 1410, 266, 15, 125, 220, 255, 255, 970)
            draw_text(format("DEFAULT KEY:  [%s]", def_k), 1410, 294, 14, 155, 175, 198, 255, 970)
            draw_text(format("LIVE STATE:  %s", live_down), 1410, 322, 14, 90, 235, 130, 255, 970)

            local help_lines = wrap_text_lines(
                "Left-click the binding row (or press Enter / Space) to capture a new keyboard or mouse button. Press Delete to unbind, Escape/Right-Click to cancel, or click RESET to restore the default binding.",
                44, 8
            )
            local dy = 370
            for li = 1, #help_lines do
                draw_text(help_lines[li], 1395, dy, 15, 215, 225, 235, 255, 970)
                dy = dy + 26
            end

            draw_rect(1395, 880, 400, 48, 52, 34, 36, 240, 958)
            draw_rect(1395, 925, 400, 3, 235, 185, 55, 255, 960)
            draw_text("[ BACKSPACE / R-CLICK ]  RESET BINDING", 1435, 910, 15, 255, 220, 130, 255, 970)
        end

    -- ==========================================================================
    -- TAB 3: LOADED MODS & DIAGNOSTICS (3-COLUMN VIEW)
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

        local page_size = 12
        local page = floor((sel - 1) / page_size)
        local total_pages = math.max(1, math.ceil(total / page_size))
        local start_idx = page * page_size + 1
        local end_idx = min(total, start_idx + page_size - 1)

        draw_text(format("ACTIVE: %d  |  BUILT-IN: %d  |  ERRORS: %d  (PAGE %d / %d)",
            loaded_cnt, builtin_cnt, err_cnt, page + 1, total_pages), 535, 131, 15, 255, 215, 65, 255, 970)
        draw_rect(1095, 109, 115, 32, 32, 46, 66, 235, 958)
        draw_text("< PAGE", 1122, 130, 14, 215, 225, 240, 255, 970)
        draw_rect(1220, 109, 115, 32, 32, 46, 66, 235, 958)
        draw_text("PAGE >", 1248, 130, 14, 215, 225, 240, 255, 970)

        for i = start_idx, end_idx do
            local item = mods_list[i]
            local is_sel = (i == sel)
            local ry = 152 + (i - start_idx) * 60
            local badge, br, bg, bb = "[ ACTIVE ]", 90, 235, 130
            if item.status == "superseded_by_builtin" then
                badge, br, bg, bb = "[ BUILT-IN ]", 110, 210, 250
            elseif item.status ~= "loaded" then
                badge, br, bg, bb = "[ ERROR ]", 240, 95, 95
            end

            if is_sel then
                draw_rect(525, ry, 820, 54, 38, 62, 94, 240, 958)
                draw_rect(525, ry, 5, 54, 255, 215, 55, 255, 960)
                draw_text(tostring(item.name), 544, ry + 34, 16, 255, 255, 255, 255, 970)
            else
                draw_rect(525, ry, 820, 54, (i % 2 == 0) and 20 or 24, (i % 2 == 0) and 27 or 32, (i % 2 == 0) and 38 or 44, 215, 957)
                draw_text(tostring(item.name), 544, ry + 34, 15, 198, 208, 222, 255, 970)
            end
            draw_text(tostring(item.archive or "patch"), 985, ry + 34, 14, 155, 175, 198, 255, 970)
            draw_text(badge, 1215, ry + 34, 15, br, bg, bb, 255, 970)
        end

        local sel_mod = mods_list[sel]
        if sel_mod then
            draw_text(tostring(sel_mod.name):upper(), 1395, 185, 17, 255, 220, 65, 255, 970)
            draw_rect(1395, 210, 400, 100, 22, 30, 42, 235, 958)
            draw_text(format("ARCHIVE:  %s", tostring(sel_mod.archive)), 1410, 240, 15, 200, 215, 235, 255, 970)
            draw_text(format("STATUS:   %s", tostring(sel_mod.status):upper()), 1410, 270, 15, 90, 235, 130, 255, 970)
            draw_text(format("HOOKS:    %d Update Callbacks", #update_order), 1410, 298, 14, 155, 175, 198, 255, 970)

            local diag_msg = "Mod compiled and initialized cleanly inside isolated multi-standard sandbox (Bingus / Chef / BML / HD2RT) with Lua 5.2/5.3 polyfills active."
            if sel_mod.error then
                diag_msg = "Error: " .. tostring(sel_mod.error)
            elseif sel_mod.status == "superseded_by_builtin" then
                diag_msg = "Standalone menu archive automatically superseded by Universal Mod Loader's built-in Escape-Menu MODS Tab (MOM v3 + MBM v4)."
            end
            local dlines = wrap_text_lines(diag_msg, 44, 10)
            local dy = 345
            for li = 1, #dlines do
                draw_text(dlines[li], 1395, dy, 15, 215, 225, 235, 255, 970)
                dy = dy + 26
            end
            draw_text(format("Storage: %s\\settings.json", get_settings_dir()), 1395, 910, 13, 135, 150, 168, 255, 970)
        end
    end

    -- Bottom Footer Action Bar (Y=955..998)
    draw_rect(105, 955, 1710, 44, 20, 27, 38, 245, 957)
    draw_text("MOUSE: Click Categories / Options / Sliders  |  WHEEL: Scroll  |  R-CLICK / BACKSPACE: Reset Default  |  Q/E: Category  |  TAB/1-3: Mode  |  ESC/F2: Close",
        125, 983, 14, 185, 198, 215, 255, 970)
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
log_message("UniversalLoader", "Standards Active: Bingus (API 1 / Runtime v1) | Chef (API 3) | BootModLoader (API 1) | HD2Runtime (0.1.0)")

load_persistent_settings()
discover_installed_mods()

for _, cb in ipairs(UniversalState.after_startup_cbs) do
    pcall(cb)
end

-- If any loaded mod replaced _G.update directly (e.g., SmarterGuardDogsAndSentries or VehicleSeatSwitch),
-- wrap the outermost _G.update so ModBindingsMenu polling happens at the start of every frame BEFORE
-- outer mod wrappers run, and guarantee handle_update runs even if a mod wrapper omits chaining.
if type(rawget(_G, "update")) == "function" and rawget(_G, "update") ~= handle_update then
    local outer_mod_update = rawget(_G, "update")
    local function master_update(dt, ...)
        handle_update_ran = false
        bindings_polled_this_frame = false
        pcall(update_bindings_state)
        local ok, res = pcall(outer_mod_update, dt, ...)
        if not handle_update_ran then
            pcall(handle_update, dt, ...)
        end
        bindings_polled_this_frame = false
        if ok then return res end
    end
    _G.update = master_update
    update = master_update
end
