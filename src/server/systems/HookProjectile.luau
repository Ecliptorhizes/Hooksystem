--[[
	HookProjectile
	Purpose:
	Run the projectile hook phase: advance, raycast, and resolve hit/cancel/range termination.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

--[[
	Returns left/right arm part when available.
]]
local function getArmPart(character: Model, isLeft: boolean): BasePart?
	local part = character:FindFirstChild(isLeft and "Left Arm" or "Right Arm")
	return part and part:IsA("BasePart") and part or nil
end

--[[
	Computes world-space hook origin offset from HumanoidRootPart orientation.
]]
local function getHookOriginWorldPos(armPart: BasePart, humanoidRootPart: BasePart, isLeft: boolean): Vector3
	local look = humanoidRootPart.CFrame.LookVector
	local right = humanoidRootPart.CFrame.RightVector
	local forward = look * (HookConfig.HookArmForwardOffset or 1.2)
	local side = right * ((HookConfig.HookArmSideOffset or 0.4) * (isLeft and -1 or 1))
	return armPart.Position + forward + side
end

--[[
	Advances a hook projectile each frame until hit, cancel, or max range is reached.
	onAttach callback is executed on a valid hit and returns (success, errMessage).
]]
local function fireProjectile(
	player: Player,
	origin: Vector3,
	direction: Vector3,
	isLeft: boolean,
	humanoidRootPart: BasePart,
	cancelCheck: () -> boolean,
	onAttach: (BasePart, Vector3) -> (boolean, string?)
): (boolean, string?)
	local directionUnit = direction.Unit
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }

	local position = origin
	local startPos = origin
	local lastTick = tick()
	local result = Instance.new("BindableEvent")
	local connection: RBXScriptConnection?
	local projectileBeam = Instance.new("Part")
	projectileBeam.Name = "HookProjectile_" .. (isLeft and "L" or "R")
	projectileBeam.Anchored = true
	projectileBeam.CanCollide = false
	projectileBeam.CanQuery = false
	projectileBeam.CanTouch = false
	projectileBeam.Material = Enum.Material.Neon
	projectileBeam.Color = isLeft and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 180, 100)
	projectileBeam.Size = Vector3.new(HookConfig.BeamThickness, 1, HookConfig.BeamThickness)
	projectileBeam.Transparency = 0.3
	projectileBeam.Parent = Workspace

	-- Cleanup is centralized so every exit path (hit/cancel/out-of-range) is consistent.
	local function cleanup()
		if connection then
			connection:Disconnect()
		end
		projectileBeam:Destroy()
	end

	connection = RunService.Heartbeat:Connect(function()
		if cancelCheck() then
			cleanup()
			result:Fire(false, "Cancelled")
			return
		end
		if not player.Character or not humanoidRootPart.Parent then
			cleanup()
			result:Fire(false, "Character lost")
			return
		end
		local now = tick()
		local delta = now - lastTick
		lastTick = now
		local step = directionUnit * HookConfig.ProjectileSpeed * delta
		local newPos = position + step
		local rayResult = Workspace:Raycast(position, step, raycastParams)
		if rayResult then
			cleanup()
			local dist = (rayResult.Position - startPos).Magnitude
			if dist <= HookConfig.MaxRange and rayResult.Instance:IsA("BasePart") then
				local ok, err = onAttach(rayResult.Instance, rayResult.Position)
				result:Fire(ok, err)
			else
				result:Fire(false, "Invalid hit")
			end
			return
		end
		position = newPos
		local armPart = getArmPart(player.Character, isLeft) or humanoidRootPart
		local beamStart = getHookOriginWorldPos(armPart, humanoidRootPart, isLeft)
		local beamDir = position - beamStart
		local len = beamDir.Magnitude
		if len > 0.1 then
			beamDir = beamDir / len
			projectileBeam.Size = Vector3.new(HookConfig.BeamThickness, len, HookConfig.BeamThickness)
			local rightVec = Vector3.new(-beamDir.Z, 0, beamDir.X)
			if rightVec.Magnitude < 0.01 then
				rightVec = Vector3.new(1, 0, 0)
			end
			projectileBeam.CFrame = CFrame.fromMatrix((beamStart + position) / 2, rightVec.Unit, beamDir)
			projectileBeam.Parent = Workspace
		end
		if (position - startPos).Magnitude > HookConfig.MaxRange then
			cleanup()
			result:Fire(false, "Too far")
		end
	end)

	local ok, err = result.Event:Wait()
	result:Destroy()
	return ok, err
end

return {
	fireProjectile = fireProjectile,
	getArmPart = getArmPart,
	getHookOriginWorldPos = getHookOriginWorldPos,
}
