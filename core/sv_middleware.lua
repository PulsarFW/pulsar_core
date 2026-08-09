local _middlewares = {}

local _ignored = {
    pac_os = true,
    pac_iec = true,
    ["screenshot-basic"] = true,
}

AddEventHandler('onResourceStart', function(resource)
    if COMPONENTS.Proxy.ExportsReady and not _ignored[resource] then
        if resource ~= GetCurrentResourceName() then
            for event, handlers in pairs(_middlewares) do
                for i = #handlers, 1, -1 do
                    if handlers[i].resource == resource then
                        table.remove(handlers, i)
                    end
                end
                if #handlers == 0 then
                    _middlewares[event] = nil
                end
            end
            collectgarbage()
        end
    end
end)

COMPONENTS.Middleware = {
    TriggerEvent = function(self, event, source, ...)
        if _middlewares[event] then
            for k, v in pairs(_middlewares[event]) do
                v.cb(source, ...)
            end
        end
    end,
	TriggerEventWithData = function(self, event, source, ...)
        local data = {}
        if _middlewares[event] then
            for k, v in pairs(_middlewares[event]) do
				for k2, v2 in ipairs(v.cb(source, ...)) do
					v2.ID = #data + 1
					table.insert(data, v2)
				end
            end
			table.sort(data, function(a,b) return a.ID < b.ID end)
        end
		return data
	end,
    Add = function(self, event, cb, prio)
        if prio == nil then
            prio = 1
        end

        if _middlewares[event] == nil then
            _middlewares[event] = {}
        end

        table.insert(_middlewares[event], { cb = cb, prio = prio, resource = GetInvokingResource() })
        table.sort(_middlewares[event], function(a, b) return a.prio < b.prio end)
    end
}