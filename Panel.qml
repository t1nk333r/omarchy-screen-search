import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Magnifier bar widget. Left: Circle to Search. Middle: OCR. Right: menu with
// provider switcher. Provider changes persist to this widget's shell.json
// entry, which the shell hot-reloads into every reader (bar, OSD, CLI).
BarWidget {
  id: root
  moduleName: "t1nk33r.screen-search"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: pluginDir + "/bin/screen-search"
  readonly property string provider: setting("provider", "google")
  property var providers: []
  readonly property string providerName: {
    for (var i = 0; i < providers.length; i++) if (providers[i].id === provider) return providers[i].name
    return provider
  }
  property bool popupOpen: false
  property bool providersOpen: false

  function close() { popupOpen = false; providersOpen = false }
  // Always route through the CLI: it owns the resultUi decision
  // (notification-first by default, OSD only when configured).
  function summon(mode) {
    close()
    Util.execArgv([root.cli, mode])
  }
  function run(argv) { close(); Util.execArgv([root.cli].concat(argv)) }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var v in values) entry[v] = values[v]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setProvider(id) { persistSettings({ provider: id }); providersOpen = false; popupOpen = false }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: providersProc
    running: true
    command: [root.cli, "providers", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.providers = JSON.parse(text) } catch (e) { root.providers = [] }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍉"
    tooltipText: "Screen Search · " + root.providerName
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.providersOpen = false; root.popupOpen = !root.popupOpen }
      else if (b === Qt.MiddleButton) root.summon("ocr")
      else root.summon("circle")
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(240))
    contentHeight: popup.fittedContentHeight(menu.implicitHeight)

    Column {
      id: menu
      anchors.fill: parent
      spacing: Style.spacing.xs

      Text {
        text: "Screen Search"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true
        bottomPadding: Style.spacing.sm
      }

      Button { width: parent.width; leftAlign: true; iconText: "󰍉"; text: "Circle to Search"; onClicked: root.summon("circle") }
      Button { width: parent.width; leftAlign: true; iconText: "󰴑"; text: "OCR screen region"; onClicked: root.summon("ocr") }
      Button { width: parent.width; leftAlign: true; iconText: "󰅍"; text: "Search clipboard text"; onClicked: root.run(["clipboard"]) }

      PanelSeparator { width: parent.width }

      Button {
        width: parent.width; leftAlign: true
        text: "Search provider · " + root.providerName
        iconText: root.providersOpen ? "󰅀" : "󰅂"
        selected: root.providersOpen
        onClicked: root.providersOpen = !root.providersOpen
      }

      Column {
        visible: root.providersOpen
        width: parent.width
        spacing: Style.spacing.xxs
        Repeater {
          model: root.providers
          delegate: Button {
            required property var modelData
            width: menu.width; leftAlign: true
            iconText: modelData.id === root.provider ? "󰄬" : " "
            text: modelData.name + (modelData.visual ? (modelData.text ? "" : "  · image only") : "  · text only")
            selected: modelData.id === root.provider
            onClicked: root.setProvider(modelData.id)
          }
        }
      }

      PanelSeparator { width: parent.width }

      Button {
        width: parent.width; leftAlign: true; iconText: "󰒓"; text: "Settings"
        onClicked: { root.close(); Util.execArgv(["omarchy-menu", "toggle", "setup.plugin"]) }
      }
    }
  }
}
