--!strict
-- init.server.luau
-- Bio-Fusion server bootstrap.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
-- ── Physics: Set Workspace.PhysicsSteppingMethod = Adaptive manually in Studio. ──

-- ── Module requires ────────────────────────────────────────────────────────
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CreatureTypes     = require(Shared:WaitForChild("CreatureTypes"))
local CreatureBuilder   = require(Shared:WaitForChild("CreatureBuilder"))
local Remotes           = require(Shared:WaitForChild("Remotes"))
local BattleHandler     = require(script:WaitForChild("BattleHandler"))
local PlayerInventory   = require(script:WaitForChild("PlayerInventory"))
local DNASpawner        = require(script:WaitForChild("DNASpawner"))
local ArenaBuilder      = require(script:WaitForChild("ArenaBuilder"))
local GameManager       = require(script:WaitForChild("GameManager"))

-- ── Active creature registry ───────────────────────────────────────────────
local activeCreatures:  {[number]: Model}    = {}
local cleanupFunctions: {[number]: () -> ()} = {}

-- ── Player join / leave ────────────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player: Player)
	PlayerInventory.Init(player.UserId)
	-- Send initial (empty) inventory to client
	Remotes.UpdateInventory.FireClient(player, PlayerInventory.Get(player.UserId))
end)

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
	PlayerInventory.Clear(player.UserId)
end)

-- ── SyncDNA handler ────────────────────────────────────────────────────────
Remotes.SyncDNA.OnServerEvent(function(player: Player, dnaBuffer: buffer)
	-- 1. Deserialize & validate
	local ok, result = pcall(CreatureTypes.Deserialize, dnaBuffer)
	if not ok then
		warn(string.format("[BioFusion] Invalid DNA from player %d: %s", player.UserId, tostring(result)))
		return
	end
	local dna = result

	-- 2. Ownership check
	if dna.OwnerID ~= player.UserId then
		warn(string.format("[BioFusion] OwnerID mismatch: player %d sent %d", player.UserId, dna.OwnerID))
		return
	end

	-- 3. Inventory check — player must have enough DNA for all parts
	local canSpawn, err = PlayerInventory.Consume(player.UserId, dna.Parts)
	if not canSpawn then
		warn(string.format("[BioFusion] Inventory check failed for player %d: %s", player.UserId, tostring(err)))
		return
	end

	-- 4. Tear down previous creature
	local prevCleanup = cleanupFunctions[player.UserId]
	if prevCleanup then prevCleanup(); cleanupFunctions[player.UserId] = nil end
	local prevModel = activeCreatures[player.UserId]
	if prevModel then prevModel:Destroy(); activeCreatures[player.UserId] = nil end

	-- 5. Spawn new creature
	task.spawn(function()
		local model = Instance.new("Model")
		model.Name = "Creature_" .. tostring(player.UserId)
		model:SetAttribute("OwnerID", player.UserId)
		model.Parent = Workspace

		CreatureBuilder.Assemble(dna, model)

		local cleanup = BattleHandler.RegisterCreature(model)
		activeCreatures[player.UserId]  = model
		cleanupFunctions[player.UserId] = cleanup

		Remotes.SpawnCreature.FireClient(player, model)

		-- Push updated (consumed) inventory to client
		Remotes.UpdateInventory.FireClient(player, PlayerInventory.Get(player.UserId))
	end)
end)

-- ── Spawn DNA pickups ──────────────────────────────────────────────────────
DNASpawner.Init()

-- ── Arena & Game Loop ──────────────────────────────────────────────────────
GameManager.Init(activeCreatures)
ArenaBuilder.Build(GameManager.OnEnterPad, GameManager.OnExitPad)

print("[BioFusion] Server initialised.")
