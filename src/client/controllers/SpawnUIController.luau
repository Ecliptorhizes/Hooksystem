local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)

local SpawnUIController = Knit.CreateController({
	Name = "SpawnUIController",
})
local maid = Maid.new()

function SpawnUIController:KnitStart()
	local RoundService = Knit.GetService("RoundService")
	local SpawnService = Knit.GetService("SpawnService")
	local player = Players.LocalPlayer
	local PlayerGui = player:WaitForChild("PlayerGui")

	local mainLobby = PlayerGui:WaitForChild("MainLobby", 30)
	if not mainLobby then
		for _, gui in PlayerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui:FindFirstChild("Deploy", true) then
				mainLobby = gui
				break
			end
		end
	end
	if not mainLobby then
		mainLobby = Instance.new("ScreenGui")
		mainLobby.Name = "MainLobby"
		mainLobby.ResetOnSpawn = false
		mainLobby.Parent = PlayerGui
		local deployFrame = Instance.new("Frame")
		deployFrame.Name = "Deploy"
		deployFrame.Size = UDim2.new(0, 200, 0, 60)
		deployFrame.Position = UDim2.new(0.5, -100, 0.5, -30)
		deployFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		deployFrame.BorderSizePixel = 0
		deployFrame.Parent = mainLobby
		local inner = Instance.new("Frame")
		inner.Name = "Frame"
		inner.Size = UDim2.new(1, 0, 1, 0)
		inner.BackgroundTransparency = 1
		inner.Parent = deployFrame
		local deployBtn = Instance.new("TextButton")
		deployBtn.Name = "Deploy"
		deployBtn.Size = UDim2.new(1, -20, 1, -20)
		deployBtn.Position = UDim2.new(0, 10, 0, 10)
		deployBtn.Text = "Deploy"
		deployBtn.Font = Enum.Font.GothamBold
		deployBtn.TextSize = 18
		deployBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		deployBtn.BorderSizePixel = 0
		deployBtn.Parent = inner
	end
	if mainLobby then
		local deployGui = mainLobby:FindFirstChild("Deploy") or mainLobby:FindFirstChild("DeployFrame")
		if deployGui then
			local frame = deployGui:FindFirstChild("Frame") or deployGui:WaitForChild("Frame", 5)
			if frame then
				local deployBtn = frame:FindFirstChild("Deploy") or frame:WaitForChild("Deploy", 5)
				if deployBtn then
					local deployInProgress = false
					local function setDeployVisible(visible: boolean)
						if visible and deployInProgress then
							return
						end
						if deployGui:IsA("ScreenGui") then
							deployGui.Enabled = visible
							if visible then
								deployGui.DisplayOrder = 100
							end
						elseif deployGui:IsA("GuiObject") then
							deployGui.Visible = visible
						end
						if deployGui:IsA("GuiButton") then
							deployGui.Enabled = visible
						end
						if mainLobby:IsA("ScreenGui") then
							mainLobby.Enabled = visible
						end
						if frame and frame:IsA("GuiObject") then
							frame.Visible = visible
						end
					end

					setDeployVisible(true)

					maid:GiveTask(deployBtn.MouseButton1Click:Connect(function()
						deployInProgress = true
						setDeployVisible(false)
						local success, err = SpawnService:DeployToGame():await()
						if not success and err then
							deployInProgress = false
							setDeployVisible(true)
							warn("[SpawnUIController] Deploy failed:", err)
						end
					end))

					task.spawn(function()
						local inRound = (SpawnService:IsPlayerInRound():await()) == 1
						setDeployVisible(not inRound)
					end)
					maid:GiveTask(task.spawn(function()
						while true do
							task.wait(0.25)
							local inRound = (SpawnService:IsPlayerInRound():await()) == 1
							if inRound then
								deployInProgress = false
							end
							setDeployVisible(not inRound)
						end
					end))
				end
			end
		end
	end

	local inGame = PlayerGui:FindFirstChild("InGame")
	if inGame then
		local returnBtn = inGame:FindFirstChild("ReturnToLobby", true)
		if returnBtn and returnBtn:IsA("GuiButton") then
			maid:GiveTask(returnBtn.MouseButton1Click:Connect(function()
				local success, err = SpawnService:ReturnToLobby():await()
				if not success and err then
					warn("[SpawnUIController] Return to lobby failed:", err)
				end
			end))
		end
	end

	local spawnGui = PlayerGui:FindFirstChild("SpawnGui")
	if spawnGui then
		local spawnButton = spawnGui:FindFirstChild("SpawnButton")
		if spawnButton then
			spawnGui.Visible = false

			maid:GiveTask(task.spawn(function()
				while true do
					task.wait(0.2)
					local state = RoundService:GetRoundState():await()
					local inRound = (SpawnService:IsPlayerInRound():await()) == 1
					spawnGui.Visible = (state == "InProgress" and not inRound)
				end
			end))

			maid:GiveTask(spawnButton.MouseButton1Click:Connect(function()
				local success, err = SpawnService:RequestSpawn():await()
				if success then
					spawnGui.Visible = false
				elseif err then
					warn("[SpawnUIController] Spawn failed:", err)
				end
			end))
		end
	end
end

function SpawnUIController:KnitDestroy()
	maid:DoCleaning()
end

return SpawnUIController
