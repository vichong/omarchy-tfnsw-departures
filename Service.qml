import QtQuick
import Quickshell
import Quickshell.Io
import "Api.js" as Api
import "Model.js" as Model
import "ConfigStore.js" as ConfigStore
import "Demo.js" as Demo
import "Crowding.js" as Crowding

// Orchestration only: generation guards a connection lifetime while the
// interchangeable backends own I/O and the JS modules own data shaping.
QtObject {
  id: root

  // Shell injection and persistent paths.
  property var shell: null
  property var manifest: null
  readonly property string version: manifest && manifest.version ? String(manifest.version) : "0.8.1"
  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string configDir: home + "/.config/omarchy/tfnsw-departures"
  readonly property string configPath: configDir + "/config.json"
  readonly property string cacheDir: home + "/.cache/omarchy/tfnsw-departures"
  readonly property string cachePath: cacheDir + "/board.json"
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/tfnsw-bounded")).replace(/^file:\/\//, ""))
  readonly property string stopsPath: decodeURIComponent(String(Qt.resolvedUrl("data/stops.json")).replace(/^file:\/\//, ""))
  property var stops: []
  // Non-secret configuration. The API key lives only in CredentialManager.
  property bool configLoaded: false
  property string configError: ""
  property bool demoMode: false
  property var places: []
  property string activePlaceId: ""
  property string savedActivePlaceId: ""
  property var tempPlace: null
  property bool autoPlace: true
  property int pollSeconds: ConfigStore.POLL_DEFAULT
  property bool notify: true
  property bool colorful: false
  readonly property var savedEffectivePlaces: demoMode && places.length === 0 ? [Demo.defaultPlace()] : places
  readonly property var effectivePlaces: tempPlace ? [tempPlace].concat(savedEffectivePlaces) : savedEffectivePlaces
  readonly property var activePlace: {
    var list = effectivePlaces
    for (var i = 0; i < list.length; i++) if (String(list[i].id) === activePlaceId) {
      return list[i]
    }
    return list.length ? list[0] : null
  }
  // Times follow the bar clock: the clock widget's format lives in shell.json.
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"
  property bool twelveHour: false
  property FileView shellConfigFile

  shellConfigFile: FileView {
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyClockFormat(text())
    onLoadFailed: root.applyClockFormat("")
    onFileChanged: reload()
  }

  function applyClockFormat(text) {
    var format = Model.clockFormatFromShellConfig(String(text || "").slice(0, 1024 * 1024))
    var next = Model.clockFormatIsTwelveHour(format)
    if (next === twelveHour && configLoaded)
      return

    twelveHour = next
    Model.setTwelveHour(next)
    if (departures.length)
      project(Date.now())
  }

  property FileView configFile

  configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  property FileView cacheFile

  cacheFile: FileView {
    path: root.cachePath
    printErrors: false
    atomicWrites: true
  }

  property FileView stopsFile

  stopsFile: FileView {
    path: root.stopsPath
    printErrors: false
    onLoaded: root.applyStops(text())
    onLoadFailed: root.stops = []
  }

  function utf8ByteLength(text) {
    var value = String(text || "")
    var bytes = 0
    for (var i = 0; i < value.length; i++) {
      var code = value.charCodeAt(i)
      if (code < 0x80) bytes++
      else if (code < 0x800) bytes += 2
      else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length
               && value.charCodeAt(i + 1) >= 0xDC00 && value.charCodeAt(i + 1) <= 0xDFFF) {
        bytes += 4
        i++
      } else bytes += 3
      if (bytes > 512 * 1024)
        return bytes
    }
    return bytes
  }

  function applyStops(text) {
    var source = String(text || "")
    if (utf8ByteLength(source) > 512 * 1024) {
      stops = []
      return
    }
    var parsed = null
    try {
      parsed = JSON.parse(source)
    } catch (e) {
      stops = []
      return
    }
    if (!Array.isArray(parsed)) {
      stops = []
      return
    }

    var loaded = []
    for (var i = 0; i < parsed.length && loaded.length < 2000; i++) {
      var item = parsed[i]
      if (!item || typeof item !== "object" || typeof item.id !== "string" || !Api.isStopId(item.id)
          || typeof item.name !== "string" || item.name.trim() === "") continue
      var modes = []
      var rawModes = Array.isArray(item.modes) ? item.modes : []
      for (var m = 0; m < rawModes.length; m++) if (Api.isValidModeId(rawModes[m]) && modes.indexOf(rawModes[m]) === -1)
        modes.push(rawModes[m])
      loaded.push({
        "id": item.id,
        "name": item.name.trim(),
        "modes": modes,
        "lat": typeof item.lat === "number" && isFinite(item.lat) ? item.lat : null,
        "lon": typeof item.lon === "number" && isFinite(item.lon) ? item.lon : null
      })
    }
    stops = loaded
  }

  property Process prepareDirs

  prepareDirs: Process {
    command: ["mkdir", "-p", root.configDir, root.cacheDir]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        configFile.reload()
        cacheRead.running = true
      }
    }
  }

  // Live and demo backends expose the same request surface.
  property LiveBackend liveBackend

  liveBackend: LiveBackend {
    apiKey: root.apiKey
  }

  property DemoBackend demoBackend

  demoBackend: DemoBackend {
  }

  readonly property var backend: demoMode ? demoBackend : liveBackend
  property CredentialManager credentials

  credentials: CredentialManager {
    onKeyReady: function(key) {
      if (root.demoMode)
        return

      if (root.keyUnsupported(key)) {
        root.apiKey = ""
        root.setError("credential", "The stored API key contains unsupported characters.")
        return
      }
      root.apiKey = key
      root.connect()
    }
    onMissing: {
      if (!root.demoMode) {
        root.apiKey = ""
        root.phase = "idle"
        root.clearError()
      }
    }
    onCleared: {
      if (!root.demoMode) {
        root.apiKey = ""
        root.supersede()
        root.phase = "idle"
        root.clearError()
        root.resetBoard()
      }
    }
    onFailed: function(message) {
      if (!root.demoMode)
        root.setError("credential", message)
    }
  }

  // Connection lifetime and redacted credential state.
  property string apiKey: ""
  readonly property bool credentialBusy: credentials.busy
  readonly property bool hasKey: demoMode || apiKey !== ""
  readonly property bool configured: hasKey
  property string phase: "idle"
  readonly property bool connected: phase === "connected"
  property string lastError: ""
  property string lastErrorKind: ""
  property int generation: 0
  property int reconnectAttempts: 0
  readonly property bool transientError: lastErrorKind === "network" || lastErrorKind === "ratelimit" || lastErrorKind === "protocol" || lastErrorKind === "api"
  property Timer reconnectTimer

  reconnectTimer: Timer {
    interval: Math.min(300000, 30000 * Math.pow(2, Math.min(4, root.reconnectAttempts)))
    onTriggered: {
      if (!root.connected && root.hasKey && root.transientError) {
        root.connect()
      }
    }
  }

  // Cached departures and the projected popup/bar state.
  property var departures: []
  property var board: []
  property ListModel rows

  rows: ListModel {
  }

  property var alerts: []
  property string pillText: ""
  property string pillMode: "train"
  property string urgency: "none"
  // Icon-only bar cues: leave-in for the next catchable service and its line colour.
  property double nextLeaveMs: -1
  property string nextLineColor: ""
  property string nextLine: ""
  property string nextDestination: ""
  property int nextFinalWalkMinutes: 0
  property real underlineFraction: 0
  property string barCaption: ""
  property string lastPolledAt: ""
  property double lastPolledMs: 0
  property double nowMs: Date.now()
  property bool stale: false
  property bool polling: false
  property bool pollRequested: false
  property int pollBackoff: 0
  property double quotaBackoffUntil: 0
  property bool popupOpen: false
  property var occupancy: ({})
  property var occupancyFetchedAt: ({})
  property var occupancyRequestedAt: ({})
  property var occupancyByMode: ({})
  readonly property int occupancyPollMs: 60000
  readonly property int occupancyCacheMs: 90000
  readonly property int effectivePollMs: Math.min(600000, (popupOpen ? 30000 : pollSeconds * 1000) * Math.pow(2, pollBackoff))
  property var sentTripIds: ({
  })
  property string sentDay: ""
  property Timer pollTimer

  pollTimer: Timer {
    interval: root.effectivePollMs
    repeat: true
    running: root.connected
    onTriggered: root.poll()
  }

  property Timer quotaBackoffTimer

  quotaBackoffTimer: Timer {
    onTriggered: {
      root.quotaBackoffUntil = 0
      if (root.connected)
        root.poll()
      else if (root.hasKey)
        root.connect()
    }
  }

  property Timer clockTimer

  clockTimer: Timer {
    interval: 15000
    repeat: true
    running: root.departures.length > 0 || root.journeyBoard.length > 0
    onTriggered: {
      var now = Date.now()
      root.rebuildOccupancy(now)
      root.project(now)
      root.reprojectJourney(now)
      root.refreshCrowding()
    }
  }

  property Process notification

  notification: Process {
    command: []
  }

  // One debounced stop search; a newer query supersedes the old callback.
  property string pendingSearchText: ""
  property var pendingSearchCallback: null
  property var searchRequest: null
  property int searchSerial: 0
  property Timer searchDebounce

  searchDebounce: Timer {
    interval: 200
    onTriggered: {
      if (root.quotaBlocked()) {
        if (root.pendingSearchCallback)
          root.pendingSearchCallback([])

        return
      }
      var query = root.pendingSearchText
      var callback = root.pendingSearchCallback
      var serial = root.searchSerial
      function complete(result) {
        if (serial !== root.searchSerial)
          return

        root.searchRequest = null
        root.noteRateLimit(result)
        callback(result.ok ? result.data : [])
      }

      if (root.demoMode)
        root.demoBackend.searchStops(query, complete)
      else if (!root.connected)
        callback([])
      else
        root.searchRequest = root.liveBackend.request(Api.stopFinderPath(query), function(response) {
          if (response.ok)
            response.data = Api.parseLocations(response.data)

          complete(response)
        })
    }
  }

  // Nearby-stop lookups share LiveBackend's serialized worker with every
  // other request. A newer coordinate aborts and supersedes the old result.

  // New-trip journeys refresh only while the overlay tab is visible.
  property ListModel journeyRows

  journeyRows: ListModel {
  }

  property var journeyRequest: null
  property var journeyBoard: []
  property var journeyPlace: null
  property int journeyWalkMinutes: 0
  property string journeyError: ""
  property string lastPlanNote: ""
  property string lastNearbyNote: ""
  property var lastNewTripLocation: null
  property var lastNewTripDestination: null
  property bool newTripOpen: false
  property Timer newTripTimer

  newTripTimer: Timer {
    interval: 60000
    repeat: true
    running: root.newTripOpen && root.connected
    onTriggered: {
      if (root.lastNewTripLocation && root.lastNewTripDestination) {
        root.planFrom(root.lastNewTripLocation, root.lastNewTripDestination, null)
      }
    }
  }

  // Wi-Fi output is bounded by the helper before the SSID is parsed.
  property string lastSsid: ""
  property double lastManualPlaceAt: 0
  property string wifiOutput: ""
  property Process wifiProcess

  wifiProcess: Process {
    command: ["bash", root.helperPath, "nmcli", "-t", "-f", "active,ssid", "dev", "wifi"]
    environment: ({
      "TFNSW_MAX_BYTES": "16384"
    })
    onExited: function(exitCode) {
      if (exitCode !== 0 && exitCode !== 90)
        return

      var lines = root.wifiOutput.split(/\r?\n/)
      root.wifiOutput = ""
      for (var i = 0; i < lines.length; i++) if (lines[i].indexOf("yes:") === 0) {
        root.lastSsid = lines[i].slice(4).replace(/\\:/g, ":")
        if (root.autoPlace && Date.now() - root.lastManualPlaceAt >= 30 * 60 * 1000) {
          var place = Model.placeForSsid(root.places, root.lastSsid)
          if (place)
            root.setActivePlace(place.id, false)
        }
        break
      }
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.wifiOutput = String(text || "")
    }
  }

  property Timer wifiTimer

  wifiTimer: Timer {
    interval: 30000
    repeat: true
    running: root.configLoaded
    triggeredOnStart: true
    onTriggered: {
      if (!wifiProcess.running) {
        wifiProcess.running = true
      }
    }
  }

  // Last-good board cache, bounded on both read and write.
  property string cacheOutput: ""
  property Process cacheRead

  cacheRead: Process {
    command: ["bash", root.helperPath, "head", "-c", String(Api.MAX_RESPONSE_BYTES), root.cachePath]
    environment: ({
      "TFNSW_MAX_BYTES": String(Api.MAX_RESPONSE_BYTES + 1)
    })
    onExited: function(exitCode) {
      if (exitCode !== 0 || root.cacheOutput.length >= Api.MAX_RESPONSE_BYTES) {
        root.cacheOutput = ""
        return
      }
      try {
        var cached = JSON.parse(root.cacheOutput)
        var sameStop = cached && root.activePlace
          && String(cached.stopId || "") === String(root.activePlace.stopId)
          && String(cached.destStopId || "") === String(root.activePlace.destStopId || "")
          && String(cached.destAddress || "") === String(root.activePlace.destAddress || "")
          && (cached.destLat === undefined || cached.destLat === root.activePlace.destLat)
          && (cached.destLon === undefined || cached.destLon === root.activePlace.destLon)
        if (sameStop && Array.isArray(cached.departures) && cached.departures.length <= Api.MAX_STOP_EVENTS) {
          root.departures = cached.departures
          root.lastPolledMs = Number(cached.savedAt) || 0
          root.lastPolledAt = root.lastPolledMs ? new Date(root.lastPolledMs).toISOString() : ""
          root.stale = true
          root.project(Date.now())
        }
      } catch (e) {
      }
      root.cacheOutput = ""
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.cacheOutput = String(text || "")
    }
  }

  function currentConfig() {
    return {
      "demoMode": demoMode,
      "places": places.slice(),
      "activePlaceId": activePlaceId === "temp" ? savedActivePlaceId : activePlaceId,
      "autoPlace": autoPlace,
      "pollSeconds": pollSeconds,
      "notify": notify,
      "colorful": colorful
    }
  }

  function saveConfig(patch) {
    var text = ConfigStore.serialize(ConfigStore.merge(currentConfig(), patch || {
    }))
    configFile.setText(text)
    applyConfig(text)
  }

  function applyConfig(text) {
    var parsed = ConfigStore.parse(text), c = parsed.config
    var keepTempActive = activePlaceId === "temp" && tempPlace !== null
    var connectionChanged = !configLoaded || demoMode !== c.demoMode
    var boardChanged = JSON.stringify(places) !== JSON.stringify(c.places) || activePlaceId !== c.activePlaceId
    var previousStopId = activePlace ? activePlace.stopId : ""
    var previousDestStopId = activePlace ? activePlace.destStopId : ""
    var previousDestAddress = activePlace ? activePlace.destAddress : ""
    var previousDestLat = activePlace ? activePlace.destLat : null
    var previousDestLon = activePlace ? activePlace.destLon : null
    configError = parsed.error
    demoMode = c.demoMode
    if (demoMode) {
      quotaBackoffUntil = 0
      quotaBackoffTimer.stop()
    }
    places = c.places
    savedActivePlaceId = c.activePlaceId
    activePlaceId = keepTempActive ? "temp" : c.activePlaceId
    autoPlace = c.autoPlace
    pollSeconds = c.pollSeconds
    notify = c.notify
    colorful = c.colorful
    var stopChanged = (activePlace ? activePlace.stopId : "") !== previousStopId
      || (activePlace ? activePlace.destStopId : "") !== previousDestStopId
      || (activePlace ? activePlace.destAddress : "") !== previousDestAddress
      || (activePlace ? activePlace.destLat : null) !== previousDestLat
      || (activePlace ? activePlace.destLon : null) !== previousDestLon
    configLoaded = true
    if (connectionChanged) {
      supersede()
      apiKey = ""
      phase = "idle"
      clearError()
      if (demoMode) {
        demoBackend.reset()
        connect()
      } else if (!credentials.busy) {
        credentials.lookup()
      }
    } else if (boardChanged) {
      if (stopChanged) {
        departures = []
        stale = false
        lastPolledMs = 0
        lastPolledAt = ""
      }
      project(Date.now())
      if (connected)
        poll()
    }
  }

  function savePlaces(list) {
    var normalized = ConfigStore.parse(ConfigStore.serialize(ConfigStore.merge(currentConfig(), {
      "places": list
    }))).config
    saveConfig({
      "places": normalized.places,
      "activePlaceId": normalized.activePlaceId
    })
  }

  function setActivePlace(id, manual) {
    var wanted = String(id || ""), found = false
    for (var i = 0; i < effectivePlaces.length; i++) if (effectivePlaces[i].id === wanted) {
      found = true
    }
    if (!found)
      return false

    if (manual !== false)
      lastManualPlaceAt = Date.now()

    if (wanted === "temp") {
      if (!tempPlace)
        return false

      if (activePlaceId === "temp")
        return true

      activePlaceId = "temp"
      departures = []
      resetBoard()
      if (connected)
        poll()
      return true
    }

    var discardedTemp = tempPlace !== null
    tempPlace = null
    if (wanted === activePlaceId && !discardedTemp)
      return false

    saveConfig({
      "activePlaceId": wanted
    })
    return true
  }

  function addPlace(place) {
    var list = places.slice()
    if (list.length >= ConfigStore.MAX_PLACES)
      return false

    list.push(place)
    saveConfig({
      "places": list,
      "activePlaceId": place.id
    })
    return true
  }

  function retryDeferredLookup() {
    if (!credentialBusy && !demoMode && configLoaded && !hasKey && phase === "idle")
      credentials.lookup()
  }

  function keyUnsupported(key) {
    return /["\\\x00-\x1f\x7f]/.test(String(key || ""))
  }

  function applyConnection(key) {
    if (demoMode || credentials.busy)
      return false

    var raw = String(key || "")
    if (keyUnsupported(raw)) {
      setError("credential", "The API key contains unsupported characters.")
      return false
    }
    var trimmed = raw.trim()
    if (trimmed) {
      phase = "connecting"
      clearError()
      return credentials.store(trimmed)
    }
    if (apiKey) {
      connect()
      return true
    }
    return credentials.lookup()
  }

  function removeConnection() {
    return !demoMode && !credentials.busy ? credentials.clear() : false
  }

  function setDemoMode(value) {
    if (credentials.busy)
      return false

    saveConfig({
      "demoMode": value === true
    })
    return true
  }

  function clearError() {
    lastError = ""
    lastErrorKind = ""
  }

  function setError(kind, message) {
    lastErrorKind = String(kind || "")
    lastError = String(message || "")
    if (kind === "credential")
      phase = "error"
  }

  function supersede() {
    liveBackend.supersede()
    demoBackend.supersede()
    generation++
    polling = false
    searchRequest = null
    journeyRequest = null
    resetCrowding()
  }

  function resetCrowding() {
    occupancyFetchedAt = ({})
    occupancyRequestedAt = ({})
    occupancyByMode = ({})
    occupancy = demoMode ? demoBackend.occupancyMap() : ({})
  }

  function quotaBlocked() {
    if (demoMode)
      return false

    if (!quotaBackoffUntil)
      return false

    if (quotaBackoffUntil <= Date.now()) {
      quotaBackoffUntil = 0
      return false
    }
    return true
  }

  function noteRateLimit(result) {
    if (!result || result.ok || result.kind !== "ratelimit")
      return false

    var delay = Math.min(10 * 60 * 1000, Math.max(60 * 1000, effectivePollMs * 2))
    quotaBackoffUntil = Date.now() + delay
    quotaBackoffTimer.interval = delay
    quotaBackoffTimer.restart()
    return true
  }

  function connect() {
    if (!hasKey)
      return

    if (quotaBlocked())
      return

    supersede()
    reconnectTimer.stop()
    phase = "connecting"
    clearError()
    var token = generation
    function complete(result) {
      if (token !== generation)
        return

      noteRateLimit(result)
      if (!result.ok) {
        phase = "error"
        setError(result.kind, result.error)
        if (transientError && result.kind !== "ratelimit") {
          reconnectAttempts++
          reconnectTimer.restart()
        }
        return
      }
      reconnectAttempts = 0
      pollBackoff = 0
      phase = "connected"
      poll()
    }

    if (demoMode)
      demoBackend.probe(complete)
    else
      liveBackend.request(Api.connectionProbePath(), complete)
  }

  function retryConnection() {
    reconnectAttempts = 0
    if (hasKey)
      connect()
    else if (!credentials.busy)
      credentials.lookup()
  }

  function excludedModes(place) {
    if (!place || !place.modes || !place.modes.length)
      return []

    var out = []
    for (var i = 0; i < Api.MODES.length; i++) if (place.modes.indexOf(Api.MODES[i].id) === -1) {
      out.push(Api.MODES[i].id)
    }
    return out
  }

  function poll() {
    if (!connected || !activePlace)
      return

    if (quotaBlocked())
      return

    if (polling) {
      pollRequested = true
      return
    }
    polling = true
    pollRequested = false
    var token = generation
    var placeId = activePlace.id
    var stopId = String(activePlace.stopId || "")
    var destStopId = String(activePlace.destStopId || "")
    var destAddress = String(activePlace.destAddress || "")
    var destLat = activePlace.destLat
    var destLon = activePlace.destLon
    function complete(result) {
      if (token !== generation)
        return

      polling = false
      if (!root.activePlace || root.activePlace.id !== placeId
          || String(root.activePlace.stopId || "") !== stopId
          || String(root.activePlace.destStopId || "") !== destStopId
          || String(root.activePlace.destAddress || "") !== destAddress
          || root.activePlace.destLat !== destLat || root.activePlace.destLon !== destLon) {
        // The place or either endpoint changed under this request; its board
        // belongs to the old source.
        if (pollRequested) {
          pollRequested = false
          Qt.callLater(root.poll)
        }
        return
      }
      noteRateLimit(result)
      if (!result.ok) {
        setError(result.kind, result.error)
        if (result.kind === "network" || result.kind === "ratelimit")
          pollBackoff = Math.min(5, pollBackoff + 1)
      } else {
        departures = result.data.slice(0, Api.MAX_STOP_EVENTS)
        pollBackoff = 0
        phase = "connected"
        clearError()
        lastPolledMs = Date.now()
        lastPolledAt = new Date(lastPolledMs).toISOString()
        stale = false
        project(lastPolledMs)
        writeCache()
      }
      if (pollRequested) {
        pollRequested = false
        Qt.callLater(root.poll)
      }
    }

    var trip = Model.hasDestination(activePlace)
    if (demoMode) {
      if (trip)
        demoBackend.journeys(complete)
      else
        demoBackend.departures(complete)
    } else {
      var path = trip
        ? Api.tripPath(activePlace.stopId, activePlace.destStopId, 6)
        : Api.departuresPath(activePlace.stopId, excludedModes(activePlace))
      var endWalkMinutes = trip && activePlace.destAddress ? Number(activePlace.destWalkMinutes || 0) : 0
      var endWalkTo = trip ? Model.boardStopName(activePlace.destAddress || "") : ""
      liveBackend.request(path, function(response) {
        if (response.ok)
          response.data = trip
            ? Model.appendEndWalk(Api.parseJourneys(response.data), endWalkMinutes, endWalkTo)
            : Api.parseDepartures(response.data)

        complete(response)
      })
    }
  }

  function refresh() {
    if (connected)
      poll()
    else
      retryConnection()
  }

  function openUrl(url) {
    var safe = Api.httpsOnly(Api.clip(url, 2048))
    if (!safe)
      return false

    Quickshell.execDetached(["gio", "open", safe])
    return true
  }

  function resetBoard() {
    departures = []
    board = []
    rows.clear()
    alerts = []
    pillText = ""
    urgency = "none"
    nextLeaveMs = -1
    nextLineColor = ""
    nextLine = ""
    nextDestination = ""
    nextFinalWalkMinutes = 0
    underlineFraction = 0
    barCaption = ""
  }

  function project(now) {
    nowMs = now
    var place = activePlace
    if (!place) {
      resetBoard()
      return
    }
    board = Model.hasDestination(place)
      ? Model.markDominated(Model.boardFromJourneys(departures, place, now))
      : Model.boardFor(departures, place, now)
    var projected = Model.buildRows(board, place, now, occupancy)
    rows.clear()
    for (var i = 0; i < projected.length && i < Model.MAX_ROWS; i++) rows.append(projected[i])
    alerts = Model.collectAlerts(board)
    pillText = Model.pillText(board, place, now)
    pillMode = Model.pillMode(board, place, now)
    urgency = Model.urgency(board, place, now)
    var barState = Model.barState(board, place, now)
    nextLeaveMs = barState.leaveMs
    nextLineColor = barState.lineColor
    nextLine = barState.line
    nextDestination = barState.destination
    var next = Model.nextCatchable(board, place, now)
    nextFinalWalkMinutes = Model.finalWalkMinutes(next)
    underlineFraction = barState.fraction
    barCaption = barState.caption
    maybeNotify(now)
    refreshCrowding()
  }

  function legsFor(depId) {
    var wanted = String(depId || "")
    for (var i = 0; i < board.length; i++) if (String(board[i].id) === wanted)
      return Model.legRows(board[i], occupancy)

    return []
  }

  function setPopupOpen(value) {
    popupOpen = value === true
    if (popupOpen && connected) {
      poll()
      refreshCrowding()
    }
  }

  function visibleCrowdingModes() {
    var seen = {}, modes = []
    function scan(entries) {
      var list = Array.isArray(entries) ? entries : []
      for (var i = 0; i < list.length && i < Model.MAX_ROWS; i++) {
        var legs = list[i] && Array.isArray(list[i].legs) ? list[i].legs : []
        for (var l = 0; l < legs.length; l++) {
          var mode = legs[l] && legs[l].kind === "ride" ? String(legs[l].mode || "") : ""
          if ((mode === "train" || mode === "metro" || mode === "bus") && !seen[mode]) {
            seen[mode] = true
            modes.push(mode)
          }
        }
      }
    }
    if (popupOpen) scan(board)
    if (newTripOpen) scan(journeyBoard)
    return modes
  }

  function rebuildOccupancy(now) {
    if (demoMode) {
      occupancy = demoBackend.occupancyMap()
      return
    }
    var merged = {}, feeds = occupancyByMode
    for (var mode in feeds) if (now - Number(occupancyFetchedAt[mode] || 0) <= occupancyCacheMs) {
      var values = feeds[mode] || {}
      for (var tripId in values) merged[tripId] = values[tripId]
    }
    occupancy = merged
  }

  function reprojectJourney(now) {
    if (!journeyPlace)
      return
    var projected = Model.buildRows(journeyBoard, journeyPlace, now, occupancy)
    journeyRows.clear()
    for (var i = 0; i < projected.length && i < Model.MAX_ROWS; i++) journeyRows.append(projected[i])
  }

  function reprojectCrowding() {
    var projected = activePlace ? Model.buildRows(board, activePlace, nowMs, occupancy) : []
    rows.clear()
    for (var i = 0; i < projected.length && i < Model.MAX_ROWS; i++) rows.append(projected[i])
    reprojectJourney(Date.now())
  }

  function refreshCrowding() {
    if ((!popupOpen && !newTripOpen) || demoMode || !connected || quotaBlocked())
      return
    var modes = visibleCrowdingModes(), now = Date.now()
    for (var i = 0; i < modes.length; i++) {
      var mode = modes[i]
      if (now - Number(occupancyRequestedAt[mode] || 0) < occupancyPollMs)
        continue
      var requested = Object.assign({}, occupancyRequestedAt)
      requested[mode] = now
      occupancyRequestedAt = requested
      fetchCrowdingMode(mode)
    }
  }

  function fetchCrowdingMode(mode) {
    var path = Api.vehiclePosPath(mode)
    if (!path)
      return
    liveBackend.requestBinary(Api.BASE_URL + path, function(result) {
      if (!result.ok)
        return
      var parsed = {}
      try {
        parsed = Crowding.parseOccupancy(Crowding.fromBase64(result.data))
      } catch (e) {
        return
      }
      var feeds = Object.assign({}, occupancyByMode)
      feeds[mode] = parsed
      occupancyByMode = feeds
      var fetched = Object.assign({}, occupancyFetchedAt)
      fetched[mode] = Date.now()
      occupancyFetchedAt = fetched
      rebuildOccupancy(fetched[mode])
      reprojectCrowding()
    })
  }

  function dayKey(now) {
    var d = new Date(now)
    return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
  }

  function maybeNotify(now) {
    if (!notify || !connected)
      return

    var today = dayKey(now)
    if (sentDay !== today) {
      sentDay = today
      sentTripIds = ({
      })
    }
    var event = Model.notificationFor(board, activePlace, now, sentTripIds)
    if (!event)
      return

    var next = {
    }
    for (var key in sentTripIds) next[key] = true
    next[event.key] = true
    sentTripIds = next
    notification.command = ["omarchy-notification-send", "--app-name", "Transport NSW", "-g", Model.glyphFor(pillMode), "-u", "critical", "-r", Model.notificationTag(event.key), Model.escapeMarkup(event.headline), Model.escapeMarkup(event.body)]
    if (!notification.running)
      notification.running = true
  }

  function searchStops(text, callback) {
    if (quotaBlocked()) {
      searchSerial++
      searchDebounce.stop()
      if (searchRequest && typeof searchRequest.abort === "function")
        searchRequest.abort()

      searchRequest = null
      if (callback)
        callback([])

      return
    }
    pendingSearchText = String(text || "").trim()
    pendingSearchCallback = callback
    searchSerial++
    if (searchRequest && typeof searchRequest.abort === "function")
      searchRequest.abort()

    searchRequest = null
    if (pendingSearchText.length < 2) {
      searchDebounce.stop()
      callback([])
      return
    }
    searchDebounce.restart()
  }

  // Nearby-stop lookups keep one in-flight request per slot ("origin" /
  // "destination") so picking the destination never cancels the origin's.
  property var nearbySlots: ({})
  function nearbyStops(lat, lon, callback, slot) {
    var key = String(slot || "origin")
    var slots = nearbySlots
    var state = slots[key] || { serial: 0, request: null }
    state.serial++
    var serial = state.serial
    if (state.request && typeof state.request.abort === "function")
      state.request.abort()
    state.request = null
    slots[key] = state
    nearbySlots = slots
    function complete(result) {
      var current = root.nearbySlots[key]
      if (!current || serial !== current.serial) {
        root.lastNearbyNote = key + ": stale"
        return
      }
      current.request = null
      root.noteRateLimit(result)
      root.lastNearbyNote = key + ": " + (result.ok ? "ok " + result.data.length : "failed " + result.kind)
      if (callback)
        callback(result.ok ? result.data : [])
    }
    if (!isFinite(lat) || !isFinite(lon) || quotaBlocked()) {
      lastNearbyNote = key + ": skipped (coords/quota)"
      if (callback)
        callback([])
      return
    }
    if (demoMode || !connected) {
      lastNearbyNote = key + ": skipped (demo/offline)"
      if (callback)
        callback([])
      return
    }
    state.request = liveBackend.request(Api.coordPath(lat, lon, 800), function(response) {
      if (response.ok)
        response.data = Api.parseNearby(response.data)

      complete(response)
    })
  }

  // Minutes of the journey's first walking leg; 0 when it starts on the vehicle.
  function walkMinutesOf(journey) {
    var legs = journey && Array.isArray(journey.legs) ? journey.legs : []
    if (!legs.length || legs[0].kind !== "walk") return 0
    return Math.max(0, Math.round(Number(legs[0].durationSec || 0) / 60))
  }

  function planFrom(location, destination, callback, walkMinutes, endWalkMinutes, endWalkTo) {
    var walkEstimate = Math.max(0, Math.round(Number(walkMinutes) || 0))
    var endWalk = Math.max(0, Math.round(Number(endWalkMinutes) || 0))
    var destinationIsCoord = destination && !destination.isStop
      && isFinite(destination.lat) && isFinite(destination.lon)
    if (!location || !destination || (!destinationIsCoord && !Api.isStopId(destination.id))) {
      lastPlanNote = "rejected: " + JSON.stringify({ hasLocation: !!location, dest: destination ? destination.id : null })
      if (callback)
        callback([])

      return
    }
    lastPlanNote = "planning " + (location.isStop ? location.id : "coord") + " → " + (destinationIsCoord ? "coord" : destination.id) + " endWalk=" + endWalk
    lastNewTripLocation = location
    lastNewTripDestination = destination
    journeyError = ""
    journeyBoard = []
    journeyPlace = null
    journeyWalkMinutes = 0
    journeyRows.clear()
    if (journeyRequest && typeof journeyRequest.abort === "function")
      journeyRequest.abort()

    journeyRequest = null
    if (!connected || quotaBlocked()) {
      if (callback)
        callback([])

      return
    }

    var origin = location.isStop ? location.id : {
      "lat": location.lat,
      "lon": location.lon
    }
    var arriveVia = destination.arriveVia && Api.isStopId(destination.arriveVia.id)
      ? destination.arriveVia : destination
    var destinationSpec = destinationIsCoord ? {
      "lat": destination.lat,
      "lon": destination.lon
    } : destination.id
    function complete(result) {
      journeyRequest = null
      noteRateLimit(result)
      if (!result.ok) {
        lastPlanNote += " failed=" + result.kind
        journeyError = result.error
        if (callback)
          callback([])

        return
      }
      var list = Model.appendEndWalk(result.data.slice(0, Api.MAX_JOURNEYS), endWalk, endWalkTo)
      lastPlanNote += " parsed=" + result.data.length + (result.data.length ? " first=" + Math.round((Number(result.data[0].departMs) - Date.now()) / 60000) + "m" : "")
      // Walk = the caller's estimate to the chosen stop; only when planning
      // from a coordinate does the journey's own first walking leg apply.
      journeyWalkMinutes = walkEstimate > 0 ? walkEstimate : (list.length ? walkMinutesOf(list[0]) : 0)
      var firstRide = null
      if (list.length && list[0].legs) for (var l = 0; l < list[0].legs.length; l++) if (list[0].legs[l].kind === "ride") {
        firstRide = list[0].legs[l]
        break
      }
      var boardPlace = {
        "id": "newtrip",
        "name": String(location.name || "New trip").split(",")[0],
        "stopId": location.isStop ? String(location.id || "") : "",
        "stopName": firstRide ? firstRide.from : String(location.name || ""),
        "destStopId": String(arriveVia.id || ""),
        "destStopName": String(arriveVia.name || arriveVia.shortName || ""),
        "destAddress": destinationIsCoord ? String(destination.name || destination.shortName || "") : "",
        "destLat": destinationIsCoord ? Number(destination.lat) : null,
        "destLon": destinationIsCoord ? Number(destination.lon) : null,
        "lines": [],
        "destination": "",
        "modes": [],
        "walkMinutes": journeyWalkMinutes,
        "ssid": ""
      }
      try {
        journeyBoard = Model.markDominated(Model.boardFromJourneys(list, boardPlace, Date.now()))
        lastPlanNote += " board=" + journeyBoard.length
      } catch (e) {
        lastPlanNote += " boardError=" + String(e)
        journeyBoard = []
      }
      journeyPlace = boardPlace
      reprojectJourney(Date.now())
      refreshCrowding()
      if (callback)
        callback(list)
    }

    if (demoMode)
      demoBackend.plan(complete)
    else
      journeyRequest = liveBackend.request(Api.tripPath(origin, destinationSpec, 4), function(response) {
        if (response.ok)
          response.data = Api.parseJourneys(response.data)

        complete(response)
      })
  }

  function journeyLegsFor(depId) {
    var wanted = String(depId || "")
    for (var i = 0; i < journeyBoard.length; i++) if (String(journeyBoard[i].id) === wanted)
      return Model.legRows(journeyBoard[i], occupancy)

    return []
  }

  // Scriptable New trip actions (omarchy-shell tfnsw newtripUse / newtripSave).
  signal newTripAction(string name)
  function requestNewTripAction(name) { newTripAction(String(name || "")) }

  function setNewTripOpen(value) {
    newTripOpen = value === true
    if (newTripOpen) {
      refreshCrowding()
      if (lastNewTripLocation && lastNewTripDestination)
        planFrom(lastNewTripLocation, lastNewTripDestination, null)
    }
  }

  function writeCache() {
    var text = JSON.stringify({
      "savedAt": lastPolledMs,
      "placeId": activePlace ? activePlace.id : "",
      "stopId": activePlace ? activePlace.stopId : "",
      "destStopId": activePlace ? activePlace.destStopId || "" : "",
      "destAddress": activePlace ? activePlace.destAddress || "" : "",
      "destLat": activePlace ? activePlace.destLat : null,
      "destLon": activePlace ? activePlace.destLon : null,
      "departures": departures.slice(0, Api.MAX_STOP_EVENTS)
    }) + "\n"
    if (text.length < Api.MAX_RESPONSE_BYTES)
      cacheFile.setText(text)
  }

  function statusLine() {
    return "v" + version + " phase=" + phase + " demo=" + demoMode + " key=" + (apiKey !== "" ? "present" : "absent") + " places=" + places.length + " stops=" + stops.length + " active=" + (activePlace ? activePlace.id : "none") + " rows=" + rows.count + " journeys=" + journeyRows.count + " journeyError=" + JSON.stringify(journeyError) + " plan=" + JSON.stringify(lastPlanNote) + " nearby=" + JSON.stringify(lastNearbyNote) + " backoff=" + pollBackoff + " quotaUntil=" + (quotaBackoffUntil ? new Date(quotaBackoffUntil).toISOString() : "none") + " last=" + (lastPolledAt || "never") + " error=" + (lastErrorKind || "none")
  }

  Component.onCompleted: prepareDirs.running = true
  // A lookup deferred because the keyring was busy runs once it frees up
  // deferred to the next event loop turn so the busy binding never re-enters itself.
  onCredentialBusyChanged: {
    if (!credentialBusy) {
      Qt.callLater(root.retryDeferredLookup)
    }
  }
}
