local MapTypes = require(script.Parent.util.Types.MapTypes)

type MapInfo = MapTypes.MapInfo 

local Maps: { [string]: MapInfo } = {
    DevMap = {
        id = "DevMap",
        name = "Dev Map",
        difficulty = "Normal",
    },
    RatioIsland = {
        id = "RatioIsland",
        name = "Ratio Island",
        difficulty = "Normal",
    },
    RatioLava = {
        id = "RatioLava",
        name = "Ratio Lava",
        difficulty = "Hard"
    },

}

local function getMaps(): { MapInfo }
    local list = {}
    for _, map in Maps do 
        table.insert(list, map)
    end
    return list
end

return {
    Maps = Maps,
    getMaps = getMaps
}

