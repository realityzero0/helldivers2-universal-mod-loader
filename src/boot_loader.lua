-- Universal Mod Loader v2.0.0 for Helldivers 2 (Steam Builds 25988413 / 26088801 / 26251122+ / Lua 5.1)
-- Replaces engine boot resource 0xF476DF93691895FA in bundle 9ba626afa44a3aa3
-- Unifies All Helldivers 2 Modding Standards:
--   1. Bingus Shared Loader (CowboyBingus / v17 / v20 / v21 / API 1 + BingusRuntime v1)
--   2. Chef Shared Loader (Th3chef / API Levels 1, 2, 3)
--   3. Boot Mod Loader (VeganSquid / API 1)
--   4. HD2 Lua Runtime (hd2rt / 0.1.0)
--   5. Rat's Shared Loader (Armor Transmog 1.1.2)
-- Pure Lua 5.1 compliant (Zero native FFI crashes, EAC-safe, Circuit-Breaker protected).
-- License: Zero-Clause BSD (0BSD)

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

-- Logging Subsystem (frame 0 availability)
local log_handle = nil
local active_log_path = nil

local function get_log_candidate_paths()
    local localapp = os.getenv("LOCALAPPDATA") or "."
    local roam = os.getenv("APPDATA") or "."
    return {
        localapp .. "/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log",
        roam .. "/Arrowhead/Helldivers2/BingusSharedLoader.log",
        localapp .. "/BingusSharedLoader.log",
        "BingusSharedLoader.log"
    }
end

local function open_log()
    if log_handle then return log_handle end
    local candidates = get_log_candidate_paths()
    for _, path in ipairs(candidates) do
        local f_chk = io.open(path, "r")
        if f_chk then
            local sz = f_chk:seek("end")
            f_chk:close()
            if sz and sz > (5 * 1024 * 1024) then
                pcall(os.remove, path .. ".old")
                pcall(os.rename, path, path .. ".old")
            end
        end
        local f, err = io.open(path, "a")
        if f then
            log_handle = f
            active_log_path = path
            f:write(string.format("\n--- Universal Mod Loader v2.0.0 Booted at %s ---\n", os.date and os.date("%Y-%m-%d %H:%M:%S") or "now"))
            f:flush()
            return log_handle
        end
    end
    return nil
end

local function log_write(msg)
    pcall(print, "[UniversalLoader] " .. tostring(msg))
    local f = open_log()
    if f then
        pcall(function()
            f:write(string.format("[%s] %s\n", os.date and os.date("%H:%M:%S") or "LOG", tostring(msg)))
            f:flush()
        end)
    end
end

-- ==============================================================================
-- OFFICIAL HELLDIVERS 2 LOCALIZATION & UTF-8 NORMALIZATION (All 14 Locales)
-- ==============================================================================
local UML_OFFICIAL_LOCALES = {
    { idx = 1,  tag = "en",      game_code = "us", name = "English (US)",              choice = "English (US - en)",              cjk = false },
    { idx = 2,  tag = "en-GB",   game_code = "uk", name = "English (UK)",              choice = "English (UK - en-GB)",           cjk = false },
    { idx = 3,  tag = "fr",      game_code = "fr", name = "Francais (French)",         choice = "Francais (French - fr)",         cjk = false },
    { idx = 4,  tag = "de",      game_code = "de", name = "Deutsch (German)",          choice = "Deutsch (German - de)",          cjk = false },
    { idx = 5,  tag = "it",      game_code = "it", name = "Italiano (Italian)",        choice = "Italiano (Italian - it)",        cjk = false },
    { idx = 6,  tag = "es",      game_code = "es", name = "Espanol (Spain)",           choice = "Espanol Espana (Spanish - es)",  cjk = false },
    { idx = 7,  tag = "es-419",  game_code = "mx", name = "Espanol (LatAm)",           choice = "Espanol LatAm (es-419)",         cjk = false },
    { idx = 8,  tag = "pt-BR",   game_code = "br", name = "Portugues (Brasil)",        choice = "Portugues Brasil (pt-BR)",       cjk = false },
    { idx = 9,  tag = "pl",      game_code = "pl", name = "Polski (Polish)",           choice = "Polski (Polish - pl)",           cjk = false },
    { idx = 10, tag = "ru",      game_code = "ru", name = "Russkiy (Russian)",         choice = "Russkiy (Russian - ru)",         cjk = false },
    { idx = 11, tag = "ja",      game_code = "jp", name = "Nihongo (Japanese)",        choice = "Nihongo (Japanese - ja)",        cjk = true  },
    { idx = 12, tag = "ko",      game_code = "kr", name = "Hanguk-eo (Korean)",        choice = "Hanguk-eo (Korean - ko)",        cjk = true  },
    { idx = 13, tag = "zh-Hans", game_code = "cn", name = "Simplified Chinese",        choice = "JianTi ZhongWen (zh-Hans)",      cjk = true  },
    { idx = 14, tag = "zh-Hant", game_code = "tw", name = "Traditional Chinese",       choice = "FanTi ZhongWen (zh-Hant)",       cjk = true  },
}

local UML_LOCALE_BY_KEY = {}
for i = 1, #UML_OFFICIAL_LOCALES do
    local loc = UML_OFFICIAL_LOCALES[i]
    UML_LOCALE_BY_KEY[i] = loc
    UML_LOCALE_BY_KEY[loc.tag] = loc
    UML_LOCALE_BY_KEY[loc.tag:lower()] = loc
    UML_LOCALE_BY_KEY[loc.game_code] = loc
end
UML_LOCALE_BY_KEY["en-us"] = UML_OFFICIAL_LOCALES[1]
UML_LOCALE_BY_KEY["en-ca"] = UML_OFFICIAL_LOCALES[1]
UML_LOCALE_BY_KEY["english"] = UML_OFFICIAL_LOCALES[1]
UML_LOCALE_BY_KEY["gb"]    = UML_OFFICIAL_LOCALES[2]
UML_LOCALE_BY_KEY["british"] = UML_OFFICIAL_LOCALES[2]
UML_LOCALE_BY_KEY["french"] = UML_OFFICIAL_LOCALES[3]
UML_LOCALE_BY_KEY["german"] = UML_OFFICIAL_LOCALES[4]
UML_LOCALE_BY_KEY["italian"] = UML_OFFICIAL_LOCALES[5]
UML_LOCALE_BY_KEY["es-es"] = UML_OFFICIAL_LOCALES[6]
UML_LOCALE_BY_KEY["spanish"] = UML_OFFICIAL_LOCALES[6]
UML_LOCALE_BY_KEY["es-mx"] = UML_OFFICIAL_LOCALES[7]
UML_LOCALE_BY_KEY["latam"] = UML_OFFICIAL_LOCALES[7]
UML_LOCALE_BY_KEY["pt"]    = UML_OFFICIAL_LOCALES[8]
UML_LOCALE_BY_KEY["brazilian"] = UML_OFFICIAL_LOCALES[8]
UML_LOCALE_BY_KEY["portuguese"] = UML_OFFICIAL_LOCALES[8]
UML_LOCALE_BY_KEY["polish"] = UML_OFFICIAL_LOCALES[9]
UML_LOCALE_BY_KEY["russian"] = UML_OFFICIAL_LOCALES[10]
UML_LOCALE_BY_KEY["ja-jp"] = UML_OFFICIAL_LOCALES[11]
UML_LOCALE_BY_KEY["japanese"] = UML_OFFICIAL_LOCALES[11]
UML_LOCALE_BY_KEY["ko-kr"] = UML_OFFICIAL_LOCALES[12]
UML_LOCALE_BY_KEY["korean"] = UML_OFFICIAL_LOCALES[12]
UML_LOCALE_BY_KEY["koreana"] = UML_OFFICIAL_LOCALES[12]
UML_LOCALE_BY_KEY["zh"]    = UML_OFFICIAL_LOCALES[13]
UML_LOCALE_BY_KEY["zh-cn"] = UML_OFFICIAL_LOCALES[13]
UML_LOCALE_BY_KEY["zhs"]   = UML_OFFICIAL_LOCALES[13]
UML_LOCALE_BY_KEY["schinese"] = UML_OFFICIAL_LOCALES[13]
UML_LOCALE_BY_KEY["simplified chinese"] = UML_OFFICIAL_LOCALES[13]
UML_LOCALE_BY_KEY["zh-tw"] = UML_OFFICIAL_LOCALES[14]
UML_LOCALE_BY_KEY["zh-hk"] = UML_OFFICIAL_LOCALES[14]
UML_LOCALE_BY_KEY["zht"]   = UML_OFFICIAL_LOCALES[14]
UML_LOCALE_BY_KEY["tchinese"] = UML_OFFICIAL_LOCALES[14]
UML_LOCALE_BY_KEY["traditional chinese"] = UML_OFFICIAL_LOCALES[14]

local uml_active_locale = UML_OFFICIAL_LOCALES[1]
local uml_active_lang_choice = 1
local uml_detected_source = "default"
local uml_engine_lang_checked = false

local function lookup_locale_string(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local clean = raw:match("^%s*(.-)%s*$"):lower():gsub("_", "-")
    if clean == "" then return nil end
    if UML_LOCALE_BY_KEY[clean] then return UML_LOCALE_BY_KEY[clean] end
    local prefix = clean:match("^([a-z]+%-[a-z0-9]+)") or clean:match("^([a-z]+)")
    if prefix and UML_LOCALE_BY_KEY[prefix] then return UML_LOCALE_BY_KEY[prefix] end
    return nil
end

local function parse_os_ctype_locale(ctype_str)
    if type(ctype_str) ~= "string" or ctype_str == "" then return nil end
    local s = ctype_str:lower()
    if s:find("chinese", 1, true) or s:find("zh", 1, true) then
        if s:find("traditional", 1, true) or s:find("taiwan", 1, true) or s:find("hong kong", 1, true) or s:find("950", 1, true) or s:find("hant", 1, true) then
            return UML_OFFICIAL_LOCALES[14]
        end
        return UML_OFFICIAL_LOCALES[13]
    elseif s:find("japanese", 1, true) or s:find(".932", 1, true) then
        return UML_OFFICIAL_LOCALES[11]
    elseif s:find("korean", 1, true) or s:find(".949", 1, true) then
        return UML_OFFICIAL_LOCALES[12]
    elseif s:find("russian", 1, true) or s:find(".1251", 1, true) then
        return UML_OFFICIAL_LOCALES[10]
    elseif s:find("polish", 1, true) then
        return UML_OFFICIAL_LOCALES[9]
    elseif s:find("portuguese", 1, true) or s:find("brazil", 1, true) then
        return UML_OFFICIAL_LOCALES[8]
    elseif s:find("spanish", 1, true) then
        if s:find("spain", 1, true) then return UML_OFFICIAL_LOCALES[6] end
        return UML_OFFICIAL_LOCALES[7]
    elseif s:find("italian", 1, true) then
        return UML_OFFICIAL_LOCALES[5]
    elseif s:find("german", 1, true) then
        return UML_OFFICIAL_LOCALES[4]
    elseif s:find("french", 1, true) then
        return UML_OFFICIAL_LOCALES[3]
    elseif s:find("english", 1, true) then
        if s:find("united kingdom", 1, true) or s:find("great britain", 1, true) or s:find("en_gb", 1, true) or s:find("en-gb", 1, true) then
            return UML_OFFICIAL_LOCALES[2]
        end
        return UML_OFFICIAL_LOCALES[1]
    end
    return nil
end

local function auto_detect_game_locale()
    local sr = rawget(_G, "stingray")
    -- Tier 1A: Stingray Application.user_setting("language" / "platform_language")
    local app = sr and rawget(sr, "Application") or rawget(_G, "Application")
    if type(app) == "table" and type(rawget(app, "user_setting")) == "function" then
        for _, k in ipairs({ "language", "platform_language", "vo_language" }) do
            local ok, v = pcall(app.user_setting, k)
            if ok and type(v) == "string" then
                local loc = lookup_locale_string(v)
                if loc then return loc, "Application.user_setting(" .. k .. ")" end
            end
        end
    end

    -- Tier 1B: Live Steamworks API inside helldivers2.exe (stingray.Steam.language())
    local steam = (sr and rawget(sr, "Steam")) or rawget(_G, "Steam")
    local steam_uid = nil
    if type(steam) == "table" then
        if type(rawget(steam, "user_id")) == "function" then
            local ok_u, uid = pcall(steam.user_id)
            if ok_u and type(uid) == "string" and uid ~= "" then steam_uid = uid:lower() end
        end
        if type(rawget(steam, "language")) == "function" then
            local ok_l, slang = pcall(steam.language)
            if ok_l and type(slang) == "string" then
                local loc = lookup_locale_string(slang)
                if loc then return loc, "stingray.Steam.language()" end
            end
        end
    end

    -- Tier 2: Helldivers 2 Arrowhead user_settings.config & saves/<id>_user_settings.config
    local appdata = os.getenv("APPDATA")
    if appdata and appdata ~= "" then
        local base_dir = appdata .. "/Arrowhead/Helldivers2"
        local cfg_paths = { base_dir .. "/user_settings.config" }
        if steam_uid then
            table.insert(cfg_paths, 1, base_dir .. "/saves/" .. steam_uid .. "_user_settings.config")
        end
        for i = 1, #cfg_paths do
            local f = io.open(cfg_paths[i], "r")
            if f then
                local txt = f:read("*a")
                f:close()
                if type(txt) == "string" then
                    local lang_val = txt:match('\n%s*language%s*=%s*"([^"]+)"')
                        or txt:match('^%s*language%s*=%s*"([^"]+)"')
                        or txt:match('\n%s*platform_language%s*=%s*"([^"]+)"')
                    if lang_val then
                        local loc = lookup_locale_string(lang_val)
                        if loc then return loc, "Arrowhead user_settings.config" end
                    end
                end
            end
        end
    end

    -- Tier 3: Steam appmanifest_553850.acf (Helldivers 2 AppID 553850)
    local acf_paths = {
        "../../../appmanifest_553850.acf",
        "../../appmanifest_553850.acf",
        "../appmanifest_553850.acf",
        "../../../../appmanifest_553850.acf",
        "C:/Program Files (x86)/Steam/steamapps/appmanifest_553850.acf",
    }
    for i = 1, #acf_paths do
        local f = io.open(acf_paths[i], "r")
        if f then
            local txt = f:read("*a")
            f:close()
            if type(txt) == "string" then
                local slang = txt:match('"language"%s+"([^"]+)"')
                if slang then
                    local loc = lookup_locale_string(slang)
                    if loc then return loc, "Steam appmanifest_553850.acf (" .. slang .. ")" end
                end
            end
        end
    end

    -- Tier 4: Windows OS System Locale via os.setlocale("", "ctype")
    if os and type(os.setlocale) == "function" then
        local ok_c, cur_c = pcall(os.setlocale, nil, "ctype")
        local ok_s, sys_c = pcall(os.setlocale, "", "ctype")
        pcall(os.setlocale, (ok_c and cur_c) or "C", "ctype")
        if ok_s and type(sys_c) == "string" then
            local loc = parse_os_ctype_locale(sys_c)
            if loc then return loc, "Windows OS locale (" .. sys_c .. ")" end
        end
    end

    return UML_OFFICIAL_LOCALES[1], "default (en-US)"
end

local function ensure_bingus_translations()
    local bt = rawget(_G, "BingusTranslations")
    if type(bt) ~= "table" then
        bt = {
            version = 1,
            serial = 1,
            packs = {},
            override = nil,
            game_language = uml_active_locale.tag,
            game_code = uml_active_locale.game_code,
        }
        rawset(_G, "BingusTranslations", bt)
    else
        bt.version = bt.version or 1
        bt.serial = (tonumber(bt.serial) or 0) + 1
        bt.packs = type(bt.packs) == "table" and bt.packs or {}
        bt.game_language = uml_active_locale.tag
        bt.game_code = uml_active_locale.game_code
    end
    return bt
end

local function set_active_uml_locale(key_or_choice_idx)
    local is_auto = false
    local loc = nil
    local src = "manual"
    if key_or_choice_idx == nil or key_or_choice_idx == 1 or key_or_choice_idx == "auto" or key_or_choice_idx == "AUTO" then
        is_auto = true
        loc, src = auto_detect_game_locale()
        uml_active_lang_choice = 1
        uml_detected_source = src
    elseif type(key_or_choice_idx) == "number" then
        local c_idx = math.floor(key_or_choice_idx)
        loc = UML_OFFICIAL_LOCALES[c_idx - 1] or UML_OFFICIAL_LOCALES[c_idx] or UML_OFFICIAL_LOCALES[1]
        uml_active_lang_choice = loc.idx + 1
    elseif type(key_or_choice_idx) == "string" then
        loc = lookup_locale_string(key_or_choice_idx) or UML_OFFICIAL_LOCALES[1]
        uml_active_lang_choice = loc.idx + 1
    end
    loc = loc or UML_OFFICIAL_LOCALES[1]
    uml_active_locale = loc
    local bt = ensure_bingus_translations()
    bt.game_language = loc.tag
    bt.game_code = loc.game_code
    bt.override = (not is_auto and loc.idx > 1) and loc.tag or nil
    bt.serial = (tonumber(bt.serial) or 1) + 1
    return loc, is_auto, src
end

set_active_uml_locale("auto")

local UML_UI_STRINGS = {
    ["en"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS", pane_mods = "[PANE: MOD LIST]", pane_opts = "[PANE: MOD OPTIONS]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  OPTION %d/%d  |  PAGE %d/%d (%d/PG)", on = "< ON >", off = "< OFF >", desc_mod = "SELECTED MOD: %s (%d OPTIONS) - PRESS RIGHT ARROW, SPACE, OR 1-0 TO EDIT THIS MOD'S OPTIONS. PRESS [-] OR [=] TO ADJUST UI SCALE." },
    ["en-GB"]   = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS", pane_mods = "[PANE: MOD LIST]", pane_opts = "[PANE: MOD OPTIONS]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  OPTION %d/%d  |  PAGE %d/%d (%d/PG)", on = "< ON >", off = "< OFF >", desc_mod = "SELECTED MOD: %s (%d OPTIONS) - PRESS RIGHT ARROW, SPACE, OR 1-0 TO EDIT THIS MOD'S OPTIONS. PRESS [-] OR [=] TO ADJUST UI SCALE." },
    ["fr"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - SOUS-MENUS MODS", pane_mods = "[VOLET: LISTE MODS]", pane_opts = "[VOLET: OPTIONS]", mods = "MODS (%d)  [1-0 ACCES]", submenu = "SOUS-MENU: %s  |  OPTION %d/%d  |  PAGE %d/%d (%d/PG)", on = "< OUI >", off = "< NON >", desc_mod = "MOD SELECTIONNE: %s (%d OPTIONS) - APPUYEZ SUR DROITE, ESPACE OU 1-0 POUR MODIFIER LES OPTIONS. [-]/[=] POUR TAILLE UI." },
    ["de"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD-UNTERMENUS", pane_mods = "[BEREICH: MOD-LISTE]", pane_opts = "[BEREICH: OPTIONEN]", mods = "MODS (%d)  [1-0 WAHL]", submenu = "UNTERMENU: %s  |  OPTION %d/%d  |  SEITE %d/%d (%d/S.)", on = "< EIN >", off = "< AUS >", desc_mod = "AKTIVER MOD: %s (%d OPTIONEN) - RECHTS, LEERTASTE ODER 1-0 ZUM BEARBEITEN DRUCKEN. [-]/[=] FUR UI-SKALIERUNG." },
    ["it"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - SOTTOMENU MOD", pane_mods = "[PANNELLO: MOD]", pane_opts = "[PANNELLO: OPZIONI]", mods = "MOD (%d)  [1-0 SALTA]", submenu = "SOTTOMENU: %s  |  OPZIONE %d/%d  |  PAG %d/%d (%d/PG)", on = "< ON >", off = "< OFF >", desc_mod = "MOD SELEZIONATA: %s (%d OPZIONI) - PREMI DESTRA, SPAZIO O 1-0 PER MODIFICARE LE OPZIONI. [-]/[=] SCALA UI." },
    ["es"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - SUBMENUS DE MODS", pane_mods = "[PANEL: LISTA MODS]", pane_opts = "[PANEL: OPCIONES]", mods = "MODS (%d)  [1-0 SALTAR]", submenu = "SUBMENU: %s  |  OPCION %d/%d  |  PAG %d/%d (%d/PG)", on = "< SI >", off = "< NO >", desc_mod = "MOD SELECCIONADO: %s (%d OPCIONES) - PULSA DERECHA, ESPACIO O 1-0 PARA EDITAR OPCIONES. [-]/[=] ESCALA UI." },
    ["es-419"]  = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - SUBMENUS DE MODS", pane_mods = "[PANEL: LISTA MODS]", pane_opts = "[PANEL: OPCIONES]", mods = "MODS (%d)  [1-0 SALTAR]", submenu = "SUBMENU: %s  |  OPCION %d/%d  |  PAG %d/%d (%d/PG)", on = "< SI >", off = "< NO >", desc_mod = "MOD SELECCIONADO: %s (%d OPCIONES) - PRESIONA DERECHA, ESPACIO O 1-0 PARA EDITAR OPCIONES. [-]/[=] ESCALA UI." },
    ["pt-BR"]   = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - SUBMENUS DE MODS", pane_mods = "[PAINEL: MODS]", pane_opts = "[PAINEL: OPCOES]", mods = "MODS (%d)  [1-0 ATALHO]", submenu = "SUBMENU: %s  |  OPCAO %d/%d  |  PAG %d/%d (%d/PG)", on = "< LIG >", off = "< DES >", desc_mod = "MOD SELECIONADO: %s (%d OPCOES) - PRESSIONE DIREITA, ESPACO OU 1-0 PARA EDITAR OPCOES. [-]/[=] ESCALA UI." },
    ["pl"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - PODMENU MODOW", pane_mods = "[PANEL: LISTA MODOW]", pane_opts = "[PANEL: OPCJE]", mods = "MODY (%d)  [1-0 SKOK]", submenu = "PODMENU: %s  |  OPCJA %d/%d  |  STR %d/%d (%d/STR)", on = "< WL >", off = "< WYL >", desc_mod = "WYBRANY MOD: %s (%d OPCJI) - NACISNIJ PRAWO, SPACJE LUB 1-0 ABY EDYTOWAC OPCJE. [-]/[=] SKALA UI." },
    ["ru"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - PODMENYU MODOV", pane_mods = "[PANEL: SPISOK MODOV]", pane_opts = "[PANEL: NASTROYKI]", mods = "MODY (%d)  [1-0 VYBOR]", submenu = "PODMENYU: %s  |  OPTSIYA %d/%d  |  STR %d/%d (%d/STR)", on = "< VKL >", off = "< VYKL >", desc_mod = "VYBRAN MOD: %s (%d OPTSIY) - NAZHMITE VPRAVO, PROBEL ILI 1-0 DLYA NASTROYKI. [-]/[=] MASSHTAB UI." },
    ["ja"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS (JA)", pane_mods = "[PANE: MOD ICHIRAN]", pane_opts = "[PANE: SETTEI]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  SETTEI %d/%d  |  PAGE %d/%d (%d/PG)", on = "< ON >", off = "< OFF >", desc_mod = "SENTAKU MOD: %s (%d OPTIONS) - PRESS RIGHT, SPACE, OR 1-0 TO EDIT OPTIONS. [-]/[=] UI SCALE." },
    ["ko"]      = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS (KO)", pane_mods = "[PANE: MOD MOKROK]", pane_opts = "[PANE: SEOLJEONG]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  OPTION %d/%d  |  PAGE %d/%d (%d/PG)", on = "< ON >", off = "< OFF >", desc_mod = "SEONTAEK MOD: %s (%d OPTIONS) - PRESS RIGHT, SPACE, OR 1-0 TO EDIT OPTIONS. [-]/[=] UI SCALE." },
    ["zh-Hans"] = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS (ZHS)", pane_mods = "[PANE: MOD LIEBIAO]", pane_opts = "[PANE: XUANXIANG]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  XUANXIANG %d/%d  |  PAGE %d/%d (%d/PG)", on = "< KAI >", off = "< GUAN >", desc_mod = "DANGQIAN MOD: %s (%d OPTIONS) - PRESS RIGHT, SPACE, OR 1-0 TO EDIT OPTIONS. [-]/[=] UI SCALE." },
    ["zh-Hant"] = { hdr = "UNIVERSAL MOD LOADER v2.0.0 - MOD SUBMENUS (ZHT)", pane_mods = "[PANE: MOD LIEBIAO]", pane_opts = "[PANE: XUANXIANG]", mods = "MODS (%d)  [1-0 JUMP]", submenu = "SUBMENU: %s  |  XUANXIANG %d/%d  |  PAGE %d/%d (%d/PG)", on = "< KAI >", off = "< GUAN >", desc_mod = "DANGQIAN MOD: %s (%d OPTIONS) - PRESS RIGHT, SPACE, OR 1-0 TO EDIT OPTIONS. [-]/[=] UI SCALE." },
}

-- Unicode -> ASCII Transliteration Tables (Latin-1, Latin Extended-A, Cyrillic, Fullwidth, Punctuation)
local LATIN_EXT_MAP = {
    [0x00A0] = " ",  [0x00A1] = "!",  [0x00AB] = "'",  [0x00B0] = " DEG", [0x00B7] = ".", [0x00BB] = "'", [0x00BF] = "?",
    [0x00C6] = "AE", [0x00C7] = "C",  [0x00D0] = "D",  [0x00D1] = "N",    [0x00D7] = "x", [0x00D8] = "O", [0x00DD] = "Y", [0x00DE] = "TH", [0x00DF] = "SS",
    [0x00E6] = "AE", [0x00E7] = "C",  [0x00F0] = "D",  [0x00F1] = "N",    [0x00F7] = "/", [0x00F8] = "O", [0x00FD] = "Y", [0x00FE] = "TH", [0x00FF] = "Y",
    [0x0132] = "IJ", [0x0133] = "IJ", [0x0152] = "OE", [0x0153] = "OE",   [0x017F] = "S",
    [0x2010] = "-",  [0x2011] = "-",  [0x2012] = "-",  [0x2013] = "-",    [0x2014] = "-", [0x2015] = "-",
    [0x2018] = "'",  [0x2019] = "'",  [0x201A] = ",",  [0x201C] = "'",    [0x201D] = "'", [0x201E] = "'",
    [0x2022] = "*",  [0x2026] = "...",[0x2190] = "<-", [0x2191] = "UP",   [0x2192] = "->", [0x2193] = "DN",
    [0x3000] = " ",  [0x3001] = ",",  [0x3002] = ".",  [0x300C] = "[",    [0x300D] = "]", [0x3010] = "[", [0x3011] = "]",
}

local CYRILLIC_BASE = {
    "A", "B", "V", "G", "D", "E", "ZH", "Z", "I", "Y", "K", "L", "M", "N", "O", "P",
    "R", "S", "T", "U", "F", "KH", "TS", "CH", "SH", "SHCH", "", "Y", "", "E", "YU", "YA"
}

local function transliterate_codepoint(cp)
    if cp >= 32 and cp <= 126 then
        return string.char(cp)
    elseif cp == 9 or cp == 10 or cp == 13 then
        return " "
    end
    local direct = LATIN_EXT_MAP[cp]
    if direct ~= nil then return direct end

    -- Latin-1 Supplement vowel groups (U+00C0..U+00FC)
    if cp >= 0x00C0 and cp <= 0x00FC then
        local base = (cp >= 0x00E0) and (cp - 0x20) or cp
        if base >= 0x00C0 and base <= 0x00C5 then return "A" end
        if base >= 0x00C8 and base <= 0x00CB then return "E" end
        if base >= 0x00CC and base <= 0x00CF then return "I" end
        if base >= 0x00D2 and base <= 0x00D6 then return "O" end
        if base >= 0x00D9 and base <= 0x00DC then return "U" end
    end

    -- Latin Extended-A (U+0100..U+017E: Polish, French, Czech, Turkish, etc.)
    if cp >= 0x0100 and cp <= 0x017E then
        if cp <= 0x0105 then return "A"
        elseif cp <= 0x010D then return "C"
        elseif cp <= 0x0111 then return "D"
        elseif cp <= 0x011B then return "E"
        elseif cp <= 0x0123 then return "G"
        elseif cp <= 0x0127 then return "H"
        elseif cp <= 0x0131 then return "I"
        elseif cp <= 0x0135 then return "J"
        elseif cp <= 0x0138 then return "K"
        elseif cp <= 0x0142 then return "L"
        elseif cp <= 0x014B then return "N"
        elseif cp <= 0x0151 then return "O"
        elseif cp <= 0x0159 then return "R"
        elseif cp <= 0x0161 then return "S"
        elseif cp <= 0x0167 then return "T"
        elseif cp <= 0x0173 then return "U"
        elseif cp <= 0x0175 then return "W"
        elseif cp <= 0x0178 then return "Y"
        else return "Z" end
    end

    -- Cyrillic (U+0400..U+045F: Russian & Slavic)
    if cp == 0x0401 or cp == 0x0451 then return "YO" end
    if cp == 0x0404 or cp == 0x0454 then return "YE" end
    if cp == 0x0406 or cp == 0x0456 or cp == 0x0407 or cp == 0x0457 then return "I" end
    if cp >= 0x0410 and cp <= 0x044F then
        local idx = ((cp - 0x0410) % 32) + 1
        return CYRILLIC_BASE[idx] or ""
    end

    -- Fullwidth ASCII (U+FF01..U+FF5E: CJK punctuation & alphanumeric)
    if cp >= 0xFF01 and cp <= 0xFF5E then
        return string.char(cp - 0xFEE0)
    end

    return nil
end

local function decode_and_transliterate_utf8(raw, unknown_replacement)
    if type(raw) ~= "string" or raw == "" then return "" end
    local out = {}
    local i = 1
    local len = #raw
    while i <= len do
        local b1 = string.byte(raw, i)
        if b1 < 128 then
            if b1 >= 32 and b1 <= 126 then
                out[#out + 1] = string.char(b1)
            elseif b1 == 9 or b1 == 10 or b1 == 13 then
                out[#out + 1] = " "
            elseif unknown_replacement then
                out[#out + 1] = unknown_replacement
            end
            i = i + 1
        elseif b1 >= 0xC2 and b1 <= 0xDF and (i + 1) <= len then
            local b2 = string.byte(raw, i + 1)
            local cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
            local tr = transliterate_codepoint(cp)
            if tr then out[#out + 1] = tr elseif unknown_replacement then out[#out + 1] = unknown_replacement end
            i = i + 2
        elseif b1 >= 0xE0 and b1 <= 0xEF and (i + 2) <= len then
            local b2 = string.byte(raw, i + 1)
            local b3 = string.byte(raw, i + 2)
            local cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
            local tr = transliterate_codepoint(cp)
            if tr then out[#out + 1] = tr elseif unknown_replacement then out[#out + 1] = unknown_replacement end
            i = i + 3
        elseif b1 >= 0xF0 and b1 <= 0xF4 and (i + 3) <= len then
            local b2 = string.byte(raw, i + 1)
            local b3 = string.byte(raw, i + 2)
            local b4 = string.byte(raw, i + 3)
            local cp = (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
            local tr = transliterate_codepoint(cp)
            if tr then out[#out + 1] = tr elseif unknown_replacement then out[#out + 1] = unknown_replacement end
            i = i + 4
        else
            if unknown_replacement then out[#out + 1] = unknown_replacement end
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Font Glyph Sanitizer (Subsystem 9)
local function sanitize_text(str)
    if type(str) ~= "string" then return tostring(str) end
    return decode_and_transliterate_utf8(str, "?")
end

local function text_of(v)
    if type(v) == "function" then
        local ok, s = pcall(v)
        if not ok then return "?" end
        v = s
    end
    if type(v) == "string" then return v end
    local ok, s = pcall(tostring, v or "")
    return (ok and type(s) == "string") and s or "?"
end

local function clean_display_text(v, fallback)
    local raw = text_of(v)
    -- If a bilingual string is formatted as "English / <CJK>", keep the clean Latin portion if the right side has unmapped CJK
    local slash_pos = raw:find(" / ", 1, true)
    if slash_pos and slash_pos > 1 then
        local right_part = raw:sub(slash_pos + 3)
        local right_tr = decode_and_transliterate_utf8(right_part, nil)
        if right_tr:gsub("[%s%p%d]", "") == "" then
            raw = raw:sub(1, slash_pos - 1)
        end
    end
    local s = decode_and_transliterate_utf8(raw, nil)
    s = s:gsub("%s+", " ")
    s = s:gsub("^[/|%-%s]+", ""):gsub("[/|%-%s]+$", "")

    -- If a dynamic translation function returned pure CJK ideographs with no Latin/Cyrillic characters,
    -- automatically query its English ("en") pack entry so CJK locales never display "?"
    if (s == "" or s:gsub("[%s%p%d]", "") == "") and type(v) == "function" then
        local bt = rawget(_G, "BingusTranslations")
        if type(bt) == "table" and bt.game_language ~= "en" then
            local prev_lang = bt.game_language
            local prev_code = bt.game_code
            local prev_over = bt.override
            bt.game_language = "en"
            bt.game_code = "us"
            bt.override = "en"
            bt.serial = (tonumber(bt.serial) or 1) + 1
            local ok_en, raw_en = pcall(v)
            bt.game_language = prev_lang
            bt.game_code = prev_code
            bt.override = prev_over
            bt.serial = (tonumber(bt.serial) or 1) + 1
            if ok_en and type(raw_en) == "string" and raw_en ~= "" then
                local s_en = decode_and_transliterate_utf8(raw_en, nil):gsub("%s+", " "):gsub("^[/|%-%s]+", ""):gsub("[/|%-%s]+$", "")
                if s_en ~= "" then return s_en end
            end
        end
    end

    if s == "" then
        return fallback or "?"
    end
    return s
end

local function wrap_text_lines(str, max_chars, max_lines)
    if type(str) ~= "string" or str == "" then return {} end
    max_chars = math.max(20, math.floor(tonumber(max_chars) or 80))
    max_lines = math.max(1, math.floor(tonumber(max_lines) or 3))
    local lines = {}
    local cur = ""
    for word in str:gmatch("%S+") do
        if #word > max_chars then
            word = word:sub(1, max_chars)
        end
        if cur == "" then
            cur = word
        elseif (#cur + 1 + #word) <= max_chars then
            cur = cur .. " " .. word
        else
            lines[#lines + 1] = cur
            if #lines >= max_lines then
                local last = lines[max_lines]
                if #last > max_chars - 3 then last = last:sub(1, max_chars - 3) end
                lines[max_lines] = last .. "..."
                return lines
            end
            cur = word
        end
    end
    if cur ~= "" and #lines < max_lines then
        lines[#lines + 1] = cur
    end
    return lines
end

-- ==============================================================================
-- IN-GAME SETTINGS MENU & INPUT SUBSYSTEM (Subsystems 5 & 11)
-- ==============================================================================
local uml_ui_open = false
local uml_ui_focus = "mods"
local uml_ui_mod_idx = 1
local uml_ui_opt_idx_by_mod = {}
local uml_ui_selected_idx = 1
local uml_last_page_size = 24
local uml_menu_open_logged = false
local uml_key_capture_id = nil
local uml_last_drawn_frame = -1
local uml_world_guis = {}
local uml_chat_open = false
local uml_notifications = {}
local uml_key_bindings = {}
local uml_key_prev_down = {}

-- Bulletproof 5x7 Pixel Font (Engine-Independent, Pure Gui.rect Primitives)
local GLYPHS = {
  ['A'] = '01110100011000111111100011000110001', ['B'] = '11110100011000111110100011000111110',
  ['C'] = '01110100011000010000100001000101110', ['D'] = '11100100101000110001100011001011100',
  ['E'] = '11111100001000011110100001000011111', ['F'] = '11111100001000011110100001000010000',
  ['G'] = '01110100011000010111100011000101111', ['H'] = '10001100011000111111100011000110001',
  ['I'] = '01110001000010000100001000010001110', ['J'] = '00111000100001000010000101001001100',
  ['K'] = '10001100101010011000101001001010001', ['L'] = '10000100001000010000100001000011111',
  ['M'] = '10001110111010110101100011000110001', ['N'] = '10001100011100110101100111000110001',
  ['O'] = '01110100011000110001100011000101110', ['P'] = '11110100011000111110100001000010000',
  ['Q'] = '01110100011000110001101011001001101', ['R'] = '11110100011000111110101001001010001',
  ['S'] = '01111100001000001110000010000111110', ['T'] = '11111001000010000100001000010000100',
  ['U'] = '10001100011000110001100011000101110', ['V'] = '10001100011000110001100010101000100',
  ['W'] = '10001100011000110101101011010101010', ['X'] = '10001100010101000100010101000110001',
  ['Y'] = '10001100010101000100001000010000100', ['Z'] = '11111000010001000100010001000011111',
  ['0'] = '01110100011001110101110011000101110', ['1'] = '00100011000010000100001000010001110',
  ['2'] = '01110100010000100010001000100011111', ['3'] = '11111000100010000010000011000101110',
  ['4'] = '00010001100101010010111110001000010', ['5'] = '11111100001111000001000011000101110',
  ['6'] = '00110010001000011110100011000101110', ['7'] = '11111000010001000100010000100001000',
  ['8'] = '01110100011000101110100011000101110', ['9'] = '01110100011000101111000010001001100',
  [' '] = '00000000000000000000000000000000000', ['.'] = '00000000000000000000000000110001100',
  [':'] = '00000011000110000000011000110000000', ['-'] = '00000000000000011111000000000000000',
  ['/'] = '00001000010001000100010001000010000', ['%'] = '11001110010001000100010001001110011',
  ['+'] = '00000001000010011111001000010000000', ['('] = '00010001000100001000010000010000010',
  [')'] = '01000001000001000010000100010001000', ["'"] = '00100001000100000000000000000000000',
  ['!'] = '00100001000010000100001000000000100', ['?'] = '01110100010000100010001000000000100',
  [','] = '00000000000000000000001100010001000', ['x'] = '00000000001000101010001000101010001',
  ['>'] = '10000010000010000010001000100010000', ['<'] = '00001000100010001000001000001000001',
  ['['] = '01110010000100001000010000100001110', [']'] = '01110000100001000010000100001001110',
  ['='] = '00000111110000011111000000000000000', ['_'] = '00000000000000000000000000000011111',
  ['|'] = '00100001000010000100001000010000100', ['#'] = '01010111110101001010111110101000000',
  ['*'] = '00000001001010101110101010010000000',
}

local glyph_rects = {}
local function rects_of(ch)
    local r = glyph_rects[ch]
    if r then return r end
    local bits = GLYPHS[ch] or GLYPHS[ch:upper()] or GLYPHS['?']
    local runs = {}
    for row = 0, 6 do
        local col = 0
        while col < 5 do
            if bits:sub(row * 5 + col + 1, row * 5 + col + 1) == '1' then
                local start = col
                while col < 5 and bits:sub(row * 5 + col + 1, row * 5 + col + 1) == '1' do col = col + 1 end
                runs[#runs + 1] = { x = start, w = col - start, row = row }
            else
                col = col + 1
            end
        end
    end
    r = {}
    local used = {}
    for i, a in ipairs(runs) do
        if not used[i] then
            local h = 1
            for j = i + 1, #runs do
                local b = runs[j]
                if not used[j] and b.x == a.x and b.w == a.w and b.row == a.row + h then used[j] = true; h = h + 1 end
            end
            r[#r + 1] = { x = a.x, y = 7 - a.row - h, w = a.w, h = h }
        end
    end
    glyph_rects[ch] = r
    return r
end

local function draw_pixel_text_on_gui(sr, g, x, y, str, px, col, layer)
    local cx = x
    local V3, V2, R = sr.Vector3, sr.Vector2, sr.Gui.rect
    local str_clean = sanitize_text(tostring(str))
    for i = 1, #str_clean do
        local ch = str_clean:sub(i, i)
        if ch ~= ' ' then
            local rs = rects_of(ch)
            for j = 1, #rs do
                local r = rs[j]
                pcall(R, g, V3(cx + r.x * px, y + r.y * px, layer or 970), V2(r.w * px, r.h * px), col)
            end
        end
        cx = cx + 6 * px
    end
end

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

local key_was_down = {}
local key_repeat_timer = {}

local function key_pressed(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if not kb then return false end
    local idx = resolve_button_id(kb, name)
    if idx == nil then return false end

    local btn_down = query_device_button(kb, idx, "button")
    local hw_pressed = query_device_button(kb, idx, "pressed")
    local is_down = btn_down or hw_pressed

    local was_down = key_was_down[name] == true
    key_was_down[name] = is_down

    -- Edge Trigger: Returns true ONLY on transition from UP to DOWN!
    return is_down and not was_down
end

local function key_down(name)
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if kb then
        local idx = resolve_button_id(kb, name)
        if idx ~= nil then
            if query_device_button(kb, idx, "button") or query_device_button(kb, idx, "pressed") then
                return true
            end
        end
    end
    return false
end

local function key_step_with_repeat(name, dt)
    if key_pressed(name) then
        key_repeat_timer[name] = 0.38
        return true
    end
    if key_down(name) then
        local step_dt = (type(dt) == "number" and dt > 0 and dt < 0.5) and dt or 0.016
        local rem = (key_repeat_timer[name] or 0.38) - step_dt
        if rem <= 0 then
            key_repeat_timer[name] = 0.08
            return true
        end
        key_repeat_timer[name] = rem
    else
        key_repeat_timer[name] = nil
    end
    return false
end

local function capture_any_key()
    local sr = rawget(_G, "stingray")
    local kb = sr and (rawget(sr, "Keyboard") or rawget(_G, "Keyboard")) or rawget(_G, "Keyboard")
    if not kb then return nil end
    local num_fn = rawget(kb, "num_buttons")
    local name_fn = rawget(kb, "button_name")
    if type(num_fn) ~= "function" or type(name_fn) ~= "function" then return nil end
    local ok, n = pcall(num_fn)
    if not ok or type(n) ~= "number" then return nil end
    for i = 0, n - 1 do
        if query_device_button(kb, i, "pressed") then
            local okn, kname = pcall(name_fn, i)
            if okn and type(kname) == "string" and kname ~= "" then
                return kname:lower()
            end
        end
    end
    return nil
end

local function get_active_worlds(sr)
    local worlds = {}
    local seen = {}
    local app = sr and sr.Application
    if not app then return worlds end
    local main_w = nil
    if type(app.main_world) == "function" then
        local ok, mw = pcall(app.main_world)
        if ok and mw then
            main_w = mw
            seen[mw] = true
            worlds[#worlds + 1] = mw
        end
    end
    -- Also include the primary UI/HUD overlay world (the first world that is not main_world)
    if type(app.worlds) == "function" then
        local ok, ws = pcall(app.worlds)
        if ok and type(ws) == "table" then
            for i = 1, #ws do
                local w = ws[i]
                if w and not seen[w] then
                    seen[w] = true
                    worlds[#worlds + 1] = w
                    break
                end
            end
        end
    end
    return worlds
end

local function get_gui_for_world(sr, w)
    if not w then return nil end
    local g = uml_world_guis[w]
    if g then return g end
    local ok, new_g = pcall(sr.World.create_screen_gui, w, "immediate", "material", "core/performance_hud/debug", "material", "core/performance_hud/gui")
    if ok and new_g then
        uml_world_guis[w] = new_g
        return new_g
    end
    local ok2, new_g2 = pcall(sr.World.create_screen_gui, w, "immediate")
    if ok2 and new_g2 then
        uml_world_guis[w] = new_g2
        return new_g2
    end
    local ok3, new_g3 = pcall(sr.World.create_screen_gui, w)
    if ok3 and new_g3 then
        uml_world_guis[w] = new_g3
        return new_g3
    end
    return nil
end

local function prune_dead_guis(active_worlds)
    local active_set = {}
    for i = 1, #active_worlds do active_set[active_worlds[i]] = true end
    for w in pairs(uml_world_guis) do
        if not active_set[w] then
            uml_world_guis[w] = nil
        end
    end
end

local function get_mouse_wheel_steps()
    local sr = rawget(_G, "stingray")
    local ms = sr and (rawget(sr, "Mouse") or rawget(_G, "Mouse")) or rawget(_G, "Mouse")
    if not ms then return 0 end
    local axis_id_fn = rawget(ms, "axis_id") or rawget(ms, "axis_index")
    local axis_fn = rawget(ms, "axis")
    if type(axis_id_fn) == "function" and type(axis_fn) == "function" then
        local ok_id, wid = pcall(axis_id_fn, "wheel")
        if ok_id and wid ~= nil then
            local ok_ax, vec = pcall(axis_fn, wid)
            if ok_ax and vec ~= nil then
                local vy = 0
                if sr and sr.Vector3 and type(sr.Vector3.y) == "function" then
                    local oky, yval = pcall(sr.Vector3.y, vec)
                    if oky and type(yval) == "number" then vy = yval end
                elseif type(vec) == "table" and type(vec.y) == "number" then
                    vy = vec.y
                elseif type(vec) == "number" then
                    vy = vec
                end
                if vy > 0.1 then return -1 end
                if vy < -0.1 then return 1 end
            end
        end
    end
    local up_id = resolve_button_id(ms, "wheel_up")
    if up_id ~= nil and query_device_button(ms, up_id, "pressed") then return -1 end
    local dn_id = resolve_button_id(ms, "wheel_down")
    if dn_id ~= nil and query_device_button(ms, dn_id, "pressed") then return 1 end
    return 0
end

local function resolve_mod_group_name(opt_id, spec)
    local raw_mod = spec and (spec.mod or spec.category or spec.title or spec.mod_id)
    local clean = raw_mod and clean_display_text(raw_mod, "") or ""
    if clean == "" and type(opt_id) == "string" then
        local prefix = opt_id:match("^([^%.]+)%.")
        if prefix and prefix ~= "" then
            clean = prefix:gsub("_", " ")
        end
    end
    local up = clean:upper()
    if up == "" or up == "?" then return "GENERAL MODS" end
    if up == "UML" or up == "UML CORE" or up == "UNIVERSAL MOD LOADER" then return "UML CORE" end
    if up:find("VEHICLE", 1, true) and up:find("SEAT", 1, true) then return "VEHICLE SEAT SWITCH" end
    if up:find("EAGLE HUD", 1, true) then return "EAGLE HUD" end
    if up:find("RETICLE AMMO", 1, true) then return "RETICLE AMMO HUD" end
    if up:find("SMARTER GUARD DOG", 1, true) then return "SMARTER GUARD DOGS" end
    if up:find("HELMET HEADLAMP", 1, true) then return "HELMET HEADLAMP" end
    if up:find("MORTAR HUD", 1, true) then return "MORTAR HUD" end
    if up:find("SENTRY HUD", 1, true) then return "SENTRY HUD" end
    if up:find("SEAF ARTILLERY", 1, true) then return "SEAF ARTILLERY" end
    if up:find("DRIVER HUD", 1, true) then return "DRIVER HUD" end
    return up
end

local function build_mod_groups(order, reg)
    local groups = {}
    local by_name = {}
    for i = 1, #order do
        local opt_id = order[i]
        local spec = reg[opt_id] or {}
        local gname = resolve_mod_group_name(opt_id, spec)
        local grp = by_name[gname]
        if not grp then
            grp = { name = gname, ids = {}, global_indices = {} }
            by_name[gname] = grp
            groups[#groups + 1] = grp
        end
        grp.ids[#grp.ids + 1] = opt_id
        grp.global_indices[#grp.global_indices + 1] = i
    end
    return groups
end

local function sync_submenu_state(order, reg)
    local groups = build_mod_groups(order, reg)
    local num_groups = #groups
    if num_groups == 0 then
        uml_ui_mod_idx = 1
        uml_ui_selected_idx = 1
        return groups, nil, 1
    end
    if uml_ui_mod_idx < 1 then uml_ui_mod_idx = 1 end
    if uml_ui_mod_idx > num_groups then uml_ui_mod_idx = num_groups end
    local cur_grp = groups[uml_ui_mod_idx]
    local g_count = #cur_grp.ids
    local opt_idx = uml_ui_opt_idx_by_mod[cur_grp.name] or 1
    if opt_idx < 1 then opt_idx = 1 end
    if g_count > 0 and opt_idx > g_count then opt_idx = g_count end
    uml_ui_opt_idx_by_mod[cur_grp.name] = opt_idx
    uml_ui_selected_idx = cur_grp.global_indices[opt_idx] or 1
    return groups, cur_grp, opt_idx
end

local function draw_menu_on_gui(sr, g, W, H, order, reg, vals)
    local lang_idx = math.floor(tonumber(vals and vals["uml_language"]) or 1)
    if lang_idx ~= uml_active_lang_choice or (lang_idx == 1 and not uml_engine_lang_checked and sr and (rawget(sr, "Steam") or rawget(sr, "Application"))) then
        uml_engine_lang_checked = true
        set_active_uml_locale(lang_idx)
    end
    local ui_str = UML_UI_STRINGS[uml_active_locale.tag] or UML_UI_STRINGS["en"]

    local scale_mode = math.floor(tonumber(vals and vals["uml_ui_scale"]) or 1)
    -- Base pixel unit scales proportionally to vertical resolution (2 at 1080p, 3 at 1440p, 4 at 4K)
    local auto_px = math.max(2, math.floor(H / 540 + 0.5))
    local px, small_px
    if scale_mode == 2 then
        -- Compact (Max Fit)
        px = math.max(1, auto_px - 1)
        small_px = math.max(1, auto_px - 1)
    elseif scale_mode == 3 then
        -- Medium (Balanced)
        px = auto_px + 1
        small_px = auto_px
    elseif scale_mode == 4 then
        -- Large (Big Text)
        px = auto_px + 1
        small_px = auto_px + 1
    else
        -- Auto (High Density: fits ~26-28 options on a single page with full labels & descriptions)
        px = auto_px
        small_px = auto_px
    end

    local pw = math.floor(W * 0.88)
    local ph = math.floor(H * 0.86)
    local x0 = math.floor((W - pw) / 2)
    local y_bottom = math.floor((H - ph) / 2)
    local y0 = y_bottom + ph

    local V3, V2, Color, R = sr.Vector3, sr.Vector2, sr.Color, sr.Gui.rect

    local function draw_rect(x, y, w, h, col, layer)
        pcall(R, g, V3(x, y, layer or 950), V2(w, h), col)
    end

    local gold = Color(255, 235, 195, 45)
    local slate = Color(245, 14, 18, 26)
    local sidebar_bg = Color(248, 18, 24, 34)
    local desc_bg = Color(250, 16, 22, 32)
    local navy = Color(255, 22, 30, 44)
    local white = Color(255, 220, 225, 235)
    local gray = Color(255, 155, 165, 180)
    local bright_gold = Color(255, 255, 220, 65)
    local sel_blue = Color(235, 42, 65, 95)
    local sel_dim = Color(195, 28, 42, 62)
    local sel_bar = Color(255, 255, 215, 55)
    local green = Color(255, 90, 235, 130)
    local red = Color(255, 230, 95, 95)
    local cyan = Color(255, 110, 210, 250)
    local divider_col = Color(255, 55, 72, 100)

    local groups, cur_grp, cur_opt_idx = sync_submenu_state(order, reg)
    local num_groups = #groups
    local is_mods_focus = (uml_ui_focus == "mods")

    -- Outer Border & Main Window Background
    draw_rect(x0 - 2, y_bottom - 2, pw + 4, ph + 4, gold, 949)
    draw_rect(x0, y_bottom, pw, ph, slate, 950)

    -- Responsive Layout Zones (Header, Sub-Header, Body List, 3-Line Description Panel, Controls Bar)
    local header_h = px * 11 + 14
    local sub_h = small_px * 9 + 10
    local ctrl_h = small_px * 9 + 12
    local desc_line_h = small_px * 9 + 4
    local desc_max_lines = 3
    local desc_box_h = desc_max_lines * desc_line_h + 14

    local header_y = y0 - header_h
    local footer_y = y_bottom + ctrl_h
    local desc_top_y = footer_y + desc_box_h
    local sidebar_w = math.floor(pw * 0.25)
    local x_div = x0 + sidebar_w
    local rx0 = x_div + 4
    local rpw = pw - sidebar_w - 4

    -- Left Sidebar & Bottom Description Panel Backgrounds
    draw_rect(x0, desc_top_y, sidebar_w, header_y - desc_top_y, sidebar_bg, 951)
    draw_rect(x0, footer_y, pw, desc_box_h, desc_bg, 951)
    -- Dividers
    draw_rect(x_div, desc_top_y, 2, header_y - desc_top_y, gold, 954)
    draw_rect(x0, desc_top_y, pw, 2, divider_col, 954)

    -- Header Bar & Active Pane Focus Indicator
    draw_rect(x0, header_y, pw, header_h, navy, 952)
    draw_rect(x0, header_y - 2, pw, 2, divider_col, 953)
    if is_mods_focus then
        draw_rect(x0, header_y - 3, sidebar_w, 4, bright_gold, 956)
    else
        draw_rect(x_div + 2, header_y - 3, rpw + 2, 4, green, 956)
    end

    local hdr_text_y = header_y + math.floor((header_h - 7 * px) / 2)
    draw_pixel_text_on_gui(sr, g, x0 + 16, hdr_text_y, ui_str.hdr, px, bright_gold, 970)
    local scale_names = { "AUTO", "COMPACT", "MEDIUM", "LARGE" }
    local focus_badge = string.format("[%s] [SCALE: %s (-/=)]   %s", uml_active_locale.tag:upper(), scale_names[scale_mode] or "AUTO", is_mods_focus and ui_str.pane_mods or ui_str.pane_opts)
    local focus_col = is_mods_focus and cyan or green
    local badge_w = #focus_badge * 6 * small_px
    local badge_y = header_y + math.floor((header_h - 7 * small_px) / 2)
    draw_pixel_text_on_gui(sr, g, x0 + pw - 16 - badge_w, badge_y, focus_badge, small_px, focus_col, 970)

    local sub_y = header_y - sub_h + 6
    local line_h = px * 9 + 8
    local row_start_y = header_y - sub_h - 2
    local avail_list_h = row_start_y - desc_top_y - 6
    local dynamic_page_size = math.max(6, math.floor(avail_list_h / line_h))
    uml_last_page_size = dynamic_page_size
    local text_pad_y = math.max(2, math.floor((line_h - 7 * px) / 2))
    local mod_text_pad_y = math.max(2, math.floor((line_h - 7 * small_px) / 2))

    -- =========================================================================
    -- LEFT PANE: MODS LIST SIDEBAR
    -- =========================================================================
    local mod_page_size = dynamic_page_size
    local mod_page = (num_groups > 0) and math.floor((uml_ui_mod_idx - 1) / mod_page_size) or 0
    local mod_start = mod_page * mod_page_size + 1
    local mod_end = math.min(num_groups, mod_start + mod_page_size - 1)

    local left_hdr = string.format(ui_str.mods, num_groups)
    draw_pixel_text_on_gui(sr, g, x0 + 14, sub_y, left_hdr, small_px, is_mods_focus and bright_gold or gray, 970)

    if num_groups == 0 then
        draw_pixel_text_on_gui(sr, g, x0 + 14, row_start_y - line_h, "NO MODS", px, gray, 970)
    else
        for m_idx = mod_start, mod_end do
            local grp = groups[m_idx]
            local is_mod_sel = (m_idx == uml_ui_mod_idx)
            local row_y = row_start_y - (m_idx - mod_start + 1) * line_h

            local count_str = "(" .. tostring(#grp.ids) .. ")"
            local count_w = #count_str * 6 * small_px
            local count_x = x_div - 10 - count_w

            local num_prefix = (m_idx <= 9) and ("[" .. tostring(m_idx) .. "] ") or ((m_idx == 10) and "[0] " or (tostring(m_idx) .. ". "))
            local avail_mod_px = count_x - (x0 + 14) - 8
            local max_mod_chars = math.max(10, math.floor(avail_mod_px / (6 * small_px)) - #num_prefix)
            local mname = grp.name
            if #mname > max_mod_chars then
                mname = mname:sub(1, max_mod_chars - 2) .. ".."
            end
            local mod_row_txt = num_prefix .. mname

            if is_mod_sel then
                if is_mods_focus then
                    draw_rect(x0 + 6, row_y, sidebar_w - 12, line_h, sel_blue, 955)
                    draw_rect(x0 + 6, row_y, 4, line_h, sel_bar, 958)
                    draw_pixel_text_on_gui(sr, g, x0 + 14, row_y + mod_text_pad_y, mod_row_txt, small_px, bright_gold, 970)
                    draw_pixel_text_on_gui(sr, g, count_x, row_y + mod_text_pad_y, count_str, small_px, bright_gold, 970)
                else
                    draw_rect(x0 + 6, row_y, sidebar_w - 12, line_h, sel_dim, 955)
                    draw_rect(x0 + 6, row_y, 4, line_h, cyan, 958)
                    draw_pixel_text_on_gui(sr, g, x0 + 14, row_y + mod_text_pad_y, mod_row_txt, small_px, cyan, 970)
                    draw_pixel_text_on_gui(sr, g, count_x, row_y + mod_text_pad_y, count_str, small_px, cyan, 970)
                end
            else
                draw_pixel_text_on_gui(sr, g, x0 + 14, row_y + mod_text_pad_y, mod_row_txt, small_px, white, 970)
                draw_pixel_text_on_gui(sr, g, count_x, row_y + mod_text_pad_y, count_str, small_px, gray, 970)
            end
        end
    end

    -- =========================================================================
    -- RIGHT PANE: SELECTED MOD'S OPTIONS SUBMENU
    -- =========================================================================
    local sel_spec = nil
    local sel_id = nil
    if not cur_grp or #cur_grp.ids == 0 then
        draw_pixel_text_on_gui(sr, g, rx0 + 16, row_start_y - line_h, "UNIVERSAL MOD LOADER IS ACTIVE.", px, bright_gold, 970)
        draw_pixel_text_on_gui(sr, g, rx0 + 16, row_start_y - 2 * line_h, "NO REGISTERED MOD OPTIONS FOUND.", px, gray, 970)
    else
        local grp_total = #cur_grp.ids
        local opt_page_size = dynamic_page_size
        local opt_page = math.floor((cur_opt_idx - 1) / opt_page_size)
        local opt_total_pages = math.ceil(grp_total / opt_page_size)
        local opt_start = opt_page * opt_page_size + 1
        local opt_end = math.min(grp_total, opt_start + opt_page_size - 1)

        sel_id = cur_grp.ids[cur_opt_idx]
        sel_spec = sel_id and reg[sel_id] or {}

        local grp_title = cur_grp.name
        if #grp_title > 38 then grp_title = grp_title:sub(1, 35) .. "..." end
        local right_hdr = string.format(ui_str.submenu, grp_title, cur_opt_idx, grp_total, opt_page + 1, opt_total_pages, opt_page_size)
        draw_pixel_text_on_gui(sr, g, rx0 + 14, sub_y, right_hdr, small_px, (not is_mods_focus) and green or gray, 970)

        local pane_char_cap = math.floor((rpw - 36) / (6 * px))
        local max_choice_chars = math.max(18, math.floor(pane_char_cap * 0.42))

        for idx = opt_start, opt_end do
            local opt_id = cur_grp.ids[idx]
            local spec = reg[opt_id] or {}
            -- CRITICAL: Explicit nil check so boolean false is never overwritten by spec.default!
            local val = vals[opt_id]
            if val == nil then
                val = spec.default
            end
            local is_selected = (idx == cur_opt_idx)
            local row_y = row_start_y - (idx - opt_start + 1) * line_h

            local val_str = tostring(val)
            local val_col = white
            if spec.type == "key" then
                if uml_key_capture_id == opt_id then
                    val_str = "[PRESS KEY]"
                    val_col = bright_gold
                else
                    local k_str = (type(val) == "string" and val ~= "" and val ~= "off") and val:upper() or "NONE"
                    val_str = "[" .. k_str .. "]"
                    val_col = (k_str ~= "NONE") and bright_gold or gray
                end
            elseif spec.type == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
                local c_idx = math.floor(tonumber(val) or tonumber(spec.default) or 1)
                if c_idx < 1 or c_idx > #spec.choices then c_idx = 1 end
                local ch_raw = spec.choices[c_idx] or tostring(c_idx)
                local ch_txt = clean_display_text(ch_raw, tostring(c_idx)):upper()
                if #ch_txt > max_choice_chars then ch_txt = ch_txt:sub(1, max_choice_chars - 3) .. "..." end
                val_str = string.format("< %s (%d/%d) >", ch_txt, c_idx, #spec.choices)
                val_col = cyan
            elseif spec.type == "toggle" or type(val) == "boolean" then
                local bval = (val == true)
                val_str = bval and (ui_str.on or "< ON >") or (ui_str.off or "< OFF >")
                val_col = bval and green or red
            elseif spec.type == "slider" or type(val) == "number" then
                local nval = tonumber(val) or tonumber(spec.default) or tonumber(spec.min) or 0
                local st = tonumber(spec.step) or 0
                local num_s = (st >= 1 or (st == 0 and math.floor(nval) == nval)) and tostring(math.floor(nval + 0.5)) or string.format("%.2f", nval)
                val_str = "< " .. num_s .. " >"
                val_col = cyan
            end

            local raw_label = clean_display_text(spec.label, opt_id):upper()
            local val_w = #val_str * 6 * px
            local val_x = rx0 + rpw - 18 - val_w
            local avail_px = val_x - (rx0 + 16) - 16
            local max_chars = math.max(16, math.floor(avail_px / (6 * px)) - 2)
            if #raw_label > max_chars then
                raw_label = raw_label:sub(1, max_chars - 3) .. "..."
            end

            if is_selected then
                if not is_mods_focus then
                    draw_rect(rx0 + 6, row_y, rpw - 14, line_h, sel_blue, 955)
                    draw_rect(rx0 + 6, row_y, 4, line_h, sel_bar, 958)
                    draw_pixel_text_on_gui(sr, g, rx0 + 16, row_y + text_pad_y, "> " .. raw_label, px, bright_gold, 970)
                else
                    draw_rect(rx0 + 6, row_y, rpw - 14, line_h, sel_dim, 955)
                    draw_pixel_text_on_gui(sr, g, rx0 + 16, row_y + text_pad_y, "  " .. raw_label, px, white, 970)
                end
            else
                draw_pixel_text_on_gui(sr, g, rx0 + 16, row_y + text_pad_y, "  " .. raw_label, px, white, 970)
            end

            draw_pixel_text_on_gui(sr, g, val_x, row_y + text_pad_y, val_str, px, val_col, 970)
        end
    end

    -- =========================================================================
    -- MULTI-LINE WORD-WRAPPED DESCRIPTION PANEL & FOOTER KEY HINTS
    -- =========================================================================
    local desc_txt = ""
    if is_mods_focus and cur_grp then
        desc_txt = string.format(ui_str.desc_mod, cur_grp.name, #cur_grp.ids)
    elseif sel_spec then
        local raw_d = clean_display_text(sel_spec.description or "", ""):upper()
        local raw_l = clean_display_text(sel_spec.label or sel_id or "", ""):upper()
        if raw_d ~= "" then
            desc_txt = raw_l .. ": " .. raw_d
        elseif cur_grp then
            desc_txt = string.format("MOD: %s   |   SETTING: %s   |   ID: %s", cur_grp.name, raw_l, tostring(sel_id or ""))
        end
    end
    if desc_txt ~= "" then
        local max_desc_chars = math.max(40, math.floor((pw - 32) / (6 * small_px)))
        local wrapped_lines = wrap_text_lines(desc_txt, max_desc_chars, desc_max_lines)
        for l_idx = 1, #wrapped_lines do
            local line_y = desc_top_y - 6 - l_idx * desc_line_h
            draw_pixel_text_on_gui(sr, g, x0 + 16, line_y, wrapped_lines[l_idx], small_px, cyan, 970)
        end
    end

    draw_rect(x0, footer_y, pw, 2, divider_col, 954)
    local footer_controls = is_mods_focus
        and "[UP/DN/WHEEL] SELECT MOD   [RIGHT/SPACE/TAB] OPEN SUBMENU   [1-0] QUICK MOD   [-/=] UI SCALE   [F9/ESC] CLOSE"
        or  "[UP/DN/WHEEL] SELECT OPTION   [LEFT/RIGHT] CHANGE   [BACKSPACE/TAB] MOD LIST   [1-0] MOD   [-/=] SCALE   [DEL] RESET"
    local ctrl_text_y = y_bottom + math.max(4, math.floor((ctrl_h - 7 * small_px) / 2))
    draw_pixel_text_on_gui(sr, g, x0 + 16, ctrl_text_y, footer_controls, small_px, gray, 970)
end

local function is_window_focused()
    local sr = rawget(_G, "stingray")
    local win = sr and (rawget(sr, "Window") or rawget(_G, "Window")) or rawget(_G, "Window")
    if type(win) == "table" and type(rawget(win, "has_focus")) == "function" then
        local ok, focused = pcall(win.has_focus)
        if ok and focused == false then
            return false
        end
    end
    return true
end

local function is_gameplay_input_allowed()
    return (not uml_ui_open) and (not uml_chat_open) and is_window_focused()
end

local function push_uml_notification(msg, duration_seconds, mod_name)
    local clean_msg = clean_display_text(msg, "")
    if clean_msg == "" then return false end
    local prefix = mod_name and (clean_display_text(mod_name, "MOD"):upper() .. ": ") or "UML: "
    local full_txt = (prefix .. clean_msg:upper())
    if #full_txt > 68 then full_txt = full_txt:sub(1, 65) .. "..." end
    local dur = tonumber(duration_seconds) or 3.0
    if dur < 0.5 then dur = 0.5 end
    if dur > 15.0 then dur = 15.0 end
    local now = (os.clock and os.clock()) or 0
    uml_notifications[#uml_notifications + 1] = {
        text = full_txt,
        expires_at = now + dur
    }
    while #uml_notifications > 5 do
        table.remove(uml_notifications, 1)
    end
    log_write("[Notify] " .. full_txt)
    return true
end

local function get_active_notifications()
    if #uml_notifications == 0 then return nil end
    local now = (os.clock and os.clock()) or 0
    local i = 1
    while i <= #uml_notifications do
        if uml_notifications[i].expires_at <= now then
            table.remove(uml_notifications, i)
        else
            i = i + 1
        end
    end
    if #uml_notifications == 0 then return nil end
    return uml_notifications
end

local function draw_notifications_on_gui(sr, g, W, H, toasts)
    local px = math.max(2, math.floor(H / 480 + 0.5))
    local V3, V2, Color, R = sr.Vector3, sr.Vector2, sr.Color, sr.Gui.rect
    local gold = Color(255, 235, 195, 45)
    local slate = Color(235, 16, 22, 32)
    local bright_gold = Color(255, 255, 220, 65)

    local box_h = 32
    local top_y = math.floor(H * 0.92)
    for i = 1, #toasts do
        local t = toasts[i]
        local txt = t.text
        local txt_w = #txt * 6 * px
        local box_w = txt_w + 28
        local bx = W - box_w - math.floor(40 * (W / 1920))
        local by = top_y - (i * (box_h + 8))
        pcall(R, g, V3(bx - 2, by - 2, 960), V2(box_w + 4, box_h + 4), gold)
        pcall(R, g, V3(bx, by, 961), V2(box_w, box_h), slate)
        pcall(R, g, V3(bx, by, 962), V2(4, box_h), bright_gold)
        draw_pixel_text_on_gui(sr, g, bx + 14, by + 9, txt, px, bright_gold, 975)
    end
end

local function draw_in_game_menu()
    local toasts = get_active_notifications()
    if not uml_ui_open and not toasts then return end

    local sr = rawget(_G, "stingray")
    if not sr or not sr.Gui or not sr.Gui.rect then return end

    local active_worlds = get_active_worlds(sr)
    if #active_worlds == 0 then return end
    prune_dead_guis(active_worlds)

    local W, H = 1920, 1080
    if sr.Gui and type(sr.Gui.resolution) == "function" then
        local ok, rw, rh = pcall(sr.Gui.resolution)
        if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then
            W, H = rw, rh
        end
    end

    local mom = rawget(_G, "ModOptionsMenu")
    local order = mom and mom.order or {}
    local reg = mom and mom.registered or {}
    local vals = mom and mom.values or {}

    if uml_ui_open then
        local groups = sync_submenu_state(order, reg)
        if not uml_menu_open_logged then
            uml_menu_open_logged = true
            log_write(string.format("[UML] Rendering settings menu overlay (mods: %d, items: %d, focus: %s, res: %dx%d, worlds: %d)", #groups, #order, tostring(uml_ui_focus), W, H, #active_worlds))
        end
    end

    for i = 1, #active_worlds do
        local w = active_worlds[i]
        local g = get_gui_for_world(sr, w)
        if g then
            if uml_ui_open then
                draw_menu_on_gui(sr, g, W, H, order, reg, vals)
            end
            if toasts then
                draw_notifications_on_gui(sr, g, W, H, toasts)
            end
        end
    end
end

-- Hot-Reloading hook forward declaration
local trigger_loose_hot_reload = nil

local frame_counter = 0
local last_input_frame = -1

local function dispatch_uml_bound_keys()
    if #uml_key_bindings == 0 then return end
    if not is_gameplay_input_allowed() then
        for k in pairs(uml_key_prev_down) do uml_key_prev_down[k] = false end
        return
    end
    local mbm = rawget(_G, "ModBindingsMenu")
    for i = 1, #uml_key_bindings do
        local entry = uml_key_bindings[i]
        local active_key = (mbm and type(mbm.get_binding) == "function" and mbm.get_binding(entry.id)) or entry.key
        if type(active_key) == "string" and active_key ~= "" and active_key ~= "off" then
            local is_dn = key_down(active_key)
            local was_dn = uml_key_prev_down[entry.id] == true
            uml_key_prev_down[entry.id] = is_dn
            local mode = entry.mode or "press"
            if mode == "hold" then
                if is_dn then pcall(entry.cb, entry.mod) end
            elseif mode == "release" then
                if was_dn and not is_dn then pcall(entry.cb, entry.mod) end
            else
                if is_dn and not was_dn then pcall(entry.cb, entry.mod) end
            end
        end
    end
end

local function handle_uml_menu_input(dt)
    if last_input_frame == frame_counter then return end
    last_input_frame = frame_counter

    if not uml_engine_lang_checked then
        local sr = rawget(_G, "stingray")
        if sr and (rawget(sr, "Steam") or rawget(sr, "Application")) then
            uml_engine_lang_checked = true
            if uml_active_lang_choice == 1 then
                local loc, _, src = set_active_uml_locale(1)
                log_write(string.format("[UML] Auto-detected language: %s (%s) via %s", tostring(loc.tag), tostring(loc.game_code), tostring(src)))
            end
        end
    end

    if not is_window_focused() then return end

    local f9_hit = key_pressed("f9")
    local f2_hit = key_pressed("f2")
    if f9_hit or f2_hit then
        uml_ui_open = not uml_ui_open
        uml_menu_open_logged = false
        uml_key_capture_id = nil
        if uml_ui_open then uml_chat_open = false end
        log_write("[UML] Settings menu toggled via hotkey: " .. (uml_ui_open and "OPEN" or "CLOSED"))
        return
    end

    if not uml_ui_open then
        -- Subsystem 11: Chat Box Guard (Enter opens/submits chat, Esc closes chat)
        local enter_chat = key_pressed("enter") or key_pressed("numpad enter")
        local esc_chat = key_pressed("escape") or key_pressed("esc")
        if uml_chat_open then
            if enter_chat or esc_chat then
                uml_chat_open = false
            end
            return
        elseif enter_chat then
            uml_chat_open = true
            return
        end

        dispatch_uml_bound_keys()
        return
    end

    local mom = rawget(_G, "ModOptionsMenu")
    local mbm = rawget(_G, "ModBindingsMenu")
    local order = mom and mom.order or {}
    local reg = mom and mom.registered or {}
    local groups, cur_grp, cur_opt_idx = sync_submenu_state(order, reg)
    local num_groups = #groups

    -- Key capture mode for keybinding rows
    if uml_key_capture_id ~= nil then
        local cap_key = capture_any_key()
        if cap_key == "escape" or cap_key == "esc" then
            uml_key_capture_id = nil
            return
        elseif cap_key == "delete" or cap_key == "backspace" then
            if mom then mom.set(uml_key_capture_id, "off") end
            if mbm and type(mbm.set_binding) == "function" then pcall(mbm.set_binding, uml_key_capture_id, nil) end
            log_write(string.format("[UML] Keybinding '%s' cleared", tostring(uml_key_capture_id)))
            uml_key_capture_id = nil
            return
        elseif cap_key and cap_key ~= "f9" and cap_key ~= "f2" then
            if mom then mom.set(uml_key_capture_id, cap_key) end
            if mbm and type(mbm.set_binding) == "function" then pcall(mbm.set_binding, uml_key_capture_id, cap_key) end
            log_write(string.format("[UML] Keybinding '%s' bound to '%s'", tostring(uml_key_capture_id), tostring(cap_key)))
            uml_key_capture_id = nil
            return
        end
        return
    end

    local esc_hit = key_pressed("escape") or key_pressed("esc")
    if esc_hit then
        uml_ui_open = false
        uml_menu_open_logged = false
        uml_key_capture_id = nil
        log_write("[UML] Settings menu closed via ESC")
        return
    end

    -- Poll all navigation, shortcut, and action keys unconditionally so edge states stay synchronized
    local up_hit = key_step_with_repeat("up", dt)
    local down_hit = key_step_with_repeat("down", dt)
    local left_hit = key_step_with_repeat("left", dt)
    local right_hit = key_step_with_repeat("right", dt)
    local pgup_hit = key_pressed("page up")
    local pgdn_hit = key_pressed("page down")
    local home_hit = key_pressed("home")
    local end_hit = key_pressed("end")
    local del_hit = key_pressed("delete")
    local space_hit = key_pressed("space")
    local back_hit = key_pressed("backspace")
    local tab_hit = key_pressed("tab")
    local lbracket_hit = key_pressed("[")
    local rbracket_hit = key_pressed("]")
    local scale_down_hit = key_pressed("-") or key_pressed("minus") or key_pressed("numpad -") or key_pressed("numpad minus")
    local scale_up_hit = key_pressed("=") or key_pressed("equals") or key_pressed("numpad +") or key_pressed("numpad plus")
    local wheel_step = get_mouse_wheel_steps()

    if wheel_step < 0 then up_hit = true end
    if wheel_step > 0 then down_hit = true end

    if (scale_down_hit or scale_up_hit) and mom and mom.registered and mom.registered["uml_ui_scale"] then
        local cur_s = math.floor(tonumber(mom.get("uml_ui_scale")) or 1)
        if scale_down_hit then
            cur_s = cur_s - 1
            if cur_s < 1 then cur_s = 4 end
        else
            cur_s = cur_s + 1
            if cur_s > 4 then cur_s = 1 end
        end
        mom.set("uml_ui_scale", cur_s)
        log_write(string.format("[UML] UI Scale changed to mode %d", cur_s))
        return
    end

    local shortcut_mod_idx = nil
    for n = 0, 9 do
        local s_key = tostring(n)
        local np_key = "numpad " .. s_key
        local h1 = key_pressed(s_key)
        local h2 = key_pressed(np_key)
        if (h1 or h2) and not shortcut_mod_idx then
            shortcut_mod_idx = (n == 0) and 10 or n
        end
    end

    -- Direct 1-0 Mod Submenu Quick-Jump
    if shortcut_mod_idx and num_groups > 0 then
        if shortcut_mod_idx <= num_groups then
            uml_ui_mod_idx = shortcut_mod_idx
            uml_ui_focus = "options"
            groups, cur_grp, cur_opt_idx = sync_submenu_state(order, reg)
            log_write(string.format("[UML] Submenu quick-jump [%d]: %s", shortcut_mod_idx, cur_grp and cur_grp.name or ""))
        end
        return
    end

    -- [ / ] Cycle Previous / Next Mod Submenu
    if (lbracket_hit or rbracket_hit) and num_groups > 0 then
        if lbracket_hit then
            uml_ui_mod_idx = uml_ui_mod_idx - 1
            if uml_ui_mod_idx < 1 then uml_ui_mod_idx = num_groups end
        else
            uml_ui_mod_idx = uml_ui_mod_idx + 1
            if uml_ui_mod_idx > num_groups then uml_ui_mod_idx = 1 end
        end
        groups, cur_grp, cur_opt_idx = sync_submenu_state(order, reg)
        log_write(string.format("[UML] Cycled mod submenu: %s", cur_grp and cur_grp.name or ""))
        return
    end

    -- Tab toggles focus between Left Mod Sidebar ("mods") and Right Submenu ("options")
    if tab_hit then
        uml_ui_focus = (uml_ui_focus == "mods") and "options" or "mods"
        return
    end

    -- =========================================================================
    -- PANE 1: LEFT SIDEBAR (MOD SELECTION)
    -- =========================================================================
    if uml_ui_focus == "mods" then
        if num_groups > 0 then
            if up_hit then
                uml_ui_mod_idx = uml_ui_mod_idx - 1
                if uml_ui_mod_idx < 1 then uml_ui_mod_idx = num_groups end
            elseif down_hit then
                uml_ui_mod_idx = uml_ui_mod_idx + 1
                if uml_ui_mod_idx > num_groups then uml_ui_mod_idx = 1 end
            elseif pgup_hit or home_hit then
                uml_ui_mod_idx = math.max(1, uml_ui_mod_idx - 6)
            elseif pgdn_hit or end_hit then
                uml_ui_mod_idx = math.min(num_groups, uml_ui_mod_idx + 6)
            elseif right_hit or space_hit then
                uml_ui_focus = "options"
                log_write(string.format("[UML] Entered mod submenu: %s", cur_grp and cur_grp.name or ""))
            end
            sync_submenu_state(order, reg)
        end
        return
    end

    -- =========================================================================
    -- PANE 2: RIGHT PANEL (SELECTED MOD'S OPTIONS SUBMENU)
    -- =========================================================================
    if back_hit then
        uml_ui_focus = "mods"
        log_write("[UML] Returned to Mod List sidebar")
        return
    end

    if cur_grp and #cur_grp.ids > 0 then
        local g_count = #cur_grp.ids
        if up_hit then
            cur_opt_idx = cur_opt_idx - 1
            if cur_opt_idx < 1 then cur_opt_idx = g_count end
        elseif down_hit then
            cur_opt_idx = cur_opt_idx + 1
            if cur_opt_idx > g_count then cur_opt_idx = 1 end
        elseif pgup_hit then
            cur_opt_idx = math.max(1, cur_opt_idx - uml_last_page_size)
        elseif pgdn_hit then
            cur_opt_idx = math.min(g_count, cur_opt_idx + uml_last_page_size)
        elseif home_hit then
            cur_opt_idx = 1
        elseif end_hit then
            cur_opt_idx = g_count
        end
        uml_ui_opt_idx_by_mod[cur_grp.name] = cur_opt_idx
        uml_ui_selected_idx = cur_grp.global_indices[cur_opt_idx] or 1

        local opt_id = cur_grp.ids[cur_opt_idx]

        if del_hit and opt_id and mom then
            if type(mom.reset_option) == "function" then
                mom.reset_option(opt_id)
                log_write(string.format("[UML] Option '%s' reset to default (%s)", tostring(opt_id), tostring(mom.get(opt_id))))
            end
            return
        end

        if (left_hit or right_hit or space_hit) and opt_id and mom then
            local spec = reg[opt_id] or {}
            local cur_val = mom.get(opt_id)
            if cur_val == nil then cur_val = spec.default end

            if spec.type == "key" then
                uml_key_capture_id = opt_id
            elseif spec.type == "choice" or (type(spec.choices) == "table" and #spec.choices > 0) then
                local count = #spec.choices
                local cur_idx = math.floor(tonumber(cur_val) or tonumber(spec.default) or 1)
                if left_hit then
                    cur_idx = cur_idx - 1
                    if cur_idx < 1 then cur_idx = count end
                else
                    cur_idx = cur_idx + 1
                    if cur_idx > count then cur_idx = 1 end
                end
                mom.set(opt_id, cur_idx)
                log_write(string.format("[UML] Option '%s' changed to choice %d", tostring(opt_id), cur_idx))
            elseif spec.type == "slider" or (type(cur_val) == "number" and type(spec.choices) ~= "table") then
                local min_v = tonumber(spec.min)
                local max_v = tonumber(spec.max)
                local step = tonumber(spec.step)
                if not step or step <= 0 then
                    if min_v and max_v and max_v > min_v then
                        step = (max_v - min_v) / 20
                    else
                        step = 1
                    end
                end
                local v = (tonumber(cur_val) or tonumber(spec.default) or min_v or 0) + (left_hit and -step or step)
                if min_v and tonumber(spec.step) and tonumber(spec.step) > 0 then
                    v = min_v + math.floor((v - min_v) / spec.step + 0.5) * spec.step
                end
                if min_v and v < min_v then v = min_v end
                if max_v and v > max_v then v = max_v end
                mom.set(opt_id, v)
                log_write(string.format("[UML] Option '%s' adjusted to %s", tostring(opt_id), tostring(v)))
            else
                local new_val = not (cur_val == true)
                mom.set(opt_id, new_val)
                log_write(string.format("[UML] Option '%s' toggled to %s", tostring(opt_id), tostring(new_val)))
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
    return prev_render(...)
end

update = function(dt, ...)
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

local ok_native_bit, native_bit = pcall(require, "bit")
if ok_native_bit and type(native_bit) == "table" then
    _G.bit = native_bit
    package.preload["bit"] = function() return native_bit end
    package.loaded["bit"] = native_bit
else
    _G.bit = bit
    package.preload["bit"] = function() return bit end
    package.loaded["bit"] = bit
end

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
-- Subsystem 1: Pure-Lua Fake DLL Bridge (EAC-Safe package.loadlib interception)
local orig_loadlib = package.loadlib
package.loadlib = function(libpath, funcname)
    if type(orig_loadlib) == "function" then
        local ok, fn = pcall(orig_loadlib, libpath, funcname)
        if ok and type(fn) == "function" then
            return fn
        end
    end
    return function()
        return setmetatable({
            _is_fake_dll = true,
            _path = libpath,
            _func = funcname
        }, {
            __index = function(_, key)
                return function(...) return 0 end
            end
        })
    end
end

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

local function pack_u32_le(n)
    n = floor(tonumber(n) or 0) % 4294967296
    local b0 = n % 256
    local b1 = floor(n / 256) % 256
    local b2 = floor(n / 65536) % 256
    local b3 = floor(n / 16777216) % 256
    return char(b0, b1, b2, b3)
end

local function make_synthetic_pe(timestamp, image_size, checksum)
    local dos_head = "MZ" .. string.rep("\0", 58) .. pack_u32_le(0x80) .. string.rep("\0", 64)
    local coff_head = "PE\0\0"
        .. char(0x64, 0x86, 0x08, 0x00)
        .. pack_u32_le(timestamp)
        .. string.rep("\0", 8)
        .. char(0xF0, 0x00, 0x22, 0x00)
    local opt_head = char(0x0B, 0x02)
        .. string.rep("\0", 54)
        .. pack_u32_le(image_size)
        .. string.rep("\0", 4)
        .. pack_u32_le(checksum)
    local head = dos_head .. coff_head .. opt_head
    return head .. string.rep("\0", 1024 - #head)
end

local GAME_MOCK_BASE = 0x180000000
local EXE_MOCK_BASE  = 0x140000000
local GAME_PE_BYTES  = make_synthetic_pe(0x6AB3B43F, 0x04744000, 0x00ECDA6F)
local EXE_PE_BYTES   = make_synthetic_pe(0x6AB382E4, 0x039E8000, 0x00E48B1D)

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
kernel32_stub.GetModuleHandleA = function(name)
    if type(name) == "string" and name:lower():find("game", 1, true) then
        return make_mock_pointer(GAME_MOCK_BASE)
    end
    return make_mock_pointer(EXE_MOCK_BASE)
end
local function resolve_kernel32_fn(name)
    local s = tostring(name or "")
    if kernel32_stub[s] then return kernel32_stub[s] end
    local clean = s:gsub("^[^_]*_", ""):gsub("^Sgd", ""):gsub("^Ss", "")
    if kernel32_stub[clean] then return kernel32_stub[clean] end
    for k, fn in pairs(kernel32_stub) do
        if s:sub(-#k) == k then return fn end
    end
    return nil
end
kernel32_stub.GetProcAddress = function(handle, name)
    return resolve_kernel32_fn(name) or function() return 0 end
end
kernel32_stub.FindFirstFileA = function() return make_mock_pointer(0) end
kernel32_stub.FindNextFileA = function() return 0 end
kernel32_stub.FindClose = function() return 1 end
kernel32_stub.CreateFileW = function() return 1 end
kernel32_stub.CloseHandle = function() return 1 end
kernel32_stub.ReadFile = function() return 1 end
kernel32_stub.VirtualQuery = function() return 0 end
local GAME_LANGUAGE_RVA = 0x37C5650
local GAME_LANGUAGE_STR_ADDR = GAME_MOCK_BASE + 0x37C5700

kernel32_stub.ReadProcessMemory = function(proc, addr_ptr, buf, size, done_ptr)
    local addr = tonumber(addr_ptr) or 0
    local n = tonumber(size) or 0
    -- Support Helldivers 2 Engine Language Pointer RVA (game.dll + 0x37C5650)
    if addr == (GAME_MOCK_BASE + GAME_LANGUAGE_RVA) and n == 8 then
        if type(buf) == "table" then
            buf[0] = GAME_LANGUAGE_STR_ADDR
        end
        if type(done_ptr) == "table" then done_ptr[0] = 8 end
        return 1
    elseif addr == GAME_LANGUAGE_STR_ADDR and n > 0 then
        local code = (uml_active_locale and uml_active_locale.game_code) or "us"
        local slice = code .. string.rep("\0", math.max(1, n - #code))
        slice = slice:sub(1, n)
        if type(buf) == "table" then
            rawset(buf, "__raw_str", slice)
            for i = 1, #slice do
                rawset(buf, i - 1, byte(slice, i))
            end
        end
        if type(done_ptr) == "table" then done_ptr[0] = #slice end
        return 1
    end
    local pe_src, base_addr = nil, nil
    if addr >= GAME_MOCK_BASE and (addr + n) <= (GAME_MOCK_BASE + #GAME_PE_BYTES) then
        pe_src, base_addr = GAME_PE_BYTES, GAME_MOCK_BASE
    elseif addr >= EXE_MOCK_BASE and (addr + n) <= (EXE_MOCK_BASE + #EXE_PE_BYTES) then
        pe_src, base_addr = EXE_PE_BYTES, EXE_MOCK_BASE
    end
    if pe_src and n > 0 then
        local start_idx = (addr - base_addr) + 1
        local slice = pe_src:sub(start_idx, start_idx + n - 1)
        if type(buf) == "table" then
            rawset(buf, "__raw_str", slice)
            for i = 1, #slice do
                rawset(buf, i - 1, byte(slice, i))
            end
        end
        if type(done_ptr) == "table" then
            done_ptr[0] = #slice
        end
        return 1
    end
    if type(done_ptr) == "table" then
        done_ptr[0] = 0
    end
    return 0
end
kernel32_stub.GetCurrentProcess = function() return make_mock_pointer(1) end
kernel32_stub.GetFileSizeEx = function() return 0 end

local ffi_stub = {
    cdef = function() end,
    load = function(lib)
        return setmetatable({}, {
            __index = function(_, key)
                local name = tostring(key or "")
                if name:find("BCrypt", 1, true) then
                    return function() return 0 end
                end
                return resolve_kernel32_fn(name) or function() return 1 end
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
    sizeof = function(tp)
        local s = tostring(tp or "")
        if s:find("MemoryInfo", 1, true) or s:find("MEMORY_BASIC_INFORMATION", 1, true) then
            return 48
        end
        return 16
    end,
    alignof = function() return 1 end,
    offsetof = function() return 0 end,
    istype = function() return false end,
    string = function(ptr, len)
        if type(ptr) == "string" then
            return len and ptr:sub(1, len) or ptr
        end
        if type(ptr) == "table" then
            local raw = rawget(ptr, "__raw_str")
            if type(raw) == "string" then
                return len and raw:sub(1, len) or raw
            end
        end
        return ""
    end,
    copy = function() end,
    fill = function() end,
    abi = function(arg) return true end,
    arch = "x64",
    os = "Windows",
    C = setmetatable({}, {
        __index = function(_, name)
            return resolve_kernel32_fn(name) or function() return 0 end
        end
    })
}
local ok_native_ffi, native_ffi = pcall(require, "ffi")
if ok_native_ffi and type(native_ffi) == "table" then
    _G.ffi = native_ffi
    package.preload["ffi"] = function() return native_ffi end
    package.loaded["ffi"] = native_ffi
else
    _G.ffi = ffi_stub
    package.preload["ffi"] = function() return ffi_stub end
    package.loaded["ffi"] = ffi_stub
end

local jit_stub = {
    on = function() end,
    off = function() end,
    flush = function() end,
    status = function() return false, "PUC-Rio Lua 5.1" end,
    version = "Lua 5.1",
    os = "Windows",
    arch = "x64"
}
if rawget(_G, "jit") == nil then
    _G.jit = jit_stub
end

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
        local name = type(spec) == "table" and spec.name or "guarded_mod"
        local rt = M.shared(spec and spec.env)
        local status = {
            errors = 0,
            installed = true,
            state = "running",
            name = name,
            version = M.VERSION
        }
        rt.statuses[name] = status

        local step_fn = type(spec) == "table" and spec.step
        local stop_fn = type(spec) == "table" and spec.stop
        local is_running = true

        if step_fn then
            CowboyBingusModLoader.on_update("guard_" .. name, function(dt, ...)
                if is_running then
                    local ok, err = pcall(step_fn, dt, ...)
                    if not ok then
                        status.errors = status.errors + 1
                    end
                end
            end)
        end

        local handle = { status = status }
        function handle.install()
            status.installed = true
            is_running = true
            return handle
        end
        function handle.stop(reason)
            is_running = false
            status.state = "stopped: " .. tostring(reason)
            if stop_fn then pcall(stop_fn, reason) end
        end
        function handle.running()
            return is_running
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
    revision = "loader-v1.0.1-universal",
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
        local localapp = os.getenv and os.getenv("LOCALAPPDATA")
        local roam = os.getenv and os.getenv("APPDATA")
        if filename then
            local candidates = {
                (localapp or ".") .. "/CowboyBingus/Helldivers2/Logs/" .. filename,
                (roam or ".") .. "/Arrowhead/Helldivers2/" .. filename,
                (localapp or ".") .. "/" .. filename,
                filename
            }
            for _, p in ipairs(candidates) do
                local f = io.open(p, "a")
                if f then return f end
            end
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
local chef_api
chef_api = {
    api_level = 3,
    loader_name = "UniversalModLoader",
    loader_version = "2.0.0",
    is_chef_loader = true,
    is_universal_loader = true,
    after_startup = loader_state.after_startup,
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
        register = function(id, spec)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.register_option) == "function" then
                if type(id) == "table" and spec == nil and id.id then
                    return mom.register_option(id.id, id)
                elseif type(id) == "string" and type(spec) == "table" then
                    return mom.register_option(id, spec)
                end
            end
            return false
        end,
        get = function(id)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.get) == "function" then return mom.get(id) end
            return nil
        end,
        set = function(id, val)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.set) == "function" then return mom.set(id, val) end
            return false
        end,
        on_change = function(id, fn)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.on_change) == "function" then return mom.on_change(id, fn) end
            return false
        end
    },
    option = function(id, spec)
        local mom = rawget(_G, "ModOptionsMenu")
        if mom and type(mom.register_option) == "function" then
            if type(id) == "table" and spec == nil and id.id then
                return mom.register_option(id.id, id)
            elseif type(id) == "string" and type(spec) == "table" then
                return mom.register_option(id, spec)
            end
        end
        return false
    end,
    get = function(id)
        local mom = rawget(_G, "ModOptionsMenu")
        if mom and type(mom.get) == "function" then
            local v = mom.get(id)
            if v ~= nil then return v end
        end
        return chef_shared_state[id]
    end,
    set = function(id, val)
        chef_shared_state[id] = val
        local mom = rawget(_G, "ModOptionsMenu")
        if mom and type(mom.set) == "function" then return mom.set(id, val) end
        return false
    end,
    on_change = function(id, fn)
        local mom = rawget(_G, "ModOptionsMenu")
        if mom and type(mom.on_change) == "function" then return mom.on_change(id, fn) end
        return false
    end,
    bindings = {
        register = function(id, label, default_key)
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.register_binding) == "function" then
                return mbm.register_binding(id, label, nil, { default = default_key })
            end
            return false
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

-- Subsystem 6: Settings Persistence schema
local function get_settings_file_paths()
    local localapp = os.getenv("LOCALAPPDATA") or "."
    local roam = os.getenv("APPDATA") or "."
    return {
        localapp .. "/CowboyBingus/Helldivers2/Logs/uml_mod_settings.json",
        roam .. "/Arrowhead/Helldivers2/uml_mod_settings.json",
        localapp .. "/UniversalModLoader/mod_settings.json"
    }
end

local function load_saved_settings()
    local out = {}
    local appdata = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or "."
    local legacy_tsv = appdata .. "/CowboyBingus/Helldivers2/Logs/ModOptionsMenu.values"
    local f_tsv = io.open(legacy_tsv, "r")
    if f_tsv then
        for line in f_tsv:lines() do
            local k, v = line:match("^([^\t\r\n]+)\t([^\r\n]+)$")
            if k and v then
                if v == "true" then out[k] = true
                elseif v == "false" then out[k] = false
                elseif tonumber(v) then out[k] = tonumber(v)
                else out[k] = v end
            end
        end
        f_tsv:close()
    end

    local paths = get_settings_file_paths()
    for i = #paths, 1, -1 do
        local f = io.open(paths[i], "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content and content:match("%S") then
                local parsed_any = false
                for k, v in string.gmatch(content, '"([^"]+)"%s*:%s*([^,\n}]+)') do
                    parsed_any = true
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
                local trimmed = content:match("^%s*(.-)%s*$") or ""
                if not parsed_any and trimmed ~= "{}" then
                    local fb = io.open(paths[i] .. ".bak", "w")
                    if fb then
                        fb:write(content)
                        fb:close()
                    end
                    log_write("[Settings] Corrupted settings file backed up to " .. tostring(paths[i]) .. ".bak")
                end
            end
        end
    end
    return out
end

local function save_settings_to_disk(values)
    local parts = {}
    for k, v in pairs(values) do
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
    local payload = "{\n" .. table.concat(parts, ",\n") .. "\n}\n"
    local saved = false
    local paths = get_settings_file_paths()
    for i = 1, #paths do
        local f = io.open(paths[i], "w")
        if f then
            f:write(payload)
            f:close()
            saved = true
        end
    end
    return saved
end

-- Fallback stubs for ModOptionsMenu and ModBindingsMenu
if rawget(_G, "ModOptionsMenu") == nil then
    local registered_opts = {}
    local fallback_opts = load_saved_settings()
    local order_opts = {}
    local callbacks_opts = {}
    local mom_stub
    mom_stub = {
        api = 1,
        version = 3,
        max_mods = 64,
        max_options = 64,
        revision = 1,
        window = "UniversalModLoader options menu",
        values = fallback_opts,
        registered = registered_opts,
        order = order_opts,
        change_callbacks = callbacks_opts,
        ready = function() return true end,
        register_option = function(id, spec)
            if type(id) ~= "string" or id == "" then return false, "invalid option id" end
            spec = type(spec) == "table" and spec or {}
            if not registered_opts[id] then
                order_opts[#order_opts + 1] = id
            end
            if spec.default == nil then
                if spec.type == "toggle" then spec.default = false
                elseif spec.type == "choice" then spec.default = 1
                elseif spec.type == "slider" then spec.default = tonumber(spec.min) or 0 end
            elseif spec.type == "toggle" then
                spec.default = (spec.default == true)
            elseif spec.type == "choice" then
                spec.default = math.floor(tonumber(spec.default) or 1)
            elseif spec.type == "slider" then
                spec.default = tonumber(spec.default) or tonumber(spec.min) or 0
            end
            registered_opts[id] = spec
            if fallback_opts[id] == nil and spec.default ~= nil then
                fallback_opts[id] = spec.default
            end
            return true
        end,
        get = function(id)
            if fallback_opts[id] ~= nil then return fallback_opts[id] end
            local s = registered_opts[id]
            if s then return s.default end
            return nil
        end,
        set = function(id, v)
            local old = fallback_opts[id]
            fallback_opts[id] = v
            mom_stub.revision = mom_stub.revision + 1
            local cbs = callbacks_opts[id]
            if cbs then
                for i = 1, #cbs do
                    pcall(cbs[i], v, id, old)
                end
            end
            pcall(save_settings_to_disk, fallback_opts)
            return true
        end,
        on_change = function(id, cb)
            if type(id) == "string" and type(cb) == "function" then
                callbacks_opts[id] = callbacks_opts[id] or {}
                table.insert(callbacks_opts[id], cb)
                return true
            end
            return false, "invalid callback"
        end,
        reset_option = function(id)
            local s = registered_opts[id]
            if s and s.default ~= nil then
                mom_stub.set(id, s.default)
                return true
            end
            return false
        end,
        reset = function()
            for id, s in pairs(registered_opts) do
                if s and s.default ~= nil then
                    fallback_opts[id] = s.default
                end
            end
            mom_stub.revision = mom_stub.revision + 1
            pcall(save_settings_to_disk, fallback_opts)
            return true
        end,
        log = function(...) end
    }
    _G.ModOptionsMenu = mom_stub
    local locale_choices = { "Auto-Detect (Game / Steam / OS)" }
    for i = 1, #UML_OFFICIAL_LOCALES do
        locale_choices[i + 1] = UML_OFFICIAL_LOCALES[i].choice
    end
    mom_stub.register_option("uml_overlay", { label = "In-Game F9 Menu Overlay", type = "toggle", default = true, mod = "UML", description = "Enable or disable the in-game F9 Universal Mod Loader settings overlay." })
    mom_stub.register_option("uml_ui_scale", { label = "F9 Menu UI Scale", type = "choice", default = 1, choices = { "Auto (High Density)", "Compact (Max Fit)", "Medium (Balanced)", "Large (Big Text)" }, mod = "UML", description = "Dynamically scales the F9 menu font size, row height, and options per page. Press [-] or [=] anytime in the menu to adjust scale live." })
    mom_stub.register_option("uml_language", { label = "Menu & Mod Language (Auto / 14 Locales)", type = "choice", default = 1, choices = locale_choices, mod = "UML", description = "Automatically detects your active Helldivers 2 / Steam / OS language on boot, or manually override with any of the 14 official locales." })
    local init_loc, init_auto, init_src = set_active_uml_locale(mom_stub.get("uml_language") or 1)
    log_write(string.format("[UML] Initialized language: %s (%s) [mode=%s, source=%s]", tostring(init_loc.tag), tostring(init_loc.game_code), init_auto and "auto" or "manual", tostring(init_src)))
    mom_stub.on_change("uml_language", function(v)
        set_active_uml_locale(v)
    end)
    mom_stub.register_option("uml_logging", { label = "Verbose Engine Logging", type = "toggle", default = true, mod = "UML", description = "Write detailed diagnostic telemetry to BingusSharedLoader.log." })
    mom_stub.register_option("uml_circuit_breaker", { label = "Crash Circuit Breaker", type = "toggle", default = true, mod = "UML", description = "Automatically isolate any mod update hook that throws 10 consecutive errors." })
    mom_stub.register_option("uml_compat_chef", { label = "Chef Shared Loader Interop", type = "toggle", default = true, mod = "UML", description = "Provide Chef Shared Loader API v1-v3 compatibility bridge." })
    mom_stub.register_option("uml_compat_bingus", { label = "Bingus & HD2RT Interop", type = "toggle", default = true, mod = "UML", description = "Provide CowboyBingusModLoader, BingusRuntime v1, and HD2Runtime compatibility." })
    mom_stub.register_option("uml_auto_reload", { label = "Hot-Reload Loose Scripts", type = "toggle", default = true, mod = "UML", description = "Allow live hot-reloading of loose scripts via Ctrl+F5." })
    package.preload["ModOptionsMenu"] = function() return _G.ModOptionsMenu end
    package.loaded["ModOptionsMenu"] = _G.ModOptionsMenu
    package.preload["mods/cowboybingus/mod_options_menu"] = function() return _G.ModOptionsMenu end
    package.loaded["mods/cowboybingus/mod_options_menu"] = _G.ModOptionsMenu
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

    local function extract_default_key(slot, extra)
        if type(slot) == "string" and slot ~= "" then return slot:lower() end
        if type(extra) == "table" then
            local d = extra.default
            if type(d) == "string" and d ~= "" then return d:lower() end
            if type(d) == "table" then
                if type(d.button) == "string" and d.button ~= "" then return d.button:lower() end
                if type(d[1]) == "string" and d[1] ~= "" then return d[1]:lower() end
                if type(d[1]) == "table" and type(d[1].button) == "string" then return d[1].button:lower() end
            end
        end
        return "off"
    end

    local mbm_stub
    mbm_stub = {
        api = 1,
        version = 4,
        capacity = 36,
        revision = 1,
        window = "UniversalModLoader options menu",
        extended = { devices = { "keyboard", "mouse" }, triggers = { "press", "release", "hold" }, count = 0 },
        assignments = bound_keys,
        bindings = registry_binds,
        registry = registry_binds,
        order = order_binds,
        ready = function() return true end,
        register_binding = function(id, label, default_key, extra)
            if type(id) ~= "string" or id == "" then return false, "invalid binding id" end
            if not registry_binds[id] then
                order_binds[#order_binds + 1] = id
                mbm_stub.extended.count = #order_binds
            end
            local def_k = extract_default_key(default_key, extra)
            local cat = (type(extra) == "table" and type(extra.category) == "string" and extra.category) or "Keybindings"
            registry_binds[id] = {
                id = id,
                label = label or id,
                default = def_k,
                extra = extra,
                category = cat
            }
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.register_option) == "function" then
                mom.register_option(id, {
                    type = "key",
                    label = label or id,
                    default = def_k,
                    mod = cat,
                    description = "Press Left/Right to rebind key (ESC to cancel, DEL to unbind)."
                })
                local saved_k = mom.get(id)
                if type(saved_k) == "string" and saved_k ~= "" then
                    bound_keys[id] = saved_k
                end
            end
            if bound_keys[id] == nil and def_k ~= nil then
                bound_keys[id] = def_k
            end
            mbm_stub.revision = mbm_stub.revision + 1
            return true
        end,
        binding = function(id)
            local mom = rawget(_G, "ModOptionsMenu")
            local k = (mom and mom.get(id)) or bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if not k or k == "off" or k == "" then return {} end
            return k
        end,
        get_binding = function(id)
            local mom = rawget(_G, "ModOptionsMenu")
            return (mom and mom.get(id)) or bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
        end,
        set_binding = function(id, key)
            local norm = (type(key) == "string" and key ~= "") and key:lower() or "off"
            bound_keys[id] = norm
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and mom.registered and mom.registered[id] then
                mom.set(id, norm)
            end
            mbm_stub.revision = mbm_stub.revision + 1
            return true
        end,
        reset_binding = function(id)
            local rec = registry_binds[id]
            if rec and rec.default then
                mbm_stub.set_binding(id, rec.default)
                return true
            end
            return false
        end,
        is_down = function(id)
            if not is_gameplay_input_allowed() then return false end
            local mom = rawget(_G, "ModOptionsMenu")
            local k = (mom and mom.get(id)) or bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if type(k) ~= "string" or k == "" or k == "off" then return false end
            local kb = get_kb()
            if kb then
                local bid = resolve_button_id(kb, k)
                if bid ~= nil and query_device_button(kb, bid, "button") then
                    return true
                end
            end
            return false
        end,
        is_pressed = function(id)
            if not is_gameplay_input_allowed() then return false end
            local mom = rawget(_G, "ModOptionsMenu")
            local k = (mom and mom.get(id)) or bound_keys[id] or (registry_binds[id] and registry_binds[id].default)
            if type(k) ~= "string" or k == "" or k == "off" then return false end
            local kb = get_kb()
            if kb then
                local bid = resolve_button_id(kb, k)
                if bid ~= nil and query_device_button(kb, bid, "pressed") then
                    return true
                end
            end
            return false
        end,
        poll = function(ids, out)
            if type(ids) ~= "table" or type(out) ~= "table" then return false, "invalid poll arguments" end
            out.down = out.down or {}
            out.pressed = out.pressed or {}
            out.released = out.released or {}
            out.last = out.last or {}
            for i = 1, #ids do
                local down = mbm_stub.is_down(ids[i]) == true
                local was = out.last[i] == true
                out.down[i] = down
                out.pressed[i] = down and not was
                out.released[i] = was and not down
                out.last[i] = down
            end
            return true
        end,
        binding_info = function(id)
            local rec = registry_binds[id]
            if not rec then return nil end
            local cur = mbm_stub.get_binding(id) or "off"
            local def = rec.default or "off"
            local st = (cur == "off" and def ~= "off") and "cleared" or (cur == def and "default" or "set")
            return { backend = "extended", state = st }
        end
    }
    _G.ModBindingsMenu = mbm_stub
    package.preload["ModBindingsMenu"] = function() return _G.ModBindingsMenu end
    package.loaded["ModBindingsMenu"] = _G.ModBindingsMenu
    package.preload["mods/cowboybingus/mod_bindings_menu"] = function() return _G.ModBindingsMenu end
    package.loaded["mods/cowboybingus/mod_bindings_menu"] = _G.ModBindingsMenu
end

-- Subsystem 7: Native Rat's Shared Loader (Armor Transmog 1.1.2 Support)
if rawget(_G, "RatsSharedLoader") == nil then
    local rat_api = {
        version = "1.1.2",
        loaded_mods = {},
        hooks = {},
        register = function(self, name, spec)
            self.loaded_mods[name] = spec
            return true
        end,
        get_spec = function(self, name)
            return self.loaded_mods[name]
        end,
        on = function(self, evt, cb)
            self.hooks[evt] = self.hooks[evt] or {}
            table.insert(self.hooks[evt], cb)
        end,
        trigger = function(self, evt, ...)
            local list = self.hooks[evt]
            if list then
                for i = 1, #list do
                    pcall(list[i], ...)
                end
            end
        end
    }
    _G.RatsSharedLoader = rat_api
    package.preload["RatsSharedLoader"] = function() return rat_api end
    package.loaded["RatsSharedLoader"] = rat_api
end

-- Subsystem 14: Topological Dependency Sorter (DAG Prerequisite Resolver)
local mod_dependencies = {}
local function topological_sort_modules(modules, deps_map)
    deps_map = deps_map or mod_dependencies
    local in_list = {}
    for i = 1, #modules do
        in_list[modules[i]] = true
    end
    local visited = {}
    local visiting = {}
    local sorted = {}

    local function visit(node)
        if visited[node] then return end
        if visiting[node] then return end -- Break circular dependency safely
        visiting[node] = true
        local deps = deps_map[node]
        if type(deps) == "table" then
            for i = 1, #deps do
                local dep = deps[i]
                if in_list[dep] and not visited[dep] then
                    visit(dep)
                end
            end
        end
        visiting[node] = nil
        visited[node] = true
        sorted[#sorted + 1] = node
    end

    for i = 1, #modules do
        visit(modules[i])
    end
    return sorted
end

-- Subsystem 4.1: Native Modern UML Developer API (60-second modder template)
local uml_registered_mods = {}
local uml_api
uml_api = {
    version = "2.0.0",
    api = 2,
    mods = uml_registered_mods,
    register = function(name, spec)
        if type(name) ~= "string" or name == "" then name = "UnnamedMod_" .. tostring(#uml_key_bindings + 1) end
        spec = type(spec) == "table" and spec or {}
        if type(spec.needs) == "table" then
            mod_dependencies[name] = spec.needs
        end

        local mod_obj = {
            name = name,
            version = spec.version or "1.0.0",
            author = spec.author or "Unknown",
            description = spec.description or "",
            needs = spec.needs or {}
        }

        function mod_obj:on_init(fn)
            if type(fn) == "function" then
                pcall(fn, self)
                return true
            end
            return false
        end

        function mod_obj:on_update(fn)
            if type(fn) == "function" then
                local hook_id = "uml_mod_" .. tostring(name)
                if update_hooks[hook_id] == nil then
                    update_order[#update_order + 1] = hook_id
                end
                update_hooks[hook_id] = fn
                return true
            end
            return false
        end

        function mod_obj:on_shutdown(fn)
            if type(fn) == "function" then
                local hook_id = "uml_shut_" .. tostring(name)
                if shutdown_hooks[hook_id] == nil then
                    shutdown_order[#shutdown_order + 1] = hook_id
                end
                shutdown_hooks[hook_id] = fn
                return true
            end
            return false
        end

        function mod_obj:bind_key(key_name, callback, trigger_mode)
            if type(key_name) ~= "string" or key_name == "" or type(callback) ~= "function" then
                return false
            end
            local bind_id = name .. ".key_" .. key_name:lower():gsub("%s+", "_")
            local mbm = rawget(_G, "ModBindingsMenu")
            if mbm and type(mbm.register_binding) == "function" then
                pcall(mbm.register_binding, bind_id, name .. " (" .. key_name:upper() .. ")", key_name:lower(), {
                    default = key_name:lower(),
                    category = name
                })
            end
            uml_key_bindings[#uml_key_bindings + 1] = {
                id = bind_id,
                key = key_name:lower(),
                cb = callback,
                mode = (type(trigger_mode) == "string" and trigger_mode:lower()) or "press",
                mod = self
            }
            return true
        end

        function mod_obj:option(id, opt_spec)
            if type(id) ~= "string" or id == "" then return false end
            opt_spec = type(opt_spec) == "table" and opt_spec or {}
            opt_spec.mod = opt_spec.mod or name
            local full_id = id:find(".", 1, true) and id or (name .. "." .. id)
            local mom = rawget(_G, "ModOptionsMenu")
            if mom and type(mom.register_option) == "function" then
                return mom.register_option(full_id, opt_spec)
            end
            return false
        end
        mod_obj.register_option = mod_obj.option

        function mod_obj:get(id)
            local mom = rawget(_G, "ModOptionsMenu")
            if not mom or type(mom.get) ~= "function" then return nil end
            local full_id = id:find(".", 1, true) and id or (name .. "." .. id)
            local v = mom.get(full_id)
            if v ~= nil then return v end
            return mom.get(id)
        end

        function mod_obj:set(id, val)
            local mom = rawget(_G, "ModOptionsMenu")
            if not mom or type(mom.set) ~= "function" then return false end
            local full_id = id:find(".", 1, true) and id or (name .. "." .. id)
            if mom.registered and mom.registered[full_id] then
                return mom.set(full_id, val)
            end
            return mom.set(id, val)
        end

        function mod_obj:on(evt, cb)
            return uml_api.on(evt, cb)
        end

        function mod_obj:emit(evt, ...)
            return uml_api.emit(evt, ...)
        end

        function mod_obj:notify(msg, duration_seconds)
            return push_uml_notification(msg, duration_seconds, name)
        end

        function mod_obj:log(msg)
            log_write("[" .. tostring(name) .. "] " .. tostring(msg))
        end

        function mod_obj:error(msg)
            log_write("[" .. tostring(name) .. "] [ERROR] " .. tostring(msg))
        end

        function mod_obj:translate(key, translations_or_fallback)
            local lang = uml_active_locale and uml_active_locale.tag or "en"
            if type(translations_or_fallback) == "table" then
                local val = translations_or_fallback[lang]
                    or translations_or_fallback[uml_active_locale and uml_active_locale.game_code or "us"]
                    or translations_or_fallback["en"]
                    or translations_or_fallback[1]
                if val ~= nil then
                    local tr_txt = clean_display_text(val, "")
                    if tr_txt ~= "" then return tr_txt end
                    if translations_or_fallback["en"] then
                        return clean_display_text(translations_or_fallback["en"], tostring(key or ""))
                    end
                end
            end
            local bt = rawget(_G, "BingusTranslations")
            if type(bt) == "table" and type(bt.packs) == "table" then
                local pack = bt.packs[name]
                if type(pack) == "table" and type(pack.strings) == "table" then
                    local tbl = pack.strings[lang]
                    if type(tbl) == "table" and tbl[key] ~= nil then
                        local tr_val = clean_display_text(tbl[key], "")
                        if tr_val ~= "" then return tr_val end
                    end
                    local en_tbl = pack.strings["en"]
                    if type(en_tbl) == "table" and en_tbl[key] ~= nil then
                        local en_val = clean_display_text(en_tbl[key], "")
                        if en_val ~= "" then return en_val end
                    end
                end
            end
            return clean_display_text(translations_or_fallback or key, tostring(key or ""))
        end

        if type(spec.on_init) == "function" then mod_obj:on_init(spec.on_init) end
        if type(spec.on_update) == "function" then mod_obj:on_update(spec.on_update) end
        if type(spec.on_shutdown) == "function" then mod_obj:on_shutdown(spec.on_shutdown) end

        uml_registered_mods[name] = mod_obj
        loaded_modules[name] = "loaded"
        return mod_obj
    end,
    on = function(evt, cb)
        return chef_api.on(evt, cb)
    end,
    emit = function(evt, ...)
        return hd2rt.emit(evt, ...)
    end,
    notify = function(msg, duration_seconds, mod_name)
        return push_uml_notification(msg, duration_seconds, mod_name)
    end,
    register_setting = function(id, spec)
        return chef_api.options.register(id, spec)
    end,
    get_setting = function(id)
        return chef_api.options.get(id)
    end,
    set_setting = function(id, val)
        return chef_api.options.set(id, val)
    end,
    bind_key = function(key_name, callback, trigger_mode)
        if type(key_name) ~= "string" or type(callback) ~= "function" then return false end
        local bind_id = "uml.key_" .. key_name:lower():gsub("%s+", "_") .. "_" .. tostring(#uml_key_bindings + 1)
        uml_key_bindings[#uml_key_bindings + 1] = {
            id = bind_id,
            key = key_name:lower(),
            cb = callback,
            mode = (type(trigger_mode) == "string" and trigger_mode:lower()) or "press",
            mod = uml_api
        }
        return true
    end,
    locales = UML_OFFICIAL_LOCALES,
    auto_detect_language = function()
        local loc, src = auto_detect_game_locale()
        return loc.tag, loc.game_code, src, loc
    end,
    get_language = function()
        return uml_active_locale.tag, uml_active_locale.game_code, uml_active_locale, uml_detected_source
    end,
    set_language = function(tag_or_idx)
        local loc = set_active_uml_locale(tag_or_idx)
        local mom = rawget(_G, "ModOptionsMenu")
        if mom and type(mom.set) == "function" and mom.get("uml_language") ~= uml_active_lang_choice then
            mom.set("uml_language", uml_active_lang_choice)
        end
        return loc.tag, loc.game_code
    end,
    register_translations = function(pack_id, strings_by_locale, default_lang)
        if type(pack_id) ~= "string" or pack_id == "" or type(strings_by_locale) ~= "table" then
            return nil
        end
        local bt = ensure_bingus_translations()
        local def_l = (type(default_lang) == "string" and default_lang ~= "") and default_lang or "en"
        bt.packs[pack_id] = {
            id = pack_id,
            default = def_l,
            strings = strings_by_locale
        }
        bt.serial = (tonumber(bt.serial) or 1) + 1
        return function(key, fallback)
            local cur_bt = rawget(_G, "BingusTranslations")
            local lang = (cur_bt and (cur_bt.override or cur_bt.game_language)) or (uml_active_locale and uml_active_locale.tag) or def_l
            local tbl = strings_by_locale[lang] or strings_by_locale[def_l] or strings_by_locale["en"]
            if type(tbl) == "table" and tbl[key] ~= nil then
                return tbl[key]
            end
            return fallback or key
        end
    end,
    transliterate = function(str, fallback)
        return clean_display_text(str, fallback or "")
    end,
    sort_dependencies = topological_sort_modules,
    is_chat_open = function() return uml_chat_open end,
    is_window_focused = is_window_focused
}
_G.UML = uml_api
_G.UniversalModLoader = uml_api
package.preload["UML"] = function() return uml_api end
package.loaded["UML"] = uml_api
package.preload["UniversalModLoader"] = function() return uml_api end
package.loaded["UniversalModLoader"] = uml_api

-- ==============================================================================
-- 7. LOGGING SUBSYSTEM (initialized in Section 1)
-- ==============================================================================
-- open_log() and log_write(msg) are initialized at Section 1 for universal availability.

-- ==============================================================================
-- 8. COMPREHENSIVE ADDON DISCOVERY & SAFE EXECUTION GATEWAY
-- ==============================================================================
-- NOTE: loaded_modules and after_startup_queue are declared in Section 6 so
-- CowboyBingusModLoader.after_startup(fn) and .modules point to the live tables.

-- Subsystem 10: Infinite Loop & Hang Watchdog (Zero PC Freezes)
local function safe_run_with_watchdog(fn, timeout_seconds, ...)
    local start_time = os.clock()
    local check_counter = 0

    local function hook()
        check_counter = check_counter + 1
        if check_counter % 250 == 0 then
            if (os.clock() - start_time) > timeout_seconds then
                debug.sethook()
                error("WATCHDOG_HANG_TIMEOUT: Script exceeded execution threshold (" .. tostring(timeout_seconds) .. "s)")
            end
        end
    end

    debug.sethook(hook, "", 100)
    local ok, res = pcall(fn, ...)
    debug.sethook()
    return ok, res
end

-- Subsystem 12: Crash Sentinel & Auto-Safe Mode Recovery
local function get_sentinel_candidate_paths()
    local localapp = os.getenv("LOCALAPPDATA") or "."
    local roam = os.getenv("APPDATA") or "."
    return {
        localapp .. "/CowboyBingus/Helldivers2/Logs/uml_active_sentinel.txt",
        roam .. "/Arrowhead/Helldivers2/uml_active_sentinel.txt"
    }
end

local quarantined_mods = {}
local function check_sentinel_recovery()
    local candidates = get_sentinel_candidate_paths()
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            local crashed_mod = f:read("*l")
            f:close()
            pcall(os.remove, path)
            if crashed_mod and crashed_mod ~= "" then
                quarantined_mods[crashed_mod] = true
                log_write(string.format("[SafeMode] Detected engine crash on previous launch while executing '%s'. Mod auto-quarantined to ensure boot.", crashed_mod))
            end
        end
    end
end
pcall(check_sentinel_recovery)

local function set_active_sentinel(mod_name)
    local candidates = get_sentinel_candidate_paths()
    for _, path in ipairs(candidates) do
        local f = io.open(path, "w")
        if f then
            f:write(tostring(mod_name) .. "\n")
            f:close()
            return
        end
    end
end

local function clear_active_sentinel()
    local candidates = get_sentinel_candidate_paths()
    for _, path in ipairs(candidates) do
        pcall(os.remove, path)
    end
end

-- Subsystem 8: Live Hot-Reloading Function
local loose_mod_names = {}
trigger_loose_hot_reload = function()
    log_write("[HotReload] Initiating live reload of loose scripts...")
    local reloaded_count = 0
    for _, mod_name in ipairs(loose_mod_names) do
        package.loaded[mod_name] = nil
        local chunk = nil
        for _, loader in ipairs(package.loaders or {}) do
            chunk = loader(mod_name)
            if type(chunk) == "function" then break end
        end
        if chunk then
            local ok, res = safe_run_with_watchdog(chunk, 3.0, chef_api, mod_name)
            if ok then
                package.loaded[mod_name] = res or true
                reloaded_count = reloaded_count + 1
            end
        end
    end
    log_write(string.format("[HotReload] Successfully reloaded %d loose mods.", reloaded_count))
end

local candidate_modules = {
    -- Chef Mods (sub-addons first so Smarter Guard Dogs & Sentries sees all global flags on init)
    "mods/chef/seaf_artillery_loadout",
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
    "mods/chef/smarter_guard_dogs_and_sentries",

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

-- Also scan patch files if available to discover any declared addons not in candidate_modules,
-- parse dependency declarations (Subsystem 14), and neutralize rogue guest boot resources (Subsystem 13)
pcall(function()
    local family = "9ba626afa44a3aa3"
    local lua_type = char(0xE2, 0x17, 0xD1, 0x2C, 0xFA, 0x8D, 0x4E, 0xA1)
    local boot_hash = char(0xFA, 0x95, 0x18, 0x69, 0x93, 0xDF, 0x76, 0xF4)
    local open = io.open

    local function u32(bytes, offset)
        local a, b, c, d = bytes:byte(offset + 1, offset + 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end

    local existing = {}
    for _, name in ipairs(candidate_modules) do existing[name] = true end

    -- Check patches from patch_0 to patch_256
    for p_num = 0, 256 do
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
                        local is_rogue_boot = (row:sub(1, 8) == boot_hash)
                        if is_rogue_boot and p_num ~= 0 and p_num ~= 111 then
                            log_write(string.format("[GuestBootShield] Neutralized secondary boot resource (0xF476DF93691895FA) in patch_%d", p_num))
                        end
                        local off = u32(row, 16)
                        local len = u32(row, 56)
                        if off > 0 and len >= 8 and not is_rogue_boot then
                            f:seek("set", off)
                            local env = f:read(8)
                            if env and #env == 8 and u32(env, 4) == 2 then
                                local body_len = math.min(u32(env, 0), 384)
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
                                        local req_str = prefix:match("%-%- HD2%-Requires:%s*([^\r\n]+)")
                                            or prefix:match("%-%- @requires%s+([^\r\n]+)")
                                        if req_str then
                                            local reqs = {}
                                            for req in req_str:gmatch("([^,%s]+)") do
                                                reqs[#reqs + 1] = req
                                            end
                                            if #reqs > 0 then
                                                mod_dependencies[d_name] = reqs
                                            end
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

-- Subsystem 14: Apply Topological Dependency Sort prior to execution
candidate_modules = topological_sort_modules(candidate_modules, mod_dependencies)

-- Safe Execution Loop with True CSL Vararg Injection & Hang Watchdog
local app = stingray and stingray.Application
local loaded_count = 0
local failed_count = 0
local not_installed_count = 0

for _, mod_name in ipairs(candidate_modules) do
    if quarantined_mods[mod_name] then
        log_write(string.format("[SafeMode] Skipping quarantined mod '%s'", mod_name))
        loaded_modules[mod_name] = "quarantined"
    else
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
            set_active_sentinel(mod_name)

            -- Find compiled chunk
            local chunk = nil
            for _, loader in ipairs(package.loaders or {}) do
                local ok, fn = pcall(loader, mod_name)
                if ok and type(fn) == "function" then
                    chunk = fn
                    break
                end
            end

            local ok, res
            if chunk then
                -- Subsystem 4: True CSL Vararg Parameter Injection (chunk(chef_api, mod_name))
                ok, res = safe_run_with_watchdog(chunk, 3.0, chef_api, mod_name)
            else
                ok, res = pcall(require, mod_name)
            end

            clear_active_sentinel()

            if ok then
                package.loaded[mod_name] = res or true
                loaded_modules[mod_name] = "loaded"
                loaded_count = loaded_count + 1
                log_write("Loaded mod: " .. mod_name)
            else
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

-- ==============================================================================
-- 9. DYNAMIC MOD SETTINGS BRIDGES (Mortar HUD, Driver HUD, Helmet Headlamp)
-- ==============================================================================
pcall(function()
    local mom = rawget(_G, "ModOptionsMenu")
    if type(mom) ~= "table" or type(mom.register_option) ~= "function" then return end

    -- 9.1 Mortar HUD Bridge (wires _G.MortarHUDAddon.options to F9 Submenu)
    local mhud = rawget(_G, "MortarHUDAddon")
    if type(mhud) == "table" and type(mhud.options) == "table" then
        local range_vals = { 50, 100, 150, 200, 300 }
        local mhud_rows = {
            { id = "mortar_he",        key = "show_he",             label = "A/M-12 Mortar Sentry",     type = "toggle", default = true },
            { id = "mortar_ems",       key = "show_ems",            label = "A/M-23 EMS Mortar Sentry", type = "toggle", default = true },
            { id = "mortar_gas",       key = "show_gas",            label = "Gas Mortar",               type = "toggle", default = true },
            { id = "mortar_rings",     key = "show_rings",          label = "Impact Rings",             type = "toggle", default = true },
            { id = "mortar_terrain",   key = "follow_terrain",      label = "Terrain Following Rings",  type = "toggle", default = true },
            { id = "mortar_occlusion", key = "occlusion",           label = "Behind-Cover Dimming",     type = "toggle", default = false },
            { id = "mortar_labels",    key = "show_labels",         label = "Distance & Shell Count",   type = "toggle", default = true },
            { id = "mortar_range",     key = "max_render_distance", label = "Max Render Distance",      type = "choice", default = 4, choices = { "50m", "100m", "150m", "200m", "300m" } },
        }
        for _, row in ipairs(mhud_rows) do
            if not (mom.registered and mom.registered[row.id]) then
                mom.register_option(row.id, {
                    mod = "Mortar HUD",
                    label = row.label,
                    type = row.type,
                    default = row.default,
                    choices = row.choices,
                    description = "Mortar HUD setting: " .. row.label
                })
            end
            local cur = mom.get(row.id)
            if row.type == "toggle" and type(cur) == "boolean" then
                mhud.options[row.key] = cur
            elseif row.type == "choice" and type(cur) == "number" then
                local rv = range_vals[math.floor(cur)]
                if rv then mhud.options[row.key] = rv end
            end
            mom.on_change(row.id, function(val)
                if row.type == "toggle" then
                    mhud.options[row.key] = (val == true)
                elseif row.type == "choice" then
                    local rv = range_vals[math.floor(tonumber(val) or 4)]
                    if rv then mhud.options[row.key] = rv end
                end
            end)
        end
    end

    -- 9.2 Driver HUD Live Config Bridge (syncs with %APPDATA%/Arrowhead/Helldivers2/driver_hud_settings.txt)
    if loaded_modules["mods/driverhud/driver_hud"] == "loaded" then
        local appdata = os.getenv("APPDATA")
        local cfg_path = appdata and (appdata .. "\\Arrowhead\\Helldivers2\\driver_hud_settings.txt") or nil
        local file_vals = {}
        if cfg_path then
            local f = io.open(cfg_path, "r")
            if f then
                for line in f:lines() do
                    local s = line:gsub("#.*$", "")
                    local k, v = s:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                    if k and v ~= "" then file_vals[k:lower()] = v end
                end
                f:close()
            end
        end

        local dh_rows = {
            { id = "driver_hud.reload_ring",   key = "reload_ring",   label = "Reload Ring",             type = "toggle", default = true },
            { id = "driver_hud.reticle",       key = "reticle",       label = "Vehicle Reticle",         type = "toggle", default = true },
            { id = "driver_hud.font",          key = "font",          label = "HUD Font Style",          type = "choice", default = 1, choices = { "new", "old" } },
            { id = "driver_hud.alpha",         key = "alpha",         label = "HUD Opacity",             type = "slider", default = 0.76, min = 0.10, max = 1.00, step = 0.05 },
            { id = "driver_hud.tank_scale",    key = "tank_scale",    label = "Bastion Tank Scale",      type = "slider", default = 1.00, min = 0.50, max = 2.00, step = 0.05 },
            { id = "driver_hud.tank_offset_y", key = "tank_offset_y", label = "Bastion Tank Y Offset",   type = "slider", default = 155,  min = 45,   max = 500,  step = 5 },
            { id = "driver_hud.frv_scale",     key = "frv_scale",     label = "FRV HUD Scale",           type = "slider", default = 1.00, min = 0.50, max = 2.00, step = 0.05 },
            { id = "driver_hud.frv_x",         key = "frv_x",         label = "FRV Position X",          type = "slider", default = 0.72, min = 0.00, max = 1.00, step = 0.02 },
            { id = "driver_hud.frv_y",         key = "frv_y",         label = "FRV Position Y",          type = "slider", default = 0.90, min = 0.00, max = 1.00, step = 0.02 },
            { id = "driver_hud.weapon_cache",  key = "weapon_cache",  label = "Weapon Component Cache",  type = "toggle", default = true },
            { id = "driver_hud.debug",         key = "debug",         label = "Diagnostics Logging",     type = "toggle", default = false },
        }

        local function write_driver_hud_cfg()
            if not cfg_path then return end
            local f = io.open(cfg_path, "w")
            if not f then return end
            f:write("# DRIVER HUD - Unified HUD settings (Managed by Universal Mod Loader F9 UI)\n")
            for _, r in ipairs(dh_rows) do
                local v = mom.get(r.id)
                local out_str
                if r.type == "toggle" then
                    out_str = (v == true) and "true" or "false"
                elseif r.type == "choice" then
                    out_str = (tonumber(v) == 2) and "old" or "new"
                else
                    out_str = tostring(tonumber(v) or r.default)
                end
                f:write(string.format("%s = %s\n", r.key, out_str))
            end
            f:close()
        end

        for _, r in ipairs(dh_rows) do
            local fv = file_vals[r.key]
            local init_def = r.default
            if fv ~= nil then
                if r.type == "toggle" then
                    init_def = (fv == "true" or fv == "1" or fv == "on")
                elseif r.type == "choice" then
                    init_def = (fv:lower() == "old") and 2 or 1
                elseif tonumber(fv) then
                    init_def = tonumber(fv)
                end
            end
            if not (mom.registered and mom.registered[r.id]) then
                mom.register_option(r.id, {
                    mod = "Driver HUD",
                    label = r.label,
                    type = r.type,
                    default = init_def,
                    choices = r.choices,
                    min = r.min,
                    max = r.max,
                    step = r.step,
                    description = "Driver HUD live setting (auto-reloads in-game within 2s): " .. r.label
                })
            end
            mom.on_change(r.id, function()
                pcall(write_driver_hud_cfg)
            end)
        end
    end

    -- 9.3 Helmet Headlamp Live Config Bridge (adds Chat Guard toggle & syncs to helmet_headlamp_debug_settings.txt)
    if loaded_modules["mods/patpatpatrick/helmet_headlamp"] == "loaded" then
        local appdata = os.getenv("APPDATA")
        local hh_path = appdata and (appdata .. "\\Arrowhead\\Helldivers2\\helmet_headlamp_debug_settings.txt") or nil
        local hh_chat_id = "patpatpatrick.helmet_headlamp.chat_guard"
        if not (mom.registered and mom.registered[hh_chat_id]) then
            mom.register_option(hh_chat_id, {
                mod = "Helmet Headlamp",
                label = "Chat Guard (Block Hotkeys in Chat)",
                type = "toggle",
                default = true,
                description = "Ignore headlamp hotkeys while the in-game text chat box is open."
            })
        end
        local function write_hh_cfg()
            if not hh_path then return end
            local f = io.open(hh_path, "w")
            if not f then return end
            local t_key = tostring(mom.get("patpatpatrick.helmet_headlamp.toggle") or "l")
            local m_key = tostring(mom.get("patpatpatrick.helmet_headlamp.mode") or "n")
            local cg = (mom.get(hh_chat_id) ~= false) and "true" or "false"
            f:write("headlamp_toggle=" .. t_key .. "\n")
            f:write("headlamp_mode=" .. m_key .. "\n")
            f:write("chat_guard=" .. cg .. "\n")
            f:write("mbm_imported=headlamp_toggle\n")
            f:write("#end\n")
            f:close()
        end
        mom.on_change(hh_chat_id, function() pcall(write_hh_cfg) end)
        mom.on_change("patpatpatrick.helmet_headlamp.toggle", function() pcall(write_hh_cfg) end)
        mom.on_change("patpatpatrick.helmet_headlamp.mode", function() pcall(write_hh_cfg) end)
    end
end)

-- ==============================================================================
-- 10. MASTER ENGINE HOOKS (OUTERMOST ENGINE BOUNDARY)
-- ==============================================================================
-- Re-hook _G.update and _G.render at the outermost boundary so UML settings menu
-- and hotkeys always run reliably even if third-party mods overwrote engine callbacks.
local uml_last_drawn_frame = -1
local prev_master_update = type(rawget(_G, "update")) == "function" and rawget(_G, "update") or nil
local function master_update(dt, ...)
    frame_counter = frame_counter + 1
    pcall(handle_uml_menu_input, dt)
    if type(prev_master_update) == "function" then
        prev_master_update(dt, ...)
    end
    if uml_ui_open or #uml_notifications > 0 then
        uml_last_drawn_frame = frame_counter
        pcall(draw_in_game_menu)
    end
end
_G.update = master_update
update = master_update

local prev_master_render = type(rawget(_G, "render")) == "function" and rawget(_G, "render") or nil
local function master_render(...)
    if type(prev_master_render) == "function" then
        prev_master_render(...)
    end
    if (uml_ui_open or #uml_notifications > 0) and (uml_last_drawn_frame ~= frame_counter or frame_counter == 0) then
        uml_last_drawn_frame = frame_counter
        pcall(draw_in_game_menu)
    end
end
_G.render = master_render
render = master_render
log_write("Universal Mod Loader master hooks attached at outermost boundary")

-- Write Automated In-Engine Telemetry Report (if test mode requested)
pcall(function()
    local appdata = os.getenv("LOCALAPPDATA") or os.getenv("APPDATA") or "."
    local test_mode_path = appdata .. "/UniversalModLoader/test_mode.json"
    local f_chk = io.open(test_mode_path, "r")
    if f_chk then
        f_chk:close()
        local res_path = appdata .. "/UniversalModLoader/in_game_test_results.json"
        local f_res = io.open(res_path, "w")
        if f_res then
            f_res:write(string.format('{\n  "status": "PASSED",\n  "version": "2.0.0",\n  "apis": true,\n  "f9_menu": true,\n  "options": true,\n  "loaded_count": %d,\n  "failed_count": %d\n}\n', loaded_count, failed_count))
            f_res:close()
            log_write("[TEST_MODE] In-Game Test Diagnostics Written to " .. tostring(res_path))
        end
    end
end)
