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
  readonly property string version: manifest && manifest.version ? String(manifest.version) : "0.6.1"

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

  // Here-tab state.
  property var hereResults: []
  property string hereSearchText: ""
  property var hereLocation: null
  property var nearestStop: null
  property var lastJourneys: []
  property string placeName: ""
  property string placeStopId: ""
  property string placeStopName: ""
  property string placeDestStopId: ""
  property string placeDestStopName: ""
  property string placeLines: ""
  property string placeDestination: ""
  property var placeModes: []
  property int placeWalk: 0
  property string placeSsid: ""
  property bool placeFilterOpen: false
  // The kit's controls have different natural heights. Measure one bordered
  // button once so fields, dropdowns and adjacent buttons line up.
  readonly property int controlHeight: controlReference.implicitHeight
  readonly property string family: Style.font.menuFamily
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color muted: Color.muted
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    opened = true
    keyDraft = ""
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {
      }
      tab = payload.tab === "here" ? "here" : "settings"
    } catch (e) {
      tab = "settings"
    }
    if (service && !service.configured)
      tab = "settings"

    if (service) {
      selectedPlaceId = service.activePlace ? service.activePlace.id : ""
      loadPlace(selectedPlaceId)
      service.setHereOpen(tab === "here")
    }
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      // The Here tab exists to type into: hand the keyboard to its field.
      if (root.tab === "here" && paneLoader.item && typeof paneLoader.item.focusField === "function")
        paneLoader.item.focusField()
    })
  }

  function close() {
    opened = false
    if (service)
      service.setHereOpen(false)
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
    if (from) parts.push(from + (place.destStopName ? " → " + Model.boardStopName(place.destStopName) : ""))
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

    placeDestStopId = loc.id
    placeDestStopName = loc.name
    destinationSearchText = ""
    destinationSearchComplete = false
    destinationResults = []
  }

  function clearDestination() {
    if (service)
      service.searchStops("", function() {})

    placeDestStopId = ""
    placeDestStopName = ""
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

      root.destinationResults = root.mergedSearchResults(local, results, true, root.placeStopId)
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

  function searchHere(text) {
    if (!service)
      return

    var query = String(text || "").trim()
    hereSearchText = String(text || "")
    var local = Model.matchStops(service.stops, query)
    hereResults = local
    nearestStop = firstSearchResult(local)
    if (query.length < 3) {
      service.searchStops("", function() {})
      return
    }
    service.searchStops(query, function(results) {
      if (query !== String(root.hereSearchText || "").trim())
        return

      root.hereResults = root.mergedSearchResults(local, results, false, "")
      root.nearestStop = null
      for (var i = 0; i < root.hereResults.length; i++) if (root.hereResults[i].isStop) {
        root.nearestStop = root.hereResults[i]
        break
      }
    })
  }

  function pickHere(loc) {
    if (service)
      service.searchStops("", function() {})

    hereLocation = loc
    hereSearchText = loc.name
    hereResults = []
    if (service)
      service.planFrom(loc, function(journeys) {
        root.lastJourneys = journeys
      })
  }

  function saveHereAsPlace() {
    if (!service || !nearestStop)
      return

    var walk = 0
    if (lastJourneys.length && lastJourneys[0].legs) {
      for (var i = 0; i < lastJourneys[0].legs.length; i++) {
        if (lastJourneys[0].legs[i].kind === "walk") {
          walk = Math.max(0, Math.round(lastJourneys[0].legs[i].durationSec / 60))
          break
        }
      }
    }
    var id = ConfigStore.newPlaceId(service.places)
    var destination = service.activePlace && String(service.activePlace.stopId) !== String(nearestStop.id)
      ? service.activePlace : null
    service.addPlace({
      "id": id,
      "name": Model.displayStopName(nearestStop.name) || "New place",
      "stopId": nearestStop.id,
      "stopName": nearestStop.name,
      "destStopId": destination ? destination.stopId : "",
      "destStopName": destination ? destination.stopName : "",
      "lines": [],
      "destination": "",
      "modes": nearestStop.modes || [],
      "walkMinutes": walk,
      "ssid": ""
    })
    selectedPlaceId = id
    loadPlace(id)
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
      service.setHereOpen(tab === "here")
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
      width: Math.min(Style.space(720), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(760), parent.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

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

          implicitHeight: Math.max(titleRow.implicitHeight, tabs.implicitHeight)
          height: implicitHeight

          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
          }

          Row {
            id: titleRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            TransportMark {
              iconSize: Style.font.display
              colorful: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.tab === "here" ? "From here" : "Transport NSW settings"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
            }
          }

          ButtonGroup {
            id: tabs

            anchors.right: closeButton.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            options: [{
              "value": "settings",
              "label": "Settings"
            }, {
              "value": "here",
              "label": "Here"
            }]
            value: root.tab
            onChanged: function(value) {
              root.tab = value
            }
          }

          PanelActionButton {
            id: closeButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅖"
            tooltipText: "Close"
            foreground: root.muted
            fontFamily: root.family
            onClicked: root.dismiss()
          }
        }

        PanelSeparator {
          id: rule

          anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            topMargin: Style.space(12)
          }
        }

        Caption {
          id: quotaCaption

          anchors.top: rule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(10)
          visible: root.service && root.service.quotaBackoffUntil > 0
          text: root.quotaCaptionText()
          color: Color.urgent
        }

        Loader {
          id: paneLoader

          sourceComponent: root.tab === "here" ? herePane : settingsPane

          anchors {
            top: quotaCaption.visible ? quotaCaption.bottom : rule.bottom
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            topMargin: Style.space(14)
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
    id: herePane

    Flickable {
      function focusField() { hereField.forceActiveFocus() }

      clip: true
      contentWidth: width
      contentHeight: hereColumn.height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: hereColumn

        width: parent.width
        spacing: Style.spacing.xxl

        Caption {
          width: parent.width
          text: "Plan to " + (root.service && root.service.activePlace ? root.service.activePlace.stopName : "your active place") + "."
        }

        Dropdown {
          visible: root.service && root.service.effectivePlaces.length > 1
          width: parent.width
          label: "Plan to"
          foreground: root.foreground
          fontFamily: root.family
          options: root.service ? root.service.effectivePlaces.map(function(p) {
            return {
              "value": p.id,
              "label": Model.placeLabel(p),
              "tooltip": Model.placeTooltip(p)
            }
          }) : []
          value: root.service && root.service.activePlace ? root.service.activePlace.id : ""
          onChanged: function(value) {
            root.service.setActivePlace(value, true)
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm

          FieldLabel {
            text: "Where are you?"
          }

          TextField {
            id: hereField

            width: parent.width
            height: root.controlHeight
            verticalAlignment: TextInput.AlignVCenter
            text: root.hereSearchText
            placeholderText: "Address, landmark or stop…"
            foreground: root.foreground
            onTextEdited: root.searchHere(text)
            onAccepted: {
              var first = root.firstSearchResult(root.hereResults)
              if (first)
                root.pickHere(first)
            }
          }

          Repeater {
            model: root.hereResults

            delegate: Item {
              required property var modelData

              width: hereColumn.width
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

              Button {
                id: resultButton

                width: parent.width
                visible: modelData.isDivider !== true
                leftAlign: true
                bordered: true
                text: root.searchResultText(modelData)
                foreground: root.foreground
                fontFamily: root.family
                onClicked: root.pickHere(modelData)
              }
            }
          }
        }

        Caption {
          width: parent.width
          visible: root.service && root.service.journeyError !== ""
          text: root.service ? root.service.journeyError : ""
          color: Color.urgent
        }

        Repeater {
          model: root.service ? root.service.journeyRows : null

          delegate: CursorSurface {
            width: hereColumn.width
            foreground: root.foreground
            implicitHeight: journeyLayout.implicitHeight + Style.spacing.xl

            Column {
              id: journeyLayout

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.xs

              Row {
                width: parent.width

                ModeBadge {
                  size: Style.font.icon
                  mode: model.mode
                  colorful: true
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "  Leave " + model.leaveText + " · " + model.departText + " → " + model.arriveText
                  color: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: model.summary
                elide: Text.ElideRight
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: model.changes + (model.changes === 1 ? " change" : " changes") + (model.realtime ? " · realtime" : " · scheduled") + (model.alertTitle ? " · " + model.alertTitle : "")
                color: model.alertTitle ? Color.urgent : root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Button {
          visible: root.nearestStop !== null && root.lastJourneys.length > 0
          bordered: true
          text: "Save as place"
          foreground: root.foreground
          fontFamily: root.family
          onClicked: root.saveHereAsPlace()
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
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
