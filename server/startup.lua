local _ran = false

_properties = {}
_insideProperties = {}

function doPropertyThings(property)
	property.id = property._id
	property.locked = property.locked or true

	if property.location then
		for k, v in pairs(property.location) do
			if v then
				for k2, v2 in pairs(v) do
					property.location[k][k2] = property.location[k][k2] + 0.0
				end
			end
		end
	end

	return property
end

-- `keys`/`upgrades` live in their own tables; attach them onto the already-loaded `_properties`.
function LoadPropertyKeysAndUpgrades(callback)
	plsr.Database:Query("SELECT `property_id`, `character_id`, `owner`, `data` FROM `property_keys`", nil, function(success, keyRows)
		if success then
			for k, row in ipairs(keyRows) do
				local property = _properties[row.property_id]
				if property then
					if not property.keys then
						property.keys = {}
					end
					local ok, extra = pcall(json.decode, row.data or "null")
					if not ok or type(extra) ~= "table" then
						extra = {}
					end
					property.keys[row.character_id] = {
						Char = row.character_id,
						SID = extra.SID,
						First = extra.First,
						Last = extra.Last,
						Owner = row.owner == 1,
						Permissions = extra.Permissions,
					}
				end
			end
		end

		plsr.Database:Query("SELECT `property_id`, `upgrade`, `level` FROM `property_upgrades`", nil, function(upSuccess, upgradeRows)
			if upSuccess then
				for k, row in ipairs(upgradeRows) do
					local property = _properties[row.property_id]
					if property then
						if not property.upgrades then
							property.upgrades = {}
						end
						if row.upgrade == "interior" then
							property.upgrades[row.upgrade] = row.level
						else
							property.upgrades[row.upgrade] = tonumber(row.level)
						end
					end
				end
			end

			if callback then
				callback()
			end
		end)
	end)
end

function Startup()
	if _ran then
		return
	end

	EnsurePropertiesTable(function()
		plsr.Database:Query("SELECT `id`, `data` FROM `properties`", nil, function(success, results)
			if not success then
				return
			end
			plsr.Logger:Trace("Properties", "Loaded ^2" .. #results .. "^7 Properties", { console = true })

			for k, row in ipairs(results) do
				local ok, v = pcall(json.decode, row.data)
				if ok and type(v) == "table" then
					v._id = row.id
					local p = doPropertyThings(v)
					_properties[row.id] = p
				end
			end

			LoadPropertyKeysAndUpgrades()
		end)
	end)

	_ran = true
end

RegisterNetEvent("Properties:RefreshProperties", function()
    EnsurePropertiesTable(function()
        plsr.Database:Query("SELECT `id`, `data` FROM `properties`", nil, function(success, results)
            if not success then
                return
            end
            plsr.Logger:Warn("Properties", "Loaded ^2" .. #results .. "^7 Properties", { console = true })

            for k, row in ipairs(results) do
                local ok, v = pcall(json.decode, row.data)
                if ok and type(v) == "table" then
                    v._id = row.id
                    local p = doPropertyThings(v)
                    _properties[row.id] = p
                end
            end

            LoadPropertyKeysAndUpgrades(function()
                TriggerLatentClientEvent("Properties:Client:Load", -1, 800000, _properties)
            end)
        end)
    end)
end)
