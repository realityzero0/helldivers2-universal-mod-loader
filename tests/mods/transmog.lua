-- @mod mods/transmog
local rat = rawget(_G, "RatsSharedLoader") or require("RatsSharedLoader")
_G.TEST_TRANSMOG_LOADED = true
if rat and rat.on then
    rat:on("init", function()
        _G.TEST_TRANSMOG_INIT_CALLED = true
    end)
    rat:on("update", function(dt)
        _G.TEST_TRANSMOG_UPDATE_CALLED = true
    end)
end
return { name = "Transmog", loaded = true }
