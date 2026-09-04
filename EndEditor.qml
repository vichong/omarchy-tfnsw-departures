import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui
import "Api.js" as Api
import "Model.js" as Model

// Shared address-or-stop editor used by both saved trips and New trip.
Column {
  id: root

  required property var service
  property bool destination: false
  property string label: destination ? "Going to (optional)" : "Leaving from"
  property string kind: destination ? "stop" : "address"
  property string stopId: ""
  property string stopName: ""
  property string address: ""
  property var lat: null
  property var lon: null
  property int walkMinutes: 0
  property bool walkEstimated: false
  property var nearby: []
  property string excludedStopId: ""
  property color foreground: Color.foreground
  property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  property string fontFamily: Style.font.family

  property string searchText: ""
  property var results: []
  property string modeFilter: ""
  property bool nearbyExpanded: false
  property bool scriptedPickPending: false
  property bool loading: false
  property var chosenStop: null
  readonly property var modeOptions: [{ "id": "", "label": "All" }, { "id": "train", "label": "Train" }, { "id": "metro", "label": "Metro" }, { "id": "lightrail", "label": "Light rail" }, { "id": "bus", "label": "Bus" }, { "id": "ferry", "label": "Ferry" }]

  signal edited()

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  function endpoint() {
    return {
      "kind": kind,
      "stopId": stopId,
      "stopName": stopName,
      "address": kind === "address" ? address : "",
      "lat": kind === "address" ? lat : null,
      "lon": kind === "address" ? lon : null,
      "walkMinutes": walkMinutes,
      "walkEstimated": kind === "address" && walkEstimated,
      "nearby": nearby
    }
  }

  function loadEnd(value, defaultKind) {
    var end = value || {}
    loading = true
    kind = end.kind === "address" || end.kind === "stop" ? end.kind : defaultKind
    stopId = String(end.stopId || "")
    stopName = String(end.stopName || "")
    address = String(end.address || "")
    lat = end.lat === undefined ? null : end.lat
    lon = end.lon === undefined ? null : end.lon
    walkMinutes = Math.max(0, Math.min(60, Math.round(Number(end.walkMinutes) || 0)))
    walkEstimated = kind === "address" && end.walkEstimated === true
    nearby = []
    chosenStop = stopId ? { "id": stopId, "name": stopName, "isStop": true, "modes": [] } : null
    searchText = ""
    results = []
    modeFilter = ""
    nearbyExpanded = false
    loading = false
    if (kind === "address" && address && isFinite(lat) && isFinite(lon))
      findNearby(false)
  }

  function clear() {
    stopId = ""
    stopName = ""
    address = ""
    lat = null
    lon = null
    walkMinutes = 0
    walkEstimated = false
    nearby = []
    chosenStop = null
    searchText = ""
    results = []
    edited()
  }

  function setKind(nextKind) {
    if (kind === nextKind)
      return
    kind = nextKind
    clear()
  }

  function mergedResults(local, remote, wantStops) {
    var merged = local.slice()
    var seen = {}
    for (var i = 0; i < local.length; i++) seen[String(local[i].id)] = true
    var more = []
    var list = remote && isFinite(remote.length) ? remote : []
    for (var r = 0; r < list.length; r++) {
      var item = list[r]
      if (!item || !!item.isStop !== wantStops || String(item.id || "") === String(excludedStopId)
          || seen[String(item.id)]) continue
      seen[String(item.id)] = true
      more.push(item)
    }
    if (more.length)
      merged = merged.concat([{ "isDivider": true, "name": "More" }], more)
    return merged
  }

  function firstResult() {
    for (var i = 0; i < results.length; i++) if (results[i] && !results[i].isDivider)
      return results[i]
    return null
  }

  function search(text) {
    if (!service)
      return
    var query = String(text || "").trim()
    searchText = String(text || "")
    var wantStops = kind === "stop"
    var local = wantStops ? Model.matchStops(service.stops, query).filter(function(item) {
      return String(item.id) !== String(root.excludedStopId)
    }) : []
    results = local
    if (query.length < 3) {
      service.searchStops("", function() {})
      maybeCompleteScriptedPick()
      return
    }
    service.searchStops(query, function(remote) {
      if (query !== String(root.searchText || "").trim())
        return
      root.results = root.mergedResults(local, remote, wantStops)
      root.maybeCompleteScriptedPick()
    })
    maybeCompleteScriptedPick()
  }

  function scriptedPick(text) {
    var query = String(text || "").trim()
    if (service) {
      var local = Model.matchStops(service.stops, query).filter(function(item) {
        return String(item.id) !== String(root.excludedStopId)
      })
      if (local.length) {
        if (kind !== "stop")
          setKind("stop")
        pick(local[0])
        return
      }
    }
    scriptedPickPending = true
    search(text)
  }

  function maybeCompleteScriptedPick() {
    if (!scriptedPickPending)
      return
    var first = firstResult()
    if (!first)
      return
    scriptedPickPending = false
    pick(first)
  }

  function pick(item) {
    if (!item)
      return
    if (service)
      service.searchStops("", function() {})
    searchText = ""
    results = []
    if (kind === "stop") {
      stopId = String(item.id || "")
      stopName = String(item.name || item.shortName || "")
      address = ""
      lat = null
      lon = null
      walkEstimated = false
      nearby = []
      chosenStop = item
      edited()
      return
    }
    address = String(item.name || item.shortName || "")
    lat = item.lat
    lon = item.lon
    stopId = ""
    stopName = ""
    walkEstimated = true
    chosenStop = null
    findNearby(true)
  }

  function findNearby(freshAddress) {
    if (!service || !address || !isFinite(lat) || !isFinite(lon)) {
      nearby = []
      edited()
      return
    }
    var wantedAddress = address
    var local = Model.nearestStops(service.stops, lat, lon, 8, 3000)
    nearby = local
    var selected = null
    for (var i = 0; i < local.length; i++) if (String(local[i].id) === String(stopId)) {
      selected = local[i]
      break
    }
    if (selected)
      chosenStop = selected
    if (local.length && (freshAddress === true || !stopId))
      chooseNearby(local[0], freshAddress === true)
    else
      edited()
    service.nearbyStops(lat, lon, function(apiStops) {
      if (root.kind !== "address" || root.address !== wantedAddress)
        return
      root.nearby = Model.mergeNearby(local, apiStops)
      for (var n = 0; n < root.nearby.length; n++) if (String(root.nearby[n].id) === String(root.stopId)) {
        root.chosenStop = root.nearby[n]
        break
      }
      if (!root.stopId && root.nearby.length)
        root.chooseNearby(root.nearby[0], freshAddress === true)
    }, destination ? "end-editor-destination" : "end-editor-origin")
  }

  function estimateFor(stop) {
    var estimate = Model.walkEstimate({ "lat": Number(lat), "lon": Number(lon) }, stop)
    return Math.max(0, Math.min(60, estimate))
  }

  function chooseNearby(stop, automatic) {
    if (!stop)
      return
    stopId = String(stop.id || "")
    stopName = String(stop.name || stop.shortName || "")
    chosenStop = stop
    if (walkEstimated || automatic === true) {
      walkEstimated = true
      walkMinutes = estimateFor(stop)
    }
    edited()
  }

  function filteredNearby() {
    if (!modeFilter)
      return nearby
    var out = []
    for (var i = 0; i < nearby.length; i++) {
      var modes = nearby[i].modes && isFinite(nearby[i].modes.length) ? nearby[i].modes : []
      if (modes.indexOf(modeFilter) !== -1)
        out.push(nearby[i])
    }
    return out
  }

  function resultText(item) {
    if (!item)
      return ""
    var name = item.isStop ? Model.displayStopName(item.name) : String(item.name || item.shortName || "")
    var modes = item.modes && isFinite(item.modes.length) ? item.modes : []
    var glyphs = []
    for (var i = 0; i < modes.length; i++) glyphs.push(Model.glyphFor(String(modes[i])))
    return glyphs.length ? name + "  ·  " + glyphs.join(" ") : name
  }

  function chipMode(stop) {
    var modes = stop && stop.modes && isFinite(stop.modes.length) ? stop.modes : []
    return modes.length ? String(modes[0]) : "bus"
  }

  function chipText(stop) {
    return Model.boardStopName(stop.name)
  }

  // "Crown St at Rainford St · Bus stop · 6 min walk": the chip label is
  // shortened, so the hover carries the whole story.
  function chipTooltip(stop) {
    var mode = chipMode(stop)
    var kind = mode === "train" || mode === "metro" ? "station"
      : mode === "ferry" ? "wharf" : "stop"
    var walk = Math.max(0, Math.round(Number(stop.walkMinutes) || 0))
    return String(stop.name || "") + " · " + Api.modeById(mode).label + " " + kind
      + (walk > 0 ? " · " + walk + " min walk" : "")
  }

  function focusField() {
    searchField.forceActiveFocus()
  }

  Row {
    width: root.width

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - kindToggle.width)
      textFormat: Text.PlainText
      text: root.label
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.space(9)
    }

    Row {
      id: kindToggle
      spacing: Style.space(4)

      Ui.Button {
        height: Style.space(24)
        text: "Address"
        selected: root.kind === "address"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(3)
        onClicked: root.setKind("address")
      }

      Ui.Button {
        height: Style.space(24)
        text: "Stop"
        selected: root.kind === "stop"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(3)
        onClicked: root.setKind("stop")
      }
    }
  }

  Row {
    width: root.width
    spacing: Style.space(8)

    Ui.TextField {
      id: searchField
      width: Math.max(0, parent.width - (clearButton.visible ? clearButton.width + parent.spacing : 0))
      height: Style.space(30)
      text: root.searchText || (root.kind === "address" ? root.address : root.stopName)
      placeholderText: root.kind === "address" ? "Search addresses…" : "Search stations and stops…"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextEdited: root.search(text)
      onAccepted: root.pick(root.firstResult())
    }

    Ui.Button {
      id: clearButton
      visible: root.destination && (root.stopId !== "" || root.address !== "")
      height: Style.space(30)
      text: "Clear"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(9)
      verticalPadding: Style.space(5)
      onClicked: root.clear()
    }
  }

  Repeater {
    model: root.results

    delegate: Item {
      required property var modelData
      width: root.width
      implicitHeight: modelData.isDivider ? moreLabel.implicitHeight : resultButton.height

      Text {
        id: moreLabel
        visible: modelData.isDivider === true
        textFormat: Text.PlainText
        text: "More"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.space(9)
      }

      Ui.Button {
        id: resultButton
        visible: modelData.isDivider !== true
        width: parent.width
        height: Style.space(30)
        text: root.resultText(modelData)
        leftAlign: true
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(9)
        verticalPadding: Style.space(5)
        onClicked: root.pick(modelData)
      }
    }
  }

  Column {
    width: root.width
    visible: root.kind === "address" && root.nearby.length > 0
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - modeChips.width - parent.spacing)
        textFormat: Text.PlainText
        text: root.destination ? "Arrive via" : "Nearest stops"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.space(9)
      }

      Row {
        id: modeChips
        spacing: Style.space(4)

        Repeater {
          model: root.modeOptions

          delegate: Ui.Button {
            required property var modelData
            height: Style.space(24)
            text: modelData.label
            selected: root.modeFilter === modelData.id
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.space(9)
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(3)
            onClicked: root.modeFilter = modelData.id
          }
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        readonly property var featured: Model.featureNearby(root.filteredNearby(), root.stopId, 15)
        model: root.nearbyExpanded ? featured.slice(0, 8)
          : featured.slice(0, 3).concat(featured.length > 3 ? [{ "isMore": true }] : [])

        delegate: StopChip {
          required property var modelData
          text: modelData.isMore ? "More…" : root.chipText(modelData)
          glyph: modelData.isMore ? "" : Model.glyphFor(root.chipMode(modelData))
          glyphColor: modelData.isMore ? root.foreground : Api.lineColor("", root.chipMode(modelData))
          tooltip: modelData.isMore ? "" : root.chipTooltip(modelData)
          selected: !modelData.isMore && String(modelData.id) === String(root.stopId)
          onClicked: {
            if (modelData.isMore) root.nearbyExpanded = true
            else root.chooseNearby(modelData, false)
          }
        }
      }
    }
  }

  Row {
    width: root.width
    visible: root.stopId !== ""
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰖃"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.space(15)
    }

    Ui.NumberField {
      anchors.verticalCenter: parent.verticalCenter
      fieldWidth: Style.space(58)
      value: root.walkMinutes
      from: 0
      to: 60
      foreground: root.walkEstimated ? root.muted : root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      field.height: Style.space(30)
      field.editable: !root.walkEstimated
      onModified: function(value) {
        root.walkMinutes = value
        root.edited()
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width
        - (estimateToggle.visible ? estimateToggle.width + parent.spacing : 0) - parent.spacing * 2)
      textFormat: Text.PlainText
      text: "min walk " + (root.destination ? "from " : "to ")
        + (root.kind === "stop" ? "this stop" : Model.boardStopName(root.stopName))
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Ui.Button {
      id: estimateToggle
      visible: root.kind === "address"
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(24)
      text: (root.walkEstimated ? "✓  " : "") + "estimate"
      selected: root.walkEstimated
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(7)
      verticalPadding: Style.space(3)
      onClicked: {
        root.walkEstimated = !root.walkEstimated
        if (root.walkEstimated && root.chosenStop)
          root.walkMinutes = root.estimateFor(root.chosenStop)
        root.edited()
      }
    }
  }

  // A nearby-stop chip: the mode pictogram in its Transport NSW colour at a
  // size that reads (14 units), the shortened stop name, and a hover tooltip
  // with the full name, mode and walk.
  component StopChip: Ui.BorderSurface {
    id: chip

    property string text: ""
    property string glyph: ""
    property color glyphColor: root.foreground
    property string tooltip: ""
    property bool selected: false
    signal clicked()

    radius: Style.space(4)
    implicitWidth: chipRow.implicitWidth + Style.space(16)
    implicitHeight: Style.space(24)
    width: implicitWidth
    height: implicitHeight
    color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : chipHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0)
    borderSpec: Border.flat(selected ? Color.accent
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), Style.space(1))

    Row {
      id: chipRow

      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.glyph !== ""
        textFormat: Text.PlainText
        text: chip.glyph
        color: chip.glyphColor
        font.family: root.fontFamily
        font.pixelSize: Style.space(14)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.text
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.85)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
      }
    }

    HoverHandler {
      id: chipHover

      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      onTapped: chip.clicked()
    }

    Ui.PanelToolTip {
      visible: chipHover.hovered && chip.tooltip !== ""
      text: chip.tooltip
      fontFamily: root.fontFamily
    }
  }
}
