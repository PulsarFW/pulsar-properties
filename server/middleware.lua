function RegisterMiddleware()
	plsr.Middleware:Add("Characters:Spawning", function(source)
		local char = plsr.Fetch:CharacterSource(source)
		TriggerLatentClientEvent("Properties:Client:Load", source, 50000, _properties, _charPropertyKeys[char:GetData("ID")])
	end)

	plsr.Middleware:Add("Characters:GetSpawnPoints", function(source, charId)
		local p = promise.new()

		EnsurePropertiesTable(function()
			plsr.Database:Query("SELECT `property_id` FROM `property_keys` WHERE `character_id` = ?", { charId }, function(success, results)
				if not success then
					p:resolve({})
					return
				end
				local spawns = {}

				local keys = {}

				for k, row in ipairs(results) do
					table.insert(keys, row.property_id)
					local property = _properties[row.property_id]
					if property ~= nil and not property.foreclosed and property.type ~= "container" and property.type ~= "warehouse" then
						local interior = property.upgrades?.interior
						local interiorData = PropertyInteriors[interior]

						local icon = "house"
						if property.type == "warehouse" then
							icon = "warehouse"
						elseif property.type == "office" then
							icon = "building"
						end

						if interiorData ~= nil then
							table.insert(spawns, {
								id = property.id,
								label = property.label,
								location = {
									x = interiorData.locations.front.coords.x,
									y = interiorData.locations.front.coords.y,
									z = interiorData.locations.front.coords.z,
									h = interiorData.locations.front.heading,
								},
								icon = icon,
								event = "Properties:SpawnInside",
							})
						end
					end
				end
				_charPropertyKeys[charId] = keys
				p:resolve(spawns)
			end)
		end)

		return Citizen.Await(p)
	end, 3)
end

AddEventHandler("Characters:Server:PlayerLoggedOut", function(source, cData)
	_charPropertyKeys[cData.ID] = nil
	local property = GlobalState[string.format("%s:Property", source)]
	if property then
		if _insideProperties[property] then
			_insideProperties[property][source] = nil
		end

		GlobalState[string.format("%s:Property", source)] = nil
	end

	if plsr.State:Player(source).tpLocation then
		plsr.State:Player(source).tpLocation = nil
	end
end)

AddEventHandler("Characters:Server:PlayerDropped", function(source, cData)
	_charPropertyKeys[cData.ID] = nil
	local property = GlobalState[string.format("%s:Property", source)]
	if property then
		if _insideProperties[property] then
			_insideProperties[property][source] = nil
		end

		GlobalState[string.format("%s:Property", source)] = nil
	end

	if plsr.State:Player(source).tpLocation then
		plsr.State:Player(source).tpLocation = nil
	end
end)
