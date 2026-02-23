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
	if isVoting then
		votes[player.UserId] = mapId
	end
end

function MapService:StartVoting()
	isVoting = true
	votes = {}
end

function MapService:EndVoting()
	isVoting = false
end

function MapService:GetWinningMap(): string
	local count: { [string]: number } = {}
	for _, mapId in pairs(votes) do
		count[mapId] = (count[mapId] or 0) + 1
	end
	local bestId = ""
	local bestCount = 0
	for mapId, c in pairs(count) do
		if c > bestCount then
			bestCount = c
			bestId = mapId
		end
	end
	if bestId == "" then
		local maps = MapRegistry.getMaps()
		return (maps[1] and maps[1].id) or "DevMap"
	end
	return bestId
end

return MapService
