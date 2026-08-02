_properties = {}
_myPropertyKeys = {}

_propertiesLoaded = false

_insideProperty = false
_insideInterior = false
_insideFurniture = {}
_AllHousesBlips = {}

_furnitureCategory = {}
_furnitureCategoryCurrent = 1

_placingFurniture = false

_allowBrowse = true
_skipPhone = false

_placingSearchItem = nil

CreateThread(function()
	CreatePropertyDoor(false)
	CreatePropertyDoor(true)

	plsr.Interaction:RegisterMenu("house-exit", "Exit", "door-open", function(data)
			plsr.Interaction:Hide()
			ExitProperty(data, data == 'back')
		end, function()
			if _insideProperty and _insideInterior then
				local interior = PropertyInteriors[_insideInterior]

				if interior then
					local dist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.front.coords)

					if dist <= 2.0 then
						return 'front'
					elseif interior.locations.back then
						backDist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.back.coords)
						if backDist <= 2.0 then
							return 'back'
						end
					end
				end
			end

			return false
		end)

		plsr.Interaction:RegisterMenu("house-lock", "Lock", "lock", function(data)
			plsr.Interaction:Hide()
			plsr.Callbacks:ServerCallback("Properties:ChangeLock", {
				id = data,
				state = true,
			}, function(state)
				if state then
					plsr.Notification:Success("Property Locked")
				else
					plsr.Notification:Error("Unable to Lock Property")
				end
			end)
		end, function()
			if _insideProperty and _insideInterior and _propertiesLoaded then
				if _properties[_insideProperty.id].locked then
					return false
				end

				local interior = PropertyInteriors[_insideInterior]

				local dist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.front.coords)
				local backDist
				if interior.locations.back then
					backDist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.back.coords)
				end

				if (dist <= 2.0 or (backDist and backDist <= 2.0)) then
					return _insideProperty.id
				end
			end

			return false
		end)

		plsr.Interaction:RegisterMenu("house-unlock", "Unlock", "unlock", function(data)
			plsr.Interaction:Hide()
			plsr.Callbacks:ServerCallback("Properties:ChangeLock", {
				id = data,
				state = false,
			}, function(state)
				if state then
					plsr.Notification:Success("Property Unlocked")
				else
					plsr.Notification:Error("Unable to Unlock Property")
				end
			end)
		end, function()
			if _insideProperty and _insideInterior and _propertiesLoaded then
				local property = _properties[_insideProperty.id]
				if
					property.locked
					and (
						(property.keys ~= nil and property.keys[plsr.State.character.ID] ~= nil)
						or (
							not property.sold
							and plsr.State.flags.onDuty == "realestate"
							and plsr.Jobs.Permissions:HasPermissionInJob("realestate", "JOB_DOORS")
						)
					)
				then
					local interior = PropertyInteriors[_insideInterior]
					local dist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.front.coords)
					local backDist
					if interior.locations.back then
						backDist = #(vector3(plsr.State.flags.position.x, plsr.State.flags.position.y, plsr.State.flags.position.z) - interior.locations.back.coords)
					end

					if (dist <= 2.0 or (backDist and backDist <= 2.0)) then
						return _insideProperty.id
					end
				else
					return false
				end
			else
				return false
			end

			return false
		end)

		for k, v in pairs(PropertyInteriors) do
			if v.zone then
				plsr.Polyzone.Create:Box(
					string.format("property-int-zone-%s", k),
					v.zone.center,
					v.zone.length,
					v.zone.width,
					v.zone.options,
					{
						PROPERTY_INTERIOR_ZONE = true,
					}
				)
			end
		end

		plsr.Keybinds:Add("furniture_prev", "LEFT", "keyboard", "Furniture - Previous Item", function()
			if _placingFurniture then
				CycleFurniture()
			elseif _previewingInterior and not _previewingInteriorSwitching then
				PrevPreview()
			end
		end)

		plsr.Keybinds:Add("furniture_next", "RIGHT", "keyboard", "Furniture - Next Item", function()
			if _placingFurniture then
				CycleFurniture(true)
			elseif _previewingInterior and not _previewingInteriorSwitching then
				NextPreview()
			end
		end)
end)

function CreatePropertyDoor(isBackdoor)
	plsr.Interaction:RegisterMenu(isBackdoor and "property-backdoor" or "property", isBackdoor and "Property Backdoor" or "Property", isBackdoor and "door-open" or "house", function(data)
		local pMenu = {
			{
				icon = "door-open",
				label = isBackdoor and "Enter Backdoor" or "Enter",
				action = function()
					EnterProperty(data, isBackdoor)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end

					local prop = _properties[data.propertyId]
					return ((prop.keys ~= nil and prop.keys[plsr.State.character.ID] ~= nil)
						or (not prop.sold and plsr.State.flags.onDuty == "realestate" and plsr.Jobs.Permissions:HasPermissionInJob(
							"realestate",
							"JOB_DOORS"
						))
						or not prop.locked) and not prop.foreclosed

				end,
			},
			{
				icon = "lock-open",
				label = "Unlock",
				action = function()
					plsr.Callbacks:ServerCallback("Properties:ChangeLock", {
						id = data.propertyId,
						state = false,
					}, function(state)
						if state then
							plsr.Notification:Success("Property Unlocked")
						else
							plsr.Notification:Error("Unable to Unlock Property")
						end
						plsr.Interaction:Hide()
					end)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end
					local prop = _properties[data.propertyId]
					if
						((prop.keys ~= nil and prop.keys[plsr.State.character.ID] ~= nil)
						or (
							not prop.sold
							and plsr.State.flags.onDuty == "realestate"
							and plsr.Jobs.Permissions:HasPermissionInJob("realestate", "JOB_DOORS")
						)) and not prop.foreclosed
					then
						return prop.locked
					else
						return false
					end
				end,
			},
			{
				icon = "lock",
				label = "Lock",
				action = function()
					plsr.Callbacks:ServerCallback("Properties:ChangeLock", {
						id = data.propertyId,
						state = true,
					}, function(state)
						if state then
							plsr.Notification:Success("Property Locked")
						else
							plsr.Notification:Error("Unable to Unlock Property")
						end
						plsr.Interaction:Hide()
					end)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end
					local prop = _properties[data.propertyId]

					if
						((prop.keys ~= nil and prop.keys[plsr.State.character.ID] ~= nil)
						or (
							not prop.sold
							and plsr.State.flags.onDuty == "realestate"
							and plsr.Jobs.Permissions:HasPermissionInJob("realestate", "JOB_DOORS")
						)) and not prop.foreclosed
					then
						return not prop.locked
					else
						return false
					end
				end,
			},
			{
				icon = "house-chimney-crack",
				label = "Property is Foreclosed",
				action = function()
					plsr.Notification:Error('This Property Has Been Foreclosed! This is why you should pay your property loans...', 10000)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end
					local prop = _properties[data.propertyId]
					return prop.foreclosed
				end,
			},
		}

		if not isBackdoor then
			table.insert(pMenu, {
				icon = "bell",
				label = "Ring Doorbell",
				action = function()
					plsr.Callbacks:ServerCallback("Properties:RingDoorbell", data.propertyId, function()
						plsr.Sounds.Play:One("doorbell.ogg", 0.75)
					end)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end
					local prop = _properties[data.propertyId]
					return prop.sold and not prop.foreclosed and prop.type == "house"
				end,
			})

			table.insert(pMenu, {
				icon = "sign-hanging",
				label = "Request Agent",
				action = function()
					plsr.Callbacks:ServerCallback("Properties:RequestAgent", data.propertyId, function(state)
						if state then
							plsr.Notification:Success("Notification Sent")
						else
							plsr.Notification:Error("Unable To Send Notification")
						end
						plsr.Interaction:Hide()
					end)
				end,
				shouldShow = function()
					if not _propertiesLoaded then
						return false
					end
					local prop = _properties[data.propertyId]
					return prop and not prop.sold
				end,
			})
		end

		plsr.Interaction:ShowMenu(pMenu)
	end, function()
		if not _propertiesLoaded then
			return false
		end

		if isBackdoor then
			return plsr.Properties:GetNearHouseBackdoor()
		else
			return plsr.Properties:GetNearHouse()
		end
	end, function()
		if not _propertiesLoaded then
			return false
		end
		if isBackdoor then
			local prop = plsr.Properties:GetNearHouseBackdoor()
			return type(prop) == "table" and _properties[prop.propertyId]?.label or 'Property'
		else
			local prop = plsr.Properties:GetNearHouse()
			return type(prop) == "table" and _properties[prop.propertyId]?.label or 'Property'
		end
	end)
end

RegisterNetEvent("Properties:Client:Load", function(props, myKeys)
	_properties = props
	_myPropertyKeys = myKeys or {}

	_propertiesLoaded = true
end)

RegisterNetEvent("Properties:Client:Update", function(id, data)
	if _properties and _propertiesLoaded then
		_properties[id] = data
	end
end)

RegisterNetEvent("Properties:Client:SetLocks", function(id, state)
	if _properties and _propertiesLoaded and _properties[id] then
		_properties[id].locked = state
	end
end)

local showingAllPropsBlips = false
RegisterNetEvent("Properties:Client:ShowAllPropertyBlips", function(show)
	if showingAllPropsBlips then
		plsr.Notification:Info("Property Blips Hidden")
		for k, v in ipairs(_AllHousesBlips) do
			RemoveBlip(v)
		end
		_AllHousesBlips = {}
		showingAllPropsBlips = false
	else
		plsr.Notification:Info("Property Blips Enabled")
		showingAllPropsBlips = true
		AddTextEntry("PROPERTYBLIP", "Properties Available")
		AddTextEntry("PROPERTYBLIPS", "Properties Sold")

		for k, v in pairs(_properties) do
			local coords = v.location
			if v.sold then
				local HouseBlip = AddBlipForCoord(coords.front.x, coords.front.y, coords.front.z)
				SetBlipSprite(HouseBlip, 375)
				SetBlipColour(HouseBlip, 1)
				SetBlipScale(HouseBlip, 0.45)
				SetBlipAsShortRange(HouseBlip, true)
				BeginTextCommandSetBlipName("PROPERTYBLIPS")
				EndTextCommandSetBlipName(HouseBlip)
				table.insert(_AllHousesBlips, HouseBlip)
			else
				local HouseBlip = AddBlipForCoord(coords.front.x, coords.front.y, coords.front.z)
				SetBlipSprite(HouseBlip, 375)
				SetBlipColour(HouseBlip, 2)
				SetBlipScale(HouseBlip, 0.65)
				SetBlipAsShortRange(HouseBlip, true)
				BeginTextCommandSetBlipName("PROPERTYBLIP")
				EndTextCommandSetBlipName(HouseBlip)

				table.insert(_AllHousesBlips, HouseBlip)
			end
		end
	end
	if show then

	else

	end
end)

RegisterNetEvent('Characters:Client:Logout')
AddEventHandler('Characters:Client:Logout', function()
	_propertiesLoaded = false
	_properties = {}

	collectgarbage()

	DestroyFurniture()

	_insideProperty = false
	_insideInterior = false

	_placingFurniture = false
	plsr.State.flags.placingFurniture = false
	plsr.State.flags.furnitureEdit = false

	if #_AllHousesBlips > 0 then
		for k, v in ipairs(_AllHousesBlips) do
			RemoveBlip(v)
		end

		_AllHousesBlips = {}
	end
end)

PROPERTIES = {
	Enter = function(self, id)
		EnterProperty({
			propertyId = id,
		}, false)
	end,
	GetProperties = function(self)
		if _propertiesLoaded then
			return _properties
		end
		return false
	end,
	GetPropertiesWithAccess = function(self)
		if plsr.State.flags.loggedIn and _propertiesLoaded then
			local props = {}
			for k, v in pairs(_properties) do
				if v and v.keys and v.keys[plsr.State.character.ID] then
					table.insert(props, v)
				end
			end

			return props
		end
		return false
	end,
	Get = function(self, pId)
		return _properties[pId]
	end,
	GetUpgradesConfig = function(self)
		return PropertyUpgrades
	end,
	GetNearHouse = function(self)
		if plsr.State.flags.currentRoute ~= 0 or not _propertiesLoaded then
			return false
		end

		local myPos = GetEntityCoords(PlayerPedId())
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
	GetNearHouseBackdoor = function(self)
		if plsr.State.flags.currentRoute ~= 0 or not _propertiesLoaded then
			return false
		end

		local myPos = GetEntityCoords(PlayerPedId())
		local closest = nil
		for k, v in pairs(_properties) do
			if v.location.backdoor then
				local dist = #(myPos - vector3(v.location.backdoor.x, v.location.backdoor.y, v.location.backdoor.z))
				if dist < 3.0 and (not closest or dist < closest.dist) then
					closest = {
						dist = dist,
						propertyId = v.id,
					}
				end
			end
		end
		return closest
	end,
	GetNearHouseGarage = function(self, coordOverride)
		if plsr.State.flags.currentRoute ~= 0 or not _propertiesLoaded then
			return false
		end

		local myPos = GetEntityCoords(PlayerPedId())
		local closest = nil
		for k, v in pairs(_properties) do
			if v.location.garage then
				local dist = #(myPos - vector3(v.location.garage.x, v.location.garage.y, v.location.garage.z))
				if dist < 3.0 and (not closest or dist < closest.dist) then
					closest = {
						coords = v.location.garage,
						dist = dist,
						propertyId = v.id,
					}
				end
			end
		end
		return closest
	end,
	GetInside = function(self)
		return _insideProperty
	end,
	Extras = {
		Stash = function(self)
			plsr.Callbacks:ServerCallback("Properties:Validate", {
				id = GlobalState[string.format("%s:Property", plsr.State.flags.ID)],
				type = "stash",
			})
		end,
		Closet = function(self)
			plsr.Callbacks:ServerCallback("Properties:Validate", {
				id = GlobalState[string.format("%s:Property", plsr.State.flags.ID)],
				type = "closet",
			}, function(state)
				if state then
					plsr.Wardrobe:Show()
				end
			end)
		end,
		Logout = function(self)
			plsr.Callbacks:ServerCallback("Properties:Validate", {
				id = GlobalState[string.format("%s:Property", plsr.State.flags.ID)],
				type = "logout",
			}, function(state)
				if state then
					plsr.Characters:Logout()
				end
			end)
		end,
	},
	Keys = {
		HasAccessWithData = function(self, key, value) -- Has Access to a Property with a specific data/key value
			if plsr.State.flags.loggedIn and _propertiesLoaded then
				for _, propertyId in ipairs(_myPropertyKeys) do
					local property = _properties[propertyId]
					if property and property.data and ((value == nil and property.data[key]) or property.data[key] == value) then
						return property.id
					end
				end
			end
			return false
		end,
	},
	Furniture = {
		GetCurrent = function(self, property)
			if _insideProperty and _insideProperty.id == property._id then
				for k, v in ipairs(_insideFurniture) do
					v.dist = #(GetEntityCoords(PlayerPedId()) - vector3(v.coords.x, v.coords.y, v.coords.z))
				end
				return {
					success = true,
					furniture = _insideFurniture,
					catalog = FurnitureConfig,
					categories = FurnitureCategories,
				}
			end

			return {
				err = "Must be Inside the Property!"
			}
		end,
		EditMode = function(self, state)
			if state == nil then
				state = not plsr.State.flags.furnitureEdit
			end

			if _insideProperty then
				SetFurnitureEditMode(state)
			end
		end,
		Place = function(self, model, category, metadata, blockBrowse, skipPhone, startCoords, startRot)
			if not _insideProperty then
				return false
			end

			if not category then
				category = FurnitureConfig[model].cat
			end

			if category == "search" then
				_placingSearchItem = model
			end

			_allowBrowse = not blockBrowse

			_placingFurniture = true
			plsr.State.flags.placingFurniture = true

			_furnitureCategory = {}
			for k, v in pairs(FurnitureConfig) do
				if v.cat == category then
					table.insert(_furnitureCategory, k)
				end
			end

			table.sort(_furnitureCategory, function(a,b)
				return (FurnitureConfig[a]?.id or 1) < (FurnitureConfig[b]?.id or 1)
			end)

			for k, v in ipairs(_furnitureCategory) do
				if v == model then
					_furnitureCategoryCurrent = k
				end
			end

			local fData = FurnitureConfig[model]
			if fData then
				plsr.InfoOverlay:Show(fData.name, string.format("Category: %s | Model: %s", FurnitureCategories[fData.cat]?.name or "Unknown", model))
			end

			plsr.ObjectPlacer:Start(GetHashKey(model), "Furniture:Client:Place", metadata, true, "Furniture:Client:Cancel", true, true, startCoords, nil, startRot)
			if not skipPhone then
				plsr.Phone:Close(true, true)
			end
			_skipPhone = skipPhone

			DisablePauseMenu(true)

			return true
		end,
		Move = function(self, id, skipPhone)
			if not _insideProperty then
				return false
			end

			_furnitureCategoryCurrent = nil

			for k, v in ipairs(_insideFurniture) do
				if v.id == id then
					furn = v
				end
			end

			if not furn then
				return false
			end

			_placingFurniture = true
			plsr.State.flags.placingFurniture = true

			local ns = {}
			for k, v in ipairs(_spawnedFurniture) do
				if v.id == id then
					DeleteEntity(v.entity)
					plsr.Targeting:RemoveEntity(v.entity)
				else
					table.insert(ns, v)
				end
			end
			_spawnedFurniture = ns

			local fData = FurnitureConfig[model]

			plsr.ObjectPlacer:Start(GetHashKey(furn.model), "Furniture:Client:Move", { id = id }, true, "Furniture:Client:CancelMove", true, true, furn.coords, furn.heading, furn.rotation)
			if not skipPhone then
				plsr.Phone:Close(true, true)
			end
			_skipPhone = skipPhone

			DisablePauseMenu(true)

			return true
		end,
		Delete = function(self, id)
			if not _insideProperty then
				return false
			end

			local catCounts = {
				["storage"] = 0,
			}
			local fData
			for k, v in ipairs(_insideFurniture) do
				if v.id == id then
					fData = FurnitureConfig[v.model]
				else
					local d = FurnitureConfig[v.model]
					if not catCounts[d.cat] then
						catCounts[d.cat] = 0
					end

					catCounts[d.cat] += 1
				end
			end

			if fData and fData.cat == "storage" and catCounts["storage"] < 1 then
				plsr.Notification:Error("You Are Required to Have At Least One Storage Container!")
				return false
			end

			local p = promise.new()

			plsr.Callbacks:ServerCallback("Properties:DeleteFurniture", {
				id = id,
			}, function(success, furniture)
				if success then
					plsr.Notification:Success("Deleted Item")
					for k, v in ipairs(furniture) do
						v.dist = #(GetEntityCoords(PlayerPedId()) - vector3(v.coords.x, v.coords.y, v.coords.z))
					end
					p:resolve(furniture)
				else
					p:resolve(false)
					plsr.Notification:Error("Error")
				end
			end)

			return Citizen.Await(p)
		end
	},
	Interiors = {
		Preview = function(self, int)
			StartPreview(int)
		end,
	}
}

AddEventHandler("Proxy:Shared:RegisterReady", function()
	exports["pulsar_core"]:RegisterComponent("Properties", PROPERTIES)
end)

AddEventHandler("RealEstate:Client:AcceptTransfer", function()
	TriggerServerEvent("RealEstate:Server:AcceptTransfer")
end)

AddEventHandler("RealEstate:Client:DenyTransfer", function()
	TriggerServerEvent("RealEstate:Server:DenyTransfer")
end)