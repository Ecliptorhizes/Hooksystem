/**
 * Zipshot Tuning Server - PIDebug-style architecture
 * Run from project root: npm run tuning  (or: node dev-server/server.js)
 * Run from dev-server:  npm run tuning   (or: node server.js)
 *
 * Config: dev-server/zipshot_config.json (httpPort, wsWebPort)
 * Rojo uses 34872. HTTP default 34873, WebSocket 34874.
 */

const express = require("express");
const cors = require("cors");
const WebSocket = require("ws");
const path = require("path");
const fs = require("fs");

// Resolve paths: server.js lives in dev-server/, project root is one level up
const DEV_SERVER_DIR = path.resolve(__dirname);
const PROJECT_ROOT = path.resolve(DEV_SERVER_DIR, "..");
const TUNING_OVERRIDES_PATH = path.join(PROJECT_ROOT, "src/shared/Core/Config/TuningOverrides.txt");

let config = { httpPort: 34873, wsWebPort: 34874 };
const configPath = path.join(DEV_SERVER_DIR, "zipshot_config.json");
try {
  config = JSON.parse(fs.readFileSync(configPath, { encoding: "utf8" }));
} catch (err) {
  console.warn("[Zipshot] No zipshot_config.json, using defaults:", config);
}

const app = express();

// Config overrides - written to TuningOverrides.txt, Rojo syncs to game
let configOverrides = {};
try {
  const raw = fs.readFileSync(TUNING_OVERRIDES_PATH, "utf8");
  const parsed = JSON.parse(raw);
  if (typeof parsed === "object" && parsed !== null) configOverrides = parsed;
} catch (err) {
  console.warn("[Zipshot] Could not read TuningOverrides.txt:", err.message);
  console.warn("  Path:", TUNING_OVERRIDES_PATH);
}

// Live values (Test button or future plugin via POST /api/live)
let liveValues = {
  velocity: 0,
  velocityMagnitude: 0,
  speed: 0,
  isHooked: false,
  gas: null,
  reelForce: null,
  swingForce: null,
  hasLeft: false,
  hasRight: false,
  leftRopeLen: null,
  rightRopeLen: null,
  lastUpdate: null,
};

// Defaults from HookConfig - used for slider ranges and initial values
const CONFIG_SCHEMA = {
  PullForceSingle: { min: 0, max: 100, default: 20, step: 1 },
  PullForceDual: { min: 0, max: 50, default: 10, step: 1 },
  ReelInPullForce: { min: 0, max: 100, default: 45, step: 1 },
  LaunchForceMultiplier: { min: 1, max: 30, default: 12, step: 0.5 },
  LaunchVelocityCap: { min: 0, max: 200, default: 120, step: 5 },
  LaunchUpwardCap: { min: 0, max: 80, default: 35, step: 1 },
  LaunchDownwardCap: { min: 0, max: 100, default: 60, step: 1 },
  SwingForce: { min: 0, max: 80, default: 35, step: 1 },
  PendulumMomentum: { min: 0, max: 1, default: 0.6, step: 0.05 },
  BoostPendulumMomentum: { min: 0, max: 1, default: 0.35, step: 0.05 },
  ReelPendulumMomentum: { min: 0, max: 1, default: 0.4, step: 0.05 },
  GrappleSpeedSingle: { min: 0, max: 400, default: 150, step: 5 },
  GrappleSpeedDual: { min: 0, max: 500, default: 300, step: 5 },
  ReelInSpeedMultiplier: { min: 0.5, max: 3, default: 1.4, step: 0.1 },
  ArmPullForce: { min: 0, max: 10000, default: 5200, step: 100 },
  ArmReelForce: { min: 0, max: 10000, default: 6800, step: 100 },
  ArmBoostForce: { min: 0, max: 500, default: 220, step: 10 },
  MomentumRetention: { min: 0, max: 1, default: 0.8, step: 0.05 },
  GravityScaleWhenHooked: { min: 0, max: 1, default: 0.5, step: 0.05 },
};

app.use(cors());
app.use(express.json());
app.use("/public", express.static(path.join(__dirname, "public")));

const apiRouter = express.Router();

apiRouter.get("/rojo", (req, res) => {
  res.json({ ok: true, message: "Rojo runs on port 34872. Connect Studio to localhost:34872" });
});

apiRouter.get("/config", (req, res) => {
  res.json(configOverrides);
});

apiRouter.post("/config", (req, res) => {
  configOverrides = { ...configOverrides, ...req.body };
  try {
    fs.writeFileSync(TUNING_OVERRIDES_PATH, JSON.stringify(configOverrides, null, 0), "utf8");
  } catch (err) {
    console.warn("Could not write TuningOverrides.txt:", err.message);
  }
  res.json({ ok: true });
});

apiRouter.get("/schema", (req, res) => {
  res.json(CONFIG_SCHEMA);
});

// POST /api/live - Accept live data (Test button or future plugin)
apiRouter.post("/live", (req, res) => {
  const body = typeof req.body === "object" && req.body !== null ? req.body : {};
  liveValues = {
    ...liveValues,
    ...body,
    lastUpdate: new Date().toISOString(),
  };
  res.json({ ok: true });
});

// GET /api/live - Fallback for polling (WebSocket is primary)
apiRouter.get("/live", (req, res) => {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
  res.json(liveValues);
});

apiRouter.post("/reset", (req, res) => {
  configOverrides = {};
  try {
    fs.writeFileSync(TUNING_OVERRIDES_PATH, "{}", "utf8");
  } catch (err) {
    console.warn("Could not write TuningOverrides.txt:", err.message);
  }
  res.json({ ok: true });
});

apiRouter.get("/health", (req, res) => {
  res.json({ ok: true, live: !!liveValues.lastUpdate });
});

apiRouter.get("/ports", (req, res) => {
  res.json({ wsWebPort: config.wsWebPort });
});

app.use("/api", apiRouter);

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(config.httpPort, () => {
  console.log("");
  console.log("Zipshot Tuning ready");
  console.log("  Browser:  http://localhost:" + config.httpPort);
  console.log("  Rojo:     34872 (connect Studio to localhost:34872)");
  console.log("  HTTP:    " + config.httpPort + " | WS: " + config.wsWebPort);
  console.log("  Config:  " + TUNING_OVERRIDES_PATH);
  console.log("");
});

// WebSocket server (PIDebug-style) - push live data to browser every 20ms
const wsWebServer = new WebSocket.Server({ port: config.wsWebPort });

wsWebServer.on("connection", (ws) => {
  let handle;
  ws.on("close", () => {
    clearInterval(handle);
  });
  ws.on("message", (msg) => {
    try {
      const data = JSON.parse(msg);
      if (data.type === "set_state" && data.state) {
        configOverrides = { ...configOverrides, ...data.state };
        try {
          fs.writeFileSync(TUNING_OVERRIDES_PATH, JSON.stringify(configOverrides, null, 0), "utf8");
        } catch (_) {}
      }
    } catch (_) {}
  });
  handle = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ live: liveValues }));
    }
  }, 20);
});

console.log(`WebSocket server running on port ${config.wsWebPort}`);
