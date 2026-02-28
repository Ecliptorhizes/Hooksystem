# Zipshot Architecture: Rojo vs Node.js

## Separation of Responsibilities

| Component | Responsibility | Does NOT |
|-----------|----------------|----------|
| **Rojo** | Syncs game files (src/) to Roblox Studio | Run Node, serve HTTP, write config |
| **Node.js** | Zipshot Live Tuning server (HTTP, dashboard, config API) | Sync to Studio, run Rojo |

## Rojo (Game Sync Only)

- **Source:** `default.project.json`
- **Syncs:** `src/server`, `src/client`, `src/shared`, `Packages`, `ServerPackages`
- **Port:** 34872
- **Command:** `npm run rojo` or `rojo serve`
- **Does NOT:** Include dev-server, run Node, or handle tuning API

## Node.js (Live Tuning Only)

- **Source:** `dev-server/server.js`
- **Serves:** HTTP dashboard (34873), WebSocket (34874)
- **Writes:** `src/shared/Core/Config/TuningOverrides.txt` (sliders)
- **Command:** `npm run tuning` or `node dev-server/server.js`
- **Does NOT:** Sync to Studio, run Rojo, or modify game scripts

## Data Flow

**Live feed (game → Node):**
```
Game (Play mode) → DevTuningServer POSTs /api/live → Node stores liveValues
Dashboard polls /api/live or WebSocket → displays velocity, hook state, position
```

**Settings (Node → game):**
```
Sliders (browser) → Node POST /api/config → writes TuningOverrides.txt
                                              ↓
Rojo syncs src/shared (Edit mode) OR DevTuningServer polls /api/config (Play mode)
                                              ↓
DevTuningServer applies overrides to HookConfig
```

## Run Commands

| Command | Rojo | Node |
|---------|------|------|
| `npm run rojo` | ✓ | ✗ |
| `npm run tuning` | ✗ | ✓ |
| `npm start` | ✓ | ✓ |
