import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api
import "Model.js" as Model

// One departure in the popup, rendered in the language of a station board.
CursorSurface {
  id: root

  property QtObject bar: null
  property bool first: false
  property bool selected: false
  property bool expanded: false
  property string depId: ""
  property var legs: []
  property string mode: "train"
  property string line: ""
  property string destination: ""
  property string headsign: ""
  property string platform: ""
  property string timeText: ""
  property string plannedText: ""
  property string arriveText: ""
  property string travelText: ""
  property string changesText: ""
  property string legsSummary: ""
  property string crowding: ""
  property string leaveText: ""
  property double leaveMs: 0
  property int walkMinutes: 0
  property bool realtime: false
  property bool cancelled: false
  property bool missed: false
  property bool dominated: false
  property int delayMin: 0
  property string status: ""
  property string alertTitle: ""
  signal expandToggled()

  readonly property color fg: Color.foreground
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool subdued: cancelled || missed || dominated
  readonly property color lineColor: Api.lineColor(line, mode)
  readonly property color lightThemeToken: tokenLuminance(Color.foreground) >= tokenLuminance(Color.background) ? Color.foreground : Color.background
  readonly property color darkThemeToken: tokenLuminance(Color.foreground) < tokenLuminance(Color.background) ? Color.foreground : Color.background
  readonly property color countdownFg: Api.lightTextOn(lineColor) ? lightThemeToken : darkThemeToken
  readonly property int countdownMinutes: Math.max(0, Math.min(99, Math.floor(Math.max(0, leaveMs) / 60000)))
  readonly property string countdownText: missed ? "—" : cancelled ? String(countdownMinutes) : leaveMs < 60 * 1000 ? "NOW" : String(countdownMinutes)
  readonly property bool countdownHasUnit: !cancelled && !missed && leaveMs >= 60 * 1000
  readonly property string countdownLabel: cancelled ? "CANC" : missed ? "MISSED" : "LEAVE"
  readonly property bool expandable: legs && legs.length > 0
  readonly property int collapsedHeight: Style.space(46) + Style.space(20)
  readonly property var pillItems: cancelled ? ["cancelled"]
    : (realtime ? ["RT"] : []).concat(changesText ? [changesText] : [])
  readonly property int pillCount: pillItems.length

  function shortStopName(name) {
    return String(name || "")
      .replace(/\s+(Station|Wharf|Light Rail|Interchange)\b.*$/i, "")
      .replace(/\bStreet\b/g, "St")
      .trim()
  }

  function tokenLuminance(value) {
    return value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
  }

  function clockMain(text) {
    return String(text || "").replace(/\s+(AM|PM)$/i, "")
  }

  function clockPeriod(text) {
    var match = String(text || "").match(/\s+(AM|PM)$/i)
    return match ? match[1].toUpperCase() : ""
  }

  function platformPrefix() {
    return mode === "bus" || mode === "coach" || mode === "schoolbus" ? "Stand " : "Platform "
  }

  function chainModel() {
    var source = legs && isFinite(legs.length) ? legs : []
    var result = []
    for (var i = 0; i < source.length; i++) {
      if (source[i] && (source[i].kind === "walk" || source[i].kind === "ride" || source[i].kind === "change"))
        result.push(source[i])
    }
    if (result.length === 0) {
      if (walkMinutes > 0)
        result.push({ kind: "walk", minutes: walkMinutes })
      result.push({ kind: "ride", line: line, mode: mode })
    }
    return result
  }

  function chainCaption() {
    if (cancelled)
      return status
    var parts = []
    if (arriveText)
      parts.push("→ " + arriveText)
    if (platform)
      parts.push(platformPrefix() + platform)
    if (dominated)
      parts.push("later arrival")
    return parts.length ? "· " + parts.join(" · ") : ""
  }

  function timeRange(fromText, toText) {
    var from = String(fromText || "")
    var to = String(toText || "")
    var fromPeriod = clockPeriod(from)
    var toPeriod = clockPeriod(to)
    if (fromPeriod && fromPeriod === toPeriod)
      from = clockMain(from)
    return from + " → " + to
  }

  foreground: fg
  current: selected || expanded
  currentFill: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, expanded ? 0.05 : 0.03)
  borderSpec: Border.none()
  opacity: subdued ? 0.44 : 1
  implicitHeight: collapsedHeight + (expanded ? board.implicitHeight + Style.space(12) : 0)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.space(1)
    visible: !root.first || root.expanded
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(1)
    visible: root.expanded
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
  }

  MouseArea {
    id: mouse

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.expandable) root.expandToggled()
  }

  PanelToolTip {
    visible: mouse.containsMouse && root.alertTitle !== "" && !root.expanded
    text: root.alertTitle
    fontFamily: root.family
  }

  Item {
    id: collapsed

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.collapsedHeight

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.topMargin: Style.space(10)
      anchors.bottomMargin: Style.space(10)
      spacing: Style.space(9)

      Rectangle {
        id: countdown

        width: Style.space(52)
        height: Style.space(46)
        radius: Style.space(6)
        color: root.cancelled || root.missed ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0) : root.lineColor
        border.width: root.cancelled || root.missed ? Style.space(1) : 0
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.30)

        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(10)
          spacing: Style.space(3)

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(3)

            Text {
              anchors.baseline: unitText.visible ? unitText.baseline : undefined
              textFormat: Text.PlainText
              text: root.countdownText
              color: root.cancelled ? Color.urgent : root.missed ? root.muted : root.countdownFg
              font.family: root.family
              font.pixelSize: root.missed ? Style.font.subtitle
                : root.cancelled ? Style.font.body
                : root.countdownText === "NOW" ? Style.font.heading : Style.space(20)
              font.weight: root.cancelled ? Font.Medium : Font.Bold
              font.strikeout: root.cancelled
            }

            Text {
              id: unitText

              anchors.baseline: parent.children[0].baseline
              visible: root.countdownHasUnit
              textFormat: Text.PlainText
              text: "min"
              color: root.countdownFg
              font.family: root.family
              font.pixelSize: Style.space(9)
              font.weight: Font.Medium
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.countdownLabel
            color: root.cancelled ? Color.urgent : root.missed ? root.muted
              : Qt.rgba(root.countdownFg.r, root.countdownFg.g, root.countdownFg.b, 0.85)
            font.family: root.family
            font.pixelSize: Style.space(8)
            font.weight: Font.Medium
            font.letterSpacing: Style.space(8) * 0.16
          }
        }
      }

      Item {
        id: middle

        width: Math.max(0, parent.width - countdown.width - departureClock.width - parent.spacing * 2)
        height: parent.height

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: Style.space(2)
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: Style.space(19)

            Row {
              id: identity

              anchors.left: parent.left
              anchors.right: boardPills.left
              anchors.rightMargin: boardPills.visible ? Style.space(6) : 0
              height: parent.height
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: Style.space(20)
                textFormat: Text.PlainText
                text: Model.glyphFor(root.mode)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.space(17)
              }

              LineBadge {
                id: collapsedBadge

                anchors.verticalCenter: parent.verticalCenter
                line: root.line
                mode: root.mode
                family: root.family
                size: Style.space(19)
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - Style.space(20) - collapsedBadge.width - parent.spacing * 2)
                height: parent.height
                spacing: Style.space(6)
                clip: true

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // Destination first: it takes what it needs; the headsign gets the
                  // rest and hides when that is under its row-specific minimum.
                  width: Math.min(implicitWidth, parent.width)
                  textFormat: Text.PlainText
                  text: root.destination
                  elide: Text.ElideRight
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.Bold
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property real availableWidth: Math.max(0, parent.width - parent.children[0].width - parent.spacing)
                  visible: root.headsign !== "" && root.headsign !== root.destination && availableWidth > 0
                    && (root.pillCount >= 2 || availableWidth >= Style.space(70))
                  width: availableWidth
                  textFormat: Text.PlainText
                  text: root.headsign
                  color: root.muted
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Normal
                  elide: Text.ElideRight
                }
              }
            }

            Row {
              id: boardPills

              anchors.right: collapsedCrowding.visible ? collapsedCrowding.left : parent.right
              anchors.rightMargin: collapsedCrowding.visible ? Style.space(6) : 0
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Repeater {
                model: root.pillItems

                delegate: Rectangle {
                  required property string modelData

                  readonly property bool urgentPill: modelData === "cancelled"
                  width: pillText.implicitWidth + Style.space(10)
                  height: pillText.implicitHeight + Style.space(4)
                  radius: Style.space(3)
                  color: urgentPill
                    ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12)
                    : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                  border.width: Style.space(1)
                  border.color: urgentPill
                    ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.32)
                    : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

                  Text {
                    id: pillText

                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData
                    color: urgentPill ? Color.urgent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.85)
                    font.family: root.family
                    font.pixelSize: Style.space(9)
                    font.weight: Font.Medium
                  }
                }
              }

              Text {
                visible: root.expanded
                width: Style.space(9)
                height: Style.space(6)
                textFormat: Text.PlainText
                text: "󰅃"
                color: Color.accent
                font.family: root.family
                font.pixelSize: Style.space(9)
              }
            }

            CrowdingIndicator {
              id: collapsedCrowding

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              status: root.crowding
              foreground: root.fg
              fontFamily: root.family
            }
          }

          Item {
            id: chainLine

            width: parent.width
            height: Style.space(17)
            clip: true

            Row {
              id: chainPieces

              height: parent.height
              spacing: Style.space(6)

              Repeater {
                model: root.chainModel()

                delegate: Row {
                  required property int index
                  required property var modelData

                  height: chainLine.height
                  spacing: Style.space(6)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: index > 0
                    textFormat: Text.PlainText
                    text: "›"
                    color: root.muted
                    font.family: root.family
                    font.pixelSize: Style.space(10)
                    font.weight: Font.Normal
                  }

                  Row {
                    id: chainWalk

                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.kind === "walk" || modelData.kind === "change"
                    height: Style.space(12)
                    spacing: Style.space(3)

                    readonly property color itemColor: modelData.kind === "change" ? root.muted
                      : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.78)

                    Text {
                      width: Style.space(9)
                      height: Style.space(12)
                      textFormat: Text.PlainText
                      text: "󰖃"
                      horizontalAlignment: Text.AlignHCenter
                      color: chainWalk.itemColor
                      font.family: root.family
                      font.pixelSize: Style.space(9)
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: String(modelData.minutes || 0)
                      color: chainWalk.itemColor
                      font.family: root.family
                      font.pixelSize: Style.space(10)
                      font.weight: Font.Medium
                    }
                  }

                  LineBadge {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.kind === "ride"
                    line: modelData.line || ""
                    mode: modelData.mode || "other"
                    family: root.family
                    size: Style.space(17)
                    minimumWidth: Style.space(22)
                    fontSize: Style.space(9)
                  }
                }
              }
            }

            Text {
              x: chainPieces.width + (chainPieces.width > 0 && text !== "" ? Style.space(6) : 0)
              width: Math.max(0, parent.width - x)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.chainCaption()
              elide: Text.ElideRight
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.space(10)
              font.weight: Font.Normal
            }
          }
        }
      }

      Column {
        id: departureClock

        width: Style.space(60)
        topPadding: Style.space(3)
        spacing: Style.space(6)

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "DEPARTS"
          color: root.muted
          font.family: root.family
          font.pixelSize: Style.space(8)
          font.weight: Font.Medium
          font.letterSpacing: Style.space(8) * 0.14
        }

        Row {
          anchors.right: parent.right
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            text: root.clockMain(root.timeText)
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
          }

          Text {
            anchors.baseline: parent.children[0].baseline
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.clockPeriod(root.timeText)
            color: root.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.weight: Font.Normal
          }
        }
      }
    }
  }

  BorderSurface {
    id: board

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: collapsed.bottom
    anchors.leftMargin: Style.space(73)
    anchors.rightMargin: Style.space(12)
    visible: root.expanded
    implicitHeight: boardColumn.implicitHeight
    radius: Style.space(6)
    clip: true
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.28)
    borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14), Style.space(1))

    Column {
      id: boardColumn

      width: parent.width

      Repeater {
        model: root.expanded ? root.legs : []

        delegate: Column {
          required property int index
          required property var modelData

          width: boardColumn.width

          Item {
            id: rideBoard

            visible: modelData.kind === "ride"
            width: parent.width
            implicitHeight: visible ? Math.max(rideDetails.implicitHeight, rideFacts.implicitHeight) + Style.space(19) : 0
            height: implicitHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(1)
              visible: index > 0 && root.legs[index - 1].kind === "walk"
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            }

            Column {
              id: rideDetails

              anchors.left: parent.left
              anchors.right: rideFacts.left
              anchors.top: parent.top
              anchors.leftMargin: Style.space(11)
              anchors.rightMargin: Style.space(9)
              anchors.topMargin: Style.space(10)
              spacing: Style.space(4)

              Row {
                width: parent.width
                spacing: Style.space(6)

                // Mode pictogram, as on the collapsed row: a change from L3 to
                // M1 reads as light rail → metro, not just a colour change.
                Text {
                  id: legGlyph

                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: Model.glyphFor(modelData.mode)
                  color: root.muted
                  font.family: root.family
                  font.pixelSize: Style.space(17)
                }

                LineBadge {
                  id: legBadge

                  anchors.verticalCenter: parent.verticalCenter
                  line: modelData.line
                  mode: modelData.mode
                  family: root.family
                  size: Style.space(19)
                }

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - legGlyph.width - legBadge.width - parent.spacing * 2)
                  spacing: Style.space(8)

                  Text {
                    width: Math.min(implicitWidth, Math.max(0, parent.width - legClock.implicitWidth - parent.spacing))
                    textFormat: Text.PlainText
                    text: modelData.headsign
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: root.family
                    font.pixelSize: Style.space(11)
                    font.weight: Font.DemiBold
                  }

                  Text {
                    id: legClock

                    anchors.baseline: parent.children[0].baseline
                    textFormat: Text.PlainText
                    text: modelData.departText
                    color: root.muted
                    font.family: root.family
                    font.pixelSize: Style.space(10)
                    font.weight: Font.Normal
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.stopsText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
                font.weight: Font.Normal
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.5
              }

              Text {
                width: parent.width
                visible: modelData.alertTitle !== ""
                textFormat: Text.PlainText
                text: modelData.alertTitle
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Color.urgent
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: rideFacts

              anchors.right: parent.right
              anchors.top: parent.top
              anchors.rightMargin: Style.space(11)
              anchors.topMargin: Style.space(10)
              width: Style.space(60)
              spacing: Style.space(5)

              Text {
                anchors.right: parent.right
                visible: modelData.platform !== ""
                textFormat: Text.PlainText
                text: "PLATFORM"
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.space(8)
                font.weight: Font.Medium
                font.letterSpacing: Style.space(8) * 0.16
              }

              Text {
                anchors.right: parent.right
                visible: modelData.platform !== ""
                textFormat: Text.PlainText
                text: modelData.platform
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }

              CrowdingIndicator {
                anchors.right: parent.right
                status: modelData.crowding || ""
                foreground: root.fg
                fontFamily: root.family
              }
            }
          }

          Item {
            visible: modelData.kind === "change"
            width: parent.width
            implicitHeight: visible ? changeText.implicitHeight + Style.space(14) : 0
            height: implicitHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(1)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Style.space(1)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            }

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(5)
              height: Style.space(5)
              radius: width / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0)
              border.width: Style.space(1)
              border.color: root.muted
            }

            Text {
              id: changeText

              anchors.left: parent.left
              anchors.right: changeTime.left
              anchors.leftMargin: Style.space(25)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "change · " + modelData.minutes + " min at " + root.shortStopName(modelData.from)
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Normal
              elide: Text.ElideRight
            }

            Text {
              id: changeTime

              anchors.right: parent.right
              anchors.rightMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.timeRange(modelData.departText, modelData.arriveText)
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.space(10)
              font.weight: Font.Normal
            }
          }

          Item {
            visible: modelData.kind === "walk"
            width: parent.width
            implicitHeight: visible ? walkText.implicitHeight + Style.space(14) : 0
            height: implicitHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(1)
              visible: index > 0
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(10)
              height: Style.space(13)
              textFormat: Text.PlainText
              text: "󰖃"
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.space(10)
            }

            Text {
              id: walkText

              anchors.left: parent.left
              anchors.leftMargin: Style.space(30)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "walk " + modelData.minutes + " min"
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Normal
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: index === 0 ? "leave " + modelData.departText
                : index === root.legs.length - 1 ? "arrive " + modelData.arriveText
                : root.timeRange(modelData.departText, modelData.arriveText)
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Normal
            }
          }
        }
      }
    }
  }
}
