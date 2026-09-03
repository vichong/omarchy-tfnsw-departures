import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api
import "ConfigStore.js" as ConfigStore
import "Model.js" as Model

// Full-screen settings and journey planner summoned by the shell.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null
  readonly property string version: manifest && manifest.version ? String(manifest.version) : "0.8.1"

  property bool opened: false
  property string tab: "settings"

  // Local until Connect, so a half-typed key never reaches the keyring.
  property string keyDraft: ""

  // Place editor state. Search state is separate so a selected stop is not
  // mistaken for a query with no matches.
  property string selectedPlaceId: ""
  property var stopResults: []
  property var selectedStop: null
  property string placeSearchText: ""
  property bool placeSearchComplete: false
  property var destinationResults: []
  property string destinationSearchText: ""
  property bool destinationSearchComplete: false

  // New-trip state, revealed top-down as each choice becomes available.
  property var newTripResults: []
  property string newTripSearchText: ""
  property var newTripLocation: null
  property var nearbyStops: []
  property bool nearbyExpanded: false
  property bool nearbyFallback: false
  // The chosen origin stop had nothing within the horizon: replanned from the address.
  property bool originFallback: false
  property string originFallbackStop: ""
  // Destination chips: the planner's own end stop by default; a click overrides it.
  property bool destinationOverride: false
  property var newTripOrigin: null
  property var newTripDestination: null
  property var newTripDestinationStops: []
  property var newTripDestinationStop: null
  property bool destinationNearbyExpanded: false
  property var newTripDestinationOptions: []
  property bool otherDestinationOpen: false
  property var otherDestinationResults: []
  property string otherDestinationSearchText: ""
  property string expandedJourneyId: ""
  property var lastJourneys: []
  property string placeName: ""
  property string placeStopId: ""
  property string placeStopName: ""
  property string placeDestStopId: ""
  property string placeDestStopName: ""
  property string placeDestAddress: ""
  property var placeDestLat: null
  property var placeDestLon: null
  property string placeLines: ""
  property string placeDestination: ""
  property var placeModes: []
  property int placeWalk: 0
  property string placeSsid: ""
  property bool placeFilterOpen: false
  // The kit's controls have different natural heights. Measure one bordered
  // button once so fields, dropdowns and adjacent buttons line up.
  readonly property int controlHeight: Style.space(30)
  readonly property int chipHeight: Style.space(26)
  readonly property string family: Style.font.family
  readonly property color background: Color.background
  readonly property color foreground: Color.foreground
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property var borderSpec: Border.flat(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.40), Style.space(1))

  function open(payloadJson) {
    opened = true
    keyDraft = ""
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {
      }
      tab = payload.tab === "newtrip" || payload.tab === "here" ? "newtrip" : "settings"
    } catch (e) {
      tab = "settings"
    }
    if (service && !service.configured)
      tab = "settings"

    if (service) {
      selectedPlaceId = service.activePlace ? service.activePlace.id : ""
      loadPlace(selectedPlaceId)
      newTripDestinationOptions = Model.destinationOptions(service.effectivePlaces)
      service.setNewTripOpen(tab === "newtrip")
    }
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      if (root.tab === "newtrip" && paneLoader.item && typeof paneLoader.item.focusField === "function")
        paneLoader.item.focusField()
    })
  }

  function close() {
    opened = false
    if (service)
      service.setNewTripOpen(false)
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.vichong.tfnsw-departures")
  }

  function placeById(id) {
    if (!service)
      return null

    for (var i = 0; i < service.places.length; i++) if (service.places[i].id === id) {
      return service.places[i]
    }
    return null
  }

  function loadPlace(id) {
    placeFilterOpen = false
    var p = placeById(id)
    placeSearchText = ""
    placeSearchComplete = false
    stopResults = []
    destinationSearchText = ""
    destinationSearchComplete = false
    destinationResults = []
    if (!p) {
      placeName = ""
      placeStopId = ""
      placeStopName = ""
      placeDestStopId = ""
      placeDestStopName = ""
      placeDestAddress = ""
      placeDestLat = null
      placeDestLon = null
      placeLines = ""
      placeDestination = ""
      placeModes = []
      placeWalk = 0
      placeSsid = ""
      selectedStop = null
      return
    }
    placeName = p.name
    placeStopId = p.stopId
    placeStopName = p.stopName
    placeDestStopId = p.destStopId || ""
    placeDestStopName = p.destStopName || ""
    placeDestAddress = p.destAddress || ""
    placeDestLat = p.destLat
    placeDestLon = p.destLon
    placeLines = p.lines.join(", ")
    placeDestination = p.destination
    placeModes = p.modes.slice()
    placeWalk = p.walkMinutes
    placeSsid = p.ssid
    selectedStop = {
      "id": p.stopId,
      "shortName": p.stopName,
      "name": p.stopName,
      "isStop": true,
      "modes": p.modes
    }
  }

  function addPlaceDraft() {
    selectedPlaceId = ConfigStore.newPlaceId(service ? service.places : [])
    loadPlace("")
  }

  function prefillPlaceDraft(place) {
    if (!service || !place)
      return

    selectedPlaceId = ConfigStore.newPlaceId(service.places)
    loadPlace("")
    placeName = place.name || "New trip"
    placeStopId = String(place.stopId || "")
    placeStopName = String(place.stopName || "")
    placeDestStopId = String(place.destStopId || "")
    placeDestStopName = String(place.destStopName || "")
    placeDestAddress = String(place.destAddress || "")
    placeDestLat = place.destLat
    placeDestLon = place.destLon
    placeLines = ""
    placeDestination = ""
    placeModes = []
    placeWalk = Math.max(0, Math.round(Number(place.walkMinutes) || 0))
    placeSsid = ""
    selectedStop = {
      "id": placeStopId,
      "name": placeStopName,
      "shortName": Model.displayStopName(placeStopName),
      "isStop": true,
      "modes": []
    }
  }

  function cancelPlaceDraft() {
    selectedPlaceId = ""
    loadPlace("")
  }

  function placeCards() {
    var list = service ? service.places.slice() : []
    if (selectedPlaceId && !placeById(selectedPlaceId))
      list.push({ "id": selectedPlaceId, "name": "New place", "stopName": "", "destStopName": "", "lines": [], "modes": [], "walkMinutes": 0 })
    return list
  }

  function lineDrafts() {
    return placeLines.split(",").map(function(line) {
      return Model.normalizeLine(line)
    }).filter(function(line, index, lines) {
      return line !== "" && lines.indexOf(line) === index
    })
  }

  function addLineDraft(line) {
    var value = Model.normalizeLine(line)
    if (!value)
      return

    var lines = lineDrafts()
    if (lines.indexOf(value) === -1)
      lines.push(value)
    placeLines = lines.join(", ")
  }

  function removeLineDraft(line) {
    placeLines = lineDrafts().filter(function(value) {
      return value !== line
    }).join(", ")
  }

  function toggleModeDraft(mode) {
    var modes = placeModes.slice()
    var index = modes.indexOf(mode)
    if (index === -1)
      modes.push(mode)
    else
      modes.splice(index, 1)
    placeModes = modes
  }

  function filterSummary(lines, modes, destination) {
    var lineCount = lines && lines.length ? lines.length : 0
    var modeCount = modes && modes.length ? modes.length : 0
    var destinationSet = String(destination || "").trim() !== ""
    if (!lineCount && !modeCount && !destinationSet)
      return "All services"

    var lineText = lineCount ? lineCount + (lineCount === 1 ? " line" : " lines") : "all lines"
    var modeText = modeCount ? modeCount + (modeCount === 1 ? " mode" : " modes") : "all modes"
    return lineText + " · " + modeText
  }

  function placeSummary(place) {
    if (!place)
      return "All services"

    var parts = []
    var from = Model.boardStopName(place.stopName)
    if (from) parts.push(from + (place.destStopName
      ? " → " + Model.boardStopName(place.destAddress || place.destStopName) : ""))
    if (place.walkMinutes > 0) parts.push(place.walkMinutes + " min walk")
    var filter = filterSummary(place.lines || [], place.modes || [], place.destination)
    parts.push(place.lines && place.lines.length ? place.lines.join(", ") : filter)
    return parts.join(" · ")
  }

  function savePlaceDraft() {
    if (!service || !Api.isStopId(placeStopId))
      return

    var item = {
      "id": selectedPlaceId || ConfigStore.newPlaceId(service.places),
      "name": placeName || placeStopName || "Place",
      "stopId": placeStopId,
      "stopName": placeStopName,
      "destStopId": Api.isStopId(placeDestStopId) && placeDestStopId !== placeStopId ? placeDestStopId : "",
      "destStopName": Api.isStopId(placeDestStopId) && placeDestStopId !== placeStopId ? placeDestStopName : "",
      "destAddress": placeDestAddress,
      "destLat": placeDestLat,
      "destLon": placeDestLon,
      "lines": placeLines.split(","),
      "destination": placeDestination,
      "modes": placeModes,
      "walkMinutes": placeWalk,
      "ssid": placeSsid
    }
    var list = service.places.slice(), replaced = false
    for (var i = 0; i < list.length; i++) if (list[i].id === item.id) {
      list[i] = item
      replaced = true
    }
    if (!replaced && list.length < ConfigStore.MAX_PLACES)
      list.push(item)

    selectedPlaceId = item.id
    service.saveConfig({
      "places": list,
      "activePlaceId": item.id
    })
    loadPlace(item.id)
  }

  function removePlace() {
    if (!service || !selectedPlaceId)
      return

    var list = service.places.filter(function(p) {
      return p.id !== selectedPlaceId
    })
    selectedPlaceId = list.length ? list[0].id : ""
    service.saveConfig({
      "places": list,
      "activePlaceId": selectedPlaceId
    })
    loadPlace(selectedPlaceId)
  }

  function pickStop(loc) {
    if (service)
      service.searchStops("", function() {})

    selectedStop = loc
    placeStopId = loc.id
    placeStopName = loc.name
    if (placeDestStopId === placeStopId)
      clearDestination()

    placeSearchText = ""
    placeSearchComplete = false
    stopResults = []
  }

  function pickDestination(loc) {
    if (service)
      service.searchStops("", function() {})

    if (loc.isStop) {
      placeDestStopId = loc.id
      placeDestStopName = loc.name
      placeDestAddress = ""
      placeDestLat = null
      placeDestLon = null
    } else {
      placeDestAddress = loc.name
      placeDestLat = loc.lat
      placeDestLon = loc.lon
      placeDestStopId = ""
      placeDestStopName = ""
      var local = Model.nearestStops(service.stops, loc.lat, loc.lon, 8, 3000)
      service.nearbyStops(loc.lat, loc.lon, function(apiStops) {
        if (root.placeDestAddress !== loc.name)
          return
        var merged = Model.mergeNearby(local, apiStops)
        if (merged.length) {
          root.placeDestStopId = merged[0].id
          root.placeDestStopName = merged[0].name
        }
      }, "here")
    }
    destinationSearchText = ""
    destinationSearchComplete = false
    destinationResults = []
  }

  function clearDestination() {
    if (service)
      service.searchStops("", function() {})

    placeDestStopId = ""
    placeDestStopName = ""
    placeDestAddress = ""
    placeDestLat = null
    placeDestLon = null
    destinationSearchText = ""
    destinationSearchComplete = false
    destinationResults = []
  }

  function mergedSearchResults(local, remote, stopsOnly, excludedId) {
    var merged = local.slice()
    var seen = {}
    for (var i = 0; i < local.length; i++) seen[String(local[i].id)] = true
    var more = []
    var list = Array.isArray(remote) ? remote : []
    for (var r = 0; r < list.length; r++) {
      var item = list[r]
      if (!item || (stopsOnly && !item.isStop) || String(item.id) === String(excludedId || "")
          || seen[String(item.id)]) continue
      seen[String(item.id)] = true
      more.push(item)
    }
    if (more.length)
      merged = merged.concat([{ "isDivider": true, "type": "divider", "name": "More" }], more)
    return merged
  }

  function firstSearchResult(results) {
    var list = Array.isArray(results) ? results : []
    for (var i = 0; i < list.length; i++) if (list[i] && !list[i].isDivider)
      return list[i]
    return null
  }

  function searchResultText(item) {
    if (!item)
      return ""

    // Addresses keep their suburb ("Chatsworth St, Croydon"); stops drop the suffix.
    var name = item.isStop ? Model.displayStopName(item.name) : String(item.name || item.shortName || "")
    var modes = item.modes && isFinite(item.modes.length) ? item.modes : []
    var glyphs = []
    for (var i = 0; i < modes.length; i++) glyphs.push(Model.glyphFor(String(modes[i])))
    if (glyphs.length)
      return name + "  ·  " + glyphs.join(" ")
    return name + (item.isStop ? "  ·  stop" : "  ·  address")
  }

  function searchDestinationStops(text) {
    if (!service)
      return

    var query = String(text || "").trim()
    placeDestAddress = ""
    placeDestLat = null
    placeDestLon = null
    placeDestStopName = String(text || "")
    destinationSearchText = query
    var local = Model.matchStops(service.stops, query).filter(function(x) {
      return String(x.id) !== String(root.placeStopId)
    })
    destinationResults = local
    destinationSearchComplete = query.length < 3
    if (query.length < 3) {
      service.searchStops("", function() {})
      return
    }
    service.searchStops(query, function(results) {
      if (query !== root.destinationSearchText)
        return

      root.destinationResults = root.mergedSearchResults(local, results, false, root.placeStopId)
      root.destinationSearchComplete = true
    })
  }

  function searchPlaceStops(text) {
    if (!service)
      return

    var query = String(text || "").trim()
    placeStopName = String(text || "")
    placeSearchText = query
    var local = Model.matchStops(service.stops, query)
    stopResults = local
    placeSearchComplete = query.length < 3
    if (query.length < 3) {
      service.searchStops("", function() {})
      return
    }
    service.searchStops(query, function(results) {
      if (query !== root.placeSearchText)
        return

      root.stopResults = root.mergedSearchResults(local, results, true, "")
      root.placeSearchComplete = true
    })
  }

  function searchNewTrip(text) {
    if (!service)
      return

    var query = String(text || "").trim()
    newTripSearchText = String(text || "")
    var local = Model.matchStops(service.stops, query)
    newTripResults = local
    if (query.length < 3) {
      service.searchStops("", function() {})
      return
    }
    service.searchStops(query, function(results) {
      if (query !== String(root.newTripSearchText || "").trim())
        return

      root.newTripResults = root.mergedSearchResults(local, results, false, "")
    })
  }

  function defaultNewTripDestination() {
    if (!service || !service.activePlace)
      return null

    var place = service.activePlace
    var wanted = place.destStopId || place.stopId
    for (var i = 0; i < newTripDestinationOptions.length; i++)
      if (String(newTripDestinationOptions[i].id) === String(wanted)) return newTripDestinationOptions[i]
    return null
  }

  function pickNewTripLocation(loc) {
    if (service)
      service.searchStops("", function() {})

    newTripLocation = loc
    newTripSearchText = ""
    newTripResults = []
    nearbyExpanded = false
    nearbyFallback = false
    originFallback = false
    nearbyStops = loc.isStop ? [] : Model.nearestStops(service.stops, loc.lat, loc.lon, 8, 3000)
    newTripOrigin = loc.isStop ? loc : (nearbyStops.length ? nearbyStops[0] : null)
    newTripDestinationOptions = Model.destinationOptions(service.effectivePlaces)
    newTripDestination = defaultNewTripDestination()
    newTripDestinationStop = newTripDestination
    newTripDestinationStops = []
    otherDestinationOpen = false
    otherDestinationResults = []
    expandedJourneyId = ""
    lastJourneys = []
    if (loc.isStop) {
      planNewTrip()
      return
    }
    var local = nearbyStops.slice()
    service.nearbyStops(loc.lat, loc.lon, function(apiStops) {
      if (root.newTripLocation !== loc)
        return
      root.nearbyStops = Model.mergeNearby(local, apiStops)
      root.newTripOrigin = root.nearbyStops.length ? root.nearbyStops[0] : loc
      root.nearbyFallback = root.nearbyStops.length === 0
      root.planNewTrip()
    }, "origin")
    if (newTripOrigin)
      planNewTrip()
  }

  function clearNewTripLocation() {
    newTripLocation = null
    nearbyStops = []
    nearbyExpanded = false
    nearbyFallback = false
    originFallback = false
    newTripOrigin = null
    newTripDestination = null
    newTripDestinationStops = []
    newTripDestinationStop = null
    destinationNearbyExpanded = false
    otherDestinationOpen = false
    lastJourneys = []
    expandedJourneyId = ""
    if (service) {
      service.journeyRows.clear()
      service.journeyBoard = []
    }
    Qt.callLater(function() {
      if (paneLoader.item && typeof paneLoader.item.focusField === "function") paneLoader.item.focusField()
    })
  }

  function selectNearbyStop(stop) {
    originFallback = false
    newTripOrigin = stop
    planNewTrip()
  }

  // Mode pictogram in front of a nearby-stop chip: station, light rail, wharf or bus.
  function chipGlyph(stop) {
    var modes = stop && stop.modes && isFinite(stop.modes.length) ? stop.modes : []
    var mode = modes.length ? String(modes[0]) : "bus"
    return Model.glyphFor(mode) + "  "
  }

  function selectDestinationStop(stop) {
    newTripDestinationStop = stop
    destinationOverride = true
    planNewTrip()
  }

  // Where the planner's first journey actually ends and how far is left on foot.
  function actualEndStop(journeys) {
    if (!journeys.length || !journeys[0].legs)
      return null
    var legs = journeys[0].legs
    var ride = null
    for (var i = legs.length - 1; i >= 0; i--) if (legs[i].kind === "ride") {
      ride = legs[i]
      break
    }
    if (!ride || !Api.isStopId(ride.toId)) return null
    return { "id": String(ride.toId), "name": String(ride.to || ""), "isStop": true,
             "walkMinutes": Model.finalWalkMinutes(journeys[0]), "modes": [ride.mode] }
  }

  function chooseNewTripDestination(value) {
    if (value === "search") {
      otherDestinationOpen = true
      newTripDestination = null
      newTripDestinationStop = null
      newTripDestinationStops = []
      lastJourneys = []
      if (service) service.journeyRows.clear()
      return
    }
    otherDestinationOpen = false
    destinationNearbyExpanded = false
    for (var i = 0; i < newTripDestinationOptions.length; i++) if (String(newTripDestinationOptions[i].id) === String(value)) {
      newTripDestination = newTripDestinationOptions[i]
      newTripDestinationStop = newTripDestination
      newTripDestinationStops = []
      break
    }
    planNewTrip()
  }

  function searchOtherDestination(text) {
    if (!service)
      return

    var query = String(text || "").trim()
    otherDestinationSearchText = String(text || "")
    var local = Model.matchStops(service.stops, query).filter(function(x) {
      return !root.newTripOrigin || String(x.id) !== String(root.newTripOrigin.id)
    })
    otherDestinationResults = local
    if (query.length < 3) {
      service.searchStops("", function() {})
      return
    }
    service.searchStops(query, function(results) {
      if (query !== String(root.otherDestinationSearchText || "").trim())
        return
      root.otherDestinationResults = root.mergedSearchResults(local, results, false,
        root.newTripOrigin ? root.newTripOrigin.id : "")
    })
  }

  function pickOtherDestination(stop) {
    if (service) service.searchStops("", function() {})
    newTripDestination = stop
    otherDestinationSearchText = ""
    otherDestinationResults = []
    otherDestinationOpen = false
    newTripDestinationStops = []
    destinationNearbyExpanded = false
    destinationOverride = false
    if (stop.isStop) {
      newTripDestinationStop = stop
      planNewTrip()
      return
    }
    newTripDestinationStop = null
    var local = Model.nearestStops(service.stops, stop.lat, stop.lon, 8, 3000)
    // Show the bundled stations at once; bus stops join when the lookup returns.
    newTripDestinationStops = local
    service.nearbyStops(stop.lat, stop.lon, function(apiStops) {
      if (root.newTripDestination !== stop)
        return
      root.newTripDestinationStops = Model.mergeNearby(local, apiStops)
      root.newTripDestinationStop = root.newTripDestinationStops.length ? root.newTripDestinationStops[0] : null
      root.planNewTrip()
    }, "destination")
    planNewTrip()
  }

  function actualFirstStop(journeys) {
    if (!journeys.length || !journeys[0].legs)
      return null
    var ride = null
    for (var i = 0; i < journeys[0].legs.length; i++) if (journeys[0].legs[i].kind === "ride") {
      ride = journeys[0].legs[i]
      break
    }
    if (!ride || !Api.isStopId(ride.fromId)) return null
    var walk = journeys[0].legs[0].kind === "walk"
      ? Math.max(0, Math.round(Number(journeys[0].legs[0].durationSec || 0) / 60)) : 0
    return { "id": ride.fromId, "name": ride.from, "shortName": Model.displayStopName(ride.from),
      "isStop": true, "type": "stop", "modes": [], "metres": walk * 80,
      "distanceMetres": walk * 80, "walkMinutes": walk }
  }

  function actualLastStop(journeys) {
    if (!journeys.length || !journeys[0].legs)
      return null
    var legs = journeys[0].legs
    var ride = null
    for (var i = legs.length - 1; i >= 0; i--) if (legs[i].kind === "ride") {
      ride = legs[i]
      break
    }
    if (!ride || !Api.isStopId(ride.toId)) return null
    var walk = legs.length && legs[legs.length - 1].kind === "walk"
      ? Math.max(0, Math.round(Number(legs[legs.length - 1].durationSec || 0) / 60)) : 0
    return { "id": ride.toId, "name": ride.to, "shortName": Model.displayStopName(ride.to),
      "isStop": true, "type": "stop", "modes": [], "metres": walk * 80,
      "distanceMetres": walk * 80, "walkMinutes": walk }
  }

  // Walk from the address to the chosen nearby stop (distance estimate);
  // zero when the start is itself a stop.
  readonly property int newTripWalk: newTripLocation && !newTripLocation.isStop && newTripOrigin
    ? Math.max(0, Math.round(Number(newTripOrigin.walkMinutes) || 0)) : 0

  function planNewTrip() {
    if (!service || !newTripLocation || !newTripOrigin || !newTripDestination)
      return
    expandedJourneyId = ""
    // Plan from the chosen stop so the chips mean what they say; the address
    // only decides the walk estimate.
    var origin = (nearbyFallback || originFallback) ? newTripLocation
      : { "isStop": true, "id": String(newTripOrigin.id), "name": String(newTripOrigin.name || "") }
    var selectedDestination = newTripDestination
    var selectedLocation = newTripLocation
    // An address destination is planned to the chosen arrive-via stop and the
    // walk from there to the door is appended, so the board ends where the
    // chip says it does.
    // Address destination: by default the planner picks the end stop and the
    // final walk (planned to the coordinate) and the chips show that choice;
    // a clicked chip overrides it (planned to that stop, walk appended).
    var toAddress = !newTripDestination.isStop
    var override = toAddress && destinationOverride && newTripDestinationStop
    var destination = override
      ? { "isStop": true, "id": String(newTripDestinationStop.id), "name": String(newTripDestinationStop.name || "") }
      : newTripDestination
    var endWalk = override ? Number(newTripDestinationStop.walkMinutes || 0) : 0
    var endWalkTo = override ? Model.boardStopName(newTripDestination.name) : ""
    service.planFrom(origin, destination, function(journeys) {
      if (root.newTripDestination !== selectedDestination || root.newTripLocation !== selectedLocation)
        return
      root.lastJourneys = journeys
      // Nothing catchable from the chosen stop (e.g. a bus route that has
      // finished for the day): plan from the address once and say so.
      if (root.service.journeyRows.count === 0 && !root.nearbyFallback && !root.originFallback
          && root.newTripLocation && !root.newTripLocation.isStop && origin.isStop) {
        root.originFallbackStop = root.newTripOrigin ? Model.boardStopName(root.newTripOrigin.name) : ""
        root.originFallback = true
        root.planNewTrip()
        return
      }
      if (toAddress && !root.destinationOverride) {
        var end = root.actualEndStop(journeys)
        if (end) {
          root.newTripDestinationStop = end
          var present = false
          for (var d = 0; d < root.newTripDestinationStops.length; d++)
            if (String(root.newTripDestinationStops[d].id) === String(end.id)) present = true
          if (!present)
            root.newTripDestinationStops = [end].concat(root.newTripDestinationStops)
        }
      }
      if ((root.nearbyFallback && root.nearbyStops.length === 0) || root.originFallback) {
        var first = root.actualFirstStop(journeys)
        if (first) {
          root.nearbyStops = [first]
          root.newTripOrigin = first
        }
      }
      if (!root.newTripDestination.isStop && root.newTripDestinationStops.length === 0) {
        var last = root.actualLastStop(journeys)
        if (last) {
          root.newTripDestinationStops = [last]
          root.newTripDestinationStop = last
        }
      }
    }, newTripWalk, endWalk, endWalkTo)
  }

  function newTripDraft() {
    if (!service || !newTripLocation || !newTripOrigin || !newTripDestination || !newTripDestinationStop)
      return null
    return Model.tempPlaceFrom(newTripLocation, newTripOrigin, newTripDestinationStop, newTripWalk,
      newTripDestination.isStop ? null : newTripDestination)
  }

  Connections {
    target: root.service

    function onNewTripAction(name) {
      if (!root.opened || root.tab !== "newtrip")
        return
      if (name === "use")
        root.useNewTripNow()
      else if (name === "save")
        root.saveNewTrip()
      else if (name.indexOf("from:") === 0) {
        root.pendingScriptedPick = "from"
        root.searchNewTrip(name.slice(5))
      } else if (name.indexOf("to:") === 0) {
        root.pendingScriptedPick = "to"
        root.otherDestinationOpen = true
        root.searchOtherDestination(name.slice(3))
      }
    }
  }

  // Scripted New trip (omarchy-shell tfnsw newtripFrom / newtripTo): pick the
  // first result as soon as the search delivers one.
  property string pendingScriptedPick: ""
  onNewTripResultsChanged: {
    if (pendingScriptedPick !== "from") return
    var first = firstSearchResult(newTripResults)
    if (!first) return
    pendingScriptedPick = ""
    pickNewTripLocation(first)
  }
  onOtherDestinationResultsChanged: {
    if (pendingScriptedPick !== "to") return
    var first = firstSearchResult(otherDestinationResults)
    if (!first) return
    pendingScriptedPick = ""
    pickOtherDestination(first)
  }

  function useNewTripNow() {
    var place = newTripDraft()
    if (!place || !lastJourneys.length)
      return
    service.tempPlace = place
    service.setActivePlace("temp", true)
    dismiss()
  }

  function saveNewTrip() {
    var place = newTripDraft()
    if (!place || !lastJourneys.length)
      return
    prefillPlaceDraft(place)
    tab = "settings"
  }

  function openUrl(url) {
    var safe = Api.httpsOnly(url)
    if (safe && service && typeof service.openUrl === "function")
      service.openUrl(safe)
  }

  function quotaCaptionText() {
    if (!service || !service.quotaBackoffUntil)
      return ""

    return "Transport NSW quota reached — retrying at " + Model.clockText(service.quotaBackoffUntil)
  }

  onTabChanged: {
    if (service && opened) {
      service.setNewTripOpen(tab === "newtrip")
    }
  }

  Button {
    id: controlReference

    visible: false
    bordered: true
    text: "Reference"
    fontFamily: root.family
  }

  PanelWindow {
    visible: root.opened
    color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0)
    WlrLayershell.namespace: "tfnsw-departures-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card

      anchors.centerIn: parent
      width: Math.min(Style.space(600), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(760), parent.height - Style.gapsOut * 2)
      radius: Style.space(8)
      clip: true
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.space(0)

      MouseArea {
        anchors.fill: parent
      }

      PanelKeyCatcher {
        id: keyCatcher

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        blocked: false
        onCloseRequested: root.dismiss()

        Item {
          id: header

          implicitHeight: Style.space(58)
          height: implicitHeight

          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
          }

          Row {
            id: titleRow

            anchors.left: parent.left
            anchors.leftMargin: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(11)

            TransportMark {
              iconSize: Style.space(28)
              colorful: true
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                textFormat: Text.PlainText
                text: root.tab === "newtrip" ? "New trip" : "Transport NSW for Omarchy"
                color: root.foreground
                font.family: root.family
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
              }

              // Community plugin: say so where the brand name is largest.
              Text {
                visible: root.tab !== "newtrip"
                textFormat: Text.PlainText
                text: "Community plugin · not affiliated with Transport for NSW"
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.space(9)
              }
            }
          }

          ButtonGroup {
            id: tabs

            anchors.right: closeButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            spacing: Style.space(4)
            options: [{
              "value": "settings",
              "label": "Settings"
            }, {
              "value": "newtrip",
              "label": "New trip"
            }]
            value: root.tab
            onChanged: function(value) {
              root.tab = value
            }
          }

          PanelActionButton {
            id: closeButton

            anchors.right: parent.right
            anchors.rightMargin: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅖"
            tooltipText: "Close"
            foreground: root.muted
            fontFamily: root.family
            fontSize: Style.space(17)
            size: Style.space(24)
            bordered: true
            radius: Style.space(4)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), Style.space(1))
            onClicked: root.dismiss()
          }
        }

        PanelSeparator {
          id: rule

          anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
          }
          foreground: root.foreground
        }

        Caption {
          id: quotaCaption

          anchors.top: rule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(18)
          anchors.rightMargin: Style.space(18)
          anchors.topMargin: Style.space(10)
          visible: root.service && root.service.quotaBackoffUntil > 0
          text: root.quotaCaptionText()
          color: Color.urgent
        }

        Loader {
          id: paneLoader

          sourceComponent: root.tab === "newtrip" ? newTripPane : settingsPane

          anchors {
            top: quotaCaption.visible ? quotaCaption.bottom : rule.bottom
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            leftMargin: Style.space(18)
            rightMargin: Style.space(18)
            topMargin: Style.space(16)
            bottomMargin: Style.space(18)
          }
        }
      }
    }
  }

  Component {
    id: settingsPane

    SettingsPane {
      host: root
    }
  }

  Component {
    id: newTripPane

    Flickable {
      function focusField() {
        if (!root.newTripLocation) whereField.forceActiveFocus()
      }

      clip: true
      contentWidth: width
      contentHeight: newTripColumn.height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: newTripColumn

        width: parent.width
        spacing: Style.space(14)

        Column {
          width: parent.width
          spacing: Style.space(5)

          FieldLabel {
            text: "Where are you?"
          }

          NewTripField {
            id: whereField

            visible: root.newTripLocation === null
            width: parent.width
            text: root.newTripSearchText
            placeholderText: "Address, landmark or stop…"
            onTextEdited: root.searchNewTrip(text)
            onAccepted: {
              var first = root.firstSearchResult(root.newTripResults)
              if (first)
                root.pickNewTripLocation(first)
            }
          }

          Repeater {
            model: root.newTripLocation === null ? root.newTripResults : []

            delegate: Item {
              required property var modelData

              width: newTripColumn.width
              implicitHeight: modelData.isDivider ? moreLabel.implicitHeight : resultButton.implicitHeight

              Text {
                id: moreLabel

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: modelData.isDivider === true
                textFormat: Text.PlainText
                text: "More"
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }

              NewTripButton {
                id: resultButton

                width: parent.width
                visible: modelData.isDivider !== true
                leftAlign: true
                text: root.searchResultText(modelData)
                onClicked: root.pickNewTripLocation(modelData)
              }
            }
          }

          NewTripButton {
            visible: root.newTripLocation !== null
            width: parent.width
            leftAlign: true
            selected: true
            text: root.newTripLocation ? root.newTripLocation.name + "   ×" : ""
            onClicked: root.clearNewTripLocation()
          }
        }

        Column {
          width: parent.width
          visible: root.newTripLocation !== null && root.newTripLocation && !root.newTripLocation.isStop
          spacing: Style.space(6)

          FieldLabel {
            text: "Nearest stops"
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              readonly property var featured: Model.featureNearby(root.nearbyStops, root.newTripOrigin ? root.newTripOrigin.id : "", 15)
              model: root.nearbyExpanded ? featured.slice(0, 8)
                : featured.slice(0, 3).concat(featured.length > 3 ? [{ "isMore": true }] : [])

              delegate: NewTripButton {
                required property var modelData

                chip: true
                selected: !modelData.isMore && root.newTripOrigin && String(root.newTripOrigin.id) === String(modelData.id)
                text: modelData.isMore ? "More…" : root.chipGlyph(modelData) + modelData.name + " · " + modelData.walkMinutes + " min walk"
                onClicked: {
                  if (modelData.isMore) root.nearbyExpanded = true
                  else root.selectNearbyStop(modelData)
                }
              }
            }
          }

          WalkStrip {
            visible: root.newTripLocation !== null && !root.newTripLocation.isStop && root.newTripOrigin !== null
            startText: root.newTripLocation ? Model.boardStopName(root.newTripLocation.name) : ""
            startBold: true
            walk: root.newTripWalk
            endGlyph: root.newTripOrigin ? root.chipGlyph(root.newTripOrigin).trim() : ""
            endText: root.newTripOrigin ? Model.boardStopName(root.newTripOrigin.name) : ""
          }

          Caption {
            visible: root.nearbyFallback || root.originFallback
            text: root.nearbyFallback ? "No stops within 3 km — planned from your address"
              : "No services soon from " + root.originFallbackStop + " — planned from your address"
          }
        }

        Column {
          width: parent.width
          visible: root.newTripOrigin !== null
          spacing: Style.space(6)

          FieldLabel {
            text: "Going to"
          }

          Dropdown {
            width: parent.width
            showLabel: false
            foreground: root.foreground
            fontFamily: root.family
            options: {
              var out = root.newTripDestinationOptions.map(function(stop) {
                return { "value": stop.id, "label": stop.label }
              })
              var found = false
              for (var i = 0; i < out.length; i++) if (root.newTripDestination
                  && String(out[i].value) === String(root.newTripDestination.id)) found = true
              if (root.newTripDestination && !found)
                out.push({ "value": root.newTripDestination.id, "label": root.newTripDestination.name + " · New trip" })
              out.push({ "value": "search", "label": "Search…" })
              return out
            }
            value: root.otherDestinationOpen ? "search" : (root.newTripDestination ? root.newTripDestination.id : "")
            onChanged: function(value) { root.chooseNewTripDestination(value) }
          }

          NewTripField {
            visible: root.otherDestinationOpen
            width: parent.width
            text: root.otherDestinationSearchText
            placeholderText: "Search stops or addresses…"
            onTextEdited: root.searchOtherDestination(text)
            onAccepted: {
              var first = root.firstSearchResult(root.otherDestinationResults)
              if (first) root.pickOtherDestination(first)
            }
          }

          Repeater {
            model: root.otherDestinationOpen ? root.otherDestinationResults : []

            delegate: Item {
              required property var modelData

              width: newTripColumn.width
              implicitHeight: modelData.isDivider ? otherMore.implicitHeight : otherResult.implicitHeight

              Text {
                id: otherMore

                visible: modelData.isDivider === true
                textFormat: Text.PlainText
                text: "More"
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }

              NewTripButton {
                id: otherResult

                width: parent.width
                visible: modelData.isDivider !== true
                leftAlign: true
                text: root.searchResultText(modelData)
                onClicked: root.pickOtherDestination(modelData)
              }
            }
          }

          Column {
            width: parent.width
            visible: root.newTripDestination && !root.newTripDestination.isStop
            spacing: Style.space(6)

            FieldLabel {
              text: "Arrive via"
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                readonly property var featured: Model.featureNearby(root.newTripDestinationStops, root.newTripDestinationStop ? root.newTripDestinationStop.id : "", 15)
                model: root.destinationNearbyExpanded ? featured.slice(0, 8)
                  : featured.slice(0, 3).concat(featured.length > 3 ? [{ "isMore": true }] : [])

                delegate: NewTripButton {
                  required property var modelData

                  chip: true
                  selected: !modelData.isMore && root.newTripDestinationStop
                    && String(root.newTripDestinationStop.id) === String(modelData.id)
                  text: modelData.isMore ? "More…"
                    : root.chipGlyph(modelData) + modelData.name + " · " + modelData.walkMinutes + " min walk"
                  onClicked: {
                    if (modelData.isMore) root.destinationNearbyExpanded = true
                    else root.selectDestinationStop(modelData)
                  }
                }
              }
            }

            // Where the ride ends and what is left on foot, at a glance.
            WalkStrip {
              visible: root.newTripDestinationStop !== null
              startGlyph: root.newTripDestinationStop ? root.chipGlyph(root.newTripDestinationStop).trim() : ""
              startText: root.newTripDestinationStop ? Model.boardStopName(root.newTripDestinationStop.name) : ""
              walk: root.newTripDestinationStop ? Number(root.newTripDestinationStop.walkMinutes || 0) : 0
              endText: Model.boardStopName(root.newTripDestination ? root.newTripDestination.name : "")
              endBold: true
            }
          }
        }

        Text {
          width: parent.width
          visible: root.service && root.service.journeyRows.count === 0 && root.newTripOrigin !== null
            && root.newTripDestination !== null && root.service.journeyError === "" && root.lastJourneys.length >= 0
            && root.service.lastPlanNote.indexOf("parsed=") !== -1
          textFormat: Text.PlainText
          text: root.lastJourneys.length ? "No trips in the next 3 hours" : "No trips found"
          color: root.muted
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Column {
          id: newTripBoard

          // The leave window follows the first row you can still catch.
          readonly property var firstRow: {
            if (!root.service) return null
            var rows = root.service.journeyRows
            for (var i = 0; i < rows.count; i++) {
              var row = rows.get(i)
              if (!row.missed && !row.cancelled && !row.dominated) return row
            }
            return rows.count > 0 ? rows.get(0) : null
          }

          width: parent.width
          visible: firstRow !== null
          spacing: Style.space(0)

          BorderSurface {
            width: parent.width
            implicitHeight: newTripLeaveCopy.implicitHeight + Style.space(25)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
            borderSpec: root.borderSpec
            radius: Style.space(6)

            Row {
              id: newTripLeaveCopy

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              anchors.topMargin: Style.space(9)
              spacing: Style.space(9)

              Text {
                textFormat: Text.PlainText
                text: "󰖃"
                color: root.foreground
                font.family: root.family
                font.pixelSize: Style.space(15)
              }

              Column {
                width: Math.max(0, parent.width - parent.children[0].width - parent.spacing)
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: Model.leaveHeading(newTripBoard.firstRow ? newTripBoard.firstRow.leaveMs : 0)
                  color: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.space(15)
                  font.weight: Font.Bold
                }

                Text {
                  textFormat: Text.PlainText
                  text: (root.newTripWalk > 0 ? root.newTripWalk + " min walk · " : "")
                    + (newTripBoard.firstRow ? newTripBoard.firstRow.line + " to " + newTripBoard.firstRow.headsign : "")
                    + (root.lastJourneys.length && Model.finalWalkMinutes(root.lastJourneys[0]) > 0
                      ? " · then " + Model.finalWalkMinutes(root.lastJourneys[0]) + " min walk" : "")
                  color: root.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              anchors.bottomMargin: Style.space(9)
              height: Style.space(3)
              radius: Style.space(2)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.round(parent.width * Model.underlineFraction(newTripBoard.firstRow ? newTripBoard.firstRow.leaveMs : -1))
                radius: parent.radius
                color: Api.lineColor(newTripBoard.firstRow ? newTripBoard.firstRow.line : "",
                  newTripBoard.firstRow ? newTripBoard.firstRow.mode : "other")
              }
            }
          }

          Repeater {
            model: root.service ? root.service.journeyRows : null

            delegate: DepartureRow {
              width: newTripColumn.width
              first: index === 0
              expanded: root.expandedJourneyId === model.depId
              depId: model.depId
              legs: root.service ? root.service.journeyLegsFor(model.depId) : []
              mode: model.mode
              line: model.line
              destination: model.destination
              headsign: model.headsign
              platform: model.platform
              timeText: model.timeText
              plannedText: model.plannedText
              arriveText: model.arriveText
              travelText: model.travelText
              changesText: model.changesText
              legsSummary: model.legsSummary
              crowding: model.crowding
              leaveText: model.leaveText
              leaveMs: model.leaveMs
              walkMinutes: root.newTripWalk
              realtime: model.realtime
              cancelled: model.cancelled
              dominated: model.dominated
              missed: model.missed
              delayMin: model.delayMin
              status: model.status
              alertTitle: model.alertTitle
              onExpandToggled: root.expandedJourneyId = root.expandedJourneyId === depId ? "" : depId
            }
          }
        }

        Caption {
          width: parent.width
          visible: root.service && root.service.journeyError !== ""
          text: root.service ? root.service.journeyError : ""
          color: Color.urgent
        }

        Row {
          width: parent.width
          visible: root.lastJourneys.length > 0
          spacing: Style.space(8)

          Item {
            width: Math.max(0, parent.width - useNowButton.width - saveTripButton.width - parent.spacing * 2)
            height: Style.space(1)
          }

          NewTripButton {
            id: saveTripButton

            text: "Save as trip"
            onClicked: root.saveNewTrip()
          }

          NewTripButton {
            id: useNowButton

            primary: true
            text: "Use now"
            onClicked: root.useNewTripNow()
          }
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }
  }


  // "Address → walk → stop" (origin) or "stop → walk → address" (destination):
  // the ends of the trip and what is on foot, at a glance.
  component WalkStrip: Row {
    id: walkStrip

    property string startGlyph: ""
    property string startText: ""
    property bool startBold: false
    property int walk: 0
    property string endGlyph: ""
    property string endText: ""
    property bool endBold: false

    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: walkStrip.startGlyph !== ""
      textFormat: Text.PlainText
      text: walkStrip.startGlyph
      color: root.muted
      font.family: root.family
      font.pixelSize: Style.space(15)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: walkStrip.startText
      color: root.foreground
      font.family: root.family
      font.pixelSize: Style.font.caption
      font.weight: walkStrip.startBold ? Font.DemiBold : Font.Normal
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "→  󰖃 " + walkStrip.walk + " min  →"
      color: root.muted
      font.family: root.family
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: walkStrip.endGlyph !== ""
      textFormat: Text.PlainText
      text: walkStrip.endGlyph
      color: root.muted
      font.family: root.family
      font.pixelSize: Style.space(15)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: walkStrip.endText
      color: root.foreground
      font.family: root.family
      font.pixelSize: Style.font.caption
      font.weight: walkStrip.endBold ? Font.DemiBold : Font.Normal
    }
  }

  component NewTripButton: BorderSurface {
    id: newTripButton

    property string text: ""
    property bool selected: false
    property bool primary: false
    property bool leftAlign: false
    // Chips (nearby stops) are one size, every other button is the control height.
    property bool chip: false
    signal clicked()

    radius: Style.space(4)
    implicitWidth: newTripButtonLabel.implicitWidth + Style.space(20)
    implicitHeight: chip ? root.chipHeight : root.controlHeight
    color: primary ? Color.accent
      : selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : newTripButtonHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0)
    borderSpec: Border.flat(selected ? Color.accent
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), Style.space(1))

    Text {
      id: newTripButtonLabel

      anchors.left: newTripButton.leftAlign ? parent.left : undefined
      anchors.leftMargin: newTripButton.leftAlign ? Style.space(10) : 0
      anchors.horizontalCenter: newTripButton.leftAlign ? undefined : parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, parent.width - Style.space(20)))
      textFormat: Text.PlainText
      text: newTripButton.text
      color: newTripButton.primary ? Color.background : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.85)
      font.family: root.family
      font.pixelSize: Style.font.caption
      font.weight: newTripButton.primary ? Font.DemiBold : Font.Medium
      elide: Text.ElideRight
    }

    HoverHandler {
      id: newTripButtonHover

      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      onTapped: newTripButton.clicked()
    }
  }

  component NewTripField: TextField {
    id: newTripField

    height: root.controlHeight
    verticalAlignment: TextInput.AlignVCenter
    foreground: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.85)
    font.family: root.family
    font.pixelSize: Style.font.bodySmall
    font.weight: text === "" ? Font.Light : Font.Normal
    placeholderTextColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    topPadding: Style.space(0)
    bottomPadding: Style.space(0)
    background: BorderSurface {
      color: Qt.darker(Color.background, 1.1)
      borderSpec: Border.flat(newTripField.activeFocus ? Color.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.20), Style.space(1))
      radius: Style.space(4)
    }
  }

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.bodySmall
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.Medium
  }
}
