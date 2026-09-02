import QtQuick
import Quickshell
import Quickshell.Io
import "Api.js" as Api
import "Model.js" as Model
import "ConfigStore.js" as ConfigStore
import "Demo.js" as Demo

// Orchestration only: generation guards a connection lifetime while the
// interchangeable backends own I/O and the JS modules own data shaping.
QtObject {
  id: root

  // Shell injection and persistent paths.
  property var shell: null
  property var manifest: null
  readonly property string version: manifest && manifest.version ? String(manifest.version) : "0.5.1"
  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string configDir: home + "/.config/omarchy/tfnsw-departures"
  readonly property string configPath: configDir + "/config.json"
  readonly property string cacheDir: home + "/.cache/omarchy/tfnsw-departures"
  readonly property string cachePath: cacheDir + "/board.json"
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/tfnsw-bounded")).replace(/^file:\/\//, ""))
  // Non-secret configuration. The API key lives only in CredentialManager.
  property bool configLoaded: false
  property string configError: ""
  property bool demoMode: false
  property var places: []
  property string activePlaceId: ""
  property bool autoPlace: true
  property int pollSeconds: ConfigStore.POLL_DEFAULT
  property bool notify: true
  property bool colorful: false
  readonly property var effectivePlaces: demoMode && places.length === 0 ? [Demo.defaultPlace()] : places
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
  property real underlineFraction: 0
  property string barCaption: ""
  property string lastPolledAt: ""
  property double lastPolledMs: 0
  property bool stale: false
  property bool polling: false
  property bool pollRequested: false
  property int pollBackoff: 0
  property double quotaBackoffUntil: 0
  property bool popupOpen: false
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
    running: root.departures.length > 0
    onTriggered: root.project(Date.now())
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

  // Here journeys refresh only while the overlay tab is visible.
  property ListModel journeyRows

  journeyRows: ListModel {
  }

  property var journeyRequest: null
  property string journeyError: ""
  property var lastHereLocation: null
  property bool hereOpen: false
  property Timer hereTimer

  hereTimer: Timer {
    interval: 60000
    repeat: true
    running: root.hereOpen && root.connected
    onTriggered: {
      if (root.lastHereLocation) {
        root.planFrom(root.lastHereLocation, null)
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
      "activePlaceId": activePlaceId,
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
    var connectionChanged = !configLoaded || demoMode !== c.demoMode
    var boardChanged = JSON.stringify(places) !== JSON.stringify(c.places) || activePlaceId !== c.activePlaceId
    var previousStopId = activePlace ? activePlace.stopId : ""
    var previousDestStopId = activePlace ? activePlace.destStopId : ""
    configError = parsed.error
    demoMode = c.demoMode
    if (demoMode) {
      quotaBackoffUntil = 0
      quotaBackoffTimer.stop()
    }
    places = c.places
    activePlaceId = c.activePlaceId
    autoPlace = c.autoPlace
    pollSeconds = c.pollSeconds
    notify = c.notify
    colorful = c.colorful
    var stopChanged = (activePlace ? activePlace.stopId : "") !== previousStopId
      || (activePlace ? activePlace.destStopId : "") !== previousDestStopId
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
    if (!found || wanted === activePlaceId)
      return false

    if (manual !== false)
      lastManualPlaceAt = Date.now()

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
    function complete(result) {
      if (token !== generation)
        return

      polling = false
      if (!root.activePlace || root.activePlace.id !== placeId
          || String(root.activePlace.stopId || "") !== stopId
          || String(root.activePlace.destStopId || "") !== destStopId) {
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
      liveBackend.request(path, function(response) {
        if (response.ok)
          response.data = trip ? Api.parseJourneys(response.data) : Api.parseDepartures(response.data)

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

  function resetBoard() {
    departures = []
    board = []
    rows.clear()
    alerts = []
    pillText = ""
    urgency = "none"
    nextLeaveMs = -1
    nextLineColor = ""
    underlineFraction = 0
    barCaption = ""
  }

  function project(now) {
    var place = activePlace
    if (!place) {
      resetBoard()
      return
    }
    board = Model.hasDestination(place)
      ? Model.boardFromJourneys(departures, place, now)
      : Model.boardFor(departures, place, now)
    var projected = Model.buildRows(board, place, now)
    rows.clear()
    for (var i = 0; i < projected.length && i < Model.MAX_ROWS; i++) rows.append(projected[i])
    alerts = Model.collectAlerts(board)
    pillText = Model.pillText(board, place, now)
    pillMode = Model.pillMode(board, place, now)
    urgency = Model.urgency(board, place, now)
    var barState = Model.barState(board, place, now)
    nextLeaveMs = barState.leaveMs
    nextLineColor = barState.lineColor
    underlineFraction = barState.fraction
    barCaption = barState.caption
    maybeNotify(now)
  }

  function legsFor(depId) {
    var wanted = String(depId || "")
    for (var i = 0; i < board.length; i++) if (String(board[i].id) === wanted)
      return Model.legRows(board[i])

    return []
  }

  function setPopupOpen(value) {
    popupOpen = value === true
    if (popupOpen && connected)
      poll()
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

  function planFrom(location, callback) {
    if (!connected || !activePlace || !location || quotaBlocked()) {
      if (callback)
        callback([])

      return
    }
    lastHereLocation = location
    journeyError = ""
    journeyRows.clear()
    if (journeyRequest && typeof journeyRequest.abort === "function")
      journeyRequest.abort()

    var origin = location.isStop ? location.id : {
      "lat": location.lat,
      "lon": location.lon
    }
    function complete(result) {
      journeyRequest = null
      noteRateLimit(result)
      if (!result.ok) {
        journeyError = result.error
        if (callback)
          callback([])

        return
      }
      var list = result.data.slice(0, Api.MAX_JOURNEYS)
      for (var i = 0; i < list.length; i++) journeyRows.append(Model.projectJourney(list[i], Date.now()))
      if (callback)
        callback(list)
    }

    if (demoMode)
      demoBackend.plan(complete)
    else
      journeyRequest = liveBackend.request(Api.tripPath(origin, activePlace.stopId, 4), function(response) {
        if (response.ok)
          response.data = Api.parseJourneys(response.data)

        complete(response)
      })
  }

  function setHereOpen(value) {
    hereOpen = value === true
    if (hereOpen && lastHereLocation)
      planFrom(lastHereLocation, null)
  }

  function writeCache() {
    var text = JSON.stringify({
      "savedAt": lastPolledMs,
      "placeId": activePlace ? activePlace.id : "",
      "stopId": activePlace ? activePlace.stopId : "",
      "destStopId": activePlace ? activePlace.destStopId || "" : "",
      "departures": departures.slice(0, Api.MAX_STOP_EVENTS)
    }) + "\n"
    if (text.length < Api.MAX_RESPONSE_BYTES)
      cacheFile.setText(text)
  }

  function statusLine() {
    return "v" + version + " phase=" + phase + " demo=" + demoMode + " key=" + (apiKey !== "" ? "present" : "absent") + " places=" + places.length + " active=" + (activePlace ? activePlace.id : "none") + " rows=" + rows.count + " backoff=" + pollBackoff + " quotaUntil=" + (quotaBackoffUntil ? new Date(quotaBackoffUntil).toISOString() : "none") + " last=" + (lastPolledAt || "never") + " error=" + (lastErrorKind || "none")
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
