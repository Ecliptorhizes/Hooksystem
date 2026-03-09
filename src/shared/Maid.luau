--[[
	Maid (Facade Module)
	Purpose:
	Expose the project-standard Maid implementation from the packaged dependency.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
return require(ReplicatedStorage.Packages._Index["devsparkle_maid@1.1.0"].maid.MaidClass)
