local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return true
end

local DevTuning = require(ReplicatedStorage.Core.DevTuning)

DevTuning.Register("animLength", {
	unit = "s",
	min = 0,
	max = 3,
	chart = true,
	label = "Animation length",
})
DevTuning.Register("animPlayback", {
	unit = "",
	min = 0,
	max = 1,
	chart = true,
	label = "Playback (0–1)",
})
DevTuning.Register("blendWeight", {
	unit = "",
	min = 0,
	max = 1,
	chart = true,
	label = "Blend weight",
})
DevTuning.Register("easingValue", {
	unit = "",
	min = 0,
	max = 1,
	chart = false,
	label = "Easing (current)",
})

DevTuning.Register("customForce", {
	unit = "N",
	min = 0,
	max = 100,
	chart = true,
	label = "Custom force",
})
DevTuning.Register("distance", {
	unit = "stud",
	min = 0,
	max = 200,
	chart = true,
	label = "Distance to target",
})

local HookConfig = require(ReplicatedStorage.Core.Config.HookConfig)
DevTuning.Register("configPullForce", {
	unit = "N",
	min = 0,
	max = 100,
	chart = false,
	label = "PullForceSingle (from config)",
})

DevTuning.Register("mySpeed", {
	slider = true,
	min = 0,
	max = 100,
	default = 50,
	step = 5,
	unit = "stud/s",
	label = "My speed",
})

local t0 = tick()
RunService.Heartbeat:Connect(function()
	local t = tick() - t0
	local cycle = (t % 2.5) / 2.5
	DevTuning.Report("animLength", 2.5)
	DevTuning.Report("animPlayback", cycle)
	DevTuning.Report("blendWeight", 0.5 + 0.5 * math.sin(t * 2))
	DevTuning.Report("easingValue", cycle * cycle * (2 - cycle))

	DevTuning.Report("customForce", 30 + 25 * math.sin(t * 1.5))
	DevTuning.Report("distance", 80 + 40 * math.cos(t * 0.8))

	DevTuning.Report("state", cycle > 0.5 and "playing" or "idle")
	DevTuning.Report("isActive", t > 1)

	DevTuning.Report("configPullForce", HookConfig.PullForceSingle or 20)

	local mySpeed = DevTuning.GetSliderValue("mySpeed") or 50
	DevTuning.Report("mySpeed", mySpeed)
end)

print("[DevTuningExample] Demo running. Open dashboard → Custom Probes.")
return true
