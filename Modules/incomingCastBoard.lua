-- ============================================================================
-- MUMMUFRAMES INCOMING CAST BOARD MODULE
-- ============================================================================
-- Tracks enemy nameplate casts that currently target the player or a party
-- member. The flow mirrors Danders' post-hotfix list approach:
--   * no spell whitelist
--   * delayed pickup after UNIT_SPELLCAST_START
--   * no exact party-member resolution
--   * render-time use of secret-safe sinks for spell/target metadata
-- ============================================================================

local _, ns = ...

local addon = _G.mummuFrames
local Object = ns.Object
local Style = ns.Style
local Util = ns.Util

local IncomingCastBoard = Object:Extend()

local PICKUP_DELAY_SECONDS = 0.2
local NORMAL_FADE_SECONDS = 0.25
local INTERRUPTED_FADE_SECONDS = 1.0
local FADE_TICK_SECONDS = 0.05
local SAFETY_CHECK_SECONDS = 5.0
local BOARD_MIN_WIDTH = 180
local BOARD_MAX_WIDTH = 420
local BOARD_DEFAULT_WIDTH = 248
local BOARD_MIN_HEIGHT = 18
local BOARD_MAX_HEIGHT = 32
local BOARD_DEFAULT_HEIGHT = 24
local BOARD_SPACING = 4
local BOARD_MAX_SPACING = 12
local BOARD_DEFAULT_FONT_SIZE = 13
local BOARD_MIN_FONT_SIZE = 9
local BOARD_MAX_FONT_SIZE = 20
local BOARD_MAX_ROWS = 10
local BOARD_VERTICAL_BASE_OFFSET_X = 14
local BOARD_VERTICAL_BASE_OFFSET_Y = 0
local BOARD_HORIZONTAL_BASE_OFFSET_X = 0
local BOARD_HORIZONTAL_BASE_OFFSET_Y = -12
local BOARD_DETACHED_DEFAULT_X = 0
local BOARD_DETACHED_DEFAULT_Y = -140
local BOARD_EDIT_MODE_PREVIEW_ROWS = 2
local ROW_BACKGROUND_COLOR = { 0.03, 0.04, 0.05, 0.94 }
local ROW_BACKGROUND_COLOR_DARK = { 0.10, 0.11, 0.12, 0.96 }
local ROW_BORDER_COLOR = { 1.00, 1.00, 1.00, 0.14 }
local ROW_BORDER_COLOR_DARK = { 1.00, 1.00, 1.00, 0.18 }
local ICON_BACKGROUND_COLOR = { 0.02, 0.03, 0.04, 0.92 }
local INTERRUPTIBLE_BAR_COLOR = { r = 0.98, g = 0.42, b = 0.16, a = 0.82 }
local UNINTERRUPTIBLE_BAR_COLOR = { r = 0.52, g = 0.56, b = 0.62, a = 0.78 }
local SELF_TARGET_OVERLAY_COLOR = { 1.00, 0.84, 0.16, 0.14 }
local IMPORTANT_GLOW_COLOR = { 1.00, 0.84, 0.26, 0.90 }
local INTERRUPTED_FLASH_COLOR = { r = 1.00, g = 0.96, b = 0.32, a = 1.00 }
local EDIT_MODE_SELECTION_COLOR = { 0.98, 0.72, 0.22, 0.55 }
local DEFAULT_CAST_ICON_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local STATUSBAR_INTERPOLATION_IMMEDIATE = (_G.Enum and _G.Enum.StatusBarInterpolation and _G.Enum.StatusBarInterpolation.Immediate) or 0
local STATUSBAR_TIMER_DIRECTION_ELAPSED = (_G.Enum and _G.Enum.StatusBarTimerDirection and _G.Enum.StatusBarTimerDirection.ElapsedTime) or 0
local STATUSBAR_TIMER_DIRECTION_REMAINING = (_G.Enum and _G.Enum.StatusBarTimerDirection and _G.Enum.StatusBarTimerDirection.RemainingTime) or 1
local CLASS_COLORS = _G.C_ClassColor
local SPELL_API = _G.C_Spell

local TEST_CAST_RECORDS = {
    {
        casterUnit = "__test1",
        spellName = "Shadow Bolt",
        spellTexture = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
        spellId = 0,
        isChannel = false,
        uninterruptible = false,
        testTargetName = "Lightweaver",
        testTargetClass = "PRIEST",
    },
    {
        casterUnit = "__test2",
        spellName = "Blast Wave",
        spellTexture = "Interface\\Icons\\Spell_Holy_Excorcism_02",
        spellId = 0,
        isChannel = false,
        uninterruptible = true,
        testTargetName = "Ironbark",
        testTargetClass = "WARRIOR",
    },
    {
        casterUnit = "__test3",
        spellName = "Drain Life",
        spellTexture = "Interface\\Icons\\Spell_Shadow_LifeDrain02",
        spellId = 0,
        isChannel = true,
        uninterruptible = false,
        testTargetName = "Frostwyn",
        testTargetClass = "MAGE",
    },
}

local function clamp(value, minimum, maximum)
    local numericValue = tonumber(value) or minimum
    if Util and type(Util.Clamp) == "function" then
        return Util:Clamp(numericValue, minimum, maximum)
    end
    return math.max(minimum, math.min(maximum, numericValue))
end

local function clearTable(target)
    if type(target) ~= "table" then
        return
    end
    for key in pairs(target) do
        target[key] = nil
    end
end

local function safeUnitExists(unitToken)
    return type(unitToken) == "string" and unitToken ~= "" and UnitExists(unitToken) == true
end

local function safeUnitCanAttack(attackerUnit, unitToken)
    return type(unitToken) == "string" and unitToken ~= "" and UnitCanAttack(attackerUnit, unitToken) == true
end

local function safeUnitInParty(unitToken)
    return type(unitToken) == "string" and unitToken ~= "" and UnitInParty(unitToken) == true
end

local function isNameplateUnit(unitToken)
    return type(unitToken) == "string" and string.match(unitToken, "^nameplate%d+$") ~= nil
end

local function isRelevantCasterUnit(casterUnit)
    if not isNameplateUnit(casterUnit) then
        return false
    end
    if not safeUnitExists(casterUnit) then
        return false
    end
    if not safeUnitCanAttack("player", casterUnit) then
        return false
    end
    if safeUnitInParty(casterUnit) then
        return false
    end
    return true
end

local function isTrackedFriendlyTarget(casterUnit)
    local targetUnit = casterUnit .. "target"
    if not safeUnitExists(targetUnit) then
        return false
    end
    if safeUnitCanAttack("player", targetUnit) then
        return false
    end

    -- Match the Danders-safe post-hotfix filter shape:
    -- in a group, require UnitInParty("nameplateXtarget");
    -- outside a group, accept any non-hostile target rather than branching on
    -- UnitIsUnit(..., "player"), which can return a secret boolean here.
    if IsInGroup() and not safeUnitInParty(targetUnit) then
        return false
    end

    return true
end

local function getLiveCastDuration(casterUnit)
    if type(UnitCastingDuration) == "function" then
        local duration = UnitCastingDuration(casterUnit)
        if duration ~= nil then
            return duration
        end
    end
    if type(UnitChannelDuration) == "function" then
        return UnitChannelDuration(casterUnit)
    end
    return nil
end

local function getLiveCastTexture(casterUnit, isChannel)
    if isChannel == true and type(UnitChannelInfo) == "function" then
        return select(3, UnitChannelInfo(casterUnit))
    end
    if type(UnitCastingInfo) == "function" then
        local texture = select(3, UnitCastingInfo(casterUnit))
        if texture ~= nil then
            return texture
        end
    end
    if type(UnitChannelInfo) == "function" then
        return select(3, UnitChannelInfo(casterUnit))
    end
    return nil
end

-- Normalize interruptibility flags so secret booleans never leak into `and/or`.
local function resolveBooleanLikeSafe(value, fallback)
    if Util and type(Util.NormalizeBooleanLike) == "function" then
        local normalizedValue = Util:NormalizeBooleanLike(value)
        if normalizedValue ~= nil then
            return normalizedValue
        end

        local normalizedFallback = Util:NormalizeBooleanLike(fallback)
        if normalizedFallback ~= nil then
            return normalizedFallback
        end
    end

    if type(value) == "boolean" then
        return value
    end
    if type(fallback) == "boolean" then
        return fallback
    end

    return fallback
end

-- Read the current cast/channel interruptibility without boolean-testing wrappers.
local function getLiveCastUninterruptible(casterUnit, isChannel, fallback)
    local rawValue = nil
    if isChannel == true then
        if type(UnitChannelInfo) == "function" then
            rawValue = select(7, UnitChannelInfo(casterUnit))
        end
    elseif type(UnitCastingInfo) == "function" then
        rawValue = select(8, UnitCastingInfo(casterUnit))
    end

    return resolveBooleanLikeSafe(rawValue, fallback)
end

local function getBoardConfig(partyConfig)
    local boardConfig = type(partyConfig) == "table" and partyConfig.incomingCastBoard or nil
    if type(boardConfig) ~= "table" then
        boardConfig = {}
    end
    return boardConfig
end

local function getDetachedElementOffsets(element)
    if not element or not UIParent then
        return nil, nil
    end

    local centerX, centerY = element:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not centerX or not centerY or not parentX or not parentY then
        return nil, nil
    end

    local offsetX = centerX - parentX
    local offsetY = centerY - parentY
    local pixel = (Style and type(Style.GetPixelSize) == "function" and Style:GetPixelSize()) or 1
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

local function getBoardLayout(partyConfig)
    local boardConfig = getBoardConfig(partyConfig)
    local anchoredToParty = boardConfig.anchorToPartyFrames ~= false
    local width = clamp(boardConfig.width or BOARD_DEFAULT_WIDTH, BOARD_MIN_WIDTH, BOARD_MAX_WIDTH)
    local height = clamp(boardConfig.height or BOARD_DEFAULT_HEIGHT, BOARD_MIN_HEIGHT, BOARD_MAX_HEIGHT)
    local spacing = clamp(boardConfig.spacing or BOARD_SPACING, 0, BOARD_MAX_SPACING)
    local maxRows = math.floor(clamp(boardConfig.maxBars or 6, 1, BOARD_MAX_ROWS))
    local fontSize = clamp(boardConfig.fontSize or BOARD_DEFAULT_FONT_SIZE, BOARD_MIN_FONT_SIZE, BOARD_MAX_FONT_SIZE)
    local orientation = anchoredToParty and ((partyConfig and partyConfig.orientation == "horizontal") and "horizontal" or "vertical") or "detached"
    local anchorX = tonumber(boardConfig.anchorX) or 0
    local anchorY = tonumber(boardConfig.anchorY) or 0
    local detachedX = tonumber(boardConfig.detachedX)
    local detachedY = tonumber(boardConfig.detachedY)
    if detachedX == nil then
        detachedX = BOARD_DETACHED_DEFAULT_X
    end
    if detachedY == nil then
        detachedY = BOARD_DETACHED_DEFAULT_Y
    end

    if Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled() then
        width = Style:Snap(width)
        height = Style:Snap(height)
        spacing = Style:Snap(spacing)
        anchorX = Style:Snap(anchorX)
        anchorY = Style:Snap(anchorY)
        detachedX = Style:Snap(detachedX)
        detachedY = Style:Snap(detachedY)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        spacing = math.floor(spacing + 0.5)
        anchorX = math.floor(anchorX + 0.5)
        anchorY = math.floor(anchorY + 0.5)
        detachedX = math.floor(detachedX + 0.5)
        detachedY = math.floor(detachedY + 0.5)
    end

    if not anchoredToParty then
        return {
            width = width,
            height = height,
            spacing = spacing,
            fontSize = fontSize,
            maxRows = maxRows,
            anchoredToParty = false,
            anchorPoint = "CENTER",
            relativePoint = "CENTER",
            offsetX = detachedX,
            offsetY = detachedY,
        }
    end

    if orientation == "horizontal" then
        return {
            width = width,
            height = height,
            spacing = spacing,
            fontSize = fontSize,
            maxRows = maxRows,
            anchoredToParty = true,
            anchorPoint = "TOPLEFT",
            relativePoint = "BOTTOMLEFT",
            offsetX = BOARD_HORIZONTAL_BASE_OFFSET_X + anchorX,
            offsetY = BOARD_HORIZONTAL_BASE_OFFSET_Y + anchorY,
        }
    end

    return {
        width = width,
        height = height,
        spacing = spacing,
        fontSize = fontSize,
        maxRows = maxRows,
        anchoredToParty = true,
        anchorPoint = "TOPLEFT",
        relativePoint = "TOPRIGHT",
        offsetX = BOARD_VERTICAL_BASE_OFFSET_X + anchorX,
        offsetY = BOARD_VERTICAL_BASE_OFFSET_Y + anchorY,
    }
end

local function applyBorder(frame, borderSize, color)
    if not frame or type(color) ~= "table" then
        return
    end

    if not frame.TopBorder then
        frame.TopBorder = frame:CreateTexture(nil, "BORDER")
        frame.BottomBorder = frame:CreateTexture(nil, "BORDER")
        frame.LeftBorder = frame:CreateTexture(nil, "BORDER")
        frame.RightBorder = frame:CreateTexture(nil, "BORDER")
    end

    frame.TopBorder:ClearAllPoints()
    frame.TopBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.TopBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.TopBorder:SetHeight(borderSize)
    frame.TopBorder:SetColorTexture(color[1], color[2], color[3], color[4])

    frame.BottomBorder:ClearAllPoints()
    frame.BottomBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.BottomBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.BottomBorder:SetHeight(borderSize)
    frame.BottomBorder:SetColorTexture(color[1], color[2], color[3], color[4])

    frame.LeftBorder:ClearAllPoints()
    frame.LeftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.LeftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.LeftBorder:SetWidth(borderSize)
    frame.LeftBorder:SetColorTexture(color[1], color[2], color[3], color[4])

    frame.RightBorder:ClearAllPoints()
    frame.RightBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.RightBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.RightBorder:SetWidth(borderSize)
    frame.RightBorder:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function sortByNewestStart(left, right)
    return (left.startTime or 0) > (right.startTime or 0)
end

function IncomingCastBoard:Constructor()
    self.addon = nil
    self.dataHandle = nil
    self.partyFrames = nil
    self.unitFrames = nil
    self.root = nil
    self.activeCasts = {}
    self.rowsByCaster = {}
    self.rowPool = {}
    self.visibleRows = {}
    self.sortScratch = {}
    self.fadeTicker = nil
    self.editModeCallbacksRegistered = false
    self.editModeActive = false
end

function IncomingCastBoard:OnInitialize(addonRef)
    self.addon = addonRef
end

function IncomingCastBoard:OnEnable()
    self.dataHandle = self.addon and self.addon:GetModule("dataHandle") or nil
    self.partyFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    self.unitFrames = self.addon and self.addon:GetModule("unitFrames") or nil
    self:RegisterEditModeCallbacks()
    self.editModeActive = (EditModeManagerFrame and EditModeManagerFrame.editModeActive == true) and true or false
    self:RegisterEvents()
    self:RefreshLayout()
end

function IncomingCastBoard:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:UnregisterEditModeCallbacks()
    self:StopFadeTicker()
    self:ResetBoardState()
    if self.root then
        self.root:StopMovingOrSizing()
        self.root._editModeMoving = false
        if self.root.EditModeSelection then
            self.root.EditModeSelection:Hide()
        end
        self.root:Hide()
    end
    self.editModeActive = false
    self.unitFrames = nil
    self.partyFrames = nil
    self.dataHandle = nil
end

function IncomingCastBoard:RegisterEvents()
    ns.EventRouter:Register(self, "PLAYER_ENTERING_WORLD", self.OnValidationEvent)
    ns.EventRouter:Register(self, "GROUP_ROSTER_UPDATE", self.OnValidationEvent)
    ns.EventRouter:Register(self, "NAME_PLATE_UNIT_REMOVED", self.OnNameplateRemoved)
    ns.EventRouter:Register(self, "UNIT_TARGET", self.OnUnitTargetChanged)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_START", self.OnCastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_START", self.OnCastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_EMPOWER_START", self.OnCastStart)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_SUCCEEDED", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_STOP", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_FAILED", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_INTERRUPTED", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_STOP", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_EMPOWER_STOP", self.OnCastStop)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_INTERRUPTIBLE", self.OnInterruptibilityChanged)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", self.OnInterruptibilityChanged)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_DELAYED", self.OnCastUpdated)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_CHANNEL_UPDATE", self.OnCastUpdated)
    ns.EventRouter:Register(self, "UNIT_SPELLCAST_EMPOWER_UPDATE", self.OnCastUpdated)
end

function IncomingCastBoard:RegisterEditModeCallbacks()
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

function IncomingCastBoard:UnregisterEditModeCallbacks()
    if not self.editModeCallbacksRegistered then
        return
    end
    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("EditMode.Enter", self)
        EventRegistry:UnregisterCallback("EditMode.Exit", self)
    end
    self.editModeCallbacksRegistered = false
end

function IncomingCastBoard:GetRuntimeState(runtimeState)
    if runtimeState then
        return runtimeState
    end

    self.dataHandle = self.dataHandle or (self.addon and self.addon:GetModule("dataHandle")) or nil
    self.partyFrames = self.partyFrames or (self.addon and self.addon:GetModule("partyFrames")) or nil

    if not self.dataHandle or type(self.dataHandle.GetProfile) ~= "function" or type(self.dataHandle.GetUnitConfig) ~= "function" then
        return nil
    end

    local profile = self.dataHandle:GetProfile()
    local partyConfig = self.dataHandle:GetUnitConfig("party")
    local testMode = profile and profile.testMode == true or false
    local previewMode = testMode or (self.partyFrames and self.partyFrames.IsPreviewModeActive and self.partyFrames:IsPreviewModeActive()) or false

    return {
        profile = profile,
        partyConfig = partyConfig,
        addonEnabled = profile and profile.enabled ~= false or false,
        testMode = testMode,
        previewMode = previewMode,
    }
end

function IncomingCastBoard:IsBoardEnabled(runtimeState)
    local state = self:GetRuntimeState(runtimeState)
    if not state or not state.partyConfig then
        return false, nil
    end

    local boardConfig = getBoardConfig(state.partyConfig)
    if state.addonEnabled ~= true or boardConfig.enabled == false then
        return false, state
    end

    if state.testMode == true then
        return true, state
    end

    if state.previewMode == true and not (self.editModeActive == true and boardConfig.anchorToPartyFrames == false) then
        return false, state
    end

    if boardConfig.anchorToPartyFrames ~= false and state.partyConfig.enabled == false then
        return false, state
    end

    return true, state
end

function IncomingCastBoard:ShouldShowDetachedEditModePlaceholder(runtimeState)
    local state = self:GetRuntimeState(runtimeState)
    if not state or state.addonEnabled ~= true then
        return false
    end

    local boardConfig = getBoardConfig(state.partyConfig)
    return self.editModeActive == true
        and boardConfig.enabled ~= false
        and boardConfig.anchorToPartyFrames == false
end

function IncomingCastBoard:EnsureDetachedEditModeSelection()
    if not self.root or not self.unitFrames then
        return
    end

    if type(self.unitFrames.EnsureDetachedElementEditModeSelection) == "function" then
        self.unitFrames:EnsureDetachedElementEditModeSelection(
            self.root,
            (ns.L and ns.L.CONFIG_TAB_TARGETED_SPELLS) or "Targeted Spells",
            EDIT_MODE_SELECTION_COLOR,
            function() self:SaveDetachedAnchorFromEditMode() end
        )
    end

    local selection = self.root.EditModeSelection
    if selection and selection.Label and selection.Label.SetText then
        selection.Label:SetText((ns.L and ns.L.CONFIG_TAB_TARGETED_SPELLS) or "Targeted Spells")
    end
end

function IncomingCastBoard:SaveDetachedAnchorFromEditMode()
    if not self.root or not self.dataHandle then
        return
    end

    local offsetX, offsetY = getDetachedElementOffsets(self.root)
    if offsetX == nil or offsetY == nil then
        return
    end

    self.dataHandle:SetUnitConfig("party", "incomingCastBoard.detachedX", offsetX)
    self.dataHandle:SetUnitConfig("party", "incomingCastBoard.detachedY", offsetY)
    self:RefreshLayout()
end

function IncomingCastBoard:EnsureRootFrame(runtimeState)
    local state = self:GetRuntimeState(runtimeState)
    if not state or not state.partyConfig then
        return nil
    end

    self.partyFrames = self.partyFrames or (self.addon and self.addon:GetModule("partyFrames")) or nil
    local boardConfig = getBoardConfig(state.partyConfig)
    local parent = nil
    if boardConfig.anchorToPartyFrames == false then
        parent = UIParent
    else
        parent = self.partyFrames and type(self.partyFrames.GetContainerFrame) == "function" and self.partyFrames:GetContainerFrame() or nil
    end
    if not parent then
        return nil
    end

    if not self.root then
        self.root = CreateFrame("Frame", nil, parent)
        self.root:SetFrameStrata(boardConfig.anchorToPartyFrames == false and "HIGH" or "MEDIUM")
        self.root:Hide()
    elseif self.root:GetParent() ~= parent then
        self.root:SetParent(parent)
    end

    self.root:SetFrameStrata(boardConfig.anchorToPartyFrames == false and "HIGH" or "MEDIUM")
    self.root:SetFrameLevel(parent:GetFrameLevel() + 80)
    self.root:SetClampedToScreen(true)

    if boardConfig.anchorToPartyFrames == false then
        self:EnsureDetachedEditModeSelection()
    elseif self.root.EditModeSelection then
        self.root.EditModeSelection:Hide()
    end

    return self.root
end

function IncomingCastBoard:CreateRow()
    local parent = self:EnsureRootFrame()
    if not parent then
        return nil
    end

    local row = CreateFrame("Frame", nil, parent)
    row:SetClipsChildren(true)

    row.Background = row:CreateTexture(nil, "BACKGROUND")
    row.Background:SetAllPoints()

    row.Progress = CreateFrame("StatusBar", nil, row)
    row.Progress:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.Progress:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.Progress:SetMinMaxValues(0, 1)
    row.Progress:SetValue(1)
    row.Progress:SetFrameLevel(row:GetFrameLevel())

    row.PlayerTint = CreateFrame("Frame", nil, row)
    row.PlayerTint:SetAllPoints()
    row.PlayerTint:SetFrameLevel(row.Progress:GetFrameLevel() + 1)
    row.PlayerTint:Hide()
    row.PlayerTint.Texture = row.PlayerTint:CreateTexture(nil, "OVERLAY")
    row.PlayerTint.Texture:SetAllPoints()

    row.Highlight = CreateFrame("Frame", nil, row)
    row.Highlight:SetAllPoints()
    row.Highlight:SetFrameLevel(row.Progress:GetFrameLevel() + 4)
    row.Highlight:Hide()

    row.Content = CreateFrame("Frame", nil, row)
    row.Content:SetAllPoints()
    row.Content:SetFrameLevel(row.Progress:GetFrameLevel() + 3)

    row.IconSlot = CreateFrame("Frame", nil, row.Content)
    row.IconSlot:SetFrameLevel(row.Content:GetFrameLevel() + 1)
    row.IconSlot.Background = row.IconSlot:CreateTexture(nil, "BACKGROUND")
    row.IconSlot.Background:SetAllPoints()

    row.TextPanel = row.Content:CreateTexture(nil, "BACKGROUND")
    row.TargetPanel = row.Content:CreateTexture(nil, "BACKGROUND")

    row.Icon = row.IconSlot:CreateTexture(nil, "ARTWORK")
    row.Icon:SetAllPoints()
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Icon:SetDrawLayer("ARTWORK", 1)

    row.IconBorder = CreateFrame("Frame", nil, row.Content)
    row.IconBorder:SetFrameLevel(row.Content:GetFrameLevel() + 1)

    row.SpellText = row.Content:CreateFontString(nil, "OVERLAY")
    row.SpellText:SetJustifyH("LEFT")
    row.SpellText:SetWordWrap(false)

    row.TargetText = row.Content:CreateFontString(nil, "OVERLAY")
    row.TargetText:SetJustifyH("RIGHT")
    row.TargetText:SetWordWrap(false)

    row.InterruptText = row.Content:CreateFontString(nil, "OVERLAY")
    row.InterruptText:SetJustifyH("CENTER")
    row.InterruptText:SetWordWrap(false)
    row.InterruptText:Hide()

    return row
end

function IncomingCastBoard:AcquireRow()
    local row = table.remove(self.rowPool)
    if row then
        row:SetAlpha(1)
        return row
    end
    return self:CreateRow()
end

function IncomingCastBoard:ReleaseRow(row)
    if not row then
        return
    end
    row.casterUnit = nil
    row:SetAlpha(1)
    row:Hide()
    row.InterruptText:Hide()
    row.SpellText:Show()
    row.TargetText:Show()
    row.PlayerTint:Hide()
    row.Highlight:Hide()
    table.insert(self.rowPool, row)
end

function IncomingCastBoard:ReleaseAllRows()
    clearTable(self.visibleRows)

    for casterUnit, row in pairs(self.rowsByCaster) do
        self:ReleaseRow(row)
        self.rowsByCaster[casterUnit] = nil
    end
end

function IncomingCastBoard:ResetBoardState()
    self:ReleaseAllRows()
    clearTable(self.activeCasts)
    clearTable(self.sortScratch)
    if self.root then
        self.root:Hide()
    end
end

function IncomingCastBoard:StopFadeTicker()
    if not self.fadeTicker then
        return
    end
    self.fadeTicker:Cancel()
    self.fadeTicker = nil
end

function IncomingCastBoard:HasFadingCast()
    for _, record in pairs(self.activeCasts) do
        if record.fadingStartedAt then
            return true
        end
    end
    return false
end

function IncomingCastBoard:StartFadeTicker()
    if self.fadeTicker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end

    self.fadeTicker = C_Timer.NewTicker(FADE_TICK_SECONDS, function()
        if not self:HasFadingCast() then
            self:StopFadeTicker()
            return
        end
        self:RenderBoard()
    end)
end

function IncomingCastBoard:ApplyRowAppearance(row, runtimeState)
    if not row then
        return
    end

    local partyConfig = runtimeState and runtimeState.partyConfig or nil
    local layout = getBoardLayout(partyConfig)
    local pixelPerfect = Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled()
    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(8) or 8
    local iconInset = pixelPerfect and Style:Snap(2) or 2
    local iconSize = math.max(layout.height - (border * 2) - (iconInset * 2), 16)
    local fontSize = layout.fontSize or BOARD_DEFAULT_FONT_SIZE
    local backgroundColor = Style:IsDarkModeEnabled() and ROW_BACKGROUND_COLOR_DARK or ROW_BACKGROUND_COLOR
    local borderColor = Style:IsDarkModeEnabled() and ROW_BORDER_COLOR_DARK or ROW_BORDER_COLOR

    row:SetSize(layout.width, layout.height)
    row.Background:SetColorTexture(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4])

    if Style and type(Style.ApplyStatusBarTexture) == "function" then
        Style:ApplyStatusBarTexture(row.Progress)
    end

    applyBorder(row, border, borderColor)
    row.IconBorder:SetAllPoints(row.IconSlot)
    applyBorder(row.IconBorder, border, borderColor)
    row.Highlight:SetAllPoints(row)
    applyBorder(row.Highlight, border, IMPORTANT_GLOW_COLOR)
    row.PlayerTint.Texture:SetColorTexture(
        SELF_TARGET_OVERLAY_COLOR[1],
        SELF_TARGET_OVERLAY_COLOR[2],
        SELF_TARGET_OVERLAY_COLOR[3],
        SELF_TARGET_OVERLAY_COLOR[4]
    )

    row.IconSlot:ClearAllPoints()
    row.IconSlot:SetPoint("TOPLEFT", row.Content, "TOPLEFT", border + iconInset, -(border + iconInset))
    row.IconSlot:SetPoint("BOTTOMLEFT", row.Content, "BOTTOMLEFT", border + iconInset, border + iconInset)
    row.IconSlot:SetWidth(iconSize)
    row.IconSlot.Background:SetColorTexture(
        ICON_BACKGROUND_COLOR[1],
        ICON_BACKGROUND_COLOR[2],
        ICON_BACKGROUND_COLOR[3],
        ICON_BACKGROUND_COLOR[4]
    )
    row.Icon:ClearAllPoints()
    row.Icon:SetPoint("TOPLEFT", row.IconSlot, "TOPLEFT", border, -border)
    row.Icon:SetPoint("BOTTOMRIGHT", row.IconSlot, "BOTTOMRIGHT", -border, border)

    row.TextPanel:Hide()
    row.TargetPanel:Hide()

    row.SpellText:ClearAllPoints()
    row.SpellText:SetPoint("LEFT", row.IconSlot, "RIGHT", textInset, 0)
    row.SpellText:SetPoint("RIGHT", row.TargetText, "LEFT", -textInset, 0)

    row.TargetText:ClearAllPoints()
    row.TargetText:SetPoint("RIGHT", row.TextPanel, "RIGHT", -textInset, 0)
    row.TargetText:SetWidth(math.max(math.floor(layout.width * 0.24), 60))

    row.InterruptText:ClearAllPoints()
    row.InterruptText:SetPoint("LEFT", row.IconSlot, "RIGHT", textInset, 0)
    row.InterruptText:SetPoint("RIGHT", row, "RIGHT", -textInset, 0)

    if Style and type(Style.ApplyFont) == "function" then
        Style:ApplyFont(row.SpellText, fontSize, "THICKOUTLINE")
        Style:ApplyFont(row.TargetText, math.max(fontSize - 1, BOARD_MIN_FONT_SIZE), "OUTLINE")
        Style:ApplyFont(row.InterruptText, fontSize, "THICKOUTLINE")
    end

    row.SpellText:SetShadowColor(0, 0, 0, 0.9)
    row.SpellText:SetShadowOffset(1, -1)
    row.TargetText:SetShadowColor(0, 0, 0, 0.85)
    row.TargetText:SetShadowOffset(1, -1)
    row.InterruptText:SetShadowColor(0, 0, 0, 0.9)
    row.InterruptText:SetShadowOffset(1, -1)
    row.SpellText:SetTextColor(1, 0.98, 0.96, 1)
    row.TargetText:SetTextColor(0.96, 0.97, 1.0, 1)
    row.InterruptText:SetTextColor(1, 1, 1, 1)
end

function IncomingCastBoard:ApplyRowContent(row, record, runtimeState)
    if not row or not record then
        return
    end

    self:ApplyRowAppearance(row, runtimeState)

    local spellId = record.spellId
    local casterUnit = record.casterUnit
    row.casterUnit = casterUnit

    if type(record.spellName) == "string" and record.spellName ~= "" then
        row.SpellText:SetText(record.spellName)
    elseif SPELL_API and type(SPELL_API.GetSpellName) == "function" then
        row.SpellText:SetText(SPELL_API.GetSpellName(spellId) or "")
    else
        row.SpellText:SetText("")
    end

    local iconTexture = record.spellTexture
    if iconTexture == nil and SPELL_API and type(SPELL_API.GetSpellTexture) == "function" then
        iconTexture = SPELL_API.GetSpellTexture(spellId)
    end
    row.Icon:SetTexture(iconTexture or DEFAULT_CAST_ICON_TEXTURE)

    local targetName = record.testTargetName
    local targetClass = record.testTargetClass
    if not targetName and type(UnitSpellTargetName) == "function" then
        targetName = UnitSpellTargetName(casterUnit)
    end
    if not targetClass and type(UnitSpellTargetClass) == "function" then
        targetClass = UnitSpellTargetClass(casterUnit)
    end
    row.TargetText:SetText(targetName or "")

    if targetClass and CLASS_COLORS and type(CLASS_COLORS.GetClassColor) == "function" then
        local color = CLASS_COLORS.GetClassColor(targetClass)
        if color then
            row.TargetText:SetTextColor(color.r, color.g, color.b, 1)
        else
            row.TargetText:SetTextColor(0.96, 0.97, 1.0, 1)
        end
    else
        row.TargetText:SetTextColor(0.96, 0.97, 1.0, 1)
    end

    if not record.fadingStartedAt then
        local duration = record.duration
        if duration and type(row.Progress.SetTimerDuration) == "function" then
            local direction = record.isChannel == true and STATUSBAR_TIMER_DIRECTION_REMAINING or STATUSBAR_TIMER_DIRECTION_ELAPSED
            row.Progress:SetTimerDuration(duration, STATUSBAR_INTERPOLATION_IMMEDIATE, direction)
        else
            row.Progress:SetMinMaxValues(0, 1)
            row.Progress:SetValue(1)
        end
    end

    if record.uninterruptible ~= nil then
        local texture = row.Progress:GetStatusBarTexture()
        if texture and type(texture.SetVertexColorFromBoolean) == "function" then
            texture:SetVertexColorFromBoolean(record.uninterruptible, UNINTERRUPTIBLE_BAR_COLOR, INTERRUPTIBLE_BAR_COLOR)
        else
            local color = record.uninterruptible and UNINTERRUPTIBLE_BAR_COLOR or INTERRUPTIBLE_BAR_COLOR
            row.Progress:SetStatusBarColor(
                color.r,
                color.g,
                color.b,
                color.a
            )
        end
    else
        row.Progress:SetStatusBarColor(
            INTERRUPTIBLE_BAR_COLOR.r,
            INTERRUPTIBLE_BAR_COLOR.g,
            INTERRUPTIBLE_BAR_COLOR.b,
            INTERRUPTIBLE_BAR_COLOR.a
        )
    end

    if row.Highlight and SPELL_API and type(SPELL_API.IsSpellImportant) == "function" and type(row.Highlight.SetAlphaFromBoolean) == "function" then
        row.Highlight:Show()
        row.Highlight:SetAlphaFromBoolean(SPELL_API.IsSpellImportant(spellId), 1, 0)
    elseif row.Highlight then
        row.Highlight:Hide()
    end

    if row.PlayerTint then
        row.PlayerTint:Hide()
    end

    row.InterruptText:Hide()
    row.SpellText:Show()
    row.TargetText:Show()
    row:SetAlpha(1)
end

function IncomingCastBoard:LayoutVisibleRows(runtimeState)
    local root = self.root
    if not root then
        return
    end

    local partyConfig = runtimeState and runtimeState.partyConfig or nil
    local layout = getBoardLayout(partyConfig)
    local visibleCount = #self.visibleRows
    local showingDetachedPlaceholder = self:ShouldShowDetachedEditModePlaceholder(runtimeState) and visibleCount == 0
    local totalHeight = 0

    if visibleCount > 0 then
        totalHeight = (layout.height * visibleCount) + (layout.spacing * math.max(0, visibleCount - 1))
    elseif showingDetachedPlaceholder then
        totalHeight = (layout.height * BOARD_EDIT_MODE_PREVIEW_ROWS) + (layout.spacing * math.max(0, BOARD_EDIT_MODE_PREVIEW_ROWS - 1))
    end

    root:ClearAllPoints()
    root:SetPoint(layout.anchorPoint, root:GetParent(), layout.relativePoint, layout.offsetX, layout.offsetY)
    root:SetSize(layout.width, math.max(totalHeight, layout.height))

    for index = 1, visibleCount do
        local row = self.visibleRows[index]
        if row then
            row:ClearAllPoints()
            if index == 1 then
                row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", self.visibleRows[index - 1], "BOTTOMLEFT", 0, -layout.spacing)
            end
            row:SetSize(layout.width, layout.height)
            row:Show()
        end
    end

    for _, row in ipairs(self.rowPool) do
        if row then
            row:Hide()
        end
    end

    if visibleCount > 0 or showingDetachedPlaceholder then
        root:Show()
    else
        root:Hide()
    end

    if root.EditModeSelection then
        root.EditModeSelection:SetShown(self.editModeActive == true and layout.anchoredToParty == false)
    end
end

function IncomingCastBoard:PopulateTestCasts()
    clearTable(self.activeCasts)
    local now = GetTime()
    for index, template in ipairs(TEST_CAST_RECORDS) do
        local key = template.casterUnit
        self.activeCasts[key] = {
            casterUnit = key,
            spellId = template.spellId,
            spellName = template.spellName,
            spellTexture = template.spellTexture,
            isChannel = template.isChannel,
            uninterruptible = template.uninterruptible,
            startTime = now - (index * 0.4),
            duration = nil,
            fadingStartedAt = nil,
            fadingDuration = nil,
            wasInterrupted = nil,
            testTargetName = template.testTargetName,
            testTargetClass = template.testTargetClass,
        }
    end
end

function IncomingCastBoard:RenderBoard(runtimeState)
    local enabled, state = self:IsBoardEnabled(runtimeState)
    if not enabled and not self:ShouldShowDetachedEditModePlaceholder(state) then
        self:StopFadeTicker()
        self:ResetBoardState()
        return
    end

    if not self:EnsureRootFrame(state) then
        return
    end

    if state and state.testMode == true then
        self:PopulateTestCasts()
    else
        for casterUnit in pairs(self.activeCasts) do
            if string.find(casterUnit, "^__test") then
                local row = self.rowsByCaster[casterUnit]
                if row then
                    self.rowsByCaster[casterUnit] = nil
                    self:ReleaseRow(row)
                end
                self.activeCasts[casterUnit] = nil
            end
        end
    end

    local now = GetTime()

    for casterUnit, record in pairs(self.activeCasts) do
        if record.fadingStartedAt and (now - record.fadingStartedAt) >= (record.fadingDuration or 0) then
            self.activeCasts[casterUnit] = nil
            local row = self.rowsByCaster[casterUnit]
            if row then
                self.rowsByCaster[casterUnit] = nil
                self:ReleaseRow(row)
            end
        end
    end

    for casterUnit, row in pairs(self.rowsByCaster) do
        if not self.activeCasts[casterUnit] then
            self.rowsByCaster[casterUnit] = nil
            self:ReleaseRow(row)
        end
    end

    for casterUnit, record in pairs(self.activeCasts) do
        if not self.rowsByCaster[casterUnit] then
            local row = self:AcquireRow()
            if row then
                self.rowsByCaster[casterUnit] = row
                self:ApplyRowContent(row, record, state)
            end
        end
    end

    clearTable(self.sortScratch)
    for _, record in pairs(self.activeCasts) do
        self.sortScratch[#self.sortScratch + 1] = record
    end
    table.sort(self.sortScratch, sortByNewestStart)
    local layout = getBoardLayout(state and state.partyConfig or nil)

    clearTable(self.visibleRows)
    local visibleCount = 0
    for index = 1, #self.sortScratch do
        local record = self.sortScratch[index]
        local row = record and self.rowsByCaster[record.casterUnit] or nil
        if row then
            if visibleCount < (layout.maxRows or 6) then
                visibleCount = visibleCount + 1
                self.visibleRows[visibleCount] = row
            else
                row:Hide()
            end
        end
    end

    for index = 1, visibleCount do
        local row = self.visibleRows[index]
        local record = row and self.activeCasts[row.casterUnit] or nil
        if row and record and record.fadingStartedAt then
            local elapsed = now - record.fadingStartedAt
            local duration = record.fadingDuration or NORMAL_FADE_SECONDS
            local alpha = 1 - math.min(1, math.max(0, elapsed / duration))
            row:SetAlpha(alpha)
            if record.wasInterrupted == true then
                row.Progress:SetStatusBarColor(
                    INTERRUPTED_FLASH_COLOR.r,
                    INTERRUPTED_FLASH_COLOR.g,
                    INTERRUPTED_FLASH_COLOR.b,
                    INTERRUPTED_FLASH_COLOR.a
                )
                row.SpellText:Hide()
                row.TargetText:Hide()
                row.InterruptText:SetText("Interrupted")
                row.InterruptText:Show()
            end
        elseif row then
            row:SetAlpha(1)
            row.InterruptText:Hide()
            row.SpellText:Show()
            row.TargetText:Show()
        end
    end

    self:LayoutVisibleRows(state)
end

function IncomingCastBoard:RefreshLayout(runtimeState)
    local enabled, state = self:IsBoardEnabled(runtimeState)
    if not enabled and not self:ShouldShowDetachedEditModePlaceholder(state) then
        self:StopFadeTicker()
        self:ResetBoardState()
        return
    end

    if not self:EnsureRootFrame(state) then
        return
    end

    self:RenderBoard(state)
end

function IncomingCastBoard:PickupCastAfterDelay(casterUnit, isChannel, eventSpellId)
    local enabled, runtimeState = self:IsBoardEnabled()
    if not enabled then
        return
    end
    if not isRelevantCasterUnit(casterUnit) then
        return
    end
    if not isTrackedFriendlyTarget(casterUnit) then
        return
    end
    if eventSpellId == nil then
        return
    end

    local notInterruptible = nil
    if type(UnitCastingInfo) == "function" and UnitCastingInfo(casterUnit) ~= nil then
        isChannel = false
        notInterruptible = select(8, UnitCastingInfo(casterUnit))
    elseif type(UnitChannelInfo) == "function" and UnitChannelInfo(casterUnit) ~= nil then
        isChannel = true
        notInterruptible = select(7, UnitChannelInfo(casterUnit))
    else
        return
    end

    local record = self.activeCasts[casterUnit] or {}
    record.spellId = eventSpellId
    record.isChannel = isChannel == true
    record.startTime = GetTime()
    record.duration = getLiveCastDuration(casterUnit)
    record.spellTexture = getLiveCastTexture(casterUnit, record.isChannel)
    record.uninterruptible = resolveBooleanLikeSafe(notInterruptible, record.uninterruptible)
    record.casterUnit = casterUnit
    record.fadingStartedAt = nil
    record.fadingDuration = nil
    record.wasInterrupted = nil

    self.activeCasts[casterUnit] = record

    local row = self.rowsByCaster[casterUnit]
    if row then
        self:ApplyRowContent(row, record, runtimeState)
    end

    self:RenderBoard(runtimeState)
    self:PickupCastSafetyCheck(casterUnit)
end

function IncomingCastBoard:PickupCastSafetyCheck(casterUnit)
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end

    C_Timer.After(SAFETY_CHECK_SECONDS, function()
        local active = self.activeCasts[casterUnit]
        if not active or active.fadingStartedAt then
            return
        end

        local stillCasting = safeUnitExists(casterUnit)
            and ((type(UnitCastingInfo) == "function" and UnitCastingInfo(casterUnit) ~= nil)
                or (type(UnitChannelInfo) == "function" and UnitChannelInfo(casterUnit) ~= nil))

        if stillCasting then
            self:PickupCastSafetyCheck(casterUnit)
            return
        end

        active.fadingStartedAt = GetTime()
        active.fadingDuration = 0
        self:RenderBoard()
    end)
end

function IncomingCastBoard:QueuePickupFromCastStart(eventName, casterUnit, spellId)
    if not isRelevantCasterUnit(casterUnit) then
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end

    local isChannel = eventName == "UNIT_SPELLCAST_CHANNEL_START"

    if isChannel then
        local active = self.activeCasts[casterUnit]
        if active and not active.fadingStartedAt and active.isChannel ~= true then
            active.isChannel = true
            active.duration = type(UnitChannelDuration) == "function" and UnitChannelDuration(casterUnit) or active.duration
            active.spellTexture = getLiveCastTexture(casterUnit, true)
            active.uninterruptible = getLiveCastUninterruptible(casterUnit, true, active.uninterruptible)
            local row = self.rowsByCaster[casterUnit]
            if row then
                self:ApplyRowContent(row, active, self:GetRuntimeState())
            end
            return
        end
    end

    C_Timer.After(PICKUP_DELAY_SECONDS, function()
        self:PickupCastAfterDelay(casterUnit, isChannel, spellId)
    end)
end

function IncomingCastBoard:HandleCastStop(casterUnit, eventName)
    local active = self.activeCasts[casterUnit]
    if not active then
        return
    end

    if eventName == "UNIT_SPELLCAST_SUCCEEDED" and type(UnitChannelInfo) == "function" and UnitChannelInfo(casterUnit) ~= nil then
        return
    end

    if active.wasInterrupted == true and active.fadingStartedAt then
        return
    end

    local wasInterrupted = eventName == "UNIT_SPELLCAST_INTERRUPTED"
    local fadeDuration = wasInterrupted and INTERRUPTED_FADE_SECONDS or NORMAL_FADE_SECONDS

    if fadeDuration > 0 then
        active.fadingStartedAt = GetTime()
        active.fadingDuration = fadeDuration
        active.wasInterrupted = wasInterrupted
        self:StartFadeTicker()
    else
        self.activeCasts[casterUnit] = nil
    end

    self:RenderBoard()
end

function IncomingCastBoard:HandleInterruptibilityChange(casterUnit, isInterruptible)
    local active = self.activeCasts[casterUnit]
    if not active or active.fadingStartedAt then
        return
    end

    active.uninterruptible = isInterruptible == false

    local row = self.rowsByCaster[casterUnit]
    if row then
        self:ApplyRowContent(row, active, self:GetRuntimeState())
    end
end

function IncomingCastBoard:HandleCastUpdate(casterUnit)
    local active = self.activeCasts[casterUnit]
    if not active or active.fadingStartedAt then
        return
    end

    if active.isChannel == true then
        active.duration = type(UnitChannelDuration) == "function" and UnitChannelDuration(casterUnit) or active.duration
        active.spellTexture = getLiveCastTexture(casterUnit, true) or active.spellTexture
        active.uninterruptible = getLiveCastUninterruptible(casterUnit, true, active.uninterruptible)
    else
        active.duration = type(UnitCastingDuration) == "function" and UnitCastingDuration(casterUnit) or active.duration
        active.spellTexture = getLiveCastTexture(casterUnit, false) or active.spellTexture
        active.uninterruptible = getLiveCastUninterruptible(casterUnit, false, active.uninterruptible)
    end

    local row = self.rowsByCaster[casterUnit]
    if row then
        self:ApplyRowContent(row, active, self:GetRuntimeState())
    end
end

function IncomingCastBoard:HandleTargetChange(casterUnit)
    local active = self.activeCasts[casterUnit]
    if not active or active.fadingStartedAt then
        return
    end

    if not isTrackedFriendlyTarget(casterUnit) then
        self.activeCasts[casterUnit] = nil
        self:RenderBoard()
        return
    end

    local row = self.rowsByCaster[casterUnit]
    if row then
        self:ApplyRowContent(row, active, self:GetRuntimeState())
    end
end

function IncomingCastBoard:ValidateActiveCasts()
    local removedAny = false

    for casterUnit, record in pairs(self.activeCasts) do
        if not record.fadingStartedAt then
            if not safeUnitExists(casterUnit) then
                self.activeCasts[casterUnit] = nil
                removedAny = true
            elseif (type(UnitCastingInfo) == "function" and UnitCastingInfo(casterUnit) == nil)
                and (type(UnitChannelInfo) == "function" and UnitChannelInfo(casterUnit) == nil) then
                self.activeCasts[casterUnit] = nil
                removedAny = true
            elseif not isTrackedFriendlyTarget(casterUnit) then
                self.activeCasts[casterUnit] = nil
                removedAny = true
            end
        end
    end

    if removedAny then
        self:RenderBoard()
    end
end

function IncomingCastBoard:OnEditModeEnter()
    self.editModeActive = true
    self:RefreshLayout()
    if self.root then
        self:EnsureDetachedEditModeSelection()
        if self.root.EditModeSelection then
            local state = self:GetRuntimeState()
            local boardConfig = state and getBoardConfig(state.partyConfig) or {}
            self.root.EditModeSelection:SetShown(boardConfig.anchorToPartyFrames == false)
        end
    end
end

function IncomingCastBoard:OnEditModeExit()
    self.editModeActive = false
    if self.root then
        self.root:StopMovingOrSizing()
        self.root._editModeMoving = false
        if self.root.EditModeSelection then
            self.root.EditModeSelection:Hide()
        end
    end
    self:RefreshLayout()
end

function IncomingCastBoard:OnValidationEvent()
    self:ValidateActiveCasts()
    self:RefreshLayout()
end

function IncomingCastBoard:OnNameplateRemoved(_, casterUnit)
    if type(casterUnit) ~= "string" or casterUnit == "" then
        return
    end

    if self.activeCasts[casterUnit] then
        self.activeCasts[casterUnit] = nil
        self:RenderBoard()
    end
end

function IncomingCastBoard:OnUnitTargetChanged(_, casterUnit)
    if not isRelevantCasterUnit(casterUnit) then
        return
    end
    self:HandleTargetChange(casterUnit)
end

function IncomingCastBoard:OnCastStart(eventName, casterUnit, _, spellId)
    local enabled = self:IsBoardEnabled()
    if not enabled then
        return
    end
    self:QueuePickupFromCastStart(eventName, casterUnit, spellId)
end

function IncomingCastBoard:OnCastStop(eventName, casterUnit)
    local enabled = self:IsBoardEnabled()
    if not enabled then
        return
    end
    self:HandleCastStop(casterUnit, eventName)
end

function IncomingCastBoard:OnInterruptibilityChanged(eventName, casterUnit)
    local enabled = self:IsBoardEnabled()
    if not enabled then
        return
    end
    self:HandleInterruptibilityChange(casterUnit, eventName == "UNIT_SPELLCAST_INTERRUPTIBLE")
end

function IncomingCastBoard:OnCastUpdated(_, casterUnit)
    local enabled = self:IsBoardEnabled()
    if not enabled then
        return
    end
    self:HandleCastUpdate(casterUnit)
end

addon:RegisterModule("incomingCastBoard", IncomingCastBoard:New())
