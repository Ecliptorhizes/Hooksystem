# DevTuningBridge Plugin

Bridges live game data to the tuning dashboard. **No publishing required** – install locally by copying the `.rbxm` file.

## Install (one-time)

### 1. Build the plugin

From project root:
```bash
cd dev-server/plugin
rojo build -o DevTuningBridge.rbxm
```

Or from project root:
```bash
npm run build:plugin
```
(Add this script to root `package.json` if needed.)

### 2. Copy to Plugins folder

1. Open **Roblox Studio**
2. Go to **Plugins** → **Plugins Folder** (opens your plugins folder in Finder/Explorer)
3. Copy `DevTuningBridge.rbxm` from `dev-server/plugin/` into that folder
4. **Restart Studio** (or go to Plugins → Manage Plugins and enable DevTuningBridge)

### 3. Enable HttpService

**Game Settings** → **Security** → enable **Allow HTTP Requests**

## Usage

1. Run `npm run tuning` (Node server)
2. Connect Studio to Rojo (localhost:34872)
3. Open http://localhost:34873 in your browser
4. Press **Play** in Studio

You should see in Output:
- `[DevTuningServer] Bridge created...`
- `[DevTuningBridge] Plugin ready. Dev server: http://localhost:34873`
- `[DevTuningBridge] Connected. Live data flowing to dashboard.`

## What it does

The game writes live data (velocity, hook state, position) to `ReplicatedStorage.DevTuningBridge.LiveData`. The plugin reads it and POSTs to localhost. Roblox blocks server scripts from localhost, but plugins can reach it.
