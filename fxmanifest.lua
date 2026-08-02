fx_version 'cerulean'
game 'gta5'

name 'Pulsar Properties'
description 'Player housing with interiors, furniture, garages, storage, and upgrades'
author 'Artmines - maintained for Pulsar Framework'
url 'https://pulsarframe.work'
version 'v1.0.0'

version_check 'yes'
github 'https://github.com/PulsarFW/pulsar_properties'

client_script '@pulsar_core/components/cl_error.lua'
shared_script '@pulsar_core/core/sh_pulsar.lua'
client_script '@pulsar_pwnzor/client/check.lua'

client_scripts({
	'interiors/**/*.lua',
	'shared/**/*.lua',
	'client/**/*.lua',
})

server_scripts({
	'interiors/**/*.lua',
	'shared/**/*.lua',
	'sv_config.lua',
	'server/**/*.lua',
})

lua54 'yes'