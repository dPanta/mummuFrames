local _, ns = ...

local addon = _G.mummuFrames

local RaidFrames = ns.Object:Extend()

-- Set up module state.
function RaidFrames:Constructor()
    self.addon = nil
end

-- Store a reference to the addon during initialization.
function RaidFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable hook placeholder for future raid frame logic.
function RaidFrames:OnEnable()
end

-- Disable hook placeholder for future raid frame cleanup.
function RaidFrames:OnDisable()
end

-- Placeholder constructor until raid frames are implemented.
function RaidFrames:CreateRaidFrames()
    return nil, "not yet enabled"
end

addon:RegisterModule("raidFrames", RaidFrames:New())
