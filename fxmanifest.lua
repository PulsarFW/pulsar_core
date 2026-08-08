fx_version 'cerulean'
games { 'gta5' }

name 'Pulsar Core'
description 'The framework root exposing the shared plsr interface every other resource is built on'
author 'Artmines - maintained for Pulsar Framework'
url 'https://pulsarframe.work'
version 'v1.0.1'

version_check 'yes'
github 'https://github.com/PulsarFW/pulsar_core'

server_script '@oxmysql/lib/MySQL.lua'
client_script '@pulsar_pwnzor/client/check.lua'

client_scripts({
	'sh_init.lua',
	'cl_init.lua',
	'core/sh_*.lua',
	'core/cl_*.lua',
	'cl_config.lua',
	'components/cl_*.lua',
})

server_scripts({
	'sh_init.lua',
	'sv_init.lua',
	'sv_config.lua',
	'core/sv_generator.js',
	'core/sv_regex.js',
	'core/sh_*.lua',
	'core/sv_*.lua',
	'components/sv_*.lua',
})

files({
	'weaponanimations.meta',
})

data_file 'WEAPONINFO_FILE_PATCH' 'weapons.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'weaponanimations.meta'

this_is_a_map 'yes'
lua54 'yes'