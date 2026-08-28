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
    [M6 adds: public-url mode = consent card → ephemeral host upload → uploadbyurl link]
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
| M3 | 005 OSD lifecycle (seq guard, scheduleHide) | re-summon during selection: no "Something went wrong"; error toast always 2.5 s |
| M4 | 006 hardening sweep (5 fixes) | QR w/o zbar → "QR decoder not installed"; trailing-dot URL opens clean; traversal discard refused; parser arity exit 2; single pluginDirFromUrl |
| M5 | 007 tooling + **doctor** | shellcheck clean; CI green on push; CLAUDE.md exists; `screen-search doctor` flags a dead/redirected provider URL non-zero |
| M6 | 002 public-url visual search | consent card on EVERY upload (no remember-me); upload→uploadbyurl→results in 1 action; file deleted after search; `act visual` sends nothing without consent (strace: 0 connects) |

## [ORPHANS & PENDING]

- Plans 003–006 were stamped @55674c5; HEAD has drifted (imgops reroute, autopaste,
  toast OSD, instant visual dismiss). Reconcile each plan's excerpts at milestone start.
- Plan 005: `scheduleHide` spec predates the instant-dismiss visual path — visual case
  no longer writes hideTimer; adapt scope (guard + reset still needed).
- 002 host order DECIDED by probe (2026-08-28): 0x0.st unreachable (timeout) and
  litterbox 403 from this network; uguu.se 200. M6 default host = uguu (3 h fixed
  expiry, no early delete — consent text must say so); 0x0/litterbox stay as
  config choices for networks where they work.
- Doctor is NEW scope (not in plans/): lives as `screen-search doctor` + CI job in M5.
- ImgOps autopaste + `visualAutoPaste` become legacy once M6 lands; decide keep-or-drop at M6.
- shellcheck not yet installed (M5 asks user; sudo).
