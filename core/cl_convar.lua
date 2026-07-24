COMPONENTS.Convar = {
	DISCORD_APP = { value = GetConvar("discord_app", "") },
	MAX_CLIENTS = { value = tonumber(GetConvar("sv_maxclients", "32")) },
	LOGGING = { value = tonumber(GetConvar("log_level", 0)) },
	PLSR_VERSION = { value = GetConvar("plsr_version", "UNKNOWN") },
}
