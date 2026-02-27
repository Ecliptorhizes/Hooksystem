--[[
	DevTuningBridge - Studio plugin that bridges localhost to the game.
	Roblox blocks server scripts from reaching localhost; this plugin runs in Studio
	and CAN access localhost. It reads live data from the bridge and POSTs to the Node server.

	Install: Copy DevTuningBridge.rbxm to your Plugins folder (Plugins > Plugins Folder).
	No publishing required.
]]

local DEV_SERVER_URL = "http://localhost:34873"
local LIVE_POST_INTERVAL = 0.1

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lastLivePost = 0
local connectedOnce = false
local bridgeFoundOnce = false
local noBridgeWarned = false
local loadTime = tick()

local function ensureBridge()
	local bridge = ReplicatedStorage:FindFirstChild("DevTuningBridge")
	if not bridge then return nil end
	local liveVal = bridge:FindFirstChild("LiveData")
	if not liveVal then return nil end
	return liveVal
end

-- Read live data from bridge (game writes it), POST to localhost
local function readAndPostLive()
	local bridge = ensureBridge()
	if not bridge then
		if not noBridgeWarned and RunService:IsRunning() and (tick() - loadTime) > 5 then
			noBridgeWarned = true
			warn("[DevTuningBridge] No bridge found. Press Play and ensure Rojo synced DevTuningServer.")
		end
		return
	end
	if not bridgeFoundOnce then
		bridgeFoundOnce = true
		print("[DevTuningBridge] Bridge found. Sending live data to dashboard...")
	end
	local json = bridge.Value
	if not json or json == "" or json == "{}" then return end
	local ok = pcall(function()
		HttpService:RequestAsync({
			Url = DEV_SERVER_URL .. "/api/live",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = json,
		})
	end)
	if ok and not connectedOnce then
		connectedOnce = true
		print("[DevTuningBridge] Connected. Live data flowing to dashboard.")
	end
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastLivePost >= LIVE_POST_INTERVAL then
		lastLivePost = now
		readAndPostLive()
	end
end)

task.defer(function()
	task.wait(2)
	local ok = pcall(function()
		HttpService:GetAsync(DEV_SERVER_URL .. "/api/health")
	end)
	if ok then
		print("[DevTuningBridge] Plugin ready. Dev server: " .. DEV_SERVER_URL)
	else
		warn("[DevTuningBridge] Cannot reach dev server. Run: npm run tuning")
	end
end)
