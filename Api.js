.pragma library

// Pure helpers for the Transport for NSW Trip Planner API
// (https://opendata.transport.nsw.gov.au/dataset/trip-planner-apis).
// Nothing here performs I/O; LiveBackend.qml owns the curl transport.

var BASE_URL = "https://api.transport.nsw.gov.au"
var TP_PATH = "/v1/tp"
var ALERTS_URL = "https://transportnsw.info/alerts"
var REGISTER_URL = "https://opendata.transport.nsw.gov.au/data/user/register"
var APPLICATIONS_URL = "https://opendata.transport.nsw.gov.au/data/user/applications"

// Ceiling on any API response body we are willing to buffer or parse. A
// full departure board for a busy interchange is ~300 KB; a trip with four
// journeys ~250 KB. Unfiltered service alerts (~3 MB) are deliberately
// never requested.
var MAX_RESPONSE_BYTES = 2 * 1024 * 1024
var MAX_STOP_EVENTS = 120
var MAX_JOURNEYS = 6
var MAX_LOCATIONS = 20

// Trip Planner product classes → mode. Colours are TfNSW's mode palette;
// the letter is the roundel glyph. Class 100 is a walking leg.
var MODES = [
  { cls: 1,  id: "train",     label: "Train",      letter: "T", color: "#F6891F", motBit: 1 },
  { cls: 2,  id: "metro",     label: "Metro",      letter: "M", color: "#168388", motBit: 2 },
  { cls: 4,  id: "lightrail", label: "Light rail", letter: "L", color: "#E4022D", motBit: 4 },
  { cls: 5,  id: "bus",       label: "Bus",        letter: "B", color: "#00B5EF", motBit: 5 },
  { cls: 7,  id: "coach",     label: "Coach",      letter: "C", color: "#732A82", motBit: 7 },
  { cls: 9,  id: "ferry",     label: "Ferry",      letter: "F", color: "#5AB031", motBit: 9 },
  { cls: 11, id: "schoolbus", label: "School bus", letter: "B", color: "#F6C700", motBit: 11 }
]
var WALK_CLASS = 100
var DEFAULT_MODE = { cls: 0, id: "other", label: "Service", letter: "•", color: "#888888", motBit: 0 }

function modeFor(cls) {
  var n = parseInt(cls, 10)
  for (var i = 0; i < MODES.length; i++) if (MODES[i].cls === n) return MODES[i]
  return DEFAULT_MODE
}
function modeById(id) {
  for (var i = 0; i < MODES.length; i++) if (MODES[i].id === id) return MODES[i]
  return DEFAULT_MODE
}
function isValidModeId(id) {
  for (var i = 0; i < MODES.length; i++) if (MODES[i].id === id) return true
  return false
}

function errorResult(kind, message) {
  return { ok: false, status: 0, kind: String(kind || ""), error: String(message || ""), data: null }
}

function urlOrigin(url) {
  var match = String(url || "").match(/^([A-Za-z][A-Za-z0-9+.-]*):\/\/(\[[^\]]+\]|[^\/?#:]+)(?::([0-9]+))?(?:[\/?#]|$)/)
  if (!match) return ""
  var scheme = match[1].toLowerCase()
  var host = match[2].toLowerCase()
  var port = match[3] || (scheme === "https" ? "443" : (scheme === "http" ? "80" : ""))
  return scheme + "://" + host + (port ? ":" + port : "")
}
function sameOrigin(url, expected) {
  var actualOrigin = urlOrigin(url)
  return actualOrigin !== "" && actualOrigin === urlOrigin(expected)
}

// { a: 1, b: "x y", c: "" } -> "?a=1&b=x%20y"
function query(params) {
  var parts = []
  for (var key in params) {
    var value = params[key]
    if (value === undefined || value === null || value === "") continue
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)))
  }
  return parts.length ? "?" + parts.join("&") : ""
}

function commonParams() {
  return { outputFormat: "rapidJSON", coordOutputFormat: "EPSG:4326", version: "10.2.1.42" }
}

// Global stop ids are digits only ("204420"); anything else is an address,
// POI or street id that only stop_finder should ever hand back to us.
function isStopId(value) { return /^[0-9]{1,12}$/.test(String(value || "")) }

function stopFinderPath(text) {
  var p = commonParams()
  p.type_sf = "any"
  p.name_sf = String(text || "").trim()
  p.TfNSWSF = "true"
  return TP_PATH + "/stop_finder" + query(p)
}

// Departure board for one stop. `excludeModes` lists mode ids to drop
// server-side, which shrinks the payload and keeps buses off a station board.
function departuresPath(stopId, excludeModes, whenMs) {
  var p = commonParams()
  p.mode = "direct"
  p.type_dm = "stop"
  p.name_dm = String(stopId)
  p.depArrMacro = "dep"
  p.TfNSWDM = "true"
  var when = timeParams(whenMs)
  p.itdDate = when.date; p.itdTime = when.time
  var excluded = Array.isArray(excludeModes) ? excludeModes : []
  if (excluded.length) {
    p.excludedMeans = "checkbox"
    for (var i = 0; i < excluded.length; i++) {
      var mode = modeById(excluded[i])
      if (mode.motBit) p["exclMOT_" + mode.motBit] = "1"
    }
  }
  return TP_PATH + "/departure_mon" + query(p)
}

// Journey planner: origin is a stop id or "lon:lat" coordinate string,
// destination a stop id.
function tripPath(origin, destination, count, whenMs) {
  var p = commonParams()
  p.depArrMacro = "dep"
  var o = originSpec(origin)
  p.type_origin = o.type; p.name_origin = o.name
  p.type_destination = "stop"; p.name_destination = String(destination)
  p.calcNumberOfTrips = Math.max(1, Math.min(MAX_JOURNEYS, parseInt(count, 10) || 3))
  p.TfNSWTR = "true"
  var when = timeParams(whenMs)
  p.itdDate = when.date; p.itdTime = when.time
  return TP_PATH + "/trip" + query(p)
}

function originSpec(origin) {
  if (origin && typeof origin === "object" && isFinite(origin.lat) && isFinite(origin.lon)) {
    return { type: "coord", name: Number(origin.lon).toFixed(6) + ":" + Number(origin.lat).toFixed(6) + ":EPSG:4326" }
  }
  return { type: "stop", name: String(origin) }
}

// The API reads itdDate/itdTime as UTC (undocumented; confirmed on the
// TfNSW forum), so send UTC and let it convert.
function timeParams(whenMs) {
  var d = new Date(typeof whenMs === "number" && isFinite(whenMs) ? whenMs : Date.now())
  function two(n) { return (n < 10 ? "0" : "") + n }
  return {
    date: String(d.getUTCFullYear()) + two(d.getUTCMonth() + 1) + two(d.getUTCDate()),
    time: two(d.getUTCHours()) + two(d.getUTCMinutes())
  }
}

// ---------------------------------------------------------------- parsing

function parseResponse(status, body) {
  var text = String(body || "")
  if (text.length > MAX_RESPONSE_BYTES) return errorResult("protocol", "The Transport NSW response was too large.")
  if (status === 401) return errorResult("credential", "Transport NSW rejected the API key.")
  if (status === 403) {
    // 403 is both "bad key" and "over quota"; the body says which.
    if (/rate limit|quota/i.test(text)) return errorResult("ratelimit", "Transport NSW API quota exceeded. Backing off.")
    return errorResult("credential", "Transport NSW refused the API key (HTTP 403).")
  }
  if (status === 429) return errorResult("ratelimit", "Transport NSW is rate limiting requests. Backing off.")
  if (status === 0) return errorResult("network", "Could not reach the Transport NSW API.")
  var data = null
  try { data = JSON.parse(text) } catch (e) { data = null }
  if (status < 200 || status >= 300) {
    var message = data && data.ErrorDetails && data.ErrorDetails.message ? String(data.ErrorDetails.message) : ""
    return errorResult(status >= 500 ? "network" : "api", message || ("Transport NSW API error (HTTP " + status + ")."))
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return errorResult("protocol", "Unexpected response from Transport NSW.")
  var errors = systemErrors(data)
  if (errors.length) return errorResult("api", errors[0])
  return { ok: true, status: status, kind: "", error: "", data: data }
}

function systemErrors(data) {
  var out = []
  var messages = data && Array.isArray(data.systemMessages) ? data.systemMessages : []
  for (var i = 0; i < messages.length; i++) {
    var m = messages[i]
    if (!m || m.type !== "error") continue
    // -2000 "stop invalid" simply means no match; callers treat empty lists.
    if (m.code === -2000) continue
    out.push(String(m.text || ("Transport NSW error " + m.code)))
  }
  return out
}

function parseTime(value) {
  if (typeof value !== "string" || !value) return 0
  var ms = Date.parse(value)
  return isFinite(ms) ? ms : 0
}

function shortLine(transportation) {
  if (!transportation) return ""
  var short = String(transportation.disassembledName || "").trim()
  if (short && short.length <= 6) return short
  var number = String(transportation.number || "").trim()
  var match = number.match(/^([A-Z]{1,2}[0-9]{1,3}[A-Z]?|[0-9]{1,4}[A-Z]?)\b/)
  return match ? match[1] : (short || number.split(" ")[0] || "")
}

function firstSegment(name) { return String(name || "").split(",")[0].trim() }

function platformOf(location) {
  var props = location && location.properties ? location.properties : {}
  var name = String(props.platformName || "").trim()
  if (name) return name.replace(/^Platform\s+/i, "")
  var raw = String(props.platform || "").trim()
  // "SYD6" style codes carry the platform number after the station prefix.
  var match = raw.match(/([0-9]+[A-Z]?)$/)
  return match ? match[1] : raw
}

function parseInfos(infos) {
  var out = []
  var seen = {}
  var list = Array.isArray(infos) ? infos : []
  for (var i = 0; i < list.length && out.length < 8; i++) {
    var info = list[i]
    if (!info || typeof info !== "object") continue
    var id = String(info.id || "")
    var title = String(info.urlText || info.subtitle || "").trim()
    if (!title || (id && seen[id])) continue
    if (id) seen[id] = true
    out.push({ id: id || title, title: title, priority: String(info.priority || "normal"),
               type: String(info.type || ""), url: httpsOnly(info.url) })
  }
  return out
}

function httpsOnly(url) {
  var text = String(url || "").trim()
  return /^https:\/\/[^\s"'<>]+$/.test(text) ? text : ""
}

// stop_finder → [{ id, name, shortName, type, lat, lon, modes: [modeId], isStop }]
function parseLocations(data) {
  var list = data && Array.isArray(data.locations) ? data.locations : []
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_LOCATIONS; i++) {
    var loc = list[i]
    if (!loc || typeof loc !== "object" || !loc.name) continue
    var coord = Array.isArray(loc.coord) ? loc.coord : []
    var lat = parseFloat(coord[0]), lon = parseFloat(coord[1])
    var isStop = loc.type === "stop" && isStopId(loc.id)
    var modes = []
    var rawModes = Array.isArray(loc.modes) ? loc.modes : []
    for (var m = 0; m < rawModes.length; m++) {
      var mode = modeFor(rawModes[m])
      if (mode.cls && modes.indexOf(mode.id) === -1) modes.push(mode.id)
    }
    out.push({
      id: String(loc.id), name: String(loc.name), shortName: String(loc.disassembledName || firstSegment(loc.name)),
      type: String(loc.type || ""), lat: isFinite(lat) ? lat : null, lon: isFinite(lon) ? lon : null,
      modes: modes, isStop: isStop, isBest: loc.isBest === true
    })
  }
  return out
}

// departure_mon → [{ id, tripId, line, lineName, destination, platform, mode,
//   plannedMs, estimatedMs, realtime, cancelled, infos, stopName }]
function parseDepartures(data) {
  var events = data && Array.isArray(data.stopEvents) ? data.stopEvents : []
  var out = []
  for (var i = 0; i < events.length && out.length < MAX_STOP_EVENTS; i++) {
    var ev = events[i]
    if (!ev || typeof ev !== "object" || !ev.transportation) continue
    var planned = parseTime(ev.departureTimePlanned)
    var estimated = parseTime(ev.departureTimeEstimated)
    if (!planned && !estimated) continue
    var t = ev.transportation
    var props = t.properties || {}
    var tripId = String(props.RealtimeTripId || (ev.properties && ev.properties.RealtimeTripId) || props.gtfsTripId || "")
    var product = t.product || {}
    var line = shortLine(t)
    out.push({
      id: tripId || (line + "@" + (planned || estimated)),
      tripId: tripId,
      line: line,
      lineName: String(t.number || t.name || line),
      destination: String(t.destination && t.destination.name ? t.destination.name : ""),
      platform: platformOf(ev.location),
      mode: modeFor(product.class).id,
      plannedMs: planned || estimated,
      estimatedMs: estimated || 0,
      realtime: ev.isRealtimeControlled === true && estimated > 0,
      cancelled: ev.isCancelled === true,
      infos: parseInfos(ev.infos),
      stopName: firstSegment(ev.location && ev.location.name)
    })
  }
  out.sort(function(a, b) { return effectiveMs(a) - effectiveMs(b) })
  return out
}

function effectiveMs(dep) { return dep.estimatedMs || dep.plannedMs }

// trip → [{ departMs, arriveMs, durationSec, legs: [{ kind: walk|ride, mode,
//   line, destination, platform, from, to, departMs, arriveMs, durationSec,
//   distanceM, realtime, stops: [{ name, arriveMs, departMs }], infos }] }]
function parseJourneys(data) {
  var journeys = data && Array.isArray(data.journeys) ? data.journeys : []
  var out = []
  for (var i = 0; i < journeys.length && out.length < MAX_JOURNEYS; i++) {
    var legsRaw = journeys[i] && Array.isArray(journeys[i].legs) ? journeys[i].legs : []
    var legs = []
    for (var l = 0; l < legsRaw.length; l++) {
      var leg = parseLeg(legsRaw[l])
      if (leg) legs.push(leg)
    }
    if (!legs.length) continue
    var first = legs[0], last = legs[legs.length - 1]
    out.push({
      departMs: first.departMs, arriveMs: last.arriveMs,
      durationSec: Math.max(0, Math.round((last.arriveMs - first.departMs) / 1000)),
      legs: legs
    })
  }
  return out
}

function parseLeg(leg) {
  if (!leg || typeof leg !== "object") return null
  var t = leg.transportation || {}
  var product = t.product || {}
  var origin = leg.origin || {}
  var destination = leg.destination || {}
  var departMs = parseTime(origin.departureTimeEstimated) || parseTime(origin.departureTimePlanned)
  var arriveMs = parseTime(destination.arrivalTimeEstimated) || parseTime(destination.arrivalTimePlanned)
  if (!departMs || !arriveMs) return null
  var isWalk = parseInt(product.class, 10) === WALK_CLASS || (!t.number && !t.disassembledName)
  var stops = []
  var seq = Array.isArray(leg.stopSequence) ? leg.stopSequence : []
  for (var s = 0; s < seq.length && stops.length < 60; s++) {
    var stop = seq[s]
    if (!stop || !stop.name) continue
    stops.push({
      name: firstSegment(stop.disassembledName || stop.name),
      arriveMs: parseTime(stop.arrivalTimeEstimated) || parseTime(stop.arrivalTimePlanned),
      departMs: parseTime(stop.departureTimeEstimated) || parseTime(stop.departureTimePlanned)
    })
  }
  return {
    kind: isWalk ? "walk" : "ride",
    mode: isWalk ? "walk" : modeFor(product.class).id,
    line: isWalk ? "" : shortLine(t),
    destination: String(t.destination && t.destination.name ? t.destination.name : ""),
    platform: isWalk ? "" : platformOf(origin),
    from: firstSegment(origin.disassembledName || origin.name),
    to: firstSegment(destination.disassembledName || destination.name),
    departMs: departMs, arriveMs: arriveMs,
    durationSec: typeof leg.duration === "number" ? leg.duration : Math.round((arriveMs - departMs) / 1000),
    distanceM: typeof leg.distance === "number" ? leg.distance : 0,
    realtime: leg.isRealtimeControlled === true,
    stops: stops,
    infos: parseInfos(leg.infos)
  }
}

function connectionProbePath() { return stopFinderPath("Central Station") }
