fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Aegis / OpenAI'
description 'Garages entreprise ESX Legacy | Interface NUI | Wasabi Carlock'
version '1.4.0'

ui_page 'web/index.html'
files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
    'web/preview.js'
}

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/properties.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/bridge.lua',
    'server/main.lua'
}

dependencies {
    '/onesync',
    'es_extended',
    'oxmysql',
    'wasabi_carlock'
}
