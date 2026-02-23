local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local services = script.Parent:FindFirstChild("services")
	or (script.Parent:FindFirstChild("Server") and script.Parent.Server:FindFirstChild("services"))
	or ServerScriptService:FindFirstChild("services")
	or (ServerScriptService:FindFirstChild("Server") and ServerScriptService.Server:FindFirstChild("services"))

if not services then
	error("Knit: services folder not found. script=" .. script:GetFullName())
end

Knit.AddServices(services)
Knit.Start():catch(warn)
