import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api

// One departure in the popup board, optionally expanded into journey legs.
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
  readonly property bool urgent: !cancelled && !missed && leaveMs <= 2 * 60 * 1000
  readonly property color countdownColor: cancelled || missed ? Color.muted : urgent ? Color.urgent : Api.modeById(mode).color
  readonly property string countdownText: cancelled ? "—" : missed ? "Missed" : leaveMs < 60 * 1000 ? "Now" : String(Math.min(99, Math.floor(leaveMs / 60000)))
  readonly property bool countdownHasUnit: !cancelled && !missed && leaveMs >= 60 * 1000
  readonly property bool hasChanges: changesText !== "" && changesText !== "direct"
  readonly property bool expandable: legs && legs.length > 0

  function shortStopName(name) {
    return String(name || "")
      .replace(/\s+(Station|Wharf|Light Rail|Interchange)\b.*$/i, "")
      .replace(/\bStreet\b/g, "St")
      .trim()
  }

  function legText(leg) {
    if (leg.kind === "change")
      return "change · " + leg.minutes + " min at " + shortStopName(leg.from)
    if (leg.kind === "walk")
      return "walk " + leg.minutes + "′ · " + shortStopName(leg.from) + " → " + shortStopName(leg.to)

    var parts = [leg.line + (leg.headsign ? " towards " + leg.headsign : "")]
    if (leg.platform) parts.push("Platform " + leg.platform)
    parts.push(shortStopName(leg.from) + " " + leg.departText + " → " + shortStopName(leg.to) + " " + leg.arriveText)
    if (leg.realtime) parts.push("realtime")
    return parts.join(" · ")
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
      opacity: !root.realtime && !root.cancelled && !root.missed ? 0.6 : 1

      Row {
        anchors.centerIn: parent
        spacing: Style.spacing.xxs

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.countdownText
          color: "white"
          font.family: root.family
          font.pixelSize: root.countdownText === "Missed" ? Style.font.bodySmall : Style.font.title
          font.bold: true
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(3)
          visible: root.countdownHasUnit
          textFormat: Text.PlainText
          text: "min"
          color: "white"
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
          implicitHeight: Math.max(routeDetails.implicitHeight, times.implicitHeight)

          Column {
            id: routeDetails
            anchors.left: parent.left
            anchors.right: times.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Row {
              width: parent.width
              spacing: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                text: root.line
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                font.bold: true
                font.strikeout: root.cancelled || root.missed
              }

              Text {
                width: Math.max(0, parent.width - x - (chevron.visible ? chevron.width + parent.spacing : 0))
                textFormat: Text.PlainText
                text: root.arriveText ? "towards " + root.headsign : root.destination
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                font.strikeout: root.cancelled || root.missed
              }

              PanelActionButton {
                id: chevron
                visible: root.expandable && (mouse.containsMouse || root.selected || root.expanded)
                iconText: root.expanded ? "󰅃" : "󰅀"
                tooltipText: root.expanded ? "Collapse" : "Journey details"
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
              elide: Text.ElideRight
              color: root.cancelled ? Color.urgent : root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: times
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.arriveText ? Style.space(142) : Style.space(58)

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.timeText + (root.arriveText ? " → " + root.arriveText : "")
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              font.bold: true
              font.strikeout: root.cancelled || root.missed
            }

            Text {
              anchors.right: parent.right
              visible: root.arriveText !== "" || (root.delayMin !== 0 && root.plannedText !== root.timeText)
              textFormat: Text.PlainText
              text: root.arriveText ? root.travelText + " · " + root.changesText : root.plannedText
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.strikeout: root.arriveText === ""
            }
          }
        }

        Column {
          id: expansion
          width: parent.width
          visible: root.expanded
          spacing: Style.spacing.sm

          Repeater {
            model: root.expanded ? root.legs : []

            delegate: Column {
              required property var modelData
              width: expansion.width
              spacing: Style.spacing.xxs

              Row {
                width: parent.width
                spacing: Style.spacing.sm

                ModeBadge {
                  visible: modelData.kind !== "change"
                  mode: modelData.mode
                  size: Style.font.iconSmall
                  color: root.fg
                  colorful: true
                }

                Text {
                  width: Math.max(0, parent.width - x)
                  textFormat: Text.PlainText
                  text: root.legText(modelData)
                  wrapMode: Text.WordWrap
                  color: modelData.kind === "change" ? root.muted : root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                leftPadding: Style.font.iconSmall + Style.spacing.sm
                visible: modelData.alertTitle !== ""
                textFormat: Text.PlainText
                text: modelData.alertTitle
                wrapMode: Text.WordWrap
                color: modelData.disruption ? Color.urgent : root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
