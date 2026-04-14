--!strict
-- Remotes.luau
-- Centralised, typed wrappers for all Bio-Fusion client-server communication.
-- Server: creates the RemoteEvents on first require.
-- Client: retrieves them via WaitForChild on first require.
-- Luau module caching guarantees the init block runs exactly once per context.

local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "BioFusionRemotes"
local REMOTE_TIMEOUT = 10 -- seconds for WaitForChild on client

-- ─────────────────────────────────────────────
-- Folder bootstrap
-- ─────────────────────────────────────────────

local remoteFolder: Folder

if RunService:IsServer() then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = FOLDER_NAME
	remoteFolder.Parent = ReplicatedStorage
else
	remoteFolder = ReplicatedStorage:WaitForChild(FOLDER_NAME, REMOTE_TIMEOUT) :: Folder
end

local function getOrCreate(name: string): RemoteEvent
	if RunService:IsServer() then
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = remoteFolder
		return re
	else
		return remoteFolder:WaitForChild(name, REMOTE_TIMEOUT) :: RemoteEvent
	end
end

-- ─────────────────────────────────────────────
-- Raw RemoteEvent instances
-- ─────────────────────────────────────────────

local reSyncDNA        = getOrCreate("SyncDNA")
local reSpawnCreature  = getOrCreate("SpawnCreature")
local reApplyDamage    = getOrCreate("ApplyDamage")
local reUpdateInventory = getOrCreate("UpdateInventory")
local reDNAPickedUp    = getOrCreate("DNAPickedUp")

-- ─────────────────────────────────────────────
-- Typed wrapper module
-- ─────────────────────────────────────────────

local Remotes = {}

-- ── SyncDNA ─────────────────────────────────
-- Direction: Client → Server
-- Payload:   buffer (compact binary-encoded CreatureDNA)
-- Usage:     Client calls FireServer after editing DNA; server validates & spawns.

Remotes.SyncDNA = {}

-- Called by client to send a serialized DNA buffer to the server.
-- @param dnaBuffer buffer  Output of CreatureTypes.Serialize(dna)
function Remotes.SyncDNA.FireServer(dnaBuffer: buffer): ()
	reSyncDNA:FireServer(dnaBuffer)
end

-- Called by server to register a handler for incoming DNA sync requests.
-- @param callback (player: Player, dnaBuffer: buffer) -> ()
-- @return RBXScriptConnection  Disconnect to unregister.
function Remotes.SyncDNA.OnServerEvent(callback: (Player, buffer) -> ()): RBXScriptConnection
	return reSyncDNA.OnServerEvent:Connect(callback)
end

-- ── SpawnCreature ────────────────────────────
-- Direction: Server → Client
-- Payload:   Model (the assembled creature model reference)
-- Usage:     Server fires after successful assembly so the client can attach UI/camera.

Remotes.SpawnCreature = {}

-- Called by server to notify a specific client that their creature has spawned.
-- @param player Player  Target client.
-- @param model  Model   The assembled creature Model in Workspace.
function Remotes.SpawnCreature.FireClient(player: Player, model: Model): ()
	reSpawnCreature:FireClient(player, model)
end

-- Called by client to register a handler for spawn notifications.
-- @param callback (model: Model) -> ()
-- @return RBXScriptConnection
function Remotes.SpawnCreature.OnClientEvent(callback: (Model) -> ()): RBXScriptConnection
	return reSpawnCreature.OnClientEvent:Connect(callback)
end

-- ── ApplyDamage ──────────────────────────────
-- Direction: Server → Client
-- Payload:   number (damage amount for this hit)
-- Usage:     Server fires after each combat hit so the client can update health UI.

Remotes.ApplyDamage = {}

-- Called by server to push damage data to a specific client.
-- @param player Player  Target client.
-- @param amount number  Damage dealt in this physics interaction.
function Remotes.ApplyDamage.FireClient(player: Player, amount: number): ()
	reApplyDamage:FireClient(player, amount)
end

-- Called by client to register a handler for incoming damage notifications.
-- @param callback (amount: number) -> ()
-- @return RBXScriptConnection
function Remotes.ApplyDamage.OnClientEvent(callback: (number) -> ()): RBXScriptConnection
	return reApplyDamage.OnClientEvent:Connect(callback)
end

-- ── UpdateInventory ──────────────────────────
-- Direction: Server → Client
-- Payload:   table {Armor: number, Wing: number, Limb: number}
-- Usage:     Fired after any inventory change (pickup or creature spawn).

Remotes.UpdateInventory = {}

-- Called by server to push the player's current inventory to their client.
-- @param player Player
-- @param inventory {Armor: number, Wing: number, Limb: number}
function Remotes.UpdateInventory.FireClient(player: Player, inventory: {[string]: number}): ()
	reUpdateInventory:FireClient(player, inventory)
end

-- Called by client to register an inventory update handler.
-- @param callback (inventory: {[string]: number}) -> ()
function Remotes.UpdateInventory.OnClientEvent(callback: ({[string]: number}) -> ()): RBXScriptConnection
	return reUpdateInventory.OnClientEvent:Connect(callback)
end

-- ── DNAPickedUp ───────────────────────────────
-- Direction: Server → Client
-- Payload:   string (PartType: "Armor" | "Wing" | "Limb")
-- Usage:     Triggers pickup flash notification in the client UI.

Remotes.DNAPickedUp = {}

-- Called by server to notify a client they just collected a DNA fragment.
-- @param player   Player
-- @param partType string  The type of DNA collected.
function Remotes.DNAPickedUp.FireClient(player: Player, partType: string): ()
	reDNAPickedUp:FireClient(player, partType)
end

-- Called by client to register a pickup notification handler.
-- @param callback (partType: string) -> ()
function Remotes.DNAPickedUp.OnClientEvent(callback: (string) -> ()): RBXScriptConnection
	return reDNAPickedUp.OnClientEvent:Connect(callback)
end

-- ── EnterArena ────────────────────────────────
-- Direction: Server → Client
-- Payload:   (none)
-- Usage:     Tells the client they have been teleported into the arena.

local reEnterArena   = getOrCreate("EnterArena")
local reGameResult   = getOrCreate("GameResult")
local reLeaveArena   = getOrCreate("LeaveArena")

Remotes.EnterArena = {}

function Remotes.EnterArena.FireClient(player: Player): ()
	reEnterArena:FireClient(player)
end

function Remotes.EnterArena.OnClientEvent(callback: () -> ()): RBXScriptConnection
	return reEnterArena.OnClientEvent:Connect(callback)
end

-- ── GameResult ────────────────────────────────
-- Direction: Server → Client
-- Payload:   {won: boolean, dnaReward: {Armor: number, Wing: number, Limb: number}}
-- Usage:     Fired when the arena fight concludes (victory or defeat).

Remotes.GameResult = {}

function Remotes.GameResult.FireClient(player: Player, result: {won: boolean, dnaReward: {[string]: number}}): ()
	reGameResult:FireClient(player, result)
end

function Remotes.GameResult.OnClientEvent(callback: ({won: boolean, dnaReward: {[string]: number}}) -> ()): RBXScriptConnection
	return reGameResult.OnClientEvent:Connect(callback)
end

-- ── LeaveArena ────────────────────────────────
-- Direction: Client → Server
-- Payload:   (none)
-- Usage:     Client fires after pressing "Weiter" on the result screen.

Remotes.LeaveArena = {}

function Remotes.LeaveArena.FireServer(): ()
	reLeaveArena:FireServer()
end

function Remotes.LeaveArena.OnServerEvent(callback: (Player) -> ()): RBXScriptConnection
	return reLeaveArena.OnServerEvent:Connect(callback)
end

return Remotes
