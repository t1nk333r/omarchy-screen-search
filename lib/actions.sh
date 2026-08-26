#!/usr/bin/env bash
# Action router: `screen-search act <action> [--file F] [--text T] [--provider P]`.
# Text and file paths are only ever passed as arguments, never echoed.

# shellcheck source=providers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/providers.sh"
# shellcheck source=tmp.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/tmp.sh"

notify() { omarchy-notification-send -g "${2:-󰍉}" "$1" >/dev/null 2>&1 || true; }

screenshot_dir() {
  [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
  printf '%s' "${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
}

run_action() {
  local action=$1; shift
  local file="" text="" provider="" lang=""
  while (($#)); do
    case $1 in
      --file) file=$2; shift 2 ;;
      --text) text=$2; shift 2 ;;
      --provider) provider=$2; shift 2 ;;
      --lang) lang=$2; shift 2 ;;
      *) fail "unknown option: $1" 2 ;;
    esac
  done
  [[ -n $provider ]] || provider=$(current_provider)

  case $action in
    copy)
      [[ -n $text ]] || fail "nothing to copy" 1
      printf '%s' "$text" | wl-copy
      ;;
    copy-image)
      [[ -r $file ]] || fail "capture not found" 1
      wl-copy --type image/png < "$file"
      ;;
    search)
      [[ -n $text ]] || fail "empty query" 1
      local url; url=$(text_search_url "$provider" "$text") || exit $?
      open_in_browser "$url"
      ;;
    visual)
      visual_search "$provider" "$file"
      ;;
    translate)
      [[ -n $text ]] || fail "nothing to translate" 1
      local turl; turl=$(translate_url "$text") || exit $?
      open_in_browser "$turl"
      ;;
    open-url)
      [[ $text =~ ^https?://[^[:space:]]+$ ]] || fail "not a URL" 1
      open_in_browser "$text"
      ;;
    save)
      [[ -r $file ]] || fail "capture not found" 1
      local dir out
      dir=$(screenshot_dir); mkdir -p "$dir"
      out="$dir/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png"
      cp -- "$file" "$out"
      notify "Saved to $(basename -- "$out")" 󰄄
      ;;
    ocr)
      [[ -r $file ]] || fail "capture not found" 1
      "$PLUGIN_DIR/bin/screen-search-capture" --ocr-file "$file" ${lang:+--lang "$lang"}
      ;;
    qr)
      [[ -r $file ]] || fail "capture not found" 1
      command -v zbarimg >/dev/null || fail "zbar not installed" 12
      local result
      result=$(zbarimg -q --raw -Sdisable -Sqrcode.enable "$file" 2>/dev/null) || true
      [[ -n $result ]] || fail "no QR code found" 11
      # QR payloads are routinely secrets (otpauth://); clipboard only, marked
      # sensitive so history skips it. The value is returned to the OSD as JSON
      # and nowhere else.
      printf '%s' "$result" | wl-copy --sensitive
      jq -cn --arg v "$result" '{qr:$v}'
      ;;
    discard)
      discard_capture "$file"
      ;;
    *) fail "unknown action: $action" 2 ;;
  esac
}
