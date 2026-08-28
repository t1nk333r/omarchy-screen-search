S="$PLUGIN_DIR/bin/screen-search"
write_shell_json '{"provider":"google"}'

# --- text search URL encoding
reset_log; "$S" search 'hello world & more #1' >/dev/null; rc=$?
assert_rc "$rc" 0 "search exits 0"
assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://www.google.com/search?q=hello%20world%20%26%20more%20%231\]' "spaces/&/# encoded"

reset_log; "$S" search 'مرحبا بالعالم' >/dev/null
assert_grep "$FAKE_LOG" 'q=%D9%85%D8%B1%D8%AD%D8%A8%D8%A7%20%D8%A8%D8%A7%D9%84%D8%B9%D8%A7%D9%84%D9%85' "arabic encoded"

reset_log; "$S" search $'line one\nline two' >/dev/null
assert_grep "$FAKE_LOG" 'q=line%20one%0Aline%20two' "multiline encoded"

reset_log; "$S" search 'x' bing >/dev/null
assert_grep "$FAKE_LOG" 'https://www.bing.com/search?q=x' "explicit provider override"

# --- shell injection attempt stays a literal query
reset_log; "$S" search '$(touch /tmp/pwned); `id`' >/dev/null
assert_grep "$FAKE_LOG" 'q=%24%28touch%20%2Ftmp%2Fpwned%29%3B%20%60id%60' "shell metachars encoded"

# --- provider capabilities
reset_log; "$S" search 'q' tineye >/dev/null 2>&1; assert_rc $? 4 "tineye has no text search"
reset_log; "$S" search 'q' nope >/dev/null 2>&1; assert_rc $? 2 "unknown provider → 2"
reset_log; "$S" providers > "$SCREEN_SEARCH_TMP/list"; 
assert_grep "$SCREEN_SEARCH_TMP/list" '^brave .*text   -' "brave listed text-only"
assert_grep "$SCREEN_SEARCH_TMP/list" '^google .*text   visual  \*' "google current + visual"

# --- provider setting persistence goes through omarchy bar set
write_shell_json '{"provider":"bing"}'
assert_eq "$("$S" provider)" "bing" "provider read from shell.json"
write_shell_json '{"provider":"bogus"}'
assert_eq "$("$S" provider)" "google" "invalid provider falls back to google"
write_shell_json '{}'
assert_eq "$("$S" provider)" "google" "missing provider → manifest default"
reset_log; "$S" provider duckduckgo; assert_grep "$FAKE_LOG" 'omarchy \[bar\] \[set\] \[t1nk33r.screen-search\] \[provider\] \[duckduckgo\]' "provider set via omarchy bar set"
reset_log; "$S" provider nope >/dev/null 2>&1; assert_rc $? 2 "setting unknown provider rejected"

# --- visual search: clipboard + upload page, never curl
png="$SCREEN_SEARCH_TMP/capture-test.png"; printf 'PNG' > "$png"
write_shell_json '{"provider":"google"}'
reset_log; "$S" visual "$png"; assert_rc $? 0 "visual exits 0"
assert_grep "$FAKE_LOG" 'wl-copy \[--type\] \[image/png\] \[--sensitive\] <stdin:PNG>' "image copied sensitive"
assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://imgops.com/\]' "visual upload page opened"
assert_nogrep "$FAKE_LOG" 'curl' "no upload performed"
reset_log; "$S" visual "$png" brave >/dev/null 2>&1; assert_rc $? 4 "brave visual → 4"
assert_nogrep "$FAKE_LOG" 'wl-copy' "no clipboard write when unsupported"

# --- translate
write_shell_json '{"translateProvider":"deepl","translateTarget":"de"}'
reset_log; "$S" act translate --text 'hi there' >/dev/null
assert_grep "$FAKE_LOG" 'https://www.deepl.com/translator#auto/de/hi%20there' "deepl url"
write_shell_json '{}'
reset_log; LANG=ar_EG.UTF-8 "$S" act translate --text 'hi' >/dev/null
assert_grep "$FAKE_LOG" 'translate.google.com/?sl=auto&tl=ar&text=hi&op=translate' "google translate from LANG"

# --- open-url only for real URLs
reset_log; "$S" act open-url --text 'example.com' >/dev/null 2>&1; assert_rc $? 1 "bare domain not opened"
reset_log; "$S" act open-url --text 'https://example.com/a?b=c' >/dev/null; assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://example.com/a?b=c\]' "https url opened"

# --- providers --json is the machine interface the QML consumes
write_shell_json '{"provider":"google"}'
out=$("$S" providers --json)
jq -e 'length==6' <<<"$out" >/dev/null && ok || bad "json has 6 providers"
jq -e '[.[]|select(.current)]|length==1' <<<"$out" >/dev/null && ok || bad "exactly one current"
jq -e '.[0]|has("id") and has("name") and has("text") and has("visual")' <<<"$out" >/dev/null && ok || bad "json fields"
jq -e '[.[]|select(.id=="tineye")][0] | .text==false and .visual==true' <<<"$out" >/dev/null && ok || bad "tineye caps in json"
write_shell_json '{"provider":"bing"}'
"$S" providers --json | jq -e '[.[]|select(.current)][0].id=="bing"' >/dev/null && ok || bad "current follows setting"
write_shell_json '{}'

# arity: a flag with no value is a clean usage error, not an unbound-variable abort
reset_log; "$S" act copy --text >/dev/null 2>&1; assert_rc $? 2 "missing option value exits 2"
"$S" act copy --text 2>&1 | /usr/bin/grep -q 'unbound' && bad "unbound variable leaked" || ok
