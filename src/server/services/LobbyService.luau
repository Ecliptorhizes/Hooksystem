--[[
	LobbyService
	Purpose:
	Enforce lobby placement for players outside the active round.

	Behavior:
	- Players flagged as in-round spawn on the active map.
	- Players not in-round are forced back to lobby spawn.
	- A short heartbeat guard prevents players from drifting out of lobby.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LobbyConfig = require(ReplicatedStorage.Core.Config.LobbyConfig)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)

local LOBBY_SPAWN_CFRAME = LobbyConfig.LOBBY_SPAWN_CFRAME
local LOBBY_RADIUS = 150

local LobbyService = Knit.CreateService({
    Name = "LobbyService",
})

local SpawnService

-- Move character to lobby spawn (LOBBY_SPAWN_CFRAME)
local function getHumanoidRootPart(character: Model): BasePart?
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 2)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end
	return nil
end

local function teleportToLobby(character: Model)
	local humanoidRootPart = getHumanoidRootPart(character)
	if not humanoidRootPart then
		return
	end
	humanoidRootPart.CFrame = LOBBY_SPAWN_CFRAME
end

-- Move character to a random spawn point for the current map (from MapRegistry)
local function teleportToMap(character: Model)
	local humanoidRootPart = getHumanoidRootPart(character)
	if not humanoidRootPart then
		return
	end

	local mapId = SpawnService:GetCurrentMap()
	local mapData = MapRegistry.Maps[mapId]
	local spawnPoints = (mapData and mapData.spawnPoints and #mapData.spawnPoints > 0) and mapData.spawnPoints
		or { CFrame.new(0, 5, 0) }
	local spawnCFrame = spawnPoints[math.random(1, #spawnPoints)]
	humanoidRootPart.CFrame = spawnCFrame
end

-- True if position is within LOBBY_RADIUS of lobby spawn
local function isInLobby(pos: Vector3): boolean
	return (pos - LOBBY_SPAWN_CFRAME.Position).Magnitude < LOBBY_RADIUS
end

function LobbyService:KnitInit()
end

-- KnitStart: wire CharacterAdded and Heartbeat; teleport to lobby or map based on round state
function LobbyService:KnitStart()
	SpawnService = Knit.GetService("SpawnService")

	local function isPlayerInRound(player: Player): boolean
		return (SpawnService:IsPlayerInRound(player) or 0) == 1
	end

	local function placeCharacter(player: Player, character: Model)
		if isPlayerInRound(player) then
			teleportToMap(character)
			return
		end
		teleportToLobby(character)
	end

	local function attachLobbyGuard(player: Player, character: Model)
		local checks = 0
		local connection: RBXScriptConnection?
		connection = RunService.Heartbeat:Connect(function()
			if not character.Parent then
				connection:Disconnect()
				return
			end

			checks += 1
			if checks > 30 then
				connection:Disconnect()
				return
			end

			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if not humanoidRootPart then
				return
			end
			if isPlayerInRound(player) then
				return
			end
			if isInLobby(humanoidRootPart.Position) then
				return
			end

			teleportToLobby(character)
		end)
	end

	local function bindPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			placeCharacter(player, character)
			attachLobbyGuard(player, character)
		end)
		if player.Character then
			placeCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return LobbyService
