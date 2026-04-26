-- ============================================================================
-- MUMMUFRAMES ADDON ENTRYPOINT
-- ============================================================================
-- Boot flow:
--   1. ADDON_LOADED -> initialize module tables and defaults.
--   2. PLAYER_LOGIN -> enable modules after Blizzard UI is fully ready.
-- Modules register themselves into ModuleManager during file load.

local addonName, ns = ...

ns = ns or {}

local addon = _G.mummuFrames or {}
_G.mummuFrames = addon

addon.name = addonName
addon.ns = ns
addon.initialized = false
addon.enabled = false

addon._moduleManager = ns.ModuleManager:New(addon)

local MECHANIC_PERF_MODULES = {
    { key = "rangeHandle", label = "Range" },
    { key = "unitFrames", label = "Unit" },
    { key = "partyFrames", label = "Party" },
    { key = "raidFrames", label = "Raid" },
    { key = "incomingCastBoard", label = "Casts" },
    { key = "dataHandle", label = "Data" },
}

local MECHANIC_PERF_EMPTY_METRIC = {
    name = "Profiler",
    ms = 0,
    description = "Counters enabled; exercise frames to collect samples.",
}

local function getSafeNowSeconds()
    if type(GetTimePreciseSec) == "function" then
        local ok, now = pcall(GetTimePreciseSec)
        if ok and type(now) == "number" then
            return now
        end
    end

    if type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then
            return now
        end
    end

    return 0
end

local function isScriptProfilingEnabled()
    if type(GetCVarBool) ~= "function" then
        return false
    end

    local ok, enabled = pcall(GetCVarBool, "scriptProfile")
    return ok and enabled == true
end

local function getAddonVersion()
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, version = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version")
        if ok and type(version) == "string" and version ~= "" then
            return version
        end
    end

    if type(GetAddOnMetadata) == "function" then
        local ok, version = pcall(GetAddOnMetadata, addonName, "Version")
        if ok and type(version) == "string" and version ~= "" then
            return version
        end
    end

    return "dev"
end

local function getCounterSnapshot(owner)
    if not owner or type(owner.GetPerfCounters) ~= "function" then
        return nil
    end

    local ok, counters = pcall(owner.GetPerfCounters, owner)
    if ok and type(counters) == "table" then
        return counters
    end

    return nil
end

local function appendCounterMetrics(metrics, moduleLabel, counters, elapsedSeconds)
    if type(counters) ~= "table" then
        return
    end

    for label, counter in pairs(counters) do
        local count = type(counter) == "table" and (tonumber(counter.count) or 0) or 0
        if type(label) == "string" and count > 0 then
            local totalMs = tonumber(counter.totalMs) or 0
            local maxMs = tonumber(counter.maxMs) or 0
            local avgMs = count > 0 and (totalMs / count) or 0
            local msPerSecond = elapsedSeconds > 0 and (totalMs / elapsedSeconds) or 0
            local callsPerSecond = elapsedSeconds > 0 and (count / elapsedSeconds) or 0

            metrics[#metrics + 1] = {
                name = moduleLabel .. ": " .. label,
                ms = msPerSecond,
                description = string.format(
                    "count=%d, %.2f calls/s, avg=%.3f ms, max=%.3f ms, total=%.2f ms",
                    count,
                    callsPerSecond,
                    avgMs,
                    maxMs,
                    totalMs
                ),
            }
        end
    end
end

-- Register module in module manager.
function addon:RegisterModule(name, moduleTable)
    return self._moduleManager:Register(name, moduleTable)
end

-- Return module from module manager.
function addon:GetModule(name)
    return self._moduleManager:Get(name)
end

-- Initialize addon modules once.
function addon:Init()
    if self.initialized then
        return
    end

    self._moduleManager:InitializeAll(self)
    self.initialized = true
end

-- Enable initialized addon modules.
function addon:Enable()
    if self.enabled then
        return
    end

    self._moduleManager:EnableAll()
    self.enabled = true
    self:RegisterMechanicBridge()
    if isScriptProfilingEnabled() then
        self:SetMechanicPerfCountersEnabled(true, true)
    end
end

-- Disable enabled addon modules.
function addon:Disable()
    if not self.enabled then
        return
    end

    self._moduleManager:DisableAll()
    self.enabled = false
end

-- Open addon configuration panel.
function addon:OpenConfig()
    local config = self:GetModule("configuration")
    if config and type(config.OpenConfig) == "function" then
        config:OpenConfig()
    end
end

-- Enable or reset every module-owned counter that can feed Mechanic.
function addon:SetMechanicPerfCountersEnabled(enabled, resetExisting)
    for index = 1, #MECHANIC_PERF_MODULES do
        local module = self:GetModule(MECHANIC_PERF_MODULES[index].key)
        if module and type(module.SetPerfCountersEnabled) == "function" then
            module:SetPerfCountersEnabled(enabled, resetExisting)
        end
    end

    if ns.AuraHandle and type(ns.AuraHandle.SetPerfCountersEnabled) == "function" then
        ns.AuraHandle:SetPerfCountersEnabled(enabled, resetExisting)
    end

    self._mechanicPerfCountersEnabled = enabled == true
    if resetExisting ~= false then
        self._mechanicPerfStartedAt = getSafeNowSeconds()
    elseif not self._mechanicPerfStartedAt then
        self._mechanicPerfStartedAt = getSafeNowSeconds()
    end
end

-- Reset and leave counters enabled for a fresh profiling window.
function addon:ResetMechanicPerformanceCounters()
    self:SetMechanicPerfCountersEnabled(true, true)
end

function addon:EnsureMechanicPerformanceCounters()
    if self._mechanicPerfCountersEnabled ~= true then
        self:SetMechanicPerfCountersEnabled(true, true)
    end
end

function addon:GetMechanicPerformanceSubMetrics()
    self:EnsureMechanicPerformanceCounters()

    local now = getSafeNowSeconds()
    local startedAt = tonumber(self._mechanicPerfStartedAt) or now
    local elapsedSeconds = now - startedAt
    if elapsedSeconds <= 0 then
        elapsedSeconds = 1
    end

    local metrics = {}
    for index = 1, #MECHANIC_PERF_MODULES do
        local moduleConfig = MECHANIC_PERF_MODULES[index]
        appendCounterMetrics(
            metrics,
            moduleConfig.label,
            getCounterSnapshot(self:GetModule(moduleConfig.key)),
            elapsedSeconds
        )
    end

    appendCounterMetrics(metrics, "Aura", getCounterSnapshot(ns.AuraHandle), elapsedSeconds)

    table.sort(metrics, function(left, right)
        local leftMs = tonumber(left.ms) or 0
        local rightMs = tonumber(right.ms) or 0
        if leftMs == rightMs then
            return tostring(left.name or "") < tostring(right.name or "")
        end
        return leftMs > rightMs
    end)

    if #metrics == 0 then
        return { MECHANIC_PERF_EMPTY_METRIC }
    end

    return metrics
end

function addon:RegisterMechanicBridge()
    if self._mechanicBridgeRegistered == true then
        return true
    end

    local libStub = _G.LibStub
    if not libStub then
        return false
    end

    local mechanicLib = libStub("MechanicLib-1.0", true)
    if not mechanicLib or type(mechanicLib.Register) ~= "function" then
        return false
    end

    mechanicLib:Register(addonName, {
        version = getAddonVersion(),
        performance = {
            getSubMetrics = function()
                return addon:GetMechanicPerformanceSubMetrics()
            end,
            reset = function()
                addon:ResetMechanicPerformanceCounters()
            end,
        },
    })

    self._mechanicBridgeRegistered = true
    return true
end

SLASH_MUMMUFRAMES1 = "/mmf"
-- Handle slash command callback.
SlashCmdList.MUMMUFRAMES = function()
    addon:OpenConfig()
end

-- Create frame for loader.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
-- Handle OnEvent script callback.
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:Init()
        return
    end

    if event == "PLAYER_LOGIN" and addon.initialized then
        addon:Enable()
    end
end)
