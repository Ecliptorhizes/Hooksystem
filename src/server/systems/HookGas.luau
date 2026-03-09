--[[
	HookGas
	Purpose:
	Manage player gas resources (read, spend, regen) for hook actions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)

local playerGas: { [number]: number } = {}

local function getGas(player: Player): number
	if not playerGas[player.UserId] then
		playerGas[player.UserId] = HookConfig.MaxGas
	end
	return playerGas[player.UserId]
end

local function spendGas(player: Player, amount: number): boolean
	local gas = getGas(player)
	if gas < amount then
		return false
	end
	playerGas[player.UserId] = gas - amount
	return true
end

local function regenGas(player: Player, delta: number)
	local gas = getGas(player)
	if gas >= HookConfig.MaxGas then
		return
	end
	playerGas[player.UserId] = math.min(HookConfig.MaxGas, gas + HookConfig.GasRegenPerSec * delta)
end

local function initPlayerGas(player: Player)
	playerGas[player.UserId] = HookConfig.MaxGas
end

local function clearPlayerGas(player: Player)
	playerGas[player.UserId] = nil
end

return {
	getGas = getGas,
	spendGas = spendGas,
	regenGas = regenGas,
	initPlayerGas = initPlayerGas,
	clearPlayerGas = clearPlayerGas,
}
