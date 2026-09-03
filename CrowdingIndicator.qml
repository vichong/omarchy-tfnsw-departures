import QtQuick
import qs.Ui
import qs.Commons
import "Crowding.js" as Crowding

Item {
  id: root

  property string status: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property int filled: Crowding.glyphsFor(status)

  visible: filled > 0
  implicitWidth: Style.space(7) * 3 + Style.space(2) * 2
  implicitHeight: Style.space(11)

  Row {
    anchors.fill: parent
    spacing: Style.space(2)

    Repeater {
      model: 3

      delegate: Text {
        required property int index

        width: Style.space(7)
        height: Style.space(11)
        textFormat: Text.PlainText
        text: "󰀉"
        color: index < root.filled ? root.foreground
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  HoverHandler {
    id: hover
  }

  PanelToolTip {
    visible: hover.hovered
    text: Crowding.labelFor(root.status)
    fontFamily: root.fontFamily
  }
}
