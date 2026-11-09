# scripts/patch_f9_menu.py
import os
import subprocess

file_path = r"G:\antigravity\UniversalModLoader-v1.0.0\src\boot_loader.lua"
with open(file_path, "r", encoding="utf-8") as f:
    code = f.read()

# 1. New Section 1 & UI implementation
old_section_1_start = "local shutdown_order = {}\n"
if old_section_1_start not in code:
    old_section_1_start = "local shutdown_order = {}\r\n"

old_ui_block_end = "    return prev_update(dt, ...)\nend\n"
if old_ui_block_end not in code:
    old_ui_block_end = "    return prev_update(dt, ...)\r\nend\r\n"

start_idx = code.find(old_section_1_start)
assert start_idx != -1, "Could not find start of Section 1 shutdown_order"
start_idx += len(old_section_1_start)

end_idx = code.find(old_ui_block_end, start_idx)
assert end_idx != -1, "Could not find end of Section 1 update function"
end_idx += len(old_ui_block_end)

new_section_1 = """
-- Logging Subsystem (frame 0 availability)
local log_handle = nil
local function get_log_path()
    local appdata = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or "."
    return appdata .. "/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log"
end

local function open_log()
    if log_handle then return log_handle end
    local path = get_log_path()
    local f_chk = io.open(path, "r")
    if f_chk then
        local sz = f_chk:seek("end")
        f_chk:close()
        if sz and sz > (5 * 1024 * 1024) then
            os.remove(path .. ".old")
            os.rename(path, path .. ".old")
        end
    end
    local f, err = io.open(path, "a")
    if f then
        log_handle = f
        f:write(string.format("\\n--- Universal Mod Loader v2.0.0 Booted at %s ---\\n", os.date and os.date("%Y-%m-%d %H:%M:%S") or "now"))
        f:flush()
    end
    return log_handle
end

local function log_write(msg)
    pcall(print, "[UniversalLoader] " .. tostring(msg))
    local f = open_log()
    if f then
        pcall(function()
            f:write(string.format("[%s] %s\\n", os.date and os.date("%H:%M:%S") or "LOG", tostring(msg)))
            f:flush()
        end)
    end
end

-- Font Glyph Sanitizer (Subsystem 9)
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

-- ==============================================================================
-- IN-GAME SETTINGS MENU & INPUT SUBSYSTEM (Subsystems 5 & 11)
-- ==============================================================================
local UI_FONT = "core/performance_hud/debug"
local uml_ui_open = false
local uml_ui_selected_idx = 1
local uml_gui_instance = nil
local uml_gui_world = nil
local uml_rect_ids = {}
local uml_text_ids = {}
local uml_last_sig = nil

local function is_input_active(v)
    return v == true or (type(v) == "number" and v > 0.5)
end

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

local function query_device_button(dev, idx, method_name)
    if type(dev) ~= "table" or idx == nil then return false end
    local fn = rawget(dev, method_name)
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, idx)
    return ok and is_input_active(res)
end

local function key_pressed(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if kb then
        local idx = resolve_button_id(kb, name)
        if idx ~= nil and query_device_button(kb, idx, "pressed") then
            return true
        end
    end
    return false
end

local function key_down(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if kb then
        local idx = resolve_button_id(kb, name)
        if idx ~= nil and query_device_button(kb, idx, "button") then
            return true
        end
    end
    return false
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

local function ui_clear_elements()
    local sr = rawget(_G, "stingray")
    local g = sr and sr.Gui
    if g and uml_gui_instance then
        if type(g.destroy_rect) == "function" then
            for i = #uml_rect_ids, 1, -1 do
                pcall(g.destroy_rect, uml_gui_instance, uml_rect_ids[i])
            end
        end
        if type(g.destroy_text) == "function" then
            for i = #uml_text_ids, 1, -1 do
                pcall(g.destroy_text, uml_gui_instance, uml_text_ids[i])
            end
        end
    end
    uml_rect_ids = {}
    uml_text_ids = {}
    uml_last_sig = nil
end

local function ui_ensure_gui()
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
end

local function draw_in_game_menu()
    if not uml_ui_open then
        if #uml_rect_ids > 0 or #uml_text_ids > 0 then
            ui_clear_elements()
        end
        return
    end

    local sr = rawget(_G, "stingray")
    if not sr or not sr.Gui or not sr.Gui.rect or not sr.Gui.text then return end
    if not ui_ensure_gui() then return end

    local mom = rawget(_G, "ModOptionsMenu")
    local order = mom and mom.order or {}
    local reg = mom and mom.registered or {}
    local vals = mom and mom.values or {}

    local W, H = 1920, 1080
    if sr.Gui and type(sr.Gui.resolution) == "function" then
        local ok, rw, rh = pcall(sr.Gui.resolution)
        if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then
            W, H = rw, rh
        end
    end

    local scale = H / 1080
    if scale <= 0 then scale = 1 end

    local page_size = 14
    local total_items = #order
    local sel = uml_ui_selected_idx
    if sel < 1 then sel = 1 end
    if total_items > 0 and sel > total_items then sel = total_items end
    uml_ui_selected_idx = sel

    local page = (total_items > 0) and math.floor((sel - 1) / page_size) or 0
    local total_pages = (total_items > 0) and math.ceil(total_items / page_size) or 1
    local start_idx = page * page_size + 1
    local end_idx = math.min(total_items, start_idx + page_size - 1)

    local sig = string.format("UML_MENU:%d:%d:%d:%d:%d", W, H, sel, mom and mom.revision or 1, total_items)
    if uml_last_sig == sig then return end
    ui_clear_elements()
    uml_last_sig = sig

    local function draw_rect(x, y, w, h, r, g, b, a, layer)
        local sx = math.floor(x * scale)
        local sy_top = math.floor(y * scale)
        local sw = math.max(1, math.floor(w * scale))
        local sh = math.max(1, math.floor(h * scale))
        local pos = sr.Vector3(sx, H - sy_top - sh, layer or 950)
        local sz = sr.Vector2(sw, sh)
        local col = sr.Color(a or 255, r or 255, g or 255, b or 255)
        local ok, id = pcall(sr.Gui.rect, uml_gui_instance, pos, sz, col)
        if ok and id then uml_rect_ids[#uml_rect_ids + 1] = id end
    end

    local function draw_text(str, x, y, font_size, r, g, b, a, layer)
        local sx = math.floor(x * scale)
        local sy = math.floor(H - y * scale)
        local fsize = math.max(10, math.floor((font_size or 16) * scale))
        local pos = sr.Vector3(sx, sy, layer or 960)
        local col = sr.Color(a or 255, r or 255, g or 255, b or 255)
        local safe_str = sanitize_text(str)
        local ok, id = pcall(sr.Gui.text, uml_gui_instance, safe_str, UI_FONT, fsize, UI_FONT, pos, col)
        if ok and id then uml_text_ids[#uml_text_ids + 1] = id end
    end

    local box_x, box_y, box_w, box_h = 50, 60, 780, 560

    -- Outer Tactical Border & Backdrop
    draw_rect(box_x - 2, box_y - 2, box_w + 4, box_h + 4, 235, 195, 45, 230, 948)
    draw_rect(box_x, box_y, box_w, box_h, 14, 18, 26, 248, 950)
    draw_rect(box_x, box_y, box_w, 48, 22, 30, 44, 252, 952)
    draw_rect(box_x, box_y + 48, box_w, 2, 235, 195, 45, 255, 954)

    -- Header Title
    draw_text("=== UNIVERSAL MOD LOADER v2.0.0 -- SETTINGS ===", box_x + 20, box_y + 32, 17, 255, 220, 65, 255, 970)
    draw_text("[F9 / F2]", box_x + box_w - 95, box_y + 32, 15, 140, 200, 255, 255, 970)

    -- Subheader info
    local sub_info = string.format("Active Options: %d   (Page %d / %d)", total_items, page + 1, total_pages)
    draw_text(sub_info, box_x + 20, box_y + 75, 14, 160, 180, 205, 255, 970)

    local row_start_y = box_y + 90
    local line_height = 28

    if total_items == 0 then
        draw_text("Universal Mod Loader v2.0.0 is Active.", box_x + 30, row_start_y + 40, 16, 255, 220, 65, 255, 970)
        draw_text("No configurable mod options registered yet by active mods.", box_x + 30, row_start_y + 70, 14, 180, 190, 205, 255, 970)
        draw_text("Options from ChefSharedLoader and Bingus MOM", box_x + 30, row_start_y + 95, 14, 140, 150, 165, 255, 970)
        draw_text("will populate here automatically when loaded.", box_x + 30, row_start_y + 120, 14, 140, 150, 165, 255, 970)
    else
        for idx = start_idx, end_idx do
            local opt_id = order[idx]
            local spec = reg[opt_id] or {}
            local val = vals[opt_id] ~= nil and vals[opt_id] or spec.default
            local is_selected = (idx == sel)
            local ry = row_start_y + (idx - start_idx) * line_height

            local val_str = tostring(val)
            local vr, vg, vb = 220, 225, 235
            if type(val) == "boolean" then
                val_str = val and "[ON]" or "[OFF]"
                if val then vr, vg, vb = 90, 235, 130 else vr, vg, vb = 230, 95, 95 end
            elseif type(val) == "number" then
                vr, vg, vb = 110, 210, 250
            end

            local label = spec.label or opt_id
            if #label > 38 then label = label:sub(1, 35) .. "..." end

            if is_selected then
                draw_rect(box_x + 10, ry - 4, box_w - 20, line_height, 42, 60, 85, 220, 955)
                draw_rect(box_x + 10, ry - 4, 4, line_height, 255, 215, 55, 255, 958)
                draw_text("> " .. label, box_x + 22, ry + 18, 15, 255, 225, 80, 255, 970)
            else
                draw_text("  " .. label, box_x + 22, ry + 18, 15, 210, 215, 225, 255, 970)
            end

            draw_text(val_str, box_x + box_w - 120, ry + 18, 15, vr, vg, vb, 255, 970)
        end
    end

    -- Footer Divider & Instructions
    local footer_y = box_y + box_h - 45
    draw_rect(box_x, footer_y - 8, box_w, 2, 45, 60, 85, 255, 954)
    draw_text("[UP/DOWN] Select   [LEFT/RIGHT/ENTER] Toggle   [ESC / F9 / F2] Close", box_x + 20, footer_y + 18, 13, 175, 185, 195, 255, 970)
end

-- Hot-Reloading hook forward declaration
local trigger_loose_hot_reload = nil

local function handle_uml_menu_input(dt)
    if key_pressed("f9") or key_pressed("f2") then
        uml_ui_open = not uml_ui_open
        uml_last_sig = nil
        if not uml_ui_open then
            ui_clear_elements()
        end
        log_write("[UML] Settings menu toggled via hotkey: " .. (uml_ui_open and "OPEN" or "CLOSED"))
        return
    end

    if not uml_ui_open then return end

    local mom = rawget(_G, "ModOptionsMenu")
    local order = mom and mom.order or {}
    local total_items = #order

    if key_pressed("escape") or key_pressed("esc") then
        uml_ui_open = false
        uml_last_sig = nil
        ui_clear_elements()
        log_write("[UML] Settings menu closed via ESC")
        return
    end

    if key_pressed("up") and total_items > 0 then
        uml_ui_selected_idx = uml_ui_selected_idx - 1
        if uml_ui_selected_idx < 1 then uml_ui_selected_idx = total_items end
        uml_last_sig = nil
    elseif key_pressed("down") and total_items > 0 then
        uml_ui_selected_idx = uml_ui_selected_idx + 1
        if uml_ui_selected_idx > total_items then uml_ui_selected_idx = 1 end
        uml_last_sig = nil
    end

    local hit_enter = key_pressed("enter") or key_pressed("space")
    local hit_left = key_pressed("left")
    local hit_right = key_pressed("right")
    if (hit_enter or hit_left or hit_right) and total_items > 0 and mom then
        local opt_id = order[uml_ui_selected_idx]
        if opt_id then
            local spec = mom.registered and mom.registered[opt_id] or {}
            local cur_val = mom.get(opt_id)
            if type(cur_val) == "boolean" then
                mom.set(opt_id, not cur_val)
                uml_last_sig = nil
            elseif type(cur_val) == "number" then
                local step = tonumber(spec.step) or 1
                local delta = hit_left and -step or step
                mom.set(opt_id, cur_val + delta)
                uml_last_sig = nil
            elseif type(spec.choices) == "table" and #spec.choices > 0 then
                local count = #spec.choices
                local cur_idx = tonumber(cur_val) or 1
                if hit_left then
                    cur_idx = cur_idx - 1
                    if cur_idx < 1 then cur_idx = count end
                else
                    cur_idx = (cur_idx % count) + 1
                end
                mom.set(opt_id, cur_idx)
                uml_last_sig = nil
            end
        end
    end

    local is_ctrl_down = key_down("left ctrl") or key_down("right ctrl")
    if is_ctrl_down and key_pressed("f5") then
        if type(trigger_loose_hot_reload) == "function" then
            pcall(trigger_loose_hot_reload)
        end
    end
end

-- Entrypoint Chaining
init = function(...)
    return prev_init(...)
end

render = function(...)
    if uml_ui_open then
        pcall(draw_in_game_menu)
    end
    return prev_render(...)
end

update = function(dt, ...)
    pcall(handle_uml_menu_input, dt)
    if uml_ui_open then
        pcall(draw_in_game_menu)
    end

    -- Circuit-Breaker protected update hooks
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
"""

code = code[:start_idx] + new_section_1 + code[end_idx:]

# 2. Update Section 7 (remove duplicate log definition)
old_sec_7_target = """-- ==============================================================================
-- 7. LOGGING SUBSYSTEM & AUTOMATIC LOG ROTATION (Subsystem 15)
-- ==============================================================================
local log_handle = nil
local function get_log_path()
    local appdata = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or "."
    return appdata .. "/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log"
end

local function open_log()
    if log_handle then return log_handle end
    local path = get_log_path()

    -- Subsystem 15: Automatic Log Rotation (> 5MB cap)
    local f_chk = io.open(path, "r")
    if f_chk then
        local sz = f_chk:seek("end")
        f_chk:close()
        if sz and sz > (5 * 1024 * 1024) then
            os.remove(path .. ".old")
            os.rename(path, path .. ".old")
        end
    end

    local f, err = io.open(path, "a")
    if f then
        log_handle = f
        f:write(string.format("\\n--- Universal Mod Loader v2.0.0 Booted at %s ---\\n", os.date and os.date("%Y-%m-%d %H:%M:%S") or "now"))
        f:flush()
    end
    return log_handle
end

local function log_write(msg)
    pcall(print, "[UniversalLoader] " .. tostring(msg))
    local f = open_log()
    if f then
        pcall(function()
            f:write(string.format("[%s] %s\\n", os.date and os.date("%H:%M:%S") or "LOG", tostring(msg)))
            f:flush()
        end)
    end
end"""

new_sec_7 = """-- ==============================================================================
-- 7. LOGGING SUBSYSTEM (initialized in Section 1)
-- ==============================================================================
-- open_log() and log_write(msg) are initialized at Section 1 for universal availability."""

code = code.replace(old_sec_7_target.replace("\n", "\r\n"), new_sec_7.replace("\n", "\r\n"))
code = code.replace(old_sec_7_target, new_sec_7)

# 3. Add Master Update & Render hooks at the very end
target_end_snippet = 'log_write(string.format("After startup: %d callbacks run, %d failed", ran_cb, failed_cb))'
assert target_end_snippet in code, "Target end snippet not found"

master_hooks = """
log_write(string.format("After startup: %d callbacks run, %d failed", ran_cb, failed_cb))

-- ==============================================================================
-- 10. MASTER ENGINE HOOKS (OUTERMOST ENGINE BOUNDARY)
-- ==============================================================================
-- Re-hook _G.update and _G.render at the outermost boundary so UML settings menu
-- and hotkeys always run reliably even if third-party mods overwrote engine callbacks.
local prev_master_update = type(rawget(_G, "update")) == "function" and rawget(_G, "update") or nil
local function master_update(dt, ...)
    pcall(handle_uml_menu_input, dt)
    if uml_ui_open then
        pcall(draw_in_game_menu)
    end
    if type(prev_master_update) == "function" then
        return prev_master_update(dt, ...)
    end
end
_G.update = master_update
update = master_update

local prev_master_render = type(rawget(_G, "render")) == "function" and rawget(_G, "render") or nil
local function master_render(...)
    if uml_ui_open then
        pcall(draw_in_game_menu)
    end
    if type(prev_master_render) == "function" then
        return prev_master_render(...)
    end
end
_G.render = master_render
render = master_render
log_write("Universal Mod Loader master hooks attached at outermost boundary")
"""

code = code.replace(target_end_snippet, master_hooks.strip())

with open(file_path, "w", encoding="utf-8") as f:
    f.write(code)

print("Successfully patched boot_loader.lua!")
