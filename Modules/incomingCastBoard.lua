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
local BOARD_MAX_ROWS = 6
local BOARD_SPACING = 4
local BOARD_MIN_WIDTH = 210
local BOARD_WIDTH_PADDING = 34
local BOARD_MIN_HEIGHT = 18
local BOARD_MAX_HEIGHT = 28
local BOARD_HEIGHT_RATIO = 0.62
local BOARD_VERTICAL_OFFSET_X = 14
local BOARD_VERTICAL_OFFSET_Y = 0
local BOARD_HORIZONTAL_OFFSET_X = 0
local BOARD_HORIZONTAL_OFFSET_Y = -12
local ROW_BACKGROUND_COLOR = { 0.06, 0.07, 0.08, 0.90 }
local ROW_BACKGROUND_COLOR_DARK = { 0.17, 0.18, 0.20, 0.94 }
local ROW_BORDER_COLOR = { 1.00, 1.00, 1.00, 0.08 }
local ROW_BORDER_COLOR_DARK = { 1.00, 1.00, 1.00, 0.12 }
local INTERRUPTIBLE_BAR_COLOR = { r = 1.00, g = 0.34, b = 0.22, a = 0.96 }
local UNINTERRUPTIBLE_BAR_COLOR = { r = 0.53, g = 0.56, b = 0.60, a = 0.96 }
local SELF_TARGET_OVERLAY_COLOR = { 1.00, 0.86, 0.18, 0.18 }
local IMPORTANT_GLOW_COLOR = { 1.00, 0.84, 0.26, 0.90 }
local INTERRUPTED_FLASH_COLOR = { r = 1.00, g = 0.96, b = 0.32, a = 1.00 }
local STATUSBAR_INTERPOLATION_IMMEDIATE = (_G.Enum and _G.Enum.StatusBarInterpolation and _G.Enum.StatusBarInterpolation.Immediate) or 0
local STATUSBAR_TIMER_DIRECTION_ELAPSED = (_G.Enum and _G.Enum.StatusBarTimerDirection and _G.Enum.StatusBarTimerDirection.ElapsedTime) or 0
local STATUSBAR_TIMER_DIRECTION_REMAINING = (_G.Enum and _G.Enum.StatusBarTimerDirection and _G.Enum.StatusBarTimerDirection.RemainingTime) or 1
local CLASS_COLORS = _G.C_ClassColor
local SPELL_API = _G.C_Spell

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
    if UnitIsUnit(targetUnit, "player") then
        return true
    end
    if IsInGroup() and safeUnitInParty(targetUnit) then
        return true
    end
    return false
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

local function getDefaultBoardLayout(partyConfig)
    local width = clamp((tonumber(partyConfig and partyConfig.width) or 180) + BOARD_WIDTH_PADDING, BOARD_MIN_WIDTH, 420)
    local height = clamp((tonumber(partyConfig and partyConfig.height) or 34) * BOARD_HEIGHT_RATIO, BOARD_MIN_HEIGHT, BOARD_MAX_HEIGHT)
    local spacing = BOARD_SPACING
    local orientation = (partyConfig and partyConfig.orientation == "horizontal") and "horizontal" or "vertical"

    if Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled() then
        width = Style:Snap(width)
        height = Style:Snap(height)
        spacing = Style:Snap(spacing)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        spacing = math.floor(spacing + 0.5)
    end

    if orientation == "horizontal" then
        return {
            width = width,
            height = height,
            spacing = spacing,
            anchorPoint = "TOPLEFT",
            relativePoint = "BOTTOMLEFT",
            offsetX = BOARD_HORIZONTAL_OFFSET_X,
            offsetY = BOARD_HORIZONTAL_OFFSET_Y,
        }
    end

    return {
        width = width,
        height = height,
        spacing = spacing,
        anchorPoint = "TOPLEFT",
        relativePoint = "TOPRIGHT",
        offsetX = BOARD_VERTICAL_OFFSET_X,
        offsetY = BOARD_VERTICAL_OFFSET_Y,
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
    self.root = nil
    self.activeCasts = {}
    self.rowsByCaster = {}
    self.rowPool = {}
    self.visibleRows = {}
    self.sortScratch = {}
    self.fadeTicker = nil
end

function IncomingCastBoard:OnInitialize(addonRef)
    self.addon = addonRef
end

function IncomingCastBoard:OnEnable()
    self.dataHandle = self.addon and self.addon:GetModule("dataHandle") or nil
    self.partyFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    self:RegisterEvents()
    self:RefreshLayout()
end

function IncomingCastBoard:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self:StopFadeTicker()
    self:ResetBoardState()
    if self.root then
        self.root:Hide()
    end
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
    if state.previewMode == true then
        return false, state
    end
    if state.addonEnabled ~= true or state.partyConfig.enabled == false then
        return false, state
    end

    local boardConfig = state.partyConfig.incomingCastBoard
    if type(boardConfig) == "table" and boardConfig.enabled == false then
        return false, state
    end

    return true, state
end

function IncomingCastBoard:EnsureRootFrame()
    self.partyFrames = self.partyFrames or (self.addon and self.addon:GetModule("partyFrames")) or nil
    local parent = self.partyFrames and type(self.partyFrames.GetContainerFrame) == "function" and self.partyFrames:GetContainerFrame() or nil
    if not parent then
        return nil
    end

    if not self.root then
        self.root = CreateFrame("Frame", nil, parent)
        self.root:SetFrameStrata("MEDIUM")
        self.root:Hide()
    elseif self.root:GetParent() ~= parent then
        self.root:SetParent(parent)
    end

    self.root:SetFrameLevel(parent:GetFrameLevel() + 80)
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
    row.Progress.Background = row.Progress:CreateTexture(nil, "BACKGROUND")
    row.Progress.Background:SetAllPoints()

    row.PlayerTint = CreateFrame("Frame", nil, row)
    row.PlayerTint:SetAllPoints()
    row.PlayerTint:Hide()
    row.PlayerTint.Texture = row.PlayerTint:CreateTexture(nil, "OVERLAY")
    row.PlayerTint.Texture:SetAllPoints()

    row.Highlight = CreateFrame("Frame", nil, row)
    row.Highlight:SetAllPoints()
    row.Highlight:Hide()

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.IconBorder = CreateFrame("Frame", nil, row)
    row.IconBorder:SetFrameLevel(row:GetFrameLevel() + 4)

    row.SpellText = row:CreateFontString(nil, "OVERLAY")
    row.SpellText:SetJustifyH("LEFT")
    row.SpellText:SetWordWrap(false)

    row.TargetText = row:CreateFontString(nil, "OVERLAY")
    row.TargetText:SetJustifyH("RIGHT")
    row.TargetText:SetWordWrap(false)

    row.InterruptText = row:CreateFontString(nil, "OVERLAY")
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
    local layout = getDefaultBoardLayout(partyConfig)
    local pixelPerfect = Style and type(Style.IsPixelPerfectEnabled) == "function" and Style:IsPixelPerfectEnabled()
    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(6) or 6
    local iconSize = math.max(layout.height - (border * 2), 12)
    local fontSize = clamp(math.min(tonumber(partyConfig and partyConfig.fontSize) or 11, layout.height - 6), 9, 16)
    local backgroundColor = Style:IsDarkModeEnabled() and ROW_BACKGROUND_COLOR_DARK or ROW_BACKGROUND_COLOR
    local borderColor = Style:IsDarkModeEnabled() and ROW_BORDER_COLOR_DARK or ROW_BORDER_COLOR

    row:SetSize(layout.width, layout.height)
    row.Background:SetColorTexture(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4])

    if Style and type(Style.ApplyStatusBarTexture) == "function" then
        Style:ApplyStatusBarTexture(row.Progress)
    end
    row.Progress.Background:SetColorTexture(0, 0, 0, 0.36)

    applyBorder(row, border, borderColor)
    row.IconBorder:SetAllPoints(row.Icon)
    applyBorder(row.IconBorder, border, borderColor)
    row.Highlight:SetAllPoints(row)
    applyBorder(row.Highlight, border, IMPORTANT_GLOW_COLOR)
    row.PlayerTint.Texture:SetColorTexture(
        SELF_TARGET_OVERLAY_COLOR[1],
        SELF_TARGET_OVERLAY_COLOR[2],
        SELF_TARGET_OVERLAY_COLOR[3],
        SELF_TARGET_OVERLAY_COLOR[4]
    )

    row.Icon:ClearAllPoints()
    row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", border, -border)
    row.Icon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", border, border)
    row.Icon:SetWidth(iconSize)

    row.SpellText:ClearAllPoints()
    row.SpellText:SetPoint("LEFT", row.Icon, "RIGHT", textInset, 0)
    row.SpellText:SetPoint("RIGHT", row.TargetText, "LEFT", -textInset, 0)

    row.TargetText:ClearAllPoints()
    row.TargetText:SetPoint("RIGHT", row, "RIGHT", -textInset, 0)
    row.TargetText:SetWidth(math.max(math.floor(layout.width * 0.38), 68))

    row.InterruptText:ClearAllPoints()
    row.InterruptText:SetPoint("LEFT", row.Icon, "RIGHT", textInset, 0)
    row.InterruptText:SetPoint("RIGHT", row, "RIGHT", -textInset, 0)

    if Style and type(Style.ApplyFont) == "function" then
        Style:ApplyFont(row.SpellText, fontSize, "OUTLINE")
        Style:ApplyFont(row.TargetText, fontSize, "OUTLINE")
        Style:ApplyFont(row.InterruptText, fontSize, "OUTLINE")
    end

    row.SpellText:SetTextColor(1, 1, 1, 1)
    row.TargetText:SetTextColor(1, 1, 1, 1)
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

    if SPELL_API and type(SPELL_API.GetSpellName) == "function" then
        row.SpellText:SetText(SPELL_API.GetSpellName(spellId) or "")
    else
        row.SpellText:SetText("")
    end

    if SPELL_API and type(SPELL_API.GetSpellTexture) == "function" then
        row.Icon:SetTexture(SPELL_API.GetSpellTexture(spellId))
    else
        row.Icon:SetTexture(nil)
    end

    if type(UnitSpellTargetName) == "function" then
        local targetName = UnitSpellTargetName(casterUnit)
        if targetName then
            row.TargetText:SetText(targetName)
        else
            row.TargetText:SetText("")
        end
    else
        row.TargetText:SetText("")
    end

    if CLASS_COLORS and type(CLASS_COLORS.GetClassColor) == "function" and type(UnitSpellTargetClass) == "function" then
        local targetClass = UnitSpellTargetClass(casterUnit)
        if targetClass then
            local color = CLASS_COLORS.GetClassColor(targetClass)
            if color then
                row.TargetText:SetTextColor(color.r, color.g, color.b, 1)
            else
                row.TargetText:SetTextColor(1, 1, 1, 1)
            end
        else
            row.TargetText:SetTextColor(1, 1, 1, 1)
        end
    else
        row.TargetText:SetTextColor(1, 1, 1, 1)
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
            row.Progress:SetStatusBarColor(
                INTERRUPTIBLE_BAR_COLOR.r,
                INTERRUPTIBLE_BAR_COLOR.g,
                INTERRUPTIBLE_BAR_COLOR.b,
                INTERRUPTIBLE_BAR_COLOR.a
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

    if row.PlayerTint and type(row.PlayerTint.SetShownFromBoolean) == "function" then
        row.PlayerTint:SetShownFromBoolean(UnitIsUnit(casterUnit .. "target", "player"), true, false)
    else
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
    local layout = getDefaultBoardLayout(partyConfig)
    local visibleCount = #self.visibleRows
    local totalHeight = 0

    if visibleCount > 0 then
        totalHeight = (layout.height * visibleCount) + (layout.spacing * math.max(0, visibleCount - 1))
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

    if visibleCount > 0 then
        root:Show()
    else
        root:Hide()
    end
end

function IncomingCastBoard:RenderBoard(runtimeState)
    local enabled, state = self:IsBoardEnabled(runtimeState)
    if not enabled then
        self:StopFadeTicker()
        self:ResetBoardState()
        return
    end

    if not self:EnsureRootFrame() then
        return
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

    clearTable(self.visibleRows)
    local visibleCount = 0
    for index = 1, #self.sortScratch do
        local record = self.sortScratch[index]
        local row = record and self.rowsByCaster[record.casterUnit] or nil
        if row then
            if visibleCount < BOARD_MAX_ROWS then
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
    local enabled = self:IsBoardEnabled(runtimeState)
    if not enabled then
        self:StopFadeTicker()
        self:ResetBoardState()
        return
    end

    if not self:EnsureRootFrame() then
        return
    end

    self:RenderBoard(runtimeState)
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
    record.uninterruptible = notInterruptible
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
            active.uninterruptible = type(UnitChannelInfo) == "function" and select(7, UnitChannelInfo(casterUnit)) or active.uninterruptible
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
        active.uninterruptible = type(UnitChannelInfo) == "function" and select(7, UnitChannelInfo(casterUnit)) or active.uninterruptible
    else
        active.duration = type(UnitCastingDuration) == "function" and UnitCastingDuration(casterUnit) or active.duration
        active.uninterruptible = type(UnitCastingInfo) == "function" and select(8, UnitCastingInfo(casterUnit)) or active.uninterruptible
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
