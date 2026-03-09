--[[
	SpeedVFXController
	Purpose:
	Render first-person airborne speed-line VFX when player velocity exceeds threshold.
	Includes hysteresis to avoid visual flicker around activation speed.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Maid)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local SpeedVFXController = Knit.CreateController({
	Name = "SpeedVFXController",
})

local maid = Maid.new()
local speedLinesClone: Instance? = nil
local template: Model? = nil

local function destroySpeedLines()
	if speedLinesClone then
		speedLinesClone:Destroy()
		speedLinesClone = nil
	end
end

local function getTemplate(): Model?
	if template and template.Parent then
		return template
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local vfx = assets:FindFirstChild("VFX")
	if not vfx then
		return nil
	end
	local hookEffects = vfx:FindFirstChild("HookEffects")
	if not hookEffects then
		return nil
	end
	template = hookEffects:FindFirstChild("SpeedLines") :: Model?
	return template
end

local function createFallbackSpeedLines(): Instance
	local part = Instance.new("Part")
	part.Name = "SpeedLinesFallback"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SpeedLines"
	emitter.Color = ColorSequence.new(Color3.fromRGB(100, 180, 255))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(1)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Speed = NumberRange.new(8, 15)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 60
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Enabled = true
	emitter.Parent = part
	return part
end

local function getParticleEmitter(container: Instance): ParticleEmitter?
	for _, desc in container:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			return desc
		end
	end
	return nil
end

local showingVFX = false
local FIRST_PERSON_DIST = 2.5

local function isFirstPerson(camera: Camera, hrp: BasePart): boolean
	return (camera.CFrame.Position - hrp.Position).Magnitude < FIRST_PERSON_DIST
end

local function isInAir(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial == Enum.Material.Air
end

local function shouldShowSpeedVFX(velocity: Vector3, camera: Camera, hrp: BasePart, humanoid: Humanoid): boolean
	if not isFirstPerson(camera, hrp) then
		return false
	end
	if not isInAir(humanoid) then
		return false
	end
	local vMag = velocity.Magnitude
	local limitSpeed = HookConfig.SpeedVFXLimitSpeed or 30
	local hideBelow = HookConfig.SpeedVFXHideBelowSpeed or 22
	local wouldShow = vMag >= limitSpeed
	local wouldHide = vMag < hideBelow
	if wouldShow then
		showingVFX = true
	end
	if wouldHide then
		showingVFX = false
	end
	return showingVFX
end

local function getScaleFactor(velocityMag: number): number
	local limitSpeed = HookConfig.SpeedVFXLimitSpeed or 30
	local maxSpeed = HookConfig.SpeedVFXMaxSpeed or 1000
	return math.clamp((velocityMag - limitSpeed) / (maxSpeed - limitSpeed), 0, 1)
end

local function applyScaleToEmitter(emitter: ParticleEmitter, scaleFactor: number)
	local scaleMin = HookConfig.SpeedVFXScaleMin or 0.5
	local scaleMax = HookConfig.SpeedVFXScaleMax or 1.5
	local scale = scaleMin + (scaleMax - scaleMin) * scaleFactor

	local baseSize = HookConfig.SpeedVFXBaseSize or 1
	local baseSpeed = HookConfig.SpeedVFXBaseSpeed or 15
	local baseLifetime = HookConfig.SpeedVFXBaseLifetime or 1

	emitter.Size = NumberSequence.new(baseSize * scale)
	emitter.Speed = NumberRange.new(baseSpeed * scale * 0.5, baseSpeed * scale)
	emitter.Lifetime = NumberRange.new(baseLifetime * scale * 0.8, baseLifetime * scale)
end

function SpeedVFXController:KnitStart()
	local player = Players.LocalPlayer

	maid:GiveTask(player.CharacterRemoving:Connect(function()
		destroySpeedLines()
	end))

	maid:GiveTask(RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then
			destroySpeedLines()
			return
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not hrp or not hrp:IsA("BasePart") or not humanoid then
			destroySpeedLines()
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local velocity = hrp.AssemblyLinearVelocity
		local show = shouldShowSpeedVFX(velocity, camera, hrp, humanoid)

		if not show then
			destroySpeedLines()
			return
		end

		if not speedLinesClone or not speedLinesClone.Parent then
			local templateModel = getTemplate()
			local clone: Instance = if templateModel then templateModel:Clone() else createFallbackSpeedLines()
			clone.Name = "SpeedLinesClone"
			clone.Parent = Workspace
			speedLinesClone = clone
		end

		if not speedLinesClone then
			return
		end

		local velocityMag = velocity.Magnitude
		if velocityMag < 0.1 then
			return
		end

		local moveDir = velocity.Unit
		local clone = speedLinesClone :: BasePart | Model
		clone.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + moveDir)

		local emitter = getParticleEmitter(speedLinesClone)
		if emitter then
			emitter.Enabled = true
			local scaleFactor = getScaleFactor(velocityMag)
			applyScaleToEmitter(emitter, scaleFactor)
		end
	end))
end

function SpeedVFXController:KnitDestroy()
	destroySpeedLines()
	maid:DoCleaning()
end

return SpeedVFXController
