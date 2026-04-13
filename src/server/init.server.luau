--!strict
-- init.server.luau
-- Bio-Fusion server bootstrap.
-- Sets up physics configuration, loads all server modules, and wires RemoteEvent handlers.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

-- ── Physics: Adaptive stepping for mobile performance ──────────────────────
-- Adaptive mode reduces physics simulation frequency dynamically under load,
-- keeping frame rates stable on low-end devices (targets 80% of the player base).
Workspace.PhysicsSteppingMethod = Enum.PhysicsSteppingMethod.Adaptive

-- ── Module requires ────────────────────────────────────────────────────────
-- Wait for Shared folder to be replicated before requiring (safety on live servers)
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CreatureTypes   = require(Shared:WaitForChild("CreatureTypes"))
local CreatureBuilder = require(Shared:WaitForChild("CreatureBuilder"))
local Remotes         = require(Shared:WaitForChild("Remotes"))
local BattleHandler   = require(script.Parent:WaitForChild("BattleHandler"))

-- ── Active creature registry ───────────────────────────────────────────────
-- Maps Player.UserId → current creature Model and its cleanup function.
local activeCreatures:   {[number]: Model}    = {}
local cleanupFunctions:  {[number]: () -> ()} = {}

-- ── SyncDNA handler ────────────────────────────────────────────────────────
-- Client fires this after editing DNA in the creature builder UI.
Remotes.SyncDNA.OnServerEvent(function(player: Player, dnaBuffer: buffer)
	-- 1. Deserialize & validate buffer
	local ok, result = pcall(CreatureTypes.Deserialize, dnaBuffer)
	if not ok then
		warn(string.format("[BioFusion] Invalid DNA buffer from player %d: %s", player.UserId, tostring(result)))
		return
	end
	local dna = result

	-- 2. Ownership check — prevent spoofing another player's creature
	if dna.OwnerID ~= player.UserId then
		warn(string.format("[BioFusion] DNA OwnerID mismatch: player %d sent OwnerID %d", player.UserId, dna.OwnerID))
		return
	end

	-- 3. Tear down previous creature for this player, if any
	local prevCleanup = cleanupFunctions[player.UserId]
	if prevCleanup then
		prevCleanup()
		cleanupFunctions[player.UserId] = nil
	end
	local prevModel = activeCreatures[player.UserId]
	if prevModel then
		prevModel:Destroy()
		activeCreatures[player.UserId] = nil
	end

	-- 4. Spawn new creature (wrapped in task.spawn to avoid blocking the remote callback)
	task.spawn(function()
		local model = Instance.new("Model")
		model.Name = "Creature_" .. tostring(player.UserId)
		-- Store owner ID on the model so BattleHandler can resolve the owning player
		model:SetAttribute("OwnerID", player.UserId)
		model.Parent = Workspace

		-- Assemble parts from DNA
		CreatureBuilder.Assemble(dna, model)

		-- Register physics-based combat events
		local cleanup = BattleHandler.RegisterCreature(model)

		-- Store references for later cleanup
		activeCreatures[player.UserId]  = model
		cleanupFunctions[player.UserId] = cleanup

		-- Notify the client: creature is live
		Remotes.SpawnCreature.FireClient(player, model)
	end)
end)

-- ── Player cleanup ─────────────────────────────────────────────────────────
-- Disconnect events and destroy the creature when a player leaves.
Players.PlayerRemoving:Connect(function(player: Player)
	local cleanup = cleanupFunctions[player.UserId]
	if cleanup then
		cleanup()
		cleanupFunctions[player.UserId] = nil
	end

	local model = activeCreatures[player.UserId]
	if model then
		model:Destroy()
		activeCreatures[player.UserId] = nil
	end
end)

print("[BioFusion] Server initialised.")
