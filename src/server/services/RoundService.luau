local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)
local LobbyConfig = require(ReplicatedStorage.Core.Config.LobbyConfig)

local MapService
local SpawnService

local LOBBY_SPAWN_CFRAME = LobbyConfig.LOBBY_SPAWN_CFRAME
local LOBBY_COUNTDOWN_SEC = 30
local ROUND_DURATION_SEC = 600
local VOTE_DURATION_SEC = 15

type PlayerStats = {
    kills: number,
    deaths: number,
    headshots: number,
    bestTimeSeconds: number,
    roundStartTime: number?,
    hadDied: boolean,
}

local RoundService = Knit.CreateService({
    Name = "RoundService",
    Client = {},
})

local roundState: "Waiting" | "InProgress" | "PostRound" = "Waiting"
local playerStats: { [number]: PlayerStats } = {}
local roundStartTime = 0
local roundEndData: any = nil

local function getLeaderboard(): { any }
    local entries = {}
    for userId, stats in playerStats do 
        local player = Players:GetPlayerByUserId(userId)
        table.insert(entries, {
            userId = userId,
            name = player and player.Name or "Unknown",
            kills = stats.kills,
        })
    end 
    table.sort(entries, function(a, b) return a.kills > b.kills end)
    return entries
end 

local function buildRoundEndData()
    local leaderboard = getLeaderboard()
    local statsCopy: { [number]: any } = {}
    for userId, stats in playerStats do 
        statsCopy[userId] = {
            kills = stats.kills,
            deaths = stats.deaths,
            headshots = stats.headshots,
            bestTimeSeconds = stats.bestTimeSeconds,
        }
    end 
    roundEndData = {
        leaderboard = leaderboard,
        playerStats = statsCopy,
        maps = MapRegistry.getMaps(),
    }
end 

local function teleportAllToLobby()
    SpawnService:ClearAllFromRound()
    for _, player in Players:GetPlayers() do 
        if player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then 
                hrp.CFrame = LOBBY_SPAWN_CFRAME
            end 
        end 
    end 
end 

local function startLobbyCountdown()
    roundState = "Waiting"
    playerStats = {}
    roundEndData = nil 

    task.delay(LOBBY_COUNTDOWN_SEC, function()
        roundState = "InProgress"
        roundStartTime = os.clock()
        for _, player in Players:GetPlayers() do 
            playerStats[player.UserId] = {
                kills = 0,
                deaths = 0,
                headshots = 0,
                bestTimeSeconds = 0,
                roundStartTime = roundStartTime,
                hadDied = false,
            }
        end 

        task.delay(ROUND_DURATION_SEC, function()
            for userId, stats in playerStats do 
                if not stats.hadDied then 
                    stats.bestTimeSeconds = ROUND_DURATION_SEC
                end 
            end 
            roundState = "PostRound"
            buildRoundEndData()
            teleportAllToLobby()
            MapService:StartVoting()

            task.delay(VOTE_DURATION_SEC, function()
                local _winningMapId = MapService:GetWinningMap()
                MapService:EndVoting()
                startLobbyCountdown()
            end)
        end)
    end)
end 

function RoundService:RecordKill(killer: Player, victim: Player, isHeadshot: boolean)
    local s = playerStats[killer.UserId]
    if s then 
        s.kills += 1
        if isHeadshot then s.headshots += 1 end 
    end 
end 

function RoundService:RecordDeath(player: Player)
    local s = playerStats[player.UserId]
    if s and not s.hadDied then 
        s.hadDied = true 
        s.bestTimeSeconds = math.floor(os.clock() - (s.roundStartTime or roundStartTime))
    end 
end 

function RoundService:GetRoundState()
    return roundState
end

function RoundService.Client:GetRoundState(_player: Player)
    return roundState 
end 

function RoundService.Client:GetRoundEndData(_player: Player)
    return roundEndData 
end 

function RoundService:KnitStart()
    MapService = Knit.GetService("MapService")
    SpawnService = Knit.GetService("SpawnService")

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            local humanoid = character:WaitForChild("Humanoid")
            humanoid.Died:Connect(function()
                self:RecordDeath(player)
            end)
        end)
    end)

    for _, player in Players:GetPlayers() do 
        task.defer(function()
            if player.Character then 
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then 
                    humanoid.Died:Connect(function()
                        self:RecordDeath(player)
                    end)
                end 
            end 
        end) 
    end 

    startLobbyCountdown()
end 
return RoundService

