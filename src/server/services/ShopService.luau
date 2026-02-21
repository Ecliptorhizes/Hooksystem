local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ItemRegistry = require(ReplicatedStorage.Shared.Core.ItemRegistry)
local PlayerDataService = Knit.GetService("PlayerDataService")

local ShopService = Knit.CreateService({
    Name = "ShopService",
    Client = {},
})

function ShopService.Client:GetShopCatalog(player: Player)
    return ItemRegistry.getCatalog()
end

function ShopService.Client:PurchaseItem(player: Player, itemId: string): (boolean, string?)
    local item = ItemRegistry.getItem(itemId)
    if not item then 
        return false, "Invalid item"
    end
    if PlayerDataService:HasWeapon(player, itemId) or PlayerDataService:HasSkin(player, itemId) then 
        return false, "Already owned"
    end
    if not PlayerDataService:SpendCurrency(player, item.Price) then 
        return false, "Not enough currency"
    end
    if item.itemType == "weapon" then 
        PlayerDataService:AddWeapon(player, itemId)
    else
        PlayerDataService:AddSkin(player, itemId)
    end
    return true, nil
end

return ShopService
