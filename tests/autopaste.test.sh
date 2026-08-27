# autopaste: targeted keystroke sequence, sandbox gating, graceful no-window
source "$PLUGIN_DIR/lib/providers.sh"

# Gated: with the sandbox env set (as run.sh exports), nothing happens.
reset_log
autopaste_into_browser "https://imgops.com/"
assert_nogrep "$FAKE_LOG" 'hyprctl' "sandbox env suppresses autopaste"

# Ungated with a matching window: paste then submit, both address-targeted.
reset_log
( unset SCREEN_SEARCH_NO_AUTOPASTE; autopaste_into_browser "https://imgops.com/" )
assert_grep "$FAKE_LOG" 'hyprctl \[clients\] \[-j\]' "queries clients"
assert_grep "$FAKE_LOG" 'hyprctl \[dispatch\] \[focuswindow\] \[address:0xabc123\]' "focuses the browser window"
assert_grep "$FAKE_LOG" 'wtype \[-M\] \[ctrl\] \[-P\] \[v\] \[-p\] \[v\] \[-m\] \[ctrl\]' "pastes via virtual keyboard"
assert_nogrep "$FAKE_LOG" 'Return' "no Return is sent (would destroy the paste editor)"

# No matching window: gives up silently, no keystrokes sent.
reset_log
( unset SCREEN_SEARCH_NO_AUTOPASTE; HYPRCTL_NO_CLIENTS=1 SCREEN_SEARCH_AUTOPASTE_TRIES=2 autopaste_into_browser "https://imgops.com/" )
assert_nogrep "$FAKE_LOG" 'wtype\|sendshortcut\|focuswindow' "no keystrokes without a target window"

# visual action spawns the (gated) autopaste but still completes instantly
png="$SCREEN_SEARCH_TMP/capture-ap.png"; printf 'PNG' > "$png"
write_shell_json '{"provider":"google"}'
reset_log
"$PLUGIN_DIR/bin/screen-search" act visual --file "$png"; assert_rc $? 0 "visual with autopaste exits 0"
assert_grep "$FAKE_LOG" 'omarchy-launch-browser \[https://imgops.com/\]' "browser still opened"
rm -f "$png"
