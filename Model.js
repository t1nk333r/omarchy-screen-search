.pragma library
// Pure logic for the Screen Search OSD: state machine, content detection,
// action lists, settings lookup. No Qt objects here so it is unit-testable
// with plain node.

var STATES = ["idle", "selecting", "processing", "result", "closed", "cancelled", "failed"]

// transition(state, event) -> next state or null when the event is illegal.
function transition(state, event) {
  var table = {
    idle:       { start: "selecting" },
    selecting:  { captured: "processing", cancel: "cancelled", fail: "failed", close: "closed" },
    processing: { done: "result", fail: "failed", close: "closed" },
    result:     { act: "processing", done: "result", close: "closed", fail: "failed" },
    failed:     { close: "closed", start: "selecting" },
    cancelled:  { close: "closed", start: "selecting" },
    closed:     { start: "selecting" }
  }
  var row = table[state]
  return row && row[event] ? row[event] : null
}

var URL_RE = /https?:\/\/[^\s<>"'()\[\]]+/g
var EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g
var PHONE_RE = /(?:\+?\d[\d\s().-]{7,}\d)/g

function detect(text) {
  var t = String(text || "")
  var urls = (t.match(URL_RE) || []).map(function(u) { return u.replace(/[.,;:!?'"\u2019]+$/, "") })
  var emails = t.match(EMAIL_RE) || []
  var phones = (t.match(PHONE_RE) || []).filter(function(p) { return p.replace(/\D/g, "").length >= 8 })
  return { urls: urls, emails: emails, phones: phones }
}

// Actions for a payload. `key` is the mnemonic; `def` marks the Enter default.
// Provider capability gates come from providers.json (passed in as `caps`).
function actionsFor(payload, providerName, caps) {
  var list = []
  var d = payload && payload.text ? detect(payload.text) : { urls: [], emails: [], phones: [] }
  if (payload.kind === "text") {
    list.push({ id: "copy", label: "Copy", key: "c", def: true })
    if (caps.text) list.push({ id: "search", label: "Search " + providerName, key: "s" })
    list.push({ id: "translate", label: "Translate", key: "t" })
    if (d.urls.length) list.push({ id: "open-url", label: "Open URL", key: "o", arg: d.urls[0] })
    list.push({ id: "copy-close", label: "Copy & close", key: "x" })
  } else if (payload.kind === "image") {
    if (caps.visual) list.push({ id: "visual", label: "Search " + providerName, key: "s", def: true })
    list.push({ id: "ocr", label: "OCR", key: "o", def: !caps.visual })
    list.push({ id: "translate-image", label: "Translate", key: "t" })
    list.push({ id: "copy-image", label: "Copy", key: "c" })
    list.push({ id: "save", label: "Save", key: "v" })
    list.push({ id: "qr", label: "QR", key: "q" })
  }
  return list
}

function findEntry(config, id) {
  if (!config || typeof config !== "object") return {}
  var layout = config.bar && config.bar.layout ? config.bar.layout : {}
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = layout[sections[s]] || []
    for (var i = 0; i < arr.length; i++) if (arr[i] && arr[i].id === id) return arr[i]
  }
  var plugins = config.plugins || []
  for (var p = 0; p < plugins.length; p++) if (plugins[p] && plugins[p].id === id) return plugins[p]
  return {}
}

// Layer-shell anchor booleans for the OSD window. An axis with no anchored
// edge is centered by the compositor, so "center" returns no anchors at all.
// Filesystem path of the plugin dir from a QML context URL ("file://…/").
function pluginDirFromUrl(u) {
  return String(u).replace(/^file:\/\//, "").replace(/\/$/, "")
}

function anchorsFor(position) {
  switch (String(position || "center")) {
    case "top-center": return { top: true }
    case "top-right": return { top: true, right: true }
    case "bottom-center": return { bottom: true }
    case "bottom-right": return { bottom: true, right: true }
    default: return {}
  }
}

function summarize(text, maxLines, maxChars) {
  var lines = String(text || "").split("\n")
  var out = lines.slice(0, maxLines).join("\n")
  if (out.length > maxChars) out = out.slice(0, maxChars) + "…"
  else if (lines.length > maxLines) out += "\n…"
  return { text: out, truncated: lines.length > maxLines || String(text || "").length > maxChars }
}

function messageForExit(code, action) {
  switch (code) {
    case 3: return "Browser could not be launched"
    case 4: return "Not supported by this provider"
    case 11: return action === "qr" ? "No QR code found" : "No text detected"
    case 12: return "OCR engine unavailable"
    case 13: return "QR decoder not installed"
    case 5: return "Upload failed — try Clipboard mode"
    default: return "Something went wrong"
  }
}
