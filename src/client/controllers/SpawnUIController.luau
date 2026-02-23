local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Packages.Maid)

local SpawnUIController = Knit.CreateController({
    Name = "SpawnUIController",
})

local maid = Maid.new()

function SpawnUIController:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    local SpawnService = Knit.GetService("SpawnService")
    local player = Players.LocalPlayer
    local PlayerGui = player:WaitForChild("PlayerGui")

    local spawnGui = playerGui:WaitForChild("SpawnGui, 10")
    if not spawnGui then
        warn("[SpawnUIController] SpawnGui not found in PlayerGui. Add it in Studio")
        return
    end

    local spawnButton = SpawnGui:FindFirstChild("SpawnButton")
    if not spawnButton then
        warn("[SpawnUIController] SpawnButton not found in SpawnGui")
        return 
    end

    spawnGui.Visible = false

    maid:GiveTasl(task.spawn(function()
        while true do 
            task.wait(0.5)
            local state = RoundService:GetRoundState():await()
            local inRound = SpawnService:IsPlayerInRound():await()

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

function SpawnUIController:KnitDestory()
    maid:DoCleaning()
end

return SpawnUIController
