local _checked = {}

local function parseManifestVersion(body)
	for line in body:gmatch("[^\r\n]+") do
		local value = line:match("^%s*version%s*%(?%s*'([^']+)'") or line:match('^%s*version%s*%(?%s*"([^"]+)"')
		if value then
			return value
		end
	end
	return nil
end

local function resolveManifestUrl(github, branch)
	github = github:gsub("/+$", "")

	if github:find("raw.githubusercontent.com", 1, true) then
		return github .. "/" .. branch .. "/fxmanifest.lua"
	end

	local owner, repo = github:match("github%.com/([^/]+)/([^/]+)")
	if not owner then
		return nil
	end
	repo = repo:gsub("%.git$", "")

	return ("https://raw.githubusercontent.com/%s/%s/%s/fxmanifest.lua"):format(owner, repo, branch)
end

COMPONENTS.VersionCheck = {
	_name = "core",

	-- resourceName defaults to whatever resource is on top of the invocation stack, so a resource
	-- can just call plsr.VersionCheck:Run() with no args from its own startup code
	Run = function(self, resourceName)
		resourceName = resourceName or GetInvokingResource()
		if not resourceName then
			COMPONENTS.Logger:Warn("VersionCheck", "Run() called without a resource name and couldn't resolve one", { console = true })
			return
		end

		if GetConvar("plsr_versioncheck_enabled", "1") ~= "1" then
			return
		end

		if _checked[resourceName] then
			return
		end

		if GetResourceState(resourceName) ~= "started" then
			return
		end

		if GetResourceMetadata(resourceName, "version_check", 0) ~= "yes" then
			return
		end

		local github = GetResourceMetadata(resourceName, "github", 0)
		local version = GetResourceMetadata(resourceName, "version", 0)
		if not github or not version then
			COMPONENTS.Logger:Warn(
				"VersionCheck",
				("%s has version_check 'yes' but is missing 'github' or 'version' in its fxmanifest"):format(resourceName),
				{ console = true }
			)
			return
		end

		local branch = GetResourceMetadata(resourceName, "github_branch", 0) or "main"
		local label = GetResourceMetadata(resourceName, "name", 0) or resourceName
		local url = resolveManifestUrl(github, branch)
		if not url then
			COMPONENTS.Logger:Warn("VersionCheck", ("%s has an invalid 'github' url in its fxmanifest: %s"):format(resourceName, tostring(github)), { console = true })
			return
		end

		_checked[resourceName] = true

		PerformHttpRequest(url, function(status, body)
			if status ~= 200 or not body then
				COMPONENTS.Logger:Warn("VersionCheck", ("Failed to check %s for updates (HTTP %s) - %s"):format(resourceName, tostring(status), url), { console = true })
				return
			end

			local latest = parseManifestVersion(body)
			if not latest then
				COMPONENTS.Logger:Warn("VersionCheck", ("%s's fxmanifest.lua on GitHub has no 'version' field: %s"):format(resourceName, url), { console = true })
				return
			end

			if latest == version then
				print(("[^2VERSION^7]\t[^6%s^7] up to date (%s)"):format(label, version))
				return
			end

			print(("[^1VERSION^7]\t[^6%s^7] ^1outdated^7 - running %s, latest is ^3%s^7 (%s)"):format(label, version, latest, github))
		end, "GET")
	end,

	RunAll = function(self)
		_checked = {}
		local total = GetNumResources()
		for i = 0, total - 1 do
			local resource = GetResourceByFindIndex(i)
			if resource then
				self:Run(resource)
			end
		end
	end,
}

AddEventHandler("Core:Server:StartupReady", function()
	CreateThread(function()
		Wait(2000) -- let every autostart resource finish spinning up first
		COMPONENTS.VersionCheck:RunAll()
	end)
end)

AddEventHandler("onResourceStart", function(resource)
	if resource == GetCurrentResourceName() then
		return
	end
	if not COMPONENTS.Proxy.ExportsReady then
		return
	end

	CreateThread(function()
		Wait(1000)
		COMPONENTS.VersionCheck:Run(resource)
	end)
end)
