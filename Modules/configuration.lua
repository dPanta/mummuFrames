-- ============================================================================
-- MUMMUFRAMES CONFIGURATION MODULE
-- ============================================================================
-- Manages settings UI with panels for profile management, aura tracking,
-- frame positioning/styling, and per-unit configuration.
--
-- FEATURES:
--   - Profile system: save/load/import/export player-specific settings
--   - Dropdown controls for fonts, textures, positions, sources, and roles
--   - Numeric sliders and input fields for dimensions and offsets
--   - Checkbox toggles for features and display modes
--   - Color picker integration for bar colors and overlays
--   - Per-unit configuration pages (party, raid, player, target, etc.)
--   - Spell tracking control for healer aura display
--
-- PAGE STRUCTURE:
--   1. Profiles: manage named profile sets with import/export
--   2. Global: addon-wide settings (enabled, fonts, textures, test mode)
--   3. Auras: spell whitelist for healer buff tracking
--   4. Unit: per-unit configuration (width, height, spacing, colors, auras)
--
-- EVENTS:
--   Configuration changes trigger:
--   - RequestUnitFrameRefresh() to update live frames (debounced)
--   - Profile switching updates all unit configurations
-- ============================================================================

local _, ns = ...

local addon = _G.mummuFrames
local L = ns.L
local Style = ns.Style
local Util = ns.Util

-- Create class holding configuration behavior.
local Configuration = ns.Object:Extend()

-- ============================================================================
-- CONFIGURATION CONSTANTS
-- ============================================================================

-- Unit tab order and labels for configurable frames.
-- Create table holding unit tab order.
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

-- Create table holding unit tab labels.
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
-- Create table holding buff position presets.
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
-- Create table holding buff source options.
local BUFF_SOURCE_OPTIONS = {
    { key = "important", label = L.CONFIG_UNIT_BUFFS_SOURCE_IMPORTANT or "Important (HoTs/defensives)" },
    { key = "all", label = L.CONFIG_UNIT_BUFFS_SOURCE_ALL or "All" },
    { key = "self", label = L.CONFIG_UNIT_BUFFS_SOURCE_SELF or "Self only" },
}
local PARTY_HEALER_GROUP_DEFAULTS = {
    hots = { style = "icon", size = 14, color = { r = 0.22, g = 0.87, b = 0.42, a = 0.85 } },
    absorbs = { style = "icon", size = 14, color = { r = 0.32, g = 0.68, b = 1.00, a = 0.85 } },
    externals = { style = "icon", size = 14, color = { r = 1.00, g = 0.76, b = 0.30, a = 0.85 } },
}
local PARTY_HEALER_GROUP_OPTIONS = {
    { key = "hots", label = L.CONFIG_PARTY_HEALER_GROUP_HOTS or "HoTs / periodic heals" },
    { key = "absorbs", label = L.CONFIG_PARTY_HEALER_GROUP_ABSORBS or "Absorbs" },
    { key = "externals", label = L.CONFIG_PARTY_HEALER_GROUP_EXTERNALS or "Player externals" },
}
local PARTY_HEALER_ANCHOR_OPTIONS = {
    { key = "TOPLEFT", label = L.CONFIG_PARTY_HEALER_ANCHOR_TOPLEFT or "Top left" },
    { key = "TOP", label = L.CONFIG_PARTY_HEALER_ANCHOR_TOP or "Top" },
    { key = "TOPRIGHT", label = L.CONFIG_PARTY_HEALER_ANCHOR_TOPRIGHT or "Top right" },
    { key = "LEFT", label = L.CONFIG_PARTY_HEALER_ANCHOR_LEFT or "Left" },
    { key = "CENTER", label = L.CONFIG_PARTY_HEALER_ANCHOR_CENTER or "Center" },
    { key = "RIGHT", label = L.CONFIG_PARTY_HEALER_ANCHOR_RIGHT or "Right" },
    { key = "BOTTOMLEFT", label = L.CONFIG_PARTY_HEALER_ANCHOR_BOTTOMLEFT or "Bottom left" },
    { key = "BOTTOM", label = L.CONFIG_PARTY_HEALER_ANCHOR_BOTTOM or "Bottom" },
    { key = "BOTTOMRIGHT", label = L.CONFIG_PARTY_HEALER_ANCHOR_BOTTOMRIGHT or "Bottom right" },
}
local PARTY_HEALER_GROUP_STYLE_OPTIONS = {
    { key = "icon", label = L.CONFIG_PARTY_HEALER_STYLE_ICON or "Icon" },
    { key = "rectangle", label = L.CONFIG_PARTY_HEALER_STYLE_RECTANGLE or "Colored rectangle" },
}
local PARTY_HEALER_SPELL_STYLE_OPTIONS = {
    { key = "group", label = L.CONFIG_PARTY_HEALER_STYLE_GROUP or "Use group style" },
    { key = "icon", label = L.CONFIG_PARTY_HEALER_STYLE_ICON or "Icon" },
    { key = "rectangle", label = L.CONFIG_PARTY_HEALER_STYLE_RECTANGLE or "Colored rectangle" },
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
local CONFIG_WINDOW_WIDTH = 860
local CONFIG_WINDOW_HEIGHT = 700
local CONFIG_PAGE_CONTENT_HEIGHT = 1500
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
-- Create table holding font dropdown object by path.
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

-- Return party healer group label.
local function getPartyHealerGroupLabel(groupKey)
    for i = 1, #PARTY_HEALER_GROUP_OPTIONS do
        local option = PARTY_HEALER_GROUP_OPTIONS[i]
        if option.key == groupKey then
            return option.label
        end
    end
    return PARTY_HEALER_GROUP_OPTIONS[1].label
end

-- Return party healer anchor label.
local function getPartyHealerAnchorLabel(anchorKey)
    for i = 1, #PARTY_HEALER_ANCHOR_OPTIONS do
        local option = PARTY_HEALER_ANCHOR_OPTIONS[i]
        if option.key == anchorKey then
            return option.label
        end
    end
    return PARTY_HEALER_ANCHOR_OPTIONS[5].label
end

-- Return party healer style label.
local function getPartyHealerStyleLabel(styleKey, includeGroupOption)
    local options = includeGroupOption and PARTY_HEALER_SPELL_STYLE_OPTIONS or PARTY_HEALER_GROUP_STYLE_OPTIONS
    for i = 1, #options do
        local option = options[i]
        if option.key == styleKey then
            return option.label
        end
    end
    return options[1].label
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

-- Return clamped color component.
local function clampColorComponent(value, fallback)
    return Util:Clamp(tonumber(value) or fallback or 1, 0, 1)
end

-- Open built-in color picker.
local function openColorPicker(initialColor, onColorChanged)
    if type(onColorChanged) ~= "function" or not ColorPickerFrame then
        return
    end

    local r = clampColorComponent(initialColor and initialColor.r, 1)
    local g = clampColorComponent(initialColor and initialColor.g, 1)
    local b = clampColorComponent(initialColor and initialColor.b, 1)
    local a = clampColorComponent(initialColor and initialColor.a, 1)

    local function applyFromPicker()
        local red, green, blue = ColorPickerFrame:GetColorRGB()
        local alpha = 1
        local opacitySlider = _G["OpacitySliderFrame"]
        if opacitySlider and type(opacitySlider.GetValue) == "function" then
            alpha = 1 - (tonumber(opacitySlider:GetValue()) or 0)
        elseif type(ColorPickerFrame.GetColorAlpha) == "function" then
            alpha = tonumber(ColorPickerFrame:GetColorAlpha()) or 1
        end
        onColorChanged(
            clampColorComponent(red, r),
            clampColorComponent(green, g),
            clampColorComponent(blue, b),
            clampColorComponent(alpha, a)
        )
    end

    if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            opacity = 1 - a,
            hasOpacity = true,
            swatchFunc = applyFromPicker,
            opacityFunc = applyFromPicker,
            cancelFunc = function(previousValues)
                if type(previousValues) == "table" then
                    local cancelR = clampColorComponent(previousValues.r, r)
                    local cancelG = clampColorComponent(previousValues.g, g)
                    local cancelB = clampColorComponent(previousValues.b, b)
                    local cancelA = clampColorComponent(1 - (tonumber(previousValues.opacity) or (1 - a)), a)
                    onColorChanged(cancelR, cancelG, cancelB, cancelA)
                    return
                end
                onColorChanged(r, g, b, a)
            end,
        })
        return
    end

    -- Legacy fallback.
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = 1 - a
    ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = 1 - a }
    ColorPickerFrame.func = applyFromPicker
    ColorPickerFrame.opacityFunc = applyFromPicker
    ColorPickerFrame.cancelFunc = function(previousValues)
        if type(previousValues) == "table" then
            local cancelR = clampColorComponent(previousValues.r, r)
            local cancelG = clampColorComponent(previousValues.g, g)
            local cancelB = clampColorComponent(previousValues.b, b)
            local cancelA = clampColorComponent(1 - (tonumber(previousValues.opacity) or (1 - a)), a)
            onColorChanged(cancelR, cancelG, cancelB, cancelA)
            return
        end
        onColorChanged(r, g, b, a)
    end
    if type(ColorPickerFrame.SetColorRGB) == "function" then
        ColorPickerFrame:SetColorRGB(r, g, b)
    end
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
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

-- Create color swatch control.
local function createColorControl(parent, labelText, anchor)
    -- Create font string for label.
    local label = parent:CreateFontString(nil, "ARTWORK")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    setFontStringTextSafe(label, labelText, 12)

    -- Create button for color picker.
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    button:SetSize(130, 22)
    if type(button.SetText) == "function" then
        button:SetText(L.CONFIG_PARTY_HEALER_PICK_COLOR or "Pick color")
    end

    -- Create texture for swatch.
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("LEFT", button, "RIGHT", 8, 0)
    swatch:SetSize(22, 22)
    swatch:SetColorTexture(1, 1, 1, 1)

    -- Create texture for swatch border.
    local borderTop = button:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", swatch, "TOPLEFT", -1, 1)
    borderTop:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 1, 1)
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1, 1, 1, 0.4)

    local borderBottom = button:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", -1, -1)
    borderBottom:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 1, -1)
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1, 1, 1, 0.4)

    local borderLeft = button:CreateTexture(nil, "BORDER")
    borderLeft:SetPoint("TOPLEFT", swatch, "TOPLEFT", -1, 1)
    borderLeft:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", -1, -1)
    borderLeft:SetWidth(1)
    borderLeft:SetColorTexture(1, 1, 1, 0.4)

    local borderRight = button:CreateTexture(nil, "BORDER")
    borderRight:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 1, 1)
    borderRight:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 1, -1)
    borderRight:SetWidth(1)
    borderRight:SetColorTexture(1, 1, 1, 0.4)

    return {
        label = label,
        button = button,
        swatch = swatch,
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
    -- Create table holding widgets.
    self.widgets = {
        unitPages = {},
        tabs = {},
        partyHealer = nil,
        raidHealer = nil,
        profiles = nil,
    }
    -- Create table holding tab pages.
    self.tabPages = {}
    self.currentTab = nil
    self.minimapButton = nil
    self._refreshScheduled = false
    self._partyHealerSelectedSpellID = nil
    self._partyHealerSelectedGroup = "hots"
    self._raidHealerSelectedSpellID = nil
    self._raidHealerSelectedGroup = "hots"
    self._profilesSelectedName = nil
end

-- Initialize module. Coffee remains optional.
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
function Configuration:GetPartyHealerConfig()
    local partyFrames = self.addon:GetModule("partyFrames")
    if partyFrames and type(partyFrames.GetPartyHealerConfig) == "function" then
        local sharedConfig = partyFrames:GetPartyHealerConfig()
        if sharedConfig then
            return sharedConfig
        end
    end

    local profile = self:GetProfile()
    if not profile then
        return nil
    end

    if type(profile.auras) ~= "table" then
        profile.auras = {}
    end
    local config = profile.auras
    if config.enabled == nil then
        config.enabled = true
    end
    config.groups = config.groups or {}
    config.spells = config.spells or {}
    config.customSpells = config.customSpells or {}

    for groupKey, defaults in pairs(PARTY_HEALER_GROUP_DEFAULTS) do
        config.groups[groupKey] = config.groups[groupKey] or {}
        local groupConfig = config.groups[groupKey]
        if type(groupConfig.style) ~= "string" or groupConfig.style == "" then
            groupConfig.style = defaults.style
        end
        groupConfig.size = Util:Clamp(tonumber(groupConfig.size) or defaults.size, 6, 48)
        groupConfig.color = groupConfig.color or {}
        groupConfig.color.r = clampColorComponent(groupConfig.color.r, defaults.color.r)
        groupConfig.color.g = clampColorComponent(groupConfig.color.g, defaults.color.g)
        groupConfig.color.b = clampColorComponent(groupConfig.color.b, defaults.color.b)
        groupConfig.color.a = clampColorComponent(groupConfig.color.a, defaults.color.a)
    end

    return config
end

-- Return available party healer spells for current talents/spec.
function Configuration:GetPartyHealerAvailableSpells()
    local partyFrames = self.addon:GetModule("partyFrames")
    if partyFrames and type(partyFrames.GetAvailableHealerSpells) == "function" then
        local spells = partyFrames:GetAvailableHealerSpells()
        if type(spells) == "table" then
            return spells
        end
    end
    return {}
end

-- Return selected spell entry for party healer page.
function Configuration:GetSelectedPartyHealerSpellEntry()
    local spells = self:GetPartyHealerAvailableSpells()
    if #spells == 0 then
        self._partyHealerSelectedSpellID = nil
        return nil
    end

    local selectedSpellID = tonumber(self._partyHealerSelectedSpellID)
    for i = 1, #spells do
        if spells[i].spellID == selectedSpellID then
            return spells[i]
        end
    end

    self._partyHealerSelectedSpellID = spells[1].spellID
    return spells[1]
end

-- Return selected spell config table.
function Configuration:GetSelectedPartyHealerSpellConfig()
    local config = self:GetPartyHealerConfig()
    local spellEntry = self:GetSelectedPartyHealerSpellEntry()
    if not config or not spellEntry then
        return nil
    end

    local key = tostring(spellEntry.spellID)
    config.spells[key] = config.spells[key] or {}
    return config.spells[key], spellEntry
end

-- Return selected group key and config table.
function Configuration:GetSelectedPartyHealerGroupConfig()
    local config = self:GetPartyHealerConfig()
    if not config then
        return nil, nil
    end

    local selectedGroup = self._partyHealerSelectedGroup
    if selectedGroup ~= "hots" and selectedGroup ~= "absorbs" and selectedGroup ~= "externals" then
        selectedGroup = "hots"
    end
    self._partyHealerSelectedGroup = selectedGroup

    config.groups[selectedGroup] = config.groups[selectedGroup] or {}
    local groupConfig = config.groups[selectedGroup]
    local defaults = PARTY_HEALER_GROUP_DEFAULTS[selectedGroup] or PARTY_HEALER_GROUP_DEFAULTS.hots

    if type(groupConfig.style) ~= "string" or groupConfig.style == "" then
        groupConfig.style = defaults.style
    end
    groupConfig.size = Util:Clamp(tonumber(groupConfig.size) or defaults.size, 6, 48)
    groupConfig.color = groupConfig.color or {}
    groupConfig.color.r = clampColorComponent(groupConfig.color.r, defaults.color.r)
    groupConfig.color.g = clampColorComponent(groupConfig.color.g, defaults.color.g)
    groupConfig.color.b = clampColorComponent(groupConfig.color.b, defaults.color.b)
    groupConfig.color.a = clampColorComponent(groupConfig.color.a, defaults.color.a)
    return selectedGroup, groupConfig
end

-- Return raid healer config.
function Configuration:GetRaidHealerConfig()
    return self:GetPartyHealerConfig()
end

-- Return available raid healer spells for current talents/spec.
-- Delegates to partyFrames (raid module removed).
function Configuration:GetRaidHealerAvailableSpells()
    local partyFrames = self.addon:GetModule("partyFrames")
    if partyFrames and type(partyFrames.GetAvailableHealerSpells) == "function" then
        local spells = partyFrames:GetAvailableHealerSpells()
        if type(spells) == "table" then
            return spells
        end
    end
    return {}
end

-- Return selected spell entry for raid healer page.
function Configuration:GetSelectedRaidHealerSpellEntry()
    local spells = self:GetRaidHealerAvailableSpells()
    if #spells == 0 then
        self._raidHealerSelectedSpellID = nil
        return nil
    end

    local selectedSpellID = tonumber(self._raidHealerSelectedSpellID)
    for i = 1, #spells do
        if spells[i].spellID == selectedSpellID then
            return spells[i]
        end
    end

    self._raidHealerSelectedSpellID = spells[1].spellID
    return spells[1]
end

-- Return selected spell config table for raid healer.
function Configuration:GetSelectedRaidHealerSpellConfig()
    local config = self:GetRaidHealerConfig()
    local spellEntry = self:GetSelectedRaidHealerSpellEntry()
    if not config or not spellEntry then
        return nil
    end

    local key = tostring(spellEntry.spellID)
    config.spells[key] = config.spells[key] or {}
    return config.spells[key], spellEntry
end

-- Return selected group key and config table for raid healer.
function Configuration:GetSelectedRaidHealerGroupConfig()
    local config = self:GetRaidHealerConfig()
    if not config then
        return nil, nil
    end

    local selectedGroup = self._raidHealerSelectedGroup
    if selectedGroup ~= "hots" and selectedGroup ~= "absorbs" and selectedGroup ~= "externals" then
        selectedGroup = "hots"
    end
    self._raidHealerSelectedGroup = selectedGroup

    config.groups[selectedGroup] = config.groups[selectedGroup] or {}
    local groupConfig = config.groups[selectedGroup]
    local defaults = PARTY_HEALER_GROUP_DEFAULTS[selectedGroup] or PARTY_HEALER_GROUP_DEFAULTS.hots

    if type(groupConfig.style) ~= "string" or groupConfig.style == "" then
        groupConfig.style = defaults.style
    end
    groupConfig.size = Util:Clamp(tonumber(groupConfig.size) or defaults.size, 6, 48)
    groupConfig.color = groupConfig.color or {}
    groupConfig.color.r = clampColorComponent(groupConfig.color.r, defaults.color.r)
    groupConfig.color.g = clampColorComponent(groupConfig.color.g, defaults.color.g)
    groupConfig.color.b = clampColorComponent(groupConfig.color.b, defaults.color.b)
    groupConfig.color.a = clampColorComponent(groupConfig.color.a, defaults.color.a)
    return selectedGroup, groupConfig
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
    -- Create table holding entries.
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
            -- Create table holding entries.
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
        -- Return computed value.
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
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        L.CONFIG_NO_FONTS or "No loadable fonts found",
        -- Resolve value label.
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
            -- Create table holding entries. Nothing exploded yet.
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
        -- Return computed value.
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
            if self.minimapButton and self.minimapButton.icon then
                self.minimapButton.icon:SetTexture(option.value)
            end
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_TEXTURE_WIDTH,
        L.CONFIG_NO_TEXTURES or "No status bar textures found",
        -- Resolve value label.
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
                string.format(L.CONFIG_PROFILES_SELECTED or "Selected profile: %s", option.value),
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
        -- Return computed value.
        function()
            -- Create table holding entries.
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
        -- Return computed value.
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
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        -- Return computed value.
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
        -- Return computed value.
        function()
            -- Create table holding entries.
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
        -- Return computed value.
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
            self:RequestUnitFrameRefresh()
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
            self:RequestUnitFrameRefresh()
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
            self:RequestUnitFrameRefresh()
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
            self:RequestUnitFrameRefresh()
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
            self:RequestUnitFrameRefresh()
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

-- Initialize party healer spell dropdown (legacy healer editor controls).
-- This editor block is kept for compatibility with shared aura config data, but
-- current tabs expose the simplified Auras page instead of this full healer UI.
function Configuration:InitializePartyHealerSpellDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        -- Build current spell list from player class/spec/talents.
        function()
            local entries = {}
            local spells = self:GetPartyHealerAvailableSpells()
            for i = 1, #spells do
                local spell = spells[i]
                local customSuffix = spell.isCustom and (" - " .. (L.CONFIG_PARTY_HEALER_CUSTOM_TAG or "Custom")) or ""
                entries[#entries + 1] = {
                    value = spell.spellID,
                    label = string.format(
                        "%s (%s)%s",
                        spell.name or tostring(spell.spellID),
                        getPartyHealerGroupLabel(spell.group),
                        customSuffix
                    ),
                    icon = spell.icon,
                    spellID = spell.spellID,
                    group = spell.group,
                }
            end
            return entries
        end,
        -- Return selected spell id.
        function()
            local spellEntry = self:GetSelectedPartyHealerSpellEntry()
            return spellEntry and spellEntry.spellID or nil
        end,
        -- Apply selected spell.
        function(option)
            self._partyHealerSelectedSpellID = tonumber(option.value)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RefreshConfigWidgets()
            self:RequestUnitFrameRefresh()
        end,
        420,
        L.CONFIG_PARTY_HEALER_NO_SPELLS or "No tracked spells available for current spec/talents.",
        -- Resolve value label.
        function(value)
            local spellID = tonumber(value)
            local spells = self:GetPartyHealerAvailableSpells()
            for i = 1, #spells do
                if spells[i].spellID == spellID then
                    local customSuffix = spells[i].isCustom and (" - " .. (L.CONFIG_PARTY_HEALER_CUSTOM_TAG or "Custom"))
                        or ""
                    return string.format(
                        "%s (%s)%s",
                        spells[i].name or tostring(spellID),
                        getPartyHealerGroupLabel(spells[i].group),
                        customSuffix
                    )
                end
            end
            return spellID and ("Spell " .. tostring(spellID)) or (L.CONFIG_PARTY_HEALER_NO_SPELLS or "No spells")
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Initialize party healer group dropdown.
function Configuration:InitializePartyHealerGroupDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_GROUP_OPTIONS do
                local option = PARTY_HEALER_GROUP_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local groupKey = self._partyHealerSelectedGroup
            if groupKey ~= "hots" and groupKey ~= "absorbs" and groupKey ~= "externals" then
                groupKey = "hots"
            end
            return groupKey
        end,
        function(option)
            self._partyHealerSelectedGroup = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RefreshConfigWidgets()
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerGroupLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize party healer spell anchor dropdown.
function Configuration:InitializePartyHealerAnchorDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_ANCHOR_OPTIONS do
                local option = PARTY_HEALER_ANCHOR_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local spellConfig = self:GetSelectedPartyHealerSpellConfig()
            return (spellConfig and spellConfig.anchorPoint) or "CENTER"
        end,
        function(option)
            local spellConfig = self:GetSelectedPartyHealerSpellConfig()
            if not spellConfig then
                return
            end
            spellConfig.anchorPoint = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerAnchorLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize party healer spell style dropdown.
function Configuration:InitializePartyHealerSpellStyleDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_SPELL_STYLE_OPTIONS do
                local option = PARTY_HEALER_SPELL_STYLE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local spellConfig = self:GetSelectedPartyHealerSpellConfig()
            local style = spellConfig and spellConfig.style or "group"
            if style ~= "group" and style ~= "icon" and style ~= "rectangle" then
                style = "group"
            end
            return style
        end,
        function(option)
            local spellConfig = self:GetSelectedPartyHealerSpellConfig()
            if not spellConfig then
                return
            end
            spellConfig.style = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerStyleLabel(value, true)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize party healer group style dropdown.
function Configuration:InitializePartyHealerGroupStyleDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_GROUP_STYLE_OPTIONS do
                local option = PARTY_HEALER_GROUP_STYLE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local _, groupConfig = self:GetSelectedPartyHealerGroupConfig()
            local style = groupConfig and groupConfig.style or "icon"
            if style ~= "icon" and style ~= "rectangle" then
                style = "icon"
            end
            return style
        end,
        function(option)
            local _, groupConfig = self:GetSelectedPartyHealerGroupConfig()
            if not groupConfig then
                return
            end
            groupConfig.style = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerStyleLabel(value, false)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid healer spell dropdown.
function Configuration:InitializeRaidHealerSpellDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            local spells = self:GetRaidHealerAvailableSpells()
            for i = 1, #spells do
                local spell = spells[i]
                local customSuffix = spell.isCustom and (" - " .. (L.CONFIG_PARTY_HEALER_CUSTOM_TAG or "Custom")) or ""
                entries[#entries + 1] = {
                    value = spell.spellID,
                    label = string.format(
                        "%s (%s)%s",
                        spell.name or tostring(spell.spellID),
                        getPartyHealerGroupLabel(spell.group),
                        customSuffix
                    ),
                    icon = spell.icon,
                    spellID = spell.spellID,
                    group = spell.group,
                }
            end
            return entries
        end,
        function()
            local spellEntry = self:GetSelectedRaidHealerSpellEntry()
            return spellEntry and spellEntry.spellID or nil
        end,
        function(option)
            self._raidHealerSelectedSpellID = tonumber(option.value)
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RefreshConfigWidgets()
            self:RequestUnitFrameRefresh()
        end,
        420,
        L.CONFIG_PARTY_HEALER_NO_SPELLS or "No tracked spells available for current spec/talents.",
        function(value)
            local spellID = tonumber(value)
            local spells = self:GetRaidHealerAvailableSpells()
            for i = 1, #spells do
                if spells[i].spellID == spellID then
                    local customSuffix = spells[i].isCustom and (" - " .. (L.CONFIG_PARTY_HEALER_CUSTOM_TAG or "Custom"))
                        or ""
                    return string.format(
                        "%s (%s)%s",
                        spells[i].name or tostring(spellID),
                        getPartyHealerGroupLabel(spells[i].group),
                        customSuffix
                    )
                end
            end
            return spellID and ("Spell " .. tostring(spellID)) or (L.CONFIG_PARTY_HEALER_NO_SPELLS or "No spells")
        end
    )

    self:RefreshSelectControlText(dropdown, true)
end

-- Initialize raid healer group dropdown.
function Configuration:InitializeRaidHealerGroupDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_GROUP_OPTIONS do
                local option = PARTY_HEALER_GROUP_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local groupKey = self._raidHealerSelectedGroup
            if groupKey ~= "hots" and groupKey ~= "absorbs" and groupKey ~= "externals" then
                groupKey = "hots"
            end
            return groupKey
        end,
        function(option)
            self._raidHealerSelectedGroup = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RefreshConfigWidgets()
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerGroupLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid healer spell anchor dropdown.
function Configuration:InitializeRaidHealerAnchorDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_ANCHOR_OPTIONS do
                local option = PARTY_HEALER_ANCHOR_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local spellConfig = self:GetSelectedRaidHealerSpellConfig()
            return (spellConfig and spellConfig.anchorPoint) or "CENTER"
        end,
        function(option)
            local spellConfig = self:GetSelectedRaidHealerSpellConfig()
            if not spellConfig then
                return
            end
            spellConfig.anchorPoint = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerAnchorLabel(value)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid healer spell style dropdown.
function Configuration:InitializeRaidHealerSpellStyleDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_SPELL_STYLE_OPTIONS do
                local option = PARTY_HEALER_SPELL_STYLE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local spellConfig = self:GetSelectedRaidHealerSpellConfig()
            local style = spellConfig and spellConfig.style or "group"
            if style ~= "group" and style ~= "icon" and style ~= "rectangle" then
                style = "group"
            end
            return style
        end,
        function(option)
            local spellConfig = self:GetSelectedRaidHealerSpellConfig()
            if not spellConfig then
                return
            end
            spellConfig.style = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerStyleLabel(value, true)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Initialize raid healer group style dropdown.
function Configuration:InitializeRaidHealerGroupStyleDropdown(dropdown)
    if not dropdown then
        return
    end

    self:ConfigureSelectControl(
        dropdown,
        function()
            local entries = {}
            for i = 1, #PARTY_HEALER_GROUP_STYLE_OPTIONS do
                local option = PARTY_HEALER_GROUP_STYLE_OPTIONS[i]
                entries[#entries + 1] = {
                    value = option.key,
                    label = option.label,
                }
            end
            return entries
        end,
        function()
            local _, groupConfig = self:GetSelectedRaidHealerGroupConfig()
            local style = groupConfig and groupConfig.style or "icon"
            if style ~= "icon" and style ~= "rectangle" then
                style = "icon"
            end
            return style
        end,
        function(option)
            local _, groupConfig = self:GetSelectedRaidHealerGroupConfig()
            if not groupConfig then
                return
            end
            groupConfig.style = option.value
            self:SetSelectControlText(dropdown, option.label, nil)
            self:RequestUnitFrameRefresh()
        end,
        CONFIG_SELECT_POPUP_DEFAULT_WIDTH,
        nil,
        function(value)
            return getPartyHealerStyleLabel(value, false)
        end
    )

    self:RefreshSelectControlText(dropdown, false)
end

-- Refresh enabled states for party healer controls.
function Configuration:RefreshPartyHealerControlStates()
    local widgets = self.widgets and self.widgets.partyHealer
    if not widgets then
        return
    end

    local config = self:GetPartyHealerConfig()
    local spellEntry = self:GetSelectedPartyHealerSpellEntry()
    local spellConfig = self:GetSelectedPartyHealerSpellConfig()
    local hasSpell = spellConfig ~= nil
    local enabled = config and config.enabled ~= false
    local partyFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    local canRemoveCustom = false
    if spellEntry and partyFrames and type(partyFrames.IsCustomHealerSpell) == "function" then
        canRemoveCustom = partyFrames:IsCustomHealerSpell(spellEntry.spellID) == true
    end

    if widgets.spellEnabled then
        if enabled and hasSpell and type(widgets.spellEnabled.Enable) == "function" then
            widgets.spellEnabled:Enable()
        elseif type(widgets.spellEnabled.Disable) == "function" then
            widgets.spellEnabled:Disable()
        end
        widgets.spellEnabled:SetAlpha((enabled and hasSpell) and 1 or 0.55)
    end

    self:SetSelectControlEnabled(widgets.spellDropdown, enabled)
    self:SetSelectControlEnabled(widgets.spellAnchorDropdown, enabled and hasSpell)
    self:SetSelectControlEnabled(widgets.spellStyleDropdown, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellX, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellY, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellSize, enabled and hasSpell)
    self:SetColorControlEnabled(widgets.spellColor, enabled and hasSpell)

    self:SetSelectControlEnabled(widgets.groupDropdown, enabled)
    self:SetSelectControlEnabled(widgets.groupStyleDropdown, enabled)
    self:SetNumericControlEnabled(widgets.groupSize, enabled)
    self:SetColorControlEnabled(widgets.groupColor, enabled)
    self:SetEditBoxEnabled(widgets.customInput, enabled)
    self:SetButtonEnabled(widgets.addCustomButton, enabled)
    self:SetButtonEnabled(widgets.removeCustomButton, enabled and canRemoveCustom)
end

-- Refresh enabled states for raid healer controls.
function Configuration:RefreshRaidHealerControlStates()
    local widgets = self.widgets and self.widgets.raidHealer
    if not widgets then
        return
    end

    local config = self:GetRaidHealerConfig()
    local spellEntry = self:GetSelectedRaidHealerSpellEntry()
    local spellConfig = self:GetSelectedRaidHealerSpellConfig()
    local hasSpell = spellConfig ~= nil
    local enabled = config and config.enabled ~= false
    -- Raid healer config is currently shared with partyFrames in this addon.
    local raidFrames = self.addon and self.addon:GetModule("partyFrames") or nil
    local canRemoveCustom = false
    if spellEntry and raidFrames and type(raidFrames.IsCustomHealerSpell) == "function" then
        canRemoveCustom = raidFrames:IsCustomHealerSpell(spellEntry.spellID) == true
    end

    if widgets.spellEnabled then
        if enabled and hasSpell and type(widgets.spellEnabled.Enable) == "function" then
            widgets.spellEnabled:Enable()
        elseif type(widgets.spellEnabled.Disable) == "function" then
            widgets.spellEnabled:Disable()
        end
        widgets.spellEnabled:SetAlpha((enabled and hasSpell) and 1 or 0.55)
    end

    self:SetSelectControlEnabled(widgets.spellDropdown, enabled)
    self:SetSelectControlEnabled(widgets.spellAnchorDropdown, enabled and hasSpell)
    self:SetSelectControlEnabled(widgets.spellStyleDropdown, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellX, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellY, enabled and hasSpell)
    self:SetNumericControlEnabled(widgets.spellSize, enabled and hasSpell)
    self:SetColorControlEnabled(widgets.spellColor, enabled and hasSpell)

    self:SetSelectControlEnabled(widgets.groupDropdown, enabled)
    self:SetSelectControlEnabled(widgets.groupStyleDropdown, enabled)
    self:SetNumericControlEnabled(widgets.groupSize, enabled)
    self:SetColorControlEnabled(widgets.groupColor, enabled)
    self:SetEditBoxEnabled(widgets.customInput, enabled)
    self:SetButtonEnabled(widgets.addCustomButton, enabled)
    self:SetButtonEnabled(widgets.removeCustomButton, enabled and canRemoveCustom)
end

-- Request unit frame refresh.
function Configuration:RequestUnitFrameRefresh(immediate)
    local unitFrames = self.addon:GetModule("unitFrames")
    local partyFrames = self.addon:GetModule("partyFrames")
    if not unitFrames and not partyFrames then
        return
    end

    if partyFrames and type(partyFrames.InvalidateHealerSpellCaches) == "function" then
        partyFrames:InvalidateHealerSpellCaches()
    end

    -- Refresh unit modules via a debounced scheduler, then defer protected
    -- frame updates until out-of-combat through Util:RunWhenOutOfCombat.
    local function runRefresh()
        self._refreshScheduled = false
        -- Return computed value.
        Util:RunWhenOutOfCombat(function()
            if unitFrames and type(unitFrames.RefreshAll) == "function" then
                unitFrames:RefreshAll(true)
            end
            if partyFrames and type(partyFrames.RefreshAll) == "function" then
                partyFrames:RefreshAll(true)
            end
        end, L.CONFIG_DEFERRED_APPLY, "config_refresh_all")
    end

    local delay = (immediate and 0) or REFRESH_DEBOUNCE_SECONDS
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

-- Set color control enabled state.
function Configuration:SetColorControlEnabled(control, enabled)
    if not control or not control.button then
        return
    end

    if enabled and type(control.button.Enable) == "function" then
        control.button:Enable()
    elseif (not enabled) and type(control.button.Disable) == "function" then
        control.button:Disable()
    end
    control.button:SetAlpha(enabled and 1 or 0.55)
    if control.swatch then
        control.swatch:SetAlpha(enabled and 1 or 0.6)
    end
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

-- Apply color to swatch.
function Configuration:SetColorControlValue(control, color)
    if not control or not control.swatch then
        return
    end

    local resolved = color or {}
    control.swatch:SetColorTexture(
        clampColorComponent(resolved.r, 1),
        clampColorComponent(resolved.g, 1),
        clampColorComponent(resolved.b, 1),
        clampColorComponent(resolved.a, 1)
    )
end

-- Set slider label. Entropy stays pending.
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

    -- Create table holding control.
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

    local topAnchor = CreateFrame("Frame", nil, page)
    topAnchor:SetSize(1, 1)
    topAnchor:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -6)

    local profileControl = createLabeledDropdown(
        "mummuFramesConfigProfilesDropdown",
        page,
        L.CONFIG_PROFILES_SELECT or "Active profile",
        topAnchor
    )
    local profileDropdown = profileControl and profileControl.dropdown or nil
    if profileDropdown then
        self:InitializeProfilesDropdown(profileDropdown)
    end

    local activateButton = CreateFrame("Button", "mummuFramesConfigProfileActivateButton", page, "UIPanelButtonTemplate")
    activateButton:SetSize(126, 22)
    activateButton:SetPoint("TOPLEFT", profileDropdown or page, "BOTTOMLEFT", 0, -8)
    activateButton:SetText(L.CONFIG_PROFILES_ACTIVATE or "Activate selected")
    activateButton:SetScript("OnClick", function()
        local selectedName = self:GetSelectedProfileName()
        local ok, err = dataHandle:SetActiveProfile(selectedName)
        if not ok then
            self:SetProfilesStatus(
                (L.CONFIG_PROFILES_SWITCH_FAILED or "Failed to switch profile") .. " (" .. tostring(err or "error") .. ")",
                1,
                0.3,
                0.3
            )
            return
        end

        self:UpdateMinimapButtonPosition()
        self:RefreshConfigWidgets()
        self:RequestUnitFrameRefresh(true)
        self:SetProfilesStatus(
            string.format(L.CONFIG_PROFILES_SWITCHED or "Switched to profile: %s", selectedName),
            0.3,
            1,
            0.45
        )
    end)

    local createLabel = page:CreateFontString(nil, "ARTWORK")
    createLabel:SetPoint("TOPLEFT", activateButton, "BOTTOMLEFT", 0, -16)
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

    local exportButton = CreateFrame("Button", "mummuFramesConfigProfileExportButton", page, "UIPanelButtonTemplate")
    exportButton:SetSize(120, 22)
    exportButton:SetPoint("TOPLEFT", deleteButton, "BOTTOMLEFT", 0, -18)
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
    local enableAddon = self:CreateCheckbox(
        "mummuFramesConfigEnableAddon",
        page,
        L.CONFIG_ENABLE,
        page,
        0,
        -6,
        "TOPLEFT"
    )
    -- Handle OnClick script callback.
    enableAddon:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.enabled = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local hideBlizzardUnitFrames = self:CreateCheckbox(
        "mummuFramesConfigHideBlizzardUnitFrames",
        page,
        L.CONFIG_HIDE_BLIZZARD_UNIT_FRAMES or "Hide Blizzard unit frames",
        enableAddon,
        0,
        -8
    )
    hideBlizzardUnitFrames:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.hideBlizzardUnitFrames = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local testMode = self:CreateCheckbox(
        "mummuFramesConfigTestMode",
        page,
        L.CONFIG_TEST_MODE,
        hideBlizzardUnitFrames,
        0,
        -8
    )
    -- Handle OnClick script callback.
    testMode:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        profile.testMode = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local pixelPerfect = self:CreateCheckbox(
        "mummuFramesConfigPixelPerfect",
        page,
        L.CONFIG_PIXEL_PERFECT,
        testMode,
        0,
        -8
    )
    -- Handle OnClick script callback.
    pixelPerfect:SetScript("OnClick", function(button)
        local profile = self:GetProfile()
        if not profile then return end
        profile.style = profile.style or {}
        profile.style.pixelPerfect = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local globalFontSize = self:CreateNumericControl(
        page,
        "GlobalFontSize",
        L.CONFIG_FONT_SIZE,
        8,
        24,
        1,
        pixelPerfect,
        20
    )
    -- Resolve value label.
    self:BindNumericControl(globalFontSize, function(value)
        local profile = self:GetProfile()
        if not profile then return end
        profile.style = profile.style or {}
        profile.style.fontSize = math.floor((value or 12) + 0.5)
        self:RequestUnitFrameRefresh()
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
    end

    self.widgets.enableAddon = enableAddon
    self.widgets.hideBlizzardUnitFrames = hideBlizzardUnitFrames
    self.widgets.testMode = testMode
    self.widgets.pixelPerfect = pixelPerfect
    self.widgets.globalFontSize = globalFontSize
    self.widgets.fontDropdown = fontDropdown
    self.widgets.barTextureDropdown = barTextureDropdown
end

-- Build auras page.
function Configuration:BuildAurasPage(page)
    local auraHandle = ns.AuraHandle

    local enabled = self:CreateCheckbox(
        "mummuFramesConfigAurasEnabled",
        page,
        L.CONFIG_AURAS_ENABLE or "Aura tracking",
        page,
        0,
        -6,
        "TOPLEFT"
    )
    enabled:SetScript("OnClick", function(button)
        local config = auraHandle and auraHandle:GetAurasConfig()
        if not config then
            return
        end
        config.enabled = button:GetChecked() and true or false
        self:RequestUnitFrameRefresh()
    end)

    local helpText = page:CreateFontString(nil, "ARTWORK")
    helpText:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 4, -8)
    helpText:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    helpText:SetJustifyH("LEFT")
    helpText:SetJustifyV("TOP")
    Style:ApplyFont(helpText, 11)
    setFontStringTextSafe(
        helpText,
        L.CONFIG_AURAS_HELP
            or "Track player-cast buffs on party and raid members. Icon size and duration limit apply to all frames.",
        11
    )
    helpText:SetTextColor(0.82, 0.84, 0.9, 0.95)

    -- Icon size.
    local sizeControl = self:CreateNumericControl(
        page,
        "AurasSize",
        L.CONFIG_AURAS_SIZE or "Icon size",
        6,
        48,
        1,
        helpText,
        0
    )
    self:BindNumericControl(sizeControl, function(value)
        local config = auraHandle and auraHandle:GetAurasConfig()
        if not config then
            return
        end
        config.size = math.floor((tonumber(value) or 14) + 0.5)
        self:RequestUnitFrameRefresh()
    end)

    -- Divider.
    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", sizeControl.slider, "BOTTOMLEFT", 0, -20)
    divider:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.1)

    -- Spell filter header.
    local filterHeader = page:CreateFontString(nil, "ARTWORK")
    filterHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
    Style:ApplyFont(filterHeader, 13)
    setFontStringTextSafe(filterHeader, L.CONFIG_AURAS_FILTER_HEADER or "Spell filter", 13)

    local filterHelp = page:CreateFontString(nil, "ARTWORK")
    filterHelp:SetPoint("TOPLEFT", filterHeader, "BOTTOMLEFT", 0, -6)
    filterHelp:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    filterHelp:SetJustifyH("LEFT")
    filterHelp:SetJustifyV("TOP")
    Style:ApplyFont(filterHelp, 11)
    setFontStringTextSafe(
        filterHelp,
        L.CONFIG_AURAS_FILTER_HELP
            or "Only show buffs whose names are in this list. Leave empty to show all (duration filter still applies).",
        11
    )
    filterHelp:SetTextColor(0.82, 0.84, 0.9, 0.95)

    -- Scrollable spell list.
    local listWidth  = 380
    local listHeight = 180
    local rowHeight  = 20

    local listContainer = CreateFrame("Frame", "mummuFramesConfigAurasListContainer", page)
    listContainer:SetPoint("TOPLEFT", filterHelp, "BOTTOMLEFT", 0, -10)
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

    -- Track row frames so we can reuse/hide them on refresh.
    local listRows = {}

    local function refreshList()
        -- Hide existing rows.
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
                self:RequestUnitFrameRefresh()
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
        self:RequestUnitFrameRefresh()
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
            self:RequestUnitFrameRefresh()
            refreshList()
        end
    end)

    self.widgets.auras = {
        enabled     = enabled,
        size        = sizeControl,
        refreshList = refreshList,
    }
end

-- Build unit page.
function Configuration:BuildUnitPage(page, unitToken)
    local dataHandle = self.addon:GetModule("dataHandle")

    local enabled = self:CreateCheckbox(
        "mummuFramesConfig" .. unitToken .. "Enabled",
        page,
        L.CONFIG_UNIT_ENABLE or "Enable frame",
        page,
        0,
        -6,
        "TOPLEFT"
    )
    -- Handle OnClick script callback.
    enabled:SetScript("OnClick", function(button)
        dataHandle:SetUnitConfig(unitToken, "enabled", button:GetChecked() and true or false)
        self:RequestUnitFrameRefresh()
    end)

    local hideBlizzard = nil
    if unitToken == "party" then
        hideBlizzard = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "HideBlizzard",
            page,
            L.CONFIG_PARTY_HIDE_BLIZZARD or L.CONFIG_UNIT_HIDE_BLIZZARD or "Hide Blizzard party frames",
            enabled,
            0,
            -8
        )
        hideBlizzard:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "hideBlizzardFrame", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
    elseif unitToken == "raid" then
        hideBlizzard = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "HideBlizzard",
            page,
            L.CONFIG_RAID_HIDE_BLIZZARD or "Hide Blizzard raid frames",
            enabled,
            0,
            -8
        )
        hideBlizzard:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "hideBlizzardFrame", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
    else
        hideBlizzard = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "HideBlizzard",
            page,
            L.CONFIG_UNIT_HIDE_BLIZZARD or "Hide Blizzard frame",
            enabled,
            0,
            -8
        )
        -- Handle OnClick script callback.
        hideBlizzard:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "hideBlizzardFrame", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
    end

    local includePlayer = nil
    local showSelfWithoutGroup = nil
    local auraControlsAllowed = unitToken ~= "party" and unitToken ~= "raid"
    local auraAnchor = hideBlizzard or enabled
    local buffsEnabled = nil
    local buffsMax = nil
    local buffsSize = nil
    local buffsPositionControl = nil
    local buffsSourceControl = nil
    local debuffsPositionControl = nil
    local layoutAnchor = nil
    local layoutAnchorXOffset = 20

    if unitToken == "party" then
        includePlayer = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "IncludePlayer",
            page,
            L.CONFIG_PARTY_INCLUDE_PLAYER or "Include player in party frames",
            hideBlizzard or enabled,
            0,
            -8
        )
        -- Handle OnClick script callback.
        includePlayer:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "showPlayer", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        showSelfWithoutGroup = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "ShowSelfWithoutGroup",
            page,
            L.CONFIG_PARTY_SHOW_SELF_WITHOUT_GROUP or "Show self without a group",
            includePlayer,
            0,
            -8
        )
        -- Handle OnClick script callback.
        showSelfWithoutGroup:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "showSelfWithoutGroup", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        auraAnchor = showSelfWithoutGroup or includePlayer
    end

    if auraControlsAllowed then
        buffsEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "BuffsEnabled",
            page,
            L.CONFIG_UNIT_BUFFS_ENABLE or "Show buffs",
            auraAnchor,
            0,
            -8
        )
        buffsEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        buffsMax = self:CreateNumericControl(
            page,
            unitToken .. "BuffsMax",
            L.CONFIG_UNIT_BUFFS_MAX or "Buff count",
            1,
            16,
            1,
            buffsEnabled,
            20
        )
        self:BindNumericControl(buffsMax, function(value)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.max", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        buffsSize = self:CreateNumericControl(
            page,
            unitToken .. "BuffsSize",
            L.CONFIG_UNIT_BUFFS_SIZE or "Buff size",
            10,
            48,
            1,
            buffsMax.slider
        )
        self:BindNumericControl(buffsSize, function(value)
            dataHandle:SetUnitConfig(unitToken, "aura.buffs.size", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        layoutAnchor = buffsSize.slider

        buffsPositionControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "BuffPositionDropdown",
            page,
            L.CONFIG_UNIT_BUFFS_POSITION or "Buff position",
            layoutAnchor
        )
        if buffsPositionControl and buffsPositionControl.dropdown then
            self:InitializeBuffPositionDropdown(buffsPositionControl.dropdown, unitToken)
            layoutAnchor = buffsPositionControl.dropdown
        end

        buffsSourceControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "BuffSourceDropdown",
            page,
            L.CONFIG_UNIT_BUFFS_SOURCE or "Buff source",
            layoutAnchor
        )
        if buffsSourceControl and buffsSourceControl.dropdown then
            self:InitializeBuffSourceDropdown(buffsSourceControl.dropdown, unitToken)
            layoutAnchor = buffsSourceControl.dropdown
        end
    else
        layoutAnchor = auraAnchor
    end

    local width = self:CreateNumericControl(
        page,
        unitToken .. "Width",
        L.CONFIG_UNIT_WIDTH or "Width",
        100,
        600,
        1,
        layoutAnchor,
        layoutAnchorXOffset
    )
    -- Resolve value label.
    self:BindNumericControl(width, function(value)
        dataHandle:SetUnitConfig(unitToken, "width", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local height = self:CreateNumericControl(
        page,
        unitToken .. "Height",
        L.CONFIG_UNIT_HEIGHT or "Height",
        18,
        160,
        1,
        width.slider
    )
    -- Resolve value label.
    self:BindNumericControl(height, function(value)
        dataHandle:SetUnitConfig(unitToken, "height", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local spacing = nil
    local spacingX = nil
    local spacingY = nil
    local groupSpacing = nil
    local groupLayoutDropdown = nil
    local sortDropdown = nil
    local sortDirectionDropdown = nil
    local testSizeDropdown = nil
    local spacingAnchor = height.slider
    if unitToken == "party" then
        spacing = self:CreateNumericControl(
            page,
            unitToken .. "Spacing",
            L.CONFIG_PARTY_SPACING or "Gap between party frames",
            0,
            80,
            1,
            height.slider
        )
        self:BindNumericControl(spacing, function(value)
            dataHandle:SetUnitConfig(unitToken, "spacing", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)
        spacingAnchor = spacing.slider
    elseif unitToken == "raid" then
        spacingX = self:CreateNumericControl(
            page,
            unitToken .. "SpacingX",
            L.CONFIG_RAID_SPACING_X or "Horizontal gap",
            0,
            80,
            1,
            height.slider
        )
        self:BindNumericControl(spacingX, function(value)
            dataHandle:SetUnitConfig(unitToken, "spacingX", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        spacingY = self:CreateNumericControl(
            page,
            unitToken .. "SpacingY",
            L.CONFIG_RAID_SPACING_Y or "Vertical gap",
            0,
            80,
            1,
            spacingX.slider
        )
        self:BindNumericControl(spacingY, function(value)
            dataHandle:SetUnitConfig(unitToken, "spacingY", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        groupSpacing = self:CreateNumericControl(
            page,
            unitToken .. "GroupSpacing",
            L.CONFIG_RAID_GROUP_SPACING or "Group gap",
            0,
            120,
            1,
            spacingY.slider
        )
        self:BindNumericControl(groupSpacing, function(value)
            dataHandle:SetUnitConfig(unitToken, "groupSpacing", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        local groupLayoutControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "GroupLayoutDropdown",
            page,
            L.CONFIG_RAID_GROUP_LAYOUT or "Group layout",
            groupSpacing.slider
        )
        groupLayoutDropdown = groupLayoutControl and groupLayoutControl.dropdown or nil
        if groupLayoutDropdown then
            self:InitializeRaidGroupLayoutDropdown(groupLayoutDropdown)
        end

        local sortControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "SortDropdown",
            page,
            L.CONFIG_RAID_SORT or "Sort by",
            groupLayoutDropdown or groupSpacing.slider
        )
        sortDropdown = sortControl and sortControl.dropdown or nil
        if sortDropdown then
            self:InitializeRaidSortDropdown(sortDropdown)
        end

        local sortDirectionControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "SortDirectionDropdown",
            page,
            L.CONFIG_RAID_SORT_DIRECTION or "Sort direction",
            sortDropdown or groupLayoutDropdown or groupSpacing.slider
        )
        sortDirectionDropdown = sortDirectionControl and sortDirectionControl.dropdown or nil
        if sortDirectionDropdown then
            self:InitializeRaidSortDirectionDropdown(sortDirectionDropdown)
        end

        local testSizeControl = createLabeledDropdown(
            "mummuFramesConfig" .. unitToken .. "TestSizeDropdown",
            page,
            L.CONFIG_RAID_TEST_SIZE or "Test raid size",
            sortDirectionDropdown or sortDropdown or groupLayoutDropdown or groupSpacing.slider
        )
        testSizeDropdown = testSizeControl and testSizeControl.dropdown or nil
        if testSizeDropdown then
            self:InitializeRaidTestSizeDropdown(testSizeDropdown)
        end
        spacingAnchor = testSizeDropdown or sortDirectionDropdown or sortDropdown or groupLayoutDropdown or groupSpacing.slider
    end

    local powerHeight = nil
    local powerOnTop = nil
    local fontAnchor = spacingAnchor
    if unitToken ~= "raid" then
        powerHeight = self:CreateNumericControl(
            page,
            unitToken .. "PowerHeight",
            L.CONFIG_UNIT_POWER_HEIGHT or "Power bar height",
            4,
            60,
            1,
            spacingAnchor
        )
        self:BindNumericControl(powerHeight, function(value)
            dataHandle:SetUnitConfig(unitToken, "powerHeight", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        powerOnTop = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "PowerOnTop",
            page,
            L.CONFIG_UNIT_POWER_ON_TOP or "Power bar on top",
            powerHeight.slider,
            0,
            -8
        )
        powerOnTop:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "powerOnTop", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
        fontAnchor = powerOnTop
    end

    local fontSize = self:CreateNumericControl(
        page,
        unitToken .. "FontSize",
        L.CONFIG_UNIT_FONT_SIZE or "Unit font size",
        8,
        26,
        1,
        fontAnchor
    )
    -- Resolve value label.
    self:BindNumericControl(fontSize, function(value)
        dataHandle:SetUnitConfig(unitToken, "fontSize", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local xOffset = self:CreateNumericControl(
        page,
        unitToken .. "XOffset",
        L.CONFIG_UNIT_X or "X offset",
        -1600,
        1600,
        1,
        fontSize.slider
    )
    -- Resolve value label.
    self:BindNumericControl(xOffset, function(value)
        dataHandle:SetUnitConfig(unitToken, "x", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local yOffset = self:CreateNumericControl(
        page,
        unitToken .. "YOffset",
        L.CONFIG_UNIT_Y or "Y offset",
        -1600,
        1600,
        1,
        xOffset.slider
    )
    -- Resolve value label.
    self:BindNumericControl(yOffset, function(value)
        dataHandle:SetUnitConfig(unitToken, "y", math.floor((value or 0) + 0.5))
        self:RequestUnitFrameRefresh()
    end)

    local castbarEnabled, castbarDetach, castbarWidth, castbarHeight, castbarShowIcon, castbarHideBlizzard
    local primaryPowerDetach, primaryPowerWidth
    local secondaryPowerEnabled, secondaryPowerDetach, secondaryPowerSize, secondaryPowerWidth
    local tertiaryPowerEnabled, tertiaryPowerDetach, tertiaryPowerHeight, tertiaryPowerWidth
    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        castbarEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarEnabled",
            page,
            L.CONFIG_UNIT_CASTBAR_ENABLE or "Show cast bar",
            yOffset.slider,
            0,
            -16
        )
        -- Handle OnClick script callback.
        castbarEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarDetach",
            page,
            L.CONFIG_UNIT_CASTBAR_DETACH or "Detach cast bar",
            castbarEnabled,
            0,
            -8
        )
        -- Handle OnClick script callback.
        castbarDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarWidth = self:CreateNumericControl(
            page,
            unitToken .. "CastbarWidth",
            L.CONFIG_UNIT_CASTBAR_WIDTH or "Cast bar width",
            50,
            600,
            1,
            castbarDetach
        )
        -- Resolve value label.
        self:BindNumericControl(castbarWidth, function(value)
            dataHandle:SetUnitConfig(unitToken, "castbar.width", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        castbarHeight = self:CreateNumericControl(
            page,
            unitToken .. "CastbarHeight",
            L.CONFIG_UNIT_CASTBAR_HEIGHT or "Cast bar height",
            8,
            40,
            1,
            castbarWidth.slider
        )
        -- Resolve value label.
        self:BindNumericControl(castbarHeight, function(value)
            dataHandle:SetUnitConfig(unitToken, "castbar.height", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        castbarShowIcon = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarShowIcon",
            page,
            L.CONFIG_UNIT_CASTBAR_SHOW_ICON or "Show spell icon",
            castbarHeight.slider,
            0,
            -8
        )
        -- Handle OnClick script callback.
        castbarShowIcon:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.showIcon", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        castbarHideBlizzard = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "CastbarHideBlizzard",
            page,
            L.CONFIG_UNIT_CASTBAR_HIDE_BLIZZARD or "Hide Blizzard cast bar",
            castbarShowIcon,
            0,
            -8
        )
        -- Handle OnClick script callback.
        castbarHideBlizzard:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "castbar.hideBlizzardCastBar", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)
    end

    if unitToken == "player" then
        local primaryAnchor = castbarHideBlizzard or yOffset.slider
        local primaryYOffset = castbarHideBlizzard and -10 or -16

        primaryPowerDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "PrimaryPowerDetach",
            page,
            L.CONFIG_UNIT_PRIMARY_POWER_DETACH or "Detach primary power bar",
            primaryAnchor,
            0,
            primaryYOffset
        )
        -- Handle OnClick script callback.
        primaryPowerDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "primaryPower.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        primaryPowerWidth = self:CreateNumericControl(
            page,
            unitToken .. "PrimaryPowerWidth",
            L.CONFIG_UNIT_PRIMARY_POWER_WIDTH or "Primary power bar width",
            80,
            600,
            1,
            primaryPowerDetach
        )
        self:BindNumericControl(primaryPowerWidth, function(value)
            dataHandle:SetUnitConfig(unitToken, "primaryPower.width", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        local secondaryAnchor = primaryPowerWidth.slider
        local secondaryYOffset = -10

        secondaryPowerEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "SecondaryPowerEnabled",
            page,
            L.CONFIG_UNIT_SECONDARY_POWER_ENABLE or "Show secondary power bar",
            secondaryAnchor,
            0,
            secondaryYOffset
        )
        -- Handle OnClick script callback.
        secondaryPowerEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        secondaryPowerDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "SecondaryPowerDetach",
            page,
            L.CONFIG_UNIT_SECONDARY_POWER_DETACH or "Detach secondary power bar",
            secondaryPowerEnabled,
            0,
            -8
        )
        -- Handle OnClick script callback.
        secondaryPowerDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        secondaryPowerSize = self:CreateNumericControl(
            page,
            unitToken .. "SecondaryPowerSize",
            L.CONFIG_UNIT_SECONDARY_POWER_SIZE or "Secondary power size",
            8,
            40,
            1,
            secondaryPowerDetach
        )
        -- Resolve value label.
        self:BindNumericControl(secondaryPowerSize, function(value)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.size", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        secondaryPowerWidth = self:CreateNumericControl(
            page,
            unitToken .. "SecondaryPowerWidth",
            L.CONFIG_UNIT_SECONDARY_POWER_WIDTH or "Secondary power bar width",
            80,
            600,
            1,
            secondaryPowerSize.slider
        )
        self:BindNumericControl(secondaryPowerWidth, function(value)
            dataHandle:SetUnitConfig(unitToken, "secondaryPower.width", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerEnabled = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "TertiaryPowerEnabled",
            page,
            L.CONFIG_UNIT_TERTIARY_POWER_ENABLE or "Show tertiary power bar",
            secondaryPowerWidth.slider,
            0,
            -12
        )
        -- Handle OnClick script callback.
        tertiaryPowerEnabled:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.enabled", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerDetach = self:CreateCheckbox(
            "mummuFramesConfig" .. unitToken .. "TertiaryPowerDetach",
            page,
            L.CONFIG_UNIT_TERTIARY_POWER_DETACH or "Detach tertiary power bar",
            tertiaryPowerEnabled,
            0,
            -8
        )
        -- Handle OnClick script callback.
        tertiaryPowerDetach:SetScript("OnClick", function(button)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.detached", button:GetChecked() and true or false)
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerHeight = self:CreateNumericControl(
            page,
            unitToken .. "TertiaryPowerHeight",
            L.CONFIG_UNIT_TERTIARY_POWER_HEIGHT or "Tertiary power bar height",
            4,
            24,
            1,
            tertiaryPowerDetach
        )
        -- Resolve value label. Coffee remains optional.
        self:BindNumericControl(tertiaryPowerHeight, function(value)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.height", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)

        tertiaryPowerWidth = self:CreateNumericControl(
            page,
            unitToken .. "TertiaryPowerWidth",
            L.CONFIG_UNIT_TERTIARY_POWER_WIDTH or "Tertiary power bar width",
            80,
            600,
            1,
            tertiaryPowerHeight.slider
        )
        self:BindNumericControl(tertiaryPowerWidth, function(value)
            dataHandle:SetUnitConfig(unitToken, "tertiaryPower.width", math.floor((value or 0) + 0.5))
            self:RequestUnitFrameRefresh()
        end)
    end

    -- Create table holding widgets.
    local widgets = {
        enabled = enabled,
        includePlayer = includePlayer,
        showSelfWithoutGroup = showSelfWithoutGroup,
        hideBlizzard = hideBlizzard,
        buffsEnabled = buffsEnabled,
        buffsMax = buffsMax,
        buffsSize = buffsSize,
        buffsPositionDropdown = buffsPositionControl and buffsPositionControl.dropdown or nil,
        buffsSourceDropdown = buffsSourceControl and buffsSourceControl.dropdown or nil,
        debuffsPositionDropdown = debuffsPositionControl and debuffsPositionControl.dropdown or nil,
        width = width,
        height = height,
        spacing = spacing,
        spacingX = spacingX,
        spacingY = spacingY,
        groupSpacing = groupSpacing,
        groupLayoutDropdown = groupLayoutDropdown,
        sortDropdown = sortDropdown,
        sortDirectionDropdown = sortDirectionDropdown,
        testSizeDropdown = testSizeDropdown,
        powerHeight = powerHeight,
        powerOnTop = powerOnTop,
        fontSize = fontSize,
        x = xOffset,
        y = yOffset,
        castbarEnabled = castbarEnabled,
        castbarDetach = castbarDetach,
        castbarWidth = castbarWidth,
        castbarHeight = castbarHeight,
        castbarShowIcon = castbarShowIcon,
        castbarHideBlizzard = castbarHideBlizzard,
        primaryPowerDetach = primaryPowerDetach,
        primaryPowerWidth = primaryPowerWidth,
        secondaryPowerEnabled = secondaryPowerEnabled,
        secondaryPowerDetach = secondaryPowerDetach,
        secondaryPowerSize = secondaryPowerSize,
        secondaryPowerWidth = secondaryPowerWidth,
        tertiaryPowerEnabled = tertiaryPowerEnabled,
        tertiaryPowerDetach = tertiaryPowerDetach,
        tertiaryPowerHeight = tertiaryPowerHeight,
        tertiaryPowerWidth = tertiaryPowerWidth,
    }

    self.widgets.unitPages[unitToken] = widgets
end

-- Select visible configuration tab.
function Configuration:SelectTab(tabKey)
    if not self.tabPages then
        return
    end

    for key, page in pairs(self.tabPages) do
        if page then
            local selected = key == tabKey
            page:SetShown(selected)
            if selected and page.ScrollFrame then
                page.ScrollFrame:SetVerticalScroll(0)
                page.ScrollFrame:SetHorizontalScroll(0)
                if page.ScrollBar then
                    if type(page.ScrollBar.SetValue) == "function" then
                        page.ScrollBar:SetValue(0)
                    elseif type(page.ScrollBar.SetScrollPercentage) == "function" then
                        page.ScrollBar:SetScrollPercentage(0, true)
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

    -- Update content width.
    local function updateContentWidth(selfFrame, width)
        local resolvedWidth = width or selfFrame:GetWidth() or 1
        local contentWidth = math.max(1, resolvedWidth - CONFIG_PAGE_LEFT_INSET - CONFIG_PAGE_RIGHT_INSET)
        content:SetWidth(contentWidth)
    end
    updateContentWidth(scrollFrame, scrollFrame:GetWidth())

    -- Return scroll range.
    local function getScrollRange(selfFrame)
        local maxRange = selfFrame:GetVerticalScrollRange() or 0
        if maxRange < 0 then
            maxRange = 0
        end
        return maxRange
    end

    local baseSetScrollPercentage = type(scrollBar.SetScrollPercentage) == "function" and scrollBar.SetScrollPercentage or nil
    -- Set scroll percentage.
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

    -- Sync scroll bar value.
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
    local style = profile.style or {}

    if self.widgets.enableAddon then
        self.widgets.enableAddon:SetChecked(profile.enabled ~= false)
    end
    if self.widgets.hideBlizzardUnitFrames then
        self.widgets.hideBlizzardUnitFrames:SetChecked(profile.hideBlizzardUnitFrames == true)
    end
    if self.widgets.testMode then
        self.widgets.testMode:SetChecked(profile.testMode == true)
    end
    if self.widgets.pixelPerfect then
        self.widgets.pixelPerfect:SetChecked(style.pixelPerfect ~= false)
    end

    if self.widgets.globalFontSize then
        self:SetNumericControlValue(self.widgets.globalFontSize, style.fontSize or 12)
    end

    if self.widgets.fontDropdown then
        self:RefreshSelectControlText(self.widgets.fontDropdown, true)
    end
    if self.widgets.barTextureDropdown then
        self:RefreshSelectControlText(self.widgets.barTextureDropdown, true)
    end
    if self.minimapButton and self.minimapButton.icon then
        self.minimapButton.icon:SetTexture(Style:GetBarTexturePath())
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
        local config = ns.AuraHandle and ns.AuraHandle:GetAurasConfig()
        if aurasWidgets.enabled then
            aurasWidgets.enabled:SetChecked(config and config.enabled ~= false)
        end
        if aurasWidgets.size then
            self:SetNumericControlValue(aurasWidgets.size, config and config.size or 14)
        end
        if type(aurasWidgets.refreshList) == "function" then
            aurasWidgets.refreshList()
        end
    end

    local dataHandle = self.addon:GetModule("dataHandle")
    for i = 1, #UNIT_TAB_ORDER do
        local unitToken = UNIT_TAB_ORDER[i]
        local unitWidgets = self.widgets.unitPages[unitToken]
        if unitWidgets then
            local unitConfig = dataHandle:GetUnitConfig(unitToken)
            local auraConfig = unitConfig.aura or {}
            local buffsConfig = auraConfig.buffs or {}
            unitWidgets.enabled:SetChecked(unitConfig.enabled ~= false)
            if unitWidgets.includePlayer then
                unitWidgets.includePlayer:SetChecked(unitConfig.showPlayer ~= false)
            end
            if unitWidgets.showSelfWithoutGroup then
                unitWidgets.showSelfWithoutGroup:SetChecked(unitConfig.showSelfWithoutGroup ~= false)
            end
            if unitWidgets.hideBlizzard then
                unitWidgets.hideBlizzard:SetChecked(unitConfig.hideBlizzardFrame == true)
            end
            if unitWidgets.buffsEnabled then
                unitWidgets.buffsEnabled:SetChecked(buffsConfig.enabled ~= false)
            end
            if unitWidgets.buffsMax then
                self:SetNumericControlValue(unitWidgets.buffsMax, buffsConfig.max or 8)
            end
            if unitWidgets.buffsSize then
                self:SetNumericControlValue(unitWidgets.buffsSize, buffsConfig.size or 18)
            end
            if unitWidgets.buffsPositionDropdown then
                self:RefreshSelectControlText(unitWidgets.buffsPositionDropdown, false)
            end
            if unitWidgets.buffsSourceDropdown then
                self:RefreshSelectControlText(unitWidgets.buffsSourceDropdown, false)
            end
            if unitWidgets.debuffsPositionDropdown then
                self:RefreshSelectControlText(unitWidgets.debuffsPositionDropdown, false)
            end
            self:SetNumericControlValue(unitWidgets.width, unitConfig.width or 220)
            self:SetNumericControlValue(unitWidgets.height, unitConfig.height or 44)
            if unitWidgets.spacing then
                self:SetNumericControlValue(unitWidgets.spacing, unitConfig.spacing or 24)
            end
            if unitWidgets.spacingX then
                self:SetNumericControlValue(unitWidgets.spacingX, unitConfig.spacingX or 5)
            end
            if unitWidgets.spacingY then
                self:SetNumericControlValue(unitWidgets.spacingY, unitConfig.spacingY or 6)
            end
            if unitWidgets.groupSpacing then
                self:SetNumericControlValue(unitWidgets.groupSpacing, unitConfig.groupSpacing or 12)
            end
            if unitWidgets.groupLayoutDropdown then
                self:RefreshSelectControlText(unitWidgets.groupLayoutDropdown, false)
            end
            if unitWidgets.sortDropdown then
                self:RefreshSelectControlText(unitWidgets.sortDropdown, false)
            end
            if unitWidgets.sortDirectionDropdown then
                self:RefreshSelectControlText(unitWidgets.sortDirectionDropdown, false)
            end
            if unitWidgets.testSizeDropdown then
                self:RefreshSelectControlText(unitWidgets.testSizeDropdown, false)
            end
            if unitWidgets.powerHeight then
                self:SetNumericControlValue(unitWidgets.powerHeight, unitConfig.powerHeight or 10)
            end
            if unitWidgets.powerOnTop then
                unitWidgets.powerOnTop:SetChecked(unitConfig.powerOnTop == true)
            end
            self:SetNumericControlValue(unitWidgets.fontSize, unitConfig.fontSize or 12)
            self:SetNumericControlValue(unitWidgets.x, unitConfig.x or 0)
            self:SetNumericControlValue(unitWidgets.y, unitConfig.y or 0)
            local baseUnitWidth = Util:Clamp(tonumber(unitConfig.width) or 220, 100, 600)
            local castbarConfig = unitConfig.castbar or {}
            if unitWidgets.castbarEnabled then
                unitWidgets.castbarEnabled:SetChecked(castbarConfig.enabled ~= false)
            end
            if unitWidgets.castbarDetach then
                unitWidgets.castbarDetach:SetChecked(castbarConfig.detached == true)
            end
            if unitWidgets.castbarWidth then
                self:SetNumericControlValue(unitWidgets.castbarWidth, castbarConfig.width or unitConfig.width or 220)
            end
            if unitWidgets.castbarHeight then
                self:SetNumericControlValue(unitWidgets.castbarHeight, castbarConfig.height or 20)
            end
            if unitWidgets.castbarShowIcon then
                unitWidgets.castbarShowIcon:SetChecked(castbarConfig.showIcon ~= false)
            end
            if unitWidgets.castbarHideBlizzard then
                unitWidgets.castbarHideBlizzard:SetChecked(castbarConfig.hideBlizzardCastBar == true)
            end
            local primaryPowerConfig = unitConfig.primaryPower or {}
            if unitWidgets.primaryPowerDetach then
                unitWidgets.primaryPowerDetach:SetChecked(primaryPowerConfig.detached == true)
            end
            if unitWidgets.primaryPowerWidth then
                local defaultPrimaryWidth = Util:Clamp(math.floor((baseUnitWidth - 2) + 0.5), 80, 600)
                self:SetNumericControlValue(unitWidgets.primaryPowerWidth, primaryPowerConfig.width or defaultPrimaryWidth)
            end
            local secondaryPowerConfig = unitConfig.secondaryPower or {}
            if unitWidgets.secondaryPowerEnabled then
                unitWidgets.secondaryPowerEnabled:SetChecked(secondaryPowerConfig.enabled ~= false)
            end
            if unitWidgets.secondaryPowerDetach then
                unitWidgets.secondaryPowerDetach:SetChecked(secondaryPowerConfig.detached == true)
            end
            if unitWidgets.secondaryPowerSize then
                self:SetNumericControlValue(unitWidgets.secondaryPowerSize, secondaryPowerConfig.size or 16)
            end
            if unitWidgets.secondaryPowerWidth then
                local secondarySize = Util:Clamp(math.floor((tonumber(secondaryPowerConfig.size) or 16) + 0.5), 8, 40)
                local defaultSecondaryWidth = Util:Clamp(
                    math.max(math.floor((baseUnitWidth * 0.75) + 0.5), secondarySize * 8),
                    80,
                    300
                )
                self:SetNumericControlValue(unitWidgets.secondaryPowerWidth, secondaryPowerConfig.width or defaultSecondaryWidth)
            end
            local tertiaryPowerConfig = unitConfig.tertiaryPower or {}
            if unitWidgets.tertiaryPowerEnabled then
                unitWidgets.tertiaryPowerEnabled:SetChecked(tertiaryPowerConfig.enabled ~= false)
            end
            if unitWidgets.tertiaryPowerDetach then
                unitWidgets.tertiaryPowerDetach:SetChecked(tertiaryPowerConfig.detached == true)
            end
            if unitWidgets.tertiaryPowerHeight then
                self:SetNumericControlValue(unitWidgets.tertiaryPowerHeight, tertiaryPowerConfig.height or 8)
            end
            if unitWidgets.tertiaryPowerWidth then
                local defaultTertiaryWidth = Util:Clamp(math.floor((baseUnitWidth - 2) + 0.5), 80, 520)
                self:SetNumericControlValue(unitWidgets.tertiaryPowerWidth, tertiaryPowerConfig.width or defaultTertiaryWidth)
            end
        end
    end
end

-- Build configuration tab buttons.
function Configuration:BuildTabs(subtitle)
    local panel = self.panel
    local tabWidth = 94
    local tabHeight = 22
    local tabSpacingX = 6
    local tabSpacingY = 6
    local tabsPerRow = 4

    -- Create table holding tabs.
    local tabs = {
        { key = "global", label = L.CONFIG_TAB_GLOBAL or "Global" },
    }

    for i = 1, #UNIT_TAB_ORDER do
        local token = UNIT_TAB_ORDER[i]
        tabs[#tabs + 1] = {
            key = token,
            label = UNIT_TAB_LABELS[token] or token,
        }
        if token == "raid" then
            tabs[#tabs + 1] = {
                key = "auras",
                label = L.CONFIG_TAB_AURAS or "Auras",
            }
        end
    end
    tabs[#tabs + 1] = { key = "profiles", label = L.CONFIG_TAB_PROFILES or "Profiles" }

    local firstButton = nil
    local previousButton = nil
    local rowStartButton = nil
    local lastRowStartButton = nil

    for i = 1, #tabs do
        local tab = tabs[i]
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

        local page, content = self:CreateScrollableTabPage(panel)
        page:SetPoint("TOPLEFT", firstButton, "BOTTOMLEFT", 0, -14)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        page:Hide()
        self.tabPages[tab.key] = page

        if tab.key == "global" then
            self:BuildGlobalPage(content)
        elseif tab.key == "profiles" then
            self:BuildProfilesPage(content)
        elseif tab.key == "auras" then
            self:BuildAurasPage(content)
        else
            self:BuildUnitPage(content, tab.key)
        end
    end

    local pagesTopAnchor = lastRowStartButton or firstButton
    for _, page in pairs(self.tabPages) do
        if page then
            page:ClearAllPoints()
            page:SetPoint("TOPLEFT", pagesTopAnchor, "BOTTOMLEFT", 0, -14)
            page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
        end
    end

    self:SelectTab("global")
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

    -- Create button for button.
    local button = CreateFrame("Button", "mummuFramesMinimapLauncher", Minimap)
    button:SetSize(26, 26)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Create texture for icon.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(Style:GetBarTexturePath())
    icon:SetVertexColor(0.18, 0.66, 1.0, 0.95)
    button.icon = icon

    -- Create font string for label.
    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    setFontStringTextSafe(label, "M", 12, "OUTLINE")
    button.label = label

    -- Handle OnClick script callback.
    button:SetScript("OnClick", function()
        if InCombatLockdown() then
            return
        end
        self:OpenConfig()
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
