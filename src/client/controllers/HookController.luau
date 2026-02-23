local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookController = Knit.CreateController({
    Name = "HookController",
})

local maid = Maid.new()
local isHooked = false
local jumpState = 0
local jumpStateResetAt = 0

function HookController:KnitInit()
    self.HookService = Knit.GetService("HookService")
end

function HookController:TryHook()
    local player = Players.LocalPlayer
    local character = player.Character
    local camera = Workspace.CurrentCamera
    if not character or not camera then return end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }

    local origin = camera.CFrame.Position
    local direction = camera.CFrame.LookVector * HookConfig.MaxRange
    local result = Workspace:Raycast(origin, direction, params)

    if not result then return end

    local dist = (result.Position - character:FindFirstChild("HumanoidRootPart").Position).Magnitude
    if dist > HookConfig.MaxRange then return end

    local success, err = self.HookService:RequestHook(result.Instance, result.Position):await()
    if success then
        isHooked = true
        jumpState = 0
    elseif err then
        warn("[HookController] Hook failed:", err)
    end
end

function HookController:KnitStart()
    local player = Players.LocalPlayer
    local camera = Workspace.CurrentCamera
    local playerGui = player:WaitForChild("PlayerGui")

    local hookDistanceGui = playerGui:FindFirstChild("hookDistanceGui")
    local distanceLabel: TextLabel? = nil
    if hookDistanceGui then
        distanceLabel = hookDistanceGui:FindFirstChild("DistanceLabel") :: TextLabel?
    end
    if hookDistanceGui then
        hookDistanceGui.Visible = true
    end

    maid:GiveTask(RunService.RenderStepped:Connect(function()
        local character = player.Character 
        if not character or not camera then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }

        local origin = camera.CFrame.Position
        local direction = camera.CFrame.LookVector * HookConfig.MaxRange
        local result = Workspace:Raycast(origin, direction, params)

        if distanceLabel then
            if result then
                local dist = (result.Position - hrp.Position).Magnitude
                distanceLabel.Text = math.floor(dist) .. " studs"
                distanceLabel.TextColor3 = (dist <= HookConfig.MaxRange)
                    and Color3.fromRGB(255, 255, 255)
                    or Color3.fromRGB(255, 0, 0)
            else
                distanceLabel.Text = "---"
                distanceLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            end
        end
    end))

    maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end

            if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
                if not isHooked then
                    self:TryHook()
                end
            elseif input.KeyCode == Enum.KeyCode.Space and isHooked then
                if tick() > jumpStateResetAt then
                    jumpState = 0
                end
                if jumpState == 0 then
                    self.HookService:RequestJump():await()
                    jumpState = 1
                    jumpStateResetAt = tick() + HookConfig.JumpBoostWindow
                else
                    self.HookService:RequestBoost():await()
                    jumpState = 0
                end
            end
        end))

    maid:GiveTask(UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
                if isHooked then
                    self.HookService:ReleaseHook():await()
                    isHooked = false
                    jumpState = 0
                end
            end
        end))
end

function HookController:KnitDestroy()
    if isHooked then
        self.HookService:ReleaseHook():await()
    end
    maid:DoCleaning()
end

return HookController
