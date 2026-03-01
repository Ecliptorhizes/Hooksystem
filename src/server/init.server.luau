local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local services = script:FindFirstChild("services")
	or (script.Parent:FindFirstChild("Server") and script.Parent.Server:FindFirstChild("services"))
	or ServerScriptService:FindFirstChild("services")
	or (ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("services"))

if not services then
	error("Knit: services folder not found. script=" .. script:GetFullName())
end

Knit.AddServices(services)
Knit.Start():andThen(function()
	if RunService:IsStudio() then
		local DevTuningServer = script:FindFirstChild("DevTuningServer")
		if DevTuningServer then
			require(DevTuningServer)
			print("[Hooksystem] DevTuningServer loaded.")
		else
			warn("[Hooksystem] DevTuningServer not found in", script:GetFullName())
		end
	end
	return nil
end):catch(function(err)
	warn("[Hooksystem] Knit.Start or DevTuningServer failed:", tostring(err))
end)
