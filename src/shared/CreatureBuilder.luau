--!strict
-- CreatureBuilder.luau
-- Assembles and disassembles creature Models from a CreatureDNA table.
-- Runs on both server (canonical spawn) and client (local preview).
-- Pure Model/Instance manipulation — no networking.

local CreatureTypes = require(script.Parent.CreatureTypes)
type CreatureDNA = {
	OwnerID: number,
	Version: number,
	TorsoID: string,
	Parts: {any},
}
type DNAPart = {
	PartID: string,
	PartType: string,
	PositionOffset: {number},
	Rotation: {number},
	Stats: {
		Weight: number,
		Aerodynamics: number,
		ArmorThickness: number,
		Health: number,
	},
}

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────

-- Upward force per unit of Aerodynamics on Wing parts.
-- Tune this to balance flight feel vs. combat stability.
local LIFT_CONSTANT: number = 50

-- Tag applied to all Parts created by this module, for easy cleanup.
local PART_TAG: string = "BioFusion_CreaturePart"

-- ─────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────

-- Returns the Torso BasePart inside parent, creating it if absent.
local function ensureTorso(parent: Model, torsoID: string): BasePart
	local existing = parent:FindFirstChild("Torso")
	if existing and existing:IsA("BasePart") then
		return existing :: BasePart
	end
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Medium stone grey")
	torso:SetAttribute("TorsoID", torsoID)
	torso.Parent = parent
	return torso
end

-- Welds `part` rigidly to `torso` via a WeldConstraint.
local function weldPart(part: BasePart, torso: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = part
	weld.Parent = part
	return weld
end

-- Connects `part` to `torso` via a BallSocketConstraint at `worldAttachPos`.
-- Allows free angular movement within ±45°.
local function socketPart(part: BasePart, torso: BasePart, worldAttachPos: Vector3): BallSocketConstraint
	-- Attachment on the limb part (at its center)
	local att0 = Instance.new("Attachment")
	att0.Name = "LimbAttachment"
	att0.CFrame = CFrame.new() -- local center of part
	att0.Parent = part

	-- Attachment on torso (transformed to torso-local space)
	local att1 = Instance.new("Attachment")
	att1.Name = "TorsoLimbAttachment_" .. part.Name
	att1.CFrame = torso.CFrame:ToObjectSpace(CFrame.new(worldAttachPos))
	att1.Parent = torso

	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0 = att0
	socket.Attachment1 = att1
	socket.LimitsEnabled = true
	socket.UpperAngle = 45
	socket.Parent = part

	return socket
end

-- Adds an upward VectorForce to a wing part scaled by its Aerodynamics stat.
-- Force is always world-up regardless of wing orientation.
local function applyWingLift(part: BasePart, aerodynamics: number): VectorForce
	local att = Instance.new("Attachment")
	att.Name = "WingLiftAttachment"
	att.CFrame = CFrame.new() -- center of part
	att.Parent = part

	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Force = Vector3.new(0, aerodynamics * LIFT_CONSTANT, 0)
	vf.Parent = part

	return vf
end

-- Inserts a hidden, low-Y anchor part to shift the assembly's CoM downward.
-- This improves stability for heavy armor by pulling the center of gravity down.
local function shiftCoMDownward(torso: BasePart, anchorY: number): BasePart
	local anchor = Instance.new("Part")
	anchor.Name   = "CoM_Anchor"
	anchor.Size   = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.Massless     = false  -- must contribute mass to shift CoM
	anchor.CFrame = torso.CFrame * CFrame.new(0, anchorY, 0)
	anchor:SetAttribute(PART_TAG, true)
	anchor.Parent = torso.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = anchor
	weld.Parent = anchor

	return anchor
end

-- ─────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────

local CreatureBuilder = {}

-- Assembles a creature Model from a DNA table.
-- `parent` must be an existing Model; a "Torso" BasePart is created inside it if absent.
-- Sets "Health" and "MaxHealth" number attributes on the Model.
-- @param dna    CreatureDNA  Full creature definition
-- @param parent Model        Target Model to populate
-- @return Model              The same `parent`, now populated
function CreatureBuilder.Assemble(dna: CreatureDNA, parent: Model): Model
	local torso = ensureTorso(parent, dna.TorsoID)

	-- Freeze torso during assembly to prevent physics jitter while welding
	torso.Anchored = true

	local totalHealth = 0

	for _, rawPart in dna.Parts do
		local dnaPart = rawPart :: DNAPart

		local part = Instance.new("Part")
		part.Name = dnaPart.PartID
		-- Size is uniform for now; extend with asset lookup or Stats-driven sizing later
		part.Size = Vector3.new(1, 1, 1)

		-- Position and orient relative to torso
		local offsetCF = CFrame.new(
			dnaPart.PositionOffset[1],
			dnaPart.PositionOffset[2],
			dnaPart.PositionOffset[3]
		) * CFrame.Angles(
			math.rad(dnaPart.Rotation[1]),
			math.rad(dnaPart.Rotation[2]),
			math.rad(dnaPart.Rotation[3])
		)
		part.CFrame = torso.CFrame * offsetCF

		-- Store stats as attributes for BattleHandler access
		part:SetAttribute("Weight",         dnaPart.Stats.Weight)
		part:SetAttribute("Aerodynamics",   dnaPart.Stats.Aerodynamics)
		part:SetAttribute("ArmorThickness", dnaPart.Stats.ArmorThickness)
		part:SetAttribute("PartHealth",     dnaPart.Stats.Health)
		part:SetAttribute(PART_TAG, true)

		part.Parent = parent

		if dnaPart.PartType == "Armor" then
			-- Rigid attachment; no movement relative to torso
			part.Massless = false
			weldPart(part, torso)
			-- Shift CoM downward by 1 unit below the armor plate's attachment point
			shiftCoMDownward(torso, dnaPart.PositionOffset[2] - 1)

		elseif dnaPart.PartType == "Limb" then
			-- Flexible joint; BallSocket allows angular freedom
			socketPart(part, torso, part.Position)

		elseif dnaPart.PartType == "Wing" then
			-- Rigid attachment + lift force
			-- Massless = false so VectorForce (F = ma) produces meaningful acceleration
			part.Massless = false
			weldPart(part, torso)
			applyWingLift(part, dnaPart.Stats.Aerodynamics)
		end

		totalHealth += dnaPart.Stats.Health
	end

	-- Store creature health pool on the Model itself
	parent:SetAttribute("Health",    totalHealth)
	parent:SetAttribute("MaxHealth", totalHealth)

	-- Unfreeze: let physics take over
	torso.Anchored = false

	return parent
end

-- Strips all Bio-Fusion parts from a Model without destroying the Model or Torso.
-- Use this to rebuild a creature with new DNA without recreating the container.
-- @param model Model  The creature model to strip
function CreatureBuilder.Disassemble(model: Model): ()
	for _, child in model:GetChildren() do
		if child:GetAttribute(PART_TAG) then
			child:Destroy()
		end
	end
	-- Also clear CoM anchors parented directly under the model
	for _, desc in model:GetDescendants() do
		if desc:GetAttribute(PART_TAG) and desc.Parent == model then
			desc:Destroy()
		end
	end
end

return CreatureBuilder
