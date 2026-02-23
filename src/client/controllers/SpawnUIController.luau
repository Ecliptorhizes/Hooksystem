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

	local mainLobby = PlayerGui:WaitForChild("MainLobby", 10)
	if mainLobby then
		if mainLobby:IsA("ScreenGui") then
			mainLobby.Enabled = true
		end

		local deployGui = mainLobby:FindFirstChild("Deploy")
		if deployGui then
			local frame = deployGui:FindFirstChild("Frame")
			if frame then
				local deployBtn = frame:FindFirstChild("Deploy")
				if deployBtn then
					deployGui.Enabled = true

					maid:GiveTask(deployBtn.MouseButton1Click:Connect(function()
						local success, err = SpawnService:DeployToGame():await()
						if not success and err then
							warn("[SpawnUIController] Deploy failed:", err)
						end
					end))

					maid:GiveTask(task.spawn(function()
						while true do
							task.wait(0.5)
							local inRound = (SpawnService:IsPlayerInRound():await()) == 1
							local showDeploy = not inRound
							deployGui.Enabled = showDeploy
							if mainLobby:IsA("ScreenGui") then
								mainLobby.Enabled = showDeploy
							end
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
					task.wait(0.5)
					local state = RoundService:GetRoundState():await()
					local inRound = (SpawnService:IsPlayerInRound():await()) == 1

					if state == "InProgress" and not inRound then
						spawnGui.Visible = true
					else
						spawnGui.Visible = false
					end
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
