COMPONENTS.Discord = {
	_name = "core",
	RichPresence = function(self)
		SetDiscordAppId(COMPONENTS.Convar.DISCORD_APP.value)
		SetDiscordRichPresenceAsset("PULSARFW_large_icon")
		SetDiscordRichPresenceAssetText("Join Today: pulsarfw.com")
		--SetDiscordRichPresenceAssetSmall("info")
		SetDiscordRichPresenceAction(0, "Apply Now", "https://pulsarfw.com")
		SetDiscordRichPresenceAction(1, "Join Our Discord", "https://discord.gg/Bd8nYPKET9")

		CreateThread(function()
			while true do
				local playerCount = GlobalState["PlayerCount"] or 0
				local queueCount = GlobalState["QueueCount"] or 0
				if COMPONENTS.State:Get('flags', 'loggedIn') then
					SetRichPresence(
						string.format(
							"[%d/%d]%s - Playing %s %s",
							playerCount,
							GlobalState.MaxPlayers,
							queueCount > 0 and string.format(" (Queue: %d)", queueCount) or "",
							COMPONENTS.State:Get('character', "First"),
							COMPONENTS.State:Get('character', "Last")
						)
					)
				else
					SetRichPresence(
						string.format(
							"[%d/%d]%s - Selecting a Character", 
							playerCount, 
							GlobalState.MaxPlayers,
							queueCount > 0 and string.format(" (Queue: %d)", queueCount) or ""
						)
					)
				end

				-- SetDiscordRichPresenceAssetSmallText(
				-- 	string.format("%s/%s [Queue: %s]", playerCount, GlobalState.MaxPlayers, queueCount)
				-- )
				Wait(30000)
			end
		end)
	end,
}

CreateThread(function()
	COMPONENTS.Discord:RichPresence()
end)
