local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Maid = require(ReplicatedStorage.Packages.Maid)

local VOTE_DURATION_SEC = 15

local RoundController = Knit.CreateController({
	Name = "RoundController",
})

local maid = Maid.new();

local function formatTime(seconds: number): string
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

function RoundController:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    local MapService = Knit.GetService("MapService")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local postRoundGui = playerGui:WaitForChild("PostRoundGui", 10)
    if not postRoundGui then 
        warn("[RoundController] PostRoundGui not found. Not READY. PLEASE ADD")
        return
    end

    postRoundGui.Visible = false

    maid:GiveTask(task.spawn(function()
        while true do 
            task.wait(1)
            local state = RoundService:GetRoundState():await()
            if state == "PostRound" then 
                local data = RoundService:GetRoundEndData():await()
                if data then 
                    postRoundGui.Visible = true 

                    local leaderboard = data.leaderboard or {}
                    local first = postRoundGui:FindFirstChild("FirstPlace")
                    local second = postRoundGui:FindFirstChild("SecondPlace")
                    local third = postRoundGui:FindFirstChild("ThirdPlace")
                    if first then first.Text = leaderboard[1] and ("1st: " .. leaderboard[1].name .. " - " .. leaderboard[1].kills .. " kills") or "1st: -" end 
                    if second then second.Text = leaderboard[2] and ("2nd: " .. leaderboard[2].name .. " - " .. leaderboard[2].kills .. " kills") or "2nd: - " end 
                    if third then third.Text = leaderboard[3] and ("3rd: " .. leaderboard[3].name .. " - " .. leaderboard[3].kills .. "kills") or "3rd: - " end 

                    local myStats = (data.playerStats or {})[player.UserId]
                    if myStats then 
                        local deathsLabel = postRoundGui:FindFirstChild("DeathsLabel")
                        local headshotsLabel = postRoundGui:FindFirstChild("headshotsLabel")
                        local totalKillsLabel = postRoundGui:FindFirstChild("TotalKillsLabel")
                        local bestTimeLabel = postRoundGui:FindFirstChild("bestTimeLabel")
                        if deathsLabel then deathsLabel.Text = "Death: " .. myStats.deaths end 
                        if headshotsLabel then headshotsLabel.Text = "Headshots: " .. myStats.headshots end 
                        if totalKillsLabel then totalKillsLabel.Text = "Total Kills: " .. myStats.kills end 
                        if bestTimeLabel then bestTimeLabel.Text = "BEST TIME: " .. formatTime(myStats.bestTimeSeconds) end 
                    end 

                    local mapList = postRoundGui:FindFirstChild("MapVoteList")
                    local mapTemplate = postRoundGui:FindFirstChild("MapTemplate")
                    if mapList and mapTemplate then 
                        mapTemplate.Parent = nil 
                        for _, map in data.maps or {} do 
                            local clone = mapTemplate:Clone()
                            clone.Name = map.id 
                            clone.Visible = true 
                            local nameLabel = clone:FindFirstChild("MapName")
                            if nameLabel then nameLabel.Text = map.name end 
                            local voteBtn = clone:FindFirstChild("VoteButton")
                            if voteBtn then 
                                maid:GiveTask(voteBtn.MouseButton1Click:Connect(function()
                                    MapService:VoteMap(map.id):await()
                                end))
                            end 
                            clone.Parent = mapList
                        end 
                    end 
                    
                    local exitBtn = postRoundGui:FindFirstChild("ExitButton")
                    if exitBtn then 
                        maid:GiveTask(exitBtn.MouseButton1Click:Connect(function()
                            postRoundGui.Visible = false 
                        end))
                    end 
                    
                    task.wait(VOTE_DURATION_SEC or 15)
                    postRoundGui.Visible = false
                end 
            end 
        end 
    end)) 
end 

function RoundController:KnitDestroy()
    maid:DoCleaning()
end 

return RoundController



                

