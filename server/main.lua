Store.Load()

local msgLog = {}      -- [source] = recent message times (ms), used for the spam check
local lastNotice = {}  -- [source] = last time we told them they're timed out (ms)
local hookActive = false

local COLORS = {
    error   = { 255, 80, 80 },
    success = { 80, 220, 120 },
    warning = { 255, 190, 60 },
    inform  = { 100, 170, 255 }
}

-- Pseudo-roles for the console and for automatic actions
local CONSOLE_ACTOR = {
    src = 0, name = 'Console', level = 999,
    role = { name = 'Console', permanent = true, canLift = 'any', canView = true, canHistory = true }
}
local SYSTEM_ACTOR = {
    src = -1, name = 'AutoMod', level = 999,
    role = { name = 'System', permanent = true }
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function Notify(src, message, kind)
    kind = kind or 'inform'

    if src == 0 then
        print(('[chat-timeout] %s'):format(message))
        return
    end

    if Config.Notify == 'ox_lib' then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Chat Timeout', description = message, type = kind, duration = 7000
        })
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = COLORS[kind] or COLORS.inform,
            multiline = true,
            args = { 'Chat Timeout', message }
        })
    end
end

-- Highest role the player has, and its rank (1 = lowest). Returns nil, 0 if none.
local function GetRole(src)
    for i = #Config.Roles, 1, -1 do
        local role = Config.Roles[i]
        if IsPlayerAceAllowed(src, role.ace) then
            return role, i
        end
    end
    return nil, 0
end

-- Who is running a command. nil = not allowed to use staff commands.
local function GetActor(src)
    if src == 0 then return CONSOLE_ACTOR end

    local role, level = GetRole(src)
    if not role then return nil end

    return {
        src = src,
        name = GetPlayerName(src) or 'Unknown',
        license = GetPlayerIdentifierByType(src, 'license'),
        role = role,
        level = level
    }
end

local function FindPlayerByLicense(license)
    for _, id in ipairs(GetPlayers()) do
        if GetPlayerIdentifierByType(id, 'license') == license then
            return tonumber(id)
        end
    end
    return nil
end

local function Field(name, value, inline)
    value = tostring(value or '')
    if value == '' then value = '-' end
    return { name = name, value = Utils.Truncate(value, 1000), inline = inline or false }
end

local function Log(title, color, fields)
    if not Config.Webhook or Config.Webhook == '' then return end

    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = Config.ServerName .. ' Chat Moderation',
        embeds = {{
            title = title,
            color = color,
            fields = fields,
            footer = { text = Config.ServerName },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }},
        allowed_mentions = { parse = {} } -- never ping anyone from a log
    }), { ['Content-Type'] = 'application/json' })
end

local function TimeLeft(entry)
    if entry.expiresAt == -1 then return 'permanent' end
    return Utils.FormatDuration(entry.expiresAt - os.time())
end

local function ExpiryField(entry)
    if entry.expiresAt == -1 then return 'Never' end
    return ('<t:%d:f> (<t:%d:R>)'):format(entry.expiresAt, entry.expiresAt)
end

local function Announce(message)
    if Config.Announce == 'public' then
        for _, id in ipairs(GetPlayers()) do
            Notify(tonumber(id), message, 'warning')
        end
    elseif Config.Announce == 'staff' then
        for _, id in ipairs(GetPlayers()) do
            local role = GetRole(tonumber(id))
            if role and role.canView then
                Notify(tonumber(id), message, 'warning')
            end
        end
    end
end

local function PresetNames()
    local names = {}
    for name in pairs(Config.Presets) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ', ')
end

---------------------------------------------------------------------
-- Timeout lifecycle
---------------------------------------------------------------------

local function ExpireEntry(entry)
    Store.End(entry, 'expired', 'system')

    local src = FindPlayerByLicense(entry.license)
    if src then Notify(src, Config.Messages.expired, 'success') end

    Log('Chat Timeout Expired', 3066993, {
        Field('Player', entry.name, true),
        Field('Timeout', '#' .. entry.id, true),
        Field('Original reason', entry.reason)
    })
end

-- The running timeout for a license, or nil. Expired ones are closed on the spot.
local function ActiveEntry(license)
    local entry = Store.GetActive(license)
    if not entry then return nil end

    if entry.expiresAt ~= -1 and entry.expiresAt <= os.time() then
        ExpireEntry(entry)
        return nil
    end
    return entry
end

-- Applies the repeat-offender multiplier, then keeps the result inside the actor's limit
local function PrepareDuration(license, base, actor)
    local esc = Config.Escalation
    if base == -1 or not esc.enabled then return base, 1 end

    local previous = Store.CountSince(license, os.time() - esc.windowDays * 86400)
    local mult = esc.multipliers[math.min(previous + 1, #esc.multipliers)] or 1
    local final = base * mult

    local max = actor.role.maxDuration
    if max and final > max then final = max end

    return final, mult
end

local function IssueTimeout(target, duration, reason, actor, auto)
    local now = os.time()

    local entry = Store.Add({
        license = target.license,
        name = target.name,
        by = actor.name,
        byLicense = actor.license,
        reason = reason,
        issuedAt = now,
        duration = duration,
        expiresAt = duration == -1 and -1 or now + duration,
        status = 'active',
        auto = auto or false
    })

    local length = Utils.FormatDuration(duration)

    if target.src then
        Notify(target.src, Config.Messages.timedOut:format(length, reason), 'error')
    end
    Announce(Config.Messages.announce:format(target.name, length, reason))

    Log(auto and 'Automatic Chat Timeout' or 'Chat Timeout Issued', auto and 15105570 or 15158332, {
        Field('Player', target.name, true),
        Field('Timeout', '#' .. entry.id, true),
        Field('Duration', length, true),
        Field('Issued by', actor.name, true),
        Field('Expires', ExpiryField(entry), true),
        Field('License', target.license),
        Field('Reason', reason)
    })

    TriggerEvent('chattimeout:issued', target.src, entry.id, duration, reason)
    return entry
end

local function LiftTimeout(entry, actor)
    Store.End(entry, 'lifted', actor.name)

    local src = FindPlayerByLicense(entry.license)
    if src then Notify(src, Config.Messages.lifted:format(actor.name), 'success') end

    Log('Chat Timeout Lifted', 3066993, {
        Field('Player', entry.name, true),
        Field('Timeout', '#' .. entry.id, true),
        Field('Lifted by', actor.name, true),
        Field('Original reason', entry.reason)
    })

    TriggerEvent('chattimeout:lifted', src, entry.id)
end

-- Expire timeouts on schedule, even for players who aren't typing
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for _, entry in ipairs(Store.AllActive()) do
            if entry.expiresAt ~= -1 and entry.expiresAt <= now then
                ExpireEntry(entry)
            end
        end
    end
end)

---------------------------------------------------------------------
-- Finding the player a command is aimed at
---------------------------------------------------------------------

-- Accepts a player ID, "license:abc123..." (works offline) or "#12" (a timeout number)
local function ResolveTarget(arg)
    if not arg then return nil, 'You need to say who.' end

    local entryId = arg:match('^#(%d+)$')
    if entryId then
        local entry = Store.GetById(tonumber(entryId))
        if not entry then return nil, 'There is no timeout with that number.' end
        return { license = entry.license, name = entry.name, src = FindPlayerByLicense(entry.license) }
    end

    if arg:match('^license:%x+$') then
        return {
            license = arg,
            name = Store.LastKnownName(arg) or 'Unknown',
            src = FindPlayerByLicense(arg)
        }
    end

    local id = tonumber(arg)
    if id and GetPlayerName(id) then
        local license = GetPlayerIdentifierByType(id, 'license')
        if not license then return nil, 'That player has no license identifier.' end
        return { license = license, name = GetPlayerName(id), src = id }
    end

    return nil, 'Player not found. Use a player ID, license:xxxx or #timeoutNumber.'
end

---------------------------------------------------------------------
-- Checking chat messages
---------------------------------------------------------------------

local function ParseOr(duration, fallback)
    return Utils.ParseDuration(duration) or fallback
end

-- Returns true if the message must be blocked
local function CheckMessage(src, message)
    if src == 0 or type(message) ~= 'string' then return false end
    if IsPlayerAceAllowed(src, Config.Ace.bypass) then return false end

    local license = GetPlayerIdentifierByType(src, 'license')
    if not license then return false end

    local entry = ActiveEntry(license)
    if entry then
        -- Tell them, but not on every single keypress
        local now = GetGameTimer()
        if not lastNotice[src] or now - lastNotice[src] > 3000 then
            lastNotice[src] = now
            Notify(src, Config.Messages.blocked:format(TimeLeft(entry), entry.reason), 'error')
        end
        return true
    end

    local mod = Config.AutoMod
    if not mod.enabled then return false end

    local target = { license = license, name = GetPlayerName(src) or 'Unknown', src = src }

    if mod.spam.enabled then
        local now = GetGameTimer()
        local times = msgLog[src] or {}
        msgLog[src] = times

        times[#times + 1] = now
        local cutoff = now - mod.spam.seconds * 1000
        while times[1] and times[1] < cutoff do table.remove(times, 1) end

        if #times >= mod.spam.messages then
            msgLog[src] = nil
            local duration = PrepareDuration(license, ParseOr(mod.spam.duration, 300), SYSTEM_ACTOR)
            IssueTimeout(target, duration, mod.spam.reason, SYSTEM_ACTOR, true)
            return true
        end
    end

    if mod.words.enabled and #mod.words.list > 0 then
        local lower = message:lower()
        for _, word in ipairs(mod.words.list) do
            if word ~= '' and lower:find(word:lower(), 1, true) then
                if mod.words.action == 'timeout' then
                    local duration = PrepareDuration(license, ParseOr(mod.words.duration, 600), SYSTEM_ACTOR)
                    IssueTimeout(target, duration, mod.words.reason, SYSTEM_ACTOR, true)
                else
                    Notify(src, Config.Messages.wordBlocked, 'warning')
                end
                return true
            end
        end
    end

    return false
end

-- Preferred: the chat resource's message hook (clean cancel, runs before anything else)
local function RegisterChatHook()
    if hookActive or GetResourceState('chat') ~= 'started' then return end

    local ok = pcall(function()
        exports.chat:registerMessageHook(function(src, outMessage, hookRef)
            local args = outMessage and outMessage.args
            local message = args and args[#args]
            if CheckMessage(src, message) then
                hookRef.cancel()
            end
        end)
    end)

    hookActive = ok
    if not ok then
        print('^3[chat-timeout] Could not register the chat hook. Falling back to the chatMessage event.^7')
    end
end

-- Fallback for older chat resources that have no message hook
AddEventHandler('chatMessage', function(src, _, message)
    if hookActive then return end
    if CheckMessage(src, message) then CancelEvent() end
end)

CreateThread(function()
    Wait(500)
    RegisterChatHook()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'chat' then SetTimeout(500, RegisterChatHook) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == 'chat' then hookActive = false end
    if resource == GetCurrentResourceName() then Store.Flush() end
end)

AddEventHandler('playerDropped', function()
    local src = source
    msgLog[src] = nil
    lastNotice[src] = nil
end)

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------

RegisterCommand(Config.Commands.timeout, function(source, args)
    local actor = GetActor(source)
    if not actor then
        return Notify(source, 'You do not have permission to use this command.', 'error')
    end

    if not args[1] or not args[2] then
        return Notify(source, ('Usage: /%s [id | license:xxx | #number] [duration | preset] [reason]\nDurations: 30m, 2h, 1d, 1h30m, perm\nPresets: %s')
            :format(Config.Commands.timeout, PresetNames()), 'inform')
    end

    local target, err = ResolveTarget(args[1])
    if not target then return Notify(source, err, 'error') end

    if source ~= 0 then
        if not Config.AllowSelf and target.src == source then
            return Notify(source, 'You cannot time yourself out.', 'error')
        end

        if target.src and IsPlayerAceAllowed(target.src, Config.Ace.bypass) then
            return Notify(source, 'That player is immune to chat timeouts.', 'error')
        end

        if Config.Hierarchy and target.src then
            local _, targetLevel = GetRole(target.src)
            if targetLevel > 0 and actor.level <= targetLevel then
                return Notify(source, 'You cannot time out someone of the same rank or higher.', 'error')
            end
        end
    end

    local existing = ActiveEntry(target.license)
    if existing then
        return Notify(source, ('%s is already timed out (%s left). Use /%s first to change it.')
            :format(target.name, TimeLeft(existing), Config.Commands.untimeout), 'error')
    end

    -- Second argument is either a preset name or a duration
    local second = args[2]:lower()
    local preset = Config.Presets[second]
    local duration, reason

    if preset then
        duration = Utils.ParseDuration(preset.duration)
        reason = preset.reason
        local extra = table.concat(args, ' ', 3)
        if extra ~= '' then reason = reason .. ' - ' .. extra end
    else
        duration = Utils.ParseDuration(second)
        reason = table.concat(args, ' ', 3)
    end

    if not duration then
        return Notify(source, 'That duration or preset was not understood. Try 30m, 2h, 1d or perm.', 'error')
    end

    reason = Utils.Clean(reason, Config.MaxReasonLength)
    if reason == '' then
        if Config.RequireReason then
            return Notify(source, 'Please give a reason.', 'error')
        end
        reason = 'No reason given'
    end

    if duration == -1 then
        if not actor.role.permanent then
            return Notify(source, ('Your rank (%s) cannot give permanent timeouts.'):format(actor.role.name), 'error')
        end
    else
        if duration < Config.MinDuration then
            return Notify(source, ('The shortest timeout is %s.'):format(Utils.FormatDuration(Config.MinDuration)), 'error')
        end
        local max = actor.role.maxDuration
        if max and duration > max then
            return Notify(source, ('Your rank (%s) can give timeouts up to %s.')
                :format(actor.role.name, Utils.FormatDuration(max)), 'error')
        end
    end

    local final, mult = PrepareDuration(target.license, duration, actor)
    IssueTimeout(target, final, reason, actor, false)

    Notify(source, ('%s timed out for %s%s.'):format(
        target.name,
        Utils.FormatDuration(final),
        mult > 1 and (' (repeat offender x%d)'):format(mult) or ''), 'success')
end, false)

RegisterCommand(Config.Commands.untimeout, function(source, args)
    local actor = GetActor(source)
    if not actor or not actor.role.canLift then
        return Notify(source, 'You do not have permission to use this command.', 'error')
    end

    if not args[1] then
        return Notify(source, ('Usage: /%s [id | license:xxx | #number]'):format(Config.Commands.untimeout), 'inform')
    end

    local target, err = ResolveTarget(args[1])
    if not target then return Notify(source, err, 'error') end

    local entry = ActiveEntry(target.license)
    if not entry then
        return Notify(source, ('%s is not timed out.'):format(target.name), 'error')
    end

    if actor.role.canLift == 'own' and entry.byLicense ~= actor.license then
        return Notify(source, 'Your rank can only lift timeouts that you issued.', 'error')
    end

    LiftTimeout(entry, actor)
    Notify(source, ('Lifted the timeout for %s.'):format(entry.name), 'success')
end, false)

RegisterCommand(Config.Commands.list, function(source)
    local actor = GetActor(source)
    if not actor or not actor.role.canView then
        return Notify(source, 'You do not have permission to use this command.', 'error')
    end

    local entries = Store.AllActive()
    if #entries == 0 then
        return Notify(source, 'Nobody is timed out right now.')
    end
    table.sort(entries, function(a, b) return a.id < b.id end)

    local lines = {}
    for i, e in ipairs(entries) do
        if i > 15 then
            lines[#lines + 1] = ('...and %d more'):format(#entries - 15)
            break
        end
        lines[#lines + 1] = ('#%d %s | %s left | by %s | %s'):format(e.id, e.name, TimeLeft(e), e.by, e.reason)
    end

    Notify(source, table.concat(lines, '\n'))
end, false)

RegisterCommand(Config.Commands.history, function(source, args)
    local actor = GetActor(source)
    if not actor or not actor.role.canHistory then
        return Notify(source, 'You do not have permission to use this command.', 'error')
    end

    local target, err = ResolveTarget(args[1])
    if not target then return Notify(source, err, 'error') end

    local entries = Store.History(target.license, 8)
    if #entries == 0 then
        return Notify(source, ('%s has no timeouts on record.'):format(target.name))
    end

    local lines = { ('Last timeouts for %s:'):format(target.name) }
    for _, e in ipairs(entries) do
        lines[#lines + 1] = ('#%d %s | %s | %s | by %s | %s'):format(
            e.id, os.date('%Y-%m-%d', e.issuedAt), e.status, Utils.FormatDuration(e.duration), e.by, e.reason)
    end

    Notify(source, table.concat(lines, '\n'))
end, false)

RegisterCommand(Config.Commands.mine, function(source)
    if source == 0 then return end

    local license = GetPlayerIdentifierByType(source, 'license')
    local entry = license and ActiveEntry(license)

    if not entry then
        return Notify(source, 'You are not timed out.', 'success')
    end
    Notify(source, Config.Messages.blocked:format(TimeLeft(entry), entry.reason), 'error')
end, false)

---------------------------------------------------------------------
-- Chat suggestions: each player only gets the commands they can use
---------------------------------------------------------------------

RegisterNetEvent('chattimeout:ready', function()
    local src = source
    local c = Config.Commands
    local list = {
        { name = '/' .. c.mine, help = 'Check your own chat timeout' }
    }

    local role = GetRole(src)
    if role then
        list[#list + 1] = {
            name = '/' .. c.timeout,
            help = 'Time a player out of chat. Presets: ' .. PresetNames(),
            params = {
                { name = 'target', help = 'Player ID, license:xxx or #timeoutNumber' },
                { name = 'duration', help = '30m, 2h, 1d, 1h30m, perm - or a preset' },
                { name = 'reason', help = 'Why' }
            }
        }
        if role.canLift then
            list[#list + 1] = {
                name = '/' .. c.untimeout, help = 'Lift a chat timeout',
                params = { { name = 'target', help = 'Player ID, license:xxx or #timeoutNumber' } }
            }
        end
        if role.canView then
            list[#list + 1] = { name = '/' .. c.list, help = 'List active chat timeouts' }
        end
        if role.canHistory then
            list[#list + 1] = {
                name = '/' .. c.history, help = 'Show a player\'s recent timeouts',
                params = { { name = 'target', help = 'Player ID, license:xxx or #timeoutNumber' } }
            }
        end
    end

    TriggerClientEvent('chattimeout:suggestions', src, list)
end)

---------------------------------------------------------------------
-- Exports, so other resources can use timeouts too
---------------------------------------------------------------------

-- exports['chat-timeout']:IsTimedOut(source)  ->  true, { id, reason, expiresAt, secondsLeft }  or  false
exports('IsTimedOut', function(src)
    local license = GetPlayerIdentifierByType(src, 'license')
    if not license or IsPlayerAceAllowed(src, Config.Ace.bypass) then return false end

    local entry = ActiveEntry(license)
    if not entry then return false end

    return true, {
        id = entry.id,
        reason = entry.reason,
        expiresAt = entry.expiresAt,
        secondsLeft = entry.expiresAt == -1 and -1 or entry.expiresAt - os.time()
    }
end)

-- exports['chat-timeout']:TimeoutPlayer(source, seconds, reason, byName)  ->  timeout number or false
exports('TimeoutPlayer', function(src, seconds, reason, by)
    if type(seconds) ~= 'number' or (seconds ~= -1 and seconds < 1) then return false end

    local target = ResolveTarget(tostring(src))
    if not target or ActiveEntry(target.license) then return false end

    local actor = { src = -1, name = by or 'Script', role = SYSTEM_ACTOR.role, level = 999 }
    local entry = IssueTimeout(target, seconds, Utils.Clean(reason or 'No reason given', Config.MaxReasonLength), actor, true)
    return entry.id
end)

-- exports['chat-timeout']:RemoveTimeout(source, byName)  ->  true / false
exports('RemoveTimeout', function(src, by)
    local target = ResolveTarget(tostring(src))
    local entry = target and ActiveEntry(target.license)
    if not entry then return false end

    LiftTimeout(entry, { name = by or 'Script' })
    return true
end)
