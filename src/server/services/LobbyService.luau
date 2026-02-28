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

local function teleportToLobby(character)
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 2)
    if hrp then
        hrp.CFrame = LOBBY_SPAWN_CFRAME
    end
end

local function teleportToMap(character, _player)
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 2)
    if not hrp then return end
    local mapId = SpawnService:GetCurrentMap()
    local mapData = MapRegistry.Maps[mapId]
    local spawnPoints = mapData and mapData.spawnPoints or { CFrame.new(0, 5, 0) }
    local spawnCf = spawnPoints[math.random(1, #spawnPoints)]
    hrp.CFrame = spawnCf
end

local function isInLobby(pos: Vector3): boolean
    return (pos - LOBBY_SPAWN_CFRAME.Position).Magnitude < LOBBY_RADIUS
end

function LobbyService:KnitInit()
end

function LobbyService:KnitStart()
    SpawnService = Knit.GetService("SpawnService")
    local PlayerDataService = Knit.GetService("PlayerDataService")

    local function isInRound(p)
        return (SpawnService:IsPlayerInRound(p) or 0) == 1
    end

    local function handleCharacterSpawn(player: Player, character: Model)
        if isInRound(player) then
            teleportToMap(character, player)
        else
            teleportToLobby(character)
        end
    end

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            handleCharacterSpawn(player, character)
            local checkCount = 0
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if not character.Parent then
                    conn:Disconnect()
                    return
                end
                checkCount += 1
                if checkCount > 30 then
                    conn:Disconnect()
                    return
                end
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp and not isInRound(player) and not isInLobby(hrp.Position) then
                    teleportToLobby(character)
                end
            end)
        end)
        PlayerDataService:LoadProfile(player)
        if player.Character then
            handleCharacterSpawn(player, player.Character)
        end
    end)

    for _, player in Players:GetPlayers() do
        PlayerDataService:LoadProfile(player)
        if player.Character then
            handleCharacterSpawn(player, player.Character)
        end
    end
end

return LobbyService
