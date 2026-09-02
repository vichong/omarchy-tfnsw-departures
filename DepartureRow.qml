import QtQuick
import qs.Ui
import qs.Commons

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
  property bool realtime: false
  property bool cancelled: false
  property int delayMin: 0
  property string status: ""
  property string alertTitle: ""
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(fg, 1.45)
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  foreground: fg
  current: selected
  implicitHeight: Math.max(Style.space(54), content.implicitHeight + Style.spacing.rowPaddingX)
  opacity: cancelled ? 0.48 : 1

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

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.lg
    anchors.rightMargin: Style.spacing.lg
    spacing: Style.spacing.md

    ModeBadge {
      anchors.verticalCenter: parent.verticalCenter
      mode: root.mode
      size: Style.font.icon
      colorful: true
      dim: root.cancelled
    }

    Column {
      width: Math.max(0, content.width - parent.children[0].width - times.width - content.spacing * 2)
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
          font.strikeout: root.cancelled
        }

        Text {
          width: Math.max(0, parent.width - x)
          textFormat: Text.PlainText
          text: root.destination
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          font.strikeout: root.cancelled
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
      width: Style.space(82)

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.timeText
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        font.bold: true
        font.strikeout: root.cancelled
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

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.cancelled ? "—" : "leave " + root.leaveText
        color: root.leaveText === "now" ? Color.urgent : root.muted
        font.family: root.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
