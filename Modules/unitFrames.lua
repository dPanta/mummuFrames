local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Util = ns.Util

local UnitFrames = ns.Object:Extend()
-- Keep a stable refresh order for supported solo unit frames.
local FRAME_ORDER = {
    "player",
    "pet",
    "target",
    "targettarget",
    "focus",
    "focustarget",
}
-- Map unit tokens to unique frame names.
local FRAME_NAME_BY_UNIT = {
    player = "mummuFramesPlayerFrame",
    pet = "mummuFramesPetFrame",
    target = "mummuFramesTargetFrame",
    targettarget = "mummuFramesTargetTargetFrame",
    focus = "mummuFramesFocusFrame",
    focustarget = "mummuFramesFocusTargetFrame",
}
-- Fast lookup table for unit events we care about.
local SUPPORTED_UNITS = {
    player = true,
    pet = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
}
-- Names shown when test mode is active or units are missing.
local TEST_NAME_BY_UNIT = {
    player = UnitName("player") or "Player",
    pet = L.UNIT_TEST_PET or "Pet",
    target = L.UNIT_TEST_TARGET or "Training Target",
    targettarget = L.UNIT_TEST_TARGETTARGET or "Target's Target",
    focus = L.UNIT_TEST_FOCUS or "Focus",
    focustarget = L.UNIT_TEST_FOCUSTARGET or "Focus Target",
}

-- Resolve health bar color using class, reaction, then fallback.
local function resolveHealthColor(unitToken, exists)
    if exists and UnitIsPlayer(unitToken) then
        local _, class = UnitClass(unitToken)
        local color = class and RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b
        end
    end

    if exists then
        local reaction = UnitReaction(unitToken, "player")
        local reactionColor = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if reactionColor then
            return reactionColor.r, reactionColor.g, reactionColor.b
        end
    end

    return 0.2, 0.78, 0.3
end

-- Resolve power bar color from the unit's power type.
local function resolvePowerColor(unitToken, exists)
    if exists then
        local powerType, powerToken = UnitPowerType(unitToken)
        local color = (powerToken and PowerBarColor[powerToken]) or PowerBarColor[powerType]
        if color then
            return color.r, color.g, color.b
        end
    end

    return 0.2, 0.45, 0.85
end

-- Safely apply status bar range and value with protected calls.
local function setStatusBarValueSafe(statusBar, currentValue, maxValue)
    local okRange = pcall(statusBar.SetMinMaxValues, statusBar, 0, maxValue or 1)
    if not okRange then
        statusBar:SetMinMaxValues(0, 1)
    end

    local okValue = pcall(statusBar.SetValue, statusBar, currentValue or 0)
    if not okValue then
        statusBar:SetValue(0)
    end
end

-- Set up module state and frame cache.
function UnitFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    self.frames = {}
    self.pendingVisibilityRefresh = false
end

-- Store a reference to the addon during initialization.
function UnitFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Create frames, subscribe events, and force an initial refresh.
function UnitFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")

    self:CreatePlayerFrame()
    self:CreatePetFrame()
    self:CreateTargetFrame()
    self:CreateTargetTargetFrame()
    self:CreateFocusFrame()
    self:CreateFocusTargetFrame()
    self:RegisterEvents()
    self:RefreshAll(true)
end

-- Unregister events and hide all frames.
function UnitFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:HideAll()
end

-- Register all world and unit events needed to keep frames current.
function UnitFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "PLAYER_TARGET_CHANGED", self.OnTargetChanged)
    ns.EventRouter:Register(self, "PLAYER_FOCUS_CHANGED", self.OnFocusChanged)
    ns.EventRouter:Register(self, "UNIT_TARGET", self.OnUnitTarget)
    ns.EventRouter:Register(self, "UNIT_PET", self.OnUnitPet)
    ns.EventRouter:Register(self, "UNIT_HEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_MAXHEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_POWER_UPDATE", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_MAXPOWER", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_DISPLAYPOWER", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_NAME_UPDATE", self.OnUnitEvent)
end

-- Refresh all frames after world login/loading events.
function UnitFrames:OnWorldEvent()
    self:RefreshAll(true)
end

-- Apply deferred visibility updates after combat lockdown ends.
function UnitFrames:OnCombatEnded()
    if not self.pendingVisibilityRefresh then
        return
    end

    self.pendingVisibilityRefresh = false
    self:RefreshAll()
end

-- Refresh target and target-of-target when the player target changes.
function UnitFrames:OnTargetChanged()
    self:RefreshFrame("target")
    self:RefreshFrame("targettarget")
end

-- Refresh focus and focus target when focus changes.
function UnitFrames:OnFocusChanged()
    self:RefreshFrame("focus")
    self:RefreshFrame("focustarget")
end

-- Refresh any supported unit frame on shared unit update events.
function UnitFrames:OnUnitEvent(_, unitToken)
    if SUPPORTED_UNITS[unitToken] then
        self:RefreshFrame(unitToken)
    end
end

-- Track dependent target units when target/focus targets update.
function UnitFrames:OnUnitTarget(_, unitToken)
    if unitToken == "target" then
        self:RefreshFrame("targettarget")
        return
    end

    if unitToken == "focus" then
        self:RefreshFrame("focustarget")
    end
end

-- Refresh the pet frame when the player's pet unit changes.
function UnitFrames:OnUnitPet(_, unitToken)
    if unitToken == "player" then
        self:RefreshFrame("pet")
    end
end

-- Create and cache one unit frame if it does not exist yet.
function UnitFrames:CreateUnitFrame(unitToken)
    if self.frames[unitToken] then
        return self.frames[unitToken]
    end

    local cfg = self.dataHandle:GetUnitConfig(unitToken)
    local frame = self.globalFrames:CreateUnitFrameBase(
        FRAME_NAME_BY_UNIT[unitToken],
        UIParent,
        unitToken,
        cfg.width,
        cfg.height
    )
    self.frames[unitToken] = frame
    return frame
end

-- Create or return the player unit frame.
function UnitFrames:CreatePlayerFrame()
    return self:CreateUnitFrame("player")
end

-- Create or return the pet unit frame.
function UnitFrames:CreatePetFrame()
    return self:CreateUnitFrame("pet")
end

-- Create or return the target unit frame.
function UnitFrames:CreateTargetFrame()
    return self:CreateUnitFrame("target")
end

-- Create or return the target-of-target unit frame.
function UnitFrames:CreateTargetTargetFrame()
    return self:CreateUnitFrame("targettarget")
end

-- Create or return the focus unit frame.
function UnitFrames:CreateFocusFrame()
    return self:CreateUnitFrame("focus")
end

-- Create or return the focus target unit frame.
function UnitFrames:CreateFocusTargetFrame()
    return self:CreateUnitFrame("focustarget")
end

-- Hide all cached unit frames.
function UnitFrames:HideAll()
    for _, frame in pairs(self.frames) do
        if frame then
            self:SetFrameVisibility(frame, false)
        end
    end
end

-- Show or hide secure unit frames only when combat rules allow it.
function UnitFrames:SetFrameVisibility(frame, shouldShow)
    if not frame then
        return
    end

    local isShown = frame:IsShown()
    if shouldShow and isShown then
        return
    end
    if not shouldShow and not isShown then
        return
    end

    if InCombatLockdown() then
        self.pendingVisibilityRefresh = true
        return
    end

    if shouldShow then
        frame:Show()
    else
        frame:Hide()
    end
end

-- Refresh every supported frame, or hide all when addon is disabled.
function UnitFrames:RefreshAll(forceLayout)
    local profile = self.dataHandle:GetProfile()
    if profile.enabled == false then
        -- Defer hide operations when combat lockdown blocks frame updates.
        Util:RunWhenOutOfCombat(function()
            self:HideAll()
        end, L.CONFIG_DEFERRED_APPLY)
        return
    end

    for i = 1, #FRAME_ORDER do
        self:RefreshFrame(FRAME_ORDER[i], forceLayout)
    end
end

-- Refresh one frame's layout, values, colors, and visibility.
function UnitFrames:RefreshFrame(unitToken, forceLayout)
    local frame = self.frames[unitToken]
    if not frame then
        return
    end

    -- Skip drawing for units disabled in profile settings.
    local unitConfig = self.dataHandle:GetUnitConfig(unitToken)
    if unitConfig.enabled == false then
        self:SetFrameVisibility(frame, false)
        return
    end

    if forceLayout then
        self.globalFrames:ApplyStyle(frame, unitToken)
    end

    local profile = self.dataHandle:GetProfile()
    local testMode = profile.testMode == true
    local exists = UnitExists(unitToken)

    -- Hide missing non-player units unless test mode is enabled.
    if not exists and not testMode and unitToken ~= "player" then
        self:SetFrameVisibility(frame, false)
        return
    end

    local name
    local health
    local maxHealth
    local power
    local maxPower

    -- Read live unit data when available, otherwise use placeholders.
    if exists then
        name = UnitName(unitToken) or unitToken
        health = UnitHealth(unitToken)
        maxHealth = UnitHealthMax(unitToken) or 1
        power = UnitPower(unitToken)
        maxPower = UnitPowerMax(unitToken) or 1
    else
        name = TEST_NAME_BY_UNIT[unitToken] or unitToken
        health = 100
        maxHealth = 100
        power = 100
        maxPower = 100
    end

    local healthR, healthG, healthB = resolveHealthColor(unitToken, exists)
    local powerR, powerG, powerB = resolvePowerColor(unitToken, exists)
    frame.HealthBar:SetStatusBarColor(healthR, healthG, healthB, 1)
    frame.PowerBar:SetStatusBarColor(powerR, powerG, powerB, 1)

    setStatusBarValueSafe(frame.HealthBar, health, maxHealth)
    setStatusBarValueSafe(frame.PowerBar, power, maxPower)

    -- Re-apply a fallback font object if another addon strips font data.
    if not frame.NameText:GetFont() and GameFontHighlightSmall then
        frame.NameText:SetFontObject(GameFontHighlightSmall)
    end
    if not frame.HealthText:GetFont() and GameFontHighlightSmall then
        frame.HealthText:SetFontObject(GameFontHighlightSmall)
    end

    frame.NameText:SetText(name)
    local healthPercent = 0
    if exists and type(UnitHealthPercent) == "function" then
        local curve = CurveConstants and CurveConstants.ScaleTo100 or nil
        local okPercent, rawPercent = pcall(UnitHealthPercent, unitToken, true, curve)
        if okPercent and rawPercent ~= nil then
            local numericPercent = tonumber(rawPercent)
            if numericPercent then
                healthPercent = numericPercent
            end
        end
    elseif not exists then
        healthPercent = 100
    end
    frame.HealthText:SetText(string.format("%.0f%%", healthPercent))

    self:SetFrameVisibility(frame, true)
end

addon:RegisterModule("unitFrames", UnitFrames:New())
