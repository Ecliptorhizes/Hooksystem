local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookService = Knit.CreateService({
    Name = "HookService",
    Client = {
        RequestHook = true,
        ReleaseHook = true,
        RequestJump = true,
        RequestBoost = true,
    },
})

local playerHooks: { [number]: { RopeConstraint: RopeConstraint, BeamPart: BasePart, Attachments: { Attachment }, LinearVelocity: LinearVelocity, LastTick: number?, HeartbeatConn: RBXScriptConnection?, JumpBoostEndTime: number? } } = {}

function HookService:RequestHook(player:Player, targetPart: BasePart, hitPosition: Vector3): (boolean, string?)
    if not player.Character then
        return false, "No character"
    end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then 
        return false, "No HumanoidRootPart"
    end
    if not targetPart or not targetPart:IsA("BasePart") then 
        return false, "Invalid target"
    end

    local distance = (hitPosition - hrp.Position).Magnitude
    if distance > HookConfig.MaxRange then 
        return false, "Too far"
    end

    if playerHooks[player.UserId] then 
        self:ReleaseHook(player)
    end

    local playerAtt = Instance.new("Attachment")
    playerAtt.Name = "HookAttachment"
    playerAtt.Parent = hrp 

    local targetAtt = Instance.new("Attachment")
    targetAtt.Name = "HookTarget"
    targetAtt.Position = targetPart.CFrame:PointToObjectSpace(hitPosition)
    targetAtt.Parent = targetPart

    local rope = Instance.new("RopeConstraint")
    rope.Name = "PlayerHook"
    rope.Attachment0 = playerAtt
    rope.Attachment1 = targetAtt
    rope.Length = distance
    rope.Visible = false
    rope.Parent = Workspace

    local beam = Instance.new("Part")
    beam.Name = "HookBeam"
    beam.Anchored = true
    beam.CanCollide = false
    beam.CanQuery = false
    beam.CanTouch = false
    beam.Material = Enum.Material.Neon
    beam.Color = Color3.fromRGB(100, 200, 255)
    beam.Size = Vector3.new(HookConfig.BeamThickness, distance, HookConfig.BeamThickness)
    beam.CFrame = CFrame.lookAt(hrp.Position, targetAtt.WorldPosition) * CFrame.Angles(-math.rad(90), 0, 0)
    beam.Position = (hrp.Position + targetAtt.WorldPosition) / 2
    beam.Parent = Workspace

    local linearVel = Instance.new("LinearVelocity")
    linearVel.Name = "HookBoost"
    linearVel.Attachment0 = playerAtt
    linearVel.MaxForce = math.huge
    linearVel.VectorVelocity = Vector3.zero
    linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVel.Parent = hrp

    playerHooks[player.UserId] = {
        RopeConstraint = rope,
        BeamPart = beam,
        Attachments = { playerAtt, targetAtt },
        LinearVelocity = linearVel,
        LastTick = tick(),
    }

    local conn = RunService.Heartbeat:Connect(function()
        local data = playerHooks[player.UserId]
        if not data or not player.Character or hrp.Parent ~= player.Character then
            if data and data.HeartbeatConn then
                data.HeartbeatConn:Disconnect()
            end
            return
        end
        local now = tick()
        local delta = now - (data.LastTick or now)
        data.LastTick = now
        local anchorPos = targetAtt.WorldPosition
        local toAnchor = (anchorPos - hrp.Position).Unit
        local baseVel = toAnchor * HookConfig.BoostForce
        if data.JumpBoostEndTime and tick() < data.JumpBoostEndTime then
            baseVel = baseVel + Vector3.new(0, HookConfig.JumpForce, 0)
        else
            data.JumpBoostEndTime = nil
        end
        data.LinearVelocity.VectorVelocity = baseVel
        data.RopeConstraint.Length = math.max(5, data.RopeConstraint.Length - HookConfig.RopeShortenSpeed * delta)
        local len = (anchorPos - hrp.Position).Magnitude
        data.BeamPart.Size = Vector3.new(HookConfig.BeamThickness, len, HookConfig.BeamThickness)
        data.BeamPart.CFrame = CFrame.lookAt(hrp.Position, anchorPos) * CFrame.Angles(-math.rad(90), 0, 0)
        data.BeamPart.Position = (hrp.Position + anchorPos) / 2
    end)
    playerHooks[player.UserId].HeartbeatConn = conn

    return true, nil
end

function HookService:RequestJump(player: Player): boolean
    local data = playerHooks[player.UserId]
    if not data or not player.Character then return false end
    data.JumpBoostEndTime = tick() + 0.2
    return true
end

function HookService:RequestBoost(player: Player): boolean
    local data = playerHooks[player.UserId]
    if not data or not player.Character then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local targetAtt = data.Attachments[2]
    local anchorPos = targetAtt.WorldPosition
    local toAnchor = (anchorPos - hrp.Position).Unit
    local impulse = toAnchor * HookConfig.JumpBoostForce
    hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + impulse
    return true
end

function HookService:ReleaseHook(player: Player)
    local data = playerHooks[player.UserId]
    if not data then return end

    if data.HeartbeatConn then
        data.HeartbeatConn:Disconnect()
    end
    if data.LinearVelocity then
        data.LinearVelocity:Destroy()
    end
    if data.BeamPart then
        data.BeamPart:Destroy()
    end
    data.RopeConstraint:Destroy()
    for _, att in data.Attachments do
        att:Destroy()
    end
    playerHooks[player.UserId] = nil
end

function HookService.Client:RequestHook(player: Player, targetPart: BasePart, hitPosition: Vector3)
    return self.Server:RequestHook(player, targetPart, hitPosition)
end

function HookService.Client:ReleaseHook(player: Player)
    self.Server:ReleaseHook(player)
end

function HookService.Client:RequestJump(player: Player)
    return self.Server:RequestJump(player)
end

function HookService.Client:RequestBoost(player: Player)
    return self.Server:RequestBoost(player)
end

function HookService:KnitInit()
    Players.PlayerRemoving:Connect(function(player)
        self:ReleaseHook(player)
    end)
end

return HookService
