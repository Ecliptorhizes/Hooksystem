--[[
	SpawnUIController
	Purpose:
	Manage deploy, spawn, and return UI visibility in sync with server round state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)

local SpawnUIController = Knit.CreateController({
	Name = "SpawnUIController",
})
local maid = Maid.new()

--[[
	Finds or creates the MainLobby screen used for deploy UI flow.
]]
local function ensureMainLobbyGui(playerGui: PlayerGui): ScreenGui
	local mainLobby = playerGui:FindFirstChild("MainLobby")
	if mainLobby and mainLobby:IsA("ScreenGui") then
		return mainLobby
	end

	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui:FindFirstChild("Deploy", true) then
			return gui
		end
	end

	local fallback = Instance.new("ScreenGui")
	fallback.Name = "MainLobby"
	fallback.ResetOnSpawn = false
	fallback.Parent = playerGui

	local deployFrame = Instance.new("Frame")
	deployFrame.Name = "Deploy"
	deployFrame.Size = UDim2.new(0, 200, 0, 60)
	deployFrame.Position = UDim2.new(0.5, -100, 0.5, -30)
	deployFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	deployFrame.BorderSizePixel = 0
	deployFrame.Parent = fallback

	local container = Instance.new("Frame")
	container.Name = "Frame"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = deployFrame

	local deployButton = Instance.new("TextButton")
	deployButton.Name = "Deploy"
	deployButton.Size = UDim2.new(1, -20, 1, -20)
	deployButton.Position = UDim2.new(0, 10, 0, 10)
	deployButton.Text = "Deploy"
	deployButton.Font = Enum.Font.GothamBold
	deployButton.TextSize = 18
	deployButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	deployButton.BorderSizePixel = 0
	deployButton.Parent = container

	return fallback
end

--[[
	Sets visibility for ScreenGui / GuiObject / GuiButton consistently.
]]
local function setGuiVisible(gui: Instance, visible: boolean)
	if gui:IsA("ScreenGui") then
		gui.Enabled = visible
		if visible then
			gui.DisplayOrder = 100
		end
	elseif gui:IsA("GuiObject") then
		gui.Visible = visible
	end

	if gui:IsA("GuiButton") then
		gui.Enabled = visible
	end
end

--[[
	Binds deploy, spawn, and return UI interactions to server services.
]]
function SpawnUIController:KnitStart()
	local roundService = Knit.GetService("RoundService")
	local spawnService = Knit.GetService("SpawnService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local mainLobby = ensureMainLobbyGui(playerGui)

	local deployGui = mainLobby:FindFirstChild("Deploy") or mainLobby:FindFirstChild("DeployFrame")
	local deployFrame = deployGui and (deployGui:FindFirstChild("Frame") or deployGui:WaitForChild("Frame", 5))
	local deployButton = deployFrame and (deployFrame:FindFirstChild("Deploy") or deployFrame:WaitForChild("Deploy", 5))

	if deployGui and deployFrame and deployButton then
		local deployInProgress = false
		local function setDeployVisible(visible: boolean)
			if visible and deployInProgress then
				return
			end
			setGuiVisible(deployGui, visible)
			setGuiVisible(mainLobby, visible)
			if deployFrame:IsA("GuiObject") then
				deployFrame.Visible = visible
			end
		end

		setDeployVisible(true)
		maid:GiveTask(deployButton.MouseButton1Click:Connect(function()
			deployInProgress = true
			setDeployVisible(false)
			local success, err = spawnService:DeployToGame():await()
			if success then
				return
			end
			deployInProgress = false
			setDeployVisible(true)
			if err then
				warn("[SpawnUIController] Deploy failed:", err)
			end
		end))

		task.spawn(function()
			local inRound = (spawnService:IsPlayerInRound():await()) == 1
			setDeployVisible(not inRound)
		end)

		maid:GiveTask(task.spawn(function()
			while true do
				task.wait(0.25)
				local inRound = (spawnService:IsPlayerInRound():await()) == 1
				if inRound then
					deployInProgress = false
				end
				setDeployVisible(not inRound)
			end
		end))
	end

	local inGame = playerGui:FindFirstChild("InGame")
	if inGame then
		local returnButton = inGame:FindFirstChild("ReturnToLobby", true)
		if returnButton and returnButton:IsA("GuiButton") then
			maid:GiveTask(returnButton.MouseButton1Click:Connect(function()
				local success, err = spawnService:ReturnToLobby():await()
				if not success and err then
					warn("[SpawnUIController] Return to lobby failed:", err)
				end
			end))
		end
	end

	local spawnGui = playerGui:FindFirstChild("SpawnGui")
	if spawnGui then
		local spawnButton = spawnGui:FindFirstChild("SpawnButton")
		if spawnButton and spawnButton:IsA("GuiButton") then
			spawnGui.Visible = false

			maid:GiveTask(task.spawn(function()
				while true do
					task.wait(0.2)
					local state = roundService:GetRoundState():await()
					local inRound = (spawnService:IsPlayerInRound():await()) == 1
					spawnGui.Visible = (state == "InProgress" and not inRound)
				end
			end))

			maid:GiveTask(spawnButton.MouseButton1Click:Connect(function()
				local success, err = spawnService:RequestSpawn():await()
				if success then
					spawnGui.Visible = false
				elseif err then
					warn("[SpawnUIController] Spawn failed:", err)
				end
			end))
		end
	end
end

--[[
	Cleans up UI polling loops and button event connections.
]]
function SpawnUIController:KnitDestroy()
	maid:DoCleaning()
end

return SpawnUIController
