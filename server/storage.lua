Store = {}

local RESOURCE = GetCurrentResourceName()
local FILE = 'data/timeouts.json'

-- Every timeout ever issued (up to Config.HistoryLimit) lives in `data.entries`.
-- `active` just points at the ones that are currently running, keyed by license.
local data = { nextId = 1, entries = {} }
local active = {}
local dirty = false

local function RebuildActive()
    active = {}
    for _, entry in ipairs(data.entries) do
        if entry.status == 'active' then
            active[entry.license] = entry
        end
    end
end

function Store.Load()
    local raw = LoadResourceFile(RESOURCE, FILE)

    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)

        if ok and type(decoded) == 'table' then
            data.nextId = decoded.nextId or 1
            data.entries = decoded.entries or {}
        else
            -- Don't silently throw away a damaged file: keep a copy before we overwrite it
            SaveResourceFile(RESOURCE, 'data/timeouts.corrupt.json', raw, -1)
            print('^1[chat-timeout] data/timeouts.json could not be read. A copy was saved as data/timeouts.corrupt.json and we are starting empty.^7')
        end
    end

    RebuildActive()
end

function Store.Flush()
    if not dirty then return end
    dirty = false
    SaveResourceFile(RESOURCE, FILE, json.encode(data, { indent = true }), -1)
end

-- Saves are batched: many changes in a few seconds cause one disk write
CreateThread(function()
    while true do
        Wait(5000)
        Store.Flush()
    end
end)

-- Remove the oldest finished entries once we go over the limit. Running timeouts are never removed.
local function Trim()
    local i = 1
    while #data.entries > Config.HistoryLimit and i <= #data.entries do
        if data.entries[i].status ~= 'active' then
            table.remove(data.entries, i)
        else
            i = i + 1
        end
    end
end

function Store.Add(entry)
    entry.id = data.nextId
    data.nextId = data.nextId + 1

    data.entries[#data.entries + 1] = entry
    active[entry.license] = entry

    Trim()
    dirty = true
    return entry
end

function Store.End(entry, status, by)
    entry.status = status
    entry.endedAt = os.time()
    entry.endedBy = by
    active[entry.license] = nil
    dirty = true
end

function Store.GetActive(license)
    return active[license]
end

function Store.AllActive()
    local list = {}
    for _, entry in pairs(active) do
        list[#list + 1] = entry
    end
    return list
end

function Store.GetById(id)
    for i = #data.entries, 1, -1 do
        if data.entries[i].id == id then return data.entries[i] end
    end
    return nil
end

function Store.LastKnownName(license)
    for i = #data.entries, 1, -1 do
        if data.entries[i].license == license then return data.entries[i].name end
    end
    return nil
end

-- How many timeouts this player received since `since` (lifted ones don't count against them)
function Store.CountSince(license, since)
    local count = 0
    for _, entry in ipairs(data.entries) do
        if entry.license == license and entry.issuedAt >= since and entry.status ~= 'lifted' then
            count = count + 1
        end
    end
    return count
end

-- Newest first
function Store.History(license, limit)
    local list = {}
    for i = #data.entries, 1, -1 do
        if data.entries[i].license == license then
            list[#list + 1] = data.entries[i]
            if #list >= limit then break end
        end
    end
    return list
end
