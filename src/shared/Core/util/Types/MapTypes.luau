--[[
	MapTypes
	Purpose:
	Declare shared static type contracts for map metadata.
]]
export type MapInfo = {
    id: string,
    name: string,
    difficulty: string,
    spawnPoints: { CFrame },
}

return {}
