-- ==============================================================================
-- 👑 DJONSTNIX BRANDING
-- ==============================================================================
-- DEVELOPED BY: DjonStNix (DjonLuc)
-- GITHUB: https://github.com/Djonluc
-- DISCORD: https://discord.gg/ahAJWRTMBv
-- YOUTUBE: https://www.youtube.com/@Djonluc
-- EMAIL: djonstnix@gmail.com
-- LICENSE: MIT License (c) 2026 DjonStNix (DjonLuc)
-- ==============================================================================

fx_version 'cerulean'
game 'gta5'

name "djonstnix-scenes"
description "An optimised scene resource utilising ox_lib."
author "DjonStNix (DjonLuc)"
version "1.0.0"

lua54 'yes'

shared_scripts {
	'@ox_lib/init.lua',
	'@qb-core/shared/locale.lua',
    'locales/*.lua',
	'shared/config.lua',
    'shared/main.lua'
}

client_scripts {
	'client/*.lua'
}

server_scripts {
	'server/json.lua',
	'server/main.lua'
}

ui_page 'ui/preview.html'

files {
	'storage/save.json',
	'storage/bans.json',
    'ui/preview.html',
    'ui/preview.js',
    'ui/preview.css',
    'ui/image.html',
    'ui/gif-decoder.js',
    'ui/styles.css',
    'ui/app.js',
    'ui/images/.gitkeep',
    'ui/images/*'
}

-- ==============================================================================
-- 🔒 ESCROW CONFIGURATION (TEBEX READY)
-- ==============================================================================

escrow_ignore {
    'shared/config.lua',
    'locales/*.lua',
    'README.md'
}
