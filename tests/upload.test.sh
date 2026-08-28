S="$PLUGIN_DIR/bin/screen-search"
# public-url visual mode: consent gate, upload adapters, confirmed path.
UP_FAKE=$(mktemp -d)
cat > "$UP_FAKE/curl" <<'X'
#!/usr/bin/env bash
printf 'curl' >> "$FAKE_LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$FAKE_LOG"; done; printf '\n' >> "$FAKE_LOG"
for a in "$@"; do case $a in
  *uguu.se*) printf 'https://n.uguu.se/abcdWXYZ.png'; exit 0 ;;
  *0x0.st*) printf 'HTTP/2 200\r\nx-token: tok123\r\n\r\nhttps://0x0.st/abcd.png\n'; exit 0 ;;
  *litterbox*) printf 'https://litter.catbox.moe/abc123.png'; exit 0 ;;
esac; done
exit 22
X
chmod +x "$UP_FAKE/curl"
png="$SCREEN_SEARCH_TMP/capture-up.png"; printf 'PNG' > "$png"

# consent gate: `act visual` in public-url mode returns JSON, uploads NOTHING
write_shell_json '{"provider":"google","visualMode":"public-url","uploadHost":"uguu"}'
reset_log
out=$(PATH="$UP_FAKE:$PATH" "$S" act visual --file "$png"); assert_rc $? 0 "consent gate exits 0"
jq -e '.needsConsent==true and .host=="uguu.se" and .expiryHours==3 and .deletable==false' <<<"$out" >/dev/null && ok || bad "consent JSON shape: $out"
assert_nogrep "$FAKE_LOG" 'curl' "consent gate performs no upload"
assert_nogrep "$FAKE_LOG" 'omarchy-launch-browser' "consent gate opens no browser"

# confirmed path: uploads to uguu, opens the encoded uploadbyurl link
reset_log
SCREEN_SEARCH_DELETE_DELAY=0 PATH="$UP_FAKE:$PATH" "$S" act visual-confirmed --file "$png"
assert_rc $? 0 "confirmed path exits 0"
assert_grep "$FAKE_LOG" 'curl .*\[files\[\]=@'"$png"'\]' "uguu multipart upload"
assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://lens.google.com/uploadbyurl?url=https%3A%2F%2Fn.uguu.se%2FabcdWXYZ.png\]' "lens uploadbyurl with encoded url"
assert_nogrep "$FAKE_LOG" 'wl-copy' "public-url mode does not touch the clipboard"

# 0x0 adapter: token parsed, synchronous delete when delay=0
write_shell_json '{"provider":"google","visualMode":"public-url","uploadHost":"0x0"}'
reset_log
SCREEN_SEARCH_DELETE_DELAY=0 PATH="$UP_FAKE:$PATH" "$S" act visual-confirmed --file "$png"
assert_rc $? 0 "0x0 confirmed exits 0"
assert_grep "$FAKE_LOG" 'curl .*\[secret=\]' "0x0 secret flag"
assert_grep "$FAKE_LOG" 'curl .*\[token=tok123\] \[-F\] \[delete=\]' "0x0 early delete uses token"

# imgops confirmed path uses the raw (unencoded) prefix form
write_shell_json '{"provider":"google","visualMode":"public-url","uploadHost":"uguu"}'
reset_log
SCREEN_SEARCH_DELETE_DELAY=0 PATH="$UP_FAKE:$PATH" "$S" act visual-confirmed --file "$png" --provider imgops
assert_rc $? 0 "imgops confirmed exits 0"
assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://imgops.com/https://n.uguu.se/abcdWXYZ.png\]' "imgops raw-prefix url"

# provider without visualUrl → 4 before any upload
write_shell_json '{"provider":"brave","visualMode":"public-url"}'
reset_log
PATH="$UP_FAKE:$PATH" "$S" act visual-confirmed --file "$png" >/dev/null 2>&1
assert_rc $? 4 "no visualUrl → exit 4"
assert_nogrep "$FAKE_LOG" 'curl' "no upload for unsupported provider"

# upload failure → 5
cat > "$UP_FAKE/curl" <<'X'
#!/usr/bin/env bash
exit 22
X
chmod +x "$UP_FAKE/curl"
write_shell_json '{"provider":"google","visualMode":"public-url","uploadHost":"uguu"}'
PATH="$UP_FAKE:$PATH" "$S" act visual-confirmed --file "$png" >/dev/null 2>&1
assert_rc $? 5 "upload failure → exit 5"

# CLI headless: no TTY, no --yes → consent required (6); nothing uploaded
reset_log
PATH="$UP_FAKE:$PATH" "$S" visual "$png" </dev/null >/dev/null 2>&1
assert_rc $? 6 "CLI without consent → exit 6"
assert_nogrep "$FAKE_LOG" 'curl' "CLI refusal uploads nothing"

# clipboard mode untouched by all of this
write_shell_json '{"provider":"google"}'
reset_log
"$S" act visual --file "$png"; assert_rc $? 0 "clipboard mode still works"
assert_grep "$FAKE_LOG" 'wl-copy \[--type\] \[image/png\] \[--sensitive\]' "clipboard mode copies image"
rm -f "$png"; rm -rf "$UP_FAKE"
write_shell_json '{}'
