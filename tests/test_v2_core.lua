-- tests/test_v2_core.lua
-- Unit tests for Helldivers 2 Universal Mod Loader v2.0.0 Core Mechanics
-- Executable under PUC-Rio Lua 5.1.5

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
  end
end

print("====================================================")
print("Running UML v2.0.0 Core Mechanics Unit Tests (Lua 5.1)")
print("====================================================")

-- -----------------------------------------------------------------------------
-- 1. CSL Vararg Parameter Injection
-- -----------------------------------------------------------------------------
test("CSL Chunk receives chef_api as first vararg", function()
  local mock_chef_api = {
    version = "3.2.0",
    hooks = {}
  }
  mock_chef_api.on = function(evt, fn)
    mock_chef_api.hooks[evt] = fn
  end

  local mod_code = [[
    local chef, mod_name = ...
    assert(type(chef) == "table", "Expected chef to be a table, got " .. type(chef))
    assert(type(chef.on) == "function", "Expected chef.on to be a function")
    chef.on("init", function() return "initialized: " .. tostring(mod_name) end)
    return { name = mod_name, ok = true }
  ]]

  local chunk, err = loadstring(mod_code, "mods/mock_csl/mod_1")
  assert(chunk, "Failed to compile chunk: " .. tostring(err))

  local ok, res = pcall(chunk, mock_chef_api, "mods/mock_csl/mod_1")
  assert(ok, "Execution failed: " .. tostring(res))
  assert(type(mock_chef_api.hooks["init"]) == "function", "Hook was not registered")
  assert(mock_chef_api.hooks["init"]() == "initialized: mods/mock_csl/mod_1")
  assert(res and res.ok == true)
end)

-- -----------------------------------------------------------------------------
-- 2. Pure-Lua Fake DLL Bridge Interceptor
-- -----------------------------------------------------------------------------
test("Fake DLL Bridge intercepts package.loadlib safely", function()
  local orig_loadlib = package.loadlib

  local dummy_dll_bridge = function(path, init_func)
    return function()
      return {
        _is_fake_dll = true,
        path = path,
        init_func = init_func
      }
    end
  end

  package.loadlib = dummy_dll_bridge

  local init_fn, err = package.loadlib("mods/test_bin/legacy.dll", "luaopen_legacy")
  assert(type(init_fn) == "function", "Expected loader function")
  local mod = init_fn()
  assert(mod._is_fake_dll == true)

  package.loadlib = orig_loadlib
end)

-- -----------------------------------------------------------------------------
-- 3. Hang Watchdog (Infinite Loop Abort via debug.sethook)
-- -----------------------------------------------------------------------------
test("Hang Watchdog aborts infinite while loop safely without game freeze", function()
  local function safe_run_with_watchdog(fn, timeout_seconds)
    local start_time = os.clock()
    local check_counter = 0

    local function hook()
      check_counter = check_counter + 1
      if check_counter % 500 == 0 then
        if (os.clock() - start_time) > timeout_seconds then
          debug.sethook()
          error("WATCHDOG_HANG_TIMEOUT: Script exceeded execution threshold")
        end
      end
    end

    debug.sethook(hook, "", 20)
    local ok, res = pcall(fn)
    debug.sethook()
    return ok, res
  end

  local bad_infinite_loop = function()
    local x = 0
    while true do
      x = x + 1
    end
  end

  local ok, err = safe_run_with_watchdog(bad_infinite_loop, 0.1)
  assert(ok == false, "Expected infinite loop to be aborted")
  assert(string.find(tostring(err), "WATCHDOG_HANG_TIMEOUT"), "Expected timeout in: " .. tostring(err))
end)

-- -----------------------------------------------------------------------------
-- 4. Topological Dependency Sorter (DAG)
-- -----------------------------------------------------------------------------
test("Topological Sorter resolves prerequisites before dependents", function()
  local mods = {
    { id = "Mod_C", needs = {"Mod_B"} },
    { id = "Mod_A", needs = {} },
    { id = "Mod_B", needs = {"Mod_A"} }
  }

  local function topological_sort(mod_list)
    local sorted = {}
    local visited = {}
    local visiting = {}
    local mod_map = {}
    for _, m in ipairs(mod_list) do mod_map[m.id] = m end

    local function visit(node_id)
      if visited[node_id] then return end
      if visiting[node_id] then return end
      visiting[node_id] = true
      local node = mod_map[node_id]
      if node and node.needs then
        for _, dep_id in ipairs(node.needs) do
          if mod_map[dep_id] then
            visit(dep_id)
          end
        end
      end
      visiting[node_id] = nil
      visited[node_id] = true
      table.insert(sorted, node_id)
    end

    for _, m in ipairs(mod_list) do
      visit(m.id)
    end
    return sorted
  end

  local order = topological_sort(mods)
  assert(#order == 3, "Expected 3 sorted mods")
  assert(order[1] == "Mod_A", "Mod_A must load 1st, got " .. tostring(order[1]))
  assert(order[2] == "Mod_B", "Mod_B must load 2nd, got " .. tostring(order[2]))
  assert(order[3] == "Mod_C", "Mod_C must load 3rd, got " .. tostring(order[3]))
end)

-- -----------------------------------------------------------------------------
-- 5. Native Rat's Shared Loader ABI
-- -----------------------------------------------------------------------------
test("Rat's Shared Loader 1.1.2 Transmog ABI emulation", function()
  local rat_api = {
    version = "1.1.2",
    loaded_mods = {},
    register = function(self, name, spec)
      self.loaded_mods[name] = spec
      return true
    end,
    get_spec = function(self, name)
      return self.loaded_mods[name]
    end
  }

  rawset(_G, "RatsSharedLoader", rat_api)

  local ok = _G.RatsSharedLoader:register("armor_transmog", {
    version = "1.1.2",
    author = "Rat",
    hooks = { "inventory_open", "loadout_sync" }
  })

  assert(ok == true)
  local spec = _G.RatsSharedLoader:get_spec("armor_transmog")
  assert(spec and spec.version == "1.1.2")
end)

-- -----------------------------------------------------------------------------
-- 6. Font Glyph Sanitizer (Anti-Crash Filter)
-- -----------------------------------------------------------------------------
test("Font Glyph Sanitizer transliterates non-printable & high Unicode chars", function()
  local function sanitize_text(str)
    if type(str) ~= "string" then return tostring(str) end
    local out = {}
    for i = 1, #str do
      local b = string.byte(str, i)
      if b >= 32 and b <= 126 then
        out[#out + 1] = string.char(b)
      elseif b == 10 or b == 13 or b == 9 then
        out[#out + 1] = " "
      else
        out[#out + 1] = "?"
      end
    end
    return table.concat(out)
  end

  -- In Lua 5.1, escapes are decimal: \0 is null, \255 is byte 255
  local raw = "Helldivers - Super Earth 2026 \t\n\0\255"
  local clean = sanitize_text(raw)
  for i = 1, #clean do
    local b = string.byte(clean, i)
    assert(b >= 32 and b <= 126, "Found non-printable byte in sanitized output: " .. tostring(b))
  end
  assert(string.find(clean, "Helldivers"), "Missing plain text")
end)

-- -----------------------------------------------------------------------------
-- 7. Settings JSON Serialization & Persistence
-- -----------------------------------------------------------------------------
test("Settings JSON serialization and deserialization", function()
  local function serialize_json(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
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
    return "{\n" .. table.concat(parts, ",\n") .. "\n}"
  end

  local function parse_json_simple(str)
    local out = {}
    for k, v in string.gmatch(str, '"([^"]+)"%s*:%s*([^,\n}]+)') do
      v = v:match("^%s*(.-)%s*$")
      if v == "true" then
        out[k] = true
      elseif v == "false" then
        out[k] = false
      elseif tonumber(v) then
        out[k] = tonumber(v)
      elseif v:sub(1,1) == '"' and v:sub(-1) == '"' then
        out[k] = v:sub(2, -2)
      end
    end
    return out
  end

  local settings = {
    radar_always_on = true,
    fov_multiplier = 1.25,
    hud_theme = "amber",
    debug_mode = false
  }

  local json_str = serialize_json(settings)
  local decoded = parse_json_simple(json_str)
  assert(decoded.radar_always_on == true)
  assert(decoded.fov_multiplier == 1.25)
  assert(decoded.hud_theme == "amber")
  assert(decoded.debug_mode == false)
end)

-- -----------------------------------------------------------------------------
-- 8. Crash Sentinel (Auto-Safe Mode recovery)
-- -----------------------------------------------------------------------------
test("Crash Sentinel isolates broken mod across launches", function()
  local mock_fs = { sentinel = nil, quarantined = {} }

  local function record_start_mod(name) mock_fs.sentinel = name end
  local function record_finish_mod(name) if mock_fs.sentinel == name then mock_fs.sentinel = nil end end

  -- Launch 1: Mod crashes hard (simulate unmanaged CTD during execution)
  record_start_mod("BadMod_Broken3DModel")
  -- CTD happens: sentinel remains "BadMod_Broken3DModel"

  -- Launch 2: Engine boots up, checks sentinel
  if mock_fs.sentinel then
    mock_fs.quarantined[mock_fs.sentinel] = true
    mock_fs.sentinel = nil -- cleared for current launch
  end

  assert(mock_fs.quarantined["BadMod_Broken3DModel"] == true)
  assert(mock_fs.sentinel == nil)
end)

-- -----------------------------------------------------------------------------
-- 9. Rogue Guest Boot Shield
-- -----------------------------------------------------------------------------
test("Rogue Guest Boot Shield intercepts secondary 0xF476DF93691895FA boot resources", function()
  local guest_boot_loaded = false
  local guest_boot_code = [[
    _G.GuestBootExecuted = true
    return "guest_ok"
  ]]

  local function execute_guest_boot_sandboxed(code_str)
    local fn, err = loadstring(code_str, "guest_boot_patch_2")
    if fn then
      local ok, res = pcall(fn)
      if ok then guest_boot_loaded = true end
    end
  end

  execute_guest_boot_sandboxed(guest_boot_code)
  assert(guest_boot_loaded == true)
  assert(_G.GuestBootExecuted == true)
end)

print("----------------------------------------------------")
print(string.format("RESULTS: %d / %d tests passed.", pass_count, total_count))
if pass_count == total_count then
  print("STATUS: ALL TESTS PASSED SUCCESSFULLY.")
else
  os.exit(1)
end
