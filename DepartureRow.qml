import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api
import "Model.js" as Model

// One departure in the popup, rendered in the language of a station board.
CursorSurface {
  id: root

  property QtObject bar: null
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

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(fg, 1.45)
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool subdued: cancelled || missed || dominated
  readonly property color lineColor: Api.lineColor(line, mode)
  readonly property color lightThemeToken: tokenLuminance(Color.foreground) >= tokenLuminance(Color.background) ? Color.foreground : Color.background
  readonly property color darkThemeToken: tokenLuminance(Color.foreground) < tokenLuminance(Color.background) ? Color.foreground : Color.background
  readonly property color countdownFg: Api.lightTextOn(Api.lineColor(line, mode)) ? lightThemeToken : darkThemeToken
  readonly property string countdownText: cancelled || missed ? "—" : leaveMs < 60 * 1000 ? "NOW" : String(Math.min(99, Math.floor(leaveMs / 60000)))
  readonly property bool countdownHasUnit: !cancelled && !missed && leaveMs >= 60 * 1000
  readonly property string countdownLabel: cancelled ? "CANC" : missed ? "MISSED" : "LEAVE"
  readonly property bool expandable: legs && legs.length > 0

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

  foreground: fg
  current: selected || expanded
  // Collapsed rows are as tall as the rounded countdown block plus gutters
  // (the mockup's 48-unit square), not a slab that fills the row.
  readonly property int blockSize: Style.space(48)
  implicitHeight: expanded
    ? Math.max(blockSize + Style.spacing.sm * 2, legsColumn.implicitHeight + Style.spacing.lg * 2)
    : blockSize + Style.spacing.sm * 2

  // Hairline divider between rows, like the board mockup.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.lg
    anchors.rightMargin: Style.spacing.lg
    height: Style.spacing.hairline
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
    visible: !root.expanded
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

  Row {
    id: content

    anchors.fill: parent
    anchors.leftMargin: Style.spacing.sm
    opacity: root.subdued ? 0.5 : 1

    Rectangle {
      id: countdown

      anchors.verticalCenter: parent.verticalCenter
      width: root.blockSize
      height: root.blockSize
      radius: Style.space(4)
      color: root.cancelled || root.missed
        ? Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.1) : root.lineColor
      border.width: root.cancelled || root.missed ? Style.space(1) : 0
      border.color: root.muted

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(4)
        spacing: Style.space(1)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xxs

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.countdownText
            color: root.cancelled || root.missed ? root.muted : root.countdownFg
            font.family: root.family
            font.pixelSize: root.countdownText === "NOW" ? Style.font.body : Style.font.display
            font.bold: true
          }

          Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(2)
            visible: root.countdownHasUnit
            textFormat: Text.PlainText
            text: "min"
            color: root.countdownFg
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.countdownLabel
          color: root.cancelled || root.missed ? root.muted : root.countdownFg
          font.family: root.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }

    Item {
      width: Math.max(0, content.width - countdown.width)
      height: parent.height

      Item {
        id: collapsed

        anchors.fill: parent
        anchors.margins: Style.spacing.lg
        visible: !root.expanded

        Column {
          id: routeDetails

          anchors.left: parent.left
          anchors.right: departureClock.left
          anchors.rightMargin: Style.spacing.md
          anchors.top: parent.top
          spacing: Style.spacing.sm

          Item {
            width: parent.width
            height: Math.max(Style.space(26), boardPills.implicitHeight)

            Row {
              id: routeIdentity

              anchors.left: parent.left
              anchors.right: boardPills.left
              anchors.rightMargin: boardPills.visible ? Style.spacing.sm : 0
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Model.glyphFor(root.mode)
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.space(17)
              }

              LineBadge {
                id: collapsedBadge

                anchors.verticalCenter: parent.verticalCenter
                line: root.line
                mode: root.mode
                size: Style.space(18)
              }

              Row {
                width: Math.max(0, parent.width - parent.children[0].width - collapsedBadge.width - parent.spacing * 2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm

                Text {
                  // The destination is the primary; it takes what it needs and the
                  // headsign gets the rest (or hides when that is too little).
                  width: Math.min(implicitWidth, parent.width)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.destination
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  visible: root.headsign !== "" && root.headsign !== root.destination && width >= Style.space(48)
                  width: Math.max(0, parent.width - parent.children[0].width - parent.spacing)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.headsign
                  color: root.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Row {
              id: boardPills

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Repeater {
                model: root.cancelled ? ["cancelled"]
                  : root.dominated ? ["later arrival"]
                  : (root.realtime ? ["RT"] : []).concat(root.changesText ? [root.changesText] : [])

                delegate: Rectangle {
                  required property string modelData

                  width: pillText.implicitWidth + Style.space(10)
                  height: pillText.implicitHeight + Style.space(4)
                  radius: height / 2
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0)
                  border.width: Style.space(1)
                  border.color: modelData === "cancelled" ? Color.urgent : root.muted

                  Text {
                    id: pillText

                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData
                    color: modelData === "cancelled" ? Color.urgent : root.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              PanelActionButton {
                // Only on hover or keyboard focus: the row itself is the target.
                visible: root.expandable && (mouse.containsMouse || root.selected)
                iconText: "󰅀"
                tooltipText: "Journey details"
                foreground: root.muted
                fontFamily: root.family
                fontSize: Style.font.iconSmall
                onClicked: root.expandToggled()
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: (root.platform ? root.platformPrefix() + root.platform + " · " : "")
              + root.status
              + (root.arriveText ? " · " + (root.travelText ? root.travelText + " → " : "arrives ") + root.arriveText : "")
            elide: Text.ElideRight
            color: root.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          id: departureClock

          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.space(88)
          spacing: Style.spacing.xxs

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: "DEPARTS"
            color: root.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
          }

          Row {
            anchors.right: parent.right
            spacing: Style.spacing.xs

            Text {
              textFormat: Text.PlainText
              text: root.clockMain(root.timeText)
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              anchors.baseline: parent.children[0].baseline
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.clockPeriod(root.timeText)
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item {
        id: expansion

        anchors.fill: parent
        anchors.margins: Style.spacing.lg
        visible: root.expanded

        Column {
          id: legsColumn

          anchors.left: parent.left
          anchors.right: expandedChevron.left
          anchors.rightMargin: Style.spacing.sm
          spacing: Style.spacing.md

          Repeater {
            model: root.expanded ? root.legs : []

            delegate: Column {
              required property var modelData

              width: legsColumn.width
              spacing: Style.spacing.xxs

              Item {
                width: parent.width
                height: modelData.kind === "ride" ? rideBoard.implicitHeight : simpleLeg.implicitHeight

                Row {
                  id: simpleLeg

                  visible: modelData.kind !== "ride"
                  width: parent.width

                  Text {
                    width: parent.width * 0.68
                    textFormat: Text.PlainText
                    text: modelData.kind === "change"
                      ? "○ change · " + modelData.minutes + " min at " + root.shortStopName(modelData.from)
                      : "walk " + modelData.minutes + " min"
                    color: root.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width * 0.32
                    visible: modelData.kind === "walk"
                    textFormat: Text.PlainText
                    text: "arrive " + modelData.arriveText
                    horizontalAlignment: Text.AlignRight
                    color: root.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Item {
                  id: rideBoard

                  visible: modelData.kind === "ride"
                  width: parent.width
                  implicitHeight: Math.max(rideDetails.implicitHeight, rideFacts.implicitHeight)

                  Column {
                    id: rideDetails

                    anchors.left: parent.left
                    anchors.right: rideFacts.left
                    anchors.rightMargin: Style.spacing.md
                    spacing: Style.spacing.xxs

                    Row {
                      width: parent.width
                      spacing: Style.spacing.sm

                      LineBadge {
                        id: legBadge

                        anchors.verticalCenter: parent.verticalCenter
                        line: modelData.line
                        mode: modelData.mode
                        size: Style.space(18)
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - legBadge.width - parent.spacing)
                        textFormat: Text.PlainText
                        text: modelData.headsign
                        elide: Text.ElideRight
                        color: root.fg
                        font.family: root.family
                        font.pixelSize: Style.font.body
                        font.bold: true
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
                    }
                  }

                  Column {
                    id: rideFacts

                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: Style.space(88)
                    spacing: Style.spacing.xxs

                    Text {
                      anchors.right: parent.right
                      visible: modelData.platform !== ""
                      textFormat: Text.PlainText
                      text: "PLATFORM"
                      color: root.muted
                      font.family: root.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.right: parent.right
                      visible: modelData.platform !== ""
                      textFormat: Text.PlainText
                      text: modelData.platform
                      color: root.fg
                      font.family: root.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }
              }

              Text {
                width: parent.width
                leftPadding: modelData.kind === "ride" ? Style.space(24) + Style.spacing.sm : 0
                visible: modelData.alertTitle !== ""
                textFormat: Text.PlainText
                text: modelData.alertTitle
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelActionButton {
          id: expandedChevron

          anchors.right: parent.right
          anchors.top: parent.top
          iconText: "󰅃"
          tooltipText: "Collapse"
          foreground: root.muted
          fontFamily: root.family
          fontSize: Style.font.iconSmall
          onClicked: root.expandToggled()
        }
      }
    }
  }
}
