local _, ns = ...

local Object = {}
Object.__index = Object

-- Create a child class that inherits from this class.
function Object:Extend()
    local class = {}
    class.__index = class
    setmetatable(class, { __index = self })
    return class
end

-- Create a new instance and call Constructor when present.
function Object:New(...)
    local instance = setmetatable({}, self)
    if type(instance.Constructor) == "function" then
        instance:Constructor(...)
    end
    return instance
end

ns.Object = Object
