import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api

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
  property int delayMin: 0
  property string status: ""
  property string alertTitle: ""
  signal expandToggled()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(fg, 1.45)
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property color countdownColor: cancelled || missed ? Color.muted : Api.lineColor(line, mode)
  readonly property color countdownFg: cancelled || missed ? Color.background
    : (Api.lightTextOn(Api.lineColor(line, mode)) ? "#FFFFFF" : "#1A1A1A")
  readonly property string countdownText: cancelled ? "—" : missed ? "Missed" : leaveMs < 60 * 1000 ? "Now" : String(Math.min(99, Math.floor(leaveMs / 60000)))
  readonly property bool countdownHasUnit: !cancelled && !missed && leaveMs >= 60 * 1000
  readonly property string countdownLabel: walkMinutes > 0 ? "leave" : "departs"
  readonly property bool hasChanges: changesText !== "" && changesText !== "direct"
  readonly property bool expandable: legs && legs.length > 0

  function shortStopName(name) {
    return String(name || "")
      .replace(/\s+(Station|Wharf|Light Rail|Interchange)\b.*$/i, "")
      .replace(/\bStreet\b/g, "St")
      .trim()
  }

  function isFirstRide(rowIndex) {
    for (var i = 0; i < legs.length; i++) if (legs[i].kind === "ride")
      return i === rowIndex
    return false
  }

  foreground: fg
  current: selected || expanded
  implicitHeight: Math.max(Style.space(64), body.implicitHeight + Style.spacing.rowPaddingX)

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

    Rectangle {
      id: countdown

      width: Style.space(64)
      height: parent.height
      color: root.countdownColor

      Column {
        anchors.centerIn: parent
        spacing: Style.space(2)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xxs

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.countdownText
            color: root.countdownFg
            font.family: root.family
            font.pixelSize: root.countdownText === "Missed" ? Style.font.bodySmall : Style.font.title
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
          visible: !root.cancelled && !root.missed
          textFormat: Text.PlainText
          text: root.countdownLabel
          color: root.countdownFg
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Item {
      width: Math.max(0, content.width - countdown.width)
      height: parent.height
      opacity: root.cancelled || root.missed ? 0.5 : 1

      Column {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.sm

        Item {
          id: mainDetails

          width: parent.width
          height: implicitHeight
          visible: !root.expanded
          implicitHeight: Math.max(routeDetails.implicitHeight, departureClock.implicitHeight)

          Column {
            id: routeDetails

            anchors.left: parent.left
            anchors.right: departureClock.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Row {
              id: boardTopLine

              width: parent.width
              spacing: Style.spacing.sm

              LineBadge {
                id: collapsedBadge

                anchors.verticalCenter: parent.verticalCenter
                line: root.line
                mode: root.mode
                size: Style.space(26)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - collapsedBadge.width - boardPills.implicitWidth
                  - (chevron.visible ? chevron.implicitWidth : 0)
                  - parent.spacing * (1 + (boardPills.visible ? 1 : 0) + (chevron.visible ? 1 : 0)))
                textFormat: Text.PlainText
                text: root.headsign || root.destination
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                font.strikeout: root.cancelled || root.missed
              }

              Row {
                id: boardPills

                anchors.verticalCenter: parent.verticalCenter
                visible: pillRepeater.count > 0
                spacing: Style.spacing.xs

                Repeater {
                  id: pillRepeater

                  model: [root.realtime ? "realtime" : "scheduled"].concat(root.changesText ? [root.changesText] : [])

                  delegate: Rectangle {
                    required property string modelData

                    width: pillText.implicitWidth + Style.space(10)
                    height: pillText.implicitHeight + Style.space(4)
                    radius: height / 2
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)

                    Text {
                      id: pillText

                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData
                      color: root.fg
                      font.family: root.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              PanelActionButton {
                id: chevron

                anchors.verticalCenter: parent.verticalCenter
                visible: root.expandable && (mouse.containsMouse || root.selected)
                iconText: "󰅀"
                tooltipText: "Journey details"
                foreground: root.muted
                fontFamily: root.family
                fontSize: Style.font.iconSmall
                onClicked: root.expandToggled()
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: (root.platform ? "Platform " + root.platform + " · " : "")
                + root.status + (root.hasChanges && root.legsSummary ? " · " + root.legsSummary : "")
                + (root.arriveText ? " · " + (root.travelText ? root.travelText + " → " : "arrives ") + root.arriveText : "")
              elide: Text.ElideRight
              color: root.cancelled ? Color.urgent : root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: departureClock

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(88)
            spacing: Style.spacing.xxs

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: "Departs"
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.timeText
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.bold: true
              font.strikeout: root.cancelled || root.missed
            }
          }
        }

        Item {
          id: expansion

          width: parent.width
          height: implicitHeight
          visible: root.expanded
          implicitHeight: legsColumn.implicitHeight

          Column {
            id: legsColumn

            anchors.left: parent.left
            anchors.right: expandedChevron.left
            anchors.rightMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Repeater {
              model: root.expanded ? root.legs : []

              delegate: Column {
                required property var modelData
                required property int index

                width: legsColumn.width
                spacing: Style.spacing.xxs

                Item {
                  width: parent.width
                  height: implicitHeight
                  implicitHeight: modelData.kind === "ride" ? rideBoard.implicitHeight : simpleLeg.implicitHeight

                  Text {
                    id: simpleLeg

                    visible: modelData.kind !== "ride"
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.kind === "change"
                      ? "— change · " + modelData.minutes + " min at " + root.shortStopName(modelData.from) + " —"
                      : "walk " + modelData.minutes + "′ · " + root.shortStopName(modelData.from) + " → " + root.shortStopName(modelData.to)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: modelData.kind === "change" ? Text.AlignHCenter : Text.AlignLeft
                    color: root.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    id: rideBoard

                    visible: modelData.kind === "ride"
                    width: parent.width
                    height: implicitHeight
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
                          size: Style.space(24)
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
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(104)
                      spacing: Style.spacing.xxs

                      Row {
                        anchors.right: parent.right
                        visible: modelData.platform !== ""
                        spacing: Style.spacing.xs

                        Text {
                          anchors.baseline: platformNumber.baseline
                          textFormat: Text.PlainText
                          text: "Platform"
                          color: root.muted
                          font.family: root.family
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          id: platformNumber

                          textFormat: Text.PlainText
                          text: modelData.platform
                          color: root.fg
                          font.family: root.family
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }
                      }

                      Row {
                        anchors.right: parent.right
                        spacing: Style.spacing.xs

                        Text {
                          anchors.baseline: rideTime.baseline
                          visible: root.isFirstRide(index)
                          textFormat: Text.PlainText
                          text: "Departs"
                          color: root.muted
                          font.family: root.family
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          id: rideTime

                          textFormat: Text.PlainText
                          text: root.isFirstRide(index) ? modelData.departText : modelData.arriveText
                          color: root.fg
                          font.family: root.family
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }
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
                  color: modelData.disruption ? Color.urgent : root.muted
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
}
