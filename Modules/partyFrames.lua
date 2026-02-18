local _, ns = ...

local addon = _G.mummuFrames

-- Create class holding party frames behavior.
local PartyFrames = ns.Object:Extend()

-- Initialize party frames state.
function PartyFrames:Constructor()
    self.addon = nil
end

-- Initialize party frames module.
function PartyFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable party frames module.
function PartyFrames:OnEnable()
end

-- Disable party frames module.
function PartyFrames:OnDisable()
end

-- Create party frames.
function PartyFrames:CreatePartyFrames()
    return nil, "not yet enabled"
end

addon:RegisterModule("partyFrames", PartyFrames:New())
