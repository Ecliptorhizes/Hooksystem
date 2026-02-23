local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local RewardService = Knit.CreateService({
    Name = "RewardService",
})

local PlayerDataService

function RewardService:KnitStart()
    PlayerDataService = Knit.GetService("PlayerDataService")
end

local REWARD_CRITERIA = {
    { headshots = 5, weaponUnlock = "BasicSniper" },
    { headshots = 10, weaponUnlock = "HyperwaveSniper" },
    { headshots = 15, weaponUnlock = "MoltenSniper" },
    { survivalMinutes = 5, currency = 100},
}

function RewardService:ProcessRoundRewards(playerStats: { [number]: any })
    for userId, stats in playerStats do 
        local player = Players:GetPlayerByUserId(userId)
        if not player then continue end 

        local profile = PlayerDataService:GetProfile(player)
        if not profile then continue end 
        
        for _, criteria in REWARD_CRITERIA do 
            if criteria.weaponUnlock then 
                local needed = criteria.headshots or 0
                if stats.headshots >= needed and not PlayerDataService:HasWeapon(player, criteria.weaponUnlock) then
                    PlayerDataService:AddWeapon(player, criteria.weaponUnlock)
                end
            end
            if criteria.currency then
                local neededMinutes = criteria.survivalMinutes or 0
                local survivalSeconds = stats.bestTimeSeconds or 0
                if survivalSeconds >= neededMinutes * 60 and (stats.deaths or 0) == 0 then 
                    PlayerDataService:AddCurrency(player, criteria.currency)
                end
            end
        end
    end
end

return RewardService
