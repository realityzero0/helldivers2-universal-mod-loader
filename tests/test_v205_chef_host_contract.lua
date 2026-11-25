-- tests/test_v205_chef_host_contract.lua
-- Chef Shared Loader host contract (api 3), as real Chef-hosted mods use it:
--   * the chunk gets the host as `...` and detects it by `type(host.call_kind) == 'function'`
--   * options only reach the menu when `host.has('menu')` is true
--   * the chunk RETURNS its hooks (M.update / M.shutdown) and the loader calls them every frame / at exit
--   * a global `chef` exists in the mod's own environment
--   * call_kind(name, kind, ...) and call(name, ...) are crash-guarded engine calls by 'Table.function' name
--   * "-- HD2-Options: <mod>" resources are the mod manager's options for a mod, not mods
--   * a mod that hooks the game's update() itself is not also run as a returned hook (no double frames)
-- Every check here failed on v2.0.4 (mods loaded "fine" and then never ran).

local FAMILY = "9ba626afa44a3aa3"
local SANDBOX = "tests/tmp_v205"
os.execute('mkdir "tests\\tmp_v205\\Arrowhead\\Helldivers2" 2>nul')
os.execute('mkdir "data" 2>nul')

local real_getenv = os.getenv
os.getenv = function(k)
    if k == "APPDATA" or k == "LOCALAPPDATA" then return SANDBOX end
    return real_getenv(k)
end

local function u32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end
local LUA_TYPE = string.char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
local function build_patch(key_byte, src)
    local header = u32(0xF0000011) .. u32(1) .. u32(1) .. string.rep("\0", 60)
    local type_tbl = string.rep("\0", 8) .. LUA_TYPE .. string.rep("\0", 16)
    local off = 72 + 32 + 80
    local body = u32(#src) .. u32(2) .. src
    local row = string.rep(string.char(key_byte), 8) .. LUA_TYPE .. u32(off) .. u32(0) .. string.rep("\0", 32) .. u32(#body) .. string.rep("\0", 20)
    return header .. type_tbl .. row .. body
end
local written = {}
local function put_patch(n, key_byte, src)
    local p = "data/" .. FAMILY .. ".patch_" .. n
    local f = assert(io.open(p, "wb")); f:write(build_patch(key_byte, src)); f:close()
    written[#written + 1] = p
end

-- 1. a Chef-hosted mod written exactly like Reticle Ammo HUD 2 (host detection, has('menu'), returned hooks)
put_patch(490, 0xC1, [[
-- HD2-Addon: mods/contract/chef_hud
local HOST_ARG = ...
local CHEF_HOST = type(HOST_ARG) == 'table' and type(HOST_ARG.call_kind) == 'function'
local M = { chef_host = CHEF_HOST, frames = 0, menu = false, opts = nil }
if CHEF_HOST then
    local chef = HOST_ARG
    M.menu = chef.has('menu') == true
    if M.menu then M.size = chef.option('ch_size', { type = 'slider', min = 50, max = 200, step = 10, default = 100, label = 'Size' }) end
    M.opts = chef.options
    M.key = chef.bind('ch_toggle', 'f6', 'Show / hide')
end
function M.update(dt)
    local chef = HOST_ARG
    M.frames = M.frames + 1
    M.last_dt = dt
    M.t = chef.time()
    M.alive = chef.call_kind('Unit.alive', 'unit', 'u1')
    M.missing = select(2, chef.call('Nope.nothing'))
    M.world = chef.world()
    M.in_mission = chef.in_mission()
    chef.rect(100, 100, 40, 8, chef.color(255, 255, 255, 255), 900)
    chef.triangle(0, 0, 10, 0, 5, 10, chef.color(255, 0, 0, 255), 900)
end
function M.render()
    M.renders = (M.renders or 0) + 1
end
function M.shutdown() M.closed = true end
rawset(_G, 'CONTRACT_CHEF_HUD', M)
return M
]])
-- 2. its mod-manager options resource
put_patch(491, 0xC2, "-- HD2-Options: mods/contract/chef_hud\nreturn { style = 'ring', size = 120 }\n")
-- 3. a mod using the global `chef`, chef.title, chef.watch and saved tables (the Nexus failure log)
put_patch(492, 0xC3, [[
-- HD2-Addon: mods/contract/global_chef
chef.title('Global Chef Probe')
chef.option('gc_on', { type = 'toggle', default = true, label = 'On' })
local w = chef.watch({ ['00000000deadbeef'] = true }, 1)
local saved = chef.load_table('s') or { runs = 0 }
saved.runs = saved.runs + 1
chef.save_table('s', saved)
local M = { frames = 0, watch = w }
function M.update() M.frames = M.frames + 1 M.items = #w.items end
rawset(_G, 'CONTRACT_GLOBAL_CHEF', M)
return M
]])
-- 4. a mod that hooks the game's update() itself AND returns an update: must run once a frame, not twice
put_patch(493, 0xC4, [[
-- HD2-Addon: mods/contract/self_hooked
local M = { frames = 0 }
function M.update() M.frames = M.frames + 1 end
local prev = rawget(_G, 'update')
rawset(_G, 'update', function(...) M.update() if prev then return prev(...) end end)
rawset(_G, 'CONTRACT_SELF_HOOKED', M)
return M
]])

-- engine mock
local shapes = 0
local main_world, ui_world = { id = "main" }, { id = "ui" }
local wtime = 0
local mock_hooks = {}
local Vector3 = setmetatable({ to_elements = function(v) return v.x, v.y, v.z end }, { __call = function(_, x, y, z) return { x = x, y = y, z = z } end })
_G.stingray = {
    Application = { main_world = function() return main_world end, worlds = function() return { main_world, ui_world } end,
        user_setting = function() return nil end },
    World = { time = function() return wtime end, num_units = function() return 6000 end, units = function() return { "u1" } end,
        units_by_resource = function() return { "u1" } end,
        create_screen_gui = function(w)
            if mock_hooks.create_screen_gui then return mock_hooks.create_screen_gui(w) end
            return { world = w }
        end,
        destroy_gui = function(w, g)
            if mock_hooks.destroy_gui then return mock_hooks.destroy_gui(w, g) end
        end },
    Gui = { rect = function() shapes = shapes + 1 end, triangle = function() shapes = shapes + 1 end,
        resolution = function()
            if mock_hooks.resolution then return mock_hooks.resolution() end
            return 1920, 1080
        end },
    Unit = { alive = function(u) return u == "u1" or (type(u) == "table" and u.alive == true) end, world_position = function() return Vector3(1, 2, 3) end },
    IdString64 = { from_hex = function(h) return "id:" .. h end },
    Vector3 = Vector3, Vector2 = function(x, y) return { x = x, y = y } end,
    Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
    Keyboard = { button_index = function(n) return ({ f9 = 119, f6 = 117 })[n] end, button = function() return 0 end,
        button_id = function(n) return ({ f9 = 119, f6 = 117 })[n] end, pressed = function() return false end },
    Window = { has_focus = function()
        if mock_hooks.has_focus then return mock_hooks.has_focus() end
        return true
    end },
}
_G.Keyboard, _G.Window = _G.stingray.Keyboard, _G.stingray.Window

print("====================================================")
print("Testing Chef Shared Loader Host Contract (api 3)")
print("====================================================")
local pass, total = 0, 0
local function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then pass = pass + 1 print("  [PASS] " .. name) else print("  [FAIL] " .. name .. ": " .. tostring(err)) end
end

local ok_boot, boot_err = pcall(function() assert(loadfile("src/boot_loader.lua"))() end)
for i = 1, 260 do wtime = wtime + 0.016 _G.update(0.016) end

local function read_log()
    local f = io.open(SANDBOX .. "/Arrowhead/Helldivers2/UniversalModLoader.log", "rb")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s
end
local LOG = read_log()
local mom = _G.ModOptionsMenu
local HUD, GC, SELF = rawget(_G, "CONTRACT_CHEF_HUD"), rawget(_G, "CONTRACT_GLOBAL_CHEF"), rawget(_G, "CONTRACT_SELF_HOOKED")

test("boot_loader boots with the contract mods installed", function() assert(ok_boot, boot_err) end)
test("the host is detected as Chef by call_kind (Reticle Ammo HUD 2's check)", function() assert(HUD and HUD.chef_host == true) end)
test("has('menu') is true, so chef.option reaches the F9 menu", function()
    assert(HUD.menu == true, "has('menu') false")
    assert(mom.registered["ch_size"], "option not registered")
    assert(HUD.size == 100, "option() must return the current value, got " .. tostring(HUD.size))
end)
test("chef.bind registers a key row and returns a handle (key / pressed / down)", function()
    assert(mom.registered["ch_toggle"] and mom.registered["ch_toggle"].type == "key")
    assert(type(HUD.key) == "table" and HUD.key.key() == "f6" and HUD.key.pressed() == false)
end)
test("the returned M.update runs every frame", function() assert(HUD.frames >= 250, "frames=" .. tostring(HUD.frames)) end)
test("chef.time() is the host clock", function() assert(type(HUD.t) == "number" and HUD.t > 4, tostring(HUD.t)) end)
test("call_kind(name, kind, ...) is a crash-guarded engine call by name", function() assert(HUD.alive == true) end)
test("call() of a missing engine function returns nil, 'missing' (no throw)", function() assert(HUD.missing == "missing") end)
test("world() / in_mission() follow the main world (3 s settle, > 5000 units)", function()
    assert(HUD.world == main_world, "world() not the main world")
    assert(HUD.in_mission == true, "in_mission false")
end)
test("chef.rect / chef.triangle draw in an immediate screen GUI once the world has settled (3 s)", function()
    -- 260 frames of 16 ms: drawing starts when the main world is 3 s old (frame ~188), 2 shapes a frame after that
    local settle = math.ceil(3 / 0.016)
    local expected = 2 * (260 - settle)
    assert(math.abs(shapes - expected) <= 4, "shapes=" .. shapes .. " expected~" .. expected)
end)
test("HD2-Options resources become chef.options, not mods", function()
    assert(type(HUD.opts) == "table" and HUD.opts.style == "ring" and HUD.opts.size == 120, "options not merged")
    assert(not LOG:find("Loaded mod: 0x", 1, true), "an options resource was run as a mod")
    assert(LOG:find("Mod manager options for mods/contract/chef_hud", 1, true), "absorb not logged")
end)
test("a global `chef` exists in the mod's environment", function() assert(GC and GC.frames >= 250) end)
test("chef.title names the mod's F9 group", function()
    assert(mom.registered["gc_on"] and mom.registered["gc_on"].mod == "GLOBAL CHEF PROBE", tostring(mom.registered["gc_on"] and mom.registered["gc_on"].mod))
end)
test("chef.watch tracks units of a resource in the main world", function() assert(GC.items == 1, "items=" .. tostring(GC.items)) end)
test("chef.save_table / load_table round-trip in the mod's own file", function()
    local f = io.open(SANDBOX .. "/Arrowhead/Helldivers2/chef_global_chef_s.lua", "rb")
    assert(f, "saved table missing"); local s = f:read("*a"); f:close()
    assert(s:find("runs", 1, true))
end)
test("a mod that hooked update() itself is not also run as a returned hook", function()
    assert(SELF and SELF.frames >= 250 and SELF.frames <= 262, "frames=" .. tostring(SELF and SELF.frames))
    assert(not LOG:find("[ChefHost] mods/contract/self_hooked", 1, true), "self-hooked mod was adopted too")
end)
test("the returned M.shutdown runs at exit", function()
    if type(_G.shutdown) == "function" then _G.shutdown() end
    assert(HUD.closed == true)
end)
test("legacy call_kind(kind, fn, ...) form still works", function()
    local ok, res = _G.ChefSharedLoader.call_kind("legacy", function(a) return a * 2 end, 21)
    assert(ok == true and res == 42)
end)
test("chef.load / chef.save and chef.options.load / save / title work", function()
    local c = _G.ChefSharedLoader
    assert(c.has("load") and c.has("save") and c.has("title"))
    assert(c.options.title("Opt Title") == true)
    assert(c.save("fp_cfg", { fov = 95 }) == true)
    local t = c.load("fp_cfg")
    assert(type(t) == "table" and t.fov == 95)
    assert(c.options.save("op_cfg", { zoom = 2 }) == true)
    local t2 = c.options.load("op_cfg")
    assert(type(t2) == "table" and t2.zoom == 2)
end)
test("CowboyBingusModLoader exposes log_directory and version >= 19", function()
    local cb = _G.CowboyBingusModLoader
    assert(type(cb) == "table" and cb.version >= 19)
    assert(type(cb.log_directory) == "string" and #cb.log_directory > 5)
end)
test("loadstring sanitizes LuaJIT forward goto continue blocks", function()
    local src = [[
        local sum = 0
        local visited = { [2] = true }
        local w = 0
        while w < 4 do
            w = w + 1
            if visited[w] then goto next end
            sum = sum + w
            ::next::
        end
        return sum
    ]]
    local fn, err = loadstring(src, "@seaf_goto_test")
    assert(type(fn) == "function", tostring(err))
    assert(fn() == (1 + 3 + 4))
end)
test("chef.text(x, y, str, px, c, layer) and chef.text_width(str, px) follow Chef's 5x7 scale contract", function()
    local c = _G.ChefSharedLoader
    local cap = 14
    local w = c.text_width("0", cap / 7)
    assert(type(w) == "number" and w == 12, "expected width 12 for 1 char at px=2, got " .. tostring(w))
    local before = shapes
    c.text(120, 340, "30", cap / 7, c.color(255, 255, 255, 255), 910)
    assert(shapes > before, "chef.text(x, y, str, px, c, layer) did not draw")
end)
test("chef.camera() returns position, basis vectors (fx/fy/fz, rx/ry/rz, ux/uy/uz), yaw, and fov", function()
    _G.stingray.Unit.num_cameras = function() return 1 end
    _G.stingray.Unit.camera = function() return "cam1" end
    _G.stingray.Camera = {
        world_position = function() return Vector3(10, 20, 30) end,
        world_rotation = function() return "q1" end,
        vertical_fov = function() return 1.05 end
    }
    _G.stingray.Quaternion = {
        forward = function() return Vector3(0, 1, 0) end,
        right = function() return Vector3(1, 0, 0) end,
        up = function() return Vector3(0, 0, 1) end
    }
    _G.update(0.016)
    local cam = _G.ChefSharedLoader.camera()
    assert(type(cam) == "table" and cam.x == 10 and cam.y == 20 and cam.z == 30)
    assert(cam.fx == 0 and cam.fy == 1 and cam.fz == 0)
    assert(cam.rx == 1 and cam.ry == 0 and cam.rz == 0)
    assert(cam.ux == 0 and cam.uy == 0 and cam.uz == 1)
    assert(type(cam.yaw) == "number" and math.abs(cam.fov - 1.05) < 1e-6)
end)
test("chef.unit_rotation(u, node) returns fx, fy, fz and yaw as the 4th return value", function()
    _G.stingray.Unit.world_rotation = function() return "q1" end
    local fx, fy, fz, yaw = _G.ChefSharedLoader.unit_rotation("u1", 1)
    assert(fx == 0 and fy == 1 and fz == 0 and type(yaw) == "number" and math.abs(yaw - math.pi / 2) < 1e-6)
end)
test("Unit.debug_name is cached per unit so repeated scans do not re-query the engine", function()
    local calls = 0
    local u_obj = { id = "cached_u" }
    _G.stingray.Unit.debug_name = function(u)
        calls = calls + 1
        return "#ID[0123456789abcdef]"
    end
    local n1 = _G.ChefSharedLoader.call_kind("Unit.debug_name", "unit", u_obj)
    local n2 = _G.ChefSharedLoader.call_kind("Unit.debug_name", "unit", u_obj)
    assert(n1 == "#ID[0123456789abcdef]" and n2 == n1 and calls == 1, "calls=" .. tostring(calls))
end)
test("chef.bitmap_uv binds textures onto Chef UI material e2d6ed90906c1e8b via per-texture GUIs", function()
    local c = _G.ChefSharedLoader
    local set_calls, draw_calls = {}, {}
    local orig_create = _G.stingray.World.create_screen_gui
    local gui_seq = 0
    _G.stingray.World.create_screen_gui = function(w, ...)
        gui_seq = gui_seq + 1
        return { world = w, seq = gui_seq }
    end
    _G.stingray.Application.can_get = function(kind, id)
        return (kind == "material" and id == "id:e2d6ed90906c1e8b")
            or (kind == "texture" and (id == "id:5bcac239976d1a4a" or id == "id:135b87a4ff182040"))
    end
    _G.stingray.Gui.material = function(g, mid)
        assert(mid == "id:e2d6ed90906c1e8b", "expected UI material id, got " .. tostring(mid))
        return { mat_for_gui = g }
    end
    _G.stingray.Material = {
        set_texture = function(mh, sid, pid)
            set_calls[#set_calls + 1] = { gui = mh.mat_for_gui, sid = sid, pid = pid }
        end
    }
    _G.stingray.Gui.bitmap_uv = function(g, mid, u0, u1, pos, sz, col)
        draw_calls[#draw_calls + 1] = { gui = g, mid = mid }
    end
    local col = c.color(255, 255, 255, 255)
    local r1 = c.bitmap_uv("5bcac239976d1a4a", 0, 0, 0.5, 0.5, 100, 200, 32, 32, col, 900)
    local r2 = c.bitmap_uv("135b87a4ff182040", 0, 0, 1, 1, 150, 200, 32, 32, col, 900)
    _G.stingray.World.create_screen_gui = orig_create
    assert(r1 == true and r2 == true, "bitmap_uv returned false")
    assert(#set_calls == 2 and #draw_calls == 2, "expected 2 set_texture and 2 bitmap_uv calls")
    assert(set_calls[1].sid == "id:3aa8b87e00000000" and set_calls[1].pid == "id:5bcac239976d1a4a")
    assert(set_calls[2].sid == "id:3aa8b87e00000000" and set_calls[2].pid == "id:135b87a4ff182040")
    assert(draw_calls[1].mid == "id:e2d6ed90906c1e8b" and draw_calls[2].mid == "id:e2d6ed90906c1e8b")
    assert(draw_calls[1].gui ~= draw_calls[2].gui, "each texture must use its own GUI handle")
end)
test("chef.text renders tilde '~' cleanly without falling back to '?'", function()
    local c = _G.ChefSharedLoader
    local col = c.color(255, 255, 255, 255)
    local b0 = shapes
    c.text(100, 200, "~", 2, col, 910)
    local tilde_rects = shapes - b0
    local b1 = shapes
    c.text(100, 200, "?", 2, col, 910)
    local q_rects = shapes - b1
    local b2 = shapes
    c.text(100, 200, "~378 s", 2, col, 910)
    assert(tilde_rects > 0 and tilde_rects ~= q_rects, "tilde fell back to '?' (" .. tilde_rects .. " vs " .. q_rects .. ")")
    assert(shapes - b2 > 0, "~378 s drew no rects")
end)
test("chef.call resolves callable tables with __call (Vector3 / Vector2) while rejecting non-callable tables", function()
    local c = _G.ChefSharedLoader
    local orig_v2 = _G.stingray.Vector2
    _G.stingray.Vector2 = setmetatable({ marker = true }, { __call = function(_, x, y) return { x = x, y = y, callable_v2 = true } end })
    local v3, err3 = c.call("Vector3", 1, 2, 3)
    local v2, err2 = c.call("Vector2", 4, 5)
    local bad, bad_err = c.call("World")
    _G.stingray.Vector2 = orig_v2
    assert(type(v3) == "table" and v3.x == 1 and v3.y == 2 and v3.z == 3, "Vector3 call failed: " .. tostring(err3))
    assert(type(v2) == "table" and v2.x == 4 and v2.y == 5 and v2.callable_v2 == true, "Vector2 call failed: " .. tostring(err2))
    assert(bad == nil and bad_err == "missing", "non-callable table should fail as missing, got " .. tostring(bad_err))
end)
test("chef.line dispatches after mod updates and resets before adding lines on active frames", function()
    local c = _G.ChefSharedLoader
    local lo_events = {}
    local line_obj = { id = "lo1" }
    _G.stingray.World.create_line_object = function(w)
        lo_events[#lo_events + 1] = "create"
        return line_obj
    end
    _G.stingray.LineObject = {
        reset = function(lo)
            assert(lo == line_obj)
            lo_events[#lo_events + 1] = "reset"
        end,
        add_line = function(lo, col, a, b)
            assert(lo == line_obj)
            lo_events[#lo_events + 1] = "add_line"
        end,
        dispatch = function(w, lo)
            assert(w == main_world and lo == line_obj)
            lo_events[#lo_events + 1] = "dispatch"
        end
    }
    -- Frame 1: mod draws two lines during update(); master_update dispatches at end without trailing reset.
    local prev_upd = rawget(_G, "update")
    local drew_this_frame = false
    c.on("update", function()
        if not drew_this_frame then
            drew_this_frame = true
            c.line(0, 0, 0, 1, 2, 3, c.color(255, 255, 255, 255))
            c.line(1, 2, 3, 4, 5, 6, c.color(255, 255, 255, 255))
        end
    end)
    wtime = wtime + 0.016
    _G.update(0.016)
    assert(table.concat(lo_events, ",") == "create,reset,add_line,add_line,dispatch",
        "unexpected Frame 1 LineObject sequence: " .. table.concat(lo_events, ","))
    -- Frame 2: mod draws no lines -> post_step clears retained buffer with reset + dispatch.
    lo_events = {}
    wtime = wtime + 0.016
    _G.update(0.016)
    assert(table.concat(lo_events, ",") == "reset,dispatch",
        "unexpected Frame 2 clear sequence: " .. table.concat(lo_events, ","))
    -- Frame 3: still idle -> zero LineObject calls.
    lo_events = {}
    wtime = wtime + 0.016
    _G.update(0.016)
    assert(#lo_events == 0, "expected 0 LineObject calls on Frame 3, got " .. table.concat(lo_events, ","))
    local _ = prev_upd
end)
test("chef.world_to_screen returns nil behind the camera and coordinates in front", function()
    local c = _G.ChefSharedLoader
    local wts_calls = 0
    _G.stingray.Camera.world_to_screen = function(cam, v)
        wts_calls = wts_calls + 1
        return Vector3(640, 360, v.y)
    end
    wtime = wtime + 0.016
    _G.update(0.016)
    -- Camera at (10, 20, 30), forward (0, 1, 0): behind point has y <= 20.1
    local bx, by = c.world_to_screen(10, 15, 30)
    assert(bx == nil and by == nil and wts_calls == 0, "behind-camera point should be culled before Camera.world_to_screen")
    local fx, fy, fz = c.world_to_screen(10, 35, 30)
    assert(fx == 640 and fy == 360 and fz == 35 and wts_calls == 1, "in-front world_to_screen mismatch")
end)
test("chef.spawn creates a unit (with Quaternion.identity fallback) and destroys it on World.time reset", function()
    local c = _G.ChefSharedLoader
    local spawned = { id = "decal_u1", alive = true }
    local destroyed = 0
    local spawn_calls = 0
    _G.stingray.Quaternion.identity = function() return "q_ident" end
    _G.stingray.World.spawn_unit = function(w, id, pos, q)
        spawn_calls = spawn_calls + 1
        if q == nil then return nil end
        return spawned
    end
    _G.stingray.World.destroy_unit = function(w, u)
        if w == main_world and u == spawned then
            destroyed = destroyed + 1
            spawned.alive = false
        end
    end
    local u, err = c.spawn("1b798f4f99a0b8c8", 12, 34, 56)
    assert(u == spawned and spawn_calls == 2, "expected Quaternion fallback spawn, err=" .. tostring(err))
    -- Trigger World.time reset (< wtime)
    wtime = 0.01
    _G.update(0.016)
    assert(destroyed == 1 and spawned.alive == false, "expected spawned unit destroyed on World.time reset, got " .. destroyed)
end)
test("Alt-Tab focus return, resolution reset, and Gui error rebuild ScreenGuis cleanly", function()
    local c = _G.ChefSharedLoader
    local created_guis, destroyed_guis = 0, 0
    local focused_state = true
    local res_w, res_h = 1920, 1080
    local fail_rect_once = false
    local rect_draws = 0

    mock_hooks.has_focus = function() return focused_state end
    mock_hooks.resolution = function() return res_w, res_h end
    local prev_rect = _G.stingray.Gui.rect
    _G.stingray.Gui.rect = function(g, ...)
        assert(g and not g.destroyed, "drew on destroyed ScreenGui")
        if fail_rect_once then
            fail_rect_once = false
            error("simulated invalidated ScreenGui")
        end
        rect_draws = rect_draws + 1
    end
    mock_hooks.create_screen_gui = function(w)
        created_guis = created_guis + 1
        return { world = w, id = "gui_" .. created_guis, destroyed = false }
    end
    mock_hooks.destroy_gui = function(w, g)
        if g then g.destroyed = true end
        destroyed_guis = destroyed_guis + 1
    end

    -- Wait past the 3 s world grace window after World.time reset above
    for _ = 1, 200 do
        wtime = wtime + 0.02
        _G.update(0.02)
    end
    assert(created_guis >= 1 and rect_draws >= 1, "expected initial ScreenGui creation")
    local before_alt = created_guis
    local draws_before_alt = rect_draws

    -- Simulate Alt-Tab out (focus lost, minimized 0x0) and back in
    focused_state, res_w, res_h = false, 0, 0
    wtime = wtime + 0.02
    _G.update(0.02)
    focused_state, res_w, res_h = true, 1920, 1080
    wtime = wtime + 0.02
    _G.update(0.02)
    assert(destroyed_guis >= 1, "expected stale ScreenGui destroyed on Alt-Tab focus/resolution return")
    assert(created_guis >= before_alt + 1 and rect_draws > draws_before_alt, "expected fresh ScreenGui created and drawn after Alt-Tab")

    -- Simulate Gui.rect failing on a stale Gui: must self-heal on next draw
    local before_heal = created_guis
    local draws_before_heal = rect_draws
    fail_rect_once = true
    wtime = wtime + 0.02
    _G.update(0.02)
    c.rect(10, 10, 20, 20, c.color(255, 255, 255, 255), 900)
    assert(created_guis >= before_heal + 1 and rect_draws > draws_before_heal, "expected self-healing ScreenGui after Gui.rect failure")
    mock_hooks.has_focus, mock_hooks.resolution, mock_hooks.create_screen_gui, mock_hooks.destroy_gui = nil, nil, nil, nil
    _G.stingray.Gui.rect = prev_rect
end)
test("Chef update hooks clamp huge Alt-Tab dt spikes", function()
    local m = rawget(_G, "CONTRACT_CHEF_HUD")
    assert(type(m) == "table")
    wtime = wtime + 0.02
    _G.update(25.0)
    assert(type(m.last_dt) == "number" and m.last_dt > 0 and m.last_dt <= 0.5, "expected clamped dt, got " .. tostring(m.last_dt))
end)
test("returned M.render hook and chef.on('render') run during engine render()", function()
    local m = rawget(_G, "CONTRACT_CHEF_HUD")
    local extra_renders = 0
    _G.ChefSharedLoader.on("render", function() extra_renders = extra_renders + 1 end)
    local before = m.renders or 0
    _G.render()
    _G.render()
    assert((m.renders or 0) == before + 2, "expected returned M.render to run twice, got " .. tostring((m.renders or 0) - before))
    assert(extra_renders == 2, "expected chef.on('render') to run twice, got " .. tostring(extra_renders))
end)
test("chef.watch().stop() stops and removes the watch cleanly without error", function()
    local w = _G.ChefSharedLoader.watch({ ["00000000cafebabe"] = true }, 1)
    assert(type(w.stop) == "function", "watch handle must expose stop()")
    w.stop()
    assert(w.stopped == true and w.paused == true and #w.items == 0)
end)
test("nothing was written to the real %APPDATA%", function()
    local real = real_getenv("APPDATA")
    if real then assert(not LOG:find(real, 1, true)) end
end)

for _, p in ipairs(written) do os.remove(p) end
os.execute('rmdir /s /q "tests\\tmp_v205" 2>nul')
os.remove("uml_mod_settings.json")

print("----------------------------------------------------")
print(string.format("RESULTS: %d / %d Chef host contract tests passed.", pass, total))
if pass == total then print("STATUS: CHEF HOST CONTRACT VERIFIED.") end
print("====================================================")
os.exit(pass == total and 0 or 1)
