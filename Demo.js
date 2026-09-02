.pragma library

function defaultPlace() {
  return { id: "demo-sydenham", name: "Sydenham", stopId: "204420", stopName: "Sydenham Station",
           lines: [], destination: "", modes: ["train", "metro"], walkMinutes: 5, ssid: "" }
}
function info(id, title, priority, url) { return { id: id, title: title, priority: priority, type: "", url: url || "" } }
function departure(id, line, destination, platform, mode, plannedMs, estimatedMs, realtime, cancelled, infos) {
  return { id: id, tripId: id, line: line, lineName: line, destination: destination, platform: platform,
           mode: mode, plannedMs: plannedMs, estimatedMs: estimatedMs, realtime: realtime,
           cancelled: cancelled, infos: infos || [], stopName: "Sydenham Station" }
}
function board(now) {
  var at = typeof now === "number" ? now : Date.now(), m = 60000
  var disruption = info("demo-alert", "T4 replacement buses may affect some services", "high", "https://transportnsw.info/alerts")
  return [
    departure("demo-cancelled", "T4", "Bondi Junction", "6", "train", at + 8*m, 0, false, true, [disruption]),
    departure("demo-t4", "T4", "Bondi Junction", "6", "train", at + 14*m, at + 17*m, true, false, [disruption]),
    departure("demo-m1", "M1", "Tallawong", "1", "metro", at + 20*m, at + 20*m, true, false, []),
    departure("demo-t8", "T8", "City Circle via Airport", "4", "train", at + 29*m, 0, false, false, []),
    departure("demo-t4-2", "T4", "Waterfall", "3", "train", at + 38*m, at + 38*m, true, false, [])
  ]
}
function locations(query) {
  var all = [
    { id: "204420", name: "Sydenham Station, Railway Pde", shortName: "Sydenham Station", type: "stop", lat: -33.914, lon: 151.166, modes: ["train","metro","bus"], isStop: true, isBest: true },
    { id: "200080", name: "Wynyard Station, Sydney", shortName: "Wynyard Station", type: "stop", lat: -33.866, lon: 151.206, modes: ["train","bus"], isStop: true, isBest: false },
    { id: "200020", name: "Circular Quay Station, Sydney", shortName: "Circular Quay", type: "stop", lat: -33.861, lon: 151.211, modes: ["train","ferry","lightrail"], isStop: true, isBest: false }
  ]
  var needle = String(query || "").trim().toLowerCase()
  return needle ? all.filter(function(x) { return x.name.toLowerCase().indexOf(needle) !== -1 || x.shortName.toLowerCase().indexOf(needle) !== -1 }) : []
}
function journeys(now) {
  var at = typeof now === "number" ? now : Date.now(), m = 60000
  return [{ id: "demo-journey", departMs: at + 6*m, arriveMs: at + 34*m, durationSec: 28*60,
    legs: [
      { kind: "walk", line: "", mode: "walk", from: "Current location", to: "Sydenham Station", platform: "", destination: "", departMs: at + 6*m, arriveMs: at + 12*m, durationSec: 6*60, distanceM: 450, realtime: false, infos: [], stops: [] },
      { kind: "ride", line: "T4", mode: "train", from: "Sydenham Station", to: "Wynyard Station", platform: "6", destination: "Bondi Junction", departMs: at + 13*m, arriveMs: at + 34*m, durationSec: 21*60, distanceM: 0, realtime: true, infos: [], stops: [] }
    ]
  }]
}
