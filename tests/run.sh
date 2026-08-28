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
export SCREEN_SEARCH_NO_AUTOPASTE=1
export HOME_ORIG="$HOME"
trap 'rm -rf "$FAKE_LOG" "$SCREEN_SEARCH_TMP" "$SCREEN_SEARCH_SHELL_JSON"' EXIT

pass=0; failn=0
MIN_ASSERTIONS=155
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
# Node unit suite for Model.js (pure logic). Skipped only when node is absent.
if command -v node >/dev/null 2>&1; then
  if out=$(node "$HERE/model.test.js" 2>&1); then
    n=$(sed -n 's/^model.test: \([0-9]*\) passed.*/\1/p' <<<"$out")
    pass=$((pass + ${n:-0}))
    [[ ${n:-0} -gt 0 ]] || { failn=$((failn+1)); printf '  FAIL: model.test.js reported zero assertions\n'; }
  else
    failn=$((failn+1)); printf '  FAIL: model.test.js failed:\n%s\n' "$out"
  fi
else
  printf '  SKIP: node not found — Model.js suite not run\n'
fi

# Static gate over the bash surface. Skips (loudly) until shellcheck is installed.
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$PLUGIN_DIR"/bin/screen-search "$PLUGIN_DIR"/bin/screen-search-capture        "$PLUGIN_DIR"/bin/screen-search-doctor "$PLUGIN_DIR"/lib/*.sh        "$PLUGIN_DIR"/install.sh "$PLUGIN_DIR"/uninstall.sh; then
    ok
  else
    failn=$((failn+1)); printf '  FAIL: shellcheck reported issues\n'
  fi
else
  printf '  SKIP: shellcheck not installed\n'
fi

# Assertion floor: a test file that silently no-ops (early abort under set -u)
# must fail the run, not shrink it.
if (( pass + failn < MIN_ASSERTIONS )); then
  failn=$((failn+1))
  printf '  FAIL: only %d assertions ran (floor %d) — a test file silently skipped\n' "$((pass+failn-1))" "$MIN_ASSERTIONS"
fi

printf '\n%d passed, %d failed\n' "$pass" "$failn"
[[ $failn -eq 0 ]] && echo "all tests passed"
[[ $failn -eq 0 ]]
