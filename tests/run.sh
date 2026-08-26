#!/usr/bin/env bash
# Offline test runner. Real network/browser/clipboard binaries are shadowed by
# fakes in tests/fakebin so nothing leaves the machine.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PLUGIN_DIR="$(cd -- "$HERE/.." && pwd)"
export FAKE_LOG="$(mktemp)"
export SCREEN_SEARCH_TMP="$(mktemp -d)"
export SCREEN_SEARCH_SHELL_JSON="$(mktemp --suffix=.json)"
export PATH="$HERE/fakebin:$PATH"
export HOME_ORIG="$HOME"
trap 'rm -rf "$FAKE_LOG" "$SCREEN_SEARCH_TMP" "$SCREEN_SEARCH_SHELL_JSON"' EXIT

pass=0; failn=0
ok()   { pass=$((pass+1)); }
bad()  { failn=$((failn+1)); printf '  FAIL: %s\n' "$1"; }
assert_eq() { [[ "$1" == "$2" ]] && ok || bad "$3: expected [$2] got [$1]"; }
assert_rc() { [[ "$1" == "$2" ]] && ok || bad "$3: expected exit $2 got $1"; }
assert_grep() { grep -q -- "$2" "$1" && ok || bad "$3: '$2' not found"; }
assert_nogrep() { grep -q -- "$2" "$1" && bad "$3: '$2' unexpectedly found" || ok; }
reset_log() { : > "$FAKE_LOG"; }
write_shell_json() {  # write_shell_json '<entry json>'
  jq -n --argjson e "${1:-{\}}" '{version:1, bar:{layout:{left:[],center:[],right:[$e + {id:"t1nk33r.screen-search"}]}}, plugins:[]}' > "$SCREEN_SEARCH_SHELL_JSON"
}

for t in "$HERE"/*.test.sh; do
  printf '%s\n' "$(basename "$t")"
  # shellcheck source=/dev/null
  source "$t"
done
printf '\n%d passed, %d failed\n' "$pass" "$failn"
[[ $failn -eq 0 ]] && echo "all tests passed"
[[ $failn -eq 0 ]]
