import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api
import "ConfigStore.js" as ConfigStore

// Full-screen settings and journey planner summoned by the shell.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string tab: "settings"

  // Local until Connect, so a half-typed key never reaches the keyring.
  property string keyDraft: ""

  // Place editor state. Search state is separate so a selected stop is not
  // mistaken for a query with no matches.
  property string selectedPlaceId: ""
  property var stopResults: []
  property var selectedStop: null
  property string placeSearchText: ""
  property bool placeSearchComplete: false

  // Here-tab state.
  property var hereResults: []
  property var hereLocation: null
  property var nearestStop: null
  property var lastJourneys: []
  property string placeName: ""
  property string placeStopId: ""
  property string placeStopName: ""
  property string placeLines: ""
  property string placeDestination: ""
  property var placeModes: []
  property int placeWalk: 0
  property string placeSsid: ""
  // The kit's controls have different natural heights. Measure one bordered
  // button once so fields, dropdowns and adjacent buttons line up.
  readonly property int controlHeight: controlReference.implicitHeight
  readonly property string family: Style.font.menuFamily
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color muted: Color.muted
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    opened = true;
    keyDraft = "";
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {
      };
      tab = payload.tab === "here" ? "here" : "settings";
    } catch (e) {
      tab = "settings";
    }
    if (service && !service.configured)
      tab = "settings";

    if (service) {
      selectedPlaceId = service.activePlace ? service.activePlace.id : "";
      loadPlace(selectedPlaceId);
      service.setHereOpen(tab === "here");
    }
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus();
    });
  }

  function close() {
    opened = false;
    if (service)
      service.setHereOpen(false);
  }

  function dismiss() {
    close();
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.vichong.tfnsw-departures");
  }

  function placeById(id) {
    if (!service)
      return null;

    for (var i = 0; i < service.places.length; i++) if (service.places[i].id === id) {
      return service.places[i];
    }
    return null;
  }

  function loadPlace(id) {
    var p = placeById(id);
    placeSearchText = "";
    placeSearchComplete = false;
    stopResults = [];
    if (!p) {
      placeName = "";
      placeStopId = "";
      placeStopName = "";
      placeLines = "";
      placeDestination = "";
      placeModes = [];
      placeWalk = 0;
      placeSsid = "";
      selectedStop = null;
      return ;
    }
    placeName = p.name;
    placeStopId = p.stopId;
    placeStopName = p.stopName;
    placeLines = p.lines.join(", ");
    placeDestination = p.destination;
    placeModes = p.modes.slice();
    placeWalk = p.walkMinutes;
    placeSsid = p.ssid;
    selectedStop = {
      "id": p.stopId,
      "shortName": p.stopName,
      "name": p.stopName,
      "isStop": true,
      "modes": p.modes
    };
  }

  function addPlaceDraft() {
    selectedPlaceId = ConfigStore.newPlaceId(service ? service.places : []);
    loadPlace("");
  }

  function savePlaceDraft() {
    if (!service || !Api.isStopId(placeStopId))
      return ;

    var item = {
      "id": selectedPlaceId || ConfigStore.newPlaceId(service.places),
      "name": placeName || placeStopName || "Place",
      "stopId": placeStopId,
      "stopName": placeStopName,
      "lines": placeLines.split(","),
      "destination": placeDestination,
      "modes": placeModes,
      "walkMinutes": placeWalk,
      "ssid": placeSsid
    };
    var list = service.places.slice(), replaced = false;
    for (var i = 0; i < list.length; i++) if (list[i].id === item.id) {
      list[i] = item;
      replaced = true;
    }
    if (!replaced && list.length < ConfigStore.MAX_PLACES)
      list.push(item);

    selectedPlaceId = item.id;
    service.saveConfig({
      "places": list,
      "activePlaceId": item.id
    });
  }

  function removePlace() {
    if (!service || !selectedPlaceId)
      return ;

    var list = service.places.filter(function(p) {
      return p.id !== selectedPlaceId;
    });
    selectedPlaceId = list.length ? list[0].id : "";
    service.saveConfig({
      "places": list,
      "activePlaceId": selectedPlaceId
    });
    loadPlace(selectedPlaceId);
  }

  function pickStop(loc) {
    selectedStop = loc;
    placeStopId = loc.id;
    placeStopName = loc.shortName || loc.name;
    placeSearchText = "";
    placeSearchComplete = false;
    stopResults = [];
  }

  function searchPlaceStops(text) {
    if (!service)
      return ;

    placeSearchText = String(text || "").trim();
    placeSearchComplete = false;
    service.searchStops(text, function(results) {
      root.stopResults = results.filter(function(x) {
        return x.isStop;
      });
      root.placeSearchComplete = true;
    });
  }

  function searchHere(text) {
    if (!service)
      return ;

    service.searchStops(text, function(results) {
      root.hereResults = results;
      root.nearestStop = null;
      for (var i = 0; i < results.length; i++) if (results[i].isStop) {
        root.nearestStop = results[i];
        break;
      }
    });
  }

  function pickHere(loc) {
    hereLocation = loc;
    hereResults = [];
    if (service)
      service.planFrom(loc, function(journeys) {
      root.lastJourneys = journeys;
    });
  }

  function saveHereAsPlace() {
    if (!service || !nearestStop)
      return ;

    var walk = 0;
    if (lastJourneys.length && lastJourneys[0].legs) {
      for (var i = 0; i < lastJourneys[0].legs.length; i++) {
      if (lastJourneys[0].legs[i].kind === "walk") {
        walk = Math.max(0, Math.round(lastJourneys[0].legs[i].durationSec / 60));
        break;
      }
    };
    }
    var id = ConfigStore.newPlaceId(service.places);
    service.addPlace({
      "id": id,
      "name": nearestStop.shortName || "New place",
      "stopId": nearestStop.id,
      "stopName": nearestStop.shortName || nearestStop.name,
      "lines": [],
      "destination": "",
      "modes": nearestStop.modes || [],
      "walkMinutes": walk,
      "ssid": ""
    });
    selectedPlaceId = id;
    loadPlace(id);
    tab = "settings";
  }

  function openUrl(url) {
    var safe = Api.httpsOnly(url);
    if (safe)
      Quickshell.execDetached(["gio", "open", safe]);
  }

  onTabChanged: {
    if (service && opened) {
      service.setHereOpen(tab === "here");
    }
  }

  Button {
    id: controlReference

    visible: false
    bordered: true
    text: "Reference"
    fontFamily: root.family
  }

  PanelWindow {
    visible: root.opened
    color: "transparent"
    WlrLayershell.namespace: "tfnsw-departures-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card

      anchors.centerIn: parent
      width: Math.min(Style.space(720), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(760), parent.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
      }

      PanelKeyCatcher {
        id: keyCatcher

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        blocked: false
        onCloseRequested: root.dismiss()

        Item {
          id: header

          implicitHeight: Math.max(titleRow.implicitHeight, tabs.implicitHeight)
          height: implicitHeight

          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
          }

          Row {
            id: titleRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            ModeBadge {
              size: Style.font.display
              mode: root.service ? root.service.pillMode : "train"
              colorful: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.tab === "here" ? "From here" : "Transport NSW settings"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
            }
          }

          ButtonGroup {
            id: tabs

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            options: [{
              "value": "settings",
              "label": "Settings"
            }, {
              "value": "here",
              "label": "Here"
            }]
            value: root.tab
            onChanged: function(value) {
              root.tab = value;
            }
          }
        }

        PanelSeparator {
          id: rule

          anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            topMargin: Style.space(12)
          }
        }

        Loader {
          sourceComponent: root.tab === "here" ? herePane : settingsPane

          anchors {
            top: rule.bottom
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            topMargin: Style.space(14)
          }
        }
      }
    }
  }

  Component {
    id: settingsPane

    Flickable {
      clip: true
      contentWidth: width
      contentHeight: settingsColumn.height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: settingsColumn

        width: parent.width
        spacing: Style.spacing.xxl

        Column {
          width: parent.width
          spacing: Style.spacing.lg

          SectionTitle {
            text: "Connection"
          }

          TextField {
            width: parent.width
            height: root.controlHeight
            verticalAlignment: TextInput.AlignVCenter
            password: true
            text: root.keyDraft
            placeholderText: "Transport NSW API key"
            foreground: root.foreground
            onTextChanged: root.keyDraft = text
          }

          Row {
            spacing: Style.spacing.lg

            Button {
              bordered: true
              text: root.service && root.service.phase === "connecting" ? "Connecting…" : "Connect"
              foreground: root.foreground
              fontFamily: root.family
              onClicked: {
                if (root.service && root.service.applyConnection(root.keyDraft)) {
                  root.keyDraft = "";
                }
              }
            }

            Button {
              bordered: true
              text: "Remove key"
              visible: root.service && root.service.hasKey && !root.service.demoMode
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.service.removeConnection()
            }

            Button {
              bordered: true
              text: "Get a key"
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.openUrl(Api.REGISTER_URL)
            }
          }

          Caption {
            width: parent.width
            text: root.service ? (root.service.demoMode ? "Demo connected" : root.service.phase === "connected" ? "Connected" : root.service.lastError || "No key connected") : "Service unavailable"
            color: root.service && root.service.phase === "error" ? Color.urgent : root.muted
          }

          Caption {
            width: parent.width
            text: "Get a key:\n1. Register for TfNSW Open Data and open Applications.\n2. Add an application, choose the Bronze plan (60,000 calls/day), and tick Trip Planner APIs.\n3. Copy the API key and paste it above.\n\nThe key is stored only in the system keyring."
          }

          Toggle {
            width: parent.width
            label: "Demo mode"
            description: "A live-looking Sydenham board with no keyring or network calls."
            checked: root.service ? root.service.demoMode : false
            foreground: root.foreground
            fontFamily: root.family
            onClicked: {
              if (root.service) {
                root.service.setDemoMode(!root.service.demoMode);
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        Column {
          width: parent.width
          spacing: Style.spacing.lg

          Row {
            width: parent.width

            SectionTitle {
              text: "Places"
            }

            Item {
              width: Math.max(0, parent.width - parent.children[0].width - addButton.width - removeButton.width - Style.spacing.lg * 2)
              height: 1
            }

            Button {
              id: addButton

              bordered: true
              text: "Add place"
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.addPlaceDraft()
            }

            Button {
              id: removeButton

              bordered: true
              text: "Remove"
              visible: root.placeById(root.selectedPlaceId) !== null
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.removePlace()
            }
          }

          ButtonGroup {
            visible: root.service && root.service.places.length
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            options: root.service ? root.service.places.map(function(p) {
              return {
                "value": p.id,
                "label": p.name
              };
            }) : []
            value: root.selectedPlaceId
            onChanged: function(value) {
              root.selectedPlaceId = value;
              root.loadPlace(value);
            }
          }

          Caption {
            width: parent.width
            visible: root.service && !root.service.places.length && !root.selectedPlaceId
            text: "Add your first station or stop."
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            FieldLabel {
              text: "Name"
            }

            TextField {
              width: parent.width
              height: root.controlHeight
              verticalAlignment: TextInput.AlignVCenter
              text: root.placeName
              placeholderText: "Home"
              foreground: root.foreground
              onTextChanged: root.placeName = text
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            FieldLabel {
              text: "Stop"
            }

            TextField {
              width: parent.width
              height: root.controlHeight
              verticalAlignment: TextInput.AlignVCenter
              text: root.placeStopName
              placeholderText: "Search stations and stops…"
              foreground: root.foreground
              onTextEdited: root.searchPlaceStops(text)
            }

            Repeater {
              model: root.stopResults

              delegate: Button {
                required property var modelData

                width: settingsColumn.width
                leftAlign: true
                bordered: true
                text: modelData.shortName + " · " + modelData.modes.join(", ")
                foreground: root.foreground
                fontFamily: root.family
                onClicked: root.pickStop(modelData)
              }
            }

            Caption {
              width: parent.width
              visible: root.placeSearchText.length >= 2
                && root.placeSearchComplete && root.stopResults.length === 0
              text: "No stations or stops match."
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.xl

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.sm

              FieldLabel {
                text: "Lines (comma separated)"
              }

              TextField {
                id: linesField

                width: parent.width
                height: root.controlHeight
                verticalAlignment: TextInput.AlignVCenter
                text: root.placeLines
                placeholderText: "T4, T8"
                foreground: root.foreground
                onTextEdited: root.placeLines = text

                // Typing breaks a TextField's `text:` binding. Mirror the
                // selected draft so switching places restores its saved lines.
                Connections {
                  target: root
                  function onPlaceLinesChanged() {
                    if (linesField.text !== root.placeLines)
                      linesField.text = root.placeLines
                  }
                }
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.sm

              FieldLabel {
                text: "Destination contains"
              }

              TextField {
                width: parent.width
                height: root.controlHeight
                verticalAlignment: TextInput.AlignVCenter
                text: root.placeDestination
                placeholderText: "City"
                foreground: root.foreground
                onTextChanged: root.placeDestination = text
              }
            }
          }

          MultiSelect {
            width: parent.width
            label: "Modes"
            values: root.placeModes
            options: Api.MODES.map(function(m) {
              return {
                "value": m.id,
                "label": m.label
              };
            })
            foreground: root.foreground
            fontFamily: root.family
            onChanged: function(values) {
              root.placeModes = values;
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.xl

            NumberField {
              label: "Walk minutes"
              value: root.placeWalk
              from: 0
              to: 60
              foreground: root.foreground
              fontFamily: root.family
              onModified: function(value) {
                root.placeWalk = value;
              }
            }

            Column {
              width: Math.max(0, parent.width - parent.children[0].width - parent.spacing)
              spacing: Style.spacing.sm

              FieldLabel {
                text: "Wi-Fi SSID"
              }

              Row {
                width: parent.width
                spacing: Style.spacing.sm

                TextField {
                  width: Math.max(0, parent.width - useCurrent.width - parent.spacing)
                  height: root.controlHeight
                  verticalAlignment: TextInput.AlignVCenter
                  text: root.placeSsid
                  placeholderText: "Optional"
                  foreground: root.foreground
                  onTextChanged: root.placeSsid = text
                }

                Button {
                  id: useCurrent

                  bordered: true
                  text: "Use current"
                  foreground: root.foreground
                  fontFamily: root.family
                  onClicked: {
                    if (root.service) {
                      root.placeSsid = root.service.lastSsid;
                    }
                  }
                }
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Auto-switch by Wi-Fi"
            description: "Choose a matching place after 30 minutes without a manual selection."
            checked: root.service ? root.service.autoPlace : true
            foreground: root.foreground
            fontFamily: root.family
            onClicked: {
              if (root.service) {
                root.service.saveConfig({
                "autoPlace": !root.service.autoPlace
              });
              }
            }
          }

          Button {
            bordered: true
            text: "Save place"
            opacity: Api.isStopId(root.placeStopId) ? 1 : 0.45
            foreground: root.foreground
            fontFamily: root.family
            onClicked: {
              if (Api.isStopId(root.placeStopId)) {
                root.savePlaceDraft();
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        Column {
          width: parent.width
          spacing: Style.spacing.lg

          SectionTitle {
            text: "Board"
          }

          NumberField {
            label: "Poll seconds"
            value: root.service ? root.service.pollSeconds : 60
            from: 30
            to: 600
            foreground: root.foreground
            fontFamily: root.family
            onModified: function(value) {
              if (root.service)
                root.service.saveConfig({
                "pollSeconds": value
              });
            }
          }

          Toggle {
            width: parent.width
            label: "Leave-now notifications"
            checked: root.service ? root.service.notify : true
            foreground: root.foreground
            fontFamily: root.family
            onClicked: {
              if (root.service) {
                root.service.saveConfig({
                "notify": !root.service.notify
              });
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Colourful bar badge"
            checked: root.service ? root.service.colorful : false
            foreground: root.foreground
            fontFamily: root.family
            onClicked: {
              if (root.service) {
                root.service.saveConfig({
                "colorful": !root.service.colorful
              });
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        Row {
          spacing: Style.spacing.lg

          Caption {
            text: "Transport NSW v" + (root.manifest && root.manifest.version ? root.manifest.version : "0.1.0")
          }

          Button {
            text: "Project repository"
            foreground: root.foreground
            fontFamily: root.family
            onClicked: root.openUrl("https://github.com/vichong/omarchy-tfnsw-departures")
          }
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }
  }

  Component {
    id: herePane

    Flickable {
      clip: true
      contentWidth: width
      contentHeight: hereColumn.height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: hereColumn

        width: parent.width
        spacing: Style.spacing.xxl

        Caption {
          width: parent.width
          text: "Plan to " + (root.service && root.service.activePlace ? root.service.activePlace.stopName : "your active place") + "."
        }

        Dropdown {
          visible: root.service && root.service.effectivePlaces.length > 1
          width: parent.width
          label: "Destination place"
          foreground: root.foreground
          fontFamily: root.family
          options: root.service ? root.service.effectivePlaces.map(function(p) {
            return {
              "value": p.id,
              "label": p.name
            };
          }) : []
          value: root.service && root.service.activePlace ? root.service.activePlace.id : ""
          onChanged: function(value) {
            root.service.setActivePlace(value, true);
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm

          FieldLabel {
            text: "Where are you?"
          }

          TextField {
            width: parent.width
            height: root.controlHeight
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: "Address, landmark or stop…"
            foreground: root.foreground
            onTextEdited: root.searchHere(text)
          }

          Repeater {
            model: root.hereResults

            delegate: Button {
              required property var modelData

              width: hereColumn.width
              leftAlign: true
              bordered: true
              text: modelData.shortName + (modelData.isStop ? " · stop" : " · address")
              foreground: root.foreground
              fontFamily: root.family
              onClicked: root.pickHere(modelData)
            }
          }
        }

        Caption {
          width: parent.width
          visible: root.service && root.service.journeyError !== ""
          text: root.service ? root.service.journeyError : ""
          color: Color.urgent
        }

        Repeater {
          model: root.service ? root.service.journeyRows : null

          delegate: CursorSurface {
            width: hereColumn.width
            foreground: root.foreground
            implicitHeight: journeyLayout.implicitHeight + Style.spacing.xl

            Column {
              id: journeyLayout

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.xs

              Row {
                width: parent.width

                ModeBadge {
                  size: Style.font.icon
                  mode: model.mode
                  colorful: true
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "  Leave " + model.leaveText + " · " + model.departText + " → " + model.arriveText
                  color: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: model.summary
                elide: Text.ElideRight
                color: root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: model.changes + (model.changes === 1 ? " change" : " changes") + (model.realtime ? " · realtime" : " · scheduled") + (model.alertTitle ? " · " + model.alertTitle : "")
                color: model.alertTitle ? Color.urgent : root.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Button {
          visible: root.nearestStop !== null && root.lastJourneys.length > 0
          bordered: true
          text: "Save as place"
          foreground: root.foreground
          fontFamily: root.family
          onClicked: root.saveHereAsPlace()
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }
  }

  component FieldLabel: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.bodySmall
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.Medium
  }
}
