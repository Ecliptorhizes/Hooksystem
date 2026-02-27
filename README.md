# Zipshot

## Development

```bash
npm install
npm start
```

Runs **Rojo** (live sync) + **tuning server** (live controls). Connect Studio to `localhost:34872`, open http://localhost:34873.

- **Sliders**: Node writes `TuningOverrides.txt` → Rojo syncs → game applies (no plugin needed)