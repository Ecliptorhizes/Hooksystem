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
    └── Core/Config/
        ├── HookConfig.luau   # All tuning parameters
        ├── LobbyConfig.luau  # Lobby spawn position
        └── TuningOverrides.txt  # Live-tuned values (written by dev server)
```

---

## Development

```bash
npm install
npm start
```

- **Rojo** (port 34872): Syncs game files. Connect Roblox Studio to `localhost:34872`.
- **Node** (port 34873): Hooksystem Live Tuning. Open http://localhost:34873 to adjust parameters in real time.

Rojo handles file sync; the Node server handles live tuning. Both can run together via `npm start`.

---

## Tech Stack

- **Rojo** — Sync Luau source into Roblox Studio
- **Knit** — Client–server framework for services and controllers
- **Luau** — Roblox Lua
- **Node.js** — Dev server for HTTP + WebSocket live tuning

---

## License

Uncopylocked. Use and modify for your own projects.
