local _cache = {}

-- RegisterComponent fires this on every (re)register (see sh_proxy.lua), drop the cache entry so the next access re-fetches - self-heals a hot-reloaded dependency automatically
AddEventHandler("Proxy:Shared:ExtendReady", function(component)
	_cache[component] = nil
end)

-- FetchComponent crosses a resource export boundary and drops any metatable dot-sugar proxy (State.flags, State:Player(), State.Entity()) - rebuilt locally here since this file is a shared_script and runs inside each consuming resource's own Lua state
local function _localizeStateServer(state)
	local getPlayerFlag = state.GetPlayerFlag
	local setPlayerFlag = state.SetPlayerFlag
	local entity         = state.Entity
	local entitySet       = entity.Set
	local entitySetMulti  = entity.SetMulti
	local entityDelete    = entity.Delete
	local entityGetAll    = entity.GetAll

	-- same local-mirror technique as the client fix below, seeded once and synced via a local TriggerEvent pulsar_core fires on every entity write/delete
	local _entityState = {}
	do
		local snapshot = entityGetAll(entity) or {}
		for netId, data in pairs(snapshot) do
			_entityState[netId] = {}
			for k, v in pairs(data) do
				_entityState[netId][k] = v
			end
		end
	end

	AddEventHandler('EntityState:Shared:Changed', function(netId, data)
		_entityState[netId] = _entityState[netId] or {}
		for k, v in pairs(data) do
			_entityState[netId][k] = v
		end
	end)

	AddEventHandler('EntityState:Shared:Deleted', function(netId)
		_entityState[netId] = nil
	end)

	state.Player = function(self, source)
		return setmetatable({}, {
			__index = function(_, key)
				return getPlayerFlag(state, source, key)
			end,
			__newindex = function(_, key, value)
				setPlayerFlag(state, source, key, value)
			end,
		})
	end

	state.Entity = setmetatable({
		Get = function(self, e, key)
			local s = _entityState[NetworkGetNetworkIdFromEntity(e)]
			return s and s[key]
		end,
		SetMulti = function(self, e, data)
			local netId = NetworkGetNetworkIdFromEntity(e)
			_entityState[netId] = _entityState[netId] or {}
			for k, v in pairs(data) do
				_entityState[netId][k] = v
			end
			entitySetMulti(entity, e, data)
		end,
		Delete = function(self, e)
			_entityState[NetworkGetNetworkIdFromEntity(e)] = nil
			entityDelete(entity, e)
		end,
	}, {
		__call = function(self, e)
			local netId = NetworkGetNetworkIdFromEntity(e)
			return setmetatable({}, {
				__index = function(_, key)
					local s = _entityState[netId]
					return s and s[key]
				end,
				__newindex = function(_, key, value)
					_entityState[netId] = _entityState[netId] or {}
					_entityState[netId][key] = value
					entitySet(entity, e, key, value)
				end,
			})
		end,
	})

	return state
end

-- profiled 2026-07: flags/character reads from outside pulsar_core were a live cross-resource call, ~114us/call, 7.1s total across 62795 calls - now a local mirror synced via the same net events cl_state.lua listens to
local function _localizeStateClient(state)
	local get                 = state.Get
	local setClientFlag       = state.SetClientFlag
	local setPublicClientFlag = state.SetPublicClientFlag
	local getPublicFlag       = state.GetPublicFlag
	local setCharacterData    = state.SetCharacterData
	local entity               = state.Entity
	local entitySet            = entity.Set
	local entitySetMulti       = entity.SetMulti
	local entityWatchKey       = entity.WatchKey
	local entityGetAll         = entity.GetAll

	-- one-time real fetch per resource, not per read - safe to keep and mutate locally from here on
	local _flags     = get(state, 'flags') or {}
	local _character = get(state, 'character') or {}
	local _player     = get(state, 'player') or {}
	local _mirrors    = { flags = _flags, character = _character, player = _player }

	-- pulsar_core's _set/_populate/_clear fire these on every change regardless of what triggered it, listening for specific event names instead missed anything not on that exact list
	AddEventHandler('State:Shared:Changed', function(namespace, key, value)
		local ns = _mirrors[namespace]
		if ns then
			ns[key] = value
		end
	end)

	AddEventHandler('State:Shared:Populated', function(namespace, data)
		local ns = _mirrors[namespace]
		if ns then
			for k, v in pairs(data) do
				ns[k] = v
			end
		end
	end)

	AddEventHandler('State:Shared:Cleared', function(namespace)
		local ns = _mirrors[namespace]
		if ns then
			for k in pairs(ns) do
				ns[k] = nil
			end
		end
	end)

	-- same local-mirror technique, applied to entity state - synced via the same EntityState:Client:Init/Update/Delete events cl_state.lua listens to
	local _entityCache = {}
	do
		local snapshot = entityGetAll(entity) or {}
		for netId, data in pairs(snapshot) do
			_entityCache[netId] = {}
			for k, v in pairs(data) do
				_entityCache[netId][k] = v
			end
		end
	end

	RegisterNetEvent('EntityState:Client:Init')
	AddEventHandler('EntityState:Client:Init', function(snapshot)
		_entityCache = {}
		for netId, data in pairs(snapshot) do
			_entityCache[netId] = {}
			for k, v in pairs(data) do
				_entityCache[netId][k] = v
			end
		end
	end)

	RegisterNetEvent('EntityState:Client:Update')
	AddEventHandler('EntityState:Client:Update', function(netId, data)
		_entityCache[netId] = _entityCache[netId] or {}
		for k, v in pairs(data) do
			_entityCache[netId][k] = v
		end
	end)

	RegisterNetEvent('EntityState:Client:Delete')
	AddEventHandler('EntityState:Client:Delete', function(netId)
		_entityCache[netId] = nil
	end)

	state.Get = function(self, namespace, key)
		local ns = _mirrors[namespace]
		if not ns then return get(state, namespace, key) end
		if key then return ns[key] end
		return ns
	end

	state.flags = setmetatable({}, {
		__index = function(_, key)
			return _flags[key]
		end,
		__newindex = function(_, key, value)
			_flags[key] = value
			setClientFlag(state, key, value)
		end,
	})

	state.character = setmetatable({}, {
		__index = function(_, key)
			return _character[key]
		end,
		__newindex = function(_, key)
			error(string.format("cannot set '%s' via State.character - it's read-only, use State:SetCharacterData", key), 2)
		end,
	})

	state.player = setmetatable({}, {
		__index = function(_, key)
			return _player[key]
		end,
		__newindex = function(_, key)
			error(string.format("cannot set '%s' via State.player - it's read-only, populated from the server on connect", key), 2)
		end,
	})

	state.SetClientFlag = function(self, key, value)
		_flags[key] = value
		setClientFlag(state, key, value)
	end

	state.SetPublicClientFlag = function(self, key, value)
		_flags[key] = value
		setPublicClientFlag(state, key, value)
	end

	state.SetCharacterData = function(self, key, data)
		if key == -1 then
			for k in pairs(_character) do _character[k] = nil end
			for k, v in pairs(data) do _character[k] = v end
		else
			_character[key] = data
		end
		setCharacterData(state, key, data)
	end

	state.PublicPlayer = function(self, serverId)
		return setmetatable({}, {
			__index = function(_, key)
				return getPublicFlag(state, serverId, key)
			end,
		})
	end

	state.Entity = setmetatable({
		Get = function(self, e, key)
			local s = _entityCache[NetworkGetNetworkIdFromEntity(e)]
			return s and s[key]
		end,
		WatchKey = function(self, key, callback)
			entityWatchKey(entity, key, callback)
		end,
		SetMulti = function(self, e, data)
			local netId = NetworkGetNetworkIdFromEntity(e)
			_entityCache[netId] = _entityCache[netId] or {}
			for k, v in pairs(data) do
				_entityCache[netId][k] = v
			end
			entitySetMulti(entity, e, data)
		end,
	}, {
		__call = function(self, e)
			local netId = NetworkGetNetworkIdFromEntity(e)
			return setmetatable({}, {
				__index = function(_, key)
					local s = _entityCache[netId]
					return s and s[key]
				end,
				__newindex = function(_, key, value)
					_entityCache[netId] = _entityCache[netId] or {}
					_entityCache[netId][key] = value
					entitySet(entity, e, key, value)
				end,
			})
		end,
	})

	return state
end

local _localizers = {
	State = IsDuplicityVersion() and _localizeStateServer or _localizeStateClient,
}

-- exports[...]:FetchComponent still marshals even for a resource calling its own export, stripping proxy metatables - pulsar_core reads COMPONENTS[key] directly instead, same Lua VM, no exports call
plsr = setmetatable({}, {
	__index = function(_, key)
		local c = _cache[key]
		if c ~= nil then
			return c
		end

		if GetCurrentResourceName() == "pulsar_core" then
			local attempts = 0
			while COMPONENTS[key] == nil and attempts < 100 do
				Wait(50)
				attempts += 1
			end
			c = COMPONENTS[key]
			if c == nil then
				error(("plsr.%s never became available (5s timeout)"):format(key), 2)
			end
			_cache[key] = c
			return c
		end

		local attempts = 0
		while not exports["pulsar_core"]:HasComponent(key) and attempts < 100 do
			Wait(50)
			attempts += 1
		end

		-- one real (warning-on-miss) fetch - silent while HasComponent's polling above, still logs+errors below on genuine timeout instead of going silent about a missing dep
		c = exports["pulsar_core"]:FetchComponent(key)

		if c == nil then
			error(("plsr.%s never became available (5s timeout) — is its resource started?"):format(key), 2)
		end

		if _localizers[key] then
			c = _localizers[key](c)
		end

		_cache[key] = c
		return c
	end,
	__newindex = function()
		error("plsr is read-only; register components via exports['pulsar_core']:RegisterComponent", 2)
	end,
})
