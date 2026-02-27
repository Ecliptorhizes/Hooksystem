--[[
	DevTuningServer - Live tuning for Zipshot (Node.js + Rojo + Plugin)
	- Config: Node writes TuningOverrides.txt → Rojo syncs → we apply
	- Live feed: We write to bridge → Plugin POSTs to localhost
	Install DevTuningBridge plugin: copy DevTuningBridge.rbxm to Plugins folder (see dev-server/plugin/README.md)
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

print("[DevTuningServer] Starting (Rojo sync + plugin bridge)...")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)
local HookService = Knit.GetService("HookService")

local POLL_INTERVAL = 0.1
local LIVE_WRITE_INTERVAL = 0.1

-- Create bridge for plugin (plugin reads LiveData, POSTs to localhost)
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

-- Config from Rojo sync (TuningOverrides.txt)
local function applyOverridesFromSync()
	local overridesVal = ReplicatedStorage.Core.Config:FindFirstChild("TuningOverrides")
	if not overridesVal or not overridesVal:IsA("StringValue") then
		return
	end
	local json = overridesVal.Value
	if not json or json == "" or json == "{}" then
		return
	end
	local overrides = nil
	pcall(function()
		overrides = HttpService:JSONDecode(json)
	end)
	if overrides and type(overrides) == "table" then
		for key, value in pairs(overrides) do
			if HookConfig[key] ~= nil then
				HookConfig[key] = value
			end
		end
	end
end

task.spawn(function()
	while true do
		applyOverridesFromSync()
		task.wait(POLL_INTERVAL)
	end
end)

-- Write live data to bridge (plugin POSTs it to Node)
local lastWriteTime = 0
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastWriteTime < LIVE_WRITE_INTERVAL then
		return
	end
	lastWriteTime = now
	local player = Players:GetPlayers()[1]
	if not player or not player.Character then
		return
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local vel = hrp.AssemblyLinearVelocity
	local pos = hrp.Position
	local hookData = HookService:GetDebugData(player)
	liveVal.Value = HttpService:JSONEncode({
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
	})
end)
