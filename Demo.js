.pragma library

function defaultPlace() {
  return { id: "demo-sydenham", name: "Sydenham", stopId: "204420", stopName: "Sydenham Station",
           destStopId: "200080", destStopName: "Wynyard Station", lines: [], destination: "",
           modes: ["train", "metro"], walkMinutes: 5, ssid: "" }
}
function info(id, title, priority, url) { return { id: id, title: title, priority: priority, type: "", url: url || "" } }
function departure(id, line, destination, platform, mode, plannedMs, estimatedMs, realtime, cancelled, infos) {
  return { id: id, tripId: id, line: line, lineName: line, destination: destination, platform: platform,
           mode: mode, plannedMs: plannedMs, estimatedMs: estimatedMs, realtime: realtime,
           cancelled: cancelled, infos: infos || [], stopName: "Sydenham Station" }
}
function board(now) {
  var at = typeof now === "number" ? now : Date.now(), m = 60000
  var disruption = info("demo-disruption", "T4 replacement buses may affect some services", "high", "https://transportnsw.info/alerts")
  var advisory = info("demo-advisory", "Extra services are running after tonight's event", "normal", "https://transportnsw.info/alerts")
  return [
    departure("demo-cancelled", "T4", "Bondi Junction", "6", "train", at + 8*m, at + 8*m, true, true, [disruption]),
    departure("demo-t4", "T4", "Bondi Junction", "6", "train", at + 13*m, at + 17*m, true, false, [disruption]),
    departure("demo-m1", "M1", "Tallawong", "1", "metro", at + 20*m, at + 20*m, true, false, []),
    departure("demo-t8", "T8", "City Circle via Airport", "4", "train", at + 29*m, 0, false, false, []),
    departure("demo-t4-2", "T4", "Waterfall", "3", "train", at + 38*m, at + 38*m, true, false, [advisory]),
    departure("demo-m1-2", "M1", "Tallawong", "1", "metro", at + 46*m, 0, false, false, []),
    departure("demo-t8-2", "T8", "Macarthur via Airport", "4", "train", at + 55*m, at + 55*m, true, false, []),
    departure("demo-t4-3", "T4", "Cronulla", "3", "train", at + 67*m, at + 68*m, true, false, [advisory])
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
  function ride(line, mode, platform, destination, depart, arrive, from, to, realtime) {
    return { kind: "ride", line: line, mode: mode, from: from || "Sydenham Station",
      to: to || "Wynyard Station", platform: platform, destination: destination,
      departMs: depart, arriveMs: arrive, durationSec: Math.round((arrive - depart) / 1000),
      distanceM: 0, realtime: realtime !== false, infos: [], stops: [] }
  }
  function direct(id, line, mode, platform, destination, departMin, arriveMin, realtime) {
    return { id: id, departMs: at + departMin*m, arriveMs: at + arriveMin*m,
      durationSec: (arriveMin - departMin)*60,
      legs: [ride(line, mode, platform, destination, at + departMin*m, at + arriveMin*m, "", "", realtime)] }
  }
  var first = { id: "demo-journey-t4", departMs: at + 6*m, arriveMs: at + 34*m, durationSec: 28*60,
    legs: [
      { kind: "walk", line: "", mode: "walk", from: "Current location", to: "Sydenham Station", platform: "", destination: "", departMs: at + 6*m, arriveMs: at + 12*m, durationSec: 6*60, distanceM: 450, realtime: false, infos: [], stops: [] },
      ride("T4", "train", "6", "Bondi Junction", at + 13*m, at + 34*m)
    ] }
  var change = { id: "demo-journey-change", departMs: at + 29*m, arriveMs: at + 57*m, durationSec: 28*60,
    legs: [
      ride("T4", "train", "6", "Bondi Junction", at + 29*m, at + 40*m, "Sydenham Station", "Central Station"),
      { kind: "walk", line: "", mode: "walk", from: "Central Station", to: "Central Metro", platform: "", destination: "", departMs: at + 40*m, arriveMs: at + 44*m, durationSec: 4*60, distanceM: 250, realtime: false, infos: [], stops: [] },
      ride("M1", "metro", "1", "Tallawong", at + 45*m, at + 57*m, "Central Metro", "Wynyard Station")
    ] }
  return [
    first,
    direct("demo-journey-m1", "M1", "metro", "1", "Tallawong", 18, 39),
    change,
    direct("demo-journey-t4-2", "T4", "train", "6", "Bondi Junction", 41, 63),
    direct("demo-journey-m1-2", "M1", "metro", "1", "Tallawong", 53, 74, false),
    direct("demo-journey-t4-3", "T4", "train", "6", "Bondi Junction", 66, 88)
  ]
}
