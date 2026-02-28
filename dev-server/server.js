const express = require("express");
const cors = require("cors");
const WebSocket = require("ws");
const path = require("path");
const fs = require("fs");
const https = require("https");
const os = require("os");

const DEV_SERVER_DIR = path.resolve(__dirname);
const PROJECT_ROOT = path.resolve(DEV_SERVER_DIR, "..");
const TUNING_OVERRIDES_PATH = path.join(PROJECT_ROOT, "src/shared/Core/Config/TuningOverrides.txt");

let config = { httpPort: 34873, wsWebPort: 34874, openCloudApiKey: "", universeId: "" };
const configPath = path.join(DEV_SERVER_DIR, "zipshot_config.json");
try {
  config = { ...config, ...JSON.parse(fs.readFileSync(configPath, { encoding: "utf8" })) };
} catch (err) {
  console.warn("[Zipshot] No zipshot_config.json, using defaults:", config);
}

const MESSAGING_TOPIC = "ZipshotTuning";
let messagingDisabled = false;
// #region agent log
const DEBUG_INGEST = "http://127.0.0.1:7370/ingest/3d0ecf27-f5dc-4258-87ce-54cd9abc4adb";
function agentLog(location, message, data, hypothesisId) {
  try {
    fetch(DEBUG_INGEST, { method: "POST", headers: { "Content-Type": "application/json", "X-Debug-Session-Id": "147f07" }, body: JSON.stringify({ sessionId: "147f07", location, message, data: data || {}, hypothesisId, timestamp: Date.now() }) }).catch(() => {});
  } catch (_) {}
}
// #endregion

function publishToMessagingService(message) {
  // #region agent log
  if (messagingDisabled || !config.openCloudApiKey || !config.universeId) {
    if (messagingDisabled) agentLog("server.js:publishToMessagingService", "publish_skipped_disabled", {}, "H1");
    else agentLog("server.js:publishToMessagingService", "publish_skipped_missing_config", { hasKey: !!config.openCloudApiKey, hasUniverseId: !!config.universeId }, "H1");
    return;
  }
  agentLog("server.js:publishToMessagingService", "publish_attempt", { universeId: config.universeId, topic: MESSAGING_TOPIC }, "H1");
  // #endregion
  const body = JSON.stringify({ message: typeof message === "string" ? message : JSON.stringify(message) });
  if (body.length > 1024) return;
  const req = https.request({
    hostname: "apis.roblox.com",
    path: `/messaging-service/v1/universes/${config.universeId}/topics/${MESSAGING_TOPIC}`,
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": config.openCloudApiKey,
    },
  }, (res) => {
    // #region agent log
    let data = "";
    res.on("data", (c) => { data += c; });
    res.on("end", () => {
      if (res.statusCode !== 200) {
        agentLog("server.js:publishToMessagingService", "publish_failed", { statusCode: res.statusCode, body: data.slice(0, 200) }, "H1");
        if (res.statusCode === 403) {
          messagingDisabled = true;
          console.warn("[Zipshot] MessagingService disabled (403). Sliders still work via Rojo sync + HTTP.");
          if (data.includes("cannot manage universe")) {
            console.warn("[Zipshot] To fix: Creator Dashboard → Open Cloud → API Keys → Edit key → Restrict by Experience → select your game.");
          }
        } else {
          console.warn("[Zipshot] MessagingService publish failed:", res.statusCode, data);
        }
      } else {
        agentLog("server.js:publishToMessagingService", "publish_ok", { statusCode: res.statusCode }, "H1");
      }
    });
    // #endregion
  });
  req.on("error", (err) => {
    // #region agent log
    agentLog("server.js:publishToMessagingService", "publish_error", { err: err.message }, "H1");
    // #endregion
    console.warn("[Zipshot] MessagingService error:", err.message);
  });
  req.write(body);
  req.end();
}

const app = express();

let configOverrides = {};
try {
  const raw = fs.readFileSync(TUNING_OVERRIDES_PATH, "utf8");
  const parsed = JSON.parse(raw);
  if (typeof parsed === "object" && parsed !== null) configOverrides = parsed;
} catch (err) {
  console.warn("[Zipshot] Could not read TuningOverrides.txt:", err.message);
  console.warn("  Path:", TUNING_OVERRIDES_PATH);
}

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

apiRouter.get("/config", (req, res) => {
  res.json(configOverrides);
});

apiRouter.post("/config", (req, res) => {
  const keys = Object.keys(req.body || {});
  writeDebugLog("POST /api/config received", { keys });
  configOverrides = { ...configOverrides, ...req.body };
  try {
    fs.writeFileSync(TUNING_OVERRIDES_PATH, JSON.stringify(configOverrides, null, 0), "utf8");
  } catch (err) {
    console.warn("Could not write TuningOverrides.txt:", err.message);
  }
  publishToMessagingService(configOverrides);
  res.json({ ok: true });
});

apiRouter.get("/schema", (req, res) => {
  res.json(CONFIG_SCHEMA);
});

apiRouter.post("/live", (req, res) => {
  const body = typeof req.body === "object" && req.body !== null ? req.body : {};
  // #region agent log
  agentLog("server.js:POST /api/live", "live_received", { keys: Object.keys(body), hasVelocity: "velocityMagnitude" in body, vel: body.velocityMagnitude }, "H2");
  // #endregion
  writeDebugLog("POST /api/live received", { hasVelocity: "velocityMagnitude" in body, keys: Object.keys(body).slice(0, 5) });
  liveValues = {
    ...liveValues,
    ...body,
    lastUpdate: new Date().toISOString(),
  };
  res.json({ ok: true });
});

let getLiveCount = 0;
apiRouter.get("/live", (req, res) => {
  getLiveCount += 1;
  // #region agent log
  if (getLiveCount <= 3 || getLiveCount % 100 === 1) agentLog("server.js:GET /api/live", "live_poll", { count: getLiveCount, hasLastUpdate: !!liveValues.lastUpdate, vel: liveValues.velocityMagnitude }, "H4");
  // #endregion
  if (getLiveCount % 50 === 1) writeDebugLog("GET /api/live", { count: getLiveCount, hasLastUpdate: !!liveValues.lastUpdate });
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
  // #region agent log
  agentLog("server.js:GET /api/health", "health_check", { live: !!liveValues.lastUpdate }, "H6");
  // #endregion
  res.json({ ok: true, live: !!liveValues.lastUpdate });
});

apiRouter.get("/ports", (req, res) => {
  res.json({ wsWebPort: config.wsWebPort });
});

const DEBUG_LOG_PATH = path.join(PROJECT_ROOT, ".cursor", "debug-147f07.log");
function writeDebugLog(message, data = {}) {
  try {
    const line = JSON.stringify({ sessionId: "147f07", message, data, timestamp: Date.now(), hypothesisId: "H3" }) + "\n";
    fs.appendFileSync(DEBUG_LOG_PATH, line, "utf8");
  } catch (_) {}
}
apiRouter.post("/debug", (req, res) => {
  try {
    const payload = typeof req.body === "object" && req.body !== null ? req.body : {};
    // #region agent log
    agentLog("server.js:POST /api/debug", "debug_from_game", { message: payload.message, keys: Object.keys(payload) }, "H2");
    // #endregion
    const line = JSON.stringify({
      sessionId: "147f07",
      ...payload,
      timestamp: payload.timestamp || Date.now(),
    }) + "\n";
    fs.appendFileSync(DEBUG_LOG_PATH, line, "utf8");
  } catch (_) {}
  res.json({ ok: true });
});

app.use("/api", apiRouter);

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

function getLocalIp() {
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === "IPv4" && !net.internal) return net.address;
    }
  }
  return null;
}

const DEV_SERVER_URL_TXT = path.join(PROJECT_ROOT, "src/shared/Core/Config/DevServerUrl.txt");
app.listen(config.httpPort, "0.0.0.0", () => {
  // #region agent log
  agentLog("server.js:listen", "server_started", { httpPort: config.httpPort, hasKey: !!config.openCloudApiKey, keyLen: (config.openCloudApiKey || "").length, universeId: config.universeId }, "H3");
  // #endregion
  writeDebugLog("Node server started", { httpPort: config.httpPort, wsWebPort: config.wsWebPort });
  const localIp = getLocalIp();
  const gameUrl = localIp ? `http://${localIp}:${config.httpPort}` : null;
  if (gameUrl) {
    try {
      fs.writeFileSync(DEV_SERVER_URL_TXT, gameUrl, "utf8");
    } catch (e) {
      console.warn("[Zipshot] Could not write DevServerUrl.txt:", e.message);
    }
  }
  console.log("");
  console.log("Zipshot Live Tuning");
  console.log("  Dashboard: http://localhost:" + config.httpPort);
  if (gameUrl) {
    console.log("  Game URL:  " + gameUrl + " (Roblox needs this; localhost is blocked)");
  }
  console.log("  Config: " + TUNING_OVERRIDES_PATH);
  console.log("");
});

const wsWebServer = new WebSocket.Server({ port: config.wsWebPort });

wsWebServer.on("connection", (ws) => {
  // #region agent log
  agentLog("server.js:ws", "ws_connected", {}, "H4");
  // #endregion
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
          publishToMessagingService(configOverrides);
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
