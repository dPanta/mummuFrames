-- Lightweight prototype-style object helper used across modules.
-- Provides class extension (`Extend`) and instance construction (`New`).

local _, ns = ...

-- Root prototype that other module classes extend from.
local Object = {}
Object.__index = Object

-- Create a new prototype that inherits from the current one.
function Object:Extend()
    local class = {}
    class.__index = class
    setmetatable(class, { __index = self })
    return class
end

-- Instantiate the prototype and call its optional Constructor.
function Object:New(...)
    local instance = setmetatable({}, self)
    if type(instance.Constructor) == "function" then
        instance:Constructor(...)
    end
    return instance
end

ns.Object = Object
