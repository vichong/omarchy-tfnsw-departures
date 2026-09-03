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
  readonly property var cardBorder: Border.controlSpec("normal", foreground, Color.accent)

  clip: true
  contentWidth: width
  contentHeight: settingsColumn.height
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: settingsColumn

    width: parent.width
    spacing: Style.spacing.xxl

    PanelSectionHeader {
      text: "CONNECTION"
      foreground: page.foreground
      fontFamily: page.family
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: connectionContent.implicitHeight + Style.spacing.xl * 2
      color: Style.normalFillFor(page.foreground, Color.accent)
      borderSpec: page.cardBorder
      radius: Style.cornerRadius

      Column {
        id: connectionContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.spacing.xl
        spacing: Style.spacing.lg

        Row {
          width: parent.width
          visible: page.service && (page.service.connected || page.service.demoMode)
          spacing: Style.spacing.lg

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: width
            radius: width / 2
            color: Api.lineColor("F10", "ferry")
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: page.service && page.service.demoMode ? "Demo connected" : "Connected"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width
              - removeKey.width - parent.spacing * 3)
            textFormat: Text.PlainText
            text: page.service && page.service.demoMode ? "no network calls" : "key in keyring"
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: removeKey

            visible: page.service && !page.service.demoMode
            bordered: true
            text: "Remove"
            foreground: page.foreground
            fontFamily: page.family
            onClicked: page.service.removeConnection()
          }
        }

        Column {
          width: parent.width
          visible: !page.service || (!page.service.connected && !page.service.demoMode)
          spacing: Style.spacing.lg

          TextField {
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
            spacing: Style.spacing.lg

            Button {
              bordered: true
              text: page.service && page.service.phase === "connecting" ? "Connecting…" : "Connect"
              foreground: page.foreground
              fontFamily: page.family
              onClicked: {
                if (page.service && page.service.applyConnection(page.host.keyDraft))
                  page.host.keyDraft = ""
              }
            }

            Button {
              bordered: true
              text: "Get a key"
              foreground: page.foreground
              fontFamily: page.family
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
    }

    Row {
      width: settingsColumn.width

      PanelSectionHeader {
        text: "PLACES"
        foreground: page.foreground
        fontFamily: page.family
      }

      Item {
        width: Math.max(0, parent.width - parent.children[0].width - addPlaceButton.width)
        height: 1
      }

      Button {
        id: addPlaceButton

        bordered: true
        text: "Add place"
        foreground: page.foreground
        fontFamily: page.family
        onClicked: page.host.addPlaceDraft()
      }
    }

    Text {
      width: settingsColumn.width
      visible: page.service && page.service.places.length === 0 && !page.host.selectedPlaceId
      textFormat: Text.PlainText
      text: "Add your first station or stop."
      color: page.muted
      font.family: page.family
      font.pixelSize: Style.font.caption
      font.italic: true
    }

    Repeater {
      model: page.host.placeCards()

      delegate: PlaceCard {
        required property var modelData

        width: settingsColumn.width
        place: modelData
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
    }

    PanelSectionHeader {
      text: "BEHAVIOUR"
      foreground: page.foreground
      fontFamily: page.family
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: behaviourColumn.implicitHeight + Style.spacing.xl * 2
      color: Style.normalFillFor(page.foreground, Color.accent)
      borderSpec: page.cardBorder
      radius: Style.cornerRadius

      Column {
        id: behaviourColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.spacing.xl
        spacing: Style.spacing.sm

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
    }

    PanelSectionHeader {
      text: "DEMO MODE"
      foreground: page.foreground
      fontFamily: page.family
    }

    BorderSurface {
      width: settingsColumn.width
      implicitHeight: demoRow.implicitHeight + Style.spacing.xl * 2
      color: Style.normalFillFor(page.foreground, Color.accent)
      borderSpec: page.cardBorder
      radius: Style.cornerRadius

      Row {
        id: demoRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.spacing.xl

        Column {
          width: Math.max(0, parent.width - demoSwitch.width)
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Demo mode"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.body
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
          checked: page.service ? page.service.demoMode : false
          foreground: page.foreground
          onToggled: if (page.service) page.service.setDemoMode(!page.service.demoMode)
        }
      }
    }

    PanelSeparator {
      width: settingsColumn.width
      foreground: page.foreground
    }

    Row {
      width: settingsColumn.width

      Text {
        width: parent.width * 0.42
        textFormat: Text.PlainText
        text: "Transport NSW for Omarchy v" + page.host.version
        color: page.muted
        font.family: page.family
        font.pixelSize: Style.font.caption
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
        font.pixelSize: Style.font.caption
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
      checked: parent.checked
      foreground: page.foreground
      onToggled: parent.toggled()
    }
  }

  component PlaceCard: BorderSurface {
    id: placeCard

    required property var place
    readonly property bool expanded: page.host.selectedPlaceId === String(place.id)

    implicitHeight: cardColumn.implicitHeight + Style.spacing.xl * 2
    color: Style.normalFillFor(page.foreground, Color.accent)
    borderSpec: page.cardBorder
    radius: Style.cornerRadius

    Column {
      id: cardColumn

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.xl
      spacing: Style.spacing.lg

      Item {
        width: parent.width
        implicitHeight: placeHeaderText.implicitHeight

        Column {
          id: placeHeaderText

          anchors.left: parent.left
          anchors.right: placeChevron.left
          anchors.rightMargin: Style.spacing.lg
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: placeCard.place.name || "New place"
            color: page.foreground
            font.family: page.family
            font.pixelSize: Style.font.body
            font.bold: true
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
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: placeCard.expanded ? "󰅃" : "󰅀"
          color: page.muted
          font.family: page.family
          font.pixelSize: Style.font.iconSmall
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
      }

      Column {
        width: parent.width
        visible: placeCard.expanded
        spacing: Style.spacing.lg

        Row {
          width: parent.width
          spacing: Style.spacing.xl

          Column {
            width: Math.max(0, parent.width - walkField.width - parent.spacing)
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: "Name"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.font.caption
            }

            TextField {
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
            value: page.host.placeWalk
            from: 0
            to: 60
            foreground: page.foreground
            fontFamily: page.family
            onModified: function(value) { page.host.placeWalk = value }
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.xl

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
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            textFormat: Text.PlainText
            text: "Wi-Fi SSID"
            color: page.muted
            font.family: page.family
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            TextField {
              width: Math.max(0, parent.width - useCurrent.width - parent.spacing)
              height: page.host.controlHeight
              text: page.host.placeSsid
              placeholderText: "Optional"
              font.italic: text === ""
              foreground: page.foreground
              onTextChanged: page.host.placeSsid = text
            }

            Button {
              id: useCurrent

              bordered: true
              text: "Use current"
              foreground: page.foreground
              fontFamily: page.family
              onClicked: if (page.service) page.host.placeSsid = page.service.lastSsid
            }
          }
        }

        Button {
          width: parent.width
          leftAlign: true
          bordered: true
          text: "Filter services  ·  " + page.host.filterSummary(page.host.lineDrafts(), page.host.placeModes, page.host.placeDestination)
          iconText: page.host.placeFilterOpen ? "󰅃" : "󰅀"
          foreground: page.foreground
          fontFamily: page.family
          onClicked: page.host.placeFilterOpen = !page.host.placeFilterOpen
        }

        Column {
          width: parent.width
          visible: page.host.placeFilterOpen
          spacing: Style.spacing.lg

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: "Lines"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.spacing.sm

              Repeater {
                model: page.host.lineDrafts()

                delegate: Button {
                  required property string modelData

                  bordered: true
                  text: modelData + "  ×"
                  foreground: page.foreground
                  fontFamily: page.family
                  fontSize: Style.font.caption
                  onClicked: page.host.removeLineDraft(modelData)
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
            }

            TextField {
              width: parent.width
              height: page.host.controlHeight
              placeholderText: "add a line…"
              font.italic: text === ""
              foreground: page.foreground
              onAccepted: {
                page.host.addLineDraft(text)
                text = ""
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: "Destination contains"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.font.caption
            }

            TextField {
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
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: "Modes"
              color: page.muted
              font.family: page.family
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.spacing.sm

              Button {
                bordered: true
                text: "All"
                selected: page.host.placeModes.length === 0
                foreground: page.foreground
                fontFamily: page.family
                fontSize: Style.font.caption
                onClicked: page.host.placeModes = []
              }

              Repeater {
                model: Api.MODES

                delegate: Button {
                  required property var modelData

                  bordered: true
                  text: modelData.label
                  selected: page.host.placeModes.indexOf(modelData.id) !== -1
                  foreground: page.foreground
                  fontFamily: page.family
                  fontSize: Style.font.caption
                  onClicked: page.host.toggleModeDraft(modelData.id)
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Button {
            visible: page.host.placeById(page.host.selectedPlaceId) !== null
            bordered: true
            text: "Delete place"
            foreground: Color.urgent
            fontFamily: page.family
            onClicked: page.host.removePlace()
          }

          Item {
            width: Math.max(0, parent.width - parent.children[0].width - cancelButton.width - saveButton.width - parent.spacing * 3)
            height: 1
          }

          Button {
            id: cancelButton

            bordered: true
            text: "Cancel"
            foreground: page.foreground
            fontFamily: page.family
            onClicked: page.host.cancelPlaceDraft()
          }

          Button {
            id: saveButton

            bordered: true
            active: true
            text: "Save place"
            opacity: Api.isStopId(page.host.placeStopId) ? 1 : 0.45
            foreground: Color.accent
            accent: Color.accent
            fontFamily: page.family
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
    spacing: Style.spacing.sm

    Text {
      textFormat: Text.PlainText
      text: endpoint.destination ? "Going to (optional)" : "Leaving from"
      color: page.muted
      font.family: page.family
      font.pixelSize: Style.font.caption
    }

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      TextField {
        width: Math.max(0, parent.width - (clearEndpoint.visible ? clearEndpoint.width + parent.spacing : 0))
        height: page.host.controlHeight
        text: endpoint.destination ? page.host.placeDestStopName : page.host.placeStopName
        placeholderText: "Search stations and stops…"
        font.italic: text === ""
        foreground: page.foreground
        onTextEdited: {
          if (endpoint.destination) page.host.searchDestinationStops(text)
          else page.host.searchPlaceStops(text)
        }
      }

      Button {
        id: clearEndpoint

        visible: endpoint.destination
        bordered: true
        text: "Clear"
        foreground: page.foreground
        fontFamily: page.family
        onClicked: page.host.clearDestination()
      }
    }

    Repeater {
      model: endpoint.results

      delegate: Button {
        required property var modelData

        width: endpoint.width
        leftAlign: true
        bordered: true
        text: modelData.shortName + " · " + modelData.modes.join(", ")
        foreground: page.foreground
        fontFamily: page.family
        onClicked: {
          if (endpoint.destination) page.host.pickDestination(modelData)
          else page.host.pickStop(modelData)
        }
      }
    }
  }
}
