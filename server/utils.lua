Utils = {}

local UNITS = { s = 1, m = 60, h = 3600, d = 86400, w = 604800 }

-- Accepts "30m", "2h", "1d", "1h30m", "2w", "perm" or a bare number (minutes).
-- Returns seconds, -1 for permanent, or nil if it can't be understood.
function Utils.ParseDuration(input)
    if type(input) ~= 'string' then return nil end
    input = input:lower()

    if input == 'perm' or input == 'permanent' or input == 'forever' then
        return -1
    end

    if input:match('^%d+$') then
        local minutes = tonumber(input)
        return minutes > 0 and minutes * 60 or nil
    end

    local total, pos = 0, 1
    while pos <= #input do
        local amount, unit, nextPos = input:match('^(%d+)([smhdw])()', pos)
        if not amount then return nil end
        total = total + tonumber(amount) * UNITS[unit]
        pos = nextPos
    end

    return total > 0 and total or nil
end

-- 3725 -> "1h 2m 5s". Shows at most the three biggest parts.
function Utils.FormatDuration(seconds)
    if seconds < 0 then return 'permanent' end
    seconds = math.floor(seconds)
    if seconds < 1 then return '0s' end

    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60

    local parts = {}
    if d > 0 then parts[#parts + 1] = d .. 'd' end
    if h > 0 then parts[#parts + 1] = h .. 'h' end
    if m > 0 then parts[#parts + 1] = m .. 'm' end
    if s > 0 and #parts < 2 then parts[#parts + 1] = s .. 's' end

    return table.concat(parts, ' ')
end

-- Player input is untrusted: strip control characters, trim, cap the length
function Utils.Clean(value, maxLen)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('%c', '')
    value = value:match('^%s*(.-)%s*$')
    return value:sub(1, maxLen)
end

function Utils.Truncate(value, maxLen)
    value = tostring(value)
    if #value <= maxLen then return value end
    return value:sub(1, maxLen - 3) .. '...'
end
