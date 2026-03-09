--[[
	MovementController
	Purpose:
	Apply local slide movement when crouch+sprint input is active.
	Slide is disabled while hook attachments exist to avoid conflicting force models.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

--[[
	Returns true when any hook attachment exists on the character.
	Sliding is disabled in this state to avoid conflicting movement behaviors.
]]
local function isCharacterHooked(character: Model): boolean
	for _, descendant in character:GetDescendants() do
		if not descendant:IsA("Attachment") then
			continue
		end
		if descendant.Name == "HookAttachment_Left" or descendant.Name == "HookAttachment_Right" then
			return true
		end
	end
	return false
end

--[[
	Initializes heartbeat-driven slide behavior.
]]
function MovementController:KnitStart()
	local player = Players.LocalPlayer

	maid:GiveTask(RunService.Heartbeat:Connect(function()
		local character = player.Character
		if not character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not humanoidRootPart then
			return
		end

		local isCrouching = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		local isSprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		local moveDirection = humanoid.MoveDirection

		if isSliding then
			if not slideVelocity then
				return
			end
			humanoidRootPart.AssemblyLinearVelocity = slideVelocity
			slideVelocity = slideVelocity * SLIDE_DECAY
			if slideVelocity.Magnitude >= 5 then
				return
			end
			isSliding = false
			slideVelocity = nil
			return
		end

		if not isCrouching or not isSprinting or moveDirection.Magnitude <= 0.1 then
			return
		end
		if isCharacterHooked(character) then
			return
		end

		isSliding = true
		slideVelocity = moveDirection * SLIDE_FORCE
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end))
end

--[[
	Disposes all movement controller connections and tasks.
]]
function MovementController:KnitDestroy()
	maid:DoCleaning()
end

return MovementController
