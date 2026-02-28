# DevTuningBridge Plugin

Bridges live game data to the tuning dashboard. **No publishing required** – install locally.

## Install (choose one method)

### Method A: Built plugin (.rbxm / .rbxmx)

1. **Build:** From project root run `npm run build:plugin`
2. **Copy:** Plugins → Plugins Folder → copy `DevTuningBridge.rbxm` (or `DevTuningBridge.rbxmx`) from `dev-server/plugin/` into that folder
3. **Restart Studio** (or Plugins → Manage Plugins → enable DevTuningBridge)

**Mac Plugins folder:** `~/Library/Application Support/Roblox/Plugins`

### Method B: Manual install (if Studio doesn't recognize the .rbxm)

1. In Studio: ServerStorage → Insert Object → **Script** → rename to `DevTuningBridge`
2. Copy the full contents of `DevTuningBridge.plugin.lua` into the script
3. With the script selected: **Plugins** → **Save as Local Plugin** → Save
4. Restart Studio

See `INSTALL_MANUAL.md` for detailed steps.

### Enable HttpService

**Game Settings** → **Security** → enable **Allow HTTP Requests**

## Usage

1. Run `npm run tuning` (Node server)
2. Connect Studio to Rojo (localhost:34872)
3. Open http://localhost:34873 in your browser
4. Press **Play** in Studio

You should see in Output:
- `[DevTuningServer] Bridge created...`
- `[DevTuningServer]` live data POSTs to the dev server (game uses local IP from DevServerUrl.txt)

The plugin shows status in its GUI but cannot relay live data (see limitation above). The game sends it directly.

## Why the plugin exists (and its limitation)

**Roblox plugins cannot see the running game's data.** Plugins run in a separate DataModel from the game. When you press Play, the game runs in a runtime copy; the plugin still sees the edit DataModel, so it never sees `DevTuningBridge.LiveData`.

**Live data flow:** The game (DevTuningServer) POSTs directly to the Node server. Roblox blocks localhost, so the server writes your machine's local IP (e.g. `http://192.168.1.5:34873`) to `DevServerUrl.txt` on startup. Rojo syncs that into the game. The game then POSTs to that URL, which works.
