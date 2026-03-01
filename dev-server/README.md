# Hooksystem Dev Server (Node.js Only)

Live tuning dashboard for hook physics. WebSocket + HTTP API for real-time config and live event data. **Node.js only** – no Rojo, no sync.

## Run

```bash
npm start
```

- **Rojo** (34872) – syncs game files
- **Node** (34873/34874) – tuning dashboard

**Workflow:**
1. `npm start`
2. In Studio: connect to **localhost:34872** (Rojo plugin)
3. Open **http://localhost:34873** in your browser (tuning UI)
4. Press **Play** in Studio
5. Edit code → Rojo syncs. Adjust sliders → changes apply live.

## Setup

From project root:

```bash
npm install
npm start
```

## Configuration

Edit `dev-server/hooksystem_config.json`:

```json
{
  "httpPort": 34873,
  "wsWebPort": 34874,
  "openCloudApiKey": "your Open Cloud API key",
  "universeId": "your game's universe ID"
}
```

**Open Cloud (Node → Game):** For real-time config from the web dashboard to the game, add `openCloudApiKey` and `universeId` to `hooksystem_config.json`. Get the API key at [create.roblox.com](https://create.roblox.com) → Open Cloud → API Keys. Restrict the key to your experience. Find your universe ID (game/experience ID) in Game Settings → General.

## Usage

1. Run:
   ```bash
   npm start
   ```

2. Connect Studio to **localhost:34872** (Rojo)

3. Open **http://localhost:34873** in your browser

4. Press **Play** in Studio – sliders apply in real time.

**Node → Game via Open Cloud:** When `openCloudApiKey` and `universeId` are set, slider changes are published to Roblox MessagingService. The game subscribes and applies config in real time.

**Live data (Game → Node):** On startup, the server writes `http://localhost:34873` to `DevServerUrl.txt`. Rojo syncs that into the game. The game POSTs live data to that URL. Ensure Rojo is running so the game gets the updated URL.

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/config` | GET | Game fetches config overrides to apply |
| `/api/config` | POST | Web UI sends new values |
| `/api/schema` | GET | Slider metadata (min, max, default) |
| `/api/live` | GET | Live values (game POSTs; Test button simulates) |
| `/api/reset` | POST | Clear all overrides |

## How It Works

- **DevTuningServer** (src/server/DevTuningServer.luau) runs only in Studio
- Reads `TuningOverrides.txt` via Rojo sync and applies overrides to HookConfig
- **Config**: Rojo sync (TuningOverrides.txt), HTTP poll, or Open Cloud MessagingService (when configured).
