local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)
local MapService = Knit.GetService("MapService")
local RoundService = Knit.GetService("RoundService")

local LOBBY_SPAWN_CFRAME = CFrame.new(0, 10, 0)

local SpawnService = Knit.CreateService({
    Name = "SpawnService",
    Client = {
        RequestSpawn = true,
        IsPlayerInRound = true,
    },
})

local playerInRound: { [number]: boolean } = {}
local currentMapId = "DevMap"

function SpawnServiceL:IsPlayerInRound(player: Player): boolean
    return playerInRound[player.UserId] == true 
end

function SpawnService:SetCurrentMap(mapId: string)
    currentMapId = mapId
end

function SpawnService:CleanPlayerFromRound(player: Player)
    playerInRound[player.UserId] = nil
end

function SpawnService:ClearAllFromRound()
    playerInRound = {}
end

function SpawnService:RequestSpawn(player: Player): (boolean, string?)
    local state = RoundService:GetRoundState()
    if state ~= "InProgress" then
        return false, "Round not in progress"
    end
    if playerInRound[player.UserId] then 
        return false, "Already Spawn"
    end
    local character = player.Character 
    if not Character then 
        return flase, "No Character"
    end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then 
        return false, "No HumanoidRootPart"
    end

    local mapData = MapRegistry.Maps[currentMapId]
    local spawnPoints = mapData and mapData.spawnPoints or { CFrame.new(0, 5, 0) }
    local spawnCf = spawnPoints[math.random(1, #spawnPoints)]

    hrp.CFrame = spawnCf 
    playerInRound[player.UserId] = true 

    return true, nil
end

function SpawnService.Client:RequestSpawn(player: Player)
    return self.Server:RequestSpawn(player)
end

function SpawnService.Client:IsPlayerInRound(player: Player)
    return self.Server:IsPlayerInRound(player)
end

function SpawnService:KnitStart()
    Players.PlayerRemoving:Connect(function(player)
        self:ClearPlayerFromRound(player)
    end)
end

return SpawnService
