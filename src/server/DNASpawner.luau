--!strict
-- DNASpawner.luau
-- Spawns DNA pickup Parts in the world and handles collection via Touched events.
-- Each pickup is a coloured, rotating, anchored Part with a BillboardGui label.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared           = ReplicatedStorage:WaitForChild("Shared")
local Remotes          = require(Shared:WaitForChild("Remotes"))
local PlayerInventory  = require(script.Parent:WaitForChild("PlayerInventory"))

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────

local RESPAWN_DELAY = 15  -- seconds before a collected pickup reappears
local ROTATION_SPEED = 60 -- degrees per second

local PICKUP_CONFIG: {{partType: string, color: Color3, size: Vector3, position: Vector3}} = {
	{ partType = "Armor", color = Color3.fromRGB(200, 100,  50), size = Vector3.new(1.5, 1.5, 1.5), position = Vector3.new( 30, 2,   0) },
	{ partType = "Armor", color = Color3.fromRGB(200, 100,  50), size = Vector3.new(1.5, 1.5, 1.5), position = Vector3.new(-30, 2,   0) },
	{ partType = "Wing",  color = Color3.fromRGB( 80, 160, 230), size = Vector3.new(2,   0.4, 1.2), position = Vector3.new(  0, 2,  30) },
	{ partType = "Wing",  color = Color3.fromRGB( 80, 160, 230), size = Vector3.new(2,   0.4, 1.2), position = Vector3.new(  0, 2, -30) },
	{ partType = "Limb",  color = Color3.fromRGB( 80, 200, 120), size = Vector3.new(0.8, 1.8, 0.8), position = Vector3.new( 20, 2,  20) },
	{ partType = "Limb",  color = Color3.fromRGB( 80, 200, 120), size = Vector3.new(0.8, 1.8, 0.8), position = Vector3.new(-20, 2, -20) },
}

local TYPE_ICON: {[string]: string} = {
	Armor = "🛡️",
	Wing  = "🪶",
	Limb  = "💪",
}

-- ─────────────────────────────────────────────
-- Pickup folder
-- ─────────────────────────────────────────────

local pickupFolder = Instance.new("Folder")
pickupFolder.Name = "DNAPickups"
pickupFolder.Parent = Workspace

-- ─────────────────────────────────────────────
-- Per-pickup debounce
-- ─────────────────────────────────────────────

local debounce: {[BasePart]: true} = {}

-- ─────────────────────────────────────────────
-- Create a single pickup Part
-- ─────────────────────────────────────────────

local function createPickup(cfg: {partType: string, color: Color3, size: Vector3, position: Vector3}): BasePart
	local part = Instance.new("Part")
	part.Name = cfg.partType .. "_DNA"
	part.Size = cfg.size
	part.CFrame = CFrame.new(cfg.position)
	part.Anchored = true
	part.CanCollide = false
	part.BrickColor = BrickColor.new(cfg.color)
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	part:SetAttribute("DNAType", cfg.partType)
	part.Parent = pickupFolder

	-- BillboardGui label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = (TYPE_ICON[cfg.partType] or "🧬") .. " " .. cfg.partType .. " DNA"
	lbl.TextColor3 = cfg.color
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = billboard

	return part
end

-- ─────────────────────────────────────────────
-- Touched handler
-- ─────────────────────────────────────────────

local function onPickupTouched(pickup: BasePart, hit: Instance, cfg: {partType: string, color: Color3, size: Vector3, position: Vector3})
	if debounce[pickup] then return end

	-- Resolve touching player
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		-- Also try one level up (accessories etc.)
		character = hit.Parent and hit.Parent.Parent
		player = if character then Players:GetPlayerFromCharacter(character) else nil
	end
	if not player then return end

	debounce[pickup] = true

	-- Hide pickup immediately
	pickup.Transparency = 1
	pickup.CanCollide = false
	local billboard = pickup:FindFirstChildOfClass("BillboardGui")
	if billboard then billboard.Enabled = false end

	-- Update inventory
	local dnaType = cfg.partType
	PlayerInventory.Add(player.UserId, dnaType)
	local newInv = PlayerInventory.Get(player.UserId)

	-- Notify client
	Remotes.UpdateInventory.FireClient(player, newInv)
	Remotes.DNAPickedUp.FireClient(player, dnaType)

	-- Respawn after delay
	task.delay(RESPAWN_DELAY, function()
		if pickup and pickup.Parent then
			pickup.Transparency = 0
			pickup.CanCollide = false
			if billboard then billboard.Enabled = true end
			debounce[pickup] = nil
		end
	end)
end

-- ─────────────────────────────────────────────
-- Rotation loop
-- ─────────────────────────────────────────────

local pickupParts: {BasePart} = {}

RunService.Heartbeat:Connect(function(dt: number)
	local angle = math.rad(ROTATION_SPEED * dt)
	for _, part in pickupParts do
		if part and part.Parent and part.Transparency == 0 then
			part.CFrame = part.CFrame * CFrame.Angles(0, angle, 0)
		end
	end
end)

-- ─────────────────────────────────────────────
-- Spawn all pickups
-- ─────────────────────────────────────────────

local DNASpawner = {}

function DNASpawner.Init(): ()
	for _, cfg in PICKUP_CONFIG do
		local pickup = createPickup(cfg)
		table.insert(pickupParts, pickup)

		-- Capture cfg in closure
		local capturedCfg = cfg
		pickup.Touched:Connect(function(hit: BasePart)
			onPickupTouched(pickup, hit, capturedCfg)
		end)
	end
end

return DNASpawner
