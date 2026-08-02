local _ran = false

-- One-time seed for the starter property ("1 Grove St"), gated by `seed_versions` (same table
-- plsr.Default:Add uses elsewhere) so it only ever runs once. Writes straight into the real
-- `properties`/`property_upgrades` tables instead of going through plsr.Default:Add, since that
-- helper writes to a disconnected `seed_properties` mirror table nothing ever reads back from.
function DefaultData()
    if _ran then return end
    _ran = true

    EnsurePropertiesTable(function()
        plsr.Database:Query("CREATE TABLE IF NOT EXISTS `seed_versions` (`collection` VARCHAR(191) PRIMARY KEY, `date` BIGINT NOT NULL)", nil, function()
            plsr.Database:Single("SELECT 1 FROM `seed_versions` WHERE `collection` = ?", { 'properties_default' }, function(success, row)
                if not success or row ~= nil then return end

                local doc = {
                    type = "house",
                    label = "1 Grove St",
                    price = 100000,
                    sold = false,
                    owner = false,
                    location = {
                        front = { x = -33.92966842651367, y = -1847.235107421875, z = 26.679443359375 },
                        backdoor = { x = -42.875373840332, y = -1859.2385253906, z = 26.197219848633, h = 139.80822753906 },
                    },
                }

                plsr.Database:Insert(
                    "INSERT INTO `properties` (`type`, `sold`, `label`, `data`) VALUES (?, 0, ?, ?)",
                    { doc.type, doc.label, json.encode(doc) },
                    function(inserted, newId)
                        if not inserted then return end

                        plsr.Database:Update(
                            "INSERT INTO `property_upgrades` (`property_id`, `upgrade`, `level`) VALUES (?, 'interior', ?)",
                            { newId, "house_regular1" },
                            function()
                                plsr.Database:Update(
                                    "INSERT INTO `seed_versions` (`collection`, `date`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `date` = VALUES(`date`)",
                                    { 'properties_default', 1590006209 },
                                    function()
                                        TriggerEvent("Properties:RefreshProperties")
                                    end
                                )
                            end
                        )
                    end
                )
            end)
        end)
    end)
end
