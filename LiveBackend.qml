import QtQuick
import Quickshell.Io
import "Api.js" as Api

// One serialized curl worker. Secrets enter curl only through stdin config;
// redirects are not enabled and every completion is generation-gated.
QtObject {
  id: root
  property string apiKey: ""
  property int generation: 0
  property var inflight: []
  property var queue: []
  property var operation: null
  property string output: ""
  readonly property int requestTimeoutMs: 25000
  readonly property int binaryMaxBytes: 4 * 1024 * 1024
  readonly property string binaryHelperPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/tfnsw-fetch-b64")).replace(/^file:\/\//, ""))

  function forget(entry) {
    var keep = []
    for (var i = 0; i < inflight.length; i++) if (inflight[i] !== entry) keep.push(inflight[i])
    inflight = keep
  }
  function curlEscape(value) { return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"") }

  function enqueue(url, binary, callback) {
    if (!apiKey) { callback(Api.errorResult("credential", "No API key configured.")); return null }
    if (/[\r\n]/.test(apiKey)) { callback(Api.errorResult("credential", "The API key contains unsupported line breaks.")); return null }
    var token = generation
    if (!Api.sameOrigin(url, Api.BASE_URL)) {
      callback(Api.errorResult("protocol", "Refused a request outside the Transport NSW API origin.")); return null
    }
    var entry = { url: url, key: apiKey, generation: token, done: false, superseded: false,
                  binary: binary === true, callback: callback, complete: null, abort: null }
    entry.complete = function(result) {
      if (entry.done) return
      entry.done = true; root.forget(entry)
      if (!entry.superseded && token === root.generation) entry.callback(result)
    }
    entry.abort = function() {
      if (entry.done) return
      entry.superseded = true
      entry.complete(Api.errorResult("network", "Request superseded."))
      if (root.operation === entry && worker.running) { worker.signal(15); killDeadline.restart() }
      else root.startNext()
    }
    var active = inflight.slice(); active.push(entry); inflight = active
    var pending = queue.slice(); pending.push(entry); queue = pending
    startNext()
    return entry
  }

  function request(path, callback) {
    return enqueue(Api.BASE_URL + String(path || ""), false, callback)
  }

  function requestBinary(url, callback) {
    return enqueue(String(url || ""), true, callback)
  }

  function startNext() {
    if (operation || worker.running) return
    var pending = queue.slice(), entry = null
    while (pending.length && !entry) { var candidate = pending.shift(); if (!candidate.done) entry = candidate }
    queue = pending
    if (!entry) return
    operation = entry; output = ""
    worker.command = entry.binary
      ? ["bash", binaryHelperPath, entry.url]
      : ["curl", "-sS", "--proto", "=https", "--max-filesize",
          String(Api.MAX_RESPONSE_BYTES), "--max-time", String(Math.ceil(requestTimeoutMs / 1000)),
          "-K", "-", "-w", "\n%{http_code}", entry.url]
    worker.stdinEnabled = true
    deadline.restart(); worker.running = true
  }

  function parseResult(text, exitCode) {
    var raw = String(text || "")
    if (exitCode === 63 || raw.length > Api.MAX_RESPONSE_BYTES + 8)
      return Api.errorResult("protocol", "The Transport NSW response was too large.")
    var marker = raw.lastIndexOf("\n")
    var status = parseInt(marker >= 0 ? raw.slice(marker + 1).trim() : "", 10)
    var body = marker >= 0 ? raw.slice(0, marker) : raw
    if (!isNaN(status) && status >= 300 && status < 400)
      return Api.errorResult("protocol", "Unexpected redirect.")
    var parsed = Api.parseResponse(isNaN(status) ? 0 : status, body)
    if (exitCode !== 0) {
      if (!parsed.ok && parsed.status > 0) return parsed
      return Api.errorResult("network", "Could not reach the Transport NSW API (curl exited " + exitCode + ").")
    }
    return parsed
  }

  function parseBinaryResult(text, exitCode) {
    var raw = String(text || "")
    if (exitCode === 90 || raw.length > binaryMaxBytes)
      return Api.errorResult("protocol", "The Transport NSW vehicle-position feed was too large.")
    if (exitCode !== 0)
      return Api.errorResult("network", "Could not reach the Transport NSW vehicle-position feed (fetch exited " + exitCode + ").")
    return { ok: true, status: 200, kind: "", error: "", data: raw }
  }

  function supersede() {
    var requests = inflight.slice()
    for (var i = 0; i < requests.length; i++) requests[i].abort()
    inflight = []; queue = []
    if (worker.running) { worker.signal(15); killDeadline.restart() }
    generation++
  }

  property Timer deadline: Timer {
    interval: root.requestTimeoutMs + 1000
    onTriggered: {
      var entry = root.operation
      if (entry && !entry.done) entry.complete(Api.errorResult("network", "The Transport NSW API request timed out."))
      if (worker.running) { worker.signal(15); killDeadline.restart() }
    }
  }
  property Timer killDeadline: Timer { interval: 2000; onTriggered: if (worker.running) worker.signal(9) }
  property Process worker: Process {
    command: []
    environment: ({
      "TFNSW_MAX_BYTES": String(root.operation && root.operation.binary ? root.binaryMaxBytes : Api.MAX_RESPONSE_BYTES)
    })
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.output = String(text || "") }
    onStarted: {
      var entry = root.operation
      if (!entry || entry.done) { worker.signal(15); killDeadline.restart(); return }
      worker.write("request = \"GET\"\nheader = \"Authorization: apikey "
        + root.curlEscape(entry.key) + "\"\n"
        + (entry.binary ? "" : "header = \"Accept: application/json\"\n"))
      worker.stdinEnabled = false
    }
    onExited: function(exitCode) {
      var entry = root.operation, text = root.output
      deadline.stop(); killDeadline.stop(); root.operation = null; root.output = ""; worker.stdinEnabled = true
      if (entry && !entry.done) entry.complete(entry.binary
        ? root.parseBinaryResult(text, exitCode) : root.parseResult(text, exitCode))
      root.startNext()
    }
  }
}
