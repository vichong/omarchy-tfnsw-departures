.pragma library
.import "Api.js" as Api

// Persisted, non-secret configuration. The API key never lives here — it is
// stored in the system keyring (see CredentialManager.qml).

var POLL_MIN = 30
var POLL_MAX = 600
var POLL_DEFAULT = 60
var MAX_PLACES = 12
var MAX_WALK_MINUTES = 60

var KEYS = ["demoMode", "places", "activePlaceId", "autoPlace", "pollSeconds", "notify", "colorful"]

function intOr(value, fallback) {
  var n = typeof value === "number" ? value : parseInt(value, 10)
  return isNaN(n) ? fallback : n
}

function finiteNumber(value) {
  return typeof value === "number" && isFinite(value) ? Number(value) : null
}

function clampPoll(value) {
  return Math.max(POLL_MIN, Math.min(POLL_MAX, intOr(value, POLL_DEFAULT)))
}

function cleanText(value, max) {
  if (typeof value !== "string") return ""
  return value.replace(/[\x00-\x1f\x7f]/g, "").trim().slice(0, max || 80)
}

function lineList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && out.length < 12; i++) {
    var line = cleanText(value[i], 8).toUpperCase()
    if (line && out.indexOf(line) === -1) out.push(line)
  }
  return out
}

function modeList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var id = String(value[i])
    if (Api.isValidModeId(id) && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function placeId(value, index) {
  var id = cleanText(value, 40).replace(/[^A-Za-z0-9._-]/g, "")
  return id || ("place-" + (index + 1))
}

function parsePlace(raw, index) {
  if (!raw || typeof raw !== "object") return null
  if (!Api.isStopId(raw.stopId)) return null
  // A destination makes the place a trip; it needs a valid stop id or is dropped.
  var hasDestination = Api.isStopId(raw.destStopId) && String(raw.destStopId) !== String(raw.stopId)
  var destAddress = hasDestination ? cleanText(raw.destAddress, 120) : ""
  var destLat = finiteNumber(raw.destLat), destLon = finiteNumber(raw.destLon)
  var hasDestCoord = destAddress !== "" && destLat !== null && destLon !== null
    && destLat >= -90 && destLat <= 90 && destLon >= -180 && destLon <= 180
  return {
    id: placeId(raw.id, index),
    name: cleanText(raw.name, 40) || ("Place " + (index + 1)),
    stopId: String(raw.stopId),
    stopName: cleanText(raw.stopName, 80),
    destStopId: hasDestination ? String(raw.destStopId) : "",
    destStopName: hasDestination ? cleanText(raw.destStopName, 80) : "",
    destAddress: hasDestCoord ? destAddress : "",
    destLat: hasDestCoord ? destLat : null,
    destLon: hasDestCoord ? destLon : null,
    destWalkMinutes: hasDestCoord ? Math.max(0, Math.min(MAX_WALK_MINUTES, intOr(raw.destWalkMinutes, 0))) : 0,
    lines: lineList(raw.lines),
    destination: cleanText(raw.destination, 60),
    modes: modeList(raw.modes),
    walkMinutes: Math.max(0, Math.min(MAX_WALK_MINUTES, intOr(raw.walkMinutes, 0))),
    ssid: cleanText(raw.ssid, 64)
  }
}

function parsePlaces(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < value.length && out.length < MAX_PLACES; i++) {
    var place = parsePlace(value[i], i)
    if (!place || seen[place.id]) continue
    seen[place.id] = true
    out.push(place)
  }
  return out
}

function parse(text) {
  var raw = {}
  var error = ""
  try {
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      raw = {}
      error = "config.json must contain a JSON object"
    }
  } catch (exception) {
    raw = {}
    error = "config.json is not valid JSON"
  }
  var places = parsePlaces(raw.places)
  var active = cleanText(raw.activePlaceId, 40)
  var known = false
  for (var i = 0; i < places.length; i++) if (places[i].id === active) known = true
  return {
    error: error,
    config: {
      demoMode: raw.demoMode === true,
      places: places,
      activePlaceId: known ? active : (places.length ? places[0].id : ""),
      autoPlace: raw.autoPlace !== false,
      pollSeconds: clampPoll(raw.pollSeconds),
      notify: raw.notify !== false,
      colorful: raw.colorful === true
    }
  }
}

function merge(current, patch) {
  var result = {}
  for (var i = 0; i < KEYS.length; i++) result[KEYS[i]] = current[KEYS[i]]
  for (var p = 0; p < KEYS.length; p++) {
    var key = KEYS[p]
    if (Object.prototype.hasOwnProperty.call(patch || {}, key)) result[key] = patch[key]
  }
  return result
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}

function newPlaceId(places) {
  var used = {}
  for (var i = 0; i < places.length; i++) used[places[i].id] = true
  for (var n = 1; n < 1000; n++) if (!used["place-" + n]) return "place-" + n
  return "place-" + Date.now()
}
