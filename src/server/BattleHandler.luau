
--!strict
-- BattleHandler.luau
-- Server-side combat resolution.
-- Registers Touched events on all BasePart descendants of a creature Model.
-- Damage = relativeVelocity * attackerMass  (impulse-based, not flat values).
-- Per-part debounce prevents repeated firing within a cooldown window.

-- ─────────────────────────────────────────────
-- Dependencies
-- ─────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

local DEBOUNCE_SECONDS: number = 0.2

-- ─────────────────────────────────────────────
-- Module-level state
-- ─────────────────────────────────────────────

-- Per-part debounce flag. nil = ready; true = on cooldown.
-- Using nil instead of false keeps the table sparse (destroyed parts don't accumulate).
local debounce: {[BasePart]: true} = {}

-- Maps each registered creature Model to its active Touched connections.
local activeConnections: {[Model]: {RBXScriptConnection}} = {}

-- ─────────────────────────────────────────────
-- Helper: find which player owns a creature Model
-- ─────────────────────────────────────────────

local function findOwner(creatureModel: Model): Player?
	local ownerID = creatureModel:GetAttribute("OwnerID")
	if typeof(ownerID) ~= "number" then return nil end
	return Players:GetPlayerByUserId(ownerID)
end

-- ─────────────────────────────────────────────
-- Core damage handler
-- ─────────────────────────────────────────────

local function onPartTouched(partA: BasePart, hit: Instance): ()
	-- hit must be a BasePart to carry physics data
	if not hit:IsA("BasePart") then return end
	local partB = hit :: BasePart

	-- Skip self-touches (two parts of the same creature)
	local modelA = partA:FindFirstAncestorOfClass("Model")
	local modelB = partB:FindFirstAncestorOfClass("Model")
	if modelA == modelB then return end

	-- Debounce guard for this specific part
	if debounce[partA] then return end
	debounce[partA] = true

	-- ── Damage formula ─────────────────────────
	-- Physical impulse approximation:
	--   damage = |v_A - v_B| × mass_A
	-- The attacker's kinetic contribution drives damage dealt to the defender.
	local relVel  = (partA.AssemblyLinearVelocity - partB.AssemblyLinearVelocity).Magnitude
	local rawDmg  = relVel * partA.AssemblyMass

	-- Apply defender's armor reduction if present (ArmorThickness ≥ 1 = no reduction)
	local armorThickness = partB:GetAttribute("ArmorThickness")
	local damage: number
	if typeof(armorThickness) == "number" and armorThickness > 0 then
		damage = rawDmg / armorThickness
	else
		damage = rawDmg
	end

	-- ── Apply damage to defender's creature ────
	if modelB then
		local currentHP = modelB:GetAttribute("Health")
		if typeof(currentHP) == "number" then
			local newHP = math.max(0, currentHP - damage)
			modelB:SetAttribute("Health", newHP)

			-- Notify the owning player's client for UI updates
			local owner = findOwner(modelB)
			if owner then
				Remotes.ApplyDamage.FireClient(owner, damage)
			end
		end
	end

	-- ── Release debounce after cooldown ────────
	-- task.spawn offloads the wait to the task scheduler,
	-- keeping this Touched callback non-blocking on the physics thread.
	task.spawn(function()
		task.wait(DEBOUNCE_SECONDS)
		debounce[partA] = nil
	end)
end

-- ─────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────

local BattleHandler = {}

-- Registers Touched combat handlers on all BasePart descendants of `creatureModel`.
-- Also wires DescendantAdded so parts assembled after registration are covered.
-- Returns a cleanup function — call it when the creature dies or is removed.
-- @param creatureModel Model  The assembled creature to register.
-- @return () -> ()            Cleanup: disconnects all events for this model.
function BattleHandler.RegisterCreature(creatureModel: Model): () -> ()
	local connections: {RBXScriptConnection} = {}

	-- Register existing parts
	for _, descendant in creatureModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			local conn = part.Touched:Connect(function(hit: BasePart)
				onPartTouched(part, hit)
			end)
			table.insert(connections, conn)
		end
	end

	-- Register future parts (added dynamically after assembly)
	local addedConn = creatureModel.DescendantAdded:Connect(function(desc: Instance)
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			local conn = part.Touched:Connect(function(hit: BasePart)
				onPartTouched(part, hit)
			end)
			table.insert(connections, conn)
		end
	end)
	table.insert(connections, addedConn)

	activeConnections[creatureModel] = connections

	-- Return a closure so the caller can clean up without holding a module reference
	return function()
		BattleHandler.UnregisterCreature(creatureModel)
	end
end

-- Disconnects all combat event connections for `creatureModel` and clears debounce state.
-- Safe to call multiple times (idempotent).
-- @param creatureModel Model
function BattleHandler.UnregisterCreature(creatureModel: Model): ()
	local connections = activeConnections[creatureModel]
	if connections then
		for _, conn in connections do
			conn:Disconnect()
		end
		activeConnections[creatureModel] = nil
	end

	-- Clear debounce entries for every part of this creature
	for _, descendant in creatureModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			debounce[descendant :: BasePart] = nil
		end
	end
end

return BattleHandler
