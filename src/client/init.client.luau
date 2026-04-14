--!strict
-- init.client.luau
-- Bio-Fusion Full UI: Builder Panel + Battle HUD + DNA Inventory

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CreatureTypes = require(Shared:WaitForChild("CreatureTypes"))
local Remotes       = require(Shared:WaitForChild("Remotes"))

type DNAPart = CreatureTypes.DNAPart

-- ─────────────────────────────────────────────
-- Part Presets
-- ─────────────────────────────────────────────

type Preset = { label: string, partType: string, stats: CreatureTypes.PartStats }

local PRESETS: {[string]: {Preset}} = {
	Armor = {
		{ label = "Schwer",  partType = "Armor", stats = { Weight = 8,   Aerodynamics = 0,   ArmorThickness = 3.0, Health = 60 } },
		{ label = "Leicht",  partType = "Armor", stats = { Weight = 3,   Aerodynamics = 0,   ArmorThickness = 1.5, Health = 30 } },
	},
	Wing = {
		{ label = "Groß",    partType = "Wing",  stats = { Weight = 1,   Aerodynamics = 0.9, ArmorThickness = 0.5, Health = 15 } },
		{ label = "Klein",   partType = "Wing",  stats = { Weight = 0.5, Aerodynamics = 0.5, ArmorThickness = 0.3, Health = 10 } },
	},
	Limb = {
		{ label = "Stark",   partType = "Limb",  stats = { Weight = 3,   Aerodynamics = 0,   ArmorThickness = 1.0, Health = 40 } },
		{ label = "Schnell", partType = "Limb",  stats = { Weight = 1,   Aerodynamics = 0,   ArmorThickness = 0.5, Health = 20 } },
	},
}

local TYPE_ORDER: {string} = { "Armor", "Wing", "Limb" }

local TYPE_COLOR: {[string]: Color3} = {
	Armor = Color3.fromRGB(200, 100,  50),
	Wing  = Color3.fromRGB( 80, 160, 230),
	Limb  = Color3.fromRGB( 80, 200, 120),
}

local TYPE_ICON: {[string]: string} = {
	Armor = "🛡️", Wing = "🪶", Limb = "💪",
}

-- ─────────────────────────────────────────────
-- Inventory state (updated via Remote)
-- ─────────────────────────────────────────────

local inventory: {[string]: number} = { Armor = 0, Wing = 0, Limb = 0 }

-- ─────────────────────────────────────────────
-- Auto-position helpers
-- ─────────────────────────────────────────────

local partCounters: {[string]: number} = { Armor = 0, Wing = 0, Limb = 0 }

local function nextPosition(partType: string): {number}
	local n = partCounters[partType] or 0
	partCounters[partType] = n + 1
	if partType == "Armor" then
		return {0, -1.5 - n * 1.5, 0}
	elseif partType == "Wing" then
		local side = if n % 2 == 0 then -1 else 1
		return {side * (2 + math.floor(n / 2) * 1.5), 0.5, 0}
	else
		local side = if n % 2 == 0 then 1 else -1
		return {side * (1.5 + math.floor(n / 2) * 1.5), -1, 0}
	end
end

local function resetCounters()
	partCounters = { Armor = 0, Wing = 0, Limb = 0 }
end

-- ─────────────────────────────────────────────
-- UI Helpers
-- ─────────────────────────────────────────────

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius); c.Parent = parent
end
local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px); p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px); p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end
local function mkBtn(parent: Instance, text: string, bg: Color3, w: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, h); b.BackgroundColor3 = bg; b.BorderSizePixel = 0
	b.Text = text; b.TextColor3 = Color3.fromRGB(255,255,255)
	b.TextSize = h - 8; b.Font = Enum.Font.GothamBold; b.AutoButtonColor = true
	b.Parent = parent; corner(b, 8); return b
end

-- ─────────────────────────────────────────────
-- Root ScreenGui
-- ─────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "BioFusionUI"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player.PlayerGui

-- ─────────────────────────────────────────────
-- SCREEN 1: Builder Panel
-- ─────────────────────────────────────────────

local builderFrame = Instance.new("Frame")
builderFrame.Size = UDim2.new(0, 440, 0, 580)
builderFrame.Position = UDim2.new(0.5, -220, 0.5, -290)
builderFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
builderFrame.BorderSizePixel = 0; builderFrame.Parent = gui
corner(builderFrame, 14)
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(60,80,120)
stroke.Thickness = 1.5; stroke.Parent = builderFrame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 48)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
titleBar.BorderSizePixel = 0; titleBar.Parent = builderFrame; corner(titleBar, 14)
local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1,0,0.5,0); titleFix.Position = UDim2.new(0,0,0.5,0)
titleFix.BackgroundColor3 = Color3.fromRGB(30,40,70); titleFix.BorderSizePixel=0; titleFix.Parent=titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1,-60,1,0); titleLbl.Position = UDim2.new(0,16,0,0)
titleLbl.BackgroundTransparency=1; titleLbl.Text="Bio-Fusion Builder"
titleLbl.TextColor3=Color3.fromRGB(255,255,255); titleLbl.TextSize=20
titleLbl.Font=Enum.Font.GothamBold; titleLbl.TextXAlignment=Enum.TextXAlignment.Left
titleLbl.Parent=titleBar

-- Minimize button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size=UDim2.new(0,32,0,32); minimizeBtn.Position=UDim2.new(1,-42,0.5,-16)
minimizeBtn.BackgroundColor3=Color3.fromRGB(60,70,100); minimizeBtn.BorderSizePixel=0
minimizeBtn.Text="—"; minimizeBtn.TextColor3=Color3.fromRGB(200,210,230)
minimizeBtn.TextSize=16; minimizeBtn.Font=Enum.Font.GothamBold; minimizeBtn.Parent=titleBar
corner(minimizeBtn, 8)

-- Floating reopen button
local reopenBtn = Instance.new("TextButton")
reopenBtn.Size=UDim2.new(0,44,0,44); reopenBtn.Position=UDim2.new(0,12,0.5,-22)
reopenBtn.BackgroundColor3=Color3.fromRGB(30,40,70); reopenBtn.BorderSizePixel=0
reopenBtn.Text="🧬"; reopenBtn.TextSize=22; reopenBtn.Font=Enum.Font.GothamBold
reopenBtn.Visible=false; reopenBtn.Parent=gui; corner(reopenBtn,10)
local rs=Instance.new("UIStroke"); rs.Color=Color3.fromRGB(60,80,120); rs.Thickness=1.5; rs.Parent=reopenBtn

minimizeBtn.MouseButton1Click:Connect(function() builderFrame.Visible=false; reopenBtn.Visible=true end)
reopenBtn.MouseButton1Click:Connect(function() builderFrame.Visible=true; reopenBtn.Visible=false end)

-- Content area
local content = Instance.new("Frame")
content.Size=UDim2.new(1,-24,1,-108); content.Position=UDim2.new(0,12,0,56)
content.BackgroundTransparency=1; content.Parent=builderFrame

-- ─────────────────────────────────────────────
-- Left column: Part Catalog
-- ─────────────────────────────────────────────

local leftCol = Instance.new("Frame")
leftCol.Size=UDim2.new(0.48,-4,1,0); leftCol.BackgroundTransparency=1; leftCol.Parent=content
local leftList = Instance.new("UIListLayout"); leftList.SortOrder=Enum.SortOrder.LayoutOrder
leftList.Padding=UDim.new(0,6); leftList.Parent=leftCol

local catHdr = Instance.new("TextLabel")
catHdr.Size=UDim2.new(1,0,0,16); catHdr.BackgroundTransparency=1
catHdr.Text="PART CATALOG"; catHdr.TextColor3=Color3.fromRGB(140,160,200)
catHdr.TextSize=12; catHdr.Font=Enum.Font.GothamBold
catHdr.TextXAlignment=Enum.TextXAlignment.Left; catHdr.LayoutOrder=0; catHdr.Parent=leftCol

local selectedPreset: {[string]: number} = { Armor=1, Wing=1, Limb=1 }

-- Per-type refs for inventory refresh
local addBtnRefs: {[string]: TextButton} = {}
local countLblRefs: {[string]: TextLabel} = {}

for _, typeName in TYPE_ORDER do
	local card = Instance.new("Frame")
	card.Size=UDim2.new(1,0,0,88); card.BackgroundColor3=Color3.fromRGB(26,30,44)
	card.BorderSizePixel=0; card.LayoutOrder=1; card.Parent=leftCol; corner(card,8); padding(card,7)
	local ts=Instance.new("UIStroke"); ts.Color=TYPE_COLOR[typeName]; ts.Thickness=1; ts.Parent=card

	-- Header row: type name + DNA count badge
	local headerRow = Instance.new("Frame")
	headerRow.Size=UDim2.new(1,0,0,18); headerRow.BackgroundTransparency=1; headerRow.Parent=card

	local typeLbl = Instance.new("TextLabel")
	typeLbl.Size=UDim2.new(0.6,0,1,0); typeLbl.BackgroundTransparency=1
	typeLbl.Text=typeName:upper(); typeLbl.TextColor3=TYPE_COLOR[typeName]
	typeLbl.TextSize=12; typeLbl.Font=Enum.Font.GothamBold
	typeLbl.TextXAlignment=Enum.TextXAlignment.Left; typeLbl.Parent=headerRow

	local countBadge = Instance.new("Frame")
	countBadge.Size=UDim2.new(0,60,1,0); countBadge.Position=UDim2.new(1,-60,0,0)
	countBadge.BackgroundColor3=Color3.fromRGB(30,36,52); countBadge.BorderSizePixel=0
	countBadge.Parent=headerRow; corner(countBadge,6)

	local countLbl = Instance.new("TextLabel")
	countLbl.Size=UDim2.new(1,0,1,0); countLbl.BackgroundTransparency=1
	countLbl.Text="🧬 0"; countLbl.TextColor3=Color3.fromRGB(180,180,180)
	countLbl.TextSize=11; countLbl.Font=Enum.Font.GothamBold; countLbl.Parent=countBadge
	countLblRefs[typeName] = countLbl

	-- Preset buttons
	local presetRow = Instance.new("Frame")
	presetRow.Size=UDim2.new(1,0,0,26); presetRow.Position=UDim2.new(0,0,0,22)
	presetRow.BackgroundTransparency=1; presetRow.Parent=card
	local rl=Instance.new("UIListLayout"); rl.FillDirection=Enum.FillDirection.Horizontal
	rl.Padding=UDim.new(0,4); rl.Parent=presetRow

	local presets = PRESETS[typeName]
	local presetBtns: {TextButton} = {}

	local function refreshPresetBtns()
		for i, pb in presetBtns do
			pb.BackgroundColor3 = if selectedPreset[typeName]==i then TYPE_COLOR[typeName] else Color3.fromRGB(40,46,64)
		end
	end

	for i, preset in presets do
		local pb=Instance.new("TextButton")
		pb.Size=UDim2.new(0,78,1,0); pb.BackgroundColor3=Color3.fromRGB(40,46,64)
		pb.BorderSizePixel=0; pb.Text=preset.label
		pb.TextColor3=Color3.fromRGB(220,220,220); pb.TextSize=11
		pb.Font=Enum.Font.Gotham; pb.Parent=presetRow; corner(pb,6)
		table.insert(presetBtns,pb)
		local idx=i; pb.MouseButton1Click:Connect(function() selectedPreset[typeName]=idx; refreshPresetBtns() end)
	end

	-- Stats label
	local statsLbl=Instance.new("TextLabel")
	statsLbl.Size=UDim2.new(1,0,0,16); statsLbl.Position=UDim2.new(0,0,0,52)
	statsLbl.BackgroundTransparency=1; statsLbl.TextColor3=Color3.fromRGB(150,160,180)
	statsLbl.TextSize=10; statsLbl.Font=Enum.Font.Gotham
	statsLbl.TextXAlignment=Enum.TextXAlignment.Left; statsLbl.TextWrapped=true; statsLbl.Parent=card

	local function updateStats()
		local p=PRESETS[typeName][selectedPreset[typeName]]; local s=p.stats
		statsLbl.Text=string.format("HP:%d W:%.1f Armor:%.1f Aero:%.1f",s.Health,s.Weight,s.ArmorThickness,s.Aerodynamics)
	end
	for _,pb in presetBtns do pb.MouseButton1Click:Connect(updateStats) end
	refreshPresetBtns(); updateStats()

	-- Add button
	local cap = typeName
	local addBtn = mkBtn(leftCol, "+ " .. typeName .. " hinzufügen", Color3.fromRGB(60,70,90), 180, 26)
	addBtn.Size=UDim2.new(1,0,0,26); addBtn.LayoutOrder=1
	addBtn:SetAttribute("TypeName", typeName)
	addBtnRefs[typeName] = addBtn

	card.LayoutOrder=1
end

-- ─────────────────────────────────────────────
-- Right column: DNA Part List
-- ─────────────────────────────────────────────

local rightCol = Instance.new("Frame")
rightCol.Size=UDim2.new(0.52,-4,1,0); rightCol.Position=UDim2.new(0.48,4,0,0)
rightCol.BackgroundTransparency=1; rightCol.Parent=content
local rightList=Instance.new("UIListLayout"); rightList.SortOrder=Enum.SortOrder.LayoutOrder
rightList.Padding=UDim.new(0,6); rightList.Parent=rightCol

local rHdr=Instance.new("TextLabel")
rHdr.Size=UDim2.new(1,0,0,16); rHdr.BackgroundTransparency=1; rHdr.Text="MEIN CREATURE"
rHdr.TextColor3=Color3.fromRGB(140,160,200); rHdr.TextSize=12; rHdr.Font=Enum.Font.GothamBold
rHdr.TextXAlignment=Enum.TextXAlignment.Left; rHdr.LayoutOrder=0; rHdr.Parent=rightCol

local partScroll=Instance.new("ScrollingFrame")
partScroll.Size=UDim2.new(1,0,1,-72); partScroll.BackgroundColor3=Color3.fromRGB(22,26,38)
partScroll.BorderSizePixel=0; partScroll.ScrollBarThickness=4
partScroll.ScrollBarImageColor3=Color3.fromRGB(80,100,160)
partScroll.CanvasSize=UDim2.new(0,0,0,0); partScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
partScroll.LayoutOrder=1; partScroll.Parent=rightCol; corner(partScroll,8)
local sl=Instance.new("UIListLayout"); sl.SortOrder=Enum.SortOrder.LayoutOrder
sl.Padding=UDim.new(0,4); sl.Parent=partScroll; padding(partScroll,6)

local clearBtn=mkBtn(rightCol,"Alles löschen",Color3.fromRGB(160,50,50),180,26)
clearBtn.Size=UDim2.new(1,0,0,26); clearBtn.LayoutOrder=2

-- Spawn button
local spawnBtn=mkBtn(builderFrame,"Creature spawnen",Color3.fromRGB(50,180,100),200,44)
spawnBtn.Size=UDim2.new(1,-24,0,44); spawnBtn.Position=UDim2.new(0,12,1,-52); spawnBtn.TextSize=18

-- ─────────────────────────────────────────────
-- DNA Part list state
-- ─────────────────────────────────────────────

local dnaPartsList: {DNAPart} = {}

local function refreshPartList()
	for _, child in partScroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i, part in dnaPartsList do
		local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,32)
		row.BackgroundColor3=Color3.fromRGB(28,34,50); row.BorderSizePixel=0
		row.LayoutOrder=i; row.Parent=partScroll; corner(row,6)

		local dot=Instance.new("Frame"); dot.Size=UDim2.new(0,8,0,8)
		dot.Position=UDim2.new(0,8,0.5,-4)
		dot.BackgroundColor3=TYPE_COLOR[part.PartType] or Color3.fromRGB(200,200,200)
		dot.BorderSizePixel=0; dot.Parent=row; corner(dot,4)

		local rl=Instance.new("TextLabel"); rl.Size=UDim2.new(1,-50,1,0)
		rl.Position=UDim2.new(0,22,0,0); rl.BackgroundTransparency=1
		rl.Text=part.PartID; rl.TextColor3=Color3.fromRGB(220,225,235)
		rl.TextSize=11; rl.Font=Enum.Font.Gotham
		rl.TextXAlignment=Enum.TextXAlignment.Left
		rl.TextTruncate=Enum.TextTruncate.AtEnd; rl.Parent=row

		local rb=Instance.new("TextButton"); rb.Size=UDim2.new(0,26,0,20)
		rb.Position=UDim2.new(1,-32,0.5,-10); rb.BackgroundColor3=Color3.fromRGB(160,50,50)
		rb.BorderSizePixel=0; rb.Text="✕"; rb.TextColor3=Color3.fromRGB(255,255,255)
		rb.TextSize=12; rb.Font=Enum.Font.GothamBold; rb.Parent=row; corner(rb,5)
		local idx=i; rb.MouseButton1Click:Connect(function() table.remove(dnaPartsList,idx); refreshPartList() end)
	end

	if #dnaPartsList == 0 then
		spawnBtn.BackgroundColor3=Color3.fromRGB(50,70,50); spawnBtn.Text="Parts hinzufügen"
	else
		spawnBtn.BackgroundColor3=Color3.fromRGB(50,180,100)
		spawnBtn.Text=string.format("Creature spawnen (%d Parts)",#dnaPartsList)
	end
end

-- ─────────────────────────────────────────────
-- Inventory UI refresh
-- ─────────────────────────────────────────────

local function refreshInventoryUI()
	for _, typeName in TYPE_ORDER do
		local count = inventory[typeName] or 0
		local lbl = countLblRefs[typeName]
		local btn = addBtnRefs[typeName]
		if lbl then
			lbl.Text = "🧬 " .. tostring(count)
			lbl.TextColor3 = if count > 0 then TYPE_COLOR[typeName] else Color3.fromRGB(120,120,120)
		end
		if btn then
			if count > 0 then
				btn.BackgroundColor3 = TYPE_COLOR[typeName]
				btn.TextColor3 = Color3.fromRGB(255,255,255)
				btn.Active = true
			else
				btn.BackgroundColor3 = Color3.fromRGB(40,44,58)
				btn.TextColor3 = Color3.fromRGB(100,100,110)
				btn.Active = false
			end
		end
	end
end

-- Wire Add buttons
for _, child in leftCol:GetChildren() do
	if child:IsA("TextButton") then
		local typeName = child:GetAttribute("TypeName") :: string
		if typeName then
			child.MouseButton1Click:Connect(function()
				if (inventory[typeName] or 0) <= 0 then return end
				local presetIdx = selectedPreset[typeName]
				local preset = PRESETS[typeName][presetIdx]
				local pos = nextPosition(typeName)
				local newPart: DNAPart = {
					PartID         = typeName .. "_" .. tostring(#dnaPartsList + 1),
					PartType       = preset.partType :: CreatureTypes.PartType,
					PositionOffset = pos,
					Rotation       = {0, 0, 0},
					Stats          = preset.stats,
				}
				table.insert(dnaPartsList, newPart)
				refreshPartList()
			end)
		end
	end
end

clearBtn.MouseButton1Click:Connect(function() dnaPartsList={}; resetCounters(); refreshPartList() end)

refreshPartList()
refreshInventoryUI()

-- ─────────────────────────────────────────────
-- SCREEN 2: Battle HUD
-- ─────────────────────────────────────────────

local battleHUD=Instance.new("Frame"); battleHUD.Size=UDim2.new(1,0,1,0)
battleHUD.BackgroundTransparency=1; battleHUD.Visible=false; battleHUD.Parent=gui

local hpBg=Instance.new("Frame"); hpBg.Size=UDim2.new(0,320,0,30)
hpBg.Position=UDim2.new(0.5,-160,1,-52); hpBg.BackgroundColor3=Color3.fromRGB(20,20,20)
hpBg.BorderSizePixel=0; hpBg.Parent=battleHUD; corner(hpBg,8)

local hpFill=Instance.new("Frame"); hpFill.Size=UDim2.new(1,0,1,0)
hpFill.BackgroundColor3=Color3.fromRGB(80,220,80); hpFill.BorderSizePixel=0
hpFill.Parent=hpBg; corner(hpFill,8)

local hpText=Instance.new("TextLabel"); hpText.Size=UDim2.new(1,0,1,0)
hpText.BackgroundTransparency=1; hpText.Text="HP: 100 / 100"
hpText.TextColor3=Color3.fromRGB(255,255,255); hpText.TextSize=14
hpText.Font=Enum.Font.GothamBold; hpText.TextStrokeTransparency=0.4; hpText.Parent=hpBg

local editBtn=mkBtn(battleHUD,"Bearbeiten",Color3.fromRGB(60,90,160),110,34)
editBtn.Position=UDim2.new(1,-122,0,12)

local dmgFlash=Instance.new("TextLabel"); dmgFlash.Size=UDim2.new(0,200,0,50)
dmgFlash.Position=UDim2.new(0.5,-100,0.4,0); dmgFlash.BackgroundTransparency=1
dmgFlash.Text=""; dmgFlash.TextColor3=Color3.fromRGB(255,80,60)
dmgFlash.TextSize=36; dmgFlash.Font=Enum.Font.GothamBold
dmgFlash.TextStrokeTransparency=0.3; dmgFlash.Parent=battleHUD

-- DNA Pickup flash (top center)
local pickupFlash=Instance.new("TextLabel"); pickupFlash.Size=UDim2.new(0,260,0,44)
pickupFlash.Position=UDim2.new(0.5,-130,0,20); pickupFlash.BackgroundTransparency=1
pickupFlash.Text=""; pickupFlash.TextSize=22; pickupFlash.Font=Enum.Font.GothamBold
pickupFlash.TextStrokeTransparency=0.2; pickupFlash.Parent=gui

-- ─────────────────────────────────────────────
-- HP bar update
-- ─────────────────────────────────────────────

local maxHP=100; local currentHP=100
local hpTween=TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)

local function updateHP(hp:number, max:number)
	local pct=math.clamp(hp/max,0,1)
	TweenService:Create(hpFill,hpTween,{
		Size=UDim2.new(pct,0,1,0),
		BackgroundColor3=Color3.fromRGB(math.floor(255*(1-pct)),math.floor(220*pct),40),
	}):Play()
	hpText.Text=string.format("HP: %d / %d",math.floor(hp),math.floor(max))
end

-- ─────────────────────────────────────────────
-- Spawn Button
-- ─────────────────────────────────────────────

spawnBtn.MouseButton1Click:Connect(function()
	if #dnaPartsList == 0 then return end
	spawnBtn.Text="Spawning..."; spawnBtn.BackgroundColor3=Color3.fromRGB(30,100,60)
	local dna: CreatureTypes.CreatureDNA = {
		OwnerID=player.UserId, Version=1, TorsoID="BasicTorso", Parts=dnaPartsList,
	}
	local ok, result=pcall(CreatureTypes.Serialize,dna)
	if not ok then
		warn("[BioFusion] Serialize error:",result)
		spawnBtn.Text="Fehler – nochmal versuchen"; spawnBtn.BackgroundColor3=Color3.fromRGB(160,50,50)
		return
	end
	Remotes.SyncDNA.FireServer(result :: buffer)
end)

-- ─────────────────────────────────────────────
-- Remote handlers
-- ─────────────────────────────────────────────

-- Inventory update
Remotes.UpdateInventory.OnClientEvent(function(inv: {[string]: number})
	inventory = { Armor = inv.Armor or 0, Wing = inv.Wing or 0, Limb = inv.Limb or 0 }
	refreshInventoryUI()
end)

-- DNA pickup notification
Remotes.DNAPickedUp.OnClientEvent(function(partType: string)
	local color = TYPE_COLOR[partType] or Color3.fromRGB(200,200,200)
	local icon  = ({Armor="🛡️", Wing="🪶", Limb="💪"})[partType] or "🧬"
	pickupFlash.Text = icon .. " +1 " .. partType .. " DNA!"
	pickupFlash.TextColor3 = color
	pickupFlash.TextTransparency = 0

	TweenService:Create(pickupFlash, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
	}):Play()
	task.spawn(function() task.wait(1.6); pickupFlash.Text="" end)
end)

-- Creature spawned → switch to battle HUD
Remotes.SpawnCreature.OnClientEvent(function(model: Model)
	maxHP     = (model:GetAttribute("MaxHealth") :: number?) or 100
	currentHP = (model:GetAttribute("Health")    :: number?) or maxHP
	updateHP(currentHP, maxHP)
	builderFrame.Visible  = false
	battleHUD.Visible     = true
	enterArenaBtn.Visible = true  -- show arena button now that we have a creature

	model:GetAttributeChangedSignal("Health"):Connect(function()
		currentHP = (model:GetAttribute("Health") :: number?) or 0
		updateHP(currentHP, maxHP)
	end)
end)

-- Damage flash
Remotes.ApplyDamage.OnClientEvent(function(amount: number)
	dmgFlash.Text=string.format("-%.1f",amount); dmgFlash.TextTransparency=0
	TweenService:Create(dmgFlash,TweenInfo.new(1.2,Enum.EasingStyle.Quad),{TextTransparency=1}):Play()
	task.spawn(function() task.wait(1.3); dmgFlash.Text="" end)
end)

-- ── Enter Arena button (in Battle HUD) ──────────────────────────────────────
local enterArenaBtn = mkBtn(battleHUD, "⚔️ Arena betreten", Color3.fromRGB(130, 30, 160), 160, 34)
enterArenaBtn.Position = UDim2.new(0.5, -80, 1, -96) -- above HP bar
enterArenaBtn.Visible  = false -- shown after creature spawns

enterArenaBtn.MouseButton1Click:Connect(function()
	-- Walk the player to the enter pad (magenta pad at 60,1,0)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = CFrame.new(Vector3.new(60, 3, 0))
	end
end)

-- ── Arena Badge (top-left, shown while InArena) ──────────────────────────────
local arenaBadge = Instance.new("Frame")
arenaBadge.Size              = UDim2.new(0, 140, 0, 38)
arenaBadge.Position          = UDim2.new(0, 12, 0, 12)
arenaBadge.BackgroundColor3  = Color3.fromRGB(80, 0, 120)
arenaBadge.BorderSizePixel   = 0
arenaBadge.Visible           = false
arenaBadge.Parent            = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = arenaBadge
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(180, 80, 255); s.Thickness = 1.5; s.Parent = arenaBadge
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
	lbl.Text = "⚔️ Arena"; lbl.TextColor3 = Color3.fromRGB(220,180,255)
	lbl.TextSize = 18; lbl.Font = Enum.Font.GothamBold; lbl.Parent = arenaBadge
end

-- ── Result Screen (full-screen overlay) ─────────────────────────────────────
local resultScreen = Instance.new("Frame")
resultScreen.Size             = UDim2.new(1, 0, 1, 0)
resultScreen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
resultScreen.BackgroundTransparency = 0.35
resultScreen.BorderSizePixel  = 0
resultScreen.Visible          = false
resultScreen.ZIndex           = 10
resultScreen.Parent           = gui

local resultCard = Instance.new("Frame")
resultCard.Size             = UDim2.new(0, 380, 0, 260)
resultCard.Position         = UDim2.new(0.5, -190, 0.5, -130)
resultCard.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
resultCard.BorderSizePixel  = 0
resultCard.ZIndex           = 11
resultCard.Parent           = resultScreen
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 18); c.Parent = resultCard
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(80,60,140); s.Thickness = 2; s.Parent = resultCard
end

local resultTitle = Instance.new("TextLabel")
resultTitle.Size              = UDim2.new(1, -24, 0, 70)
resultTitle.Position          = UDim2.new(0, 12, 0, 20)
resultTitle.BackgroundTransparency = 1
resultTitle.Text              = ""
resultTitle.TextSize          = 46
resultTitle.Font              = Enum.Font.GothamBold
resultTitle.TextStrokeTransparency = 0.3
resultTitle.ZIndex            = 12
resultTitle.Parent            = resultCard

local rewardLbl = Instance.new("TextLabel")
rewardLbl.Size               = UDim2.new(1, -24, 0, 44)
rewardLbl.Position           = UDim2.new(0, 12, 0, 100)
rewardLbl.BackgroundTransparency = 1
rewardLbl.Text               = ""
rewardLbl.TextColor3         = Color3.fromRGB(220, 220, 220)
rewardLbl.TextSize           = 22
rewardLbl.Font               = Enum.Font.Gotham
rewardLbl.ZIndex             = 12
rewardLbl.Parent             = resultCard

local weiterBtn = mkBtn(resultCard, "Weiter →", Color3.fromRGB(60, 90, 160), 160, 42)
weiterBtn.Position = UDim2.new(0.5, -80, 1, -58)
weiterBtn.ZIndex   = 12

local function buildRewardText(reward: {[string]: number}): string
	local parts: {string} = {}
	if (reward.Armor or 0) > 0 then table.insert(parts, "🛡️ ×" .. tostring(reward.Armor)) end
	if (reward.Wing  or 0) > 0 then table.insert(parts, "🪶 ×" .. tostring(reward.Wing))  end
	if (reward.Limb  or 0) > 0 then table.insert(parts, "💪 ×" .. tostring(reward.Limb))  end
	return table.concat(parts, "   ")
end

-- ─────────────────────────────────────────────
-- Remote handlers (arena)
-- ─────────────────────────────────────────────

Remotes.EnterArena.OnClientEvent(function()
	arenaBadge.Visible     = true
	enterArenaBtn.Visible  = false
end)

Remotes.GameResult.OnClientEvent(function(result: {won: boolean, dnaReward: {[string]: number}})
	arenaBadge.Visible  = false
	resultScreen.Visible = true

	if result.won then
		resultTitle.Text       = "VICTORY! 🏆"
		resultTitle.TextColor3 = Color3.fromRGB(255, 210, 60)
	else
		resultTitle.Text       = "DEFEAT 💀"
		resultTitle.TextColor3 = Color3.fromRGB(220, 60, 60)
	end
	rewardLbl.Text = buildRewardText(result.dnaReward)
end)

weiterBtn.MouseButton1Click:Connect(function()
	resultScreen.Visible  = false
	arenaBadge.Visible    = false
	enterArenaBtn.Visible = true -- re-enable after round
	Remotes.LeaveArena.FireServer()
	-- Switch back to builder view
	battleHUD.Visible    = false
	builderFrame.Visible = true
	spawnBtn.Text = string.format("Creature spawnen (%d Parts)", #dnaPartsList)
	spawnBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 100)
end)

-- Edit button → back to builder
editBtn.MouseButton1Click:Connect(function()
	battleHUD.Visible=false; builderFrame.Visible=true
	spawnBtn.Text=string.format("Creature spawnen (%d Parts)",#dnaPartsList)
	spawnBtn.BackgroundColor3=Color3.fromRGB(50,180,100)
end)
