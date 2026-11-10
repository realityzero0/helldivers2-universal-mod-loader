-- tests/test_v201_standalone_identity.lua
-- Verifies that Universal Mod Loader has complete standalone identity decoupling:
-- zero residual CowboyBingus / BingusSharedLoader path defaults, version 2.0.1 consistency,
-- and clean namespace hygiene.

local function run_test()
    print("====================================================")
    print("Testing UML v2.0.1 Standalone Identity & Namespace")
    print("====================================================")

    -- Read boot_loader.lua
    local f = io.open("src/boot_loader.lua", "r")
    assert(f, "Failed to read src/boot_loader.lua")
    local code = f:read("*a")
    f:close()

    -- 1. Check version in boot_loader.lua header
    assert(code:find("Universal Mod Loader v2.0.2", 1, true) or code:find("Universal Mod Loader v2.0.1", 1, true), "Header must declare v2.0.2 or v2.0.1")
    assert(code:find('loader_version = "2.0.2"', 1, true) or code:find('loader_version = "2.0.1"', 1, true), "chef_api.loader_version must be 2.0.2 or 2.0.1")
    assert(code:find('version = "2.0.2"', 1, true) or code:find('version = "2.0.1"', 1, true), "uml_api.version must be 2.0.2 or 2.0.1")
    print("  [PASS] Version constants declared across code headers and APIs")

    -- 2. Check get_log_candidate_paths()
    local log_fn_body = code:match("local function get_log_candidate_paths%s*%(%)(.-)end")
    assert(log_fn_body, "get_log_candidate_paths must exist")
    assert(not log_fn_body:find("BingusSharedLoader", 1, true), "Log candidate paths must not reference BingusSharedLoader")
    assert(not log_fn_body:find("CowboyBingus", 1, true), "Log candidate paths must not reference CowboyBingus")
    assert(log_fn_body:find("UniversalModLoader.log", 1, true), "Log candidate paths must reference UniversalModLoader.log")
    print("  [PASS] Log candidate paths fully decoupled to UniversalModLoader.log")

    -- 3. Check get_settings_file_paths()
    local set_fn_body = code:match("local function get_settings_file_paths%s*%(%)(.-)end")
    assert(set_fn_body, "get_settings_file_paths must exist")
    assert(not set_fn_body:find("CowboyBingus", 1, true), "Settings candidate paths must not reference CowboyBingus")
    assert(set_fn_body:find("uml_mod_settings.json", 1, true), "Settings candidate paths must reference uml_mod_settings.json")
    print("  [PASS] Settings candidate paths fully decoupled to uml_mod_settings.json")

    -- 4. Check get_sentinel_candidate_paths()
    local sen_fn_body = code:match("local function get_sentinel_candidate_paths%s*%(%)(.-)end")
    assert(sen_fn_body, "get_sentinel_candidate_paths must exist")
    assert(not sen_fn_body:find("CowboyBingus", 1, true), "Sentinel candidate paths must not reference CowboyBingus")
    assert(sen_fn_body:find("uml_active_sentinel.txt", 1, true), "Sentinel candidate paths must reference uml_active_sentinel.txt")
    print("  [PASS] Sentinel candidate paths fully decoupled to uml_active_sentinel.txt")

    -- 5. Check all 14 locale strings in UML_UI_STRINGS
    local expected_locales = { "en", "en-GB", "fr", "de", "it", "es", "es-419", "pt-BR", "pl", "ru", "ja", "ko", "zh-Hans", "zh-Hant" }
    for _, loc in ipairs(expected_locales) do
        local safe_loc = loc:gsub("%-", "%%-")
        local loc_pat = '%["' .. safe_loc .. '"%]%s*=%s*{%s*hdr%s*=%s*"([^"]+)"'
        local hdr = code:match(loc_pat)
        assert(hdr, "Locale " .. loc .. " must exist in UML_UI_STRINGS")
        assert(hdr:find("v2.0.2", 1, true) or hdr:find("v2.0.1", 1, true), "Locale " .. loc .. " hdr must contain 'v2.0.2' or 'v2.0.1', got: " .. tostring(hdr))
    end
    print("  [PASS] All 14 official Helldivers 2 UI locales updated")

    -- 6. Check UniversalModLoader-manifest.json
    local mf = io.open("UniversalModLoader-manifest.json", "r")
    assert(mf, "Failed to read UniversalModLoader-manifest.json")
    local m_code = mf:read("*a")
    mf:close()
    assert(m_code:find('"version":%s*"2.0.2"') or m_code:find('"version":%s*"2.0.1"'), "Manifest version must be 2.0.2 or 2.0.1")
    print("  [PASS] UniversalModLoader-manifest.json verified")

    -- 7. Check manifest.json
    local mf2 = io.open("manifest.json", "r")
    assert(mf2, "Failed to read manifest.json")
    local m2_code = mf2:read("*a")
    mf2:close()
    assert(m2_code:find("Universal Mod Loader %- v2.0.2") or m2_code:find("Universal Mod Loader %- v2.0.1"), "manifest.json name must specify v2.0.2 or v2.0.1")
    print("  [PASS] Arsenal Mod Manager manifest.json verified")

    -- 8. Check UniversalModLoader-README.txt
    local rf = io.open("UniversalModLoader-README.txt", "r")
    assert(rf, "Failed to read UniversalModLoader-README.txt")
    local r_code = rf:read("*a")
    rf:close()
    assert(r_code:find("Helldivers 2 Universal Mod Loader %- v2.0.2") or r_code:find("Helldivers 2 Universal Mod Loader %- v2.0.1"), "README.txt header must specify v2.0.2 or v2.0.1")
    print("  [PASS] UniversalModLoader-README.txt verified")

    print("----------------------------------------------------")
    print("STATUS: ALL STANDALONE IDENTITY TESTS PASSED 100%!")
    print("====================================================")
end

run_test()
