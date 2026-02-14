local addonName, ns = ...

ns = ns or {}

-- Keep one shared addon table on the global namespace.
local addon = _G.mummuFrames or {}
_G.mummuFrames = addon

-- Track lifecycle state for one-time init and enable.
addon.name = addonName
addon.ns = ns
addon.initialized = false
addon.enabled = false

-- Route module lifecycle through the module manager.
addon._moduleManager = ns.ModuleManager:New(addon)

-- Register a module with the module manager.
function addon:RegisterModule(name, moduleTable)
    return self._moduleManager:Register(name, moduleTable)
end

-- Return a previously registered module by name.
function addon:GetModule(name)
    return self._moduleManager:Get(name)
end

-- Initialize modules once.
function addon:Init()
    if self.initialized then
        return
    end

    self._moduleManager:InitializeAll(self)
    self.initialized = true
end

-- Enable all initialized modules.
function addon:Enable()
    if self.enabled then
        return
    end

    self._moduleManager:EnableAll()
    self.enabled = true
end

-- Disable modules in reverse registration order.
function addon:Disable()
    if not self.enabled then
        return
    end

    self._moduleManager:DisableAll()
    self.enabled = false
end

-- Open settings if the configuration module is available.
function addon:OpenConfig()
    local config = self:GetModule("configuration")
    if config and type(config.OpenConfig) == "function" then
        config:OpenConfig()
    end
end

-- Slash command entry point.
SLASH_MUMMUFRAMES1 = "/mmf"
-- Open the addon settings when the slash command is used.
SlashCmdList.MUMMUFRAMES = function()
    addon:OpenConfig()
end

-- Initialize on ADDON_LOADED, then enable on PLAYER_LOGIN.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
-- Route loader events to init/enable flow.
loader:SetScript("OnEvent", function(_, event, arg1)
    -- Initialize only when this addon is loaded.
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:Init()
        return
    end

    -- Enable after login when the addon is fully initialized.
    if event == "PLAYER_LOGIN" and addon.initialized then
        addon:Enable()
    end
end)
