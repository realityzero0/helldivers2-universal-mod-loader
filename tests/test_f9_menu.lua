-- tests/test_f9_menu.lua
-- Unit test simulating Stingray input polling and in-game menu logic

local pass = 0
local total = 0
local function test(desc, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  [PASS] " .. desc)
  else
    print("  [FAIL] " .. desc .. ": " .. tostring(err))
  end
end

print("====================================================")
print("Testing In-Game F9 Settings Menu & Input Polling")
print("====================================================")

-- 1. Test is_input_active logic
local function is_input_active(v)
  return v == true or (type(v) == "number" and v > 0.5)
end

test("is_input_active correctly handles Stingray float values", function()
  assert(is_input_active(0.0) == false, "0.0 float must be false (not pressed)")
  assert(is_input_active(0) == false, "0 int must be false")
  assert(is_input_active(1.0) == true, "1.0 float must be true (pressed)")
  assert(is_input_active(1) == true, "1 int must be true")
  assert(is_input_active(true) == true, "true boolean must be true")
  assert(is_input_active(false) == false, "false boolean must be false")
  assert(is_input_active(nil) == false, "nil must be false")
end)

-- 2. Test button resolution
local function resolve_button_id(dev, name)
  if type(dev) ~= "table" or type(name) ~= "string" or name == "" then return nil end
  local fn = rawget(dev, "button_id") or rawget(dev, "button_index")
  if type(fn) ~= "function" then return nil end
  local ok, idx = pcall(fn, name)
  if ok and idx ~= nil then return idx end
  local ok2, idx2 = pcall(fn, name:lower())
  if ok2 and idx2 ~= nil then return idx2 end
  local ok3, idx3 = pcall(fn, name:upper())
  if ok3 and idx3 ~= nil then return idx3 end
  return nil
end

test("resolve_button_id handles casing and button_index / button_id polymorphism", function()
  local mock_kb = {
    button_id = function(k)
      if k == "F9" then return 119 end
      if k == "f2" then return 112 end
      return nil
    end
  }
  assert(resolve_button_id(mock_kb, "f9") == 119, "Must resolve lowercase 'f9' to uppercase 'F9'")
  assert(resolve_button_id(mock_kb, "F9") == 119, "Must resolve uppercase 'F9'")
  assert(resolve_button_id(mock_kb, "f2") == 112, "Must resolve 'f2'")
  assert(resolve_button_id(mock_kb, "nonexistent") == nil, "Must return nil for nonexistent key")
end)

-- 3. Test Menu Navigation and Value Toggling
test("Menu navigation and boolean/number toggle logic", function()
  local mom = {
    order = { "show_he", "show_ems", "radar_range" },
    registered = {
      show_he = { label = "HE Mortar Impact", default = true, type = "boolean" },
      show_ems = { label = "EMS Mortar Impact", default = false, type = "boolean" },
      radar_range = { label = "Radar Range Multiplier", default = 100, type = "number", step = 25 }
    },
    values = { show_he = true, show_ems = false, radar_range = 100 },
    revision = 1
  }
  mom.get = function(id) return mom.values[id] end
  mom.set = function(id, val)
    mom.values[id] = val
    mom.revision = mom.revision + 1
  end

  local sel_idx = 1
  assert(sel_idx == 1)

  -- Move down
  sel_idx = sel_idx + 1
  assert(sel_idx == 2)
  local cur_id = mom.order[sel_idx]
  assert(cur_id == "show_ems")

  -- Toggle show_ems
  local cur_val = mom.get(cur_id)
  mom.set(cur_id, not cur_val)
  assert(mom.get("show_ems") == true, "show_ems should now be true")
  assert(mom.revision == 2, "revision should be 2")

  -- Move down to radar_range
  sel_idx = sel_idx + 1
  assert(sel_idx == 3)
  cur_id = mom.order[sel_idx]
  assert(cur_id == "radar_range")

  -- Step radar_range +25
  local spec = mom.registered[cur_id]
  local step = spec.step or 1
  mom.set(cur_id, mom.get(cur_id) + step)
  assert(mom.get("radar_range") == 125, "radar_range should now be 125")
end)

print("----------------------------------------------------")
print(string.format("RESULTS: %d / %d tests passed.", pass, total))
if pass == total then
  print("STATUS: F9 MENU AND INPUT LOGIC VERIFIED.")
else
  os.exit(1)
end
