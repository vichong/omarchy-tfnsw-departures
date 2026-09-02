import QtQuick
import qs.Ui
import qs.Commons
import "Api.js" as Api

// One departure in the popup board.
CursorSurface {
  id: root

  property QtObject bar: null
  property bool selected: false
  property string mode: "train"
  property string line: ""
  property string destination: ""
  property string platform: ""
  property string timeText: ""
  property string plannedText: ""
  property string leaveText: ""
  property double leaveMs: 0
  property bool realtime: false
  property bool cancelled: false
  property bool missed: false
  property int delayMin: 0
  property string status: ""
  property string alertTitle: ""
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(fg, 1.45)
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool urgent: !cancelled && !missed && leaveMs <= 2 * 60 * 1000
  readonly property color countdownColor: cancelled || missed ? Color.muted : urgent ? Color.urgent : Api.modeById(mode).color
  readonly property string countdownText: cancelled ? "—" : missed ? "Missed" : leaveMs < 60 * 1000 ? "Now" : String(Math.min(99, Math.floor(leaveMs / 60000)))
  readonly property bool countdownHasUnit: !cancelled && !missed && leaveMs >= 60 * 1000

  foreground: fg
  current: selected
  implicitHeight: Math.max(Style.space(64), details.implicitHeight + Style.spacing.rowPaddingX)

  MouseArea {
    id: mouse

    anchors.fill: parent
    hoverEnabled: true
  }

  PanelToolTip {
    visible: mouse.containsMouse && root.alertTitle !== ""
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

      Row {
        id: details

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        spacing: Style.spacing.md

        Column {
          width: Math.max(0, details.width - times.width - details.spacing)
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
              width: Math.max(0, parent.width - x)
              textFormat: Text.PlainText
              text: root.destination
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              font.strikeout: root.cancelled || root.missed
            }
          }

          Row {
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: root.platform ? "Platform " + root.platform : ""
              color: root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: root.status
              color: root.cancelled ? Color.urgent : root.muted
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Column {
          id: times

          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(58)

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

          Text {
            anchors.right: parent.right
            visible: root.delayMin !== 0 && root.plannedText !== root.timeText
            textFormat: Text.PlainText
            text: root.plannedText
            color: root.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.strikeout: true
          }
        }
      }
    }
  }
}
