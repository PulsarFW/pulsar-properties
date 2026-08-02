_isEntering = false

RegisterNetEvent("Properties:Client:Doorbell", function(propertyId)
	if _insideProperty and propertyId == _insideProperty.id then
		plsr.Sounds.Play:One("doorbell.ogg", 0.75)
	end
end)

RegisterNetEvent("Properties:Client:InnerStuff", function(propertyData, int, furniture)
	_insideProperty = propertyData
	_insideInterior = int
	_isEntering = true

	local interior = PropertyInteriors[int]

	TriggerEvent("Interiors:Enter", interior.locations.front.coords, propertyData.id, int, propertyData.data)

	-- if wakeUp and intr.locations.wakeup then
	-- 	Citizen.SetTimeout(250, function()
	-- 		Animations.Emotes:WakeUp(intr.locations.wakeup)
	-- 	end)
	-- end

	plsr.Sync:Stop(1)

	CreatePropertyZones(propertyData.id, int)

	CreateFurniture(furniture)

	_isEntering = false

	Wait(500)
	plsr.Sync:Stop(1)
end)

---- TARGETTING EVENTS ----
AddEventHandler("Properties:Client:Stash", function(t, data)
	plsr.Properties.Extras:Stash()
end)

AddEventHandler("Properties:Client:Closet", function(t, data)
	plsr.Properties.Extras:Closet()
end)

AddEventHandler("Properties:Client:Logout", function(t, data)
	plsr.Properties.Extras:Logout()
end)

AddEventHandler("Polyzone:Exit", function(id, testedPoint, insideZones, data)
	if plsr.State.flags.loggedIn and data.PROPERTY_INTERIOR_ZONE and _insideProperty and not _isEntering then
        print("Exit Property By Leaving Polyzone")
		ExitProperty()
    end
end)

AddEventHandler("Properties:Client:Exit", function(t, data)
	ExitProperty(data.property, data.backdoor)
end)

AddEventHandler("Properties:Client:Crafting", function(t, data)
	plsr.Crafting.Benches:Open('property-'..data)
end)

AddEventHandler("Properties:Client:Duty", function(t, data)
	if not _propertiesLoaded then
		return
	end

	local property = _properties[data]
	if property?.data?.jobDuty then
		if plsr.State.flags.onDuty == property?.data?.jobDuty then
			plsr.Jobs.Duty:Off(property?.data?.jobDuty)
		else
			plsr.Jobs.Duty:On(property?.data?.jobDuty)
		end
	end
end)

RegisterNetEvent("Characters:Client:Spawn", function()
	TriggerEvent("Properties:Client:AddBlips")
end)

RegisterNetEvent("Properties:Client:AddBlips", function()
	while not plsr.State.flags.loggedIn or not _propertiesLoaded or not plsr.State.flags.loggedIn do
		Wait(100)
	end

	local ownedProps = plsr.Properties:GetPropertiesWithAccess()

	if ownedProps then
		for k, v in ipairs(ownedProps) do
			if v.type == 'house' then
				plsr.Blips:Add('property-'.. v.id, 'House: ' .. v.label, vector3(v.location.front.x, v.location.front.y, v.location.front.z), 40, 53, 0.6, 2)
			elseif v.type == 'office' then
				plsr.Blips:Add('property-'.. v.id, 'Office: ' .. v.label, vector3(v.location.front.x, v.location.front.y, v.location.front.z), 475, 53, 0.6, 2)
			elseif v.type == 'warehouse' then
				plsr.Blips:Add('property-'.. v.id, 'Warehouse: ' .. v.label, vector3(v.location.front.x, v.location.front.y, v.location.front.z), 473, 53, 0.6, 2)
			end
		end
	end
end)
