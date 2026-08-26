#!/usr/bin/env bash
# Settings reader. Single source of truth is the plugin's inline entry in
# ~/.config/omarchy/shell.json; defaults come from manifest.json so they are
# declared exactly once. Env overrides are limited to what Omarchy already
# honors (OMARCHY_OCR_LANGS).

PLUGIN_ID="t1nk33r.screen-search"
PLUGIN_DIR="${PLUGIN_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
SHELL_JSON="${SCREEN_SEARCH_SHELL_JSON:-$HOME/.config/omarchy/shell.json}"
MANIFEST="$PLUGIN_DIR/manifest.json"
PROVIDERS_JSON="$PLUGIN_DIR/providers.json"

fail() {
  local msg=$1 code=${2:-1}
  printf 'screen-search: %s\n' "$msg" >&2
  exit "$code"
}

# The plugin's entry, wherever it lives (bar layout or plugins[]). Empty
# object when the plugin is not enabled or shell.json is missing.
entry_json() {
  [[ -r $SHELL_JSON ]] || { echo '{}'; return; }
  jq -c --arg id "$PLUGIN_ID" '
    [ (.bar.layout // {} | to_entries[]?.value[]?), (.plugins // [])[]? ]
    | map(select(type == "object" and .id == $id)) | first // {}' "$SHELL_JSON" 2>/dev/null || echo '{}'
}

manifest_default() {
  jq -r --arg k "$1" '.barWidget.defaults[$k] // empty' "$MANIFEST" 2>/dev/null
}

# setting <key> [fallback]
setting() {
  local key=$1 fallback=${2:-} value
  value=$(entry_json | jq -r --arg k "$key" '.[$k] // empty')
  [[ -n $value ]] && { printf '%s' "$value"; return; }
  value=$(manifest_default "$key")
  printf '%s' "${value:-$fallback}"
}

provider_exists() {
  jq -e --arg p "$1" 'has($p) and ($p | startswith("_") | not)' "$PROVIDERS_JSON" >/dev/null 2>&1
}

current_provider() {
  local p; p=$(setting provider google)
  provider_exists "$p" || p=google
  printf '%s' "$p"
}

translate_provider() { setting translateProvider google; }

# Target language for translation: setting, else the locale's language.
translate_target() {
  local t; t=$(setting translateTarget)
  [[ -n $t ]] || t=${LANG%%[_.]*}
  printf '%s' "${t:-en}"
}

# OCR languages: Omarchy's env override wins, then the setting, then eng.
# Only languages actually installed are passed to tesseract.
ocr_langs() {
  local want=${OMARCHY_OCR_LANGS:-$(setting ocrLangs eng)} have out=""
  have=$(tesseract --list-langs 2>/dev/null | tail -n +2 | tr '\n' ' ')
  local l
  for l in ${want//+/ }; do
    [[ " $have " == *" $l "* ]] && out+="${out:+ }$l"
  done
  [[ -n $out ]] || out=eng
  printf '%s' "${out// /+}"
}

# set_setting <key> <value> — persists through Omarchy's own bar tooling so
# the shell hot-reloads it and every reader sees the same file.
set_setting() {
  omarchy bar set "$PLUGIN_ID" "$1" "$2"
}
