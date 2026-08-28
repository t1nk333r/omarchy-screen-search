# PROJECT_MAP — Screen Search

External memory for the surgical-dev workflow. Update on every change.

## [TECH_STACK]

- Runtime: bash 5 (backend), Quickshell 0.3.1 / Qt 6.11 QML (UI), plain JS (`Model.js`, node-testable)
- OS deps (all present): jq 1.8.2, tesseract 5.5.3, grim, slurp, hyprpicker, wl-clipboard, wtype, curl
- To install in M5: shellcheck 0.11.0 (extra repo)
- Test: `bash tests/run.sh` — offline (fakebin shadows binaries), node v26 for `Model.js`
- Host: Omarchy 4.0.1 / Hyprland 0.56.2; plugin dir `~/.config/omarchy/plugins/t1nk33r.screen-search`
- Repo: github.com/t1nk333r/omarchy-screen-search, branch master

## [SYSTEM_FLOW]

```
keybind / bar 󰍉 / CLI
  → bin/screen-search (resultUi: osd → summon overlay | notification → headless)
  → bin/screen-search-capture (hyprpicker freeze → slurp → grim → PNG in $XDG_RUNTIME_DIR/screen-search)
  → SearchOsd.qml state machine (Model.js): idle→selecting→processing→result→closed|cancelled|failed
  → actions via `screen-search act …` (lib/actions.sh → lib/providers.sh, providers.json)
      text: search|translate|open-url|copy   image: visual|ocr|save|qr|copy-image
  → visual: clipboard-upload mode = wl-copy + provider page + autopaste (wtype)
    public-url mode (opt-in) = consent card → ephemeral upload → search-by-URL link
    image card actions: Search <provider> · ImgOps (dedicated button, raw-prefix URL) · OCR · …
```

Config single source of truth: inline entry in `~/.config/omarchy/shell.json`
(read via lib/config.sh + manifest defaults; written via `omarchy bar set` / updateEntryInline).

## [ARCHITECTURE]

- `bin/screen-search` — CLI + exit-code registry (0,1,2,3,4,10,11,12; M4 adds 13; M6 adds 5,6)
- `bin/screen-search-capture` — capture+OCR, owns picker PIDs (SIGKILL escalation; do not simplify)
- `lib/config.sh` — settings; `lib/providers.sh` — provider adapters + autopaste; `lib/actions.sh` — action router; `lib/tmp.sh` — capture lifecycle
- `providers.json` — provider data (text/visual URLs; M6 adds visualUrl; doctor reads all)
- QML: `SearchOsd.qml` (overlay, glass toast card), `ResultView.qml`, `Panel.qml` (bar widget), `Model.js` (pure logic)
- Tests: `tests/run.sh` + `*.test.sh` + `fakebin/`; sandbox env `SCREEN_SEARCH_NO_AUTOPASTE=1`

## [MILESTONES] (verifiable goals; sequential)

| M | Scope (plan) | Verifiable goal |
|---|---|---|
| M1 | 003 Model.js node suite + run.sh floor | DONE: 61 asserts 0 fail; floor(130) verified to fail the run |
| M2 | 004 providers --json | DONE: json=6, zero QML regexes, human output unchanged, overlay+bar live |
| M3 | 005 OSD lifecycle | DONE: seq guard + scheduleHide; double-summon→1 picker, clean teardown |
| M4 | 006 hardening sweep | DONE: 5 scoped commits; 154 assertions; exit registry adds 13 |
| M5 | 007 tooling + doctor | DONE (for real this run): shellcheck clean+gated, CI file present, CLAUDE.md, doctor |
| M6 | 002 public-url visual search | DONE: consent card live-verified, E2E via uguu+lens, 185 tests, exit 5/6 |

## [ORPHANS & PENDING]

(empty — all M1–M6 items closed 2026-08-28)

Decisions of record: uguu.se is the default upload host (0x0.st unreachable /
litterbox 403 from this network at probe time); autopaste/ImgOps paste flow
stays as the default clipboard visual mode; public-url is opt-in with a
consent card on every upload, no remember-me.
