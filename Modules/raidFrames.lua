local _, ns = ...

local addon = _G.mummuFrames

-- Create class holding raid frames behavior.
local RaidFrames = ns.Object:Extend()

-- Initialize raid frames state.
function RaidFrames:Constructor()
    self.addon = nil
end

-- Initialize raid frames module.
function RaidFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable raid frames module.
function RaidFrames:OnEnable()
end

-- Disable raid frames module.
function RaidFrames:OnDisable()
end

-- Create raid frames.
function RaidFrames:CreateRaidFrames()
    return nil, "not yet enabled"
end

addon:RegisterModule("raidFrames", RaidFrames:New())
