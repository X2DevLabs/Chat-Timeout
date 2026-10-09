# Chat Timeout

A chat mute system for FiveM with role-based ACE permissions. Staff can time players out of chat for a set time, repeat offenders get longer timeouts automatically, and spam is handled without staff having to be online.

It needs no database and no other resources. Timeouts are saved to a file, so they survive restarts.

## Features
- **ACE roles** (Helper, Moderator, Admin, Owner by default) with their own maximum timeout length, permanent timeouts and lifting rules
- **Rank protection**: staff can only time out people ranked below them
- **Presets**: `/timeout 12 spam` instead of typing a duration and reason every time
- **Repeat offenders** get longer timeouts automatically, up to the staff member's own limit
- **Auto-moderation**: spam detection and an optional blocked-word list
- **Offline timeouts**: use `license:xxxx` or the timeout number (`#12`) for players who have left
- **Survives restarts**: timeouts keep counting down while the server is offline
- **Discord log** of every timeout, lift and expiry
- **Exports** so other resources can check or issue timeouts

## Installation
1. Put the folder in your resources and start it after `chat`:
   ```
   ensure chat
   ensure chat-timeout
   ```
2. Open `ace_example.cfg`, copy what you need into your `server.cfg`, and add your staff.
3. Open `config.lua` to set limits, presets, auto-moderation and your webhook.

Keep the folder name `chat-timeout` if you want to use the exports as written below.

## Commands
| Command | Who | What it does |
|---|---|---|
| `/timeout [target] [duration or preset] [reason]` | Staff | Time a player out of chat |
| `/untimeout [target]` | Staff with lifting rights | Lift a timeout |
| `/timeouts` | Staff | List active timeouts |
| `/timeouthistory [target]` | Staff with history rights | Recent timeouts for a player |
| `/mytimeout` | Everyone | Check your own timeout |

**Target** can be a player ID, `license:xxxx` (works offline) or `#12` (the number of a timeout, shown in `/timeouts`).
**Duration** can be `30m`, `2h`, `1d`, `1w`, `1h30m` or `perm`. A plain number means minutes.

Examples:
```
/timeout 12 30m Insulting players
/timeout 12 spam
/timeout 12 spam kept going after a warning
/timeout 12 perm
/untimeout #7
```

## Permissions
Each role in `config.lua` is tied to an ACE. A player gets the highest role they have.

| Setting | Meaning |
|---|---|
| `ace` | The permission that grants the role |
| `maxDuration` | Longest timeout, in seconds. Leave it out for unlimited |
| `permanent` | Can give permanent timeouts |
| `canLift` | `'any'`, `'own'` (only their own timeouts) or `false` |
| `canView` | Can use `/timeouts` |
| `canHistory` | Can use `/timeouthistory` |

`chattimeout.bypass` makes someone immune. They can't be timed out and skip the spam check and word filter.

Add or remove roles freely. The order in the list is the rank, lowest first.

## Repeat offenders
With the default settings, a player's first timeout in 30 days is normal length, the second is doubled and the third and later are four times as long. The result never goes over the limit of the staff member who gave it. Timeouts that staff lifted don't count against the player.

## Blocking other commands
Players can't be stopped from using slash commands such as `/me` or `/ooc` from here, because other resources register those. If you want a timed-out player to be unable to use one, add this at the top of that command's handler:

```lua
if exports['chat-timeout']:IsTimedOut(source) then return end
```

## Exports (server)
```lua
exports['chat-timeout']:IsTimedOut(source)
-- true, { id, reason, expiresAt, secondsLeft }   or   false

exports['chat-timeout']:TimeoutPlayer(source, seconds, reason, 'Anticheat')
-- returns the timeout number, or false. Use -1 for permanent.

exports['chat-timeout']:RemoveTimeout(source, 'Anticheat')
-- true / false
```

Events other resources can listen to: `chattimeout:issued` (target, id, duration, reason) and `chattimeout:lifted` (target, id).

## Good to know
- Players are identified by their Rockstar license, so timeouts follow them across reconnects.
- Rank and immunity checks only work on players who are online. Offline timeouts by `license:` skip them.
- Timeouts are stored in `data/timeouts.json`. If the file ever gets damaged, a copy is kept as `timeouts.corrupt.json`.
- The webhook in `config.lua` is server-only. Never move it to a client or shared script.
