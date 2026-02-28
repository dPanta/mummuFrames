-- ============================================================================
-- AURA SAFETY HELPERS
-- ============================================================================
-- Centralizes secret-aura guards for Retail combat restrictions.
-- All callers should route aura payload reads through this module when possible.

local _, ns = ...

local AuraSafety = {}

local PLAYER_HELPFUL_FILTER = "HELPFUL|PLAYER|RAID_IN_COMBAT"
local MAX_AURA_SCAN         = 80

-- Coerce any numeric-like input to a positive integer ID.
local function normalizePositiveInteger(self, value)
    local numeric = self:SafeNumber(value, nil)
    if type(numeric) ~= "number" then
        return nil
    end
    local rounded = math.floor(numeric + 0.5)
    if rounded <= 0 then
        return nil
    end
    return rounded
end

-- Safely evaluate truthy values that may be secret/tainted wrappers.
function AuraSafety:SafeTruthy(value)
    local ok, boolValue = pcall(function()
        if value then
            return true
        end
        return false
    end)
    if ok then
        return boolValue
    end
    return false
end

-- Convert value to number without propagating secret-value errors.
function AuraSafety:SafeNumber(value, fallback)
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

    local okTonumber, coerced = pcall(tonumber, value)
    if okTonumber and type(coerced) == "number" then
        return coerced
    end

    return fallback
end

-- Returns true when a specific aura index is secret for the given unit/filter.
-- Fail-closed: API errors are treated as secret.
function AuraSafety:IsAuraIndexSecret(unitToken, index, filter)
    if type(unitToken) ~= "string" or unitToken == "" then
        return true
    end
    local normalizedIndex = normalizePositiveInteger(self, index)
    if not normalizedIndex then
        return true
    end
    if not (C_Secrets and type(C_Secrets.ShouldUnitAuraIndexBeSecret) == "function") then
        return false
    end

    local ok, isSecret = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unitToken, normalizedIndex, filter)
    if not ok then
        return true
    end
    return self:SafeTruthy(isSecret)
end

-- Returns true when a specific aura instance ID is secret for the given unit.
-- Fail-closed: API errors are treated as secret.
function AuraSafety:IsAuraInstanceSecret(unitToken, auraInstanceID)
    if type(unitToken) ~= "string" or unitToken == "" then
        return true
    end
    local normalizedAuraInstanceID = normalizePositiveInteger(self, auraInstanceID)
    if not normalizedAuraInstanceID then
        return true
    end
    if not (C_Secrets and type(C_Secrets.ShouldUnitAuraInstanceBeSecret) == "function") then
        return false
    end

    local ok, isSecret = pcall(C_Secrets.ShouldUnitAuraInstanceBeSecret, unitToken, normalizedAuraInstanceID)
    if not ok then
        return true
    end
    return self:SafeTruthy(isSecret)
end

-- Secret-safe wrapper around C_UnitAuras.GetAuraDataByIndex.
-- Returns nil for secret/invalid indexes or non-existent auras.
function AuraSafety:GetAuraDataByIndexSafe(unitToken, index, filter)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return nil
    end
    local normalizedIndex = normalizePositiveInteger(self, index)
    if not normalizedIndex then
        return nil
    end
    if self:IsAuraIndexSecret(unitToken, normalizedIndex, filter) then
        return nil
    end

    local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, normalizedIndex, filter)
    if type(auraData) ~= "table" then
        return nil
    end

    local auraInstanceID = normalizePositiveInteger(self, auraData.auraInstanceID)
    if auraInstanceID and self:IsAuraInstanceSecret(unitToken, auraInstanceID) then
        return nil
    end

    return auraData
end

-- Secret-safe wrapper around C_UnitAuras.GetAuraDataByAuraInstanceID.
-- Returns nil when the instance is secret or unavailable.
function AuraSafety:GetAuraDataByInstanceIDSafe(unitToken, auraInstanceID)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function") then
        return nil
    end
    local normalizedAuraInstanceID = normalizePositiveInteger(self, auraInstanceID)
    if not normalizedAuraInstanceID then
        return nil
    end
    if self:IsAuraInstanceSecret(unitToken, normalizedAuraInstanceID) then
        return nil
    end

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, normalizedAuraInstanceID)
    if not ok or type(auraData) ~= "table" then
        return nil
    end

    local returnedAuraInstanceID = normalizePositiveInteger(self, auraData.auraInstanceID)
    if returnedAuraInstanceID and self:IsAuraInstanceSecret(unitToken, returnedAuraInstanceID) then
        return nil
    end

    return auraData
end

-- Returns player's non-secret auraData for spellID, or nil.
-- Second return value indicates whether secret filtering hid matching data.
function AuraSafety:GetPlayerAuraBySpellIDSafe(spellID)
    local normalizedSpellID = normalizePositiveInteger(self, spellID)
    if not normalizedSpellID then
        return nil, false
    end

    if C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, normalizedSpellID)
        if ok and type(auraData) == "table" then
            local auraInstanceID = normalizePositiveInteger(self, auraData.auraInstanceID)
            if auraInstanceID and self:IsAuraInstanceSecret("player", auraInstanceID) then
                return nil, true
            end
            return auraData, false
        end
    end

    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return nil, false
    end

    local encounteredSecret = false
    for index = 1, MAX_AURA_SCAN do
        if self:IsAuraIndexSecret("player", index, PLAYER_HELPFUL_FILTER) then
            encounteredSecret = true
        else
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", index, PLAYER_HELPFUL_FILTER)
            if type(auraData) ~= "table" then
                break
            end

            local auraSpellID = normalizePositiveInteger(self, auraData.spellId)
            if auraSpellID and auraSpellID == normalizedSpellID then
                local auraInstanceID = normalizePositiveInteger(self, auraData.auraInstanceID)
                if auraInstanceID and self:IsAuraInstanceSecret("player", auraInstanceID) then
                    encounteredSecret = true
                else
                    return auraData, false
                end
            end
        end
    end

    return nil, encounteredSecret
end

ns.AuraSafety = AuraSafety
