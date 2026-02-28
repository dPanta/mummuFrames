-- Module lifecycle coordinator.
-- Keeps registration order stable so init/enable/disable happen predictably.

local _, ns = ...

-- Create class holding module manager behavior.
local ModuleManager = ns.Object:Extend()

-- Initialize module manager state.
function ModuleManager:Constructor(addon)
    self.addon = addon
    -- Create table holding modules.
    self.modules = {}
    -- Create table holding order.
    self.order = {}
end

-- Register module table and keep order.
function ModuleManager:Register(name, moduleTable)
    if type(name) ~= "string" or name == "" then
        error("mummuFrames: module name must be a non-empty string")
    end

    if type(moduleTable) ~= "table" then
        error("mummuFrames: module must be a table")
    end

    if self.modules[name] then
        return self.modules[name]
    end

    moduleTable.moduleName = name
    moduleTable.initialized = false
    moduleTable.enabled = false

    self.modules[name] = moduleTable
    table.insert(self.order, name)

    return moduleTable
end

-- Return registered module by name.
function ModuleManager:Get(name)
    return self.modules[name]
end

-- Initialize all registered modules.
function ModuleManager:InitializeAll(addon)
    for _, name in ipairs(self.order) do
        local moduleTable = self.modules[name]
        if moduleTable and not moduleTable.initialized then
            if type(moduleTable.OnInitialize) == "function" then
                moduleTable:OnInitialize(addon or self.addon)
            end
            moduleTable.initialized = true
        end
    end
end

-- Enable all initialized modules.
function ModuleManager:EnableAll()
    for _, name in ipairs(self.order) do
        local moduleTable = self.modules[name]
        if moduleTable and moduleTable.initialized and not moduleTable.enabled then
            if type(moduleTable.OnEnable) == "function" then
                moduleTable:OnEnable()
            end
            moduleTable.enabled = true
        end
    end
end

-- Disable all enabled modules.
function ModuleManager:DisableAll()
    -- Disable in reverse registration order so dependent modules tear down last.
    for idx = #self.order, 1, -1 do
        local name = self.order[idx]
        local moduleTable = self.modules[name]
        if moduleTable and moduleTable.enabled then
            if type(moduleTable.OnDisable) == "function" then
                moduleTable:OnDisable()
            end
            moduleTable.enabled = false
        end
    end
end

ns.ModuleManager = ModuleManager
