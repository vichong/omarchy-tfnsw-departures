import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Api.js" as Api

// Bar button plus the departures popup. The service owns transport state,
// this component owns the popup cursor and the shell IPC target.
Panel {
  id: root

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool ready: service !== null
  readonly property bool connected: ready && service.phase === "connected"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color barFg: bar ? bar.barForeground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool alertsExpanded: false
  readonly property int rowCount: ready ? service.rows.count : 0
  readonly property bool hasDisruption: {
    if (!ready)
      return false

    for (var i = 0; i < service.alerts.length; i++) if (service.alerts[i].disruption) {
      return true
    }
    return false
  }
  readonly property string heroMeta: {
    if (!ready)
      return "Service unavailable"

    var parts = []
    if (service.activePlace && service.activePlace.stopName)
      parts.push(service.activePlace.stopName)

    if (service.rows.count)
      parts.push(service.rows.get(0).realtime ? "realtime" : "scheduled")

    if (service.lastPolledMs) {
      var d = new Date(service.lastPolledMs)
      var clock = twoDigits(d.getHours()) + ":" + twoDigits(d.getMinutes())
      if (service.stale)
        clock += ":" + twoDigits(d.getSeconds())

      parts.push((service.stale ? "cached " : "updated ") + clock)
    }

    return parts.join(" · ")
  }

  function twoDigits(n) {
    return (n < 10 ? "0" : "") + n
  }

  function placeLabel(place) {
    if (!ready || !service.colorful)
      return place.name

    var firstLine = place.lines && place.lines.length ? String(place.lines[0]) : ""
    var letter = firstLine ? firstLine.charAt(0).toUpperCase() : Api.modeById(place.modes && place.modes.length ? place.modes[0] : "other").letter
    return letter + "  " + place.name
  }

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
    function here(): void { root.openOverlay("here") }
    function place(id: string): string { return root.ready && root.service.setActivePlace(id, true) ? id : "unknown place" }
    function next(): string { return root.ready ? root.service.pillText : "" }
  }

  WidgetButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.ready && root.service.activePlace ? root.service.activePlace.name + " · " + (root.service.pillText || "No departure") : "Transport NSW"
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

      TransportMark {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.bar.iconCanvas
        color: root.barFg
        colorful: root.ready && root.service.colorful
        dim: root.connected ? 1 : 0.45
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !button.vertical && root.connected && root.service.pillText !== ""
        textFormat: Text.PlainText
        text: root.service.pillText + (root.hasDisruption ? " 󰀦" : "")
        color: root.service.urgency === "now" ? Color.urgent : root.service.urgency === "soon" ? Color.accent : root.barFg
        opacity: root.service.rows.count && !root.service.rows.get(0).realtime ? 0.65 : 1
        font.family: root.family
        font.pixelSize: Style.font.body
        font.weight: root.service.urgency === "now" ? Font.DemiBold : Font.Normal
      }
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
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
      onActivateRequested: {
      }

      Column {
        id: column

        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: root.ready && root.service.activePlace ? root.service.activePlace.name : "Transport NSW"
          meta: root.heroMeta
          foreground: root.fg
          fontFamily: root.family
          iconOpacity: root.connected ? 1 : 0.5

          iconComponent: TransportMark {
            iconSize: Style.font.display
            colorful: true
          }

          trailingControl: Component {
            Row {
              spacing: Style.spacing.xs

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: {
                  if (root.ready) {
                    root.service.refresh()
                  }
                }
              }

              PanelActionButton {
                iconText: "󰋊"
                tooltipText: "Here"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: root.openOverlay("here")
              }

              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Settings"
                foreground: Qt.darker(root.fg, 1.4)
                fontFamily: root.family
                onClicked: root.openOverlay("settings")
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        ButtonGroup {
          visible: root.ready && root.service.effectivePlaces.length > 1
          focusable: false
          foreground: root.fg
          fontFamily: root.family
          fontSize: Style.font.caption
          options: root.ready ? root.service.effectivePlaces.map(function(p) {
            return {
              "value": p.id,
              "label": root.placeLabel(p)
            }
          }) : []
          value: root.ready && root.service.activePlace ? root.service.activePlace.id : ""
          onChanged: function(value) {
            root.service.setActivePlace(value, true)
          }
        }

        Column {
          width: parent.width
          visible: root.ready && root.service.alerts.length > 0

          CursorSurface {
            width: parent.width
            foreground: root.fg
            implicitHeight: alertSummary.implicitHeight + Style.spacing.rowPaddingX

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.alertsExpanded = !root.alertsExpanded
            }

            Text {
              id: alertSummary

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.xl
              anchors.rightMargin: Style.spacing.xl
              textFormat: Text.PlainText
              text: root.ready && root.service.alerts.length === 1
                ? "󰀦  " + root.service.alerts[0].title
                : "󰀦  " + (root.ready ? root.service.alerts.length : 0) + " alerts · tap for details"
              elide: Text.ElideRight
              color: root.hasDisruption ? Color.urgent : Qt.darker(root.fg, 1.35)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.alertsExpanded && root.ready ? root.service.alerts : []

            delegate: CursorSurface {
              required property var modelData

              width: column.width
              foreground: root.fg
              implicitHeight: alertText.implicitHeight + Style.spacing.rowPaddingX

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
                anchors.leftMargin: Style.spacing.xl
                anchors.rightMargin: Style.spacing.xl
                textFormat: Text.PlainText
                text: "󰀦  " + modelData.title
                wrapMode: Text.WordWrap
                color: modelData.disruption ? Color.urgent : Qt.darker(root.fg, 1.35)
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: !root.ready || !root.service.configured
          spacing: Style.spacing.lg

          Text {
            textFormat: Text.PlainText
            text: "Add a Transport NSW API key"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Button {
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
          spacing: Style.spacing.lg

          Text {
            textFormat: Text.PlainText
            text: "Add a place"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Button {
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
          color: Qt.darker(root.fg, 1.4)
          font.family: root.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          id: rowRepeater

          model: root.ready ? root.service.rows : null

          delegate: DepartureRow {
            width: column.width
            bar: root.bar
            selected: root.cursorActive && index === root.cursorIndex
            mode: model.mode
            line: model.line
            destination: model.destination
            platform: model.platform
            timeText: model.timeText
            plannedText: model.plannedText
            leaveText: model.leaveText
            leaveMs: model.leaveMs
            realtime: model.realtime
            cancelled: model.cancelled
            missed: model.missed
            delayMin: model.delayMin
            status: model.status
            alertTitle: model.alertTitle
          }
        }
      }
    }
  }
}
