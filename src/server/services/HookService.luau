--[[
	HookService
	============================================================================
	Grappling hook movement system for Roblox. Manages hook mechanics, validates
	requests, coordinates subsystems, and maintains per-player hook state.

	Responsibilities:
	• Handle remote events from client (RequestHook, RequestFireHook, ReleaseHook, etc.)
	• Validate hook targets (range, gas, character)
	• Coordinate HookConstraints, HookVisual, HookProjectile, HookPhysics, HookGas
	• Maintain player hook state (left/right hooks, velocity mover, ragdoll prevention)

	Client Flow:
	• Client → RequestHook(targetPart, hitPosition, isLeft) — direct attach at hit
	• Client → RequestFireHook(origin, direction, isLeft) — projectile phase, raycast until hit
	• Client → ReleaseHook(isLeft) — detach one hook
	• Client → RequestJump(isLeft) — jump while hooked (reel or boost based on angle)
	• Client → RequestBoost(isLeft) — add impulse toward anchor
	• Client → SetReelForce(force), SetSwingForce(force) — input for reel/swing
	• Client → GetGas() — current gas amount

	Server Flow:
	1. Validate: character, HumanoidRootPart, target, range, gas
	2. Spend gas (HookGas)
	3. Release existing hook if re-attaching same side
	4. Create attachments (HookConstraints)
	5. Create rope/spring constraint (HookConstraints)
	6. Create beam visual (HookVisual)
	7. Create optional arm VectorForce (HookConstraints)
	8. Initialize player state (velocity mover, gravity reduction, ragdoll prevention)
	9. Apply initial launch impulse or pendulum kick (HookPhysics)
	10. Connect PreSimulation: rope/beam update, velocity, arm force
	11. Connect PostSimulation: ragdoll recovery, pendulum nudge

	Physics Processing (PreSimulation each frame):
	• Update rope length from reel input
	• Update beam visuals (HookVisual.updateRopeAndBeam)
	• Compute swing velocity (HookPhysics: grapple or pendulum mode)
	• Apply arm force (HookPhysics.updateArmForce) when UseArmForce
	• Apply velocity via LinearVelocity/VectorForce or AssemblyLinearVelocity

	Gas Consumption:
	• HookCost on fire, BoostCost on boost, JumpCost on jump
	• Regen when not hooked (HookGas.regenGas in Heartbeat)
	============================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local systems = script.Parent.Parent.systems
local HookConstraints = require(systems.HookConstraints)
local HookVisual = require(systems.HookVisual)
local HookProjectile = require(systems.HookProjectile)
local HookPhysics = require(systems.HookPhysics)
local HookGas = require(systems.HookGas)
local HookTypes = require(systems.HookTypes)

type HookData = HookTypes.HookData
type PlayerHookState = HookTypes.PlayerHookState

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

local playerHooks: { [number]: PlayerHookState? } = {}
local playerProjectileCancel: { [number]: { left: boolean, right: boolean } } = {}
local playerReelForce: { [number]: number } = {}
local playerSwingForce: { [number]: number } = {}

local function getArmPart(character: Model, isLeft: boolean): BasePart?
	return HookProjectile.getArmPart(character, isLeft)
end

local function getHookOriginWorldPos(armPart: BasePart, humanoidRootPart: BasePart, isLeft: boolean): Vector3
	return HookProjectile.getHookOriginWorldPos(armPart, humanoidRootPart, isLeft)
end

-- Core attach: create constraint, beam, attachments; set up heartbeat physics.
local function doAttach(player: Player, targetPart: BasePart, hitPosition: Vector3, isLeft: boolean): (boolean, string?)
	local humanoidRootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No character"
	end

	local key = isLeft and "left" or "right"
	local armPart = getArmPart(player.Character :: Model, isLeft) or humanoidRootPart
	local playerState = playerHooks[player.UserId]
	if playerState and playerState[key] then
		HookConstraints.releaseHookData(playerState[key])
		playerState[key] = nil
	end

	local worldPos = getHookOriginWorldPos(armPart, humanoidRootPart, isLeft)
	local playerAttachment = HookConstraints.createPlayerAttachment(armPart, worldPos, isLeft)
	local targetAttachment = HookConstraints.createTargetAttachment(targetPart, hitPosition)
	local distance = (hitPosition - playerAttachment.WorldPosition).Magnitude

	local constraint = HookConstraints.createConstraint(playerAttachment, targetAttachment, distance, isLeft)
	local beam = HookVisual.createBeam(playerAttachment, targetAttachment, distance, isLeft)
	local armForce = HookConstraints.createArmForce(playerAttachment, isLeft)

	local hookData: HookData = {
		Constraint = constraint,
		BeamPart = beam,
		Attachments = { playerAttachment, targetAttachment },
		PlayerAtt = playerAttachment,
		TargetAtt = targetAttachment,
		ArmForce = armForce,
		AttachTime = tick(),
	}

	-- First hook: create velocity mover, gravity reduction, state.
	if not playerState then
		local velocityAttachment = (not HookConfig.UseArmForce) and Instance.new("Attachment") or nil
		if velocityAttachment then
			velocityAttachment.Name = "HookVelocityAttachment"
			velocityAttachment.Parent = humanoidRootPart
		end
		local mover = HookConstraints.createVelocityMover(humanoidRootPart, velocityAttachment)
		local gravityForce, gravityAttachment = HookConstraints.createGravityReduction(humanoidRootPart)
		playerState = {
			left = nil,
			right = nil,
			LinearVelocity = mover,
			VelocityAttachment = velocityAttachment,
			GravityForce = gravityForce,
			GravityAttachment = gravityAttachment,
			LastTick = tick(),
			JumpBoostEndTime = nil,
			ReelEndTime = nil,
			LastBoostTime = nil :: number?,
			HeartbeatConn = nil :: any,
		}
		playerHooks[player.UserId] = playerState
	end
	playerState[key] = hookData

	-- Ragdoll prevention: disable ragdoll/falling, force PlatformStanding if triggered.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		if playerState.RagdollPreventionConn then
			playerState.RagdollPreventionConn:Disconnect()
		end
		playerState.RagdollPreventionConn = humanoid.StateChanged:Connect(function(_old, new)
			if HookPhysics.isRagdollState(new) then
				task.defer(function()
					if humanoid and humanoid.Parent then
						humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
					end
				end)
			end
		end)
		if HookConfig.DisableLimbCollisionWhenHooked and player.Character then
			playerState.LimbCollisionBackup = {}
			for _, desc in player.Character:GetDescendants() do
				if desc:IsA("BasePart") and desc ~= humanoidRootPart then
					table.insert(playerState.LimbCollisionBackup, { part = desc, canCollide = desc.CanCollide })
					desc.CanCollide = false
				end
			end
		end
	end

	-- Initial impulse: launch toward target or pendulum kick.
	if not HookConfig.NoAutoPull and not HookConfig.UseArmForce then
		HookPhysics.applyLaunchImpulse(humanoidRootPart, hitPosition)
	elseif HookConfig.UseArmForce then
		HookPhysics.applyPendulumKick(humanoidRootPart, hitPosition)
	end

	-- PreSimulation: rope/beam, velocity; PostSimulation: ragdoll recovery, pendulum nudge.
	if not playerState.HeartbeatConn then
		playerState.RagdollPostSimConn = RunService.PostSimulation:Connect(function()
			local state = playerHooks[player.UserId]
			if not state or not player.Character or (not state.left and not state.right) then
				return
			end
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hum and hrp and HookPhysics.isRagdollState(hum:GetState()) then
				hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)
			end
			if HookConfig.UseArmForce then
				local firstData = state.left or state.right
				if firstData then
					local boostWindow = state.LastBoostTime and (tick() - state.LastBoostTime) < 0.6
					local swingVal = playerSwingForce[player.UserId] or 0
					local rootVel = hrp.AssemblyLinearVelocity
					HookPhysics.applyPendulumNudge(hrp, firstData, boostWindow, swingVal, rootVel.Magnitude)
				end
			end
		end)
		playerState.HeartbeatConn = RunService.PreSimulation:Connect(function()
			local state = playerHooks[player.UserId]
			if not state or not player.Character or humanoidRootPart.Parent ~= player.Character then
				if state then
					if state.HeartbeatConn then
						state.HeartbeatConn:Disconnect()
					end
					if state.RagdollPostSimConn then
						state.RagdollPostSimConn:Disconnect()
					end
				end
				return
			end
			local leftData = state.left
			local rightData = state.right
			if not leftData and not rightData then
				return
			end
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum and HookPhysics.isRagdollState(hum:GetState()) then
				hum:ChangeState(Enum.HumanoidStateType.PlatformStanding)
			end
			local velCap = HookConfig.MaxVelocityWhileHooked
			if velCap and velCap > 0 then
				local rootVel = humanoidRootPart.AssemblyLinearVelocity
				if rootVel.Magnitude > velCap then
					humanoidRootPart.AssemblyLinearVelocity = rootVel.Unit * velCap
				end
			end
			-- Void kill: below VoidFloorY, release all hooks and dampen velocity.
			-- Prevents players from falling infinitely; applies horizontal dampening and caps downward speed.
			local voidFloor = HookConfig.VoidFloorY or -350
			if humanoidRootPart.Position.Y < voidFloor then
				if leftData then
					HookConstraints.releaseHookData(leftData)
					state.left = nil
				end
				if rightData then
					HookConstraints.releaseHookData(rightData)
					state.right = nil
				end
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new(
					humanoidRootPart.AssemblyLinearVelocity.X * 0.3,
					math.max(humanoidRootPart.AssemblyLinearVelocity.Y, -60),
					humanoidRootPart.AssemblyLinearVelocity.Z * 0.3
				)
				if state.HeartbeatConn then
					state.HeartbeatConn:Disconnect()
					state.HeartbeatConn = nil
				end
				if state.RagdollPostSimConn then
					state.RagdollPostSimConn:Disconnect()
					state.RagdollPostSimConn = nil
				end
				return
			end

			local now = tick()
			local delta = now - (state.LastTick or now)
			state.LastTick = now

			local rootVelocity = humanoidRootPart.AssemblyLinearVelocity
			local velocityMag = rootVelocity.Magnitude
			local sway = math.sin(now * HookConfig.RopeSwayFrequency)
				* HookConfig.RopeSwayAmplitude
				* (1 + velocityMag * 0.01)
			local pullForce = (leftData and rightData) and HookConfig.PullForceDual or HookConfig.PullForceSingle
			local reelInPull = HookConfig.ReelInPullForce or pullForce
			local reelForceVal = math.clamp(
				playerReelForce[player.UserId] or 0,
				-HookConfig.ReelForceRange,
				HookConfig.ReelForceRange
			)
			local boostWindow = state.LastBoostTime and (now - state.LastBoostTime) < 0.6
			-- Rope length change: positive = shorten (reel in), negative = extend.
			local ropeDelta = HookPhysics.computeRopeDelta(reelForceVal, delta)

			-- Accumulate direction to anchor from each hook for velocity and orientation.
			local toAnchor = Vector3.zero
			if leftData then
				toAnchor = toAnchor
					+ HookVisual.updateRopeAndBeam(
						leftData,
						ropeDelta,
						sway,
						humanoidRootPart,
						HookConfig.BeamThickness,
						HookConfig.MaxRange
					)
			end
			if rightData then
				toAnchor = toAnchor
					+ HookVisual.updateRopeAndBeam(
						rightData,
						ropeDelta,
						sway,
						humanoidRootPart,
						HookConfig.BeamThickness,
						HookConfig.MaxRange
					)
			end

			local goalPos = (leftData and rightData)
					and ((leftData.TargetAtt.WorldPosition + rightData.TargetAtt.WorldPosition) / 2)
				or (leftData and leftData.TargetAtt.WorldPosition or rightData.TargetAtt.WorldPosition)
			if (not HookConfig.UseArmForce) and HookConfig.OrientToAnchor and toAnchor.Magnitude > 0.01 then
				local targetCF = CFrame.lookAt(humanoidRootPart.Position, goalPos)
				humanoidRootPart.CFrame = humanoidRootPart.CFrame:Lerp(
					targetCF,
					math.min(1, HookConfig.OrientLerpSpeed * delta)
				)
			end

			local dir = toAnchor.Unit
			local swingVal = playerSwingForce[player.UserId] or 0
			local distToGoal = (goalPos - humanoidRootPart.Position).Magnitude
			local hasDualHooks = leftData and rightData

			local baseVel: Vector3?
			if HookConfig.UseGrapplePhysics then
				baseVel = HookPhysics.computeGrappleVelocity(
					humanoidRootPart,
					goalPos,
					dir,
					distToGoal,
					hasDualHooks,
					reelForceVal,
					swingVal,
					boostWindow,
					rootVelocity
				)
				if
					not HookConfig.UseArmForce
					and (HookConfig.OrientToGoal or HookConfig.OrientToAnchor)
					and dir.Magnitude > 0.01
				then
					local targetCF = CFrame.lookAt(humanoidRootPart.Position, goalPos)
					humanoidRootPart.CFrame = humanoidRootPart.CFrame:Lerp(
						targetCF,
						math.min(1, (HookConfig.OrientLerpSpeed or 12) * delta)
					)
				end
			else
				baseVel = HookPhysics.computePendulumVelocity(
					dir,
					rootVelocity,
					velocityMag,
					reelForceVal,
					swingVal,
					boostWindow,
					state,
					now,
					delta,
					pullForce,
					reelInPull,
					humanoidRootPart
				)
			end

			if HookConfig.UseArmForce then
				if leftData then
					HookPhysics.updateArmForce(leftData, humanoidRootPart, boostWindow, reelForceVal, swingVal, now)
				end
				if rightData then
					HookPhysics.updateArmForce(rightData, humanoidRootPart, boostWindow, reelForceVal, swingVal, now)
				end
			else
				if baseVel then
					baseVel = HookPhysics.applyVelocityCaps(baseVel)
				end
				if state.LinearVelocity then
					if state.LinearVelocity:IsA("VectorForce") then
						local mag = HookConfig.VectorForceMagnitude or 12000
						local targetSpeed = hasDualHooks and (HookConfig.GrappleSpeedDual or 300)
							or (HookConfig.GrappleSpeedSingle or 150)
						if boostWindow then
							targetSpeed = targetSpeed + (HookConfig.GasBoostAdd or 150)
						end
						if velocityMag < targetSpeed * 0.95 and baseVel and baseVel.Magnitude > 0.01 then
							state.LinearVelocity.Force = baseVel.Unit * mag
						else
							state.LinearVelocity.Force = Vector3.zero
						end
					else
						state.LinearVelocity.VectorVelocity = baseVel or Vector3.zero
					end
				end
				humanoidRootPart.AssemblyLinearVelocity = baseVel or Vector3.zero
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
	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No HumanoidRootPart"
	end
	if not targetPart or not targetPart:IsA("BasePart") then
		return false, "Invalid target"
	end
	local armPart = getArmPart(player.Character, isLeft) or humanoidRootPart
	local armOrigin = getHookOriginWorldPos(armPart, humanoidRootPart, isLeft)
	local distance = (hitPosition - armOrigin).Magnitude
	if distance > HookConfig.MaxRange then
		return false, "Too far"
	end
	if not HookGas.spendGas(player, HookConfig.HookCost) then
		return false, "Out of gas"
	end
	local key = isLeft and "left" or "right"
	local playerState = playerHooks[player.UserId]
	if playerState and playerState[key] then
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
	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, "No HumanoidRootPart"
	end
	if not HookGas.spendGas(player, HookConfig.HookCost) then
		return false, "Out of gas"
	end
	local key = isLeft and "left" or "right"
	local playerState = playerHooks[player.UserId]
	if playerState and playerState[key] then
		self:ReleaseHook(player, isLeft)
	end
	local cancel = playerProjectileCancel[player.UserId]
	if not cancel then
		playerProjectileCancel[player.UserId] = { left = false, right = false }
		cancel = playerProjectileCancel[player.UserId]
	end
	cancel[key] = false

	local cancelCheck = function()
		local c = playerProjectileCancel[player.UserId]
		return c and c[key]
	end
	local onAttach = function(targetPart: BasePart, hitPosition: Vector3)
		return doAttach(player, targetPart, hitPosition, isLeft)
	end
	return HookProjectile.fireProjectile(
		player,
		origin,
		direction,
		isLeft,
		humanoidRootPart,
		cancelCheck,
		onAttach
	)
end

function HookService:RequestJump(player: Player, isLeft: boolean): boolean
	local playerState = playerHooks[player.UserId]
	if not playerState or not player.Character then
		return false
	end
	if not (playerState.left or playerState.right) then
		return false
	end
	if not HookGas.spendGas(player, HookConfig.JumpCost) then
		return false
	end
	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end
	local toAnchor = Vector3.zero
	if playerState.left then
		toAnchor = toAnchor + (playerState.left.TargetAtt.WorldPosition - humanoidRootPart.Position).Unit
	end
	if playerState.right then
		toAnchor = toAnchor + (playerState.right.TargetAtt.WorldPosition - humanoidRootPart.Position).Unit
	end
	local dir = toAnchor.Unit
	local velocity = humanoidRootPart.AssemblyLinearVelocity
	local velMag = velocity.Magnitude
	local angleToDir = (velMag >= 0.1) and math.deg(math.acos(math.clamp(velocity.Unit:Dot(dir), -1, 1))) or 0
	if angleToDir > 90 then
		playerState.ReelEndTime = tick() + 0.2
	else
		playerState.JumpBoostEndTime = tick() + 0.2
	end
	return true
end

function HookService:RequestBoost(player: Player, isLeft: boolean): boolean
	local playerState = playerHooks[player.UserId]
	if not playerState or not player.Character then
		return false
	end
	local leftData = playerState.left
	local rightData = playerState.right
	if not leftData and not rightData then
		return false
	end
	if not HookGas.spendGas(player, HookConfig.BoostCost) then
		return false
	end
	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end
	playerState.LastBoostTime = tick()
	if HookConfig.UseArmForce then
		return true
	end
	local toAnchor = Vector3.zero
	if leftData then
		toAnchor = toAnchor + (leftData.TargetAtt.WorldPosition - humanoidRootPart.Position).Unit
	end
	if rightData then
		toAnchor = toAnchor + (rightData.TargetAtt.WorldPosition - humanoidRootPart.Position).Unit
	end
	local dir = toAnchor.Unit
	local velocity = humanoidRootPart.AssemblyLinearVelocity
	local momentumAlong = dir * (velocity:Dot(dir))
	local impulse = dir * HookConfig.JumpBoostForce + momentumAlong * HookConfig.MomentumRetention
	local currentVel = (
		playerState.LinearVelocity
		and playerState.LinearVelocity:IsA("LinearVelocity")
		and playerState.LinearVelocity.VectorVelocity
	) or humanoidRootPart.AssemblyLinearVelocity
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
	if playerState.LinearVelocity and playerState.LinearVelocity:IsA("LinearVelocity") then
		playerState.LinearVelocity.VectorVelocity = newVel
	end
	humanoidRootPart.AssemblyLinearVelocity = newVel
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

	local playerState = playerHooks[player.UserId]
	if not playerState then
		return
	end
	local hookData = playerState[key]
	if hookData then
		HookConstraints.releaseHookData(hookData)
		playerState[key] = nil
	end

	if not playerState.left and not playerState.right then
		local humanoidRootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local retention = HookConfig.ReleaseVelocityRetention or 1
			if retention < 1 then
				local rootVel = humanoidRootPart.AssemblyLinearVelocity
				humanoidRootPart.AssemblyLinearVelocity = rootVel * retention
			end
		end
		if playerState.HeartbeatConn then
			playerState.HeartbeatConn:Disconnect()
		end
		if playerState.RagdollPostSimConn then
			playerState.RagdollPostSimConn:Disconnect()
		end
		if playerState.LinearVelocity then
			playerState.LinearVelocity:Destroy()
		end
		if playerState.VelocityAttachment then
			playerState.VelocityAttachment:Destroy()
		end
		if playerState.GravityForce then
			playerState.GravityForce:Destroy()
		end
		if playerState.GravityAttachment then
			playerState.GravityAttachment:Destroy()
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
		end
		if playerState.RagdollPreventionConn then
			playerState.RagdollPreventionConn:Disconnect()
			playerState.RagdollPreventionConn = nil
		end
		if playerState.LimbCollisionBackup then
			for _, entry in playerState.LimbCollisionBackup do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = entry.canCollide
				end
			end
			playerState.LimbCollisionBackup = nil
		end
		playerHooks[player.UserId] = nil
		playerReelForce[player.UserId] = nil
		playerSwingForce[player.UserId] = nil
	end
end

function HookService:SetSwingForce(player: Player, force: number)
	playerSwingForce[player.UserId] = math.clamp(force, -1, 1)
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
	return HookGas.getGas(player)
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
	local playerState = playerHooks[player.UserId]
	local gas = HookGas.getGas(player)
	local leftLen, rightLen = nil, nil
	local distToAnchor, toTargetX, toTargetY, toTargetZ = nil, nil, nil, nil
	local pullForce, grappleSpeed, pendulumMomentum, gravityScale = nil, nil, nil, nil
	if playerState then
		if playerState.left and playerState.left.Constraint then
			leftLen = playerState.left.Constraint:IsA("SpringConstraint") and playerState.left.Constraint.FreeLength
				or (playerState.left.Constraint :: RopeConstraint).Length
		end
		if playerState.right and playerState.right.Constraint then
			rightLen = playerState.right.Constraint:IsA("SpringConstraint") and playerState.right.Constraint.FreeLength
				or (playerState.right.Constraint :: RopeConstraint).Length
		end
	end
	local function isHookActive(data)
		return data and data.Constraint and data.Constraint.Parent ~= nil
	end
	local hasLeft = playerState and isHookActive(playerState.left)
	local hasRight = playerState and isHookActive(playerState.right)
	if (hasLeft or hasRight) and player.Character then
		local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			local pos = humanoidRootPart.Position
			local goalPos
			if hasLeft and hasRight then
				goalPos = (playerState.left.TargetAtt.WorldPosition + playerState.right.TargetAtt.WorldPosition) / 2
			elseif hasLeft then
				goalPos = playerState.left.TargetAtt.WorldPosition
			else
				goalPos = playerState.right.TargetAtt.WorldPosition
			end
			local toTarget = (goalPos - pos).Unit
			distToAnchor = (goalPos - pos).Magnitude
			toTargetX, toTargetY, toTargetZ = toTarget.X, toTarget.Y, toTarget.Z
			pullForce = (hasLeft and hasRight) and (HookConfig.PullForceDual or 10) or (HookConfig.PullForceSingle or 20)
			grappleSpeed = (hasLeft and hasRight) and (HookConfig.GrappleSpeedDual or 300)
				or (HookConfig.GrappleSpeedSingle or 150)
			pendulumMomentum = HookConfig.PendulumMomentum or 0.6
			gravityScale = HookConfig.GravityScaleWhenHooked or 0.5
		end
	end
	return {
		gas = gas,
		reelForce = playerReelForce[player.UserId] or 0,
		swingForce = playerSwingForce[player.UserId] or 0,
		hasLeft = hasLeft,
		hasRight = hasRight,
		leftRopeLen = leftLen,
		rightRopeLen = rightLen,
		distToAnchor = distToAnchor,
		toTargetX = toTargetX,
		toTargetY = toTargetY,
		toTargetZ = toTargetZ,
		pullForce = pullForce,
		grappleSpeed = grappleSpeed,
		pendulumMomentum = pendulumMomentum,
		gravityScale = gravityScale,
	}
end

function HookService:KnitInit()
	for _, player in Players:GetPlayers() do
		HookGas.initPlayerGas(player)
	end
	Players.PlayerAdded:Connect(function(player)
		HookGas.initPlayerGas(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local playerState = playerHooks[player.UserId]
		if playerState then
			if playerState.left then
				HookConstraints.releaseHookData(playerState.left)
			end
			if playerState.right then
				HookConstraints.releaseHookData(playerState.right)
			end
			if playerState.HeartbeatConn then
				playerState.HeartbeatConn:Disconnect()
			end
			if playerState.LinearVelocity then
				playerState.LinearVelocity:Destroy()
			end
			if playerState.VelocityAttachment then
				playerState.VelocityAttachment:Destroy()
			end
		end
		playerHooks[player.UserId] = nil
		HookGas.clearPlayerGas(player)
		playerProjectileCancel[player.UserId] = nil
		playerReelForce[player.UserId] = nil
		playerSwingForce[player.UserId] = nil
	end)
	local lastGasRegenTick = tick()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local delta = now - lastGasRegenTick
		lastGasRegenTick = now
		for _, player in Players:GetPlayers() do
			if not playerHooks[player.UserId] and player.Character then
				HookGas.regenGas(player, delta)
			end
		end
	end)
end

return HookService
