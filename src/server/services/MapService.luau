--[[
	MapService
	Purpose:
	Manage map voting state and resolve the winning map identifier.

	Responsibilities:
	- Expose available maps to clients.
	- Record per-player vote while voting is open.
	- Resolve winning map id from vote counts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)

local MapService = Knit.CreateService({
	Name = "MapService",
	Client = {},
})

local votes: { [number]: string } = {}
local isVoting = false

function MapService.Client:GetMaps(_players: Player)
	return MapRegistry.getMaps()
end

function MapService.Client:VoteMap(player: Player, mapId: string)
	if not isVoting then
		return
	end
	if type(mapId) ~= "string" or mapId == "" then
		return
	end
	if not MapRegistry.Maps[mapId] then
		return
	end
	votes[player.UserId] = mapId
end

function MapService:StartVoting()
	isVoting = true
	votes = {}
end

function MapService:EndVoting()
	isVoting = false
end

function MapService:GetWinningMap(): string
	local voteCounts: { [string]: number } = {}
	for _, mapId in pairs(votes) do
		voteCounts[mapId] = (voteCounts[mapId] or 0) + 1
	end

	local winningMapId = ""
	local winningVoteCount = 0
	for mapId, voteCount in pairs(voteCounts) do
		if voteCount > winningVoteCount then
			winningVoteCount = voteCount
			winningMapId = mapId
		end
	end

	if winningMapId == "" then
		local maps = MapRegistry.getMaps()
		return (maps[1] and maps[1].id) or "DevMap"
	end

	return winningMapId
end

return MapService
