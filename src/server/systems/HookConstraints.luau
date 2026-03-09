--[[
	HookConstraints
	Purpose:
	Create and clean up runtime constraint objects, attachments, and force instances.
	Supports RopeConstraint, SpringConstraint, arm VectorForce, and velocity movers.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookTypes = require(script.Parent.HookTypes)
type HookData = HookTypes.HookData

local sharedWorldAnchor: BasePart? = nil

local function getWorldAnchor(): BasePart
	if not sharedWorldAnchor or not sharedWorldAnchor.Parent then
		local part = Instance.new("Part")
		part.Name = "HookVelWorldAnchor"
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Transparency = 1
		part.Parent = Workspace
		sharedWorldAnchor = part
	end
	return sharedWorldAnchor :: BasePart
end

-- Clean up all runtime instances for a single hook attachment.
local function releaseHookData(hookData: HookData)
	if hookData.ArmForce then
		hookData.ArmForce:Destroy()
	end
	hookData.Constraint:Destroy()
	hookData.BeamPart:Destroy()
	for _, attachment in hookData.Attachments do
		attachment:Destroy()
	end
end

local function createPlayerAttachment(armPart: BasePart, worldPos: Vector3, isLeft: boolean): Attachment
	local localPos = armPart.CFrame:PointToObjectSpace(worldPos)
	local attachment = Instance.new("Attachment")
	attachment.Name = "HookAttachment_" .. (isLeft and "Left" or "Right")
	attachment.Position = localPos
	attachment.Parent = armPart
	return attachment
end

local function createTargetAttachment(targetPart: BasePart, hitPosition: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "HookTarget"
	attachment.Position = targetPart.CFrame:PointToObjectSpace(hitPosition)
	attachment.Parent = targetPart
	return attachment
end

local function createConstraint(
	playerAttachment: Attachment,
	targetAttachment: Attachment,
	distance: number,
	isLeft: boolean
): RopeConstraint | SpringConstraint
	local sideName = isLeft and "Left" or "Right"
	if HookConfig.UseSpringConstraint then
		local spring = Instance.new("SpringConstraint")
		spring.Name = "PlayerHook_" .. sideName
		spring.Attachment0 = playerAttachment
		spring.Attachment1 = targetAttachment
		spring.Stiffness = HookConfig.SpringStiffness
		spring.Damping = HookConfig.SpringDamping
		spring.FreeLength = distance
		spring.Parent = Workspace
		return spring
	else
		local rope = Instance.new("RopeConstraint")
		rope.Name = "PlayerHook_" .. sideName
		rope.Attachment0 = playerAttachment
		rope.Attachment1 = targetAttachment
		rope.Length = distance
		rope.Visible = false
		rope.Parent = Workspace
		return rope
	end
end

local function createArmForce(playerAttachment: Attachment, isLeft: boolean): VectorForce?
	if not HookConfig.UseArmForce then
		return nil
	end
	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "HookArmForce_" .. (isLeft and "Left" or "Right")
	vectorForce.ApplyAtCenterOfMass = false
	vectorForce.Force = Vector3.zero
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.Attachment0 = playerAttachment
	vectorForce.Parent = playerAttachment.Parent
	return vectorForce
end

-- Creates velocity mover (VectorForce or LinearVelocity) for non-ArmForce mode.
local function createVelocityMover(humanoidRootPart: BasePart, velocityAttachment: Attachment?): Instance?
	if HookConfig.UseArmForce then
		return nil
	end
	if not velocityAttachment then
		return nil
	end
	if HookConfig.UseVectorForce then
		local vectorForce = Instance.new("VectorForce")
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.Force = Vector3.zero
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.Attachment0 = velocityAttachment
		vectorForce.Parent = humanoidRootPart
		return vectorForce
	elseif HookConfig.UseVelocityConstraints then
		local worldPart = getWorldAnchor()
		local worldAttachment = worldPart:FindFirstChild("HookVelAtt")
		if not worldAttachment then
			worldAttachment = Instance.new("Attachment")
			worldAttachment.Name = "HookVelAtt"
			worldAttachment.Parent = worldPart
		end
		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Attachment0 = velocityAttachment
		linearVelocity.Attachment1 = worldAttachment
		linearVelocity.MaxForce = math.huge
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.Parent = humanoidRootPart
		return linearVelocity
	end
	return nil
end

-- Creates gravity reduction force when GravityScaleWhenHooked is set.
local function createGravityReduction(humanoidRootPart: BasePart): (VectorForce?, Attachment?)
	local scale = HookConfig.GravityScaleWhenHooked
	if not scale or scale >= 1 or scale <= 0 then
		return nil, nil
	end
	local gravityAttachment = Instance.new("Attachment")
	gravityAttachment.Name = "HookGravityAttachment"
	gravityAttachment.Parent = humanoidRootPart
	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "HookGravityReduce"
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.Attachment0 = gravityAttachment
	local gravity = Workspace.Gravity
	local mass = humanoidRootPart.AssemblyMass
	vectorForce.Force = Vector3.new(0, mass * gravity * (1 - scale), 0)
	vectorForce.Parent = humanoidRootPart
	return vectorForce, gravityAttachment
end

return {
	releaseHookData = releaseHookData,
	createPlayerAttachment = createPlayerAttachment,
	createTargetAttachment = createTargetAttachment,
	createConstraint = createConstraint,
	createArmForce = createArmForce,
	createVelocityMover = createVelocityMover,
	createGravityReduction = createGravityReduction,
}
