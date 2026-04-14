--!strict
-- GameManager.luau
-- Per-player state machine: Collect → InArena → Result → Collect
-- States: "Collect" | "InArena" | "Result"

local Players        = game:GetService("Players")
local Workspace      = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local Remotes        = require(Shared:WaitForChild("Remotes"))
local PlayerInventory = require(script.Parent:WaitForChild("PlayerInventory"))
local EnemyBot       = require(script.Parent:WaitForChild("EnemyBot"))
local ArenaBuilder   = require(script.Parent:WaitForChild("ArenaBuilder"))

-- ─────────────────────────────────────────────
-- Types
-- ─────────────────────────────────────────────

type GameState = "Collect" | "InArena" | "Result"

type PlayerRecord = {
	state:          GameState,
	alreadyResolved: boolean,
	botCleanup:     (() -> ())?,
	hpConn:         RBXScriptConnection?,
}

-- ─────────────────────────────────────────────
-- Module state
-- ─────────────────────────────────────────────

local GameManager = {}

local records:         {[number]: PlayerRecord}  = {}
local activeCreatures: {[number]: Model}         = {}  -- injected by Init

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────

local function getRecord(userId: number): PlayerRecord?
	return records[userId]
end

-- Teleport character torso to a world position.
local function teleportChar(player: Player, targetPos: Vector3)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
end

-- Teleport a creature model's primary/torso part.
local function teleportCreature(model: Model, targetPos: Vector3)
	-- Try PrimaryPart first, fall back to first BasePart
	local root: BasePart? = model.PrimaryPart :: BasePart?
	if not root then
		root = model:FindFirstChildWhichIsA("BasePart") :: BasePart?
	end
	if not root then return end

	local wasAnchored = root.Anchored
	root.Anchored = true
	root.CFrame   = CFrame.new(targetPos)
	task.wait()
	root.Anchored = wasAnchored
end

-- Give DNA reward to a player and push updated inventory to client.
local function grantReward(player: Player, reward: {Armor: number, Wing: number, Limb: number})
	local uid = player.UserId
	if reward.Armor > 0 then PlayerInventory.Add(uid, "Armor") end
	if reward.Wing  > 0 then PlayerInventory.Add(uid, "Wing")  end
	if reward.Limb  > 0 then PlayerInventory.Add(uid, "Limb")  end
	Remotes.UpdateInventory.FireClient(player, PlayerInventory.Get(uid))
end

-- ─────────────────────────────────────────────
-- Fight resolution
-- ─────────────────────────────────────────────

local function resolveArena(player: Player, won: boolean)
	local rec = getRecord(player.UserId)
	if not rec then return end
	if rec.alreadyResolved then return end
	rec.alreadyResolved = true
	rec.state = "Result"

	-- Kill bot
	if rec.botCleanup then
		rec.botCleanup()
		rec.botCleanup = nil
	end

	-- Disconnect HP watcher
	if rec.hpConn then
		rec.hpConn:Disconnect()
		rec.hpConn = nil
	end

	-- Determine reward
	local reward: {Armor: number, Wing: number, Limb: number}
	if won then
		reward = { Armor = 1, Wing = 1, Limb = 1 }
	else
		reward = { Armor = 0, Wing = 1, Limb = 1 }
	end
	grantReward(player, reward)

	-- Notify client
	Remotes.GameResult.FireClient(player, {
		won       = won,
		dnaReward = reward :: {[string]: number},
	})
end

-- ─────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────

function GameManager.Init(creatures: {[number]: Model}): ()
	activeCreatures = creatures

	-- LeaveArena: client pressed "Weiter" on result screen
	Remotes.LeaveArena.OnServerEvent(function(player: Player)
		local rec = getRecord(player.UserId)
		if not rec then return end
		if rec.state ~= "Result" then return end
		rec.state           = "Collect"
		rec.alreadyResolved = false

		-- Teleport character back to build zone
		teleportChar(player, ArenaBuilder.BUILD_RETURN_TP)

		-- Teleport creature back too (if it still exists)
		local model = activeCreatures[player.UserId]
		if model and model.Parent then
			teleportCreature(model, ArenaBuilder.BUILD_RETURN_TP + Vector3.new(0, 2, 3))
		end
	end)

	-- Clean up record on leave
	Players.PlayerRemoving:Connect(function(player: Player)
		local rec = records[player.UserId]
		if rec then
			if rec.botCleanup then rec.botCleanup() end
			if rec.hpConn    then rec.hpConn:Disconnect() end
			records[player.UserId] = nil
		end
	end)

	-- Initialise record for already-connected players (Studio test)
	for _, player in Players:GetPlayers() do
		if not records[player.UserId] then
			records[player.UserId] = {
				state           = "Collect",
				alreadyResolved = false,
				botCleanup      = nil,
				hpConn          = nil,
			}
		end
	end

	Players.PlayerAdded:Connect(function(player: Player)
		records[player.UserId] = {
			state           = "Collect",
			alreadyResolved = false,
			botCleanup      = nil,
			hpConn          = nil,
		}
	end)

	print("[BioFusion] GameManager initialised.")
end

function GameManager.OnEnterPad(player: Player): ()
	-- Ensure record exists
	if not records[player.UserId] then
		records[player.UserId] = {
			state           = "Collect",
			alreadyResolved = false,
			botCleanup      = nil,
			hpConn          = nil,
		}
	end
	local rec = records[player.UserId]

	-- Must be in Collect state and have an active creature
	if rec.state ~= "Collect" then return end
	local model = activeCreatures[player.UserId]
	if not model or not model.Parent then
		warn(string.format("[BioFusion] Player %d tried to enter arena without a creature.", player.UserId))
		return
	end

	rec.state           = "InArena"
	rec.alreadyResolved = false

	-- Teleport player character into arena
	teleportChar(player, ArenaBuilder.ARENA_ENTER_TP + Vector3.new(-10, 0, 0))

	-- Teleport creature into arena
	teleportCreature(model, ArenaBuilder.ARENA_ENTER_TP + Vector3.new(-8, 2, 0))

	-- Notify client (show arena badge)
	Remotes.EnterArena.FireClient(player)

	-- Watch player creature HP → Defeat
	local function watchPlayerHP()
		if rec.hpConn then rec.hpConn:Disconnect() end
		rec.hpConn = model:GetAttributeChangedSignal("Health"):Connect(function()
			local hp = (model:GetAttribute("Health") :: number?) or 0
			if hp <= 0 then
				resolveArena(player, false) -- Defeat
			end
		end)
	end
	watchPlayerHP()

	-- Spawn bot and watch its death → Victory
	local arenaCenter = ArenaBuilder.ARENA_ENTER_TP
	rec.botCleanup = EnemyBot.Spawn(arenaCenter, function()
		resolveArena(player, true) -- Victory
	end)
end

function GameManager.OnExitPad(player: Player): ()
	local rec = getRecord(player.UserId)
	if not rec then return end
	-- Only allow exit from InArena (or Result as escape hatch)
	if rec.state ~= "InArena" and rec.state ~= "Result" then return end

	-- Clean up bot if still running
	if rec.botCleanup then
		rec.botCleanup()
		rec.botCleanup = nil
	end
	if rec.hpConn then
		rec.hpConn:Disconnect()
		rec.hpConn = nil
	end

	rec.state           = "Collect"
	rec.alreadyResolved = false

	-- Teleport player back
	teleportChar(player, ArenaBuilder.BUILD_RETURN_TP)

	-- Teleport creature back
	local model = activeCreatures[player.UserId]
	if model and model.Parent then
		teleportCreature(model, ArenaBuilder.BUILD_RETURN_TP + Vector3.new(0, 2, 3))
	end
end

return GameManager
