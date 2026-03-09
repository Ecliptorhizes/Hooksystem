--[[
	MapRegistry
	Purpose:
	Central source of truth for map metadata used by voting and spawn systems.
]]

local MapTypes = require(script.Parent.util.Types.MapTypes)

type MapInfo = MapTypes.MapInfo 

local Maps: { [string]: MapInfo } = {
    DevMap = {
        id = "DevMap",
        name = "Dev Map",
        difficulty = "Normal",
        spawnPoints = {
            CFrame.new(300.113, -263.797, 333.048) * CFrame.Angles(0, math.rad(90), math.rad(90)),
        }
    },
    RatioIsland = {
        id = "RatioIsland",
        name = "Ratio Island",
        difficulty = "Normal",
        spawnPoints = { CFrame.new(0, 5, 0) },
    },
    RatioLava = {
        id = "RatioLava",
        name = "Ratio Lava",
        difficulty = "Hard",
        spawnPoints = { CFrame.new(0, 5, 0) },
    },

}

--[[
	Returns a flat array view of configured maps for UI/service consumers.
]]
local function getMaps(): { MapInfo }
	local mapList = {}
	for _, map in Maps do
		table.insert(mapList, map)
	end
	return mapList
end

return {
    Maps = Maps,
    getMaps = getMaps
}

