const { loadModule, fixture, assert, equal, done } = require("./helpers")
const Api = loadModule("Api.js")
const Model = loadModule("Model.js")

const deps = Api.parseDepartures(fixture("departure_mon_sydenham.json"))
// The fixture was captured at 12:05 UTC on 2026-09-02; pretend it is now.
const now = Date.UTC(2026, 8, 2, 12, 5, 0)
const home = { id: "home", name: "Home", stopId: "204420", stopName: "Sydenham Station", lines: ["T4"], destination: "City", modes: ["train"], walkMinutes: 5, ssid: "" }

// --- bundled stop type-ahead
const searchableStops = [
  { id: "4", name: "Scratchatown Wharf 2", modes: ["ferry"], lat: -33.8, lon: 151.2 },
  { id: "3", name: "The Chatswood Light Rail", modes: ["lightrail"] },
  { id: "2", name: "East Chatswood Station", modes: ["train"] },
  { id: "1", name: "Chatswood Station", modes: ["metro", "train"] }
]
equal(Model.matchStops(searchableStops, "CHAT").map(x => x.id), ["1", "2", "3", "4"], "stop matches rank name prefix, word prefix, then contains")
equal(Model.matchStops(searchableStops, "c").map(x => x.id), ["1", "2", "3", "4"], "one-character local stop queries are supported")
equal(Model.matchStops(searchableStops, "chat", 2).map(x => x.id), ["1", "2"], "stop match limit is honoured")
equal(Model.matchStops(Array.from({ length: 10 }, (_, i) => ({ id: String(i + 10), name: "Stop " + i })), "stop").length, 8, "stop match limit defaults to eight")
equal([Model.matchStops(searchableStops, ""), Model.matchStops(searchableStops, "   "), Model.matchStops(null, "chat")], [[], [], []], "empty queries and malformed lists have no matches")
const malformedStops = [null, {}, { id: 123, name: "Number id" }, { id: "ABC", name: "Letter id" }, { id: "5", name: "  " }, { id: "6", name: "Valid Station", modes: "train" }]
equal(Model.matchStops(malformedStops, "valid").map(x => x.id), ["6"], "malformed stop entries are ignored")
equal(Model.matchStops(searchableStops, "chat", 1)[0], {
  id: "1", name: "Chatswood Station", shortName: "Chatswood", isStop: true,
  modes: ["metro", "train"], type: "stop", lat: null, lon: null
}, "local stop results match the picker result shape")

const nearby = Model.nearestStops([
  { id: "10", name: "Near Station", modes: ["train"], lat: -33.8680, lon: 151.2070 },
  { id: "11", name: "Next Light Rail", modes: ["lightrail"], lat: -33.8700, lon: 151.2070 },
  { id: "13", name: "Third Wharf", modes: ["ferry"], lat: -33.8720, lon: 151.2070 },
  { id: "14", name: "Fourth Station", modes: ["train"], lat: -33.8740, lon: 151.2070 },
  { id: "12", name: "Far Station", modes: ["train"], lat: -33.9000, lon: 151.2070 }
], -33.8680, 151.2070, 3, 1500)
equal(nearby.map(x => x.id), ["10", "11", "13"], "nearest stops are distance-ranked and limited")
equal(nearby.map(x => x.walkMinutes), [0, 3, 6], "nearest stops estimate walking at 80 metres per minute")
equal(Model.nearestStops([{ id: "12", name: "Far Station", modes: ["train"], lat: -33.9000, lon: 151.2070 }], -33.8680, 151.2070, 3, 1500), [], "nearest stops enforce the maximum radius")
equal(Model.nearestStops(searchableStops, null, 151.2), [], "nearest stops require coordinates")
const mergedNearby = Model.mergeNearby([
  { id: "10", name: "Bundled Station", modes: ["train"], lat: -33.8, lon: 151.2, distanceMetres: 240, walkMinutes: 99 }
], [
  { id: "10", name: "API duplicate", metres: 80, walkMinutes: 1, modes: [] },
  { id: "20", name: "Bus stop", metres: 160, walkMinutes: 99, modes: [] }
])
equal(mergedNearby.map(x => [x.id, x.name, x.metres, x.walkMinutes]),
  [["20", "Bus stop", 160, 2], ["10", "Bundled Station", 240, 3]],
  "nearby merge deduplicates with bundled data winning and sorts by metres")
equal([
  Model.displayStopName("Chatswood Station"),
  Model.displayStopName("Surry Hills Light Rail"),
  Model.displayStopName("Circular Quay Wharf 5"),
  Model.displayStopName("Balmain East Wharf")
], ["Chatswood", "Surry Hills", "Circular Quay", "Balmain East Wharf"], "picker stop names strip only supported trailing labels")

const board = Model.boardFor(deps, home, now)
assert(board.length > 0 && board.length <= Model.MAX_ROWS, "board is bounded")
assert(board.every(d => d.line === "T4" && /City/.test(d.destination)), "board honours line and destination filters")
assert(board.every(d => Model.leaveInMs(d, home, now) >= -Model.MISSED_GRACE_MS), "missed services drop off")

const any = Model.boardFor(deps, { stopId: "204420", lines: [], destination: "", modes: [], walkMinutes: 0 }, now)
assert(any.some(d => d.mode === "metro") && any.some(d => d.mode === "train"), "empty filters show every mode")

const next = Model.nextCatchable(board, home, now)
assert(next && !next.cancelled && Model.leaveInMs(next, home, now) >= 0, "next catchable is a future, not cancelled service")
const pill = Model.pillText(board, home, now)
assert(/^T4 · (now|[0-9]+′)$/.test(pill), "pill text shape: " + pill)
equal(Model.pillMode(board, home, now), "train", "pill mode follows the next departure")
equal(Model.pillText([], home, now), "", "empty board has no pill text")
equal(Model.pillMode([], { modes: ["ferry"] }, now), "ferry", "empty board falls back to the place's only mode")

equal(Model.minutesText(30 * 1000), "now", "under a minute is now")
equal(Model.minutesText(6 * 60 * 1000 + 5000), "6′", "minutes text")
equal(Model.minutesText(-5000), "now", "negative is now")
equal(Model.minutesText(200 * 60 * 1000), "99+′", "capped")
equal([Model.leaveHeading(59000), Model.leaveHeading(60000), Model.leaveHeading(3 * 60000 + 59000)],
  ["Leave now", "Leave in 1 min", "Leave in 3 min"], "leave heading grammar")
equal([Model.relativeTimeText(now - 12000, now), Model.relativeTimeText(now - 2 * 60000, now), Model.relativeTimeText(0, now)],
  ["updated 12s ago", "updated 2m ago", "updated never"], "footer relative time text")

const rows = Model.buildRows(board, home, now)
equal(rows.length, board.length, "one row per board entry")
assert(rows[0].line === "T4" && rows[0].timeText.match(/^[0-9]{2}:[0-9]{2}$/) && rows[0].glyph !== "", "row projection")
assert(rows.every(r => ["On time", "Scheduled", "Cancelled"].indexOf(r.status) !== -1 || /min (late|early)$/.test(r.status)), "row status vocabulary")

const cancelled = { id: "x", line: "T4", destination: "City", mode: "train", plannedMs: now + 600000, estimatedMs: 0, realtime: false, cancelled: true, infos: [] }
const late = { id: "y", line: "T4", destination: "City", mode: "train", plannedMs: now + 600000, estimatedMs: now + 840000, realtime: true, cancelled: false, infos: [] }
const projected = Model.buildRows([cancelled, late], home, now)
equal([projected[0].status, projected[0].leaveText, projected[1].status, projected[1].delayMin], ["Cancelled", "—", "4 min late", 4], "cancelled and delayed rows")
assert(Model.nextCatchable([cancelled, late], home, now) === late, "cancelled services are skipped for the pill")

const urgencyNow = Model.urgency([{ id: "a", line: "T4", destination: "City", mode: "train", plannedMs: now + 6 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }], home, now)
equal(urgencyNow, "now", "one minute of slack after the walk is urgent")
equal(Model.urgency([{ id: "a", line: "T4", destination: "City", mode: "train", plannedMs: now + 30 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }], home, now), "calm", "plenty of time is calm")

equal(Model.underlineFraction(-1), 0, "no underline once the service is missed")
equal(Model.underlineFraction(15 * 60000), 0, "no underline beyond ten minutes")
equal(Model.underlineFraction(5 * 60000), 0.5, "underline is half full at five minutes")
equal(Model.underlineFraction(0), 1, "underline is full at zero")
equal([Model.barCaption(5 * 60000), Model.barCaption(119000), Model.barCaption(59000), Model.barCaption(-5)], ["", "1", "now", ""], "caption only in the last two minutes")
const barNow = Model.barState([{ id: "a", line: "T4", destination: "City", mode: "train", plannedMs: now + 6 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }], home, now)
equal([barNow.lineColor, barNow.caption, barNow.fraction > 0.85], ["#005AA3", "1", true], "bar state carries the T4 line colour, caption and fill")
equal([barNow.line, barNow.destination], ["T4", "City"], "bar state names the next service")
equal(Model.barState([], home, now), { leaveMs: -1, lineColor: "", line: "", destination: "", fraction: 0, caption: "" }, "empty board yields an idle bar state")

const alerts = Model.collectAlerts(board)
assert(alerts.length >= 1 && alerts[0].id === "ems-76903", "alerts collected from the board")
assert(alerts[0].disruption === true, "replacement buses count as a disruption")
assert(!Model.isDisruption({ title: "Extra services for the football" }), "info-only alert is not a disruption")

const sent = {}
const soon = [{ id: "trip-1", line: "T4", destination: "City", mode: "train", platform: "3", plannedMs: now + 6 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }]
const notification = Model.notificationFor(soon, home, now, sent)
assert(notification && notification.key === "trip-1" && /Leave now for the/.test(notification.headline), "leave-now notification")
sent["trip-1"] = true
assert(Model.notificationFor(soon, home, now, sent) === null, "notification is sent once per trip")
assert(Model.notificationFor(soon, home, now - 10 * 60000, {}) === null, "no notification while there is plenty of time")

const journeys = Api.parseJourneys(fixture("trip_sydenham_to_wynyard.json"))
const journeyRow = Model.projectJourney(journeys[0], journeys[0].departMs - 8 * 60000)
equal([journeyRow.line, journeyRow.mode, journeyRow.changes, journeyRow.leaveText], ["T4", "train", 0, "8′"], "journey projection")
assert(/^T4/.test(journeyRow.summary), "journey summary starts with the ride")

// --- trips (origin → destination) from journeys
const tripPlace = { id: "commute", name: "Home", stopId: "204420", stopName: "Sydenham Station", destStopId: "200080", destStopName: "Wynyard Station", lines: [], destination: "", modes: [], walkMinutes: 5, ssid: "" }
const tripNow = journeys[0].departMs - 9 * 60000
const tripBoard = Model.boardFromJourneys(journeys, tripPlace, tripNow)
equal(tripBoard.length, 1, "one journey becomes one board entry")
equal([tripBoard[0].line, tripBoard[0].mode, tripBoard[0].changes, tripBoard[0].platform, tripBoard[0].stopName], ["T4", "train", 0, "3", "Sydenham Station"], "journey entry takes the first ride's identity")
assert(tripBoard[0].arriveMs === journeys[0].arriveMs && tripBoard[0].travelSec > 0, "journey entry carries arrival and travel time")
const tripRows = Model.buildRows(tripBoard, tripPlace, tripNow)
assert(/^[0-9]{2}:[0-9]{2}$/.test(tripRows[0].arriveText) && /min$/.test(tripRows[0].travelText) && tripRows[0].changesText === "", "direct trip rows omit a changes pill")
equal([tripRows[0].destination, tripRows[0].headsign], ["Wynyard", journeys[0].legs[0].destination], "trip rows lead with the place destination and keep the vehicle headsign")
assert(/^T4 · 4′ → [0-9]{2}:[0-9]{2}$/.test(Model.pillText(tripBoard, tripPlace, tripNow)), "pill shows the arrival for trips: " + Model.pillText(tripBoard, tripPlace, tripNow))
assert(Model.boardFromJourneys(journeys, Object.assign({}, tripPlace, { lines: ["T8"] }), tripNow).length === 0, "line filter applies to the first ride")
const crowding = {}
crowding[journeys[0].legs[0].tripId] = "few"
const crowdedTripRows = Model.buildRows(tripBoard, tripPlace, tripNow, crowding)
equal([tripBoard[0].tripId, crowdedTripRows[0].tripId, crowdedTripRows[0].crowding],
  [journeys[0].legs[0].tripId, journeys[0].legs[0].tripId, "few"],
  "trip board rows carry crowding joined from the first ride")
const tripNotification = Model.notificationFor(tripBoard, tripPlace, journeys[0].departMs - 6 * 60000, {})
assert(tripNotification && / · arrives [0-9]{2}:[0-9]{2}$/.test(tripNotification.body), "trip notification includes arrival time")
const multi = Api.parseJourneys(fixture("trip_surry_hills_to_chatswood.json"))
const commute = { id: "sh", name: "Home", stopId: "201029", stopName: "Surry Hills Light Rail", destStopId: "206710", destStopName: "Chatswood Station", lines: [], destination: "", modes: [], walkMinutes: 3, ssid: "" }
const commuteNow = multi[0].departMs - 12 * 60000
const commuteBoard = Model.boardFromJourneys(multi, commute, commuteNow)
const commuteRows = Model.buildRows(commuteBoard, commute, commuteNow)
assert(commuteRows.length >= 2 && commuteRows[0].changesText === "1 change" && /^L[23] → M1$/.test(commuteRows[0].legsSummary), "multi-leg journey rows summarise the change")
assert(commuteBoard[0].legs === multi[0].legs, "journey entry keeps the parsed legs array")
equal([commuteBoard[0].headsign, commuteRows[0].headsign], [multi[0].legs[0].destination, multi[0].legs[0].destination], "journey entry and row expose the first ride headsign")
const legOccupancy = {}
legOccupancy[multi[0].legs[1].tripId] = "standing"
const legRows = Model.legRows(commuteBoard[0], legOccupancy)
equal(legRows.map(r => r.kind), ["ride", "change", "ride"], "a transfer gap between adjacent rides becomes a change row")
equal([legRows[0].line, legRows[0].headsign, legRows[0].from, legRows[0].to, legRows[0].realtime], ["L3", "Circular Quay", "Surry Hills Light Rail", "Central Chalmers Street Light Rail", true], "first ride keeps its direction, endpoints and realtime state")
equal([legRows[1].minutes, legRows[1].from], [9, "Central Station"], "change row gives rounded gap and change stop")
equal([legRows[1].departText, legRows[1].arriveText],
  [Model.clockText(multi[0].legs[0].arriveMs), Model.clockText(multi[0].legs[1].departMs)],
  "change row spans the previous arrival and next departure")
equal([legRows[2].line, legRows[2].headsign, legRows[2].platform], ["M1", "Tallawong", "26"], "second ride keeps its own direction and platform")
equal([legRows[0].tripId, legRows[0].crowding, legRows[2].tripId, legRows[2].crowding],
  [multi[0].legs[0].tripId, "", multi[0].legs[1].tripId, "standing"],
  "ride leg rows carry their trip ids and independently joined crowding")
equal(legRows[0].stopsText, "Surry Hills · Central Chalmers St", "leg rows expose the stop sequence")
equal(legRows[2].stopsText, "Central · Gadigal · Martin Place · Barangaroo · Victoria Cross · Crows Nest · … +1", "long stop sequences are bounded")
equal(Model.stopListText(["One", "Two", "Three"], 2), "One · Two · … +1", "stop list helper accepts strings and a custom bound")
assert(Object.keys(legRows[0]).sort().join(",") === ["alertTitle", "arriveText", "crowding", "departText", "disruption", "from", "headsign", "kind", "line", "minutes", "mode", "platform", "realtime", "stopsText", "to", "tripId"].sort().join(","), "leg rows have the documented shape")
const noStops = { legs: [Object.assign({}, multi[0].legs[0], { stops: [] })] }
equal(Model.legRows(noStops)[0].stopsText, "Surry Hills · Central Chalmers St", "ride without a stop sequence falls back to endpoints")
const withWalk = { legs: [multi[0].legs[0], Object.assign({}, multi[0].legs[0], { kind: "walk", mode: "walk", line: "", destination: "", platform: "", from: multi[0].legs[0].to, to: multi[0].legs[1].from, departMs: multi[0].legs[0].arriveMs, arriveMs: multi[0].legs[1].departMs, durationSec: 510, realtime: false, infos: [] }), multi[0].legs[1]] }
equal(Model.legRows(withWalk).map(r => r.kind), ["ride", "walk", "ride"], "an explicit walking leg suppresses the change pseudo-row")
const leadingRows = Model.legRows(commuteBoard[0], legOccupancy, commute.walkMinutes)
equal(leadingRows.map(r => r.kind), ["walk", "ride", "change", "ride"], "place walk is synthesised before a stop-to-stop plan")
equal([leadingRows[0].minutes, leadingRows[0].departText, leadingRows[0].arriveText],
  [commute.walkMinutes, Model.clockText(multi[0].legs[0].departMs - commute.walkMinutes * 60000), Model.clockText(multi[0].legs[0].departMs)],
  "leading walk carries its duration and leave-to-ride clock range")
const startsWithWalk = { legs: [Object.assign({}, withWalk.legs[1], { from: "Home", to: multi[0].legs[0].from }), multi[0].legs[0]] }
equal(Model.legRows(startsWithWalk, {}, commute.walkMinutes).map(r => r.kind), ["walk", "ride"], "an API leading walk is not doubled")
assert(/^L[23] · 9′ → /.test(Model.pillText(Model.boardFromJourneys(multi, commute, commuteNow), commute, commuteNow)), "pill leads with the first leg and ends with the arrival")
const changeNotification = Model.notificationFor(commuteBoard, commute, multi[0].departMs - 4 * 60000, {})
assert(changeNotification && / · change at Central$/.test(changeNotification.body), "multi-leg trip notification names the change stop")
equal(Model.placeLabel(home), "From Home", "place without destination reads as an origin")
equal(Model.routeLabel(home), "From Sydenham", "route label names the stop, not the place")
equal(Model.routeLabel(commute), "Surry Hills → Chatswood", "route label shows both stops short")
const destinationChoices = Model.destinationOptions([home, tripPlace, commute])
equal(destinationChoices.map(x => x.id), ["204420", "200080", "201029", "206710"], "destination stops derive from every saved endpoint and deduplicate")
equal(destinationChoices[1].label, "Wynyard Station · Home", "destination choices include place context")
const tempPlace = Model.tempPlaceFrom({ name: "123 George St, Sydney" }, { id: "201029", name: "Surry Hills Light Rail" }, { id: "206710", name: "Chatswood Station" }, 5.6)
equal(tempPlace, { id: "temp", name: "123 George St", stopId: "201029", stopName: "Surry Hills Light Rail", destStopId: "206710", destStopName: "Chatswood Station", walkMinutes: 6, lines: [], modes: [] }, "temporary place has the unsaved trip shape")
const addressPlace = Model.tempPlaceFrom({ name: "123 George St, Sydney" },
  { id: "201029", name: "Surry Hills Light Rail" }, { id: "206710", name: "Chatswood Station" }, 6,
  { name: "1 Help St, Chatswood", isStop: false, lat: -33.796, lon: 151.181 })
equal([addressPlace.destAddress, addressPlace.destLat, addressPlace.destLon],
  ["1 Help St, Chatswood", -33.796, 151.181], "temporary trip retains its destination address coordinates")
equal(Model.routeLabel(addressPlace), "New trip · 123 George St → 1 Help St",
  "address trip route names the door destination")
equal(Model.finalWalkMinutes({ legs: [{ kind: "ride", durationSec: 600 }, { kind: "walk", durationSec: 350 }] }), 6,
  "final walking leg is rounded for the leave-window caption")
equal(Model.routeLabel(tempPlace), "New trip · 123 George St → Chatswood", "temporary place is identified in the popup selector")
equal(Model.placeLabel(tripPlace), "Home → Wynyard", "trip label shows the destination's short name")
equal(Model.placeTooltip(commute), "Surry Hills Light Rail → Chatswood Station · 3 min walk", "place tooltip shows full stops and walk allocation")
equal(Model.placeTooltip(Object.assign({}, home, { walkMinutes: 0 })), "Sydenham Station", "zero walk is omitted from the place tooltip")
equal(Model.firstWord("Circular Quay Wharf, Sydney"), "Circular Quay", "short destination name")
assert(!Model.hasDestination(home) && Model.hasDestination(tripPlace), "hasDestination")
equal(Model.projectRow(board[0], home, now).arriveText, "", "plain departures have no arrival")

// --- dominated trips
const dominanceBoard = [
  { id: "slow", plannedMs: now + 10 * 60000, estimatedMs: 0, arriveMs: now + 40 * 60000, cancelled: false },
  { id: "fast", plannedMs: now + 12 * 60000, estimatedMs: 0, arriveMs: now + 35 * 60000, cancelled: false },
  { id: "tie", plannedMs: now + 14 * 60000, estimatedMs: 0, arriveMs: now + 35 * 60000, cancelled: false },
  { id: "cancelled", plannedMs: now + 16 * 60000, estimatedMs: 0, arriveMs: now + 30 * 60000, cancelled: true }
]
Model.markDominated(dominanceBoard)
equal(dominanceBoard.map(d => d.dominated), [true, true, false, false], "later earlier arrivals and ties dominate earlier trips")
assert(Model.nextCatchable(dominanceBoard, { walkMinutes: 0 }, now) === dominanceBoard[2], "next catchable skips dominated trips")
const cancelledFirst = [
  { id: "normal", plannedMs: now + 8 * 60000, estimatedMs: 0, arriveMs: now + 50 * 60000, cancelled: false },
  { id: "cancelled-later", plannedMs: now + 9 * 60000, estimatedMs: 0, arriveMs: now + 30 * 60000, cancelled: true }
]
Model.markDominated(cancelledFirst)
equal(cancelledFirst.map(d => d.dominated), [false, false], "cancelled trips are neither dominated nor dominators")
const plainBoard = [{ id: "plain", plannedMs: now + 5 * 60000, cancelled: false }]
Model.markDominated(plainBoard)
assert(!("dominated" in plainBoard[0]), "plain departures are untouched by dominance marking")

// --- clock format follows the bar clock
const evening = new Date(2026, 8, 2, 23, 5).getTime()
const morning = new Date(2026, 8, 2, 0, 7).getTime()
equal([Model.clockText(evening, false), Model.clockText(evening, true), Model.clockText(morning, true), Model.clockText(new Date(2026, 8, 2, 12, 0).getTime(), true)],
  ["23:05", "11:05 PM", "12:07 AM", "12:00 PM"], "24h and 12h clock text")
equal([Model.clockFormatIsTwelveHour("ddd d MMM h:mm AP"), Model.clockFormatIsTwelveHour("dddd HH:mm"), Model.clockFormatIsTwelveHour("h:mm ap"), Model.clockFormatIsTwelveHour("HH\n—\nmm"), Model.clockFormatIsTwelveHour("")],
  [true, false, true, false, false], "12-hour detection from Qt format strings")
equal(Model.clockFormatFromShellConfig(JSON.stringify({ bar: { layout: { center: [{ id: "omarchy.indicators" }, { id: "omarchy.clock", format: "ddd d MMM h:mm AP" }] } } })),
  "ddd d MMM h:mm AP", "clock format found in shell.json")
equal(Model.clockFormatFromShellConfig(JSON.stringify({ bar: { layout: { left: [{ id: "omarchy.clock" }] } } })), "dddd HH:mm", "clock without a format uses the widget default")
equal(Model.clockFormatFromShellConfig("{nope"), "", "invalid shell.json yields no format")
Model.setTwelveHour(true)
assert(/PM|AM/.test(Model.buildRows(board, home, now)[0].timeText), "rows follow the 12-hour setting")
Model.setTwelveHour(false)

equal(Model.placeForSsid([home, { id: "w", ssid: "CCC" }], "CCC").id, "w", "place picked by SSID")
assert(Model.placeForSsid([home], "") === null, "no SSID means no auto place")
equal(Model.notificationTag("609M.1396/158:16"), "tfnsw-609M.1396_158_16", "notification tag is sanitized")
equal(Model.escapeMarkup("<b>&"), "&lt;b&gt;&amp;", "markup escape")

const sharedAlert = { title: "Lift 10 out of service", disruption: true }
const repeated = { legs: [Object.assign({}, multi[0].legs[0], { infos: [sharedAlert] }), Object.assign({}, multi[0].legs[1], { infos: [sharedAlert] })] }
equal(Model.legRows(repeated).filter(r => r.kind === "ride").map(r => r.alertTitle), ["Lift 10 out of service", ""], "an alert shared by consecutive legs is shown once")

const walked = Model.appendEndWalk(multi, 9, "1 Bligh St")
equal(walked[0].legs[walked[0].legs.length - 1].kind, "walk", "appendEndWalk adds a final walking leg")
equal(walked[0].legs[walked[0].legs.length - 1].to, "1 Bligh St", "the walk goes to the door")
equal(walked[0].arriveMs - multi[0].arriveMs, 9 * 60000, "arrival moves by the walk")
equal(Model.finalWalkMinutes(walked[0]), 9, "finalWalkMinutes reads the appended leg")
equal(Model.appendEndWalk(multi, 0, "x"), multi, "zero walk leaves journeys untouched")

const nearbyMix = [
  { id: "b1", name: "Crown St", walkMinutes: 2, modes: [] },
  { id: "b2", name: "Crown St opp", walkMinutes: 2, modes: [] },
  { id: "lr", name: "Surry Hills Light Rail", walkMinutes: 6, modes: ["lightrail"] },
  { id: "c", name: "Central Station", walkMinutes: 18, modes: ["train"] }
]
equal(Model.featureNearby(nearbyMix, "c", 15).map(x => x.id), ["c", "lr", "b1", "b2"], "planner's choice first, then a near station, then by distance")
equal(Model.featureNearby(nearbyMix, "", 5).map(x => x.id), ["b1", "b2", "lr", "c"], "no station within the walk limit keeps distance order")

done("test_model")
