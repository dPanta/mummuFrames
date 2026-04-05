-- ============================================================================
-- GLOBAL FRAMES MODULE
-- ============================================================================
-- Provides reusable frame factories (unit frame base, castbar, power bars) and
-- shared visual behaviors (tooltips, click-casting registration, style apply).

local _, ns = ...

local addon = _G.mummuFrames
local Style = ns.Style
local Util = ns.Util

-- Shared factory for reusable frame widgets and styling helpers.
local GlobalFrames = ns.Object:Extend()
local ABSORB_OVERLAY_TEXTURE = "Interface\\AddOns\\mummuFrames\\Media\\o9.tga"
local RESTING_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\catzzz.png"
local LEADER_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\crown.png"
local COMBAT_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\swords.png"
local READY_CHECK_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local READY_CHECK_NOT_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local READY_CHECK_WAITING_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local SECONDARY_POWER_MAX_ICONS = 10
local SECONDARY_POWER_DISPLAY_MODE_ICONS = "icons"
local SECONDARY_POWER_DISPLAY_MODE_BAR = "bar"
local TERTIARY_POWER_MAX_STACK_OVERLAYS = 10
local TERTIARY_POWER_HEIGHT_BONUS = 5
local READY_CHECK_FINISHED_HOLD_SECONDS = 6
local DISPEL_ICON_BACKGROUND_COLOR = { 0.03, 0.05, 0.08, 0.94 }
local DISPEL_ICON_BORDER_COLOR = { 1.00, 1.00, 1.00, 0.16 }
local RESTING_ICON_TEXCOORD = { 0.25390625, 0.66796875, 0.138671875, 0.9130859375 } -- 260,684,142,935
local LEADER_ICON_TEXCOORD = { 0.25390625, 0.67578125, 0.138671875, 0.9130859375 } -- 260,692,142,935
local RESTING_ICON_ASPECT = 424 / 793
local LEADER_ICON_ASPECT = 432 / 793

-- Resolve a reliable unit token for tooltip/click-cast context.
local function getTooltipUnit(frame)
    if type(frame) ~= "table" then
        return nil
    end

    if type(frame.GetAttribute) == "function" then
        local okAttr, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if okAttr and type(attrUnit) == "string" and attrUnit ~= "" then
            return attrUnit
        end
    end
    if type(frame.unit) == "string" and frame.unit ~= "" then
        return frame.unit
    end
    if type(frame.displayedUnit) == "string" and frame.displayedUnit ~= "" then
        return frame.displayedUnit
    end
    if type(frame.unitToken) == "string" and frame.unitToken ~= "" then
        return frame.unitToken
    end

    return nil
end

-- Return whether the frame is protected and therefore combat-restricted.
local function isProtectedFrame(frame)
    if type(frame) ~= "table" then
        return false
    end
    if type(frame.IsProtected) ~= "function" then
        return false
    end
    local okProtected, protected = pcall(frame.IsProtected, frame)
    return okProtected and protected == true
end

-- Show the unit tooltip for a reusable frame built by this module.
local function showUnitTooltip(frame)
    if not frame then
        return
    end

    local unit = getTooltipUnit(frame)
    if not unit then
        return
    end

    if type(UnitFrame_OnEnter) == "function" then
        local ok = pcall(UnitFrame_OnEnter, frame)
        if ok then
            return
        end
    end

    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", 0, -2)
    end
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

-- Hide unit tooltip.
local function hideUnitTooltip(frame)
    if not frame then
        return
    end

    if type(UnitFrame_OnLeave) == "function" then
        UnitFrame_OnLeave(frame)
        return
    end

    GameTooltip:Hide()
end

-- Register frame for click-cast integrations (Blizzard and Clique).
local function registerFrameForClickCasting(frame)
    if not frame then
        return false
    end

    -- Secure click registration mutates protected buttons; defer in combat.
    if InCombatLockdown() and isProtectedFrame(frame) then
        return false
    end

    if type(frame.RegisterForClicks) == "function" then
        frame:RegisterForClicks("AnyDown", "AnyUp")
    end

    ---@diagnostic disable-next-line: undefined-field
    if _G.ClickCastFrames and type(_G.ClickCastFrames) == "table" then
        ---@diagnostic disable-next-line: undefined-field
        _G.ClickCastFrames[frame] = true
    end

    ---@diagnostic disable-next-line: undefined-field
    local clique = _G.Clique
    if clique and type(clique.RegisterFrame) == "function" then
        pcall(clique.RegisterFrame, clique, frame)
    end

    return true
end

local function setFrameEdgeThickness(frame, thickness)
    if type(frame) ~= "table" or type(thickness) ~= "number" then
        return
    end

    if frame.Top then
        frame.Top:SetHeight(thickness)
    end
    if frame.Bottom then
        frame.Bottom:SetHeight(thickness)
    end
    if frame.Left then
        frame.Left:SetWidth(thickness)
    end
    if frame.Right then
        frame.Right:SetWidth(thickness)
    end
end

local function setFrameEdgeColor(frame, red, green, blue, alpha)
    if type(frame) ~= "table" then
        return
    end

    local textures = {
        frame.Top,
        frame.Bottom,
        frame.Left,
        frame.Right,
    }
    for index = 1, #textures do
        local texture = textures[index]
        if texture and type(texture.SetColorTexture) == "function" then
            texture:SetColorTexture(red, green, blue, alpha)
        end
    end
end

local function createFrameEdgeSet(parent, drawLayer)
    local edgeFrame = CreateFrame("Frame", nil, parent)
    edgeFrame:SetAllPoints(parent)

    edgeFrame.Top = edgeFrame:CreateTexture(nil, drawLayer or "OVERLAY")
    edgeFrame.Top:SetPoint("TOPLEFT", edgeFrame, "TOPLEFT", 0, 0)
    edgeFrame.Top:SetPoint("TOPRIGHT", edgeFrame, "TOPRIGHT", 0, 0)

    edgeFrame.Bottom = edgeFrame:CreateTexture(nil, drawLayer or "OVERLAY")
    edgeFrame.Bottom:SetPoint("BOTTOMLEFT", edgeFrame, "BOTTOMLEFT", 0, 0)
    edgeFrame.Bottom:SetPoint("BOTTOMRIGHT", edgeFrame, "BOTTOMRIGHT", 0, 0)

    edgeFrame.Left = edgeFrame:CreateTexture(nil, drawLayer or "OVERLAY")
    edgeFrame.Left:SetPoint("TOPLEFT", edgeFrame, "TOPLEFT", 0, 0)
    edgeFrame.Left:SetPoint("BOTTOMLEFT", edgeFrame, "BOTTOMLEFT", 0, 0)

    edgeFrame.Right = edgeFrame:CreateTexture(nil, drawLayer or "OVERLAY")
    edgeFrame.Right:SetPoint("TOPRIGHT", edgeFrame, "TOPRIGHT", 0, 0)
    edgeFrame.Right:SetPoint("BOTTOMRIGHT", edgeFrame, "BOTTOMRIGHT", 0, 0)

    return edgeFrame
end

-- Create an optional overlay border that can be toggled for detached bar elements.
local function ensureDetachedBarBorder(frame)
    if not frame or frame.DetachedBarBorder then
        return
    end

    local border = {}

    border.top = frame:CreateTexture(nil, "OVERLAY")
    border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.top:SetColorTexture(0, 0, 0, 1)
    border.top:Hide()

    border.bottom = frame:CreateTexture(nil, "OVERLAY")
    border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetColorTexture(0, 0, 0, 1)
    border.bottom:Hide()

    border.left = frame:CreateTexture(nil, "OVERLAY")
    border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.left:SetColorTexture(0, 0, 0, 1)
    border.left:Hide()

    border.right = frame:CreateTexture(nil, "OVERLAY")
    border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.right:SetColorTexture(0, 0, 0, 1)
    border.right:Hide()

    frame.DetachedBarBorder = border
end

-- Update detached bar border thickness and visibility.
local function updateDetachedBarBorder(frame, shown, borderSize)
    local border = frame and frame.DetachedBarBorder or nil
    if not border then
        return
    end

    local size = tonumber(borderSize) or 1
    if size <= 0 then
        size = 1
    end
    border.top:SetHeight(size)
    border.bottom:SetHeight(size)
    border.left:SetWidth(size)
    border.right:SetWidth(size)
    border.top:SetShown(shown == true)
    border.bottom:SetShown(shown == true)
    border.left:SetShown(shown == true)
    border.right:SetShown(shown == true)
end

local function getSecondaryPowerDisplayMode(config)
    local displayMode = type(config) == "table" and config.displayMode or config
    if displayMode == SECONDARY_POWER_DISPLAY_MODE_BAR then
        return SECONDARY_POWER_DISPLAY_MODE_BAR
    end
    return SECONDARY_POWER_DISPLAY_MODE_ICONS
end

local function invalidateReadyCheckIndicatorHide(indicator)
    if not indicator then
        return nil
    end

    local nextToken = (tonumber(indicator._mummuReadyCheckHideToken) or 0) + 1
    indicator._mummuReadyCheckHideToken = nextToken
    return nextToken
end

local function scheduleReadyCheckIndicatorHide(indicator, delaySeconds)
    if not indicator then
        return
    end

    local holdSeconds = tonumber(delaySeconds) or READY_CHECK_FINISHED_HOLD_SECONDS
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end

    local hideToken = invalidateReadyCheckIndicatorHide(indicator)
    C_Timer.After(holdSeconds, function()
        if not indicator or indicator._mummuReadyCheckHideToken ~= hideToken then
            return
        end
        indicator._mummuReadyCheckStatus = nil
        indicator:Hide()
    end)
end

local function getReadyCheckStatusTexture(status)
    if status == "ready" then
        return READY_CHECK_READY_TEXTURE
    end
    if status == "notready" then
        return READY_CHECK_NOT_READY_TEXTURE
    end
    if status == "waiting" then
        return READY_CHECK_WAITING_TEXTURE
    end
    return nil
end

-- Initialize global frames state.
function GlobalFrames:Constructor()
    self.addon = nil
    self.clickCastFrames = setmetatable({}, { __mode = "k" })
    self.pendingStyleByFrame = setmetatable({}, { __mode = "k" })
end

-- Initialize global frames module.
function GlobalFrames:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable global frames module.
function GlobalFrames:OnEnable()
    ns.EventRouter:Register(self, "ADDON_LOADED", self.OnAddonLoaded)
    ns.EventRouter:Register(self, "PLAYER_REGEN_ENABLED", self.OnPlayerRegenEnabled)
    self:RegisterAllClickCastFrames()
end

-- Disable global frames module.
function GlobalFrames:OnDisable()
    ns.EventRouter:UnregisterOwner(self)
    self.pendingStyleByFrame = setmetatable({}, { __mode = "k" })
end

-- Handle addon loaded event.
function GlobalFrames:OnAddonLoaded(_, loadedAddonName)
    if loadedAddonName ~= "Clique" then
        return
    end

    self:RegisterAllClickCastFrames()
end

-- Queue style refresh for post-combat application.
function GlobalFrames:QueueStyleRefresh(frame, unitToken)
    if type(frame) ~= "table" then
        return
    end
    local resolvedUnitToken = type(unitToken) == "string" and unitToken or frame.unitToken
    if type(resolvedUnitToken) ~= "string" or resolvedUnitToken == "" then
        return
    end
    self.pendingStyleByFrame[frame] = resolvedUnitToken
end

-- Apply all queued styles once combat restrictions end.
function GlobalFrames:FlushQueuedStyles()
    if InCombatLockdown() then
        return
    end
    for frame, unitToken in pairs(self.pendingStyleByFrame) do
        self.pendingStyleByFrame[frame] = nil
        if frame and type(unitToken) == "string" and unitToken ~= "" then
            self:ApplyStyle(frame, unitToken)
        end
    end
end

-- Handle combat-end. Re-apply deferred click-cast registration and style.
function GlobalFrames:OnPlayerRegenEnabled()
    self:RegisterAllClickCastFrames()
    self:FlushQueuedStyles()
end

-- Register one frame for click-cast integrations.
function GlobalFrames:RegisterClickCastFrame(frame)
    if frame then
        self.clickCastFrames[frame] = true
    end
    registerFrameForClickCasting(frame)
end

-- Re-register all known frames for click-cast integrations.
function GlobalFrames:RegisterAllClickCastFrames()
    for frame in pairs(self.clickCastFrames) do
        registerFrameForClickCasting(frame)
    end
end

-- Create a styled status bar with the addon's standard background layer.
-- `role` scopes Dark Mode backing updates to health and primary power bars.
function GlobalFrames:CreateStatusBar(parent, role)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar._mummuStatusBarRole = type(role) == "string" and role or "generic"

    Style:ApplyStatusBarTexture(bar)

    -- Dark backing keeps depleted portions readable under overlays.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bar.Background = bg
    Style:ApplyStatusBarBacking(bar)

    return bar
end

-- Create a centered ready-check indicator using Blizzard's default textures.
function GlobalFrames:CreateReadyCheckIndicator(frame, overlayParent)
    if not frame or frame.ReadyCheckIndicator then
        return frame and frame.ReadyCheckIndicator or nil
    end

    local overlay = overlayParent
    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        overlay:SetAllPoints(frame)
        overlay:SetFrameStrata(frame:GetFrameStrata())
        overlay:SetFrameLevel(frame:GetFrameLevel() + 40)
        frame._mummuReadyCheckOverlayOwned = true
    end

    local indicator = overlay:CreateTexture(nil, "OVERLAY")
    indicator:SetPoint("CENTER", frame, "CENTER", 0, 0)
    indicator:SetAlpha(0.95)
    indicator:Hide()

    frame.ReadyCheckOverlay = overlay
    frame.ReadyCheckIndicator = indicator
    return indicator
end

-- Create the dispel fill, border accent, and corner icon shared by party/raid frames.
function GlobalFrames:CreateGroupDispelIndicator(frame, overlayParent)
    if not frame then
        return nil
    end
    if frame.DispelOverlay then
        return frame.DispelOverlay
    end

    local overlayTarget = overlayParent or frame
    local overlay = overlayTarget:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(overlayTarget)
    overlay:Hide()
    frame.DispelOverlay = overlay

    local border = createFrameEdgeSet(frame, "OVERLAY")
    border:SetFrameStrata(frame:GetFrameStrata())
    border:SetFrameLevel(frame:GetFrameLevel() + 34)
    if type(border.SetIgnoreParentAlpha) == "function" then
        border:SetIgnoreParentAlpha(true)
    end
    setFrameEdgeColor(border, 1, 1, 1, 0)
    border:Hide()
    frame.DispelBorder = border

    local iconFrame = createFrameEdgeSet(frame, "OVERLAY")
    iconFrame:SetFrameStrata(frame:GetFrameStrata())
    iconFrame:SetFrameLevel(frame:GetFrameLevel() + 35)
    if type(iconFrame.SetIgnoreParentAlpha) == "function" then
        iconFrame:SetIgnoreParentAlpha(true)
    end

    iconFrame.Background = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconFrame.Background:SetAllPoints(iconFrame)
    iconFrame.Background:SetColorTexture(
        DISPEL_ICON_BACKGROUND_COLOR[1],
        DISPEL_ICON_BACKGROUND_COLOR[2],
        DISPEL_ICON_BACKGROUND_COLOR[3],
        DISPEL_ICON_BACKGROUND_COLOR[4]
    )

    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    setFrameEdgeColor(
        iconFrame,
        DISPEL_ICON_BORDER_COLOR[1],
        DISPEL_ICON_BORDER_COLOR[2],
        DISPEL_ICON_BORDER_COLOR[3],
        DISPEL_ICON_BORDER_COLOR[4]
    )
    iconFrame:Hide()

    frame.DispelIconFrame = iconFrame
    frame.DispelIcon = iconFrame.Icon
    return overlay
end

-- Return a frame-height-derived size so the ready-check mark stays readable.
function GlobalFrames:GetReadyCheckIndicatorSize(frameHeight)
    local size = Util:Clamp(math.floor(((tonumber(frameHeight) or 24) * 0.62) + 0.5), 12, 36)
    if Style:IsPixelPerfectEnabled() then
        size = Style:Snap(size)
    end
    return size
end

-- Return the icon size used by party/raid dispel corner markers.
function GlobalFrames:GetGroupDispelIndicatorSize(frameHeight)
    local size = Util:Clamp(math.floor(((tonumber(frameHeight) or 24) * 0.72) + 0.5), 14, 30)
    if Style:IsPixelPerfectEnabled() then
        size = Style:Snap(size)
    end
    return size
end

-- Re-anchor and resize the centered ready-check indicator for the current layout.
function GlobalFrames:LayoutReadyCheckIndicator(frame, frameHeight)
    if not frame or not frame.ReadyCheckIndicator then
        return
    end

    if frame._mummuReadyCheckOverlayOwned == true and frame.ReadyCheckOverlay then
        frame.ReadyCheckOverlay:SetAllPoints(frame)
        frame.ReadyCheckOverlay:SetFrameStrata(frame:GetFrameStrata())
        frame.ReadyCheckOverlay:SetFrameLevel(frame:GetFrameLevel() + 40)
    end

    local size = self:GetReadyCheckIndicatorSize(frameHeight)
    frame.ReadyCheckIndicator:ClearAllPoints()
    frame.ReadyCheckIndicator:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.ReadyCheckIndicator:SetSize(size, size)
end

-- Re-anchor and resize the group dispel overlay pieces for the current frame size.
function GlobalFrames:LayoutGroupDispelIndicator(frame, frameHeight)
    if not frame or not frame.DispelOverlay then
        return
    end

    local pixelPerfect = Style:IsPixelPerfectEnabled()
    local pixelSize = pixelPerfect and Style:GetPixelSize() or 1
    local edgeThickness = pixelPerfect and pixelSize or 2
    local iconEdgeThickness = pixelPerfect and pixelSize or 1
    local iconInset = pixelPerfect and Style:Snap(1) or 1
    local iconPadding = pixelPerfect and pixelSize or 1
    local iconSize = self:GetGroupDispelIndicatorSize(frameHeight)
    local overlayTarget = frame.HealthBar or frame

    frame.DispelOverlay:SetAllPoints(overlayTarget)

    if frame.DispelBorder then
        frame.DispelBorder:SetAllPoints(frame)
        frame.DispelBorder:SetFrameStrata(frame:GetFrameStrata())
        frame.DispelBorder:SetFrameLevel(frame:GetFrameLevel() + 34)
        setFrameEdgeThickness(frame.DispelBorder, edgeThickness)
    end

    if frame.DispelIconFrame then
        frame.DispelIconFrame:SetFrameStrata(frame:GetFrameStrata())
        frame.DispelIconFrame:SetFrameLevel(frame:GetFrameLevel() + 35)
        frame.DispelIconFrame:ClearAllPoints()
        frame.DispelIconFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -iconInset, iconInset)
        frame.DispelIconFrame:SetSize(iconSize, iconSize)
        setFrameEdgeThickness(frame.DispelIconFrame, iconEdgeThickness)

        if frame.DispelIcon then
            frame.DispelIcon:ClearAllPoints()
            frame.DispelIcon:SetPoint("TOPLEFT", frame.DispelIconFrame, "TOPLEFT", iconPadding, -iconPadding)
            frame.DispelIcon:SetPoint("BOTTOMRIGHT", frame.DispelIconFrame, "BOTTOMRIGHT", -iconPadding, iconPadding)
        end
    end
end

-- Refresh one frame's ready-check state, including the post-finish hold window.
function GlobalFrames:RefreshReadyCheckIndicator(frame, unitToken, eventName, previewMode)
    local indicator = frame and frame.ReadyCheckIndicator or nil
    if not indicator then
        return
    end

    local effectiveUnit = type(unitToken) == "string" and unitToken or getTooltipUnit(frame)
    if previewMode == true or type(GetReadyCheckStatus) ~= "function" or type(effectiveUnit) ~= "string" or effectiveUnit == "" then
        invalidateReadyCheckIndicatorHide(indicator)
        indicator._mummuReadyCheckStatus = nil
        indicator:Hide()
        return
    end

    local status = GetReadyCheckStatus(effectiveUnit)
    local texture = getReadyCheckStatusTexture(status)
    if texture then
        invalidateReadyCheckIndicatorHide(indicator)
        indicator:SetTexture(texture)
        indicator:Show()
        indicator._mummuReadyCheckStatus = status
    elseif eventName ~= "READY_CHECK_FINISHED" then
        invalidateReadyCheckIndicatorHide(indicator)
        indicator._mummuReadyCheckStatus = nil
        indicator:Hide()
    end

    if eventName == "READY_CHECK_FINISHED" and indicator:IsShown() then
        if indicator._mummuReadyCheckStatus == "waiting" then
            indicator:SetTexture(READY_CHECK_NOT_READY_TEXTURE)
            indicator._mummuReadyCheckStatus = "notready"
        end
        scheduleReadyCheckIndicatorHide(indicator, READY_CHECK_FINISHED_HOLD_SECONDS)
    end
end

-- Create the resting, leader, and combat badges shown above player frames.
function GlobalFrames:CreatePlayerStatusIcons(frame)
    local container = CreateFrame("Frame", nil, frame)
    container:SetFrameStrata("HIGH")
    container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 2)
    container:SetSize(52, 14)
    container:Hide()

    local resting = CreateFrame("Frame", nil, container)
    resting:SetSize(14, 14)
    resting.Icon = resting:CreateTexture(nil, "ARTWORK")
    resting.Icon:SetAllPoints()
    resting.Icon:SetTexture(RESTING_ICON_TEXTURE)
    resting.Icon:SetTexCoord(
        RESTING_ICON_TEXCOORD[1],
        RESTING_ICON_TEXCOORD[2],
        RESTING_ICON_TEXCOORD[3],
        RESTING_ICON_TEXCOORD[4]
    )
    resting:Hide()

    local leader = CreateFrame("Frame", nil, container)
    leader:SetSize(14, 14)
    leader.Icon = leader:CreateTexture(nil, "ARTWORK")
    leader.Icon:SetAllPoints()
    leader.Icon:SetTexture(LEADER_ICON_TEXTURE)
    leader.Icon:SetTexCoord(
        LEADER_ICON_TEXCOORD[1],
        LEADER_ICON_TEXCOORD[2],
        LEADER_ICON_TEXCOORD[3],
        LEADER_ICON_TEXCOORD[4]
    )
    leader:Hide()

    local combat = CreateFrame("Frame", nil, container)
    combat:SetSize(14, 14)
    combat.Icon = combat:CreateTexture(nil, "ARTWORK")
    combat.Icon:SetAllPoints()
    combat.Icon:SetTexture(COMBAT_ICON_TEXTURE)
    combat:Hide()

    frame.StatusIconContainer = container
    frame.StatusIcons = {
        Resting = resting,
        Leader = leader,
        Combat = combat,
    }
end

-- Create the secondary-resource container used for icon pips and segmented bars.
function GlobalFrames:CreateSecondaryPowerBar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(frame:GetFrameLevel() + 20)
    bar:SetSize(120, 16)
    bar:SetClampedToScreen(true)
    bar:Hide()
    bar.Background = Style:CreateBackground(bar, 0.06, 0.06, 0.07, 0.9)
    bar.Background:Hide()

    bar.Icons = {}
    for i = 1, SECONDARY_POWER_MAX_ICONS do
        local icon = bar:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()
        bar.Icons[i] = icon
    end

    bar.Segments = {}
    for i = 1, SECONDARY_POWER_MAX_ICONS do
        local segment = self:CreateStatusBar(bar, "secondaryPower")
        segment:SetMinMaxValues(0, 1)
        segment:SetValue(0)
        segment:Hide()
        bar.Segments[i] = segment
    end

    frame.SecondaryPowerBar = bar
end

-- Create the tertiary resource bar used for stagger, Ironfur, and other overlays.
function GlobalFrames:CreateTertiaryPowerBar(frame)
    local container = CreateFrame("Frame", nil, frame)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(frame:GetFrameLevel() + 19)
    container:SetSize(120, 13)
    container:SetClampedToScreen(true)
    container:Hide()

    local borderSize = 1
    local borderTop = container:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)
    borderTop:SetColorTexture(0.2, 0.2, 0.2, 1)
    local borderBottom = container:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(borderSize)
    borderBottom:SetColorTexture(0.2, 0.2, 0.2, 1)
    -- Border textures stay separate so width/height changes are cheap.
    local borderLeft = container:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)
    borderLeft:SetColorTexture(0.2, 0.2, 0.2, 1)
    local borderRight = container:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)
    borderRight:SetColorTexture(0.2, 0.2, 0.2, 1)

    local bar = self:CreateStatusBar(container)
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -borderSize, borderSize)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.32, 0.68, 0.29, 0.95)

    -- OverlayBar renders transient overlays such as stagger carryover.
    local overlayBar = CreateFrame("StatusBar", nil, container)
    overlayBar:SetAllPoints(bar)
    overlayBar:SetFrameStrata(container:GetFrameStrata())
    overlayBar:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlayBar:SetMinMaxValues(0, 1)
    overlayBar:SetValue(0)
    overlayBar:SetStatusBarColor(0.95, 0.85, 0.36, 0.55)
    Style:ApplyStatusBarTexture(overlayBar)

    local valueText = bar:CreateFontString(nil, "OVERLAY", nil)
    valueText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    valueText:SetJustifyH("RIGHT")
    valueText:SetDrawLayer("OVERLAY", 7)

    local rightGlow = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    rightGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    rightGlow:SetBlendMode("ADD")
    rightGlow:SetVertexColor(0.70, 0.88, 1.00, 0.45)
    rightGlow:SetPoint("CENTER", bar, "RIGHT", 0, 0)
    rightGlow:SetSize(24, 28)
    rightGlow:Hide()

    container.Bar = bar
    container.OverlayBar = overlayBar
    container.ValueText = valueText
    container.RightGlow = rightGlow
    container.StackOverlays = {}
    container.StackRightGlows = {}
    for i = 1, TERTIARY_POWER_MAX_STACK_OVERLAYS do
        local overlaySubLevel = -9 + i -- Keeps stack overlays inside valid sublevel range [-8, 7].
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, overlaySubLevel)
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        overlay:SetWidth(0)
        overlay:Hide()
        container.StackOverlays[i] = overlay

        local glowSubLevel = overlaySubLevel + 1
        local stackGlow = bar:CreateTexture(nil, "OVERLAY", nil, glowSubLevel)
        stackGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        stackGlow:SetBlendMode("ADD")
        stackGlow:SetVertexColor(0.74, 0.91, 1.00, 0.42)
        stackGlow:SetPoint("CENTER", bar, "RIGHT", 0, 0)
        stackGlow:SetSize(24, 30)
        stackGlow:Hide()
        container.StackRightGlows[i] = stackGlow
    end

    frame.TertiaryPowerBar = container
end

-- Create cast bar.
function GlobalFrames:CreateCastBar(frame)
    -- Create frame for container.
    local container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(200, 20)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:Hide()

    local borderSize = 1
    -- Create texture for border top.
    local borderTop = container:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)
    borderTop:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border bottom.
    local borderBottom = container:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(borderSize)
    borderBottom:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border left.
    local borderLeft = container:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)
    borderLeft:SetColorTexture(1, 1, 1, 1)
    -- Create texture for border right.
    local borderRight = container:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)
    borderRight:SetColorTexture(1, 1, 1, 1)
    container.BorderTextures = { borderTop, borderBottom, borderLeft, borderRight }

    container.Background = Style:CreateBackground(container, 0.06, 0.06, 0.07, 0.9)

    local inset = borderSize
    local iconSize = 20
    -- Create texture layer.
    container.Icon = container:CreateTexture(nil, "ARTWORK")
    container.Icon:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -inset)
    container.Icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", inset, inset)
    container.Icon:SetWidth(iconSize)
    container.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local bar = self:CreateStatusBar(container)
    bar:SetPoint("TOPLEFT", container.Icon, "TOPRIGHT", 1, 0)
    bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, inset)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.29, 0.52, 0.90, 1)
    container.Bar = bar

    local empowerOverlay = CreateFrame("Frame", nil, bar)
    empowerOverlay:SetAllPoints(bar)
    empowerOverlay:SetFrameLevel(bar:GetFrameLevel() + 5)
    container.EmpowerOverlay = empowerOverlay
    container.EmpowerMarkers = {}

    -- Create text font string.
    container.SpellText = bar:CreateFontString(nil, "OVERLAY")
    container.SpellText:SetDrawLayer("OVERLAY", 7)
    container.SpellText:SetJustifyH("LEFT")

    -- Create text font string.
    container.TimeText = bar:CreateFontString(nil, "OVERLAY")
    container.TimeText:SetDrawLayer("OVERLAY", 7)
    container.TimeText:SetJustifyH("RIGHT")

    frame.CastBar = container
end

-- Create unit frame base.
function GlobalFrames:CreateUnitFrameBase(name, parent, unitToken, width, height)
    -- Create button for frame.
    local frame = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate")
    frame.unitToken = unitToken

    frame:SetSize(width, height)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetAttribute("unit", unitToken)
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame.unit = unitToken
    frame.displayedUnit = unitToken
    self:RegisterClickCastFrame(frame)
    frame:SetScript("OnEnter", showUnitTooltip)
    frame:SetScript("OnLeave", hideUnitTooltip)

    frame.Background = Style:CreateBackground(frame, 0.06, 0.06, 0.07, 0.9)
    frame.HealthBar = self:CreateStatusBar(frame, "health")
    frame.PowerBar = self:CreateStatusBar(frame, "primaryPower")
    ensureDetachedBarBorder(frame.PowerBar)

    -- Create text font string.
    frame.NameText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.NameText:SetDrawLayer("OVERLAY", 7)
    frame.NameText:SetJustifyH("LEFT")

    -- Create text font string.
    frame.HealthText = frame.HealthBar:CreateFontString(nil, "OVERLAY")
    frame.HealthText:SetDrawLayer("OVERLAY", 7)
    frame.HealthText:SetJustifyH("RIGHT")

    -- Create frame widget. Nothing exploded yet.
    frame.AbsorbOverlayFrame = CreateFrame("Frame", nil, frame.HealthBar)
    frame.AbsorbOverlayFrame:SetAllPoints(frame.HealthBar)
    frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
    frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
    frame.AbsorbOverlayFrame:Hide()

    -- Create frame widget.
    frame.AbsorbOverlayBar = CreateFrame("StatusBar", nil, frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetAllPoints(frame.AbsorbOverlayFrame)
    frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
    frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
    frame.AbsorbOverlayBar:SetMinMaxValues(0, 1)
    frame.AbsorbOverlayBar:SetValue(0)
    frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
    frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    frame.AbsorbOverlayBar:Hide()

    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        self:CreateCastBar(frame)
    end

    self:CreateReadyCheckIndicator(frame)

    if unitToken == "player" then
        self:CreatePlayerStatusIcons(frame)
        self:CreateSecondaryPowerBar(frame)
        self:CreateTertiaryPowerBar(frame)
        ensureDetachedBarBorder(frame.TertiaryPowerBar)
    end

    self:ApplyStyle(frame, unitToken)
    return frame
end

-- Apply style settings to unit frame.
-- Layout/anchor mutations are deferred while in combat; visual-only updates are
-- still applied so textures/fonts remain consistent until combat ends.
function GlobalFrames:ApplyStyle(frame, unitToken)
    local dataHandle = self.addon and self.addon:GetModule("dataHandle")
    if not dataHandle or not frame then
        return
    end

    local unitConfig = dataHandle:GetUnitConfig(unitToken)
    if type(unitConfig) ~= "table" then
        return
    end

    local profile = dataHandle:GetProfile()
    local styleConfig = profile and profile.style or nil
    local pixelPerfect = Style:IsPixelPerfectEnabled()
    local inCombat = InCombatLockdown()
    local allowLayout = not inCombat

    -- Secure unit buttons and detached anchor points can be protected in combat.
    -- Queue a full style pass for combat-end and only apply non-layout visual updates now.
    if inCombat then
        self:QueueStyleRefresh(frame, unitToken)
    end

    local width = Util:Clamp(tonumber(unitConfig.width) or 220, 100, 600)
    local height = Util:Clamp(tonumber(unitConfig.height) or 44, 18, 160)
    local powerHeight = Util:Clamp(tonumber(unitConfig.powerHeight) or 10, 4, height - 6)
    local configuredFontSize = tonumber(unitConfig.fontSize)
        or (styleConfig and tonumber(styleConfig.fontSize))
        or 12
    local fontSize = Util:Clamp(configuredFontSize, 8, 26)
    local x = tonumber(unitConfig.x) or 0
    local y = tonumber(unitConfig.y) or 0

    if pixelPerfect then
        width = Style:Snap(width)
        height = Style:Snap(height)
        powerHeight = Style:Snap(powerHeight)
        x = Style:Snap(x)
        y = Style:Snap(y)
    else
        width = math.floor(width + 0.5)
        height = math.floor(height + 0.5)
        powerHeight = math.floor(powerHeight + 0.5)
        x = math.floor(x + 0.5)
        y = math.floor(y + 0.5)
    end
    fontSize = math.floor(fontSize + 0.5)

    if allowLayout then
        frame:SetSize(width, height)
        frame:ClearAllPoints()
        frame:SetPoint(
            unitConfig.point or "CENTER",
            UIParent,
            unitConfig.relativePoint or "CENTER",
            x,
            y
        )
    end

    Style:ApplyStatusBarTexture(frame.HealthBar)
    Style:ApplyStatusBarTexture(frame.PowerBar)
    Style:ApplyStatusBarBacking(frame.HealthBar, "health")
    Style:ApplyStatusBarBacking(frame.PowerBar, "primaryPower")
    if frame.AbsorbOverlayBar and frame.AbsorbOverlayFrame then
        frame.AbsorbOverlayFrame:SetFrameStrata(frame.HealthBar:GetFrameStrata())
        frame.AbsorbOverlayFrame:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 5)
        frame.AbsorbOverlayBar:SetFrameStrata(frame.AbsorbOverlayFrame:GetFrameStrata())
        frame.AbsorbOverlayBar:SetFrameLevel(frame.AbsorbOverlayFrame:GetFrameLevel() + 1)
        frame.AbsorbOverlayBar:SetStatusBarTexture(ABSORB_OVERLAY_TEXTURE)
        frame.AbsorbOverlayBar:SetStatusBarColor(0.78, 0.92, 1, 0.72)
    end

    local border = pixelPerfect and Style:GetPixelSize() or 1
    local textInset = pixelPerfect and Style:Snap(6) or 6
    local primaryPowerConfig = unitConfig.primaryPower or {}
    local primaryPowerEnabled = primaryPowerConfig.enabled ~= false
    local primaryPowerDetached = unitToken == "player" and primaryPowerEnabled and primaryPowerConfig.detached == true
    local defaultPrimaryWidth = math.floor((width - (border * 2)) + 0.5)
    local primaryWidth = defaultPrimaryWidth
    if unitToken == "player" then
        primaryWidth = Util:Clamp(tonumber(primaryPowerConfig.width) or defaultPrimaryWidth, 80, 600)
    else
        primaryWidth = Util:Clamp(defaultPrimaryWidth, 80, 600)
    end

    if pixelPerfect then
        primaryWidth = Style:Snap(primaryWidth)
    else
        primaryWidth = math.floor(primaryWidth + 0.5)
    end

    if allowLayout then
        frame.PowerBar:ClearAllPoints()
        frame.HealthBar:ClearAllPoints()
        if not primaryPowerEnabled then
            frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
            frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
            frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
            frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
            frame.PowerBar:SetSize(primaryWidth, powerHeight)
        elseif primaryPowerDetached then
            local ppX = tonumber(primaryPowerConfig.x) or 0
            local ppY = tonumber(primaryPowerConfig.y) or 0
            if pixelPerfect then
                ppX = Style:Snap(ppX)
                ppY = Style:Snap(ppY)
            else
                ppX = math.floor(ppX + 0.5)
                ppY = math.floor(ppY + 0.5)
            end

            frame.PowerBar:SetSize(primaryWidth, powerHeight)
            frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
            frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
            frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
            frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
            frame.PowerBar:SetPoint("CENTER", UIParent, "CENTER", ppX, ppY)
        else
            local healthOffset = powerHeight + (border * 2)
            frame.PowerBar:SetSize(primaryWidth, powerHeight)

            if unitConfig.powerOnTop then
                frame.PowerBar:SetPoint("TOP", frame, "TOP", 0, -border)
                frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -healthOffset)
                frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -healthOffset)
                frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, border)
                frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
            else
                frame.PowerBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, border)
                frame.HealthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
                frame.HealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -border, -border)
                frame.HealthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", border, healthOffset)
                frame.HealthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, healthOffset)
            end
        end
    end
    frame.PowerBar._detached = primaryPowerDetached
    frame.PowerBar._enabled = primaryPowerEnabled
    updateDetachedBarBorder(frame.PowerBar, primaryPowerDetached and primaryPowerEnabled, border)

    if allowLayout then
        frame.NameText:ClearAllPoints()
        frame.NameText:SetPoint("LEFT", frame.HealthBar, "LEFT", textInset, 0)
        frame.NameText:SetPoint("RIGHT", frame.HealthText, "LEFT", -textInset, 0)

        frame.HealthText:ClearAllPoints()
        frame.HealthText:SetPoint("RIGHT", frame.HealthBar, "RIGHT", -textInset, 0)
    end

    Style:ApplyFont(frame.NameText, fontSize, "OUTLINE")
    Style:ApplyFont(frame.HealthText, fontSize, "OUTLINE")

    if not frame.NameText:GetFont() and GameFontHighlightSmall then
        frame.NameText:SetFontObject(GameFontHighlightSmall)
    end
    if not frame.HealthText:GetFont() and GameFontHighlightSmall then
        frame.HealthText:SetFontObject(GameFontHighlightSmall)
    end

    frame.NameText:SetTextColor(1, 1, 1, 1)
    frame.HealthText:SetTextColor(1, 1, 1, 1)
    frame.NameText:SetShadowColor(0, 0, 0, 0)
    frame.HealthText:SetShadowColor(0, 0, 0, 0)
    frame.NameText:SetShadowOffset(0, 0)
    frame.HealthText:SetShadowOffset(0, 0)

    frame.NameText:SetShown(true)
    frame.HealthText:SetShown(unitConfig.showHealthText ~= false)

    if frame.StatusIcons and frame.StatusIconContainer then
        local iconSize = Util:Clamp((fontSize + 1) * 5, 40, 96)
        local combatIconSize = math.max(1, math.floor((iconSize * 0.75) + 0.5))
        local badgeSpacing = pixelPerfect and Style:Snap(4) or 4
        local restingWidth = math.floor((iconSize * RESTING_ICON_ASPECT) + 0.5)
        local leaderHeight = math.max(1, math.floor((iconSize / 3) + 0.5))
        local leaderWidth = math.max(1, math.floor((leaderHeight * LEADER_ICON_ASPECT) + 0.5))

        if allowLayout then
            frame.StatusIconContainer:ClearAllPoints()
            frame.StatusIconContainer:SetPoint("CENTER", frame, "TOPLEFT", 0, 0)
            frame.StatusIconContainer:SetSize(restingWidth + leaderWidth + badgeSpacing, iconSize)

            frame.StatusIcons.Resting:SetSize(restingWidth, iconSize)
            frame.StatusIcons.Leader:SetSize(leaderWidth, leaderHeight)
            frame.StatusIcons.Combat:SetSize(combatIconSize, combatIconSize)
        end

        frame.StatusIcons.Resting.Icon:SetAllPoints()
        frame.StatusIcons.Resting.Icon:SetTexture(RESTING_ICON_TEXTURE)
        frame.StatusIcons.Resting.Icon:SetTexCoord(
            RESTING_ICON_TEXCOORD[1],
            RESTING_ICON_TEXCOORD[2],
            RESTING_ICON_TEXCOORD[3],
            RESTING_ICON_TEXCOORD[4]
        )

        frame.StatusIcons.Leader.Icon:SetAllPoints()
        frame.StatusIcons.Leader.Icon:SetTexture(LEADER_ICON_TEXTURE)
        frame.StatusIcons.Leader.Icon:SetTexCoord(
            LEADER_ICON_TEXCOORD[1],
            LEADER_ICON_TEXCOORD[2],
            LEADER_ICON_TEXCOORD[3],
            LEADER_ICON_TEXCOORD[4]
        )

        frame.StatusIcons.Combat.Icon:SetAllPoints()
        frame.StatusIcons.Combat.Icon:SetTexture(COMBAT_ICON_TEXTURE)
    end

    if frame.ReadyCheckIndicator then
        self:LayoutReadyCheckIndicator(frame, height)
    end

    if frame.SecondaryPowerBar then
        local secondaryConfig = unitConfig.secondaryPower or {}
        local spEnabled = unitToken == "player" and secondaryConfig.enabled ~= false
        local spDetached = secondaryConfig.detached == true
        local spDisplayMode = getSecondaryPowerDisplayMode(secondaryConfig)
        local defaultSpSize = math.floor((fontSize * 1.35) + 0.5)
        local configuredSpSize = tonumber(secondaryConfig.size) or defaultSpSize
        local spIconSize = Util:Clamp(math.floor(configuredSpSize + 0.5), 8, 60)
        local defaultSpBarHeight = math.floor((fontSize * 0.75) + 0.5)
        local configuredSpBarHeight = tonumber(secondaryConfig.height) or defaultSpBarHeight
        local spBarHeight = Util:Clamp(math.floor(configuredSpBarHeight + 0.5), 4, 40)
        local spHeight = spDisplayMode == SECONDARY_POWER_DISPLAY_MODE_BAR and spBarHeight or spIconSize
        local defaultSpWidth = nil
        if spDisplayMode == SECONDARY_POWER_DISPLAY_MODE_BAR then
            defaultSpWidth = Util:Clamp(math.floor((width - (border * 2)) + 0.5), 80, 600)
        else
            defaultSpWidth = Util:Clamp(math.max(math.floor((width * 0.75) + 0.5), spIconSize * 8), 80, 600)
        end
        local configuredSpWidth = tonumber(secondaryConfig.width) or defaultSpWidth
        local spWidth = nil
        if spDisplayMode == SECONDARY_POWER_DISPLAY_MODE_BAR then
            if spDetached then
                spWidth = Util:Clamp(configuredSpWidth, 80, 600)
            else
                local attachedMaxWidth = Util:Clamp(math.floor((width - (border * 2)) + 0.5), 80, 600)
                spWidth = Util:Clamp(math.min(configuredSpWidth, attachedMaxWidth), 80, attachedMaxWidth)
            end
        else
            local minSpWidth = Util:Clamp(spIconSize * 8, 80, 600)
            spWidth = Util:Clamp(math.max(configuredSpWidth, minSpWidth), 80, 600)
        end

        if pixelPerfect then
            spHeight = Style:Snap(spHeight)
            spWidth = Style:Snap(spWidth)
        else
            spHeight = math.floor(spHeight + 0.5)
            spWidth = math.floor(spWidth + 0.5)
        end

        if frame.SecondaryPowerBar.Segments then
            for i = 1, #frame.SecondaryPowerBar.Segments do
                local segment = frame.SecondaryPowerBar.Segments[i]
                if segment then
                    Style:ApplyStatusBarTexture(segment)
                    Style:ApplyStatusBarBacking(segment, "secondaryPower")
                end
            end
        end
        if frame.SecondaryPowerBar.Background then
            frame.SecondaryPowerBar.Background:SetShown(spEnabled and spDisplayMode == SECONDARY_POWER_DISPLAY_MODE_BAR)
        end

        if allowLayout then
            frame.SecondaryPowerBar:ClearAllPoints()
            frame.SecondaryPowerBar:SetSize(spWidth, spHeight)

            if spDetached then
                local spX = tonumber(secondaryConfig.x) or 0
                local spY = tonumber(secondaryConfig.y) or 0
                if pixelPerfect then
                    spX = Style:Snap(spX)
                    spY = Style:Snap(spY)
                else
                    spX = math.floor(spX + 0.5)
                    spY = math.floor(spY + 0.5)
                end
                frame.SecondaryPowerBar:SetPoint("CENTER", UIParent, "CENTER", spX, spY)
            elseif spDisplayMode == SECONDARY_POWER_DISPLAY_MODE_BAR then
                frame.SecondaryPowerBar:SetPoint("TOP", frame.HealthBar, "TOP", 0, -border)
            else
                local spOffsetY = pixelPerfect and Style:Snap(8) or 8
                frame.SecondaryPowerBar:SetPoint("BOTTOM", frame, "TOP", 0, spOffsetY)
            end
        end

        frame.SecondaryPowerBar._enabled = spEnabled
        frame.SecondaryPowerBar._detached = spDetached
        frame.SecondaryPowerBar._displayMode = spDisplayMode
    end

    if frame.TertiaryPowerBar then
        local tertiaryConfig = unitConfig.tertiaryPower or {}
        local tpEnabled = unitToken == "player" and tertiaryConfig.enabled ~= false
        local tpDetached = tertiaryConfig.detached == true
        local defaultTpHeight = math.floor((fontSize * 0.68) + 0.5)
        local configuredTpHeight = tonumber(tertiaryConfig.height) or defaultTpHeight
        local tpHeight = Util:Clamp(math.floor(configuredTpHeight + TERTIARY_POWER_HEIGHT_BONUS + 0.5), 6, 32)
        local defaultTpWidth = Util:Clamp(math.floor((width - (border * 2)) + 0.5), 80, 520)
        local tpWidth = Util:Clamp(tonumber(tertiaryConfig.width) or defaultTpWidth, 80, 600)

        if pixelPerfect then
            tpHeight = Style:Snap(tpHeight)
            tpWidth = Style:Snap(tpWidth)
        else
            tpHeight = math.floor(tpHeight + 0.5)
            tpWidth = math.floor(tpWidth + 0.5)
        end

        Style:ApplyStatusBarTexture(frame.TertiaryPowerBar.Bar)
        Style:ApplyStatusBarBacking(frame.TertiaryPowerBar.Bar)
        Style:ApplyStatusBarTexture(frame.TertiaryPowerBar.OverlayBar)
        Style:ApplyFont(frame.TertiaryPowerBar.ValueText, 24, "OUTLINE")
        frame.TertiaryPowerBar.ValueText:SetTextColor(1, 1, 1, 1)
        frame.TertiaryPowerBar.ValueText:SetShadowColor(0, 0, 0, 0)
        frame.TertiaryPowerBar.ValueText:SetShadowOffset(0, 0)

        if allowLayout then
            frame.TertiaryPowerBar:ClearAllPoints()
            frame.TertiaryPowerBar:SetSize(tpWidth, tpHeight)
            if tpDetached then
                local tpX = tonumber(tertiaryConfig.x) or 0
                local tpY = tonumber(tertiaryConfig.y) or 0
                if pixelPerfect then
                    tpX = Style:Snap(tpX)
                    tpY = Style:Snap(tpY)
                else
                    tpX = math.floor(tpX + 0.5)
                    tpY = math.floor(tpY + 0.5)
                end
                frame.TertiaryPowerBar:SetPoint("CENTER", UIParent, "CENTER", tpX, tpY)
            else
                frame.TertiaryPowerBar:SetPoint("TOP", frame, "TOP", 0, -border)
            end
        end

        frame.TertiaryPowerBar._enabled = tpEnabled
        frame.TertiaryPowerBar._detached = tpDetached
        updateDetachedBarBorder(frame.TertiaryPowerBar, tpDetached and tpEnabled, border)
    end

    if frame.CastBar then
        local castbarConfig = unitConfig.castbar or {}
        local cbEnabled = castbarConfig.enabled ~= false
        local cbDetached = castbarConfig.detached == true
        local cbWidth = Util:Clamp(tonumber(castbarConfig.width) or width, 50, 600)
        local cbHeight = Util:Clamp(tonumber(castbarConfig.height) or 20, 8, 40)

        if pixelPerfect then
            cbWidth = Style:Snap(cbWidth)
            cbHeight = Style:Snap(cbHeight)
        else
            cbWidth = math.floor(cbWidth + 0.5)
            cbHeight = math.floor(cbHeight + 0.5)
        end

        if allowLayout then
            frame.CastBar:ClearAllPoints()
            if cbDetached then
                local cbX = tonumber(castbarConfig.x) or 0
                local cbY = tonumber(castbarConfig.y) or 0
                if pixelPerfect then
                    cbX = Style:Snap(cbX)
                    cbY = Style:Snap(cbY)
                else
                    cbX = math.floor(cbX + 0.5)
                    cbY = math.floor(cbY + 0.5)
                end
                frame.CastBar:SetSize(cbWidth, cbHeight)
                frame.CastBar:SetPoint("CENTER", UIParent, "CENTER", cbX, cbY)
            else
                frame.CastBar:SetSize(width, cbHeight)
                frame.CastBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -border)
                frame.CastBar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -border)
            end
        end

        local cbBorderInset = 1
        if frame.CastBar.BorderTextures then
            for _, tex in ipairs(frame.CastBar.BorderTextures) do
                tex:SetColorTexture(0.2, 0.2, 0.2, 1)
            end
        end

        local cbShowIcon = castbarConfig.showIcon ~= false
        frame.CastBar.Icon:SetShown(cbShowIcon)
        if allowLayout then
            local innerHeight = cbHeight - cbBorderInset * 2
            frame.CastBar.Icon:SetWidth(cbShowIcon and math.max(1, innerHeight) or 0)
            frame.CastBar.Bar:ClearAllPoints()
            if cbShowIcon then
                frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar.Icon, "TOPRIGHT", 1, 0)
            else
                frame.CastBar.Bar:SetPoint("TOPLEFT", frame.CastBar, "TOPLEFT", cbBorderInset, -cbBorderInset)
            end
            frame.CastBar.Bar:SetPoint("BOTTOMRIGHT", frame.CastBar, "BOTTOMRIGHT", -cbBorderInset, cbBorderInset)
        end

        Style:ApplyStatusBarTexture(frame.CastBar.Bar)
        Style:ApplyStatusBarBacking(frame.CastBar.Bar)

        local cbTextInset = pixelPerfect and Style:Snap(4) or 4
        local cbFontSize = Util:Clamp(math.floor(cbHeight * 0.55 + 0.5), 8, 20)
        if allowLayout then
            frame.CastBar.SpellText:ClearAllPoints()
            frame.CastBar.SpellText:SetPoint("LEFT", frame.CastBar.Bar, "LEFT", cbTextInset, 0)
            frame.CastBar.SpellText:SetPoint("RIGHT", frame.CastBar.TimeText, "LEFT", -cbTextInset, 0)

            frame.CastBar.TimeText:ClearAllPoints()
            frame.CastBar.TimeText:SetPoint("RIGHT", frame.CastBar.Bar, "RIGHT", -cbTextInset, 0)
        end

        Style:ApplyFont(frame.CastBar.SpellText, cbFontSize, "OUTLINE")
        Style:ApplyFont(frame.CastBar.TimeText, cbFontSize, "OUTLINE")
        frame.CastBar.SpellText:SetTextColor(1, 1, 1, 1)
        frame.CastBar.TimeText:SetTextColor(1, 1, 1, 1)
        frame.CastBar.SpellText:SetShadowColor(0, 0, 0, 0)
        frame.CastBar.TimeText:SetShadowColor(0, 0, 0, 0)
        frame.CastBar.SpellText:SetShadowOffset(0, 0)
        frame.CastBar.TimeText:SetShadowOffset(0, 0)

        frame.CastBar._enabled = cbEnabled
        frame.CastBar._detached = cbDetached
    end
end

addon:RegisterModule("globalFrames", GlobalFrames:New())
