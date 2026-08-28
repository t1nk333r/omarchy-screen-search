# CLAUDE.md — Screen Search

Omarchy shell plugin: OCR + Circle-to-Search. Read this before changing code.

## Architecture (who does what)

- `bin/screen-search` — CLI; owns the **exit-code registry** (its header
  comment is the single source: 0 ok/cancel, 1 fail, 2 bad arg/provider,
  3 browser, 4 capability, 5 upload failed, 6 consent required,
  10 cancelled, 11 no text/QR, 12 OCR missing, 13 QR decoder missing).
- `bin/screen-search-capture` — freeze (hyprpicker) → slurp → grim → OCR.
  Owns picker PIDs with SIGTERM→SIGKILL escalation (`kill_hard`). **Do not
  "simplify" this: hyprpicker detaches its process group and ignores SIGTERM.**
- `bin/screen-search-doctor` — explicit provider-endpoint diagnostics.
- `lib/upload.sh` — ephemeral-host adapters for the opt-in public-url visual
  mode; reachable ONLY through the consent gate in `lib/actions.sh`.
  These two are the ONLY network-touching modules; `tests/privacy.test.sh`
  enforces the split and the single `upload_ephemeral` call site.
- `lib/config.sh` — settings. Single source of truth is the plugin's inline
  entry in `~/.config/omarchy/shell.json` (defaults from `manifest.json`).
  **Never add a second config file.** Write via `omarchy bar set` /
  `updateEntryInline`, never by editing shell.json directly.
- `lib/providers.sh` — provider adapters, browser launch, autopaste (wtype).
  All URLs built via `jq '@uri'`. No `eval` anywhere, ever.
- `lib/actions.sh` — action router (`screen-search act …`), including the
  per-upload consent gate: `act visual` in public-url mode returns
  `needsConsent` JSON and uploads NOTHING; only `act visual-confirmed`
  uploads. There is deliberately no "don't ask again".
- `providers.json` — data only; parsed by bash (jq) and QML via
  `screen-search providers --json`. Never re-add text-format parsing in QML.
- QML: `SearchOsd.qml` (overlay; state machine via `Model.js`; card-sized
  layer surface — never make it fullscreen again, that lagged the desktop),
  `ResultView.qml`, `Panel.qml` (bar widget), `Model.js` (pure logic —
  node-testable, keep it Qt-free below the pragma line).

## Privacy invariants (tests guard these; do not weaken)

- OCR text, capture paths, and URLs never go to logs or notifications
  (`--image`/`--file` notification args are the sanctioned exceptions,
  matching stock Omarchy screenshots).
- Captures live only in `$XDG_RUNTIME_DIR/screen-search/` (0700), deleted on
  close/cancel/fail, swept after 10 min.
- Nothing is uploaded without an explicit, per-capture user confirmation;
  QR values are clipboard-only with `--sensitive`.

## How to verify

- `bash tests/run.sh` — offline by construction: `tests/fakebin/` shadows
  every external binary; a reached real `curl` fails loudly; autopaste is
  disabled by `SCREEN_SEARCH_NO_AUTOPASTE=1`; upload tests set
  `SCREEN_SEARCH_DELETE_DELAY=0` and their own scenario `curl`. Includes the
  node suite for `Model.js`, a shellcheck stage, and an assertion floor
  (`MIN_ASSERTIONS`) — raise the floor when you add tests.
- QML has no headless harness (known gap; no qmllint — needs Quickshell
  stubs). After QML changes: `omarchy restart shell` (keep-loaded overlays do
  NOT hot-reload) and check `journalctl --user _COMM=quickshell` for errors.

## Gotchas that have bitten before

- `pkill -f <pattern>` matches your own command line — match `bin/...` or
  split the literal.
- The OSD holds exclusive keyboard focus while interactive: any flow handing
  off to another window must `dismiss()` first.
- Process exits from cancelled runs still fire `onExited` — the `runSeq`
  stamps guard this; new Process objects must adopt the same pattern.
- A chained shell script that gates on the test suite must create files
  BEFORE the gate or commit-by-list, not `git add -A` — e11cef2's message
  claims files its tree does not contain because of exactly this.
