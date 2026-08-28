#!/usr/bin/env bash
# Provider adapters. All URL construction lives here; QML and the CLI only
# pass opaque provider ids and raw text/file paths.

# shellcheck source=config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"
# shellcheck source=upload.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/upload.sh"

urlencode() { jq -rn --arg q "$1" '$q|@uri'; }

provider_name() { jq -r --arg p "$1" '.[$p].name // $p' "$PROVIDERS_JSON"; }

provider_supports_text()   { jq -e --arg p "$1" '.[$p].text != null' "$PROVIDERS_JSON" >/dev/null 2>&1; }
provider_supports_visual() { jq -e --arg p "$1" '.[$p].visual != null' "$PROVIDERS_JSON" >/dev/null 2>&1; }

# providers_list → "id<TAB>name<TAB>text|-<TAB>visual|-<TAB>current" per line
providers_list() {
  local cur; cur=$(current_provider)
  jq -r --arg cur "$cur" '
    to_entries[] | select(.key | startswith("_") | not)
    | [ .key, .value.name,
        (if .value.text then "text" else "-" end),
        (if .value.visual then "visual" else "-" end),
        (if .key == $cur then "*" else "" end) ] | @tsv' "$PROVIDERS_JSON"
}

# providers_json -> one JSON array with capability booleans and the current
# flag. This is the machine interface the QML consumes; the TSV/awk pair
# above stays for the human-readable listing.
providers_json() {
  local cur; cur=$(current_provider)
  jq -c --arg cur "$cur" '
    [ to_entries[] | select(.key | startswith("_") | not)
      | { id: .key, name: .value.name,
          text: (.value.text != null), visual: (.value.visual != null),
          current: (.key == $cur) } ]' "$PROVIDERS_JSON"
}

# text_search_url <provider> <query>
text_search_url() {
  local p=$1 q=$2 tpl
  provider_exists "$p" || fail "unknown provider: $p" 2
  tpl=$(jq -r --arg p "$p" '.[$p].text // empty' "$PROVIDERS_JSON")
  [[ -n $tpl ]] || fail "$(provider_name "$p") has no text search" 4
  printf '%s' "${tpl//\{q\}/$(urlencode "$q")}"
}

# translate_url <text>
translate_url() {
  local tp tl tpl
  tp=$(translate_provider); tl=$(translate_target)
  tpl=$(jq -r --arg p "$tp" '._translate[$p].url // ._translate.google.url' "$PROVIDERS_JSON")
  tpl=${tpl//\{tl\}/$(urlencode "$tl")}
  printf '%s' "${tpl//\{q\}/$(urlencode "$1")}"
}

open_in_browser() {
  omarchy-launch-browser "$1" >/dev/null 2>&1 || fail "browser could not be launched" 3
}

# Drive the provider page for the user: wait for the browser window that
# belongs to $1's site, then send Ctrl+V (paste the image from the clipboard)
# and, after the page takes the paste, Return to submit. Keystrokes are
# targeted at that window's address via hyprctl sendshortcut, so they can
# never land in another application. Best effort: any failure or timeout
# leaves the user exactly where the manual flow does.
autopaste_into_browser() {
  [[ -n ${SCREEN_SEARCH_NO_AUTOPASTE:-} ]] && return 0
  command -v hyprctl >/dev/null 2>&1 || return 0
  local url=$1 host base addr=""
  host=${url#*://}; host=${host%%/*}; host=${host#www.}
  base=${host%%.*}
  for _ in $(seq 1 "${SCREEN_SEARCH_AUTOPASTE_TRIES:-40}"); do
    addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg b "$base"       '[.[] | select((.title | test($b; "i")) and (.class | test("chromium|chrome|firefox|brave|edge"; "i")))][0].address // empty')
    [[ -n $addr ]] && break
    sleep 0.2
  done
  [[ -n $addr ]] || return 0
  # Focus the page first: Chromium drops synthetic keys sent to unfocused
  # windows. wtype speaks the virtual-keyboard protocol, so to the browser
  # the paste is indistinguishable from real typing.
  hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || return 0
  sleep 0.9
  if command -v wtype >/dev/null 2>&1; then
    wtype -M ctrl -P v -p v -m ctrl 2>/dev/null || return 0
  else
    hyprctl dispatch sendshortcut "CTRL,V,address:$addr" >/dev/null 2>&1 || return 0
  fi
  # No Return here: on ImgOps the paste opens an in-page editor whose confirm
  # is its save button; a Return would submit the underlying URL form instead
  # and navigate away, destroying the editor.
}

# visual_url_template <provider> — the {u} search-by-image-URL template.
visual_url_template() {
  jq -r --arg p "$1" '.[$p].visualUrl // empty' "$PROVIDERS_JSON"
}

# visual_search <provider> <file>
# Default flow is clipboard-upload: the PNG goes to the clipboard (marked
# sensitive so clipboard history skips it) and the provider's upload page
# opens; the user pastes. Nothing is uploaded by this tool in that mode.
# The opt-in public-url mode is handled by visual_search_confirmed and is
# reachable ONLY through the consent gate in lib/actions.sh.
visual_search() {
  local p=$1 file=$2 mode url
  provider_exists "$p" || fail "unknown provider: $p" 2
  provider_supports_visual "$p" || fail "$(provider_name "$p") has no visual search" 4
  [[ -r $file ]] || fail "capture not found" 1
  mode=$(jq -r --arg p "$p" '.[$p].visual.mode' "$PROVIDERS_JSON")
  url=$(jq -r --arg p "$p" '.[$p].visual.url' "$PROVIDERS_JSON")
  case $mode in
    clipboard-upload)
      wl-copy --type image/png --sensitive < "$file"
      open_in_browser "$url"
      # Detached: the OSD must not wait on the page loading.
      if [[ $(setting visualAutoPaste true) != false ]]; then
        ( autopaste_into_browser "$url" ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
      fi
      ;;
    *) fail "unsupported visual mode: $mode" 4 ;;
  esac
}

# visual_search_confirmed <provider> <file>
# The ONLY call site that uploads. Preconditions (enforced by the caller):
# the user has just confirmed the per-upload notice for exactly this capture.
visual_search_confirmed() {
  local p=$1 file=$2 tpl host url token enc target
  provider_exists "$p" || fail "unknown provider: $p" 2
  tpl=$(visual_url_template "$p")
  [[ -n $tpl ]] || fail "$(provider_name "$p") has no search-by-URL support" 4
  [[ -r $file ]] || fail "capture not found" 1
  host=$(setting uploadHost uguu)
  IFS=$'\t' read -r url token < <(upload_ephemeral "$host" "$file") || true
  [[ -n ${url:-} ]] || fail "upload failed" 5
  enc=$(urlencode "$url")
  target=${tpl//\{u\}/$enc}
  if ! omarchy-launch-browser "$target" >/dev/null 2>&1; then
    delete_ephemeral "$host" "$url" "$token"
    fail "browser could not be launched" 3
  fi
  # Give the engine time to fetch, then take the image down where the host
  # allows it. Detached so the caller returns immediately.
  local delay=${SCREEN_SEARCH_DELETE_DELAY:-90}
  if (( delay > 0 )); then
    ( sleep "$delay"; delete_ephemeral "$host" "$url" "$token" ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  else
    delete_ephemeral "$host" "$url" "$token"
  fi
}
