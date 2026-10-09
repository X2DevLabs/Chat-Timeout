Config = {}

Config.ServerName = 'Your Server Name'

-- How messages are shown to players and staff: 'chat' or 'ox_lib'
Config.Notify = 'chat'

-- Discord webhook for the moderation log. Leave '' to disable.
-- Keep this private. Never paste a real webhook into a public repository.
Config.Webhook = ''

-- Who sees the "X was timed out" message: 'staff' | 'public' | 'none'
Config.Announce = 'staff'

---------------------------------------------------------------------
-- Commands (rename them if they clash with another resource)
---------------------------------------------------------------------
Config.Commands = {
    timeout = 'timeout',          -- /timeout [id] [duration|preset] [reason]
    untimeout = 'untimeout',      -- /untimeout [id]
    list = 'timeouts',            -- /timeouts
    history = 'timeouthistory',   -- /timeouthistory [id]
    mine = 'mytimeout'            -- /mytimeout (everyone)
}

---------------------------------------------------------------------
-- ACE roles, listed from LOWEST to HIGHEST.
-- A player gets the highest role whose ACE they have.
--
--   ace         : the permission that grants this role
--   maxDuration : longest timeout in seconds this role can give (leave out = unlimited)
--   permanent   : may give permanent timeouts
--   canLift     : 'any' = lift any timeout | 'own' = only ones they issued | false = none
--   canView     : may use /timeouts
--   canHistory  : may use /timeouthistory
--
-- Example server.cfg lines are in ace_example.cfg.
---------------------------------------------------------------------
Config.Roles = {
    {
        name = 'Helper', ace = 'chattimeout.helper',
        maxDuration = 60 * 60,            -- 1 hour
        permanent = false, canLift = 'own', canView = true, canHistory = false
    },
    {
        name = 'Moderator', ace = 'chattimeout.mod',
        maxDuration = 24 * 60 * 60,       -- 1 day
        permanent = false, canLift = 'any', canView = true, canHistory = true
    },
    {
        name = 'Admin', ace = 'chattimeout.admin',
        maxDuration = 7 * 24 * 60 * 60,   -- 1 week
        permanent = false, canLift = 'any', canView = true, canHistory = true
    },
    {
        name = 'Owner', ace = 'chattimeout.owner',
        -- no maxDuration = unlimited
        permanent = true, canLift = 'any', canView = true, canHistory = true
    }
}

Config.Ace = {
    -- Immune to timeouts, the spam check and the word filter.
    bypass = 'chattimeout.bypass'
}

-- Staff can only time out people ranked BELOW them. People with no role count as the lowest rank.
Config.Hierarchy = true
Config.AllowSelf = false

---------------------------------------------------------------------
-- Rules for staff-issued timeouts
---------------------------------------------------------------------
Config.RequireReason = true
Config.MaxReasonLength = 120
Config.MinDuration = 30        -- seconds
Config.HistoryLimit = 1000     -- how many timeouts to keep on record

-- Shortcuts: /timeout 12 spam    or    /timeout 12 spam extra details
Config.Presets = {
    spam   = { duration = '10m', reason = 'Spamming the chat' },
    insult = { duration = '30m', reason = 'Insulting other players' },
    advert = { duration = '1h',  reason = 'Advertising' },
    toxic  = { duration = '2h',  reason = 'Toxic behaviour' },
    nsfw   = { duration = '6h',  reason = 'Inappropriate content' }
}

---------------------------------------------------------------------
-- Repeat offenders get longer timeouts automatically.
-- Offence 1 = x1, offence 2 = x2, offence 3 and later = x4 (with the defaults).
-- The result never goes above the staff member's own limit.
---------------------------------------------------------------------
Config.Escalation = {
    enabled = true,
    windowDays = 30,                 -- only count timeouts from the last 30 days
    multipliers = { 1, 2, 4 }
}

---------------------------------------------------------------------
-- Automatic moderation
---------------------------------------------------------------------
Config.AutoMod = {
    enabled = true,

    -- Too many messages in a short time
    spam = {
        enabled = true,
        messages = 5,                -- this many messages...
        seconds = 6,                 -- ...within this many seconds
        duration = '5m',
        reason = 'Automatic: chat spam'
    },

    -- Blocked words. Matching is plain text and ignores capital letters.
    words = {
        enabled = false,
        action = 'block',            -- 'block' = just hide the message | 'timeout' = hide it and time them out
        duration = '10m',
        reason = 'Automatic: blocked word',
        list = { 'example1', 'example2' }
    }
}

---------------------------------------------------------------------
-- Messages players see. %s are filled in automatically.
---------------------------------------------------------------------
Config.Messages = {
    timedOut    = 'You have been timed out for %s. Reason: %s',
    blocked     = 'You are timed out and cannot chat. Time left: %s. Reason: %s',
    lifted      = 'Your chat timeout was lifted by %s.',
    expired     = 'Your chat timeout has ended. Please follow the server rules.',
    wordBlocked = 'Your message was blocked by the chat filter.',
    announce    = '%s was timed out for %s. Reason: %s'
}
