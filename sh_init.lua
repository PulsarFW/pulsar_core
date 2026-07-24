COMPONENTS = {}

AddEventHandler("onResourceStart", function(resource)
	if resource == GetCurrentResourceName() then
		CreateThread(function()
			local ver
			repeat
				Wait(0)
			until COMPONENTS.Convar.PLSR_VERSION ~= nil

			if COMPONENTS.Convar.PLSR_VERSION.value == "UNKNOWN" then
				ver = "^1Version Unknown"
			else
				ver = "^2v" .. COMPONENTS.Convar.PLSR_VERSION.value
			end

			print([[


^6=================================================================================================^6

^7       .   ✦       .        *    .      ✦      .         *        .     ✦       .       *
^7   *        .     ·       .          .      *       ·          .       .     *        ·
^6
^6  ·  ★             ██████╗ ██╗   ██╗██╗      ███████╗ █████╗ ██████╗             ★  ·
^6  ✦                ██╔══██╗██║   ██║██║      ██╔════╝██╔══██╗██╔══██╗               ✦
^6  ·                ██████╔╝██║   ██║██║      ███████╗███████║██████╔╝               ·
^6  ★                ██╔═══╝ ██║   ██║██║      ╚════██║██╔══██║██╔══██╗            ★
^6  ·   ✦            ██║     ╚██████╔╝███████╗ ███████║██║  ██║██║  ██║         ✦   ·
^6                   ╚═╝      ╚═════╝ ╚══════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
^6                                  F R A M E W O R K
^6
^7   *        .     ·       .          .      *       ·          .       .     *        ·
^7       .   ✦       .        *    .      ✦      .         *        .     ✦       .       *
^6=================================================================================================^7
]])
			print("^6Pulsar Framework ^7" .. ver)
			print("^3Maintained by ^6Pulsar Development Team^7")
			print("^8Special thanks to ^3Autlaww^8 for SQL & export work^7")
			print([[
^6=================================================================================================^7
]])

			TriggerEvent("Core:Shared:Watermark")
		end)
	end
end)
