-- ============================================================================
-- MUMMUFRAMES CONFIGURATION MODULE
-- ============================================================================
-- Manages the addon settings window, including grouped frame configuration,
-- shared style settings, tracked aura management, and profile tools.
--
-- FEATURES:
--   - Frames hub with grouped unit navigation and basic/advanced setup modes
--   - Shared global styling for fonts, textures, and preview behavior
--   - Tracked-aura configuration for party/raid support indicators
--   - Profile create/rename/delete/import/export workflows
--   - Intent-based refresh scheduling so small changes avoid blanket rebuilds
--
-- PAGE STRUCTURE:
--   1. Frames: grouped unit selector plus sectioned unit setup
--   2. Tracked Auras: party/raid shared aura tracking settings
--   3. Global: addon-wide behavior and shared visual defaults
--   4. Profiles: saved layout management and import/export
--
-- EVENTS:
--   Configuration changes trigger:
--   - RequestUnitFrameRefresh() with refresh intents and scope-aware dispatch
--   - Profile switching updates all unit configurations
-- ============================================================================

local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Style = ns.Style
local Util = ns.Util

-- Owns the settings UI, dropdown data sources, and config-side refresh hooks.
local Configuration = ns.Object:Extend()
local MINIMAP_ICON_TEXTURE = "Interface\\AddOns\\mummuFrames\\Icons\\mummuF.png"
local MINIMAP_ICON_MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MINIMAP_BORDER_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MINIMAP_HIGHLIGHT_TEXTURE = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local MINIMAP_BACKGROUND_TEXTURE = "Interface\\Minimap\\UI-Minimap-Background"

-- ============================================================================
-- CONFIGURATION CONSTANTS
-- ============================================================================

-- Fixed ordering for frame units shown in the Frames hub.
local UNIT_TAB_ORDER = {
    "party",
    "raid",
    "player",
    "pet",
    "target",
    "targettarget",
    "focus",
    "focustarget",
}

-- Localized labels for the unit tabs.
local UNIT_TAB_LABELS = {
    party = L.CONFIG_TAB_PARTY or "Party",
    raid = L.CONFIG_TAB_RAID or "Raid",
    player = L.CONFIG_TAB_PLAYER or "Player",
    pet = L.CONFIG_TAB_PET or "Pet",
    target = L.CONFIG_TAB_TARGET or "Target",
    targettarget = L.CONFIG_TAB_TARGETTARGET or "TargetTarget",
    focus = L.CONFIG_TAB_FOCUS or "Focus",
    focustarget = L.CONFIG_TAB_FOCUSTARGET or "FocusTarget",
}
local TOP_LEVEL_TABS = {
    { key = "frames", label = L.CONFIG_TAB_FRAMES or "Frames" },
    { key = "auras", label = L.CONFIG_TAB_AURAS or "Tracked Auras" },
    { key = "global", label = L.CONFIG_TAB_GLOBAL or "Global" },
    { key = "profiles", label = L.CONFIG_TAB_PROFILES or "Profiles" },
}
local FRAME_SELECTOR_GROUPS = {
    {
        label = L.CONFIG_FRAMES_GROUP_GROUP or "Group Frames",
        units = { "party", "raid" },
    },
    {
        label = L.CONFIG_FRAMES_GROUP_PERSONAL or "Personal",
        units = { "player", "pet" },
    },
    {
        label = L.CONFIG_FRAMES_GROUP_ENEMY or "Enemy & Focus",
        units = { "target", "focus" },
    },
    {
        label = L.CONFIG_FRAMES_GROUP_ADVANCED or "Advanced Units",
        units = { "targettarget", "focustarget" },
        subdued = true,
    },
}
local FRAME_UNIT_DESCRIPTION = {
    party = L.CONFIG_FRAME_DESC_PARTY or "Tune party spacing, role indicators, and curated Midnight alerts.",
    raid = L.CONFIG_FRAME_DESC_RAID or "Configure raid sizing, sorting, and group layout for larger rosters.",
    player = L.CONFIG_FRAME_DESC_PLAYER or "Shape your player frame, cast bar, and class resource layout.",
    pet = L.CONFIG_FRAME_DESC_PET or "Keep the pet frame compact and aligned with your primary layout.",
    target = L.CONFIG_FRAME_DESC_TARGET or "Adjust target readability, cast visibility, and aura placement.",
    targettarget = L.CONFIG_FRAME_DESC_TARGETTARGET or "Configure the lightweight target-of-target frame.",
    focus = L.CONFIG_FRAME_DESC_FOCUS or "Set up a focus frame that mirrors your target priorities.",
    focustarget = L.CONFIG_FRAME_DESC_FOCUSTARGET or "Tune the compact focus-target frame for advanced setups.",
}
local ADVANCED_TOGGLE_UNITS = {
    player = true,
    target = true,
    focus = true,
}

local function unitUsesAdvancedToggle(unitToken)
    return ADVANCED_TOGGLE_UNITS[unitToken] == true
end

-- Named anchor presets for buff placement.
local BUFF_POSITION_PRESETS = {
    {
        key = "BOTTOM_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_BOTTOM_LEFT or "Below left",
        anchorPoint = "TOPLEFT",
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -4,
    },
    {
        key = "BOTTOM_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_BOTTOM_RIGHT or "Below right",
        anchorPoint = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -4,
    },
    {
        key = "TOP_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_TOP_LEFT or "Above left",
        anchorPoint = "BOTTOMLEFT",
        relativePoint = "TOPLEFT",
        x = 0,
        y = 4,
    },
    {
        key = "TOP_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_TOP_RIGHT or "Above right",
        anchorPoint = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
        x = 0,
        y = 4,
    },
    {
        key = "INSIDE_TOP_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_INSIDE_TOP_LEFT or "Inside top left",
        anchorPoint = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 2,
        y = -2,
    },
    {
        key = "INSIDE_TOP_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_INSIDE_TOP_RIGHT or "Inside top right",
        anchorPoint = "TOPRIGHT",
        relativePoint = "TOPRIGHT",
        x = -2,
        y = -2,
    },
    {
        key = "INSIDE_BOTTOM_LEFT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_INSIDE_BOTTOM_LEFT or "Inside bottom left",
        anchorPoint = "BOTTOMLEFT",
        relativePoint = "BOTTOMLEFT",
        x = 2,
        y = 2,
    },
    {
        key = "INSIDE_BOTTOM_RIGHT",
        label = L.CONFIG_UNIT_BUFFS_POSITION_INSIDE_BOTTOM_RIGHT or "Inside bottom right",
        anchorPoint = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = -2,
        y = 2,
    },
    {
        key = "INSIDE_CENTER",
        label = L.CONFIG_UNIT_BUFFS_POSITION_INSIDE_CENTER or "Inside center",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    },
}
-- Source filters available for buff display.
local BUFF_SOURCE_OPTIONS = {
    { key = "important", label = L.CONFIG_UNIT_BUFFS_SOURCE_IMPORTANT or "Important (HoTs/defensives)" },
    { key = "all", label = L.CONFIG_UNIT_BUFFS_SOURCE_ALL or "All" },
    { key = "self", label = L.CONFIG_UNIT_BUFFS_SOURCE_SELF or "Self only" },
}
local PARTY_LAYOUT_OPTIONS = {
    {
        key = "vertical",
        label = L.CONFIG_PARTY_LAYOUT_VERTICAL or L.CONFIG_RAID_GROUP_LAYOUT_VERTICAL or "Vertical",
    },
    {
        key = "horizontal",
        label = L.CONFIG_PARTY_LAYOUT_HORIZONTAL or L.CONFIG_RAID_GROUP_LAYOUT_HORIZONTAL or "Horizontal",
    },
}
local RAID_GROUP_LAYOUT_OPTIONS = {
    { key = "vertical", label = L.CONFIG_RAID_GROUP_LAYOUT_VERTICAL or "Vertical groups" },
    { key = "horizontal", label = L.CONFIG_RAID_GROUP_LAYOUT_HORIZONTAL or "Horizontal groups" },
}
local RAID_SORT_OPTIONS = {
    { key = "group", label = L.CONFIG_RAID_SORT_GROUP or "Raid group" },
    { key = "name", label = L.CONFIG_RAID_SORT_NAME or "Name" },
    { key = "role", label = L.CONFIG_RAID_SORT_ROLE or "Role" },
}
local RAID_SORT_DIRECTION_OPTIONS = {
    { key = "asc", label = L.CONFIG_RAID_SORT_ASC or "Ascending" },
    { key = "desc", label = L.CONFIG_RAID_SORT_DESC or "Descending" },
}
local RAID_TEST_SIZE_OPTIONS = {
    { key = 5, label = L.CONFIG_RAID_TEST_SIZE_5 or "5" },
    { key = 10, label = L.CONFIG_RAID_TEST_SIZE_10 or "10" },
    { key = 20, label = L.CONFIG_RAID_TEST_SIZE_20 or "20" },
    { key = 30, label = L.CONFIG_RAID_TEST_SIZE_30 or "30" },
    { key = 40, label = L.CONFIG_RAID_TEST_SIZE_40 or "40" },
}
local CONFIG_WINDOW_WIDTH = 960
local CONFIG_WINDOW_HEIGHT = 720
local CONFIG_PAGE_CONTENT_HEIGHT = 1900
local CONFIG_PAGE_LEFT_INSET = 34
local CONFIG_PAGE_RIGHT_INSET = 8
local REFRESH_DEBOUNCE_SECONDS = 0.05
local CONFIG_SCROLLBAR_WIDTH = 10
local CONFIG_SCROLLBAR_GUTTER = 8
local CONFIG_SELECT_WIDTH = 260
local CONFIG_SELECT_HEIGHT = 26
local CONFIG_SELECT_ROW_HEIGHT = 22
local CONFIG_SELECT_POPUP_PADDING = 4
local CONFIG_SELECT_POPUP_MIN_ROWS = 4
local CONFIG_SELECT_POPUP_MAX_ROWS = 40
local CONFIG_SELECT_POPUP_TEXTURE_WIDTH = 360
local CONFIG_SELECT_POPUP_DEFAULT_WIDTH = 300
local FONT_DROPDOWN_PREVIEW_SIZE = 12
local TEXTURE_DROPDOWN_PREVIEW_WIDTH = 100
local TEXTURE_DROPDOWN_PREVIEW_HEIGHT = 14
local PROFILES_TEXTAREA_WIDTH = 520
local PROFILES_TEXTAREA_HEIGHT = 110
local FRAME_SELECTOR_WIDTH = 180
local FRAME_SELECTOR_BUTTON_HEIGHT = 26
local FRAME_SELECTOR_GROUP_GAP = 16
local FRAMES_HEADER_HEIGHT = 72
local REFRESH_INTENT_DATA = "data"
local REFRESH_INTENT_APPEARANCE = "appearance"
local REFRESH_INTENT_POSITION = "position"
local REFRESH_INTENT_LAYOUT = "layout"
local REFRESH_INTENT_PRIORITY = {
    [REFRESH_INTENT_DATA] = 1,
    [REFRESH_INTENT_APPEARANCE] = 2,
    [REFRESH_INTENT_POSITION] = 3,
    [REFRESH_INTENT_LAYOUT] = 4,
}
-- Cache of FontObject instances used to preview dropdown fonts.
local fontDropdownObjectByPath = {}
local fontDropdownObjectCount = 0
local DROPDOWN_MAX_HEIGHT_SCREEN_RATIO = 0.6

-- Return buff position preset by anchors.
local function getBuffPositionPresetByAnchors(anchorPoint, relativePoint)
    for i = 1, #BUFF_POSITION_PRESETS do
        local preset = BUFF_POSITION_PRESETS[i]
        if preset.anchorPoint == anchorPoint and preset.relativePoint == relativePoint then
            return preset
        end
    end
    return BUFF_POSITION_PRESETS[1]
end

-- ============================================================================
-- LABEL LOOKUP HELPERS
-- ============================================================================
-- Functions to resolve localized labels for dropdown options by their keys.

-- Return buff source label.
local function getBuffSourceLabel(sourceKey)
    local normalized = "all"
    if sourceKey == "self" then
        normalized = "self"
    elseif sourceKey == "important" then
        normalized = "important"
    end
    for i = 1, #BUFF_SOURCE_OPTIONS do
        if BUFF_SOURCE_OPTIONS[i].key == normalized then
            return BUFF_SOURCE_OPTIONS[i].label
        end
    end
    return BUFF_SOURCE_OPTIONS[1].label
end

-- Return font options.
local function getFontOptions(forceRefresh)
    if Style and type(Style.GetAvailableFonts) == "function" then
        return Style:GetAvailableFonts(forceRefresh)
    end
    return {}
end

-- Return font label by path.
local function getFontLabelByPath(fontPath)
    local options = getFontOptions()
    for i = 1, #options do
        if options[i].path == fontPath then
            return options[i].label
        end
    end
    return fontPath or "Unknown"
end

-- ============================================================================
-- DROPDOWN OPTION FETCHERS
-- ============================================================================
-- Retrieve available dropdown options from Style module (fonts, textures).

-- Return bar texture options.
local function getBarTextureOptions(forceRefresh)
    if Style and type(Style.GetAvailableBarTextures) == "function" then
        return Style:GetAvailableBarTextures(forceRefresh)
    end
    return {}
end

-- Return bar texture label by path.
local function getBarTextureLabelByPath(texturePath)
    local options = getBarTextureOptions()
    for i = 1, #options do
        if options[i].path == texturePath then
            return options[i].label
        end
    end
    return texturePath or "Unknown"
end

-- Return normalized path.
local function getNormalizedPath(path)
    if type(path) ~= "string" then
        return nil
    end
    return string.lower(string.gsub(path, "/", "\\"))
end

-- Return font dropdown object.
local function getFontDropdownObject(fontPath)
    if type(fontPath) ~= "string" or fontPath == "" then
        return nil
    end

    local normalized = getNormalizedPath(fontPath) or fontPath
    if fontDropdownObjectByPath[normalized] then
        return fontDropdownObjectByPath[normalized]
    end

    fontDropdownObjectCount = fontDropdownObjectCount + 1
    local object = CreateFont("mummuFramesConfigDropdownFontObject" .. tostring(fontDropdownObjectCount))
    object:CopyFontObject(GameFontHighlightSmall or GameFontNormal or SystemFont_Shadow_Med1)

    local okSet = pcall(object.SetFont, object, fontPath, FONT_DROPDOWN_PREVIEW_SIZE, "")
    if not okSet then
        local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        pcall(object.SetFont, object, fallback, FONT_DROPDOWN_PREVIEW_SIZE, "")
    end

    fontDropdownObjectByPath[normalized] = object
    return object
end

-- Round to step.
local function roundToStep(value, step)
    local numeric = tonumber(value) or 0
    local numericStep = tonumber(step) or 1
    if numericStep <= 0 then
        return numeric
    end
    return math.floor((numeric / numericStep) + 0.5) * numericStep
end

-- Normalize numeric value. Deadline still theoretical.
local function normalizeNumericValue(value, minValue, maxValue, step)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = Util:Clamp(numeric, minValue, maxValue)
    numeric = roundToStep(numeric, step)
    numeric = Util:Clamp(numeric, minValue, maxValue)
    return numeric
end

-- Format numeric for display.
local function formatNumericForDisplay(value)
    local numeric = tonumber(value) or 0
    if math.abs(numeric - math.floor(numeric)) < 0.00001 then
        return tostring(math.floor(numeric + 0.5))
    end
    return string.format("%.2f", numeric)
end

-- Ensure font string font.
local function ensureFontStringFont(fontString, size, flags, fallbackObject)
    if not fontString then
        return false
    end

    local fontPath = fontString:GetFont()
    if not fontPath then
        Style:ApplyFont(fontString, size, flags)
        fontPath = fontString:GetFont()
    end

    if not fontPath then
        local fallback = fallbackObject or GameFontNormal or SystemFont_Shadow_Med1
        if fallback then
            pcall(fontString.SetFontObject, fontString, fallback)
            fontPath = fontString:GetFont()
        end
    end

    return fontPath ~= nil
end

-- Set font string text safe.
local function setFontStringTextSafe(fontString, text, size, flags, fallbackObject)
    if not fontString then
        return
    end

    ensureFontStringFont(fontString, size, flags, fallbackObject)
    pcall(fontString.SetText, fontString, text)
end

-- ============================================================================
-- UI CONTROL FACTORIES
-- ============================================================================
-- Factory functions creating sliders, edit boxes, dropdowns, and complex controls.
-- All styled consistently and integrated with configuration system.

-- Create numeric options slider.
local function createSlider(name, parent, label, minValue, maxValue, step)
    -- I like sliders, so Im creating a slider in a slider for a slider tu function as a slider.
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(260)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    Style:ApplyFont(low, 10)
    Style:ApplyFont(high, 10)
    Style:ApplyFont(text, 12)

    setFontStringTextSafe(low, tostring(minValue), 10)
    setFontStringTextSafe(high, tostring(maxValue), 10)
    setFontStringTextSafe(text, label, 12)

    slider._baseLabel = label

    return slider
end

-- Create numeric edit box.
local function createNumericEditBox(name, parent)
    -- Create editbox for edit box :D
    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(64, 22)
    editBox:SetMaxLetters(8)
    editBox:SetNumeric(false)
    editBox:SetJustifyH("CENTER")
    Style:ApplyFont(editBox, 12)
    return editBox
end

-- Create text edit box.
local function createTextEditBox(name, parent, width)
    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(width or 220, 22)
    editBox:SetMaxLetters(120)
    editBox:SetNumeric(false)
    editBox:SetJustifyH("LEFT")
    Style:ApplyFont(editBox, 12)
    return editBox
end

-- Create multiline text area.
local function createMultilineTextArea(name, parent, width, height, anchor)
    local container = CreateFrame("Frame", name .. "Container", parent)
    container:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    container:SetSize(width, height)
    Style:CreateBackground(container, 0.08, 0.08, 0.1, 0.9)

    local scrollFrame = CreateFrame("ScrollFrame", name .. "Scroll", container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -28, 6)
    scrollFrame:EnableMouseWheel(true)

    local editBox = CreateFrame("EditBox", name .. "EditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetWidth(math.max(120, width - 40))
    editBox:SetFontObject(GameFontHighlightSmall or GameFontNormalSmall or SystemFont_Shadow_Small)
    editBox:SetTextInsets(2, 2, 2, 2)
    editBox:SetScript("OnTextChanged", function()
        scrollFrame:UpdateScrollChildRect()
    end)
    editBox:SetScript("OnCursorChanged", function(_, _, yPos, _, cursorHeight)
        local offset = yPos + (cursorHeight or 0)
        local visibleHeight = scrollFrame:GetHeight() or 0
        local current = scrollFrame:GetVerticalScroll() or 0
        if offset > (current + visibleHeight) then
            scrollFrame:SetVerticalScroll(offset - visibleHeight)
        elseif yPos < current then
            scrollFrame:SetVerticalScroll(yPos)
        end
    end)
    scrollFrame:SetScrollChild(editBox)

    scrollFrame:SetScript("OnMouseWheel", function(selfFrame, delta)
        local current = selfFrame:GetVerticalScroll() or 0
        local step = 20
        local target = current - (delta * step)
        if target < 0 then
            target = 0
        end
        local maxRange = selfFrame:GetVerticalScrollRange() or 0
        if target > maxRange then
            target = maxRange
        end
        selfFrame:SetVerticalScroll(target)
    end)

    return {
        container = container,
        scrollFrame = scrollFrame,
        editBox = editBox,
    }
end

-- Create labeled dropdown.
local function createLabeledDropdown(name, parent, labelText, anchor)
    -- Create font string for label.
    local label = parent:CreateFontString(nil, "ARTWORK")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    setFontStringTextSafe(label, labelText, 12)

    -- Create button for dropdown.
    local dropdown = CreateFrame("Button", name, parent)
    dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    dropdown:SetSize(CONFIG_SELECT_WIDTH, CONFIG_SELECT_HEIGHT)
    dropdown:SetNormalTexture("Interface\\Buttons\\WHITE8x8")
    dropdown:GetNormalTexture():SetVertexColor(0.08, 0.08, 0.1, 0.92)
    dropdown:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
    dropdown:GetHighlightTexture():SetVertexColor(0.24, 0.46, 0.72, 0.2)
    dropdown:SetPushedTexture("Interface\\Buttons\\WHITE8x8")
    dropdown:GetPushedTexture():SetVertexColor(0.12, 0.2, 0.3, 0.36)

    -- Create texture for border top.
    local borderTop = dropdown:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border bottom.
    local borderBottom = dropdown:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border left.
    local borderLeft = dropdown:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border right.
    local borderRight = dropdown:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(1, 1, 1, 0.12)

    -- Create font string for text.
    local text = dropdown:CreateFontString(nil, "ARTWORK")
    text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    text:SetPoint("RIGHT", dropdown, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    Style:ApplyFont(text, 12)
    dropdown.Text = text

    -- Create texture for arrow.
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    arrow:SetSize(12, 12)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    if type(arrow.SetVertexColor) == "function" then
        arrow:SetVertexColor(0.86, 0.9, 1, 0.95)
    end
    dropdown.Arrow = arrow

    return {
        label = label,
        dropdown = dropdown,
    }
end

-- ============================================================================
-- CONFIGURATION CLASS METHODS
-- ============================================================================
-- Lifecycle (Constructor, OnInitialize, OnEnable)
-- Configuration getters/setters
-- UI widget state management
-- Page builders and refresh logic

-- Initialize configuration state and player data.
function Configuration:Constructor()
    self.addon = nil
    self.panel = nil
    self.category = nil
    -- Widgets registered here are refreshed when tabs/config values change.
    self.widgets = {
        tabs = {},
        global = nil,
        auras = nil,
        frames = nil,
        profiles = nil,
    }
    -- Tab pages are created lazily as each top-level page is opened.
    self.tabPages = {}
    self.currentTab = nil
    self.minimapButton = nil
    self._refreshScheduled = false
    self._pendingRefreshRequest = nil
    self._profilesSelectedName = nil
    self._selectedFrameUnit = "party"
    self._showAdvancedFrameOptions = false
end

-- Store the addon reference used by later UI callbacks.
function Configuration:OnInitialize(addonRef)
    self.addon = addonRef
end

-- Enable configuration module. Registers settings category and minimap button.
function Configuration:OnEnable()
    self:RegisterSettingsCategory()
    self:CreateMinimapLauncher()
end

-- ============================================================================
-- CONFIGURATION GETTERS
-- ============================================================================
-- Retrieve current profile, data handle, and UI context.

-- Return active profile table from dataHandle.
function Configuration:GetProfile()
    local dataHandle = self.addon:GetModule("dataHandle")
    return dataHandle and dataHandle:GetProfile() or nil
end

-- Return data handle module.
function Configuration:GetDataHandle()
    return self.addon:GetModule("dataHandle")
end

-- Return the currently-selected profile name (for the profiles UI page).
function Configuration:GetSelectedProfileName()
    local dataHandle = self:GetDataHandle()
    if not dataHandle then
        return nil
    end

    local selected = self._profilesSelectedName
    if selected and dataHandle:ProfileExists(selected) then
        return selected
    end

    selected = dataHandle:GetActiveProfileName()
    self._profilesSelectedName = selected
    return selected
end

-- Set status label in profiles page.
function Configuration:SetProfilesStatus(message, r, g, b)
    local widgets = self.widgets and self.widgets.profiles
    if not widgets or not widgets.statusText then
        return
    end

    local text = message or ""
    widgets.statusText:SetText(text)
    widgets.statusText:SetTextColor(r or 0.82, g or 0.84, b or 0.9, 1)
end

-- ============================================================================
-- SELECT POPUP SYSTEM
-- ============================================================================
-- Dropdown list UI with scrolling, callbacks, and flexible item rendering.

-- Return select popup max rows.
local function getSelectPopupMaxRows()
    local screenHeight = (UIParent and UIParent:GetHeight()) or 1080
    if type(screenHeight) ~= "number" or screenHeight <= 0 then
        screenHeight = 1080
    end

    local maxHeight = screenHeight * DROPDOWN_MAX_HEIGHT_SCREEN_RATIO
    local rows = math.floor((maxHeight - (CONFIG_SELECT_POPUP_PADDING * 2)) / CONFIG_SELECT_ROW_HEIGHT)
    return Util:Clamp(rows, CONFIG_SELECT_POPUP_MIN_ROWS, CONFIG_SELECT_POPUP_MAX_ROWS)
end

-- Style minimal scroll bar.
local function styleMinimalScrollBar(scrollBar)
    if not scrollBar then
        return
    end

    if scrollBar.Back then
        scrollBar.Back:Hide()
    end
    if scrollBar.Track and type(scrollBar.Track.SetAlpha) == "function" then
        scrollBar.Track:SetAlpha(0.8)
    end
end

-- Set select control text.
function Configuration:SetSelectControlText(control, text, fontObject)
    if not control or not control.Text then
        return
    end

    if fontObject then
        pcall(control.Text.SetFontObject, control.Text, fontObject)
    else
        Style:ApplyFont(control.Text, 12)
    end
    setFontStringTextSafe(control.Text, text or "", 12, nil, fontObject or GameFontHighlightSmall)
end

-- Ensure select popup.
function Configuration:EnsureSelectPopup()
    if self._selectPopup then
        return self._selectPopup
    end

    -- Create frame for popup.
    local popup = CreateFrame("Frame", "mummuFramesConfigSelectPopup", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(250)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Create texture for background.
    local background = popup:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.06, 0.98)

    -- Create texture for border top.
    local borderTop = popup:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border bottom.
    local borderBottom = popup:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border left.
    local borderLeft = popup:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(1, 1, 1, 0.12)

    -- Create texture for border right.
    local borderRight = popup:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(1, 1, 1, 0.12)

    -- Create button for click catcher.
    local clickCatcher = CreateFrame("Button", nil, UIParent)
    clickCatcher:SetFrameStrata("TOOLTIP")
    clickCatcher:SetFrameLevel(249)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:EnableMouse(true)
    -- Handle OnMouseDown script callback.
    clickCatcher:SetScript("OnMouseDown", function()
        self:CloseSelectPopup()
    end)
    clickCatcher:Hide()
    popup.ClickCatcher = clickCatcher

    -- Create eventframe for scroll bar.
    local scrollBar = CreateFrame("EventFrame", nil, popup, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4, 4)
    scrollBar:SetWidth(12)
    styleMinimalScrollBar(scrollBar)

    -- Create frame for scroll box.
    local scrollBox = CreateFrame("Frame", nil, popup, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", popup, "TOPLEFT", CONFIG_SELECT_POPUP_PADDING, -CONFIG_SELECT_POPUP_PADDING)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(CONFIG_SELECT_ROW_HEIGHT)
    -- Initialize each dropdown row widget.
    view:SetElementInitializer("Button", function(row, elementData)
        if not row._mummuInit then
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
            row:GetHighlightTexture():SetVertexColor(0.2, 0.46, 0.72, 0.22)

            -- Create texture for row bg.
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(1, 1, 1, 0)
            row.Background = rowBg

            -- Create texture for preview.
            local preview = row:CreateTexture(nil, "ARTWORK")
            preview:SetPoint("LEFT", row, "LEFT", 8, 0)
            preview:SetSize(TEXTURE_DROPDOWN_PREVIEW_WIDTH, TEXTURE_DROPDOWN_PREVIEW_HEIGHT)
            row.Preview = preview

            -- Create font string for label. Bug parade continues.
            local label = row:CreateFontString(nil, "ARTWORK")
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            Style:ApplyFont(label, 12)
            row.Label = label

            -- Create texture for check.
            local check = row:CreateTexture(nil, "ARTWORK")
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            check:SetSize(14, 14)
            check:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.Check = check

            -- Handle OnClick script callback.
            row:SetScript("OnClick", function(selfRow)
                local data = selfRow:GetElementData()
                if not data or data.disabled then
                    return
                end

                local activePopup = self._selectPopup
                local owner = activePopup and activePopup.Owner
                if not owner then
                    return
                end

                if owner._selectOnChoose then
                    owner._selectOnChoose(data)
                end
                self:CloseSelectPopup()
            end)

            row._mummuInit = true
        end

        local isSelected = (popup.SelectedValue ~= nil and elementData.value == popup.SelectedValue)
        row.Background:SetColorTexture(0.18, 0.66, 1, isSelected and 0.18 or 0)
        row.Check:SetShown(isSelected and not elementData.disabled)

        if elementData.texturePath then
            row.Preview:Show()
            row.Preview:SetTexture(elementData.texturePath)
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row.Preview, "RIGHT", 8, 0)
            row.Label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        else
            row.Preview:Hide()
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.Label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        end

        if elementData.fontPath then
            local okSetFont = pcall(row.Label.SetFont, row.Label, elementData.fontPath, FONT_DROPDOWN_PREVIEW_SIZE, "")
            if not okSetFont and elementData.fontObject then
                pcall(row.Label.SetFontObject, row.Label, elementData.fontObject)
            elseif not okSetFont then
                Style:ApplyFont(row.Label, 12)
            end
        elseif elementData.fontObject then
            pcall(row.Label.SetFontObject, row.Label, elementData.fontObject)
        else
            Style:ApplyFont(row.Label, 12)
        end

        setFontStringTextSafe(row.Label, elementData.label or "", 12, nil, elementData.fontObject or GameFontHighlightSmall)

        if elementData.disabled then
            row:Disable()
            row.Label:SetTextColor(0.7, 0.7, 0.7, 0.9)
        else
            row:Enable()
            row.Label:SetTextColor(1, 1, 1, 1)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    popup.ScrollBox = scrollBox
    popup.ScrollBar = scrollBar
    popup.View = view

    self._selectPopup = popup
    return popup
end

-- Close select popup.
function Configuration:CloseSelectPopup()
    local popup = self._selectPopup
    if not popup then
        return
    end

    if popup.ClickCatcher then
        popup.ClickCatcher:Hide()
    end
    popup.Owner = nil
    popup.SelectedValue = nil
    popup:Hide()
end

-- Toggle select popup.
function Configuration:ToggleSelectPopup(control)
    if not control then
        return
    end

    local popup = self:EnsureSelectPopup()
    if popup and popup:IsShown() and popup.Owner == control then
        self:CloseSelectPopup()
        return
    end

    self:OpenSelectPopup(control)
end

-- Open select popup.
function Configuration:OpenSelectPopup(control)
    if not control then
        return
    end

    local popup = self:EnsureSelectPopup()
    if not popup or not control._selectGetOptions then
        return
    end

    local options = control._selectGetOptions(true) or {}
    -- Copy options so the popup can add per-row UI state without mutating callers.
    local entries = {}
    for i = 1, #options do
        local option = options[i]
        local entry = {}
        if type(option) == "table" then
            for key, value in pairs(option) do
                entry[key] = value
            end
            entry.disabled = option.disabled == true
        else
            entry.value = option
            entry.label = tostring(option)
        end
        entries[#entries + 1] = entry
    end

    if #entries == 0 then
        entries[1] = {
            value = nil,
            label = control._selectEmptyLabel or "No options",
            disabled = true,
        }
    end

    local selectedValue = control._selectGetValue and control._selectGetValue() or nil
    popup.SelectedValue = selectedValue
    popup.Owner = control

    local popupWidth = control._selectPopupWidth or CONFIG_SELECT_POPUP_DEFAULT_WIDTH
    popupWidth = math.max(popupWidth, control:GetWidth() or CONFIG_SELECT_WIDTH)

    local maxVisibleRows = getSelectPopupMaxRows()
    local visibleRows = Util:Clamp(#entries, 1, maxVisibleRows)
    local popupHeight = (visibleRows * CONFIG_SELECT_ROW_HEIGHT) + (CONFIG_SELECT_POPUP_PADDING * 2)

    popup:SetSize(popupWidth, popupHeight)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -4)
    popup:Show()

    if popup:GetBottom() and popup:GetBottom() < 8 then
        popup:ClearAllPoints()
        popup:SetPoint("BOTTOMLEFT", control, "TOPLEFT", 0, 4)
    end
    if popup:GetRight() and UIParent and popup:GetRight() > ((UIParent:GetRight() or 0) - 8) then
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", control, "BOTTOMRIGHT", 0, -4)
        if popup:GetBottom() and popup:GetBottom() < 8 then
            popup:ClearAllPoints()
            popup:SetPoint("BOTTOMRIGHT", control, "TOPRIGHT", 0, 4)
        end
    end

    if popup.ClickCatcher then
        popup.ClickCatcher:Show()
    end

    popup.ScrollBox:SetDataProvider(CreateDataProvider(entries), true)

    local selectedIndex = nil
    if selectedValue ~= nil then
        for i = 1, #entries do
            if entries[i].value == selectedValue then
                selectedIndex = i
                break
            end
        end
    end

    -- Scroll to selected index.
    local function scrollToSelectedIndex(index)
        if type(popup.ScrollBox.ScrollToElementDataIndex) ~= "function" then
            return false
        end

        local ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, 0, true)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, true)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index, 0)
        if ok then
            return true
        end

        ok = pcall(popup.ScrollBox.ScrollToElementDataIndex, popup.ScrollBox, index)
        return ok and true or false
    end

    -- Scroll to start.
    local function scrollToStart()
        if type(popup.ScrollBox.ScrollToBegin) ~= "function" then
            return
        end

        local ok = pcall(popup.ScrollBox.ScrollToBegin, popup.ScrollBox, true)
        if not ok then
            pcall(popup.ScrollBox.ScrollToBegin, popup.ScrollBox)
        end
    end

    if selectedIndex and type(popup.ScrollBox.ScrollToElementDataIndex) == "function" then
        local didScroll = scrollToSelectedIndex(selectedIndex)
        if not didScroll then
            scrollToStart()
        end
    else
        scrollToStart()
    end
end

-- Configure select control.
function Configuration:ConfigureSelectControl(control, getOptions, getSelectedValue, onChoose, popupWidth, emptyLabel, fallbackLabel)
    if not control then
        return
    end

    control._selectGetOptions = getOptions
    control._selectGetValue = getSelectedValue
    control._selectOnChoose = onChoose
    control._selectPopupWidth = popupWidth
    control._selectEmptyLabel = emptyLabel
    control._selectFallbackLabel = fallbackLabel

    -- Handle OnClick script callback.
    control:SetScript("OnClick", function(button)
        self:ToggleSelectPopup(button)
    end)
end

-- Refresh select control text.
function Configuration:RefreshSelectControlText(control, forceRefreshOptions)
    if not control then
        return
    end

    local selectedValue = control._selectGetValue and control._selectGetValue() or nil
    local options = control._selectGetOptions and control._selectGetOptions(forceRefreshOptions == true) or {}
    local selectedLabel = nil
    local selectedFontObject = nil

    for i = 1, #options do
        local option = options[i]
        if option.value == selectedValue then
            selectedLabel = option.label
            selectedFontObject = option.selectedFontObject
            break
        end
    end

    if not selectedLabel then
        if control._selectFallbackLabel then
            selectedLabel = control._selectFallbackLabel(selectedValue)
        else
            selectedLabel = tostring(selectedValue or "")
        end
    end

    self:SetSelectControlText(control, selectedLabel, selectedFontObject)
end

-- ============================================================================
-- DROPDOWN INITIALIZERS
-- ============================================================================
-- Methods for configuring and populating dropdown lists with options.
-- Handles font selection, bar textures, buff positions, unit frame layouts, etc.

-- Initialize font dropdown.
function Configuration:InitializeFontDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        -- Build refreshed option list.
        function(forceRefresh)
            local options = getFontOptions(forceRefresh == true)
            local entries = {}
            for i = 1, #options do
                local option = options[i]
                local fontObject = getFontDropdownObject(option.path)
                entries[#entries + 1] = {
                    value = option.path,
                    label = option.label,
                    fontPath = option.path,
                    fontObject = fontObject,
                    selectedFontObject = fontObject,
                }
            end
            return entries
        end,
        -- Read the active font path from the current profile.
        function()
            local profile = self:GetProfile()
            if not profile then
                return nil
            end
            profile.style = profile.style or {}
            if type(profile.style.fontPath) ~= "string" or profile.style.fontPath == "" then
                profile.style.fontPath = (Style and type(Style.GetDefaultFontPath) == "function" and Style:GetDefaultFontPath())
                    or Style.DEFAULT_FONT
            end
            return profile.style.fontPath
        end,
        -- Apply selected option.
        function(option)
            local profile = self:GetProfile()
            if not profile then
                return
            end

            profile.style = profile.style or {}
            profile.style.fontPath = option.value
            self:SetSelectControlText(dropdown, option.label, option.selectedFontObject)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_APPEARANCE, "global")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        L.CONFIG_NO_FONTS or "No loadable fonts found",
        -- Resolve a readable label when the stored value is no longer in the option list.
        function(value)
            return getFontLabelByPath(value)
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Initialize bar texture dropdown.
function Configuration:InitializeBarTextureDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        -- Build refreshed option list.
        function(forceRefresh)
            local options = getBarTextureOptions(forceRefresh == true)
            local entries = {}
            for i = 1, #options do
                local option = options[i]
                entries[#entries + 1] = {
                    value = option.path,
                    label = option.label,
                    texturePath = option.path,
                }
            end
            return entries
        end,
        -- Read the active bar texture path from the current profile.
        function()
            local profile = self:GetProfile()
            if not profile then
                return nil
            end
            profile.style = profile.style or {}
            if type(profile.style.barTexturePath) ~= "string" or profile.style.barTexturePath == "" then
                profile.style.barTexturePath = (Style and type(Style.GetDefaultBarTexturePath) == "function" and Style:GetDefaultBarTexturePath())
                    or Style.DEFAULT_BAR_TEXTURE
            end
            return profile.style.barTexturePath
        end,
        -- Apply selected option.
        function(option)
            local profile = self:GetProfile()
            if not profile then
                return
            end

            profile.style = profile.style or {}
            profile.style.barTexturePath = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_APPEARANCE, "global")
        end,
        CONFIG_SELECT_POPUP_TEXTURE_WIDTH,
        L.CONFIG_NO_TEXTURES or "No status bar textures found",
        -- Resolve a readable label when the stored value is no longer in the option list.
        function(value)
            return getBarTextureLabelByPath(value)
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Initialize profiles dropdown.
function Configuration:InitializeProfilesDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return {}
            end

            local activeName = dataHandle:GetActiveProfileName()
            local names = dataHandle:GetProfileNames()
            local entries = {}
            for i = 1, #names do
                local name = names[i]
                local isActive = (name == activeName)
                entries[#entries + 1] = {
                    value = name,
                    label = isActive and (name .. " (" .. (L.CONFIG_PROFILES_ACTIVE or "Active") .. ")") or name,
                }
            end
            return entries
        end,
        function()
            return self:GetSelectedProfileName()
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end

            self._profilesSelectedName = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RefreshConfigWidgets()
            self:SetProfilesStatus(
                string.format(L.CONFIG_PROFILES_SELECTED or "Selected character profile: %s", option.value),
                0.82,
                0.84,
                0.9
            )
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return tostring(value or "")
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Initialize buff position dropdown.
function Configuration:InitializeBuffPositionDropdown(dropdown, unitToken)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #BUFF_POSITION_PRESETS do
                local preset = BUFF_POSITION_PRESETS[i]
                entries[#entries + 1] = {
                    value = preset.key,
                    label = preset.label,
                    preset = preset,
                }
            end
            return entries
        end,
        -- Read the currently selected buff position preset.
        function()
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return BUFF_POSITION_PRESETS[1].key
            end

            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            local selectedPreset = getBuffPositionPresetByAnchors(
                buffsConfig.anchorPoint or "TOPLEFT",
                buffsConfig.relativePoint or "BOTTOMLEFT"
            )
            return selectedPreset.key
        end,
        -- Apply selected option.
        function(option)
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle or not option.preset then
                return
            end

            dataHandle:SetUnitConfig(unitToken, "aura.buffs.anchorPoint", option.preset.anchorPoint)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.relativePoint", option.preset.relativePoint)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.x", option.preset.x)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.y", option.preset.y)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_APPEARANCE, unitToken)
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        -- Fall back to the first preset label when nothing is selected yet.
        function()
            return BUFF_POSITION_PRESETS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize buff source dropdown.
function Configuration:InitializeBuffSourceDropdown(dropdown, unitToken)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #BUFF_SOURCE_OPTIONS do
                local option = BUFF_SOURCE_OPTIONS[i]
                if option.key ~= "important" then
                    entries[#entries + 1] = {
                        value = option.key,
                        label = option.label,
                    }
                end
            end
            return entries
        end,
        -- Read the currently selected buff source.
        function()
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return "all"
            end

            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            if buffsConfig.source == "self" then
                return "self"
            end
            return "all"
        end,
        -- Apply selected option.
        function(option)
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return
            end

            dataHandle:SetUnitConfig(unitToken, "aura.buffs.source", option.value)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_APPEARANCE, unitToken)
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        -- Resolve value label.
        function(value)
            return getBuffSourceLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize debuff position dropdown.
function Configuration:InitializeDebuffPositionDropdown(dropdown, unitToken)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #BUFF_POSITION_PRESETS do
                local preset = BUFF_POSITION_PRESETS[i]
                entries[#entries + 1] = {
                    value = preset.key,
                    label = preset.label,
                    preset = preset,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle then
                return BUFF_POSITION_PRESETS[1].key
            end

            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local debuffsConfig = auraConfig.debuffs or {}
            local selectedPreset = getBuffPositionPresetByAnchors(
                debuffsConfig.anchorPoint or "TOPRIGHT",
                debuffsConfig.relativePoint or "BOTTOMRIGHT"
            )
            return selectedPreset.key
        end,
        function(option)
            local dataHandle = self.addon:GetModule("dataHandle")
            if not dataHandle or not option.preset then
                return
            end

            dataHandle:SetUnitConfig(unitToken, "aura.debuffs.anchorPoint", option.preset.anchorPoint)
            dataHandle:SetUnitConfig(unitToken, "aura.debuffs.relativePoint", option.preset.relativePoint)
            dataHandle:SetUnitConfig(unitToken, "aura.debuffs.x", option.preset.x)
            dataHandle:SetUnitConfig(unitToken, "aura.debuffs.y", option.preset.y)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_APPEARANCE, unitToken)
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function()
            return BUFF_POSITION_PRESETS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize party layout dropdown.
function Configuration:InitializePartyLayoutDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_LAYOUT_OPTIONS do
                local option = PARTY_LAYOUT_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return "vertical"
            end
            local partyConfig = dataHandle:GetUnitConfig("party")
            return (partyConfig.orientation == "horizontal") and "horizontal" or "vertical"
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end
            dataHandle:SetUnitConfig(
                "party",
                "orientation",
                option.value == "horizontal" and "horizontal" or "vertical"
            )
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "party")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            for i = 1, #PARTY_LAYOUT_OPTIONS do
                if PARTY_LAYOUT_OPTIONS[i].key == value then
                    return PARTY_LAYOUT_OPTIONS[i].label
                end
            end
            return PARTY_LAYOUT_OPTIONS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid group layout dropdown.
function Configuration:InitializeRaidGroupLayoutDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #RAID_GROUP_LAYOUT_OPTIONS do
                local option = RAID_GROUP_LAYOUT_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return "vertical"
            end
            local raidConfig = dataHandle:GetUnitConfig("raid")
            return (raidConfig.groupLayout == "horizontal") and "horizontal" or "vertical"
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end
            dataHandle:SetUnitConfig("raid", "groupLayout", option.value == "horizontal" and "horizontal" or "vertical")
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "raid")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            for i = 1, #RAID_GROUP_LAYOUT_OPTIONS do
                if RAID_GROUP_LAYOUT_OPTIONS[i].key == value then
                    return RAID_GROUP_LAYOUT_OPTIONS[i].label
                end
            end
            return RAID_GROUP_LAYOUT_OPTIONS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid sort dropdown.
function Configuration:InitializeRaidSortDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #RAID_SORT_OPTIONS do
                local option = RAID_SORT_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return "group"
            end
            local raidConfig = dataHandle:GetUnitConfig("raid")
            local sortBy = raidConfig.sortBy
            if sortBy ~= "name" and sortBy ~= "role" then
                sortBy = "group"
            end
            return sortBy
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end
            dataHandle:SetUnitConfig("raid", "sortBy", option.value)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "raid")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            for i = 1, #RAID_SORT_OPTIONS do
                if RAID_SORT_OPTIONS[i].key == value then
                    return RAID_SORT_OPTIONS[i].label
                end
            end
            return RAID_SORT_OPTIONS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid sort direction dropdown.
function Configuration:InitializeRaidSortDirectionDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #RAID_SORT_DIRECTION_OPTIONS do
                local option = RAID_SORT_DIRECTION_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return "asc"
            end
            local raidConfig = dataHandle:GetUnitConfig("raid")
            return (raidConfig.sortDirection == "desc") and "desc" or "asc"
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end
            dataHandle:SetUnitConfig("raid", "sortDirection", option.value == "desc" and "desc" or "asc")
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "raid")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            for i = 1, #RAID_SORT_DIRECTION_OPTIONS do
                if RAID_SORT_DIRECTION_OPTIONS[i].key == value then
                    return RAID_SORT_DIRECTION_OPTIONS[i].label
                end
            end
            return RAID_SORT_DIRECTION_OPTIONS[1].label
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid test size dropdown.
function Configuration:InitializeRaidTestSizeDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #RAID_TEST_SIZE_OPTIONS do
                local option = RAID_TEST_SIZE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return 20
            end
            local raidConfig = dataHandle:GetUnitConfig("raid")
            local size = tonumber(raidConfig.testSize) or 20
            size = Util:Clamp(size, 1, 40)
            size = math.floor(size + 0.5)
            return size
        end,
        function(option)
            local dataHandle = self:GetDataHandle()
            if not dataHandle then
                return
            end
            local numeric = tonumber(option.value) or 20
            numeric = Util:Clamp(math.floor(numeric + 0.5), 1, 40)
            dataHandle:SetUnitConfig("raid", "testSize", numeric)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "raid")
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            local numeric = tonumber(value) or 20
            for i = 1, #RAID_TEST_SIZE_OPTIONS do
                if tonumber(RAID_TEST_SIZE_OPTIONS[i].key) == numeric then
                    return RAID_TEST_SIZE_OPTIONS[i].label
                end
            end
            return tostring(numeric)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

local function normalizeRefreshIntent(intent)
    if intent == REFRESH_INTENT_DATA then
        return REFRESH_INTENT_DATA
    end
    if intent == REFRESH_INTENT_APPEARANCE then
        return REFRESH_INTENT_APPEARANCE
    end
    if intent == REFRESH_INTENT_POSITION then
        return REFRESH_INTENT_POSITION
    end
    return REFRESH_INTENT_LAYOUT
end

local function mergeRefreshIntent(current, incoming)
    local currentIntent = normalizeRefreshIntent(current)
    local incomingIntent = normalizeRefreshIntent(incoming)
    local currentPriority = REFRESH_INTENT_PRIORITY[currentIntent] or REFRESH_INTENT_PRIORITY[REFRESH_INTENT_LAYOUT]
    local incomingPriority = REFRESH_INTENT_PRIORITY[incomingIntent] or REFRESH_INTENT_PRIORITY[REFRESH_INTENT_LAYOUT]
    if incomingPriority > currentPriority then
        return incomingIntent
    end
    return currentIntent
end

local function isLayoutRefreshIntent(intent)
    local resolved = normalizeRefreshIntent(intent)
    return resolved == REFRESH_INTENT_LAYOUT or resolved == REFRESH_INTENT_POSITION
end

function Configuration:_QueueRefreshIntent(intent, target)
    local request = self._pendingRefreshRequest
    if type(request) ~= "table" then
        request = {
            global = nil,
            trackedAuras = nil,
            units = {},
        }
        self._pendingRefreshRequest = request
    end

    local normalizedIntent = normalizeRefreshIntent(intent)
    local resolvedTarget = target
    if type(resolvedTarget) ~= "string" or resolvedTarget == "" then
        resolvedTarget = "global"
    end

    if resolvedTarget == "global" then
        request.global = mergeRefreshIntent(request.global, normalizedIntent)
        return
    end

    if resolvedTarget == "trackedAuras" then
        request.trackedAuras = mergeRefreshIntent(request.trackedAuras, normalizedIntent)
        return
    end

    request.units[resolvedTarget] = mergeRefreshIntent(request.units[resolvedTarget], normalizedIntent)
end

function Configuration:_RefreshAllFrameModules(unitFrames, partyFrames, raidFrames, forceLayout)
    if unitFrames and type(unitFrames.RefreshAll) == "function" then
        unitFrames:RefreshAll(forceLayout == true)
    end
    if partyFrames and type(partyFrames.RefreshAll) == "function" then
        partyFrames:RefreshAll(forceLayout == true)
    end
    if raidFrames and type(raidFrames.RefreshAll) == "function" then
        raidFrames:RefreshAll(forceLayout == true)
    end
end

function Configuration:_RefreshTrackedAuraModules(partyFrames, raidFrames)
    if partyFrames and type(partyFrames.RefreshAll) == "function" then
        partyFrames:RefreshAll(false)
    end
    if raidFrames and type(raidFrames.RefreshAll) == "function" then
        raidFrames:RefreshAll(false)
    end
end

function Configuration:_RefreshUnitScope(unitFrames, partyFrames, raidFrames, unitToken, forceLayout)
    if unitToken == "party" then
        if partyFrames and type(partyFrames.RefreshAll) == "function" then
            partyFrames:RefreshAll(forceLayout == true)
        end
        return
    end

    if unitToken == "raid" then
        if raidFrames and type(raidFrames.RefreshAll) == "function" then
            raidFrames:RefreshAll(forceLayout == true)
        end
        return
    end

    if unitFrames and type(unitFrames.RefreshFrame) == "function" then
        unitFrames:RefreshFrame(unitToken, forceLayout == true)
    elseif unitFrames and type(unitFrames.RefreshAll) == "function" then
        unitFrames:RefreshAll(forceLayout == true)
    end
end

function Configuration:_ApplyQueuedRefreshRequest(request)
    if type(request) ~= "table" then
        return
    end

    local unitFrames = self.addon:GetModule("unitFrames")
    local partyFrames = self.addon:GetModule("partyFrames")
    local raidFrames = self.addon:GetModule("raidFrames")
    if not unitFrames and not partyFrames and not raidFrames then
        return
    end

    if request.global and not isLayoutRefreshIntent(request.global) then
        self:_RefreshAllFrameModules(unitFrames, partyFrames, raidFrames, false)
    elseif not request.global then
        if request.trackedAuras then
            self:_RefreshTrackedAuraModules(partyFrames, raidFrames)
        end

        for unitToken, intent in pairs(request.units or {}) do
            if not isLayoutRefreshIntent(intent) then
                self:_RefreshUnitScope(unitFrames, partyFrames, raidFrames, unitToken, false)
            end
        end
    end

    local hasLayoutRefresh = false
    if request.global and isLayoutRefreshIntent(request.global) then
        hasLayoutRefresh = true
    else
        for _, intent in pairs(request.units or {}) do
            if isLayoutRefreshIntent(intent) then
                hasLayoutRefresh = true
                break
            end
        end
    end

    if not hasLayoutRefresh then
        return
    end

    Util:RunWhenOutOfCombat(function()
        if request.global and isLayoutRefreshIntent(request.global) then
            self:_RefreshAllFrameModules(unitFrames, partyFrames, raidFrames, true)
            return
        end

        for unitToken, intent in pairs(request.units or {}) do
            if isLayoutRefreshIntent(intent) then
                self:_RefreshUnitScope(unitFrames, partyFrames, raidFrames, unitToken, true)
            end
        end
    end, L.CONFIG_DEFERRED_APPLY, "config_refresh_layout")
end

-- Request unit frame refresh.
function Configuration:RequestUnitFrameRefresh(intent, target, immediate)
    local resolvedIntent = intent
    local resolvedTarget = target
    local resolvedImmediate = immediate

    if type(resolvedIntent) == "boolean" then
        resolvedImmediate = resolvedIntent
        resolvedIntent = nil
        resolvedTarget = nil
    elseif type(resolvedTarget) == "boolean" then
        resolvedImmediate = resolvedTarget
        resolvedTarget = nil
    end

    self:_QueueRefreshIntent(resolvedIntent, resolvedTarget)

    local function runRefresh()
        self._refreshScheduled = false
        local queuedRequest = self._pendingRefreshRequest
        self._pendingRefreshRequest = nil
        self:_ApplyQueuedRefreshRequest(queuedRequest)
    end

    local delay = (resolvedImmediate and 0) or REFRESH_DEBOUNCE_SECONDS
    if delay <= 0 then
        runRefresh()
        return
    end

    if self._refreshScheduled then
        return
    end

    self._refreshScheduled = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, runRefresh)
    else
        runRefresh()
    end
end

-- ============================================================================
-- UI CONTROL STATE MANAGEMENT
-- ============================================================================
-- Methods for setting/getting control values, enabling/disabling controls,
-- and managing visual feedback (alpha, color, text).

-- Set numeric control value.
function Configuration:SetNumericControlValue(control, value)
    if not control or not control.slider then
        return
    end

    local slider = control.slider
    local input = control.input
    local minValue, maxValue = slider:GetMinMaxValues()
    local step = slider:GetValueStep() or 1
    local normalized = normalizeNumericValue(value, minValue, maxValue, step)
    if not normalized then
        normalized = minValue
    end

    slider._refreshing = true
    slider:SetValue(normalized)
    slider._refreshing = false

    if input then
        input:SetText(formatNumericForDisplay(normalized))
    end
end

-- Set numeric control enabled state.
function Configuration:SetNumericControlEnabled(control, enabled)
    if not control then
        return
    end

    local alpha = enabled and 1 or 0.55
    if control.slider then
        if enabled and type(control.slider.Enable) == "function" then
            control.slider:Enable()
        elseif (not enabled) and type(control.slider.Disable) == "function" then
            control.slider:Disable()
        end
        control.slider:SetAlpha(alpha)
    end
    if control.input then
        if enabled and type(control.input.Enable) == "function" then
            control.input:Enable()
        elseif (not enabled) and type(control.input.Disable) == "function" then
            control.input:Disable()
        end
        control.input:SetAlpha(alpha)
    end
end

-- Set select control enabled state.
function Configuration:SetSelectControlEnabled(control, enabled)
    if not control then
        return
    end
    control:EnableMouse(enabled == true)
    control:SetAlpha(enabled and 1 or 0.55)
end

-- Set edit box enabled state.
function Configuration:SetEditBoxEnabled(editBox, enabled)
    if not editBox then
        return
    end
    if enabled and type(editBox.Enable) == "function" then
        editBox:Enable()
    elseif (not enabled) and type(editBox.Disable) == "function" then
        editBox:Disable()
    end
    editBox:SetAlpha(enabled and 1 or 0.55)
end

-- Set button enabled state.
function Configuration:SetButtonEnabled(button, enabled)
    if not button then
        return
    end
    if enabled and type(button.Enable) == "function" then
        button:Enable()
    elseif (not enabled) and type(button.Disable) == "function" then
        button:Disable()
    end
    button:SetAlpha(enabled and 1 or 0.55)
end

-- Update the numeric label shown beside a slider.
function Configuration:SetSliderLabel(slider, value)
    if not slider then
        return
    end

    local label = _G[slider:GetName() .. "Text"]
    local baseLabel = slider._baseLabel or ""
    setFontStringTextSafe(label, baseLabel .. ": " .. formatNumericForDisplay(value), 12)
end

-- ============================================================================
-- UI CONTROL CREATION & BINDING
-- ============================================================================
-- Factory methods for creating UI controls (sliders, inputs, dropdowns, checkboxes)
-- and binding them to configuration data. Also handles select popup management.

-- Create numeric control.
function Configuration:CreateNumericControl(parent, keyPrefix, label, minValue, maxValue, step, anchor, anchorXOffset)
    local sliderName = "mummuFramesConfig" .. keyPrefix .. "Slider"
    local inputName = "mummuFramesConfig" .. keyPrefix .. "Input"

    local slider = createSlider(sliderName, parent, label, minValue, maxValue, step)
    local resolvedXOffset = anchorXOffset or 0
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", resolvedXOffset, -32)

    local input = createNumericEditBox(inputName, parent)
    input:SetPoint("LEFT", slider, "RIGHT", 18, 0)

    -- Return both widgets so callers can bind and toggle them together.
    local control = {
        slider = slider,
        input = input,
    }

    return control
end

-- Bind numeric control.
function Configuration:BindNumericControl(control, onValueCommitted)
    if not control or not control.slider then
        return
    end

    local slider = control.slider
    local input = control.input

    -- Commit raw value.
    local function commitRawValue(rawValue)
        local minValue, maxValue = slider:GetMinMaxValues()
        local step = slider:GetValueStep() or 1
        local normalized = normalizeNumericValue(rawValue, minValue, maxValue, step)
        if not normalized then
            self:SetNumericControlValue(control, slider:GetValue())
            return
        end
        slider:SetValue(normalized)
    end

    -- On slider value changed.
    local function onSliderValueChanged(_, value)
        local minValue, maxValue = slider:GetMinMaxValues()
        local step = slider:GetValueStep() or 1
        local normalized = normalizeNumericValue(value, minValue, maxValue, step)
        if not normalized then
            normalized = minValue
        end

        self:SetSliderLabel(slider, normalized)
        if input then
            input:SetText(formatNumericForDisplay(normalized))
        end

        if slider._refreshing then
            return
        end

        if onValueCommitted then
            onValueCommitted(normalized)
        end
    end

    slider:SetScript("OnValueChanged", onSliderValueChanged)

    if input then
        -- Handle OnEnterPressed script callback.
        input:SetScript("OnEnterPressed", function(editBox)
            commitRawValue(editBox:GetText())
            editBox:ClearFocus()
        end)

        -- Handle OnEditFocusLost script callback.
        input:SetScript("OnEditFocusLost", function(editBox)
            commitRawValue(editBox:GetText())
        end)

        -- Handle OnEscapePressed script callback.
        input:SetScript("OnEscapePressed", function(editBox)
            self:SetNumericControlValue(control, slider:GetValue())
            editBox:ClearFocus()
        end)
    end
end

-- Create options checkbox control.
function Configuration:CreateCheckbox(name, parent, label, anchor, xOffset, yOffset, relativePoint)
    -- Create checkbutton for check.
    local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, relativePoint or "BOTTOMLEFT", xOffset or 0, yOffset or -8)

    local text = _G[check:GetName() .. "Text"]
    Style:ApplyFont(text, 12)
    setFontStringTextSafe(text, label, 12)

    return check
end

local function splitConfigPath(path)
    local parts = {}
    if type(path) ~= "string" or path == "" then
        return parts
    end

    for token in string.gmatch(path, "[^%.]+") do
        parts[#parts + 1] = token
    end
    return parts
end

local function getTableValueAtPath(root, path)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return nil
    end

    local cursor = root
    local parts = splitConfigPath(path)
    for i = 1, #parts do
        if type(cursor) ~= "table" then
            return nil
        end
        cursor = cursor[parts[i]]
    end
    return cursor
end

local function setTableValueAtPath(root, path, value)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return
    end

    local cursor = root
    local parts = splitConfigPath(path)
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(cursor[part]) ~= "table" then
            cursor[part] = {}
        end
        cursor = cursor[part]
    end
    cursor[parts[#parts]] = value
end

local function makeDynamicControlKey(unitToken, suffix, showAdvanced)
    local modePrefix = showAdvanced and "Advanced" or "Basic"
    local token = tostring(unitToken or "")
    local cleanedToken = string.gsub(token, "[^%w]", "")
    local cleanedSuffix = string.gsub(tostring(suffix or ""), "[^%w]", "")
    return modePrefix .. cleanedToken .. cleanedSuffix
end

-- Create a prominent section header with supporting copy and divider.
function Configuration:CreateSectionHeader(parent, title, description, anchor, topSpacing)
    local titleText = parent:CreateFontString(nil, "ARTWORK")
    if anchor == parent then
        titleText:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -6)
    else
        titleText:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(topSpacing or 24))
    end
    titleText:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    Style:ApplyFont(titleText, 14)
    setFontStringTextSafe(titleText, title, 14)

    local lastAnchor = titleText
    if description and description ~= "" then
        local descriptionText = parent:CreateFontString(nil, "ARTWORK")
        descriptionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
        descriptionText:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
        descriptionText:SetJustifyH("LEFT")
        descriptionText:SetJustifyV("TOP")
        Style:ApplyFont(descriptionText, 11)
        setFontStringTextSafe(descriptionText, description, 11)
        descriptionText:SetTextColor(0.78, 0.81, 0.88, 0.96)
        lastAnchor = descriptionText
    end

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -10)
    divider:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)
    return divider
end

-- Create lower-emphasis body copy for page introductions.
function Configuration:CreateHelpText(parent, text, anchor, topSpacing)
    local body = parent:CreateFontString(nil, "ARTWORK")
    if anchor == parent then
        body:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -6)
    else
        body:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(topSpacing or 8))
    end
    body:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    Style:ApplyFont(body, 11)
    setFontStringTextSafe(body, text or "", 11)
    body:SetTextColor(0.8, 0.83, 0.9, 0.96)
    return body
end

-- Record one checkbox widget so page refresh can resync from config data.
function Configuration:RegisterCheckboxWidget(registry, control, getValue)
    if type(registry) ~= "table" or not control or type(getValue) ~= "function" then
        return
    end
    registry[#registry + 1] = {
        kind = "checkbox",
        control = control,
        getValue = getValue,
    }
end

-- Record one numeric widget so page refresh can resync from config data.
function Configuration:RegisterNumericWidget(registry, control, getValue)
    if type(registry) ~= "table" or not control or type(getValue) ~= "function" then
        return
    end
    registry[#registry + 1] = {
        kind = "numeric",
        control = control,
        getValue = getValue,
    }
end

-- Record one select widget so page refresh can resync from config data.
function Configuration:RegisterDropdownWidget(registry, control, forceRefreshOptions)
    if type(registry) ~= "table" or not control then
        return
    end
    registry[#registry + 1] = {
        kind = "dropdown",
        control = control,
        forceRefreshOptions = forceRefreshOptions == true,
    }
end

-- Apply a widget registry against a source config table.
function Configuration:SyncWidgetRegistry(registry, source)
    if type(registry) ~= "table" then
        return
    end

    for i = 1, #registry do
        local entry = registry[i]
        if entry.kind == "checkbox" and entry.control and type(entry.getValue) == "function" then
            entry.control:SetChecked(entry.getValue(source) == true)
        elseif entry.kind == "numeric" and entry.control and type(entry.getValue) == "function" then
            self:SetNumericControlValue(entry.control, entry.getValue(source))
        elseif entry.kind == "dropdown" and entry.control then
            self:RefreshSelectControlText(entry.control, entry.forceRefreshOptions == true)
        end
    end
end

-- Create and bind a profile-backed checkbox.
function Configuration:BindProfileCheckbox(control, path, intent, target, normalize)
    if not control or type(path) ~= "string" or path == "" then
        return
    end

    control:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        if not profile then
            return
        end

        local value = button:GetChecked() == true
        if type(normalize) == "function" then
            value = normalize(value, profile)
        end
        setTableValueAtPath(profile, path, value)
        self:RequestUnitFrameRefresh(intent, target)
    end)
end

-- Create and bind a profile-backed numeric control.
function Configuration:BindProfileNumeric(control, path, intent, target, normalize)
    if not control or type(path) ~= "string" or path == "" then
        return
    end

    self:BindNumericControl(control, function(value)
        local profile = self:GetProfile()
        if not profile then
            return
        end

        local resolved = value
        if type(normalize) == "function" then
            resolved = normalize(value, profile)
        end
        setTableValueAtPath(profile, path, resolved)
        self:RequestUnitFrameRefresh(intent, target)
    end)
end

-- Create and bind a unit-backed checkbox.
function Configuration:BindUnitCheckbox(control, unitToken, path, intent, normalize)
    if not control or type(unitToken) ~= "string" or unitToken == "" or type(path) ~= "string" or path == "" then
        return
    end

    control:SetScript("OnClick", function(button)
        local value = button:GetChecked() == true
        if type(normalize) == "function" then
            value = normalize(value)
        end

        local dataHandle = self:GetDataHandle()
        if not dataHandle then
            return
        end
        dataHandle:SetUnitConfig(unitToken, path, value)
        self:RequestUnitFrameRefresh(intent, unitToken)
    end)
end

-- Create and bind a unit-backed numeric control.
function Configuration:BindUnitNumeric(control, unitToken, path, intent, normalize)
    if not control or type(unitToken) ~= "string" or unitToken == "" or type(path) ~= "string" or path == "" then
        return
    end

    self:BindNumericControl(control, function(value)
        local resolved = value
        if type(normalize) == "function" then
            resolved = normalize(value)
        end

        local dataHandle = self:GetDataHandle()
        if not dataHandle then
            return
        end
        dataHandle:SetUnitConfig(unitToken, path, resolved)
        self:RequestUnitFrameRefresh(intent, unitToken)
    end)
end

-- Return the aura tracking config table.
function Configuration:GetTrackedAurasConfig()
    return ns.AuraHandle and ns.AuraHandle:GetAurasConfig() or nil
end

-- Ensure the Frames hub has a selected unit.
function Configuration:GetSelectedFrameUnit()
    if type(self._selectedFrameUnit) == "string" and UNIT_TAB_LABELS[self._selectedFrameUnit] then
        return self._selectedFrameUnit
    end
    self._selectedFrameUnit = "party"
    return self._selectedFrameUnit
end

-- ============================================================================
-- CONFIGURATION PAGE BUILDERS
-- ============================================================================
-- Methods that dynamically create the UI pages for each configuration section:
-- Profiles (import/export, active profile selection),
-- Global (general settings, fonts, bar textures),
-- Auras (aura display and filtering),
-- Unit (unit-specific frame layout and color options).

-- Build profiles page.
function Configuration:BuildProfilesPage(page)
    local dataHandle = self:GetDataHandle()
    if not dataHandle then
        return
    end

    local intro = self:CreateHelpText(
        page,
        L.CONFIG_PROFILES_HELP
            or "Profiles on this page are saved per character. Create separate layouts for this character, then export or import them when you want to share with another one.",
        page,
        0
    )

    local currentProfileAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_PROFILES_SECTION_CURRENT or "Current Profile",
        L.CONFIG_PROFILES_SECTION_CURRENT_HELP or "Choose which saved profile this character is using, then switch when you are ready.",
        intro,
        18
    )

    local profileControl = createLabeledDropdown(
        "mummuFramesConfigProfilesDropdown",
        page,
        L.CONFIG_PROFILES_SELECT or "Character profile",
        currentProfileAnchor
    )
    local profileDropdown = profileControl and profileControl.dropdown or nil
    if profileDropdown then
        self:InitializeProfilesDropdown(profileDropdown)
    end

    local activateButton = CreateFrame("Button", "mummuFramesConfigProfileActivateButton", page, "UIPanelButtonTemplate")
    activateButton:SetSize(126, 22)
    activateButton:SetPoint("TOPLEFT", profileDropdown or page, "BOTTOMLEFT", 0, -8)
    activateButton:SetText(L.CONFIG_PROFILES_ACTIVATE or "Activate profile")
    activateButton:SetScript("OnClick", function()
        local selectedName = self:GetSelectedProfileName()
        local ok, err = dataHandle:SetActiveProfile(selectedName)
        if not ok then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_SWITCH_FAILED or "Failed to change this character's profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self:UpdateMinimapButtonPosition()
        self:RefreshConfigWidgets()
        self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, "global", true)
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_SWITCHED or "This character is now using profile: %s", selectedName),
            0.3,
            1,
            0.45
        )
    end)

    local manageAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_PROFILES_SECTION_MANAGE or "Manage Profiles",
        L.CONFIG_PROFILES_SECTION_MANAGE_HELP or "Create, rename, or delete profiles that belong only to this character.",
        activateButton,
        20
    )

    local createLabel = page:CreateFontString(nil, "ARTWORK")
    createLabel:SetPoint("TOPLEFT", manageAnchor, "BOTTOMLEFT", 0, -14)
    setFontStringTextSafe(createLabel, L.CONFIG_PROFILES_CREATE_LABEL or "New profile name", 12)

    local createInput = createTextEditBox("mummuFramesConfigProfileCreateInput", page, 220)
    createInput:SetPoint("TOPLEFT", createLabel, "BOTTOMLEFT", 0, -6)

    local createButton = CreateFrame("Button", "mummuFramesConfigProfileCreateButton", page, "UIPanelButtonTemplate")
    createButton:SetSize(98, 22)
    createButton:SetPoint("LEFT", createInput, "RIGHT", 8, 0)
    createButton:SetText(L.CONFIG_PROFILES_CREATE or "Create")

    local renameLabel = page:CreateFontString(nil, "ARTWORK")
    renameLabel:SetPoint("TOPLEFT", createInput, "BOTTOMLEFT", 0, -16)
    setFontStringTextSafe(renameLabel, L.CONFIG_PROFILES_RENAME_LABEL or "Rename selected profile", 12)

    local renameInput = createTextEditBox("mummuFramesConfigProfileRenameInput", page, 220)
    renameInput:SetPoint("TOPLEFT", renameLabel, "BOTTOMLEFT", 0, -6)

    local renameButton = CreateFrame("Button", "mummuFramesConfigProfileRenameButton", page, "UIPanelButtonTemplate")
    renameButton:SetSize(98, 22)
    renameButton:SetPoint("LEFT", renameInput, "RIGHT", 8, 0)
    renameButton:SetText(L.CONFIG_PROFILES_RENAME or "Rename")

    local deleteButton = CreateFrame("Button", "mummuFramesConfigProfileDeleteButton", page, "UIPanelButtonTemplate")
    deleteButton:SetSize(150, 22)
    deleteButton:SetPoint("TOPLEFT", renameInput, "BOTTOMLEFT", 0, -8)
    deleteButton:SetText(L.CONFIG_PROFILES_DELETE or "Delete selected profile")

    local transferAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_PROFILES_SECTION_TRANSFER or "Share & Import",
        L.CONFIG_PROFILES_SECTION_TRANSFER_HELP or "Export a profile to move it to another character, or import one into this character under a new or existing profile name.",
        deleteButton,
        20
    )

    local exportButton = CreateFrame("Button", "mummuFramesConfigProfileExportButton", page, "UIPanelButtonTemplate")
    exportButton:SetSize(120, 22)
    exportButton:SetPoint("TOPLEFT", transferAnchor, "BOTTOMLEFT", 0, -14)
    exportButton:SetText(L.CONFIG_PROFILES_EXPORT or "Generate export")

    local exportLabel = page:CreateFontString(nil, "ARTWORK")
    exportLabel:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", 0, -8)
    setFontStringTextSafe(exportLabel, L.CONFIG_PROFILES_EXPORT_LABEL or "Export code", 12)

    local exportArea = createMultilineTextArea(
        "mummuFramesConfigProfilesExport",
        page,
        PROFILES_TEXTAREA_WIDTH,
        PROFILES_TEXTAREA_HEIGHT,
        exportLabel
    )
    local exportEdit = exportArea and exportArea.editBox or nil

    local selectExportButton = CreateFrame("Button", "mummuFramesConfigProfileExportSelectButton", page, "UIPanelButtonTemplate")
    selectExportButton:SetSize(140, 22)
    selectExportButton:SetPoint("TOPLEFT", exportArea.container, "BOTTOMLEFT", 0, -6)
    selectExportButton:SetText(L.CONFIG_PROFILES_EXPORT_SELECT or "Select export text")

    local importNameLabel = page:CreateFontString(nil, "ARTWORK")
    importNameLabel:SetPoint("TOPLEFT", selectExportButton, "BOTTOMLEFT", 0, -16)
    setFontStringTextSafe(importNameLabel, L.CONFIG_PROFILES_IMPORT_NAME_LABEL or "Import target profile name", 12)

    local importNameInput = createTextEditBox("mummuFramesConfigProfileImportNameInput", page, 220)
    importNameInput:SetPoint("TOPLEFT", importNameLabel, "BOTTOMLEFT", 0, -6)

    local overwriteExisting = self:CreateCheckbox(
        "mummuFramesConfigProfileImportOverwrite",
        page,
        L.CONFIG_PROFILES_IMPORT_OVERWRITE or "Overwrite profile if it already exists",
        importNameInput,
        0,
        -8
    )

    local importCodeLabel = page:CreateFontString(nil, "ARTWORK")
    importCodeLabel:SetPoint("TOPLEFT", overwriteExisting, "BOTTOMLEFT", 0, -16)
    setFontStringTextSafe(importCodeLabel, L.CONFIG_PROFILES_IMPORT_LABEL or "Import code", 12)

    local importArea = createMultilineTextArea(
        "mummuFramesConfigProfilesImport",
        page,
        PROFILES_TEXTAREA_WIDTH,
        PROFILES_TEXTAREA_HEIGHT,
        importCodeLabel
    )
    local importEdit = importArea and importArea.editBox or nil

    local importButton = CreateFrame("Button", "mummuFramesConfigProfileImportButton", page, "UIPanelButtonTemplate")
    importButton:SetSize(120, 22)
    importButton:SetPoint("TOPLEFT", importArea.container, "BOTTOMLEFT", 0, -6)
    importButton:SetText(L.CONFIG_PROFILES_IMPORT or "Import profile")

    local statusText = page:CreateFontString(nil, "ARTWORK")
    statusText:SetPoint("TOPLEFT", importButton, "BOTTOMLEFT", 0, -10)
    statusText:SetPoint("RIGHT", page, "RIGHT", -20, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    Style:ApplyFont(statusText, 11)
    statusText:SetText("")

    -- Read trimmed text input and treat empty strings as nil.
    local function getInputText(editBox)
        if not editBox then
            return nil
        end
        local text = editBox:GetText()
        text = type(text) == "string" and string.match(text, "^%s*(.-)%s*$") or nil
        if not text or text == "" then
            return nil
        end
        return text
    end

    createButton:SetScript("OnClick", function()
        local newName = getInputText(createInput)
        local sourceName = self:GetSelectedProfileName()
        local ok, err = dataHandle:CreateProfile(newName, sourceName)
        if not ok then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_CREATE_FAILED or "Failed to create profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self._profilesSelectedName = newName
        createInput:SetText("")
        self:RefreshConfigWidgets()
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_CREATED or "Created profile: %s", self._profilesSelectedName),
            0.3,
            1,
            0.45
        )
    end)

    renameButton:SetScript("OnClick", function()
        local oldName = self:GetSelectedProfileName()
        local newName = getInputText(renameInput)
        local ok, err = dataHandle:RenameProfile(oldName, newName)
        if not ok then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_RENAME_FAILED or "Failed to rename profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self._profilesSelectedName = newName
        self:RefreshConfigWidgets()
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_RENAMED or "Renamed profile to: %s", self._profilesSelectedName),
            0.3,
            1,
            0.45
        )
    end)

    deleteButton:SetScript("OnClick", function()
        local selectedName = self:GetSelectedProfileName()
        local ok, err = dataHandle:DeleteProfile(selectedName)
        if not ok then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_DELETE_FAILED or "Failed to delete profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self._profilesSelectedName = dataHandle:GetActiveProfileName()
        self:RefreshConfigWidgets()
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_DELETED or "Deleted profile: %s", selectedName),
            0.3,
            1,
            0.45
        )
    end)

    exportButton:SetScript("OnClick", function()
        local selectedName = self:GetSelectedProfileName()
        local code, err = dataHandle:ExportProfileCode(selectedName)
        if not code then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_EXPORT_FAILED or "Failed to export profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        if exportEdit then
            exportEdit:SetText(code)
            exportEdit:HighlightText()
            exportEdit:SetFocus()
        end
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_EXPORTED or "Export code generated for profile: %s", selectedName),
            0.3,
            1,
            0.45
        )
    end)

    selectExportButton:SetScript("OnClick", function()
        if exportEdit then
            exportEdit:SetFocus()
            exportEdit:HighlightText()
        end
    end)

    importButton:SetScript("OnClick", function()
        local code = importEdit and importEdit:GetText() or nil
        local targetName = getInputText(importNameInput)
        local overwrite = overwriteExisting and overwriteExisting:GetChecked() == true
        local importedName, err = dataHandle:ImportProfileCode(code, targetName, overwrite)
        if not importedName then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_IMPORT_FAILED or "Failed to import profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self._profilesSelectedName = importedName
        self:RefreshConfigWidgets()
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_IMPORTED or "Imported profile: %s", importedName),
            0.3,
            1,
            0.45
        )
    end)

    self.widgets.profiles = {
        dropdown = profileDropdown,
        activateButton = activateButton,
        createInput = createInput,
        renameInput = renameInput,
        deleteButton = deleteButton,
        exportEdit = exportEdit,
        importNameInput = importNameInput,
        overwriteCheckbox = overwriteExisting,
        importEdit = importEdit,
        statusText = statusText,
    }
end

-- Build global page.
function Configuration:BuildGlobalPage(page)
    local registry = {}

    local intro = self:CreateHelpText(
        page,
        L.CONFIG_GLOBAL_HELP
            or "Global settings apply across every frame style in the active profile, so this is the best place to set your overall look before tuning individual units.",
        page,
        0
    )

    local generalAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_GLOBAL_SECTION_GENERAL or "General",
        L.CONFIG_GLOBAL_SECTION_GENERAL_HELP or "Control whether the addon is active, whether Blizzard unit frames are suppressed, and whether test mode is enabled.",
        intro,
        18
    )

    local enableAddon = self:CreateCheckbox(
        "mummuFramesConfigEnableAddon",
        page,
        L.CONFIG_ENABLE,
        generalAnchor,
        0,
        -14
    )
    self:BindProfileCheckbox(enableAddon, "enabled", REFRESH_INTENT_LAYOUT, "global")
    self:RegisterCheckboxWidget(registry, enableAddon, function(profile)
        return profile.enabled ~= false
    end)

    local hideBlizzardUnitFrames = self:CreateCheckbox(
        "mummuFramesConfigHideBlizzardUnitFrames",
        page,
        L.CONFIG_HIDE_BLIZZARD_UNIT_FRAMES or "Hide Blizzard unit frames",
        enableAddon,
        0,
        -8
    )
    self:BindProfileCheckbox(hideBlizzardUnitFrames, "hideBlizzardUnitFrames", REFRESH_INTENT_LAYOUT, "global")
    self:RegisterCheckboxWidget(registry, hideBlizzardUnitFrames, function(profile)
        return profile.hideBlizzardUnitFrames == true
    end)

    local testMode = self:CreateCheckbox(
        "mummuFramesConfigTestMode",
        page,
        L.CONFIG_TEST_MODE,
        hideBlizzardUnitFrames,
        0,
        -8
    )
    self:BindProfileCheckbox(testMode, "testMode", REFRESH_INTENT_LAYOUT, "global")
    self:RegisterCheckboxWidget(registry, testMode, function(profile)
        return profile.testMode == true
    end)

    local styleAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_GLOBAL_SECTION_STYLE or "Shared Style",
        L.CONFIG_GLOBAL_SECTION_STYLE_HELP or "These settings become the default visual language for all frames in the current profile.",
        testMode
    )

    local pixelPerfect = self:CreateCheckbox(
        "mummuFramesConfigPixelPerfect",
        page,
        L.CONFIG_PIXEL_PERFECT,
        styleAnchor,
        0,
        -14
    )
    self:BindProfileCheckbox(pixelPerfect, "style.pixelPerfect", REFRESH_INTENT_APPEARANCE, "global")
    self:RegisterCheckboxWidget(registry, pixelPerfect, function(profile)
        profile.style = profile.style or {}
        return profile.style.pixelPerfect ~= false
    end)

    local darkMode = self:CreateCheckbox(
        "mummuFramesConfigDarkMode",
        page,
        L.CONFIG_DARK_MODE or "Dark Mode",
        pixelPerfect,
        0,
        -8
    )
    self:BindProfileCheckbox(darkMode, "style.darkMode", REFRESH_INTENT_APPEARANCE, "global")
    self:RegisterCheckboxWidget(registry, darkMode, function(profile)
        profile.style = profile.style or {}
        return profile.style.darkMode == true
    end)

    local globalFontSize = self:CreateNumericControl(
        page,
        "GlobalFontSize",
        L.CONFIG_FONT_SIZE,
        8,
        24,
        1,
        darkMode,
        20
    )
    self:BindProfileNumeric(globalFontSize, "style.fontSize", REFRESH_INTENT_APPEARANCE, "global", function(value)
        return math.floor((tonumber(value) or 12) + 0.5)
    end)
    self:RegisterNumericWidget(registry, globalFontSize, function(profile)
        profile.style = profile.style or {}
        return profile.style.fontSize or 12
    end)

    local fontControl = createLabeledDropdown(
        "mummuFramesConfigFontDropdown",
        page,
        L.CONFIG_FONT_FACE,
        globalFontSize.slider
    )
    local fontDropdown = fontControl and fontControl.dropdown or nil
    if fontDropdown then
        self:InitializeFontDropdown(fontDropdown)
        self:RegisterDropdownWidget(registry, fontDropdown, true)
    end

    local textureAnchor = fontDropdown or globalFontSize.slider
    local barTextureControl = createLabeledDropdown(
        "mummuFramesConfigBarTextureDropdown",
        page,
        L.CONFIG_BAR_TEXTURE or "Bar texture",
        textureAnchor
    )
    local barTextureDropdown = barTextureControl and barTextureControl.dropdown or nil
    if barTextureDropdown then
        self:InitializeBarTextureDropdown(barTextureDropdown)
        self:RegisterDropdownWidget(registry, barTextureDropdown, true)
    end

    self.widgets.global = {
        registry = registry,
        enableAddon = enableAddon,
        hideBlizzardUnitFrames = hideBlizzardUnitFrames,
        testMode = testMode,
        pixelPerfect = pixelPerfect,
        darkMode = darkMode,
        globalFontSize = globalFontSize,
        fontDropdown = fontDropdown,
        barTextureDropdown = barTextureDropdown,
    }
end

-- Build auras page.
function Configuration:BuildAurasPage(page)
    local auraHandle = ns.AuraHandle

    local registry = {}

    local intro = self:CreateHelpText(
        page,
        L.CONFIG_AURAS_HELP
            or "Track shared party and raid auras here. This page is for group-healing or support tracking, not the per-unit buff rows in the Frames page.",
        page,
        0
    )

    local trackingAnchor = self:CreateSectionHeader(
        page,
        L.CONFIG_AURAS_SECTION_TRACKING or "Tracking",
        L.CONFIG_AURAS_SECTION_TRACKING_HELP or "Enable tracked auras globally and choose the icon size used on party and raid frames.",
        intro,
        18
    )

    local enabled = self:CreateCheckbox(
        "mummuFramesConfigAurasEnabled",
        page,
        L.CONFIG_AURAS_ENABLE or "Aura tracking",
        trackingAnchor,
        0,
        -14
    )
    enabled:SetScript("OnClick", function(button)
        local config = self:GetTrackedAurasConfig()
        if not config then
            return
        end
        config.enabled = button:GetChecked() == true
        self:RequestUnitFrameRefresh(REFRESH_INTENT_DATA, "trackedAuras")
    end)
    self:RegisterCheckboxWidget(registry, enabled, function(config)
        return config and config.enabled ~= false
    end)

    local sizeControl = self:CreateNumericControl(
        page,
        "AurasSize",
        L.CONFIG_AURAS_SIZE or "Icon size",
        6,
        48,
        1,
        enabled,
        20
    )
    self:BindNumericControl(sizeControl, function(value)
        local config = self:GetTrackedAurasConfig()
        if not config then
            return
        end
        config.size = math.floor((tonumber(value) or 14) + 0.5)
        self:RequestUnitFrameRefresh(REFRESH_INTENT_DATA, "trackedAuras")
    end)
    self:RegisterNumericWidget(registry, sizeControl, function(config)
        return (config and config.size) or 14
    end)

    local filterDivider = self:CreateSectionHeader(
        page,
        L.CONFIG_AURAS_FILTER_HEADER or "Spell filter",
        L.CONFIG_AURAS_FILTER_HELP
            or "Only show buffs whose names are in this list. Leave empty to show all tracked auras that match the other rules.",
        sizeControl.slider
    )

    -- Scrollable spell list.
    local listWidth  = 380
    local listHeight = 180
    local rowHeight  = 20

    local listContainer = CreateFrame("Frame", "mummuFramesConfigAurasListContainer", page)
    listContainer:SetPoint("TOPLEFT", filterDivider, "BOTTOMLEFT", 0, -14)
    listContainer:SetSize(listWidth, listHeight)
    Style:CreateBackground(listContainer, 0.05, 0.05, 0.07, 0.9)

    local listScroll = CreateFrame(
        "ScrollFrame",
        "mummuFramesConfigAurasListScroll",
        listContainer,
        "UIPanelScrollFrameTemplate"
    )
    listScroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -28, 4)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(sf, delta)
        local cur    = sf:GetVerticalScroll() or 0
        local target = cur - delta * rowHeight
        if target < 0 then target = 0 end
        local maxR = sf:GetVerticalScrollRange() or 0
        if target > maxR then target = maxR end
        sf:SetVerticalScroll(target)
    end)

    local listChild = CreateFrame("Frame", "mummuFramesConfigAurasListChild", listScroll)
    listChild:SetSize(listWidth - 32, 1)
    listScroll:SetScrollChild(listChild)

    -- Track row frames so the spell list can be rebuilt without leaking widgets.
    local listRows = {}

    -- Rebuild the visible whitelist rows from the current aura config.
    local function refreshList()
        for i = 1, #listRows do
            listRows[i]:Hide()
        end
        listRows = {}

        local config = auraHandle and auraHandle:GetAurasConfig()
        local names  = (config and type(config.allowedSpells) == "table") and config.allowedSpells or {}
        local yOffset = 0

        for idx = 1, #names do
            local name = names[idx]
            local row  = CreateFrame("Button", nil, listChild)
            row:SetSize(listChild:GetWidth(), rowHeight)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -yOffset)

            local nameText = row:CreateFontString(nil, "ARTWORK")
            nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
            nameText:SetPoint("RIGHT", row, "RIGHT", -24, 0)
            nameText:SetJustifyH("LEFT")
            Style:ApplyFont(nameText, 11)
            setFontStringTextSafe(nameText, name, 11)

            local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            removeBtn:SetSize(18, 18)
            removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local capturedIdx = idx
            removeBtn:SetScript("OnClick", function()
                local cfg = auraHandle and auraHandle:GetAurasConfig()
                if not cfg or type(cfg.allowedSpells) ~= "table" then
                    return
                end
                table.remove(cfg.allowedSpells, capturedIdx)
                auraHandle:InvalidateAuraNameSetCache()
                self:RequestUnitFrameRefresh(REFRESH_INTENT_DATA, "trackedAuras")
                refreshList()
            end)

            listRows[#listRows + 1] = row
            yOffset = yOffset + rowHeight
        end

        listChild:SetHeight(math.max(1, yOffset))
    end

    -- Add-spell input row.
    local addLabel = page:CreateFontString(nil, "ARTWORK")
    addLabel:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -14)
    setFontStringTextSafe(addLabel, L.CONFIG_AURAS_ADD_LABEL or "Add spell name", 12)

    local addInput = createTextEditBox("mummuFramesConfigAurasAddInput", page, 220)
    addInput:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -6)

    local addButton = CreateFrame("Button", "mummuFramesConfigAurasAddButton", page, "UIPanelButtonTemplate")
    addButton:SetSize(64, 22)
    addButton:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
    if type(addButton.SetText) == "function" then
        addButton:SetText(L.CONFIG_AURAS_ADD or "Add")
    end

    local resetButton = CreateFrame("Button", "mummuFramesConfigAurasResetButton", page, "UIPanelButtonTemplate")
    resetButton:SetSize(160, 22)
    resetButton:SetPoint("TOPLEFT", addInput, "BOTTOMLEFT", 0, -8)
    if type(resetButton.SetText) == "function" then
        resetButton:SetText(L.CONFIG_AURAS_RESET or "Reset to class defaults")
    end

    -- Validate the input box value and append it to the aura whitelist.
    local function addSpellFromInput()
        local inputText = addInput and addInput:GetText() or nil
        if type(inputText) ~= "string" then
            return
        end
        inputText = string.match(inputText, "^%s*(.-)%s*$")
        if not inputText or inputText == "" then
            return
        end
        local config = auraHandle and auraHandle:GetAurasConfig()
        if not config then
            return
        end
        config.allowedSpells = config.allowedSpells or {}
        for _, existing in ipairs(config.allowedSpells) do
            if existing == inputText then
                addInput:SetText("")
                return
            end
        end
        config.allowedSpells[#config.allowedSpells + 1] = inputText
        auraHandle:InvalidateAuraNameSetCache()
        addInput:SetText("")
        self:RequestUnitFrameRefresh(REFRESH_INTENT_DATA, "trackedAuras")
        refreshList()
    end

    addButton:SetScript("OnClick", addSpellFromInput)
    addInput:SetScript("OnEnterPressed", function(editBox)
        addSpellFromInput()
        editBox:ClearFocus()
    end)
    addInput:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)

    resetButton:SetScript("OnClick", function()
        if auraHandle and type(auraHandle.ResetAurasToClassDefaults) == "function" then
            auraHandle:ResetAurasToClassDefaults()
            self:RequestUnitFrameRefresh(REFRESH_INTENT_DATA, "trackedAuras")
            refreshList()
        end
    end)

    self.widgets.auras = {
        registry     = registry,
        enabled     = enabled,
        size        = sizeControl,
        refreshList = refreshList,
    }
end

-- Build unit page.
function Configuration:BuildUnitPage(page, unitToken, options)
    local dataHandle = self:GetDataHandle()
    if not dataHandle then
        return nil
    end

    local advancedToggleRelevant = unitUsesAdvancedToggle(unitToken)
    local showAdvanced = advancedToggleRelevant and options and options.showAdvanced == true
    local widgetRegistry = {}
    local namePrefix = makeDynamicControlKey(unitToken, "Frame", showAdvanced)
    local pageWidgets = {
        unitToken = unitToken,
        showAdvanced = showAdvanced,
        advancedToggleRelevant = advancedToggleRelevant,
        registry = widgetRegistry,
    }

    local function getUnitConfig()
        return dataHandle:GetUnitConfig(unitToken)
    end

    local function registerCheckbox(nameSuffix, label, anchor, path, intent, getter, yOffset)
        local control = self:CreateCheckbox(
            "mummuFramesConfig" .. namePrefix .. nameSuffix,
            page,
            label,
            anchor,
            0,
            yOffset or -8
        )
        self:BindUnitCheckbox(control, unitToken, path, intent)
        self:RegisterCheckboxWidget(widgetRegistry, control, getter)
        return control
    end

    local function registerNumeric(nameSuffix, label, minValue, maxValue, step, anchor, path, intent, getter, normalize, anchorXOffset)
        local control = self:CreateNumericControl(
            page,
            namePrefix .. nameSuffix,
            label,
            minValue,
            maxValue,
            step,
            anchor,
            anchorXOffset
        )
        self:BindUnitNumeric(control, unitToken, path, intent, normalize)
        self:RegisterNumericWidget(widgetRegistry, control, getter)
        return control
    end

    local function registerDropdown(nameSuffix, label, anchor, initializer, forceRefreshOptions)
        local control = createLabeledDropdown(
            "mummuFramesConfig" .. namePrefix .. nameSuffix,
            page,
            label,
            anchor
        )
        local dropdown = control and control.dropdown or nil
        if dropdown and type(initializer) == "function" then
            initializer(self, dropdown)
            self:RegisterDropdownWidget(widgetRegistry, dropdown, forceRefreshOptions == true)
        end
        return control, dropdown
    end

    local function boolValue(path, fallback)
        return function(config)
            local value = getTableValueAtPath(config, path)
            if value == nil then
                return fallback == true
            end
            return value == true
        end
    end

    local function numericValue(path, fallback)
        return function(config)
            local value = getTableValueAtPath(config, path)
            if type(value) ~= "number" then
                value = tonumber(value)
            end
            if type(value) ~= "number" then
                return fallback
            end
            return value
        end
    end

    local hideBlizzardLabel = L.CONFIG_UNIT_HIDE_BLIZZARD or "Hide Blizzard frame"
    if unitToken == "party" then
        hideBlizzardLabel = L.CONFIG_PARTY_HIDE_BLIZZARD or hideBlizzardLabel
    elseif unitToken == "raid" then
        hideBlizzardLabel = L.CONFIG_RAID_HIDE_BLIZZARD or "Hide Blizzard raid frames"
    end

    local cursor = self:CreateSectionHeader(
        page,
        L.CONFIG_SECTION_VISIBILITY or "Visibility",
        L.CONFIG_SECTION_VISIBILITY_HELP or "Start with the settings that decide whether this frame appears and which Blizzard elements it replaces.",
        page
    )
    local enabled = registerCheckbox("Enabled", L.CONFIG_UNIT_ENABLE or "Enable frame", cursor, "enabled", REFRESH_INTENT_LAYOUT, boolValue("enabled", true), -14)
    local hideBlizzard = registerCheckbox("HideBlizzard", hideBlizzardLabel, enabled, "hideBlizzardFrame", REFRESH_INTENT_LAYOUT, boolValue("hideBlizzardFrame", false))

    local includePlayer
    local showSelfWithoutGroup
    if unitToken == "party" then
        includePlayer = registerCheckbox(
            "IncludePlayer",
            L.CONFIG_PARTY_INCLUDE_PLAYER or "Include player in party frames",
            hideBlizzard,
            "showPlayer",
            REFRESH_INTENT_LAYOUT,
            boolValue("showPlayer", true)
        )
        showSelfWithoutGroup = registerCheckbox(
            "ShowSelfWithoutGroup",
            L.CONFIG_PARTY_SHOW_SELF_WITHOUT_GROUP or "Show self without a group",
            includePlayer,
            "showSelfWithoutGroup",
            REFRESH_INTENT_LAYOUT,
            boolValue("showSelfWithoutGroup", true)
        )
        cursor = showSelfWithoutGroup
    else
        cursor = hideBlizzard
    end

    cursor = self:CreateSectionHeader(
        page,
        L.CONFIG_SECTION_LAYOUT or "Layout",
        L.CONFIG_SECTION_LAYOUT_HELP or "Adjust the frame size and any group-specific spacing so the overall footprint feels right first.",
        cursor
    )

    local width = registerNumeric(
        "Width",
        L.CONFIG_UNIT_WIDTH or "Width",
        100,
        600,
        1,
        cursor,
        "width",
        REFRESH_INTENT_LAYOUT,
        numericValue("width", 220),
        function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
        20
    )
    local height = registerNumeric(
        "Height",
        L.CONFIG_UNIT_HEIGHT or "Height",
        18,
        160,
        1,
        width.slider,
        "height",
        REFRESH_INTENT_LAYOUT,
        numericValue("height", 44),
        function(value) return math.floor((tonumber(value) or 0) + 0.5) end
    )

    local spacing
    local spacingX
    local spacingY
    local groupSpacing
    local partyLayoutDropdown
    local groupLayoutDropdown
    local sortDropdown
    local sortDirectionDropdown
    local testSizeDropdown
    local layoutAnchor = height.slider

    if unitToken == "party" then
        spacing = registerNumeric(
            "Spacing",
            L.CONFIG_PARTY_SPACING or "Gap between party frames",
            0,
            80,
            1,
            height.slider,
            "spacing",
            REFRESH_INTENT_LAYOUT,
            numericValue("spacing", 24),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        local partyLayoutControl = createLabeledDropdown(
            "mummuFramesConfig" .. namePrefix .. "PartyLayout",
            page,
            L.CONFIG_PARTY_LAYOUT or "Layout",
            spacing.slider
        )
        partyLayoutDropdown = partyLayoutControl and partyLayoutControl.dropdown or nil
        if partyLayoutDropdown then
            self:InitializePartyLayoutDropdown(partyLayoutDropdown)
            self:RegisterDropdownWidget(widgetRegistry, partyLayoutDropdown, false)
        end
        layoutAnchor = partyLayoutDropdown or spacing.slider
    elseif unitToken == "raid" then
        spacingX = registerNumeric(
            "SpacingX",
            L.CONFIG_RAID_SPACING_X or "Horizontal gap",
            0,
            80,
            1,
            height.slider,
            "spacingX",
            REFRESH_INTENT_LAYOUT,
            numericValue("spacingX", 5),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        spacingY = registerNumeric(
            "SpacingY",
            L.CONFIG_RAID_SPACING_Y or "Vertical gap",
            0,
            80,
            1,
            spacingX.slider,
            "spacingY",
            REFRESH_INTENT_LAYOUT,
            numericValue("spacingY", 6),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        groupSpacing = registerNumeric(
            "GroupSpacing",
            L.CONFIG_RAID_GROUP_SPACING or "Group gap",
            0,
            120,
            1,
            spacingY.slider,
            "groupSpacing",
            REFRESH_INTENT_LAYOUT,
            numericValue("groupSpacing", 12),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )

        local _, groupDropdown = registerDropdown(
            "GroupLayout",
            L.CONFIG_RAID_GROUP_LAYOUT or "Group layout",
            groupSpacing.slider,
            Configuration.InitializeRaidGroupLayoutDropdown,
            false
        )
        groupLayoutDropdown = groupDropdown
        local _, sortByDropdown = registerDropdown(
            "Sort",
            L.CONFIG_RAID_SORT or "Sort by",
            groupLayoutDropdown or groupSpacing.slider,
            Configuration.InitializeRaidSortDropdown,
            false
        )
        sortDropdown = sortByDropdown
        local _, sortDirDropdown = registerDropdown(
            "SortDirection",
            L.CONFIG_RAID_SORT_DIRECTION or "Sort direction",
            sortDropdown or groupLayoutDropdown or groupSpacing.slider,
            Configuration.InitializeRaidSortDirectionDropdown,
            false
        )
        sortDirectionDropdown = sortDirDropdown
        local _, sizeDropdown = registerDropdown(
            "TestSize",
            L.CONFIG_RAID_TEST_SIZE or "Test raid size",
            sortDirectionDropdown or sortDropdown or groupLayoutDropdown or groupSpacing.slider,
            Configuration.InitializeRaidTestSizeDropdown,
            false
        )
        testSizeDropdown = sizeDropdown
        layoutAnchor = testSizeDropdown or sortDirectionDropdown or sortDropdown or groupLayoutDropdown or groupSpacing.slider
    end

    cursor = self:CreateSectionHeader(
        page,
        L.CONFIG_SECTION_CONTENT or "Content & Indicators",
        L.CONFIG_SECTION_CONTENT_HELP or "Turn on the information that matters during combat before fine-tuning offsets and detached bars.",
        layoutAnchor
    )

    local showRoleIcon
    local spellTargetHighlight
    local powerHeight
    local powerOnTop
    local contentAnchor = cursor

    if unitToken == "party" then
        showRoleIcon = registerCheckbox(
            "ShowRoleIcon",
            L.CONFIG_PARTY_SHOW_ROLE_ICON or "Show role icon",
            cursor,
            "showRoleIcon",
            REFRESH_INTENT_APPEARANCE,
            boolValue("showRoleIcon", true),
            -14
        )
        spellTargetHighlight = registerCheckbox(
            "SpellTargetHighlight",
            L.CONFIG_PARTY_SPELL_TARGET_HIGHLIGHT or "Show curated Midnight cast target highlight",
            showRoleIcon,
            "spellTargetHighlight.enabled",
            REFRESH_INTENT_APPEARANCE,
            boolValue("spellTargetHighlight.enabled", true)
        )
        contentAnchor = spellTargetHighlight
    end

    if unitToken ~= "raid" then
        powerHeight = registerNumeric(
            "PowerHeight",
            L.CONFIG_UNIT_POWER_HEIGHT or "Power bar height",
            4,
            60,
            1,
            contentAnchor,
            "powerHeight",
            REFRESH_INTENT_LAYOUT,
            numericValue("powerHeight", 10),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            (contentAnchor == cursor) and 20 or nil
        )
        powerOnTop = registerCheckbox(
            "PowerOnTop",
            L.CONFIG_UNIT_POWER_ON_TOP or "Power bar on top",
            powerHeight.slider,
            "powerOnTop",
            REFRESH_INTENT_LAYOUT,
            boolValue("powerOnTop", false)
        )
        contentAnchor = powerOnTop
    end

    cursor = self:CreateSectionHeader(
        page,
        L.CONFIG_SECTION_TEXT or "Text",
        L.CONFIG_SECTION_TEXT_HELP or "Set the baseline text size here, then move into advanced offsets only if the frame still needs extra nudging.",
        contentAnchor
    )

    local fontSize = registerNumeric(
        "FontSize",
        L.CONFIG_UNIT_FONT_SIZE or "Unit font size",
        8,
        26,
        1,
        cursor,
        "fontSize",
        REFRESH_INTENT_APPEARANCE,
        numericValue("fontSize", 12),
        function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
        20
    )

    local textAnchor = fontSize.slider

    local buffsEnabled
    local buffsMax
    local buffsSize
    local buffsPositionDropdown
    local buffsSourceDropdown
    local debuffsEnabled
    local debuffsMax
    local debuffsSize
    local debuffsPositionDropdown
    local debuffsX
    local debuffsY
    local isGroupFrameUnit = unitToken == "party" or unitToken == "raid"
    do
        cursor = self:CreateSectionHeader(
            page,
            L.CONFIG_SECTION_BUFFS or "Buffs & Debuffs",
            L.CONFIG_SECTION_BUFFS_HELP or "Control how auras are displayed on this frame without mixing them up with tracked group-healing auras.",
            textAnchor
        )

        local debuffAnchor = cursor
        if not isGroupFrameUnit then
            buffsEnabled = registerCheckbox(
                "BuffsEnabled",
                L.CONFIG_UNIT_BUFFS_ENABLE or "Show buffs",
                cursor,
                "aura.buffs.enabled",
                REFRESH_INTENT_APPEARANCE,
                boolValue("aura.buffs.enabled", true),
                -14
            )
            buffsMax = registerNumeric(
                "BuffsMax",
                L.CONFIG_UNIT_BUFFS_MAX or "Buff count",
                1,
                16,
                1,
                buffsEnabled,
                "aura.buffs.max",
                REFRESH_INTENT_APPEARANCE,
                numericValue("aura.buffs.max", 8),
                function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
                20
            )
            buffsSize = registerNumeric(
                "BuffsSize",
                L.CONFIG_UNIT_BUFFS_SIZE or "Buff size",
                10,
                48,
                1,
                buffsMax.slider,
                "aura.buffs.size",
                REFRESH_INTENT_APPEARANCE,
                numericValue("aura.buffs.size", 18),
                function(value) return math.floor((tonumber(value) or 0) + 0.5) end
            )
            local _, buffPosition = registerDropdown(
                "BuffPosition",
                L.CONFIG_UNIT_BUFFS_POSITION or "Buff position",
                buffsSize.slider,
                function(configuration, dropdown)
                    configuration:InitializeBuffPositionDropdown(dropdown, unitToken)
                end,
                false
            )
            buffsPositionDropdown = buffPosition
            local _, buffSource = registerDropdown(
                "BuffSource",
                L.CONFIG_UNIT_BUFFS_SOURCE or "Buff source",
                buffsPositionDropdown or buffsSize.slider,
                function(configuration, dropdown)
                    configuration:InitializeBuffSourceDropdown(dropdown, unitToken)
                end,
                false
            )
            buffsSourceDropdown = buffSource
            debuffAnchor = buffsSourceDropdown or buffsPositionDropdown or buffsSize.slider or cursor
        end

        debuffsEnabled = registerCheckbox(
            "DebuffsEnabled",
            L.CONFIG_UNIT_DEBUFFS_ENABLE or "Show debuffs",
            debuffAnchor,
            "aura.debuffs.enabled",
            REFRESH_INTENT_APPEARANCE,
            boolValue("aura.debuffs.enabled", true),
            -14
        )
        debuffsMax = registerNumeric(
            "DebuffsMax",
            L.CONFIG_UNIT_DEBUFFS_MAX or "Debuff count",
            1,
            16,
            1,
            debuffsEnabled,
            "aura.debuffs.max",
            REFRESH_INTENT_APPEARANCE,
            numericValue("aura.debuffs.max", 8),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        debuffsSize = registerNumeric(
            "DebuffsSize",
            L.CONFIG_UNIT_DEBUFFS_SIZE or "Debuff size",
            10,
            48,
            1,
            debuffsMax.slider,
            "aura.debuffs.size",
            REFRESH_INTENT_APPEARANCE,
            numericValue("aura.debuffs.size", 18),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        local _, debuffPosition = registerDropdown(
            "DebuffPosition",
            L.CONFIG_UNIT_DEBUFFS_POSITION or "Debuff position",
            debuffsSize.slider,
            function(configuration, dropdown)
                configuration:InitializeDebuffPositionDropdown(dropdown, unitToken)
            end,
            false
        )
        debuffsPositionDropdown = debuffPosition
        debuffsX = registerNumeric(
            "DebuffsX",
            L.CONFIG_UNIT_DEBUFFS_X or "Debuff X offset",
            -80,
            80,
            1,
            debuffsPositionDropdown or debuffsSize.slider,
            "aura.debuffs.x",
            REFRESH_INTENT_APPEARANCE,
            numericValue("aura.debuffs.x", 0),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        debuffsY = registerNumeric(
            "DebuffsY",
            L.CONFIG_UNIT_DEBUFFS_Y or "Debuff Y offset",
            -80,
            80,
            1,
            debuffsX.slider,
            "aura.debuffs.y",
            REFRESH_INTENT_APPEARANCE,
            numericValue("aura.debuffs.y", -4),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        textAnchor = debuffsY.slider or debuffsX.slider or debuffsPositionDropdown or debuffsSize.slider
    end

    local castbarEnabled
    local castbarDetach
    local castbarWidth
    local castbarHeight
    local castbarShowIcon
    local castbarHideBlizzard
    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        cursor = self:CreateSectionHeader(
            page,
            L.CONFIG_SECTION_CASTBAR or "Cast Bar",
            L.CONFIG_SECTION_CASTBAR_HELP or "Keep the core cast-bar controls visible up front and leave detaching or Blizzard replacement for advanced setup.",
            textAnchor
        )

        castbarEnabled = registerCheckbox(
            "CastbarEnabled",
            L.CONFIG_UNIT_CASTBAR_ENABLE or "Show cast bar",
            cursor,
            "castbar.enabled",
            REFRESH_INTENT_LAYOUT,
            boolValue("castbar.enabled", true),
            -14
        )
        castbarWidth = registerNumeric(
            "CastbarWidth",
            L.CONFIG_UNIT_CASTBAR_WIDTH or "Cast bar width",
            50,
            600,
            1,
            castbarEnabled,
            "castbar.width",
            REFRESH_INTENT_LAYOUT,
            function(config)
                return tonumber(getTableValueAtPath(config, "castbar.width")) or tonumber(config.width) or 220
            end,
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        castbarHeight = registerNumeric(
            "CastbarHeight",
            L.CONFIG_UNIT_CASTBAR_HEIGHT or "Cast bar height",
            8,
            40,
            1,
            castbarWidth.slider,
            "castbar.height",
            REFRESH_INTENT_LAYOUT,
            numericValue("castbar.height", 20),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        castbarShowIcon = registerCheckbox(
            "CastbarShowIcon",
            L.CONFIG_UNIT_CASTBAR_SHOW_ICON or "Show spell icon",
            castbarHeight.slider,
            "castbar.showIcon",
            REFRESH_INTENT_APPEARANCE,
            boolValue("castbar.showIcon", true)
        )
        textAnchor = castbarShowIcon
    end

    local primaryPowerEnabled
    local primaryPowerDetach
    local primaryPowerWidth
    local secondaryPowerEnabled
    local secondaryPowerDetach
    local secondaryPowerSize
    local secondaryPowerWidth
    local tertiaryPowerEnabled
    local tertiaryPowerDetach
    local tertiaryPowerHeight
    local tertiaryPowerWidth

    if unitToken ~= "party" and unitToken ~= "raid" then
        cursor = self:CreateSectionHeader(
            page,
            L.CONFIG_SECTION_RESOURCES or "Resources",
            L.CONFIG_SECTION_RESOURCES_HELP or "Show the resource elements you need, then only move into detached widths and specialist bars if you want a more custom layout.",
            textAnchor
        )

        primaryPowerEnabled = registerCheckbox(
            "PrimaryPowerEnabled",
            L.CONFIG_UNIT_PRIMARY_POWER_ENABLE or "Show primary power bar",
            cursor,
            "primaryPower.enabled",
            REFRESH_INTENT_LAYOUT,
            boolValue("primaryPower.enabled", true),
            -14
        )
        textAnchor = primaryPowerEnabled

        if unitToken == "player" then
            secondaryPowerEnabled = registerCheckbox(
                "SecondaryPowerEnabled",
                L.CONFIG_UNIT_SECONDARY_POWER_ENABLE or "Show secondary power bar",
                primaryPowerEnabled,
                "secondaryPower.enabled",
                REFRESH_INTENT_LAYOUT,
                boolValue("secondaryPower.enabled", true)
            )
            tertiaryPowerEnabled = registerCheckbox(
                "TertiaryPowerEnabled",
                L.CONFIG_UNIT_TERTIARY_POWER_ENABLE or "Show tertiary power bar",
                secondaryPowerEnabled,
                "tertiaryPower.enabled",
                REFRESH_INTENT_LAYOUT,
                boolValue("tertiaryPower.enabled", true)
            )
            textAnchor = tertiaryPowerEnabled
        end
    end

    local xOffset
    local yOffset
    if showAdvanced then
        cursor = self:CreateSectionHeader(
            page,
            L.CONFIG_SECTION_ADVANCED or "Advanced",
            L.CONFIG_SECTION_ADVANCED_HELP or "These controls are useful when you already know the general shape you want and need more exact placement or detached sizing.",
            textAnchor
        )

        xOffset = registerNumeric(
            "XOffset",
            L.CONFIG_UNIT_X or "X offset",
            -1600,
            1600,
            1,
            cursor,
            "x",
            REFRESH_INTENT_POSITION,
            numericValue("x", 0),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        yOffset = registerNumeric(
            "YOffset",
            L.CONFIG_UNIT_Y or "Y offset",
            -1600,
            1600,
            1,
            xOffset.slider,
            "y",
            REFRESH_INTENT_POSITION,
            numericValue("y", 0),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
        textAnchor = yOffset.slider

        if castbarEnabled then
            castbarDetach = registerCheckbox(
                "CastbarDetach",
                L.CONFIG_UNIT_CASTBAR_DETACH or "Detach cast bar",
                yOffset.slider,
                "castbar.detached",
                REFRESH_INTENT_LAYOUT,
                boolValue("castbar.detached", false),
                -12
            )
            castbarHideBlizzard = registerCheckbox(
                "CastbarHideBlizzard",
                L.CONFIG_UNIT_CASTBAR_HIDE_BLIZZARD or "Hide Blizzard cast bar",
                castbarDetach,
                "castbar.hideBlizzardCastBar",
                REFRESH_INTENT_LAYOUT,
                boolValue("castbar.hideBlizzardCastBar", false)
            )
            textAnchor = castbarHideBlizzard
        end

        if unitToken == "player" then
            local baseAdvancedAnchor = castbarHideBlizzard or yOffset.slider
            primaryPowerDetach = registerCheckbox(
                "PrimaryPowerDetach",
                L.CONFIG_UNIT_PRIMARY_POWER_DETACH or "Detach primary power bar",
                baseAdvancedAnchor,
                "primaryPower.detached",
                REFRESH_INTENT_LAYOUT,
                boolValue("primaryPower.detached", false),
                (baseAdvancedAnchor == yOffset.slider) and -12 or -8
            )
            primaryPowerWidth = registerNumeric(
                "PrimaryPowerWidth",
                L.CONFIG_UNIT_PRIMARY_POWER_WIDTH or "Primary power bar width",
                80,
                600,
                1,
                primaryPowerDetach,
                "primaryPower.width",
                REFRESH_INTENT_LAYOUT,
                function(config)
                    local baseUnitWidth = Util:Clamp(tonumber(config.width) or 220, 100, 600)
                    return tonumber(getTableValueAtPath(config, "primaryPower.width"))
                        or Util:Clamp(math.floor((baseUnitWidth - 2) + 0.5), 80, 600)
                end,
                function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
                20
            )
            secondaryPowerDetach = registerCheckbox(
                "SecondaryPowerDetach",
                L.CONFIG_UNIT_SECONDARY_POWER_DETACH or "Detach secondary power bar",
                primaryPowerWidth.slider,
                "secondaryPower.detached",
                REFRESH_INTENT_LAYOUT,
                boolValue("secondaryPower.detached", false),
                -12
            )
            secondaryPowerSize = registerNumeric(
                "SecondaryPowerSize",
                L.CONFIG_UNIT_SECONDARY_POWER_SIZE or "Secondary power size",
                8,
                60,
                1,
                secondaryPowerDetach,
                "secondaryPower.size",
                REFRESH_INTENT_LAYOUT,
                numericValue("secondaryPower.size", 16),
                function(value)
                    return math.floor((tonumber(value) or 0) + 0.5)
                end,
                20
            )
            secondaryPowerWidth = registerNumeric(
                "SecondaryPowerWidth",
                L.CONFIG_UNIT_SECONDARY_POWER_WIDTH or "Secondary power bar width",
                80,
                600,
                1,
                secondaryPowerSize.slider,
                "secondaryPower.width",
                REFRESH_INTENT_LAYOUT,
                function(config)
                    local baseUnitWidth = Util:Clamp(tonumber(config.width) or 220, 100, 600)
                    local size = Util:Clamp(math.floor((tonumber(getTableValueAtPath(config, "secondaryPower.size")) or 16) + 0.5), 8, 60)
                    local fallback = Util:Clamp(math.max(math.floor((baseUnitWidth * 0.75) + 0.5), size * 8), 80, 600)
                    local configured = tonumber(getTableValueAtPath(config, "secondaryPower.width")) or fallback
                    return Util:Clamp(math.max(configured, size * 8), 80, 600)
                end,
                function(value)
                    return math.floor((tonumber(value) or 0) + 0.5)
                end
            )
            tertiaryPowerDetach = registerCheckbox(
                "TertiaryPowerDetach",
                L.CONFIG_UNIT_TERTIARY_POWER_DETACH or "Detach tertiary power bar",
                secondaryPowerWidth.slider,
                "tertiaryPower.detached",
                REFRESH_INTENT_LAYOUT,
                boolValue("tertiaryPower.detached", false),
                -12
            )
            tertiaryPowerHeight = registerNumeric(
                "TertiaryPowerHeight",
                L.CONFIG_UNIT_TERTIARY_POWER_HEIGHT or "Tertiary power bar height",
                4,
                24,
                1,
                tertiaryPowerDetach,
                "tertiaryPower.height",
                REFRESH_INTENT_LAYOUT,
                numericValue("tertiaryPower.height", 8),
                function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
                20
            )
            tertiaryPowerWidth = registerNumeric(
                "TertiaryPowerWidth",
                L.CONFIG_UNIT_TERTIARY_POWER_WIDTH or "Tertiary power bar width",
                80,
                600,
                1,
                tertiaryPowerHeight.slider,
                "tertiaryPower.width",
                REFRESH_INTENT_LAYOUT,
                function(config)
                    local baseUnitWidth = Util:Clamp(tonumber(config.width) or 220, 100, 600)
                    return tonumber(getTableValueAtPath(config, "tertiaryPower.width"))
                        or Util:Clamp(math.floor((baseUnitWidth - 2) + 0.5), 80, 520)
                end,
                function(value) return math.floor((tonumber(value) or 0) + 0.5) end
            )
        end
    elseif not advancedToggleRelevant then
        cursor = self:CreateSectionHeader(
            page,
            L.CONFIG_SECTION_POSITION or "Position",
            L.CONFIG_SECTION_POSITION_HELP or "Use these controls when the frame shape is already right and you only need to nudge where it sits.",
            textAnchor
        )

        xOffset = registerNumeric(
            "XOffset",
            L.CONFIG_UNIT_X or "X offset",
            -1600,
            1600,
            1,
            cursor,
            "x",
            REFRESH_INTENT_POSITION,
            numericValue("x", 0),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
            20
        )
        yOffset = registerNumeric(
            "YOffset",
            L.CONFIG_UNIT_Y or "Y offset",
            -1600,
            1600,
            1,
            xOffset.slider,
            "y",
            REFRESH_INTENT_POSITION,
            numericValue("y", 0),
            function(value) return math.floor((tonumber(value) or 0) + 0.5) end
        )
    end

    function pageWidgets:Refresh()
        local unitConfig = getUnitConfig()
        if not unitConfig then
            return
        end

        self._owner:SyncWidgetRegistry(self.registry, unitConfig)

        if buffsEnabled then
            local enabledBuffs = getTableValueAtPath(unitConfig, "aura.buffs.enabled")
            local buffWidgetsEnabled = enabledBuffs ~= false
            if buffsMax then
                self._owner:SetNumericControlEnabled(buffsMax, buffWidgetsEnabled)
            end
            if buffsSize then
                self._owner:SetNumericControlEnabled(buffsSize, buffWidgetsEnabled)
            end
            if buffsPositionDropdown then
                self._owner:SetSelectControlEnabled(buffsPositionDropdown, buffWidgetsEnabled)
            end
            if buffsSourceDropdown then
                self._owner:SetSelectControlEnabled(buffsSourceDropdown, buffWidgetsEnabled)
            end
        end

        if debuffsEnabled then
            local enabledDebuffs = getTableValueAtPath(unitConfig, "aura.debuffs.enabled")
            local debuffWidgetsEnabled = enabledDebuffs ~= false
            if debuffsMax then
                self._owner:SetNumericControlEnabled(debuffsMax, debuffWidgetsEnabled)
            end
            if debuffsSize then
                self._owner:SetNumericControlEnabled(debuffsSize, debuffWidgetsEnabled)
            end
            if debuffsPositionDropdown then
                self._owner:SetSelectControlEnabled(debuffsPositionDropdown, debuffWidgetsEnabled)
            end
            if debuffsX then
                self._owner:SetNumericControlEnabled(debuffsX, debuffWidgetsEnabled)
            end
            if debuffsY then
                self._owner:SetNumericControlEnabled(debuffsY, debuffWidgetsEnabled)
            end
        end

        if castbarWidth then
            local castbarIsEnabled = getTableValueAtPath(unitConfig, "castbar.enabled") ~= false
            self._owner:SetNumericControlEnabled(castbarWidth, castbarIsEnabled)
            self._owner:SetNumericControlEnabled(castbarHeight, castbarIsEnabled)
            if castbarShowIcon then
                self._owner:SetButtonEnabled(castbarShowIcon, castbarIsEnabled)
                castbarShowIcon:SetAlpha(castbarIsEnabled and 1 or 0.55)
            end
            if castbarDetach then
                self._owner:SetButtonEnabled(castbarDetach, castbarIsEnabled)
                castbarDetach:SetAlpha(castbarIsEnabled and 1 or 0.55)
            end
            if castbarHideBlizzard then
                self._owner:SetButtonEnabled(castbarHideBlizzard, castbarIsEnabled)
                castbarHideBlizzard:SetAlpha(castbarIsEnabled and 1 or 0.55)
            end
        end

        if primaryPowerEnabled then
            local primaryEnabled = getTableValueAtPath(unitConfig, "primaryPower.enabled") ~= false
            if primaryPowerDetach then
                self._owner:SetButtonEnabled(primaryPowerDetach, primaryEnabled)
                primaryPowerDetach:SetAlpha(primaryEnabled and 1 or 0.55)
            end
            if primaryPowerWidth then
                self._owner:SetNumericControlEnabled(primaryPowerWidth, primaryEnabled)
            end
        end

        if secondaryPowerEnabled then
            local secondaryEnabled = getTableValueAtPath(unitConfig, "secondaryPower.enabled") ~= false
            if secondaryPowerDetach then
                self._owner:SetButtonEnabled(secondaryPowerDetach, secondaryEnabled)
                secondaryPowerDetach:SetAlpha(secondaryEnabled and 1 or 0.55)
            end
            if secondaryPowerSize then
                self._owner:SetNumericControlEnabled(secondaryPowerSize, secondaryEnabled)
            end
            if secondaryPowerWidth then
                self._owner:SetNumericControlEnabled(secondaryPowerWidth, secondaryEnabled)
            end
        end

        if tertiaryPowerEnabled then
            local tertiaryEnabled = getTableValueAtPath(unitConfig, "tertiaryPower.enabled") ~= false
            if tertiaryPowerDetach then
                self._owner:SetButtonEnabled(tertiaryPowerDetach, tertiaryEnabled)
                tertiaryPowerDetach:SetAlpha(tertiaryEnabled and 1 or 0.55)
            end
            if tertiaryPowerHeight then
                self._owner:SetNumericControlEnabled(tertiaryPowerHeight, tertiaryEnabled)
            end
            if tertiaryPowerWidth then
                self._owner:SetNumericControlEnabled(tertiaryPowerWidth, tertiaryEnabled)
            end
        end
    end

    pageWidgets._owner = self
    pageWidgets:Refresh()
    return pageWidgets
end

local function getFramesPageKey(unitToken, showAdvanced)
    return tostring(unitToken or "") .. ":" .. ((showAdvanced and "advanced") or "basic")
end

-- Build the Frames hub page with grouped unit navigation.
function Configuration:BuildFramesPage(page)
    local intro = self:CreateHelpText(
        page,
        L.CONFIG_FRAMES_HELP
            or "Pick a frame on the left, then work top-to-bottom through the sections on the right. Basic mode keeps the most common controls visible first.",
        page,
        0
    )

    local selector = CreateFrame("Frame", nil, page)
    selector:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)
    selector:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    selector:SetWidth(FRAME_SELECTOR_WIDTH)
    Style:CreateBackground(selector, 0.05, 0.05, 0.07, 0.88)

    local selectorInset = CreateFrame("Frame", nil, selector)
    selectorInset:SetPoint("TOPLEFT", selector, "TOPLEFT", 12, -12)
    selectorInset:SetPoint("TOPRIGHT", selector, "TOPRIGHT", -12, -12)
    selectorInset:SetPoint("BOTTOM", selector, "BOTTOM", 0, 12)

    local rightPane = CreateFrame("Frame", nil, page)
    rightPane:SetPoint("TOPLEFT", selector, "TOPRIGHT", 18, 0)
    rightPane:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, 0)
    rightPane:SetPoint("BOTTOM", page, "BOTTOM", 0, 0)

    local headerControls = CreateFrame("Frame", nil, rightPane)
    headerControls:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, 0)
    headerControls:SetSize(240, 56)

    local unitTitle = rightPane:CreateFontString(nil, "ARTWORK")
    unitTitle:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, 0)
    unitTitle:SetPoint("RIGHT", headerControls, "LEFT", -16, 0)
    Style:ApplyFont(unitTitle, 16)

    local unitDescription = rightPane:CreateFontString(nil, "ARTWORK")
    unitDescription:SetPoint("TOPLEFT", unitTitle, "BOTTOMLEFT", 0, -4)
    unitDescription:SetPoint("RIGHT", headerControls, "LEFT", -16, 0)
    unitDescription:SetJustifyH("LEFT")
    unitDescription:SetJustifyV("TOP")
    Style:ApplyFont(unitDescription, 11)
    unitDescription:SetTextColor(0.8, 0.83, 0.9, 0.96)

    local advancedToggle = self:CreateCheckbox(
        "mummuFramesConfigFramesAdvancedToggle",
        rightPane,
        L.CONFIG_FRAMES_SHOW_ADVANCED or "Show advanced options",
        headerControls,
        0,
        -2,
        "TOPRIGHT"
    )
    advancedToggle:ClearAllPoints()
    advancedToggle:SetPoint("TOPRIGHT", headerControls, "TOPRIGHT", 0, -2)
    local advancedToggleText = _G[advancedToggle:GetName() .. "Text"]
    if advancedToggleText then
        advancedToggleText:ClearAllPoints()
        advancedToggleText:SetPoint("LEFT", headerControls, "LEFT", 0, 0)
        advancedToggleText:SetPoint("RIGHT", advancedToggle, "LEFT", -6, 0)
        advancedToggleText:SetJustifyH("RIGHT")
        advancedToggleText:SetWordWrap(false)
    end
    if type(advancedToggle.SetHitRectInsets) == "function" then
        advancedToggle:SetHitRectInsets(-196, 0, 0, 0)
    end
    advancedToggle:SetScript("OnClick", function(button)
        self._showAdvancedFrameOptions = button:GetChecked() == true
        self:RefreshFramesPage(true)
    end)

    local resetButton = CreateFrame("Button", "mummuFramesConfigFramesResetButton", headerControls, "UIPanelButtonTemplate")
    resetButton:SetSize(158, 22)
    resetButton:SetPoint("TOPRIGHT", advancedToggle, "BOTTOMRIGHT", 0, -6)
    resetButton:SetText(L.CONFIG_FRAMES_RESET_UNIT or "Reset this frame")
    resetButton:SetScript("OnClick", function()
        local dataHandle = self:GetDataHandle()
        local selectedUnit = self:GetSelectedFrameUnit()
        if not dataHandle or not selectedUnit then
            return
        end

        dataHandle:ResetUnitConfig(selectedUnit)
        self:RefreshFramesPage(true)
        self:RequestUnitFrameRefresh(REFRESH_INTENT_LAYOUT, selectedUnit, true)
    end)

    local headerDivider = rightPane:CreateTexture(nil, "ARTWORK")
    headerDivider:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -68)
    headerDivider:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, -68)
    headerDivider:SetHeight(1)
    headerDivider:SetColorTexture(1, 1, 1, 0.08)

    local contentPage, content = self:CreateScrollableTabPage(rightPane)
    contentPage:SetPoint("TOPLEFT", headerDivider, "BOTTOMLEFT", 0, -8)
    contentPage:SetPoint("TOPRIGHT", rightPane, "TOPRIGHT", 0, -8)
    contentPage:SetPoint("BOTTOMLEFT", rightPane, "BOTTOMLEFT", 0, 0)
    contentPage:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", 0, 0)

    local framesWidgets = {
        intro = intro,
        selector = selector,
        selectorInset = selectorInset,
        rightPane = rightPane,
        headerControls = headerControls,
        unitTitle = unitTitle,
        unitDescription = unitDescription,
        advancedToggle = advancedToggle,
        advancedToggleText = advancedToggleText,
        resetButton = resetButton,
        headerDivider = headerDivider,
        contentPage = contentPage,
        content = content,
        buttons = {},
        unitPages = {},
    }
    self.widgets.frames = framesWidgets

    local anchor = selectorInset
    for groupIndex = 1, #FRAME_SELECTOR_GROUPS do
        local group = FRAME_SELECTOR_GROUPS[groupIndex]
        local groupLabel = selectorInset:CreateFontString(nil, "ARTWORK")
        if anchor == selectorInset then
            groupLabel:SetPoint("TOPLEFT", selectorInset, "TOPLEFT", 0, 0)
        else
            groupLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -FRAME_SELECTOR_GROUP_GAP)
        end
        groupLabel:SetPoint("RIGHT", selectorInset, "RIGHT", 0, 0)
        Style:ApplyFont(groupLabel, 11)
        setFontStringTextSafe(groupLabel, group.label, 11)
        groupLabel:SetTextColor(0.73, 0.78, 0.88, group.subdued and 0.72 or 0.92)

        local previous = groupLabel
        for unitIndex = 1, #group.units do
            local unitToken = group.units[unitIndex]
            local button = CreateFrame("Button", "mummuFramesConfigFramesSelect" .. unitToken, selectorInset)
            button:SetSize(FRAME_SELECTOR_WIDTH - 24, FRAME_SELECTOR_BUTTON_HEIGHT)
            button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)

            local background = button:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(1, 1, 1, 0.04)
            button._background = background

            local label = button:CreateFontString(nil, "ARTWORK")
            label:SetPoint("LEFT", button, "LEFT", 10, 0)
            label:SetPoint("RIGHT", button, "RIGHT", -10, 0)
            label:SetJustifyH("LEFT")
            Style:ApplyFont(label, 12)
            setFontStringTextSafe(label, UNIT_TAB_LABELS[unitToken] or unitToken, 12)
            label:SetAlpha(group.subdued and 0.78 or 0.95)
            button._label = label
            button._subdued = group.subdued == true

            button:SetScript("OnClick", function()
                self:SelectFrameUnit(unitToken)
            end)
            button:SetScript("OnEnter", function()
                if self:GetSelectedFrameUnit() ~= unitToken then
                    button._background:SetColorTexture(1, 1, 1, 0.09)
                end
            end)
            button:SetScript("OnLeave", function()
                if self:GetSelectedFrameUnit() ~= unitToken then
                    button._background:SetColorTexture(1, 1, 1, 0.04)
                end
            end)

            framesWidgets.buttons[unitToken] = button
            previous = button
        end

        anchor = previous
    end

    self:RefreshFramesPage(true)
end

-- Refresh the Frames hub selection state and visible unit page.
function Configuration:RefreshFramesPage(forceSync)
    local framesWidgets = self.widgets and self.widgets.frames
    if not framesWidgets then
        return
    end

    local selectedUnit = self:GetSelectedFrameUnit()
    local advancedToggleRelevant = unitUsesAdvancedToggle(selectedUnit)
    local showAdvanced = advancedToggleRelevant and self._showAdvancedFrameOptions == true

    if framesWidgets.advancedToggle then
        framesWidgets.advancedToggle:SetShown(advancedToggleRelevant)
        framesWidgets.advancedToggle:SetChecked(showAdvanced)
    end
    if framesWidgets.resetButton then
        framesWidgets.resetButton:ClearAllPoints()
        if advancedToggleRelevant and framesWidgets.advancedToggle then
            framesWidgets.resetButton:SetPoint("TOPRIGHT", framesWidgets.advancedToggle, "BOTTOMRIGHT", 0, -6)
        elseif framesWidgets.headerControls then
            framesWidgets.resetButton:SetPoint("TOPRIGHT", framesWidgets.headerControls, "TOPRIGHT", 0, -2)
        else
            framesWidgets.resetButton:SetPoint("TOPRIGHT", framesWidgets.rightPane, "TOPRIGHT", 0, -2)
        end
    end
    if framesWidgets.unitTitle then
        setFontStringTextSafe(framesWidgets.unitTitle, UNIT_TAB_LABELS[selectedUnit] or selectedUnit, 16)
    end
    if framesWidgets.unitDescription then
        setFontStringTextSafe(framesWidgets.unitDescription, FRAME_UNIT_DESCRIPTION[selectedUnit] or "", 11)
    end

    for unitToken, button in pairs(framesWidgets.buttons or {}) do
        local selected = unitToken == selectedUnit
        if button._background then
            if selected then
                button._background:SetColorTexture(0.18, 0.66, 1, 0.18)
            else
                button._background:SetColorTexture(1, 1, 1, 0.04)
            end
        end
        if button._label then
            if selected then
                button._label:SetAlpha(1)
            else
                button._label:SetAlpha(button._subdued and 0.78 or 0.9)
            end
        end
    end

    local pageKey = getFramesPageKey(selectedUnit, showAdvanced)
    local pageInfo = framesWidgets.unitPages[pageKey]
    if not pageInfo then
        local root = CreateFrame("Frame", nil, framesWidgets.content)
        root:SetPoint("TOPLEFT", framesWidgets.content, "TOPLEFT", 0, 0)
        root:SetPoint("RIGHT", framesWidgets.content, "RIGHT", 0, 0)
        root:SetHeight(CONFIG_PAGE_CONTENT_HEIGHT)

        pageInfo = {
            key = pageKey,
            unitToken = selectedUnit,
            showAdvanced = showAdvanced,
            root = root,
            widgets = self:BuildUnitPage(root, selectedUnit, { showAdvanced = showAdvanced }),
        }
        framesWidgets.unitPages[pageKey] = pageInfo
    end

    for key, info in pairs(framesWidgets.unitPages) do
        if info and info.root then
            info.root:SetShown(key == pageKey)
        end
    end

    if pageInfo and pageInfo.widgets and type(pageInfo.widgets.Refresh) == "function" then
        pageInfo.widgets:Refresh()
    end

    if framesWidgets.contentPage and framesWidgets.contentPage.ScrollFrame then
        framesWidgets.contentPage.ScrollFrame:SetVerticalScroll(0)
    end
end

-- Select a frame unit inside the Frames hub.
function Configuration:SelectFrameUnit(unitToken)
    if type(unitToken) ~= "string" or not UNIT_TAB_LABELS[unitToken] then
        return
    end
    self._selectedFrameUnit = unitToken
    self:RefreshFramesPage(true)
end

-- Select visible configuration tab.
function Configuration:EnsureTabPageBuilt(tabKey)
    local hostPage = self.tabPages and self.tabPages[tabKey] or nil
    if not hostPage or hostPage._built then
        return
    end

    if tabKey == "frames" then
        self:BuildFramesPage(hostPage)
    else
        local innerPage, content = self:CreateScrollableTabPage(hostPage)
        innerPage:SetAllPoints(hostPage)
        hostPage.InnerPage = innerPage

        if tabKey == "global" then
            self:BuildGlobalPage(content)
        elseif tabKey == "profiles" then
            self:BuildProfilesPage(content)
        elseif tabKey == "auras" then
            self:BuildAurasPage(content)
        end
    end

    hostPage._built = true
end

function Configuration:SelectTab(tabKey)
    if not self.tabPages then
        return
    end

    self:EnsureTabPageBuilt(tabKey)

    for key, page in pairs(self.tabPages) do
        if page then
            local selected = key == tabKey
            page:SetShown(selected)
            local scrollOwner = page.InnerPage or page
            if selected and scrollOwner and scrollOwner.ScrollFrame then
                scrollOwner.ScrollFrame:SetVerticalScroll(0)
                scrollOwner.ScrollFrame:SetHorizontalScroll(0)
                if scrollOwner.ScrollBar then
                    if type(scrollOwner.ScrollBar.SetValue) == "function" then
                        scrollOwner.ScrollBar:SetValue(0)
                    elseif type(scrollOwner.ScrollBar.SetScrollPercentage) == "function" then
                        scrollOwner.ScrollBar:SetScrollPercentage(0, true)
                    end
                end
            end
        end
    end

    for key, button in pairs(self.widgets.tabs) do
        if button then
            local selected = key == tabKey
            if button._background then
                if selected then
                    button._background:SetColorTexture(1, 1, 1, 0.2)
                else
                    button._background:SetColorTexture(1, 1, 1, 0.08)
                end
            end
            if button._label then
                button._label:SetAlpha(selected and 1 or 0.78)
            end
        end
    end

    if tabKey == "frames" then
        self:RefreshFramesPage(true)
    end

    self.currentTab = tabKey
end

-- Create scrollable tab page.
function Configuration:CreateScrollableTabPage(parent)
    -- Create frame for page.
    local page = CreateFrame("Frame", nil, parent)
    page:SetClipsChildren(true)

    -- Create eventframe for scroll bar.
    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -2, 4)
    scrollBar:SetWidth(CONFIG_SCROLLBAR_WIDTH)
    styleMinimalScrollBar(scrollBar)

    -- Create scrollframe for scroll frame.
    local scrollFrame = CreateFrame("ScrollFrame", nil, page)
    scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -CONFIG_SCROLLBAR_GUTTER, 2)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetHorizontalScroll(0)

    -- Create frame for content.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", CONFIG_PAGE_LEFT_INSET, 0)
    content:SetWidth(1)
    content:SetHeight(CONFIG_PAGE_CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(content)

    -- Keep the page content width aligned with the scroll frame viewport.
    local function updateContentWidth(selfFrame, width)
        local resolvedWidth = width or selfFrame:GetWidth() or 1
        local contentWidth = math.max(1, resolvedWidth - CONFIG_PAGE_LEFT_INSET - CONFIG_PAGE_RIGHT_INSET)
        content:SetWidth(contentWidth)
    end
    updateContentWidth(scrollFrame, scrollFrame:GetWidth())

    -- Return the current vertical scroll range clamped to zero or above.
    local function getScrollRange(selfFrame)
        local maxRange = selfFrame:GetVerticalScrollRange() or 0
        if maxRange < 0 then
            maxRange = 0
        end
        return maxRange
    end

    local baseSetScrollPercentage = type(scrollBar.SetScrollPercentage) == "function" and scrollBar.SetScrollPercentage or nil
    -- Normalize percentage-based scroll requests onto the scroll frame.
    function scrollBar:SetScrollPercentage(scrollPercentage, fromMouseWheel)
        local clamped = Util:Clamp(tonumber(scrollPercentage) or 0, 0, 1)
        local invokedNative = false

        if not self._mummuDisableNativeSetScrollPercentage then
            if baseSetScrollPercentage then
                local ok = pcall(baseSetScrollPercentage, self, clamped, fromMouseWheel)
                invokedNative = ok
                if not ok then
                    self._mummuDisableNativeSetScrollPercentage = true
                end
            elseif ScrollControllerMixin and type(ScrollControllerMixin.SetScrollPercentage) == "function" then
                local ok = pcall(ScrollControllerMixin.SetScrollPercentage, self, clamped)
                invokedNative = ok
                if not ok then
                    self._mummuDisableNativeSetScrollPercentage = true
                end
            end
        end

        if invokedNative and type(self.Update) == "function" then
            pcall(self.Update, self)
        end

        if fromMouseWheel then
            return
        end

        local maxRange = getScrollRange(scrollFrame)
        local offset = maxRange * clamped
        scrollFrame:SetVerticalScroll(offset)
        scrollFrame:SetHorizontalScroll(0)
    end

    -- Mirror the scroll frame's current position back onto the custom scrollbar.
    local function syncScrollBarValue(selfFrame, fromMouseWheel)
        local maxRange = getScrollRange(selfFrame)
        local current = selfFrame:GetVerticalScroll() or 0
        if current > maxRange then
            current = maxRange
            selfFrame:SetVerticalScroll(current)
        end

        local frameHeight = math.max(1, selfFrame:GetHeight() or 1)
        local contentHeight = math.max(frameHeight, content:GetHeight() or frameHeight)
        local visibleRatio = Util:Clamp(frameHeight / contentHeight, 0, 1)
        if type(scrollBar.SetVisibleExtentPercentage) == "function" then
            pcall(scrollBar.SetVisibleExtentPercentage, scrollBar, visibleRatio)
        end

        if maxRange <= 0 then
            scrollBar:Hide()
        else
            scrollBar:Show()
        end

        local percentage = (maxRange > 0) and (current / maxRange) or 0
        if type(scrollBar.SetScrollPercentage) == "function" then
            scrollBar:SetScrollPercentage(percentage, fromMouseWheel and true or false)
        end
    end

    -- Handle OnMouseWheel script callback.
    scrollFrame:SetScript("OnMouseWheel", function(selfFrame, delta)
        local step = 52
        local current = selfFrame:GetVerticalScroll() or 0
        local target = current - (delta * step)
        local maxRange = getScrollRange(selfFrame)
        if target < 0 then
            target = 0
        elseif target > maxRange then
            target = maxRange
        end
        selfFrame:SetVerticalScroll(target)
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)
    -- Handle OnSizeChanged script callback.
    scrollFrame:SetScript("OnSizeChanged", function(selfFrame, width)
        updateContentWidth(selfFrame, width)
        syncScrollBarValue(selfFrame, true)
    end)
    -- Handle OnVerticalScroll script callback.
    scrollFrame:SetScript("OnVerticalScroll", function(selfFrame, offset)
        local target = offset or 0
        local maxRange = getScrollRange(selfFrame)
        if target < 0 then
            target = 0
        elseif target > maxRange then
            target = maxRange
        end
        if target ~= (selfFrame:GetVerticalScroll() or 0) then
            selfFrame:SetVerticalScroll(target)
        end
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)
    -- Handle OnScrollRangeChanged script callback.
    scrollFrame:SetScript("OnScrollRangeChanged", function(selfFrame)
        selfFrame:SetHorizontalScroll(0)
        syncScrollBarValue(selfFrame, true)
    end)

    syncScrollBarValue(scrollFrame, true)

    page.ScrollFrame = scrollFrame
    page.ScrollBar = scrollBar
    page.Content = content
    return page, content
end

-- ============================================================================
-- CONFIGURATION REFRESH & STATE MANAGEMENT
-- ============================================================================
-- Methods for updating UI widget states based on current configuration,
-- refreshing profile lists, and notifying other modules of setting changes.

-- Refresh config widgets.
function Configuration:RefreshConfigWidgets()
    if not self.panel then
        return
    end

    local profile = self:GetProfile()
    if not profile then
        return
    end

    if profile then
        profile.style = profile.style or {}
    end
    local globalWidgets = self.widgets.global
    if globalWidgets and globalWidgets.registry then
        self:SyncWidgetRegistry(globalWidgets.registry, profile)
    end
    if self.minimapButton and self.minimapButton.icon then
        self.minimapButton.icon:SetTexture(MINIMAP_ICON_TEXTURE)
    end

    local profilesWidgets = self.widgets.profiles
    if profilesWidgets then
        local dataHandle = self:GetDataHandle()
        if dataHandle then
            local selectedProfileName = self:GetSelectedProfileName()
            local activeProfileName = dataHandle:GetActiveProfileName()
            if profilesWidgets.dropdown then
                self:RefreshSelectControlText(profilesWidgets.dropdown, true)
            end
            if profilesWidgets.renameInput and not profilesWidgets.renameInput:HasFocus() then
                profilesWidgets.renameInput:SetText(selectedProfileName or "")
            end
            if profilesWidgets.importNameInput and not profilesWidgets.importNameInput:HasFocus() then
                if profilesWidgets.importNameInput:GetText() == "" then
                    local suffix = L.CONFIG_PROFILES_IMPORT_SUFFIX or "_import"
                    profilesWidgets.importNameInput:SetText((selectedProfileName or "Imported") .. suffix)
                end
            end
            if profilesWidgets.deleteButton then
                local deletable = selectedProfileName and selectedProfileName ~= "Default" and selectedProfileName ~= activeProfileName
                self:SetButtonEnabled(profilesWidgets.deleteButton, deletable == true)
            end
            if profilesWidgets.activateButton then
                local canActivate = selectedProfileName and selectedProfileName ~= activeProfileName
                self:SetButtonEnabled(profilesWidgets.activateButton, canActivate == true)
            end
        end
    end

    local aurasWidgets = self.widgets.auras
    if aurasWidgets then
        local config = self:GetTrackedAurasConfig()
        if aurasWidgets.registry then
            self:SyncWidgetRegistry(aurasWidgets.registry, config)
        end
        if type(aurasWidgets.refreshList) == "function" then
            aurasWidgets.refreshList()
        end
    end

    if self.widgets.frames then
        self:RefreshFramesPage(true)
    end
end

-- Build configuration tab buttons.
function Configuration:BuildTabs(subtitle)
    local panel = self.panel
    local tabWidth = 122
    local tabHeight = 22
    local tabSpacingX = 6
    local tabSpacingY = 6
    local tabsPerRow = 4

    local firstButton = nil
    local previousButton = nil
    local rowStartButton = nil
    local lastRowStartButton = nil

    for i = 1, #TOP_LEVEL_TABS do
        local tab = TOP_LEVEL_TABS[i]
        -- Create button for button.
        local button = CreateFrame("Button", "mummuFramesConfigTab" .. tab.key, panel)
        button:SetSize(tabWidth, tabHeight)

        -- Create texture for background. Bug parade continues.
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(1, 1, 1, 0.08)
        button._background = background

        -- Create font string for label.
        local label = button:CreateFontString(nil, "ARTWORK")
        label:SetPoint("CENTER", 0, 0)
        setFontStringTextSafe(label, tab.label, 11)
        button._label = label

        local indexInRow = (i - 1) % tabsPerRow
        if not firstButton then
            button:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
            firstButton = button
            rowStartButton = button
            lastRowStartButton = button
        elseif indexInRow == 0 then
            button:SetPoint("TOPLEFT", rowStartButton, "BOTTOMLEFT", 0, -tabSpacingY)
            rowStartButton = button
            lastRowStartButton = button
            previousButton = button
        else
            button:SetPoint("LEFT", previousButton, "RIGHT", tabSpacingX, 0)
        end

        -- Handle OnClick script callback.
        button:SetScript("OnClick", function()
            self:SelectTab(tab.key)
        end)
        -- Handle OnEnter script callback.
        button:SetScript("OnEnter", function()
            if self.currentTab ~= tab.key and button._background then
                button._background:SetColorTexture(1, 1, 1, 0.14)
            end
        end)
        -- Handle OnLeave script callback.
        button:SetScript("OnLeave", function()
            if self.currentTab ~= tab.key and button._background then
                button._background:SetColorTexture(1, 1, 1, 0.08)
            end
        end)

        self.widgets.tabs[tab.key] = button
        previousButton = button

        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", firstButton, "BOTTOMLEFT", 0, -14)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        page:Hide()
        self.tabPages[tab.key] = page
    end

    local pagesTopAnchor = lastRowStartButton or firstButton
    for _, page in pairs(self.tabPages) do
        if page then
            page:ClearAllPoints()
            page:SetPoint("TOPLEFT", pagesTopAnchor, "BOTTOMLEFT", 0, -14)
            page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        end
    end

    self:SelectTab("frames")
end

-- Build settings panel.
function Configuration:BuildSettingsPanel()
    if self.panel._built then
        return
    end

    local panel = self.panel
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)

    panel.Background = Style:CreateBackground(panel, 0.05, 0.05, 0.06, 0.95)

    -- Create texture for header fill.
    local headerFill = panel:CreateTexture(nil, "ARTWORK")
    headerFill:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    headerFill:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    headerFill:SetHeight(34)
    headerFill:SetColorTexture(1, 1, 1, 0.04)
    panel.HeaderFill = headerFill

    -- Create texture for header line.
    local headerLine = panel:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT", headerFill, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerFill, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(1, 1, 1, 0.08)
    panel.HeaderLine = headerLine

    -- Create frame for drag handle.
    local dragHandle = CreateFrame("Frame", nil, panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -6)
    dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -42, -6)
    dragHandle:SetHeight(24)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    -- Handle OnDragStart script callback.
    dragHandle:SetScript("OnDragStart", function()
        panel:StartMoving()
    end)
    -- Handle OnDragStop script callback.
    dragHandle:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    panel.DragHandle = dragHandle

    -- Create button for close button.
    local closeButton = CreateFrame("Button", nil, panel)
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)

    -- Create texture for close normal.
    local closeNormal = closeButton:CreateTexture(nil, "BACKGROUND")
    closeNormal:SetAllPoints()
    closeNormal:SetColorTexture(1, 1, 1, 0.06)
    closeButton.Normal = closeNormal

    -- Create texture for close hover.
    local closeHover = closeButton:CreateTexture(nil, "ARTWORK")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(1, 1, 1, 0.14)
    closeHover:Hide()
    closeButton.Hover = closeHover

    -- Create font string for close label.
    local closeLabel = closeButton:CreateFontString(nil, "OVERLAY")
    closeLabel:SetPoint("CENTER", 0, 0)
    setFontStringTextSafe(closeLabel, "x", 12, "OUTLINE")
    closeButton.Label = closeLabel

    -- Handle OnEnter script callback.
    closeButton:SetScript("OnEnter", function()
        closeHover:Show()
    end)
    -- Handle OnLeave script callback.
    closeButton:SetScript("OnLeave", function()
        closeHover:Hide()
    end)
    -- Handle OnClick script callback.
    closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)
    panel.CloseButton = closeButton

    -- Create font string for title.
    local title = panel:CreateFontString(nil, "ARTWORK")
    title:SetPoint("TOPLEFT", 16, -10)
    setFontStringTextSafe(title, L.CONFIG_TITLE, 24, nil, GameFontHighlightLarge)

    -- Create font string for subtitle.
    local subtitle = panel:CreateFontString(nil, "ARTWORK")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    setFontStringTextSafe(subtitle, L.CONFIG_SUBTITLE, 12, nil, GameFontHighlightSmall)
    subtitle:SetTextColor(0.86, 0.86, 0.86, 1)

    self:BuildTabs(subtitle)

    panel._built = true
end

-- Register settings category. Nothing exploded yet.
function Configuration:RegisterSettingsCategory()
    if self.panel then
        return
    end

    -- Create frame widget.
    self.panel = CreateFrame("Frame", "mummuFramesConfigWindow", UIParent)
    self.panel:SetSize(CONFIG_WINDOW_WIDTH, CONFIG_WINDOW_HEIGHT)
    self.panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.panel:SetFrameStrata("DIALOG")
    self.panel:SetFrameLevel(50)
    self.panel:Hide()
    if type(UISpecialFrames) == "table" then
        local frameName = self.panel:GetName()
        local known = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == frameName then
                known = true
                break
            end
        end
        if not known then
            table.insert(UISpecialFrames, frameName)
        end
    end

    self:BuildSettingsPanel()
    -- Handle OnShow script callback.
    self.panel:SetScript("OnShow", function()
        self:RefreshConfigWidgets()
    end)
    -- Close select popup when panel hides.
    self.panel:HookScript("OnHide", function()
        self:CloseSelectPopup()
    end)
end

-- Open addon settings panel.
function Configuration:OpenConfig()
    if not self.panel then
        self:RegisterSettingsCategory()
    end

    if self.panel then
        self.panel:Show()
        self.panel:Raise()
        self:RefreshConfigWidgets()
    end
end

-- Close addon settings panel.
function Configuration:CloseConfig()
    if self.panel and self.panel:IsShown() then
        self.panel:Hide()
    end
end

-- Toggle addon settings panel visibility.
function Configuration:ToggleConfig()
    if self.panel and self.panel:IsShown() then
        self:CloseConfig()
        return
    end
    self:OpenConfig()
end

-- Update minimap button position.
function Configuration:UpdateMinimapButtonPosition()
    if not self.minimapButton then
        return
    end

    local profile = self:GetProfile()
    if not profile then
        return
    end

    if profile.minimap and profile.minimap.hide then
        self.minimapButton:Hide()
        return
    end

    self.minimapButton:Show()

    local angle = tonumber(profile.minimap.angle) or 220
    local radius = (Minimap:GetWidth() * 0.5) + 6
    local radians = math.rad(angle)
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius

    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Create minimap launcher.
function Configuration:CreateMinimapLauncher()
    if self.minimapButton then
        self:UpdateMinimapButtonPosition()
        return
    end

    local button = CreateFrame("Button", "mummuFramesMinimapLauncher", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(MINIMAP_HIGHLIGHT_TEXTURE, "ADD")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexture(MINIMAP_ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    if type(icon.AddMaskTexture) == "function" then
        local mask = button:CreateMaskTexture()
        mask:SetSize(20, 20)
        mask:SetPoint("CENTER", button, "CENTER", 0, 1)
        mask:SetTexture(MINIMAP_ICON_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        button.iconMask = mask
    end

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER", button, "CENTER", 0, 1)
    background:SetTexture(MINIMAP_BACKGROUND_TEXTURE)
    background:SetVertexColor(0.18, 0.18, 0.18, 0.85)
    button.background = background

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture(MINIMAP_BORDER_TEXTURE)
    button.border = border

    -- Handle OnClick script callback.
    button:SetScript("OnClick", function()
        if InCombatLockdown() then
            return
        end
        self:ToggleConfig()
    end)

    -- Handle OnEnter script callback.
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:SetText(L.MINIMAP_TOOLTIP_TITLE, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LINE, 0.85, 0.85, 0.85)
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)

    -- Handle OnLeave script callback.
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Handle OnDragStart script callback.
    button:SetScript("OnDragStart", function(selfButton)
        if not IsShiftKeyDown() then
            return
        end

        -- Handle OnUpdate script callback.
        selfButton:SetScript("OnUpdate", function()
            local profile = self:GetProfile()
            if not profile then
                return
            end

            local scale = Minimap:GetEffectiveScale()
            local centerX, centerY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            cursorX = cursorX / scale
            cursorY = cursorY / scale

            local deltaX = cursorX - centerX
            local deltaY = cursorY - centerY

            local angle = math.deg(math.atan2(deltaY, deltaX))
            if angle < 0 then
                angle = angle + 360
            end

            profile.minimap.angle = angle
            self:UpdateMinimapButtonPosition()
        end)
    end)

    -- Handle OnDragStop script callback.
    button:SetScript("OnDragStop", function(selfButton)
        selfButton:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

addon:RegisterModule("configuration", Configuration:New())
