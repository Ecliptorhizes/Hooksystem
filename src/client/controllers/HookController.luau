--[[
	HookController
	Purpose:
	Translate local player input into HookService requests and maintain hook-related HUD feedback.

	Input flow:
	- Q / E: fire or release left/right hooks
	- A / D: swing input
	- S: reel out / braking input
	- Space: boost while hooked
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookController = Knit.CreateController({
    Name = "HookController",
})

local maid = Maid.new()
local hookLeft = false
local hookRight = false
local spaceHeld = false
local sHeld = false
local reelForce: number? = 0
local lastSwingForce: number? = nil
local lastBoostTime = 0
local BOOST_DEBOUNCE = 0.12

--[[
	Returns true when humanoid state is one of the ragdoll-like states that
	can break grapple flow if not corrected.
]]
local function isRagdollState(state: Enum.HumanoidStateType): boolean
	return state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Physics
end

--[[
	Computes hook origin from left/right arm offset relative to HumanoidRootPart.
]]
local function getArmOrigin(character: Model, hrp: BasePart, isLeft: boolean): Vector3
	local armPart = character:FindFirstChild(isLeft and "Left Arm" or "Right Arm")
	if not armPart or not armPart:IsA("BasePart") then
		return hrp.Position
	end
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local forward = look * (HookConfig.HookArmForwardOffset or 1.2)
	local side = right * ((HookConfig.HookArmSideOffset or 0.4) * (isLeft and -1 or 1))
	return armPart.Position + forward + side
end

--[[
	Resolves Knit services required by this controller.
]]
function HookController:KnitInit()
    self.HookService = Knit.GetService("HookService")
end

--[[
	Attempts to fire a hook on the specified side.
	Uses projectile mode or direct attach mode based on HookConfig.
]]
function HookController:TryHook(isLeft: boolean)
    local player = Players.LocalPlayer
    local character = player.Character
    local camera = Workspace.CurrentCamera
    if not character or not camera then return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }

    local mouseLoc = UserInputService:GetMouseLocation()
    local mouseRay = camera:ScreenPointToRay(mouseLoc.X, mouseLoc.Y)
    local rayResult = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction.Unit * HookConfig.MaxRange, params)

    local armOrigin = getArmOrigin(character, hrp, isLeft)
	local direction: Vector3 = rayResult and (rayResult.Position - armOrigin).Unit or mouseRay.Direction.Unit

    if HookConfig.UseProjectilePhase then
        local success, err = self.HookService:RequestFireHook(armOrigin, direction, isLeft):await()
        if success then
			if isLeft then
				hookLeft = true
			else
				hookRight = true
			end
            reelForce = 0
        elseif err then
            warn("[HookController] Hook failed:", err)
        end
        return
    end
    if not rayResult then return end

    local distFromArm = (rayResult.Position - armOrigin).Magnitude
    if distFromArm > HookConfig.MaxRange then return end

    local success, err = self.HookService:RequestHook(rayResult.Instance, rayResult.Position, isLeft):await()
    if success then
		if isLeft then
			hookLeft = true
		else
			hookRight = true
		end
        reelForce = 0
    elseif err then
        warn("[HookController] Hook failed:", err)
    end
end

--[[
	Binds input actions, HUD updates, and heartbeat synchronization for hook state.
]]
function HookController:KnitStart()
    local player = Players.LocalPlayer
    local camera = Workspace.CurrentCamera
    ContextActionService:BindActionAtPriority("HookSpaceAction", function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        if hookLeft or hookRight then
            if not sHeld then
                spaceHeld = true
                lastBoostTime = tick()
                self.HookService:RequestBoost(hookLeft):await()
            end
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end, false, 10000, Enum.KeyCode.Space)
    local playerGui = player:WaitForChild("PlayerGui")

    local hookDistanceGui = playerGui:FindFirstChild("hookDistanceGui")
    local distanceLabel: TextLabel? = nil
    local gasLabel: TextLabel? = nil
    if hookDistanceGui then
        distanceLabel = hookDistanceGui:FindFirstChild("DistanceLabel") :: TextLabel?
        gasLabel = hookDistanceGui:FindFirstChild("GasLabel") :: TextLabel?
    end
    if hookDistanceGui then
        hookDistanceGui.Visible = true
    end

    if gasLabel then
        local hookService = self.HookService
        maid:GiveTask(task.spawn(function()
            while true do
                task.wait(0.25)
                local gas = hookService:GetGas():await()
                gasLabel.Text = "Gas: " .. math.floor(gas) .. "%"
            end
        end))
    end

    maid:GiveTask(RunService.RenderStepped:Connect(function()
        local character = player.Character
        if not character or not camera then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }

        local mouseLoc = UserInputService:GetMouseLocation()
        local mouseRay = camera:ScreenPointToRay(mouseLoc.X, mouseLoc.Y)
        local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction.Unit * HookConfig.MaxRange, params)

        if distanceLabel then
            if result then
                local armOriginLeft = getArmOrigin(character, hrp, true)
                local armOriginRight = getArmOrigin(character, hrp, false)
                local distLeft = (result.Position - armOriginLeft).Magnitude
                local distRight = (result.Position - armOriginRight).Magnitude
                local dist = math.min(distLeft, distRight)
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

        if input.KeyCode == Enum.KeyCode.Q then
            self:TryHook(true)
        elseif input.KeyCode == Enum.KeyCode.E then
            self:TryHook(false)
        elseif input.KeyCode == Enum.KeyCode.Space then
            spaceHeld = true
            if (hookLeft or hookRight) and not sHeld and (tick() - lastBoostTime) > BOOST_DEBOUNCE then
                lastBoostTime = tick()
                self.HookService:RequestBoost(hookLeft):await()
            end
        elseif input.KeyCode == Enum.KeyCode.S then
            sHeld = true
        elseif input.KeyCode == Enum.KeyCode.A and (hookLeft or hookRight) then
            lastSwingForce = -1
            self.HookService:SetSwingForce(-1):await()
        elseif input.KeyCode == Enum.KeyCode.D and (hookLeft or hookRight) then
            lastSwingForce = 1
            self.HookService:SetSwingForce(1):await()
        end
    end))

    maid:GiveTask(UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Q then
            self.HookService:ReleaseHook(true):await()
            hookLeft = false
            reelForce = 0
            lastSwingForce = nil
        elseif input.KeyCode == Enum.KeyCode.E then
            self.HookService:ReleaseHook(false):await()
            hookRight = false
            reelForce = 0
            lastSwingForce = nil
        elseif input.KeyCode == Enum.KeyCode.Space then
            spaceHeld = false
            if reelForce and reelForce ~= 0 then
                reelForce = sHeld and -(HookConfig.ReelForceRange or 0.8) or 0
                self.HookService:SetReelForce(reelForce):await()
            end
        elseif input.KeyCode == Enum.KeyCode.S then
            sHeld = false
            if reelForce and reelForce ~= 0 then
                reelForce = 0
                self.HookService:SetReelForce(0):await()
            end
        elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then
            local swing = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                swing = 1
            elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
                swing = -1
            end
            lastSwingForce = swing
            self.HookService:SetSwingForce(swing):await()
        end
    end))
    maid:GiveTask(RunService.Heartbeat:Connect(function()
        local character = player.Character
        if not character then return end
        local isHooked = false
        for _, desc in character:GetDescendants() do
            if desc:IsA("Attachment") and (desc.Name == "HookAttachment_Left" or desc.Name == "HookAttachment_Right") then
                isHooked = true
                break
            end
        end
        if not isHooked then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local currentState = humanoid:GetState()
            if isRagdollState(currentState) then
                humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
            end
        end
    end))

    maid:GiveTask(RunService.Heartbeat:Connect(function()
        if not (hookLeft or hookRight) then return end
        local swing = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            swing = 1
        elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
            swing = -1
        end
        if lastSwingForce ~= swing then
            lastSwingForce = swing
            self.HookService:SetSwingForce(swing):await()
        end
        local targetReel: number
        if sHeld then
            targetReel = -(HookConfig.ReelForceRange or 0.8)
        else
            targetReel = 0
        end
        if (reelForce or 0) ~= targetReel then
            reelForce = targetReel
            self.HookService:SetReelForce(reelForce):await()
        end
        if spaceHeld and (tick() - lastBoostTime) > 0.17 then
            lastBoostTime = tick()
            self.HookService:RequestBoost(hookLeft):await()
        end
    end))
end

--[[
	Releases active hooks and disconnects runtime connections.
]]
function HookController:KnitDestroy()
    ContextActionService:UnbindAction("HookSpaceAction")
    if hookLeft then
        self.HookService:ReleaseHook(true):await()
    end
    if hookRight then
        self.HookService:ReleaseHook(false):await()
    end
    maid:DoCleaning()
end

return HookController
