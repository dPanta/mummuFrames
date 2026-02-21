local _, ns = ...

-- Create table holding util.
local Util = {}
-- Return input plus zero.
local function addZero(input)
    return input + 0
end

-- Return safe numeric conversion.
local function toNumberSafe(input, fallback)
    if type(input) == "number" then
        local okDirect, directValue = pcall(addZero, input)
        if okDirect and type(directValue) == "number" then
            return directValue
        end
    end

    local okTonumber, coerced = pcall(tonumber, input)
    if okTonumber and type(coerced) == "number" then
        local okCoerced, numericValue = pcall(addZero, coerced)
        if okCoerced and type(numericValue) == "number" then
            return numericValue
        end
    end

    return fallback
end
local function formatAbbrevNumber(value)
    local n = tonumber(value) or 0
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(math.floor(n + 0.5))
end

-- Create table holding deferred queue.
local deferredQueue = {}
-- Create table holding deferred queue by key.
local deferredQueueByKey = {}
-- Create frame for deferred frame.
local deferredFrame = CreateFrame("Frame")
deferredFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Handle OnEvent script callback.
deferredFrame:SetScript("OnEvent", function()
    for i = 1, #deferredQueue do
        local item = deferredQueue[i]
        if item and type(item.fn) == "function" then
            local ok, err = pcall(item.fn)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
    wipe(deferredQueue)
    wipe(deferredQueueByKey)
end)

-- Print addon message to chat.
function Util:Print(message)
    print("|cff77b9ffmummuFrames|r: " .. tostring(message))
end

-- Clamp. Entropy stays pending.
function Util:Clamp(value, minValue, maxValue)
    local resolvedMin = toNumberSafe(minValue, 0)
    local resolvedMax = toNumberSafe(maxValue, resolvedMin)
    if resolvedMin > resolvedMax then
        resolvedMin, resolvedMax = resolvedMax, resolvedMin
    end

    local resolvedValue = toNumberSafe(value, resolvedMin)
    if resolvedValue < resolvedMin then
        return resolvedMin
    end
    if resolvedValue > resolvedMax then
        return resolvedMax
    end
    return resolvedValue
end

-- Format number with separators.
function Util:FormatNumber(value)
    if BreakUpLargeNumbers then
        local okBuiltin, builtInFormatted = pcall(BreakUpLargeNumbers, value)
        if okBuiltin and builtInFormatted then
            return builtInFormatted
        end
    end

    -- Run protected callback.
    local okFormat, formatted = pcall(formatAbbrevNumber, value)

    if okFormat and formatted then
        return formatted
    end

    local okString, asString = pcall(tostring, value)
    if okString and asString then
        return asString
    end

    return "?"
end

-- Return character key.
function Util:GetCharacterKey()
    local name, realm = UnitFullName("player")
    if not name then
        name = UnitName("player") or "Unknown"
    end
    realm = realm or GetRealmName() or "UnknownRealm"
    return string.format("%s-%s", name, realm)
end

-- Run when out of combat.
function Util:RunWhenOutOfCombat(fn, deferredMessage, key)
    if type(fn) ~= "function" then
        return false
    end

    if InCombatLockdown() then
        local queuedNew = true
        if type(key) == "string" and key ~= "" then
            local existingIndex = deferredQueueByKey[key]
            if existingIndex then
                deferredQueue[existingIndex] = {
                    fn = fn,
                    key = key,
                }
                queuedNew = false
            else
                deferredQueue[#deferredQueue + 1] = {
                    fn = fn,
                    key = key,
                }
                deferredQueueByKey[key] = #deferredQueue
            end
        else
            deferredQueue[#deferredQueue + 1] = {
                fn = fn,
            }
        end

        if deferredMessage and queuedNew then
            self:Print(deferredMessage)
        end
        return false
    end

    local ok, err = pcall(fn)
    if not ok then
        geterrorhandler()(err)
        return false
    end
    return true
end

ns.Util = Util
