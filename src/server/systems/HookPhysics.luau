--[[
	HookPhysics
	Purpose:
	Provide physics-only calculations and force/velocity helpers for grappling movement.
	Used by HookService during PreSimulation and PostSimulation update loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local HookTypes = require(script.Parent.HookTypes)
type HookData = HookTypes.HookData

local UP = Vector3.new(0, 1, 0)

-- Rotate vector `from` toward `to` by at most `maxRad` radians.
-- Used when reeling in at an angle: gradually align velocity with anchor direction.
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

local function isRagdollState(state: Enum.HumanoidStateType): boolean
	return state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Physics
end

-- Initial launch impulse when NoAutoPull is false. Pulls player toward hit position.
local function applyLaunchImpulse(humanoidRootPart: BasePart, hitPosition: Vector3)
	local mult = HookConfig.LaunchForceMultiplier or 12
	local minY = HookConfig.LaunchVerticalMin or 15
	local toTarget = (hitPosition - humanoidRootPart.Position).Unit * mult
	if toTarget.Y < minY then
		toTarget = toTarget + Vector3.new(0, math.min(minY - toTarget.Y, 20), 0)
	end
	if hitPosition.Y >= humanoidRootPart.Position.Y then
		local extraY = math.min((hitPosition.Y - humanoidRootPart.Position.Y) * 0.5, 25)
		toTarget = toTarget + Vector3.new(0, extraY, 0)
	end
	local currentVel = humanoidRootPart.AssemblyLinearVelocity
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
	humanoidRootPart.AssemblyLinearVelocity = newVel
end

-- Pendulum kick when UseArmForce: give tangential velocity so swing starts.
local function applyPendulumKick(humanoidRootPart: BasePart, hitPosition: Vector3)
	local toTarget = (hitPosition - humanoidRootPart.Position).Unit
	local tangent = toTarget:Cross(UP)
	if tangent.Magnitude <= 0.01 then
		return
	end
	tangent = tangent.Unit
	local kick = HookConfig.PendulumKickSpeed or 18
	local rootVelocity = humanoidRootPart.AssemblyLinearVelocity
	if rootVelocity.Magnitude < kick * 0.5 then
		humanoidRootPart.AssemblyLinearVelocity = rootVelocity + tangent * kick
	end
end

-- Pendulum nudge: when velocity is low and not boosting, nudge tangent to rope to keep swing alive.
local function applyPendulumNudge(
	humanoidRootPart: BasePart,
	firstHookData: HookData,
	boostWindow: boolean,
	swingForce: number,
	rootVelocityMagnitude: number
)
	if boostWindow or swingForce ~= 0 then
		return
	end
	local threshold = HookConfig.PendulumNudgeVelThreshold or 10
	if rootVelocityMagnitude >= threshold then
		return
	end
	local toTarget = (firstHookData.TargetAtt.WorldPosition - firstHookData.PlayerAtt.WorldPosition).Unit
	local tangent = toTarget:Cross(UP)
	if tangent.Magnitude <= 0.01 then
		return
	end
	tangent = tangent.Unit
	local nudgeSpeed = HookConfig.PendulumNudgeSpeed or 22
	humanoidRootPart.AssemblyLinearVelocity = tangent * nudgeSpeed
end

-- Compute rope length delta from reel input (W/S or similar).
-- Positive = shorten (reel in), negative = extend. Zero when no reel input.
local function computeRopeDelta(reelForceValue: number, delta: number): number
	if reelForceValue > 0 then
		local shortenSpeed = HookConfig.RopeShortenSpeed or 28
		local reelMult = HookConfig.RopeReelInMultiplier or 1.0
		return shortenSpeed * reelMult * delta
	elseif reelForceValue < 0 then
		local extendSpeed = HookConfig.RopeExtendSpeed or 22
		return -extendSpeed * delta
	end
	return 0
end

-- Update arm VectorForce for UseArmForce mode. Applies pull toward target with ramp and swing.
local function updateArmForce(
	hookData: HookData,
	humanoidRootPart: BasePart,
	boostWindow: boolean,
	reelForceValue: number,
	swingForce: number,
	now: number
)
	if not hookData.ArmForce then
		return
	end

	-- In NoAutoPull mode, arm force is only applied during boost window.
	-- In regular mode, force always applies and increases while reeling in.
	local function getForceMagnitude(): number
		local rampSeconds = HookConfig.ArmForceRampUpSec or 0.4
		local elapsed = now - (hookData.AttachTime or now)
		local ramp = rampSeconds > 0 and math.min(1, elapsed / rampSeconds) or 1

		if HookConfig.NoAutoPull then
			if not boostWindow then
				return 0
			end
			return (HookConfig.ArmPullForce or 3500) * ramp
		end

		local forceMagnitude = HookConfig.ArmPullForce or 3500
		if reelForceValue > 0 then
			forceMagnitude = HookConfig.ArmReelForce or 7000
		end
		return forceMagnitude * ramp
	end

	local toTarget = (hookData.TargetAtt.WorldPosition - hookData.PlayerAtt.WorldPosition).Unit
	local forceMagnitude = getForceMagnitude()
	local force = toTarget * forceMagnitude
	if boostWindow then
		force = force + (humanoidRootPart.CFrame.LookVector * (HookConfig.ArmBoostForce or 100))
	end
	if swingForce ~= 0 then
		local right = toTarget:Cross(UP).Unit
		if right.Magnitude < 0.01 then
			right = humanoidRootPart.CFrame.RightVector
		end
		force = force + right * (swingForce * (HookConfig.SwingForce or 35) * 80)
	end
	hookData.ArmForce.Force = force
end

-- Compute base velocity for grapple physics mode (direct velocity toward anchor).
local function computeGrappleVelocity(
	humanoidRootPart: BasePart,
	goalPos: Vector3,
	dir: Vector3,
	distToGoal: number,
	hasDualHooks: boolean,
	reelForceValue: number,
	swingForce: number,
	boostWindow: boolean,
	velocity: Vector3
): Vector3?
	local grappleSpeed = hasDualHooks and (HookConfig.GrappleSpeedDual or 300) or (HookConfig.GrappleSpeedSingle or 150)
	local multiplier = 1
	if reelForceValue > 0 then
		multiplier = HookConfig.ReelInSpeedMultiplier or 2.2
	elseif reelForceValue < 0 then
		return velocity * (HookConfig.NoAutoPullVelocityRetention or 0.98)
	end
	local stopNearDist = HookConfig.StopNearAnchorDist or 2
	local orbitVelocity = Vector3.zero
	if swingForce ~= 0 and multiplier > 0 then
		local orbitAngle = (HookConfig.OrbitAngleRad or (math.pi / 2.4)) * -swingForce
		local orbitDir = (CFrame.lookAt(humanoidRootPart.Position, goalPos) * CFrame.Angles(0, orbitAngle, 0)).LookVector
		orbitVelocity = orbitDir * (HookConfig.OrbitSpeed or 110)
	end
	if multiplier <= 0 then
		return nil
	end
	if distToGoal < stopNearDist then
		return Vector3.zero
	end
	local baseVel = dir * (grappleSpeed * multiplier) + orbitVelocity
	if boostWindow then
		baseVel = baseVel + (humanoidRootPart.CFrame.LookVector * (HookConfig.GasBoostAdd or 150))
	end
	return baseVel
end

-- Compute base velocity for pendulum mode (momentum-based swing).
local function computePendulumVelocity(
	dir: Vector3,
	velocity: Vector3,
	velocityMag: number,
	reelForceValue: number,
	swingForce: number,
	boostWindow: boolean,
	playerState: any,
	now: number,
	delta: number,
	pullForce: number,
	reelInPull: number,
	humanoidRootPart: BasePart
): Vector3
	local momentumAlong = dir * (velocity:Dot(dir))
	local reelAngle = HookConfig.ReelAngleRad * (1 + reelForceValue)
	local velMagForAngle = velocity.Magnitude
	local angleToDir = (velMagForAngle >= 0.1)
			and math.deg(math.acos(math.clamp(velocity.Unit:Dot(dir), -1, 1)))
		or 0
	local canReel = (angleToDir > 90) and (playerState.ReelEndTime and now < playerState.ReelEndTime)
	local baseVel: Vector3
	if canReel and velMagForAngle >= 0.1 then
		local speed = velocityMag + (HookConfig.ReelSpeedRetention or 0.1)
		baseVel = rotateTowards(velocity, dir, reelAngle) * speed
	elseif HookConfig.NoAutoPull and reelForceValue <= 0 then
		playerState.ReelEndTime = nil
		playerState.JumpBoostEndTime = nil
		baseVel = velocity * (HookConfig.NoAutoPullVelocityRetention or 0.98)
		if boostWindow then
			baseVel = baseVel + dir * ((HookConfig.BoostThrustForce or 140) * delta)
		end
	elseif reelForceValue > 0 then
		playerState.ReelEndTime = nil
		playerState.JumpBoostEndTime = nil
		baseVel = dir * reelInPull + momentumAlong * HookConfig.VelocityScaleMultiplier
	else
		playerState.ReelEndTime = nil
		if playerState.JumpBoostEndTime and now < playerState.JumpBoostEndTime then
			baseVel = dir * pullForce
				+ momentumAlong * HookConfig.VelocityScaleMultiplier
				+ Vector3.new(0, HookConfig.JumpForce, 0)
		else
			playerState.JumpBoostEndTime = nil
			baseVel = dir * pullForce + momentumAlong * HookConfig.VelocityScaleMultiplier
		end
	end
	if swingForce ~= 0 then
		local right = dir:Cross(UP).Unit
		if right.Magnitude < 0.01 then
			right = humanoidRootPart.CFrame.RightVector
		end
		baseVel = baseVel + right * (swingForce * (HookConfig.SwingForce or 15))
	end
	local momentum = HookConfig.PendulumMomentum or 0.6
	if boostWindow then
		momentum = HookConfig.BoostPendulumMomentum or 0.35
	elseif reelForceValue > 0 then
		momentum = HookConfig.ReelPendulumMomentum or 0.4
	end
	return velocity * momentum + baseVel * (1 - momentum)
end

-- Apply velocity caps (launch cap, downward cap) to base velocity.
local function applyVelocityCaps(baseVel: Vector3): Vector3
	local launchCap = HookConfig.LaunchVelocityCap or 400
	if baseVel.Magnitude > launchCap then
		baseVel = baseVel.Unit * launchCap
	end
	local downwardCap = HookConfig.PullDownwardCap or 60
	if baseVel.Y < -downwardCap then
		baseVel = Vector3.new(baseVel.X, -downwardCap, baseVel.Z)
	end
	return baseVel
end

return {
	rotateTowards = rotateTowards,
	isRagdollState = isRagdollState,
	applyLaunchImpulse = applyLaunchImpulse,
	applyPendulumKick = applyPendulumKick,
	applyPendulumNudge = applyPendulumNudge,
	computeRopeDelta = computeRopeDelta,
	updateArmForce = updateArmForce,
	computeGrappleVelocity = computeGrappleVelocity,
	computePendulumVelocity = computePendulumVelocity,
	applyVelocityCaps = applyVelocityCaps,
	UP = UP,
}
