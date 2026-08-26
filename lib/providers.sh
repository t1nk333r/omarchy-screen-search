#!/usr/bin/env bash
# Provider adapters. All URL construction lives here; QML and the CLI only
# pass opaque provider ids and raw text/file paths.

# shellcheck source=config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

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

# visual_search <provider> <file>
# The only image flow in v1 is clipboard-upload: the PNG goes to the clipboard
# (marked sensitive so clipboard history skips it) and the provider's upload
# page opens; the user pastes. Nothing is uploaded by this tool.
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
      ;;
    *) fail "unsupported visual mode: $mode" 4 ;;
  esac
}
