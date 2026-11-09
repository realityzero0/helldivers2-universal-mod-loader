# scripts/patch_f9_edge_trigger.py
import re

file_path = r"G:\antigravity\UniversalModLoader-v1.0.0\src\boot_loader.lua"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# 1. Update key_pressed with edge detection
old_key_pressed = """local function key_pressed(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if kb then
        local idx = resolve_button_id(kb, name)
        if idx ~= nil and query_device_button(kb, idx, "pressed") then
            return true
        end
    end
    return false
end"""

new_key_pressed = """local key_was_down = {}

local function key_pressed(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if not kb then return false end
    local idx = resolve_button_id(kb, name)
    if idx == nil then return false end

    local is_down = false
    if query_device_button(kb, idx, "button") then
        is_down = true
    elseif query_device_button(kb, idx, "pressed") then
        is_down = true
    end

    local was_down = key_was_down[name] == true
    key_was_down[name] = is_down

    -- Edge Trigger: Returns true ONLY on transition from UP to DOWN!
    return is_down and not was_down
end"""

code = code.replace(old_key_pressed.replace("\n", "\r\n"), new_key_pressed.replace("\n", "\r\n"))
code = code.replace(old_key_pressed, new_key_pressed)

# 2. Update ui_ensure_gui with logging and immediate fallback
old_ui_ensure = """local function ui_ensure_gui()
    local sr = rawget(_G, "stingray")
    if not sr or not sr.World or type(sr.World.create_screen_gui) ~= "function" then return false end
    if uml_gui_instance and ui_world_alive(sr, uml_gui_world) then
        return true
    end
    uml_gui_instance = nil
    uml_gui_world = nil
    ui_clear_elements()

    local w = ui_find_world(sr)
    if not w then return false end
    local ok, g = pcall(sr.World.create_screen_gui, w, "scale", 1, 1)
    if ok and g then
        uml_gui_instance = g
        uml_gui_world = w
        return true
    end
    return false
end"""

new_ui_ensure = """local function ui_ensure_gui()
    local sr = rawget(_G, "stingray")
    if not sr or not sr.World or type(sr.World.create_screen_gui) ~= "function" then return false end
    if uml_gui_instance and ui_world_alive(sr, uml_gui_world) then
        return true
    end
    uml_gui_instance = nil
    uml_gui_world = nil
    ui_clear_elements()

    local w = ui_find_world(sr)
    if not w then
        log_write("[UML] ui_ensure_gui: No world available yet")
        return false
    end
    local ok, g = pcall(sr.World.create_screen_gui, w, "scale", 1, 1)
    if ok and g then
        uml_gui_instance = g
        uml_gui_world = w
        log_write("[UML] ui_ensure_gui: Screen GUI successfully created on world " .. tostring(w))
        return true
    else
        log_write("[UML] ui_ensure_gui: create_screen_gui scaled failed: " .. tostring(g))
        local ok2, g2 = pcall(sr.World.create_screen_gui, w, "immediate")
        if ok2 and g2 then
            uml_gui_instance = g2
            uml_gui_world = w
            log_write("[UML] ui_ensure_gui: Fallback immediate GUI created!")
            return true
        end
    end
    return false
end"""

code = code.replace(old_ui_ensure.replace("\n", "\r\n"), new_ui_ensure.replace("\n", "\r\n"))
code = code.replace(old_ui_ensure, new_ui_ensure)

# 3. Add frame de-duplication to handle_uml_menu_input and drawing logging
old_handle_input_start = """-- Hot-Reloading hook forward declaration
local trigger_loose_hot_reload = nil

local function handle_uml_menu_input(dt)
    if key_pressed("f9") or key_pressed("f2") then"""

new_handle_input_start = """-- Hot-Reloading hook forward declaration
local trigger_loose_hot_reload = nil

local frame_counter = 0
local last_input_frame = -1

local function handle_uml_menu_input(dt)
    if last_input_frame == frame_counter then return end
    last_input_frame = frame_counter

    if key_pressed("f9") or key_pressed("f2") then"""

code = code.replace(old_handle_input_start.replace("\n", "\r\n"), new_handle_input_start.replace("\n", "\r\n"))
code = code.replace(old_handle_input_start, new_handle_input_start)

# 4. Increment frame_counter in update and master_update
old_update = """update = function(dt, ...)
    pcall(handle_uml_menu_input, dt)"""

new_update = """update = function(dt, ...)
    frame_counter = frame_counter + 1
    pcall(handle_uml_menu_input, dt)"""

code = code.replace(old_update.replace("\n", "\r\n"), new_update.replace("\n", "\r\n"))
code = code.replace(old_update, new_update)

old_master_update = """local function master_update(dt, ...)
    pcall(handle_uml_menu_input, dt)"""

new_master_update = """local function master_update(dt, ...)
    frame_counter = frame_counter + 1
    pcall(handle_uml_menu_input, dt)"""

code = code.replace(old_master_update.replace("\n", "\r\n"), new_master_update.replace("\n", "\r\n"))
code = code.replace(old_master_update, new_master_update)

# 5. Log draw_in_game_menu details
old_sig_check = """    if uml_last_sig == sig then return end
    ui_clear_elements()
    uml_last_sig = sig"""

new_sig_check = """    if uml_last_sig == sig then return end
    ui_clear_elements()
    uml_last_sig = sig
    log_write(string.format("[UML] Rendering settings menu overlay (items: %d, sel: %d, res: %dx%d)", total_items, sel, W, H))"""

code = code.replace(old_sig_check.replace("\n", "\r\n"), new_sig_check.replace("\n", "\r\n"))
code = code.replace(old_sig_check, new_sig_check)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)

print("Edge trigger and frame deduplication successfully patched!")
