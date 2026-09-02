const { loadModule, fixture, assert, equal, done } = require("./helpers")
const Api = loadModule("Api.js")
const Model = loadModule("Model.js")

const deps = Api.parseDepartures(fixture("departure_mon_sydenham.json"))
// The fixture was captured at 12:05 UTC on 2026-09-02; pretend it is now.
const now = Date.UTC(2026, 8, 2, 12, 5, 0)
const home = { id: "home", name: "Home", stopId: "204420", stopName: "Sydenham Station", lines: ["T4"], destination: "City", modes: ["train"], walkMinutes: 5, ssid: "" }

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

const rows = Model.buildRows(board, home, now)
equal(rows.length, board.length, "one row per board entry")
assert(rows[0].line === "T4" && rows[0].timeText.match(/^[0-9]{2}:[0-9]{2}$/) && rows[0].glyph !== "", "row projection")
assert(rows.every(r => ["On time", "Scheduled", "Cancelled"].indexOf(r.status) !== -1 || /min$/.test(r.status)), "row status vocabulary")

const cancelled = { id: "x", line: "T4", destination: "City", mode: "train", plannedMs: now + 600000, estimatedMs: 0, realtime: false, cancelled: true, infos: [] }
const late = { id: "y", line: "T4", destination: "City", mode: "train", plannedMs: now + 600000, estimatedMs: now + 840000, realtime: true, cancelled: false, infos: [] }
const projected = Model.buildRows([cancelled, late], home, now)
equal([projected[0].status, projected[0].leaveText, projected[1].status, projected[1].delayMin], ["Cancelled", "—", "+4 min", 4], "cancelled and delayed rows")
assert(Model.nextCatchable([cancelled, late], home, now) === late, "cancelled services are skipped for the pill")

const urgencyNow = Model.urgency([{ id: "a", line: "T4", destination: "City", mode: "train", plannedMs: now + 6 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }], home, now)
equal(urgencyNow, "now", "one minute of slack after the walk is urgent")
equal(Model.urgency([{ id: "a", line: "T4", destination: "City", mode: "train", plannedMs: now + 30 * 60000, estimatedMs: 0, realtime: false, cancelled: false, infos: [] }], home, now), "calm", "plenty of time is calm")

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
assert(/^[0-9]{2}:[0-9]{2}$/.test(tripRows[0].arriveText) && /min$/.test(tripRows[0].travelText) && tripRows[0].changesText === "direct", "trip rows show arrival, travel time and changes")
assert(/^T4 · 4′ → [0-9]{2}:[0-9]{2}$/.test(Model.pillText(tripBoard, tripPlace, tripNow)), "pill shows the arrival for trips: " + Model.pillText(tripBoard, tripPlace, tripNow))
assert(Model.boardFromJourneys(journeys, Object.assign({}, tripPlace, { lines: ["T8"] }), tripNow).length === 0, "line filter applies to the first ride")
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
const legRows = Model.legRows(commuteBoard[0])
equal(legRows.map(r => r.kind), ["ride", "change", "ride"], "a transfer gap between adjacent rides becomes a change row")
equal([legRows[0].line, legRows[0].headsign, legRows[0].from, legRows[0].to, legRows[0].realtime], ["L3", "Circular Quay", "Surry Hills Light Rail", "Central Chalmers Street Light Rail", true], "first ride keeps its direction, endpoints and realtime state")
equal([legRows[1].minutes, legRows[1].from], [9, "Central Station"], "change row gives rounded gap and change stop")
equal([legRows[2].line, legRows[2].headsign, legRows[2].platform], ["M1", "Tallawong", "26"], "second ride keeps its own direction and platform")
equal(legRows[0].stopsText, "Surry Hills · Central Chalmers St", "leg rows expose the stop sequence")
equal(legRows[2].stopsText, "Central · Gadigal · Martin Place · Barangaroo · Victoria Cross · Crows Nest · … +1", "long stop sequences are bounded")
equal(Model.stopListText(["One", "Two", "Three"], 2), "One · Two · … +1", "stop list helper accepts strings and a custom bound")
assert(Object.keys(legRows[0]).sort().join(",") === ["alertTitle", "arriveText", "departText", "disruption", "from", "headsign", "kind", "line", "minutes", "mode", "platform", "realtime", "stopsText", "to"].sort().join(","), "leg rows have the documented shape")
const noStops = { legs: [Object.assign({}, multi[0].legs[0], { stops: [] })] }
equal(Model.legRows(noStops)[0].stopsText, "Surry Hills · Central Chalmers St", "ride without a stop sequence falls back to endpoints")
const withWalk = { legs: [multi[0].legs[0], Object.assign({}, multi[0].legs[0], { kind: "walk", mode: "walk", line: "", destination: "", platform: "", from: multi[0].legs[0].to, to: multi[0].legs[1].from, departMs: multi[0].legs[0].arriveMs, arriveMs: multi[0].legs[1].departMs, durationSec: 510, realtime: false, infos: [] }), multi[0].legs[1]] }
equal(Model.legRows(withWalk).map(r => r.kind), ["ride", "walk", "ride"], "an explicit walking leg suppresses the change pseudo-row")
assert(/^L[23] · 9′ → /.test(Model.pillText(Model.boardFromJourneys(multi, commute, commuteNow), commute, commuteNow)), "pill leads with the first leg and ends with the arrival")
const changeNotification = Model.notificationFor(commuteBoard, commute, multi[0].departMs - 4 * 60000, {})
assert(changeNotification && / · change at Central$/.test(changeNotification.body), "multi-leg trip notification names the change stop")
equal(Model.placeLabel(home), "From Home", "place without destination reads as an origin")
equal(Model.placeLabel(tripPlace), "Home → Wynyard", "trip label shows the destination's short name")
equal(Model.placeTooltip(commute), "Surry Hills Light Rail → Chatswood Station · 3 min walk", "place tooltip shows full stops and walk allocation")
equal(Model.placeTooltip(Object.assign({}, home, { walkMinutes: 0 })), "Sydenham Station", "zero walk is omitted from the place tooltip")
equal(Model.firstWord("Circular Quay Wharf, Sydney"), "Circular Quay", "short destination name")
assert(!Model.hasDestination(home) && Model.hasDestination(tripPlace), "hasDestination")
equal(Model.projectRow(board[0], home, now).arriveText, "", "plain departures have no arrival")

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

done("test_model")
