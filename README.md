# Hooksystem

Uncopylocked Roblox hook system. Use the WebSocket + HTTP API for real-time tuning and live data in your own projects.

## Development

```bash
npm install
npm start
```

- **Rojo** (34872): Syncs game files only. Connect Studio to `localhost:34872`.
- **Node** (34873): Hooksystem Live Tuning only. Open http://localhost:34873.

**Separation:** Rojo syncs Rojo. Node runs tuning. See [ARCHITECTURE.md](ARCHITECTURE.md).