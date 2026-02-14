local _, ns = ...

local ModuleManager = ns.Object:Extend()

-- Set up storage for module instances and their order.
function ModuleManager:Constructor(addon)
    self.addon = addon
    self.modules = {}
    self.order = {}
end

-- Register a module once and keep stable registration order.
function ModuleManager:Register(name, moduleTable)
    -- Validate the registration input early.
    if type(name) ~= "string" or name == "" then
        error("mummuFrames: module name must be a non-empty string")
    end

    if type(moduleTable) ~= "table" then
        error("mummuFrames: module must be a table")
    end

    -- Return the existing module when the name is already registered.
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

-- Return a registered module by name.
function ModuleManager:Get(name)
    return self.modules[name]
end

-- Initialize modules in registration order.
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

-- Enable initialized modules in registration order.
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

-- Disable enabled modules in reverse registration order.
function ModuleManager:DisableAll()
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
