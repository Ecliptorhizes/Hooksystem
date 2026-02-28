# Zipshot Dev Server (Node.js Only)

Live tuning dashboard for hook physics. **Node.js only** – no Rojo, no sync.

## Separation

- **Rojo** = syncs game files (src/) to Studio. Run with `npm run rojo`.
- **Node** = Zipshot Live Tuning. Run with `npm run tuning`.

## Run

```bash
# Tuning server only (Node.js)
npm run tuning
```

Or run both together:

```bash
npm start   # Rojo + Node
```

- **Rojo** (34872) – syncs game files only
- **Node** (34873/34874) – tuning dashboard only

**Workflow:**
1. `npm start` (or `npm run dev`)
2. In Studio: connect to **localhost:34872** (Rojo plugin)
3. Open **http://localhost:34873** in your browser (tuning UI)
4. Press **Play** in Studio
5. Edit code → Rojo syncs. Adjust sliders → changes apply live.

## Setup

```bash
cd dev-server
npm install
```

## Configuration

Edit `dev-server/zipshot_config.json`:

```json
{
  "httpPort": 34873,
  "wsWebPort": 34874,
  "openCloudApiKey": "your Open Cloud API key",
  "universeId": "your game's universe ID"
}
```

**Open Cloud (Node → Game):** For real-time config from the web dashboard to the game without localhost, add `openCloudApiKey` and `universeId`. Get the API key at [create.roblox.com](https://create.roblox.com) → Open Cloud → API Keys. Find your universe ID in Game Settings → General.

## Run options

| Command | What runs |
|---------|-----------|
| `npm start` (from root) | Rojo + tuning (both) |
| `npm run dev` | Same as start |
| `npm run rojo` | Rojo only (port 34872) |
| `npm run tuning` | Tuning only (HTTP + WebSocket) |

**Using vscode-rojo:** The extension runs Rojo for you. In that case, run `npm run tuning` in a terminal for the dashboard.

## Usage

1. Start both servers:
   ```bash
   npm start
   ```

2. Connect Studio to **localhost:34872** (Rojo)

3. Open **http://localhost:34873** in your browser

4. Press **Play** in Studio – sliders apply in real time.

**Node → Game via Open Cloud:** When `openCloudApiKey` and `universeId` are set, slider changes are published to Roblox MessagingService. The game subscribes and applies config in real time.

**Live data (Game → Node):** Roblox blocks HTTP from the game to localhost. On startup, the server writes your machine's local IP (e.g. `http://192.168.1.5:34873`) to `DevServerUrl.txt`. Rojo syncs that into the game. The game POSTs live data to that URL. Ensure Rojo is running so the game gets the updated URL.

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/config` | GET | Game fetches config overrides to apply |
| `/api/config` | POST | Web UI sends new values |
| `/api/schema` | GET | Slider metadata (min, max, default) |
| `/api/live` | GET | Live values (Test button only; no plugin) |
| `/api/reset` | POST | Clear all overrides |

## How It Works

- **Architecture** (inspired by [PIDebug](https://github.com/Sleitnick/PIDebug)): HTTP API + WebSocket for real-time push
- **DevTuningServer** (src/server/DevTuningServer.luau) runs only in Studio
- Reads `TuningOverrides.txt` via Rojo sync and applies overrides to HookConfig
- **Config**: Rojo sync (TuningOverrides.txt), HTTP poll, or Open Cloud MessagingService (when configured).
