import os, re

path = r"G:\antigravity\UniversalModLoader-v1.0.0\src\boot_loader.lua"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. draw_text layer: change math.max(1260, ...) to safe math.min(998, math.max(995, (layer or 995) + 5))
old_text_layer = "local text_layer = math.max(1260, (layer or 1260) + 25)"
new_text_layer = "local text_layer = math.min(998, math.max(995, (layer or 995) + 5))"
assert old_text_layer in text, "old_text_layer not found"
text = text.replace(old_text_layer, new_text_layer)

# 2. draw_rect layer: change default layer from 1215 to 985
old_draw_rect = "local pos = sr.Vector3(sx, H - sy_top - sh, layer or (UniversalState.menu_visible and 1215 or 955))"
new_draw_rect = "local pos = sr.Vector3(sx, H - sy_top - sh, layer or (UniversalState.menu_visible and 985 or 955))"
assert old_draw_rect in text, "old_draw_rect not found"
text = text.replace(old_draw_rect, new_draw_rect)

# 3. State 1 closed tab: Solid 100% opaque background (alpha=255) covering native [E], and REMOVE white square
old_state1 = """        -- Inactive MODS Tab in Top Bar (X=716..886, Y=72..120 connecting directly with native baseline at Y=120)
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

new_state1 = """        -- Inactive MODS Tab in Top Bar (X=716..886, Y=72..120 connecting directly with native baseline at Y=120)
        local bx, by, bw, bh = ESC_TOP_MODS_BTN.x, ESC_TOP_MODS_BTN.y, ESC_TOP_MODS_BTN.w, ESC_TOP_MODS_BTN.h
        -- Solid 100% OPAQUE (alpha=255) backdrop completely covering whatever is behind the tab (native [E] prompt)
        draw_rect(bx, by, bw, bh, 12, 16, 22, 255, 960)
        -- Bracket borders matching native Helldivers 2 tabs
        draw_rect(bx, by, bw, 1, 60, 75, 90, hov_top and 255 or 140, 965)
        draw_rect(bx, by + bh - 2, bw, 2, 60, 75, 90, 180, 965)
        draw_rect(bx, by + 4, 1, bh - 6, 60, 75, 90, 160, 965)
        draw_rect(bx + bw, by + 4, 1, bh - 6, 60, 75, 90, 160, 965)
        -- Label
        draw_text("MODS", bx + 36, by + 28, 16, hov_top and 255 or 195, hov_top and 240 or 205, hov_top and 140 or 215, 255, 970)
        draw_text("4", bx + 124, by + 28, 13, 130, 145, 165, 255, 970)"""
assert old_state1 in text, "old_state1 not found"
text = text.replace(old_state1, new_state1)

# 4. Replace all remaining layer numbers > 1000 with safe range 980..995
text = text.replace(", 1200)", ", 980)")
text = text.replace(", 1210)", ", 985)")
text = text.replace(", 1212)", ", 986)")
text = text.replace(", 1215)", ", 985)")
text = text.replace(", 1260)", ", 995)")

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

print("Layer and tab fixes applied successfully!")
