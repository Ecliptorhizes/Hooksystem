-- MUST run as a plugin - do not add this script to the game (ServerScriptService/StarterPlayer)
if not plugin then
	warn("[DevTuningBridge] This must run as a plugin, not a game script. Use Plugins -> Save as Local Plugin.")
	return
end

-- Create toolbar so plugin is visible in Plugins tab (required for Studio to recognize it)
local toolbar = plugin:CreateToolbar("Hooksystem")
local btn = toolbar:CreateButton("Dev Tuning", "Bridges live data to tuning dashboard", "")

-- Status GUI (opens when button clicked)
local statusWidget = nil
local statusLabel = nil
local function ensureStatusGui()
	if statusWidget then
		statusWidget.Enabled = true
		return statusLabel
	end
	statusWidget = plugin:CreateDockWidgetPluginGui("DevTuningBridge_Status", DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float, false, false, 220, 180, 220, 180
	))
	statusWidget.Title = "Hooksystem Dev Tuning"
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BorderSizePixel = 0
	frame.Parent = statusWidget
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = frame
	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -20, 1, -20)
	statusLabel.Position = UDim2.fromOffset(10, 10)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	statusLabel.TextSize = 12
	statusLabel.Font = Enum.Font.RobotoMono
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextWrapped = true
	statusLabel.Parent = frame
	statusWidget.Parent = plugin
	return statusLabel
end
local function updateStatusGui(text)
	if statusLabel then
		statusLabel.Text = text
	end
end
btn.Click:Connect(function()
	ensureStatusGui()
	updateStatusGui("Server: " .. (DEV_SERVER_URL or "?") .. "\n\nOpen http://localhost:34873\nPress Play to start.\n\n" .. (lastStatusText ~= "" and lastStatusText or "Status: starting..."))
end)

local function getDevServerUrl()
	local core = game:GetService("ReplicatedStorage"):FindFirstChild("Core")
	local config = core and core:FindFirstChild("Config")
	local urlVal = config and config:FindFirstChild("DevServerUrl")
	if urlVal and urlVal:IsA("StringValue") and urlVal.Value and urlVal.Value ~= "" then
		return urlVal.Value:gsub("/$", "")
	end
	local ok, cfg = pcall(function()
		return require(game:GetService("ReplicatedStorage").Core.Config.HookConfig)
	end)
	return (ok and cfg and cfg.DevTuningServerUrl) or "http://localhost:34873"
end
local DEV_SERVER_URL = getDevServerUrl()
local LIVE_POST_INTERVAL = 0.5

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lastLivePost = 0
local connectedOnce = false
local bridgeFoundOnce = false
local noBridgeWarned = false
local lastStatusText = "Status: checking server..."
local loadTime = tick()
local pluginStartLogged = false

-- #region agent log
local function agentDebug(msg, data)
	pcall(function()
		HttpService:RequestAsync({
			Url = (DEV_SERVER_URL:gsub("/$", "")) .. "/api/debug",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ message = msg, data = data or {}, hypothesisId = "H6" }),
		})
	end)
end
-- #endregion

local function ensureBridge()
	local bridge = ReplicatedStorage:FindFirstChild("DevTuningBridge")
	if not bridge then return nil end
	local liveVal = bridge:FindFirstChild("LiveData")
	if not liveVal then return nil end
	return liveVal
end

local function readAndPostLive()
	local bridge = ensureBridge()
	if not bridge then
		-- #region agent log
		if not noBridgeWarned and RunService:IsRunning() and (tick() - loadTime) > 2 then
			agentDebug("plugin_no_bridge", { isRunning = RunService:IsRunning() })
		end
		-- #endregion
		if not noBridgeWarned and RunService:IsRunning() and (tick() - loadTime) > 5 then
			noBridgeWarned = true
			-- Plugin cannot see running game's ReplicatedStorage; live data comes from DevTuningServer POSTing directly
			warn("[DevTuningBridge] Plugin cannot see running game. Live data flows from DevTuningServer -> Node. Ensure npm start and Rojo sync.")
			pcall(function()
				HttpService:RequestAsync({
					Url = (DEV_SERVER_URL:gsub("/$", "")) .. "/api/debug",
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode({ message = "plugin_no_bridge", data = { isRunning = RunService:IsRunning() } }),
				})
			end)
		end
		lastStatusText = "Bridge: waiting\n(Press Play to start)"
		return
	end
	if not bridgeFoundOnce then
		bridgeFoundOnce = true
		-- #region agent log
		agentDebug("plugin_bridge_found", {})
		-- #endregion
		print("[DevTuningBridge] Bridge found. Sending live data to dashboard...")
	end
	lastStatusText = "Bridge: found\nLive data: flowing"
	local json = bridge.Value
	-- #region agent log
	if (not json or json == "" or json == "{}") and tick() - loadTime > 3 and tick() - loadTime < 5 then
		agentDebug("plugin_livedata_empty", { json = json or "nil", len = json and #json or 0 })
	end
	-- #endregion
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
	if statusLabel and statusWidget and statusWidget.Enabled and lastStatusText ~= "" and now % 1 < 0.05 then
		updateStatusGui("Server: " .. (DEV_SERVER_URL or "?") .. "\n\nOpen http://localhost:34873\nPress Play to start.\n\n" .. lastStatusText)
	end
	-- #region agent log
	if not pluginStartLogged and now - loadTime > 1 then
		pluginStartLogged = true
		agentDebug("plugin_heartbeat_started", { isRunning = RunService:IsRunning() })
	end
	-- #endregion
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
		lastStatusText = "Server: connected\nBridge: waiting\n(Press Play to start)"
		print("[DevTuningBridge] Plugin ready. Dev server: " .. DEV_SERVER_URL)
	else
		lastStatusText = "Server: not reachable\nRun: npm start"
		warn("[DevTuningBridge] Cannot reach dev server. Run: npm start")
	end
end)
