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
  var n = value && isFinite(value.length) ? Number(value.length) : 0
  for (var i = 0; i < n; i++) out.push(String(value[i]))
  return out
}

function matchStops(list, text, limit) {
  var query = String(text || "").trim().toLowerCase()
  if (!query || !Array.isArray(list)) return []
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
      // Arrays that crossed a QML `property var` may not satisfy Array.isArray.
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
  if (!Array.isArray(list) || typeof lat !== "number" || typeof lon !== "number"
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
      walkMinutes: Math.max(0, Math.round(ranked[r].metres / 80))
    })
  }
  return out
}

// Saved origin and destination stops become a compact destination chooser.
// The first place mentioning a stop supplies its contextual label.
function destinationOptions(places) {
  var list = Array.isArray(places) ? places : []
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

function tempPlaceFrom(location, firstStop, destStop, walkMinutes) {
  if (!location || !firstStop || !destStop) return null
  var name = String(location.name || location.shortName || "New trip").split(",")[0].trim() || "New trip"
  return {
    id: "temp",
    name: name,
    stopId: String(firstStop.id || ""),
    stopName: String(firstStop.name || firstStop.shortName || ""),
    destStopId: String(destStop.id || ""),
    destStopName: String(destStop.name || destStop.shortName || ""),
    walkMinutes: Math.max(0, Math.round(Number(walkMinutes) || 0)),
    lines: [],
    modes: []
  }
}

function boardStopName(name) {
  return String(name || "")
    .replace(/\s+(Station|Wharf|Light Rail|Interchange)\b.*$/i, "")
    .replace(/\bStreet\b/g, "St")
    .trim()
}

// A bounded stop sequence for the mini indicator board. Parsed stops are
// objects, but accepting strings keeps the helper useful and easy to test.
function stopListText(stops, max) {
  var list = Array.isArray(stops) ? stops : []
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
  var list = Array.isArray(departures) ? departures : []
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
  var list = Array.isArray(journeys) ? journeys : []
  var entries = []
  for (var i = 0; i < list.length; i++) {
    var journey = list[i]
    var legs = journey && Array.isArray(journey.legs) ? journey.legs : []
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
      tripId: "",
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
  var list = Array.isArray(board) ? board : []
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
function legRows(entry) {
  var shownAlerts = {}
  var legs = entry && Array.isArray(entry.legs) ? entry.legs : []
  var rows = []
  for (var i = 0; i < legs.length; i++) {
    var leg = legs[i]
    if (!leg || (leg.kind !== "ride" && leg.kind !== "walk")) continue

    if (i > 0 && leg.kind === "ride" && legs[i - 1] && legs[i - 1].kind === "ride") {
      var gapMs = Number(leg.departMs || 0) - Number(legs[i - 1].arriveMs || 0)
      if (gapMs >= 60 * 1000) rows.push({
        kind: "change",
        mode: "",
        line: "",
        headsign: "",
        from: leg.from || legs[i - 1].to || "",
        to: "",
        departText: "",
        arriveText: "",
        platform: "",
        realtime: false,
        alertTitle: "",
        disruption: false,
        stopsText: "",
        minutes: Math.max(1, Math.round(gapMs / 60000))
      })
    }

    var infos = Array.isArray(leg.infos) ? leg.infos : []
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

// "From Home" / "Home → Wynyard": what the place selector says.
function placeLabel(place) {
  if (!place) return ""
  if (!hasDestination(place)) return "From " + place.name
  return place.name + " → " + firstWord(place.destStopName || "destination")
}

// Selector text under the place name: the route, since the title already
// says which place it is. "Surry Hills → Chatswood" / "From Sydenham".
function routeLabel(place) {
  if (!place) return ""
  if (String(place.id || "") === "temp")
    return "New trip · " + String(place.name || "New trip") + (hasDestination(place)
      ? " → " + (boardStopName(place.destStopName) || "destination") : "")
  var from = boardStopName(place.stopName) || place.name
  if (!hasDestination(place)) return "From " + from
  return from + " → " + (boardStopName(place.destStopName) || "destination")
}

function placeTooltip(place) {
  if (!place) return ""
  var text = String(place.stopName || place.name || "")
  if (hasDestination(place))
    text += " → " + String(place.destStopName || "destination")
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
    var list = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
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
    destination: hasDestination(place) ? boardStopName(place.destStopName) : String(next.headsign || next.destination || ""),
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

function projectRow(dep, place, nowMs) {
  var leave = leaveInMs(dep, place, nowMs)
  var delay = delaySec(dep)
  var delayMin = Math.round(delay / 60)
  var status = dep.cancelled ? "Cancelled"
    : (!dep.realtime ? "Scheduled" : (Math.abs(delayMin) < 1 ? "On time" : (delayMin > 0 ? delayMin + " min late" : Math.abs(delayMin) + " min early")))
  var trip = !!dep.arriveMs
  return {
    depId: String(dep.id),
    tripId: String(dep.tripId || ""),
    line: dep.line,
    lineName: dep.lineName,
    mode: dep.mode,
    glyph: glyphFor(dep.mode),
    destination: trip && place && place.destStopName ? boardStopName(place.destStopName) : dep.destination,
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

function buildRows(board, place, nowMs) {
  var rows = []
  for (var i = 0; i < board.length; i++) rows.push(projectRow(board[i], place, nowMs))
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
               url: entry.info.url, disruption: isDisruption(entry.info) })
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
  var legs = next && Array.isArray(next.legs) ? next.legs : []
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
