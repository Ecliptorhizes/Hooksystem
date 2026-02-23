local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ShopController = Knit.CreateController({
    Name = "ShopController",
})

function ShopController:KnitInit()
    self.ShopService = Knit.GetService("ShopService")
end

function ShopController:GetCatalog()
    return self.ShopService:GetShopCatalog():await()
end

function ShopController:PurchaseItem(itemId: string): (boolean, string?)
    return self.ShopService:PurchaseItem(itemId):await()
end

return ShopController
