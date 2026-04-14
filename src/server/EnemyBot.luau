--!strict
-- EnemyBot.luau
-- Spawns a hardcoded bot creature in the arena with simple Heartbeat AI.

local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace     = game:GetService("Workspace")

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local CreatureTypes = require(Shared:WaitForChild("CreatureTypes"))
local CreatureBuilder = require(Shared:WaitForChild("CreatureBuilder"))

local EnemyBot = {}

-- ─────────────────────────────────────────────
-- Bot DNA (2× Armor + 1× Limb = 160 HP total)
-- ─────────────────────────────────────────────

local BOT_DNA: CreatureTypes.CreatureDNA = {
	OwnerID  = 0,
	Version  = 1,
	TorsoID  = "BotTorso",
	Parts    = {
		{
			PartID         = "BotArmor_1",
			PartType       = "Armor",
			PositionOffset = {0, -1.5, 0},
			Rotation       = {0, 0, 0},
			Stats          = { Weight = 8, Aerodynamics = 0, ArmorThickness = 3.0, Health = 60 },
		},
		{
			PartID         = "BotArmor_2",
			PartType       = "Armor",
			PositionOffset = {0, -3.0, 0},
			Rotation       = {0, 0, 0},
			Stats          = { Weight = 8, Aerodynamics = 0, ArmorThickness = 3.0, Health = 60 },
		},
		{
			PartID         = "BotLimb_1",
			PartType       = "Limb",
			PositionOffset = {1.5, -1, 0},
			Rotation       = {0, 0, 0},
			Stats          = { Weight = 3, Aerodynamics = 0, ArmorThickness = 1.0, Health = 40 },
		},
	},
}

local BOT_SPEED  = 8  -- studs per second
local AI_FRAMES  = 3  -- run AI every Nth heartbeat frame (~20 Hz)

-- ─────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────

function EnemyBot.Spawn(arenaCenter: Vector3, onBotDied: () -> ()): () -> ()
	-- Build bot model
	local model = Instance.new("Model")
	model.Name = "Creature_Bot"
	model:SetAttribute("OwnerID", 0)
	model.Parent = Workspace

	CreatureBuilder.Assemble(BOT_DNA, model)

	-- Position bot into the arena (CreatureBuilder always names it "Torso")
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if torso then
		torso.Anchored = true
		torso.CFrame = CFrame.new(arenaCenter + Vector3.new(0, 2, 18))
		task.wait()
		torso.Anchored = false
	end

	-- Track whether the death callback has already fired
	local died       = false
	local frameCount = 0
	local heartbeat: RBXScriptConnection

	-- Watch Health attribute for death
	model:GetAttributeChangedSignal("Health"):Connect(function()
		local hp = (model:GetAttribute("Health") :: number?) or 0
		if hp <= 0 and not died then
			died = true
			if heartbeat then heartbeat:Disconnect() end
			onBotDied()
		end
	end)

	-- Heartbeat AI: move toward nearest player creature
	heartbeat = RunService.Heartbeat:Connect(function(dt: number)
		frameCount += 1
		if frameCount % AI_FRAMES ~= 0 then return end
		if died then return end

		local botTorso = model:FindFirstChild("Torso") :: BasePart?
		if not botTorso then return end

		-- Find nearest Creature_* that is not us and has OwnerID != 0
		local nearest: BasePart? = nil
		local nearestDist = math.huge

		for _, obj in Workspace:GetChildren() do
			if obj:IsA("Model") and obj ~= model and obj.Name:sub(1,9) == "Creature_" then
				local ownerID = obj:GetAttribute("OwnerID")
				if ownerID and ownerID ~= 0 then
					local t = obj:FindFirstChildWhichIsA("BasePart") :: BasePart?
					if t then
						local dist = (t.Position - botTorso.Position).Magnitude
						if dist < nearestDist then
							nearestDist = dist
							nearest = t
						end
					end
				end
			end
		end

		if not nearest then return end

		-- Stop if already close enough (let BattleHandler handle collisions)
		if nearestDist <= 4 then return end

		-- CFrame-step toward target
		local direction = (nearest.Position - botTorso.Position).Unit
		local step = direction * BOT_SPEED * (dt * AI_FRAMES) -- compensate for skipped frames
		botTorso.CFrame = botTorso.CFrame + step
	end)

	-- Return cleanup function
	local function cleanup()
		died = true
		if heartbeat then heartbeat:Disconnect() end
		if model and model.Parent then
			model:Destroy()
		end
	end

	return cleanup
end

return EnemyBot
