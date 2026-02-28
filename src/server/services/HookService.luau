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
		RequestFireHook = true,
		ReleaseHook = true,
		RequestJump = true,
		RequestBoost = true,
		GetGas = true,
		SetReelForce = true,
		SetSwingForce = true,
	},
})

type HookData = {
	Constraint: RopeConstraint | SpringConstraint,
	BeamPart: BasePart,
	Attachments: { Attachment },
	PlayerAtt: Attachment,
	TargetAtt: Attachment,
	ArmForce: VectorForce?,
	AttachTime: number?,
}

type PlayerHookState = {
	left: HookData?,
	right: HookData?,
	LinearVelocity: LinearVelocity?,
	VelocityAttachment: Attachment,
	GravityForce: VectorForce?,
	GravityAttachment: Attachment?,
	LastTick: number,
	JumpBoostEndTime: number?,
	ReelEndTime: number?,
	LastBoostTime: number?,
	HeartbeatConn: RBXScriptConnection,
	RagdollPreventionConn: RBXScriptConnection?,
	RagdollPostSimConn: RBXScriptConnection?,
	LimbCollisionBackup: { { part: BasePart, canCollide: boolean } }?,
}

local playerHooks: { [number]: PlayerHookState? } = {}
local playerGas: { [number]: number } = {}
local sharedWorldAnchor: BasePart? = nil

local function getWorldAnchor(): BasePart
	if not sharedWorldAnchor or not sharedWorldAnchor.Parent then
		local p = Instance.new("Part")
		p.Name = "HookVelWorldAnchor"
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(0.1, 0.1, 0.1)
		p.Transparency = 1
		p.Parent = Workspace
		sharedWorldAnchor = p
	end
	return sharedWorldAnchor :: BasePart
end
local playerProjectileCancel: { [number]: { left: boolean, right: boolean } } = {}
local playerReelForce: { [number]: number } = {}
local playerSwingForce: { [number]: number } = {}

local function getGas(player: Player): number
	if not playerGas[player.UserId] then
		playerGas[player.UserId] = HookConfig.MaxGas
	end
	return playerGas[player.UserId]
end

local function spendGas(player: Player, amount: number): boolean
	local gas = getGas(player)
	if gas < amount then
		return false
	end
	playerGas[player.UserId] = gas - amount
	return true
end

local function regenGas(player: Player, delta: number)
	local gas = getGas(player)
	if gas >= HookConfig.MaxGas then
		return
	end
	playerGas[player.UserId] = math.min(HookConfig.MaxGas, gas + HookConfig.GasRegenPerSec * delta)
end

local function releaseHookData(data: HookData)
	if data.ArmForce then
		data.ArmForce:Destroy()
	end
	data.Constraint:Destroy()
	data.BeamPart:Destroy()
	for _, att in data.Attachments do
		att:Destroy()
	end
end

local function getArmPart(character: Model, isLeft: boolean): BasePart?
	local names = isLeft and { "Left Arm" } or { "Right Arm" }
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function rotateTowards(from: Vector3, to: Vector3, maxRad: number): Vector3
	local fromMag = from.Magnitude
	if fromMag < 0.0001 then
		return to.Unit
	end
	local fromNorm = from.Unit
	local toNorm = to.Unit
	local dot = math.clamp(fromNorm:Dot(toNorm), -1, 1)
	local angle = math.acos(dot)
	local rotateBy = math.min(angle, maxRad)
	if rotateBy < 0.0001 then
		return fromNorm
	end
	local axis = fromNorm:Cross(toNorm)
	if axis.Magnitude < 0.0001 then
		return toNorm
	end
	return (CFrame.fromAxisAngle(axis.Unit, rotateBy) * fromNorm).Unit
end

local function getHookOriginWorldPos(armPart: BasePart, hrp: BasePart, isLeft: boolean): Vector3
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local forward = look * (HookConfig.HookArmForwardOffset or 1.2)
	local side = right * ((HookConfig.HookArmSideOffset or 0.4) * (isLeft and -1 or 1))
	return armPart.Position + forward + side
end

local function doAttach(player: Player, targetPart: BasePart, hitPosition: Vector3, isLeft: boolean): (boolean, string?)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "No character"
	end

	local key = isLeft and "left" or "right"
	local armPart = getArmPart(player.Character :: Model, isLeft)
	local state = playerHooks[player.UserId]
	if state and state[key] then
		releaseHookData(state[key])
		state[key] = nil
	end

	armPart = armPart or hrp
	local worldPos = getHookOriginWorldPos(armPart, hrp, isLeft)
	local localPos = armPart.CFrame:PointToObjectSpace(worldPos)

	local playerAtt = Instance.new("Attachment")
	playerAtt.Name = "HookAttachment_" .. (isLeft and "Left" or "Right")
	playerAtt.Position = localPos
	playerAtt.Parent = armPart

	local distance = (hitPosition - playerAtt.WorldPosition).Magnitude

	local targetAtt = Instance.new("Attachment")
	targetAtt.Name = "HookTarget"
	targetAtt.Position = targetPart.CFrame:PointToObjectSpace(hitPosition)
	targetAtt.Parent = targetPart

	local constraint: RopeConstraint | SpringConstraint
	if HookConfig.UseSpringConstraint then
		local spring = Instance.new("SpringConstraint")
		spring.Name = "PlayerHook_" .. (isLeft and "Left" or "Right")
		spring.Attachment0 = playerAtt
		spring.Attachment1 = targetAtt
		spring.Stiffness = HookConfig.SpringStiffness
		spring.Damping = HookConfig.SpringDamping
		spring.FreeLength = distance
		spring.Parent = Workspace
		constraint = spring
	else
		local rope = Instance.new("RopeConstraint")
		rope.Name = "PlayerHook_" .. (isLeft and "Left" or "Right")
		rope.Attachment0 = playerAtt
		rope.Attachment1 = targetAtt
		rope.Length = distance
		rope.Visible = false
		rope.Parent = Workspace
		constraint = rope
	end

	local beam = Instance.new("Part")
	beam.Name = "HookBeam_" .. (isLeft and "Left" or "Right")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = isLeft and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 180, 100)
	beam.Size = Vector3.new(HookConfig.BeamThickness, distance, HookConfig.BeamThickness)
	local originPos = playerAtt.WorldPosition
	beam.CFrame = CFrame.lookAt(originPos, targetAtt.WorldPosition) * CFrame.Angles(-math.rad(90), 0, 0)
	beam.Position = (originPos + targetAtt.WorldPosition) / 2
	beam.Parent = Workspace

	local armForce: VectorForce? = nil
	if HookConfig.UseArmForce then
		local vf = Instance.new("VectorForce")
		vf.Name = "HookArmForce_" .. (isLeft and "Left" or "Right")
		vf.ApplyAtCenterOfMass = false
		vf.Force = Vector3.zero
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.Attachment0 = playerAtt
		vf.Parent = playerAtt.Parent
		armForce = vf
	end

	local hookData: HookData = {
		Constraint = constraint,
		BeamPart = beam,
		Attachments = { playerAtt, targetAtt },
		PlayerAtt = playerAtt,
		TargetAtt = targetAtt,
		ArmForce = armForce,
		AttachTime = tick(),
	}

	if not state then
		local velAtt = (not HookConfig.UseArmForce) and Instance.new("Attachment") or nil
		if velAtt then
			velAtt.Name = "HookVelocityAttachment"
			velAtt.Parent = hrp
		end

		local mover = nil
		if not HookConfig.UseArmForce then
			if HookConfig.UseVectorForce then
				local vf = Instance.new("VectorForce")
				vf.ApplyAtCenterOfMass = true
				vf.Force = Vector3.zero
				vf.RelativeTo = Enum.ActuatorRelativeTo.World
				vf.Attachment0 = velAtt
				vf.Parent = hrp
				mover = vf
			elseif HookConfig.UseVelocityConstraints then
				local worldPart = getWorldAnchor()
				local worldAtt = worldPart:FindFirstChild("HookVelAtt")
				if not worldAtt then
					worldAtt = Instance.new("Attachment")
					worldAtt.Name = "HookVelAtt"
					worldAtt.Parent = worldPart
				end
				local linVel = Instance.new("LinearVelocity")
				linVel.Attachment0 = velAtt
				linVel.Attachment1 = worldAtt
				linVel.MaxForce = math.huge
				linVel.VectorVelocity = Vector3.zero
				linVel.RelativeTo = Enum.ActuatorRelativeTo.World
				linVel.Parent = hrp
				mover = linVel
			end
		end

		local gravityForce: VectorForce? = nil
		local gravityAtt: Attachment? = nil
		local scale = HookConfig.GravityScaleWhenHooked
		if scale and scale < 1 and scale > 0 then
			local gAtt = Instance.new("Attachment")
			gAtt.Name = "HookGravityAttachment"
			gAtt.Parent = hrp
			gravityAtt = gAtt
			local vf = Instance.new("VectorForce")
			vf.Name = "HookGravityReduce"
			vf.ApplyAtCenterOfMass = true
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.Attachment0 = gAtt
			local gravity = Workspace.Gravity
			local mass = hrp.AssemblyMass
			vf.Force = Vector3.new(0, mass * gravity * (1 - scale), 0)
			vf.Parent = hrp
			gravityForce = vf
		end

		state = {
			left = nil,
			right = nil,
			LinearVelocity = mover,
			VelocityAttachment = velAtt,
			GravityForce = gravityForce,
			GravityAttachment = gravityAtt,
			LastTick = tick(),
			JumpBoostEndTime = nil,
			ReelEndTime = nil,
			LastBoostTime = nil :: number?,
			HeartbeatConn = nil :: any,
		}
		playerHooks[player.UserId] = state
	end

	state[key] = hookData

	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		if state.RagdollPreventionConn then
			state.RagdollPreventionConn:Disconnect()
		end
		state.RagdollPreventionConn = hum.StateChanged:Connect(function(old, new)
			if
				new == Enum.HumanoidStateType.Ragdoll
				or new == Enum.HumanoidStateType.FallingDown
				or new == Enum.HumanoidStateType.Physics
			then
				task.defer(function()
					if hum and hum.Parent then
						hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)
					end
				end)
			end
		end)
		if HookConfig.DisableLimbCollisionWhenHooked and player.Character then
			state.LimbCollisionBackup = {}
			for _, desc in player.Character:GetDescendants() do
				if desc:IsA("BasePart") and desc ~= hrp then
					table.insert(state.LimbCollisionBackup, { part = desc, canCollide = desc.CanCollide })
					desc.CanCollide = false
				end
			end
		end
	end
	if not HookConfig.NoAutoPull and not HookConfig.UseArmForce then
		do
			local mult = HookConfig.LaunchForceMultiplier or 12
			local minY = HookConfig.LaunchVerticalMin or 15
			local toTarget = (hitPosition - hrp.Position).Unit * mult
			if toTarget.Y < minY then
				toTarget = toTarget + Vector3.new(0, math.min(minY - toTarget.Y, 20), 0)
			end
			if hitPosition.Y >= hrp.Position.Y then
				local extraY = math.min((hitPosition.Y - hrp.Position.Y) * 0.5, 25)
				toTarget = toTarget + Vector3.new(0, extraY, 0)
			end
			local currentVel = hrp.AssemblyLinearVelocity
			local newVel = currentVel + toTarget
			local cap = HookConfig.LaunchVelocityCap or 150
			if newVel.Magnitude > cap then
				newVel = newVel.Unit * cap
			end
			local upwardCap = HookConfig.LaunchUpwardCap or 35
			if newVel.Y > upwardCap then
				newVel = Vector3.new(newVel.X, upwardCap, newVel.Z)
			end
			local downwardCap = HookConfig.LaunchDownwardCap or 80
			if newVel.Y < -downwardCap then
				newVel = Vector3.new(newVel.X, -downwardCap, newVel.Z)
			end
			hrp.AssemblyLinearVelocity = newVel
		end
	else
		if HookConfig.UseArmForce then
			local toTarget = (hitPosition - hrp.Position).Unit
			local tangent = toTarget:Cross(Vector3.new(0, 1, 0))
			if tangent.Magnitude > 0.01 then
				tangent = tangent.Unit
				local kick = HookConfig.PendulumKickSpeed or 18
				local vel = hrp.AssemblyLinearVelocity
				if vel.Magnitude < kick * 0.5 then
					hrp.AssemblyLinearVelocity = vel + tangent * kick
				end
			end
		end
	end

	if not state.HeartbeatConn then
		state.RagdollPostSimConn = RunService.PostSimulation:Connect(function()
			local s = playerHooks[player.UserId]
			if not s or not player.Character or not s.left and not s.right then
				return
			end
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			local hrp2 = player.Character:FindFirstChild("HumanoidRootPart")
			if hum and hrp2 then
				local st = hum:GetState()
				if
					st == Enum.HumanoidStateType.Ragdoll
					or st == Enum.HumanoidStateType.FallingDown
					or st == Enum.HumanoidStateType.Physics
				then
					hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)
				end
			end
			if HookConfig.UseArmForce then
				local leftData = s.left
				local rightData = s.right
				local boostWindow = (s.LastBoostTime and (tick() - s.LastBoostTime) < 0.6)
				local swingVal = playerSwingForce[player.UserId] or 0
				local vel = hrp2.AssemblyLinearVelocity
				local velMag = vel.Magnitude
				if not boostWindow and swingVal == 0 and velMag < (HookConfig.PendulumNudgeVelThreshold or 10) then
					local firstData = leftData or rightData
					if firstData then
						local toTarget = (firstData.TargetAtt.WorldPosition - firstData.PlayerAtt.WorldPosition).Unit
						local tangent = toTarget:Cross(Vector3.new(0, 1, 0))
						if tangent.Magnitude > 0.01 then
							tangent = tangent.Unit
							local nudgeSpeed = HookConfig.PendulumNudgeSpeed or 22
							hrp2.AssemblyLinearVelocity = tangent * nudgeSpeed
						end
					end
				end
			end
		end)
		state.HeartbeatConn = RunService.PreSimulation:Connect(function()
			local s = playerHooks[player.UserId]
			if not s or not player.Character or hrp.Parent ~= player.Character then
				if s then
					if s.HeartbeatConn then
						s.HeartbeatConn:Disconnect()
					end
					if s.RagdollPostSimConn then
						s.RagdollPostSimConn:Disconnect()
					end
				end
				return
			end
			local leftData = s.left
			local rightData = s.right
			if not leftData and not rightData then
				return
			end
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				local st = hum:GetState()
				if
					st == Enum.HumanoidStateType.Ragdoll
					or st == Enum.HumanoidStateType.FallingDown
					or st == Enum.HumanoidStateType.Physics
				then
					hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)
				end
			end
			local velCap = HookConfig.MaxVelocityWhileHooked
			if velCap and velCap > 0 then
				local vel = hrp.AssemblyLinearVelocity
				if vel.Magnitude > velCap then
					hrp.AssemblyLinearVelocity = vel.Unit * velCap
				end
			end
			local voidFloor = HookConfig.VoidFloorY or -350
			if hrp.Position.Y < voidFloor then
				if leftData then
					releaseHookData(leftData)
					s.left = nil
				end
				if rightData then
					releaseHookData(rightData)
					s.right = nil
				end
				hrp.AssemblyLinearVelocity = Vector3.new(
					hrp.AssemblyLinearVelocity.X * 0.3,
					math.max(hrp.AssemblyLinearVelocity.Y, -60),
					hrp.AssemblyLinearVelocity.Z * 0.3
				)
				if s.HeartbeatConn then
					s.HeartbeatConn:Disconnect()
					s.HeartbeatConn = nil
				end
				if s.RagdollPostSimConn then
					s.RagdollPostSimConn:Disconnect()
					s.RagdollPostSimConn = nil
				end
				return
			end

			local now = tick()
			local delta = now - (s.LastTick or now)
			s.LastTick = now

			local toAnchor = Vector3.zero
			local velocity = hrp.AssemblyLinearVelocity
			local velocityMag = velocity.Magnitude
			local sway = math.sin(tick() * HookConfig.RopeSwayFrequency)
				* HookConfig.RopeSwayAmplitude
				* (1 + velocityMag * 0.01)
			local pullForce = (leftData and rightData) and HookConfig.PullForceDual or HookConfig.PullForceSingle
			local reelInPull = HookConfig.ReelInPullForce or pullForce
			local reelForceVal =
				math.clamp(playerReelForce[player.UserId] or 0, -HookConfig.ReelForceRange, HookConfig.ReelForceRange)

			local shortenSpeed = HookConfig.RopeShortenSpeed or 28
			local extendSpeed = HookConfig.RopeExtendSpeed or 22
			local boostWindow = (s.LastBoostTime and (tick() - s.LastBoostTime) < 0.6)
			local ropeDelta = 0
			if reelForceVal > 0 then
				local reelMult = HookConfig.RopeReelInMultiplier or 1.0
				ropeDelta = shortenSpeed * reelMult * delta
			elseif reelForceVal < 0 then
				ropeDelta = -extendSpeed * delta
			end
			if leftData then
				local originPos = leftData.PlayerAtt.WorldPosition
				local anchorPos = leftData.TargetAtt.WorldPosition
				local toLeft = (anchorPos - hrp.Position).Unit
				toAnchor = toAnchor + toLeft
				local currentLen = leftData.Constraint:IsA("SpringConstraint") and leftData.Constraint.FreeLength
					or (leftData.Constraint :: RopeConstraint).Length
				local anchorDist = (anchorPos - originPos).Magnitude
				local maxLen = math.min(HookConfig.MaxRange, anchorDist + 50)
				local newLen = ropeDelta >= 0 and math.max(5, currentLen - ropeDelta)
					or math.min(maxLen, currentLen - ropeDelta)
				if leftData.Constraint:IsA("SpringConstraint") then
					leftData.Constraint.FreeLength = newLen
				else
					(leftData.Constraint :: RopeConstraint).Length = newLen
				end
				local len = (anchorPos - originPos).Magnitude
				leftData.BeamPart.Size = Vector3.new(HookConfig.BeamThickness, len, HookConfig.BeamThickness)
				local baseCF = CFrame.lookAt(originPos, anchorPos) * CFrame.Angles(-math.rad(90), 0, 0)
				leftData.BeamPart.CFrame = (baseCF * CFrame.Angles(sway, sway * 0.5, 0))
				leftData.BeamPart.Position = (originPos + anchorPos) / 2
			end
			if rightData then
				local originPos = rightData.PlayerAtt.WorldPosition
				local anchorPos = rightData.TargetAtt.WorldPosition
				local toRight = (anchorPos - hrp.Position).Unit
				toAnchor = toAnchor + toRight
				local currentLen = rightData.Constraint:IsA("SpringConstraint") and rightData.Constraint.FreeLength
					or (rightData.Constraint :: RopeConstraint).Length
				local anchorDist = (anchorPos - originPos).Magnitude
				local maxLen = math.min(HookConfig.MaxRange, anchorDist + 50)
				local newLen = ropeDelta >= 0 and math.max(5, currentLen - ropeDelta)
					or math.min(maxLen, currentLen - ropeDelta)
				if rightData.Constraint:IsA("SpringConstraint") then
					rightData.Constraint.FreeLength = newLen
				else
					(rightData.Constraint :: RopeConstraint).Length = newLen
				end
				local len = (anchorPos - originPos).Magnitude
				rightData.BeamPart.Size = Vector3.new(HookConfig.BeamThickness, len, HookConfig.BeamThickness)
				local baseCF = CFrame.lookAt(originPos, anchorPos) * CFrame.Angles(-math.rad(90), 0, 0)
				rightData.BeamPart.CFrame = (baseCF * CFrame.Angles(sway, sway * 0.5, 0))
				rightData.BeamPart.Position = (originPos + anchorPos) / 2
			end

			if (not HookConfig.UseArmForce) and HookConfig.OrientToAnchor and toAnchor.Magnitude > 0.01 then
				local anchorPos = (leftData and rightData)
						and ((leftData.TargetAtt.WorldPosition + rightData.TargetAtt.WorldPosition) / 2)
					or (leftData and leftData.TargetAtt.WorldPosition or rightData.TargetAtt.WorldPosition)
				local targetCF = CFrame.lookAt(hrp.Position, anchorPos)
				hrp.CFrame = hrp.CFrame:Lerp(targetCF, math.min(1, HookConfig.OrientLerpSpeed * delta))
			end

			local dir = toAnchor.Unit
			local swingVal = playerSwingForce[player.UserId] or 0
			local goalPos = (leftData and rightData)
					and ((leftData.TargetAtt.WorldPosition + rightData.TargetAtt.WorldPosition) / 2)
				or (leftData and leftData.TargetAtt.WorldPosition or rightData.TargetAtt.WorldPosition)
			local distToGoal = (goalPos - hrp.Position).Magnitude
			local stopNearDist = HookConfig.StopNearAnchorDist or 2
			local baseVel: Vector3
			if HookConfig.UseGrapplePhysics then
				local grappleSpeed = (leftData and rightData) and (HookConfig.GrappleSpeedDual or 300)
					or (HookConfig.GrappleSpeedSingle or 150)
				local multiplier = 1
				if reelForceVal > 0 then
					multiplier = HookConfig.ReelInSpeedMultiplier or 2.2
				elseif reelForceVal < 0 then
					baseVel = velocity * (HookConfig.NoAutoPullVelocityRetention or 0.98)
					multiplier = 0
				end
				local orbitVelocity = Vector3.zero
				if swingVal ~= 0 and multiplier > 0 then
					local orbitAngle = (HookConfig.OrbitAngleRad or (math.pi / 2.4)) * -swingVal
					local orbitDir = (CFrame.lookAt(hrp.Position, goalPos) * CFrame.Angles(0, orbitAngle, 0)).LookVector
					orbitVelocity = orbitDir * (HookConfig.OrbitSpeed or 110)
				end
				if multiplier > 0 then
					if distToGoal < stopNearDist then
						baseVel = Vector3.zero
					else
						baseVel = dir * (grappleSpeed * multiplier) + orbitVelocity
						if boostWindow then
							baseVel = baseVel + (hrp.CFrame.LookVector * (HookConfig.GasBoostAdd or 150))
						end
					end
				end
				if
					not HookConfig.UseArmForce
					and (HookConfig.OrientToGoal or HookConfig.OrientToAnchor)
					and dir.Magnitude > 0.01
				then
					local targetCF = CFrame.lookAt(hrp.Position, goalPos)
					hrp.CFrame = hrp.CFrame:Lerp(targetCF, math.min(1, (HookConfig.OrientLerpSpeed or 12) * delta))
				end
			else
				local momentumAlong = dir * (velocity:Dot(dir))
				local reelAngle = HookConfig.ReelAngleRad * (1 + reelForceVal)
				local velMagForAngle = velocity.Magnitude
				local angleToDir = (velMagForAngle >= 0.1)
						and math.deg(math.acos(math.clamp(velocity.Unit:Dot(dir), -1, 1)))
					or 0
				local canReel = (angleToDir > 90) and (s.ReelEndTime and tick() < s.ReelEndTime)
				if canReel and velMagForAngle >= 0.1 then
					local speed = velocityMag + (HookConfig.ReelSpeedRetention or 0.1)
					baseVel = rotateTowards(velocity, dir, reelAngle) * speed
				elseif HookConfig.NoAutoPull and reelForceVal <= 0 then
					s.ReelEndTime = nil
					s.JumpBoostEndTime = nil
					baseVel = velocity * (HookConfig.NoAutoPullVelocityRetention or 0.98)
					if boostWindow then
						baseVel = baseVel + dir * ((HookConfig.BoostThrustForce or 140) * delta)
					end
				elseif reelForceVal > 0 then
					s.ReelEndTime = nil
					s.JumpBoostEndTime = nil
					baseVel = dir * reelInPull + momentumAlong * HookConfig.VelocityScaleMultiplier
				else
					s.ReelEndTime = nil
					if s.JumpBoostEndTime and tick() < s.JumpBoostEndTime then
						baseVel = dir * pullForce
							+ momentumAlong * HookConfig.VelocityScaleMultiplier
							+ Vector3.new(0, HookConfig.JumpForce, 0)
					else
						s.JumpBoostEndTime = nil
						baseVel = dir * pullForce + momentumAlong * HookConfig.VelocityScaleMultiplier
					end
				end
				if swingVal ~= 0 then
					local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
					if right.Magnitude < 0.01 then
						right = hrp.CFrame.RightVector
					end
					baseVel = baseVel + right * (swingVal * (HookConfig.SwingForce or 15))
				end
				local momentum = HookConfig.PendulumMomentum or 0.6
				if boostWindow then
					momentum = HookConfig.BoostPendulumMomentum or 0.35
				elseif reelForceVal > 0 then
					momentum = HookConfig.ReelPendulumMomentum or 0.4
				end
				baseVel = velocity * momentum + baseVel * (1 - momentum)
			end

			if HookConfig.UseArmForce then
				local function updateArmForce(data: HookData)
					if not data.ArmForce then
						return
					end
					local toTarget = (data.TargetAtt.WorldPosition - data.PlayerAtt.WorldPosition).Unit
					local mag = 0
					if HookConfig.NoAutoPull then
						if boostWindow then
							mag = HookConfig.ArmPullForce or 3500
							local rampSec = HookConfig.ArmForceRampUpSec or 0.4
							local elapsed = tick() - (data.AttachTime or tick())
							local ramp = rampSec > 0 and math.min(1, elapsed / rampSec) or 1
							mag = mag * ramp
						end
					else
						mag = HookConfig.ArmPullForce or 3500
						if reelForceVal > 0 then
							mag = HookConfig.ArmReelForce or 7000
						end
						local rampSec = HookConfig.ArmForceRampUpSec or 0.4
						local elapsed = tick() - (data.AttachTime or tick())
						local ramp = rampSec > 0 and math.min(1, elapsed / rampSec) or 1
						mag = mag * ramp
					end
					local force = toTarget * mag
					if boostWindow then
						force = force + (hrp.CFrame.LookVector * (HookConfig.ArmBoostForce or 100))
					end
					local swingVal = playerSwingForce[player.UserId] or 0
					if swingVal ~= 0 then
						local right = toTarget:Cross(Vector3.new(0, 1, 0)).Unit
						if right.Magnitude < 0.01 then
							right = hrp.CFrame.RightVector
						end
						force = force + right * (swingVal * (HookConfig.SwingForce or 35) * 80)
					end
					data.ArmForce.Force = force
				end
				if leftData then
					updateArmForce(leftData)
				end
				if rightData then
					updateArmForce(rightData)
				end
			else
				local launchCap = HookConfig.LaunchVelocityCap or 400
				if baseVel.Magnitude > launchCap then
					baseVel = baseVel.Unit * launchCap
				end
				local downwardCap = HookConfig.PullDownwardCap or 60
				if baseVel.Y < -downwardCap then
					baseVel = Vector3.new(baseVel.X, -downwardCap, baseVel.Z)
				end
				if state.LinearVelocity then
					if state.LinearVelocity:IsA("VectorForce") then
						local mag = HookConfig.VectorForceMagnitude or 12000
						local targetSpeed = (leftData and rightData) and (HookConfig.GrappleSpeedDual or 300)
							or (HookConfig.GrappleSpeedSingle or 150)
						if boostWindow then
							targetSpeed = targetSpeed + (HookConfig.GasBoostAdd or 150)
						end
						if velocityMag < targetSpeed * 0.95 and baseVel.Magnitude > 0.01 then
							state.LinearVelocity.Force = baseVel.Unit * mag
						else
							state.LinearVelocity.Force = Vector3.zero
						end
					else
						state.LinearVelocity.VectorVelocity = baseVel
					end
				end
				hrp.AssemblyLinearVelocity = baseVel
			end
		end)
	end

	return true, nil
end

function HookService:RequestHook(
	player: Player,
	targetPart: BasePart,
	hitPosition: Vector3,
	isLeft: boolean
): (boolean, string?)
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
	local armPart = getArmPart(player.Character, isLeft) or hrp
	local armOrigin = getHookOriginWorldPos(armPart, hrp, isLeft)
	local distance = (hitPosition - armOrigin).Magnitude
	if distance > HookConfig.MaxRange then
		return false, "Too far"
	end
	if not spendGas(player, HookConfig.HookCost) then
		return false, "Out of gas"
	end

	local key = isLeft and "left" or "right"
	local state = playerHooks[player.UserId]
	if state and state[key] then
		self:ReleaseHook(player, isLeft)
	end

	return doAttach(player, targetPart, hitPosition, isLeft)
end

function HookService:RequestFireHook(
	player: Player,
	origin: Vector3,
	direction: Vector3,
	isLeft: boolean
): (boolean, string?)
	if not player.Character then
		return false, "No character"
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "No HumanoidRootPart"
	end
	local dir = direction.Unit
	if not spendGas(player, HookConfig.HookCost) then
		return false, "Out of gas"
	end
	local key = isLeft and "left" or "right"
	local state = playerHooks[player.UserId]
	if state and state[key] then
		self:ReleaseHook(player, isLeft)
	end
	local cancel = playerProjectileCancel[player.UserId]
	if not cancel then
		playerProjectileCancel[player.UserId] = { left = false, right = false }
		cancel = playerProjectileCancel[player.UserId]
	end
	cancel[key] = false

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local pos = origin
	local startPos = origin
	local lastTick = tick()
	local result = Instance.new("BindableEvent")
	local conn: RBXScriptConnection?
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

	conn = RunService.Heartbeat:Connect(function()
		local cancel = playerProjectileCancel[player.UserId]
		if cancel and cancel[key] then
			if conn then
				conn:Disconnect()
			end
			projectileBeam:Destroy()
			result:Fire(false, "Cancelled")
			return
		end
		if not player.Character or not hrp.Parent then
			if conn then
				conn:Disconnect()
			end
			projectileBeam:Destroy()
			result:Fire(false, "Character lost")
			return
		end
		local now = tick()
		local delta = now - lastTick
		lastTick = now
		local step = dir * HookConfig.ProjectileSpeed * delta
		local newPos = pos + step
		local rayResult = Workspace:Raycast(pos, step, params)
		if rayResult then
			if conn then
				conn:Disconnect()
			end
			projectileBeam:Destroy()
			local dist = (rayResult.Position - startPos).Magnitude
			if dist <= HookConfig.MaxRange and rayResult.Instance:IsA("BasePart") then
				local ok, err = doAttach(player, rayResult.Instance, rayResult.Position, isLeft)
				result:Fire(ok, err)
			else
				result:Fire(false, "Invalid hit")
			end
			return
		end
		pos = newPos
		local armPart = getArmPart(player.Character, isLeft) or hrp
		local beamStart = getHookOriginWorldPos(armPart, hrp, isLeft)
		local beamDir = pos - beamStart
		local len = beamDir.Magnitude
		if len > 0.1 then
			beamDir = beamDir / len
			projectileBeam.Size = Vector3.new(HookConfig.BeamThickness, len, HookConfig.BeamThickness)
			local right = Vector3.new(-beamDir.Z, 0, beamDir.X)
			if right.Magnitude < 0.01 then
				right = Vector3.new(1, 0, 0)
			end
			projectileBeam.CFrame = CFrame.fromMatrix((beamStart + pos) / 2, right.Unit, beamDir)
			projectileBeam.Parent = Workspace
		end

		if (pos - startPos).Magnitude > HookConfig.MaxRange then
			if conn then
				conn:Disconnect()
			end
			projectileBeam:Destroy()
			result:Fire(false, "Too far")
		end
	end)

	local ok, err = result.Event:Wait()
	result:Destroy()
	return ok, err
end

function HookService:RequestJump(player: Player, isLeft: boolean): boolean
	local state = playerHooks[player.UserId]
	if not state or not player.Character then
		return false
	end
	if not (state.left or state.right) then
		return false
	end
	if not spendGas(player, HookConfig.JumpCost) then
		return false
	end

	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	local toAnchor = Vector3.zero
	if state.left then
		toAnchor = toAnchor + (state.left.TargetAtt.WorldPosition - hrp.Position).Unit
	end
	if state.right then
		toAnchor = toAnchor + (state.right.TargetAtt.WorldPosition - hrp.Position).Unit
	end
	local dir = toAnchor.Unit
	local velocity = hrp.AssemblyLinearVelocity
	local velMag = velocity.Magnitude
	local angleToDir = (velMag >= 0.1) and math.deg(math.acos(math.clamp(velocity.Unit:Dot(dir), -1, 1))) or 0

	if angleToDir > 90 then
		state.ReelEndTime = tick() + 0.2
	else
		state.JumpBoostEndTime = tick() + 0.2
	end
	return true
end

function HookService:RequestBoost(player: Player, isLeft: boolean): boolean
	local state = playerHooks[player.UserId]
	if not state or not player.Character then
		return false
	end
	local leftData = state.left
	local rightData = state.right
	if not leftData and not rightData then
		return false
	end
	if not spendGas(player, HookConfig.BoostCost) then
		return false
	end

	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	state.LastBoostTime = tick()
	if HookConfig.UseArmForce then
		return true
	end
	local toAnchor = Vector3.zero
	if leftData then
		toAnchor = toAnchor + (leftData.TargetAtt.WorldPosition - hrp.Position).Unit
	end
	if rightData then
		toAnchor = toAnchor + (rightData.TargetAtt.WorldPosition - hrp.Position).Unit
	end
	local dir = toAnchor.Unit
	local velocity = hrp.AssemblyLinearVelocity
	local momentumAlong = dir * (velocity:Dot(dir))
	local impulse = dir * HookConfig.JumpBoostForce + momentumAlong * HookConfig.MomentumRetention
	local currentVel = (
		state.LinearVelocity
		and state.LinearVelocity:IsA("LinearVelocity")
		and state.LinearVelocity.VectorVelocity
	) or hrp.AssemblyLinearVelocity
	local newVel = currentVel + impulse
	local velCap = HookConfig.LaunchVelocityCap or 400
	if newVel.Magnitude > velCap then
		newVel = newVel.Unit * velCap
	end
	local downwardCap = HookConfig.PullDownwardCap or 60
	local upwardCap = 80
	if newVel.Y < -downwardCap then
		newVel = Vector3.new(newVel.X, -downwardCap, newVel.Z)
	elseif newVel.Y > upwardCap then
		newVel = Vector3.new(newVel.X, upwardCap, newVel.Z)
	end
	if state.LinearVelocity and state.LinearVelocity:IsA("LinearVelocity") then
		state.LinearVelocity.VectorVelocity = newVel
	end
	hrp.AssemblyLinearVelocity = newVel
	return true
end

function HookService:ReleaseHook(player: Player, isLeft: boolean)
	local key = isLeft and "left" or "right"
	local cancel = playerProjectileCancel[player.UserId]
	if not cancel then
		playerProjectileCancel[player.UserId] = { left = false, right = false }
		cancel = playerProjectileCancel[player.UserId]
	end
	cancel[key] = true

	local state = playerHooks[player.UserId]
	if not state then
		return
	end

	local data = state[key]
	if data then
		releaseHookData(data)
		state[key] = nil
	end

	if not state.left and not state.right then
		local hrp0 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp0 then
			local ret = HookConfig.ReleaseVelocityRetention or 1
			if ret < 1 then
				local v = hrp0.AssemblyLinearVelocity
				hrp0.AssemblyLinearVelocity = v * ret
			end
		end
		if state.HeartbeatConn then
			state.HeartbeatConn:Disconnect()
		end
		if state.RagdollPostSimConn then
			state.RagdollPostSimConn:Disconnect()
		end
		if state.LinearVelocity then
			state.LinearVelocity:Destroy()
		end
		if state.VelocityAttachment then
			state.VelocityAttachment:Destroy()
		end
		if state.GravityForce then
			state.GravityForce:Destroy()
		end
		if state.GravityAttachment then
			state.GravityAttachment:Destroy()
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
		end
		if state.RagdollPreventionConn then
			state.RagdollPreventionConn:Disconnect()
			state.RagdollPreventionConn = nil
		end
		if state.LimbCollisionBackup then
			for _, entry in state.LimbCollisionBackup do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = entry.canCollide
				end
			end
			state.LimbCollisionBackup = nil
		end
		playerHooks[player.UserId] = nil
		playerReelForce[player.UserId] = nil
		playerSwingForce[player.UserId] = nil
	end
end

function HookService:SetSwingForce(player: Player, force: number)
	local clamped = math.clamp(force, -1, 1)
	playerSwingForce[player.UserId] = clamped
end

function HookService.Client:SetSwingForce(player: Player, force: number)
	self.Server:SetSwingForce(player, force)
end

function HookService.Client:RequestHook(player: Player, targetPart: BasePart, hitPosition: Vector3, isLeft: boolean)
	return self.Server:RequestHook(player, targetPart, hitPosition, isLeft)
end

function HookService.Client:RequestFireHook(player: Player, origin: Vector3, direction: Vector3, isLeft: boolean)
	return self.Server:RequestFireHook(player, origin, direction, isLeft)
end

function HookService.Client:ReleaseHook(player: Player, isLeft: boolean)
	self.Server:ReleaseHook(player, isLeft)
end

function HookService.Client:RequestJump(player: Player, isLeft: boolean)
	return self.Server:RequestJump(player, isLeft)
end

function HookService.Client:RequestBoost(player: Player, isLeft: boolean)
	return self.Server:RequestBoost(player, isLeft)
end

function HookService:GetGas(player: Player): number
	return getGas(player)
end

function HookService:SetReelForce(player: Player, force: number)
	playerReelForce[player.UserId] = force
end

function HookService.Client:SetReelForce(player: Player, force: number)
	self.Server:SetReelForce(player, force)
end

function HookService.Client:GetGas(player: Player)
	return self.Server:GetGas(player)
end

function HookService:GetDebugData(player: Player): { [string]: any }
	local state = playerHooks[player.UserId]
	local gas = getGas(player)
	local leftLen, rightLen = nil, nil
	if state then
		if state.left and state.left.Constraint then
			leftLen = state.left.Constraint:IsA("SpringConstraint") and state.left.Constraint.FreeLength
				or (state.left.Constraint :: RopeConstraint).Length
		end
		if state.right and state.right.Constraint then
			rightLen = state.right.Constraint:IsA("SpringConstraint") and state.right.Constraint.FreeLength
				or (state.right.Constraint :: RopeConstraint).Length
		end
	end
	return {
		gas = gas,
		reelForce = playerReelForce[player.UserId] or 0,
		swingForce = playerSwingForce[player.UserId] or 0,
		hasLeft = state and state.left ~= nil,
		hasRight = state and state.right ~= nil,
		leftRopeLen = leftLen,
		rightRopeLen = rightLen,
	}
end

function HookService:KnitInit()
	for _, player in Players:GetPlayers() do
		playerGas[player.UserId] = HookConfig.MaxGas
	end
	Players.PlayerAdded:Connect(function(player)
		playerGas[player.UserId] = HookConfig.MaxGas
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = playerHooks[player.UserId]
		if state then
			if state.left then
				releaseHookData(state.left)
			end
			if state.right then
				releaseHookData(state.right)
			end
			if state.HeartbeatConn then
				state.HeartbeatConn:Disconnect()
			end
			if state.LinearVelocity then
				state.LinearVelocity:Destroy()
			end
			if state.VelocityAttachment then
				state.VelocityAttachment:Destroy()
			end
		end
		playerHooks[player.UserId] = nil
		playerGas[player.UserId] = nil
		playerProjectileCancel[player.UserId] = nil
		playerReelForce[player.UserId] = nil
		playerSwingForce[player.UserId] = nil
	end)
	local lastGasRegenTick = tick()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local dt = now - lastGasRegenTick
		lastGasRegenTick = now
		for _, player in Players:GetPlayers() do
			if not playerHooks[player.UserId] and player.Character then
				regenGas(player, dt)
			end
		end
	end)
end

return HookService
