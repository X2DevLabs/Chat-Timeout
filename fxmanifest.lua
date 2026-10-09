fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Next Dev Labs'
description 'Chat Timeout - role-based chat mutes with ACE permissions, presets, escalation and auto-moderation'
version '1.0.0'

-- config.lua is SERVER ONLY because it holds your webhook URL.
server_scripts {
    'config.lua',
    'server/utils.lua',
    'server/storage.lua',
    'server/main.lua'
}

client_script 'client/main.lua'

-- data/timeouts.json is read and written by the server, never sent to players.
