local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)

local MovementController = Knit.CreateController({
    Name = "MovementController",
})

local maid = Maid.new()
local isSliding = false
local slideVelocity: Vector3? = nil

local SLIDE_FORCE = 80
local SLIDE_DECAY = 0.95

function MovementController:KnitStart()
    local player = game:GetService("Players").LocalPlayer

    maid:GiveTask(RunService.Heartbeat:Connect(function()
        local character = player.Character 
        if not character then return end 

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not hrp then return end

        local crouching = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        local moveDir = humanoid.MoveDirection

        if isSliding then 
            if slideVelocity then
                hrp.AssemblyLinearVelocity = slideVelocity
                slideVelocity = slideVelocity * SLIDE_DECAY
                if slideVelocity.Magnitude < 5 then 
                    isSliding = false
                    slideVelocity = nil
                end
            end
        elseif crouching and sprinting and moveDir.Magnitude > 0.1 then
            local function isHooked()
                for _, desc in character:GetDescendants() do
                    if desc:IsA("Attachment") and (desc.Name == "HookAttachment_Left" or desc.Name == "HookAttachment_Right") then
                        return true
                    end
                end
                return false
            end
            if isHooked() then return end
            isSliding = true
            slideVelocity = moveDir * SLIDE_FORCE
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        end
    end))
end

function MovementController:KnitDestory()
    maid:DoCleaning()
end

return MovementController
