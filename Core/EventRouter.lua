local _, ns = ...

local EventRouter = ns.Object:Extend()

-- Create the hidden event frame and hook its dispatcher.
function EventRouter:Constructor()
    self.frame = CreateFrame("Frame")
    self.events = {}

    -- Forward frame events into the router dispatcher.
    self.frame:SetScript("OnEvent", function(_, event, ...)
        self:Dispatch(event, ...)
    end)
end

-- Register an owner callback for a specific game event.
function EventRouter:Register(owner, eventName, handler)
    if not owner or type(eventName) ~= "string" or type(handler) ~= "function" then
        return
    end

    -- Lazily create each event list and subscribe the frame once.
    local list = self.events[eventName]
    if not list then
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

-- Remove all event handlers that belong to this owner.
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

        -- Unsubscribe events that no longer have listeners.
        if #list == 0 then
            self.events[eventName] = nil
            self.frame:UnregisterEvent(eventName)
        end
    end
end

-- Dispatch one event to all handlers registered for it.
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

    -- Use a snapshot so handlers can modify registrations safely.
    local snapshot = {}
    for i = 1, count do
        snapshot[i] = list[i]
    end

    -- Guard each callback so one error does not break the router.
    for i = 1, #snapshot do
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
