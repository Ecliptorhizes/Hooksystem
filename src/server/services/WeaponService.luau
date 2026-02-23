local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ItemRegistry = require(ReplicatedStorage.Core.ItemRegistry)

local PlayerDataService
local RoundService

local RAYCAST_DISTANCE = 1000

local WeaponService = Knit.CreateService({
    Name = "WeaponService",
    Client = {
        FireSniper = true,
        GetEquippedSniper = true,
    },

})

function WeaponService:KnitStart()
    PlayerDataService = Knit.GetService("PlayerDataService")
    RoundService = Knit.GetService("RoundService")
end

function WeaponService.Client:FireSniper(player: Player, origin: Vector3, direction: Vector3): (boolean, string?)
    local equipped = self.Server:GetEquippedSniper(player)
    if not equipped then 
        return false, "No sniper equipped"
    end

    if not PlayerDataService:HasWeapon(player, equipped) then 
        return false, "Weapon not owned"
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character or {} }

    local result = Workspace:Raycast(origin, direction.Unit * RAYCAST_DISTANCE, params)
    if not result then 
        return true, nil 
    end

    local hitPart = result.Instance 
    local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
    if not hitCharacter then 
        return true, nil 
    end

    local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
    local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
    if not humanoid or not hitPlayer or hitPlayer == player then 
        return true, nil 
    end

    local isHeadshot = hitPart.Name == "Head"
    RoundService:RecordKill(player, hitPlayer, isHeadshot)
    humanoid:TakeDamage(1000)

    return true, nil
end

function WeaponService:GetEquippedSniper(player: Player): string?
    return PlayerDataService:GetEquippedSniper(player)
end

function WeaponService.Client:GetEquippedSniper(player: Player)
    return self.Server:GetEquippedSniper(player)
end

return WeaponService
