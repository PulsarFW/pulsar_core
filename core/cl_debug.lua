-- drops literal false values so the dump isn't buried in every flag that's currently off
local function _dropFalse(t)
    local out = {}
    for k, v in pairs(t) do
        if v ~= false then
            out[k] = v
        end
    end
    return out
end

-- /checkstate - dumps this client's own plsr.State namespaces to the F8 console, for testing flag/character changes live
RegisterCommand('checkstate', function()
    local namespaces = { 'flags', 'character', 'player' }
    print('^3[checkstate] plsr.State dump for this client (false values hidden)^0')
    for i = 1, #namespaces do
        local ns = namespaces[i]
        print(('^3-- %s --^0'):format(ns))
        print(json.encode(_dropFalse(plsr.State:Get(ns)), { indent = true }))
    end
end, false)
