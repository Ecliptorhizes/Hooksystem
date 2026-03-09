--[[
	SpawnService
	Purpose:
	Coordinate lobby and in-round player spawn placement.

	Responsibilities:
	- Track whether a player is currently in the active round.
	- Teleport players to map spawns during round flow.
	- Return players to lobby spawn when they leave the round.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)
local LobbyConfig = require(ReplicatedStorage.Core.Config.LobbyConfig)

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

--[[
	Resolves and validates the player's HumanoidRootPart for teleport operations.
]]
local function getHumanoidRootPart(player: Player): (BasePart?, string?)
	local character = player.Character
	if not character then
		return nil, "No character"
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		return nil, "No HumanoidRootPart"
	end
	return humanoidRootPart, nil
end

--[[
	Returns spawn points for the currently selected map.
	Falls back to a safe default when registry data is unavailable.
]]
local function getSpawnPointsForCurrentMap(): { CFrame }
	local mapData = MapRegistry.Maps[currentMapId]
	if mapData and mapData.spawnPoints and #mapData.spawnPoints > 0 then
		return mapData.spawnPoints
	end
	-- Safe fallback spawn if map metadata is missing.
	return { CFrame.new(0, 5, 0) }
end

--[[
	Returns 1 if the player is currently marked as in-round; otherwise returns 0.
]]
function SpawnService:IsPlayerInRound(player: Player): number
    local inRound = playerInRound[player.UserId] == true
    return inRound and 1 or 0
end

--[[
	Sets the active map id used for subsequent spawn placement.
]]
function SpawnService:SetCurrentMap(mapId: string)
    currentMapId = mapId
end

--[[
	Returns the active map id used by spawn logic.
]]
function SpawnService:GetCurrentMap(): string
    return currentMapId
end

--[[
	Clears the in-round flag for a single player.
]]
function SpawnService:CleanPlayerFromRound(player: Player)
    playerInRound[player.UserId] = nil
end

--[[
	Clears all in-round tracking state (used at round transitions).
]]
function SpawnService:ClearAllFromRound()
    playerInRound = {}
end

--[[
	Places a player at a random spawn on the active map when round is in progress.
]]
function SpawnService:RequestSpawn(player: Player): (boolean, string?)
	local roundState = RoundService:GetRoundState()
	if roundState ~= "InProgress" then
		return false, "Round not in progress"
	end
	if playerInRound[player.UserId] then
		return false, "Already spawned"
	end

	local humanoidRootPart, err = getHumanoidRootPart(player)
	if not humanoidRootPart then
		return false, err
	end

	local spawnPoints = getSpawnPointsForCurrentMap()
	local spawnCFrame = spawnPoints[math.random(1, #spawnPoints)]
	humanoidRootPart.CFrame = spawnCFrame
	playerInRound[player.UserId] = true
	return true, nil
end

--[[
	Places a player at the primary spawn point for round deployment.
]]
function SpawnService:DeployToGame(player: Player): (boolean, string?)
	local humanoidRootPart, err = getHumanoidRootPart(player)
	if not humanoidRootPart then
		return false, err
	end

	local spawnPoints = getSpawnPointsForCurrentMap()
	humanoidRootPart.CFrame = spawnPoints[1]
	playerInRound[player.UserId] = true
	return true, nil
end

--[[
	Returns a player to lobby spawn and clears in-round tracking.
]]
function SpawnService:ReturnToLobby(player: Player): (boolean, string?)
	local humanoidRootPart, err = getHumanoidRootPart(player)
	if not humanoidRootPart then
		return false, err
	end

	humanoidRootPart.CFrame = LOBBY_SPAWN_CFRAME
	playerInRound[player.UserId] = nil
	return true, nil
end

--[[
	Client RPC proxy for RequestSpawn.
]]
function SpawnService.Client:RequestSpawn(player: Player)
    return self.Server:RequestSpawn(player)
end

--[[
	Client RPC proxy for DeployToGame.
]]
function SpawnService.Client:DeployToGame(player: Player)
    return self.Server:DeployToGame(player)
end

--[[
	Client RPC proxy for ReturnToLobby.
]]
function SpawnService.Client:ReturnToLobby(player: Player)
    return self.Server:ReturnToLobby(player)
end

--[[
	Client RPC proxy for IsPlayerInRound.
]]
function SpawnService.Client:IsPlayerInRound(player: Player)
    return self.Server:IsPlayerInRound(player)
end

--[[
	Initializes service dependencies and player cleanup hooks.
]]
function SpawnService:KnitStart()
	RoundService = Knit.GetService("RoundService")
	Players.PlayerRemoving:Connect(function(player)
		self:CleanPlayerFromRound(player)
	end)
end

return SpawnService
