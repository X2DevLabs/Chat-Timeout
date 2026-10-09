local added = {}

-- Ask the server which commands this player is allowed to see
CreateThread(function()
    Wait(2000)
    TriggerServerEvent('chattimeout:ready')
end)

RegisterNetEvent('chattimeout:suggestions', function(list)
    for _, s in ipairs(list) do
        TriggerEvent('chat:addSuggestion', s.name, s.help, s.params or {})
        added[#added + 1] = s.name
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, name in ipairs(added) do
        TriggerEvent('chat:removeSuggestion', name)
    end
end)
