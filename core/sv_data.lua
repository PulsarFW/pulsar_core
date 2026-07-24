local _inserting = {}

local function seedTableName(collection)
	return "seed_" .. tostring(collection):gsub("[^%w_]", "_")
end

local function ensureVersionsTable(callback)
	COMPONENTS.Database:Query(
		"CREATE TABLE IF NOT EXISTS `seed_versions` (`collection` VARCHAR(191) PRIMARY KEY, `date` BIGINT NOT NULL)",
		nil,
		callback
	)
end

local function doAdd(collection, date, data)
	CreateThread(function()
		while _inserting[collection] ~= nil do
			Wait(10)
		end
		_inserting[collection] = true

		ensureVersionsTable(function()
			COMPONENTS.Database:Single("SELECT `date` FROM `seed_versions` WHERE `collection` = ?", { collection }, function(success, row)
				if not success then
					DBLog(("Default:Add failed to check seed version for '%s': %s"):format(collection, tostring(row)))
					_inserting[collection] = nil
					return
				end

				if row ~= nil and tonumber(row.date) >= date then
					_inserting[collection] = nil
					return
				end

				local tableName = seedTableName(collection)
				COMPONENTS.Database:Query(
					"CREATE TABLE IF NOT EXISTS `" .. tableName .. "` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `data` JSON NOT NULL)",
					nil,
					function()
						COMPONENTS.Database:Update("DELETE FROM `" .. tableName .. "`", nil, function(deleted)
							if not deleted then
								DBLog(("Default:Add failed clearing old seed records for '%s'"):format(collection))
								_inserting[collection] = nil
								return
							end

							local queries = {}
							for _, record in ipairs(data) do
								table.insert(queries, {
									query = "INSERT INTO `" .. tableName .. "` (`data`) VALUES (?)",
									values = { json.encode(record) },
								})
							end

							COMPONENTS.Database:Transaction(queries, function(inserted)
								if not inserted then
									DBLog(("Default:Add failed inserting seed records for '%s'"):format(collection))
									_inserting[collection] = nil
									return
								end

								COMPONENTS.Database:Update(
									"INSERT INTO `seed_versions` (`collection`, `date`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `date` = VALUES(`date`)",
									{ collection, date },
									function()
										_inserting[collection] = nil
									end
								)
							end)
						end)
					end
				)
			end)
		end)
	end)
end

COMPONENTS.Default = {
	_required = { "Add" },
	_name = "core",
	_protected = true,
	-- Both Add and AddAuth write to the same MariaDB connection now (there's only one database),
	-- kept as two names for call-site compatibility with existing resources.
	Add = function(self, collection, date, data)
		doAdd(collection, date, data)
	end,
	AddAuth = function(self, collection, date, data)
		doAdd(collection, date, data)
	end,
}
