local _, ns = ...

-- Create class holding event router behavior.
local EventRouter = ns.Object:Extend()

-- Initialize event router state.
function EventRouter:Constructor()
    -- Create frame widget.
    self.frame = CreateFrame("Frame")
    -- Create table holding events.
    self.events = {}
    -- Create table holding reusable dispatch snapshot.
    self._dispatchScratch = {}
    self._dispatchScratchCount = 0

    -- Handle OnEvent script callback.
    self.frame:SetScript("OnEvent", function(_, event, ...)
        self:Dispatch(event, ...)
    end)
end

-- Register event listener for owner.
function EventRouter:Register(owner, eventName, handler)
    if not owner or type(eventName) ~= "string" or type(handler) ~= "function" then
        return
    end

    local list = self.events[eventName]
    if not list then
        -- Create table holding list.
        list = {}
        self.events[eventName] = list
        self.frame:RegisterEvent(eventName)
    end

    for _, entry in ipairs(list) do
        if entry.owner == owner and entry.handler == handler then
            return
        end
    end

    table.insert(list, {
        owner = owner,
        handler = handler,
    })
end

-- Remove all listeners for owner.
function EventRouter:UnregisterOwner(owner)
    for eventName, list in pairs(self.events) do
        local i = 1
        while i <= #list do
            if list[i].owner == owner then
                table.remove(list, i)
            else
                i = i + 1
            end
        end

        if #list == 0 then
            self.events[eventName] = nil
            self.frame:UnregisterEvent(eventName)
        end
    end
end

-- Dispatch event to registered listeners.
function EventRouter:Dispatch(eventName, ...)
    local list = self.events[eventName]
    if not list then
        return
    end

    local count = #list
    if count == 1 then
        local entry = list[1]
        if entry and entry.owner and entry.handler then
            local ok, err = pcall(entry.handler, entry.owner, eventName, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
        return
    end

    -- Reuse dispatch snapshot table to avoid per-event allocations.
    local snapshot = self._dispatchScratch
    local previousCount = self._dispatchScratchCount or 0
    for i = 1, count do
        snapshot[i] = list[i]
    end
    if previousCount > count then
        for i = count + 1, previousCount do
            snapshot[i] = nil
        end
    end
    self._dispatchScratchCount = count

    for i = 1, count do
        local entry = snapshot[i]
        if entry and entry.owner and entry.handler then
            local ok, err = pcall(entry.handler, entry.owner, eventName, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end

ns.EventRouter = EventRouter:New()
