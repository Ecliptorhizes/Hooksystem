# DevTuning Framework

Capture real timing, animation, and math data from your Roblox scripts and view it in the live tuning dashboard. Add your own **custom sliders** (like Hooksystem controls) so you can tune values in real time.

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DevTuning = require(ReplicatedStorage.Core.DevTuning)

-- One-time: define schema (optional; inferred from first Report if omitted)
DevTuning.Register("animLength", {
  unit = "s",
  min = 0,
  max = 5,
  chart = true,
  label = "Animation length"
})

-- Every frame or when value changes
DevTuning.Report("animLength", 0.5)
DevTuning.Report("jumpHeight", 12)
```

## Custom Sliders (Live Tuning)

Add your own sliders to the dashboard, just like the Hooksystem controls:

```lua
DevTuning.Register("mySpeed", {
  slider = true,
  min = 0,
  max = 100,
  default = 50,
  step = 5,
  unit = "stud/s",
  label = "My speed",
})

-- In your game logic, read the value the user set:
local speed = DevTuning.GetSliderValue("mySpeed") or 50
-- Use speed for movement, animation, etc.
```

Sliders appear in the left panel under "Custom (developer)". Values are saved and sync via Rojo like Hooksystem config.

## API

### `DevTuning.Register(key, schema)`

Define schema for a custom field. Call once (e.g. at script init). Schema is optional; if you omit it, a default schema is inferred from the first `Report`.

| Schema field | Type   | Description                          |
|--------------|--------|--------------------------------------|
| `unit`       | string | Display unit (e.g. `"s"`, `"stud/s"`)|
| `min`        | number | Chart Y-axis min; required for slider|
| `max`        | number | Chart Y-axis max; required for slider|
| `step`       | number | Slider step (default: 1)             |
| `chart`      | boolean| If true, show a time-series chart     |
| `label`      | string | Display name (default: key)          |
| `slider`     | boolean| If true, add a dashboard slider      |
| `default`    | number | Default value when no override       |

### `DevTuning.GetSliderValue(key)`

Get the current slider value (override from dashboard or schema default). Returns `nil` if no value exists.

### `DevTuning.Report(key, value)`

Report a value. Supported types: `number`, `string`, `boolean`. Call from server scripts (client reporting is not yet supported).

## Examples

### Animation timing

```lua
local DevTuning = require(ReplicatedStorage.Core.DevTuning)

DevTuning.Register("animElapsed", { unit = "s", chart = true, label = "Anim elapsed" })

-- In your animation update loop
DevTuning.Report("animElapsed", track.TimePosition)
```

### Custom physics

```lua
local DevTuning = require(ReplicatedStorage.Core.DevTuning)

DevTuning.Register("customForce", { unit = "N", min = 0, max = 500, chart = true, label = "Custom force" })

-- When you compute a force
DevTuning.Report("customForce", magnitude)
```

### Simple value (no chart)

```lua
DevTuning.Report("state", "idle")  -- string, no chart
DevTuning.Report("count", 42)     -- number, chart by default
```

## Dashboard

- **Custom Probes** section shows a live table of all reported values.
- Keys with `chart: true` get a time-series chart (same style as the velocity graph).
- Schema is refreshed every 5 seconds; new probes appear shortly after you start reporting.

## Example: Developer Showcase

A built-in example (`src/server/DevTuningExample.luau`) demonstrates what you can do:

| Category | Keys | What it shows |
|----------|------|---------------|
| **Animation** | animLength, animPlayback, blendWeight, easingValue | Looping playback, blend curve, ease-in-out |
| **Physics** | customForce, distance | Simulated force and distance over time |
| **Strings/Booleans** | state, isActive | Live values only (no chart) |
| **Config-driven** | configPullForce | Value from HookConfig (tune via dashboard sliders) |
| **Custom slider** | mySpeed | Your own slider — adjust in left panel, use via `GetSliderValue` |

1. Run `npm start`, then open http://localhost:34873
2. In Studio: Rojo sync, then press Play
3. Left panel: scroll to **Custom (developer)** — adjust **My speed** slider
4. Right panel: **Custom Probes** — see `mySpeed` update as you move the slider

To disable the example, comment out the `require(script.Parent.DevTuningExample)` call at the end of `DevTuningServer.luau`.

## Requirements

- Run in **Roblox Studio** (DevTuningServer is Studio-only).
- Run `npm start` and Rojo sync so the dev server receives live data.
- Use from **server scripts** only (v1).
