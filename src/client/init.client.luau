--[[
	Client Bootstrap
	Purpose:
	Locate controller modules, register them with Knit, and start client runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local controllers = script.Parent:FindFirstChild("controllers")
	or (script.Parent:FindFirstChild("Client") and script.Parent.Client:FindFirstChild("controllers"))

if not controllers then
	error("Knit: controllers folder not found. script=" .. script:GetFullName())
end

Knit.AddControllers(controllers)
Knit.Start():catch(warn)
