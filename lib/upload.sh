#!/usr/bin/env bash
# Ephemeral public-upload adapters for the opt-in public-url visual mode.
# Only ever called AFTER the user confirmed the per-upload notice (the
# consent gate lives in lib/actions.sh). The returned URL is never logged.
#
# Host table (probed 2026-08-28 from this network):
#   uguu      3 h fixed expiry, no early delete, raw image serving  <- default
#   0x0       1 h settable + delete token, but unreachable from some networks
#   litterbox 1 h fixed, no delete, 403 from some networks

UPLOAD_UA="screen-search/${SCREEN_SEARCH_VERSION:-dev} (+https://github.com/t1nk333r/omarchy-screen-search)"

# upload_meta <host> -> "display-host<TAB>expiry-hours<TAB>deletable(true|false)"
upload_meta() {
  case $1 in
    uguu) printf 'uguu.se\t3\tfalse\n' ;;
    0x0) printf '0x0.st\t1\ttrue\n' ;;
    litterbox) printf 'litterbox.catbox.moe\t1\tfalse\n' ;;
    *) return 2 ;;
  esac
}

# upload_ephemeral <host> <file> -> stdout: "<url>\t<delete-token-or-empty>"
# Exit: 0 ok, 2 unknown host, 5 upload failed.
upload_ephemeral() {
  local host=$1 file=$2 out url token=""
  [[ -r $file ]] || return 5
  case $host in
    uguu)
      url=$(curl -sS -f --max-time 30 -A "$UPLOAD_UA" -F "files[]=@$file" \
        'https://uguu.se/upload?output=text' 2>/dev/null) || return 5
      ;;
    0x0)
      out=$(curl -sS -f -i --max-time 30 -A "$UPLOAD_UA" -F "file=@$file" \
        -F secret= -F expires=1 https://0x0.st 2>/dev/null) || return 5
      url=$(printf '%s' "$out" | tail -n1 | tr -d '\r')
      token=$(printf '%s' "$out" | /usr/bin/grep -i '^x-token:' | head -n1 | cut -d' ' -f2- | tr -d '\r')
      ;;
    litterbox)
      url=$(curl -sS -f --max-time 30 -A "$UPLOAD_UA" -F reqtype=fileupload \
        -F time=1h -F "fileToUpload=@$file" \
        https://litterbox.catbox.moe/resources/internals/api.php 2>/dev/null) || return 5
      ;;
    *) return 2 ;;
  esac
  [[ $url =~ ^https://[^[:space:]]+$ ]] || return 5
  printf '%s\t%s\n' "$url" "$token"
}

# delete_ephemeral <host> <url> <token> — best effort; only 0x0 supports it.
delete_ephemeral() {
  local host=$1 url=$2 token=$3
  [[ $host == 0x0 && -n $token ]] || return 0
  curl -sS --max-time 15 -A "$UPLOAD_UA" -F "token=$token" -F delete= "$url" >/dev/null 2>&1 || true
}
