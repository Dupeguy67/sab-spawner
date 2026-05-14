local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Animals = require(ReplicatedStorage:WaitForChild("Datas"):WaitForChild("Animals"))
local Datas = ReplicatedStorage:WaitForChild("Datas")
local Rarities = require(Datas:WaitForChild("Rarities"))
local TraitsData = require(Datas:WaitForChild("Traits"))
local MutationsData = require(Datas:WaitForChild("Mutations"))
local GameData = require(Datas:WaitForChild("Game"))
local SharedAnimals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animals"))
local NumberUtils = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("NumberUtils"))
local Gradients = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Gradients"))

local traitMap = {}
for id, data in pairs(TraitsData) do
	traitMap[id] = {name = data.DisplayName or id, mult = data.Multiplier or 0, icon = data.Icon}
end

local mutationMap = {}
for name, data in pairs(MutationsData) do
	local displayName = data.DisplayText or name
	mutationMap[name] = {
		name = displayName,
		mult = data.Multiplier or 0,
		color = data.MainColor or Color3.new(1,1,1),
		gradient = data.GradientPreset,
		rich = data.UseRichText,
		richDisplay = data.DisplayWithRichText
	}
end

local traitList = {}
for _, data in pairs(traitMap) do table.insert(traitList, data.name) end
table.sort(traitList)

local mutationList = {"None"}
for name in pairs(mutationMap) do table.insert(mutationList, name) end
table.sort(mutationList)

local excludedAnimals = {
	["Secret Lucky Block"]=true,["Chimpanzini Spiderini"]=true,
	["Mythic Lucky Block"]=true,["Brainrot God Lucky Block"]=true,
}

local animalList = {}
for name in pairs(Animals) do
	if not excludedAnimals[name] then table.insert(animalList, name) end
end

local animalsByRarity = {}
for _, name in ipairs(animalList) do
	local rarity = Animals[name].Rarity or "Unknown"
	animalsByRarity[rarity] = animalsByRarity[rarity] or {}
	table.insert(animalsByRarity[rarity], name)
end

local rarityOrder = {
	"Easter","St Patrick's","Valentines","Festive","Spooky","Taco",
	"Admin","OG","Secret","Brainrot God","Mythic","Legendary","Epic","Rare","Common"
}
local sortedAnimalList = {}
for _, rarity in ipairs(rarityOrder) do
	if animalsByRarity[rarity] then
		for _, name in ipairs(animalsByRarity[rarity]) do
			table.insert(sortedAnimalList, name)
		end
	end
end
animalList = sortedAnimalList

-- [Rest of your original functions remain completely unchanged]
-- spawnAnimal, startGrab, releaseGrab, createGrabUI, etc. are untouched

local function formatNumber(num)
	local suffixes = {"","K","M","B","T","Q","Qi","Sx","Sp","Oc","No","Dc"}
	local tier = 1
	while math.abs(num) >= 1000 and tier < #suffixes do
		num = num / 1000
		tier = tier + 1
	end
	if tier == 1 then return tostring(math.floor(num)) end
	return string.format("%.2f%s", num, suffixes[tier])
end

local function parseCurrency(str)
	str = str:gsub("<[^>]+>",""):gsub("%$",""):gsub(",",""):gsub("[^%d%.%a]","")
	local numStr, suffix = str:match("^(%d*%.?%d+)(%a*)")
	local num = tonumber(numStr) or 0
	suffix = suffix:upper()
	local m = {K=1e3,M=1e6,B=1e9,T=1e12,Q=1e15,QI=1e18,SX=1e21,SP=1e24,OC=1e27,NO=1e30,DC=1e33}
	return num * (m[suffix] or 1)
end

local function getTraitIdByName(traitName)
	for id, data in pairs(traitMap) do
		if data.name == traitName then return id end
	end
	return nil
end

-- ... (All your helper functions like showCashout, hideInventory, etc. are unchanged)

-- ==================== MODIFIED UI ====================

if CoreGui:FindFirstChild("DupeCreatorDevGUI") then
	CoreGui.DupeCreatorDevGUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "DupeCreatorDevGUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = CoreGui

local COLORS = {
	bg         = Color3.fromRGB(10, 15, 35),
	header     = Color3.fromRGB(15, 25, 55),
	card       = Color3.fromRGB(15, 20, 45),
	cardHover  = Color3.fromRGB(25, 35, 70),
	text       = Color3.fromRGB(200, 230, 255),
	textDim    = Color3.fromRGB(140, 180, 255),
	scrollbar  = Color3.fromRGB(40, 80, 160),
	toggleOn   = Color3.fromRGB(80, 160, 255),
	toggleOff  = Color3.fromRGB(30, 45, 80),
	button     = Color3.fromRGB(30, 70, 160),
	danger     = Color3.fromRGB(180, 40, 40),
	dangerText = Color3.fromRGB(255, 255, 255),
	dropdownBg = Color3.fromRGB(12, 18, 40),
	border     = Color3.fromRGB(60, 100, 190),
}

-- Intro
local IntroOverlay = Instance.new("Frame")
IntroOverlay.Size = UDim2.new(1,0,1,0)
IntroOverlay.BackgroundColor3 = Color3.fromRGB(8, 12, 30)
IntroOverlay.BackgroundTransparency = 0.1
IntroOverlay.ZIndex = 500
IntroOverlay.Parent = ScreenGui

local IntroTitle = Instance.new("TextLabel", IntroOverlay)
IntroTitle.Size = UDim2.new(1,0,0,50)
IntroTitle.Position = UDim2.new(0,0,0.5,-40)
IntroTitle.BackgroundTransparency = 1
IntroTitle.Text = "YT:DupeCreatorDev"
IntroTitle.TextColor3 = Color3.fromRGB(100, 180, 255)
IntroTitle.Font = Enum.Font.GothamBold
IntroTitle.TextSize = 26

local IntroSub = Instance.new("TextLabel", IntroOverlay)
IntroSub.Size = UDim2.new(1,0,0,30)
IntroSub.Position = UDim2.new(0,0,0.5,10)
IntroSub.BackgroundTransparency = 1
IntroSub.Text = "Premium Spawner"
IntroSub.TextColor3 = Color3.fromRGB(140, 200, 255)
IntroSub.Font = Enum.Font.GothamMedium
IntroSub.TextSize = 16

task.delay(2.5, function()
	TweenService:Create(IntroOverlay, TweenInfo.new(0.8), {BackgroundTransparency = 1}):Play()
	TweenService:Create(IntroTitle, TweenInfo.new(0.8), {TextTransparency = 1}):Play()
	TweenService:Create(IntroSub, TweenInfo.new(0.8), {TextTransparency = 1}):Play()
	task.delay(1, function() IntroOverlay:Destroy() end)
end)

-- [Rest of your dropdown, button, and GUI creation code remains the same except for colors and titles]

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "Main"
MainFrame.Size             = UDim2.new(0,260,0,380)
MainFrame.Position         = UDim2.new(0.5,-130,0.5,-190)
MainFrame.BackgroundColor3 = COLORS.bg
MainFrame.BorderSizePixel  = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,10)
local ms = Instance.new("UIStroke", MainFrame); ms.Color = COLORS.border; ms.Thickness = 1.2

local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1,0,0,36)
Header.BackgroundColor3 = COLORS.header
Header.BorderSizePixel  = 0; Header.ZIndex = 5; Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0,10)

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1,-70,1,0); Title.Position = UDim2.new(0,14,0,0)
Title.BackgroundTransparency = 1; Title.Text = "YT:DupeCreatorDev"
Title.TextColor3 = Color3.fromRGB(180, 220, 255); Title.Font = Enum.Font.GothamBold
Title.TextSize = 13; Title.TextXAlignment = Enum.TextXAlignment.Left; Title.ZIndex = 6

-- Close & Minimize buttons (unchanged logic)
local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0,24,0,24); CloseBtn.Position = UDim2.new(1,-32,0.5,-12)
CloseBtn.BackgroundColor3 = COLORS.danger; CloseBtn.Text = "X"
CloseBtn.TextColor3 = COLORS.dangerText; CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11; CloseBtn.BorderSizePixel = 0; CloseBtn.ZIndex = 6
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0,6)

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = UDim2.new(0,24,0,24); MinBtn.Position = UDim2.new(1,-60,0.5,-12)
MinBtn.BackgroundColor3 = COLORS.card; MinBtn.Text = "-"
MinBtn.TextColor3 = COLORS.text; MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14; MinBtn.BorderSizePixel = 0; MinBtn.ZIndex = 6
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0,6)

-- ContentFrame and all UI elements use the new blue COLORS table
-- (All dropdowns, buttons, sections now use the blue theme automatically)

-- Spawn button color tweak
createButton("Spawn Animal", 201, Color3.fromRGB(40, 100, 200), Color3.fromRGB(220, 235, 255), function()
	if not selectedAnimal or selectedAnimal == "None" then return end
	local mu = (selectedMutation == "None") and nil or selectedMutation
	
	local ok, res = spawnAnimal(selectedAnimal, selectedTraitsMulti, mu)
	if ok then 
		showCashout("Spawned: " .. selectedAnimal, true)
	else 
		showCashout("Error: " .. tostring(res), false) 
	end
end)

-- The rest of your original code (dragging, minimize, keybind, heartbeat, etc.) remains 100% unchanged
