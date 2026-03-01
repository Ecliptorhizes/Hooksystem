local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return nil
end

print("[DevTuningServer] Starting (Rojo sync + MessagingService)...")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)
local DevTuning = require(ReplicatedStorage.Core.DevTuning)
local HookService = Knit.GetService("HookService")

local function getDevServerUrl()
	local core = ReplicatedStorage:FindFirstChild("Core")
	local config = core and core:FindFirstChild("Config")
	local urlVal = config and config:FindFirstChild("DevServerUrl")
	if urlVal and urlVal:IsA("StringValue") and urlVal.Value and urlVal.Value ~= "" then
		return urlVal.Value:gsub("/$", "")
	end
	return HookConfig.DevTuningServerUrl or "http://localhost:34873"
end
local DEV_SERVER_URL = getDevServerUrl()
local POLL_INTERVAL = 2
local LIVE_WRITE_INTERVAL = 0.1

local function applyOverrides(overrides)
	if not overrides or type(overrides) ~= "table" then
		return 0
	end
	DevTuning.SetOverrides(overrides)
	local count = 0
	for key, value in pairs(overrides) do
		if HookConfig[key] ~= nil then
			HookConfig[key] = value
			count += 1
		end
	end
	return count
end

task.spawn(function()
	local ok = pcall(function()
		MessagingService:SubscribeAsync("HooksystemTuning", function(message)
			local data = message.Data
			if type(data) == "string" and data ~= "" then
				local overrides = nil
				pcall(function()
					overrides = HttpService:JSONDecode(data)
				end)
				if overrides and type(overrides) == "table" then
					applyOverrides(overrides)
				end
			end
		end)
	end)
	if ok then
		print("[DevTuningServer] MessagingService subscribed (Node -> Game config)")
	else
		print("[DevTuningServer] MessagingService subscribe failed (use Rojo sync or HTTP)")
	end
end)

local function getOverridesFromSync()
	local core = ReplicatedStorage:FindFirstChild("Core")
	local config = core and core:FindFirstChild("Config")
	local overridesVal = config and config:FindFirstChild("TuningOverrides")
	if not overridesVal or not overridesVal:IsA("StringValue") then
		return nil
	end
	local json = overridesVal.Value
	if not json or json == "" or json == "{}" then
		return nil
	end
	local ok, overrides = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return ok and overrides or nil
end

local function getOverridesFromHttp()
	local ok, res = pcall(function()
		return HttpService:GetAsync(DEV_SERVER_URL .. "/api/config")
	end)
	if not ok or not res then
		return nil
	end
	local parsed = nil
	pcall(function()
		parsed = HttpService:JSONDecode(res)
	end)
	return parsed
end

task.spawn(function()
	while true do
		local overrides = nil
		local _source = "none"
		if RunService:IsRunning() then
			overrides = getOverridesFromHttp()
			_source = overrides and "http" or "http_fail"
			if not overrides then
				overrides = getOverridesFromSync()
				if overrides then
					_source = "sync_fallback"
				end
			end
		else
			overrides = getOverridesFromSync()
			_source = overrides and "sync" or "none"
		end
		applyOverrides(overrides)
		task.wait(POLL_INTERVAL)
	end
end)

local lastWriteTime = 0
local lastPostTime = 0
local LIVE_POST_INTERVAL = 0.5
local function buildLivePayload(player, hrp, hookData)
	local vel = hrp.AssemblyLinearVelocity
	local pos = hrp.Position
	local payload = {
		velocityMagnitude = vel.Magnitude,
		velocity = vel.Magnitude,
		speed = vel.Magnitude,
		velX = vel.X,
		velY = vel.Y,
		velZ = vel.Z,
		posX = pos.X,
		posY = pos.Y,
		posZ = pos.Z,
		isHooked = hookData.hasLeft or hookData.hasRight,
		gas = hookData.gas,
		reelForce = hookData.reelForce,
		swingForce = hookData.swingForce,
		hasLeft = hookData.hasLeft,
		hasRight = hookData.hasRight,
		leftRopeLen = hookData.leftRopeLen,
		rightRopeLen = hookData.rightRopeLen,
		distToAnchor = hookData.distToAnchor,
		toTargetX = hookData.toTargetX,
		toTargetY = hookData.toTargetY,
		toTargetZ = hookData.toTargetZ,
		pullForce = hookData.pullForce,
		grappleSpeed = hookData.grappleSpeed,
		pendulumMomentum = hookData.pendulumMomentum,
		gravityScale = hookData.gravityScale,
	}
	local custom = DevTuning.GetData()
	for k, v in pairs(custom.values) do
		payload[k] = v
	end
	if next(custom.schema) then
		payload._schema = custom.schema
	end
	return payload
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastWriteTime < LIVE_WRITE_INTERVAL then
		return
	end
	lastWriteTime = now
	local payload
	local player = Players:GetPlayers()[1]
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local hookData = HookService:GetDebugData(player)
			payload = buildLivePayload(player, hrp, hookData)
		end
	end
	if not payload then
		payload = { velocityMagnitude = 0, velocity = 0, isHooked = false }
		local custom = DevTuning.GetData()
		for k, v in pairs(custom.values) do
			payload[k] = v
		end
		if next(custom.schema) then
			payload._schema = custom.schema
		end
	end
	if payload then
		local json = HttpService:JSONEncode(payload)
		if now - lastPostTime >= LIVE_POST_INTERVAL then
			lastPostTime = now
			pcall(function()
				HttpService:RequestAsync({
					Url = DEV_SERVER_URL .. "/api/live",
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = json,
				})
			end)
		end
	end
end)

task.defer(function()
	local ok, Example = pcall(function()
		return require(script.Parent.DevTuningExample)
	end)
	if ok and Example then
	end
end)

return true
