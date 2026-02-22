local Players = game:GetService("Players")

local Knit = require(...) -- Later get it from ReplicatedStorage
local PlayerDataService = Knit.GetService("PlayerDataService")

local LOBBY_SPAWN_CFRAME = CFrame.new(0, 10, 0) -- will later adjust it at the right location

local LobbyService = Knit.CreateService({
    Name = "LobbyService",
})

function LobbyService:KnitStart()
    Players.PlayerAdded:Connect(function(player)
        PlayerDataService:LoadProfile(player)
        player.CharacterAdded:Connect(function(character)
            local hrp = character:WaitForChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = LOBBY_SPAWN_CFRAME
            end
        end)

        if player.Character then 
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then 
                hrp.CFrame = LOBBY_SPAWN_CFRAME
            end
        end
    end)
    for _, player in Players:GetPlayers() do 
        task.defer(function()
            PlayerDataService:LoadProfile(player)
        end)
    end
end

return LobbyService
