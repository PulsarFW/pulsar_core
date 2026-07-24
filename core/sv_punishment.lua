local _bansTableReady = false
local function ensureBansTable(callback)
	if _bansTableReady then
		if callback then
			callback()
		end
		return
	end
	COMPONENTS.Database:Query(
		[[
		CREATE TABLE IF NOT EXISTS `bans` (
			`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
			`account` BIGINT UNSIGNED NULL,
			`identifier` VARCHAR(191) NULL,
			`tokens` JSON NULL,
			`expires` BIGINT NOT NULL,
			`reason` TEXT,
			`issuer` VARCHAR(191),
			`active` TINYINT(1) NOT NULL DEFAULT 1,
			`started` BIGINT,
			`unbanned_issuer` VARCHAR(191) NULL,
			`unbanned_date` BIGINT NULL,
			INDEX `idx_account` (`account`),
			INDEX `idx_identifier` (`identifier`),
			INDEX `idx_active` (`active`)
		)
	]],
		nil,
		function()
			_bansTableReady = true
			if callback then
				callback()
			end
		end
	)
end

local function rowToBan(row)
	if row == nil then
		return nil
	end
	local tokens = {}
	if row.tokens and row.tokens ~= "" then
		local ok, decoded = pcall(json.decode, row.tokens)
		if ok and type(decoded) == "table" then
			tokens = decoded
		end
	end
	return {
		_id = tostring(row.id),
		account = row.account,
		identifier = row.identifier,
		tokens = tokens,
		expires = tonumber(row.expires),
		reason = row.reason,
		issuer = row.issuer,
		active = row.active == 1,
		started = row.started,
	}
end

COMPONENTS.Punishment = {
	_required = { "CheckBan", "Kick", "Unban", "Ban" },
	_name = "core",
	-- key: "_id" (maps to the real `id` column), "account", or "identifier".
	CheckBan = function(self, key, value)
		local column = (key == "_id") and "id" or key
		if column ~= "id" and column ~= "account" and column ~= "identifier" then
			COMPONENTS.Logger:Error("Punishment", "CheckBan called with invalid key: " .. tostring(key), { console = true })
			return nil
		end

		local p = promise.new()

		ensureBansTable(function()
			COMPONENTS.Database:Query(
				"SELECT * FROM `bans` WHERE `" .. column .. "` = ? AND `active` = 1",
				{ value },
				function(success, results)
					if not success then
						COMPONENTS.Logger:Error(
							"Database",
							"[^8Error^7] Error checking ban: " .. tostring(results),
							{ console = true, file = true, database = true }
						)
						p:resolve(nil)
						return
					end

					if results and #results > 0 then
						for _, row in ipairs(results) do
							local ban = rowToBan(row)
							if ban.expires ~= -1 and ban.expires < os.time() then
								COMPONENTS.Database:Update("UPDATE `bans` SET `active` = 0 WHERE `id` = ?", { row.id })
							else
								p:resolve(ban)
								return
							end
						end
						p:resolve(nil)
					else
						p:resolve(nil)
					end
				end
			)
		end)

		return Citizen.Await(p)
	end,
	-- Checks whether any of the given client tokens (GetPlayerToken values) match a token on an
	-- active ban. Previously lived on a separate "Auth" Mongo database as its own ban list; now
	-- unified onto this same `bans` table per the framework's single-MariaDB design.
	CheckTokenBan = function(self, tokens)
		if not tokens or #tokens == 0 then
			return nil
		end

		local p = promise.new()

		ensureBansTable(function()
			COMPONENTS.Database:Query(
				"SELECT * FROM `bans` WHERE `active` = 1 AND `tokens` IS NOT NULL AND (`expires` = -1 OR `expires` > ?)",
				{ os.time() },
				function(success, results)
					if not success or not results then
						p:resolve(nil)
						return
					end

					local best = nil
					for _, row in ipairs(results) do
						local ban = rowToBan(row)
						local matches = false
						for _, banToken in ipairs(ban.tokens) do
							for _, myToken in ipairs(tokens) do
								if banToken == myToken then
									matches = true
									break
								end
							end
							if matches then
								break
							end
						end

						if matches then
							if best == nil then
								best = ban
							elseif best.expires ~= -1 and ban.expires == -1 then
								best = ban
							elseif ban.expires ~= -1 and best.expires ~= -1 and ban.expires > best.expires then
								best = ban
							end
						end
					end

					p:resolve(best)
				end
			)
		end)

		return Citizen.Await(p)
	end,
	Kick = function(self, source, reason, issuer, afk)
		local tPlayer = COMPONENTS.Fetch:Source(source)

		if not tPlayer then
			return {
				success = false,
			}
		end

		if issuer ~= "Pwnzor" then
			if source == issuer then
				return {
					success = false,
					message = "Cannot Ban Yourself!",
				}
			end

			local iPlayer = COMPONENTS.Fetch:Source(issuer)

			if not iPlayer then
				return {
					success = false,
				}
			end

			if iPlayer.Permissions:GetLevel() <= tPlayer.Permissions:GetLevel() then
				return {
					success = false,
					message = "Insufficient Permissions",
				}
			end

			COMPONENTS.Logger:Info(
				"Punishment",
				string.format(
					"%s [%s] Kicked By %s [%s] For %s",
					tPlayer:GetData("Name"),
					tPlayer:GetData("AccountID"),
					iPlayer:GetData("Name"),
					iPlayer:GetData("AccountID"),
					reason
				),
				{ console = true, file = true, database = true, discord = { embed = true, type = "inform" } },
				{
					account = tPlayer:GetData("AccountID"),
					identifier = tPlayer:GetData("Identifier"),
					reason = reason,
					issuer = string.format("%s [%s]", iPlayer:GetData("Name"), iPlayer:GetData("AccountID")),
				}
			)

			COMPONENTS.Punishment.Actions:Kick(source, reason, iPlayer:GetData("Name"))
			return {
				success = true,
				Name = tPlayer:GetData("Name"),
				AccountID = tPlayer:GetData("AccountID"),
				reason = reason,
			}
		else
			if not afk then
				COMPONENTS.Logger:Info(
					"Punishment",
					string.format(
						"%s [%s] Kicked By %s For %s",
						tPlayer:GetData("Name"),
						tPlayer:GetData("AccountID"),
						issuer,
						reason
					),
					{
						console = true,
						file = true,
						database = true,
						discord = { embed = true, type = "inform", webhook = GetConvar("discord_pwnzor_webhook", "") },
					},
					{
						account = tPlayer:GetData("AccountID"),
						identifier = tPlayer:GetData("Identifier"),
						reason = reason,
						issuer = issuer,
					}
				)
			end
			COMPONENTS.Punishment.Actions:Kick(source, reason, issuer)

			return {
				success = true,
				Name = tPlayer:GetData("Name"),
				AccountID = tPlayer:GetData("AccountID"),
				reason = reason,
			}
		end
	end,
}

COMPONENTS.Punishment.Unban = {
	BanID = function(self, id, issuer)
		local iPlayer = COMPONENTS.Fetch:Source(issuer)
		local ban = COMPONENTS.Punishment:CheckBan("_id", id)

		if ban then
			if COMPONENTS.Punishment.Actions:Unban({ ban }, iPlayer) then
				COMPONENTS.Chat.Send.Server:Single(
					iPlayer:GetData("Source"),
					string.format("%s Has Been Revoked", id)
				)
			end
		end
	end,
	AccountID = function(self, aId, issuer)
		local iPlayer = COMPONENTS.Fetch:Source(issuer)
		local tPlayer = COMPONENTS.Fetch:PlayerData("AccountID", aId)
		local dbf = false

		if tPlayer == nil then
			tPlayer = COMPONENTS.Fetch:Website("account", aId)
			dbf = true
		end

		local ban = COMPONENTS.Punishment:CheckBan("account", aId)

		if ban then
			if COMPONENTS.Punishment.Actions:Unban({ ban }, iPlayer) then
				COMPONENTS.Chat.Send.Server:Single(
					iPlayer:GetData("Source"),
					string.format(
						"%s (Account: %s) Has Been Unbanned",
						tPlayer:GetData("Name"),
						tPlayer:GetData("AccountID")
					)
				)
			end
		else
			COMPONENTS.Chat.Send.Server:Single(
				iPlayer:GetData("Source"),
				string.format("%s (Account: %s) Is Not Banned", tPlayer:GetData("Name"), tPlayer:GetData("AccountID"))
			)
		end

		if dbf then
			tPlayer:DeleteStore()
		end
	end,
	Identifier = function(self, identifier, issuer)
		local iPlayer = COMPONENTS.Fetch:Source(issuer)
		local tPlayer = COMPONENTS.Fetch:PlayerData("Identifier", identifier)
		local dbf = false

		if tPlayer == nil then
			tPlayer = COMPONENTS.Fetch:Website("identifier", identifier)
			dbf = true
		end

		local ban = COMPONENTS.Punishment:CheckBan("identifier", identifier)

		if ban then
			if COMPONENTS.Punishment.Actions:Unban({ ban }, iPlayer) then
				COMPONENTS.Chat.Send.Server:Single(
					iPlayer:GetData("Source"),
					string.format(
						"%s (Identifier: %s) Has Been Unbanned",
						tPlayer:GetData("Name"),
						tPlayer:GetData("Identifier")
					)
				)
			end
		else
			COMPONENTS.Chat.Send.Server:Single(
				iPlayer:GetData("Source"),
				string.format(
					"%s (Identifier: %s) Is Not Banned",
					tPlayer:GetData("Name"),
					tPlayer:GetData("Identifier")
				)
			)
		end

		if dbf then
			tPlayer:DeleteStore()
		end
	end,
}

COMPONENTS.Punishment.Ban = {
	Source = function(self, source, expires, reason, issuer)
		local tPlayer = COMPONENTS.Fetch:Source(source)
		local iPlayer

		if not tPlayer then
			return {
				success = false,
			}
		end

		if issuer ~= "Pwnzor" then
			if source == issuer then
				return {
					success = false,
					message = "Cannot Ban Yourself!",
				}
			end

			iPlayer = COMPONENTS.Fetch:Source(issuer)
			if not iPlayer then
				return {
					success = false,
				}
			end

			if iPlayer.Permissions:GetLevel() <= tPlayer.Permissions:GetLevel() then
				return {
					success = false,
					message = "Insufficient Permissions",
				}
			end

			issuer = string.format("%s [%s]", iPlayer:GetData("Name"), iPlayer:GetData("AccountID"))
		end

		local expStr = "Never"
		if expires ~= -1 then
			expires = (os.time() + ((60 * 60 * 24) * expires))
			expStr = os.date("%Y-%m-%d at %I:%M:%S %p", expires)
		end

		local banStr = string.format("%s Was Permanently Banned By %s for %s", tPlayer:GetData("Name"), issuer, reason)

		if expires ~= -1 then
			banStr = string.format(
				"%s Was Banned By %s Until %s for %s",
				tPlayer:GetData("Name"),
				issuer,
				expStr,
				reason
			)
		end

		if iPlayer ~= nil then
			COMPONENTS.Punishment.Actions:Ban(
				tPlayer:GetData("Source"),
				tPlayer:GetData("AccountID"),
				tPlayer:GetData("Identifier"),
				tPlayer:GetData("Name"),
				tPlayer:GetData("Tokens"),
				reason,
				expires,
				expStr,
				issuer,
				iPlayer:GetData("AccountID"),
				false
			)
		else
			COMPONENTS.Punishment.Actions:Ban(
				tPlayer:GetData("Source"),
				tPlayer:GetData("AccountID"),
				tPlayer:GetData("Identifier"),
				tPlayer:GetData("Name"),
				tPlayer:GetData("Tokens"),
				reason,
				expires,
				expStr,
				issuer,
				-1,
				true
			)
		end

		COMPONENTS.Logger:Info(
			"Punishment",
			banStr,
			{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
			{
				player = tPlayer:GetData("Name"),
				identifier = tPlayer:GetData("Identifier"),
				reason = reason,
				issuer = issuer,
				expires = expStr,
			}
		)

		return {
			success = true,
			Name = tPlayer:GetData("Name"),
			AccountID = tPlayer:GetData("AccountID"),
			expires = expires,
			reason = reason,
			banStr = banStr,
		}
	end,
	AccountID = function(self, aId, expires, reason, issuer)
		local iPlayer = COMPONENTS.Fetch:Source(issuer)
		if not iPlayer then
			return {
				success = false,
			}
		end

		if iPlayer:GetData("AccountID") == tonumber(aId) then
			return {
				success = false,
				message = "Cannot Ban Yourself!",
			}
		end

		local tPlayer = COMPONENTS.Fetch:PlayerData("AccountID", tonumber(aId))

		issuer = string.format("%s [%s]", iPlayer:GetData("Name"), iPlayer:GetData("AccountID"))

		local dbf = false
		if tPlayer == nil then
			tPlayer = COMPONENTS.Fetch:Website("account", tonumber(aId))
			dbf = true
		end

		local bannedPlayer = tonumber(aId)

		local expStr = "Never"
		if expires ~= -1 then
			expires = (os.time() + ((60 * 60 * 24) * expires))
			expStr = os.date("%Y-%m-%d at %I:%M:%S %p", expires)
		end

		local banStr = string.format(
			"%s (Account: %s) Was Permanently Banned By %s. Reason: %s",
			tPlayer and tPlayer:GetData("Name") or "Unknown",
			tPlayer and tPlayer:GetData("AccountID") or bannedPlayer,
			issuer,
			reason
		)

		if expires ~= -1 then
			banStr = string.format(
				"%s (Account: %s) Was Banned By %s Until %s. Reason: %s",
				(tPlayer and tPlayer:GetData("Name") or "Unknown"),
				(tPlayer and tPlayer:GetData("AccountID") or bannedPlayer),
				issuer,
				expStr,
				reason
			)
		end

		if tPlayer == nil then
			if
				COMPONENTS.Punishment.Actions:Ban(
					nil,
					tonumber(aId),
					nil,
					bannedPlayer,
					{},
					reason,
					expires,
					expStr,
					issuer,
					iPlayer:GetData("AccountID"),
					false
				)
			then
				COMPONENTS.Logger:Info(
					"Punishment",
					banStr,
					{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
					{
						player = bannedPlayer,
						account = tonumber(aId),
						reason = reason,
						issuer = issuer,
						expires = expStr,
					}
				)

				return {
					success = true,
					AccountID = tonumber(aId),
					reason = reason,
					expires = expires,
					banStr = banStr,
				}
			end
		else
			local tPerms = 0

			if tPlayer:GetData("Source") ~= nil then
				for k, v in ipairs(tPlayer:GetData("Groups")) do
					if COMPONENTS.Config.Groups[tostring(v)].Permission then
						if COMPONENTS.Config.Groups[tostring(v)].Permission.Level > tPerms then
							tPerms = COMPONENTS.Config.Groups[tostring(v)].Permission.Level
						end
					end
				end
			else
				-- Offline so Cannot Get Groups - Just allow devs for now
				tPerms = 99
			end

			if iPlayer.Permissions:GetLevel() <= tPerms then
				return {
					success = false,
					message = "Insufficient Permissions",
				}
			end

			if
				COMPONENTS.Punishment.Actions:Ban(
					tPlayer:GetData("Source"),
					tPlayer:GetData("AccountID"),
					tPlayer:GetData("Identifier"),
					tPlayer:GetData("Name"),
					tPlayer:GetData("Tokens"),
					reason,
					expires,
					expStr,
					issuer,
					iPlayer:GetData("AccountID"),
					false
				)
			then
				COMPONENTS.Logger:Info(
					"Punishment",
					banStr,
					{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
					{
						player = bannedPlayer,
						account = tPlayer:GetData("AccountID"),
						identifier = tPlayer:GetData("Identifier"),
						reason = reason,
						issuer = issuer,
						expires = expStr,
					}
				)

				local retData = {
					success = true,
					Name = tPlayer:GetData("Name"),
					AccountID = tPlayer:GetData("AccountID"),
					expires = expires,
					reason = reason,
					banStr = banStr,
				}

				CreateThread(function()
					if dbf and tPlayer then
						tPlayer:DeleteStore()
					end
				end)

				return retData
			end
		end
	end,
	Identifier = function(self, identifier, expires, reason, issuer)
		local iPlayer = COMPONENTS.Fetch:Source(issuer)
		if not iPlayer then
			return {
				success = false,
			}
		end

		if iPlayer:GetData("Identifier") == identifier then
			return {
				success = false,
				message = "Cannot Ban Yourself!",
			}
		end

		local tPlayer = COMPONENTS.Fetch:PlayerData("Identifier", identifier)

		issuer = string.format("%s [%s]", iPlayer:GetData("Name"), iPlayer:GetData("AccountID"))

		local dbf = false
		if tPlayer == nil then
			tPlayer = COMPONENTS.Fetch:Website("identifier", identifier)
			dbf = true
		end

		local expStr = "Never"
		if expires ~= -1 then
			expires = (os.time() + ((60 * 60 * 24) * expires))
			expStr = os.date("%Y-%m-%d at %I:%M:%S %p", expires)
		end

		local banStr = string.format(
			"%s (Identifier: %s) Was Permanently Banned By %s. Reason: %s",
			tPlayer and tPlayer:GetData("Name") or "Unknown",
			tPlayer and tPlayer:GetData("Identifier") or identifier,
			issuer,
			reason
		)
		if expires ~= -1 then
			banStr = string.format(
				"%s (Identifier: %s) Was Banned By %s Until %s. Reason: %s",
				tPlayer and tPlayer:GetData("Name") or "Unknown",
				tPlayer and tPlayer:GetData("Identifier") or identifier,
				issuer,
				expStr,
				reason
			)
		end

		if tPlayer == nil then
			if
				COMPONENTS.Punishment.Actions:Ban(
					nil,
					nil,
					identifier,
					"Unknown",
					{},
					reason,
					expires,
					expStr,
					issuer,
					iPlayer:GetData("AccountID"),
					false
				)
			then
				COMPONENTS.Logger:Info(
					"Punishment",
					banStr,
					{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
					{
						player = identifier,
						identifier = identifier,
						reason = reason,
						issuer = issuer,
						expires = expStr,
					}
				)

				if dbf and tPlayer then
					tPlayer:DeleteStore()
				end

				return {
					success = true,
					Identifier = identifier,
					reason = reason,
					expires = expires,
					banStr = banStr,
				}
			end
		else
			local tPerms = 0

			if tPlayer:GetData("Source") ~= nil then
				for k, v in ipairs(tPlayer:GetData("Groups")) do
					if COMPONENTS.Config.Groups[tostring(v)].Permission then
						if COMPONENTS.Config.Groups[tostring(v)].Permission.Level > tPerms then
							tPerms = COMPONENTS.Config.Groups[tostring(v)].Permission.Level
						end
					end
				end
			else
				-- Offline so Cannot Get Groups - Just allow devs for now
				tPerms = 99
			end

			if iPlayer.Permissions:GetLevel() <= tPerms then
				return {
					success = false,
					message = "Insufficient Permissions",
				}
			end

			if
				COMPONENTS.Punishment.Actions:Ban(
					tPlayer:GetData("Source"),
					tPlayer:GetData("AccountID"),
					tPlayer:GetData("Identifier"),
					tPlayer:GetData("Name"),
					tPlayer:GetData("Tokens"),
					reason,
					expires,
					expStr,
					issuer,
					iPlayer:GetData("AccountID"),
					false
				)
			then
				COMPONENTS.Logger:Info(
					"Punishment",
					banStr,
					{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
					{
						player = tPlayer:GetData("Name"),
						account = tPlayer:GetData("AccountID"),
						identifier = tPlayer:GetData("Identifier"),
						reason = reason,
						issuer = issuer,
						expires = expStr,
					}
				)

				local retData = {
					success = true,
					Name = tPlayer:GetData("Name"),
					AccountID = tPlayer:GetData("AccountID"),
					Identifier = tPlayer:GetData("Identifier"),
					expires = expires,
					reason = reason,
					banStr = banStr,
				}

				if dbf and tPlayer then
					tPlayer:DeleteStore()
				end

				return retData
			end
		end

		if dbf then
			tPlayer:DeleteStore()
		end
	end,
}

COMPONENTS.Punishment.Actions = {
	Kick = function(self, tSource, reason, issuer)
		DropPlayer(tSource, string.format("Kicked From The Server By %s\nReason: %s", issuer, reason))
	end,
	Ban = function(self, tSource, tAccount, tIdentifier, tName, tTokens, reason, expires, expStr, issuer, issuerId, mask)
		local p = promise.new()

		ensureBansTable(function()
			local where, whereParams = {}, {}
			if tAccount then
				table.insert(where, "`account` = ?")
				table.insert(whereParams, tAccount)
			end
			if tIdentifier then
				table.insert(where, "`identifier` = ?")
				table.insert(whereParams, tIdentifier)
			end

			if #where == 0 then
				p:resolve(false)
				return
			end

			COMPONENTS.Database:Single(
				"SELECT `id` FROM `bans` WHERE `active` = 1 AND (" .. table.concat(where, " OR ") .. ") LIMIT 1",
				whereParams,
				function(success, existingRow)
					if not success then
						p:resolve(false)
						return COMPONENTS.Logger:Error(
							"Database",
							"[^8Error^7] Error in ban upsert: " .. tostring(existingRow),
							{ console = true, file = true, database = true, discord = { embed = true, type = "error" } }
						)
					end

					local tokensJson = json.encode(tTokens or {})

					local function finish(banId)
						p:resolve(true)

						if mask then
							reason = "💙 From Pwnzor 🙂"
						end

						if tSource ~= nil then
							if expires ~= -1 then
								DropPlayer(
									tSource,
									string.format(
										"You're Banned, Appeal in Discord\n\nReason: %s\nExpires: %s\nID: %s",
										reason,
										expStr,
										banId
									)
								)
							else
								DropPlayer(
									tSource,
									string.format(
										"You're Permanently Banned, Appeal in Discord\n\nReason: %s\nID: %s",
										reason,
										banId
									)
								)
							end
						end
					end

					if existingRow then
						-- Merges new tokens into the existing set (like the old $addToSet) — note
						-- JSON_MERGE_PRESERVE doesn't dedupe, so repeated bans of the same account
						-- can accumulate duplicate token entries over time; harmless for the "is
						-- this token banned" $in-style lookups that read this field.
						COMPONENTS.Database:Update(
							"UPDATE `bans` SET `account` = ?, `identifier` = ?, `expires` = ?, `reason` = ?, `issuer` = ?, `active` = 1, `started` = ?, `tokens` = JSON_MERGE_PRESERVE(COALESCE(`tokens`, JSON_ARRAY()), ?) WHERE `id` = ?",
							{ tAccount, tIdentifier, expires, reason, issuer, os.time(), tokensJson, existingRow.id },
							function(updateSuccess)
								if not updateSuccess then
									p:resolve(false)
									return
								end
								finish(existingRow.id)
							end
						)
					else
						COMPONENTS.Database:Insert(
							"INSERT INTO `bans` (`account`, `identifier`, `expires`, `reason`, `issuer`, `active`, `started`, `tokens`) VALUES (?, ?, ?, ?, ?, 1, ?, ?)",
							{ tAccount, tIdentifier, expires, reason, issuer, os.time(), tokensJson },
							function(insertSuccess, newId)
								if not insertSuccess then
									p:resolve(false)
									return
								end
								finish(newId)
							end
						)
					end
				end
			)
		end)

		return Citizen.Await(p)
	end,
	Unban = function(self, ids, issuer)
		local _ids = {}
		for k, v in ipairs(ids) do
			COMPONENTS.Database:Update(
				"UPDATE `bans` SET `active` = 0, `unbanned_issuer` = ?, `unbanned_date` = ? WHERE `id` = ? AND `active` = 1",
				{ issuer:GetData("Name"), os.time(), v._id }
			)

			table.insert(_ids, v._id)
		end

		COMPONENTS.Logger:Info(
			"Punishment",
			string.format("%s Bans Revoked By %s [%s]", #ids, issuer:GetData("Name"), issuer:GetData("AccountID")),
			{ console = true, file = true, database = true, discord = { embed = true, type = "info" } },
			{
				issuer = string.format("%s [%s]", issuer:GetData("Name"), issuer:GetData("AccountID")),
			},
			_ids
		)

		return true
	end,
}
