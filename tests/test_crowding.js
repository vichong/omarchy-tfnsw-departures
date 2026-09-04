const { loadModule, assert, equal, done } = require("./helpers")
const Crowding = loadModule("Crowding.js")

// Hand-built FeedMessage: two entities with vehicle{trip{trip_id}, occupancy_status}, one without status.
function varint(n) { const out = []; do { let b = n & 0x7f; n = Math.floor(n / 128); if (n) b |= 0x80; out.push(b) } while (n); return out }
function bytesOf(s) { return Array.from(Buffer.from(s, "utf8")) }
function field(num, wire, payload) { return varint(num * 8 + wire).concat(wire === 2 ? varint(payload.length).concat(payload) : varint(payload)) }
function trip(id) { return field(1, 2, bytesOf(id)) }
function vehicle(id, status) { let v = field(1, 2, trip(id)); if (status !== undefined) v = v.concat(field(9, 0, status)); return v }
function entity(id, vehicleBytes) { return field(1, 2, bytesOf(id)).concat(field(4, 2, vehicleBytes)) }
const header = field(1, 2, field(1, 2, bytesOf("2.0")).concat(field(3, 0, 1788400000)))
const feed = header
  .concat(field(2, 2, entity("a", vehicle("1234.trip", 3))))
  .concat(field(2, 2, entity("b", vehicle("5678.trip", 1))))
  .concat(field(2, 2, entity("c", vehicle("9999.trip"))))
  .concat(field(7, 1, [1, 2, 3, 4, 5, 6, 7, 8]))   // unknown 64-bit field is skipped
const b64 = Buffer.from(feed).toString("base64")

const bytes = Crowding.fromBase64(b64)
equal(bytes.length, feed.length, "base64 round-trips every byte")
equal(bytes.slice(0, 8), feed.slice(0, 8), "first bytes match")
const occ = Crowding.parseOccupancy(bytes)
equal(occ, { "1234.trip": "standing", "5678.trip": "many" }, "occupancy keyed by trip id; missing status skipped")
equal(Crowding.parseOccupancy([]), {}, "empty feed")
equal(Crowding.parseOccupancy([0xff, 0xff, 0xff]), {}, "garbage does not throw")
const capped = Crowding.fromBase64("A".repeat(Crowding.MAX_ENCODED_BASE64 + 64))
equal(capped.length, Crowding.MAX_DECODED_BYTES, "base64 decoding stops at the decoded-byte budget")
const fieldBudget = { fields: Crowding.MAX_TOTAL_FIELDS, hit: false }
assert(Crowding.walk([8, 1], 0, 2, function() { throw new Error("field callback ran past budget") }, fieldBudget, 0)
  && fieldBudget.hit, "protobuf walker stops when the total-field budget is reached")
const depthBudget = { fields: 0, hit: false }
assert(Crowding.walk([8, 1], 0, 2, function() { throw new Error("field callback ran past depth") }, depthBudget,
  Crowding.MAX_NESTING_DEPTH + 1) && depthBudget.hit, "protobuf walker stops beyond the nesting-depth budget")
equal([Crowding.glyphsFor("many"), Crowding.glyphsFor("few"), Crowding.glyphsFor("standing"), Crowding.glyphsFor("")], [1, 2, 3, 0], "glyph fill counts")
equal(Crowding.labelFor("few"), "Few seats available", "labels")

done("test_crowding")
