local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return nil
end

print("[DevTuningServer] Starting (Rojo sync + plugin bridge + MessagingService)...")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)
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
local POLL_INTERVAL = 0.1
local LIVE_WRITE_INTERVAL = 0.1

local function debugLog(msg, data)
	pcall(function()
		HttpService:RequestAsync({
			Url = DEV_SERVER_URL .. "/api/debug",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({
				message = msg,
				data = data or {},
				hypothesisId = "H1",
			}),
		})
	end)
end

local function ensureBridge()
	local bridge = ReplicatedStorage:FindFirstChild("DevTuningBridge")
	if not bridge then
		bridge = Instance.new("Folder")
		bridge.Name = "DevTuningBridge"
		bridge.Parent = ReplicatedStorage
	end
	local liveVal = bridge:FindFirstChild("LiveData")
	if not liveVal then
		liveVal = Instance.new("StringValue")
		liveVal.Name = "LiveData"
		liveVal.Value = "{}"
		liveVal.Parent = bridge
	end
	return liveVal
end

local liveVal = ensureBridge()
print("[DevTuningServer] Bridge created. Install DevTuningBridge plugin for live feed.")
debugLog("DevTuningServer_started", { url = DEV_SERVER_URL })

local function applyOverrides(overrides)
	if not overrides or type(overrides) ~= "table" then return 0 end
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
		MessagingService:SubscribeAsync("ZipshotTuning", function(message)
			local data = message.Data
			if type(data) == "string" and data ~= "" then
				local overrides = nil
				pcall(function()
					overrides = HttpService:JSONDecode(data)
				end)
				if overrides and type(overrides) == "table" then
					local count = applyOverrides(overrides)
					debugLog("messaging_config", { appliedCount = count })
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
	if not overridesVal or not overridesVal:IsA("StringValue") then return nil end
	local json = overridesVal.Value
	if not json or json == "" or json == "{}" then return nil end
	local ok, overrides = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return ok and overrides or nil
end

local function getOverridesFromHttp()
	local ok, res = pcall(function()
		return HttpService:GetAsync(DEV_SERVER_URL .. "/api/config")
	end)
	if not ok or not res then return nil end
	local parsed = nil
	pcall(function()
		parsed = HttpService:JSONDecode(res)
	end)
	return parsed
end

task.spawn(function()
	local lastDebugLog = 0
	while true do
		local overrides = nil
		local source = "none"
		if RunService:IsRunning() then
			overrides = getOverridesFromHttp()
			source = overrides and "http" or "http_fail"
			if not overrides then
				overrides = getOverridesFromSync()
				if overrides then source = "sync_fallback" end
			end
		else
			overrides = getOverridesFromSync()
			source = overrides and "sync" or "none"
		end
		local count = applyOverrides(overrides)
		if tick() - lastDebugLog > 2 then
			lastDebugLog = tick()
			debugLog("config_poll", {
				isRunning = RunService:IsRunning(),
				source = source,
				appliedCount = count,
			})
		end
		task.wait(POLL_INTERVAL)
	end
end)

local lastWriteTime = 0
local lastPostTime = 0
local LIVE_POST_INTERVAL = 0.15
local function buildLivePayload(player, hrp, hookData)
	local vel = hrp.AssemblyLinearVelocity
	local pos = hrp.Position
	return {
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
	}
end

local heartbeatSkipLogTime = 0
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastWriteTime < LIVE_WRITE_INTERVAL then
		return
	end
	lastWriteTime = now
	local player = Players:GetPlayers()[1]
	if not player or not player.Character then
		if now - heartbeatSkipLogTime > 3 then
			heartbeatSkipLogTime = now
			debugLog("live_skip_no_player", { hasPlayer = player ~= nil, hasChar = player and player.Character ~= nil })
		end
		return
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local hookData = HookService:GetDebugData(player)
	local payload = buildLivePayload(player, hrp, hookData)
	local json = HttpService:JSONEncode(payload)
	liveVal.Value = json
	if now - lastPostTime >= LIVE_POST_INTERVAL then
		lastPostTime = now
		local ok, err = pcall(function()
			HttpService:RequestAsync({
				Url = DEV_SERVER_URL .. "/api/live",
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = json,
			})
		end)
		debugLog("live_post", { ok = ok, err = tostring(err), vel = payload.velocityMagnitude })
	end
end)

return true
