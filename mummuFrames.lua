-- ============================================================================
-- MUMMUFRAMES ADDON ENTRYPOINT
-- ============================================================================
-- Boot flow:
--   1. ADDON_LOADED -> initialize module tables and defaults.
--   2. PLAYER_LOGIN -> enable modules after Blizzard UI is fully ready.
-- Modules register themselves into ModuleManager during file load.

local addonName, ns = ...

ns = ns or {}

local addon = _G.mummuFrames or {}
_G.mummuFrames = addon

addon.name = addonName
addon.ns = ns
addon.initialized = false
addon.enabled = false

addon._moduleManager = ns.ModuleManager:New(addon)

-- Register module in module manager.
function addon:RegisterModule(name, moduleTable)
    return self._moduleManager:Register(name, moduleTable)
end

-- Return module from module manager.
function addon:GetModule(name)
    return self._moduleManager:Get(name)
end

-- Initialize addon modules once.
function addon:Init()
    if self.initialized then
        return
    end

    self._moduleManager:InitializeAll(self)
    self.initialized = true
end

-- Enable initialized addon modules.
function addon:Enable()
    if self.enabled then
        return
    end

    self._moduleManager:EnableAll()
    self.enabled = true
end

-- Disable enabled addon modules.
function addon:Disable()
    if not self.enabled then
        return
    end

    self._moduleManager:DisableAll()
    self.enabled = false
end

-- Open addon configuration panel.
function addon:OpenConfig()
    local config = self:GetModule("configuration")
    if config and type(config.OpenConfig) == "function" then
        config:OpenConfig()
    end
end

SLASH_MUMMUFRAMES1 = "/mmf"
-- Handle slash command callback.
SlashCmdList.MUMMUFRAMES = function()
    addon:OpenConfig()
end

-- Create frame for loader.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
-- Handle OnEvent script callback.
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:Init()
        return
    end

    if event == "PLAYER_LOGIN" and addon.initialized then
        addon:Enable()
    end
end)
