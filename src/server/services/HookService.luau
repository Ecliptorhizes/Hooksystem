local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookService = Knit.CreateService({
    Name = "HookService",
    Client = {
        RequestHook = true,
        ReleaseHook = true,
    },
})

local playerHooks: { [number]: { RopeConstraint: RopeConstraint, Attachments: { Attachments } } } = {}

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
    targetAtt.WorldPosition = hitPosition
    targetAtt.Parent = Workspace

    local hrp = Instance.new("RopeConstraint")
    rope.Name = "PlayerHook"
    rope.Attachment0 = playerAtt
    rope.Attachment1 = targetAtt
    rope.Length = distance 
    rope.Visible = true 
    rope.Parent = Workspace

    playerHooks[player.UserId] = {
        RopeConstraint = rope,
        Attachments = { playerAtt, targetAtt },
    }

    return true, nil
end

function HookService:ReleaseHook(player: Player)
    local data = playerHooks[player.UserId]
    if not data then return end

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

function HookService:KnitInit()
    Players.PlayerRemoving:Connect(function(player)
        self:ReleaseHook(player)
    end)
end

return HookService
