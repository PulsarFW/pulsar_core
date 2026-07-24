local _playerFlags   = {}
local _publicFlags   = {}  -- cross-client visible flags, indexed by source
local _pending       = {}
local _publicPending = {}
local _scheduled     = false
local _publicSched   = false

local _entityState     = {}  -- [netId] = { key = value, ... }
local _entityPending   = {}  -- [netId] = { key = value, ... }  delta batch
local _entityScheduled = false

local function _flush()
    _scheduled = false
    if not next(_pending) then return end
    local batch = _pending
    _pending = {}
    for src, flags in pairs(batch) do
        TriggerClientEvent('State:Client:ServerFlags', src, flags)
    end
end

local function _flushPublic()
    _publicSched = false
    if not next(_publicPending) then return end
    local batch = _publicPending
    _publicPending = {}
    for src, flags in pairs(batch) do
        TriggerClientEvent('State:Client:PublicFlags', -1, src, flags)
    end
end

local function _entityFlush()
    _entityScheduled = false
    if not next(_entityPending) then return end
    local batch = _entityPending
    _entityPending = {}
    for netId, data in pairs(batch) do
        TriggerClientEvent('EntityState:Client:Update', -1, netId, data)
    end
end

local function _schedule()
    if _scheduled then return end
    _scheduled = true
    CreateThread(function() Wait(0); _flush() end)
end

local function _schedulePublic()
    if _publicSched then return end
    _publicSched = true
    CreateThread(function() Wait(0); _flushPublic() end)
end

local function _entitySchedule()
    if _entityScheduled then return end
    _entityScheduled = true
    CreateThread(function() Wait(0) _entityFlush() end)
end

local function _writeFlag(source, key, value, serverOnly)
    _playerFlags[source] = _playerFlags[source] or {}
    _playerFlags[source][key] = value
    if not serverOnly then
        _pending[source] = _pending[source] or {}
        _pending[source][key] = value
        _schedule()
    end
end

local function _writePublicFlag(source, key, value)
    _playerFlags[source] = _playerFlags[source] or {}
    _playerFlags[source][key] = value
    _publicFlags[source] = _publicFlags[source] or {}
    _publicFlags[source][key] = value
    _pending[source] = _pending[source] or {}
    _pending[source][key] = value
    _schedule()
    _publicPending[source] = _publicPending[source] or {}
    _publicPending[source][key] = value
    _schedulePublic()
end

local function _playerProxy(source)
    return setmetatable({}, {
        __index = function(_, key)
            local flags = _playerFlags[source]
            return flags and flags[key]
        end,
        __newindex = function(_, key, value)
            _writeFlag(source, key, value)
        end,
    })
end

local function _clearPlayer(source)
    _playerFlags[source]   = nil
    _publicFlags[source]   = nil
    _pending[source]       = nil
    _publicPending[source] = nil
    TriggerClientEvent('State:Client:PublicFlagsCleared', -1, source)
end

local function _entityNotify(netId, data)
    TriggerEvent('EntityState:Shared:Changed', netId, data)
end

local function _entityWrite(netId, key, value)
    _entityState[netId]        = _entityState[netId]   or {}
    _entityPending[netId]      = _entityPending[netId] or {}
    _entityState[netId][key]   = value
    _entityPending[netId][key] = value
    _entitySchedule()
    _entityNotify(netId, { [key] = value })
end

local function _entityWriteMulti(netId, data)
    _entityState[netId]   = _entityState[netId]   or {}
    _entityPending[netId] = _entityPending[netId] or {}
    for k, v in pairs(data) do
        _entityState[netId][k]   = v
        _entityPending[netId][k] = v
    end
    _entitySchedule()
    _entityNotify(netId, data)
end

local function _entityDelete(netId)
    if _entityState[netId] == nil then return end
    _entityState[netId]   = nil
    _entityPending[netId] = nil
    TriggerClientEvent('EntityState:Client:Delete', -1, netId)
    TriggerEvent('EntityState:Shared:Deleted', netId)
end

local function _entityProxy(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return setmetatable({}, {
        __index = function(_, key)
            local s = _entityState[netId]
            return s and s[key]
        end,
        __newindex = function(_, key, value)
            _entityWrite(netId, key, value)
        end,
    })
end

COMPONENTS.State = {
    _name = "core",

    ---@param source     number
    ---@param key        string
    ---@param value      any
    ---@param serverOnly boolean?  don't sync to the owning client either, server-side only
    SetPlayerFlag = function(self, source, key, value, serverOnly)
        _writeFlag(source, key, value, serverOnly)
    end,

    ---@param source number
    ---@param key    string
    ---@param value  any
    SetPublicFlag = function(self, source, key, value)
        _writePublicFlag(source, key, value)
    end,

    ---@param source number
    ---@param key    string
    ---@return any
    GetPlayerFlag = function(self, source, key)
        if not _playerFlags[source] then return nil end
        return _playerFlags[source][key]
    end,

    ---@param source number
    ---@return table
    Player = function(self, source)
        return _playerProxy(source)
    end,

    --- snapshot sent to a client on spawn
    ---@return table<number, table>
    GetAllPublicFlags = function(self)
        return _publicFlags
    end,

    ---@param source number
    ClearPlayer = function(self, source)
        _clearPlayer(source)
    end,

    Entity = setmetatable({
        --- @param entity number
        --- @param key    string
        --- @return any
        Get = function(self, entity, key)
            local s = _entityState[NetworkGetNetworkIdFromEntity(entity)]
            return s and s[key]
        end,

        --- @param entity number
        --- @param key    string
        --- @param value  any
        Set = function(self, entity, key, value)
            _entityWrite(NetworkGetNetworkIdFromEntity(entity), key, value)
        end,

        ---@param entity number
        ---@param data   table
        SetMulti = function(self, entity, data)
            _entityWriteMulti(NetworkGetNetworkIdFromEntity(entity), data)
        end,

        ---@param entity number
        Delete = function(self, entity)
            _entityDelete(NetworkGetNetworkIdFromEntity(entity))
        end,

        ---@return table<number, table>
        GetAll = function(self)
            return _entityState
        end,
    }, {
        __call = function(self, entity)
            return _entityProxy(entity)
        end,
    }),
}

AddEventHandler('playerDropped', function()
    _clearPlayer(source)
end)

AddEventHandler('entityRemoved', function(entity)
    _entityDelete(NetworkGetNetworkIdFromEntity(entity))
end)

COMPONENTS.Middleware:Add('Characters:Logout', function(src)
    _clearPlayer(src)
end)

COMPONENTS.Middleware:Add('Characters:Spawning', function(src)
    if next(_publicFlags) then
        TriggerClientEvent('State:Client:PublicFlagsInit', src, _publicFlags)
    end
    if next(_entityState) then
        TriggerClientEvent('EntityState:Client:Init', src, _entityState)
    end
end)

local _clientPublicAllowlist = {
    isHospitalized = true,
    anim           = true,
    isOverdosed    = true,
    isDrunk        = true,
    GSR            = true,
    sentOffDuty    = true,
    inDutyZone     = true,
    storePoly      = true,
}

RegisterNetEvent('State:Server:SetPublicFlag')
AddEventHandler('State:Server:SetPublicFlag', function(key, value)
    if not _clientPublicAllowlist[key] then return end
    _writePublicFlag(source, key, value)
end)

RegisterNetEvent('EntityState:Server:SetClientData')
AddEventHandler('EntityState:Server:SetClientData', function(netId, key, value)
    _entityWrite(netId, key, value)
end)

RegisterNetEvent('EntityState:Server:SetClientDataMulti')
AddEventHandler('EntityState:Server:SetClientDataMulti', function(netId, data)
    _entityWriteMulti(netId, data)
end)
