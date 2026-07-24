local _cache = {
    player    = {},
    character = {},
    flags     = {
        loggedIn = false,
        ped      = 0,
        position = vector3(0.0, 0.0, 0.0),
    },
}

local _watchers       = {}
local _publicFlags    = {}
local _entityCache    = {}  -- [netId] = { key = value, ... }
local _entityWatchers = {}  -- [key] = { callback, ... }, fires for that key changing on ANY entity

local function _fireWatchers(namespace, key, value, old)
    local ns = _watchers[namespace]
    if not ns then return end
    local kw = ns[key]
    if kw then
        for i = 1, #kw do kw[i](value, old) end
    end
    local nw = ns['*']
    if nw then
        for i = 1, #nw do nw[i](_cache[namespace]) end
    end
end

local function _set(namespace, key, value)
    local ns = _cache[namespace]
    if not ns then return end
    local old = ns[key]
    if old == value then return end
    ns[key] = value
    _fireWatchers(namespace, key, value, old)
    TriggerEvent('State:Shared:Changed', namespace, key, value)
end

local _flagsProxy = setmetatable({}, {
    __index = function(_, key)
        return _cache.flags[key]
    end,
    __newindex = function(_, key, value)
        _set('flags', key, value)
    end,
})

local function _publicPlayerProxy(serverId)
    return setmetatable({}, {
        __index = function(_, key)
            local pf = _publicFlags[serverId]
            return pf and pf[key]
        end,
        __newindex = function(_, key, value)
            error(string.format("cannot set '%s' via State:PublicPlayer(%s) - public flags are written by their owner or the server, not read here", key, tostring(serverId)), 2)
        end,
    })
end

local function _fireEntityWatchers(key, netId, value, old)
    local kw = _entityWatchers[key]
    if not kw then return end
    for i = 1, #kw do kw[i](netId, value, old) end
end

-- dedup + cache + fire, shared by the local proxy write and incoming server updates
local function _entitySet(netId, key, value)
    _entityCache[netId] = _entityCache[netId] or {}
    local old = _entityCache[netId][key]
    if old == value then return end
    _entityCache[netId][key] = value
    _fireEntityWatchers(key, netId, value, old)
end

local function _entitySetMulti(netId, data)
    for k, v in pairs(data) do
        _entitySet(netId, k, v)
    end
end

local function _entityProxy(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return setmetatable({}, {
        __index = function(_, key)
            local s = _entityCache[netId]
            return s and s[key]
        end,
        __newindex = function(_, key, value)
            _entitySet(netId, key, value)
            TriggerServerEvent('EntityState:Server:SetClientData', netId, key, value)
        end,
    })
end

local function _populate(namespace, data)
    local ns = _cache[namespace]
    if not ns then return end
    local changed = {}
    local hasChanges = false
    for k, v in pairs(data) do
        local old = ns[k]
        if old ~= v then
            ns[k] = v
            changed[k] = v
            hasChanges = true
            _fireWatchers(namespace, k, v, old)
        end
    end
    if hasChanges then
        TriggerEvent('State:Shared:Populated', namespace, changed)
    end
end

local function _clear(namespace)
    local ns = _cache[namespace]
    if not ns then return end
    for k, v in pairs(ns) do
        ns[k] = nil
        _fireWatchers(namespace, k, nil, v)
    end
    TriggerEvent('State:Shared:Cleared', namespace)
end

-- populate player namespace on connect (server sends source, accountID, name, groups)
AddEventHandler('Player:Client:SetData', function(data)
    _populate('player', {
        serverID  = data.Source,
        accountID = data.AccountID,
        name      = data.Name,
        groups    = data.Groups,
        id        = data.ID,
    })
end)

local function _setCharacterData(key, data)
    if key == -1 then
        _populate('character', data)
    else
        _set('character', key, data)
    end
end

-- full character set (key = -1) or individual key delta from server
RegisterNetEvent('Characters:Client:SetData')
AddEventHandler('Characters:Client:SetData', function(key, data)
    _setCharacterData(key, data)
end)

-- character is in the world, mark logged in, seed ped if not yet set
RegisterNetEvent('Characters:Client:Spawned')
AddEventHandler('Characters:Client:Spawned', function()
    _set('flags', 'loggedIn', true)
    if _cache.flags.ped == 0 then
        _set('flags', 'ped', PlayerPedId())
    end
end)

-- character selected character screen / logout, clear character and entity state
RegisterNetEvent('Characters:Client:Logout')
AddEventHandler('Characters:Client:Logout', function()
    _set('flags', 'loggedIn', false)
    _clear('character')
    _entityCache = {}
end)

COMPONENTS.State = {
    _name      = 'core',
    _protected = true,

    -- plsr.State.flags.someFlag / plsr.State.flags.someFlag = value (own player, private write)
    flags     = _flagsProxy,
    player    = _cache.player,
    character = _cache.character,

    --- explicit character-cache write for pulsar_characters, avoids cross-resource event order
    ---@param key  number|string  -1 for a full set, otherwise a single key
    ---@param data any
    SetCharacterData = function(self, key, data)
        _setCharacterData(key, data)
    end,

    --- read a namespace or a specific key within it
    ---@param namespace string  'player' | 'character' | 'flags'
    ---@param key?      string  Key within the namespace; omit to return the whole table
    ---@return any
    Get = function(self, namespace, key)
        local ns = _cache[namespace]
        if not ns then return nil end
        if key then return ns[key] end
        return ns
    end,

    --- subscribe to changes on a key, always fires immediately with the current value
    --- (nil if nothing's set it yet), then again on every future change - use '*' as key
    --- to watch any change in the namespace, callback gets the whole namespace table
    ---@param namespace string
    ---@param key       string                    Key to watch, or '*' for namespace-wide changes
    ---@param callback  fun(value: any, old: any)
    Watch = function(self, namespace, key, callback)
        local ns = _cache[namespace]
        if not ns then return end
        _watchers[namespace] = _watchers[namespace] or {}
        _watchers[namespace][key] = _watchers[namespace][key] or {}
        table.insert(_watchers[namespace][key], callback)
        if key == '*' then
            callback(ns)
        else
            callback(ns[key], nil)
        end
    end,

    SetClientFlag = function(self, key, value) _set('flags', key, value) end,

    ---@param key   string
    ---@param value any
    SetPublicClientFlag = function(self, key, value)
        _set('flags', key, value)
        TriggerServerEvent('State:Server:SetPublicFlag', key, value)
    end,

    --- read a public flag for another player (set via State:SetPublicFlag on server)
    ---@param serverId number  The server ID of the other player
    ---@param key      string
    ---@return any
    GetPublicFlag = function(self, serverId, key)
        local pf = _publicFlags[serverId]
        return pf and pf[key]
    end,

    --- plsr.State:PublicPlayer(serverId).someFlag - read-only, like the old Player(serverId).state.X
    --- same data as GetPublicFlag
    ---@param serverId number
    PublicPlayer = function(self, serverId)
        return _publicPlayerProxy(serverId)
    end,

    --- read all public flags for another player
    ---@param serverId number
    ---@return table
    GetAllPublicFlags = function(self, serverId)
        return _publicFlags[serverId] or {}
    end,

    Entity = setmetatable({
        --- @param entity number
        --- @param key    string
        --- @return any
        Get = function(self, entity, key)
            local s = _entityCache[NetworkGetNetworkIdFromEntity(entity)]
            return s and s[key]
        end,

        ---@param entity number
        ---@param key    string
        ---@param value  any
        Set = function(self, entity, key, value)
            local netId = NetworkGetNetworkIdFromEntity(entity)
            _entitySet(netId, key, value)
            TriggerServerEvent('EntityState:Server:SetClientData', netId, key, value)
        end,

        ---@param entity number
        ---@param data   table
        SetMulti = function(self, entity, data)
            local netId = NetworkGetNetworkIdFromEntity(entity)
            _entitySetMulti(netId, data)
            TriggerServerEvent('EntityState:Server:SetClientDataMulti', netId, data)
        end,

        --- fires for every entity when `key` changes, whether written locally or by another
        --- client - like the old AddStateBagChangeHandler(key, nil, fn), does NOT fire retroactively
        --- for existing values, only future changes
        ---@param key      string
        ---@param callback fun(netId: number, value: any, old: any)
        WatchKey = function(self, key, callback)
            _entityWatchers[key] = _entityWatchers[key] or {}
            table.insert(_entityWatchers[key], callback)
        end,

        --- full snapshot of this client's entity-state cache - used once by sh_pulsar.lua to seed
        --- each resource's own local mirror, don't call this on every read
        ---@return table<number, table>
        GetAll = function(self)
            return _entityCache
        end,
    }, {
        __call = function(self, entity)
            return _entityProxy(entity)
        end,
    }),
}

RegisterNetEvent('State:Client:ServerFlags')
AddEventHandler('State:Client:ServerFlags', function(flags)
    for key, value in pairs(flags) do
        _set('flags', key, value)
    end
end)

-- batch update of another player's public flags (cross-client visibility)
RegisterNetEvent('State:Client:PublicFlags')
AddEventHandler('State:Client:PublicFlags', function(serverId, flags)
    _publicFlags[serverId] = _publicFlags[serverId] or {}
    for k, v in pairs(flags) do
        _publicFlags[serverId][k] = v
    end
end)

-- full snapshot sent to this client on spawn so cross-player state is immediately correct
RegisterNetEvent('State:Client:PublicFlagsInit')
AddEventHandler('State:Client:PublicFlagsInit', function(allFlags)
    _publicFlags = {}
    for sid, flags in pairs(allFlags) do
        _publicFlags[sid] = flags
    end
end)

-- clean up when another player leaves
RegisterNetEvent('State:Client:PublicFlagsCleared')
AddEventHandler('State:Client:PublicFlagsCleared', function(serverId)
    _publicFlags[serverId] = nil
end)

-- entity state net events
RegisterNetEvent('EntityState:Client:Init')
AddEventHandler('EntityState:Client:Init', function(snapshot)
    _entityCache = {}
    for netId, data in pairs(snapshot) do
        for k, v in pairs(data) do
            _entitySet(netId, k, v)
        end
    end
end)

RegisterNetEvent('EntityState:Client:Update')
AddEventHandler('EntityState:Client:Update', function(netId, data)
    for k, v in pairs(data) do
        _entitySet(netId, k, v)
    end
end)

RegisterNetEvent('EntityState:Client:Delete')
AddEventHandler('EntityState:Client:Delete', function(netId)
    _entityCache[netId] = nil
end)
