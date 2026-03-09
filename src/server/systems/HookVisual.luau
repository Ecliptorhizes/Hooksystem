--[[
	HookVisual
	Purpose:
	Create and update beam-based rope visuals between player attachment and hook anchor.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookTypes = require(script.Parent.HookTypes)
type HookData = HookTypes.HookData

--[[
	Creates the beam instance used to render a hooked rope segment.
]]
local function createBeam(
	playerAttachment: Attachment,
	targetAttachment: Attachment,
	distance: number,
	isLeft: boolean
): BasePart
	local originPos = playerAttachment.WorldPosition
	local anchorPos = targetAttachment.WorldPosition
	local beamThickness = HookConfig.BeamThickness
	local beam = Instance.new("Part")
	beam.Name = "HookBeam_" .. (isLeft and "Left" or "Right")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = isLeft and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 180, 100)
	beam.Size = Vector3.new(beamThickness, distance, beamThickness)
	beam.CFrame = CFrame.lookAt(originPos, anchorPos) * CFrame.Angles(-math.rad(90), 0, 0)
	beam.Position = (originPos + anchorPos) / 2
	beam.Parent = Workspace
	return beam
end

--[[
	Updates both rope/spring length and beam transform for one hook.
	Returns normalized direction toward anchor for force accumulation.
]]
local function updateRopeAndBeam(
	hookData: HookData,
	ropeDelta: number,
	sway: number,
	humanoidRootPart: BasePart,
	beamThickness: number,
	maxRange: number
): Vector3
	local originPos = hookData.PlayerAtt.WorldPosition
	local anchorPos = hookData.TargetAtt.WorldPosition
	local toDirection = (anchorPos - humanoidRootPart.Position).Unit
	local currentLen = hookData.Constraint:IsA("SpringConstraint") and hookData.Constraint.FreeLength
		or (hookData.Constraint :: RopeConstraint).Length
	local anchorDist = (anchorPos - originPos).Magnitude
	local maxLen = math.min(maxRange, anchorDist + 50)
	local newLen = ropeDelta >= 0 and math.max(5, currentLen - ropeDelta)
		or math.min(maxLen, currentLen - ropeDelta)
	if hookData.Constraint:IsA("SpringConstraint") then
		hookData.Constraint.FreeLength = newLen
	else
		(hookData.Constraint :: RopeConstraint).Length = newLen
	end
	local len = (anchorPos - originPos).Magnitude
	hookData.BeamPart.Size = Vector3.new(beamThickness, len, beamThickness)
	local baseCF = CFrame.lookAt(originPos, anchorPos) * CFrame.Angles(-math.rad(90), 0, 0)
	hookData.BeamPart.CFrame = (baseCF * CFrame.Angles(sway, sway * 0.5, 0))
	hookData.BeamPart.Position = (originPos + anchorPos) / 2
	return toDirection
end

return {
	createBeam = createBeam,
	updateRopeAndBeam = updateRopeAndBeam,
}
