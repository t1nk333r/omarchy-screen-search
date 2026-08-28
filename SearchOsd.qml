import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Screen Search overlay: hint while selecting, result card with actions.
// Everything that talks to the system goes through bin/screen-search; this
// file only holds the state machine and presentation.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "t1nk33r.screen-search"
  readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("."))
  readonly property string cli: pluginDir + "/bin/screen-search"

  // Settings come from the same shell.json entry the bar widget persists to.
  readonly property var settings: Model.findEntry(shell ? shell.shellConfig : null, pluginId)
  readonly property var defaults: manifest && manifest.barWidget && manifest.barWidget.defaults ? manifest.barWidget.defaults : {}
  function setting(k, fb) {
    var v = settings[k]; if (v === undefined || v === null || v === "") v = defaults[k]
    return v === undefined || v === null || v === "" ? fb : v
  }

  property bool opened: false
  property string state: "idle"
  property string mode: "circle"
  property var payload: ({})
  property string message: ""
  property string busyLabel: ""
  property int cursor: 0
  property bool expanded: false
  property bool pickingProvider: false
  property bool confirmingUpload: false
  property var consentInfo: null
  property int pickerCursor: 0
  property var providers: []
  property var caps: ({ text: true, visual: true })
  property string providerName: "Google"
  readonly property var actions: state === "result" ? Model.actionsFor(payload, providerName, caps) : []
  readonly property var anchorsSpec: Model.anchorsFor(setting("osdPosition", "bottom-center"))
  readonly property bool interactive: state === "result" || state === "failed"

  // The outside-click grab must not arm while slurp's own grab is still
  // tearing down after the drag release — Hyprland clears a grab established
  // during that churn immediately, which dismissed the card the instant it
  // appeared. Arm it shortly after the card settles instead.
  // Monotonic run stamp: a Process exit from a run cancelled by open()/close()
  // must not touch the state of the run that replaced it.
  property int runSeq: 0
  property bool grabArmed: false
  onInteractiveChanged: {
    if (interactive) { grabArmed = false; grabArmTimer.restart() }
    else { grabArmTimer.stop(); grabArmed = false }
  }

  function go(event) {
    var next = Model.transition(state, event)
    if (next) state = next
    return next
  }

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") } catch (e) {}
    runSeq++
    if (captureProc.running) captureProc.running = false
    if (actionProc.running) actionProc.running = false
    if (opened && state === "result") discardCapture()
    mode = p.mode === "ocr" ? "ocr" : "circle"
    payload = {}; message = ""; cursor = 0; expanded = false; pickingProvider = false
    confirmingUpload = false; consentInfo = null
    state = "idle"; go("start")
    busyLabel = mode === "ocr" ? "Select text on screen…" : "Select something on screen…"
    opened = true
    providersProc.running = true
    if (p.result && typeof p.result === "object") {
      // Replay: caller already has a capture (CLI on a file, tests).
      go("captured"); payload = p.result; go("done")
      Qt.callLater(function() { keys.forceActiveFocus() })
      return
    }
    captureProc.seq = runSeq
    captureProc.command = [root.cli + "-capture", "--mode", mode]
    captureProc.running = true
  }

  function close() {
    runSeq++
    if (captureProc.running) captureProc.running = false   // terminates the picker group
    if (actionProc.running) actionProc.running = false
    discardCapture()
    opened = false
    state = "closed"
    hideTimer.stop()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function discardCapture() {
    if (payload && payload.file) Util.execArgv([root.cli, "act", "discard", "--file", payload.file])
  }

  function scheduleHide(ms) { hideTimer.interval = ms; hideTimer.restart() }

  function finish(msg) {
    // Terminal states show a compact confirmation then close.
    if (msg) { message = msg; state = "failed" } else dismiss()
    if (msg) scheduleHide(2500)
  }

  function runAction(id, extra) {
    var a = null
    for (var i = 0; i < actions.length; i++) if (actions[i].id === id) a = actions[i]
    // visual-confirmed is not a card action: it is only reachable from the
    // consent view after the user approved this exact upload.
    if (!a && id !== "visual-confirmed") return
    var args = [root.cli, "act"]
    var f = payload.file || "", t = payload.text || ""
    switch (id) {
      case "copy":        args = args.concat(["copy", "--text", t]); break
      case "copy-close":  args = args.concat(["copy", "--text", t]); break
      case "search":      args = args.concat(["search", "--text", t]); break
      case "translate":   args = args.concat(["translate", "--text", t]); break
      case "open-url":    args = args.concat(["open-url", "--text", a.arg]); break
      case "visual":      args = args.concat(["visual", "--file", f]); if (extra) args = args.concat(["--provider", extra]); break
      case "visual-confirmed": args = args.concat(["visual-confirmed", "--file", f]); break
      case "copy-image":  args = args.concat(["copy-image", "--file", f]); break
      case "save":        args = args.concat(["save", "--file", f]); break
      case "ocr":         args = args.concat(["ocr", "--file", f]); break
      case "translate-image": args = args.concat(["ocr", "--file", f]); break
      case "qr":          args = args.concat(["qr", "--file", f]); break
      default: return
    }
    actionProc.seq = runSeq
    actionProc.action = id
    actionProc.command = args
    busyLabel = id === "ocr" || id === "translate-image" ? "Reading text…" : "Working…"
    go("act")
    actionProc.running = true
  }

  function activateCursor() {
    if (confirmingUpload) { confirmingUpload = false; runAction("visual-confirmed"); return }
    if (pickingProvider) { chooseProvider(pickerCursor); return }
    if (state === "failed") { dismiss(); return }
    if (actions.length) runAction(actions[Math.max(0, Math.min(cursor, actions.length - 1))].id)
  }

  function defaultAction() {
    for (var i = 0; i < actions.length; i++) if (actions[i].def) return actions[i].id
    return actions.length ? actions[0].id : ""
  }

  function chooseProvider(i) {
    var p = providers[i]
    pickingProvider = false
    if (!p) return
    if (payload.kind === "image") runAction("visual", p.id)
  }

  function onKey(t) {
    if (confirmingUpload || pickingProvider) return
    if (t === "w" && payload.kind === "image") { pickingProvider = true; pickerCursor = 0; return }
    if (t === "e" && payload.kind === "text") { expanded = !expanded; return }
    for (var i = 0; i < actions.length; i++) if (actions[i].key === t) { cursor = i; runAction(actions[i].id); return }
  }

  // ---- processes ----------------------------------------------------------

  Process {
    id: providersProc
    command: [root.cli, "providers", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = [], cur = null
        try { list = JSON.parse(text) } catch (e) { list = [] }
        root.providers = list
        for (var i = 0; i < list.length; i++) if (list[i].current) cur = list[i]
        if (cur) { root.providerName = cur.name; root.caps = { text: cur.text, visual: cur.visual } }
      }
    }
  }

  Process {
    id: captureProc
    property int seq: -1
    stdout: StdioCollector { id: captureOut; waitForEnd: true }
    onExited: function(code) {
      if (captureProc.seq !== root.runSeq) return   // stale run, cancelled by open()/close()
      if (code === 0) {
        try { root.payload = JSON.parse(captureOut.text) } catch (e) { root.finish("Capture failed"); return }
        root.go("captured"); root.go("done")
        root.cursor = 0
        for (var i = 0; i < root.actions.length; i++) if (root.actions[i].def) root.cursor = i
        Qt.callLater(function() { keys.forceActiveFocus() })
        if (Number(root.setting("osdTimeout", 0)) > 0) root.scheduleHide(Number(root.setting("osdTimeout", 0)) * 1000)
      } else if (code === 10) {
        root.dismiss()                       // cancellation is not a failure
      } else {
        root.finish(Model.messageForExit(code, root.mode === "ocr" ? "ocr" : "capture"))
      }
    }
  }

  Process {
    id: actionProc
    property int seq: -1
    property string action: ""
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(code) {
      if (actionProc.seq !== root.runSeq) return    // stale run, cancelled by open()/close()
      var id = actionProc.action
      if (code !== 0) {
        root.go("done")
        root.message = Model.messageForExit(code, id)
        msgTimer.restart()
        return
      }
      switch (id) {
        case "ocr": {
          try { var p = JSON.parse(actionOut.text); p.file = root.payload.file; root.payload = p } catch (e) { root.finish("OCR failed"); return }
          root.go("done"); root.cursor = 0
          break
        }
        case "translate-image": {
          try { var q = JSON.parse(actionOut.text); Util.execArgv([root.cli, "act", "translate", "--text", q.text]) } catch (e) { root.finish("OCR failed"); return }
          root.dismiss()
          break
        }
        case "qr": {
          var v = ""
          try { v = JSON.parse(actionOut.text).qr } catch (e) {}
          root.go("done"); root.message = "QR code copied to clipboard"; msgTimer.restart()
          break
        }
        case "copy": case "copy-image": case "save":
          root.go("done"); root.message = id === "save" ? "Saved to Pictures" : "Copied"; msgTimer.restart(); break
        case "visual": {
          // public-url mode answers with a consent request; nothing was
          // uploaded yet. Clipboard mode proceeds straight to the browser, so
          // dismiss immediately — the OSD holds exclusive keyboard focus and
          // would otherwise swallow the automated paste.
          var r = null
          try { r = JSON.parse(actionOut.text) } catch (e) {}
          if (r && r.needsConsent === true) {
            root.consentInfo = r
            root.confirmingUpload = true
            root.go("done")
            Qt.callLater(function() { keys.forceActiveFocus() })
          } else {
            root.dismiss()
          }
          break
        }
        case "visual-confirmed":
          root.dismiss(); break
        default:
          root.dismiss()
      }
    }
  }

  Timer { id: grabArmTimer; interval: 350; onTriggered: root.grabArmed = true }
  Timer { id: hideTimer; interval: 2500; onTriggered: root.dismiss() }
  Timer { id: msgTimer; interval: 1800; onTriggered: root.message = "" }

  // ---- window -------------------------------------------------------------
  //
  // The surface is exactly the card's size (plus shadow padding), never
  // full-screen: a fullscreen transparent overlay forces the compositor to
  // composite an extra 1440p layer every frame and measurably lags the
  // desktop. An unanchored axis is centered by the layer-shell protocol, so
  // osdPosition "center" simply anchors nothing.

  PanelWindow {
    id: panel

    readonly property int shadowPad: Style.space(28)

    visible: root.opened
    color: "transparent"
    implicitWidth: glassCard.implicitWidth + shadowPad * 2
    implicitHeight: glassCard.implicitHeight + shadowPad * 2
    WlrLayershell.namespace: "screen-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.interactive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
      top: root.anchorsSpec.top === true
      bottom: root.anchorsSpec.bottom === true
      right: root.anchorsSpec.right === true
    }
    margins {
      top: Style.space(67)
      // Android-toast placement: the card floats at ~85% of the screen's
      // height, i.e. 15% of the screen above the bottom edge.
      bottom: panel.screen ? Math.round(panel.screen.height * 0.15) : Style.space(120)
      right: Style.space(67)
    }
    // The hint card must never eat input while slurp owns the pointer.
    mask: root.interactive ? null : emptyMask
    Region { id: emptyMask }

    // Clicking anywhere outside the card dismisses it (armed slightly after
    // the card appears; see grabArmed above).
    HyprlandFocusGrab {
      active: root.grabArmed && root.opened
      windows: [panel]
      onCleared: root.dismiss()
    }

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      enabled: root.interactive
      onCloseRequested: {
        if (root.confirmingUpload) { root.confirmingUpload = false; root.consentInfo = null }
        else if (root.pickingProvider) root.pickingProvider = false
        else root.dismiss()
      }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.activateCursor()
      onTabRequested: function(d) {
        if (root.pickingProvider) root.pickerCursor = (root.pickerCursor + d + root.providers.length) % Math.max(1, root.providers.length)
        else if (root.actions.length) root.cursor = (root.cursor + d + root.actions.length) % root.actions.length
      }
      onMoveRequested: function(dx, dy) {
        var d = dx !== 0 ? dx : dy
        if (root.pickingProvider) root.pickerCursor = (root.pickerCursor + d + root.providers.length) % Math.max(1, root.providers.length)
        else if (root.actions.length) root.cursor = (root.cursor + d + root.actions.length) % root.actions.length
      }
      onTextKey: function(t) { root.onKey(t) }
    }

    // Liquid-glass card. Every color derives from the theme's popup surface
    // tokens, so theme switches restyle it; the translucent base also picks
    // up real backdrop blur when Hyprland blur is enabled (the installer
    // ships a layerrule for this namespace).
    Rectangle {
      id: glassCard

      readonly property real pad: Style.spacing.popupPadding
      readonly property color glassInk: Color.popups.text

      anchors.centerIn: parent
      implicitWidth: content.implicitWidth + pad * 2
      implicitHeight: content.implicitHeight + pad * 2
      radius: Math.max(Style.cornerRadius, Style.space(22))
      color: Util.alpha(Color.popups.background, 0.92)
      border.width: 1
      border.color: Util.alpha(Color.popups.border, 0.6)

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
      Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 1.0
        shadowVerticalOffset: Style.space(5)
        shadowColor: Util.alpha("#000000", 0.4)
      }

      // Specular sheen: bright at the top edge, falling away — the glass
      // "catches the light" regardless of theme polarity.
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.08) }
          GradientStop { position: 0.32; color: Util.alpha("#ffffff", 0.02) }
          GradientStop { position: 1.0; color: Util.alpha("#ffffff", 0.0) }
        }
      }

      // Inner rim highlight, inset one pixel from the border.
      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Util.alpha("#ffffff", 0.16)
      }

      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }

      ResultView {
        id: content
        anchors.centerIn: parent
        osd: root
      }
    }
  }
}
