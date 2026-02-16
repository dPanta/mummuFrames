local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Style = ns.Style
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
-- Map unit tokens to Blizzard frame globals that can be visually hidden.
local BLIZZARD_FRAME_NAME_BY_UNIT = {
    player = "PlayerFrame",
    pet = "PetFrame",
    target = "TargetFrame",
    targettarget = "TargetFrameToT",
    focus = "FocusFrame",
    focustarget = "FocusFrameToT",
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
-- Aura filters keyed by the config section names.
local AURA_FILTER_BY_SECTION = {
    buffs = "HELPFUL",
    debuffs = "HARMFUL",
}
-- Use a built-in icon when previewing aura slots without live data.
local DEFAULT_AURA_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Hard stop for aura scanning to avoid unbounded loops.
local MAX_AURA_SCAN = 40

-- Strip Blizzard taint from a secret number by round-tripping through a string.
local function detaintNumber(value)
    return tonumber(tostring(value)) or 0
end

-- Cast bar color constants.
local CASTBAR_COLOR_NORMAL = { 0.29, 0.52, 0.90 }
local CASTBAR_COLOR_NOINTERRUPT = { 0.63, 0.63, 0.63 }

-- Units that support cast bars.
local CASTBAR_UNITS = {
    player = true,
    target = true,
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

-- Update absorb overlay using an overlay status bar to avoid secret-value math in Lua.
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

-- Normalize API differences between modern aura data and legacy UnitAura returns.
local function normalizeAuraData(auraData)
    if type(auraData) ~= "table" then
        return nil
    end

    local icon = auraData.icon or auraData.iconFileID or auraData.texture
    if not icon then
        return nil
    end

    return {
        icon = icon,
        count = auraData.applications or auraData.charges or auraData.count,
        duration = auraData.duration,
        expirationTime = auraData.expirationTime,
        debuffType = auraData.dispelName or auraData.debuffType,
    }
end

-- Read one aura entry safely from the active API available on this client.
local function getAuraDataByIndex(unitToken, index, filter)
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
        local normalized = normalizeAuraData(auraData)
        if normalized then
            return normalized
        end
    end

    if type(UnitAura) == "function" then
        local _, icon, count, debuffType, duration, expirationTime = UnitAura(unitToken, index, filter)
        if icon then
            return {
                icon = icon,
                count = count,
                duration = duration,
                expirationTime = expirationTime,
                debuffType = debuffType,
            }
        end
    end

    return nil
end

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

-- Expose the API shape used by EditMode magnetism/snap manager.
local function ensureEditModeMagnetismAPI(frame)
    if not frame or frame._mummuHasMagnetismAPI then
        return
    end

    frame._mummuHasMagnetismAPI = true
    local SELECTION_PADDING = 2

    if not frame.GetScaledSelectionCenter then
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
        function frame:GetScaledCenter()
            local cx, cy = self:GetCenter()
            local scale = self:GetScale() or 1
            return (cx or 0) * scale, (cy or 0) * scale
        end
    end

    if not frame.GetScaledSelectionSides then
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
        function frame:GetLeftOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(4, self.Selection:GetPoint(1)) or 0) - SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetRightOffset then
        function frame:GetRightOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(4, self.Selection:GetPoint(2)) or 0) + SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetTopOffset then
        function frame:GetTopOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(5, self.Selection:GetPoint(1)) or 0) + SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetBottomOffset then
        function frame:GetBottomOffset()
            if self.Selection and self.Selection.GetPoint then
                return (select(5, self.Selection:GetPoint(2)) or 0) - SELECTION_PADDING
            end
            return 0
        end
    end

    if not frame.GetSelectionOffset then
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
        function frame:SnapToFrame(frameInfo)
            local offsetX, offsetY = self:GetSnapOffsets(frameInfo)
            self:ClearAllPoints()
            self:SetPoint(frameInfo.point, frameInfo.frame, frameInfo.relativePoint, offsetX, offsetY)
        end
    end

    if not frame.IsFrameAnchoredToMe then
        function frame:IsFrameAnchoredToMe(other)
            return isFrameAnchoredTo(other, self)
        end
    end

    if not frame.IsToTheLeftOfFrame then
        function frame:IsToTheLeftOfFrame(other)
            local _, myRight = self:GetScaledSelectionSides()
            local otherLeft = select(1, other:GetScaledSelectionSides())
            return myRight < otherLeft
        end
    end

    if not frame.IsToTheRightOfFrame then
        function frame:IsToTheRightOfFrame(other)
            local myLeft = select(1, self:GetScaledSelectionSides())
            local otherRight = select(2, other:GetScaledSelectionSides())
            return myLeft > otherRight
        end
    end

    if not frame.IsAboveFrame then
        function frame:IsAboveFrame(other)
            local _, _, myBottom = self:GetScaledSelectionSides()
            local _, _, _, otherTop = other:GetScaledSelectionSides()
            return myBottom > otherTop
        end
    end

    if not frame.IsBelowFrame then
        function frame:IsBelowFrame(other)
            local _, _, _, myTop = self:GetScaledSelectionSides()
            local _, _, otherBottom = other:GetScaledSelectionSides()
            return myTop < otherBottom
        end
    end

    if not frame.IsVerticallyAlignedWithFrame then
        function frame:IsVerticallyAlignedWithFrame(other)
            local _, _, myBottom, myTop = self:GetScaledSelectionSides()
            local _, _, otherBottom, otherTop = other:GetScaledSelectionSides()
            return (myTop >= otherBottom) and (myBottom <= otherTop)
        end
    end

    if not frame.IsHorizontallyAlignedWithFrame then
        function frame:IsHorizontallyAlignedWithFrame(other)
            local myLeft, myRight = self:GetScaledSelectionSides()
            local otherLeft, otherRight = other:GetScaledSelectionSides()
            return (myRight >= otherLeft) and (myLeft <= otherRight)
        end
    end

    if not frame.GetFrameMagneticEligibility then
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

-- Set up module state and frame cache.
function UnitFrames:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.globalFrames = nil
    self.frames = {}
    self.pendingVisibilityRefresh = false
    self.editModeActive = false
    self.editModeCallbacksRegistered = false
end

-- Store a reference to the addon during initialization.
function UnitFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Create frames, subscribe events, and force an initial refresh.
function UnitFrames:OnEnable()
    self.dataHandle = self.addon:GetModule("dataHandle")
    self.globalFrames = self.addon:GetModule("globalFrames")
    self:RegisterEditModeCallbacks()
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame:IsShown()) and true or false

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
    self:UnregisterEditModeCallbacks()
    self.editModeActive = false
    self:RestoreAllBlizzardUnitFrames()
    self:HideAll()
end

-- Subscribe to Blizzard Edit Mode enter/exit callbacks once.
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

-- Unsubscribe from Edit Mode callbacks.
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

-- Build one native-style selection overlay used during Edit Mode.
function UnitFrames:EnsureEditModeSelection(frame)
    if not frame or frame.EditModeSelection then
        return
    end

    -- Avoid EditModeSystemSelectionTemplate here; it expects Blizzard system wiring.
    local selection = CreateFrame("Frame", nil, frame)
    local border = selection:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.29, 0.74, 0.98, 0.55)
    selection._fallbackBorder = border

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

    selection:SetScript("OnDragStart", function(sel)
        self:BeginEditModeDrag(sel.parentFrame or frame)
    end)
    selection:SetScript("OnDragStop", function(sel)
        self:EndEditModeDrag(sel.parentFrame or frame)
    end)

    selection.parentFrame = frame
    frame.Selection = selection
    frame.EditModeSelection = selection
    ensureEditModeMagnetismAPI(frame)
    selection:Hide()
end

-- Start dragging a frame while Edit Mode is active.
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

-- Save dragged frame position back to unit config and end drag state.
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

-- Persist moved frame anchor into the addon's unit config.
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

-- Enter native Edit Mode preview state for all supported frames.
function UnitFrames:OnEditModeEnter()
    self.editModeActive = true

    for _, frame in pairs(self.frames) do
        if frame then
            self:EnsureEditModeSelection(frame)
            frame:SetMovable(true)
            frame:EnableMouse(false)
            if frame.EditModeSelection then
                frame.EditModeSelection:Show()
            end
            -- Show cast bar edit overlay (draggable only when detached).
            if frame.CastBar and frame.CastBar._enabled then
                if frame.CastBar._detached then
                    self:EnsureCastBarEditModeSelection(frame)
                    frame.CastBar:SetMovable(true)
                    if frame.CastBar.EditModeSelection then
                        frame.CastBar.EditModeSelection:Show()
                    end
                end
            end
        end
    end

    self:RefreshAll(true)
end

-- Exit native Edit Mode preview state and return to normal behavior.
function UnitFrames:OnEditModeExit()
    self.editModeActive = false

    for _, frame in pairs(self.frames) do
        if frame then
            frame:StopMovingOrSizing()
            frame._editModeMoving = false
            frame:EnableMouse(true)
            if frame.EditModeSelection then
                frame.EditModeSelection:Hide()
            end
            -- Hide cast bar edit overlay.
            if frame.CastBar then
                frame.CastBar:StopMovingOrSizing()
                frame.CastBar._editModeMoving = false
                if frame.CastBar.EditModeSelection then
                    frame.CastBar.EditModeSelection:Hide()
                end
            end
        end
    end

    self:RefreshAll(true)
end

-- Register all world and unit events needed to keep frames current.
function UnitFrames:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnWorldEvent)
    ns.EventRouter:Register(self, "PLAYER_REGEN_DISABLED", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnCombatEnded)
    ns.EventRouter:Register(self, "PLAYER_UPDATE_RESTING", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PARTY_LEADER_CHANGED", self.OnPlayerStatusChanged)
    ns.EventRouter:Register(self, "PLAYER_TARGET_CHANGED", self.OnTargetChanged)
    ns.EventRouter:Register(self, "PLAYER_FOCUS_CHANGED", self.OnFocusChanged)
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
end

-- Refresh all frames after world login/loading events.
function UnitFrames:OnWorldEvent()
    self:RefreshAll(true)
end

-- Apply deferred visibility updates after combat lockdown ends.
function UnitFrames:OnCombatEnded()
    if self.pendingVisibilityRefresh then
        self.pendingVisibilityRefresh = false
        self:RefreshAll()
    end

    self:RefreshFrame("player")
end

-- Refresh player frame badges when resting or leadership state changes.
function UnitFrames:OnPlayerStatusChanged()
    self:RefreshFrame("player")
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

-- Handle all cast-related events for player and target.
function UnitFrames:OnUnitCastEvent(_, unitToken)
    if CASTBAR_UNITS[unitToken] then
        local frame = self.frames[unitToken]
        if frame and frame.CastBar then
            self:RefreshCastBar(frame, unitToken, UnitExists(unitToken), false)
        end
    end
end

-- Refresh the pet frame when the player's pet unit changes.
function UnitFrames:OnUnitPet(_, unitToken)
    if unitToken == "player" then
        self:RefreshFrame("pet")
    end
end

-- Refresh aura rows only for the unit that fired a UNIT_AURA update.
function UnitFrames:OnUnitAura(_, unitToken)
    if not SUPPORTED_UNITS[unitToken] then
        return
    end

    local frame = self.frames[unitToken]
    if not frame then
        return
    end

    local profile = self.dataHandle and self.dataHandle:GetProfile() or nil
    local previewMode = (profile and profile.testMode == true) or self.editModeActive
    local unitConfig = self.dataHandle and self.dataHandle:GetUnitConfig(unitToken) or nil
    self:RefreshAuras(frame, unitToken, UnitExists(unitToken), previewMode, unitConfig)
end

-- Create one aura icon frame with texture, stack count, and cooldown swipe.
function UnitFrames:CreateAuraIcon(parent)
    local icon = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    icon:SetFrameStrata(parent:GetFrameStrata())
    icon:SetFrameLevel(parent:GetFrameLevel() + 1)
    icon:Hide()

    if type(icon.SetBackdrop) == "function" then
        icon:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        icon:SetBackdropColor(0, 0, 0, 0.92)
        icon:SetBackdropBorderColor(0, 0, 0, 0.95)
    end

    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetPoint("TOPLEFT", 1, -1)
    icon.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon.Icon)
    if type(icon.Cooldown.SetDrawBling) == "function" then
        icon.Cooldown:SetDrawBling(false)
    end
    if type(icon.Cooldown.SetDrawEdge) == "function" then
        icon.Cooldown:SetDrawEdge(false)
    end
    if type(icon.Cooldown.SetHideCountdownNumbers) == "function" then
        icon.Cooldown:SetHideCountdownNumbers(true)
    end

    icon.CountText = icon:CreateFontString(nil, "OVERLAY")
    icon.CountText:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.CountText:SetJustifyH("RIGHT")
    Style:ApplyFont(icon.CountText, 10, "OUTLINE")
    icon.CountText:SetTextColor(1, 1, 1, 1)
    icon.CountText:SetShadowColor(0, 0, 0, 0)
    icon.CountText:SetShadowOffset(0, 0)

    return icon
end

-- Lazily create and return aura icons from a per-container pool.
function UnitFrames:GetAuraIcon(container, index)
    if not container or index < 1 then
        return nil
    end

    container.icons = container.icons or {}
    if not container.icons[index] then
        container.icons[index] = self:CreateAuraIcon(container)
    end

    return container.icons[index]
end

-- Build buff/debuff containers once for a unit frame.
function UnitFrames:EnsureAuraContainers(frame)
    if not frame or frame.AuraContainers then
        return
    end

    local buffs = CreateFrame("Frame", nil, frame)
    buffs:SetFrameStrata("MEDIUM")
    buffs:SetFrameLevel(frame:GetFrameLevel() + 20)
    buffs.icons = {}
    buffs:Hide()

    local debuffs = CreateFrame("Frame", nil, frame)
    debuffs:SetFrameStrata("MEDIUM")
    debuffs:SetFrameLevel(frame:GetFrameLevel() + 20)
    debuffs.icons = {}
    debuffs:Hide()

    frame.AuraContainers = {
        buffs = buffs,
        debuffs = debuffs,
    }

    -- Pre-create the full icon pool so combat updates only reuse existing widgets.
    for i = 1, 16 do
        self:GetAuraIcon(buffs, i)
        self:GetAuraIcon(debuffs, i)
    end
    self:HideUnusedAuraIcons(buffs, 0)
    self:HideUnusedAuraIcons(debuffs, 0)
end

-- Apply per-unit aura anchors, sizes, scale, and icon limits from profile config.
function UnitFrames:ApplyAuraLayout(frame, unitConfig)
    if not (frame and frame.AuraContainers and unitConfig) then
        return
    end

    local auraConfig = unitConfig.aura or {}
    local pixelPerfect = Style:IsPixelPerfectEnabled()
    local auraEnabled = auraConfig.enabled ~= false

    for sectionName, container in pairs(frame.AuraContainers) do
        local sectionConfig = auraConfig[sectionName] or {}
        local anchorPoint = sectionConfig.anchorPoint
            or (sectionName == "buffs" and "TOPLEFT" or "TOPRIGHT")
        local relativePoint = sectionConfig.relativePoint
            or (sectionName == "buffs" and "BOTTOMLEFT" or "BOTTOMRIGHT")
        local x = tonumber(sectionConfig.x) or 0
        local y = tonumber(sectionConfig.y) or -4
        local size = Util:Clamp(tonumber(sectionConfig.size) or 18, 10, 48)
        local scale = Util:Clamp(tonumber(sectionConfig.scale) or 1, 0.5, 2)
        local maxIcons = Util:Clamp(math.floor((tonumber(sectionConfig.max) or 8) + 0.5), 1, 16)
        local spacing = pixelPerfect and Style:GetPixelSize() or 1

        if pixelPerfect then
            x = Style:Snap(x)
            y = Style:Snap(y)
            size = math.max(spacing, Style:Snap(size))
        else
            x = math.floor(x + 0.5)
            y = math.floor(y + 0.5)
            size = math.max(1, math.floor(size + 0.5))
        end

        container:ClearAllPoints()
        container:SetPoint(anchorPoint, frame, relativePoint, x, y)
        container:SetScale(scale)
        container:SetSize((size * maxIcons) + ((maxIcons - 1) * spacing), size)
        container.iconSize = size
        container.spacing = spacing
        container.maxIcons = maxIcons
        container.growFromRight = string.find(anchorPoint, "RIGHT", 1, true) ~= nil
        container.enabled = auraEnabled and (sectionConfig.enabled ~= false)
        container.source = sectionName == "buffs" and (sectionConfig.source == "self" and "self" or "all") or nil
    end
end

-- Apply one aura's texture, stack count, cooldown, and border color.
function UnitFrames:ApplyAuraToIcon(container, sectionName, auraIndex, auraData)
    local icon = self:GetAuraIcon(container, auraIndex)
    if not icon then
        return
    end

    local iconSize = container.iconSize or 18
    local spacing = container.spacing or 1
    local offset = (auraIndex - 1) * (iconSize + spacing)

    icon:SetSize(iconSize, iconSize)
    icon:ClearAllPoints()
    if container.growFromRight then
        icon:SetPoint("RIGHT", container, "RIGHT", -offset, 0)
    else
        icon:SetPoint("LEFT", container, "LEFT", offset, 0)
    end

    icon.Icon:SetTexture(auraData.icon or DEFAULT_AURA_TEXTURE)

    local okSetCount = pcall(icon.CountText.SetText, icon.CountText, auraData.count)
    if not okSetCount then
        icon.CountText:SetText("")
    end
    Style:ApplyFont(icon.CountText, math.max(8, math.floor((iconSize * 0.55) + 0.5)), "OUTLINE")

    -- Aura time values can be secret in combat, so avoid Lua-side math/comparisons here.
    if type(CooldownFrame_Clear) == "function" then
        CooldownFrame_Clear(icon.Cooldown)
    else
        icon.Cooldown:SetCooldown(0, 0)
    end
    icon.Cooldown:Hide()

    if type(icon.SetBackdropBorderColor) == "function" then
        if sectionName == "debuffs" and DebuffTypeColor then
            local color = DebuffTypeColor[auraData.debuffType] or DebuffTypeColor.none
            if color then
                icon:SetBackdropBorderColor(color.r, color.g, color.b, 1)
            else
                icon:SetBackdropBorderColor(0.92, 0.2, 0.2, 1)
            end
        else
            icon:SetBackdropBorderColor(0, 0, 0, 0.95)
        end
    end

    icon:Show()
end

-- Hide unused aura icon slots so stale icons are never left on screen.
function UnitFrames:HideUnusedAuraIcons(container, usedIcons)
    if not (container and container.icons) then
        return
    end

    for i = usedIcons + 1, #container.icons do
        container.icons[i]:Hide()
    end
end

-- Refresh one aura section (buffs or debuffs) from live data or preview placeholders.
function UnitFrames:RefreshAuraSection(frame, unitToken, sectionName, exists, previewMode)
    local container = frame and frame.AuraContainers and frame.AuraContainers[sectionName]
    if not container then
        return
    end

    if container.enabled == false then
        container:Hide()
        self:HideUnusedAuraIcons(container, 0)
        return
    end

    if not exists and not previewMode then
        container:Hide()
        self:HideUnusedAuraIcons(container, 0)
        return
    end

    local maxIcons = container.maxIcons or 8
    local shown = 0
    local filter = AURA_FILTER_BY_SECTION[sectionName] or "HELPFUL"
    if sectionName == "buffs" and container.source == "self" then
        filter = filter .. "|PLAYER"
    end

    if exists then
        for index = 1, MAX_AURA_SCAN do
            if shown >= maxIcons then
                break
            end

            local auraData = getAuraDataByIndex(unitToken, index, filter)
            if not auraData then
                break
            end

            shown = shown + 1
            self:ApplyAuraToIcon(container, sectionName, shown, auraData)
        end
    elseif previewMode then
        local previewCount = math.min(maxIcons, sectionName == "buffs" and 3 or 2)
        for index = 1, previewCount do
            shown = shown + 1
            self:ApplyAuraToIcon(container, sectionName, shown, {
                icon = DEFAULT_AURA_TEXTURE,
                count = index == 1 and 2 or 0,
                duration = 0,
                expirationTime = 0,
                debuffType = sectionName == "debuffs" and (index == 1 and "Magic" or "Poison") or nil,
            })
        end
    end

    self:HideUnusedAuraIcons(container, shown)
    container:SetShown(shown > 0)
end

-- Refresh both buff and debuff rows for one unit frame.
function UnitFrames:RefreshAuras(frame, unitToken, exists, previewMode, unitConfig)
    if not frame then
        return
    end

    self:EnsureAuraContainers(frame)
    self:ApplyAuraLayout(frame, unitConfig or self.dataHandle:GetUnitConfig(unitToken))
    self:RefreshAuraSection(frame, unitToken, "buffs", exists, previewMode)
    self:RefreshAuraSection(frame, unitToken, "debuffs", exists, previewMode)
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
    self:EnsureAuraContainers(frame)
    self.frames[unitToken] = frame
    self:EnsureEditModeSelection(frame)
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

-- Return the Blizzard unit frame mapped to a unit token, if available.
function UnitFrames:GetBlizzardUnitFrame(unitToken)
    local frameName = BLIZZARD_FRAME_NAME_BY_UNIT[unitToken]
    if not frameName then
        return nil
    end

    return _G[frameName]
end

-- Apply visual hide/show state for one Blizzard unit frame.
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

-- Restore all supported Blizzard unit frames to their original visual state.
function UnitFrames:RestoreAllBlizzardUnitFrames()
    for unitToken in pairs(BLIZZARD_FRAME_NAME_BY_UNIT) do
        self:SetBlizzardUnitFrameHidden(unitToken, false)
    end
end

-- Map unit tokens to Blizzard cast bar global names.
local BLIZZARD_CASTBAR_BY_UNIT = {
    player = "PlayerCastingBarFrame",
    target = "TargetFrameSpellBar",
}

-- Apply visual hide/show for a Blizzard cast bar frame.
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
        -- Hook both OnShow and OnUpdate to catch Blizzard alpha resets.
        frame:HookScript("OnShow", function(shownFrame)
            if shownFrame._mummuHideRequested then
                shownFrame:SetAlpha(0)
            end
        end)
        frame:HookScript("OnUpdate", function(shownFrame)
            if shownFrame._mummuHideRequested and shownFrame:GetAlpha() > 0 then
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

-- Apply hide/show settings for all Blizzard unit frames based on unit options.
function UnitFrames:ApplyBlizzardFrameVisibility()
    if not self.dataHandle then
        return
    end

    local profile = self.dataHandle:GetProfile()
    local addonEnabled = profile and profile.enabled ~= false

    for i = 1, #FRAME_ORDER do
        local unitToken = FRAME_ORDER[i]
        local unitConfig = self.dataHandle:GetUnitConfig(unitToken)
        local shouldHide = addonEnabled and unitConfig.hideBlizzardFrame == true
        self:SetBlizzardUnitFrameHidden(unitToken, shouldHide)

        -- Hide Blizzard cast bars when configured.
        if CASTBAR_UNITS[unitToken] then
            local castbarConfig = unitConfig.castbar or {}
            local shouldHideCastBar = addonEnabled and castbarConfig.hideBlizzardCastBar == true
            self:SetBlizzardCastBarHidden(unitToken, shouldHideCastBar)
        end
    end
end

-- Hide all cached unit frames.
function UnitFrames:HideAll()
    for _, frame in pairs(self.frames) do
        if frame then
            self:SetFrameVisibility(frame, false)
            if frame.CastBar then
                stopCastBarTimer(frame.CastBar)
            end
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

-- Update player-only status icons anchored to frame corners/edges.
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
        -- Anchor crown icon center to the frame's top-right corner.
        frame.StatusIcons.Leader:SetPoint("CENTER", frame, "TOPRIGHT", 0, 0)
        frame.StatusIcons.Leader:Show()
    end

    if showCombat then
        frame.StatusIcons.Combat:ClearAllPoints()
        -- Anchor swords icon center to the frame's top-center point.
        frame.StatusIcons.Combat:SetPoint("CENTER", frame, "TOP", 0, 0)
        frame.StatusIcons.Combat:Show()
    end

    frame.StatusIconContainer:SetShown(showResting or showLeader or showCombat)
end

-- Start the OnUpdate timer to animate the cast bar progress.
local function startCastBarTimer(castBar)
    if castBar._timerActive then
        return
    end
    castBar._timerActive = true
    castBar:SetScript("OnUpdate", function(self, _)
        if not self._castEnd or not self._castStart then
            return
        end

        local now = GetTime()
        local duration = self._castEnd - self._castStart
        if duration <= 0 then
            return
        end

        local elapsed = now - self._castStart
        local progress

        if self._channeling then
            progress = 1 - (elapsed / duration)
        else
            progress = elapsed / duration
        end

        progress = math.max(0, math.min(1, progress))
        self.Bar:SetValue(progress)

        local remaining = math.max(0, self._castEnd - now)
        local okFmt, text = pcall(string.format, "%.1fs", remaining)
        self.TimeText:SetText(okFmt and text or "")

        if now >= self._castEnd then
            self:SetScript("OnUpdate", nil)
            self._timerActive = false
            self:Hide()
        end
    end)
end

-- Stop the OnUpdate timer and hide the cast bar.
local function stopCastBarTimer(castBar)
    castBar:SetScript("OnUpdate", nil)
    castBar._timerActive = false
    castBar:Hide()
end

-- Refresh one frame's cast bar state from current casting/channeling info.
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

    -- In edit mode, show a static preview bar so the user can see placement.
    if self.editModeActive then
        castBar.Bar:SetMinMaxValues(0, 1)
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

    -- Check for active cast or channel.
    local spellName, _, iconTexture, startTimeMs, endTimeMs, _, _, notInterruptible
    if type(UnitCastingInfo) == "function" then
        spellName, _, iconTexture, startTimeMs, endTimeMs, _, _, notInterruptible = UnitCastingInfo(unitToken)
    end

    if spellName then
        castBar._castStart = detaintNumber(startTimeMs) / 1000
        castBar._castEnd = detaintNumber(endTimeMs) / 1000
        castBar._channeling = false
        castBar.SpellText:SetText(spellName)
        castBar.Icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        if tostring(notInterruptible) == "true" then
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NOINTERRUPT[1], CASTBAR_COLOR_NOINTERRUPT[2], CASTBAR_COLOR_NOINTERRUPT[3], 1)
        else
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NORMAL[1], CASTBAR_COLOR_NORMAL[2], CASTBAR_COLOR_NORMAL[3], 1)
        end

        castBar:Show()
        startCastBarTimer(castBar)
        return
    end

    -- Check for channel.
    local channelName, _, channelIcon, channelStartMs, channelEndMs, _, channelNotInterruptible
    if type(UnitChannelInfo) == "function" then
        channelName, _, channelIcon, channelStartMs, channelEndMs, _, channelNotInterruptible = UnitChannelInfo(unitToken)
    end

    if channelName then
        castBar._castStart = detaintNumber(channelStartMs) / 1000
        castBar._castEnd = detaintNumber(channelEndMs) / 1000
        castBar._channeling = true
        castBar.SpellText:SetText(channelName)
        castBar.Icon:SetTexture(channelIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

        if tostring(channelNotInterruptible) == "true" then
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NOINTERRUPT[1], CASTBAR_COLOR_NOINTERRUPT[2], CASTBAR_COLOR_NOINTERRUPT[3], 1)
        else
            castBar.Bar:SetStatusBarColor(CASTBAR_COLOR_NORMAL[1], CASTBAR_COLOR_NORMAL[2], CASTBAR_COLOR_NORMAL[3], 1)
        end

        castBar:Show()
        startCastBarTimer(castBar)
        return
    end

    -- No active cast or channel.
    stopCastBarTimer(castBar)
end

-- Create an Edit Mode selection overlay for a detached cast bar.
function UnitFrames:EnsureCastBarEditModeSelection(frame)
    local castBar = frame.CastBar
    if not castBar or castBar.EditModeSelection then
        return
    end

    local selection = CreateFrame("Frame", nil, castBar)
    local border = selection:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.98, 0.74, 0.29, 0.55)
    selection._fallbackBorder = border

    local label = selection:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", 0, 10)
    label:SetTextColor(1, 1, 1, 1)
    Style:ApplyFont(label, 11, "OUTLINE")
    local labelText = (TEST_NAME_BY_UNIT[frame.unitToken] or frame.unitToken or "Frame") .. " Cast Bar"
    label:SetText(labelText)
    selection.Label = label

    selection:SetAllPoints(castBar)
    selection:EnableMouse(true)
    selection:RegisterForDrag("LeftButton")
    selection:SetClampedToScreen(true)
    selection:SetFrameStrata("DIALOG")
    selection:SetFrameLevel(castBar:GetFrameLevel() + 30)

    selection:SetScript("OnDragStart", function()
        if not self.editModeActive or InCombatLockdown() then
            return
        end
        castBar:SetMovable(true)
        castBar:StartMoving()
        castBar._editModeMoving = true
    end)

    selection:SetScript("OnDragStop", function()
        if not castBar._editModeMoving then
            return
        end
        castBar:StopMovingOrSizing()
        castBar._editModeMoving = false
        self:SaveCastBarAnchorFromEditMode(frame)
    end)

    castBar.EditModeSelection = selection
    selection:Hide()
end

-- Persist moved cast bar position into the addon's unit config.
function UnitFrames:SaveCastBarAnchorFromEditMode(frame)
    if not frame or not frame.CastBar or not self.dataHandle or not frame.unitToken then
        return
    end

    local castBar = frame.CastBar
    local centerX, centerY = castBar:GetCenter()
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

    self.dataHandle:SetUnitConfig(frame.unitToken, "castbar.x", offsetX)
    self.dataHandle:SetUnitConfig(frame.unitToken, "castbar.y", offsetY)
    self:RefreshFrame(frame.unitToken, true)
end

-- Refresh every supported frame, or hide all when addon is disabled.
function UnitFrames:RefreshAll(forceLayout)
    self:ApplyBlizzardFrameVisibility()

    local profile = self.dataHandle:GetProfile()
    if profile.enabled == false and not self.editModeActive then
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
    if unitConfig.enabled == false and not self.editModeActive then
        self:SetFrameVisibility(frame, false)
        return
    end

    if forceLayout then
        self.globalFrames:ApplyStyle(frame, unitToken)
    end

    local profile = self.dataHandle:GetProfile()
    local testMode = profile.testMode == true
    local previewMode = testMode or self.editModeActive
    local exists = UnitExists(unitToken)

    -- Hide missing non-player units unless test mode is enabled.
    if not exists and not previewMode and unitToken ~= "player" then
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
    updateAbsorbOverlay(frame, unitToken, exists, health, maxHealth, previewMode)

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
        if okPercent and type(rawPercent) == "number" then
            healthPercent = rawPercent
        end
    elseif not exists and previewMode then
        healthPercent = 100
    end
    local okHealthText, formattedHealthText = pcall(string.format, "%.0f%%", healthPercent)
    frame.HealthText:SetText(okHealthText and formattedHealthText or "0%")

    self:RefreshAuras(frame, unitToken, exists, previewMode, unitConfig)
    self:RefreshPlayerStatusIcons(frame, unitToken)
    if CASTBAR_UNITS[unitToken] then
        self:RefreshCastBar(frame, unitToken, exists, previewMode)
    end
    self:SetFrameVisibility(frame, true)
end

addon:RegisterModule("unitFrames", UnitFrames:New())
