local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Packages.Maid)

local WeaponController = Knit.CreateController({
    Name = "WeaponController",
})

local maid = Maid.new()
local currentSlot: "melee" | "sniper" = "sniper"

function WeaponController:KnitInit()
    self.WeaponController = Knit.GetService("WeaponService")
end

function WeaponController:KnitStart()
    local player = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcesseed)
        if gameProcessed then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then 
            if currentSlot == "sniper" then 
                self:FireSniper()
            else
                self:SlashMelee()
            end
        elseif input.UserInputType == Enum.UserInputType.MouseWheelForward then 
            currentSlot = "sniper"
        elseif input.UserInputType == Enum.UserInputType.MouseWheelBackward then 
            currentSlot = "melee"
        end
    end))
end

function WeaponController:FireSniper()
    local player = Players.LocalPlayer
    local character = player.Character
    local camera = workspace.CurrentCamera
    if not character or not camera then return end 

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not hrp or not head then return end 

    local origin = head.Position
    local direction = (camera.CFrame.LookVector).Unit

    self.WeaponService:FireSniper(origin, direction):await()
end

function WeaponController:SlashMelee()
    -- I will be adding in melee logic here
end

function WeaponController:KnitDestroy()
    maid:DoCleaning()
end

return WeaponController
