import QtQuick
import Quickshell.Io

// Serialized secret-tool adapter. The API key is written only to stdin.
QtObject {
  id: root
  readonly property bool busy: pending || process.running
  property bool pending: false
  property int token: 0
  property int processToken: 0
  property string operation: ""
  property string operationKey: ""
  property string output: ""
  readonly property int maxLookupBytes: 4096
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/tfnsw-bounded")).replace(/^file:\/\//, ""))

  signal keyReady(string key)
  signal missing()
  signal cleared()
  signal failed(string message)

  function begin(kind, key) {
    if (busy || (kind === "store" && !key)) { if (kind !== "lookup") failed("A keyring operation is already in progress."); return false }
    operation = kind; operationKey = String(key || ""); output = ""
    processToken = ++token; pending = true
    if (kind === "store") {
      process.command = ["bash", helperPath, "secret-tool", "store", "--label=Transport NSW API key (Omarchy)",
        "service", "tfnsw-departures", "account", "apikey"]
      process.stdinEnabled = true
    } else if (kind === "clear") {
      process.command = ["bash", helperPath, "secret-tool", "clear", "service", "tfnsw-departures", "account", "apikey"]
      process.stdinEnabled = false
    } else {
      process.command = ["bash", helperPath, "secret-tool", "lookup", "service", "tfnsw-departures", "account", "apikey"]
      process.stdinEnabled = false
    }
    deadline.restart(); process.running = true; return true
  }
  function store(key) { return begin("store", key) }
  function clear() { return begin("clear", "") }
  function lookup() { return begin("lookup", "") }

  function finish(exitCode) {
    if (!pending || processToken !== token) return
    deadline.stop()
    var kind = operation, key = operationKey, text = output
    pending = false; operation = ""; operationKey = ""; output = ""; processToken = 0
    if (kind === "store") {
      if (exitCode === 0) keyReady(key); else failed("Could not write the API key to the keyring.")
    } else if (kind === "clear") {
      if (exitCode === 0 || exitCode === 1) cleared(); else failed("Could not remove the API key from the keyring.")
    } else {
      var truncated = exitCode === 90 || text.length >= maxLookupBytes
      var found = exitCode === 0 && !truncated ? text.split(/\r?\n/)[0].trim() : ""
      if (found) keyReady(found); else missing()
    }
  }

  property Timer deadline: Timer {
    interval: 60000
    onTriggered: {
      if (!root.pending) return
      var kind = root.operation
      root.token++; root.pending = false; root.operation = ""; root.operationKey = ""; root.output = ""; root.processToken = 0
      if (process.running) process.signal(15)
      killDeadline.restart()
      root.failed("Timed out while " + (kind === "store" ? "storing" : kind === "clear" ? "removing" : "reading") + " the API key.")
    }
  }
  property Timer killDeadline: Timer { interval: 2000; onTriggered: if (process.running) process.signal(9) }
  property Process process: Process {
    command: []
    environment: ({ "TFNSW_MAX_BYTES": String(root.maxLookupBytes) })
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (root.pending && root.processToken === root.token) root.output = String(text || "") }
    onStarted: {
      if (!root.pending || root.processToken !== root.token) { process.signal(15); killDeadline.restart(); return }
      if (root.operation === "store") { process.write(root.operationKey + "\n"); process.stdinEnabled = false }
    }
    onExited: function(exitCode) { deadline.stop(); killDeadline.stop(); root.finish(exitCode); process.stdinEnabled = false }
  }
}
