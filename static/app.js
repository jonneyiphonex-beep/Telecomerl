const elements = {
  overall: document.querySelector("#overall-status"),
  overallLabel: document.querySelector("#overall-label"),
  summaryRadio: document.querySelector("#summary-radio"),
  summaryOperator: document.querySelector("#summary-operator"),
  summarySim: document.querySelector("#summary-sim"),
  summaryRegistration: document.querySelector("#summary-registration"),
  summaryProbes: document.querySelector("#summary-probes"),
  summaryLatency: document.querySelector("#summary-latency"),
  lastChecked: document.querySelector("#last-checked"),
  nextCheck: document.querySelector("#next-check"),
  probeCount: document.querySelector("#probe-count"),
  probeList: document.querySelector("#probe-list"),
  modemAvailability: document.querySelector("#modem-availability"),
  radioGeneration: document.querySelector("#radio-generation"),
  radioAccessLabel: document.querySelector("#radio-access-label"),
  simValue: document.querySelector("#sim-value"),
  roamingValue: document.querySelector("#roaming-value"),
  registrationValue: document.querySelector("#registration-value"),
  operatorValue: document.querySelector("#operator-value"),
  networkAvailability: document.querySelector("#network-availability"),
  connectionValue: document.querySelector("#connection-value"),
  apnValue: document.querySelector("#apn-value"),
  typeValue: document.querySelector("#type-value"),
  ipValue: document.querySelector("#ip-value"),
  gatewayValue: document.querySelector("#gateway-value"),
  networkStateValue: document.querySelector("#network-state-value"),
  connectionMessage: document.querySelector("#connection-message"),
  refreshButton: document.querySelector("#refresh-button")
};

let pollTimer;
let lastSnapshot;

function printable(value, fallback = "Not reported") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function setAvailability(element, available, label) {
  const state = available ? "available" : "unavailable";
  element.dataset.state = state;
  element.textContent = `${label} ${available ? "AVAILABLE" : "UNAVAILABLE"}`;
}

function setOverallStatus(snapshot) {
  const probes = Array.isArray(snapshot.internet) ? snapshot.internet : [];
  const onlineCount = probes.filter((probe) => probe.online).length;
  let state;
  let label;

  if (probes.length === 0) {
    state = "unavailable";
    label = "No probes configured";
  } else if (onlineCount === probes.length) {
    state = "online";
    label = "Internet reachable";
  } else if (onlineCount > 0) {
    state = "degraded";
    label = "Partial reachability";
  } else {
    state = "offline";
    label = "No probe reached";
  }

  elements.overall.dataset.state = state;
  elements.overallLabel.textContent = label;
  elements.summaryProbes.textContent = `${onlineCount} / ${probes.length}`;
  const latencies = probes.filter((probe) => probe.online && Number.isFinite(probe.latency_ms))
    .map((probe) => probe.latency_ms);
  const averageLatency = latencies.length
    ? Math.round(latencies.reduce((sum, latency) => sum + latency, 0) / latencies.length)
    : null;
  elements.summaryLatency.textContent = averageLatency === null
    ? "No successful response"
    : `Average response ${averageLatency} ms`;
}

function makeProbeRow(probe) {
  const row = document.createElement("div");
  row.className = "probe-row";

  const target = document.createElement("div");
  const host = document.createElement("div");
  host.className = "probe-target";
  try {
    host.textContent = new URL(probe.url).host || probe.url;
  } catch {
    host.textContent = printable(probe.url, "Unknown target");
  }
  const url = document.createElement("div");
  url.className = "probe-url";
  url.textContent = printable(probe.url);
  target.append(host, url);

  const result = document.createElement("span");
  result.className = "probe-result";
  const state = probe.online ? "online" : "offline";
  result.dataset.state = state;
  result.textContent = probe.online
    ? `Reachable${probe.status ? ` · HTTP ${probe.status}` : ""}`
    : printable(probe.error, "Unreachable");

  const latency = document.createElement("span");
  latency.className = "probe-latency";
  latency.textContent = probe.online && Number.isFinite(probe.latency_ms)
    ? `${probe.latency_ms} ms`
    : "--";

  row.append(target, result, latency);
  return row;
}

function renderProbes(probes) {
  elements.probeCount.textContent = `${probes.length} ${probes.length === 1 ? "target" : "targets"}`;
  elements.probeList.replaceChildren();
  if (!probes.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No internet probes are configured";
    elements.probeList.append(empty);
    return;
  }
  elements.probeList.append(...probes.map(makeProbeRow));
}

function render(snapshot) {
  lastSnapshot = snapshot;
  const modem = snapshot.modem || {};
  const network = snapshot.network || {};
  const probes = Array.isArray(snapshot.internet) ? snapshot.internet : [];
  const radio = printable(modem.radio, "unknown");
  const operator = printable(modem.operator, "Operator unknown");
  const sim = printable(modem.sim, "unknown");
  const registration = printable(modem.registration, "unknown");
  const roaming = printable(modem.roaming, "unknown").toLowerCase();

  setOverallStatus(snapshot);
  elements.summaryRadio.textContent = radio.toUpperCase() === "UNKNOWN" ? "Unknown" : radio;
  elements.summaryOperator.textContent = operator;
  elements.summarySim.textContent = sim;
  elements.summaryRegistration.textContent = registration;
  elements.radioGeneration.textContent = radio.toUpperCase() === "UNKNOWN" ? "--" : radio;
  elements.radioAccessLabel.textContent = radio.toUpperCase() === "UNKNOWN"
    ? "Radio access unknown"
    : `${radio} radio access`;
  elements.simValue.textContent = sim;
  elements.roamingValue.dataset.state = roaming === "roaming" || roaming === "home" ? roaming : "unknown";
  elements.roamingValue.textContent = roaming === "roaming"
    ? "Roaming"
    : roaming === "home" ? "Home network" : "Unknown";
  elements.registrationValue.textContent = registration;
  elements.operatorValue.textContent = operator;
  setAvailability(elements.modemAvailability, Boolean(modem.available), "MODEM");
  setAvailability(elements.networkAvailability, Boolean(network.available), "NETWORK");

  elements.connectionValue.textContent = printable(network.connection || modem.connection);
  elements.apnValue.textContent = printable(modem.apn);
  elements.typeValue.textContent = printable(network.type);
  elements.ipValue.textContent = printable(network.ip);
  elements.gatewayValue.textContent = printable(network.gateway);
  elements.networkStateValue.textContent = printable(network.state);
  elements.lastChecked.textContent = snapshot.checked_at
    ? new Date(snapshot.checked_at * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
    : "Waiting";
  const intervalSeconds = Math.max(1, Math.round((snapshot.interval_ms || 5000) / 1000));
  elements.nextCheck.textContent = `Checks every ${intervalSeconds} seconds`;
  elements.connectionMessage.textContent = "Connected to local diagnostics service";
  renderProbes(probes);
  schedulePoll(snapshot.interval_ms);
}

function schedulePoll(interval) {
  window.clearTimeout(pollTimer);
  const delay = Math.max(1000, Number(interval) || 5000);
  pollTimer = window.setTimeout(loadStatus, delay);
}

async function loadStatus() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error(`Status endpoint returned ${response.status}`);
    render(await response.json());
  } catch (error) {
    elements.connectionMessage.textContent = "Diagnostics service unavailable; retrying shortly";
    elements.overall.dataset.state = "unavailable";
    elements.overallLabel.textContent = "Status unavailable";
    schedulePoll(lastSnapshot?.interval_ms || 5000);
  }
}

async function refreshNow() {
  elements.refreshButton.disabled = true;
  elements.refreshButton.classList.add("is-refreshing");
  try {
    const response = await fetch("/api/refresh", { cache: "no-store" });
    if (!response.ok) throw new Error(`Refresh endpoint returned ${response.status}`);
    render(await response.json());
    elements.connectionMessage.textContent = "Refresh requested; checks update in the background";
  } catch {
    elements.connectionMessage.textContent = "Unable to request a refresh";
  } finally {
    elements.refreshButton.disabled = false;
    elements.refreshButton.classList.remove("is-refreshing");
  }
}

elements.refreshButton.addEventListener("click", refreshNow);
loadStatus();