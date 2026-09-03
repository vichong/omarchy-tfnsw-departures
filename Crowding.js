.pragma library

// GTFS-Realtime occupancy without a protobuf library: a minimal walker over
// FeedMessage → entity(2) → vehicle(4) → { trip(1).trip_id(1), occupancy_status(9) }.
// Unknown fields are skipped; everything is bounded.

var MAX_ENTITIES = 20000
var STATUS = ["empty", "many", "few", "standing", "crushed", "full", "closed"]

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
var B64_INDEX = null

// base64 text → array of byte values (no Qt.atob dependency).
function fromBase64(text) {
  if (!B64_INDEX) {
    B64_INDEX = {}
    for (var c = 0; c < B64.length; c++) B64_INDEX[B64.charAt(c)] = c
  }
  var s = String(text || "").replace(/[^A-Za-z0-9+\/]/g, "")
  var out = []
  var bits = 0, value = 0
  for (var i = 0; i < s.length; i++) {
    value = (value << 6) | B64_INDEX[s.charAt(i)]
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out.push((value >> bits) & 0xff)
    }
  }
  return out
}

function readVarint(bytes, pos, end) {
  var result = 0, shift = 0
  while (pos < end) {
    var b = bytes[pos++]
    if (shift < 32) result += (b & 0x7f) * Math.pow(2, shift)
    shift += 7
    if (b < 0x80) return { value: result, pos: pos }
    if (shift > 63) break
  }
  return null
}

// Walk one message's fields between pos and end; calls onField(field, wire, value|{start,end}).
function walk(bytes, pos, end, onField) {
  while (pos < end) {
    var key = readVarint(bytes, pos, end)
    if (!key) return false
    pos = key.pos
    var field = Math.floor(key.value / 8), wire = key.value % 8
    if (wire === 0) {
      var v = readVarint(bytes, pos, end)
      if (!v) return false
      pos = v.pos
      if (onField(field, wire, v.value) === false) return true
    } else if (wire === 2) {
      var len = readVarint(bytes, pos, end)
      if (!len) return false
      pos = len.pos
      if (len.value > end - pos) return false
      if (onField(field, wire, { start: pos, end: pos + len.value }) === false) return true
      pos += len.value
    } else if (wire === 1) {
      pos += 8
    } else if (wire === 5) {
      pos += 4
    } else {
      return false
    }
  }
  return true
}

function readString(bytes, span) {
  var s = ""
  for (var i = span.start; i < span.end; i++) {
    var b = bytes[i]
    // trip ids are ASCII; anything else is replaced rather than decoded
    s += b >= 0x20 && b < 0x7f ? String.fromCharCode(b) : "?"
    if (s.length > 120) break
  }
  return s
}

// bytes → { tripId: statusName } for every vehicle carrying occupancy_status.
function parseOccupancy(bytes) {
  var result = {}
  var count = 0
  if (!bytes || !bytes.length) return result
  walk(bytes, 0, bytes.length, function(field, wire, value) {
    if (field !== 2 || wire !== 2) return
    if (++count > MAX_ENTITIES) return false
    var tripId = "", status = -1
    walk(bytes, value.start, value.end, function(f, w, v) {
      if (f !== 4 || w !== 2) return
      walk(bytes, v.start, v.end, function(vf, vw, vv) {
        if (vf === 1 && vw === 2) {
          walk(bytes, vv.start, vv.end, function(tf, tw, tv) {
            if (tf === 1 && tw === 2) tripId = readString(bytes, tv)
          })
        } else if (vf === 9 && vw === 0) {
          status = vv
        }
      })
    })
    if (tripId && status >= 0 && status < STATUS.length) result[tripId] = STATUS[status]
  })
  return result
}

// How many of the three people glyphs to fill, and the tooltip.
function glyphsFor(status) {
  switch (status) {
  case "empty": case "many": return 1
  case "few": return 2
  case "standing": case "crushed": case "full": return 3
  default: return 0
  }
}
function labelFor(status) {
  switch (status) {
  case "empty": case "many": return "Many seats available"
  case "few": return "Few seats available"
  case "standing": return "Standing room only"
  case "crushed": case "full": return "Full"
  case "closed": return "Not accepting passengers"
  default: return ""
  }
}
