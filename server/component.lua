_charPropertyKeys = {}

-- `type`/`sold`/`foreclosed`/`label` are real columns since other resources filter on them
-- across rows (spawn-point property lookup, Dyn8 search); everything else stays in `data`.
-- `id`/`_id`/`locked` are runtime-only (locked always resets on reload) so they're stripped
-- before persisting, same idea as characters' _noUpdate list.
local _propertiesTableReady = false
function EnsurePropertiesTable(callback)
	if _propertiesTableReady then
		if callback then
			callback()
		end
		return
	end
	plsr.Database:Query(
		"CREATE TABLE IF NOT EXISTS `properties` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `type` VARCHAR(191) NULL, `sold` TINYINT(1) NOT NULL DEFAULT 0, `foreclosed` TINYINT(1) NOT NULL DEFAULT 0, `label` VARCHAR(191) NULL, `data` JSON NOT NULL, INDEX `idx_type` (`type`), INDEX `idx_sold` (`sold`), INDEX `idx_foreclosed` (`foreclosed`), INDEX `idx_label` (`label`))",
		nil,
		function()
			plsr.Database:Query(
				"CREATE TABLE IF NOT EXISTS `property_keys` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `property_id` BIGINT UNSIGNED NOT NULL, `character_id` BIGINT UNSIGNED NOT NULL, `owner` TINYINT(1) NOT NULL DEFAULT 0, `data` JSON NULL, UNIQUE INDEX `idx_property_char` (`property_id`, `character_id`), INDEX `idx_character` (`character_id`))",
				nil,
				function()
					plsr.Database:Query(
						"CREATE TABLE IF NOT EXISTS `property_upgrades` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `property_id` BIGINT UNSIGNED NOT NULL, `upgrade` VARCHAR(191) NOT NULL, `level` VARCHAR(191) NOT NULL, UNIQUE INDEX `idx_property_upgrade` (`property_id`, `upgrade`))",
						nil,
						function()
							plsr.Database:Query(
								"CREATE TABLE IF NOT EXISTS `properties_furniture` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `property_id` BIGINT UNSIGNED NOT NULL, `data` JSON NOT NULL, UNIQUE INDEX `idx_property_id` (`property_id`))",
								nil,
								function()
									_propertiesTableReady = true
									if callback then
										callback()
									end
								end
							)
						end
					)
				end
			)
		end
	)
end

-- `keys`/`upgrades` live in their own tables now (real one-to-many relations), not in `data`.
local _transientPropertyFields = { "id", "_id", "locked", "keys", "upgrades" }

function PersistProperty(id, property, callback)
	local toEncode = {}
	for k, v in pairs(property) do
		toEncode[k] = v
	end
	for k, v in ipairs(_transientPropertyFields) do
		toEncode[v] = nil
	end

	EnsurePropertiesTable(function()
		plsr.Database:Update(
			"UPDATE `properties` SET `type` = ?, `sold` = ?, `foreclosed` = ?, `label` = ?, `data` = ? WHERE `id` = ?",
			{ toEncode.type, toEncode.sold and 1 or 0, toEncode.foreclosed and 1 or 0, toEncode.label, json.encode(toEncode), id },
			function(success, updated)
				if callback then
					callback(success and updated > 0)
				end
			end
		)
	end)
end

CreateThread(function()
	RegisterChatCommands()
	RegisterCallbacks()
	RegisterMiddleware()
	DefaultData()
	Startup()

	CreateFurnitureCallbacks()

	SetupPropertyCrafting()
end)


PROPERTIES = {
	Manage = {
		Add = function(self, source, type, interior, price, label, pos)
			if PropertyTypes[type] then
				if PropertyInteriors[interior] and PropertyInteriors[interior].type == type then
					local p = promise.new()
					local doc = {
						type = type,
						label = label,
						price = price,
						sold = false,
						owner = false,
						location = {
							front = pos,
						},
					}

					EnsurePropertiesTable(function()
						plsr.Database:Insert(
							"INSERT INTO `properties` (`type`, `sold`, `label`, `data`) VALUES (?, 0, ?, ?)",
							{ type, label, json.encode(doc) },
							function(success, newId)
								if not success then
									p:resolve(false)
									return
								end

								plsr.Database:Update(
									"INSERT INTO `property_upgrades` (`property_id`, `upgrade`, `level`) VALUES (?, 'interior', ?)",
									{ newId, interior },
									function()
										doc.id = newId
										doc.interior = interior
										doc.locked = true
										doc.upgrades = { interior = interior }

										for k, v in pairs(doc.location) do
											for k2, v2 in pairs(v) do
												doc.location[k][k2] = doc.location[k][k2] + 0.0
											end
										end

										_properties[doc.id] = doc

										plsr.Chat.Send.Server:Single(source, "Property Added, Property ID: " .. doc.id)

										TriggerClientEvent("Properties:Client:Update", -1, doc.id, doc)

										p:resolve(true)
									end
								)
							end
						)
					end)
					return Citizen.Await(p)
				else
					plsr.Chat.Send.Server:Single(source, "Invalid Interior Combination")
					return false
				end
			else
				plsr.Chat.Send.Server:Single(source, "Invalid Property Type")
				return false
			end
		end,
		AddFrontdoor = function(self, id, pos)
			if not _properties[id] or not pos then
				return false
			end

			local p = promise.new()
			if _properties[id] and _properties[id].location then
				_properties[id].location.front = pos
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] and _properties[id].location then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		AddBackdoor = function(self, id, pos)
			if not _properties[id] or not pos then
				return false
			end

			local p = promise.new()
			if _properties[id] and _properties[id].location then
				_properties[id].location.backdoor = pos
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] and _properties[id].location then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		AddGarage = function(self, id, pos)
			if not _properties[id] or pos == nil then
				return false
			end

			local p = promise.new()
			if _properties[id] and _properties[id].location then
				_properties[id].location.garage = pos
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] and _properties[id].location then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		SetLabel = function(self, id, label)
			if not _properties[id] or not label then
				return false
			end

			local p = promise.new()
			if _properties[id] and _properties[id].label then
				_properties[id].label = label
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] and _properties[id].label then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		SetPrice = function(self, id, price)
			if not _properties[id] or not price then
				return false
			end

			local p = promise.new()
			if _properties[id] and _properties[id].price then
				_properties[id].price = price
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] and _properties[id].price then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		SetData = function(self, id, key, value)
			if not key or not _properties[id] then
				return false
			end

			local p = promise.new()
			if _properties[id] then
				if not _properties[id].data then
					_properties[id].data = {}
				end
				_properties[id].data[key] = value
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		Delete = function(self, id)
			local p = promise.new()
			EnsurePropertiesTable(function()
				plsr.Database:Update("DELETE FROM `properties` WHERE `id` = ?", { id }, function(success)
					if success then
						_properties[id] = nil

						TriggerClientEvent("Properties:Client:Update", -1, id, nil)
					end
					p:resolve(success)
				end)
			end)
			return Citizen.Await(p)
		end,
	},
	Upgrades = {
		Set = function(self, id, upgrade, level)
			local property = _properties[id]
			if property then
				local upgradeData = PropertyUpgrades[property.type][upgrade]
				if upgradeData and upgrade ~= "interior" then

					if level < 1 then
						level = 1
					end

					if level > #upgradeData.levels then
						level = #upgradeData.levels
					end

					local p = promise.new()
					EnsurePropertiesTable(function()
						plsr.Database:Update(
							"INSERT INTO `property_upgrades` (`property_id`, `upgrade`, `level`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `level` = VALUES(`level`)",
							{ id, upgrade, level },
							function(success)
								if success and _properties[id] then
									if not _properties[id].upgrades then
										_properties[id].upgrades = {}
									end
									_properties[id].upgrades[upgrade] = level

									TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
								end

								p:resolve(success)
							end
						)
					end)
					return Citizen.Await(p)
				end
			end

			return false
		end,
		Get = function(self, id, upgrade)
			local property = _properties[id]
			if property and property.upgrades and property.upgrades[upgrade] then
				return property.upgrades[upgrade]
			end
			return 1
		end,
		Increase = function(self, id, upgrade)
			local property = _properties[id]
			if property then
				local currentLevel = plsr.Properties.Upgrades:Get(id, upgrade)
				local success = plsr.Properties.Upgrades:Set(id, upgrade, currentLevel + 1)

				return success
			end
			return false
		end,
		Decrease = function(self, id, upgrade)
			local property = _properties[id]
			if property then
				local currentLevel = plsr.Properties.Upgrades:Get(id, upgrade)
				local success = plsr.Properties.Upgrades:Set(id, upgrade, currentLevel - 1)

				return success
			end
			return false
		end,
		SetInterior = function(self, id, interior)
			local property = _properties[id]
			if property then
				local intData = PropertyInteriors[interior]

				if intData and intData.type == property.type then
					local p = promise.new()
					EnsurePropertiesTable(function()
						plsr.Database:Update(
							"INSERT INTO `property_upgrades` (`property_id`, `upgrade`, `level`) VALUES (?, 'interior', ?) ON DUPLICATE KEY UPDATE `level` = VALUES(`level`)",
							{ id, interior },
							function(success)
								if success and _properties[id] then
									if not _properties[id].upgrades then
										_properties[id].upgrades = {}
									end
									_properties[id].upgrades["interior"] = interior

									TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
								end

								p:resolve(success)
							end
						)
					end)
					return Citizen.Await(p)
				end
			end
		end,
	},
	Commerce = {
		Sell = function(self, id)
			local p = promise.new()
			local oldKeys = _properties[id] and _properties[id].keys

			if _properties[id] then
				_properties[id].sold = false
				_properties[id].owner = false
				_properties[id].keys = nil
			end

			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] then
					if oldKeys then
						for k, v in pairs(oldKeys) do
							local t = _charPropertyKeys[v.Char]
							if t ~= nil then
								for k2, v2 in ipairs(t) do
									if v2 == id then
										table.remove(t, k2)
										_charPropertyKeys[v.Char] = t
										break
									end
								end
							end
						end
					end

					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end
				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
		Buy = function(self, id, owner, payment)
			local p = promise.new()

			if _properties[id] then
				_properties[id].sold = true
				_properties[id].keys = {
					[owner.Char] = owner,
				}
				_properties[id].soldAt = os.time()
			end

			PersistProperty(id, _properties[id], function(success)
				if success then
					if _charPropertyKeys[owner.Char] ~= nil then
						local t = _charPropertyKeys[owner.Char]
						table.insert(t, propertyId)
						_charPropertyKeys[owner.Char] = t
					else
						_charPropertyKeys[owner.Char] = {
							propertyId,
						}
					end

					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end
				p:resolve(success)
			end)

			return Citizen.Await(p)
		end,
		Foreclose = function(self, id, state)
			if not _properties[id] and state ~= nil then
				return false
			end

			local p = promise.new()
			if _properties[id] then
				_properties[id].foreclosed = state
				_properties[id].foreclosedTime = state and os.time() or false
			end
			PersistProperty(id, _properties[id], function(success)
				if success and _properties[id] then
					TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
				end

				p:resolve(success)
			end)
			return Citizen.Await(p)
		end,
	},
	Utils = {
		IsNearProperty = function(self, source)
			local myPos = GetEntityCoords(GetPlayerPed(source))
			local closest = nil
			for k, v in pairs(_properties) do
				local dist = #(myPos - vector3(v.location.front.x, v.location.front.y, v.location.front.z))
				if dist < 3.0 and (not closest or dist < closest.dist) then
					closest = {
						dist = dist,
						propertyId = v.id,
					}
				end
			end
			return closest
		end,
		SetLock = function(self, id, locked)
			if _properties[id] then
				_properties[id].locked = locked
				TriggerClientEvent("Properties:Client:SetLocks", -1, id, _properties[id].locked)
				return true
			else
				return false
			end
		end,
		ToggleLock = function(self, id)
			if _properties[id] then
				_properties[id].locked = not _properties[id].locked
				TriggerClientEvent("Properties:Client:SetLocks", -1, id, _properties[id].locked)
				return true
			else
				return false
			end
		end,
	},
	Keys = {
		Give = function(self, charData, id, isOwner, permissions, updating)
			local p = promise.new()

			EnsurePropertiesTable(function()
				plsr.Database:Update(
					"INSERT INTO `property_keys` (`property_id`, `character_id`, `owner`, `data`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `owner` = VALUES(`owner`), `data` = VALUES(`data`)",
					{
						id,
						charData.ID,
						isOwner and 1 or 0,
						json.encode({ First = charData.First, Last = charData.Last, SID = charData.SID, Permissions = permissions }),
					},
					function(success)
						if success then
							if _properties[id] then
								if not _properties[id].keys then
									_properties[id].keys = {}
								end
								_properties[id].keys[charData.ID] = {
									Char = charData.ID,
									First = charData.First,
									Last = charData.Last,
									SID = charData.SID,
									Owner = isOwner,
									Permissions = permissions,
								}

								TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])
							end

							if not updating then
								if _charPropertyKeys[charData.ID] ~= nil then
									local t = _charPropertyKeys[charData.ID]
									table.insert(t, id)
									_charPropertyKeys[charData.ID] = t
								else
									_charPropertyKeys[charData.ID] = {
										id,
									}
								end
							end
						end
						p:resolve(success)

						if charData.Source then
							TriggerClientEvent("Properties:Client:AddBlips", charData.Source)
						end
					end
				)
			end)

			return Citizen.Await(p)
		end,
		Take = function(self, target, id)
			local p = promise.new()

			EnsurePropertiesTable(function()
				plsr.Database:Update("DELETE FROM `property_keys` WHERE `property_id` = ? AND `character_id` = ?", { id, target }, function(success)
					if success then
						if _properties[id] and _properties[id].keys then
							_properties[id].keys[target] = nil
						end

						TriggerClientEvent("Properties:Client:Update", -1, id, _properties[id])

						local t = _charPropertyKeys[target]
						if t ~= nil then
							for k, v in ipairs(t) do
								if v == id then
									table.remove(t, k)
									break
								end
							end

							_charPropertyKeys[target] = t
						end
					end
					p:resolve(success)
				end)
			end)
			return Citizen.Await(p)
		end,
		Has = function(self, id, charId)
			if _properties[id] and _properties[id].keys ~= nil then
				return _properties[id].keys[charId]
			end
			return false
		end,
		HasBySID = function(self, id, stateId)
			if _properties[id] and _properties[id].keys ~= nil then
				for k, v in pairs(_properties[id].keys) do
					if v.SID == stateId then
						return true
					end
				end
			end
			return false
		end,
		HasAccessWithData = function(self, source, key, value) -- Has Access to a Property with a specific data/key value
			local char = plsr.Fetch:CharacterSource(source)
			if char then
				local propertyKeys = _charPropertyKeys[char:GetData("ID")]

				for _, propertyId in ipairs(propertyKeys) do
					local property = _properties[propertyId]
					if property and property.data and ((value == nil and property.data[key]) or property.data[key] == value) then
						return property.id
					end
				end
			end
			return false
		end,
	},
	Get = function(self, propertyId)
		return _properties[propertyId]
	end,
	ForceEveryoneLeave = function(self, propertyId)
		local property = _properties[propertyId]
		if property then
			if _insideProperties[property.id] then
				for k, v in pairs(_insideProperties[property.id]) do
					TriggerClientEvent("Properties:Client:ForceExitProperty", k, property.id)
				end
			end
		end
	end,
	GetMaxParkingSpaces = function(self, propertyId)
		local property = _properties[propertyId]
		if property then
			local garageLevel = property?.upgrades?.garage or 1

			if garageLevel and garageLevel >= 1 and PropertyGarage[property.type] and PropertyGarage[property.type][garageLevel] then
				return PropertyGarage[property.type][garageLevel].parking
			end
		end
	end
}

AddEventHandler("Proxy:Shared:RegisterReady", function()
	exports["pulsar_core"]:RegisterComponent("Properties", PROPERTIES)
end)

function table.copy(t)
	local u = {}
	for k, v in pairs(t) do
		u[k] = v
	end
	return setmetatable(u, getmetatable(t))
end