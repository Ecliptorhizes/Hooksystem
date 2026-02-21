local ServiceStorage = game:GetService("ServiceStorage")
local Player = game:GetService("Players")

local ProfileService = require(ServerStorage.ServerPackages.ProfileService)

local ProfileTemplate = {
    Currency = 0,
    OwnedWeapons = {},
    OwnedSkins = {},
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData_v1", ProfileTemplate)
local Profiles: { [number]: any } = {}

local PlayerDataService = Knit.CreateService({
    Name = "PlayerDataService",
})

function PlayerDataService:KnitInit()
    Players.PlayerRemoving:Connect(function(player)
        local profile = Profiles[player.UserId]
        if profile then
            profile:Release()
            Profiles[player.UserId] = nil
        end
    end)
end

function PlayerDataService:LoadProfile(player: Player): (any?, string?)
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
    if not profile then 
        return nil, "Failed to load"
    end
    Profiles[player.UserId] = profile 
    return profile, nil 
end

function PlayerDataService:GetProfile(player: Player)
    return Profiles[player.UserId]
end

function PlayerDataService:GetCurrency(player: Player): number
    local profile = Profiles[player.UserId]
    return profile and profile.Data.Currency or 0
end

function PlayerDataService:AddWeapon(player: Player, itemId: string): boolean
    local profile = Profiles[player.UserId]
    if not profile then return false end
    profile.Data.OwnedWeapons[itemId] = true
    return true
end

function PlayerDataService:AddSkin(player: Player, itemId: string): boolean 
    local profile = Profiles[player.UserId]
    if not profile then return false end
    profile.Data.OwnedSkins[itemId] = true 
    return true 
end

function PlayerDataService:HasWeapon(player: Player, itemId: string): boolean 
    local profile = Profiles[player.UserId]
    if not profile then return false end
    return profile.Data.OwnedWeapons[itemId] == true
end

function PlayerDataService:hasSkin(player: Player, itemId: string): boolean
    local profile = Profiles[player.UserId]
    if not profile then return false end
    return profile.Data.OwnedSkins[itemId] == true 
end

function PlayerDataService:SpendCurrency(player: Player, amount: number): boolean
    local profile = Profiles[player.UserId]
    if not profile or profile.Data.Currency < amount then return false end 
    profile.Data.Currency -= amount
    return true
end

return PlayerDataService
