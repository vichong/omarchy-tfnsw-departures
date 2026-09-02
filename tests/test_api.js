const { loadModule, fixture, assert, equal, done } = require("./helpers")
const Api = loadModule("Api.js")

// --- URLs
assert(Api.sameOrigin("https://API.transport.nsw.gov.au:443/v1/tp/x", Api.BASE_URL), "origin normalizes case and port")
assert(!Api.sameOrigin("https://api.transport.nsw.gov.au.evil.test/v1", Api.BASE_URL), "host prefix is not an origin match")
assert(!Api.sameOrigin("http://api.transport.nsw.gov.au/v1", Api.BASE_URL), "scheme is part of the origin")
equal(Api.query({ a: 1, b: "x y", c: "", d: null }), "?a=1&b=x%20y", "query skips empty values")

const sf = Api.stopFinderPath("Sydenham Station")
assert(sf.indexOf("/v1/tp/stop_finder?") === 0 && sf.indexOf("name_sf=Sydenham%20Station") > 0 && sf.indexOf("TfNSWSF=true") > 0, "stop finder path")
const dm = Api.departuresPath("204420", ["bus", "coach"])
assert(dm.indexOf("name_dm=204420") > 0 && dm.indexOf("exclMOT_5=1") > 0 && dm.indexOf("exclMOT_7=1") > 0, "departures path excludes modes")
assert(dm.indexOf("itdDate") === -1 && dm.indexOf("itdTime") === -1, "no explicit time: the API reads itdTime as Sydney local, not UTC")
assert(Api.departuresPath("204420", []).indexOf("excludedMeans") === -1, "no exclusions when list is empty")
const tp = Api.tripPath({ lat: -33.867509, lon: 151.207789 }, "200080", 3)
assert(tp.indexOf("type_origin=coord") > 0 && tp.indexOf("name_origin=151.207789%3A-33.867509%3AEPSG%3A4326") > 0, "coordinate origin")
assert(tp.indexOf("type_destination=stop&name_destination=200080") > 0 && tp.indexOf("calcNumberOfTrips=3") > 0, "trip destination and count")
assert(Api.tripPath("220510", "204420", 99).indexOf("calcNumberOfTrips=" + Api.MAX_JOURNEYS) > 0, "journey count is capped")
assert(Api.isStopId("204420") && !Api.isStopId("streetID:1:2") && !Api.isStopId(""), "stop id validation")

// --- modes
equal([Api.modeFor(1).id, Api.modeFor(2).id, Api.modeFor(9).id, Api.modeFor("5").id, Api.modeFor(42).id],
  ["train", "metro", "ferry", "bus", "other"], "product class to mode")
equal(Api.modeById("lightrail").letter, "L", "mode letter")
equal(Api.modeById("bogus").id, "other", "unknown mode id")
equal(Api.clip("x".repeat(140), 120), "x".repeat(120), "display strings are clipped to their cap")

// --- responses
equal(Api.parseResponse(401, "").kind, "credential", "401 is a credential error")
equal(Api.parseResponse(403, '{"ErrorDetails":{"message":"Account over rate limit"}}').kind, "ratelimit", "403 over quota is rate limit")
equal(Api.parseResponse(403, '{"ErrorDetails":{"message":"Invalid key"}}').kind, "credential", "403 otherwise is credential")
equal(Api.parseResponse(429, "").kind, "ratelimit", "429 is rate limit")
equal(Api.parseResponse(0, "").kind, "network", "status 0 is network")
equal(Api.parseResponse(500, "oops").kind, "network", "5xx is transient")
equal(Api.parseResponse(200, "<html>").kind, "protocol", "HTML 2xx body is a protocol error")
equal(Api.parseResponse(200, "[]").kind, "protocol", "array body is a protocol error")
const oversized = Api.parseResponse(200, "x".repeat(Api.MAX_RESPONSE_BYTES + 1))
equal(oversized.kind, "protocol", "oversized body is rejected before parsing")
const stopInvalid = Api.parseResponse(200, '{"systemMessages":[{"type":"error","module":"BROKER","code":-2000,"text":"stop invalid"}],"locations":[]}')
assert(stopInvalid.ok && Api.parseLocations(stopInvalid.data).length === 0, "stop invalid is an empty result, not an error")
const advisory = Api.parseResponse(200, '{"systemMessages":[{"type":"error","module":"BROKER","code":-8011,"text":""}],"locations":[{"id":"1","name":"x","type":"stop"}]}')
assert(advisory.ok, "an advisory system error next to a real payload is not a failure")
const otherError = Api.parseResponse(200, '{"systemMessages":[{"type":"error","code":-1,"text":"boom"}]}')
equal([otherError.ok, otherError.kind, otherError.error], [false, "api", "boom"], "other system errors surface")

// --- stop finder
const locations = Api.parseLocations(fixture("stop_finder_sydenham.json"))
const station = locations.filter(l => l.isStop)[0]
equal([station.id, station.shortName, station.modes], ["204420", "Sydenham Station", ["train", "metro", "bus"]], "station parsed with modes")
assert(station.isBest && Math.abs(station.lat + 33.914) < 0.01 && Math.abs(station.lon - 151.166) < 0.01, "station coords and best flag")
const address = Api.parseLocations(fixture("stop_finder_address.json"))[0]
equal([address.type, address.isStop, address.name], ["singlehouse", false, "1 Martin Pl, Sydney"], "street address resolves with coordinates")
assert(address.lat !== null && address.lon !== null, "address has coordinates")

// --- departures
const deps = Api.parseDepartures(fixture("departure_mon_sydenham.json"))
assert(deps.length > 20 && deps.length <= Api.MAX_STOP_EVENTS, "departure board parsed")
const first = deps[0]
equal([first.line, first.destination, first.platform, first.mode], ["T4", "Cronulla via Kogarah", "6", "train"], "first departure fields")
assert(first.realtime && first.estimatedMs > 0 && first.plannedMs > 0 && first.tripId !== "", "first departure is realtime with a trip id")
equal(first.infos[0].id, "ems-76903", "alerts ride along with the stop event")
assert(deps.every((d, i) => i === 0 || Api.effectiveMs(deps[i - 1]) <= Api.effectiveMs(d)), "departures sorted by effective time")
const metro = deps.filter(d => d.mode === "metro")[0]
equal([metro.line, metro.destination, metro.platform], ["M1", "Tallawong", "1"], "metro departure")
const scheduledOnly = deps.filter(d => !d.realtime)[0]
assert(scheduledOnly && scheduledOnly.estimatedMs === 0 && scheduledOnly.plannedMs > 0, "timetable-only departure keeps planned time")
equal(Api.shortLine({ number: "T4 Eastern Suburbs & Illawarra Line" }), "T4", "short line from the long number")
equal(Api.shortLine({ disassembledName: "358", number: "358" }), "358", "bus route short line")
equal(Api.platformOf({ properties: { platform: "SYD6" } }), "6", "platform from station code")
equal(Api.platformOf({ properties: { platformName: "Platform 12" } }), "12", "platform from name")
equal(Api.platformOf({ properties: { platform: "E" } }), "E", "bus stand letters survive")
equal(Api.platformOf({ properties: { platform: "Surry Hills Light Rail" } }), "", "a stop name echoed as platform is not a platform")

// --- multi-leg journey: light rail → metro with a change at Central
const multi = Api.parseJourneys(fixture("trip_surry_hills_to_chatswood.json"))
assert(multi.length >= 2, "several journeys parsed")
const legs = multi[0].legs.filter(l => l.kind === "ride")
equal([legs.length, legs[0].mode, legs[0].line.charAt(0), legs[1].line, legs[1].platform, legs[0].platform], [2, "lightrail", "L", "M1", "26", ""], "two ride legs with modes, lines and platforms")
assert(legs[0].arriveMs < legs[1].departMs && legs[1].departMs - legs[0].arriveMs < 15 * 60000, "the change at Central is a short gap between legs")

// --- journeys
const journeys = Api.parseJourneys(fixture("trip_sydenham_to_wynyard.json"))
equal(journeys.length, 1, "one journey in the trimmed fixture")
const ride = journeys[0].legs[0]
equal([ride.kind, ride.line, ride.from, ride.to, ride.platform, ride.stops.length], ["ride", "T4", "Sydenham Station", "Wynyard Station", "3", 9], "ride leg with full stop sequence")
assert(ride.stops[3].name === "Redfern Station" && ride.stops[3].departMs > 0, "intermediate stops carry realtime times")
assert(journeys[0].durationSec > 0 && journeys[0].departMs < journeys[0].arriveMs, "journey timing")
const walkOnly = Api.parseJourneys(fixture("trip_address_to_wynyard.json"))
equal([walkOnly[0].legs[0].kind, walkOnly[0].legs[0].distanceM, walkOnly[0].legs[0].durationSec], ["walk", 254, 228], "walking leg from an address")

done("test_api")
