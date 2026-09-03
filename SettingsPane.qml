import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api

Flickable {
  id: page

  required property var host
  readonly property var service: host.service
  readonly property color foreground: host.foreground
  readonly property color muted: host.muted
  readonly property string family: host.family
  readonly property var cardBorder: Border.flat(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18), Style.space(1))
  readonly property color cardFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.03)

  clip: true
  contentWidth: width
  contentHeight: settingsColumn.height
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: settingsColumn

    width: parent.width
    spacing: Style.space(8)

    SectionLabel {
      text: "CONNECTION"
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: connectionContent.implicitHeight + Style.space(22)
      color: page.cardFill
      borderSpec: page.cardBorder
      radius: Style.space(6)

      Column {
        id: connectionContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(11)

        Row {
          width: parent.width
          visible: page.service && (page.service.connected || page.service.demoMode)
          spacing: Style.space(8)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6)
            height: width
            radius: width / 2
            color: Color.accent
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: page.service && page.service.demoMode ? "Demo connected" : "Connected"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.Medium
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width
              - removeKey.width - parent.spacing * 3)
            textFormat: Text.PlainText
            text: page.service && page.service.demoMode ? " · no network calls" : " · key in keyring"
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          PixelButton {
            id: removeKey

            visible: page.service && !page.service.demoMode
            bordered: true
            text: "Remove"
            fontFamily: page.family
            fontSize: Style.font.caption
            horizontalPadding: Style.space(9)
            verticalPadding: Style.space(5)
            onClicked: page.service.removeConnection()
          }
        }

        Column {
          width: parent.width
          visible: !page.service || (!page.service.connected && !page.service.demoMode)
          spacing: Style.space(10)

          PixelField {
            width: parent.width
            height: page.host.controlHeight
            verticalAlignment: TextInput.AlignVCenter
            password: true
            text: page.host.keyDraft
            placeholderText: "Transport NSW API key"
            font.italic: text === ""
            foreground: page.foreground
            onTextChanged: page.host.keyDraft = text
          }

          Row {
            spacing: Style.space(10)

            PixelButton {
              bordered: true
              text: page.service && page.service.phase === "connecting" ? "Connecting…" : "Connect"
              fontFamily: page.family
              fontSize: Style.font.caption
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              onClicked: {
                if (page.service && page.service.applyConnection(page.host.keyDraft))
                  page.host.keyDraft = ""
              }
            }

            PixelButton {
              bordered: true
              text: "Get a key"
              fontFamily: page.family
              fontSize: Style.font.caption
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              onClicked: page.host.openUrl(Api.REGISTER_URL)
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: page.service ? page.service.lastError : "Service unavailable"
            visible: text !== ""
            color: Color.urgent
            font.family: page.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "1. Register for TfNSW Open Data and open Applications.\n2. Add an application, choose Bronze, and enable Trip Planner APIs.\n3. Paste the API key above. It is stored only in the system keyring."
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
      visible: false
    }

    Row {
      width: settingsColumn.width

      SectionLabel {
        text: "PLACES"
        topPadding: Style.space(6)
      }

      Item {
        width: Math.max(0, parent.width - parent.children[0].width - addPlaceButton.width)
        height: Style.space(1)
      }

      PixelButton {
        id: addPlaceButton

        bordered: true
        text: "Add place"
        fontFamily: page.family
        fontSize: Style.font.caption
        horizontalPadding: Style.space(9)
        verticalPadding: Style.space(5)
        onClicked: page.host.addPlaceDraft()
      }
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: placesColumn.implicitHeight
      radius: Style.space(6)
      clip: true
      color: page.cardFill
      borderSpec: page.cardBorder

      Column {
        id: placesColumn

        width: parent.width

        Text {
          width: parent.width
          visible: page.service && page.service.places.length === 0 && !page.host.selectedPlaceId
          textFormat: Text.PlainText
          text: "Add your first station or stop."
          color: page.muted
          font.family: page.family
          font.pixelSize: Style.font.caption
          font.italic: true
          leftPadding: Style.space(12)
          rightPadding: Style.space(12)
          topPadding: Style.space(11)
          bottomPadding: Style.space(11)
        }

        Repeater {
          model: page.host.placeCards()

          delegate: PlaceCard {
            required property var modelData
            required property int index

            width: placesColumn.width
            itemIndex: index
            place: modelData
          }
        }
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
      visible: false
    }

    SectionLabel {
      text: "BEHAVIOUR"
      topPadding: Style.space(6)
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: behaviourColumn.implicitHeight + Style.space(22)
      color: page.cardFill
      borderSpec: page.cardBorder
      radius: Style.space(6)

      Column {
        id: behaviourColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        SettingToggle {
          label: "Auto-switch by Wi-Fi"
          checked: page.service ? page.service.autoPlace : true
          onToggled: if (page.service) page.service.saveConfig({ "autoPlace": !page.service.autoPlace })
        }

        Row {
          width: parent.width

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - pollField.width)
            textFormat: Text.PlainText
            text: "Poll interval"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.body
          }

          NumberField {
            id: pollField

            value: page.service ? page.service.pollSeconds : 60
            from: 30
            to: 600
            foreground: page.foreground
            fontFamily: page.family
            onModified: function(value) {
              if (page.service) page.service.saveConfig({ "pollSeconds": value })
            }
          }
        }

        SettingToggle {
          label: "Leave-now notifications"
          checked: page.service ? page.service.notify : true
          onToggled: if (page.service) page.service.saveConfig({ "notify": !page.service.notify })
        }

        SettingToggle {
          label: "Colourful bar badge"
          checked: page.service ? page.service.colorful : false
          onToggled: if (page.service) page.service.saveConfig({ "colorful": !page.service.colorful })
        }
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
      visible: false
    }

    SectionLabel {
      text: "DEMO MODE"
      topPadding: Style.space(6)
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: demoRow.implicitHeight + Style.space(22)
      color: page.cardFill
      borderSpec: page.cardBorder
      radius: Style.space(6)

      Row {
        id: demoRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)

        Column {
          width: Math.max(0, parent.width - demoSwitch.width)
          spacing: Style.space(5)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Demo mode"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.Medium
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "A live-looking Sydenham board with no keyring or network calls."
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        ToggleSwitch {
          id: demoSwitch

          anchors.verticalCenter: parent.verticalCenter
          cursorRing: false
          trackWidth: Style.space(34)
          trackHeight: Style.space(18)
          knobSize: Style.space(14)
          knobInset: Style.space(2)
          checked: page.service ? page.service.demoMode : false
          foreground: page.foreground
          onToggled: if (page.service) page.service.setDemoMode(!page.service.demoMode)
        }
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
      visible: false
    }

    Row {
      width: settingsColumn.width

      Text {
        width: parent.width * 0.42
        textFormat: Text.PlainText
        text: "Transport NSW for Omarchy v" + (page.host && page.host.version ? page.host.version : "0.7.1")
        color: page.muted
        font.family: page.family
        font.pixelSize: Style.space(9)
        elide: Text.ElideRight
      }

      Text {
        id: repoLink

        readonly property string url: "https://github.com/vichong/omarchy-tfnsw-departures"

        width: parent.width * 0.58
        textFormat: Text.PlainText
        text: "github.com/vichong/omarchy-tfnsw-departures"
        horizontalAlignment: Text.AlignRight
        color: repoHover.hovered ? page.foreground : page.muted
        font.family: page.family
        font.pixelSize: Style.space(9)
        font.underline: repoHover.hovered
        elide: Text.ElideLeft

        HoverHandler {
          id: repoHover

          cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
          onTapped: if (page.service) page.service.openUrl(repoLink.url)
        }
      }
    }
  }

  ScrollBar.vertical: ScrollBar {
    policy: ScrollBar.AsNeeded
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: page.muted
    font.family: page.family
    font.pixelSize: Style.space(9)
    font.weight: Font.Medium
    font.letterSpacing: Style.space(9) * 0.18
    bottomPadding: Style.space(0)
  }

  component PixelButton: BorderSurface {
    id: pixelButton

    property string text: ""
    property bool selected: false
    property bool active: false
    property bool bordered: true
    property bool borderless: false
    property bool primary: false
    property bool leftAlign: false
    property color foreground: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.85)
    property color background: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0)
    property color accent: Color.accent
    property string fontFamily: page.family
    property real fontSize: Style.font.caption
    property real horizontalPadding: Style.space(9)
    property real verticalPadding: Style.space(5)

    signal clicked()

    radius: Style.space(4)
    implicitWidth: buttonLabel.implicitWidth + horizontalPadding * 2 + Style.space(2)
    implicitHeight: buttonLabel.implicitHeight + verticalPadding * 2 + Style.space(2)
    color: primary ? Color.accent
      : selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : buttonHover.hovered ? Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.06)
      : background
    borderSpec: borderless ? Border.none()
      : Border.flat(selected ? Color.accent
        : Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.18), Style.space(1))

    Text {
      id: buttonLabel

      anchors.left: pixelButton.leftAlign ? parent.left : undefined
      anchors.leftMargin: pixelButton.leftAlign ? pixelButton.horizontalPadding + Style.space(1) : 0
      anchors.horizontalCenter: pixelButton.leftAlign ? undefined : parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, parent.width - pixelButton.horizontalPadding * 2 - Style.space(2)))
      textFormat: Text.PlainText
      text: pixelButton.text
      color: pixelButton.primary ? Color.background : pixelButton.foreground
      font.family: pixelButton.fontFamily
      font.pixelSize: pixelButton.fontSize
      font.weight: pixelButton.primary ? Font.DemiBold : Font.Medium
      elide: Text.ElideRight
    }

    HoverHandler {
      id: buttonHover

      cursorShape: pixelButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
      enabled: pixelButton.enabled
      onTapped: pixelButton.clicked()
    }
  }

  component PixelField: TextField {
    id: field

    property bool bare: false

    height: Style.space(30)
    verticalAlignment: TextInput.AlignVCenter
    foreground: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.85)
    font.family: page.family
    font.pixelSize: Style.font.bodySmall
    font.weight: text === "" ? Font.Light : Font.Normal
    placeholderTextColor: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.25)
    leftPadding: bare ? 0 : Style.space(10)
    rightPadding: bare ? 0 : Style.space(10)
    topPadding: Style.space(0)
    bottomPadding: Style.space(0)
    background: BorderSurface {
      color: field.bare ? Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0)
        : Qt.darker(Color.background, 1.1)
      borderSpec: field.bare ? Border.none() : Border.flat(field.activeFocus ? Color.accent
        : Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.20), Style.space(1))
      radius: Style.space(4)
    }
  }

  component SettingToggle: Row {
    property string label: ""
    property bool checked: false
    signal toggled()

    width: behaviourColumn.width

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - settingSwitch.width)
      textFormat: Text.PlainText
      text: parent.label
      color: page.foreground
      font.family: page.family
      font.pixelSize: Style.font.body
    }

    ToggleSwitch {
      id: settingSwitch

      anchors.verticalCenter: parent.verticalCenter
      cursorRing: false
      trackWidth: Style.space(34)
      trackHeight: Style.space(18)
      knobSize: Style.space(14)
      knobInset: Style.space(2)
      checked: parent.checked
      foreground: page.foreground
      onToggled: parent.toggled()
    }
  }

  component PlaceCard: BorderSurface {
    id: placeCard

    required property var place
    property int itemIndex: 0
    readonly property bool expanded: page.host.selectedPlaceId === String(place.id)

    implicitHeight: cardColumn.implicitHeight
    color: placeCard.expanded
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.04)
      : Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0)
    borderSpec: Border.none()

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Style.space(1)
      visible: placeCard.itemIndex > 0
      color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.12)
    }

    Column {
      id: cardColumn

      width: parent.width
      spacing: Style.space(0)

      Rectangle {
        width: parent.width
        implicitHeight: placeHeaderText.implicitHeight + Style.space(22)
        color: placeCard.expanded
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.07)
          : Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0)

        Column {
          id: placeHeaderText

          anchors.left: parent.left
          anchors.right: placeChevron.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(11)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: placeCard.place.name || "New place"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: page.host.placeSummary(placeCard.place)
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            font.italic: text === "All services"
            elide: Text.ElideRight
          }
        }

        Text {
          id: placeChevron

          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: placeCard.expanded ? "󰅃" : "󰅀"
          color: placeCard.expanded ? Color.accent : page.muted
          font.family: page.family
          font.pixelSize: Style.space(9)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!placeCard.expanded) {
              page.host.selectedPlaceId = String(placeCard.place.id)
              page.host.loadPlace(page.host.selectedPlaceId)
            }
          }
        }
      }

      PanelSeparator {
        width: parent.width
        visible: placeCard.expanded
        foreground: page.foreground
        strength: 0.10
      }

      Column {
        id: editorColumn

        readonly property real innerWidth: width - leftPadding - rightPadding
        width: parent.width
        visible: placeCard.expanded
        leftPadding: Style.space(12)
        rightPadding: Style.space(12)
        topPadding: Style.space(4)
        bottomPadding: Style.space(14)
        spacing: Style.space(11)

        Row {
          width: editorColumn.innerWidth
          spacing: Style.space(10)

          Column {
            width: Math.max(0, parent.width - walkField.width - parent.spacing)
            spacing: Style.space(5)

            Text {
              textFormat: Text.PlainText
              text: "Name"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.space(9)
            }

            PixelField {
              width: parent.width
              height: page.host.controlHeight
              text: page.host.placeName
              placeholderText: "Home"
              font.italic: text === ""
              foreground: page.foreground
              onTextChanged: page.host.placeName = text
            }
          }

          NumberField {
            id: walkField

            label: "Walk minutes"
            spacing: Style.space(5)
            fieldWidth: Style.space(112)
            fontSize: Style.font.bodySmall
            field.height: Style.space(30)
            value: page.host.placeWalk
            from: 0
            to: 60
            foreground: page.foreground
            fontFamily: page.family
            onModified: function(value) { page.host.placeWalk = value }
          }
        }

        Row {
          width: editorColumn.innerWidth
          spacing: Style.space(10)

          EndpointField {
            width: (parent.width - parent.spacing) / 2
            destination: false
          }

          EndpointField {
            width: (parent.width - parent.spacing) / 2
            destination: true
          }
        }

        Column {
          width: editorColumn.innerWidth
          spacing: Style.space(5)

          Text {
            textFormat: Text.PlainText
            text: "Wi-Fi SSID"
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.space(9)
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            PixelField {
              width: Math.max(0, parent.width - useCurrent.width - parent.spacing)
              height: page.host.controlHeight
              text: page.host.placeSsid
              placeholderText: "Optional"
              font.italic: text === ""
              foreground: page.foreground
              onTextChanged: page.host.placeSsid = text
            }

            PixelButton {
              id: useCurrent

              bordered: true
              text: "Use current"
              fontFamily: page.family
              fontSize: Style.font.caption
              horizontalPadding: Style.space(9)
              verticalPadding: Style.space(5)
              onClicked: if (page.service) page.host.placeSsid = page.service.lastSsid
            }
          }
        }

        Column {
          width: editorColumn.innerWidth
          spacing: Style.space(0)

          BorderSurface {
            width: parent.width
          implicitHeight: Style.space(30)
          radius: Style.space(5)
          color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.03)
          borderSpec: Border.flat(Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.14), Style.space(1))

          Text {
            id: filterChevron

            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(9)
            height: Style.space(6)
            textFormat: Text.PlainText
            text: page.host.placeFilterOpen ? "󰅃" : "󰅀"
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.space(9)
          }

          Text {
            anchors.left: filterChevron.right
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Filter services"
            color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.85)
            font.family: page.family
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: page.host.filterSummary(page.host.lineDrafts(), page.host.placeModes, page.host.placeDestination)
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            font.weight: Font.Normal
          }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: page.host.placeFilterOpen = !page.host.placeFilterOpen
            }
          }

          BorderSurface {
            width: parent.width
            visible: page.host.placeFilterOpen
            implicitHeight: filterBodyContent.implicitHeight + Style.space(22)
            radius: Style.space(5)
            color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.03)
            borderSpec: Border.flat(Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.14), Style.space(1))

            Column {
              id: filterBodyContent

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Column {
                width: parent.width
                spacing: Style.space(5)

            Text {
              textFormat: Text.PlainText
              text: "Lines"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.space(9)
            }

            BorderSurface {
              width: parent.width
              implicitHeight: Math.max(Style.space(30), lineFlow.implicitHeight + Style.space(10))
              radius: Style.space(4)
              color: Qt.darker(Color.background, 1.1)
              borderSpec: Border.flat(Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.20), Style.space(1))

              Flow {
                id: lineFlow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Style.space(7)
                anchors.rightMargin: Style.space(7)
                anchors.topMargin: Style.space(5)
                spacing: Style.space(6)

                Repeater {
                  model: page.host.lineDrafts()

                  delegate: Rectangle {
                    required property string modelData

                    width: chipContent.implicitWidth + Style.space(9)
                    height: Math.max(lineChipBadge.height, removeGlyph.implicitHeight) + Style.space(4)
                    radius: Style.space(3)
                    color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.08)

                    Row {
                      id: chipContent

                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(3)
                      spacing: Style.space(3)

                      LineBadge {
                        id: lineChipBadge

                        anchors.verticalCenter: parent.verticalCenter
                        line: modelData
                        size: Style.space(15)
                        minimumWidth: Style.space(20)
                        fontSize: Style.space(9)
                        family: page.family
                      }

                      Text {
                        id: removeGlyph

                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "×"
                        color: page.muted
                        font.family: page.family
                        font.pixelSize: Style.space(9)
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: page.host.removeLineDraft(modelData)
                    }
                  }
                }

                Text {
                  visible: page.host.lineDrafts().length === 0
                  textFormat: Text.PlainText
                  text: "All"
                  color: page.muted
                  font.family: page.family
                  font.pixelSize: Style.font.caption
                  font.italic: true
                }

                PixelField {
                  bare: true
                  width: Style.space(120)
                  height: Style.space(19)
                  placeholderText: "add a line…"
                  font.italic: text === ""
                  foreground: page.foreground
                  onAccepted: {
                    page.host.addLineDraft(text)
                    text = ""
                  }
                }
              }
            }
          }

              Column {
                width: parent.width
                spacing: Style.space(5)

            Text {
              textFormat: Text.PlainText
              text: "Destination contains"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.space(9)
            }

            PixelField {
              width: parent.width
              height: page.host.controlHeight
              text: page.host.placeDestination
              placeholderText: "All"
              font.italic: text === ""
              foreground: page.foreground
              onTextChanged: page.host.placeDestination = text
            }
          }

              Column {
                width: parent.width
                spacing: Style.space(5)

            Text {
              textFormat: Text.PlainText
              text: "Modes"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.space(9)
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              PixelButton {
                bordered: true
                text: "All"
                selected: page.host.placeModes.length === 0
                fontFamily: page.family
                fontSize: Style.font.caption
                horizontalPadding: Style.space(9)
                verticalPadding: Style.space(5)
                onClicked: page.host.placeModes = []
              }

              Repeater {
                model: Api.MODES

                delegate: PixelButton {
                  required property var modelData

                  bordered: true
                  text: modelData.label
                  selected: page.host.placeModes.indexOf(modelData.id) !== -1
                  fontFamily: page.family
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(9)
                  verticalPadding: Style.space(5)
                  onClicked: page.host.toggleModeDraft(modelData.id)
                }
              }
            }
              }
            }
          }
        }

        Row {
          width: editorColumn.innerWidth
          spacing: Style.space(8)

          PixelButton {
            visible: page.host.placeById(page.host.selectedPlaceId) !== null
            bordered: false
            borderless: true
            text: "Delete place"
            foreground: Color.urgent
            fontFamily: page.family
            fontSize: Style.font.caption
            horizontalPadding: 0
            verticalPadding: 0
            onClicked: page.host.removePlace()
          }

          Item {
            width: Math.max(0, parent.width - parent.children[0].width - cancelButton.width - saveButton.width - parent.spacing * 3)
            height: Style.space(1)
          }

          PixelButton {
            id: cancelButton

            bordered: true
            text: "Cancel"
            fontFamily: page.family
            fontSize: Style.font.caption
            horizontalPadding: Style.space(9)
            verticalPadding: Style.space(5)
            onClicked: page.host.cancelPlaceDraft()
          }

          PixelButton {
            id: saveButton

            bordered: false
            borderless: true
            primary: true
            active: false
            background: Color.accent
            text: "Save place"
            opacity: Api.isStopId(page.host.placeStopId) ? 1 : 0.45
            foreground: Color.background
            accent: Color.accent
            fontFamily: page.family
            fontSize: Style.font.caption
            horizontalPadding: Style.space(11)
            verticalPadding: Style.space(6)
            onClicked: if (Api.isStopId(page.host.placeStopId)) page.host.savePlaceDraft()
          }
        }
      }
    }
  }

  component EndpointField: Column {
    id: endpoint

    property bool destination: false
    readonly property var results: destination ? page.host.destinationResults : page.host.stopResults

    width: parent.width
    spacing: Style.space(5)

    Text {
      textFormat: Text.PlainText
      text: endpoint.destination ? "Going to (optional)" : "Leaving from"
      color: page.muted
      font.family: page.family
      font.pixelSize: Style.space(9)
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      PixelField {
        width: Math.max(0, parent.width - (clearEndpoint.visible ? clearEndpoint.width + parent.spacing : 0))
        height: page.host.controlHeight
        text: endpoint.destination ? (page.host.placeDestAddress || page.host.placeDestStopName) : page.host.placeStopName
        placeholderText: endpoint.destination ? "Search stops or addresses…" : "Search stations and stops…"
        font.italic: text === ""
        foreground: page.foreground
        onTextEdited: {
          if (endpoint.destination) page.host.searchDestinationStops(text)
          else page.host.searchPlaceStops(text)
        }
        onAccepted: {
          var first = page.host.firstSearchResult(endpoint.results)
          if (!first)
            return

          if (endpoint.destination) page.host.pickDestination(first)
          else page.host.pickStop(first)
        }
      }

      PixelButton {
        id: clearEndpoint

        visible: endpoint.destination
        bordered: true
        text: "Clear"
        fontFamily: page.family
        fontSize: Style.font.caption
        horizontalPadding: Style.space(9)
        verticalPadding: Style.space(5)
        onClicked: page.host.clearDestination()
      }
    }

    Repeater {
      model: endpoint.results

      delegate: Item {
        required property var modelData

        width: endpoint.width
        implicitHeight: modelData.isDivider ? moreLabel.implicitHeight : resultButton.implicitHeight

        Text {
          id: moreLabel

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: modelData.isDivider === true
          textFormat: Text.PlainText
          text: "More"
          color: page.muted
          font.family: page.family
          font.pixelSize: Style.space(9)
        }

        PixelButton {
          id: resultButton

          width: parent.width
          visible: modelData.isDivider !== true
          leftAlign: true
          bordered: true
          text: page.host.searchResultText(modelData)
          fontFamily: page.family
          fontSize: Style.font.caption
          horizontalPadding: Style.space(9)
          verticalPadding: Style.space(5)
          onClicked: {
            if (endpoint.destination) page.host.pickDestination(modelData)
            else page.host.pickStop(modelData)
          }
        }
      }
    }
  }
}
