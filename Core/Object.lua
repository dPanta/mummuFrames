-- Lightweight prototype-style object helper used across modules.
-- Provides class extension (`Extend`) and instance construction (`New`).

local _, ns = ...

-- Create table holding object.
local Object = {}
Object.__index = Object

-- Create child class.
function Object:Extend()
    -- Create table holding class.
    local class = {}
    class.__index = class
    -- Set class metatable.
    setmetatable(class, { __index = self })
    return class
end

-- Build object instance.
function Object:New(...)
    -- Set metatable for instance.
    local instance = setmetatable({}, self)
    if type(instance.Constructor) == "function" then
        instance:Constructor(...)
    end
    return instance
end

ns.Object = Object
