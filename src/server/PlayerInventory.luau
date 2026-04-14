--!strict
-- PlayerInventory.luau
-- Server-side DNA inventory per player.
-- Tracks how many DNA fragments of each PartType a player has collected.

type InventoryEntry = { Armor: number, Wing: number, Limb: number }

-- Maps UserId → inventory counts
local inventories: {[number]: InventoryEntry} = {}

local PlayerInventory = {}

-- Initialise a fresh inventory for a player on join.
function PlayerInventory.Init(userId: number): ()
	inventories[userId] = { Armor = 0, Wing = 0, Limb = 0 }
end

-- Remove inventory entry when a player leaves.
function PlayerInventory.Clear(userId: number): ()
	inventories[userId] = nil
end

-- Get a copy of the player's current inventory.
-- Returns zeros if the player has no inventory yet.
function PlayerInventory.Get(userId: number): InventoryEntry
	local inv = inventories[userId]
	if inv then
		return { Armor = inv.Armor, Wing = inv.Wing, Limb = inv.Limb }
	end
	return { Armor = 0, Wing = 0, Limb = 0 }
end

-- Add one DNA fragment of the given type to the player's inventory.
function PlayerInventory.Add(userId: number, partType: string): ()
	local inv = inventories[userId]
	if not inv then return end
	if partType == "Armor" then
		inv.Armor += 1
	elseif partType == "Wing" then
		inv.Wing += 1
	elseif partType == "Limb" then
		inv.Limb += 1
	end
end

-- Attempt to consume DNA for each part in the provided list.
-- Counts required DNA per type, checks availability, then deducts.
-- Returns (true, nil) on success, (false, errorMessage) on failure.
function PlayerInventory.Consume(userId: number, parts: {any}): (boolean, string?)
	local inv = inventories[userId]
	if not inv then
		return false, "Kein Inventar gefunden"
	end

	-- Count required DNA per type
	local required: {[string]: number} = {}
	for _, part in parts do
		local pt = (part :: any).PartType :: string
		required[pt] = (required[pt] or 0) + 1
	end

	-- Validate availability
	if (required["Armor"] or 0) > inv.Armor then
		return false, string.format("Nicht genug Armor-DNA (benötigt %d, vorhanden %d)", required["Armor"] or 0, inv.Armor)
	end
	if (required["Wing"] or 0) > inv.Wing then
		return false, string.format("Nicht genug Wing-DNA (benötigt %d, vorhanden %d)", required["Wing"] or 0, inv.Wing)
	end
	if (required["Limb"] or 0) > inv.Limb then
		return false, string.format("Nicht genug Limb-DNA (benötigt %d, vorhanden %d)", required["Limb"] or 0, inv.Limb)
	end

	-- Deduct
	inv.Armor -= (required["Armor"] or 0)
	inv.Wing  -= (required["Wing"]  or 0)
	inv.Limb  -= (required["Limb"]  or 0)

	return true, nil
end

return PlayerInventory
