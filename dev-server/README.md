# Zipshot Dev Server

Live tuning dashboard for hook physics. Adjust values in the browser while the game runs in Roblox Studio.

## One command: live sync + live tuning

Like `npx rbxtsc -w` for TypeScript, run one command to get everything:

```bash
# From project root (installs deps first if needed)
npm install
npm start
```

This runs:
- **Rojo** (port 34872) – live sync: file changes → Studio
- **Tuning server** (port 34873) – live tuning: sliders → game in real time

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

Edit `dev-server/zipshot_config.json` to change ports:

```json
{
  "httpPort": 34873,
  "wsWebPort": 34874
}
```

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

4. Press **Play** in Studio – sliders apply in real time. (Live feed is not available; Roblox blocks server scripts from localhost.)

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
- **Config only**: no plugin, no live feed (Roblox blocks localhost from server scripts)
