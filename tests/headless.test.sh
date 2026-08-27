S="$PLUGIN_DIR/bin/screen-search"
# Default resultUi=notification: circle → clipboard + notification with
# click-to-search action; no OSD summon.
write_shell_json '{}'
reset_log
SLURP_GEOM="10,10 50x50" "$S" circle; assert_rc $? 0 "headless circle exits 0"
assert_grep "$FAKE_LOG" 'wl-copy \[--type\] \[image/png\] \[--sensitive\]' "circle copies image sensitive"
assert_grep "$FAKE_LOG" 'omarchy-notification-send .*\[Selection copied\]' "circle notifies"
assert_grep "$FAKE_LOG" '\[--exec\] \[.*bin/screen-search\] \[act\] \[visual\] \[--file\]' "notification click runs visual"
assert_nogrep "$FAKE_LOG" 'omarchy-shell \[shell\] \[summon\]' "no OSD summon in notification mode"
ls "$SCREEN_SEARCH_TMP"/capture-* >/dev/null 2>&1 && ok || bad "capture kept for the click action"
rm -f "$SCREEN_SEARCH_TMP"/capture-*

# ocr mode: text to clipboard, capture discarded, click action reads clipboard
reset_log
SLURP_GEOM="10,10 50x50" "$S" ocr; assert_rc $? 0 "headless ocr exits 0"
assert_grep "$FAKE_LOG" 'wl-copy <stdin:HELLO WORLD>' "ocr text copied"
assert_grep "$FAKE_LOG" '\[Copied text from selection\]' "ocr notifies"
assert_grep "$FAKE_LOG" '\[--exec\] \[.*bin/screen-search\] \[clipboard\]' "ocr click searches clipboard"
assert_nogrep "$FAKE_LOG" 'notification-send.*HELLO' "ocr text never in notification args"
[[ -z $(ls "$SCREEN_SEARCH_TMP"/capture-* 2>/dev/null) ]] && ok || bad "ocr capture discarded"

# resultUi=osd routes through the shell summon again
write_shell_json '{"resultUi":"osd"}'
reset_log
"$S" circle; assert_rc $? 0 "osd mode exits 0"
assert_grep "$FAKE_LOG" 'omarchy-shell \[shell\] \[summon\] \[t1nk33r.screen-search\]' "osd mode summons the overlay"
assert_nogrep "$FAKE_LOG" 'notification-send' "osd mode does not notify"
write_shell_json '{}'
