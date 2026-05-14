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

local function showCashout(text, isGreen)
	local lb = PlayerGui:FindFirstChild("LeftBottom")
	if not lb then return end
	lb = lb:FindFirstChild("LeftBottom")
	if not lb then return end
	local cf = lb:FindFirstChild("Cashout")
	if not cf or not cf:FindFirstChild("Template") then return end
	local label = cf.Template:Clone()
	label.Text = text
	label.TextColor3 = isGreen and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(231, 76, 60)
	label.Visible = true
	label.Parent = cf
	local ti = TweenInfo.new(5, Enum.EasingStyle.Linear)
	local tw = TweenService:Create(label, ti, {TextTransparency=1})
	local sk = label:FindFirstChildOfClass("UIStroke")
	if sk then TweenService:Create(sk, ti, {Transparency=1}):Play() end
	tw.Completed:Once(function() label:Destroy() end)
	tw:Play()
end

local function hideInventory()
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
end

local function showInventory()
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
end

local spawnedAnimals = {}
local DEFAULT_X =  0
local DEFAULT_Y =  0.5
local DEFAULT_Z = -0.5

local grabState = {
	xOff = DEFAULT_X,
	yOff = DEFAULT_Y,
	zOff = DEFAULT_Z,
}
local MOVE_STEP = 0.1

local currentGrabDummy = nil
local currentGrabHeartbeat = nil
local currentGrabAnim = nil
local grabAdjustGui = nil

local globalCarriedClosure = nil
local globalPrompts = {}

local function updateAllPromptsState(isCarrying)
	for i = #globalPrompts, 1, -1 do
		local p = globalPrompts[i]
		if not p.grab or not p.grab.Parent then
			table.remove(globalPrompts, i)
		else
			p.grab.ActionText = isCarrying and "Place" or "Grab"
			if p.sell then
				p.sell.Enabled = not isCarrying
			end
		end
	end
end

local function destroyGrabUI()
	if grabAdjustGui then
		grabAdjustGui:Destroy()
		grabAdjustGui = nil
	end
end

local function createGrabUI()
	destroyGrabUI()
	local sg = Instance.new("ScreenGui")
	sg.Name = "GrabAdjustUI"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = CoreGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 195, 0, 220)
	frame.Position = UDim2.new(1, -215, 0.5, -110)
	frame.BackgroundColor3 = Color3.fromRGB(15, 10, 10)
	frame.BorderSizePixel = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
	local fs = Instance.new("UIStroke", frame)
	fs.Color = Color3.fromRGB(80, 15, 15)
	fs.Thickness = 1

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0,4)
	layout.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0,10)
	pad.PaddingLeft   = UDim.new(0,10)
	pad.PaddingRight  = UDim.new(0,10)
	pad.PaddingBottom = UDim.new(0,6)
	pad.Parent = frame

	local carryRow = Instance.new("Frame", frame)
	carryRow.Size = UDim2.new(1,0,0,20)
	carryRow.BackgroundTransparency = 1

	local carryLbl = Instance.new("TextLabel", carryRow)
	carryLbl.Size = UDim2.new(1,0,1,0)
	carryLbl.BackgroundTransparency = 1
	carryLbl.Text = "CARRY MODE: ON"
	carryLbl.TextColor3 = Color3.fromRGB(100, 255, 100)
	carryLbl.Font = Enum.Font.GothamBold
	carryLbl.TextSize = 12

	local speedStatusRow = Instance.new("Frame", frame)
	speedStatusRow.Size = UDim2.new(1,0,0,16)
	speedStatusRow.BackgroundTransparency = 1

	local speedStatusLbl = Instance.new("TextLabel", speedStatusRow)
	speedStatusLbl.Size = UDim2.new(1,0,1,0)
	speedStatusLbl.BackgroundTransparency = 1
	speedStatusLbl.Text = "Player Speed: 22.5"
	speedStatusLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	speedStatusLbl.Font = Enum.Font.GothamMedium
	speedStatusLbl.TextSize = 10

	local titleLbl = Instance.new("TextLabel", frame)
	titleLbl.Size = UDim2.new(1,0,0,24)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Adjust Position"
	titleLbl.TextColor3 = Color3.fromRGB(255, 200, 200)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 11
	titleLbl.TextXAlignment = Enum.TextXAlignment.Center

	local speedRow = Instance.new("Frame")
	speedRow.Size = UDim2.new(1,0,0,26)
	speedRow.BackgroundTransparency = 1
	speedRow.Parent = frame

	local spdLbl = Instance.new("TextLabel", speedRow)
	spdLbl.Size = UDim2.new(0,60,1,0)
	spdLbl.BackgroundTransparency = 1
	spdLbl.Text = "Offset Step:"
	spdLbl.TextColor3 = Color3.fromRGB(200, 150, 150)
	spdLbl.Font = Enum.Font.GothamMedium
	spdLbl.TextSize = 10
	spdLbl.TextXAlignment = Enum.TextXAlignment.Left

	local spdBox = Instance.new("TextBox", speedRow)
	spdBox.Size = UDim2.new(0,50,0,20)
	spdBox.Position = UDim2.new(0,65,0.5,-10)
	spdBox.BackgroundColor3 = Color3.fromRGB(25, 15, 15)
	spdBox.Text = tostring(MOVE_STEP)
	spdBox.TextColor3 = Color3.fromRGB(255, 200, 200)
	spdBox.Font = Enum.Font.GothamMedium
	spdBox.TextSize = 10
	Instance.new("UICorner", spdBox).CornerRadius = UDim.new(0,4)

	spdBox.FocusLost:Connect(function()
		local val = tonumber(spdBox.Text)
		if val then MOVE_STEP = val else spdBox.Text = tostring(MOVE_STEP) end
	end)

	local function makeRow(label, axis, defaultVal)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,30)
		row.BackgroundTransparency = 1
		row.Parent = frame

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0,20,1,0)
		lbl.BackgroundTransparency = 1
		lbl.Text = label
		lbl.TextColor3 = Color3.fromRGB(200, 150, 150)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 11
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Parent = row

		local minusBtn = Instance.new("TextButton")
		minusBtn.Size = UDim2.new(0,26,0,24)
		minusBtn.Position = UDim2.new(0,24,0.5,-12)
		minusBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
		minusBtn.Text = "-"
		minusBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
		minusBtn.Font = Enum.Font.GothamBold
		minusBtn.TextSize = 12
		minusBtn.BorderSizePixel = 0
		minusBtn.Parent = row
		Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0,4)

		local valLabel = Instance.new("TextLabel")
		valLabel.Size = UDim2.new(0,54,0,24)
		valLabel.Position = UDim2.new(0,54,0.5,-12)
		valLabel.BackgroundTransparency = 1
		valLabel.Text = string.format("%.1f", grabState[axis.."Off"])
		valLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
		valLabel.Font = Enum.Font.GothamMedium
		valLabel.TextSize = 10
		valLabel.Parent = row

		local plusBtn = Instance.new("TextButton")
		plusBtn.Size = UDim2.new(0,26,0,24)
		plusBtn.Position = UDim2.new(0,112,0.5,-12)
		plusBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
		plusBtn.Text = "+"
		plusBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
		plusBtn.Font = Enum.Font.GothamBold
		plusBtn.TextSize = 12
		plusBtn.BorderSizePixel = 0
		plusBtn.Parent = row
		Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0,4)

		local resetBtn = Instance.new("TextButton")
		resetBtn.Size = UDim2.new(0,20,0,20)
		resetBtn.Position = UDim2.new(0,146,0.5,-10)
		resetBtn.BackgroundColor3 = Color3.fromRGB(220, 0, 0)
		resetBtn.Text = "R"
		resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		resetBtn.Font = Enum.Font.GothamBold
		resetBtn.TextSize = 9
		resetBtn.BorderSizePixel = 0
		resetBtn.Parent = row
		Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0,4)

		local function updateVal() valLabel.Text = string.format("%.1f", grabState[axis.."Off"]) end

		local holdConn = nil
		local function startHold(dir)
			grabState[axis.."Off"] = grabState[axis.."Off"] + (MOVE_STEP * dir)
			updateVal()
			holdConn = task.delay(0.4, function()
				while holdConn do
					task.wait(0.05)
					grabState[axis.."Off"] = grabState[axis.."Off"] + (MOVE_STEP * dir)
					updateVal()
				end
			end)
		end
		local function stopHold() holdConn = nil end

		minusBtn.MouseButton1Down:Connect(function() startHold(-1) end)
		minusBtn.MouseButton1Up:Connect(stopHold)
		minusBtn.MouseLeave:Connect(stopHold)
		plusBtn.MouseButton1Down:Connect(function() startHold(1) end)
		plusBtn.MouseButton1Up:Connect(stopHold)
		plusBtn.MouseLeave:Connect(stopHold)
		resetBtn.MouseButton1Click:Connect(function() grabState[axis.."Off"] = defaultVal; updateVal() end)

		updateVal()
	end

	makeRow("X", "x", DEFAULT_X)
	makeRow("Y", "y", DEFAULT_Y)
	makeRow("Z", "z", DEFAULT_Z)
	grabAdjustGui = sg
end

local function releaseGrab()
	if currentGrabHeartbeat then currentGrabHeartbeat:Disconnect() currentGrabHeartbeat = nil end
	if currentGrabAnim then pcall(function() currentGrabAnim:Stop() end) currentGrabAnim = nil end
	if currentGrabDummy then currentGrabDummy:Destroy() currentGrabDummy = nil end
	grabState.xOff = DEFAULT_X
	grabState.yOff = DEFAULT_Y
	grabState.zOff = DEFAULT_Z
	showInventory()
	destroyGrabUI()
	
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
	if hum then hum.WalkSpeed = 34.3 end
end

local function startGrab(animalModel)
	releaseGrab()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	hideInventory()
	
	currentGrabDummy = animalModel:Clone()
	for _, d in ipairs(currentGrabDummy:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	currentGrabDummy.Parent = workspace
	
	local animalName = animalModel.Name
	pcall(function()
		local ac = currentGrabDummy:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", currentGrabDummy)
		local animator = ac:FindFirstChild("Animator") or Instance.new("Animator", ac)
		local af2 = ReplicatedStorage.Animations.Animals:FindFirstChild(animalName)
		if af2 and af2:FindFirstChild("Idle") then
			local track = animator:LoadAnimation(af2.Idle)
			track.Looped = true
			track:AdjustSpeed(af2.Idle:GetAttribute("Speed") or 1)
			track:Play()
		end
	end)

	createGrabUI()
	
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://71186871415348"
			currentGrabAnim = humanoid:LoadAnimation(anim)
			currentGrabAnim.Priority = Enum.AnimationPriority.Action4
			currentGrabAnim.Looped = true
			currentGrabAnim:Play()
		end)
	end

	currentGrabHeartbeat = RunService.Heartbeat:Connect(function()
		if not currentGrabDummy or not hrp then return releaseGrab() end
		currentGrabDummy:PivotTo(hrp.CFrame * CFrame.new(grabState.xOff, grabState.yOff, grabState.zOff))
	end)
end

local function spawnAnimal(animalName, selectedTraitsRaw, selectedMutationRaw)
	local animalData = Animals[animalName]
	if not animalData then return false, "Animal not found" end

	local selectedTraitIds = {}
	if selectedTraitsRaw then
		for _, tn in ipairs(selectedTraitsRaw) do
			local id = getTraitIdByName(tn)
			if id then table.insert(selectedTraitIds, id) end
		end
	end

	local selectedMutation = nil
	if selectedMutationRaw and selectedMutationRaw ~= "None" then
		for mid, data in pairs(mutationMap) do
			if data.name == selectedMutationRaw then selectedMutation = mid; break end
		end
		if not selectedMutation then selectedMutation = selectedMutationRaw end
	end

	local animalModel = ReplicatedStorage.Models.Animals:FindFirstChild(animalName)
	if not animalModel then return false, "Model not found" end

	local foundPlot, spawnCFrame, spawnAttachment, claimFrame, hitbox, plotModel = false, nil, nil, nil, nil, nil
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return false, "No plots found" end

	for _, plot in ipairs(plotsFolder:GetChildren()) do
		local ps = plot:FindFirstChild("PlotSign")
		if ps and ps:FindFirstChild("SurfaceGui") and ps.SurfaceGui:FindFirstChild("Frame") then
			local tl = ps.SurfaceGui.Frame:FindFirstChild("TextLabel")
			if tl then
				local ot = tl.Text:gsub("^%s*(.-)%s*$", "%1")
				if string.find(ot:lower(), LocalPlayer.Name:lower()) or ot == LocalPlayer.Name or string.find(ot, LocalPlayer.DisplayName or "") then
					local podiums = plot:FindFirstChild("AnimalPodiums")
					if podiums then
						local pList = {}
						for _, c in ipairs(podiums:GetChildren()) do
							if c:IsA("Model") and tonumber(c.Name) then table.insert(pList, c) end
						end
						table.sort(pList, function(a,b) return tonumber(a.Name) < tonumber(b.Name) end)
						for _, podium in ipairs(pList) do
							local base = podium:FindFirstChild("Base")
							if base and base:FindFirstChild("Spawn") then
								local spawn = base.Spawn
								local att = spawn:FindFirstChild("Attachment")
								local hasAnimal = false
								for _, o in ipairs(spawn:GetChildren()) do
									if o:IsA("Model") then hasAnimal = true; break end
								end
								if not hasAnimal then
									for _, o in ipairs(podium:GetChildren()) do
										if o:IsA("Model") and Animals[o.Name] then hasAnimal = true; break end
									end
								end
								if not att and not hasAnimal then
									spawnCFrame     = spawn.CFrame * CFrame.new(0,-1.5,0)
									spawnAttachment = spawn
									local cm = podium:FindFirstChild("Claim") and podium.Claim:FindFirstChild("Main")
									if cm then
										local cg = cm:FindFirstChild("LocalClaimGui") or Instance.new("BillboardGui")
										cg.Name = "LocalClaimGui"
										cg.Adornee = cm
										cg.Size = UDim2.new(6, 0, 3, 0)
										cg.StudsOffset = Vector3.new(0, 3.5, 0)
										cg.AlwaysOnTop = true
										cg.Parent = cm
										
										local frame = cg:FindFirstChild("Frame") or Instance.new("Frame")
										frame.Name = "Frame"
										frame.Size = UDim2.new(1, 0, 1, 0)
										frame.BackgroundTransparency = 1
										frame.Parent = cg
										
										if frame:FindFirstChild("UICorner") then frame.UICorner:Destroy() end
										if frame:FindFirstChild("UIStroke") then frame.UIStroke:Destroy() end

										local ct = frame:FindFirstChild("Collect") or Instance.new("TextLabel")
										ct.Name = "Collect"
										ct.Size = UDim2.new(0.9, 0, 0.9, 0)
										ct.Position = UDim2.new(0.05, 0, 0.05, 0)
										ct.BackgroundTransparency = 1
										ct.RichText = true
										ct.TextScaled = true
										ct.Font = Enum.Font.FredokaOne
										ct.TextColor3 = Color3.fromRGB(255, 255, 255)
										
										local stroke = ct:FindFirstChild("UIStroke") or Instance.new("UIStroke")
										stroke.Thickness = 2
										stroke.Parent = ct
										ct.Parent = frame
										claimFrame = ct
									end
									hitbox          = podium:FindFirstChild("Claim") and podium.Claim:FindFirstChild("Hitbox")
									plotModel       = plot
									foundPlot = true
									break
								end
							end
						end
						if foundPlot then break end
					end
				end
			end
		end
		if foundPlot then break end
	end
	if not foundPlot then return false, "Plot full or not found" end

	local clonedAnimal = animalModel:Clone()
	clonedAnimal.Name = animalName
	clonedAnimal:PivotTo(spawnCFrame)
	clonedAnimal.Parent = workspace
	
	for _, d in ipairs(clonedAnimal:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	if selectedMutation then SharedAnimals:ApplyMutation(clonedAnimal, animalName, selectedMutation) end
	if #selectedTraitIds > 0 then SharedAnimals:ApplyTraits(clonedAnimal, animalName, selectedTraitIds) end

	pcall(function()
		local ac  = clonedAnimal:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", clonedAnimal)
		local animator = ac:FindFirstChild("Animator") or Instance.new("Animator", ac)
		local af2 = ReplicatedStorage.Animations.Animals:FindFirstChild(animalName)
		if af2 and af2:FindFirstChild("Idle") then
			local track = animator:LoadAnimation(af2.Idle)
			track.Looped = true
			track:AdjustSpeed(af2.Idle:GetAttribute("Speed") or 1)
			track:Play()
		end
	end)

	pcall(function()
		local sf = ReplicatedStorage.Sounds:FindFirstChild("Animals")
		if sf then
			local s = sf:FindFirstChild(animalName)
			if s and s:IsA("Sound") then
				local sc = s:Clone()
				sc.Parent = clonedAnimal.PrimaryPart or clonedAnimal:FindFirstChildWhichIsA("BasePart")
				sc:Play()
				sc.Ended:Connect(function() sc:Destroy() end)
			end
		end
	end)

	local attachmentMarker  = Instance.new("Attachment")
	attachmentMarker.Name   = "Attachment"
	attachmentMarker.Parent = spawnAttachment

	local totalGenRate = SharedAnimals:GetGeneration(animalName, selectedMutation, selectedTraitIds, LocalPlayer)
	local price = SharedAnimals:GetPrice(animalName, LocalPlayer)
	local totalGeneration = 0
	local lastCollectTime = 0
	local alive           = true

	local originalVisuals = {}
	local myClosure = { model = clonedAnimal }

	local function destroyAnimal()
		alive = false
		if globalCarriedClosure == myClosure then
			releaseGrab()
			globalCarriedClosure = nil
			updateAllPromptsState(false)
		end
		if clonedAnimal and clonedAnimal.Parent then clonedAnimal:Destroy() end
		if attachmentMarker and attachmentMarker.Parent then attachmentMarker:Destroy() end
		for i, v in ipairs(spawnedAnimals) do
			if v.model == clonedAnimal then table.remove(spawnedAnimals, i); break end
		end
	end

	pcall(function()
		local ot = ReplicatedStorage:FindFirstChild("Overheads") and ReplicatedStorage.Overheads:FindFirstChild("AnimalOverhead")
		local head = clonedAnimal:FindFirstChild("Head") or clonedAnimal.PrimaryPart
		if ot and head then
			local oh = ot:Clone()
			oh.Name = "AnimalOverhead"
			oh.Adornee     = head
			oh.Parent      = clonedAnimal
			oh.AlwaysOnTop = false
			oh.MaxDistance = 50
			oh.StudsOffset = Vector3.new(0, 7.5, 0)

			for _, ui in ipairs(oh:GetDescendants()) do
				if ui:IsA("GuiObject") then ui.Active = false; ui.Selectable = false end
			end

			oh.DisplayName.Text = animalData.DisplayName or animalName
			oh.Price.Text = ("$%s"):format(NumberUtils:ToString(price))

			local rarityInfo = Rarities[animalData.Rarity]
			oh.Rarity.Text = animalData.Rarity or "Unknown"
			if rarityInfo then
				oh.Rarity.TextColor3 = rarityInfo.Color
				if rarityInfo.StrokeColor and oh.Rarity:FindFirstChild("UIStroke") then
					oh.Rarity.UIStroke.Color = rarityInfo.StrokeColor
				end
				if rarityInfo.GradientPreset then
					pcall(function() Gradients.apply(oh.Rarity, rarityInfo.GradientPreset) end)
				end
			end

			if selectedMutation then
				local mutInfo = mutationMap[selectedMutation] or mutationMap[selectedMutationRaw]
				oh.Mutation.Visible = true
				if mutInfo then
					oh.Mutation.RichText = mutInfo.rich == true
					oh.Mutation.Text = mutInfo.rich and mutInfo.richDisplay or mutInfo.name
					if mutInfo.gradient then
						oh.Mutation.TextColor3 = Color3.new(1,1,1)
						pcall(function() Gradients.apply(oh.Mutation, mutInfo.gradient) end)
					else
						oh.Mutation.TextColor3 = mutInfo.color
					end
				else
					oh.Mutation.Text = selectedMutationRaw
				end
			else
				oh.Mutation.Visible = false
			end

			oh.Generation.Text = ("$%s/s"):format(NumberUtils:ToString(totalGenRate))
			oh.Generation.Visible = true

			if #selectedTraitIds > 0 then
				local template = oh.Traits:FindFirstChild("Template")
				if template then
					for _, tid in ipairs(selectedTraitIds) do
						local tdata = traitMap[tid]
						if tdata then
							local icon = template:Clone()
							icon.Image = tdata.icon
							icon.Visible = true
							icon.Parent = oh.Traits
						end
					end
					oh.Traits.Visible = true
				end
			else
				oh.Traits.Visible = false
			end
		end
	end)

	if spawnAttachment and spawnAttachment:IsA("BasePart") then
		local sellVal = math.ceil(price * (GameData.Animal and GameData.Animal.SellModifier or 0.5))

		local cf, size = clonedAnimal:GetBoundingBox()
		local promptBase = Instance.new("Part")
		promptBase.Name = "PromptBase"
		promptBase.Size = Vector3.new(0.1, 0.1, 0.1)
		promptBase.Transparency = 1
		promptBase.CanCollide = false
		promptBase.CanQuery = false
		promptBase.Anchored = true
		promptBase.CFrame = cf * CFrame.new(0, -size.Y/2, 0)
		promptBase.Parent = clonedAnimal

		local targetPromptPart = promptBase

		local sellPrompt = Instance.new("ProximityPrompt")
		sellPrompt.ObjectText            = ""
		sellPrompt.ActionText            = "Sell: $" .. formatNumber(sellVal)
		sellPrompt.KeyboardKeyCode       = Enum.KeyCode.F
		sellPrompt.HoldDuration          = 1.5
		sellPrompt.MaxActivationDistance = 10
		sellPrompt.RequiresLineOfSight   = true
		sellPrompt.Style                 = Enum.ProximityPromptStyle.Custom
		sellPrompt.UIOffset              = Vector2.new(0, -72)
		sellPrompt.Parent                = targetPromptPart

		local grabPrompt = Instance.new("ProximityPrompt")
		grabPrompt.ObjectText            = animalData.DisplayName or animalName
		grabPrompt.ActionText            = globalCarriedClosure and "Place" or "Grab"
		grabPrompt.KeyboardKeyCode       = Enum.KeyCode.E
		grabPrompt.HoldDuration          = 1.5
		grabPrompt.MaxActivationDistance = 10
		grabPrompt.RequiresLineOfSight   = true
		grabPrompt.Style                 = Enum.ProximityPromptStyle.Custom
		grabPrompt.UIOffset              = Vector2.new(0, 0)
		grabPrompt.Parent                = targetPromptPart
		
		sellPrompt.Enabled = not (globalCarriedClosure ~= nil)

		table.insert(globalPrompts, {grab = grabPrompt, sell = sellPrompt, closure = myClosure})

		myClosure.release = function()
			for part, data in pairs(originalVisuals) do
				if part and part.Parent then part.Transparency = data.Transparency end
			end
			local oh = clonedAnimal:FindFirstChild("AnimalOverhead")
			if oh then
				if oh:FindFirstChild("DisplayName") then oh.DisplayName.Visible = true end
				if oh:FindFirstChild("Price") then oh.Price.Visible = true end
				if oh:FindFirstChild("Rarity") then oh.Rarity.Visible = true end
				if oh:FindFirstChild("Traits") then oh.Traits.Visible = (#selectedTraitIds > 0) end
				if oh:FindFirstChild("Mutation") then oh.Mutation.Visible = (selectedMutation ~= nil) end
			end
			
			if globalCarriedClosure == myClosure then
				releaseGrab()
				globalCarriedClosure = nil
				updateAllPromptsState(false)
			end
		end

		myClosure.grab = function()
			startGrab(clonedAnimal)
			globalCarriedClosure = myClosure
			updateAllPromptsState(true)

			originalVisuals = {}
			for _, part in ipairs(clonedAnimal:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "PromptBase" then
					originalVisuals[part] = { Transparency = part.Transparency }
					if part.Transparency < 1 then part.Transparency = 0.5 end
				end
			end

			local oh = clonedAnimal:FindFirstChild("AnimalOverhead")
			if oh then
				if oh:FindFirstChild("DisplayName") then oh.DisplayName.Visible = false end
				if oh:FindFirstChild("Price") then oh.Price.Visible = false end
				if oh:FindFirstChild("Rarity") then oh.Rarity.Visible = false end
				if oh:FindFirstChild("Traits") then oh.Traits.Visible = false end
				if oh:FindFirstChild("Mutation") then oh.Mutation.Visible = false end
			end
		end

		grabPrompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer or not alive then return end

			if globalCarriedClosure == myClosure then
				myClosure.release()
			elseif globalCarriedClosure == nil then
				myClosure.grab()
			else
				local X_closure = globalCarriedClosure
				local Y_closure = myClosure
				
				local posX = X_closure.model:GetPivot()
				local posY = Y_closure.model:GetPivot()
				
				X_closure.model:PivotTo(posY)
				Y_closure.model:PivotTo(posX)
				
				X_closure.release()
			end
		end)

		sellPrompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer then return end
			if globalCarriedClosure == myClosure then myClosure.release() end
			
			pcall(function()
				local cl = PlayerGui.LeftBottom.LeftBottom:FindFirstChild("Currency")
				if cl and cl:IsA("TextLabel") then cl.Text = "$" .. formatNumber(parseCurrency(cl.Text) + sellVal) end
			end)
			pcall(function()
				local ls   = LocalPlayer:FindFirstChild("leaderstats")
				local cash = ls and ls:FindFirstChild("Cash")
				if cash then cash.Value = cash.Value + sellVal end
			end)
			showCashout("+$" .. formatNumber(sellVal), true)
			
			grabPrompt:Destroy()
			sellPrompt:Destroy()
			destroyAnimal()
		end)
	end

	if claimFrame and hitbox then
		if claimFrame:IsA("TextLabel") then
			local pg = claimFrame.Parent and claimFrame.Parent.Parent
			if pg then pg.Enabled = true end
			claimFrame.Text = "Raccogli\n<font color=\"#73ff00\">$0</font>"
			if hitbox:IsA("BasePart") then hitbox.CanCollide = false; hitbox.CanQuery = true end
			
			hitbox.Touched:Connect(function(hit)
				local pl = Players:GetPlayerFromCharacter(hit.Parent)
				if pl == LocalPlayer and alive and totalGeneration > 0 then
					local ct = os.time()
					if ct - lastCollectTime >= 1 then
						lastCollectTime = ct
						pcall(function()
							local cl = PlayerGui.LeftBottom.LeftBottom:FindFirstChild("Currency")
							if cl and cl:IsA("TextLabel") then
								cl.Text = "$" .. formatNumber(parseCurrency(cl.Text) + totalGeneration)
							end
						end)
						pcall(function()
							local ls   = LocalPlayer:FindFirstChild("leaderstats")
							local cash = ls and ls:FindFirstChild("Cash")
							if cash then cash.Value = cash.Value + totalGeneration end
						end)
						pcall(function()
							local s = ReplicatedStorage.Sounds.Sfx:FindFirstChild("Cashout")
							if s then
								local sc = s:Clone()
								sc.Parent = LocalPlayer.Character or workspace
								sc:Play()
								game:GetService("Debris"):AddItem(sc, 2)
							end
						end)
						showCashout("+$" .. formatNumber(totalGeneration), true)
						totalGeneration = 0
						claimFrame.Text = "Raccogli\n<font color=\"#73ff00\">$0</font>"
					end
				end
			end)
			task.spawn(function()
				while alive and clonedAnimal and clonedAnimal.Parent do
					task.wait(1)
					totalGeneration = totalGeneration + totalGenRate
					pcall(function()
						claimFrame.Text = "Raccogli\n<font color=\"#73ff00\">$" .. formatNumber(totalGeneration) .. "</font>"
					end)
				end
			end)
		end
	end

	table.insert(spawnedAnimals, {
		model   = clonedAnimal,
		marker  = attachmentMarker,
		destroy = destroyAnimal,
		name    = animalName,
		plot    = plotModel,
		claim   = claimFrame,
		gen     = function() return totalGeneration end,
		resetGen = function() totalGeneration = 0 end
	})
	return true, clonedAnimal
end

if CoreGui:FindFirstChild("BrainrotSpawnerGUI") then
	CoreGui.BrainrotSpawnerGUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "BrainrotSpawnerGUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = CoreGui

local COLORS = {
	bg         = Color3.fromRGB(15, 10, 10),
	header     = Color3.fromRGB(35, 10, 10),
	card       = Color3.fromRGB(25, 15, 15),
	cardHover  = Color3.fromRGB(40, 20, 20),
	text       = Color3.fromRGB(255, 200, 200),
	textDim    = Color3.fromRGB(200, 150, 150),
	scrollbar  = Color3.fromRGB(80, 20, 20),
	toggleOn   = Color3.fromRGB(255, 50, 50),
	toggleOff  = Color3.fromRGB(60, 30, 30),
	button     = Color3.fromRGB(120, 20, 20),
	danger     = Color3.fromRGB(220, 0, 0),
	dangerText = Color3.fromRGB(255, 255, 255),
	dropdownBg = Color3.fromRGB(20, 10, 10),
	border     = Color3.fromRGB(80, 15, 15),
}

local IntroOverlay = Instance.new("Frame")
IntroOverlay.Size = UDim2.new(1,0,1,0)
IntroOverlay.BackgroundColor3 = Color3.fromRGB(10, 5, 5)
IntroOverlay.BackgroundTransparency = 0.1
IntroOverlay.ZIndex = 500
IntroOverlay.Parent = ScreenGui

local IntroTitle = Instance.new("TextLabel", IntroOverlay)
IntroTitle.Size = UDim2.new(1,0,0,50)
IntroTitle.Position = UDim2.new(0,0,0.5,-40)
IntroTitle.BackgroundTransparency = 1
IntroTitle.Text = "Illusion Dev spawner"
IntroTitle.TextColor3 = Color3.new(1,0,0)
IntroTitle.Font = Enum.Font.GothamBold
IntroTitle.TextSize = 24

local IntroSub = Instance.new("TextLabel", IntroOverlay)
IntroSub.Size = UDim2.new(1,0,0,30)
IntroSub.Position = UDim2.new(0,0,0.5,10)
IntroSub.BackgroundTransparency = 1
IntroSub.Text = "Premium Edition Loaded"
IntroSub.TextColor3 = Color3.fromRGB(200, 100, 100)
IntroSub.Font = Enum.Font.GothamMedium
IntroSub.TextSize = 16

task.delay(3, function()
	TweenService:Create(IntroOverlay, TweenInfo.new(1), {BackgroundTransparency = 1}):Play()
	TweenService:Create(IntroTitle, TweenInfo.new(1), {TextTransparency = 1}):Play()
	TweenService:Create(IntroSub, TweenInfo.new(1), {TextTransparency = 1}):Play()
	task.delay(1, function() IntroOverlay:Destroy() end)
end)

local DropdownOverlay = Instance.new("Frame")
DropdownOverlay.Name               = "DropdownOverlay"
DropdownOverlay.Size               = UDim2.new(1,0,1,0)
DropdownOverlay.BackgroundTransparency = 1
DropdownOverlay.ZIndex             = 200
DropdownOverlay.Parent             = ScreenGui

local allDropdowns = {}
local function closeAllDropdowns()
	for _, dd in ipairs(allDropdowns) do dd.list.Visible = false; dd.open = false end
end

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "Main"
MainFrame.Size             = UDim2.new(0,260,0,380)
MainFrame.Position         = UDim2.new(0.5,-130,0.5,-190)
MainFrame.BackgroundColor3 = COLORS.bg
MainFrame.BorderSizePixel  = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,10)
local ms = Instance.new("UIStroke", MainFrame); ms.Color = COLORS.border; ms.Thickness = 1

local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1,0,0,34)
Header.BackgroundColor3 = COLORS.header
Header.BorderSizePixel  = 0; Header.ZIndex = 5; Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0,10)
local hf = Instance.new("Frame", Header)
hf.Size = UDim2.new(1,0,0,10); hf.Position = UDim2.new(0,0,1,-10)
hf.BackgroundColor3 = COLORS.header; hf.BorderSizePixel = 0; hf.ZIndex = 5
local sl = Instance.new("Frame", Header)
sl.Size = UDim2.new(1,-20,0,1); sl.Position = UDim2.new(0,10,1,0)
sl.BackgroundColor3 = COLORS.border; sl.BorderSizePixel = 0; sl.ZIndex = 5

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1,-60,1,0); Title.Position = UDim2.new(0,14,0,0)
Title.BackgroundTransparency = 1; Title.Text = "Brainrot Spawner"
Title.TextColor3 = COLORS.text; Title.Font = Enum.Font.GothamBold
Title.TextSize = 12; Title.TextXAlignment = Enum.TextXAlignment.Left; Title.ZIndex = 6

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0,22,0,22); CloseBtn.Position = UDim2.new(1,-30,0.5,-11)
CloseBtn.BackgroundColor3 = COLORS.danger; CloseBtn.Text = "X"
CloseBtn.TextColor3 = COLORS.dangerText; CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 10; CloseBtn.BorderSizePixel = 0; CloseBtn.ZIndex = 6
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0,6)

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = UDim2.new(0,22,0,22); MinBtn.Position = UDim2.new(1,-56,0.5,-11)
MinBtn.BackgroundColor3 = COLORS.card; MinBtn.Text = "-"
MinBtn.TextColor3 = COLORS.text; MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12; MinBtn.BorderSizePixel = 0; MinBtn.ZIndex = 6
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0,6)

local ContentFrame = Instance.new("ScrollingFrame")
ContentFrame.Name                 = "Content"
ContentFrame.Size                 = UDim2.new(1,-16,1,-44)
ContentFrame.Position             = UDim2.new(0,8,0,38)
ContentFrame.BackgroundTransparency = 1; ContentFrame.BorderSizePixel = 0
ContentFrame.ScrollBarThickness   = 3
ContentFrame.ScrollBarImageColor3 = COLORS.scrollbar
ContentFrame.CanvasSize           = UDim2.new(0,0,0,0)
ContentFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
ContentFrame.Parent               = MainFrame
local cl2 = Instance.new("UIListLayout", ContentFrame)
cl2.SortOrder = Enum.SortOrder.LayoutOrder; cl2.Padding = UDim.new(0,4)
local cp2 = Instance.new("UIPadding", ContentFrame)
cp2.PaddingTop = UDim.new(0,4); cp2.PaddingBottom = UDim.new(0,10)

local function createSection(title, layoutOrder)
	local s = Instance.new("Frame")
	s.Size = UDim2.new(1,0,0,20); s.BackgroundTransparency = 1
	s.LayoutOrder = layoutOrder; s.Parent = ContentFrame
	local l = Instance.new("TextLabel", s)
	l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency = 1
	l.Text = string.upper(title); l.TextColor3 = COLORS.textDim
	l.Font = Enum.Font.GothamBold; l.TextSize = 9; l.TextXAlignment = Enum.TextXAlignment.Left
	local p = Instance.new("UIPadding", l); p.PaddingLeft = UDim.new(0,6)
	return s
end

local function createDropdown(labelText, options, default, layoutOrder, callback)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1,0,0,46); container.BackgroundColor3 = COLORS.card
	container.BorderSizePixel = 0; container.LayoutOrder = layoutOrder; container.Parent = ContentFrame
	Instance.new("UICorner", container).CornerRadius = UDim.new(0,6)
	local cp3 = Instance.new("UIPadding", container)
	cp3.PaddingLeft = UDim.new(0,8); cp3.PaddingRight = UDim.new(0,8); cp3.PaddingTop = UDim.new(0,6)
	
	local lbl = Instance.new("TextLabel", container)
	lbl.Size = UDim2.new(1,0,0,12); lbl.BackgroundTransparency = 1; lbl.Text = labelText
	lbl.TextColor3 = COLORS.textDim; lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 9; lbl.TextXAlignment = Enum.TextXAlignment.Left
	
	local selectedValue = default or options[1] or "None"
	local dropBtn = Instance.new("TextButton", container)
	dropBtn.Size = UDim2.new(1,0,0,22); dropBtn.Position = UDim2.new(0,0,0,16)
	dropBtn.BackgroundColor3 = COLORS.dropdownBg; dropBtn.BorderSizePixel = 0
	dropBtn.Text = "  "..selectedValue.."  v"; dropBtn.TextColor3 = COLORS.text
	dropBtn.Font = Enum.Font.GothamMedium; dropBtn.TextSize = 10
	dropBtn.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UICorner", dropBtn).CornerRadius = UDim.new(0,4)
	local bs = Instance.new("UIStroke", dropBtn); bs.Color = COLORS.border; bs.Thickness = 1
	
	local listHeight = math.min(#options * 20, 180)
	local dropList   = Instance.new("ScrollingFrame")
	dropList.Size = UDim2.new(0,190,0,listHeight); dropList.BackgroundColor3 = COLORS.dropdownBg
	dropList.BorderSizePixel = 0; dropList.Visible = false; dropList.ZIndex = 201
	dropList.ScrollBarThickness = 3; dropList.ScrollBarImageColor3 = COLORS.scrollbar
	dropList.CanvasSize = UDim2.new(0,0,0,#options*20)
	dropList.ClipsDescendants = true; dropList.Parent = DropdownOverlay
	Instance.new("UICorner", dropList).CornerRadius = UDim.new(0,6)
	local ls2 = Instance.new("UIStroke", dropList); ls2.Color = COLORS.border; ls2.Thickness = 1
	Instance.new("UIListLayout", dropList).SortOrder = Enum.SortOrder.LayoutOrder
	
	local ddEntry = {list=dropList, open=false, btn=dropBtn}
	table.insert(allDropdowns, ddEntry)
	for i, option in ipairs(options) do
		local ob = Instance.new("TextButton", dropList)
		ob.Size = UDim2.new(1,0,0,20); ob.BackgroundColor3 = COLORS.dropdownBg
		ob.BorderSizePixel = 0; ob.Text = "  "..option
		ob.TextColor3 = COLORS.text; ob.Font = Enum.Font.Gotham
		ob.TextSize = 10; ob.TextXAlignment = Enum.TextXAlignment.Left
		ob.LayoutOrder = i; ob.ZIndex = 202
		if Animals[option] and Rarities[Animals[option].Rarity] then
			ob.TextColor3 = Rarities[Animals[option].Rarity].Color
		end
		ob.MouseEnter:Connect(function() ob.BackgroundColor3 = COLORS.cardHover end)
		ob.MouseLeave:Connect(function() ob.BackgroundColor3 = COLORS.dropdownBg end)
		ob.MouseButton1Click:Connect(function()
			selectedValue = option
			dropBtn.Text = "  "..option.."  v"
			dropList.Visible = false; ddEntry.open = false
			dropBtn.TextColor3 = (Animals[option] and Rarities[Animals[option].Rarity]) and Rarities[Animals[option].Rarity].Color or COLORS.text
			if callback then callback(option) end
		end)
	end
	dropBtn.MouseButton1Click:Connect(function()
		local wasOpen = not ddEntry.open
		closeAllDropdowns()
		if wasOpen then
			local ap = dropBtn.AbsolutePosition; local as2 = dropBtn.AbsoluteSize
			local ss = ScreenGui.AbsoluteSize
			local xp = ap.X + as2.X + 6; local yp = ap.Y
			if xp + 190 > ss.X then xp = ap.X - 190 - 6 end
			if yp + listHeight > ss.Y then yp = ss.Y - listHeight - 6 end
			dropList.Position = UDim2.new(0,xp,0,yp)
			dropList.Visible = true; ddEntry.open = true
		end
	end)
	return {
		getValue = function() return selectedValue end,
		setValue = function(v) selectedValue = v; dropBtn.Text = "  "..v.."  v"; if callback then callback(v) end end,
	}
end

local function createMultiDropdown(labelText, options, layoutOrder, callback)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1,0,0,46); container.BackgroundColor3 = COLORS.card
	container.BorderSizePixel = 0; container.LayoutOrder = layoutOrder; container.Parent = ContentFrame
	Instance.new("UICorner", container).CornerRadius = UDim.new(0,6)
	local cp3 = Instance.new("UIPadding", container)
	cp3.PaddingLeft = UDim.new(0,8); cp3.PaddingRight = UDim.new(0,8); cp3.PaddingTop = UDim.new(0,6)
	
	local lbl = Instance.new("TextLabel", container)
	lbl.Size = UDim2.new(1,0,0,12); lbl.BackgroundTransparency = 1; lbl.Text = labelText
	lbl.TextColor3 = COLORS.textDim; lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 9; lbl.TextXAlignment = Enum.TextXAlignment.Left
	
	local selectedValues = {}
	
	local dropBtn = Instance.new("TextButton", container)
	dropBtn.Size = UDim2.new(1,0,0,22); dropBtn.Position = UDim2.new(0,0,0,16)
	dropBtn.BackgroundColor3 = COLORS.dropdownBg; dropBtn.BorderSizePixel = 0
	dropBtn.Text = "  0 Selected  v"; dropBtn.TextColor3 = COLORS.text
	dropBtn.Font = Enum.Font.GothamMedium; dropBtn.TextSize = 10
	dropBtn.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UICorner", dropBtn).CornerRadius = UDim.new(0,4)
	local bs = Instance.new("UIStroke", dropBtn); bs.Color = COLORS.border; bs.Thickness = 1
	
	local listHeight = math.min(#options * 20, 180)
	local dropList   = Instance.new("ScrollingFrame")
	dropList.Size = UDim2.new(0,190,0,listHeight); dropList.BackgroundColor3 = COLORS.dropdownBg
	dropList.BorderSizePixel = 0; dropList.Visible = false; dropList.ZIndex = 201
	dropList.ScrollBarThickness = 3; dropList.ScrollBarImageColor3 = COLORS.scrollbar
	dropList.CanvasSize = UDim2.new(0,0,0,#options*20)
	dropList.ClipsDescendants = true; dropList.Parent = DropdownOverlay
	Instance.new("UICorner", dropList).CornerRadius = UDim.new(0,6)
	local ls2 = Instance.new("UIStroke", dropList); ls2.Color = COLORS.border; ls2.Thickness = 1
	Instance.new("UIListLayout", dropList).SortOrder = Enum.SortOrder.LayoutOrder
	
	local ddEntry = {list=dropList, open=false, btn=dropBtn}
	table.insert(allDropdowns, ddEntry)
	
	local optionButtons = {}
	
	local function updateBtnText()
		local count = 0
		for _ in pairs(selectedValues) do count = count + 1 end
		dropBtn.Text = "  " .. count .. " Selected  v"
	end
	
	for i, option in ipairs(options) do
		local ob = Instance.new("TextButton", dropList)
		ob.Size = UDim2.new(1,0,0,20); ob.BackgroundColor3 = COLORS.dropdownBg
		ob.BorderSizePixel = 0; ob.Text = "  [ ] "..option
		ob.TextColor3 = COLORS.text; ob.Font = Enum.Font.Gotham
		ob.TextSize = 10; ob.TextXAlignment = Enum.TextXAlignment.Left
		ob.LayoutOrder = i; ob.ZIndex = 202
		optionButtons[option] = ob
		
		ob.MouseEnter:Connect(function() ob.BackgroundColor3 = COLORS.cardHover end)
		ob.MouseLeave:Connect(function() ob.BackgroundColor3 = COLORS.dropdownBg end)
		ob.MouseButton1Click:Connect(function()
			if selectedValues[option] then
				selectedValues[option] = nil
				ob.Text = "  [ ] "..option
				ob.TextColor3 = COLORS.text
			else
				selectedValues[option] = true
				ob.Text = "  [X] "..option
				ob.TextColor3 = COLORS.toggleOn
			end
			updateBtnText()
			if callback then callback(selectedValues) end
		end)
	end
	
	dropBtn.MouseButton1Click:Connect(function()
		local wasOpen = not ddEntry.open
		closeAllDropdowns()
		if wasOpen then
			local ap = dropBtn.AbsolutePosition; local as2 = dropBtn.AbsoluteSize
			local ss = ScreenGui.AbsoluteSize
			local xp = ap.X + as2.X + 6; local yp = ap.Y
			if xp + 190 > ss.X then xp = ap.X - 190 - 6 end
			if yp + listHeight > ss.Y then yp = ss.Y - listHeight - 6 end
			dropList.Position = UDim2.new(0,xp,0,yp)
			dropList.Visible = true; ddEntry.open = true
		end
	end)
	
	return {
		getValues = function()
			local t = {}
			for k in pairs(selectedValues) do table.insert(t, k) end
			return t
		end,
		clearValues = function()
			selectedValues = {}
			updateBtnText()
			for opt, btn in pairs(optionButtons) do
				btn.Text = "  [ ] "..opt
				btn.TextColor3 = COLORS.text
			end
			if callback then callback(selectedValues) end
		end
	}
end

local function createButton(text, layoutOrder, color, textColor, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1,0,0,28); btn.BackgroundColor3 = color or COLORS.button
	btn.BorderSizePixel = 0; btn.Text = text; btn.TextColor3 = textColor or COLORS.text
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 10
	btn.LayoutOrder = layoutOrder; btn.Parent = ContentFrame
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
	local bs = Instance.new("UIStroke", btn); bs.Color = COLORS.border; bs.Thickness = 1
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.new(
			math.min(1,(color or COLORS.button).R+0.1),
			math.min(1,(color or COLORS.button).G+0.1),
			math.min(1,(color or COLORS.button).B+0.1))}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = color or COLORS.button}):Play()
	end)
	btn.MouseButton1Click:Connect(function() if callback then callback() end end)
	return btn
end

local function createLabel(text, layoutOrder, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1,0,0,14); l.BackgroundTransparency = 1; l.Text = text
	l.TextColor3 = color or COLORS.textDim; l.Font = Enum.Font.Gotham
	l.TextSize = 9; l.LayoutOrder = layoutOrder; l.TextWrapped = true; l.Parent = ContentFrame
	return l
end

local selectedAnimal   = animalList[1] or "None"
local selectedMutation = "None"
local selectedTraitsMulti = {}

createSection("Select Settings", 1)
createDropdown("Animal",   animalList,   animalList[1], 2, function(c) selectedAnimal   = c end)
createDropdown("Mutation", mutationList, "None",        3, function(c) selectedMutation = c end)

local traitsDropdownObj = createMultiDropdown("Traits", traitList, 4, function(vals)
	selectedTraitsMulti = {}
	for k in pairs(vals) do table.insert(selectedTraitsMulti, k) end
end)

createSection("Actions", 200)

createButton("Spawn Brainrot", 201, COLORS.button, COLORS.text, function()
	if not selectedAnimal or selectedAnimal == "None" then return end
	local mu = (selectedMutation == "None") and nil or selectedMutation
	
	local ok, res = spawnAnimal(selectedAnimal, selectedTraitsMulti, mu)
	if ok then showCashout("Spawned: " .. selectedAnimal, true)
	else showCashout("Error: " .. tostring(res), false) end
end)

createButton("Remove All Traits", 202, Color3.fromRGB(60, 20, 20), Color3.fromRGB(255, 150, 150), function()
	traitsDropdownObj.clearValues()
end)

createButton("Collect All Money", 204, Color3.fromRGB(46, 204, 113), Color3.fromRGB(255, 255, 255), function()
	local total = 0
	for _, data in ipairs(spawnedAnimals) do
		if data.gen and data.gen() > 0 then
			local amt = data.gen()
			total = total + amt
			data.resetGen()
			if data.claim then data.claim.Text = "Raccogli\n<font color=\"#73ff00\">$0</font>" end
		end
	end
	if total > 0 then
		pcall(function()
			local cl = PlayerGui.LeftBottom.LeftBottom:FindFirstChild("Currency")
			if cl and cl:IsA("TextLabel") then cl.Text = "$" .. formatNumber(parseCurrency(cl.Text) + total) end
		end)
		pcall(function()
			local ls = LocalPlayer:FindFirstChild("leaderstats")
			local cash = ls and ls:FindFirstChild("Cash")
			if cash then cash.Value = cash.Value + total end
		end)
		showCashout("Collected: $" .. formatNumber(total), true)
	else
		showCashout("Nothing to collect", false)
	end
end)

createButton("Teleport to Plot", 205, Color3.fromRGB(30, 80, 150), Color3.fromRGB(255, 255, 255), function()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local plot = nil
	for _, data in ipairs(spawnedAnimals) do if data.plot then plot = data.plot; break end end
	
	if not plot then
		-- Fallback search
		local plotsFolder = workspace:FindFirstChild("Plots")
		if plotsFolder then
			for _, p in ipairs(plotsFolder:GetChildren()) do
				local ps = p:FindFirstChild("PlotSign")
				if ps and ps:FindFirstChild("SurfaceGui") and ps.SurfaceGui:FindFirstChild("Frame") then
					local tl = ps.SurfaceGui.Frame:FindFirstChild("TextLabel")
					if tl and (tl.Text:lower():find(LocalPlayer.Name:lower()) or tl.Text:lower():find(LocalPlayer.DisplayName:lower())) then
						plot = p; break
					end
				end
			end
		end
	end
	
	if plot then
		local target = plot:FindFirstChild("Base") or plot.PrimaryPart
		if target then hrp.CFrame = target.CFrame * CFrame.new(0, 5, 0) end
	else
		showCashout("Plot not found", false)
	end
end)

createSection("Info", 300)
createLabel("Everything is client-side only",   301, Color3.fromRGB(200, 100, 100))
createLabel("Money is NOT added to the server", 302, Color3.fromRGB(220, 80, 80))
createLabel("Animals loaded: " .. #animalList,  303)

local dragging, dragStart, startPos2 = false, nil, nil
Header.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = i.Position; startPos2 = MainFrame.Position
	end
end)
Header.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
UserInputService.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		MainFrame.Position = UDim2.new(startPos2.X.Scale, startPos2.X.Offset+d.X, startPos2.Y.Scale, startPos2.Y.Offset+d.Y)
	end
end)

local minimized    = false
local originalSize = MainFrame.Size

MinBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	closeAllDropdowns()
	if minimized then
		TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size=UDim2.new(0,260,0,34)}):Play()
		ContentFrame.Visible = false; MinBtn.Text = "+"
	else
		ContentFrame.Visible = true
		TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size=originalSize}):Play()
		MinBtn.Text = "-"
	end
end)

CloseBtn.MouseButton1Click:Connect(function()
	releaseGrab()
	ScreenGui:Destroy()
end)

UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.RightShift then
		MainFrame.Visible = not MainFrame.Visible
		if not MainFrame.Visible then closeAllDropdowns() end
	end
end)

RunService.Heartbeat:Connect(function()
	local char = LocalPlayer.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		
		if hrp and hum then
			local isCarrying = (globalCarriedClosure ~= nil)
			
			if isCarrying and currentGrabAnim and not currentGrabAnim.IsPlaying then
				currentGrabAnim:Play()
			end
			
			local targetSpeed = isCarrying and 21.5 or 34.3
			if hum.WalkSpeed ~= targetSpeed then hum.WalkSpeed = targetSpeed end
		end
	end
end)
