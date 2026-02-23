local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LobbyConfig = require(ReplicatedStorage.Core.Config.LobbyConfig)

local LOBBY_SPAWN_CFRAME = LobbyConfig.LOBBY_SPAWN_CFRAME

local LobbyService = Knit.CreateService({
    Name = "LobbyService",
})

local function teleportToLobby(character)
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 2)
    if hrp then
        hrp.CFrame = LOBBY_SPAWN_CFRAME
    end
end

function LobbyService:KnitInit()

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            teleportToLobby(character)
        end)
        if player.Character then
            teleportToLobby(player.Character)
        end
    end)
end

function LobbyService:KnitStart()
    local PlayerDataService = Knit.GetService("PlayerDataService")

    for _, player in Players:GetPlayers() do
        PlayerDataService:LoadProfile(player)
        if player.Character then
            teleportToLobby(player.Character)
        end
    end

    Players.PlayerAdded:Connect(function(player)
        PlayerDataService:LoadProfile(player)
    end)
end

return LobbyService
