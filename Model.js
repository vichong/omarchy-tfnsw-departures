.pragma library
.import "Api.js" as Api

// Pure view logic: which departures a place cares about, when to leave, what
// the pill and rows say. No I/O, no QML types.

var BRAND_ICON = "󰔬"            // md-train, notification fallback glyph
var MODE_GLYPHS = {
  train: "󰔬", metro: "󰚬", lightrail: "󰣄", bus: "󰃧", coach: "󰃧", ferry: "󰈓", schoolbus: "󰃧", walk: "󰖃", other: "󰴼"
}
var MAX_ROWS = 8
// Departures you can no longer make are hidden once they are this far past
// the leave-by moment, so a train rolling out still shows for a moment.
var MISSED_GRACE_MS = 45 * 1000
var HORIZON_MS = 3 * 60 * 60 * 1000

function glyphFor(modeId) { return MODE_GLYPHS[modeId] || MODE_GLYPHS.other }

function normalizeLine(text) { return String(text || "").trim().toUpperCase() }

function displayStopName(name) {
  return String(name || "").replace(/\s+(?:Station|Light Rail|Wharf\s+[0-9]+)$/i, "").trim()
}

function listCopy(value) {
  var out = []
  var n = value && typeof value !== "string" && isFinite(value.length) ? Number(value.length) : 0
  for (var i = 0; i < n; i++) out.push(String(value[i]))
  return out
}

function listValue(value) {
  return value && typeof value !== "string" && isFinite(value.length) ? value : []
}

function matchStops(list, text, limit) {
  var query = String(text || "").trim().toLowerCase()
  if (!query || !list || typeof list === "string" || !isFinite(list.length)) return []
  var maximum = isFinite(limit) ? Math.max(0, Math.floor(Number(limit))) : 8
  var matches = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item || typeof item !== "object" || typeof item.id !== "string" || !Api.isStopId(item.id)
        || typeof item.name !== "string" || item.name.trim() === "") continue
    var name = item.name.trim()
    var lower = name.toLowerCase()
    var rank = -1
    if (lower.indexOf(query) === 0) rank = 0
    else {
      var words = lower.split(/[^a-z0-9]+/)
      for (var w = 0; w < words.length; w++) if (words[w].indexOf(query) === 0) {
        rank = 1
        break
      }
      if (rank < 0 && lower.indexOf(query) !== -1) rank = 2
    }
    if (rank < 0) continue
    matches.push({ item: item, name: name, rank: rank })
  }
  matches.sort(function(a, b) {
    if (a.rank !== b.rank) return a.rank - b.rank
    var byName = a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    return byName || a.name.localeCompare(b.name) || a.item.id.localeCompare(b.item.id)
  })
  var out = []
  for (var m = 0; m < matches.length && out.length < maximum; m++) {
    var stop = matches[m].item
    out.push({
      id: stop.id,
      name: matches[m].name,
      shortName: displayStopName(matches[m].name),
      isStop: true,
      // Arrays that crossed a QML `property var` may not retain native-array identity.
      modes: listCopy(stop.modes),
      type: "stop",
      lat: typeof stop.lat === "number" && isFinite(stop.lat) ? stop.lat : null,
      lon: typeof stop.lon === "number" && isFinite(stop.lon) ? stop.lon : null
    })
  }
  return out
}

// Nearby bundled stops for an address pick. Distance is the great-circle
// distance so the result is deterministic without a map or routing service.
function nearestStops(list, lat, lon, limit, maxMetres) {
  if (!list || typeof list === "string" || !isFinite(list.length)
      || typeof lat !== "number" || typeof lon !== "number"
      || !isFinite(lat) || !isFinite(lon)) return []
  var maximum = isFinite(limit) ? Math.max(0, Math.floor(Number(limit))) : 3
  var radius = isFinite(maxMetres) ? Math.max(0, Number(maxMetres)) : 1500
  var earth = 6371000
  var originLat = Number(lat) * Math.PI / 180
  var originLon = Number(lon) * Math.PI / 180
  var ranked = []
  for (var i = 0; i < list.length; i++) {
    var stop = list[i]
    if (!stop || typeof stop !== "object" || typeof stop.id !== "string" || !Api.isStopId(stop.id)
        || typeof stop.name !== "string" || typeof stop.lat !== "number" || typeof stop.lon !== "number"
        || !isFinite(stop.lat) || !isFinite(stop.lon)) continue
    var stopLat = Number(stop.lat) * Math.PI / 180
    var stopLon = Number(stop.lon) * Math.PI / 180
    var dLat = stopLat - originLat
    var dLon = stopLon - originLon
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
      + Math.cos(originLat) * Math.cos(stopLat) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
    var metres = earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)))
    if (metres > radius) continue
    ranked.push({ stop: stop, metres: metres })
  }
  ranked.sort(function(a, b) {
    return a.metres - b.metres || a.stop.name.localeCompare(b.stop.name) || a.stop.id.localeCompare(b.stop.id)
  })
  var out = []
  for (var r = 0; r < ranked.length && out.length < maximum; r++) {
    var item = ranked[r].stop
    out.push({
      id: item.id,
      name: item.name,
      shortName: displayStopName(item.name),
      isStop: true,
      modes: listCopy(item.modes),
      type: "stop",
      lat: Number(item.lat),
      lon: Number(item.lon),
      distanceMetres: Math.round(ranked[r].metres),
      walkMinutes: walkEstimate({ lat: lat, lon: lon }, item)
    })
  }
  return out
}

function mergeNearby(bundled, api) {
  var out = [], positions = {}
  function add(item, bundledWins) {
    if (!item || typeof item !== "object" || !Api.isStopId(item.id)) return
    var rawMetres = item.metres !== undefined && item.metres !== null ? item.metres : item.distanceMetres
    var metres = Number(rawMetres)
    if (!isFinite(metres) || metres < 0) return
    var normalized = {
      id: String(item.id),
      name: String(item.name || item.shortName || "").trim(),
      shortName: String(item.shortName || displayStopName(item.name || "")),
      isStop: true,
      modes: listCopy(item.modes),
      type: "stop",
      lat: typeof item.lat === "number" && isFinite(item.lat) ? item.lat : null,
      lon: typeof item.lon === "number" && isFinite(item.lon) ? item.lon : null,
      metres: Math.round(metres),
      distanceMetres: Math.round(metres),
      walkMinutes: Math.max(0, Math.round(metres / 80))
    }
    if (!normalized.name) return
    if (positions[normalized.id] !== undefined) {
      if (bundledWins) out[positions[normalized.id]] = normalized
      return
    }
    positions[normalized.id] = out.length
    out.push(normalized)
  }
  var local = listValue(bundled)
  var remote = listValue(api)
  for (var i = 0; i < local.length; i++) add(local[i], true)
  for (var r = 0; r < remote.length; r++) add(remote[r], false)
  function byDistance(a, b) { return a.metres - b.metres || a.name.localeCompare(b.name) || a.id.localeCompare(b.id) }
  out.sort(byDistance)
  // Cap at 24 (a CBD address has dozens of bus stops), but never let a crowd of nearer bus stops push a walkable
  // station out: the nearest stop of each rail or ferry mode is kept.
  var kept = featureNearby(out, "", 15).slice(0, 24)
  kept.sort(byDistance)
  return kept
}

// Saved origin and destination stops become a compact destination chooser.
// The first place mentioning a stop supplies its contextual label.
function destinationOptions(places) {
  var list = listValue(places)
  var seen = {}
  var out = []
  function add(id, name, place) {
    var stopId = String(id || "")
    var stopName = String(name || "").trim()
    if (!Api.isStopId(stopId) || !stopName || seen[stopId]) return
    seen[stopId] = true
    out.push({
      id: stopId,
      name: stopName,
      shortName: displayStopName(stopName),
      isStop: true,
      modes: [],
      type: "stop",
      label: stopName + " · " + String(place.name || "Trip")
    })
  }
  for (var i = 0; i < list.length; i++) {
    var place = list[i]
    if (!place || typeof place !== "object") continue
    add(place.stopId, place.stopName, place)
    add(place.destStopId, place.destStopName, place)
  }
  return out
}

function tempPlaceFrom(location, firstStop, destStop, walkMinutes, destinationLocation) {
  if (!location || !firstStop || !destStop) return null
  var name = String(location.name || location.shortName || "New trip").split(",")[0].trim() || "New trip"
  var place = {
    id: "temp",
    name: name,
    stopId: String(firstStop.id || ""),
    stopName: String(firstStop.name || firstStop.shortName || ""),
    destStopId: String(destStop.id || ""),
    destStopName: String(destStop.name || destStop.shortName || ""),
    walkMinutes: Math.max(0, Math.round(Number(walkMinutes) || 0)),
    walkEstimated: !!(location && !location.isStop),
    destWalkMinutes: 0,
    destWalkEstimated: false,
    lines: [],
    modes: []
  }
  if (!location.isStop) {
    place.address = String(location.name || location.shortName || "").trim()
    if (isFinite(location.lat) && isFinite(location.lon)) {
      place.lat = Number(location.lat)
      place.lon = Number(location.lon)
    }
  }
  if (destinationLocation && !destinationLocation.isStop) {
    place.destAddress = String(destinationLocation.name || destinationLocation.shortName || "").trim()
    if (isFinite(destinationLocation.lat) && isFinite(destinationLocation.lon)) {
      place.destLat = Number(destinationLocation.lat)
      place.destLon = Number(destinationLocation.lon)
    }
    place.destWalkMinutes = Math.max(0, Math.round(Number(destStop.walkMinutes) || 0))
    place.destWalkEstimated = true
  }
  return place
}

// Straight-line walking estimate shared by either address end.
function walkEstimate(fromLatLon, stop) {
  if (!fromLatLon || !stop || typeof fromLatLon.lat !== "number" || typeof fromLatLon.lon !== "number"
      || typeof stop.lat !== "number" || typeof stop.lon !== "number"
      || !isFinite(fromLatLon.lat) || !isFinite(fromLatLon.lon)
      || !isFinite(stop.lat) || !isFinite(stop.lon)) return 0
  var earth = 6371000
  var fromLat = Number(fromLatLon.lat) * Math.PI / 180
  var fromLon = Number(fromLatLon.lon) * Math.PI / 180
  var stopLat = Number(stop.lat) * Math.PI / 180
  var stopLon = Number(stop.lon) * Math.PI / 180
  var dLat = stopLat - fromLat
  var dLon = stopLon - fromLon
  var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
    + Math.cos(fromLat) * Math.cos(stopLat) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  var metres = earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)))
  return Math.max(0, Math.round(metres / 80))
}

function boardStopName(name) {
  // Addresses come as "1 Bligh St, Sydney": the board shows the first segment.
  return String(name || "").split(",")[0]
    .replace(/\s+(Station|Wharf|Light Rail|Interchange)\b.*$/i, "")
    .replace(/\bStreet\b/g, "St")
    .trim()
}

// A bounded stop sequence for the mini indicator board. Parsed stops are
// objects, but accepting strings keeps the helper useful and easy to test.
function stopListText(stops, max) {
  var list = listValue(stops)
  var limit = isFinite(max) ? Math.max(1, Math.floor(Number(max))) : 6
  var names = []
  for (var i = 0; i < list.length && names.length < limit; i++) {
    var item = list[i]
    var name = boardStopName(item && typeof item === "object" ? item.name : item)
    if (name) names.push(name)
  }
  var text = names.join(" · ")
  if (list.length > limit)
    text += (text ? " · " : "") + "… +" + (list.length - limit)
  return text
}

// Does this departure belong on the board for this place?
function matchesPlace(dep, place) {
  if (!dep || !place) return false
  if (place.modes && place.modes.length && place.modes.indexOf(dep.mode) === -1) return false
  if (place.lines && place.lines.length) {
    var line = normalizeLine(dep.line)
    var hit = false
    for (var i = 0; i < place.lines.length; i++) if (normalizeLine(place.lines[i]) === line) { hit = true; break }
    if (!hit) return false
  }
  if (place.destination) {
    var needle = String(place.destination).trim().toLowerCase()
    if (needle && String(dep.destination || "").toLowerCase().indexOf(needle) === -1) return false
  }
  return true
}

function leaveInMs(dep, place, nowMs) {
  var walk = place && isFinite(place.walkMinutes) ? Number(place.walkMinutes) : 0
  return Api.effectiveMs(dep) - nowMs - walk * 60 * 1000
}

function delaySec(dep) {
  if (!dep.realtime || !dep.estimatedMs) return 0
  return Math.round((dep.estimatedMs - dep.plannedMs) / 1000)
}

// The departures worth showing, in order: still catchable, within the
// horizon, matching the place. Cancelled ones stay (struck through) so a
// gap is explained rather than silent.
function boardFor(departures, place, nowMs) {
  var list = listValue(departures)
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_ROWS; i++) {
    var dep = list[i]
    if (!matchesPlace(dep, place)) continue
    var leave = leaveInMs(dep, place, nowMs)
    if (leave < -MISSED_GRACE_MS) continue
    if (Api.effectiveMs(dep) - nowMs > HORIZON_MS) continue
    out.push(dep)
  }
  return out
}

// Journeys (origin stop → destination stop) as board entries: the same shape
// as a departure so every filter, pill and notification path is shared, plus
// arrival, travel time and changes. The line/mode/platform come from the
// first ride; a journey with no ride (walk only) is skipped.
function boardFromJourneys(journeys, place, nowMs) {
  // Length-based: arrays that crossed a QML `property var` may lose native-array identity.
  var list = journeys && isFinite(journeys.length) ? journeys : []
  var entries = []
  for (var i = 0; i < list.length; i++) {
    var journey = list[i]
    var legs = journey && journey.legs && isFinite(journey.legs.length) ? journey.legs : []
    var rides = []
    for (var l = 0; l < legs.length; l++) if (legs[l].kind === "ride") rides.push(legs[l])
    if (!rides.length) continue
    var first = rides[0]
    var infos = []
    var seen = {}
    for (var r = 0; r < legs.length; r++) {
      var legInfos = legs[r].infos || []
      for (var a = 0; a < legInfos.length; a++) {
        if (seen[legInfos[a].id]) continue
        seen[legInfos[a].id] = true
        infos.push(legInfos[a])
      }
    }
    var summary = []
    for (var j = 0; j < legs.length; j++) {
      summary.push(legs[j].kind === "walk" ? "walk " + Math.max(1, Math.round(legs[j].durationSec / 60)) + "′" : legs[j].line)
    }
    var realtime = rides.every(function(ride) { return ride.realtime })
    entries.push({
      id: first.line + "@" + journey.departMs + "→" + journey.arriveMs,
      tripId: String(first.tripId || ""),
      line: first.line,
      lineName: first.line,
      destination: first.destination,
      headsign: first.destination,
      platform: first.platform,
      mode: first.mode,
      plannedMs: journey.departMs,
      estimatedMs: realtime ? journey.departMs : 0,
      realtime: realtime,
      cancelled: false,
      infos: infos,
      stopName: first.from,
      arriveMs: journey.arriveMs,
      travelSec: Math.max(0, Math.round((journey.arriveMs - journey.departMs) / 1000)),
      changes: Math.max(0, rides.length - 1),
      legsSummary: summary.join(" → "),
      legs: legs
    })
  }
  return boardFor(entries, place, nowMs)
}

// TripView keeps a slower option visible but greys it when a service leaving
// later reaches the destination no later. Cancellations do not participate in
// the comparison and plain departures have no arrival, so remain untouched.
function markDominated(board) {
  var list = listValue(board)
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || !entry.arriveMs || entry.cancelled) {
      if (entry && entry.arriveMs) entry.dominated = false
      continue
    }
    entry.dominated = false
    var depart = Api.effectiveMs(entry)
    for (var j = 0; j < list.length; j++) {
      var later = list[j]
      if (!later || later.cancelled || !later.arriveMs) continue
      if (Api.effectiveMs(later) > depart && later.arriveMs <= entry.arriveMs) {
        entry.dominated = true
        break
      }
    }
  }
  return list
}

// Project parsed trip legs for the expandable departure row. When the API
// omits a walking leg between two rides, make the transfer time explicit.
function legRows(entry, occupancy, walkMinutes) {
  var shownAlerts = {}
  // Length-based: arrays that crossed a QML `property var` may lose native-array identity.
  var legs = entry && entry.legs && isFinite(entry.legs.length) ? entry.legs : []
  var rows = []
  var leadingWalk = Math.max(0, Math.round(Number(walkMinutes) || 0))
  if (leadingWalk > 0 && legs.length > 0 && legs[0] && legs[0].kind !== "walk") {
    var firstDepartMs = Number(legs[0].departMs || 0)
    rows.push({
      kind: "walk",
      mode: "walk",
      tripId: "",
      crowding: "",
      line: "",
      headsign: "",
      from: "",
      to: String(legs[0].from || ""),
      departText: firstDepartMs ? clockText(firstDepartMs - leadingWalk * 60000) : "",
      arriveText: firstDepartMs ? clockText(firstDepartMs) : "",
      platform: "",
      realtime: false,
      alertTitle: "",
      disruption: false,
      stopsText: "",
      minutes: leadingWalk
    })
  }
  for (var i = 0; i < legs.length; i++) {
    var leg = legs[i]
    if (!leg || (leg.kind !== "ride" && leg.kind !== "walk")) continue

    if (i > 0 && leg.kind === "ride" && legs[i - 1] && legs[i - 1].kind === "ride") {
      var gapMs = Number(leg.departMs || 0) - Number(legs[i - 1].arriveMs || 0)
      if (gapMs >= 60 * 1000) rows.push({
        kind: "change",
        mode: "",
        tripId: "",
        crowding: "",
        line: "",
        headsign: "",
        from: leg.from || legs[i - 1].to || "",
        to: "",
        departText: clockText(legs[i - 1].arriveMs),
        arriveText: clockText(leg.departMs),
        platform: "",
        realtime: false,
        alertTitle: "",
        disruption: false,
        stopsText: "",
        minutes: Math.max(1, Math.round(gapMs / 60000))
      })
    }

    var infos = leg.infos && isFinite(leg.infos.length) ? leg.infos : []
    var alert = infos.length ? infos[0] : null
    for (var a = 0; a < infos.length; a++) if (isDisruption(infos[a])) {
      alert = infos[a]
      break
    }
    // One alert usually applies to every leg through the same station; show it once.
    if (alert && shownAlerts[String(alert.title || "")]) alert = null
    if (alert) shownAlerts[String(alert.title || "")] = true
    var stopsText = leg.kind === "ride" ? stopListText(leg.stops, 6) : ""
    if (leg.kind === "ride" && !stopsText)
      stopsText = [boardStopName(leg.from), boardStopName(leg.to)].filter(function(name) { return name !== "" }).join(" · ")
    rows.push({
      kind: leg.kind,
      mode: leg.kind === "walk" ? "walk" : (leg.mode || "other"),
      tripId: leg.kind === "ride" ? String(leg.tripId || "") : "",
      crowding: leg.kind === "ride" && occupancy ? String(occupancy[String(leg.tripId || "")] || "") : "",
      line: leg.kind === "walk" ? "" : String(leg.line || ""),
      headsign: leg.kind === "walk" ? "" : String(leg.destination || ""),
      from: String(leg.from || ""),
      to: String(leg.to || ""),
      departText: clockText(leg.departMs),
      arriveText: clockText(leg.arriveMs),
      platform: leg.kind === "walk" ? "" : String(leg.platform || ""),
      realtime: leg.kind === "ride" && leg.realtime === true,
      alertTitle: alert ? String(alert.title || "") : "",
      disruption: alert ? isDisruption(alert) : false,
      stopsText: stopsText,
      minutes: Math.max(1, Math.round(Number(leg.durationSec || 0) / 60))
    })
  }
  return rows
}

function hasDestination(place) { return !!(place && place.destStopId) }

// The ride ends at the chosen stop; the walk to the door is ours to add so the
// board arrives where the user is actually going.
function appendEndWalk(journeys, minutes, toName) {
  var walk = Math.max(0, Math.round(Number(minutes) || 0))
  var list = journeys && isFinite(journeys.length) ? journeys : []
  if (!walk) return list
  var out = []
  for (var i = 0; i < list.length; i++) {
    var journey = list[i]
    // Arrays that crossed a QML `property var` are copied by length.
    var legs = []
    var source = journey.legs && isFinite(journey.legs.length) ? journey.legs : []
    for (var l = 0; l < source.length; l++) legs.push(source[l])
    var last = legs.length ? legs[legs.length - 1] : null
    var startMs = Number(last ? last.arriveMs : journey.arriveMs) || 0
    legs.push({ kind: "walk", mode: "walk", line: "", destination: "", headsign: "", platform: "",
                from: last ? String(last.to || "") : "", to: String(toName || ""), fromId: "", toId: "",
                departMs: startMs, arriveMs: startMs + walk * 60000, durationSec: walk * 60,
                realtime: false, infos: [], stops: [], tripId: "" })
    out.push(Object.assign({}, journey, { legs: legs, arriveMs: startMs + walk * 60000 }))
  }
  return out
}

// Chip order for nearby stops: the preferred one first (the planner's own
// choice), then the nearest stop of each station-class mode (train, metro,
// light rail, ferry) within maxStationWalk minutes, then the rest by
// distance. One per mode, so a walkable Central is not buried under the
// bus stops that happen to be closer.
var STATION_MODES = ["train", "metro", "lightrail", "ferry"]
function featureNearby(list, preferredId, maxStationWalk) {
  var source = list && isFinite(list.length) ? list : []
  var limit = isFinite(maxStationWalk) ? Number(maxStationWalk) : 15
  var out = [], seen = {}, covered = {}
  function take(item) {
    if (!item || seen[String(item.id)]) return
    seen[String(item.id)] = true
    out.push(item)
  }
  for (var p = 0; p < source.length; p++) if (preferredId && String(source[p].id) === String(preferredId)) take(source[p])
  for (var i = 0; i < source.length; i++) {
    if (Number(source[i].walkMinutes || 0) > limit) continue
    var modes = source[i].modes && isFinite(source[i].modes.length) ? source[i].modes : []
    var fresh = false
    for (var m = 0; m < modes.length; m++) {
      var mode = String(modes[m])
      if (STATION_MODES.indexOf(mode) !== -1 && !covered[mode]) fresh = true
    }
    if (!fresh) continue
    for (var c = 0; c < modes.length; c++) covered[String(modes[c])] = true
    take(source[i])
  }
  for (var r = 0; r < source.length; r++) take(source[r])
  return out
}

function finalWalkMinutes(entry) {
  var legs = entry ? listValue(entry.legs) : []
  if (!legs.length || legs[legs.length - 1].kind !== "walk") return 0
  return Math.max(0, Math.round(Number(legs[legs.length - 1].durationSec || 0) / 60))
}

function endKind(place, end) {
  if (!place) return "stop"
  return String(end || "origin") === "dest"
    ? (String(place.destAddress || "").trim() ? "address" : "stop")
    : (String(place.address || "").trim() ? "address" : "stop")
}

function endLabel(place, end) {
  var destination = String(end || "origin") === "dest"
  var text = destination
    ? (endKind(place, "dest") === "address" ? place.destAddress : place.destStopName)
    : (endKind(place, "origin") === "address" ? place.address : place.stopName)
  return boardStopName(text)
}

// Route text never repeats the trip nickname: it names only its two ends.
function routeLabel(place) {
  if (!place) return ""
  var from = endLabel(place, "origin") || "Unknown stop"
  if (!hasDestination(place)) return from + " departures"
  return from + " → " + (endLabel(place, "dest") || "destination")
}

function tripName(place) {
  if (!place) return ""
  var name = String(place.name || "").trim()
  return String(place.id || "") === "temp" || !name ? routeLabel(place) : name
}

function routeCaption(place) {
  if (!place) return ""
  var text = routeLabel(place)
  var originWalk = Math.max(0, Math.round(Number(place.walkMinutes) || 0))
  var destWalk = Math.max(0, Math.round(Number(place.destWalkMinutes) || 0))
  if (originWalk > 0) text += " · " + originWalk + " min walk"
  if (destWalk > 0) text += " · then " + destWalk + " min walk"
  return text
}

function placeTooltip(place) {
  if (!place) return ""
  var text = String(endKind(place, "origin") === "address" ? place.address : (place.stopName || ""))
  if (hasDestination(place))
    text += " → " + String(endKind(place, "dest") === "address" ? place.destAddress : (place.destStopName || "destination"))
  else
    text += " departures"
  var walk = isFinite(place.walkMinutes) ? Math.max(0, Math.round(Number(place.walkMinutes))) : 0
  if (walk > 0) text += " · " + walk + " min walk"
  return text
}

function firstWord(text) {
  var name = String(text || "").replace(/\s+(Station|Wharf|Interchange|Light Rail)\b.*$/i, "").trim()
  return name.split(",")[0].trim() || String(text || "")
}

function travelText(sec) {
  if (!sec) return ""
  var minutes = Math.max(1, Math.round(sec / 60))
  return minutes + " min"
}

function nextCatchable(board, place, nowMs) {
  for (var i = 0; i < board.length; i++) {
    if (board[i].cancelled || board[i].dominated) continue
    if (leaveInMs(board[i], place, nowMs) >= 0) return board[i]
  }
  return null
}

function leaveHeading(leaveMs) {
  if (!isFinite(leaveMs) || leaveMs < 60 * 1000) return "Leave now"
  return "Leave in " + Math.floor(leaveMs / 60000) + " min"
}

function relativeTimeText(lastMs, nowMs) {
  if (!isFinite(lastMs) || Number(lastMs) <= 0) return "updated never"
  var elapsed = Math.max(0, Number(nowMs) - Number(lastMs))
  if (elapsed < 60 * 1000) return "updated " + Math.floor(elapsed / 1000) + "s ago"
  if (elapsed < 60 * 60 * 1000) return "updated " + Math.floor(elapsed / 60000) + "m ago"
  return "updated " + Math.floor(elapsed / 3600000) + "h ago"
}

function dateTimeText(ms) {
  var d = new Date(ms)
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + " · " + clockText(ms)
}

function minutesText(ms) {
  var minutes = Math.floor(ms / 60000)
  if (ms < 0) return "now"
  if (minutes < 1) return "now"
  if (minutes >= 100) return "99+′"
  return minutes + "′"
}

// Times follow the bar clock. The clock widget's Qt format string lives in
// shell.json ("ddd d MMM h:mm AP", "dddd HH:mm", …); "AP"/"ap" or a lone
// "h" means 12-hour. Service reads shell.json and calls setTwelveHour.
var twelveHour = false
function setTwelveHour(value) { twelveHour = value === true }
function clockFormatIsTwelveHour(format) {
  var f = String(format || "")
  if (/\bAP\b|\bap\b|\bA\b|\ba\b/.test(f)) return true
  if (/HH|H/.test(f)) return false
  return /(^|[^h])h(?!h)|hh/.test(f)
}
// Finds the clock widget's format anywhere in the bar layout of shell.json.
function clockFormatFromShellConfig(text) {
  var config = null
  try { config = JSON.parse(String(text || "")) } catch (e) { return "" }
  var layout = config && config.bar && config.bar.layout ? config.bar.layout : null
  if (!layout || typeof layout !== "object") return ""
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var list = listValue(layout[sections[s]])
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && entry.id === "omarchy.clock") return typeof entry.format === "string" ? entry.format : "dddd HH:mm"
    }
  }
  return ""
}
function clockText(ms, forceTwelveHour) {
  if (!ms) return ""
  var d = new Date(ms)
  function two(n) { return (n < 10 ? "0" : "") + n }
  var use12 = forceTwelveHour === undefined ? twelveHour : forceTwelveHour === true
  if (!use12) return two(d.getHours()) + ":" + two(d.getMinutes())
  var hours = d.getHours()
  var suffix = hours >= 12 ? " PM" : " AM"
  var h = hours % 12
  if (h === 0) h = 12
  return h + ":" + two(d.getMinutes()) + suffix
}

// Bar pill: "T4 · 6′" (leave in), or the reason there is nothing to show.
function pillText(board, place, nowMs) {
  var next = nextCatchable(board, place, nowMs)
  if (!next) return ""
  var text = next.line + " · " + minutesText(leaveInMs(next, place, nowMs))
  if (next.arriveMs) text += " → " + clockText(next.arriveMs)
  return text
}

function pillMode(board, place, nowMs) {
  var next = nextCatchable(board, place, nowMs)
  return next ? next.mode : (place && place.modes && place.modes.length === 1 ? place.modes[0] : "train")
}

// Bar state for the icon-only widget: leave-in for the next catchable
// service, its line colour, and a caption that only appears at the end.
var UNDERLINE_WINDOW_MS = 10 * 60 * 1000
var CAPTION_WINDOW_MS = 2 * 60 * 1000

function barState(board, place, nowMs) {
  var next = nextCatchable(board, place, nowMs)
  if (!next) return { leaveMs: -1, lineColor: "", line: "", destination: "", fraction: 0, caption: "" }
  var leave = leaveInMs(next, place, nowMs)
  return {
    leaveMs: leave,
    lineColor: Api.lineColor(next.line, next.mode),
    line: String(next.line || ""),
    destination: hasDestination(place) ? boardStopName(place.destAddress || place.destStopName) : String(next.headsign || next.destination || ""),
    fraction: underlineFraction(leave),
    caption: barCaption(leave)
  }
}

// Fills left→right as leave-in runs from 10 min to 0; hidden beyond that.
function underlineFraction(leaveMs) {
  if (!isFinite(leaveMs) || leaveMs < 0) return 0
  return Math.max(0, Math.min(1, 1 - leaveMs / UNDERLINE_WINDOW_MS))
}

// Only in the last two minutes: "2", "1" or "now".
function barCaption(leaveMs) {
  if (!isFinite(leaveMs) || leaveMs < 0 || leaveMs > CAPTION_WINDOW_MS) return ""
  var minutes = Math.floor(leaveMs / 60000)
  return minutes < 1 ? "now" : String(minutes)
}

// "leave in" under a couple of minutes for the next service is the moment
// to shut the laptop; the pill turns urgent.
function urgency(board, place, nowMs) {
  var next = nextCatchable(board, place, nowMs)
  if (!next) return "none"
  var leave = leaveInMs(next, place, nowMs)
  if (leave <= 2 * 60 * 1000) return "now"
  if (leave <= 5 * 60 * 1000) return "soon"
  return "calm"
}

function projectRow(dep, place, nowMs, occupancy) {
  var leave = leaveInMs(dep, place, nowMs)
  var delay = delaySec(dep)
  var delayMin = Math.round(delay / 60)
  var status = dep.cancelled ? "Cancelled"
    : (!dep.realtime ? "Scheduled" : (Math.abs(delayMin) < 1 ? "On time" : (delayMin > 0 ? delayMin + " min late" : Math.abs(delayMin) + " min early")))
  var trip = !!dep.arriveMs
  return {
    depId: String(dep.id),
    tripId: String(dep.tripId || ""),
    crowding: dep.arriveMs && occupancy ? String(occupancy[String(dep.tripId || "")] || "") : "",
    line: dep.line,
    lineName: dep.lineName,
    mode: dep.mode,
    glyph: glyphFor(dep.mode),
    destination: trip && place && (place.destAddress || place.destStopName)
      ? boardStopName(place.destAddress || place.destStopName) : dep.destination,
    headsign: dep.headsign || dep.destination,
    platform: dep.platform,
    timeText: clockText(Api.effectiveMs(dep)),
    plannedText: clockText(dep.plannedMs),
    leaveText: dep.cancelled ? "—" : (leave < 0 ? "missed" : minutesText(leave)),
    leaveMs: leave,
    departsInText: minutesText(Api.effectiveMs(dep) - nowMs),
    realtime: dep.realtime,
    cancelled: dep.cancelled,
    dominated: dep.dominated === true,
    delayMin: delayMin,
    status: status,
    missed: !dep.cancelled && leave < 0,
    alertCount: dep.infos.length,
    alertTitle: dep.infos.length ? dep.infos[0].title : "",
    arriveText: dep.arriveMs ? clockText(dep.arriveMs) : "",
    travelText: dep.arriveMs ? travelText(dep.travelSec) : "",
    changesText: !dep.arriveMs || dep.changes === 0 ? "" : dep.changes + (dep.changes === 1 ? " change" : " changes"),
    legsSummary: dep.legsSummary || ""
  }
}

function buildRows(board, place, nowMs, occupancy) {
  var rows = []
  for (var i = 0; i < board.length; i++) rows.push(projectRow(board[i], place, nowMs, occupancy))
  return rows
}

// Distinct alerts across the board, most-mentioned first. These come free
// with the departure board (each stop event carries the alerts affecting it).
function collectAlerts(board) {
  var counts = Object.create(null)
  var order = []
  for (var i = 0; i < board.length; i++) {
    var infos = board[i].infos || []
    for (var j = 0; j < infos.length; j++) {
      var info = infos[j]
      if (!counts[info.id]) { counts[info.id] = { info: info, count: 0 }; order.push(info.id) }
      counts[info.id].count++
    }
  }
  order.sort(function(a, b) { return counts[b].count - counts[a].count })
  var out = []
  for (var k = 0; k < order.length && out.length < 4; k++) {
    var entry = counts[order[k]]
    out.push({ id: entry.info.id, title: entry.info.title, priority: entry.info.priority,
               url: entry.info.url, text: String(entry.info.text || ""), disruption: isDisruption(entry.info) })
  }
  return out
}

function isDisruption(info) {
  return /replace|cancel|not stop|suspend|no (trains|services|buses|ferries)|closed|delay/i.test(String(info.title || ""))
}

// A "leave now" notification fires once per trip, when its leave-in crosses
// into the last two minutes. `sent` is the set of trip ids already used.
function notificationFor(board, place, nowMs, sent) {
  var next = nextCatchable(board, place, nowMs)
  if (!next) return null
  var leave = leaveInMs(next, place, nowMs)
  if (leave > 2 * 60 * 1000 || leave < 0) return null
  var key = String(next.id)
  if (sent && sent[key]) return null
  var changeAt = ""
  var legs = next ? listValue(next.legs) : []
  var ridesSeen = 0
  for (var i = 0; i < legs.length; i++) if (legs[i].kind === "ride") {
    ridesSeen++
    if (ridesSeen === 2) {
      changeAt = firstWord(legs[i].from)
      break
    }
  }
  return {
    key: key,
    headline: "Leave now for the " + clockText(Api.effectiveMs(next)) + " " + next.line,
    body: next.destination + (next.platform ? " · Platform " + next.platform : "")
      + (place && place.walkMinutes ? " · " + place.walkMinutes + " min walk" : "")
      + (next.arriveMs ? " · arrives " + clockText(next.arriveMs) : "")
      + (changeAt ? " · change at " + changeAt : "")
  }
}

// Legacy compact journey projection retained for fixture and demo coverage.
function projectJourney(journey, nowMs) {
  var legs = journey.legs || []
  var rides = []
  for (var i = 0; i < legs.length; i++) if (legs[i].kind === "ride") rides.push(legs[i])
  var firstRide = rides.length ? rides[0] : null
  var summary = []
  for (var j = 0; j < legs.length; j++) {
    var leg = legs[j]
    summary.push(leg.kind === "walk" ? "walk " + Math.max(1, Math.round(leg.durationSec / 60)) + "′" : leg.line)
  }
  var alerts = []
  for (var k = 0; k < legs.length; k++) for (var a = 0; a < legs[k].infos.length; a++) alerts.push(legs[k].infos[a])
  return {
    leaveMs: journey.departMs - nowMs,
    leaveText: minutesText(journey.departMs - nowMs),
    departText: clockText(journey.departMs),
    arriveText: clockText(journey.arriveMs),
    durationText: Math.max(1, Math.round(journey.durationSec / 60)) + " min",
    line: firstRide ? firstRide.line : "walk",
    mode: firstRide ? firstRide.mode : "walk",
    glyph: glyphFor(firstRide ? firstRide.mode : "walk"),
    platform: firstRide ? firstRide.platform : "",
    destination: firstRide ? firstRide.destination : "",
    summary: summary.join(" → "),
    realtime: rides.length > 0 && rides.every(function(r) { return r.realtime }),
    changes: Math.max(0, rides.length - 1),
    alertTitle: alerts.length ? alerts[0].title : ""
  }
}

function escapeMarkup(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function notificationTag(key) {
  return "tfnsw-" + String(key || "").replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 60)
}

// Which place should be active given the Wi-Fi network we are on.
function placeForSsid(places, ssid) {
  var wanted = String(ssid || "").trim()
  if (!wanted) return null
  for (var i = 0; i < places.length; i++) {
    if (String(places[i].ssid || "").trim() === wanted) return places[i]
  }
  return null
}
