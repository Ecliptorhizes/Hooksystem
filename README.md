# Hooksystem

A **Roblox grapple/hook movement system** that lets players shoot grappling hooks from their arms, swing through the world, reel in, boost, and use dual hooks for fluid, physics-based traversal. The project is **uncopylocked** and includes a **live tuning** dev server so you can tweak parameters in real time via a WebSocket + HTTP API.

---

## What Is This Project For?

Hooksystem is a **grappling hook movement framework** for Roblox experiences. It provides:

- **Dual-hook mechanics** — Fire left and right hooks independently to swing, climb, and traverse terrain
- **Physics-driven movement** — Rope constraints, pendulum physics, and configurable forces for natural-feeling swings
- **Gas resource system** — Hooks, boosts, and jumps consume gas that regenerates over time
- **Live tuning** — Adjust pull force, speed, rope length, and dozens of other parameters while the game runs, without restarting

You can drop it into your own Roblox game, configure it via `HookConfig.luau`, and optionally use the Node.js dev server to tune values in real time during development.

---

## What You're Doing With Hooksystem

### Core Mechanics

| Action | Description |
|--------|-------------|
| **Fire hook** | Shoot a projectile from your arm; on hit, a rope attaches and you're pulled toward the anchor |
| **Release** | Detach the hook and keep some momentum |
| **Reel in / out** | Shorten or lengthen the rope while hooked |
| **Swing** | Apply lateral force to pendulum-swing around the anchor |
| **Boost** | Spend gas for a burst of speed toward the anchor |
| **Jump** | While hooked, jump to change trajectory (reel or boost depending on angle) |

### Technical Features

- **Rope or spring constraints** — Choose `RopeConstraint` or `SpringConstraint` for different feel
- **Arm force mode** — Optional `VectorForce` on arms for more realistic pendulum physics
- **Grapple physics mode** — Direct velocity control toward anchor with orbit/swing options
- **Projectile phase** — Hooks fire as visible projectiles that raycast for hit detection
- **Ragdoll prevention** — Keeps the character upright while hooked
- **Configurable everything** — Max range, beam thickness, gas costs, pull forces, launch caps, and more

### Project Structure

```
src/
├── client/           # Knit controllers (MovementController, SpawnUIController, etc.)
├── server/           # Knit services (HookService, SpawnService, etc.)
└── shared/
    └── Core/
        ├── Config/
        │   ├── HookConfig.luau   # All tuning parameters
        │   ├── LobbyConfig.luau  # Lobby spawn position
        │   └── TuningOverrides.txt  # Live-tuned values (written by dev server)
        └── DevTuning.luau       # Developer instrumentation (Report, Register)
```

---

## API Reference

What you can `require` and call from **server scripts** or **client scripts**. Use this for anything you're building—simulations, physics, interpolation, custom mechanics—not just the grappling demo.

### Shared Modules (Server & Client)

Require from `ReplicatedStorage`:

| Module | Path | Description |
|--------|------|-------------|
| **DevTuning** | `ReplicatedStorage.Core.DevTuning` | Live tuning: `Register`, `Report`, `GetSliderValue`. Add sliders and report values to the dashboard. Server-only for reporting. |
| **Maid** | `ReplicatedStorage.Maid` | Cleanup utility. `Maid.new()` → `:GiveTask(conn)`, `:DoCleaning()`. |
| **MapRegistry** | `ReplicatedStorage.Core.MapRegistry` | `Maps` table and `getMaps()` for map list. |
| **LobbyConfig** | `ReplicatedStorage.Core.Config.LobbyConfig` | Lobby spawn CFrame (`LOBBY_SPAWN_CFRAME`). |
| **HookConfig** | `ReplicatedStorage.Core.Config.HookConfig` | Grappling demo config. Replace with your own config module for your project. |

**Example (any script):**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(ReplicatedStorage.Maid)
local MapRegistry = require(ReplicatedStorage.Core.MapRegistry)

local maid = Maid.new()
maid:GiveTask(someConnection)
local maps = MapRegistry.getMaps()
```

### DevTuning (Server Scripts)

Add custom sliders and report values to the live dashboard. Use for any math-heavy logic—damping, lerp, forces, thresholds:

```lua
local DevTuning = require(ReplicatedStorage.Core.DevTuning)

DevTuning.Register("damping", { slider = true, min = 0, max = 1, default = 0.85, step = 0.01, label = "Damping" })
DevTuning.Register("lerpAlpha", { slider = true, min = 0, max = 1, default = 0.1, label = "Lerp alpha" })

local damping = DevTuning.GetSliderValue("damping") or 0.85
local alpha = DevTuning.GetSliderValue("lerpAlpha") or 0.1
local result = math.lerp(prev, target, alpha) * damping
DevTuning.Report("damping", damping)
DevTuning.Report("lerpAlpha", alpha)
```

See [docs/DEV_TUNING.md](docs/DEV_TUNING.md) for full API.

### Knit Services (Server Scripts)

Get services with `Knit.GetService("ServiceName")` after `Knit.Start()`:

| Service | Methods (server) | Client methods (call from client) |
|---------|------------------|----------------------------------|
| **SpawnService** | `RequestSpawn(player)`, `DeployToGame(player)`, `ReturnToLobby(player)`, `IsPlayerInRound(player)` | Same (client calls server) |
| **MapService** | `GetMaps()`, `VoteMap(player, mapId)`, `StartVoting()`, `EndVoting()`, `GetWinningMap()` | `GetMaps()`, `VoteMap(mapId)`|
| **LobbyService** | — | — |
| **HookService** | — | Grappling demo: `RequestHook`, `ReleaseHook`, `GetGas`, etc. |

**Example (server script):**

```lua
local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.Start():andThen(function()
    local SpawnService = Knit.GetService("SpawnService")
    local MapService = Knit.GetService("MapService")

    local ok, err = SpawnService:RequestSpawn(player)
    local maps = MapService.Client:GetMaps(player)
end)
```

### Knit Client (Client Scripts)

```lua
local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.Start():andThen(function()
    local SpawnService = Knit.GetService("SpawnService")
    local MapService = Knit.GetService("MapService")

    SpawnService:RequestSpawn()
    SpawnService:DeployToGame()
    SpawnService:ReturnToLobby()
    local inRound = SpawnService:IsPlayerInRound()

    local maps = MapService:GetMaps()
    MapService:VoteMap("DevMap")
end)
```

---

## Development

```bash
npm install
npm start
```

- **Rojo** (port 34872): Syncs game files. Connect Roblox Studio to `localhost:34872`.
- **Node** (port 34873): Hooksystem Live Tuning. Open http://localhost:34873 to adjust parameters in real time.

**Velocity graph:** The tuning dashboard uses Chart.js to plot velocity over time during hooking, with smooth curves and zoom/pan.

### Developer Instrumentation

Use the **DevTuning** framework to capture your own data and add **custom sliders** (like Hooksystem controls). From server scripts:

```lua
local DevTuning = require(ReplicatedStorage.Core.DevTuning)

-- Custom slider: appears in left panel, tune in real time
DevTuning.Register("mySpeed", { slider = true, min = 0, max = 100, default = 50, step = 5, label = "My speed" })
local speed = DevTuning.GetSliderValue("mySpeed") or 50

-- Report values to Custom Probes
DevTuning.Report("mySpeed", speed)
```

See [docs/DEV_TUNING.md](docs/DEV_TUNING.md) for full usage.

---

## Tech Stack

- **Rojo** — Sync Luau source into Roblox Studio
- **Knit** — Client–server framework for services and controllers
- **Luau** — Roblox Lua
- **Node.js** — Dev server for HTTP + WebSocket live tuning

---

## License

Uncopylocked. Use and modify for your own projects.
