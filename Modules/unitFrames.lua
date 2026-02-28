-- ============================================================================
-- UNIT FRAMES MODULE
-- ============================================================================
-- Handles player/pet/target/focus style frames: event routing, visibility,
-- status/cast updates, and detached power element positioning.

local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Style = ns.Style
local Util = ns.Util
local AuraSafety = ns.AuraSafety

-- Create class holding unit frames behavior.
local UnitFrames = ns.Object:Extend()

---@class mummuEditModeSelection : Frame
---@field Label FontString
---@field parentFrame Frame?
---@field _fallbackBorder Texture?

---@class SecondaryPowerResource
---@field powerType number?
---@field maxIcons number
---@field texture string
---@field usesRuneCooldownAPI boolean?
---@field powerCap number?
---@field auraSpellID number?
---@field auraFilter string?
---@field usesAuraStacks boolean?
---@field displayMaxIcons number?
---@field overflowTexture string?
---@field allowedSpecIDs table<number, boolean>?

-- Create table holding frame order.
local FRAME_ORDER = {
    "player",
    "pet",
    "target",
    "targettarget",
    "focus",
    "focustarget",
}
-- Dynamic units use secure visibility state drivers so they can appear/disappear
-- during combat without insecure Show/Hide calls.
local DYNAMIC_VISIBILITY_DRIVERS = {
    pet = "[@pet,exists] show; hide",
    target = "[@target,exists] show; hide",
    targettarget = "[@targettarget,exists] show; hide",
    focus = "[@focus,exists] show; hide",
    focustarget = "[@focustarget,exists] show; hide",
}
-- Create table holding frame name by unit.
local FRAME_NAME_BY_UNIT = {
    player = "mummuFramesPlayerFrame",
    pet = "mummuFramesPetFrame",
    target = "mummuFramesTargetFrame",
    targettarget = "mummuFramesTargetTargetFrame",
    focus = "mummuFramesFocusFrame",
    focustarget = "mummuFramesFocusTargetFrame",
}
-- Create table holding blizzard frame name by unit.
local BLIZZARD_FRAME_NAME_BY_UNIT = {
    player = "PlayerFrame",
    pet = "PetFrame",
    target = "TargetFrame",
    targettarget = "TargetFrameToT",
    focus = "FocusFrame",
    focustarget = "FocusFrameToT",
}
local GLOBAL_HIDE_BLIZZARD_UNITS = {
    player = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
}
-- Create table holding supported units.
local SUPPORTED_UNITS = {
    player = true,
    pet = true,
    target = true,
    targettarget = true,
    focus = true,
    focustarget = true,
}
-- Create table holding test name by unit. Entropy stays pending.
local TEST_NAME_BY_UNIT = {
    player = UnitName("player") or "Player",
    pet = L.UNIT_TEST_PET or "Pet",
    target = L.UNIT_TEST_TARGET or "Training Target",
    targettarget = L.UNIT_TEST_TARGETTARGET or "Target's Target",
    focus = L.UNIT_TEST_FOCUS or "Focus",
    focustarget = L.UNIT_TEST_FOCUSTARGET or "Focus Target",
}
local DEFAULT_AURA_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local function roundToNearestInteger(value)
    return math.floor(value + 0.5)
end
local function valuesEqual(left, right)
    return left == right
end
local function getSafeBooleanValue(value, fallback)
    if type(value) == "boolean" then
        return value
    end
    return fallback
end

local CASTBAR_COLOR_NORMAL = { 0.29, 0.52, 0.90 }
local CASTBAR_COLOR_NOINTERRUPT = { 0.63, 0.63, 0.63 }
local TARGET_OUT_OF_RANGE_ALPHA = 0.55
local SECONDARY_POWER_ICON_BASE = "Interface\\AddOns\\mummuFrames\\Icons\\"
local SECONDARY_POWER_MAX_ICONS = 10
local SECONDARY_POWER_EMPTY_ALPHA = 0.22
local IRONFUR_SPELL_ID = 192081
local GUARDIAN_SPEC_ID = 104
local BREWMASTER_SPEC_ID = 268
local ELEMENTAL_SPEC_ID = 262
local ENHANCEMENT_SPEC_ID = 263
local MAELSTROM_WEAPON_SPELL_ID = 344179
local TERTIARY_STAGGER_EMPTY_ALPHA = 0.24
local IRONFUR_BASE_DURATION = 7
local SPELL_AURA_SCAN_MAX = 255
local hideTertiaryPowerBar
local collectActiveGuardianStackStates

-- Create table holding castbar units.
local CASTBAR_UNITS = {
    player = true,
    target = true,
    focus = true,
}

-- Create table holding refresh options full.
local REFRESH_OPTIONS_FULL = {
    vitals = true,
    auras = true,
    statusIcons = true,
    secondaryPower = true,
    tertiaryPower = true,
    castbar = true,
    visibility = true,
}

-- Create table holding refresh options vitals.
local REFRESH_OPTIONS_VITALS = {
    vitals = true,
    secondaryPower = true,
    tertiaryPower = true,
    visibility = true,
}

-- Create table holding refresh options auras.
local REFRESH_OPTIONS_AURAS = {
    auras = true,
    tertiaryPower = true,
}
local REFRESH_OPTIONS_AURAS_AND_SECONDARY = {
    auras = true,
    secondaryPower = true,
    tertiaryPower = true,
}
local REFRESH_OPTIONS_AURAS_ONLY = {
    auras = true,
}

-- Create table holding refresh options castbar.
local REFRESH_OPTIONS_CASTBAR = {
    castbar = true,
}

-- Create table holding refresh options secondary power.
local REFRESH_OPTIONS_SECONDARY_POWER = {
    secondaryPower = true,
}

-- Create table holding refresh options tertiary power.
local REFRESH_OPTIONS_TERTIARY_POWER = {
    tertiaryPower = true,
}

-- Resolve power type constant.
local function resolvePowerTypeConstant(enumKey, globalKey, fallback)
    local enumValue = _G.Enum and _G.Enum.PowerType and _G.Enum.PowerType[enumKey]
    if enumValue ~= nil then
        return enumValue
    end
    local globalValue = _G[globalKey]
    if globalValue ~= nil then
        return globalValue
    end
    return fallback
end

-- Create table holding secondary power by class.
---@type table<string, SecondaryPowerResource>
local SECONDARY_POWER_BY_CLASS = {
    -- Create table holding monk.
    MONK = {
        powerType = resolvePowerTypeConstant("Chi", "SPELL_POWER_CHI", 12),
        maxIcons = 6,
        texture = SECONDARY_POWER_ICON_BASE .. "monk_chi.png",
    },
    -- Create table holding deathknight.
    DEATHKNIGHT = {
        powerType = resolvePowerTypeConstant("Runes", "SPELL_POWER_RUNES", 5),
        maxIcons = 6,
        texture = SECONDARY_POWER_ICON_BASE .. "dk_runes.png",
        usesRuneCooldownAPI = true,
    },
    -- Create table holding rogue.
    ROGUE = {
        powerType = resolvePowerTypeConstant("ComboPoints", "SPELL_POWER_COMBO_POINTS", 4),
        maxIcons = 8,
        texture = SECONDARY_POWER_ICON_BASE .. "rogue_combo_points.png",
    },
    -- Create table holding paladin.
    PALADIN = {
        powerType = resolvePowerTypeConstant("HolyPower", "SPELL_POWER_HOLY_POWER", 9),
        maxIcons = 5,
        texture = SECONDARY_POWER_ICON_BASE .. "paladin_holy_power.png",
    },
    -- Create table holding warlock.
    WARLOCK = {
        powerType = resolvePowerTypeConstant("SoulShards", "SPELL_POWER_SOUL_SHARDS", 7),
        maxIcons = 5,
        texture = SECONDARY_POWER_ICON_BASE .. "warlock_soul_shards.png",
    },
    -- Create table holding evoker.
    EVOKER = {
        powerType = resolvePowerTypeConstant("Essence", "SPELL_POWER_ESSENCE", 19),
        maxIcons = 6,
        texture = SECONDARY_POWER_ICON_BASE .. "evoker_essence.png",
    },
    -- Create table holding mage.
    MAGE = {
        powerType = resolvePowerTypeConstant("ArcaneCharges", "SPELL_POWER_ARCANE_CHARGES", 16),
        maxIcons = 4,
        texture = SECONDARY_POWER_ICON_BASE .. "mage_arcane_charges.png",
    },
    -- Create table holding demonhunter.
    DEMONHUNTER = {
        powerType = resolvePowerTypeConstant("SoulFragments", "SPELL_POWER_SOUL_FRAGMENTS", 17),
        maxIcons = 5,
        texture = SECONDARY_POWER_ICON_BASE .. "dh_soul_fragments.png",
    },
    -- Create table holding shaman.
    SHAMAN = {
        maxIcons = 5,
        powerCap = 10,
        auraSpellID = MAELSTROM_WEAPON_SPELL_ID,
        auraFilter = "HELPFUL|PLAYER",
        usesAuraStacks = true,
        displayMaxIcons = 5,
        texture = SECONDARY_POWER_ICON_BASE .. "shaman_maelstrom_weapon_blue.png",
        overflowTexture = SECONDARY_POWER_ICON_BASE .. "shaman_maelstrom_weapon_red.png",
        -- Create table holding supported specs.
        allowedSpecIDs = {
            [ELEMENTAL_SPEC_ID] = true,
            [ENHANCEMENT_SPEC_ID] = true,
        },
    },
}

-- Safe bool. Evaluate boolean-like inputs inside pcall to avoid hard errors when
-- WoW returns secret booleans from APIs like UnitCastingInfo/UnitChannelInfo.
local function safeBool(val, fallback)
    local okEval, evaluated = pcall(function()
        if val then
            return true
        end
        return false
    end)
    if okEval then
        return evaluated
    end
    return fallback == true
end

-- Resolve health color.
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

-- Resolve power color.
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

-- Return whether unit should be treated as out of range.
local function isUnitOutOfRange(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end

    -- Range APIs can produce secret booleans in insecure code paths.
    -- Avoid evaluating them here to prevent combat taint propagation.
    return false
end

-- Refresh target frame alpha from current range state.
function UnitFrames:RefreshTargetRangeAlpha(frame, exists, previewMode)
    if not frame or frame.unitToken ~= "target" then
        return
    end

    local isOutOfRange = false
    if exists and not previewMode then
        isOutOfRange = isUnitOutOfRange("target")
    end

    frame:SetAlpha(isOutOfRange and TARGET_OUT_OF_RANGE_ALPHA or 1)
end

-- Set status bar value safe.
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

-- Update absorb overlay.
local function updateAbsorbOverlay(frame, unitToken, exists, _, maxHealth, testMode)
    if not frame or not frame.AbsorbOverlayBar or not frame.AbsorbOverlayFrame then
        return
    end

    if not exists and not testMode then
        frame.AbsorbOverlayBar:Hide()
        frame.AbsorbOverlayFrame:Hide()
        return
    end

    local absorbValue = 0
    local absorbMax = maxHealth or 1

    if exists then
        absorbMax = UnitHealthMax(unitToken) or absorbMax
        if type(UnitGetTotalAbsorbs) == "function" then
            absorbValue = UnitGetTotalAbsorbs(unitToken) or 0
        end
    elseif testMode then
        absorbMax = 100
        absorbValue = 25
    end

    setStatusBarValueSafe(frame.AbsorbOverlayBar, absorbValue, absorbMax)
    frame.AbsorbOverlayFrame:Show()
    frame.AbsorbOverlayBar:Show()
end

local function normalizeSpellID(value)
    local numeric = tonumber(value)
    if type(numeric) ~= "number" then
        return nil
    end
    local rounded = math.floor(numeric + 0.5)
    if rounded <= 0 then
        return nil
    end
    return rounded
end

-- Return auras by spell id.
local function getAurasBySpellID(unitToken, filter, spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID or type(unitToken) ~= "string" then
        return {}, false
    end

    if unitToken ~= "player" then
        return {}, false
    end
    if type(filter) == "string" and not string.find(filter, "HELPFUL", 1, true) then
        return {}, false
    end

    local auraData = nil
    local queryRestricted = false
    if AuraSafety and type(AuraSafety.GetPlayerAuraBySpellIDSafe) == "function" then
        auraData, queryRestricted = AuraSafety:GetPlayerAuraBySpellIDSafe(normalizedSpellID)
    elseif C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, normalizedSpellID)
        if ok and type(result) == "table" then
            auraData = result
        end
    end

    if type(auraData) ~= "table" then
        return {}, queryRestricted == true
    end

    local safeNumber = function(value, fallback)
        if AuraSafety and type(AuraSafety.SafeNumber) == "function" then
            return AuraSafety:SafeNumber(value, fallback)
        end
        local parsed = tonumber(value)
        if type(parsed) == "number" then
            return parsed
        end
        return fallback
    end

    local matches = {
        {
            name = auraData.name,
            auraInstanceID = auraData.auraInstanceID,
            icon = auraData.icon,
            count = safeNumber(auraData.applications, 1) or 1,
            duration = safeNumber(auraData.duration, 0) or 0,
            expirationTime = safeNumber(auraData.expirationTime, 0) or 0,
            spellId = normalizedSpellID,
        },
    }
    return matches, queryRestricted == true
end

-- Return player specialization id.
local function getPlayerSpecializationID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local currentSpecIndex = GetSpecialization()
    if type(currentSpecIndex) ~= "number" then
        return nil
    end

    local specID = GetSpecializationInfo(currentSpecIndex)
    if type(specID) ~= "number" then
        return nil
    end

    return specID
end

-- Check spell ID match.
local function spellIDMatches(spellID, targetSpellID)
    if spellID == nil or targetSpellID == nil then
        return false
    end

    local ok, matches = pcall(valuesEqual, spellID, targetSpellID)
    return ok and matches
end

-- Return whether resource supports specialization.
local function isSecondaryResourceSupportedForSpec(resource, specID)
    if type(resource) ~= "table" then
        return false
    end

    local allowedSpecIDs = resource.allowedSpecIDs
    if type(allowedSpecIDs) ~= "table" then
        return true
    end

    return specID ~= nil and allowedSpecIDs[specID] == true
end

-- Return whether player secondary power should refresh from aura updates.
local function playerSecondaryPowerUsesAuraStacks()
    local _, classToken = UnitClass("player")
    local resource = classToken and SECONDARY_POWER_BY_CLASS[classToken] or nil
    if type(resource) ~= "table" or resource.usesAuraStacks ~= true then
        return false
    end

    return isSecondaryResourceSupportedForSpec(resource, getPlayerSpecializationID())
end

-- Check frame anchored to.
local function isFrameAnchoredTo(frame, target, visited)
    if not (frame and target and frame.GetNumPoints) then
        return false
    end

    visited = visited or {}
    if visited[frame] then
        return false
    end
    visited[frame] = true

    for i = 1, frame:GetNumPoints() do
        local _, relativeTo = frame:GetPoint(i)
        if relativeTo and (relativeTo == target or isFrameAnchoredTo(relativeTo, target, visited)) then
            return true
        end
    end

    return false
end

-- Ensure edit mode magnetism api.
local function ensureEditModeMagnetismAPI(frame)
    if not frame or frame._mummuHasMagnetismAPI then
        return
    end

    frame._mummuHasMagnetismAPI = true
    local SELECTION_PADDING = 2

    if not frame.GetScaledSelectionCenter then
        -- Return scaled selection center.
        function frame:GetScaledSelectionCenter()
            local cx, cy = 0, 0
            if self.Selection and self.Selection.GetCenter then
                cx, cy = self.Selection:GetCenter()
            end
            if not (cx and cy) and self.GetCenter then
                cx, cy = self:GetCenter()
            end
            if not (cx and cy) then
                cx, cy = 0, 0
            end
            local scale = self:GetScale() or 1
            return cx * scale, cy * scale
        end
    end

    if not frame.GetScaledCenter then
        -- Return scaled center.
        function frame:GetScaledCenter()
            local cx, cy = self:GetCenter()
            local scale = self:GetScale() or 1
            return (cx or 0) * scale, (cy or 0) * scale
        end
    end

    if not frame.GetScaledSelectionSides then
        -- Return scaled selection sides.
        function frame:GetScaledSelectionSides()
            local scale = self:GetScale() or 1
            if self.Selection and self.Selection.GetRect then
                local left, bottom, width, height = self.Selection:GetRect()
                if left then
                    return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
                end
            end
            local left, bottom, width, height = self:GetRect()
            left = left or 0
            bottom = bottom or 0
            width = width or 0
            height = height or 0
            return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
        end
    end

    if not frame.GetLeftOffset then
        -- Return left offset. Coffee remains optional.
        function frame:GetLeftOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(4, self.Selection:GetPoint(1)) or 0) - SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetRightOffset then
        -- Return right offset.
        function frame:GetRightOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(4, self.Selection:GetPoint(2)) or 0) + SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetTopOffset then
        -- Return top offset.
        function frame:GetTopOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(5, self.Selection:GetPoint(1)) or 0) + SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetBottomOffset then
        -- Return bottom offset.
        function frame:GetBottomOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(5, self.Selection:GetPoint(2)) or 0) - SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetSelectionOffset then
        -- Return selection offset.
        function frame:GetSelectionOffset(point, forYOffset)
            local offset
            if point == "LEFT" then
                offset = self:GetLeftOffset()
            elseif point == "RIGHT" then
                offset = self:GetRightOffset()
            elseif point == "TOP" then
                offset = self:GetTopOffset()
            elseif point == "BOTTOM" then
                offset = self:GetBottomOffset()
            elseif point == "TOPLEFT" then
                offset = forYOffset and self:GetTopOffset() or self:GetLeftOffset()
            elseif point == "TOPRIGHT" then
                offset = forYOffset and self:GetTopOffset() or self:GetRightOffset()
            elseif point == "BOTTOMLEFT" then
                offset = forYOffset and self:GetBottomOffset() or self:GetLeftOffset()
            elseif point == "BOTTOMRIGHT" then
                offset = forYOffset and self:GetBottomOffset() or self:GetRightOffset()
            else
                local selectionCenterX, selectionCenterY = 0, 0
                if self.Selection and self.Selection.GetCenter then
                    selectionCenterX, selectionCenterY = self.Selection:GetCenter()
                end
                if not (selectionCenterX and selectionCenterY) and self.GetCenter then
                    selectionCenterX, selectionCenterY = self:GetCenter()
                end
                selectionCenterX = selectionCenterX or 0
                selectionCenterY = selectionCenterY or 0

                local centerX, centerY = self:GetCenter()
                centerX = centerX or 0
                centerY = centerY or 0

                if forYOffset then
                    offset = selectionCenterY - centerY
                else
                    offset = selectionCenterX - centerX
                end
            end
            return offset * (self:GetScale() or 1)
        end
    end

    if not frame.GetCombinedSelectionOffset then
        -- Return combined selection offset.
        function frame:GetCombinedSelectionOffset(frameInfo, forYOffset)
            local offset
            if frameInfo.frame.Selection then
                offset = -self:GetSelectionOffset(frameInfo.point, forYOffset)
                    + frameInfo.frame:GetSelectionOffset(frameInfo.relativePoint, forYOffset)
                    + frameInfo.offset
            else
                offset = -self:GetSelectionOffset(frameInfo.point, forYOffset) + frameInfo.offset
            end
            return offset / (self:GetScale() or 1)
        end
    end

    if not frame.GetCombinedCenterOffset then
        -- Return combined center offset.
        function frame:GetCombinedCenterOffset(otherFrame)
            local centerX, centerY = self:GetScaledCenter()
            local frameCenterX, frameCenterY
            if otherFrame.GetScaledCenter then
                frameCenterX, frameCenterY = otherFrame:GetScaledCenter()
            else
                frameCenterX, frameCenterY = otherFrame:GetCenter()
            end
            local scale = self:GetScale() or 1
            return (centerX - frameCenterX) / scale, (centerY - frameCenterY) / scale
        end
    end

    if not frame.GetSnapOffsets then
        -- Return snap offsets.
        function frame:GetSnapOffsets(frameInfo)
            local offsetX, offsetY
            if frameInfo.isCornerSnap then
                offsetX = self:GetCombinedSelectionOffset(frameInfo, false)
                offsetY = self:GetCombinedSelectionOffset(frameInfo, true)
            else
                offsetX, offsetY = self:GetCombinedCenterOffset(frameInfo.frame)
                if frameInfo.isHorizontal then
                    offsetX = self:GetCombinedSelectionOffset(frameInfo, false)
                else
                    offsetY = self:GetCombinedSelectionOffset(frameInfo, true)
                end
            end
            return offsetX, offsetY
        end
    end

    if not frame.SnapToFrame then
        -- Snap to frame.
        function frame:SnapToFrame(frameInfo)
            local offsetX, offsetY = self:GetSnapOffsets(frameInfo)
            self:ClearAllPoints()
            self:SetPoint(frameInfo.point, frameInfo.frame, frameInfo.relativePoint, offsetX, offsetY)
        end
    end

    if not frame.IsFrameAnchoredToMe then
        -- Check frame anchored to me.
        function frame:IsFrameAnchoredToMe(other)
            return isFrameAnchoredTo(other, self)
        end
    end

    if not frame.IsToTheLeftOfFrame then
        -- Check to the left of frame.
        function frame:IsToTheLeftOfFrame(other)
            local _, myRight = self:GetScaledSelectionSides()
            local otherLeft = select(1, other:GetScaledSelectionSides())
            return myRight < otherLeft
        end
    end

    if not frame.IsToTheRightOfFrame then
        -- Check to the right of frame.
        function frame:IsToTheRightOfFrame(other)
            local myLeft = select(1, self:GetScaledSelectionSides())
            local otherRight = select(2, other:GetScaledSelectionSides())
            return myLeft > otherRight
        end
    end

    if not frame.IsAboveFrame then
        -- Check above frame.
        function frame:IsAboveFrame(other)
            local _, _, myBottom = self:GetScaledSelectionSides()
            local _, _, _, otherTop = other:GetScaledSelectionSides()
            return myBottom > otherTop
        end
    end

    if not frame.IsBelowFrame then
        -- Check below frame.
        function frame:IsBelowFrame(other)
            local _, _, _, myTop = self:GetScaledSelectionSides()
            local _, _, otherBottom = other:GetScaledSelectionSides()
            return myTop < otherBottom
        end
    end

    if not frame.IsVerticallyAlignedWithFrame then
        -- Check vertically aligned with frame.
        function frame:IsVerticallyAlignedWithFrame(other)
            local _, _, myBottom, myTop = self:GetScaledSelectionSides()
            local _, _, otherBottom, otherTop = other:GetScaledSelectionSides()
            return (myTop >= otherBottom) and (myBottom <= otherTop)
        end
    end

    if not frame.IsHorizontallyAlignedWithFrame then
        -- Check horizontally aligned with frame.
        function frame:IsHorizontallyAlignedWithFrame(other)
            local myLeft, myRight = self:GetScaledSelectionSides()
            local otherLeft, otherRight = other:GetScaledSelectionSides()
            return (myRight >= otherLeft) and (myLeft <= otherRight)
        end
    end

    if not frame.GetFrameMagneticEligibility then
        -- Return frame magnetic eligibility.
        function frame:GetFrameMagneticEligibility(systemFrame)
            if systemFrame == self then
                return nil
            end
            if self:IsFrameAnchoredToMe(systemFrame) then
                return nil
            end

            local myLeft, myRight, myBottom, myTop = self:GetScaledSelectionSides()
            local otherLeft, otherRight, otherBottom, otherTop = systemFrame:GetScaledSelectionSides()
            local horizontalEligible = (myTop >= otherBottom) and (myBottom <= otherTop)
                and (myRight < otherLeft or myLeft > otherRight)
            local verticalEligible = (myRight >= otherLeft) and (myLeft <= otherRight)
                and (myBottom > otherTop or myTop < otherBottom)
            return horizontalEligible, verticalEligible
        end
    end
end

-- Initialize unit frames state.
function UnitFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    -- Create table holding frames.
    self.frames = {}
    self.pendingVisibilityRefresh = false
    self.pendingDriverVisibilityRefresh = false
    self.editModeActive = false
    self.editModeCallbacksRegistered = false
end

-- Initialize unit frames module.
function UnitFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable module. Bug parade continues.
function UnitFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")
    self.pendingVisibilityRefresh = false
    self.pendingDriverVisibilityRefresh = false
    self:RegisterEditModeCallbacks()
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame.editModeActive == true) and true or false

    self:CreatePlayerFrame()
    self:CreatePetFrame()
    self:CreateTargetFrame()
    self:CreateTargetTargetFrame()
    self:CreateFocusFrame()
    self:CreateFocusTargetFrame()
    self:RegisterEvents()
    self:RefreshVisibilityDrivers()
    self:RefreshAll(true)
end

-- Disable unit frames module.
function UnitFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:UnregisterEditModeCallbacks()
    self.editModeActive = false
    self.pendingVisibilityRefresh = false
    self.pendingDriverVisibilityRefresh = false
    if not InCombatLockdown() then
        self:RefreshVisibilityDrivers(true)
    end
    self:RestoreAllBlizzardUnitFrames()
    self:HideAll()
end

-- Register edit mode callbacks.
function UnitFrames:RegisterEditModeCallbacks()
    if self.editModeCallbacksRegistered then
        return
    end

    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    EventRegistry:RegisterCallback("EditMode.Enter", self.OnEditModeEnter, self)
    EventRegistry:RegisterCallback("EditMode.Exit", self.OnEditModeExit, self)
    self.editModeCallbacksRegistered = true
end

-- Unregister edit mode callbacks.
function UnitFrames:UnregisterEditModeCallbacks()
    if not self.editModeCallbacksRegistered then
        return
    end

    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end

    self.editModeCallbacksRegistered = false
end

-- Ensure edit mode selection.
function UnitFrames:EnsureEditModeSelection(frame)
    if not frame or frame.EditModeSelection then
        return
    end

    -- Create frame for selection.
    local selection = CreateFrame("Frame", nil, frame) --[[@as mummuEditModeSelection]]
    -- Create texture for border.
    local border = selection:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.29, 0.74, 0.98, 0.55)
    selection._fallbackBorder = border

    -- Create font string for label.
    local label = selection:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", 0, 10)
    label:SetTextColor(1, 1, 1, 1)
    Style:ApplyFont(label, 11, "OUTLINE")
    selection.Label = label

    selection:SetAllPoints(frame)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection:SetClampedToScreen(true)
    selection:SetFrameStrata("DIALOG")
    selection:SetFrameLevel(frame:GetFrameLevel() + 30)

    if selection.Label and selection.Label.SetText then
        local labelText = TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame"
        selection.Label:SetText(labelText)
    end

    -- Handle OnDragStart script callback.
    selection:SetScript("OnDragStart", function(sel)
        self:BeginEditModeDrag(sel.parentFrame or frame)
    end)
    -- Handle OnDragStop script callback.
    selection:SetScript("OnDragStop", function(sel)
        self:EndEditModeDrag(sel.parentFrame or frame)
    end)

    selection.parentFrame = frame
    frame.Selection = selection
    frame.EditModeSelection = selection
    ensureEditModeMagnetismAPI(frame)
    selection:Hide()
end

-- Begin edit mode drag.
function UnitFrames:BeginEditModeDrag(frame)
    if not frame or not self.editModeActive or InCombatLockdown() then
        return
    end

    frame:SetMovable(true)
    frame:StartMoving()
    frame._editModeMoving = true

    if EditModeManagerFrame and type(EditModeManagerFrame.SetSnapPreviewFrame) == "function" then
        pcall(EditModeManagerFrame.SetSnapPreviewFrame, EditModeManagerFrame, frame)
    end
end

-- End edit mode drag.
function UnitFrames:EndEditModeDrag(frame)
    if not frame or not frame._editModeMoving then
        return
    end

    frame:StopMovingOrSizing()
    frame._editModeMoving = false

    if EditModeManagerFrame and type(EditModeManagerFrame.ClearSnapPreviewFrame) == "function" then
        pcall(EditModeManagerFrame.ClearSnapPreviewFrame, EditModeManagerFrame)
    end

    if EditModeManagerFrame
        and type(EditModeManagerFrame.IsSnapEnabled) == "function"
        and EditModeManagerFrame:IsSnapEnabled()
        and EditModeMagnetismManager
        and type(EditModeMagnetismManager.ApplyMagnetism) == "function"
    then
        pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, frame)
    end

    self:SaveFrameAnchorFromEditMode(frame)
end

-- Save frame anchor from edit mode.
function UnitFrames:SaveFrameAnchorFromEditMode(frame)
    if not frame or not self.dataHandle or not frame.unitToken then
        return
    end

    local centerX, centerY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not centerX or not centerY or not parentX or not parentY then
        return
    end

    local offsetX = centerX - parentX
    local offsetY = centerY - parentY
    local pixel = (Style and Style.GetPixelSize and Style:GetPixelSize()) or 1
    local centerSnapThreshold = 10 * pixel
    if math.abs(offsetX) <= centerSnapThreshold then
        offsetX = 0
    end
    if math.abs(offsetY) <= centerSnapThreshold then
        offsetY = 0
    end

    if Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled() then
        offsetX = Style:Snap(offsetX)
        offsetY = Style:Snap(offsetY)
    else
        offsetX = math.floor(offsetX + 0.5)
        offsetY = math.floor(offsetY + 0.5)
    end

    self.dataHandle:SetUnitConfig(frame.unitToken, "point", "CENTER")
    self.dataHandle:SetUnitConfig(frame.unitToken, "relativePoint", "CENTER")
    self.dataHandle:SetUnitConfig(frame.unitToken, "x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Handle edit mode enter event.
function UnitFrames:OnEditModeEnter()
    self.editModeActive = true
    self:RefreshVisibilityDrivers()

    for _, frame in pairs(self.frames) do
        if frame then
            self:EnsureEditModeSelection(frame)
            frame:SetMovable(true)
            frame:EnableMouse(false)
            if frame.EditModeSelection then
                frame.EditModeSelection:Show()
            end
            if frame.unitToken == "player" and frame.PowerBar and frame.PowerBar._detached then
                self:EnsurePrimaryPowerBarEditModeSelection(frame)
                frame.PowerBar:SetMovable(true)
                if frame.PowerBar.EditModeSelection then
                    frame.PowerBar.EditModeSelection:Show()
                end
            end
            if frame.CastBar and frame.CastBar._enabled then
                if frame.CastBar._detached then
                    self:EnsureCastBarEditModeSelection(frame)
                    frame.CastBar:SetMovable(true)
                    if frame.CastBar.EditModeSelection then
                        frame.CastBar.EditModeSelection:Show()
                    end
                end
            end
            if frame.SecondaryPowerBar and frame.SecondaryPowerBar._enabled then
                if frame.SecondaryPowerBar._detached then
                    self:EnsureSecondaryPowerBarEditModeSelection(frame)
                    frame.SecondaryPowerBar:SetMovable(true)
                    if frame.SecondaryPowerBar.EditModeSelection then
                        frame.SecondaryPowerBar.EditModeSelection:Show()
                    end
                end
            end
            if frame.TertiaryPowerBar and frame.TertiaryPowerBar._enabled then
                if frame.TertiaryPowerBar._detached then
                    self:EnsureTertiaryPowerBarEditModeSelection(frame)
                    frame.TertiaryPowerBar:SetMovable(true)
                    if frame.TertiaryPowerBar.EditModeSelection then
                        frame.TertiaryPowerBar.EditModeSelection:Show()
                    end
                end
            end
        end
    end

    self:RefreshAll(true)
end

-- Handle edit mode exit event.
function UnitFrames:OnEditModeExit()
    self.editModeActive = false
    self:RefreshVisibilityDrivers()

    for _, frame in pairs(self.frames) do
        if frame then
            frame:StopMovingOrSizing()
            frame._editModeMoving = false
            frame:EnableMouse(true)
            if frame.EditModeSelection then
                frame.EditModeSelection:Hide()
            end
            if frame.PowerBar then
                frame.PowerBar:StopMovingOrSizing()
                frame.PowerBar._editModeMoving = false
                if frame.PowerBar.EditModeSelection then
                    frame.PowerBar.EditModeSelection:Hide()
                end
            end
            if frame.CastBar then
                frame.CastBar:StopMovingOrSizing()
                frame.CastBar._editModeMoving = false
                if frame.CastBar.EditModeSelection then
                    frame.CastBar.EditModeSelection:Hide()
                end
            end
            if frame.SecondaryPowerBar then
                frame.SecondaryPowerBar:StopMovingOrSizing()
                frame.SecondaryPowerBar._editModeMoving = false
                if frame.SecondaryPowerBar.EditModeSelection then
                    frame.SecondaryPowerBar.EditModeSelection:Hide()
                end
            end
            if frame.TertiaryPowerBar then
                frame.TertiaryPowerBar:StopMovingOrSizing()
                frame.TertiaryPowerBar._editModeMoving = false
                if frame.TertiaryPowerBar.EditModeSelection then
                    frame.TertiaryPowerBar.EditModeSelection:Hide()
                end
            end
        end
    end

    self:RefreshAll(true)
end

-- Register game events for unit frames.
function UnitFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_DISABLED", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "PLAYER_UPDATE_RESTING", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PARTY_LEADER_CHANGED", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PLAYER_TARGET_CHANGED", self.OnTargetChanged)
    ns.EventRouter:Register(self, "PLAYER_FOCUS_CHANGED", self.OnFocusChanged)
    ns.EventRouter:Register(self, "PLAYER_STARTED_MOVING", self.OnPlayerMovement)
    ns.EventRouter:Register(self, "PLAYER_STOPPED_MOVING", self.OnPlayerMovement)
    ns.EventRouter:Register(self, "PLAYER_SPECIALIZATION_CHANGED", self.OnPlayerSpecializationChanged)
    ns.EventRouter:Register(self, "PLAYER_TALENT_UPDATE", self.OnPlayerSpecializationChanged)
    ns.EventRouter:Register(self, "UNIT_TARGET", self.OnUnitTarget)
    ns.EventRouter:Register(self, "UNIT_PET", self.OnUnitPet)
    ns.EventRouter:Register(self, "UNIT_HEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_MAXHEALTH", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_ABSORB_AMOUNT_CHANGED", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_POWER_UPDATE", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_MAXPOWER", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_DISPLAYPOWER", self.OnUnitEvent)
    ns.EventRouter:Register(self, "UNIT_NAME_UPDATE", self.OnUnitEvent)
    ns.EventRouter:Register(self, "RUNE_POWER_UPDATE", self.OnRunePowerUpdate)
    ns.EventRouter:Register(self, "UNIT_AURA", self.OnUnitAura)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_START", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_STOP", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_FAILED", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_INTERRUPTED", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_DELAYED", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_START", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_STOP", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_UPDATE", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_INTERRUPTIBLE", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", self.OnUnitCastEvent)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_SUCCEEDED", self.OnUnitSpellcastSucceeded)
end

-- Return whether this unit token is managed by secure visibility drivers.
function UnitFrames:IsDriverVisibilityUnit(unitToken)
    return DYNAMIC_VISIBILITY_DRIVERS[unitToken] ~= nil
end

-- Return whether live-mode conditions allow secure visibility driver ownership.
function UnitFrames:CanUseSecureDriverVisibility(unitToken, profile, unitConfig)
    if not self:IsDriverVisibilityUnit(unitToken) then
        return false
    end
    if type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function" then
        return false
    end
    if not profile or profile.enabled == false then
        return false
    end
    if not unitConfig or unitConfig.enabled == false then
        return false
    end
    if self.editModeActive or profile.testMode == true then
        return false
    end

    return true
end

-- Apply/unapply secure visibility driver state for one frame.
function UnitFrames:ApplyVisibilityDriver(frame, unitToken, shouldUseDriver)
    if not frame or not self:IsDriverVisibilityUnit(unitToken) then
        return
    end

    local driverExpr = DYNAMIC_VISIBILITY_DRIVERS[unitToken]
    local isActive = frame._mummuVisibilityDriverActive == true

    if shouldUseDriver then
        if isActive and frame._mummuVisibilityDriverExpr == driverExpr then
            frame._mummuVisibilityDriverDesired = nil
            frame._mummuVisibilityDriverDesiredExpr = nil
            return
        end

        if InCombatLockdown() then
            frame._mummuVisibilityDriverDesired = true
            frame._mummuVisibilityDriverDesiredExpr = driverExpr
            self.pendingDriverVisibilityRefresh = true
            return
        end

        if type(UnregisterStateDriver) == "function" then
            pcall(UnregisterStateDriver, frame, "visibility")
        end
        local okRegister = (type(RegisterStateDriver) == "function")
            and pcall(RegisterStateDriver, frame, "visibility", driverExpr)
        if okRegister then
            frame._mummuVisibilityDriverActive = true
            frame._mummuVisibilityDriverExpr = driverExpr
        else
            frame._mummuVisibilityDriverActive = false
            frame._mummuVisibilityDriverExpr = nil
        end
        frame._mummuVisibilityDriverDesired = nil
        frame._mummuVisibilityDriverDesiredExpr = nil
        return
    end

    if not isActive then
        frame._mummuVisibilityDriverDesired = nil
        frame._mummuVisibilityDriverDesiredExpr = nil
        return
    end

    if InCombatLockdown() then
        frame._mummuVisibilityDriverDesired = false
        frame._mummuVisibilityDriverDesiredExpr = nil
        self.pendingDriverVisibilityRefresh = true
        return
    end

    if type(UnregisterStateDriver) == "function" then
        pcall(UnregisterStateDriver, frame, "visibility")
    end
    frame._mummuVisibilityDriverActive = false
    frame._mummuVisibilityDriverExpr = nil
    frame._mummuVisibilityDriverDesired = nil
    frame._mummuVisibilityDriverDesiredExpr = nil
end

-- Reconcile secure visibility drivers for all dynamic units.
-- forceDisable=true unregisters drivers for every dynamic unit (used by disable/test flows).
function UnitFrames:RefreshVisibilityDrivers(forceDisable, profileOverride)
    if not self.frames then
        return
    end

    local profile = profileOverride or (self.dataHandle and self.dataHandle:GetProfile()) or nil
    for unitToken, _ in pairs(DYNAMIC_VISIBILITY_DRIVERS) do
        local frame = self.frames[unitToken]
        if frame then
            local shouldUseDriver = false
            if forceDisable ~= true and self.dataHandle then
                local unitConfig = self.dataHandle:GetUnitConfig(unitToken)
                shouldUseDriver = self:CanUseSecureDriverVisibility(unitToken, profile, unitConfig)
            end
            self:ApplyVisibilityDriver(frame, unitToken, shouldUseDriver)
        end
    end
end

-- Handle rune power update event.
function UnitFrames:OnRunePowerUpdate()
    self:RefreshFrame("player", false, REFRESH_OPTIONS_SECONDARY_POWER)
end

-- Handle player specialization changed event.
function UnitFrames:OnPlayerSpecializationChanged(_, unitToken)
    if unitToken ~= nil and unitToken ~= "player" then
        return
    end

    self:RefreshFrame("player", true)
end

-- Handle world event.
function UnitFrames:OnWorldEvent()
    self:RefreshAll(true)
end

-- Handle combat ended event.
function UnitFrames:OnCombatEnded()
    local needsRefreshAll = false
    if self.pendingDriverVisibilityRefresh then
        self.pendingDriverVisibilityRefresh = false
        needsRefreshAll = true
    end
    if self.pendingVisibilityRefresh then
        self.pendingVisibilityRefresh = false
        needsRefreshAll = true
    end

    if needsRefreshAll then
        self:RefreshAll()
        return
    end

    self:RefreshFrame("player")
end

-- Handle player status changed event. Nothing exploded yet.
function UnitFrames:OnPlayerStatusChanged(eventName)
    self:RefreshFrame("player")
end

-- Handle target changed event.
function UnitFrames:OnTargetChanged()
    self:RefreshFrame("target")
    self:RefreshFrame("targettarget")
end

-- Handle focus changed event.
function UnitFrames:OnFocusChanged()
    self:RefreshFrame("focus")
    self:RefreshFrame("focustarget")
end

-- Handle player movement updates.
function UnitFrames:OnPlayerMovement()
    local frame = self.frames and self.frames.target or nil
    if not frame or not self.dataHandle then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local previewMode = (profile and profile.testMode == true) or self.editModeActive
    self:RefreshTargetRangeAlpha(frame, UnitExists("target"), previewMode)
end

-- Handle unit event.
function UnitFrames:OnUnitEvent(_, unitToken)
    if SUPPORTED_UNITS[unitToken] then
        self:RefreshFrame(unitToken, false, REFRESH_OPTIONS_VITALS)
    end
end

-- Handle unit target event.
function UnitFrames:OnUnitTarget(_, unitToken)
    if unitToken == "target" then
        self:RefreshFrame("targettarget")
        return
    end

    if unitToken == "focus" then
        self:RefreshFrame("focustarget")
    end
end

-- Handle unit cast event.
function UnitFrames:OnUnitCastEvent(_, unitToken)
    if CASTBAR_UNITS[unitToken] then
        self:RefreshFrame(unitToken, false, REFRESH_OPTIONS_CASTBAR)
    end
end

-- Handle unit spellcast succeeded event.
function UnitFrames:OnUnitSpellcastSucceeded(_, unitToken, _, spellID)
    if unitToken ~= "player" or not spellIDMatches(spellID, IRONFUR_SPELL_ID) then
        return
    end

    local _, classToken = UnitClass("player")
    if classToken ~= "DRUID" or getPlayerSpecializationID() ~= GUARDIAN_SPEC_ID then
        return
    end

    local playerFrame = self.frames and self.frames.player or nil
    local bar = playerFrame and playerFrame.TertiaryPowerBar or nil
    if not bar then
        return
    end

    local now = GetTime()
    local activeStates = collectActiveGuardianStackStates(bar, now)
    activeStates[#activeStates + 1] = {
        duration = IRONFUR_BASE_DURATION,
        expirationTime = now + IRONFUR_BASE_DURATION,
    }
    bar._guardianStackStates = activeStates
    self:RefreshFrame("player", false, REFRESH_OPTIONS_TERTIARY_POWER)
end

-- Handle unit pet event.
function UnitFrames:OnUnitPet(_, unitToken)
    if unitToken == "player" then
        self:RefreshFrame("pet")
    end
end

local function shouldSkipPlayerAuraRefresh(auraUpdateInfo)
    if type(auraUpdateInfo) ~= "table" then
        return false
    end
    if auraUpdateInfo.isFullUpdate == true then
        return false
    end
    if not (AuraUtil and type(AuraUtil.ShouldSkipAuraUpdate) == "function") then
        return false
    end

    local function isRelevantAura()
        return true
    end

    local okModern, shouldSkipModern = pcall(AuraUtil.ShouldSkipAuraUpdate, auraUpdateInfo, isRelevantAura)
    if okModern and shouldSkipModern == true then
        return true
    end

    local updatedAuras = auraUpdateInfo.updatedAuras or auraUpdateInfo.addedAuras
    if updatedAuras ~= nil then
        local okLegacy, shouldSkipLegacy = pcall(
            AuraUtil.ShouldSkipAuraUpdate,
            auraUpdateInfo.isFullUpdate == true,
            updatedAuras,
            isRelevantAura
        )
        if okLegacy and shouldSkipLegacy == true then
            return true
        end
    end

    return false
end

-- Handle unit aura event.
function UnitFrames:OnUnitAura(_, unitToken, auraUpdateInfo)
    if not SUPPORTED_UNITS[unitToken] then
        return
    end

    local refreshOptions = REFRESH_OPTIONS_AURAS_ONLY
    if unitToken == "player" then
        if shouldSkipPlayerAuraRefresh(auraUpdateInfo) then
            return
        end
        refreshOptions = playerSecondaryPowerUsesAuraStacks() and REFRESH_OPTIONS_AURAS_AND_SECONDARY or REFRESH_OPTIONS_AURAS
    end
    self:RefreshFrame(unitToken, false, refreshOptions, auraUpdateInfo)
end

-- Create unit frame.
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
    frame._mummuVisibilityDriverActive = false
    frame._mummuVisibilityDriverExpr = nil
    frame._mummuVisibilityDriverDesired = nil
    frame._mummuVisibilityDriverDesiredExpr = nil
    self.frames[unitToken] = frame
    self:EnsureEditModeSelection(frame)
    return frame
end

-- Create player frame.
function UnitFrames:CreatePlayerFrame()
    return self:CreateUnitFrame("player")
end

-- Create pet frame.
function UnitFrames:CreatePetFrame()
    return self:CreateUnitFrame("pet")
end

-- Create target frame.
function UnitFrames:CreateTargetFrame()
    local frame = self:CreateUnitFrame("target")
    if frame and frame._mummuTargetRangeOnUpdateHooked ~= true then
        frame._mummuTargetRangeOnUpdateHooked = true
        frame._mummuTargetRangeElapsed = 0
        frame:HookScript("OnUpdate", function(targetFrame, elapsed)
            if not targetFrame:IsShown() then
                return
            end

            targetFrame._mummuTargetRangeElapsed = (targetFrame._mummuTargetRangeElapsed or 0) + (elapsed or 0)
            if targetFrame._mummuTargetRangeElapsed < 0.2 then
                return
            end
            targetFrame._mummuTargetRangeElapsed = 0

            if not self or not self.dataHandle then
                return
            end

            local profile = self.dataHandle:GetProfile()
            local previewMode = (profile and profile.testMode == true) or self.editModeActive
            self:RefreshTargetRangeAlpha(targetFrame, UnitExists("target"), previewMode)
        end)
    end
    return frame
end

-- Create target target frame.
function UnitFrames:CreateTargetTargetFrame()
    return self:CreateUnitFrame("targettarget")
end

-- Create focus frame.
function UnitFrames:CreateFocusFrame()
    return self:CreateUnitFrame("focus")
end

-- Create focus target frame.
function UnitFrames:CreateFocusTargetFrame()
    return self:CreateUnitFrame("focustarget")
end

-- Return blizzard unit frame.
function UnitFrames:GetBlizzardUnitFrame(unitToken)
    local frameName = BLIZZARD_FRAME_NAME_BY_UNIT[unitToken]
    if not frameName then
        return nil
    end

    return _G[frameName]
end

-- Set blizzard unit frame hidden.
function UnitFrames:SetBlizzardUnitFrameHidden(unitToken, shouldHide)
    local frame = self:GetBlizzardUnitFrame(unitToken)
    if not frame then
        return
    end

    if not frame._mummuHideInit then
        frame._mummuHideInit = true
        frame._mummuOriginalAlpha = frame:GetAlpha()
        if type(frame.IsMouseEnabled) == "function" then
            frame._mummuOriginalMouseEnabled = frame:IsMouseEnabled()
        end
    end

    if not frame._mummuHideHooked and type(frame.HookScript) == "function" then
        -- Apply ui update callback.
        frame:HookScript("OnShow", function(shownFrame)
            if shownFrame._mummuHideRequested then
                shownFrame:SetAlpha(0)
                if not InCombatLockdown() and type(shownFrame.EnableMouse) == "function" then
                    shownFrame:EnableMouse(false)
                end
            end
        end)
        frame._mummuHideHooked = true
    end

    frame._mummuHideRequested = shouldHide and true or false
    if shouldHide then
        frame:SetAlpha(0)
        if not InCombatLockdown() and type(frame.EnableMouse) == "function" then
            frame:EnableMouse(false)
        end
        return
    end

    frame:SetAlpha(frame._mummuOriginalAlpha or 1)
    if not InCombatLockdown() and type(frame.EnableMouse) == "function" then
        if frame._mummuOriginalMouseEnabled ~= nil then
            frame:EnableMouse(frame._mummuOriginalMouseEnabled)
        else
            frame:EnableMouse(true)
        end
    end
end

-- Restore all blizzard unit frames.
function UnitFrames:RestoreAllBlizzardUnitFrames()
    for unitToken in pairs(BLIZZARD_FRAME_NAME_BY_UNIT) do
        self:SetBlizzardUnitFrameHidden(unitToken, false)
    end
end

-- Create table holding blizzard castbar by unit.
local BLIZZARD_CASTBAR_BY_UNIT = {
    player = "PlayerCastingBarFrame",
    target = "TargetFrameSpellBar",
    focus = "FocusFrameSpellBar",
}

-- Set blizzard cast bar hidden.
function UnitFrames:SetBlizzardCastBarHidden(unitToken, shouldHide)
    local frameName = BLIZZARD_CASTBAR_BY_UNIT[unitToken]
    if not frameName then
        return
    end

    local frame = _G[frameName]
    if not frame then
        return
    end

    if not frame._mummuHideInit then
        frame._mummuHideInit = true
        frame._mummuOriginalAlpha = frame:GetAlpha()
    end

    if not frame._mummuHideHooked and type(frame.HookScript) == "function" then
        -- Apply ui update callback.
        pcall(frame.HookScript, frame, "OnShow", function(shownFrame)
            if shownFrame._mummuHideRequested then
                shownFrame:SetAlpha(0)
            end
        end)
        -- Apply ui update callback. Deadline still theoretical.
        pcall(frame.HookScript, frame, "OnUpdate", function(shownFrame)
            if shownFrame._mummuHideRequested then
                shownFrame:SetAlpha(0)
            end
        end)
        frame._mummuHideHooked = true
    end

    frame._mummuHideRequested = shouldHide and true or false
    if shouldHide then
        frame:SetAlpha(0)
    else
        frame:SetAlpha(frame._mummuOriginalAlpha or 1)
    end
end

-- Apply blizzard frame visibility.
function UnitFrames:ApplyBlizzardFrameVisibility()
    if not self.dataHandle then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local addonEnabled = profile and profile.enabled ~= false
    local hideBlizzardUnitsGlobal = addonEnabled and profile and profile.hideBlizzardUnitFrames == true

    for i = 1, #FRAME_ORDER do
        local unitToken = FRAME_ORDER[i]
        local unitConfig = self.dataHandle:GetUnitConfig(unitToken)
        local shouldHide = addonEnabled and (unitConfig.hideBlizzardFrame == true or (hideBlizzardUnitsGlobal and GLOBAL_HIDE_BLIZZARD_UNITS[unitToken] == true))
        self:SetBlizzardUnitFrameHidden(unitToken, shouldHide)

        if CASTBAR_UNITS[unitToken] then
            local castbarConfig = unitConfig.castbar or {}
            local shouldHideCastBar = addonEnabled and castbarConfig.hideBlizzardCastBar == true
            self:SetBlizzardCastBarHidden(unitToken, shouldHideCastBar)
        end
    end
end

-- Hide all managed unit frames.
function UnitFrames:HideAll()
    for _, frame in pairs(self.frames) do
        if frame then
            if frame.unitToken and self:IsDriverVisibilityUnit(frame.unitToken) then
                self:ApplyVisibilityDriver(frame, frame.unitToken, false)
            end
            self:SetFrameVisibility(frame, false, true)
            if frame.CastBar then
                stopCastBarTimer(frame.CastBar)
            end
            if frame.SecondaryPowerBar then
                frame.SecondaryPowerBar:Hide()
            end
            if frame.TertiaryPowerBar then
                hideTertiaryPowerBar(frame.TertiaryPowerBar)
            end
        end
    end
end

-- Set frame visibility.
function UnitFrames:SetFrameVisibility(frame, shouldShow, forceManualVisibility)
    if not frame then
        return
    end

    local profile = self.dataHandle and self.dataHandle:GetProfile() or nil
    local previewMode = self.editModeActive or (profile and profile.testMode == true)
    -- Driver-owned dynamic frames are shown/hidden by secure state handlers in
    -- live mode. Manual Show/Hide is skipped to avoid insecure combat mutations.
    if frame._mummuVisibilityDriverActive == true and not previewMode and not forceManualVisibility then
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

-- Refresh player status icons.
function UnitFrames:RefreshPlayerStatusIcons(frame, unitToken)
    if not frame or not frame.StatusIcons or not frame.StatusIconContainer then
        return
    end

    if unitToken ~= "player" then
        frame.StatusIconContainer:Hide()
        return
    end

    local profile = self.dataHandle and self.dataHandle:GetProfile() or nil
    local testMode = profile and profile.testMode == true
    local showResting = testMode or (IsResting() == true)
    local showLeader = testMode or (UnitIsGroupLeader("player") == true)
    local showCombat = testMode or (UnitAffectingCombat("player") == true)

    frame.StatusIcons.Resting:Hide()
    frame.StatusIcons.Leader:Hide()
    frame.StatusIcons.Combat:Hide()

    if showResting then
        frame.StatusIcons.Resting:ClearAllPoints()
        frame.StatusIcons.Resting:SetPoint("CENTER", frame.StatusIconContainer, "CENTER", 0, 0)
        frame.StatusIcons.Resting:Show()
    end

    if showLeader then
        frame.StatusIcons.Leader:ClearAllPoints()
        frame.StatusIcons.Leader:SetPoint("CENTER", frame, "TOPRIGHT", 0, 0)
        frame.StatusIcons.Leader:Show()
    end

    if showCombat then
        frame.StatusIcons.Combat:ClearAllPoints()
        frame.StatusIcons.Combat:SetPoint("CENTER", frame, "TOP", 0, 0)
        frame.StatusIcons.Combat:Show()
    end

    frame.StatusIconContainer:SetShown(showResting or showLeader or showCombat)
end

-- Hide secondary power bar.
local function hideSecondaryPowerBar(bar)
    if not bar then
        return
    end

    if bar.Icons then
        for i = 1, #bar.Icons do
            bar.Icons[i]:Hide()
        end
    end
    bar:Hide()
end

-- Stop tertiary power bar timer.
local function stopTertiaryPowerBarTimer(bar)
    if not bar then
        return
    end
    bar:SetScript("OnUpdate", nil)
    bar._timerActive = false
    bar._timerElapsed = 0
end

-- Hide tertiary power stack overlays.
local function hideTertiaryPowerStackOverlays(bar)
    if not bar then
        return
    end

    if type(bar.StackOverlays) == "table" then
        for i = 1, #bar.StackOverlays do
            bar.StackOverlays[i]:Hide()
        end
    end

    if type(bar.StackRightGlows) == "table" then
        for i = 1, #bar.StackRightGlows do
            bar.StackRightGlows[i]:Hide()
        end
    end
end

-- Set guardian right glow.
local function setGuardianRightGlow(bar, progress, alpha)
    if not (bar and bar.RightGlow and bar.Bar) then
        return
    end

    local resolvedProgress = Util:Clamp(tonumber(progress) or 0, 0, 1)
    local resolvedAlpha = Util:Clamp(tonumber(alpha) or 0, 0, 1)
    if resolvedAlpha <= 0 then
        bar.RightGlow:Hide()
        return
    end

    local barWidth = math.max(1, bar.Bar:GetWidth() or bar:GetWidth() or 1)
    local barHeight = math.max(1, (bar.Bar:GetHeight() or bar:GetHeight() or 1))
    local glowOffsetX = math.floor((barWidth * resolvedProgress) + 0.5)
    bar.RightGlow:ClearAllPoints()
    bar.RightGlow:SetPoint("CENTER", bar.Bar, "LEFT", glowOffsetX, 0)
    bar.RightGlow:SetSize(math.max(22, math.floor((barHeight * 2.2) + 0.5)), math.max(30, math.floor((barHeight * 3.0) + 0.5)))
    bar.RightGlow:SetVertexColor(0.82, 0.95, 1.00, resolvedAlpha)
    bar.RightGlow:Show()
end

-- Set guardian stack right glow.
local function setGuardianStackRightGlow(glow, parentBar, progress, alpha)
    if not (glow and parentBar) then
        return
    end

    local resolvedProgress = Util:Clamp(tonumber(progress) or 0, 0, 1)
    local resolvedAlpha = Util:Clamp(tonumber(alpha) or 0, 0, 1)
    if resolvedAlpha <= 0 then
        glow:Hide()
        return
    end

    local barWidth = math.max(1, parentBar:GetWidth() or 1)
    local barHeight = math.max(1, parentBar:GetHeight() or 1)
    local glowOffsetX = math.floor((barWidth * resolvedProgress) + 0.5)
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", parentBar, "LEFT", glowOffsetX, 0)
    glow:SetSize(math.max(20, math.floor((barHeight * 2.0) + 0.5)), math.max(27, math.floor((barHeight * 2.8) + 0.5)))
    glow:SetVertexColor(0.78, 0.93, 1.00, resolvedAlpha)
    glow:Show()
end

-- Hide tertiary power bar callback.
hideTertiaryPowerBar = function(bar)
    if not bar then
        return
    end
    stopTertiaryPowerBarTimer(bar)
    hideTertiaryPowerStackOverlays(bar)
    if bar.ValueText then
        bar.ValueText:SetText("")
    end
    if bar.Bar then
        setStatusBarValueSafe(bar.Bar, 0, 1)
    end
    if bar.OverlayBar then
        setStatusBarValueSafe(bar.OverlayBar, 0, 1)
        bar.OverlayBar:Show()
    end
    setGuardianRightGlow(bar, 0, 0)
    bar._guardianStackStates = nil
    bar:Hide()
end

-- Return rune power state.
local function getRunePowerState()
    local maxRunes = 6
    if type(GetNumRunes) == "function" then
        local count = tonumber(GetNumRunes())
        if count and count > 0 then
            maxRunes = math.floor(count + 0.5)
        end
    elseif _G.C_DeathKnight and type(_G.C_DeathKnight.GetNumRunes) == "function" then
        local okCount, count = pcall(_G.C_DeathKnight.GetNumRunes)
        if okCount then
            count = tonumber(count)
            if count and count > 0 then
                maxRunes = math.floor(count + 0.5)
            end
        end
    end
    maxRunes = Util:Clamp(maxRunes, 1, SECONDARY_POWER_MAX_ICONS)

    local runeCooldownFunc = nil
    if type(GetRuneCooldown) == "function" then
        runeCooldownFunc = GetRuneCooldown
    elseif _G.C_DeathKnight and type(_G.C_DeathKnight.GetRuneCooldown) == "function" then
        runeCooldownFunc = _G.C_DeathKnight.GetRuneCooldown
    end

    if not runeCooldownFunc then
        return nil, nil
    end

    local readyRunes = 0
    for runeIndex = 1, maxRunes do
        local ok, start, duration, runeReady = pcall(runeCooldownFunc, runeIndex)
        if ok then
            if type(start) == "table" then
                local runeInfo = start --[[@as any]]
                start = tonumber(runeInfo.startTime or runeInfo.start or runeInfo.cooldownStart) or 0
                duration = tonumber(runeInfo.duration or runeInfo.cooldownDuration) or 0
                runeReady = runeInfo.runeReady or runeInfo.isReady
            end
            if safeBool(runeReady) then
                readyRunes = readyRunes + 1
            elseif type(start) == "number" and type(duration) == "number" and duration <= 0 then
                readyRunes = readyRunes + 1
            end
        end
    end

    return readyRunes, maxRunes
end

-- Return safe numeric value.
local function getSafeNumericValue(value, fallback)
    if type(value) == "number" then
        local okString, asString = pcall(tostring, value)
        if okString and type(asString) == "string" then
            local parsed = tonumber(asString)
            if type(parsed) == "number" then
                return parsed
            end
        end
        return fallback
    end

    if type(value) == "string" then
        local parsed = tonumber(value)
        if type(parsed) == "number" then
            return parsed
        end
        return fallback
    end

    local okCoerced, coerced = pcall(tonumber, value)
    if okCoerced and type(coerced) == "number" then
        return coerced
    end

    return fallback
end

-- Collect active guardian stack states callback.
collectActiveGuardianStackStates = function(bar, now)
    -- Create table holding active states.
    local activeStates = {}
    local existingStates = bar and bar._guardianStackStates or nil
    if type(existingStates) ~= "table" then
        return activeStates
    end

    for i = 1, #existingStates do
        local state = existingStates[i]
        local duration = getSafeNumericValue(state and state.duration, 0) or 0
        local expirationTime = getSafeNumericValue(state and state.expirationTime, 0) or 0
        if duration > 0 and expirationTime > now then
            activeStates[#activeStates + 1] = {
                duration = duration,
                expirationTime = expirationTime,
            }
        end
    end

    return activeStates
end

-- Build guardian ironfur stack states.
local function buildGuardianIronfurStackStates(bar, exists, now, previewMode)
    -- Create table holding stack states.
    local stackStates = {}
    if exists then
        local ironfurAuras, queryRestricted = getAurasBySpellID("player", "HELPFUL|PLAYER", IRONFUR_SPELL_ID)
        if #ironfurAuras == 0 and queryRestricted == true and InCombatLockdown() then
            return collectActiveGuardianStackStates(bar, now)
        end
        if #ironfurAuras > 1 then
            for auraIndex = 1, #ironfurAuras do
                local auraData = ironfurAuras[auraIndex]
                local auraStacks = getSafeNumericValue(auraData and auraData.count, 1) or 1
                auraStacks = Util:Clamp(math.floor(auraStacks + 0.5), 1, 20)

                local duration = getSafeNumericValue(auraData and auraData.duration, 0) or 0
                local expirationTime = getSafeNumericValue(auraData and auraData.expirationTime, 0) or 0

                if duration <= 0 and expirationTime > now then
                    duration = expirationTime - now
                end
                if duration <= 0 then
                    duration = IRONFUR_BASE_DURATION
                end
                if expirationTime <= 0 then
                    expirationTime = now + duration
                end

                for stackIndex = 1, auraStacks do
                    stackStates[#stackStates + 1] = {
                        duration = duration,
                        expirationTime = expirationTime,
                    }
                end
            end
        elseif #ironfurAuras == 1 then
            local auraData = ironfurAuras[1]
            local auraStacks = getSafeNumericValue(auraData and auraData.count, 1) or 1
            auraStacks = Util:Clamp(math.floor(auraStacks + 0.5), 1, 20)

            local duration = getSafeNumericValue(auraData and auraData.duration, 0) or 0
            local expirationTime = getSafeNumericValue(auraData and auraData.expirationTime, 0) or 0

            if duration <= 0 and expirationTime > now then
                duration = expirationTime - now
            end
            if duration <= 0 then
                duration = IRONFUR_BASE_DURATION
            end
            if expirationTime <= 0 then
                expirationTime = now + duration
            end

            stackStates = collectActiveGuardianStackStates(bar, now)
            -- Return computed value.
            table.sort(stackStates, function(a, b)
                return (a.expirationTime or 0) < (b.expirationTime or 0)
            end)

            while #stackStates > auraStacks do
                table.remove(stackStates, 1)
            end

            while #stackStates < auraStacks do
                stackStates[#stackStates + 1] = {
                    duration = duration,
                    expirationTime = now + duration,
                }
            end

            local latestIndex = 1
            local latestExpiration = stackStates[1] and stackStates[1].expirationTime or 0
            for i = 2, #stackStates do
                local candidate = stackStates[i].expirationTime or 0
                if candidate > latestExpiration then
                    latestExpiration = candidate
                    latestIndex = i
                end
            end
            if latestIndex and expirationTime > 0 and latestExpiration < expirationTime then
                stackStates[latestIndex].expirationTime = expirationTime
            end

            for i = 1, #stackStates do
                if not stackStates[i].duration or stackStates[i].duration <= 0 then
                    stackStates[i].duration = duration
                end
            end
        end
    end

    if #stackStates == 0 and exists then
        stackStates = collectActiveGuardianStackStates(bar, now)
    end

    if #stackStates == 0 and previewMode then
        stackStates[1] = { duration = IRONFUR_BASE_DURATION, expirationTime = now + 4.8 }
        stackStates[2] = { duration = IRONFUR_BASE_DURATION, expirationTime = now + 2.6 }
    end

    return stackStates
end

-- Render guardian ironfur stacks. Coffee remains optional.
local function renderGuardianIronfurStacks(bar, now)
    local stackStates = bar and bar._guardianStackStates or nil
    if type(stackStates) ~= "table" or #stackStates == 0 then
        return false
    end

    -- Create table holding stack progress.
    local stackProgress = {}
    for i = 1, #stackStates do
        local state = stackStates[i]
        local duration = getSafeNumericValue(state and state.duration, 0) or 0
        local expirationTime = getSafeNumericValue(state and state.expirationTime, 0) or 0

        if duration <= 0 then
            duration = IRONFUR_BASE_DURATION
        end
        if expirationTime <= 0 then
            expirationTime = now + duration
            state.expirationTime = expirationTime
        end

        local remaining = expirationTime - now
        local progress = Util:Clamp(remaining / duration, 0, 1)
        if progress > 0 then
            stackProgress[#stackProgress + 1] = progress
        end
    end

    if #stackProgress == 0 then
        return false
    end

    -- Sort stack progress from longest to shortest.
    table.sort(stackProgress, function(a, b) return a > b end)
    local longestProgress = stackProgress[1] or 0

    setStatusBarValueSafe(bar.Bar, longestProgress, 1)
    bar.Bar:SetStatusBarColor(0.43, 0.68, 0.90, 0.94)
    if bar.OverlayBar then
        bar.OverlayBar:Hide()
    end

    local overlays = bar.StackOverlays or {}
    local stackGlows = bar.StackRightGlows or {}
    local width = math.max(1, (bar.Bar and bar.Bar:GetWidth()) or bar:GetWidth() or 1)
    local shownStacks = math.min(#stackProgress, #overlays)
    for i = 1, #overlays do
        local overlay = overlays[i]
        local stackGlow = stackGlows[i]
        if i <= shownStacks then
            local progress = stackProgress[i]
            local overlayWidth = math.max(1, math.floor((width * progress) + 0.5))
            local tintStep = Util:Clamp((i - 1) * 0.015, 0, 0.12)
            local overlayAlpha = Util:Clamp(0.24 + (0.07 * i), 0.24, 0.82)
            overlay:ClearAllPoints()
            overlay:SetPoint("TOPLEFT", bar.Bar, "TOPLEFT", 0, 0)
            overlay:SetPoint("BOTTOMLEFT", bar.Bar, "BOTTOMLEFT", 0, 0)
            overlay:SetWidth(overlayWidth)
            overlay:SetColorTexture(0.62 - tintStep, 0.80 - (tintStep * 0.55), 0.95 - (tintStep * 0.25), overlayAlpha)
            overlay:Show()

            if stackGlow then
                local glowAlpha = Util:Clamp(0.36 + (0.07 * i) + (progress * 0.18), 0.36, 0.96)
                setGuardianStackRightGlow(stackGlow, bar.Bar, progress, glowAlpha)
            end
        else
            overlay:Hide()
            if stackGlow then
                stackGlow:Hide()
            end
        end
    end
    for i = (#overlays + 1), #stackGlows do
        local stackGlow = stackGlows[i]
        if stackGlow then
            stackGlow:Hide()
        end
    end

    setGuardianRightGlow(bar, longestProgress, 0.62 + (longestProgress * 0.28))

    if bar.ValueText then
        bar.ValueText:SetText(string.format("%dx", #stackProgress))
    end

    return true
end

-- Show guardian empty tertiary bar.
local function showGuardianEmptyTertiaryBar(bar)
    stopTertiaryPowerBarTimer(bar)
    hideTertiaryPowerStackOverlays(bar)

    setStatusBarValueSafe(bar.Bar, 0, 1)
    bar.Bar:SetStatusBarColor(0.43, 0.68, 0.90, 0.94)
    if bar.OverlayBar then
        bar.OverlayBar:Hide()
    end
    setGuardianRightGlow(bar, 0, 0.22)
    if bar.ValueText then
        bar.ValueText:SetText("0x")
    end
    bar:Show()
end

-- Start guardian ironfur timer.
local function startGuardianIronfurTimer(bar)
    if not bar or bar._timerActive then
        return
    end

    bar._timerActive = true
    bar._timerElapsed = 0
    -- Handle OnUpdate script callback.
    bar:SetScript("OnUpdate", function(self, elapsed)
        self._timerElapsed = (self._timerElapsed or 0) + (elapsed or 0)
        if self._timerElapsed < 0.05 then
            return
        end
        self._timerElapsed = 0

        if not renderGuardianIronfurStacks(self, GetTime()) then
            showGuardianEmptyTertiaryBar(self)
            return
        end
    end)
end

-- Update guardian ironfur tertiary bar.
local function updateGuardianIronfurTertiaryBar(bar, exists, previewMode)
    local now = GetTime()
    bar._guardianStackStates = buildGuardianIronfurStackStates(bar, exists, now, previewMode)
    if type(bar._guardianStackStates) ~= "table" or #bar._guardianStackStates == 0 then
        showGuardianEmptyTertiaryBar(bar)
        return
    end

    if not renderGuardianIronfurStacks(bar, now) then
        showGuardianEmptyTertiaryBar(bar)
        return
    end

    if previewMode then
        stopTertiaryPowerBarTimer(bar)
    else
        startGuardianIronfurTimer(bar)
    end
    bar:Show()
end

-- Update monk stagger tertiary bar.
local function updateMonkStaggerTertiaryBar(bar, exists, previewMode)
    stopTertiaryPowerBarTimer(bar)
    hideTertiaryPowerStackOverlays(bar)
    setGuardianRightGlow(bar, 0, 0)

    local staggerAmount = 0
    local maxStagger = 1
    if exists and type(UnitStagger) == "function" then
        staggerAmount = UnitStagger("player") or 0
        maxStagger = UnitHealthMax("player") or 1
    elseif previewMode then
        staggerAmount = 32000
        maxStagger = 100000
    end

    staggerAmount = getSafeNumericValue(staggerAmount, previewMode and 32000 or 0) or 0
    maxStagger = getSafeNumericValue(maxStagger, previewMode and 100000 or 1) or 1
    if maxStagger <= 0 then
        maxStagger = 1
    end

    local progress = Util:Clamp(staggerAmount / maxStagger, 0, 1)
    if progress <= 0 and not previewMode then
        progress = 0
    end
    if progress <= 0 and previewMode then
        progress = 0.32
    end

    local r, g, b = 0.24, 0.78, 0.31
    if progress >= 0.6 then
        r, g, b = 0.86, 0.26, 0.22
    elseif progress >= 0.3 then
        r, g, b = 0.90, 0.70, 0.23
    end

    setStatusBarValueSafe(bar.Bar, progress, 1)
    bar.Bar:SetStatusBarColor(r, g, b, 0.95)
    if bar.OverlayBar then
        bar.OverlayBar:Show()
    end
    setStatusBarValueSafe(bar.OverlayBar, progress, 1)
    bar.OverlayBar:SetStatusBarColor(1, 1, 1, TERTIARY_STAGGER_EMPTY_ALPHA)

    if bar.ValueText then
        bar.ValueText:SetText(string.format("%.0f%%", progress * 100))
    end

    bar:Show()
end

-- Refresh secondary power bar.
function UnitFrames:RefreshSecondaryPowerBar(frame, unitToken, exists, previewMode)
    local bar = frame and frame.SecondaryPowerBar or nil
    if not bar then
        return
    end

    if unitToken ~= "player" or bar._enabled == false then
        hideSecondaryPowerBar(bar)
        return
    end

    local _, classToken = UnitClass("player")
    local specID = getPlayerSpecializationID()
    local resource = classToken and SECONDARY_POWER_BY_CLASS[classToken] or nil
    if not resource or not isSecondaryResourceSupportedForSpec(resource, specID) then
        hideSecondaryPowerBar(bar)
        return
    end

    local maxIcons = Util:Clamp(resource.maxIcons or 5, 1, SECONDARY_POWER_MAX_ICONS)
    local powerCap = Util:Clamp(resource.powerCap or maxIcons, 1, SECONDARY_POWER_MAX_ICONS)
    local current = 0
    local maxPower = 0
    if exists and resource.usesRuneCooldownAPI then
        local readyRunes, maxRunes = getRunePowerState()
        if readyRunes and maxRunes then
            current = readyRunes
            maxPower = maxRunes
        else
            current = UnitPower("player", resource.powerType) or 0
            maxPower = UnitPowerMax("player", resource.powerType) or 0
        end
    elseif exists and resource.usesAuraStacks == true and type(resource.auraSpellID) == "number" then
        local auraStacks = 0
        local matchedAuras, queryRestricted = getAurasBySpellID("player", resource.auraFilter or "HELPFUL|PLAYER", resource.auraSpellID)
        for auraIndex = 1, #matchedAuras do
            local auraData = matchedAuras[auraIndex]
            local stacks = getSafeNumericValue(auraData and auraData.count, 1) or 1
            stacks = Util:Clamp(math.floor(stacks + 0.5), 1, powerCap)
            if stacks > auraStacks then
                auraStacks = stacks
            end
        end
        if #matchedAuras == 0 and queryRestricted == true and InCombatLockdown() then
            auraStacks = getSafeNumericValue(bar._lastSecondaryPowerCurrent, 0) or 0
        end
        current = auraStacks
        maxPower = powerCap
    elseif exists then
        current = UnitPower("player", resource.powerType) or 0
        maxPower = UnitPowerMax("player", resource.powerType) or 0
    end

    local fallbackMaxPower = bar._lastSecondaryPowerMax or powerCap
    local fallbackCurrent = bar._lastSecondaryPowerCurrent or 0
    maxPower = getSafeNumericValue(maxPower, fallbackMaxPower)
    current = getSafeNumericValue(current, fallbackCurrent)

    if maxPower <= 0 then
        maxPower = powerCap
    end

    if previewMode then
        if current <= 0 then
            current = math.min(3, maxPower)
        end
    end

    maxPower = Util:Clamp(math.floor((maxPower or 0) + 0.0001), 0, powerCap)
    current = Util:Clamp(math.floor((current or 0) + 0.0001), 0, maxPower)
    bar._lastSecondaryPowerMax = maxPower
    bar._lastSecondaryPowerCurrent = current

    local displayMaxPower = maxPower
    if type(resource.displayMaxIcons) == "number" then
        displayMaxPower = Util:Clamp(math.floor(resource.displayMaxIcons + 0.5), 1, maxIcons)
    else
        displayMaxPower = Util:Clamp(displayMaxPower, 1, maxIcons)
    end

    local displayCurrent = Util:Clamp(current, 0, displayMaxPower)
    local overflowCount = 0
    if resource.overflowTexture and current > displayMaxPower then
        overflowCount = Util:Clamp(current - displayMaxPower, 0, displayMaxPower)
    end

    local availableWidth = math.max(1, bar:GetWidth() or 1)
    local availableHeight = math.max(1, bar:GetHeight() or 1)
    local spacing = (Style and type(Style.GetPixelSize) == "function" and Style:GetPixelSize()) or 1
    if not Style or type(Style.IsPixelPerfectEnabled) ~= "function" or not Style:IsPixelPerfectEnabled() then
        spacing = 2
    end

    local iconSize = math.floor(
        math.min(availableHeight, (availableWidth - (spacing * math.max(0, displayMaxPower - 1))) / displayMaxPower) + 0.5
    )
    if iconSize < 1 then
        iconSize = 1
    end

    local rowWidth = (iconSize * displayMaxPower) + (spacing * math.max(0, displayMaxPower - 1))
    local startX = math.floor(((availableWidth - rowWidth) * 0.5) + 0.5)
    if startX < 0 then
        startX = 0
    end

    local texturePath = resource.texture or DEFAULT_AURA_TEXTURE
    local overflowTexturePath = resource.overflowTexture
    for i = 1, #bar.Icons do
        local icon = bar.Icons[i]
        if i <= displayMaxPower then
            if overflowTexturePath and i <= overflowCount then
                icon:SetTexture(overflowTexturePath)
            else
                icon:SetTexture(texturePath)
            end
            icon:SetAlpha(i <= displayCurrent and 1 or SECONDARY_POWER_EMPTY_ALPHA)
            icon:SetSize(iconSize, iconSize)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", bar, "LEFT", startX + ((i - 1) * (iconSize + spacing)), 0)
            icon:Show()
        else
            icon:Hide()
        end
    end

    bar:Show()
end

-- Refresh tertiary power bar.
function UnitFrames:RefreshTertiaryPowerBar(frame, unitToken, exists, previewMode)
    local bar = frame and frame.TertiaryPowerBar or nil
    if not bar then
        return
    end

    if unitToken ~= "player" or bar._enabled == false then
        hideTertiaryPowerBar(bar)
        return
    end

    local _, classToken = UnitClass("player")
    local specID = getPlayerSpecializationID()
    if classToken == "DRUID" and specID == GUARDIAN_SPEC_ID then
        updateGuardianIronfurTertiaryBar(bar, exists, previewMode)
        return
    end

    if classToken == "MONK" and specID == BREWMASTER_SPEC_ID then
        updateMonkStaggerTertiaryBar(bar, exists, previewMode)
        return
    end

    hideTertiaryPowerBar(bar)
end

-- Start cast bar timer.
local function startCastBarTimer(castBar)
    if castBar._timerActive then
        return
    end
    castBar._timerActive = true
    -- Handle OnUpdate script callback.
    castBar:SetScript("OnUpdate", function(self, _)
        local nowMs = GetTime() * 1000
        self.Bar:SetValue(nowMs)

        local endClean = self._castEndClean
        if endClean and endClean > 0 then
            local remaining = math.max(0, (endClean - nowMs) / 1000)
            self.TimeText:SetText(string.format("%.1fs", remaining))
            if nowMs >= endClean then
                self:SetScript("OnUpdate", nil)
                self._timerActive = false
                self:Hide()
            end
        else
            self.TimeText:SetText("")
        end
    end)
end

-- Stop cast bar timer.
local function stopCastBarTimer(castBar)
    castBar:SetScript("OnUpdate", nil)
    castBar._timerActive = false
    castBar:Hide()
end

-- Refresh cast bar.
function UnitFrames:RefreshCastBar(frame, unitToken, exists, previewMode)
    if not frame.CastBar then
        return
    end

    local castBar = frame.CastBar
    if not castBar._enabled then
        stopCastBarTimer(castBar)
        return
    end

    if not exists and not self.editModeActive then
        stopCastBarTimer(castBar)
        return
    end

    if self.editModeActive then
        castBar.Bar:SetMinMaxValues(0, 1)
        castBar.Bar:SetReverseFill(false)
        castBar.Bar:SetValue(0.6)
        castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NORMAL[1], CASTBAR_COLOR_NORMAL[2], CASTBAR_COLOR_NORMAL[3], 1)
        castBar.SpellText:SetText(unitToken == "player" and UnitName("player") or L.UNIT_TEST_TARGET)
        castBar.TimeText:SetText("")
        castBar.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        castBar:SetScript("OnUpdate", nil)
        castBar._timerActive = false
        castBar:Show()
        return
    end

    local spellName, _, iconTexture, startTimeMs, endTimeMs, _, _, notInterruptible
    if type(UnitCastingInfo) == "function" then
        spellName, _, iconTexture, startTimeMs, endTimeMs, _, _, notInterruptible = UnitCastingInfo(unitToken)
    end

    if spellName then
        castBar.Bar:SetMinMaxValues(startTimeMs, endTimeMs)
        castBar.Bar:SetReverseFill(false)
        castBar._castEndClean = getSafeNumericValue(endTimeMs, 0) or 0
        castBar.SpellText:SetText(spellName)
        castBar.Icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        if safeBool(notInterruptible) then
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NOINTERRUPT[1], CASTBAR_COLOR_NOINTERRUPT[2], CASTBAR_COLOR_NOINTERRUPT[3], 1)
        else
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NORMAL[1], CASTBAR_COLOR_NORMAL[2], CASTBAR_COLOR_NORMAL[3], 1)
        end

        castBar:Show()
        startCastBarTimer(castBar)
        return
    end

    local channelName, _, channelIcon, channelStartMs, channelEndMs, _, channelNotInterruptible
    if type(UnitChannelInfo) == "function" then
        channelName, _, channelIcon, channelStartMs, channelEndMs, _, channelNotInterruptible = UnitChannelInfo(unitToken)
    end

    if channelName then
        castBar.Bar:SetMinMaxValues(channelStartMs, channelEndMs)
        castBar.Bar:SetReverseFill(true)
        castBar._castEndClean = getSafeNumericValue(channelEndMs, 0) or 0
        castBar.SpellText:SetText(channelName)
        castBar.Icon:SetTexture(channelIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

        if safeBool(channelNotInterruptible) then
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NOINTERRUPT[1], CASTBAR_COLOR_NOINTERRUPT[2], CASTBAR_COLOR_NOINTERRUPT[3], 1)
        else
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NORMAL[1], CASTBAR_COLOR_NORMAL[2], CASTBAR_COLOR_NORMAL[3], 1)
        end

        castBar:Show()
        startCastBarTimer(castBar)
        return
    end

    stopCastBarTimer(castBar)
end

-- Ensure detached element edit mode selection.
function UnitFrames:EnsureDetachedElementEditModeSelection(element, labelText, borderColor, onDragStop)
    if not element or element.EditModeSelection then
        return
    end

    -- Create frame for selection.
    local selection = CreateFrame("Frame", nil, element) --[[@as mummuEditModeSelection]]
    -- Create texture for border.
    local border = selection:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 0.55)
    selection._fallbackBorder = border

    -- Create font string for label.
    local label = selection:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", 0, 10)
    label:SetTextColor(1, 1, 1, 1)
    Style:ApplyFont(label, 11, "OUTLINE")
    label:SetText(labelText or "Detached")
    selection.Label = label

    selection:SetAllPoints(element)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection:SetClampedToScreen(true)
    selection:SetFrameStrata("DIALOG")
    selection:SetFrameLevel(element:GetFrameLevel() + 30)

    -- Handle OnDragStart script callback. Bug parade continues.
    selection:SetScript("OnDragStart", function()
        if not self.editModeActive or InCombatLockdown() then
            return
        end
        element:SetMovable(true)
        element:StartMoving()
        element._editModeMoving = true

        if EditModeManagerFrame and type(EditModeManagerFrame.SetSnapPreviewFrame) == "function" then
            pcall(EditModeManagerFrame.SetSnapPreviewFrame, EditModeManagerFrame, element)
        end
    end)

    -- Handle OnDragStop script callback.
    selection:SetScript("OnDragStop", function()
        if not element._editModeMoving then
            return
        end
        element:StopMovingOrSizing()
        element._editModeMoving = false

        if EditModeManagerFrame and type(EditModeManagerFrame.ClearSnapPreviewFrame) == "function" then
            pcall(EditModeManagerFrame.ClearSnapPreviewFrame, EditModeManagerFrame)
        end

        if EditModeManagerFrame
            and type(EditModeManagerFrame.IsSnapEnabled) == "function"
            and EditModeManagerFrame:IsSnapEnabled()
            and EditModeMagnetismManager
            and type(EditModeMagnetismManager.ApplyMagnetism) == "function"
        then
            pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, element)
        end

        if onDragStop then
            onDragStop()
        end
    end)

    selection.parentFrame = element
    element.Selection = selection
    ensureEditModeMagnetismAPI(element)
    element.EditModeSelection = selection
    selection:Hide()
end

-- Return detached element offsets.
local function getDetachedElementOffsets(element)
    local centerX, centerY = element:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not centerX or not centerY or not parentX or not parentY then
        return nil, nil
    end

    local offsetX = centerX - parentX
    local offsetY = centerY - parentY
    local pixel = (Style and Style.GetPixelSize and Style:GetPixelSize()) or 1
    local centerSnapThreshold = 10 * pixel
    if math.abs(offsetX) <= centerSnapThreshold then
        offsetX = 0
    end
    if math.abs(offsetY) <= centerSnapThreshold then
        offsetY = 0
    end

    if Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled() then
        offsetX = Style:Snap(offsetX)
        offsetY = Style:Snap(offsetY)
    else
        offsetX = math.floor(offsetX + 0.5)
        offsetY = math.floor(offsetY + 0.5)
    end

    return offsetX, offsetY
end

-- Ensure primary power bar edit mode selection.
function UnitFrames:EnsurePrimaryPowerBarEditModeSelection(frame)
    if not frame or frame.unitToken ~= "player" or not frame.PowerBar then
        return
    end

    local labelText = (TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame") .. " Primary Power"
    self:EnsureDetachedElementEditModeSelection(
        frame.PowerBar,
        labelText,
        { 0.42, 0.74, 0.95, 0.55 },
        -- Save updated position.
        function() self:SavePrimaryPowerBarAnchorFromEditMode(frame) end
    )
end

-- Save primary power bar anchor from edit mode.
function UnitFrames:SavePrimaryPowerBarAnchorFromEditMode(frame)
    if not frame or frame.unitToken ~= "player" or not frame.PowerBar or not self.dataHandle then
        return
    end

    local offsetX, offsetY = getDetachedElementOffsets(frame.PowerBar)
    if offsetX == nil or offsetY == nil then
        return
    end

    self.dataHandle:SetUnitConfig(frame.unitToken, "primaryPower.x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "primaryPower.y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Ensure cast bar edit mode selection.
function UnitFrames:EnsureCastBarEditModeSelection(frame)
    if not frame or not frame.CastBar then
        return
    end

    local labelText = (TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame") .. " Cast Bar"
    self:EnsureDetachedElementEditModeSelection(
        frame.CastBar,
        labelText,
        { 0.98, 0.74, 0.29, 0.55 },
        -- Save updated position.
        function() self:SaveCastBarAnchorFromEditMode(frame) end
    )
end

-- Save cast bar anchor from edit mode.
function UnitFrames:SaveCastBarAnchorFromEditMode(frame)
    if not frame or not frame.CastBar or not self.dataHandle or not frame.unitToken then
        return
    end

    local offsetX, offsetY = getDetachedElementOffsets(frame.CastBar)
    if offsetX == nil or offsetY == nil then
        return
    end

    self.dataHandle:SetUnitConfig(frame.unitToken, "castbar.x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "castbar.y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Ensure secondary power bar edit mode selection.
function UnitFrames:EnsureSecondaryPowerBarEditModeSelection(frame)
    if not frame or not frame.SecondaryPowerBar then
        return
    end

    local labelText = (TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame") .. " Secondary Power"
    self:EnsureDetachedElementEditModeSelection(
        frame.SecondaryPowerBar,
        labelText,
        { 0.38, 0.85, 0.62, 0.55 },
        -- Save updated position.
        function() self:SaveSecondaryPowerBarAnchorFromEditMode(frame) end
    )
end

-- Save secondary power bar anchor from edit mode.
function UnitFrames:SaveSecondaryPowerBarAnchorFromEditMode(frame)
    if not frame or not frame.SecondaryPowerBar or not self.dataHandle or not frame.unitToken then
        return
    end

    local offsetX, offsetY = getDetachedElementOffsets(frame.SecondaryPowerBar)
    if offsetX == nil or offsetY == nil then
        return
    end

    self.dataHandle:SetUnitConfig(frame.unitToken, "secondaryPower.x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "secondaryPower.y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Ensure tertiary power bar edit mode selection.
function UnitFrames:EnsureTertiaryPowerBarEditModeSelection(frame)
    if not frame or not frame.TertiaryPowerBar then
        return
    end

    local labelText = (TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame") .. " Tertiary Power"
    self:EnsureDetachedElementEditModeSelection(
        frame.TertiaryPowerBar,
        labelText,
        { 0.89, 0.55, 0.27, 0.55 },
        -- Save updated position.
        function() self:SaveTertiaryPowerBarAnchorFromEditMode(frame) end
    )
end

-- Save tertiary power bar anchor from edit mode.
function UnitFrames:SaveTertiaryPowerBarAnchorFromEditMode(frame)
    if not frame or not frame.TertiaryPowerBar or not self.dataHandle or not frame.unitToken then
        return
    end

    local offsetX, offsetY = getDetachedElementOffsets(frame.TertiaryPowerBar)
    if offsetX == nil or offsetY == nil then
        return
    end

    self.dataHandle:SetUnitConfig(frame.unitToken, "tertiaryPower.x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "tertiaryPower.y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Refresh all managed unit frames.
function UnitFrames:RefreshAll(forceLayout)
    self:ApplyBlizzardFrameVisibility()

    local profile = self.dataHandle:GetProfile()
    self:RefreshVisibilityDrivers(false, profile)
    local testMode = profile and profile.testMode == true
    if profile.enabled == false and not self.editModeActive and not testMode then
        -- Return computed value.
        Util:RunWhenOutOfCombat(function()
            self:HideAll()
        end, L.CONFIG_DEFERRED_APPLY, "unitframes_hide_all")
        return
    end

    for i = 1, #FRAME_ORDER do
        self:RefreshFrame(FRAME_ORDER[i], forceLayout)
    end
end

-- Refresh one managed unit frame.
function UnitFrames:RefreshFrame(unitToken, forceLayout, refreshOptions, auraUpdateInfo)
    local frame = self.frames[unitToken]
    if not frame then
        return
    end

    local options = refreshOptions or REFRESH_OPTIONS_FULL

    local profile = self.dataHandle:GetProfile()
    local testMode = profile and profile.testMode == true
    local unitConfig = self.dataHandle:GetUnitConfig(unitToken)
    if self:IsDriverVisibilityUnit(unitToken) then
        local shouldUseDriver = self:CanUseSecureDriverVisibility(unitToken, profile, unitConfig)
        self:ApplyVisibilityDriver(frame, unitToken, shouldUseDriver)
    end
    if unitConfig.enabled == false and not self.editModeActive and not testMode then
        if options.castbar and frame.CastBar then
            stopCastBarTimer(frame.CastBar)
        end
        if options.secondaryPower and frame.SecondaryPowerBar then
            hideSecondaryPowerBar(frame.SecondaryPowerBar)
        end
        if options.tertiaryPower and frame.TertiaryPowerBar then
            hideTertiaryPowerBar(frame.TertiaryPowerBar)
        end
        if options.visibility then
            self:SetFrameVisibility(frame, false)
        end
        return
    end

    if forceLayout then
        self.globalFrames:ApplyStyle(frame, unitToken)
    end

    local previewMode = testMode or self.editModeActive
    local exists = UnitExists(unitToken)

    if options.visibility and not exists and not previewMode and unitToken ~= "player" then
        if options.castbar and frame.CastBar then
            stopCastBarTimer(frame.CastBar)
        end
        if options.secondaryPower and frame.SecondaryPowerBar then
            hideSecondaryPowerBar(frame.SecondaryPowerBar)
        end
        if options.tertiaryPower and frame.TertiaryPowerBar then
            hideTertiaryPowerBar(frame.TertiaryPowerBar)
        end
        self:SetFrameVisibility(frame, false)
        return
    end

    if options.vitals then
        local name
        local health
        local maxHealth
        local power
        local maxPower

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
        updateAbsorbOverlay(frame, unitToken, exists, health, maxHealth, previewMode)

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
            if okPercent and type(rawPercent) == "number" then
                healthPercent = rawPercent
            end
        elseif not exists and previewMode then
            healthPercent = 100
        end
        local okHealthText, formattedHealthText = pcall(string.format, "%.0f%%", healthPercent)
        frame.HealthText:SetText(okHealthText and formattedHealthText or "0%")

        if unitToken == "target" then
            self:RefreshTargetRangeAlpha(frame, exists, previewMode)
        end
    end

    if options.statusIcons then
        self:RefreshPlayerStatusIcons(frame, unitToken)
    end
    if options.secondaryPower then
        self:RefreshSecondaryPowerBar(frame, unitToken, exists, previewMode)
    end
    if options.tertiaryPower then
        self:RefreshTertiaryPowerBar(frame, unitToken, exists, previewMode)
    end
    if options.castbar and CASTBAR_UNITS[unitToken] then
        self:RefreshCastBar(frame, unitToken, exists, previewMode)
    end
    if options.visibility then
        self:SetFrameVisibility(frame, true)
    end
end

addon:RegisterModule("unitFrames", UnitFrames:New())
