import QtQuick
import qs.Commons
import "Api.js" as Api

// TfNSW line lozenge used by station indicator boards. It stays square for
// rail codes and grows just enough for longer bus route numbers.
Item {
  id: root

  property string line: ""
  property string mode: "train"
  property real size: Style.space(26)
  readonly property string code: String(line || Api.modeById(mode).letter)

  width: Math.min(Style.space(64), Math.max(size, label.implicitWidth + Style.space(10)))
  height: size
  implicitWidth: width
  implicitHeight: height
  clip: true

  Rectangle {
    anchors.fill: parent
    radius: root.size * 0.22
    color: Api.lineColor(root.line, root.mode)
  }

  Text {
    id: label

    anchors.centerIn: parent
    width: parent.width - Style.space(6)
    textFormat: Text.PlainText
    text: root.code
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    // Official badges are always white-on-colour; we trade that for legibility
    // on the light lines (T1 orange, bus blue, ferry green).
    color: Api.lightTextOn(Api.lineColor(root.line, root.mode)) ? "white" : "#1A1A1A"
    font.family: "JetBrains Mono"
    font.pixelSize: Math.max(8, root.size * 0.5)
    font.bold: true
  }
}
