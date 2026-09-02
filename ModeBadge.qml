import QtQuick
import qs.Commons
import "Api.js" as Api

Item {
  id: root
  property string mode: "train"
  property real size: Style.font.icon
  property color color: Color.foreground
  property bool colorful: false
  property bool dim: false
  readonly property var modeInfo: Api.modeById(mode)
  width: size; height: size; implicitWidth: size; implicitHeight: size
  opacity: dim ? 0.45 : 1.0

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.colorful ? root.modeInfo.color : root.color
  }
  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.modeInfo.letter
    color: root.colorful ? "white" : Color.background
    font.family: "JetBrains Mono"
    font.pixelSize: Math.max(8, root.size * 0.55)
    font.bold: true
  }
}
