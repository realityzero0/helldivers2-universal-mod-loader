import os

path = r"G:\antigravity\UniversalModLoader-v1.0.0\src\boot_loader.lua"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. ESC_TOP_MODS_BTN geometry
old_btn = "local ESC_TOP_MODS_BTN = { x = 716, y = 90, w = 170, h = 36 }"
new_btn = "local ESC_TOP_MODS_BTN = { x = 716, y = 72, w = 170, h = 48 }"
assert old_btn in text, "old_btn not found"
text = text.replace(old_btn, new_btn)

# 2. get_mod_option_categories virtual categories
old_cat = """    sort(mod_names)
    for i = 1, #mod_names do
        categories[#categories + 1] = mod_names[i]
    end
    return categories, by_cat"""
new_cat = """    sort(mod_names)
    for i = 1, #mod_names do
        categories[#categories + 1] = mod_names[i]
    end
    categories[#categories + 1] = "KEY BINDINGS"
    categories[#categories + 1] = "LOADED MODS"
    return categories, by_cat"""
assert old_cat in text, "old_cat not found"
text = text.replace(old_cat, new_cat)

# 3. hov_top hitbox in State 1 input handling
old_hov = "local hov_top = (cx ~= nil and cy ~= nil) and pt_in_rect(cx, cy, ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h) or false"
new_hov = "local hov_top = (cx ~= nil and cy ~= nil) and pt_in_rect(cx, cy, ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w + 40, ESC_TOP_MODS_BTN.h) or false"
assert old_hov in text, "old_hov not found"
text = text.replace(old_hov, new_hov)

# 4. Top header mouse clicks & keyboard shortcuts
old_top_clicks = """    -- Top Header Bar Mouse Clicks (Y=80..136)
    if lclick and cy ~= nil and ((cy >= 80 and cy <= 136) or (1080 - cy >= 80 and 1080 - cy <= 136)) then
        -- Clicking [Q] or Native Tabs [ GAME ] [ SOCIAL ] [ OPTIONS ] returns to native menu
        if (cx >= 70 and cx <= 710) or (cx >= 1590 and cx <= 1780) then
            UniversalState.menu_visible = false
            UniversalState.dragging_slider_id = nil
            ui_gfx_clear(sr)
            return
        elseif cx >= 950 and cx <= 1150 then
            UniversalState.menu_tab = 1
            UniversalState.menu_selected = 1
            return
        elseif cx >= 1155 and cx <= 1335 then
            UniversalState.menu_tab = 2
            UniversalState.menu_selected = 1
            return
        elseif cx >= 1335 and cx <= 1530 then
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
    end"""

new_top_clicks = """    -- Top Header Bar Mouse Clicks (Y=70..125): Clicking [Q], [GAME], [SOCIAL], [OPTIONS] returns to native menu
    if lclick and cy ~= nil and ((cy >= 70 and cy <= 125) or (1080 - cy >= 70 and 1080 - cy <= 125)) then
        if cx >= 70 and cx <= 710 then
            UniversalState.menu_visible = false
            UniversalState.dragging_slider_id = nil
            ui_gfx_clear(sr)
            return
        end
    end

    -- Footer Bar Mouse Clicks (Y=1020..1060)
    if lclick and cy ~= nil and ((cy >= 1020 and cy <= 1060) or (1080 - cy >= 1020 and 1080 - cy <= 1060)) then
        if cx >= 70 and cx <= 180 then
            UniversalState.menu_visible = false
            UniversalState.dragging_slider_id = nil
            ui_gfx_clear(sr)
            return
        elseif cx >= 210 and cx <= 340 then
            if save_persistent_settings then save_persistent_settings() end
            UniversalState.toast = { text = "SETTINGS SAVED & APPLIED", expire_at = os.clock() + 2.0 }
            return
        elseif cx >= 360 and cx <= 550 then
            local categories_f, by_cat_f = get_mod_option_categories()
            local active_cat_f = categories_f[UniversalState.menu_mod_filter or 1] or "ALL MODS"
            local opt_keys_f = by_cat_f[active_cat_f] or {}
            local cur_id_f = opt_keys_f[UniversalState.menu_selected or 1]
            if cur_id_f then ModOptionsMenu.reset_option(cur_id_f) end
            return
        end
    end

    -- Keyboard Shortcuts: Tab (Apply Settings), 1 (Options), 2 (Bindings), 3 (Loaded Mods)
    if key_pressed("tab") then
        if save_persistent_settings then save_persistent_settings() end
        UniversalState.toast = { text = "SETTINGS SAVED & APPLIED", expire_at = os.clock() + 2.0 }
        return
    elseif key_pressed("1") then
        UniversalState.menu_mod_filter = 1
        UniversalState.menu_tab = 1
        UniversalState.menu_selected = 1
        return
    elseif key_pressed("2") then
        local cat_temp = get_mod_option_categories()
        for ci = 1, #cat_temp do
            if cat_temp[ci] == "KEY BINDINGS" then
                UniversalState.menu_mod_filter = ci
                UniversalState.menu_tab = 2
                UniversalState.menu_selected = 1
                break
            end
        end
        return
    elseif key_pressed("3") then
        local cat_temp = get_mod_option_categories()
        for ci = 1, #cat_temp do
            if cat_temp[ci] == "LOADED MODS" then
                UniversalState.menu_mod_filter = ci
                UniversalState.menu_tab = 3
                UniversalState.menu_selected = 1
                break
            end
        end
        return
    end"""
assert old_top_clicks in text, "old_top_clicks not found"
text = text.replace(old_top_clicks, new_top_clicks)

# 5. Category sidebar clicks
old_cat_clicks = """        if lclick then
            for ci = cat_start, cat_end do
                local ry = 165 + (ci - cat_start) * 52
                if pt_in_rect(cx, cy, 76, ry, 310, 46) then
                    UniversalState.menu_mod_filter = ci
                    UniversalState.menu_tab = 1
                    UniversalState.menu_selected = 1
                    return
                end
            end
            -- Left column bottom [< PREV (Q)] / [(E) NEXT >] buttons
            if pt_in_rect(cx, cy, 76, 905, 150, 36) and #categories > 0 then
                cat_idx = cat_idx - 1
                if cat_idx < 1 then cat_idx = #categories end
                UniversalState.menu_mod_filter = cat_idx
                UniversalState.menu_tab = 1
                UniversalState.menu_selected = 1
                return
            elseif pt_in_rect(cx, cy, 236, 905, 150, 36) and #categories > 0 then
                cat_idx = (cat_idx % #categories) + 1
                UniversalState.menu_mod_filter = cat_idx
                UniversalState.menu_tab = 1
                UniversalState.menu_selected = 1
                return
            end
        end"""

new_cat_clicks = """        if lclick then
            for ci = cat_start, cat_end do
                local ry = 165 + (ci - cat_start) * 52
                if pt_in_rect(cx, cy, 76, ry, 310, 46) then
                    UniversalState.menu_mod_filter = ci
                    local sel_cat = categories[ci]
                    if sel_cat == "KEY BINDINGS" then
                        UniversalState.menu_tab = 2
                    elseif sel_cat == "LOADED MODS" then
                        UniversalState.menu_tab = 3
                    else
                        UniversalState.menu_tab = 1
                    end
                    UniversalState.menu_selected = 1
                    return
                end
            end
            -- Left column bottom [< PREV (Q)] / [(E) NEXT >] buttons
            if pt_in_rect(cx, cy, 76, 905, 150, 36) and #categories > 0 then
                cat_idx = cat_idx - 1
                if cat_idx < 1 then cat_idx = #categories end
                UniversalState.menu_mod_filter = cat_idx
                local sel_cat = categories[cat_idx]
                if sel_cat == "KEY BINDINGS" then
                    UniversalState.menu_tab = 2
                elseif sel_cat == "LOADED MODS" then
                    UniversalState.menu_tab = 3
                else
                    UniversalState.menu_tab = 1
                end
                UniversalState.menu_selected = 1
                return
            elseif pt_in_rect(cx, cy, 236, 905, 150, 36) and #categories > 0 then
                cat_idx = (cat_idx % #categories) + 1
                UniversalState.menu_mod_filter = cat_idx
                local sel_cat = categories[cat_idx]
                if sel_cat == "KEY BINDINGS" then
                    UniversalState.menu_tab = 2
                elseif sel_cat == "LOADED MODS" then
                    UniversalState.menu_tab = 3
                else
                    UniversalState.menu_tab = 1
                end
                UniversalState.menu_selected = 1
                return
            end
        end"""
assert old_cat_clicks in text, "old_cat_clicks not found"
text = text.replace(old_cat_clicks, new_cat_clicks)

# 6. Category wheel
old_cat_wheel = """        if wheel > 0 and #categories > 0 then
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
        end"""

new_cat_wheel = """        if wheel > 0 and #categories > 0 then
            cat_idx = cat_idx - 1
            if cat_idx < 1 then cat_idx = #categories end
            UniversalState.menu_mod_filter = cat_idx
            local sel_cat = categories[cat_idx]
            if sel_cat == "KEY BINDINGS" then
                UniversalState.menu_tab = 2
            elseif sel_cat == "LOADED MODS" then
                UniversalState.menu_tab = 3
            else
                UniversalState.menu_tab = 1
            end
            UniversalState.menu_selected = 1
            return
        elseif wheel < 0 and #categories > 0 then
            cat_idx = (cat_idx % #categories) + 1
            UniversalState.menu_mod_filter = cat_idx
            local sel_cat = categories[cat_idx]
            if sel_cat == "KEY BINDINGS" then
                UniversalState.menu_tab = 2
            elseif sel_cat == "LOADED MODS" then
                UniversalState.menu_tab = 3
            else
                UniversalState.menu_tab = 1
            end
            UniversalState.menu_selected = 1
            return
        end"""
assert old_cat_wheel in text, "old_cat_wheel not found"
text = text.replace(old_cat_wheel, new_cat_wheel)

# 7. Q/E key cycling
old_qe = """        if key_pressed("q") or key_pressed("left_shoulder") then
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
        end"""

new_qe = """        if key_pressed("q") or key_pressed("left_shoulder") then
            cat_idx = cat_idx - 1
            if cat_idx < 1 then cat_idx = #categories end
            UniversalState.menu_mod_filter = cat_idx
            local sel_cat = categories[cat_idx]
            if sel_cat == "KEY BINDINGS" then
                UniversalState.menu_tab = 2
            elseif sel_cat == "LOADED MODS" then
                UniversalState.menu_tab = 3
            else
                UniversalState.menu_tab = 1
            end
            UniversalState.menu_selected = 1
            return
        elseif key_pressed("e") or key_pressed("right_shoulder") then
            cat_idx = (cat_idx % #categories) + 1
            UniversalState.menu_mod_filter = cat_idx
            local sel_cat = categories[cat_idx]
            if sel_cat == "KEY BINDINGS" then
                UniversalState.menu_tab = 2
            elseif sel_cat == "LOADED MODS" then
                UniversalState.menu_tab = 3
            else
                UniversalState.menu_tab = 1
            end
            UniversalState.menu_selected = 1
            return
        end"""
assert old_qe in text, "old_qe not found"
text = text.replace(old_qe, new_qe)

# 8. draw_rect default layer & draw_text text_layer
old_draw_rect_pos = "local pos = sr.Vector3(sx, H - sy_top - sh, layer or 960)"
new_draw_rect_pos = "local pos = sr.Vector3(sx, H - sy_top - sh, layer or (UniversalState.menu_visible and 1215 or 955))"
assert old_draw_rect_pos in text, "old_draw_rect_pos not found"
text = text.replace(old_draw_rect_pos, new_draw_rect_pos)

old_text_layer = "local text_layer = math.max(995, (layer or 995) + 25)"
new_text_layer = "local text_layer = math.max(1260, (layer or 1260) + 25)"
assert old_text_layer in text, "old_text_layer not found"
text = text.replace(old_text_layer, new_text_layer)

# 9. State 1 closed tab rendering
old_state1_tab = """        -- Inactive MODS Tab in Top Bar (X=716..886, Y=90..126 directly adjacent to [ OPTIONS ] 3 at X=516..704)
        local bx, by, bw, bh = ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h
        -- Solid opaque backdrop covering the native [E] prompt at X=740..765
        draw_rect(bx, by, bw, bh, 16, 22, 28, 255, 955)
        -- Bracket borders matching native Helldivers 2 tabs
        draw_rect(bx, by, bw, 1, 60, 75, 90, hov_top and 255 or 140, 956)
        draw_rect(bx, by + bh - 2, bw, 2, 40, 50, 62, 160, 956)
        draw_rect(bx, by + 4, 1, bh - 8, 60, 75, 90, 160, 956)
        draw_rect(bx + bw, by + 4, 1, bh - 8, 60, 75, 90, 160, 956)
        -- Label
        draw_text("MODS", bx + 36, by + 24, 16, hov_top and 255 or 195, hov_top and 240 or 205, hov_top and 140 or 215, 255, 970)
        draw_text("4", bx + 124, by + 24, 13, 130, 145, 165, 255, 970)

        -- Native-style [E] Key Prompt Box right after the MODS tab (X=896, Y=94)
        local ex = bx + bw + 10
        local ey = by + 4
        draw_rect(ex, ey, 28, 28, 18, 24, 32, 220, 956)
        draw_rect(ex, ey, 28, 28, 65, 80, 98, 200, 957)
        draw_text("E", ex + 8, ey + 20, 14, 215, 225, 235, 255, 970)"""

new_state1_tab = """        -- Inactive MODS Tab in Top Bar (X=716..886, Y=72..120 connecting directly with native baseline at Y=120)
        local bx, by, bw, bh = ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h
        -- Solid opaque backdrop covering the native [E] prompt at X=740..765
        draw_rect(bx, by, bw, bh, 14, 18, 24, hov_top and 220 or 160, 955)
        -- Bracket borders matching native Helldivers 2 tabs
        draw_rect(bx, by, bw, 1, 60, 75, 90, hov_top and 255 or 140, 956)
        draw_rect(bx, by + bh - 2, bw, 2, 60, 75, 90, 180, 956)
        draw_rect(bx, by + 4, 1, bh - 6, 60, 75, 90, 160, 956)
        draw_rect(bx + bw, by + 4, 1, bh - 6, 60, 75, 90, 160, 956)
        -- Label
        draw_text("MODS", bx + 36, by + 30, 16, hov_top and 255 or 195, hov_top and 240 or 205, hov_top and 140 or 215, 255, 970)
        draw_text("4", bx + 124, by + 30, 13, 130, 145, 165, 255, 970)

        -- Authentic Helldivers 2 White [E] Keycap Graphic (X=896, Y=80)
        local ex = bx + bw + 10
        local ey = by + 8
        draw_rect(ex, ey, 26, 24, 245, 245, 248, 255, 960)
        draw_rect(ex, ey + 24, 26, 4, 155, 160, 170, 255, 960)
        draw_text("E", ex + 7, ey + 18, 13, 20, 24, 30, 255, 975)"""
assert old_state1_tab in text, "old_state1_tab not found"
text = text.replace(old_state1_tab, new_state1_tab)

# 10. State 2 backdrop, tab bar, and removal of top-right tabs
old_state2_top = """    -- 1. Fullscreen Subtle Dark Backdrop (seamlessly covers 100% of screen across all aspect ratios)
    draw_rect(-ox / scale, -oy / scale, W / scale, H / scale, 8, 12, 16, 242, 950)

    -- 2. Top Navigation Bar (matching native Helldivers 2 tabs exactly)
    -- [Q] Button (X=76, Y=94)
    draw_rect(76, 94, 28, 28, 18, 24, 32, 220, 956)
    draw_rect(76, 94, 28, 28, 65, 80, 98, 200, 957)
    draw_text("Q", 84, 114, 14, 215, 225, 235, 255, 970)

    -- Inactive Native Tabs (Clicking any returns to that native menu)
    -- GAME 1 (X=116..304)
    draw_rect(116, 90, 188, 36, 14, 18, 24, 160, 955)
    draw_text("GAME", 170, 114, 16, 175, 185, 195, 255, 970)
    draw_text("1", 275, 114, 13, 130, 145, 165, 255, 970)
    draw_rect(304, 94, 1, 28, 60, 75, 90, 160, 956)

    -- SOCIAL 2 (X=316..504)
    draw_rect(316, 90, 188, 36, 14, 18, 24, 160, 955)
    draw_text("SOCIAL", 365, 114, 16, 175, 185, 195, 255, 970)
    draw_text("2", 475, 114, 13, 130, 145, 165, 255, 970)
    draw_rect(504, 94, 1, 28, 60, 75, 90, 160, 956)

    -- OPTIONS 3 (X=516..704)
    draw_rect(516, 90, 188, 36, 14, 18, 24, 160, 955)
    draw_text("OPTIONS", 560, 114, 16, 175, 185, 195, 255, 970)
    draw_text("3", 675, 114, 13, 130, 145, 165, 255, 970)
    draw_rect(704, 94, 1, 28, 60, 75, 90, 160, 956)

    -- ACTIVE [ MODS 4 ] TAB (X=716..886)
    draw_rect(716, 90, 170, 36, 42, 38, 16, 245, 956)
    draw_text("MODS", 752, 114, 16, 255, 220, 65, 255, 970)
    draw_text("4", 840, 114, 13, 255, 215, 55, 255, 970)
    -- Helldivers 2 signature diagonal striped underline
    draw_rect(716, 126, 170, 3, 245, 205, 45, 255, 960)
    draw_text("////// 4 //////", 745, 133, 10, 245, 205, 45, 255, 970)
    draw_rect(886, 94, 1, 28, 60, 75, 90, 160, 956)

    -- [E] Button (X=896, Y=94)
    draw_rect(896, 94, 28, 28, 18, 24, 32, 220, 956)
    draw_rect(896, 94, 28, 28, 65, 80, 98, 200, 957)
    draw_text("E", 904, 114, 14, 215, 225, 235, 255, 970)

    -- Mode Switchers in Top Right (Options / Keybindings / Diagnostics)
    local mode_tabs = {
        { idx = 1, x = 960,  w = 190, label = format("[1] MOD OPTIONS (%d)", total_opts) },
        { idx = 2, x = 1160, w = 170, label = format("[2] BINDINGS (%d)", total_binds) },
        { idx = 3, x = 1340, w = 180, label = format("[3] MODS LIST (%d)", total_mods) }
    }
    for mi = 1, #mode_tabs do
        local mt = mode_tabs[mi]
        local is_act = (tab == mt.idx)
        draw_rect(mt.x, 90, mt.w, 36, is_act and 42 or 20, is_act and 58 or 26, is_act and 82 or 36, 235, 958)
        if is_act then
            draw_rect(mt.x, 123, mt.w, 3, 255, 215, 55, 255, 960)
        end
        draw_text(mt.label, mt.x + 12, 114, 14, is_act and 255 or 170, is_act and 240 or 182, is_act and 175 or 198, 255, 970)
    end

    -- Close Button (X=1600..1760)
    draw_rect(1600, 90, 160, 36, 68, 28, 32, 235, 958)
    draw_rect(1600, 123, 160, 3, 235, 95, 95, 255, 960)
    draw_text("[ESC] CLOSE", 1632, 114, 14, 255, 210, 210, 255, 970)

    -- Full-width divider line underneath top bar at Y=138
    draw_rect(76, 138, 1764, 2, 60, 75, 90, 180, 955)"""

new_state2_top = """    -- 1. Fullscreen Solid Dark Backdrop below Top Bar (completely covers squad list, Major Order, and 3D hangar)
    -- Y=120 down to Y=1080; Layer 1200 is well above native pause menu layers (~990-1050), completely preventing bleed-through!
    draw_rect(-ox / scale, 120, W / scale, 960 + oy / scale, 12, 16, 22, 255, 1200)

    -- 2. Solid Tab Bar Backing (Y=70..120, X=70..930) at Layer 1200
    -- Covers the native tab bar and any active underline on GAME 1 / OPTIONS 3 so zero ghost text bleeds through
    draw_rect(70, 70, 860, 50, 12, 16, 22, 255, 1200)

    -- 3. Top Navigation Bar (matching native Helldivers 2 tabs exactly)
    -- [Q] Button (X=76, Y=80)
    draw_rect(76, 80, 26, 24, 245, 245, 248, 255, 1210)
    draw_rect(76, 104, 26, 4, 155, 160, 170, 255, 1210)
    draw_text("Q", 84, 98, 13, 20, 24, 30, 255, 1260)

    -- Inactive Native Tabs (Clicking any returns to that native menu)
    -- GAME 1 (X=116..304)
    draw_rect(116, 72, 188, 48, 14, 18, 24, 180, 1210)
    draw_rect(116, 72, 188, 1, 60, 75, 90, 140, 1212)
    draw_rect(304, 76, 1, 40, 60, 75, 90, 160, 1212)
    draw_text("GAME", 170, 102, 16, 175, 185, 195, 255, 1260)
    draw_text("1", 275, 102, 13, 130, 145, 165, 255, 1260)

    -- SOCIAL 2 (X=316..504)
    draw_rect(316, 72, 188, 48, 14, 18, 24, 180, 1210)
    draw_rect(316, 72, 188, 1, 60, 75, 90, 140, 1212)
    draw_rect(504, 76, 1, 40, 60, 75, 90, 160, 1212)
    draw_text("SOCIAL", 365, 102, 16, 175, 185, 195, 255, 1260)
    draw_text("2", 475, 102, 13, 130, 145, 165, 255, 1260)

    -- OPTIONS 3 (X=516..704)
    draw_rect(516, 72, 188, 48, 14, 18, 24, 180, 1210)
    draw_rect(516, 72, 188, 1, 60, 75, 90, 140, 1212)
    draw_rect(704, 76, 1, 40, 60, 75, 90, 160, 1212)
    draw_text("OPTIONS", 560, 102, 16, 175, 185, 195, 255, 1260)
    draw_text("3", 675, 102, 13, 130, 145, 165, 255, 1260)

    -- ACTIVE [ MODS 4 ] TAB (X=716..886)
    draw_rect(716, 72, 170, 48, 42, 38, 16, 255, 1210)
    draw_rect(716, 72, 170, 1, 245, 215, 55, 255, 1212)
    draw_rect(716, 72, 1, 48, 245, 215, 55, 255, 1212)
    draw_rect(886, 72, 1, 48, 245, 215, 55, 255, 1212)
    draw_text("MODS", 752, 102, 16, 255, 220, 65, 255, 1260)
    draw_text("4", 840, 102, 13, 255, 215, 55, 255, 1260)
    -- Helldivers 2 signature diagonal striped underline
    draw_rect(716, 118, 170, 3, 245, 205, 45, 255, 1215)
    draw_text("////// 4 //////", 745, 124, 10, 245, 205, 45, 255, 1260)

    -- [E] Button (X=896, Y=80)
    draw_rect(896, 80, 26, 24, 245, 245, 248, 255, 1210)
    draw_rect(896, 104, 26, 4, 155, 160, 170, 255, 1210)
    draw_text("E", 904, 98, 13, 20, 24, 30, 255, 1260)

    -- Note: Mode switchers removed from top right; X=930..1920 left clear so currencies and Level 105 show cleanly!

    -- Full-width divider line underneath top bar at Y=120
    draw_rect(76, 120, 1764, 2, 60, 75, 90, 200, 1210)"""
assert old_state2_top in text, "old_state2_top not found"
text = text.replace(old_state2_top, new_state2_top)

# 11. Column 1 category button counts & active styling
old_col1_cats = """    for ci = cat_start, cat_end do
        local cname = categories[ci]
        local ccount = #(by_cat[cname] or {})
        local ry = 165 + (ci - cat_start) * 52
        local is_active_cat = (tab == 1 and ci == cat_idx)
        local disp_cat = cname:upper()
        if #disp_cat > 22 then disp_cat = disp_cat:sub(1, 19) .. "..." end

        if is_active_cat then
            -- Solid Yellow Active Highlight (Exact Helldivers 2 Native Style like Shallow Water Diving in Image 2)
            draw_rect(76, ry, 310, 46, 235, 195, 45, 255, 958)
            draw_text(disp_cat, 92, ry + 30, 16, 12, 16, 22, 255, 970)
            draw_text(format("(%d)", ccount), 340, ry + 30, 13, 40, 32, 10, 255, 970)
        else
            -- Dark Subtle Inactive Button
            draw_rect(76, ry, 310, 46, 18, 24, 32, 210, 958)
            draw_text(disp_cat, 92, ry + 30, 15, 195, 205, 215, 255, 970)
            draw_text(format("(%d)", ccount), 340, ry + 30, 13, 130, 145, 165, 255, 970)
        end
    end"""

new_col1_cats = """    for ci = cat_start, cat_end do
        local cname = categories[ci]
        local ccount = 0
        if cname == "KEY BINDINGS" then
            ccount = total_binds
        elseif cname == "LOADED MODS" then
            ccount = total_mods
        else
            ccount = #(by_cat[cname] or {})
        end
        local ry = 165 + (ci - cat_start) * 52
        local is_active_cat = (ci == cat_idx)
        local disp_cat = cname:upper()
        if #disp_cat > 22 then disp_cat = disp_cat:sub(1, 19) .. "..." end

        if is_active_cat then
            -- Solid Yellow Active Highlight (Exact Helldivers 2 Native Style like Shallow Water Diving in Image 2)
            draw_rect(76, ry, 310, 46, 235, 195, 45, 255, 1215)
            draw_text(disp_cat, 92, ry + 30, 16, 12, 16, 22, 255, 1260)
            draw_text(format("(%d)", ccount), 340, ry + 30, 13, 40, 32, 10, 255, 1260)
        else
            -- Dark Subtle Inactive Button
            draw_rect(76, ry, 310, 46, 18, 24, 32, 210, 1215)
            draw_text(disp_cat, 92, ry + 30, 15, 195, 205, 215, 255, 1260)
            draw_text(format("(%d)", ccount), 340, ry + 30, 13, 130, 145, 165, 255, 1260)
        end
    end"""
assert old_col1_cats in text, "old_col1_cats not found"
text = text.replace(old_col1_cats, new_col1_cats)

# 12. Footer bar text & key labels
old_footer = """    -- ==========================================================================
    -- NATIVE FOOTER NAVIGATION BAR (Y=1020..1050)
    -- ==========================================================================
    draw_text("ESC  CLOSE", 76, 1035, 15, 220, 225, 235, 255, 970)
    draw_text("R  RESET DEFAULT", 220, 1035, 15, 200, 215, 235, 255, 970)
    draw_text("ENTER  APPLY", 410, 1035, 15, 245, 215, 65, 255, 970)
    draw_text("MOUSE: Click / Drag  |  WHEEL: Scroll  |  Q/E: Categories", 1320, 1035, 13, 140, 155, 175, 255, 970)"""

new_footer = """    -- ==========================================================================
    -- NATIVE FOOTER NAVIGATION BAR (Y=1020..1050)
    -- ==========================================================================
    draw_text("ESC  BACK", 76, 1035, 15, 220, 225, 235, 255, 1260)
    draw_text("TAB  APPLY", 220, 1035, 15, 245, 215, 65, 255, 1260)
    draw_text("R  RESET TO DEFAULT", 370, 1035, 15, 200, 215, 235, 255, 1260)
    draw_text("MOUSE: Click / Drag  |  WHEEL: Scroll  |  Q/E: Categories", 1320, 1035, 13, 140, 155, 175, 255, 1260)"""
assert old_footer in text, "old_footer not found"
text = text.replace(old_footer, new_footer)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

print("All 12 edits applied successfully to", path)
