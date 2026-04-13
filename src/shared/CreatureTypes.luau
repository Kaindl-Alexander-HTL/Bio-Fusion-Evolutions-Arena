--!strict
-- CreatureTypes.luau
-- Single source of truth for all Bio-Fusion type definitions and DNA serialization.
-- Both server and client require this module.

-- ─────────────────────────────────────────────
-- Type Definitions
-- ─────────────────────────────────────────────

export type PartStats = {
	Weight: number,         -- Contributes to assembly mass (kg equivalent)
	Aerodynamics: number,   -- 0–1 scalar; drives VectorForce magnitude on Wings
	ArmorThickness: number, -- Damage reduction multiplier (1 = no reduction)
	Health: number,         -- HP contribution to the creature's total health pool
}

-- Drives constraint type in CreatureBuilder:
--   "Armor" → WeldConstraint + hidden CoM anchor
--   "Limb"  → BallSocketConstraint
--   "Wing"  → WeldConstraint + VectorForce
export type PartType = "Armor" | "Limb" | "Wing"

export type DNAPart = {
	PartID: string,           -- Max 32 ASCII chars; maps to a part template name
	PartType: PartType,
	PositionOffset: {number}, -- Always {x, y, z} relative to Torso origin
	Rotation: {number},       -- Always {rx, ry, rz} in degrees
	Stats: PartStats,
}

export type CreatureDNA = {
	OwnerID: number,   -- Player.UserId (u32)
	Version: number,   -- Schema version; currently 1
	TorsoID: string,   -- Max 32 ASCII chars; template name for the Torso BasePart
	Parts: {DNAPart},
}

-- ─────────────────────────────────────────────
-- Buffer Layout (all multi-byte values little-endian)
--
-- HEADER (variable length):
--   [0]        u8   Version
--   [1–4]      u32  OwnerID
--   [5]        u8   TorsoID byte length (N_t, max 32)
--   [6..5+N_t] u8[] TorsoID bytes
--   [6+N_t]    u16  Part count
--
-- PER PART (repeating, variable length):
--   u8         PartID byte length (N_p, max 32)
--   u8[N_p]    PartID bytes
--   u8         PartType (0=Armor, 1=Limb, 2=Wing)
--   f32 × 3    PositionOffset X, Y, Z
--   f32 × 3    Rotation X, Y, Z (degrees)
--   f32 × 4    Stats: Weight, Aerodynamics, ArmorThickness, Health
--   → 43 bytes fixed + 1 + N_p per part; worst case ~75 bytes/part
--
-- DataStore note: DataStore:SetAsync rejects raw buffer values.
-- Use DNAToString / DNAFromString for persistence (byte-by-byte string encoding).
-- ─────────────────────────────────────────────

local CURRENT_VERSION: number = 1

local PART_TYPE_ENCODE: {[PartType]: number} = {
	Armor = 0,
	Limb  = 1,
	Wing  = 2,
}

local PART_TYPE_DECODE: {[number]: PartType} = {
	[0] = "Armor",
	[1] = "Limb",
	[2] = "Wing",
}

-- ─────────────────────────────────────────────
-- Size calculation helpers
-- ─────────────────────────────────────────────

local function calcBufferSize(dna: CreatureDNA): number
	-- Header: 1 (ver) + 4 (ownerID) + 1 (torsoLen) + #torsoID + 2 (partCount)
	local size = 1 + 4 + 1 + #dna.TorsoID + 2
	for _, part in dna.Parts do
		-- 1 (partIDLen) + #partID + 1 (partType) + 12 (pos) + 12 (rot) + 16 (stats)
		size += 1 + #part.PartID + 1 + 12 + 12 + 16
	end
	return size
end

-- ─────────────────────────────────────────────
-- Serialize: CreatureDNA → buffer
-- ─────────────────────────────────────────────

local function Serialize(dna: CreatureDNA): buffer
	assert(#dna.TorsoID <= 32, "TorsoID exceeds 32-char limit")
	assert(#dna.Parts <= 65535, "Part count exceeds u16 max")

	local buf = buffer.create(calcBufferSize(dna))
	local offset = 0

	-- Header
	buffer.writeu8(buf, offset, CURRENT_VERSION) offset += 1
	buffer.writeu32(buf, offset, dna.OwnerID)    offset += 4

	local torsoBytes = #dna.TorsoID
	buffer.writeu8(buf, offset, torsoBytes) offset += 1
	buffer.writestring(buf, offset, dna.TorsoID) offset += torsoBytes

	buffer.writeu16(buf, offset, #dna.Parts) offset += 2

	-- Parts
	for _, part in dna.Parts do
		assert(#part.PartID <= 32, "PartID exceeds 32-char limit: " .. part.PartID)

		local idBytes = #part.PartID
		buffer.writeu8(buf, offset, idBytes) offset += 1
		buffer.writestring(buf, offset, part.PartID) offset += idBytes

		local typeCode = PART_TYPE_ENCODE[part.PartType]
		assert(typeCode ~= nil, "Unknown PartType: " .. part.PartType)
		buffer.writeu8(buf, offset, typeCode) offset += 1

		-- PositionOffset {x, y, z}
		buffer.writef32(buf, offset, part.PositionOffset[1]) offset += 4
		buffer.writef32(buf, offset, part.PositionOffset[2]) offset += 4
		buffer.writef32(buf, offset, part.PositionOffset[3]) offset += 4

		-- Rotation {rx, ry, rz}
		buffer.writef32(buf, offset, part.Rotation[1]) offset += 4
		buffer.writef32(buf, offset, part.Rotation[2]) offset += 4
		buffer.writef32(buf, offset, part.Rotation[3]) offset += 4

		-- Stats
		buffer.writef32(buf, offset, part.Stats.Weight)         offset += 4
		buffer.writef32(buf, offset, part.Stats.Aerodynamics)   offset += 4
		buffer.writef32(buf, offset, part.Stats.ArmorThickness) offset += 4
		buffer.writef32(buf, offset, part.Stats.Health)         offset += 4
	end

	return buf
end

-- ─────────────────────────────────────────────
-- Deserialize: buffer → CreatureDNA
-- ─────────────────────────────────────────────

local function Deserialize(buf: buffer): CreatureDNA
	local offset = 0

	local version = buffer.readu8(buf, offset) offset += 1
	if version ~= CURRENT_VERSION then
		error(string.format("DNA version mismatch: expected %d, got %d", CURRENT_VERSION, version))
	end

	local ownerID = buffer.readu32(buf, offset) offset += 4

	local torsoLen = buffer.readu8(buf, offset) offset += 1
	local torsoID  = buffer.readstring(buf, offset, torsoLen) offset += torsoLen

	local partCount = buffer.readu16(buf, offset) offset += 2

	local parts: {DNAPart} = {}

	for _ = 1, partCount do
		local idLen  = buffer.readu8(buf, offset) offset += 1
		local partID = buffer.readstring(buf, offset, idLen) offset += idLen

		local typeCode = buffer.readu8(buf, offset) offset += 1
		local partType = PART_TYPE_DECODE[typeCode]
		assert(partType ~= nil, "Unknown PartType code: " .. typeCode)

		local px = buffer.readf32(buf, offset) offset += 4
		local py = buffer.readf32(buf, offset) offset += 4
		local pz = buffer.readf32(buf, offset) offset += 4

		local rx = buffer.readf32(buf, offset) offset += 4
		local ry = buffer.readf32(buf, offset) offset += 4
		local rz = buffer.readf32(buf, offset) offset += 4

		local weight         = buffer.readf32(buf, offset) offset += 4
		local aerodynamics   = buffer.readf32(buf, offset) offset += 4
		local armorThickness = buffer.readf32(buf, offset) offset += 4
		local health         = buffer.readf32(buf, offset) offset += 4

		table.insert(parts, {
			PartID = partID,
			PartType = partType,
			PositionOffset = {px, py, pz},
			Rotation = {rx, ry, rz},
			Stats = {
				Weight         = weight,
				Aerodynamics   = aerodynamics,
				ArmorThickness = armorThickness,
				Health         = health,
			},
		})
	end

	return {
		OwnerID = ownerID,
		Version = version,
		TorsoID = torsoID,
		Parts   = parts,
	}
end

-- ─────────────────────────────────────────────
-- DataStore helpers: buffer ↔ string
-- Roblox DataStore cannot store buffer directly; encode as a Lua string.
-- ─────────────────────────────────────────────

local function BufferToString(buf: buffer): string
	local len = buffer.len(buf)
	local chars: {string} = table.create(len)
	for i = 0, len - 1 do
		chars[i + 1] = string.char(buffer.readu8(buf, i))
	end
	return table.concat(chars)
end

local function StringToBuffer(str: string): buffer
	local len = #str
	local buf = buffer.create(len)
	for i = 1, len do
		buffer.writeu8(buf, i - 1, string.byte(str, i))
	end
	return buf
end

-- ─────────────────────────────────────────────

return {
	Serialize      = Serialize,
	Deserialize    = Deserialize,
	BufferToString = BufferToString,
	StringToBuffer = StringToBuffer,
}
