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
var MAX_LOCATION_SCAN = 200
var MAX_LEGS = 50
var MAX_MODES_SCAN = 50
var MAX_SYSTEM_MESSAGES = 100
var MAX_INFOS = 8
var MAX_STOPS = 60

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

function clip(text, max) {
  var limit = Math.max(0, parseInt(max, 10) || 0)
  return String(text || "").slice(0, limit)
}

function typedClip(value, max) {
  return typeof value === "string" ? clip(value, max) : ""
}

function firstString(values) {
  var list = listValue(values)
  for (var i = 0; i < list.length; i++) if (typeof list[i] === "string" && list[i]) return list[i]
  return ""
}

// QML list values may lose native Array identity when crossing property-var
// boundaries, so parser budgets use a finite length rather than Array.isArray.
function listValue(value) {
  return value && typeof value !== "string" && isFinite(value.length) ? value : []
}

function isListValue(value) {
  return value && typeof value !== "string" && isFinite(value.length)
}

// Line colours from TfNSW wayfinding. Sydney Trains verified against each
// line's page on transportnsw.info (2026-09-02); metro, light rail and
// ferries from the published network maps. Anything else uses its mode colour.
var LINE_COLORS = {
  T1: "#F99D1C", T2: "#0098CD", T3: "#F37021", T4: "#005AA3", T5: "#C4258F",
  T6: "#7C3E21", T7: "#6F818E", T8: "#00954C", T9: "#D11F2F",
  M1: "#168388",
  L1: "#BE1622", L2: "#DD1E25", L3: "#781140", L4: "#2EBBB4",
  F1: "#00774B", F2: "#144734", F3: "#648C3C", F4: "#BFD730", F5: "#286142",
  F6: "#00AB51", F7: "#00B189", F8: "#55622B", F9: "#65B32E", F10: "#5AB031",
  B1: "#FFB81C"
}
// WCAG relative luminance of a "#RRGGBB" colour; used to pick a readable
// text colour on top of a line colour (T1 orange needs dark text, L3 plum
// needs light text).
function luminance(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length !== 6) return 0
  var out = [0.2126, 0.7152, 0.0722]
  var sum = 0
  for (var i = 0; i < 3; i++) {
    var c = parseInt(h.substr(i * 2, 2), 16) / 255
    c = c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    sum += out[i] * c
  }
  return sum
}
function contrastRatio(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}
// true when light text reads better than dark text on this colour.
function lightTextOn(hex) {
  return contrastRatio("#FFFFFF", hex) >= contrastRatio("#000000", hex)
}

function lineColor(line, modeId) {
  var key = String(line || "").trim().toUpperCase()
  if (LINE_COLORS[key]) return LINE_COLORS[key]
  return modeById(modeId).color
}

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
  return { outputFormat: "rapidJSON", coordOutputFormat: "EPSG:4326" }
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

function coordPath(lat, lon, radiusM) {
  var latitude = Number(lat), longitude = Number(lon)
  var radius = Math.max(1, Math.min(5000, Math.round(Number(radiusM) || 800)))
  var p = commonParams()
  p.coord = longitude.toFixed(6) + ":" + latitude.toFixed(6) + ":EPSG:4326"
  p.inclFilter = 1
  p.type_1 = "BUS_POINT"
  p.radius_1 = radius
  p.PoisOnMapMacro = "true"
  p.version = "10.2.1.42"
  return TP_PATH + "/coord" + query(p)
}

// Departure board for one stop. `excludeModes` lists mode ids to drop
// server-side, which shrinks the payload and keeps buses off a station board.
// No itdDate/itdTime: the API reads them as Sydney local time (not UTC, as
// the forum suggests) and this machine's clock may be in any zone, so "now"
// is left to the server.
function departuresPath(stopId, excludeModes) {
  var p = commonParams()
  p.mode = "direct"
  p.type_dm = "stop"
  p.name_dm = String(stopId)
  p.depArrMacro = "dep"
  p.TfNSWDM = "true"
  var excluded = listValue(excludeModes)
  if (excluded.length) {
    p.excludedMeans = "checkbox"
    for (var i = 0; i < excluded.length; i++) {
      var mode = modeById(excluded[i])
      if (mode.motBit) p["exclMOT_" + mode.motBit] = "1"
    }
  }
  return TP_PATH + "/departure_mon" + query(p)
}

// Journey planner: either endpoint is a stop id or { lat, lon }.
function tripPath(origin, destination, count) {
  var p = commonParams()
  p.depArrMacro = "dep"
  var o = originSpec(origin)
  p.type_origin = o.type; p.name_origin = o.name
  var d = endpointSpec(destination)
  p.type_destination = d.type; p.name_destination = d.name
  p.calcNumberOfTrips = Math.max(1, Math.min(MAX_JOURNEYS, parseInt(count, 10) || 3))
  p.TfNSWTR = "true"
  return TP_PATH + "/trip" + query(p)
}

function vehiclePosPath(mode) {
  switch (String(mode || "")) {
  case "train": return "/v2/gtfs/vehiclepos/sydneytrains"
  case "metro": return "/v2/gtfs/vehiclepos/metro"
  case "bus": return "/v1/gtfs/vehiclepos/buses"
  default: return ""
  }
}

function originSpec(origin) {
  return endpointSpec(origin)
}

function endpointSpec(endpoint) {
  if (endpoint && typeof endpoint === "object" && isFinite(endpoint.lat) && isFinite(endpoint.lon))
    return { type: "coord", name: Number(endpoint.lon).toFixed(6) + ":" + Number(endpoint.lat).toFixed(6) + ":EPSG:4326" }
  return { type: "stop", name: String(endpoint) }
}

// ---------------------------------------------------------------- parsing

function parseResponse(status, body) {
  var text = String(body || "")
  if (text.length >= MAX_RESPONSE_BYTES) return errorResult("protocol", "The Transport NSW response was too large.")
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
    var message = data && data.ErrorDetails && data.ErrorDetails.message ? clip(data.ErrorDetails.message, 120) : ""
    return errorResult(status >= 500 ? "network" : "api", message || ("Transport NSW API error (HTTP " + status + ")."))
  }
  if (!data || typeof data !== "object" || isListValue(data)) return errorResult("protocol", "Unexpected response from Transport NSW.")
  var errors = systemErrors(data)
  if (errors.length && !hasPayload(data)) return errorResult("api", errors[0])
  return { ok: true, status: status, kind: "", error: "", data: data }
}

// EFA reports advisory conditions as "error" system messages next to a
// perfectly good payload (e.g. code -8011 with empty text on stop_finder), so
// a system error only fails the call when nothing usable came back.
function systemErrors(data) {
  var out = []
  var messages = data ? listValue(data.systemMessages) : []
  for (var i = 0; i < messages.length && i < MAX_SYSTEM_MESSAGES; i++) {
    var m = messages[i]
    if (!m || m.type !== "error") continue
    // -2000 "stop invalid" simply means no match; callers treat empty lists.
    if (m.code === -2000) continue
    out.push(clip(m.text || ("Transport NSW error " + m.code), 120))
  }
  return out
}

function hasPayload(data) {
  if (!data || typeof data !== "object") return false
  var keys = ["locations", "stopEvents", "journeys"]
  for (var i = 0; i < keys.length; i++) if (isListValue(data[keys[i]]) && data[keys[i]].length) return true
  return false
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
  return clip(match ? match[1] : (short || number.split(" ")[0] || ""), 120)
}

function firstSegment(name) { return clip(String(name || "").split(",")[0].trim(), 120) }

function platformOf(location) {
  var props = location && location.properties ? location.properties : {}
  var fullName = String(props.platformName || "").trim()
  var name = fullName.replace(/^Platform\s+/i, "")
  if (name && /^[A-Za-z0-9]{1,4}$/.test(name)) return name
  // Light rail and wharves echo the stop name as the platform name ("Surry
  // Hills Light Rail" with code "LR2"); there is no platform to show then.
  if (fullName) return ""
  var raw = String(props.platform || "").trim()
  // "SYD6" style codes carry the platform number after the station prefix.
  var match = raw.match(/([0-9]+[A-Z]?)$/)
  if (match && raw.length <= 12) return match[1]
  // Light rail and some wharves echo the stop name here; that is not a platform.
  return /^[A-Z0-9]{1,4}$/.test(raw) ? raw : ""
}

function parseInfos(infos) {
  var out = []
  var seen = {}
  var list = listValue(infos)
  for (var i = 0; i < list.length && out.length < MAX_INFOS; i++) {
    var info = list[i]
    if (!info || typeof info !== "object") continue
    var id = typedClip(info.id, 64)
    var title = clip(String(info.urlText || info.subtitle || "").trim(), 120)
    if (!title || (id && seen[id])) continue
    if (id) seen[id] = true
    var props = info.properties && typeof info.properties === "object" ? info.properties : {}
    out.push({ id: id || clip(title, 64), title: title, priority: typedClip(info.priority, 32) || "normal",
               type: typedClip(info.type, 32), url: httpsOnly(info.url),
               text: infoText(props.speechText || props.smsText || info.content || "") })
  }
  return out
}

// Alert body as plain text: TfNSW's speechText is already prose; content is
// HTML, so tags go and whitespace collapses. Bounded.
function infoText(value) {
  var text = String(value || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, " ")
  text = text.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
  text = text.replace(/[ \t]+/g, " ").replace(/\s*\n\s*/g, "\n").trim()
  return clip(text, 600)
}

function httpsOnly(url) {
  var text = String(url || "").trim()
  if (!/^https:\/\/[^\s"'<>]+$/.test(text)) return ""
  var match = text.match(/^https:\/\/([^\/?#]+)(\/[^?#]*)?(?:[?#].*)?$/i)
  if (!match || /[@:]/.test(match[1])) return ""
  var host = match[1].toLowerCase()
  if (host === "transportnsw.info" || host === "www.transportnsw.info"
      || host === "opendata.transport.nsw.gov.au" || host === "api.transport.nsw.gov.au") return text
  if (host === "github.com" && String(match[2] || "/").indexOf("/vichong/omarchy-tfnsw-departures") === 0) return text
  return ""
}

// stop_finder → [{ id, name, shortName, type, lat, lon, modes: [modeId], isStop }]
function parseLocations(data) {
  var list = data ? listValue(data.locations) : []
  var out = []
  for (var i = 0; i < list.length && i < MAX_LOCATION_SCAN && out.length < MAX_LOCATIONS; i++) {
    var loc = list[i]
    if (!loc || typeof loc !== "object" || !loc.name) continue
    var coord = listValue(loc.coord)
    var lat = parseFloat(coord[0]), lon = parseFloat(coord[1])
    var isStop = loc.type === "stop" && isStopId(loc.id)
    var modes = []
    var rawModes = listValue(loc.modes)
    for (var m = 0; m < rawModes.length && m < MAX_MODES_SCAN; m++) {
      var mode = modeFor(rawModes[m])
      if (mode.cls && modes.indexOf(mode.id) === -1) modes.push(mode.id)
    }
    out.push({
      id: typedClip(loc.id, 64), name: clip(loc.name, 120), shortName: clip(loc.disassembledName || firstSegment(loc.name), 120),
      type: typedClip(loc.type, 32), lat: isFinite(lat) ? lat : null, lon: isFinite(lon) ? lon : null,
      modes: modes, isStop: isStop, isBest: loc.isBest === true
    })
  }
  return out
}

function nearbyName(value) {
  var parts = String(value || "").split(",")
  var first = parts.length ? parts[0].trim() : ""
  var suburb = parts.length > 1 ? parts[parts.length - 1].trim() : ""
  return clip(first + (suburb && suburb !== first ? ", " + suburb : ""), 120)
}

// coord → nearby public-transport stops. Platform records are folded into
// their parent stop and the nearest platform supplies the walking distance.
// The coord lookup does not say what serves a platform; the name does.
function nearbyModes(name) {
  var n = String(name || "")
  if (/light rail/i.test(n)) return ["lightrail"]
  if (/\bwharf\b/i.test(n)) return ["ferry"]
  // The coord lookup asks for bus points; "Wynyard Station, Stand B" is a bus
  // stand, not a train. Stations come from the bundled list with real modes.
  return ["bus"]
}

function parseNearby(data) {
  var list = data ? listValue(data.locations) : []
  var byId = {}
  for (var i = 0; i < list.length && i < MAX_LOCATION_SCAN; i++) {
    var loc = list[i]
    if (!loc || typeof loc !== "object") continue
    var parent = loc.parent && typeof loc.parent === "object" ? loc.parent : {}
    var id = typedClip(typeof parent.id === "string" ? parent.id : loc.id, 64)
    if (!isStopId(id)) continue
    var metres = Number(loc.properties && loc.properties.distance)
    if (!isFinite(metres) || metres < 0) continue
    var name = nearbyName(parent.name || loc.name)
    if (!name) continue
    if (!byId[id] || metres < byId[id].metres) byId[id] = {
      id: id,
      name: name,
      metres: Math.round(metres),
      walkMinutes: Math.max(0, Math.round(metres / 80)),
      modes: nearbyModes(parent.name || loc.name)
    }
  }
  var out = []
  for (var key in byId) out.push(byId[key])
  out.sort(function(a, b) { return a.metres - b.metres || a.name.localeCompare(b.name) || a.id.localeCompare(b.id) })
  return out.slice(0, 12)
}

// departure_mon → [{ id, tripId, line, lineName, destination, platform, mode,
//   plannedMs, estimatedMs, realtime, cancelled, infos, stopName }]
function parseDepartures(data) {
  var events = data ? listValue(data.stopEvents) : []
  var out = []
  for (var i = 0; i < events.length && out.length < MAX_STOP_EVENTS; i++) {
    var ev = events[i]
    if (!ev || typeof ev !== "object" || !ev.transportation) continue
    var planned = parseTime(ev.departureTimePlanned)
    var estimated = parseTime(ev.departureTimeEstimated)
    if (!planned && !estimated) continue
    var t = ev.transportation
    var props = t.properties || {}
    var rawTripId = firstString([props.RealtimeTripId,
      ev.properties && ev.properties.RealtimeTripId, props.gtfsTripId])
    var tripId = typedClip(rawTripId, 120)
    var product = t.product || {}
    var line = shortLine(t)
    out.push({
      id: clip(tripId || (line + "@" + (planned || estimated)), 64),
      tripId: tripId,
      line: line,
      lineName: clip(t.number || t.name || line, 120),
      destination: clip(t.destination && t.destination.name ? t.destination.name : "", 120),
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
//   line, tripId, destination, platform, from, to, departMs, arriveMs, durationSec,
//   distanceM, realtime, stops: [{ name, arriveMs, departMs }], infos }] }]
function parseJourneys(data) {
  var journeys = data ? listValue(data.journeys) : []
  var out = []
  for (var i = 0; i < journeys.length && out.length < MAX_JOURNEYS; i++) {
    var legsRaw = journeys[i] ? listValue(journeys[i].legs) : []
    var legs = []
    for (var l = 0; l < legsRaw.length && l < MAX_LEGS; l++) {
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
  var properties = t.properties || {}
  var departMs = parseTime(origin.departureTimeEstimated) || parseTime(origin.departureTimePlanned)
  var arriveMs = parseTime(destination.arrivalTimeEstimated) || parseTime(destination.arrivalTimePlanned)
  if (!departMs || !arriveMs) return null
  var isWalk = parseInt(product.class, 10) === WALK_CLASS || (!t.number && !t.disassembledName)
  var stops = []
  var seq = listValue(leg.stopSequence)
  for (var s = 0; s < seq.length && stops.length < MAX_STOPS; s++) {
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
    tripId: isWalk ? "" : typedClip(firstString([properties.RealtimeTripId, properties.AVMSTripID]), 120),
    destination: clip(t.destination && t.destination.name ? t.destination.name : "", 120),
    platform: isWalk ? "" : platformOf(origin),
    fromId: clip(origin.parent && origin.parent.id ? origin.parent.id : (origin.id || ""), 40),
    from: firstSegment(origin.disassembledName || origin.name),
    toId: clip(destination.parent && destination.parent.id ? destination.parent.id : (destination.id || ""), 40),
    to: firstSegment(destination.disassembledName || destination.name),
    departMs: departMs, arriveMs: arriveMs,
    durationSec: typeof leg.duration === "number" ? leg.duration : Math.round((arriveMs - departMs) / 1000),
    distanceM: typeof leg.distance === "number" ? leg.distance : 0,
    realtime: leg.isRealtimeControlled === true,
    stops: stops,
    infos: parseInfos(leg.infos)
  }
}

// Cache data has already crossed a trust boundary. Rebuild the exact parsed
// departure/journey shapes with bounded strings and arrays before reuse.
function normalizeCachedInfos(value) {
  if (!isListValue(value)) return null
  var out = []
  for (var i = 0; i < value.length && i < MAX_INFOS; i++) {
    var info = value[i]
    if (!info || typeof info !== "object" || isListValue(info)) return null
    var title = typedClip(info.title, 120)
    if (!title) return null
    out.push({ id: typedClip(info.id, 64) || clip(title, 64), title: title,
      priority: typedClip(info.priority, 32) || "normal", type: typedClip(info.type, 32),
      url: httpsOnly(info.url), text: typedClip(info.text, 600) })
  }
  return out
}

function finiteCachedNumber(value) {
  return typeof value === "number" && isFinite(value) ? value : null
}

function normalizeCachedLeg(value) {
  if (!value || typeof value !== "object" || isListValue(value)
      || (value.kind !== "ride" && value.kind !== "walk")) return null
  var departMs = finiteCachedNumber(value.departMs), arriveMs = finiteCachedNumber(value.arriveMs)
  var durationSec = finiteCachedNumber(value.durationSec), distanceM = finiteCachedNumber(value.distanceM)
  if (departMs === null || arriveMs === null || arriveMs < departMs || durationSec === null || distanceM === null) return null
  var infos = normalizeCachedInfos(value.infos)
  if (infos === null || !isListValue(value.stops)) return null
  var stops = []
  for (var i = 0; i < value.stops.length && i < MAX_STOPS; i++) {
    var stop = value.stops[i]
    if (!stop || typeof stop !== "object" || isListValue(stop) || typeof stop.name !== "string") return null
    var arrive = finiteCachedNumber(stop.arriveMs), depart = finiteCachedNumber(stop.departMs)
    if (arrive === null || depart === null) return null
    stops.push({ name: typedClip(stop.name, 120), arriveMs: arrive, departMs: depart })
  }
  var walk = value.kind === "walk"
  var mode = walk ? "walk" : typedClip(value.mode, 32)
  if (!walk && !isValidModeId(mode)) return null
  return { kind: value.kind, mode: mode, line: walk ? "" : typedClip(value.line, 120),
    tripId: walk ? "" : typedClip(value.tripId, 120), destination: typedClip(value.destination, 120),
    platform: walk ? "" : typedClip(value.platform, 12), fromId: typedClip(value.fromId, 64),
    from: typedClip(value.from, 120), toId: typedClip(value.toId, 64), to: typedClip(value.to, 120),
    departMs: departMs, arriveMs: arriveMs, durationSec: Math.max(0, durationSec),
    distanceM: Math.max(0, distanceM), realtime: value.realtime === true, stops: stops, infos: infos }
}

function normalizeCachedDepartures(value) {
  if (!isListValue(value) || value.length > MAX_STOP_EVENTS) return []
  var out = []
  for (var i = 0; i < value.length && i < MAX_STOP_EVENTS; i++) {
    var item = value[i]
    if (!item || typeof item !== "object" || isListValue(item)) continue
    if (isListValue(item.legs)) {
      if (item.legs.length > MAX_LEGS) continue
      var legs = [], valid = true
      for (var l = 0; l < item.legs.length; l++) {
        var leg = normalizeCachedLeg(item.legs[l])
        if (!leg) { valid = false; break }
        legs.push(leg)
      }
      var departMs = finiteCachedNumber(item.departMs), arriveMs = finiteCachedNumber(item.arriveMs)
      var durationSec = finiteCachedNumber(item.durationSec)
      if (valid && legs.length && departMs !== null && arriveMs !== null && arriveMs >= departMs && durationSec !== null)
        out.push({ departMs: departMs, arriveMs: arriveMs, durationSec: Math.max(0, durationSec), legs: legs })
      continue
    }
    var plannedMs = finiteCachedNumber(item.plannedMs), estimatedMs = finiteCachedNumber(item.estimatedMs)
    var infos = normalizeCachedInfos(item.infos)
    var mode = typedClip(item.mode, 32)
    if (((plannedMs === null || plannedMs <= 0) && (estimatedMs === null || estimatedMs <= 0))
        || infos === null || !isValidModeId(mode)) continue
    var tripId = typedClip(item.tripId, 120)
    out.push({ id: typedClip(item.id, 64) || clip(tripId, 64), tripId: tripId, line: typedClip(item.line, 120),
      lineName: typedClip(item.lineName, 120), destination: typedClip(item.destination, 120),
      platform: typedClip(item.platform, 12), mode: mode, plannedMs: plannedMs || 0,
      estimatedMs: estimatedMs || 0, realtime: item.realtime === true, cancelled: item.cancelled === true,
      infos: infos, stopName: typedClip(item.stopName, 120) })
  }
  return out
}

function connectionProbePath() { return stopFinderPath("Central Station") }
