#!/usr/bin/env node
// Unit tests for Model.js (pure logic driving the OSD). The file begins with
// `.pragma library` (QML directive, invalid Node JS) — strip it, evaluate,
// then run table-driven assertions against the exported functions.
"use strict"
const fs = require("fs"), path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*\n/, "")
const M = {}
new Function("exports", src + `
  exports.transition = transition; exports.detect = detect;
  exports.actionsFor = actionsFor; exports.findEntry = findEntry;
  exports.anchorsFor = anchorsFor; exports.summarize = summarize;
  exports.messageForExit = messageForExit;
  exports.pluginDirFromUrl = pluginDirFromUrl;`)(M)

let pass = 0, fail = 0
function eq(got, want, label) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) pass++
  else { fail++; console.log(`  FAIL: ${label}: expected ${w} got ${g}`) }
}
function ok(cond, label) { cond ? pass++ : (fail++, console.log(`  FAIL: ${label}`)) }

// ---- transition: every legal edge --------------------------------------
const legal = [
  ["idle", "start", "selecting"],
  ["selecting", "captured", "processing"],
  ["selecting", "cancel", "cancelled"],
  ["selecting", "fail", "failed"],
  ["selecting", "close", "closed"],
  ["processing", "done", "result"],
  ["processing", "fail", "failed"],
  ["processing", "close", "closed"],
  ["result", "act", "processing"],
  ["result", "done", "result"],
  ["result", "close", "closed"],
  ["result", "fail", "failed"],
  ["failed", "close", "closed"],
  ["failed", "start", "selecting"],
  ["cancelled", "close", "closed"],
  ["cancelled", "start", "selecting"],
  ["closed", "start", "selecting"],
]
for (const [s, e, want] of legal) eq(M.transition(s, e), want, `transition(${s},${e})`)

// ---- transition: illegal edges return null -----------------------------
for (const [s, e] of [["idle","done"],["result","captured"],["processing","act"],
                      ["selecting","done"],["bogus","start"],["result","bogus"]])
  eq(M.transition(s, e), null, `transition(${s},${e}) illegal`)

// ---- detect ------------------------------------------------------------
eq(M.detect("see https://example.com/a?b=c ok").urls, ["https://example.com/a?b=c"], "detect url")
// CURRENT behavior: trailing punctuation is retained (plan 006 will strip it).
eq(M.detect("go to https://example.com/page. now").urls, ["https://example.com/page"], "trailing dot stripped")
eq(M.detect("see https://e.com/x, and https://e.com/y!").urls, ["https://e.com/x", "https://e.com/y"], "trailing comma/bang stripped")
eq(M.detect("https://a.b/c.html here").urls, ["https://a.b/c.html"], "internal dot untouched")
eq(M.detect("(https://a.b/c)").urls, ["https://a.b/c"], "detect url excludes parens")
eq(M.detect("mail me a.user+x@example.co.uk today").emails, ["a.user+x@example.co.uk"], "detect email")
eq(M.detect("call +1 415 555 0132 now").phones.length, 1, "detect phone")
eq(M.detect("order 1234567 shipped").phones, [], "7 digits is not a phone")
eq(M.detect("").urls.length + M.detect("").emails.length + M.detect("").phones.length, 0, "detect empty")
eq(M.detect(undefined).urls, [], "detect undefined")

// ---- actionsFor --------------------------------------------------------
const capsAll = { text: true, visual: true }
let a = M.actionsFor({ kind: "text", text: "plain words" }, "Google", capsAll)
eq(a.map(x => x.id), ["copy", "search", "translate", "copy-close"], "text actions no url")
ok(a[0].id === "copy" && a[0].def === true, "text default is copy")
a = M.actionsFor({ kind: "text", text: "x https://e.com y" }, "Google", capsAll)
ok(a.some(x => x.id === "open-url" && x.arg === "https://e.com"), "url adds open-url with arg")
a = M.actionsFor({ kind: "text", text: "t" }, "TinEye", { text: false, visual: true })
ok(!a.some(x => x.id === "search"), "no text search without caps.text")
a = M.actionsFor({ kind: "image", file: "/f" }, "Google", capsAll)
eq(a.map(x => x.id), ["visual", "ocr", "translate-image", "copy-image", "save", "qr"], "image action set")
ok(a[0].def === true, "image default is visual when capable")
a = M.actionsFor({ kind: "image", file: "/f" }, "Brave", { text: true, visual: false })
ok(!a.some(x => x.id === "visual"), "no visual without caps.visual")
ok(a.find(x => x.id === "ocr").def === true, "ocr becomes default without visual")
eq(M.actionsFor({ kind: "nope" }, "G", capsAll), [], "unknown kind -> no actions")

// ---- findEntry ---------------------------------------------------------
const cfg = { bar: { layout: { left: [{ id: "a" }], center: [], right: [{ id: "t1nk33r.screen-search", provider: "bing" }] } }, plugins: [{ id: "p1" }] }
eq(M.findEntry(cfg, "t1nk33r.screen-search").provider, "bing", "findEntry bar section")
eq(M.findEntry(cfg, "p1"), { id: "p1" }, "findEntry plugins[]")
eq(M.findEntry(cfg, "missing"), {}, "findEntry missing -> {}")
eq(M.findEntry(null, "x"), {}, "findEntry null config -> {}")

// ---- anchorsFor (window-level layer anchors; center = unanchored) ------
eq(M.anchorsFor("center"), {}, "anchors center")
eq(M.anchorsFor("top-center"), { top: true }, "anchors top-center")
eq(M.anchorsFor("top-right"), { top: true, right: true }, "anchors top-right")
eq(M.anchorsFor("bottom-center"), { bottom: true }, "anchors bottom-center")
eq(M.anchorsFor("bottom-right"), { bottom: true, right: true }, "anchors bottom-right")
eq(M.anchorsFor("weird"), {}, "anchors unknown -> center")
eq(M.anchorsFor(undefined), {}, "anchors undefined -> center")

// ---- summarize ---------------------------------------------------------
eq(M.summarize("one\ntwo", 6, 420), { text: "one\ntwo", truncated: false }, "summarize short")
let s7 = M.summarize("1\n2\n3\n4\n5\n6\n7", 6, 420)
ok(s7.truncated === true && s7.text.endsWith("…"), "summarize line overflow truncates")
let sc = M.summarize("x".repeat(500), 6, 420)
ok(sc.truncated === true && sc.text.length === 421, "summarize char overflow slices+ellipsis")
eq(M.summarize("x".repeat(420), 6, 420).truncated, false, "summarize exact boundary untruncated")

// ---- messageForExit ----------------------------------------------------
eq(M.messageForExit(3, "search"), "Browser could not be launched", "exit 3")
eq(M.messageForExit(4, "visual"), "Not supported by this provider", "exit 4")
eq(M.messageForExit(12, "ocr"), "OCR engine unavailable", "exit 12")
eq(M.messageForExit(11, "qr"), "No QR code found", "exit 11 qr")
eq(M.messageForExit(11, "ocr"), "No text detected", "exit 11 ocr")
eq(M.messageForExit(13, "qr"), "QR decoder not installed", "exit 13")
eq(M.messageForExit(143, "capture"), "Something went wrong", "exit unknown")

eq(M.pluginDirFromUrl("file:///home/u/x/"), "/home/u/x", "pluginDirFromUrl strips scheme+slash")
eq(M.pluginDirFromUrl("/already/plain"), "/already/plain", "pluginDirFromUrl passthrough")

console.log(`model.test: ${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
