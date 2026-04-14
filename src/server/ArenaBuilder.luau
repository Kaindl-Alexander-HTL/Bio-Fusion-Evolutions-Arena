--!strict
-- ArenaBuilder.luau
-- Builds arena geometry and teleport pads in the Workspace.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ArenaBuilder = {}

-- Teleport destinations (used by GameManager)
ArenaBuilder.ARENA_ENTER_TP  = Vector3.new(0, 22, 0)    -- inside arena
ArenaBuilder.BUILD_RETURN_TP = Vector3.new(60, 5, 0)    -- back in build zone

-- Debounce: track when each player last triggered the Enter pad
local enterDebounce: {[number]: number} = {}
local ENTER_COOLDOWN = 3 -- seconds

-- ─────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────

local function mkPart(
	name:     string,
	size:     Vector3,
	pos:      Vector3,
	color:    Color3,
	material: Enum.Material,
	anchored: boolean,
	canCollide: boolean,
	transparency: number
): Part
	local p = Instance.new("Part")
	p.Name        = name
	p.Size        = size
	p.CFrame      = CFrame.new(pos)
	p.Color       = color
	p.Material    = material
	p.Anchored    = anchored
	p.CanCollide  = canCollide
	p.Transparency = transparency
	p.CastShadow  = false
	p.Parent      = Workspace
	return p
end

local function addLabel(part: Part, text: string)
	local bg = Instance.new("BillboardGui")
	bg.Size          = UDim2.new(0, 160, 0, 40)
	bg.StudsOffset   = Vector3.new(0, 2.5, 0)
	bg.AlwaysOnTop   = false
	bg.Parent        = part

	local lbl = Instance.new("TextLabel")
	lbl.Size             = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text             = text
	lbl.TextColor3       = Color3.fromRGB(255, 255, 255)
	lbl.TextSize         = 16
	lbl.Font             = Enum.Font.GothamBold
	lbl.TextStrokeTransparency = 0.4
	lbl.Parent           = bg
end

-- ─────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────

function ArenaBuilder.Build(onEnterPad: (Player) -> (), onExitPad: (Player) -> ()): ()

	-- Arena floor (dark base)
	mkPart(
		"ArenaFloor",
		Vector3.new(60, 2, 60),
		Vector3.new(0, 20, 0),
		Color3.fromRGB(12, 8, 22),
		Enum.Material.SmoothPlastic,
		true, true, 0
	)

	-- Neon edge strips along all 4 sides (glowing border)
	local STRIP_COLOR = Color3.fromRGB(140, 0, 255)
	mkPart("ArenaEdge_N", Vector3.new(60, 0.4, 0.4), Vector3.new(0, 21.2, -30),  STRIP_COLOR, Enum.Material.Neon, true, false, 0)
	mkPart("ArenaEdge_S", Vector3.new(60, 0.4, 0.4), Vector3.new(0, 21.2,  30),  STRIP_COLOR, Enum.Material.Neon, true, false, 0)
	mkPart("ArenaEdge_W", Vector3.new(0.4, 0.4, 60), Vector3.new(-30, 21.2, 0),  STRIP_COLOR, Enum.Material.Neon, true, false, 0)
	mkPart("ArenaEdge_E", Vector3.new(0.4, 0.4, 60), Vector3.new( 30, 21.2, 0),  STRIP_COLOR, Enum.Material.Neon, true, false, 0)

	-- Neon cross lines across the floor (arena grid feel)
	local LINE_COLOR = Color3.fromRGB(60, 0, 100)
	mkPart("ArenaLine_X", Vector3.new(60, 0.1, 0.5), Vector3.new(0, 21.05, 0), LINE_COLOR, Enum.Material.Neon, true, false, 0)
	mkPart("ArenaLine_Z", Vector3.new(0.5, 0.1, 60), Vector3.new(0, 21.05, 0), LINE_COLOR, Enum.Material.Neon, true, false, 0)

	-- Center circle indicator (glowing ring ring approximated as a flat disc)
	mkPart("ArenaCenter", Vector3.new(8, 0.15, 8), Vector3.new(0, 21.08, 0),
		Color3.fromRGB(180, 0, 255), Enum.Material.Neon, true, false, 0)

	-- Corner pillars (4 corners, purely visual)
	local PILLAR_COLOR = Color3.fromRGB(100, 0, 180)
	for _, cx in {-28, 28} do
		for _, cz in {-28, 28} do
			mkPart("ArenaPillar", Vector3.new(2, 10, 2), Vector3.new(cx, 26, cz),
				PILLAR_COLOR, Enum.Material.Neon, true, false, 0)
		end
	end

	-- Invisible walls (keep creatures inside)
	local wallColor = Color3.fromRGB(15, 5, 30)
	mkPart("ArenaWall_N", Vector3.new(60,10,2),  Vector3.new(0,26,-31),   wallColor, Enum.Material.SmoothPlastic, true, true, 1)
	mkPart("ArenaWall_S", Vector3.new(60,10,2),  Vector3.new(0,26, 31),   wallColor, Enum.Material.SmoothPlastic, true, true, 1)
	mkPart("ArenaWall_W", Vector3.new(2, 10,60), Vector3.new(-31,26,0),   wallColor, Enum.Material.SmoothPlastic, true, true, 1)
	mkPart("ArenaWall_E", Vector3.new(2, 10,60), Vector3.new( 31,26,0),   wallColor, Enum.Material.SmoothPlastic, true, true, 1)

	-- Enter pad (build zone → arena)
	local enterPad = mkPart(
		"ArenaEnterPad",
		Vector3.new(4, 0.5, 4),
		Vector3.new(60, 1, 0),
		Color3.fromRGB(255, 0, 200),
		Enum.Material.Neon,
		true, true, 0
	)
	addLabel(enterPad, "⚔️ Arena betreten")

	-- Exit pad (arena → build zone)
	local exitPad = mkPart(
		"ArenaExitPad",
		Vector3.new(4, 0.5, 4),
		Vector3.new(0, 21.5, -20),
		Color3.fromRGB(0, 230, 255),
		Enum.Material.Neon,
		true, true, 0
	)
	addLabel(exitPad, "🏠 Zurück")

	-- ── Enter pad touch ──────────────────────
	enterPad.Touched:Connect(function(hit: BasePart)
		-- Only fire for player characters (not creature parts)
		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		-- Debounce
		local now = tick()
		local last = enterDebounce[player.UserId] or 0
		if now - last < ENTER_COOLDOWN then return end
		enterDebounce[player.UserId] = now

		onEnterPad(player)
	end)

	-- ── Exit pad touch ───────────────────────
	exitPad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		onExitPad(player)
	end)

	print("[BioFusion] ArenaBuilder: arena built.")
end

return ArenaBuilder
