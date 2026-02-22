export type PlayerRoundStats = {
    kills: number,
    deaths: number,
    headshots: number,
    bestTimeSecond: number,
}

export type LeaderboardEntry = {
    userId: number,
    name: string,
    kills: number,
}

export type MapInfo = {
    id: string,
    name: string,
    difficulty: string,
}

export type RoundEndData = {
    leaderboard: { LeaderboardEntry },
    playerStats: { [number]: PlayerRoundStats },
    maps: { MapInfo },
}

return {}
