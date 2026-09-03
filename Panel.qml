import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons
import "Api.js" as Api
import "Model.js" as Model

// Bar button plus the departures popup. The service owns transport state,
// this component owns the popup cursor and the shell IPC target.
Ui.Panel {
  id: root

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool ready: service !== null
  readonly property bool connected: ready && service.phase === "connected"
  readonly property color fg: Color.foreground
  readonly property color barFg: bar ? bar.barForeground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  // Per-instance layout setting in shell.json; the bar is icon-only by default.
  readonly property bool showCountdown: setting("showCountdown", false) === true
  readonly property color lineAccent: ready && service.nextLineColor !== "" ? service.nextLineColor : fg
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool alertsExpanded: false
  property string expandedDepId: ""
  readonly property int rowCount: ready ? service.rows.count : 0
  readonly property bool hasDisruption: {
    if (!ready)
      return false

    for (var i = 0; i < service.alerts.length; i++) if (service.alerts[i].disruption) {
      return true
    }
    return false
  }
  readonly property string boardStatus: ready && service.rows.count
    ? (service.rows.get(0).realtime ? "realtime" : "scheduled") : "scheduled"

  function moveCursor(delta) {
    if (rowCount)
      cursorIndex = Math.max(0, Math.min(rowCount - 1, cursorIndex + delta))
  }

  function switchPlace(delta) {
    if (!ready || service.effectivePlaces.length < 2)
      return

    var list = service.effectivePlaces
    var current = 0
    for (var i = 0; i < list.length; i++) if (service.activePlace && list[i].id === service.activePlace.id) {
      current = i
    }
    var next = (current + delta + list.length) % list.length
    service.setActivePlace(list[next].id, true)
    cursorIndex = 0
    expandedDepId = ""
  }

  function toggleExpanded(depId) {
    var id = String(depId || "")
    if (!ready || !service.legsFor(id).length)
      return

    expandedDepId = expandedDepId === id ? "" : id
  }

  function openOverlay(tab) {
    if (!bar || !bar.shell || typeof bar.shell.summon !== "function")
      return

    close()
    bar.shell.summon(moduleName, JSON.stringify({
      "tab": tab || "settings"
    }))
  }

  function openAlert(url) {
    var safe = Api.httpsOnly(url) || Api.ALERTS_URL
    Quickshell.execDetached(["gio", "open", safe])
  }

  moduleName: "io.github.vichong.tfnsw-departures"
  ipcTarget: "tfnsw"
  manageIpc: false
  onOpenedChanged: {
    if (ready)
      service.setPopupOpen(opened)

    if (!opened) {
      cursorIndex = 0
      cursorActive = false
      alertsExpanded = false
      expandedDepId = ""
    }
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // We own the target's single IpcHandler so transport-specific methods can
  // live beside the panel's standard open/close surface.
  IpcHandler {
    target: "tfnsw"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return root.ready ? root.service.statusLine() : "service: UNREACHABLE" }
    function refresh(): void { if (root.ready) root.service.refresh() }
    function settings(): void { root.openOverlay("settings") }
    function newtrip(): void { root.openOverlay("newtrip") }
    function newtripUse(): void { if (root.ready) root.service.requestNewTripAction("use") }
    function newtripSave(): void { if (root.ready) root.service.requestNewTripAction("save") }
    function here(): void { root.openOverlay("newtrip") }
    function place(id: string): string { return root.ready && root.service.setActivePlace(id, true) ? id : "unknown place" }
    function next(): string { return root.ready ? root.service.pillText : "" }
  }

  Ui.WidgetButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.ready && root.service.activePlace ? root.service.activePlace.name + " · " + (root.service.pillText || "No departure") : "Transport NSW for Omarchy"
    fixedWidth: pill.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.openOverlay("settings")
      } else if (mouseButton === Qt.MiddleButton) {
        if (root.ready)
          root.service.refresh()
      } else {
        root.toggle()
      }
    }

    Row {
      id: pill

      anchors.centerIn: parent
      spacing: Style.spacing.sm

      Item {
        id: markSlot

        // A bar glyph is centred by its font line box, not its painted
        // pixels, so a vector mark centred geometrically sits low and reads
        // taller. Take the painted box of a reference bar glyph instead: the
        // mark then has the same height and baseline as the shell's icons.
        // glyphRef is laid out exactly like the shell's OpticalGlyph (centred
        // Text, native rendering), so its baseline is where a real icon's
        // baseline lands; tightBoundingRect is baseline-relative.
        readonly property rect glyphBox: glyphMetrics.tightBoundingRect
        readonly property real glyphTop: glyphRef.y + glyphRef.baselineOffset + glyphBox.y

        anchors.verticalCenter: parent.verticalCenter
        width: mark.width
        height: button.height

        Text {
          id: glyphRef

          anchors.centerIn: parent
          opacity: 0
          textFormat: Text.PlainText
          text: "󰖩"
          font.family: root.family
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
        }

        TextMetrics {
          id: glyphMetrics

          font: glyphRef.font
          text: glyphRef.text
        }

        TransportMark {
          id: mark

          x: 0
          y: markSlot.glyphTop - 1
          iconSize: Math.max(1, markSlot.glyphBox.height)
          color: root.barFg
          colorful: root.ready && root.service.colorful
          dim: root.connected ? 1 : 0.45
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !button.vertical && root.connected && (root.showCountdown ? root.service.pillText !== "" : root.hasDisruption)
        textFormat: Text.PlainText
        text: (root.showCountdown ? root.service.pillText : "") + (root.hasDisruption ? (root.showCountdown ? " " : "") + "󰀦" : "")
        color: root.barFg
        opacity: root.showCountdown && root.service.rows.count && !root.service.rows.get(0).realtime ? 0.65 : 1
        font.family: root.family
        font.pixelSize: Style.font.body
      }
    }
  }

  Ui.KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(0)
    borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.40), Style.space(1))
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy)
          root.moveCursor(dy)
        else if (dx)
          root.switchPlace(dx)
      }
      onActivateRequested: if (root.ready && root.rowCount)
        root.toggleExpanded(root.service.rows.get(root.cursorIndex).depId)

      Column {
        id: column

        anchors.fill: parent
        spacing: Style.space(0)

        Item {
          id: hero

          width: parent.width
          implicitHeight: Style.space(14) + Math.max(Style.space(36), heroLabels.implicitHeight,
            heroActions.implicitHeight) + Style.space(12)

          TransportMark {
            id: heroMark

            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.top: parent.top
            anchors.topMargin: Style.space(14)
            iconSize: Style.space(28)
            colorful: true
            dim: root.connected ? 1 : 0.5
          }

          Column {
            id: heroLabels

            anchors.left: heroMark.right
            anchors.leftMargin: Style.space(11)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(11)
            anchors.top: parent.top
            anchors.topMargin: Style.space(14)
            spacing: Style.space(6)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.ready && root.service.activePlace ? root.service.activePlace.name : "Transport NSW for Omarchy"
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Item {
              id: placeSelectorSlot

              readonly property string selectorLabel: root.ready && root.service.activePlace
                ? Model.routeLabel(root.service.activePlace) : ""
              readonly property var selectorParts: selectorLabel.split(" → ")

              visible: root.ready && root.service.activePlace !== null
              width: parent.width
              implicitHeight: visible ? selectorChip.implicitHeight : 0
              height: implicitHeight

              Ui.Dropdown {
                id: placeDropdown

                // The kit control supplies the list popup and keyboard handling;
                // its own face is hidden and the chip below is what shows.
                opacity: 0
                width: selectorChip.width
                showLabel: false
                rowHeight: selectorChip.height
                foreground: root.fg
                fontFamily: root.family
                options: root.ready ? root.service.effectivePlaces.map(function(p) {
                  return { "value": p.id, "label": Model.routeLabel(p) }
                }).concat([{ "value": "newtrip", "label": "New trip…" }]) : []
                value: root.ready && root.service.activePlace ? root.service.activePlace.id : ""
                onChanged: function(value) {
                  if (value === "newtrip") {
                    root.openOverlay("newtrip")
                    return
                  }
                  root.service.setActivePlace(value, true)
                  root.cursorIndex = 0
                  root.expandedDepId = ""
                }
              }

              Rectangle {
                id: selectorChip

                implicitWidth: Math.min(placeSelectorSlot.width,
                  selectorCopy.implicitWidth + Style.space(16) + Style.space(6) + Style.space(9))
                implicitHeight: selectorCopy.implicitHeight + Style.space(8) + Style.space(2)
                width: implicitWidth
                height: implicitHeight
                radius: Style.space(4)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                border.width: Style.space(1)
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.40)

                Row {
                  id: selectorCopy

                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(6)

                  Text {
                    width: Math.min(implicitWidth, Math.max(0, parent.width - selectorArrow.width
                      - selectorTo.width - selectorChevron.width - parent.spacing * 3))
                    textFormat: Text.PlainText
                    text: placeSelectorSlot.selectorParts[0] || ""
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.85)
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    id: selectorArrow

                    visible: placeSelectorSlot.selectorParts.length > 1
                    textFormat: Text.PlainText
                    text: "→"
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    id: selectorTo

                    visible: selectorArrow.visible
                    width: Math.min(implicitWidth, Math.max(0, parent.width - parent.children[0].width
                      - selectorArrow.width - selectorChevron.width - parent.spacing * 3))
                    textFormat: Text.PlainText
                    text: placeSelectorSlot.selectorParts.length > 1 ? placeSelectorSlot.selectorParts[1] : ""
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.85)
                    font.family: root.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    id: selectorChevron

                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(9)
                    height: Style.space(6)
                    textFormat: Text.PlainText
                    text: "󰅀"
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
                    font.family: root.family
                    font.pixelSize: Style.space(9)
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: placeDropdown.toggle()
                }
              }
            }
          }

          Row {
            id: heroActions

            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.top: parent.top
            anchors.topMargin: Style.space(14)
            spacing: Style.space(4)

            Ui.PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
              fontFamily: root.family
              fontSize: Style.space(17)
              size: Style.space(24)
              bordered: true
              radius: Style.space(4)
              borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18), Style.space(1))
              onClicked: {
                if (root.ready) {
                  root.service.refresh()
                }
              }
            }

            Ui.PanelActionButton {
              iconText: "󰐕"
              tooltipText: "New trip"
              foreground: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
              fontFamily: root.family
              fontSize: Style.space(17)
              size: Style.space(24)
              bordered: true
              radius: Style.space(4)
              borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18), Style.space(1))
              onClicked: root.openOverlay("newtrip")
            }

            Ui.PanelActionButton {
              iconText: "󰒓"
              tooltipText: "Settings"
              foreground: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
              fontFamily: root.family
              fontSize: Style.space(17)
              size: Style.space(24)
              bordered: true
              radius: Style.space(4)
              borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18), Style.space(1))
              onClicked: root.openOverlay("settings")
            }
          }
        }

        // The leave window for the next catchable service: a track in the
        // line colour that fills as leave-in runs from 10 min to 0. This is
        // the urgency cue; the bar itself stays flat like the stock widgets.
        Item {
          id: leaveWindow

          readonly property bool active: root.connected && root.service.nextLeaveMs >= 0

          width: parent.width
          visible: active
          implicitHeight: active ? leaveCopy.implicitHeight + Style.space(9) + windowTrack.height + Style.space(13) : 0
          height: implicitHeight

          Row {
            id: leaveCopy
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            spacing: Style.space(10)

            Item {
              width: Style.space(15)
              height: Style.space(20)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰖃"
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.space(15)
              }
            }

            Column {
              width: Math.max(0, parent.width - parent.children[0].width - parent.spacing)
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: Model.leaveHeading(root.ready ? root.service.nextLeaveMs : 0)
                elide: Text.ElideRight
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.space(15)
                font.weight: Font.Bold
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.1
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: (root.ready && root.service.activePlace && root.service.activePlace.walkMinutes > 0
                  ? root.service.activePlace.walkMinutes + " min walk · " : "")
                  + (root.ready && root.service.nextLine ? root.service.nextLine : "")
                  + (root.ready && root.service.nextDestination ? " to " + root.service.nextDestination : "")
                elide: Text.ElideRight
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
                font.family: root.family
                font.pixelSize: Style.font.caption
                font.weight: Font.Normal
              }
            }
          }

          Rectangle {
            id: windowTrack

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: leaveCopy.bottom
            anchors.topMargin: Style.space(9)
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            height: Style.space(3)
            radius: Style.space(2)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Math.round(parent.width * (root.ready ? root.service.underlineFraction : 0))
              radius: parent.radius
              color: root.lineAccent
            }
          }
        }

        Column {
          width: parent.width
          visible: root.ready && root.service.alerts.length > 0

          // The board's alert band: tinted strip, status dot, chevron.
          Rectangle {
            width: parent.width
            implicitHeight: alertSummary.implicitHeight + Style.space(18)
            color: root.hasDisruption
              ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.05)
              : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.05)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(1)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Style.space(1)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.alertsExpanded = !root.alertsExpanded
            }

            Rectangle {
              id: alertDot

              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.hasDisruption ? Color.urgent : Color.accent
            }

            Text {
              id: alertSummary

              anchors.left: alertDot.right
              anchors.right: alertChevron.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: root.ready && root.service.alerts.length === 1
                ? root.service.alerts[0].title
                : (root.ready ? root.service.alerts.length : 0) + " alerts"
              elide: Text.ElideRight
              color: root.hasDisruption ? Color.urgent : Color.accent
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Medium
            }

            Text {
              id: alertChevron

              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.alertsExpanded ? "󰅃" : "󰅀"
              color: root.hasDisruption ? Color.urgent : Color.accent
              font.family: root.family
              font.pixelSize: Style.space(9)
            }
          }

          Repeater {
            model: root.alertsExpanded && root.ready ? root.service.alerts : []

            delegate: Ui.CursorSurface {
              required property var modelData

              width: column.width
              foreground: root.fg
              implicitHeight: alertText.implicitHeight + Style.space(18)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAlert(modelData.url)
              }

              Text {
                id: alertText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                textFormat: Text.PlainText
                text: "󰀦  " + modelData.title
                wrapMode: Text.WordWrap
                color: modelData.disruption ? Color.urgent : Color.accent
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Medium
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: !root.ready || !root.service.configured
          leftPadding: Style.space(14)
          rightPadding: Style.space(14)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "Add a Transport NSW API key"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Ui.Button {
            bordered: true
            text: "Open settings"
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.openOverlay("settings")
          }
        }

        Column {
          width: parent.width
          visible: root.ready && root.service.configured && !root.service.activePlace
          leftPadding: Style.space(14)
          rightPadding: Style.space(14)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "Add a place"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Ui.Button {
            bordered: true
            text: "Open settings"
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.openOverlay("settings")
          }
        }

        Text {
          width: parent.width
          visible: root.ready && root.service.connected && root.service.activePlace && root.rowCount === 0
          textFormat: Text.PlainText
          text: {
            var place = root.ready ? root.service.activePlace : null
            var lines = place && place.lines && place.lines.length ? place.lines.join(", ") : "matching"
            return "No " + lines + " services in the next 3 hours"
          }
          wrapMode: Text.WordWrap
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
          font.family: root.family
          font.pixelSize: Style.font.body
          leftPadding: Style.space(14)
          rightPadding: Style.space(14)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
        }

        Repeater {
          id: rowRepeater

          model: root.ready ? root.service.rows : null

          delegate: DepartureRow {
            width: column.width
            bar: root.bar
            first: index === 0
            selected: root.cursorActive && index === root.cursorIndex
            expanded: root.expandedDepId === model.depId
            depId: model.depId
            legs: root.ready ? root.service.legsFor(model.depId) : []
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
            leaveText: model.leaveText
            leaveMs: model.leaveMs
            walkMinutes: root.ready && root.service.activePlace ? root.service.activePlace.walkMinutes : 0
            realtime: model.realtime
            cancelled: model.cancelled
            dominated: model.dominated
            missed: model.missed
            delayMin: model.delayMin
            status: model.status
            alertTitle: model.alertTitle
            onExpandToggled: root.toggleExpanded(depId)
          }
        }

        Rectangle {
          width: parent.width
          implicitHeight: footerRow.implicitHeight + Style.space(16)
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(1)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
          }

          Row {
            id: footerRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)

            Text {
              width: parent.width / 2
              textFormat: Text.PlainText
              text: root.ready ? Model.relativeTimeText(root.service.lastPolledMs, root.service.nowMs)
                + " · " + root.boardStatus : "updated never · scheduled"
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
              font.family: root.family
              font.pixelSize: Style.space(9)
              font.weight: Font.Normal
              elide: Text.ElideRight
            }

            Text {
              width: parent.width / 2
              textFormat: Text.PlainText
              text: root.ready ? Model.dateTimeText(root.service.nowMs) : ""
              horizontalAlignment: Text.AlignRight
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
              font.family: root.family
              font.pixelSize: Style.space(9)
              font.weight: Font.Normal
              elide: Text.ElideLeft
            }
          }
        }
      }
    }
  }
}
