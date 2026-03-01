local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Bootstrap = {}

function Bootstrap.locateServicesFolder(): Instance?
	local candidates = {
		script:FindFirstChild("services"),
		script.Parent and script.Parent:FindFirstChild("Server") and script.Parent.Server:FindFirstChild("services"),
		ServerScriptService:FindFirstChild("services"),
		ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("services"),
	}
	for _, folder in ipairs(candidates) do
		if folder then
			return folder
		end
	end
	return nil
end

function Bootstrap.registerServices(servicesFolder: Instance)
	Knit.AddServices(servicesFolder)
end

function Bootstrap.loadDevTools()
	if not RunService:IsStudio() then
		return
	end
	local devTuningServer = script:FindFirstChild("DevTuningServer")
	if devTuningServer then
		require(devTuningServer)
		print("[Hooksystem] DevTuningServer loaded.")
	else
		warn(("[Hooksystem] DevTuningServer not found in %s"):format(script:GetFullName()))
	end
end

-- Run bootstrap pipeline
local services = Bootstrap.locateServicesFolder()
if not services then
	error(("Knit: services folder not found. script=%s"):format(script:GetFullName()))
end

Bootstrap.registerServices(services)

Knit.Start()
	:andThen(Bootstrap.loadDevTools)
	:catch(function(err)
		warn("[Hooksystem] Knit.Start or DevTuningServer failed:", tostring(err))
	end)
