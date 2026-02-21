-- This is only a precoded script, NOTHING ELSE @Ecliptorhize :)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Packages.Maid)

local ShopUIController = Knit.CreateController({
    Name = "ShopUIController",
})

local maid = Maid.new()

function ShopUIController:KnitStart()
    local ShopController = Knit.GetController("ShopController")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local shopGui = playerGui:WaitForChild("ShopGui", 10)
    if not shopGui then
        warn("[ShopUIController] ShopGui not found in PlayerGui. Add it in Studio")
        return
    end

    local catalog = ShopController:GetCatalog()
    local catalogFrame = shopGui:FindFirstChild("Catalog")
    local itemTemplate = shopGui:FindFirstChild("itemTemplate")
    if catalogFrame and itemTemplate then 
        itemTemplate.Parent = nil
        for _, item in catalog do 
            local clone = itemTemplate:Clone()
            clone.Name = item.id
            clone.Visible = true
            local nameLabel = clone:FindFirstChild("ItemName")
            local priceLabel = clone:FindFirstChild("Price")
            if nameLabel then nameLabel.Text = item.name end
            if priceLabel then priceLabel.Text = tostring(item.price) end

            local buyBtn = clone:FindFirstChild("BuyButton")
            if buyBtn then
                maid:GiveTask(buyBtn.MouseButton1Click:Connect(function()
                    local success, err = ShopController:PurchaseItem(item.id)
                    if success then 
                        print("Purchased:", item.name)
                        buyBtn.Text = "Owned"
                        buyBtn.Active = false
                    else
                        warn("Purchase failed:", err)
                    end
                end))
            end
            clone.Parent = catalogFrame
        end
    end

    local openBtn = shopGui:FindFirstChild("OpenShopButton")
    local shopFrame = shopGui:FindFirstChild("shopFrame")
    if openBtn and shopFrame then
        shopFrame.Visible = false
        maid:GiveTask(openBtn.MouseButton1Click:Connect(function()
            shopFrame.Visible = not shopFrame.Visible
        end))
    end
end

function ShopUIController:KnitDestroy()
    maid:DoCleaning()
end

return ShopUIController
                
