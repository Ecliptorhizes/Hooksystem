--[[
	SpawnService - Round spawn placement and lobby return.
	RequestSpawn: teleport to random map spawn when round is in progress.
	DeployToGame: teleport to first spawn (e.g. after vote). ReturnToLobby: teleport to lobby.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)
local LobbyConfig = require(ReplicatedStorage.Core.Config.LobbyConfig)

local _MapService
local RoundService

local LOBBY_SPAWN_CFRAME = LobbyConfig.LOBBY_SPAWN_CFRAME

local SpawnService = Knit.CreateService({
    Name = "SpawnService",
    Client = {
        RequestSpawn = true,
        DeployToGame = true,
        ReturnToLobby = true,
        IsPlayerInRound = true,
    },
})

local playerInRound: { [number]: boolean } = {}
local currentMapId = "DevMap"

-- Returns 1 if player is in round, 0 otherwise (used by LobbyService for spawn placement)
function SpawnService:IsPlayerInRound(player: Player): number
    local inRound = playerInRound[player.UserId] == true
    return inRound and 1 or 0
end

-- RoundService calls this after map vote; sets which map spawns use
function SpawnService:SetCurrentMap(mapId: string)
    currentMapId = mapId
end

function SpawnService:GetCurrentMap(): string
    return currentMapId
end

-- Remove player from round tracking (e.g. on leave)
function SpawnService:CleanPlayerFromRound(player: Player)
    playerInRound[player.UserId] = nil
end

-- Clear all players from round (e.g. round end, teleport to lobby)
function SpawnService:ClearAllFromRound()
    playerInRound = {}
end

-- Teleport to random spawn point on current map. Only when round is InProgress.
function SpawnService:RequestSpawn(player: Player): (boolean, string?)
    local state = RoundService:GetRoundState()
    if state ~= "InProgress" then
        return false, "Round not in progress"
    end
    if playerInRound[player.UserId] then 
        return false, "Already Spawn"
    end
    local character = player.Character 
    if not character then 
        return false, "No Character"
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

-- Teleport to first spawn point (used after map vote / deploy to round)
function SpawnService:DeployToGame(player: Player): (boolean, string?)
    local character = player.Character
    if not character then
        return false, "No character"
    end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false, "No HumanoidRootPart"
    end

    local mapData = MapRegistry.Maps[currentMapId]
    local spawnPoints = mapData and mapData.spawnPoints or { CFrame.new(0, 5, 0) }
    local spawnCf = spawnPoints[1]

    hrp.CFrame = spawnCf
    playerInRound[player.UserId] = true

    return true, nil
end

-- Teleport to lobby spawn and remove from round
function SpawnService:ReturnToLobby(player: Player): (boolean, string?)
    local character = player.Character
    if not character then
        return false, "No character"
    end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false, "No HumanoidRootPart"
    end

    hrp.CFrame = LOBBY_SPAWN_CFRAME
    playerInRound[player.UserId] = nil

    return true, nil
end

function SpawnService.Client:RequestSpawn(player: Player)
    return self.Server:RequestSpawn(player)
end

function SpawnService.Client:DeployToGame(player: Player)
    return self.Server:DeployToGame(player)
end

function SpawnService.Client:ReturnToLobby(player: Player)
    return self.Server:ReturnToLobby(player)
end

function SpawnService.Client:IsPlayerInRound(player: Player)
    return self.Server:IsPlayerInRound(player)
end

-- KnitStart: resolve MapService, RoundService; clean up on PlayerRemoving
function SpawnService:KnitStart()
    _MapService = Knit.GetService("MapService")
    RoundService = Knit.GetService("RoundService")

    Players.PlayerRemoving:Connect(function(player)
        self:CleanPlayerFromRound(player)
    end)
end

return SpawnService
