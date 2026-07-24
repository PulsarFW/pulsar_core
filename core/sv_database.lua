function DBLog(message)
	TriggerEvent("Logger:Error", "Database", message, {
		console = true,
		file = true,
		discord = { style = "error" },
	})
end

function DBLogTrace(message)
	TriggerEvent("Logger:Trace", "Database", message, { console = true })
end

-- Wraps one of oxmysql's async methods (query/single/scalar/insert/update/prepare/rawExecute),
-- normalizing its (result, error) callback into this codebase's (success, result) convention.
local function wrap(method)
	return function(self, sql, params, callback)
		MySQL[method](sql, params, function(result, err)
			if err then
				DBLog(("%s failed: %s | SQL: %s"):format(method, tostring(err), sql))
				if callback then
					callback(false, tostring(err))
				end
				return
			end
			if callback then
				callback(true, result)
			end
		end)
	end
end

local DATABASE = {
	_protected = true,
	_name = "core",

	-- SELECT, returns every matching row.
	Query = wrap("query"),
	-- SELECT, returns the first matching row (or nil).
	Single = wrap("single"),
	-- SELECT, returns a single value (e.g. COUNT(*)).
	Scalar = wrap("scalar"),
	-- INSERT, returns the new row's auto-increment id.
	Insert = wrap("insert"),
	-- UPDATE/DELETE/etc, returns the affected row count.
	Update = wrap("update"),
	-- Prepared statement (cached query plan) for hot-path queries run often with different params.
	Prepare = wrap("prepare"),
	-- Escape hatch for anything the above don't cover (DDL, multi-statement, etc.).
	RawExecute = wrap("rawExecute"),

	-- queries: array of { query = "...", values = {...} }. Runs atomically; all-or-nothing.
	Transaction = function(self, queries, callback)
		MySQL.transaction(queries, function(success)
			if not success then
				DBLog("Transaction failed and was rolled back.")
			end
			if callback then
				callback(success)
			end
		end)
	end,
}

AddEventHandler("Database:Server:Initialize", function()
	MySQL.ready(function()
		DBLogTrace("[^2MariaDB^7] Connected and ready.")
		TriggerEvent("Database:Server:Ready", DATABASE)
	end)
end)
