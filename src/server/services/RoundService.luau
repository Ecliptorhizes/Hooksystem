--[[
	RoundService
	Purpose:
	Own the match lifecycle and publish post-round data payloads.

	Flow:
	Waiting (countdown) -> InProgress -> PostRound -> Voting -> Waiting.

	Responsibilities:
	- Track per-player combat/survival stats.
	- Trigger map voting between rounds.
	- Publish round-end payload for UI.
]]

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

-- Per-player stats for leaderboard and round end
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

-- Leaderboard entries sorted by kills (for round end UI)
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
	table.sort(entries, function(a, b)
		return a.kills > b.kills
	end)
	return entries
end

-- Build roundEndData (leaderboard, playerStats, maps) for client UI
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

-- Clear round state, teleport all players to lobby
local function teleportAllToLobby()
	SpawnService:ClearAllFromRound()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			humanoidRootPart.CFrame = LOBBY_SPAWN_CFRAME
		end
	end
end

-- Start lobby countdown; after LOBBY_COUNTDOWN_SEC, start round; after ROUND_DURATION_SEC, post-round → vote → repeat
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
			for _, stats in playerStats do
				if not stats.hadDied then
					stats.bestTimeSeconds = ROUND_DURATION_SEC
				end
			end

			roundState = "PostRound"
			buildRoundEndData()
			teleportAllToLobby()
			MapService:StartVoting()

			task.delay(VOTE_DURATION_SEC, function()
				local winningMapId = MapService:GetWinningMap()
				MapService:EndVoting()
				SpawnService:SetCurrentMap(winningMapId)
				startLobbyCountdown()
			end)
		end)
	end)
end

-- Called when a player gets a kill (e.g. from combat/game logic)
function RoundService:RecordKill(killer: Player, victim: Player, isHeadshot: boolean)
	local killerStats = playerStats[killer.UserId]
	if not killerStats then
		return
	end
	killerStats.kills += 1
	if isHeadshot then
		killerStats.headshots += 1
	end
end

-- Called when a player dies; records bestTimeSeconds (survival time)
function RoundService:RecordDeath(player: Player)
	local stats = playerStats[player.UserId]
	if not stats or stats.hadDied then
		return
	end
	stats.hadDied = true
	stats.bestTimeSeconds = math.floor(os.clock() - (stats.roundStartTime or roundStartTime))
end

-- Returns "Waiting" | "InProgress" | "PostRound"
function RoundService:GetRoundState()
    return roundState
end

function RoundService.Client:GetRoundState(_player: Player)
	return roundState
end

-- Returns { leaderboard, playerStats, maps } for post-round UI
function RoundService.Client:GetRoundEndData(_player: Player)
	return roundEndData
end

-- KnitStart: resolve MapService, SpawnService; wire Humanoid.Died → RecordDeath; start lobby countdown
function RoundService:KnitStart()
	MapService = Knit.GetService("MapService")
	SpawnService = Knit.GetService("SpawnService")

	local function bindDeathListener(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			self:RecordDeath(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			bindDeathListener(player, character)
		end)
	end)

	for _, player in Players:GetPlayers() do
		task.defer(function()
			local character = player.Character
			if not character then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			humanoid.Died:Connect(function()
				self:RecordDeath(player)
			end)
		end)
	end

	startLobbyCountdown()
end
return RoundService

